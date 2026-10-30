import Foundation

/// A text field of Nastavení › Moje údaje: a detail of the supplier, or a field of the account in crowns, dollars or
/// euros.
nonisolated enum SupplierField: CaseIterable, Hashable, Sendable {
    case name
    case street
    case postcode
    case city
    case ico
    case dic
    case email
    case phone
    case czechFooter
    case czkAccountNumber
    case czkIBAN
    case czkBIC
    case usdAccountNumber
    case usdRoutingNumber
    case eurIBAN
    case eurBIC

    /// The currency of the account the field belongs to, or nil for a detail of the supplier.
    var currency: CurrencyCode? {
        switch self {
        case .czkAccountNumber, .czkIBAN, .czkBIC: .czk
        case .usdAccountNumber, .usdRoutingNumber: .usd
        case .eurIBAN, .eurBIC: .eur
        default: nil
        }
    }

    /// The text that a field with a code of the bank must be, besides empty, to be saved, and the message under a
    /// field whose text is not one: an IBAN or a BIC with a typo prints a QR code that banks reject.
    var refusal: String? {
        switch self {
        case .czkIBAN, .eurIBAN: SupplierTabModel.ibanInvalid
        case .czkBIC, .eurBIC: SupplierTabModel.bicInvalid
        default: nil
        }
    }

    /// Whether `text`, without the white space around it, can be saved in the field: anything but an IBAN or a BIC
    /// with a typo. Nothing at all can.
    func accepts(_ text: String) -> Bool {
        guard !text.isEmpty else { return true }
        switch self {
        case .czkIBAN, .eurIBAN: return BankCodes.isValidIBAN(text)
        case .czkBIC, .eurBIC: return BankCodes.isValidBIC(text)
        default: return true
        }
    }

    /// `text` as the field stores it: an IBAN and a BIC in capitals without spaces, as the invoice prints them and the
    /// QR code carries them; any other text as it is.
    func stored(_ text: String) -> String {
        refusal == nil ? text : BankCodes.normalized(text)
    }

    /// The value of the field in `supplier` and `accounts`: empty for an account that is not there.
    func value(in supplier: Supplier, accounts: [BankAccount]) -> String {
        guard let currency else { return value(of: supplier) }
        return accounts.first { $0.currency == currency }.map { value(of: $0) } ?? ""
    }

    /// Sets the field to `value`. The account of a field is made when it is not there yet, unless `value` is empty.
    func set(_ value: String, in supplier: inout Supplier, accounts: inout [BankAccount]) {
        guard let currency else {
            set(value, of: &supplier)
            return
        }
        if let index = accounts.firstIndex(where: { $0.currency == currency }) {
            set(value, of: &accounts[index])
        } else if !value.isEmpty {
            var account = BankAccount(currency: currency)
            set(value, of: &account)
            SupplierEdit.insert(account, into: &accounts)
        }
    }

    private func value(of supplier: Supplier) -> String {
        switch self {
        case .name: supplier.name
        case .street: supplier.street
        case .postcode: supplier.postcode
        case .city: supplier.city
        case .ico: supplier.ico
        case .dic: supplier.dic
        case .email: supplier.email
        case .phone: supplier.phone
        case .czechFooter: supplier.czechFooter
        default: ""
        }
    }

    private func set(_ value: String, of supplier: inout Supplier) {
        switch self {
        case .name: supplier.name = value
        case .street: supplier.street = value
        case .postcode: supplier.postcode = value
        case .city: supplier.city = value
        case .ico: supplier.ico = value
        case .dic: supplier.dic = value
        case .email: supplier.email = value
        case .phone: supplier.phone = value
        case .czechFooter: supplier.czechFooter = value
        default: break
        }
    }

    private func value(of account: BankAccount) -> String {
        switch self {
        case .czkAccountNumber, .usdAccountNumber: account.accountNumber
        case .czkIBAN, .eurIBAN: account.iban
        case .czkBIC, .eurBIC: account.bic
        case .usdRoutingNumber: account.routingNumber
        default: ""
        }
    }

    private func set(_ value: String, of account: inout BankAccount) {
        switch self {
        case .czkAccountNumber, .usdAccountNumber: account.accountNumber = value
        case .czkIBAN, .eurIBAN: account.iban = value
        case .czkBIC, .eurBIC: account.bic = value
        case .usdRoutingNumber: account.routingNumber = value
        default: break
        }
    }
}
