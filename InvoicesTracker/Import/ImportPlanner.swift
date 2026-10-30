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

/// What an import is going to do, worked out from the rows and from the invoices and clients that are there. Applying
/// it is a matter of saving what it holds.
nonisolated struct ImportPlan: Sendable, Hashable {
    /// Clients the rows have and the app has not, as they are going to be stored: with id 0.
    var newClients: [Client] = []

    /// Clients that are there, with the fields that were empty filled.
    var clientUpdates: [Client] = []

    /// Invoices to add, in the order of the rows. Their `clientID` is that of the client that is there already; for
    /// an invoice of a new client it is nil, and `newClientIndexByDigits` says which one.
    var inserts: [Invoice] = []

    /// Imported invoices to replace, each with the `id` of the invoice it replaces. An invoice that is only held for
    /// review because the rows of the import for it differ is one of them, with all it holds as it was.
    var updates: [Invoice] = []

    /// The numbers of the rows whose invoice is there as the row has it.
    var unchanged: [String] = []

    /// A line for each row that is not applied because its invoice was changed in the app: "20260902 — změněno v
    /// aplikaci — ponecháno".
    var kept: [String] = []

    /// A line for each row that cannot be added: the number is taken by an invoice made in the app, by an invoice in
    /// another currency or by another invoice of the import, the invoice came under another number, another invoice
    /// already has a number without a digit, or the row has no day of issue or no currency code to make an invoice of.
    var conflicts: [String] = []

    /// Imported invoices that are cancelled in Fakturoid now: the invoices as they are, held for review. One that was
    /// changed in the app keeps all it has, its payment too.
    var flaggedCancelled: [Invoice] = []

    /// A line for each invoice that is added or updated in review and for each invoice flagged as cancelled ("20261003
    /// — záporná částka"), and a note for each country that is neither a code nor a name the import knows.
    var reviewItems: [String] = []

    /// A line for each proforma invoice and for each cancelled invoice that has no imported invoice in the app.
    var skipped: [String] = []

    /// For the invoices of `inserts` and `updates` whose client is new, by the digits of their number: the index of
    /// that client in `newClients`.
    var newClientIndexByDigits: [String: Int] = [:]
}

