import Foundation

/// A rate the ČNB declared on one business day: `rate` crowns for `amount` units of `currency`.
nonisolated struct CNBRateRow: Sendable, Hashable {
    /// The business day the ČNB declared the rate on. The rate is valid from that day until the next declaration.
    let declaredOn: CivilDate

    let currency: CurrencyCode

    /// The number of units the rate is for: 1, 100 or 1000. Always above zero in the rows the parsers return.
    let amount: Int

    /// The price of `amount` units of the currency, in crowns, exactly as the ČNB prints it. Always above zero in the
    /// rows the parsers return.
    let rate: Decimal

    var exchangeRate: ExchangeRate {
        ExchangeRate(currency: currency, amount: amount, rate: rate)
    }
}

/// A ČNB file that this app does not read. A file is rejected whole, never read in part, so that a change in the
/// format cannot turn into a wrong rate.
nonisolated enum CNBParseError: Error, Hashable {
    /// A yearly file does not start with a header, or a later header line is not one: a header is `Datum` followed by
    /// a column for each currency, titled with its unit amount and code (`1 USD`, `100 JPY`). Or a daily file does not
    /// start with a date and a sequence number (`16.10.2026 #200`) and the titles of its columns.
    case malformedHeader

    /// A line of rates does not fit its header: it does not have a day and one cell for each column, or the day does
    /// not exist, or a rate, a unit amount or a currency code in it is not valid. In a yearly file a cell may be empty,
    /// in a daily file it may not.
    case malformedRow
}

/// Reads a yearly file of the ČNB, `rok.txt?rok=2026`: a table with a row of rates for each day the ČNB declared.
///
/// ```
/// Datum|1 AUD|1 EUR|100 JPY|1 USD
/// 02.01.2026|13,797|24,170|13,141|20,611
/// ```
///
/// The header names the columns, and it gives the unit amount with each code. A header line can come again later in
/// the file and replaces the columns from there on (the file of 2022 drops RUB after 1 March). A cell can be empty, and
/// then the currency has no rate that day. The decimal separator is a comma.
nonisolated enum CNBYearlyParser {
    /// A column of the table: the unit amount and the currency its title names.
    private nonisolated struct Column {
        let amount: Int
        let currency: CurrencyCode
    }

    /// The rates of all the days in the file, day by day and column by column. Empty cells give no row.
    /// Throws `CNBParseError` unless the whole text is in the format.
    static func parse(_ text: String) throws -> [CNBRateRow] {
        var columns: [Column]?
        var rows: [CNBRateRow] = []
        for line in CNBFormat.lines(text) {
            let cells = CNBFormat.cells(line)
            if cells[0] == "Datum" {
                columns = try readHeader(cells)
            } else if let columns {
                rows += try readRates(cells, columns: columns)
            } else {
                throw CNBParseError.malformedHeader
            }
        }
        guard columns != nil else { throw CNBParseError.malformedHeader }
        return rows
    }

    /// The columns a header line names.
    private static func readHeader(_ cells: [Substring]) throws -> [Column] {
        let titles = cells.dropFirst()
        guard !titles.isEmpty else { throw CNBParseError.malformedHeader }
        return try titles.map { title in
            let parts = title.split(separator: " ", omittingEmptySubsequences: false)
            guard parts.count == 2,
                let amount = CNBFormat.positiveInteger(parts[0]),
                let currency = CurrencyCode(String(parts[1]))
            else {
                throw CNBParseError.malformedHeader
            }
            return Column(amount: amount, currency: currency)
        }
    }

    /// The rates of a line: its day, and a rate for each column that is not empty.
    private static func readRates(_ cells: [Substring], columns: [Column]) throws -> [CNBRateRow] {
        guard cells.count == columns.count + 1, let declaredOn = CNBFormat.date(cells[0]) else {
            throw CNBParseError.malformedRow
        }
        var rows: [CNBRateRow] = []
        for (column, cell) in zip(columns, cells.dropFirst()) where !cell.isEmpty {
            guard let rate = CNBFormat.rate(cell) else { throw CNBParseError.malformedRow }
            rows.append(
                CNBRateRow(declaredOn: declaredOn, currency: column.currency, amount: column.amount, rate: rate))
        }
        return rows
    }
}

