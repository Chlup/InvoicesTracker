import Foundation

/// The supplier's bank account for one currency. An invoice prints the account of its own currency, and its QR code
/// uses that account. Which fields matter depends on the currency: a Czech account has a number and an IBAN, a US
/// one a routing number and a type.
nonisolated struct BankAccount: Sendable, Hashable, Codable {
    var currency: CurrencyCode
    var accountNumber = ""
    var iban = ""
    var bic = ""
    var routingNumber = ""
    var accountType = ""

    /// The name and address of the bank. It stays in the data with the account, but nothing asks for it or prints it.
    var bankNameAndAddress = ""
}
