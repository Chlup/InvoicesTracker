import Foundation

/// One change of the supplier's details or accounts that the tab Moje údaje makes: it sets one thing and touches
/// nothing else. The tab saves its changes on top of what is stored, in one transaction
/// (`Database.updateSupplierDetails`), so that what changed meanwhile elsewhere is kept. Applying an edit twice, or
/// after another edit of the same target, is harmless: the last one wins.
nonisolated enum SupplierEdit: Hashable, Sendable {
    /// A text field, without the white space around it.
    case text(SupplierField, String)

    /// The supplier's country, an ISO code.
    case country(String)

    /// The type of the account in dollars: Checking or Savings.
    case usdAccountType(String)

    /// Whether there is an account in euros. A new one is empty; one that goes takes its fields with it.
    case eurAccount(Bool)

    /// What an edit sets, without the value: an edit replaces an earlier one with the same target.
    enum Target: Hashable, Sendable {
        case text(SupplierField)
        case country
        case usdAccountType
        case eurAccount
    }

    var target: Target {
        switch self {
        case .text(let field, _): .text(field)
        case .country: .country
        case .usdAccountType: .usdAccountType
        case .eurAccount: .eurAccount
        }
    }

    func apply(to supplier: inout Supplier, accounts: inout [BankAccount]) {
        switch self {
        case .text(let field, let value):
            field.set(value, in: &supplier, accounts: &accounts)
        case .country(let code):
            supplier.country = code
        case .usdAccountType(let type):
            if let index = accounts.firstIndex(where: { $0.currency == .usd }) {
                accounts[index].accountType = type
            } else {
                Self.insert(BankAccount(currency: .usd, accountType: type), into: &accounts)
            }
        case .eurAccount(true):
            if !accounts.contains(where: { $0.currency == .eur }) {
                Self.insert(BankAccount(currency: .eur), into: &accounts)
            }
        case .eurAccount(false):
            accounts.removeAll { $0.currency == .eur }
        }
    }

    /// Puts a new account into `accounts` in the order the tab shows them: crowns, dollars, euros, then any other.
    static func insert(_ account: BankAccount, into accounts: inout [BankAccount]) {
        let rank = order(of: account.currency)
        let index = accounts.firstIndex { order(of: $0.currency) > rank } ?? accounts.endIndex
        accounts.insert(account, at: index)
    }

    private static func order(of currency: CurrencyCode) -> Int {
        [CurrencyCode.czk, .usd, .eur].firstIndex(of: currency) ?? 3
    }
}
