import Foundation

/// What an ISDOC invoice and a CSV row each set on an invoice of the app. The ISDOC file owns what the invoice prints;
/// the row owns the state of the invoice. The plan (`ImportPlanner.Pass`) decides which of them is applied.
nonisolated extension ImportPlanner {
    /// What the import makes of an ISDOC invoice before it is grouped with the other sources.
    nonisolated enum IsdocClass: Sendable, Hashable {
        /// Not an invoice: a proforma invoice or another kind of document. The reason is the line of `skipped`.
        case skip(reason: String)

        /// An invoice that cannot be added whatever the app holds. The reason is the line of `conflicts`.
        case conflict(reason: String)

        /// An invoice in `currency`, which joins the group of its number.
        case invoice(currency: CurrencyCode)
    }

    /// Why an ISDOC invoice whose lines have different VAT rates, or a rate no VAT mode of the app has, is not added.
    static let unknownIsdocVatReason = "sazba DPH, kterou aplikace nemá"

    /// Why a new invoice in a foreign currency from an ISDOC file without a usable rate is not added.
    static let missingInvoiceRateReason = "chybí kurz faktury"

    /// The note on an invoice the ISDOC owns whose CSV row has another subtotal or VAT than its lines.
    static let amountsDisagreeNote = "částka v CSV nesouhlasí s položkami z ISDOC — ponechány položky"

    /// What the import makes of `isdoc`.
    ///
    /// Only an invoice (`DocumentType` 1) is imported: a proforma invoice (4) is skipped as "zálohová faktura", the
    /// way the CSV says it, and any other kind as "jiný typ dokladu (n)". An invoice cannot be added when its number
    /// has no digit (it could not be matched), when it has no day of issue, when its currency is no code, or when its
    /// lines have different VAT rates or a rate the app has no mode for.
    static func classify(_ isdoc: IsdocInvoice) -> IsdocClass {
        switch isdoc.documentType {
        case 1:
            break
        case 4:
            return .skip(reason: "zálohová faktura")
        default:
            return .skip(reason: "jiný typ dokladu (\(isdoc.documentType))")
        }
        if InvoiceNumbering.digits(of: isdoc.number).isEmpty {
            return .conflict(reason: "číslo bez číslic")
        }
        if isdoc.issueDate == nil {
            return .conflict(reason: "chybí datum vystavení")
        }
        guard let currency = CurrencyCode(isdoc.currency) else {
            return .conflict(reason: "neplatná měna")
        }
        let country = countryCode(of: isdoc.customer.country)
        if IsdocInvoiceBuilder.vatMode(of: isdoc, existing: nil, clientCountry: country) == nil {
            return .conflict(reason: unknownIsdocVatReason)
        }
        return .invoice(currency: currency)
    }

    /// The new invoice an ISDOC invoice makes on its own, with the notes on its lines, or nil when it has no day of
    /// issue or its currency is no code (`classify` keeps such a file out).
    ///
    /// It is what `applying(_:to:keepingZeroMode:)` gives, unpaid and issued, without the QR code and without a
    /// review flag, with the e-mail of the customer, and in `language` with `paymentMethod`, which the plan works out
    /// from the client. No row of a CSV is imported for it yet: its Fakturoid id and the fingerprint of its row are
    /// empty. A foreign invoice whose file has no usable rate has none.
    static func invoice(
        fromIsdoc isdoc: IsdocInvoice, language: InvoiceLanguage, paymentMethod: String
    ) -> (invoice: Invoice, notes: [String])? {
        guard let issued = isdoc.issueDate, let currency = CurrencyCode(isdoc.currency) else { return nil }
        let blank = Invoice(
            number: isdoc.number, clientID: nil, client: snapshot(of: isdoc.customer, email: isdoc.customer.email),
            currency: currency, issueDate: issued, duzp: issued, dueDate: issued, items: [], vatMode: VatMode.none,
            invoiceRate: nil, qrEnabled: false, note: "", language: language, paymentMethod: paymentMethod,
            status: .issued, review: nil, payment: nil,
            source: .imported(fakturoidID: "", fingerprint: "", changedInApp: false)
        )
        return applying(isdoc, to: blank, keepingZeroMode: false)
    }

    /// `invoice` with what the ISDOC file owns taken from `isdoc`, and the notes on the lines that could not be taken
    /// as they are (`IsdocInvoiceBuilder.items(of:)`).
    ///
    /// The file sets:
    /// - the lines and the note;
    /// - the number, the day of issue, the DUZP (`TaxPointDate`, or the day of issue) and the due day
    ///   (`PaymentDueDate`, or the day of issue);
    /// - the currency and the rate, declared for the DUZP. A foreign file without a usable rate keeps the rate the
    ///   invoice has;
    /// - the printed client: name, street, postcode, city, country, IČO and DIČ. The e-mail stays as the invoice has
    ///   it;
    /// - the VAT mode of its lines. At 0 % a mode without VAT that the invoice has is kept when `keepingZeroMode` is
    ///   set, since the file cannot tell no VAT, a supply outside the country and an EU reverse charge apart;
    /// - its fingerprint, `isdocFingerprint`.
    ///
    /// Anything else, such as the payment, the state and the source of the invoice, stays as it is. `invoice` is
    /// returned as it is for a file without a day of issue.
    static func applying(
        _ isdoc: IsdocInvoice, to invoice: Invoice, keepingZeroMode: Bool
    ) -> (invoice: Invoice, notes: [String]) {
        guard let issued = isdoc.issueDate else { return (invoice, []) }
        let lines = IsdocInvoiceBuilder.items(of: isdoc)
        let duzp = isdoc.taxPointDate ?? issued
        var result = invoice
        result.number = isdoc.number
        result.items = lines.items
        result.note = isdoc.note
        result.issueDate = issued
        result.duzp = duzp
        result.dueDate = isdoc.dueDate ?? issued
        if let currency = CurrencyCode(isdoc.currency) {
            result.currency = currency
        }
        if let rate = IsdocInvoiceBuilder.invoiceRate(of: isdoc, duzp: duzp) {
            result.invoiceRate = rate
        } else if result.currency.isCZK {
            result.invoiceRate = nil
        }
        result.client = snapshot(of: isdoc.customer, email: invoice.client.email)
        let existing = keepingZeroMode ? invoice.vatMode : nil
        if let mode = IsdocInvoiceBuilder.vatMode(
            of: isdoc, existing: existing, clientCountry: result.client.country)
        {
            result.vatMode = mode
        }
        result.isdocFingerprint = isdoc.fingerprint
        return (result, lines.notes)
    }

    /// `invoice`, which the ISDOC owns, with what a CSV row owns taken from `row`, whose invoice is `csv`
    /// (`invoice(from:knownCurrencies:invoiceRates:)`): the status, the review flag, the language, the payment method,
    /// the e-mail of the client, and the kind of a VAT of 0 % (no VAT, outside the country, or an EU reverse charge
    /// for a transferred tax liability), which the ISDOC file cannot tell. The rate of the VAT stays as the lines have
    /// it. The payment and the source are for the plan to set.
    static func applyingOwnFields(of row: FakturoidRow, csv: Invoice, to invoice: Invoice) -> Invoice {
        var result = invoice
        result.status = csv.status
        result.review = csv.review
        result.language = csv.language
        result.paymentMethod = csv.paymentMethod
        result.client.email = csv.client.email
        if result.vatMode.ratePercent == 0, let mode = vatMode(of: row), mode.ratePercent == 0 {
            result.vatMode = mode
        }
        return result
    }

    /// `payment`, which was converted for the amounts of `source`, converted again the way it was for `final`
    /// (`PaymentConverter.reapply(_:to:)`) when the net or the VAT of `final` are others; otherwise as it is.
    static func reapplied(_ payment: Payment, from source: Invoice, to final: Invoice) -> Payment {
        guard source.netMinor != final.netMinor || source.vatMinor != final.vatMinor else { return payment }
        return PaymentConverter.reapply(payment, to: final)
    }

    /// What an invoice prints of the customer of an ISDOC file, with `email`: the file has an e-mail only sometimes,
    /// and the CSV owns it.
    static func snapshot(of customer: IsdocParty, email: String) -> ClientSnapshot {
        ClientSnapshot(
            name: customer.name, street: customer.street, postcode: customer.postcode, city: customer.city,
            country: countryCode(of: customer.country), ico: customer.ico, dic: customer.dic, email: email
        )
    }
}
