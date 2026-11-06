import CryptoKit
import Foundation

/// What the import makes of one row.
nonisolated enum RowClass: Sendable, Hashable {
    /// A proforma invoice or a partial proforma invoice: it is not an invoice.
    case skipProforma

    /// An invoice cancelled in Fakturoid. It is not imported, but an invoice imported earlier that is cancelled now
    /// is held for review.
    case skipCancelled

    /// An invoice. The reason is set when the importer cannot classify the row with certainty: the invoice is then
    /// imported as "ke kontrole" and not counted until the person has resolved it.
    case invoice(reviewReason: String?)
}

/// Works out an import without touching the database: it is given the rows and the ISDOC invoices of the files and what
/// the database holds. The pass that makes the plan is `ImportPlanner.Pass`, the clients are matched and made in
/// `ImportPlanner.ClientBook`, and what an ISDOC invoice sets is in `ImportPlanner+Isdoc.swift`.
nonisolated enum ImportPlanner {
    /// Why an invoice imported earlier that is cancelled in Fakturoid now is held for review.
    static let cancelledReason = "zrušeno ve Fakturoidu"

    /// Why an invoice is held for review when the import has several rows, or several ISDOC files, of it that differ.
    /// While an invoice carries it, a later import ends the hold only when it brings, without differing, every kind of
    /// file the invoice is held for (see `plan`).
    static let differingRowsReason = "v importu vícekrát s různým obsahem"

    /// The description of the one item of an invoice imported from a CSV row alone: the row has no lines, and its
    /// `Subject` is the id of the client in Fakturoid, not a description.
    static let defaultItemDescription = "Import z Fakturoidu"

    /// The currency of an invoice whose row says none: `XXX`, the code for no currency. The invoice is held for review,
    /// and its amount is not taken for crowns meanwhile.
    static let noCurrency = CurrencyCode("XXX")!

    // MARK: Classification

    /// The currencies the ČNB quotes, as far as the import can tell: those that have rates in the database
    /// (`cached`), those of the newest uniform rate table that is built in, and crowns.
    ///
    /// The uniform rate table lists the currencies the ČNB quotes, so a database that has no rates yet (the first
    /// import, before the first rates are fetched or while offline) does not make a dollar a currency without rates.
    /// An invoice that is not paid needs no rate to be imported: its rate is the one of the export.
    static func quotedCurrencies(cached: Set<CurrencyCode>) -> Set<CurrencyCode> {
        var currencies = cached
        currencies.insert(.czk)
        if let newest = BuiltInUniformRates.instructions.keys.max() {
            currencies.formUnion(BuiltInUniformRates.rates(year: newest).map(\.currency))
        }
        return currencies
    }

    /// What the import makes of `row`.
    ///
    /// A proforma (or partial proforma) invoice and a cancelled one are skipped. Any other row is an invoice, held for
    /// review when it cannot be classified with certainty:
    /// - there is no digit in its number (digits are what numbers are unique by), so that only one such invoice can be
    ///   stored: see `plan`;
    /// - its subtotal is not read exactly (it may be 10 000 000 000 or more) or is negative (a credit note);
    /// - its VAT is there and is not read exactly, or is a rate that no VAT mode of the app has;
    /// - its status is none of `open`, `sent`, `overdue` and `paid`, or it is `paid` without a payment date, or has a
    ///   payment date and is not `paid`;
    /// - it has no currency (it is never taken for crowns), or its currency is not one of `knownCurrencies`, the
    ///   currencies the ČNB quotes (see `quotedCurrencies`);
    /// - it is paid in a foreign currency and has no rate: the export has none that is usable and `invoiceRates`, the
    ///   rates found elsewhere by the fingerprint of the row, has none either (see `invoice`).
    static func classify(
        _ row: FakturoidRow, knownCurrencies: Set<CurrencyCode>, invoiceRates: [String: StoredRate] = [:]
    ) -> RowClass {
        if row.proforma {
            return .skipProforma
        }
        if row.cancelled {
            return .skipCancelled
        }
        let reason = reviewReason(of: row, knownCurrencies: knownCurrencies, invoiceRates: invoiceRates)
        return .invoice(reviewReason: reason)
    }

    /// Why the invoice of `row` is held for review, or nil: the first of the conditions `classify` lists that the row
    /// meets.
    private static func reviewReason(
        of row: FakturoidRow, knownCurrencies: Set<CurrencyCode>, invoiceRates: [String: StoredRate]
    ) -> String? {
        if let problem = unstorableReason(row) {
            return problem
        }
        if InvoiceNumbering.digits(of: row.number).isEmpty {
            return "číslo bez číslic"
        }
        guard let subtotal = row.subtotalMinor else { return "neplatná nebo příliš velká částka" }
        if subtotal < 0 {
            return "záporná částka"
        }
        if row.vatUnreadable {
            return "neplatná nebo příliš velká DPH"
        }
        if vatMode(of: row) == nil {
            return "neznámá sazba DPH"
        }
        switch row.status {
        case "open", "sent", "overdue":
            if row.paidOn != nil {
                return "datum platby u nezaplacené faktury"
            }
        case "paid":
            if row.paidOn == nil {
                return "zaplaceno bez data platby"
            }
        case "":
            return "neznámý stav faktury"
        default:
            return "neznámý stav faktury: \(row.status)"
        }
        if row.currency.isEmpty {
            return "chybí měna"
        }
        if let currency = CurrencyCode(row.currency), !currency.isCZK, !knownCurrencies.contains(currency) {
            return "měna \(currency.code) bez kurzů ČNB"
        }
        if invoiceRateNeeded(by: row) != nil && invoiceRates[row.fingerprint] == nil {
            return "chybí kurz faktury"
        }
        return nil
    }

    /// Why no invoice can be made of the row at all, or nil: an invoice needs a day of issue and a currency code (a
    /// row that says no currency is given `noCurrency`, and held for review).
    static func unstorableReason(_ row: FakturoidRow) -> String? {
        if row.issuedOn == nil {
            return "chybí datum vystavení"
        }
        if currency(of: row) == nil {
            return "neplatná měna"
        }
        return nil
    }

    /// The currency of the invoice of `row`: the code the row says, `noCurrency` when it says none, and nil for text
    /// that is no code. Crowns are never assumed.
    static func currency(of row: FakturoidRow) -> CurrencyCode? {
        row.currency.isEmpty ? noCurrency : CurrencyCode(row.currency)
    }

    /// The currency and the DUZP of a row that is paid in a foreign currency and has no rate of its own to give the
    /// invoice, or nil for any other row. The invoice needs a rate from elsewhere then, found by the DUZP: see
    /// `invoice`.
    static func invoiceRateNeeded(by row: FakturoidRow) -> (currency: CurrencyCode, duzp: CivilDate)? {
        guard !row.proforma, !row.cancelled, row.status == "paid", row.exchangeRate == nil,
            let currency = CurrencyCode(row.currency), !currency.isCZK,
            let duzp = row.taxableFulfillmentDue ?? row.issuedOn
        else {
            return nil
        }
        return (currency, duzp)
    }

    // MARK: The invoice of a row

    /// The invoice `row` becomes, or nil when no invoice can be made of it (no day of issue or a currency that is no
    /// code). It has no id, no link to a client and no payment, which are for the plan to give. It carries the review
    /// flag `classify` gives.
    ///
    /// It is issued, with one item: "Import z Fakturoidu" (`defaultItemDescription`) for one unit, at the subtotal.
    /// The `Subject` of the row is never used. The DUZP is the day of the taxable supply or the day of issue, and the
    /// due day is the one in the export or the day of issue and the days until due. The rate of an invoice in a foreign
    /// currency is the one of the export, declared on the business day the rate of the DUZP is declared on; without one
    /// it is the rate of `invoiceRates` for the row, with the day that rate was declared on. An invoice of a row that
    /// says no currency has no rate. The QR code is off. The invoice is in Czech for `cz` and in English for any other
    /// language, its payment method is the one `paymentMethod(code:human:language:)` gives, and it prints the client of
    /// its own row.
    static func invoice(
        from row: FakturoidRow, knownCurrencies: Set<CurrencyCode>, invoiceRates: [String: StoredRate] = [:]
    ) -> Invoice? {
        guard unstorableReason(row) == nil, let issued = row.issuedOn, let currency = Self.currency(of: row) else {
            return nil
        }
        let duzp = row.taxableFulfillmentDue ?? issued
        let due = row.dueOn ?? row.dueDays.map { issued.adding(days: $0) } ?? issued
        var rate: StoredRate?
        if !currency.isCZK && !row.currency.isEmpty {
            if let quoted = row.exchangeRate {
                rate = StoredRate(
                    rate: ExchangeRate(currency: currency, amount: 1, rate: quoted),
                    declaredOn: CzechCalendar.rateDeclarationDay(for: duzp)
                )
            } else {
                rate = invoiceRates[row.fingerprint]
            }
        }
        let reason = reviewReason(of: row, knownCurrencies: knownCurrencies, invoiceRates: invoiceRates)
        let language = Self.language(of: row)
        return Invoice(
            number: row.number, clientID: nil, client: snapshot(of: row), currency: currency, issueDate: issued,
            duzp: duzp, dueDate: due,
            items: [
                InvoiceItem(
                    description: defaultItemDescription, quantity: Decimal(1), unit: "",
                    unitPriceMinor: row.subtotalMinor ?? 0)
            ],
            vatMode: vatMode(of: row) ?? VatMode.none, invoiceRate: rate, qrEnabled: false, note: "",
            language: language,
            paymentMethod: paymentMethod(
                code: row.paymentMethodCode, human: row.paymentMethodHuman, language: language),
            status: .issued, review: reason.map { ReviewFlag(reason: $0) }, payment: nil,
            source: .imported(fakturoidID: row.fakturoidID, fingerprint: row.fingerprint, changedInApp: false)
        )
    }

    /// The language of the invoice of `row`: Czech for `cz`, and English for any other language or none.
    static func language(of row: FakturoidRow) -> InvoiceLanguage {
        row.language == "cz" ? .cs : .en
    }

    /// The payment method an invoice in `language` prints for the method of a row: `bank`, a payment to a bank
    /// account, is "Převodem" in Czech and "Bank transfer" in English, as Fakturoid prints it; any other method, such
    /// as a custom one, is `human`, the words of the export, as they are typed.
    static func paymentMethod(code: String, human: String, language: InvoiceLanguage) -> String {
        guard code == "bank" else { return human }
        switch language {
        case .cs: return "Převodem"
        case .en: return "Bank transfer"
        }
    }

    /// What the invoice of `row` prints of its client: the client columns of the row.
    private static func snapshot(of row: FakturoidRow) -> ClientSnapshot {
        ClientSnapshot(
            name: row.clientName, street: street(of: row), postcode: row.clientZip, city: row.clientCity,
            country: country(row.clientCountry).text, ico: row.clientRegistrationNo, dic: row.clientVatNo,
            email: row.clientEmail
        )
    }

    /// The street of the client with the second line of the address after it.
    static func street(of row: FakturoidRow) -> String {
        [row.clientStreet, row.clientStreet2].filter { !$0.isEmpty }.joined(separator: ", ")
    }

    // MARK: VAT

    /// The countries of the European Union, as ISO 3166-1 alpha-2 codes.
    static let euCountries: Set<String> = [
        "AT", "BE", "BG", "CY", "CZ", "DE", "DK", "EE", "ES", "FI", "FR", "GR", "HR", "HU", "IE", "IT", "LT", "LU",
        "LV", "MT", "NL", "PL", "PT", "RO", "SE", "SI", "SK",
    ]

    /// How VAT is charged on the invoice of `row`, or nil when the row has VAT that no mode of the app fits, such as a
    /// VAT that is there and is not read exactly.
    ///
    /// A transferred tax liability is EU reverse charge. VAT of a fifth of the subtotal or more is 21 %, and of a tenth
    /// or more is 12 %. An invoice without VAT is outside the country (§ 9) when the country of the client is known
    /// and not in the EU, and has no VAT otherwise (in the Czech Republic, in another EU country without a transferred
    /// tax liability, or in a country that is not known).
    static func vatMode(of row: FakturoidRow) -> VatMode? {
        if row.transferredTaxLiability {
            return .euReverseCharge
        }
        if row.vatUnreadable {
            return nil
        }
        let vat = row.vatMinor ?? 0
        if vat != 0 {
            guard let subtotal = row.subtotalMinor, subtotal != 0 else { return nil }
            let share = Decimal(vat) / Decimal(subtotal)
            if share >= Decimal(string: "0.20")! {
                return .domestic21
            }
            if share >= Decimal(string: "0.10")! {
                return .domestic12
            }
            return nil
        }
        if case .code(let code) = country(row.clientCountry), !euCountries.contains(code) {
            return .outsideCountry
        }
        return VatMode.none
    }

    // MARK: Country

    /// What the country of a row is.
    enum Country {
        /// The row does not say.
        case absent

        /// An ISO code of two letters, in capitals: the code of the row, or the code of the name of the row.
        case code(String)

        /// A text that is neither a code nor a name the import knows.
        case unknown(String)

        /// What is stored: the code, or the text as it is written.
        var text: String {
            switch self {
            case .absent: ""
            case .code(let code): code
            case .unknown(let text): text
            }
        }
    }

    /// The country as the import stores it: a code of two letters is kept (in capitals), a name the import knows is
    /// mapped to its code, and any other text is kept as it is.
    static func countryCode(of text: String) -> String {
        country(text).text
    }

    /// What `text`, the country of a row, is: absent, a code, or a text the import does not know.
    static func country(_ text: String) -> Country {
        if text.isEmpty {
            return .absent
        }
        let letters = UInt8(ascii: "a")...UInt8(ascii: "z")
        if text.utf8.count == 2, text.utf8.allSatisfy({ letters.contains($0 | 0x20) }) {
            return .code(text.uppercased())
        }
        if let code = countryCodes[SearchFolding.fold(text)] {
            return .code(code)
        }
        return .unknown(text)
    }

    private static let countryCodes: [String: String] = {
        let names: [(code: String, names: [String])] = [
            ("CZ", ["Česko", "Česká republika", "Czech Republic"]),
            ("SK", ["Slovensko", "Slovakia"]),
            ("DE", ["Německo", "Germany", "Deutschland"]),
            ("AT", ["Rakousko", "Austria"]),
            (
                "US",
                ["Spojené státy", "Spojené státy americké", "United States", "United States of America", "USA"]
            ),
            ("GB", ["Velká Británie", "United Kingdom"]),
            ("PL", ["Polsko", "Poland"]),
        ]
        var codes: [String: String] = [:]
        for entry in names {
            for name in entry.names {
                codes[SearchFolding.fold(name)] = entry.code
            }
        }
        return codes
    }()

    // MARK: Files that differ

    /// What the fingerprint of the files of one kind that held an invoice starts with (`fingerprint(ofAll:)`). The
    /// fingerprint of a single file is plain hexadecimal, so it never starts so.
    static let differingFilesPrefix = "held:"

    /// The fingerprint an invoice held for files that differ is stored under, for each kind of file (CSV rows, or ISDOC
    /// invoices) the import has of it: `differingFilesPrefix`, then the SHA-256 of a marker line and the distinct
    /// fingerprints, sorted and each with its length before it, as lowercase hexadecimal. The order of the files does
    /// not change it, so the same files in another import give it again.
    ///
    /// It is never the fingerprint of a single file, also when the files of that kind are all alike, so that a later
    /// import that has one of them alone applies it. A kind whose files are alike and whose file the held invoice
    /// holds already is stored under the fingerprint of that file instead (see `plan`). The prefix tells which kind of
    /// file an invoice is held for (`isFingerprintOfDifferingFiles(_:)`). Holds made before the prefix existed were
    /// development data only, never released, so nothing is migrated.
    static func fingerprint(ofAll fingerprints: [String]) -> String {
        let distinct = Set(fingerprints).sorted()
        var hasher = SHA256()
        hasher.update(data: Data("held for files that differ\n".utf8))
        for fingerprint in distinct {
            hasher.update(data: Data("\(fingerprint.utf8.count):\(fingerprint)\n".utf8))
        }
        let digits = Array("0123456789abcdef")
        var text = differingFilesPrefix
        for byte in hasher.finalize() {
            text.append(digits[Int(byte >> 4)])
            text.append(digits[Int(byte & 0x0F)])
        }
        return text
    }

    /// Whether `fingerprint`, one an invoice is stored under for a kind of file, is that of files of the kind that
    /// differed and held the invoice (`fingerprint(ofAll:)`), not that of a single file that was applied.
    static func isFingerprintOfDifferingFiles(_ fingerprint: String) -> Bool {
        fingerprint.hasPrefix(differingFilesPrefix)
    }

    // MARK: The plan

    /// What importing `sources` does, given the invoices and the clients that are there. Each format sets only the
    /// fields it is the valid source of.
    ///
    /// **Grouping.** The rows and the ISDOC invoices with the same digits in the number and the same currency are one
    /// invoice, whichever file they come from and in whatever order. A row whose number has no digit says nothing about
    /// its invoice, so it is grouped by its Fakturoid id; an ISDOC invoice without a digit cannot be matched and is not
    /// added. If a row of a group is cancelled in Fakturoid, the cancellation wins and the other rows and the ISDOC
    /// invoices of the group are not applied. Otherwise sources that are alike are taken once, and rows that differ, or
    /// ISDOC invoices that differ, hold the invoice for review without a payment: the import cannot tell which of them
    /// is right, so a new invoice has the content of the first ones, and an invoice that is there keeps all it holds.
    /// For each kind of file, the held invoice is stored under the fingerprint of the set of its files
    /// (`fingerprint(ofAll:)`), so the same files again leave it as it is, also once the person has resolved it. That
    /// fingerprint is never that of a single file, so an import whose files of the invoice no longer differ applies
    /// that kind. A kind whose files are alike and whose file the invoice holds already keeps the fingerprint of that
    /// file instead, so that the file alone is not applied again over what the person did in the app: on an invoice
    /// that is there, the file it was last imported from; on a new one, its ISDOC file, which made it. The rows of a
    /// new invoice are always stored under the fingerprint of their set, since the hold takes the payment and the
    /// review of its row away. The fingerprint of differing files is recognizable
    /// (`isFingerprintOfDifferingFiles(_:)`), so it tells which kind of file the invoice is held for; an invoice with
    /// the flag and no such fingerprint was held by the import as it was before ISDOC files, for its rows. While the
    /// invoice still carries that flag, an import whose files of it do not differ ends the hold only when it brings
    /// every kind the invoice is held for: the files of those kinds are applied whatever the invoice is stored under,
    /// the row's status, payment and review replace the flag, and without a row applied the flag goes. An import that
    /// lacks a held kind applies no file of a held kind, applies the other kind as usual, and leaves the flag. A flag
    /// the person has resolved is not asked about.
    ///
    /// **Matching.** An invoice is matched by the digits of its number and its currency, an invoice made in the app as
    /// much as an imported one. A group without a match is added (unless an imported invoice has the Fakturoid id of
    /// its row under another number: that invoice came under a new number, and adding it would count it twice). The
    /// same digits in another currency, another invoice without a digit, and a row whose Fakturoid id is another than
    /// that of the stored invoice (when both are known) are conflicts, which leave the stored invoice as it is.
    ///
    /// **Applying.** The ISDOC invoice is applied first, when there is no stored invoice, the file differs from the one
    /// the invoice was last imported from (`Invoice.isdocFingerprint`), or the invoice is still held for files that
    /// differed and this import ends the hold. It sets the lines, the note, the number, the dates, the currency, the
    /// rate (a foreign file without one keeps the rate the invoice has), the printed client but its e-mail, and the VAT
    /// mode. Then the row is applied, when there is no stored invoice, the invoice was made in the app, the row differs
    /// from the one the invoice was last imported from, or the invoice is still held for files that differed and this
    /// import ends the hold. Until the hold ends, no file of a kind the invoice is held for is applied. On an invoice
    /// the ISDOC owns (it was imported from an ISDOC file, or one is in this group) the row sets only the state: the
    /// status and the payment, the review flag, the language, the payment method, the e-mail of the client, the kind of
    /// a VAT of 0 % and the Fakturoid id with the fingerprint of the row. On any other invoice the row gives all of it,
    /// with one item "Import z Fakturoidu" at the subtotal. A group of which nothing is applied is unchanged. Whether
    /// the invoice was changed in the app is not asked: Fakturoid is the source of truth, and every invoice the plan
    /// updates is saved as not changed in the app, an invoice made in the app as an imported one.
    ///
    /// **The payment.** A row with a review reason holds the invoice and gives no payment, and so does a row that is
    /// not paid. A paid row keeps the stored payment when it was received on the day of the row, which keeps how the
    /// person converted it; otherwise it gives the payment of `payments`. Either payment is converted again, the way
    /// it was, when the amounts of the invoice are not the ones it was converted for. When no row is applied the
    /// stored payment stays, converted again the same way when the lines of the ISDOC changed the amounts. No review
    /// flag is set for that.
    ///
    /// **An ISDOC invoice alone** adds an unpaid, issued invoice without the QR code. Its language is that of the
    /// client it matches, or else Czech for a client in CZ and English otherwise; its payment method is a transfer for
    /// code 42, or else the client's, or else none; its client's e-mail is the one of the file. A foreign one without
    /// a rate is not added.
    ///
    /// **Notes.** A row whose subtotal or VAT disagrees with the lines of an invoice the ISDOC owns, a line of an
    /// ISDOC file taken as one times its amount, and a country that is neither a code nor a name the import knows are
    /// noted in `notes`; they do not hold the invoice.
    ///
    /// **Clients** are matched by company number, then VAT number, then folded name, the customers of the ISDOC
    /// invoices as the clients of the rows. A client that is not there is made from its files, the newest (by day of
    /// issue) giving the values and the older ones filling what it leaves empty; on one day an ISDOC invoice comes
    /// before the row of its invoice. The language and the payment method of a new client are those its rows say, or
    /// else those an invoice of an ISDOC file alone takes. A client that is there gets only its empty fields filled.
    /// The clients of an invoice that is cancelled are not used.
    ///
    /// **Counting.** Each document, by the digits of its number and its currency, is counted once in the outcomes of
    /// the plan: a proforma invoice in both exports is skipped once, and a source that is skipped is not counted when
    /// its invoice is added, overwritten, unchanged or not added for another source. A proforma invoice is a document
    /// of its own, apart from the invoice with the same digits, as it never joins that invoice's group.
    ///
    /// - Parameters:
    ///   - sources: The rows and the ISDOC invoices of the files, each in the order of the files.
    ///   - existingInvoices: The invoices that may be the invoices of the sources: those with the digits of the number
    ///     of a source and those with the Fakturoid id of a row, with their items and payments.
    ///   - clients: All the clients.
    ///   - knownCurrencies: The currencies the ČNB quotes, crowns among them (see `quotedCurrencies`).
    ///   - payments: The payment of each paid row, by the fingerprint of the row, converted for the invoice the row
    ///     makes (`invoice(from:knownCurrencies:invoiceRates:)`). An invoice held for review gets none, for whoever
    ///     resolves it decides.
    ///   - invoiceRates: The rate of the invoice of each paid row in a foreign currency whose export has none, by the
    ///     fingerprint of the row (see `invoice`).
    static func plan(
        sources: ImportSources,
        existingInvoices: [Invoice],
        clients: [Client],
        knownCurrencies: Set<CurrencyCode>,
        payments: [String: Payment] = [:],
        invoiceRates: [String: StoredRate] = [:]
    ) -> ImportPlan {
        var pass = Pass(
            sources: sources, existingInvoices: existingInvoices, clients: clients, knownCurrencies: knownCurrencies,
            payments: payments, invoiceRates: invoiceRates)
        pass.run()
        return pass.plan
    }
}
