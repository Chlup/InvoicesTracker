import Foundation

/// What an invoice prints of the supplier's bank account, chosen for its currency in this one place: the page of the
/// invoice prints it (`InvoiceDocument`, `InvoiceDocumentText`) and the form of a template shows it
/// (`TemplateAccountLine`), so that the form says what the invoices made from the template print.
nonisolated enum InvoiceBankDetails {
    /// A number of an account that an invoice prints.
    enum Field: Sendable, Hashable {
        case accountNumber
        case iban
        case bic
        case routingNumber
    }

    /// A number of an account as an invoice prints it: without the white space around it.
    struct PrintedField: Sendable, Hashable {
        var field: Field
        var value: String
    }

    /// The account that an invoice in `currency` prints, from the supplier's `accounts`: the one in its currency,
    /// whichever currency that is. Nastavení › Moje údaje has boxes for accounts in crowns, dollars and euros alone,
    /// but imported data can hold an account in another currency, and an invoice in it prints that account.
    static func account(for currency: CurrencyCode, in accounts: [BankAccount]) -> BankAccount? {
        accounts.first { $0.currency == currency }
    }

    /// The numbers of `account` that an invoice in `currency` prints, in the order it prints them: the number and the
    /// IBAN of an account in crowns, the number and the routing number of one in dollars, the IBAN and the BIC of one
    /// in euros, and whatever numbers it has in any other currency. A number the account does not have, or has with
    /// nothing but white space, is left out. The name and address of the bank and the type of a US account are never
    /// printed.
    static func printedFields(of account: BankAccount?, currency: CurrencyCode) -> [PrintedField] {
        guard let account else { return [] }
        let fields: [(Field, String)] =
            switch currency {
            case .czk: [(.accountNumber, account.accountNumber), (.iban, account.iban)]
            case .usd: [(.accountNumber, account.accountNumber), (.routingNumber, account.routingNumber)]
            case .eur: [(.iban, account.iban), (.bic, account.bic)]
            default:
                [
                    (.accountNumber, account.accountNumber), (.iban, account.iban), (.bic, account.bic),
                    (.routingNumber, account.routingNumber),
                ]
            }
        return fields.compactMap { field, value in
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : PrintedField(field: field, value: trimmed)
        }
    }

    /// The numbers that an invoice in `currency` prints of the account in its currency among `accounts`.
    static func printedFields(for currency: CurrencyCode, in accounts: [BankAccount]) -> [PrintedField] {
        printedFields(of: account(for: currency, in: accounts), currency: currency)
    }
}
