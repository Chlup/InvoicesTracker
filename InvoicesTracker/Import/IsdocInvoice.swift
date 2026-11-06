import CryptoKit
import Foundation

/// A party of an ISDOC invoice, the supplier or the customer: the elements Fakturoid writes under `Party`. A missing
/// element is an empty text.
nonisolated struct IsdocParty: Sendable, Hashable {
    let name: String

    /// `StreetName` and `BuildingNumber` joined with one space and trimmed. Fakturoid splits the street at its last
    /// word, so "Brod" and "44" make "Brod 44".
    let street: String
    let postcode: String
    let city: String

    /// The `Country/IdentificationCode` in capitals.
    let country: String

    /// The IČO (`PartyIdentification/ID`), empty for a client without one.
    let ico: String

    /// The DIČ (`PartyTaxScheme/CompanyID`).
    let dic: String

    /// The `Contact/ElectronicMail`, empty when the file has none.
    let email: String
}

/// A line of an ISDOC invoice (`InvoiceLine`).
nonisolated struct IsdocLine: Sendable, Hashable {
    /// The text of the line (`Item/Description`).
    let description: String

    /// The `InvoicedQuantity`, read exactly.
    var quantity: Decimal

    /// The unit as it was typed: the trimmed `unitCode` attribute of the quantity, empty when there is none.
    let unit: String

    /// The amount of the line without VAT in hundredths of the invoice currency: `LineExtensionAmountCurr` when the
    /// invoice is in a foreign currency, `LineExtensionAmount` otherwise.
    let lineAmountMinor: Int64

    /// The `UnitPrice` without VAT in hundredths of a crown. Fakturoid writes it in crowns also on an invoice in a
    /// foreign currency. Nil when the file has no price or not one that is read exactly.
    let unitPriceCZKMinor: Int64?

    /// The VAT rate of the line (`ClassifiedTaxCategory/Percent`), such as 21.
    let vatPercent: Decimal
}

/// An invoice from an ISDOC file, as Fakturoid writes it: what the import uses, typed. Nothing is made up for what the
/// file does not say, so a missing date is nil and a missing text is empty.
nonisolated struct IsdocInvoice: Sendable, Hashable {
    /// The `DocumentType`: 1 is an invoice, 4 a proforma invoice (zálohová faktura).
    let documentType: Int

    /// The `ID`, the number of the invoice.
    let number: String

    /// The `UUID` Fakturoid gives the invoice.
    let uuid: String
    let issueDate: CivilDate?

    /// The `TaxPointDate`, the DUZP.
    let taxPointDate: CivilDate?

    /// The `PaymentDueDate` of the payment.
    let dueDate: CivilDate?
    let note: String

    /// The `ForeignCurrencyCode` when there is one, otherwise the `LocalCurrencyCode`, or `CZK` when the file has
    /// neither.
    let currency: String

    /// Crowns for one unit of the foreign currency: `CurrRate` divided by `RefCurrRate`. Nil for an invoice in crowns
    /// and when the file has no usable rate.
    let rate: Decimal?
    let customer: IsdocParty
    let supplier: IsdocParty?
    var lines: [IsdocLine]

    /// The `PaymentMeansCode`: 42 is a payment to a bank account. Empty for a custom payment method.
    let paymentMeansCode: String
}

// MARK: - Fingerprint

nonisolated extension IsdocInvoice {
    /// A change detector for the invoice: the SHA-256 of all its fields, named and length-prefixed the way
    /// `FakturoidRow.fingerprint` does it, as lowercase hexadecimal. The same content gives the same fingerprint
    /// whatever the spelling of its numbers (`6.5` and `6.50`).
    ///
    /// An imported invoice keeps the fingerprint of the file it was made from, so a later import sees whether the
    /// file has changed since. The fields below, their names and their order are part of that stored data.
    var fingerprint: String {
        var fields: [(String, String)] = [
            ("documentType", String(documentType)), ("number", number), ("uuid", uuid),
            ("issueDate", issueDate?.iso ?? ""), ("taxPointDate", taxPointDate?.iso ?? ""),
            ("dueDate", dueDate?.iso ?? ""), ("note", note), ("currency", currency),
            ("rate", rate.map { DecimalMath.canonical($0) } ?? ""), ("paymentMeansCode", paymentMeansCode),
        ]
        fields += Self.fields(of: customer, prefix: "customer")
        fields.append(("hasSupplier", String(supplier != nil)))
        if let supplier {
            fields += Self.fields(of: supplier, prefix: "supplier")
        }
        fields.append(("lineCount", String(lines.count)))
        for (index, line) in lines.enumerated() {
            fields += [
                ("line\(index).description", line.description),
                ("line\(index).quantity", DecimalMath.canonical(line.quantity)),
                ("line\(index).unit", line.unit), ("line\(index).amount", String(line.lineAmountMinor)),
                ("line\(index).unitPrice", line.unitPriceCZKMinor.map { String($0) } ?? ""),
                ("line\(index).vatPercent", DecimalMath.canonical(line.vatPercent)),
            ]
        }
        var hasher = SHA256()
        for (name, value) in fields {
            // The length of the value is written before it, so that no two lists of values run together alike.
            hasher.update(data: Data("\(name):\(value.utf8.count):\(value)\n".utf8))
        }
        let digits = Array("0123456789abcdef")
        var text = ""
        for byte in hasher.finalize() {
            text.append(digits[Int(byte >> 4)])
            text.append(digits[Int(byte & 0x0F)])
        }
        return text
    }

    /// The named fields of a party.
    private static func fields(of party: IsdocParty, prefix: String) -> [(String, String)] {
        [
            ("\(prefix).name", party.name), ("\(prefix).street", party.street),
            ("\(prefix).postcode", party.postcode), ("\(prefix).city", party.city),
            ("\(prefix).country", party.country), ("\(prefix).ico", party.ico), ("\(prefix).dic", party.dic),
            ("\(prefix).email", party.email),
        ]
    }
}
