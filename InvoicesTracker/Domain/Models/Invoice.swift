import Foundation

/// A line of an invoice.
nonisolated struct InvoiceItem: Sendable, Hashable, Codable {
    var description: String
    var quantity: Decimal
    var unit: String

    /// The price of one unit in minor units of the invoice currency.
    var unitPriceMinor: Int64
}

/// The printed data of a client at the time an invoice was written. An invoice keeps its own copy, so editing or
/// deleting the client never changes an invoice that was already sent.
nonisolated struct ClientSnapshot: Sendable, Hashable, Codable {
    var name: String
    var street: String
    var postcode: String
    var city: String

    /// An ISO 3166-1 alpha-2 code.
    var country: String
    var ico: String
    var dic: String
    var email: String
}

nonisolated extension ClientSnapshot {
    /// The fields of `client` that an invoice prints.
    init(client: Client) {
        self.init(
            name: client.name, street: client.street, postcode: client.postcode, city: client.city,
            country: client.country, ico: client.ico, dic: client.dic, email: client.email
        )
    }
}

nonisolated enum InvoiceStatus: String, Sendable, Hashable, Codable {
    /// Not issued yet: it has no effect on the figures.
    case draft

    /// Issued to the client.
    case issued
}

/// How the CZK income of a payment was worked out.
nonisolated enum PaymentConversion: String, Sendable, Hashable, Codable {
    /// An invoice in crowns: nothing to convert.
    case czk

    /// At the ČNB rate of the day the money was received.
    case cnbDaily

    /// At the uniform annual rate of the GFŘ.
    case uniform

    /// At the amount in crowns the bank credited.
    case bankCZK
}

/// A rate together with the day the ČNB declared it, as it was fixed for an invoice or a payment.
nonisolated struct StoredRate: Sendable, Hashable, Codable {
    var rate: ExchangeRate
    var declaredOn: CivilDate
}

/// The payment of an invoice: when the money came and what it is worth as income.
nonisolated struct Payment: Sendable, Hashable, Codable {
    /// The day the money was received. It decides the year the income belongs to.
    var date: CivilDate
    var conversion: PaymentConversion

    /// The amount without VAT in haléře, converted to crowns.
    var czkNetHalere: Int64

    /// The VAT in haléře, converted to crowns. It is never income.
    var czkVatHalere: Int64

    /// The rate the conversion used, if it used one.
    var rate: StoredRate?

    /// Whether the rate is only a stand-in until the right one is published. The payment is worked out again then.
    var provisional = false

    /// The amount in crowns the bank credited for the whole invoice, VAT included, when it was entered.
    var bankCZKTotalHalere: Int64?
}

/// Where an invoice comes from.
nonisolated enum InvoiceSource: Sendable, Hashable, Codable {
    /// Written in the app.
    case app

    /// Read from a Fakturoid export. The fingerprint identifies the row as it was last imported, and
    /// `changedInApp` says the invoice has been changed in the app since, so a later import must leave it alone.
    case imported(fakturoidID: String, fingerprint: String, changedInApp: Bool)
}

/// Marks an invoice the import could not classify with certainty ("ke kontrole"). It is not counted as income until
/// it has been resolved.
nonisolated struct ReviewFlag: Sendable, Hashable, Codable {
    var reason: String
}

/// An invoice with its items, the printed data of its client, the rate fixed when it was issued and its payment, if
/// it has been paid. The amounts that follow from the items (net, VAT and total) are not part of the value: they are
/// worked out from the items and the VAT mode, and the database stores them with the row.
nonisolated struct Invoice: Identifiable, Sendable, Hashable, Codable {
    /// 0 until the invoice is saved.
    var id: Int64 = 0

    /// The number as printed. The digits of it are what must be unique (`2026-05-01` and `20260501` are the same).
    var number: String

    /// The client the invoice was written for, or nil when it has none any more.
    var clientID: Int64?
    var client: ClientSnapshot
    var currency: CurrencyCode
    var issueDate: CivilDate

    /// The date of the taxable supply (DUZP).
    var duzp: CivilDate
    var dueDate: CivilDate
    var items: [InvoiceItem]
    var vatMode: VatMode

    /// The ČNB rate of the DUZP, fixed when an invoice in a foreign currency is issued.
    var invoiceRate: StoredRate?

    /// Whether the invoice prints a QR code for the payment.
    var qrEnabled: Bool
    var note: String
    var language: InvoiceLanguage
    var paymentMethod: String
    var status: InvoiceStatus
    var review: ReviewFlag?
    var payment: Payment?
    var source: InvoiceSource
}
