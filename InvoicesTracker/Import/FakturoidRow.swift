import CryptoKit
import Foundation

/// A row of the invoice export of Fakturoid: the columns the import uses, typed. A column the export does not have
/// is empty (or nil), so a file with fewer columns than Fakturoid's 60 is still read. What the export does not say is
/// never made up: an invoice without a currency is not an invoice in crowns.
nonisolated struct FakturoidRow: Sendable, Hashable {
    /// The `Id` of the invoice in Fakturoid, which does not change when the invoice is renumbered.
    let fakturoidID: String

    /// A proforma invoice or a partial proforma invoice (`Proforma` or `Partial proforma` is `true`).
    let proforma: Bool

    /// The number as the export prints it, such as `20260902` or `2026-05-01`.
    let number: String
    let issuedOn: CivilDate?
    let taxableFulfillmentDue: CivilDate?

    /// The days until the invoice is due (`Due`), from 0 to 3650.
    let dueDays: Int?
    let dueOn: CivilDate?
    let paidOn: CivilDate?

    /// Cancelled in Fakturoid: it says when it was cancelled (`Cancelled at`) or its status is `cancelled`.
    let cancelled: Bool

    /// The status in lowercase: `open`, `sent`, `overdue`, `paid`, `cancelled`, `uncollectible` …
    let status: String

    /// The currency code in capitals, empty when the export does not say.
    let currency: String

    /// The rate of the invoice in crowns for one unit of its currency, above zero.
    let exchangeRate: Decimal?

    /// The amounts in minor units of the currency: hundredths. Nil when the export has none or it is not an amount
    /// that is read exactly (see `AmountParser`), such as one of 10 000 000 000 or more.
    let subtotalMinor: Int64?
    let totalMinor: Int64?
    let vatMinor: Int64?

    /// Whether the `Vat` cell has text that is not read exactly (or is out of bounds). An empty cell is no VAT: it is
    /// not unreadable.
    let vatUnreadable: Bool
    let transferredTaxLiability: Bool

    /// The language in lowercase: `cz`, `en` …
    let language: String
    let paymentMethodHuman: String
    let subject: String

    let clientName: String
    let clientStreet: String
    let clientStreet2: String
    let clientCity: String
    let clientZip: String
    let clientCountry: String
    let clientRegistrationNo: String
    let clientVatNo: String
    let clientEmail: String
    let clientPhone: String

    /// The supplier, as the export prints it on every row.
    let yourName: String
    let yourStreet: String
    let yourStreet2: String
    let yourCity: String
    let yourZip: String
    let yourCountry: String
    let yourRegistrationNo: String
    let yourVatNo: String
}

// MARK: - Reading the rows