/// Reads the daily file of the ČNB, `denni_kurz.txt`: the rates declared on one day, a row for each currency.
///
/// ```
/// 16.10.2026 #200
/// země|měna|množství|kód|kurz
/// Japonsko|jen|100|JPY|13,686
/// USA|dolar|1|USD|21,622
/// ```
///
/// The first line has the day and the number of the declaration in the year. The titles of the columns have to be
/// the ones above, so that a file with its columns changed is rejected instead of read wrong.
nonisolated enum CNBDailyParser {
    private static let columnTitles = "země|měna|množství|kód|kurz"

    /// The day the rates were declared on, and the rate of each row. Throws `CNBParseError` unless the whole text is in
    /// the format.
    static func parse(_ text: String) throws -> (declaredOn: CivilDate, rows: [CNBRateRow]) {
        var lines = CNBFormat.lines(text)[...]
        guard let firstLine = lines.popFirst(),
            let declaredOn = declarationDate(ofFirstLine: firstLine),
            let titles = lines.popFirst(),
            titles == columnTitles
        else {
            throw CNBParseError.malformedHeader
        }
        let rows = try lines.map { line in
            let cells = CNBFormat.cells(line)
            guard cells.count == 5,
                let amount = CNBFormat.positiveInteger(cells[2]),
                let currency = CurrencyCode(String(cells[3])),
                let rate = CNBFormat.rate(cells[4])
            else {
                throw CNBParseError.malformedRow
            }
            return CNBRateRow(declaredOn: declaredOn, currency: currency, amount: amount, rate: rate)
        }
        return (declaredOn, rows)
    }

    /// The day in a line such as `16.10.2026 #200`.
    private static func declarationDate(ofFirstLine line: Substring) -> CivilDate? {
        let parts = line.split(separator: " ", omittingEmptySubsequences: false)
        guard parts.count == 2,
            parts[1].first == "#",
            CNBFormat.positiveInteger(parts[1].dropFirst()) != nil
        else {
            return nil
        }
        return CNBFormat.date(parts[0])
    }
}

/// What the yearly and the daily file have in common. Every reader is strict: it accepts the one way the ČNB writes a
/// date, a unit amount or a rate and nothing near it, because a number read loosely can be a wrong rate.
private nonisolated enum CNBFormat {
    /// The lines of `text` that are not empty, whichever line ending the file has.
    static func lines(_ text: String) -> [Substring] {
        text.split(whereSeparator: \.isNewline)
    }

    /// The cells of a line, which are separated by `|`. An empty cell is kept, so the others keep their columns.
    static func cells(_ line: Substring) -> [Substring] {
        line.split(separator: "|", omittingEmptySubsequences: false)
    }

    /// A date written `DD.MM.YYYY`, two digits for the day and the month and four for the year. Nil if the date does
    /// not exist.
    static func date(_ text: Substring) -> CivilDate? {
        let parts = text.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 3,
            parts[0].count == 2, parts[1].count == 2, parts[2].count == 4,
            let day = wholeNumber(parts[0]), let month = wholeNumber(parts[1]), let year = wholeNumber(parts[2])
        else {
            return nil
        }
        return CivilDate(year: year, month: month, day: day)
    }

    /// A unit amount or a sequence number: digits only, and above zero. `Int(_:)` alone would also read a sign.
    static func positiveInteger(_ text: Substring) -> Int? {
        guard let value = wholeNumber(text), value > 0 else { return nil }
        return value
    }

    /// A rate with a decimal comma, `21,622` (or a whole number, `30`), above zero. A point, a sign, a space or
    /// anything else is not read: `1.234` could be 1.234 or 1 234.
    static func rate(_ text: Substring) -> Decimal? {
        let parts = text.split(separator: ",", omittingEmptySubsequences: false)
        guard (1...2).contains(parts.count),
            parts.allSatisfy({ isDigits($0) }),
            let value = DecimalMath.decimal(parts.joined(separator: ".")),
            value > 0
        else {
            return nil
        }
        return value
    }

    private static func wholeNumber(_ text: Substring) -> Int? {
        isDigits(text) ? Int(text) : nil
    }

    /// Whether `text` is one or more ASCII digits.
    private static func isDigits(_ text: Substring) -> Bool {
        !text.isEmpty && text.utf8.allSatisfy { (UInt8(ascii: "0")...UInt8(ascii: "9")).contains($0) }
    }
}
