import Foundation

/// The person issuing the invoices: the "Moje údaje" of Nastavení. There is one.
nonisolated struct Supplier: Sendable, Hashable, Codable {
    var name = ""
    var street = ""
    var postcode = ""
    var city = ""

    /// An ISO 3166-1 alpha-2 code.
    var country = "CZ"
    var ico = ""
    var dic = ""
    var email = ""
    var phone = ""

    /// The legal line that ends a Czech invoice.
    var czechFooter = "Fyzická osoba zapsaná v živnostenském rejstříku."
}
