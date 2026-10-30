import Foundation

/// The language an invoice is written in. A client has a default, and every invoice keeps its own.
nonisolated enum InvoiceLanguage: String, Sendable, Hashable, Codable {
    case cs
    case en
}

/// How a client came into the app.
nonisolated enum ClientOrigin: String, Sendable, Hashable, Codable {
    /// Entered in the app.
    case app

    /// Created by the Fakturoid import.
    case imported
}

/// A customer. The fields are what new invoices for the client start from.
nonisolated struct Client: Identifiable, Sendable, Hashable, Codable {
    /// 0 until the client is saved.
    var id: Int64 = 0
    var name = ""
    var street = ""
    var postcode = ""
    var city = ""

    /// An ISO 3166-1 alpha-2 code such as `CZ` or `US`. The printed name follows the invoice language.
    var country = "CZ"

    /// The company registration number: the IČO (eight digits) of a Czech client, and for a client of any other country
    /// what that country calls it, as the import copies it. An English invoice prints it as "Reg. no.".
    var ico = ""

    /// The VAT number (DIČ).
    var dic = ""
    var email = ""
    var phone = ""
    var currency = CurrencyCode.czk
    var vatMode = VatMode.domestic21
    var dueDays = 14

    /// The payment method as printed on the invoice.
    var paymentMethod = "Převodem"
    var language = InvoiceLanguage.cs
    var origin = ClientOrigin.app

    /// Whether a client created by the import has been edited since. It is kept with the client, though no screen
    /// shows it.
    var editedAfterImport = false
}
