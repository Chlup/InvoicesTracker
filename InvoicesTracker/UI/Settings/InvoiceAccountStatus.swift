import Foundation

/// The lines "Na fakturách" of Nastavení › Moje údaje: for each currency an invoice is issued in — crowns, dollars and
/// euros — what its invoices print of the supplier's account, whether they carry a QR code for the payment, and what
/// is missing. A field with nothing but white space is missing.
nonisolated enum InvoiceAccountStatus {
    /// What a line says of its account, for the dot in front of it.
    enum Kind: Hashable, Sendable {
        /// The invoices of the currency print the account, and carry the QR code where there is one.
        case ready

        /// Something the invoices need is missing.
        case incomplete

        /// There is no account in the currency, which is fine until the first invoice in it.
        case absent
    }

    /// A line and what it says.
    struct Line: Hashable, Sendable {
        var text: String
        var kind: Kind
    }

    /// The lines of crowns, dollars and euros, in that order, for the supplier's `accounts`.
    static func entries(accounts: [BankAccount]) -> [Line] {
        [crowns(account(.czk, in: accounts)), dollars(account(.usd, in: accounts)), euros(account(.eur, in: accounts))]
    }

    /// The texts of `entries(accounts:)`.
    static func lines(accounts: [BankAccount]) -> [String] {
        entries(accounts: accounts).map(\.text)
    }

    // MARK: The currencies

    /// The number is printed, and the QR Platba is made from the IBAN.
    private static func crowns(_ account: BankAccount?) -> Line {
        let number = trimmed(account?.accountNumber)
        guard !number.isEmpty else {
            return Line(
                text: "Faktury v Kč: doplňte číslo účtu – bez něj faktura nemá kam poslat platbu", kind: .incomplete)
        }
        guard !trimmed(account?.iban).isEmpty else {
            return Line(
                text: "Faktury v Kč: účet \(number) · doplňte IBAN, jinak faktura nebude mít QR Platbu",
                kind: .incomplete)
        }
        return Line(text: "Faktury v Kč: účet \(number) · QR Platba z IBAN", kind: .ready)
    }

    /// The account number and the routing number are printed; there is no standard of a QR payment in dollars.
    private static func dollars(_ account: BankAccount?) -> Line {
        let number = trimmed(account?.accountNumber)
        let routing = trimmed(account?.routingNumber)
        guard !number.isEmpty, !routing.isEmpty else {
            return Line(text: "Faktury v USD: doplňte account number a routing number", kind: .incomplete)
        }
        return Line(
            text: "Faktury v USD: účet \(number) · routing \(routing) · bez QR (pro USD standard není)", kind: .ready)
    }

    /// The IBAN is printed and the SEPA payment is made from it. Without an account in euros nothing is missing yet.
    private static func euros(_ account: BankAccount?) -> Line {
        guard let account else {
            return Line(
                text: "Faktury v EUR: bez účtu v eurech – přidejte ho, než vystavíte první fakturu v eurech",
                kind: .absent)
        }
        let iban = trimmed(account.iban)
        guard !iban.isEmpty else {
            return Line(text: "Faktury v EUR: doplňte IBAN", kind: .incomplete)
        }
        return Line(text: "Faktury v EUR: IBAN \(iban) · QR platba SEPA", kind: .ready)
    }

    private static func account(_ currency: CurrencyCode, in accounts: [BankAccount]) -> BankAccount? {
        accounts.first { $0.currency == currency }
    }

    private static func trimmed(_ text: String?) -> String {
        (text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
