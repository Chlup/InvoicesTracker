import Foundation

/// The fields of the supplier step as they were typed: the supplier's details, and the number and the IBAN of the
/// account in crowns. Spaces and line breaks around a field are not part of it. The IBAN is checked and stored as
/// Nastavení › Moje údaje checks and stores it (`SupplierField.czkIBAN`).
nonisolated struct SupplierDraft: Equatable, Sendable {
    var name = ""
    var street = ""
    var postcode = ""
    var city = ""
    var ico = ""
    var dic = ""

    /// The account in crowns as the number and the bank code, such as "19-2000145399/0800".
    var czkAccount = ""

    /// The IBAN of the account in crowns, which the QR Platba is made from.
    var czkIban = ""

    /// The supplier as typed. What the step does not ask for — the country, the e-mail, the phone and the footer of the
    /// Czech invoices — is what a new supplier has, and is filled in at Nastavení › Moje údaje.
    var supplier: Supplier {
        var supplier = Supplier()
        supplier.name = Self.trimmed(name)
        supplier.street = Self.trimmed(street)
        supplier.postcode = Self.trimmed(postcode)
        supplier.city = Self.trimmed(city)
        supplier.ico = Self.trimmed(ico)
        supplier.dic = Self.trimmed(dic)
        return supplier
    }

    /// The account in crowns as typed, with its IBAN in capitals without spaces, as the invoice prints it and the QR
    /// code carries it; nil when neither its number nor its IBAN was typed.
    var czkBankAccount: BankAccount? {
        let number = Self.trimmed(czkAccount)
        let iban = SupplierField.czkIBAN.stored(Self.trimmed(czkIban))
        guard !number.isEmpty || !iban.isEmpty else { return nil }
        return BankAccount(currency: .czk, accountNumber: number, iban: iban)
    }

    /// What the field of the IBAN says while what was typed is no IBAN — one with a typo prints a QR code that banks
    /// reject, so the step does not save it; nil while the field is empty or holds an IBAN.
    var ibanError: String? {
        SupplierField.czkIBAN.accepts(Self.trimmed(czkIban)) ? nil : SupplierField.czkIBAN.refusal
    }

    private static func trimmed(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
