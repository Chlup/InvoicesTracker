import Foundation

/// Every line an invoice page prints, in the language of the invoice, worked out from an `InvoiceDocument` and ready to
/// draw: the view only lays them out. Lines with nothing in them (a street that is empty, a DIČ the supplier does not
/// have) are left out.
nonisolated struct InvoiceDocumentText: Sendable, Hashable {
    /// The supplier or the customer: the name, the lines of the address and the identifiers (IČO and DIČ).
    nonisolated struct Party: Sendable, Hashable {
        var name: String
        var lines: [String]
        var identifiers: [InvoiceField]
    }

    /// A row of the table of items.
    nonisolated struct Item: Sendable, Hashable {
        var quantity: String
        var unit: String
        var description: String
        var vatRate: String
        var unitPrice: String

        /// The price of the row without VAT.
        var amount: String
    }

    /// The VAT summary under the items: the rate, the base, the VAT and the total with VAT. For an invoice in a foreign
    /// currency whose rate is fixed, the base and the VAT also have their equivalents in crowns.
    nonisolated struct Summary: Sendable, Hashable {
        var vatRate: String
        var base: String
        var vat: String
        var total: String
        var baseInCrowns: String?
        var vatInCrowns: String?
    }

    /// The text of the QR code and the label printed under it.
    nonisolated struct QRCode: Sendable, Hashable {
        var payload: String
        var label: String
    }

    var labels: InvoiceLabels
    var number: String
    var supplier: Party
    var customer: Party

    /// The bank account of the invoice's currency, then the reference to pay with and the method of payment.
    var paymentRows: [InvoiceField]

    /// The dates of issue, of the due day and of the taxable supply.
    var dateRows: [InvoiceField]
    var items: [Item]
    var summary: Summary

    /// The note of the invoice with its line breaks, or nil when it is empty.
    var note: String?

    /// The legal line that ends a Czech invoice, or nil on an English one.
    var legalFooter: String?
    var qr: QRCode?

    init(_ document: InvoiceDocument) {
        let invoice = document.invoice
        let supplier = document.supplier
        let language = invoice.language
        let labels = InvoiceTextFormat.labels(language)
        self.labels = labels
        number = invoice.number
        self.supplier = Self.party(
            name: supplier.name, street: supplier.street, postcode: supplier.postcode, city: supplier.city,
            country: supplier.country, registrationNumber: supplier.ico, vatID: supplier.dic, labels: labels,
            language: language)
        customer = Self.party(
            name: invoice.client.name, street: invoice.client.street, postcode: invoice.client.postcode,
            city: invoice.client.city, country: invoice.client.country, registrationNumber: invoice.client.ico,
            vatID: invoice.client.dic, labels: labels, language: language)
        var paymentRows = Self.bankRows(of: document.account, currency: invoice.currency, labels: labels)
        paymentRows.append(
            InvoiceField(
                label: labels.reference,
                value: InvoiceTextFormat.reference(ofNumber: invoice.number, language: language)))
        if let method = Self.field(labels.paymentMethod, invoice.paymentMethod) {
            paymentRows.append(method)
        }
        self.paymentRows = paymentRows
        dateRows = [
            InvoiceField(
                label: labels.issueDate, value: InvoiceTextFormat.date(invoice.issueDate, language: language)),
            InvoiceField(label: labels.dueDate, value: InvoiceTextFormat.date(invoice.dueDate, language: language)),
            InvoiceField(
                label: labels.taxableSupplyDate, value: InvoiceTextFormat.date(invoice.duzp, language: language)),
        ]
        items = invoice.items.map { Self.item($0, of: invoice) }
        summary = Self.summary(of: document)
        note = Self.nonBlank(invoice.note)
        legalFooter = language == .cs ? Self.nonBlank(supplier.czechFooter) : nil
        if case .payload(let payload, label: let label) = document.qr {
            qr = QRCode(payload: payload, label: label)
        }
    }

    // MARK: Parties

    /// The lines of a party. The country is named in the language of the invoice, and left out where it is the Czech
    /// Republic on a Czech invoice.
    private static func party(
        name: String, street: String, postcode: String, city: String, country: String, registrationNumber: String,
        vatID: String, labels: InvoiceLabels, language: InvoiceLanguage
    ) -> Party {
        let typedCountry = country.trimmed
        let showsCountry = !typedCountry.isEmpty && !(typedCountry.uppercased() == "CZ" && language == .cs)
        let lines = [
            street.trimmed, [postcode.trimmed, city.trimmed].filter { !$0.isEmpty }.joined(separator: " "),
            showsCountry ? InvoiceTextFormat.countryName(typedCountry, language: language) : "",
        ]
        return Party(
            name: name.trimmed, lines: lines.filter { !$0.isEmpty },
            identifiers: [field(labels.registrationNumber, registrationNumber), field(labels.vatID, vatID)]
                .compactMap { $0 })
    }

    // MARK: The bank account

    /// The rows of the numbers of the account that an invoice prints: those of the account in its currency whenever the
    /// data holds one, for every currency (`InvoiceBankDetails`), each with its label in the language of the invoice;
    /// none when the data holds no account in the currency.
    private static func bankRows(of account: BankAccount?, currency: CurrencyCode, labels: InvoiceLabels)
        -> [InvoiceField]
    {
        InvoiceBankDetails.printedFields(of: account, currency: currency).map { printed in
            let label =
                switch printed.field {
                case .accountNumber: labels.bankAccount
                case .iban: labels.iban
                case .bic: labels.bic
                case .routingNumber: labels.routingNumber
                }
            return InvoiceField(label: label, value: printed.value)
        }
    }

    // MARK: Items and summary

    private static func item(_ item: InvoiceItem, of invoice: Invoice) -> Item {
        let language = invoice.language
        let currency = invoice.currency
        return Item(
            quantity: InvoiceTextFormat.quantity(item.quantity, language: language), unit: item.unit,
            description: item.description, vatRate: InvoiceTextFormat.vatRate(invoice.vatMode.ratePercent),
            unitPrice: InvoiceTextFormat.amount(item.unitPriceMinor, currency: currency, language: language),
            amount: InvoiceTextFormat.amount(
                InvoiceMath.itemAmount(quantity: item.quantity, unitPriceMinor: item.unitPriceMinor),
                currency: currency, language: language))
    }

    /// The summary of the invoice. The crown equivalents of the base and of the VAT are each worked out from the rate
    /// fixed on the invoice and rounded on their own, and are marked with "≈" while the document is only a draft.
    private static func summary(of document: InvoiceDocument) -> Summary {
        let invoice = document.invoice
        let language = invoice.language
        func amount(_ minor: Int64) -> String {
            InvoiceTextFormat.amount(minor, currency: invoice.currency, language: language)
        }
        var baseInCrowns: String?
        var vatInCrowns: String?
        if invoice.isForeignCurrency, let stored = invoice.invoiceRate, stored.rate.currency == invoice.currency,
            stored.rate.amount > 0
        {
            let approximately = document.isProvisional ? "≈\u{00A0}" : ""
            func crowns(_ minor: Int64) -> String {
                approximately
                    + InvoiceTextFormat.czkAmount(stored.rate.czkHalere(fromMinor: minor), language: language)
            }
            baseInCrowns = crowns(invoice.netMinor)
            vatInCrowns = crowns(invoice.vatMinor)
        }
        return Summary(
            vatRate: InvoiceTextFormat.vatRate(invoice.vatMode.ratePercent), base: amount(invoice.netMinor),
            vat: amount(invoice.vatMinor), total: amount(invoice.totalMinor), baseInCrowns: baseInCrowns,
            vatInCrowns: vatInCrowns)
    }

    // MARK: Helpers

    private static func field(_ label: String, _ value: String) -> InvoiceField? {
        nonBlank(value).map { InvoiceField(label: label, value: $0) }
    }

    /// `text` without the white space and the line breaks around it, or nil when nothing is left.
    private static func nonBlank(_ text: String) -> String? {
        let trimmed = text.trimmed
        return trimmed.isEmpty ? nil : trimmed
    }
}

private nonisolated extension String {
    var trimmed: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