/// Works out an import without touching the database: it is given the rows of the files and what the database holds.
nonisolated enum ImportPlanner {
    /// Why an invoice imported earlier that is cancelled in Fakturoid now is held for review.
    static let cancelledReason = "zrušeno ve Fakturoidu"

    /// Why an invoice is held for review when the import has several rows of it that differ.
    static let differingRowsReason = "v importu vícekrát s různým obsahem"

    /// The description of the one item of an imported invoice whose row has no subject.
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
    private static func unstorableReason(_ row: FakturoidRow) -> String? {
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
    private static func currency(of row: FakturoidRow) -> CurrencyCode? {
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
    /// It is issued, with one item: the subject of the invoice (or "Import z Fakturoidu") for one unit, at the
    /// subtotal. The DUZP is the day of the taxable supply or the day of issue, and the due day is the one in the
    /// export or the day of issue and the days until due. The rate of an invoice in a foreign currency is the one of
    /// the export, declared on the business day the rate of the DUZP is declared on; without one it is the rate of
    /// `invoiceRates` for the row, with the day that rate was declared on. An invoice of a row that says no currency
    /// has no rate. The QR code is off. The invoice is in Czech for `cz` and in English for any other language, and it
    /// prints the client of its own row.
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
        return Invoice(
            number: row.number, clientID: nil, client: snapshot(of: row), currency: currency, issueDate: issued,
            duzp: duzp, dueDate: due,
            items: [
                InvoiceItem(
                    description: row.subject.isEmpty ? defaultItemDescription : row.subject, quantity: Decimal(1),
                    unit: "", unitPriceMinor: row.subtotalMinor ?? 0)
            ],
            vatMode: vatMode(of: row) ?? VatMode.none, invoiceRate: rate, qrEnabled: false, note: "",
            language: row.language == "cz" ? .cs : .en, paymentMethod: row.paymentMethodHuman, status: .issued,
            review: reason.map { ReviewFlag(reason: $0) }, payment: nil,
            source: .imported(fakturoidID: row.fakturoidID, fingerprint: row.fingerprint, changedInApp: false)
        )
    }

    private static func snapshot(of row: FakturoidRow) -> ClientSnapshot {
        ClientSnapshot(
            name: row.clientName, street: street(of: row), postcode: row.clientZip, city: row.clientCity,
            country: country(row.clientCountry).text, ico: row.clientRegistrationNo, dic: row.clientVatNo,
            email: row.clientEmail
        )
    }

    /// The street of the client with the second line of the address after it.
    private static func street(of row: FakturoidRow) -> String {
        [row.clientStreet, row.clientStreet2].filter { !$0.isEmpty }.joined(separator: ", ")
    }

    // MARK: VAT

    private static let euCountries: Set<String> = [
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
    private enum Country {
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

    private static func country(_ text: String) -> Country {
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

    // MARK: The plan

    /// What importing `rows` does, given the invoices and the clients that are there.
    ///
    /// Rows with the same digits in the number and the same currency are one invoice, whichever file they come from and
    /// in whatever order. If one of them is cancelled in Fakturoid, the cancellation wins and the others are not
    /// applied. Otherwise rows that are alike are taken once, and rows that differ hold the invoice for review, without
    /// a payment: the import cannot tell which of them is right, so the invoice has the content of the first one.
    ///
    /// An invoice is matched to its row by the digits of its number and its currency. A row without a match is added
    /// (unless an imported invoice has its Fakturoid id under another number: that invoice came under a new number,
    /// and adding it would count it twice). A row that is the one an imported invoice was made from leaves it as it
    /// is, except that a review flag the row no longer has is taken away (a flag is never put on an invoice for a row
    /// that has not changed). A row that differs updates an imported invoice that was not changed in the app since,
    /// and leaves one that was, listed as kept. An invoice made in the app is never touched, and its row is a conflict.
    /// A cancelled row turns an imported invoice into one held for review, and an invoice changed in the app keeps all
    /// it has, its payment too. Rows of an imported invoice that differ leave what it holds and hold it for review,
    /// unless it was changed in the app: that one is kept as it is.
    ///
    /// Numbers are unique by their digits, so only one invoice can have a number without a digit. That one is added
    /// in review, and a later import finds it by its Fakturoid id, since its number says nothing about which invoice
    /// it is; a row of another invoice with such a number is a conflict. For the same reason the same digits in two
    /// currencies are one invoice and a conflict, and so is a row whose Fakturoid id is another than that of the
    /// imported invoice with its digits (when both are known): two invoices of Fakturoid, of which the stored one is
    /// left as it is.
    ///
    /// Clients are matched by company number, then VAT number, then folded name. A client that is not there is made
    /// from the rows of the client, the newest (by day of issue) giving the values and the older ones filling what
    /// it leaves empty. A client that is there gets only its empty fields filled. The clients of the rows of an
    /// invoice that is cancelled are not used.
    ///
    /// - Parameters:
    ///   - rows: The rows of the files, in the order of the files.
    ///   - existingInvoices: The invoices that may be the invoices of the rows: those with the digits of the number of
    ///     a row and those with the Fakturoid id of a row, with their items and payments.
    ///   - clients: All the clients.
    ///   - knownCurrencies: The currencies the ČNB quotes, crowns among them (see `quotedCurrencies`).
    ///   - payments: The payment of each row that has one, by the fingerprint of the row. An invoice held for review
    ///     gets none, for whoever resolves it decides.
    ///   - invoiceRates: The rate of the invoice of each paid row in a foreign currency whose export has none, by the
    ///     fingerprint of the row (see `invoice`).
    static func plan(
        rows: [FakturoidRow],
        existingInvoices: [Invoice],
        clients: [Client],
        knownCurrencies: Set<CurrencyCode>,
        payments: [String: Payment] = [:],
        invoiceRates: [String: StoredRate] = [:]
    ) -> ImportPlan {
        var pass = Pass(
            rows: rows, existingInvoices: existingInvoices, clients: clients, knownCurrencies: knownCurrencies,
            payments: payments, invoiceRates: invoiceRates)
        pass.run()
        return pass.plan
    }

    /// One run of `plan`: the plan as it is made, and what it is made from.
    private nonisolated struct Pass {
        /// The rows of the import that are one invoice: those with the same digits in the number and the same
        /// currency, and for a number without a digit (which says nothing about the invoice) the same Fakturoid id.
        struct Group {
            let digits: String
            let currency: CurrencyCode

            /// The offsets of the rows, in the order of the rows.
            var offsets: [Int] = []

            /// The offset of the first row that is cancelled in Fakturoid, if one is.
            var cancelledOffset: Int?
        }

        private static let anotherWithoutDigits = "jiná faktura už má číslo bez číslic"
        private static let anotherCurrency = "číslo už používá faktura v jiné měně"
        private static let anotherFakturoidInvoice = "číslo už používá jiná faktura z Fakturoidu"

        private enum Addition {
            case insert
            case update
        }

        private let rows: [FakturoidRow]
        private let knownCurrencies: Set<CurrencyCode>
        private let payments: [String: Payment]
        private let invoiceRates: [String: StoredRate]
        private let existingByDigits: [String: Invoice]
        private let existingByFakturoidID: [String: Invoice]
        private var book: ClientBook
        private(set) var plan = ImportPlan()

        /// The digits of the numbers of the invoices this import adds. A number belongs to one invoice.
        private var addedDigits: Set<String> = []

        /// The place in the book of the client of each row that has one, by the offset of the row.
        private var entryOfRow: [Int: Int] = [:]

        /// The place in the book of the client of each invoice that is added or updated, by the digits of its number.
        private var entryOfInvoice: [String: Int] = [:]

        /// The countries noted as no code already.
        private var notedCountries: Set<String> = []

        init(
            rows: [FakturoidRow], existingInvoices: [Invoice], clients: [Client], knownCurrencies: Set<CurrencyCode>,
            payments: [String: Payment], invoiceRates: [String: StoredRate]
        ) {
            self.rows = rows
            self.knownCurrencies = knownCurrencies
            self.payments = payments
            self.invoiceRates = invoiceRates
            existingByDigits = Dictionary(
                existingInvoices.map { ($0.numberDigits, $0) }, uniquingKeysWith: { first, _ in first })
            existingByFakturoidID = Dictionary(
                existingInvoices.compactMap { invoice -> (String, Invoice)? in
                    guard case .imported(let id, _, _) = invoice.source, !id.isEmpty else { return nil }
                    return (id, invoice)
                }, uniquingKeysWith: { first, _ in first })
            book = ClientBook(clients: clients, knownCurrencies: knownCurrencies)
        }

        mutating func run() {
            let classes = rows.map {
                ImportPlanner.classify($0, knownCurrencies: knownCurrencies, invoiceRates: invoiceRates)
            }
            let (groups, groupOfRow) = Self.groups(of: rows, classes: classes)
            placeClients(of: groups)
            for (offset, row) in rows.enumerated() {
                if let index = groupOfRow[offset] {
                    // A group is dealt with where its first row is.
                    if groups[index].offsets[0] == offset {
                        visit(groups[index])
                    }
                    continue
                }
                switch classes[offset] {
                case .skipProforma:
                    plan.skipped.append("\(label(of: row)) — zálohová faktura")
                case .skipCancelled:
                    plan.skipped.append("\(label(of: row)) — \(ImportPlanner.cancelledReason)")
                case .invoice:
                    if let reason = ImportPlanner.unstorableReason(row) {
                        addConflict(label(of: row), reason)
                    }
                }
            }
            finishClients()
        }

        // MARK: Groups

        /// The groups of the rows, in the order of their first rows, and the group each row is in. A row is in none
        /// when it is a proforma invoice, when no invoice can be made of it (it is a conflict by itself) or when it is
        /// cancelled and says a currency that is no code (it is skipped by itself).
        private static func groups(
            of rows: [FakturoidRow], classes: [RowClass]
        ) -> (groups: [Group], groupOfRow: [Int: Int]) {
            struct Key: Hashable {
                let digits: String
                let currency: CurrencyCode

                /// Of a number without a digit: the Fakturoid id, and the row when it has none.
                let fakturoidID: String
                let offset: Int
            }
            var indexOfKey: [Key: Int] = [:]
            var groups: [Group] = []
            var groupOfRow: [Int: Int] = [:]
            for (offset, row) in rows.enumerated() {
                let cancelled: Bool
                switch classes[offset] {
                case .skipProforma:
                    continue
                case .skipCancelled:
                    cancelled = true
                case .invoice:
                    guard ImportPlanner.unstorableReason(row) == nil else { continue }
                    cancelled = false
                }
                guard let currency = ImportPlanner.currency(of: row) else { continue }
                let digits = InvoiceNumbering.digits(of: row.number)
                let withoutDigits = digits.isEmpty
                let key = Key(
                    digits: digits, currency: currency, fakturoidID: withoutDigits ? row.fakturoidID : "",
                    offset: withoutDigits && row.fakturoidID.isEmpty ? offset : -1)
                let index: Int
                if let known = indexOfKey[key] {
                    index = known
                } else {
                    index = groups.count
                    indexOfKey[key] = index
                    groups.append(Group(digits: digits, currency: currency))
                }
                groups[index].offsets.append(offset)
                if cancelled && groups[index].cancelledOffset == nil {
                    groups[index].cancelledOffset = offset
                }
                groupOfRow[offset] = index
            }
            return (groups, groupOfRow)
        }

        private mutating func visit(_ group: Group) {
            if let cancelled = group.cancelledOffset {
                visitCancelled(group, row: rows[cancelled])
            } else {
                visitInvoice(group)
            }
        }

        // MARK: Clients

        /// Puts the client of every row that is going to be an invoice in the book, whatever becomes of the invoice,
        /// the oldest row first: the newest gives the values. The rows of an invoice that is cancelled are not.
        private mutating func placeClients(of groups: [Group]) {
            let offsets = groups
                .filter { $0.cancelledOffset == nil }
                .flatMap(\.offsets)
                .sorted { first, second in
                    guard let firstDay = rows[first].issuedOn, let secondDay = rows[second].issuedOn else {
                        return first < second
                    }
                    return (firstDay, first) < (secondDay, second)
                }
            for offset in offsets {
                entryOfRow[offset] = book.place(rows[offset])
            }
        }

        /// Makes the clients and gives the added and updated invoices their clients: the id of one that is there, the
        /// index of one that is new.
        private mutating func finishClients() {
            let finished = book.finish()
            plan.newClients = finished.newClients
            plan.clientUpdates = finished.updates
            for index in plan.inserts.indices {
                linkClient(ofInsert: index, finished)
            }
            for index in plan.updates.indices {
                linkClient(ofUpdate: index, finished)
            }
        }

        private mutating func linkClient(ofInsert index: Int, _ finished: ClientBook.Finished) {
            let digits = plan.inserts[index].numberDigits
            switch entryOfInvoice[digits].flatMap({ finished.references[$0] }) {
            case .existing(let id)?: plan.inserts[index].clientID = id
            case .new(let position)?: plan.newClientIndexByDigits[digits] = position
            case nil: break
            }
        }

        private mutating func linkClient(ofUpdate index: Int, _ finished: ClientBook.Finished) {
            let digits = plan.updates[index].numberDigits
            switch entryOfInvoice[digits].flatMap({ finished.references[$0] }) {
            case .existing(let id)?:
                plan.updates[index].clientID = id
            case .new(let position)?:
                plan.updates[index].clientID = nil
                plan.newClientIndexByDigits[digits] = position
            case nil:
                // No client could be made of the row, or the invoice is only held for review: it keeps its link.
                break
            }
        }

        // MARK: Invoices

        private func label(of row: FakturoidRow) -> String {
            row.number.isEmpty ? "(bez čísla)" : row.number
        }

        /// The line of the summary for an invoice held for review.
        private func reviewLine(_ label: String, _ reason: String) -> String {
            reason == ImportPlanner.differingRowsReason ? "\(label) — \(reason) — ke kontrole" : "\(label) — \(reason)"
        }

        /// An invoice that is not cancelled. Its first row gives it, unless the rows of the invoice differ: it is held
        /// for review then, without a payment.
        private mutating func visitInvoice(_ group: Group) {
            let offset = group.offsets[0]
            let row = rows[offset]
            let label = label(of: row)
            guard
                var invoice = ImportPlanner.invoice(
                    from: row, knownCurrencies: knownCurrencies, invoiceRates: invoiceRates)
            else {
                return
            }
            let digits = group.digits
            let differing = group.offsets.count > 1 && Set(group.offsets.map { rows[$0].fingerprint }).count > 1
            if differing {
                invoice.review = ReviewFlag(reason: ImportPlanner.differingRowsReason)
            } else if invoice.review == nil {
                invoice.payment = payments[row.fingerprint]
            }
            // Another invoice of this import has the number already: in another currency, or without a digit.
            guard !addedDigits.contains(digits) else {
                addConflict(label, digits.isEmpty ? Self.anotherWithoutDigits : Self.anotherCurrency)
                return
            }
            guard let existing = existingByDigits[digits] else {
                if !row.fakturoidID.isEmpty, let renumbered = existingByFakturoidID[row.fakturoidID] {
                    addConflict(label, "už importováno pod číslem \(renumbered.number)")
                } else {
                    add(invoice, at: offset, as: .insert)
                }
                return
            }
            // A number without a digit says nothing about which invoice it is: only the invoice with the Fakturoid
            // id of the row is the invoice of the row.
            if digits.isEmpty && !isInvoice(existing, ofFakturoidID: row.fakturoidID) {
                addConflict(label, Self.anotherWithoutDigits)
                return
            }
            guard existing.currency == invoice.currency else {
                addConflict(label, Self.anotherCurrency)
                return
            }
            guard case .imported(let storedID, let fingerprint, let changedInApp) = existing.source else {
                addConflict(label, "číslo už používá faktura vytvořená v aplikaci")
                return
            }
            // Two invoices of Fakturoid whose numbers have the same digits: the stored one is not the row's.
            guard !Self.areOtherFakturoidInvoices(storedID, row.fakturoidID) else {
                addConflict(label, Self.anotherFakturoidInvoice)
                return
            }
            if differing {
                holdForDifferingRows(existing, changedInApp: changedInApp, label: label)
            } else if fingerprint == row.fingerprint {
                // The row the invoice was made from brings nothing, whatever has been done with the invoice since. Only
                // a flag that the row does not have any more is taken away, such as when the rates of a currency are
                // there now: a flag is never put on an invoice that has none for a row that has not changed.
                if !changedInApp && existing.review != nil && invoice.review == nil {
                    invoice.id = existing.id
                    invoice.clientID = existing.clientID
                    add(invoice, at: offset, as: .update)
                } else {
                    plan.unchanged.append(label)
                }
            } else if changedInApp {
                plan.kept.append("\(label) — změněno v aplikaci — ponecháno")
            } else {
                invoice.id = existing.id
                invoice.clientID = existing.clientID
                add(invoice, at: offset, as: .update)
            }
        }

        /// The rows of the import for an imported invoice differ, so none of them is applied: the invoice keeps all it
        /// holds, and is held for review, unless it is held for these rows already. An invoice changed in the app is
        /// left as the app has it.
        private mutating func holdForDifferingRows(_ existing: Invoice, changedInApp: Bool, label: String) {
            if changedInApp {
                plan.kept.append("\(label) — změněno v aplikaci — ponecháno")
            } else if existing.review?.reason == ImportPlanner.differingRowsReason {
                plan.unchanged.append(label)
            } else {
                var held = existing
                held.review = ReviewFlag(reason: ImportPlanner.differingRowsReason)
                plan.updates.append(held)
                plan.reviewItems.append(reviewLine(label, ImportPlanner.differingRowsReason))
            }
        }

        /// Whether `invoice` was imported from the invoice with the Fakturoid id `id`.
        private func isInvoice(_ invoice: Invoice, ofFakturoidID id: String) -> Bool {
            guard case .imported(let importedID, _, _) = invoice.source else { return false }
            return !id.isEmpty && importedID == id
        }

        /// Whether the Fakturoid ids `stored` and `row` say they are two invoices: both are known, and they differ. An
        /// id that is missing tells nothing, and the digits of the number decide then.
        private static func areOtherFakturoidInvoices(_ stored: String, _ row: String) -> Bool {
            !stored.isEmpty && !row.isEmpty && stored != row
        }

        /// A row that cannot be added: the number of the row, why, and what became of it.
        private mutating func addConflict(_ label: String, _ reason: String) {
            plan.conflicts.append("\(label) — \(reason) — nepřidáno")
        }

        private mutating func add(_ invoice: Invoice, at offset: Int, as addition: Addition) {
            switch addition {
            case .insert:
                plan.inserts.append(invoice)
                addedDigits.insert(invoice.numberDigits)
            case .update:
                plan.updates.append(invoice)
            }
            entryOfInvoice[invoice.numberDigits] = entryOfRow[offset]
            let row = rows[offset]
            if let review = invoice.review {
                plan.reviewItems.append(reviewLine(label(of: row), review.reason))
            }
            if case .unknown(let text) = ImportPlanner.country(row.clientCountry) {
                if notedCountries.insert(text).inserted {
                    plan.reviewItems.append("země „\(text)“ — není kód země, ponecháno jak je")
                }
            }
        }

        // MARK: Cancelled invoices

        /// An invoice with a row that is cancelled in Fakturoid, which wins over the other rows of the invoice. An
        /// imported invoice is held for review: one that was changed in the app keeps all it has, and the line says
        /// both. Without an imported invoice the row is skipped, and the row of another invoice of Fakturoid whose
        /// number has the same digits is a conflict, which leaves the stored invoice as it is.
        private mutating func visitCancelled(_ group: Group, row: FakturoidRow) {
            let label = label(of: row)
            guard let existing = existingByDigits[group.digits], existing.currency == group.currency,
                case .imported(let storedID, let fingerprint, let changedInApp) = existing.source,
                !group.digits.isEmpty || isInvoice(existing, ofFakturoidID: row.fakturoidID)
            else {
                plan.skipped.append("\(label) — \(ImportPlanner.cancelledReason)")
                return
            }
            guard !Self.areOtherFakturoidInvoices(storedID, row.fakturoidID) else {
                addConflict(label, Self.anotherFakturoidInvoice)
                return
            }
            if fingerprint == row.fingerprint {
                plan.unchanged.append(label)
                return
            }
            var flagged = existing
            flagged.review = ReviewFlag(reason: ImportPlanner.cancelledReason)
            flagged.source = .imported(
                fakturoidID: row.fakturoidID.isEmpty ? storedID : row.fakturoidID, fingerprint: row.fingerprint,
                changedInApp: changedInApp)
            plan.flaggedCancelled.append(flagged)
            let reason = ImportPlanner.cancelledReason
            plan.reviewItems.append(
                changedInApp
                    ? "\(label) — \(reason) a změněno v aplikaci — ponecháno ke kontrole" : "\(label) — \(reason)")
        }
    }

    // MARK: Clients

    /// The clients that are there and the clients the rows have, matched and made from the rows one by one.
    private nonisolated struct ClientBook {
        /// A client of the book: one that is there, or a new one that the rows are making.
        struct Entry {
            /// The client as it is stored, or a blank client for a new one.
            let client: Client
            let isNew: Bool

            /// What the rows of the client say so far, the newest last.
            var values = Values()

            /// The keys a row is matched by: the company number and the VAT number without white space (and the VAT
            /// number in capitals), and the name folded. What is empty in a client that is there but the rows say is
            /// counted, since that is what the client is filled with.
            private(set) var icoKey = ""
            private(set) var dicKey = ""
            private(set) var nameKey = ""

            init(client: Client, isNew: Bool) {
                self.client = client
                self.isNew = isNew
                refreshKeys()
            }

            mutating func refreshKeys() {
                icoKey = ClientBook.compact(client.ico.isEmpty ? values.ico : client.ico)
                dicKey = ClientBook.compact(client.dic.isEmpty ? values.dic : client.dic).uppercased()
                nameKey = SearchFolding.fold(isNew ? values.name : client.name)
            }

            /// Whether the client has another company number or another VAT number than the row, so that equal names
            /// are two companies.
            func disagrees(icoKey ico: String, dicKey dic: String) -> Bool {
                (!ico.isEmpty && !icoKey.isEmpty && icoKey != ico) || (!dic.isEmpty && !dicKey.isEmpty && dicKey != dic)
            }

            /// The client the rows make: the newest row's values, with the defaults of a new client for the rest.
            func madeClient() -> Client {
                var made = Client()
                made.name = values.name
                made.street = values.street
                made.postcode = values.postcode
                made.city = values.city
                made.country = values.country
                made.ico = values.ico
                made.dic = values.dic
                made.email = values.email
                made.phone = values.phone
                made.currency = values.currency ?? made.currency
                made.vatMode = values.vatMode ?? made.vatMode
                made.dueDays = values.dueDays ?? made.dueDays
                if !values.paymentMethod.isEmpty {
                    made.paymentMethod = values.paymentMethod
                }
                made.language = values.language ?? made.language
                made.origin = .imported
                made.editedAfterImport = false
                return made
            }

            /// The client with its empty fields filled from the rows, or nil when the rows fill none.
            func filledClient() -> Client? {
                var filled = client
                func fill(_ field: inout String, with value: String) {
                    if field.isEmpty {
                        field = value
                    }
                }
                fill(&filled.street, with: values.street)
                fill(&filled.postcode, with: values.postcode)
                fill(&filled.city, with: values.city)
                fill(&filled.country, with: values.country)
                fill(&filled.ico, with: values.ico)
                fill(&filled.dic, with: values.dic)
                fill(&filled.email, with: values.email)
                fill(&filled.phone, with: values.phone)
                fill(&filled.paymentMethod, with: values.paymentMethod)
                return filled == client ? nil : filled
            }
        }

        /// What the rows of a client say. A newer row's value replaces an older one's, unless it is empty (or a
        /// currency without rates): the client takes what the newest row that has a value has.
        struct Values {
            var name = ""
            var street = ""
            var postcode = ""
            var city = ""
            var country = ""
            var ico = ""
            var dic = ""
            var email = ""
            var phone = ""
            var paymentMethod = ""
            var currency: CurrencyCode?
            var vatMode: VatMode?
            var dueDays: Int?
            var language: InvoiceLanguage?

            mutating func absorb(_ row: FakturoidRow, knownCurrencies: Set<CurrencyCode>) {
                func take(_ field: inout String, _ value: String) {
                    if !value.isEmpty {
                        field = value
                    }
                }
                take(&name, row.clientName)
                take(&street, ImportPlanner.street(of: row))
                take(&postcode, row.clientZip)
                take(&city, row.clientCity)
                take(&country, ImportPlanner.country(row.clientCountry).text)
                take(&ico, row.clientRegistrationNo)
                take(&dic, row.clientVatNo)
                take(&email, row.clientEmail)
                take(&phone, row.clientPhone)
                take(&paymentMethod, row.paymentMethodHuman)
                if let code = CurrencyCode(row.currency), code.isCZK || knownCurrencies.contains(code) {
                    currency = code
                }
                if let mode = ImportPlanner.vatMode(of: row) {
                    vatMode = mode
                }
                if let days = row.dueDays {
                    dueDays = days
                }
                if !row.language.isEmpty {
                    language = row.language == "cz" ? .cs : .en
                }
            }
        }

        enum Reference {
            case existing(Int64)
            case new(Int)
        }

        struct Finished {
            var newClients: [Client] = []
            var updates: [Client] = []

            /// By the place of the entry in the book.
            var references: [Int: Reference] = [:]
        }

        private var entries: [Entry]
        private let knownCurrencies: Set<CurrencyCode>

        init(clients: [Client], knownCurrencies: Set<CurrencyCode>) {
            self.knownCurrencies = knownCurrencies
            entries = clients.map { Entry(client: $0, isNew: false) }
        }

        /// Puts the client of `row` in the book: the client it is matched to, or a new one, with the values of the
        /// row. Returns the place of the entry, or nil when the row names no client that is there and has no name to
        /// make one of.
        mutating func place(_ row: FakturoidRow) -> Int? {
            let index: Int
            if let found = match(row) {
                index = found
            } else if !row.clientName.isEmpty {
                entries.append(Entry(client: Client(), isNew: true))
                index = entries.count - 1
            } else {
                return nil
            }
            entries[index].values.absorb(row, knownCurrencies: knownCurrencies)
            entries[index].refreshKeys()
            return index
        }

        /// The first client with the company number of the row, otherwise the first with its VAT number, otherwise
        /// the first with its name (folded) that does not have another number.
        private func match(_ row: FakturoidRow) -> Int? {
            let ico = Self.compact(row.clientRegistrationNo)
            let dic = Self.compact(row.clientVatNo).uppercased()
            let name = SearchFolding.fold(row.clientName)
            if !ico.isEmpty, let index = entries.firstIndex(where: { $0.icoKey == ico }) {
                return index
            }
            if !dic.isEmpty, let index = entries.firstIndex(where: { $0.dicKey == dic }) {
                return index
            }
            if !name.isEmpty,
                let index = entries.firstIndex(where: { $0.nameKey == name && !$0.disagrees(icoKey: ico, dicKey: dic) })
            {
                return index
            }
            return nil
        }

        /// The new clients, the clients that are filled, and where each entry of the book went.
        func finish() -> Finished {
            var finished = Finished()
            for (index, entry) in entries.enumerated() {
                if entry.isNew {
                    finished.references[index] = .new(finished.newClients.count)
                    finished.newClients.append(entry.madeClient())
                } else {
                    finished.references[index] = .existing(entry.client.id)
                    if let filled = entry.filledClient() {
                        finished.updates.append(filled)
                    }
                }
            }
            return finished
        }

        /// `text` without any white space.
        static func compact(_ text: String) -> String {
            String(String.UnicodeScalarView(text.unicodeScalars.filter { !$0.properties.isWhitespace }))
        }
    }
}
