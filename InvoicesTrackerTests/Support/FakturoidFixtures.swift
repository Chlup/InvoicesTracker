import Foundation
@testable import InvoicesTracker

/// Exports of Fakturoid invoices made of invented data, for the tests of the import.
enum FakturoidCSV {
    /// The first line of an export: its 60 columns, in order.
    static let headerLine =
        "Id,Proforma,Partial proforma,Number,Variable symbol,Your name,Your street,Your street2,Your city,Your zip,"
        + "Your country,Your registration no,Your vat no,Client name,Client street,Client street2,Client city,"
        + "Client zip,Client country,Client registration no,Client vat no,Subject,Generator,Related,Token,Status,"
        + "Order number,Issued on,Taxable fulfillment due,Due,Due on,Sent at,Paid on,Reminder sent at,Cancelled at,"
        + "Bank account,Iban,Swift bic,Payment method,Currency,Exchange rate,Language,Transferred tax liability,"
        + "Subtotal,Total,Native subtotal,Native total,Remaining amount,Remaining native amount,Vat,Client email,"
        + "Client phone,Tax document,Payment method human,Rounding adjustment,Client delivery name,"
        + "Client delivery street,Client delivery city,Client delivery zip,Client delivery country"

    static let header: [String] = headerLine.split(separator: ",").map { String($0) }

    /// The values of one row by the name of the column.
    typealias Row = [String: String]

    /// The row every test starts from: an open invoice in crowns for Alfa Systems, issued on 1 October 2026, for
    /// 4 500,00 Kč and 945,00 Kč VAT. Every other column is empty. `overrides` replace columns by name.
    static func row(_ overrides: Row = [:]) -> Row {
        var values: Row = [
            "Id": "1", "Proforma": "false", "Partial proforma": "false", "Number": "20261001",
            "Variable symbol": "20261001", "Your name": "Jana Vzorová", "Your street": "Polní 5",
            "Your city": "Brno", "Your zip": "60200", "Your country": "CZ", "Your registration no": "11223344",
            "Your vat no": "CZ11223344", "Client name": "Alfa Systems s.r.o.", "Client street": "Náměstí 1",
            "Client city": "Příbram", "Client zip": "26101", "Client country": "CZ",
            "Client registration no": "12345678", "Client vat no": "CZ12345678", "Status": "open",
            "Issued on": "2026-10-01", "Taxable fulfillment due": "2026-10-01", "Due": "15", "Due on": "2026-10-16",
            "Payment method": "bank", "Currency": "CZK", "Exchange rate": "1.0", "Language": "cz",
            "Transferred tax liability": "false", "Subtotal": "4500,0", "Total": "5445,0", "Vat": "945.0",
            "Payment method human": "Banka",
        ]
        for (column, value) in overrides {
            values[column] = value
        }
        return values
    }

    /// An export as text: the header and a line for each row, a field in quotes when it needs them.
    static func text(_ rows: [Row], header: [String] = FakturoidCSV.header, lineEnding: String = "\n") -> String {
        var lines = [header.map(quoted).joined(separator: ",")]
        for row in rows {
            lines.append(header.map { quoted(row[$0] ?? "") }.joined(separator: ","))
        }
        return lines.joined(separator: lineEnding) + lineEnding
    }

    /// The rows as the importer reads them.
    static func rows(_ rows: [Row]) throws -> [FakturoidRow] {
        try FakturoidRow.rows(from: CSVTable.parse(text(rows)))
    }

    /// The row of `overrides` (see `row(_:)`) as the importer reads it.
    static func parsed(_ overrides: Row = [:]) throws -> FakturoidRow {
        try rows([row(overrides)])[0]
    }

    private static func quoted(_ field: String) -> String {
        guard field.contains(where: { ",\"\n\r".contains($0) }) else { return field }
        return "\"" + field.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }
}

/// The rows of a CSV fixture of the import (`fakturoid_sample` or `fakturoid_reimport`), in the order of the file.
func fakturoidFixtureRows(_ name: String = "fakturoid_sample") throws -> [FakturoidRow] {
    let text = try String(contentsOf: fixtureURL(name, "csv"), encoding: .utf8)
    return try FakturoidRow.rows(from: CSVTable.parse(text))
}

/// A CSV file with `text` in a new file of `directory`, written as UTF-8.
func writeCSV(_ text: String, named name: String, in directory: URL) throws -> URL {
    let url = directory.appending(path: name)
    try Data(text.utf8).write(to: url)
    return url
}

extension Database {
    /// Every invoice with its items and payment, in the order of the lists. For tests of what the import stored.
    func allInvoices() throws -> [Invoice] {
        try read { connection in
            try Invoice.load(where: InvoiceQueries.all, [], in: connection)
        }
    }

    /// Runs one statement that changes the data, such as the creation of a trigger. For tests.
    func execute(_ sql: String) throws {
        try write { connection in
            try connection.execute(sql)
        }
    }
}
