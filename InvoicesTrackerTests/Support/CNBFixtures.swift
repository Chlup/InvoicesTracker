import Foundation
@testable import InvoicesTracker

/// The text of a ČNB file in the test fixtures, such as `cnb_rok_2026` or `cnb_denni_2026-10-16`.
func cnbFixture(_ name: String) throws -> String {
    try String(contentsOf: fixtureURL(name, "txt"), encoding: .utf8)
}

/// The rates of the yearly fixtures (`cnb_rok_<year>`) of `years`, in the order given.
func cnbYearlyRows(_ years: [Int]) throws -> [CNBRateRow] {
    try years.flatMap { year in
        try CNBYearlyParser.parse(cnbFixture("cnb_rok_\(year)"))
    }
}

/// A daily file of the ČNB, as the server sends it, that says the rates `rows` were declared on `day`: the day and a
/// sequence number, the titles of the columns and a line for each rate, with a decimal comma. The country and the name
/// of the currency are dashes, which the parser does not read.
func cnbDailyFile(declaredOn day: CivilDate, rows: [CNBRateRow]) -> Data {
    let parts = day.iso.split(separator: "-")
    var lines = ["\(parts[2]).\(parts[1]).\(parts[0]) #1", "země|měna|množství|kód|kurz"]
    for row in rows {
        let rate = DecimalMath.canonical(row.rate).replacing(".", with: ",")
        lines.append("-|-|\(row.amount)|\(row.currency.code)|\(rate)")
    }
    return Data((lines.joined(separator: "\n") + "\n").utf8)
}
