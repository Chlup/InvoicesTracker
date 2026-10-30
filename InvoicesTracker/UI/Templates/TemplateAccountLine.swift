import Foundation

/// What the form of a template says about the bank account that its invoices print. An invoice prints the account in
/// its own currency; the currency of a template is the one of its client. Nastavení › Moje údaje has a box for an
/// account in each of crowns, dollars and euros, and imported data can hold an account in another currency too. What
/// the line shows is what the page of an invoice prints: both take it from `InvoiceBankDetails`. Under an account the
/// form also says where it comes from (`sourceHint`): from Nastavení › Moje údaje, or from the imported data.
nonisolated enum TemplateAccountLine: Equatable {
    /// The account as one line of the numbers that its invoices print, in the order they print them: the number and the
    /// IBAN of an account in crowns ("2000123456/2010 · IBAN CZ6520100000002000123456"), the number and the routing
    /// number of one in dollars ("123456789 · routing 021000021"), the IBAN and the BIC of one in euros ("IBAN
    /// DE89370400440532013000 · BIC COBADEFFXXX"). The currency is one that Nastavení › Moje údaje has boxes for.
    case account(String)

    /// The line of an account in a currency that Nastavení › Moje údaje has no boxes for (no `SupplierField` has that
    /// currency), which only imported data can hold. It is built as the line of `.account` is, from the numbers that
    /// its invoices print; a currency with no layout of its own prints whatever numbers its account has ("12345678 ·
    /// IBAN GB33BUKB20201555555555 · BIC BUKBGB22 · routing 200000" in pounds).
    case importedAccount(String)

    /// There is no account in the currency, which Nastavení › Moje údaje has a box for, or the one there is has nothing
    /// in the numbers that its invoices print.
    case missing(CurrencyCode)

    /// Nastavení › Moje údaje has no box for an account in the currency, and the data holds none in it with anything
    /// that its invoices print: they print none.
    case notKept(CurrencyCode)

    /// The line of the account in `currency` among `accounts`: an account of Nastavení › Moje údaje when it has boxes
    /// for the currency, an imported one when it has none. A number that the account does not have is left out, and so
    /// is one that its invoices do not print, such as the name and address of the bank.
    init(currency: CurrencyCode, accounts: [BankAccount]) {
        let line = InvoiceBankDetails.printedFields(for: currency, in: accounts).map { printed in
            switch printed.field {
            case .accountNumber: printed.value
            case .iban: "IBAN " + printed.value
            case .bic: "BIC " + printed.value
            case .routingNumber: "routing " + printed.value
            }
        }
        // Moje údaje has the boxes of an account in a currency when it has fields of one.
        let hasBoxes = SupplierField.allCases.contains { $0.currency == currency }
        guard line.isEmpty else {
            let numbers = line.joined(separator: " · ")
            self = hasBoxes ? .account(numbers) : .importedAccount(numbers)
            return
        }
        self = hasBoxes ? .missing(currency) : .notKept(currency)
    }

    /// What the form says: the line, that there is no account and where to add it, or that the app keeps none in the
    /// currency.
    var text: String {
        switch self {
        case .account(let line), .importedAccount(let line): line
        case .missing(let currency): "Pro měnu \(currency.code) nemáte účet – doplníte ho v Nastavení › Moje údaje."
        case .notKept(let currency):
            "Pro měnu \(currency.code) aplikace účet nevede – faktura se vytiskne bez bankovního účtu."
        }
    }

    /// What the form says in grey under the line, where the account comes from: from Nastavení › Moje údaje, by the
    /// currency of the invoice, or from the imported data, which Moje údaje has no boxes to edit it in. Nil for a line
    /// that says there is no account, or that the app keeps none: it has no account to say it of.
    var sourceHint: String? {
        switch self {
        case .account: "Tiskne se účet z Nastavení › Moje údaje podle měny faktury."
        case .importedAccount: "Tiskne se účet z importovaných dat. V Nastavení › Moje údaje ho neupravíte."
        case .missing, .notKept: nil
        }
    }
}