nonisolated extension FakturoidRow {
    /// Dates this far out are not taken for dates: the calendar and the rate lookups work from them.
    private static let plausibleYears = 1990...2100

    /// The most days an invoice is given to be paid in.
    private static let mostDaysUntilDue = 3650

    /// The rows of an export. Columns are found by their names, so their order does not matter, columns that are not
    /// known are ignored and the optional ones may be missing. A row with nothing in it is not a row.
    ///
    /// - Throws: `ImportError.notAFakturoidExport` when the table has no `Number` or no `Issued on` column, and
    ///   `ImportError.damagedFile` for a row with more or fewer fields than the header has: it is not clear then which
    ///   column a value belongs to, and a currency or a payment date could be taken for another.
    static func rows(from table: CSVTable) throws -> [FakturoidRow] {
        var columns: [String: Int] = [:]
        for (index, name) in table.header.enumerated() {
            let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
            if columns[name] == nil {
                columns[name] = index
            }
        }
        guard columns["Number"] != nil, columns["Issued on"] != nil else {
            throw ImportError.notAFakturoidExport
        }
        var rows: [FakturoidRow] = []
        for (offset, cells) in table.rows.enumerated() {
            if cells.allSatisfy({ $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) {
                continue
            }
            // The header is line 1, and a row with a line break in a field makes this a guess for the rows after it.
            guard cells.count == table.header.count else { throw ImportError.damagedFile(line: offset + 2) }
            rows.append(FakturoidRow(Cells(columns: columns, values: cells)))
        }
        return rows
    }

    /// The values of one row by the name of the column.
    private struct Cells {
        let columns: [String: Int]
        let values: [String]

        /// The trimmed text of a column, empty for a column the export does not have.
        func text(_ name: String) -> String {
            guard let index = columns[name] else { return "" }
            return values[index].trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }

    private init(_ cells: Cells) {
        let status = cells.text("Status").lowercased()
        let vatText = cells.text("Vat")
        let vat = AmountParser.minor(vatText)
        fakturoidID = cells.text("Id")
        proforma = Self.flag(cells.text("Proforma")) || Self.flag(cells.text("Partial proforma"))
        number = cells.text("Number")
        issuedOn = Self.date(cells.text("Issued on"))
        taxableFulfillmentDue = Self.date(cells.text("Taxable fulfillment due"))
        dueDays = Self.days(cells.text("Due"))
        dueOn = Self.date(cells.text("Due on"))
        paidOn = Self.date(cells.text("Paid on"))
        cancelled = !cells.text("Cancelled at").isEmpty || status == "cancelled"
        self.status = status
        currency = cells.text("Currency").uppercased()
        exchangeRate = Self.rate(cells.text("Exchange rate"))
        subtotalMinor = AmountParser.minor(cells.text("Subtotal"))
        totalMinor = AmountParser.minor(cells.text("Total"))
        vatMinor = vat
        vatUnreadable = !vatText.isEmpty && vat == nil
        transferredTaxLiability = Self.flag(cells.text("Transferred tax liability"))
        language = cells.text("Language").lowercased()
        paymentMethodHuman = cells.text("Payment method human")
        subject = cells.text("Subject")
        clientName = cells.text("Client name")
        clientStreet = cells.text("Client street")
        clientStreet2 = cells.text("Client street2")
        clientCity = cells.text("Client city")
        clientZip = cells.text("Client zip")
        clientCountry = cells.text("Client country")
        clientRegistrationNo = cells.text("Client registration no")
        clientVatNo = cells.text("Client vat no")
        clientEmail = cells.text("Client email")
        clientPhone = cells.text("Client phone")
        yourName = cells.text("Your name")
        yourStreet = cells.text("Your street")
        yourStreet2 = cells.text("Your street2")
        yourCity = cells.text("Your city")
        yourZip = cells.text("Your zip")
        yourCountry = cells.text("Your country")
        yourRegistrationNo = cells.text("Your registration no")
        yourVatNo = cells.text("Your vat no")
    }

    /// `true` in any case. The export writes nothing else for a yes.
    private static func flag(_ text: String) -> Bool {
        text.lowercased() == "true"
    }

    /// An ISO date `YYYY-MM-DD` of a year from 1990 to 2100, as the export writes the dates of an invoice.
    private static func date(_ text: String) -> CivilDate? {
        guard let date = CivilDate(iso: text), plausibleYears.contains(date.year) else { return nil }
        return date
    }

    /// A whole number of days from 0 to 3650, written with digits only.
    private static func days(_ text: String) -> Int? {
        guard !text.isEmpty, text.utf8.allSatisfy({ (UInt8(ascii: "0")...UInt8(ascii: "9")).contains($0) }),
            let days = Int(text), days <= mostDaysUntilDue
        else {
            return nil
        }
        return days
    }

    /// A rate above zero, written with a decimal comma or point.
    private static func rate(_ text: String) -> Decimal? {
        guard let rate = AmountParser.decimal(text, maxFractionDigits: 8), rate > 0 else { return nil }
        return rate
    }
}

// MARK: - Fingerprint

nonisolated extension FakturoidRow {
    /// A change detector for the row: the SHA-256 of the normalized fields the imported invoice is made of, as
    /// lowercase hexadecimal. The same invoice gives the same fingerprint whatever the spelling of its numbers
    /// (`4500,0` and `4500.00`) and whatever else the export holds, such as the supplier columns, the phone of the
    /// client or the total, none of which end up on the invoice.
    ///
    /// An imported invoice keeps the fingerprint of the row it was made from, so a later import sees whether the row
    /// has changed since. The fields below, their names and their order are part of that stored data: changing them
    /// makes every imported invoice look changed once.
    var fingerprint: String {
        let fields: [(String, String)] = [
            ("id", fakturoidID), ("number", number), ("issuedOn", issuedOn?.iso ?? ""),
            ("taxableFulfillmentDue", taxableFulfillmentDue?.iso ?? ""), ("dueDays", dueDays.map { String($0) } ?? ""),
            ("dueOn", dueOn?.iso ?? ""), ("paidOn", paidOn?.iso ?? ""), ("status", status),
            ("cancelled", String(cancelled)), ("proforma", String(proforma)), ("currency", currency),
            ("exchangeRate", exchangeRate.map { DecimalMath.canonical($0) } ?? ""),
            ("subtotal", subtotalMinor.map { String($0) } ?? ""),
            ("vat", vatMinor.map { String($0) } ?? (vatUnreadable ? "?" : "")),
            ("reverseCharge", String(transferredTaxLiability)), ("language", language),
            ("paymentMethod", paymentMethodHuman), ("subject", subject), ("clientName", clientName),
            ("clientStreet", clientStreet), ("clientStreet2", clientStreet2), ("clientCity", clientCity),
            ("clientZip", clientZip), ("clientCountry", clientCountry),
            ("clientRegistrationNo", clientRegistrationNo), ("clientVatNo", clientVatNo),
            ("clientEmail", clientEmail),
        ]
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
}
