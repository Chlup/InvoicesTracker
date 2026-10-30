import Foundation
import Testing
@testable import InvoicesTracker

struct CNBParserTests {
    // MARK: Helpers

    /// `amount` units of `code` cost `rate` crowns, the rate as plain POSIX text.
    private func quote(_ code: String, _ amount: Int, _ rate: String) -> ExchangeRate {
        ExchangeRate(currency: CurrencyCode(code)!, amount: amount, rate: decimal(rate))
    }

    /// The rate of one currency declared on one day, nil when the rows have none.
    private func rate(_ code: String, on day: String, in rows: [CNBRateRow]) -> ExchangeRate? {
        rows.first { $0.currency.code == code && $0.declaredOn == civilDate(day) }?.exchangeRate
    }

    private func row(_ day: String, _ code: String, _ amount: Int, _ rate: String) -> CNBRateRow {
        CNBRateRow(declaredOn: civilDate(day), currency: CurrencyCode(code)!, amount: amount, rate: decimal(rate))
    }

    private func declarationDays(of rows: [CNBRateRow]) -> Set<CivilDate> {
        Set(rows.map(\.declaredOn))
    }

    // MARK: Yearly files

    @Test func yearly2022() throws {
        let rows = try cnbYearlyRows([2022])
        #expect(declarationDays(of: rows).count == 252)
        // The header changes after 1 March and RUB disappears with it: 42 days with 33 currencies, then 210 with 32.
        #expect(rows.count == 42 * 33 + 210 * 32)
        #expect(rate("USD", on: "2022-01-03", in: rows) == quote("USD", 1, "21.860"))
        #expect(rate("EUR", on: "2022-01-03", in: rows) == quote("EUR", 1, "24.820"))
        #expect(rate("RUB", on: "2022-01-03", in: rows) == quote("RUB", 100, "29.362"))
        #expect(rate("USD", on: "2022-03-04", in: rows) == quote("USD", 1, "23.549"))
        #expect(rate("EUR", on: "2022-03-04", in: rows) == quote("EUR", 1, "25.735"))
        #expect(rate("RUB", on: "2022-03-04", in: rows) == nil)
        #expect(rate("USD", on: "2022-12-30", in: rows) == quote("USD", 1, "22.616"))
        #expect(rate("EUR", on: "2022-12-30", in: rows) == quote("EUR", 1, "24.115"))
    }

    @Test func rubleIsQuotedInThe2022FileThrough1MarchAndNotAfter() throws {
        let rows = try cnbYearlyRows([2022])
        #expect(rate("RUB", on: "2022-03-01", in: rows) == quote("RUB", 100, "22.877"))
        #expect(rate("USD", on: "2022-03-01", in: rows) == quote("USD", 1, "22.824"))
        #expect(rate("USD", on: "2022-03-02", in: rows) == quote("USD", 1, "23.297"))
        let rubleDays = rows.filter { $0.currency.code == "RUB" }.map(\.declaredOn)
        #expect(rubleDays.count == 42)
        #expect(rubleDays.allSatisfy { $0 <= civilDate("2022-03-01") })
    }

    @Test func yearly2025() throws {
        let rows = try cnbYearlyRows([2025])
        #expect(declarationDays(of: rows).count == 251)
        #expect(rows.count == 251 * 31)
        #expect(rate("USD", on: "2025-12-31", in: rows) == quote("USD", 1, "20.632"))
        #expect(rate("EUR", on: "2025-12-31", in: rows) == quote("EUR", 1, "24.245"))
    }

    @Test func yearly2026() throws {
        let rows = try cnbYearlyRows([2026])
        #expect(declarationDays(of: rows).count == 200)
        #expect(rows.count == 200 * 30)
        #expect(rate("USD", on: "2026-01-02", in: rows) == quote("USD", 1, "20.611"))
        #expect(rate("USD", on: "2026-10-16", in: rows) == quote("USD", 1, "21.622"))
        #expect(rate("EUR", on: "2026-10-16", in: rows) == quote("EUR", 1, "24.325"))
        #expect(rate("USD", on: "2026-09-30", in: rows) == quote("USD", 1, "21.522"))
        #expect(rate("USD", on: "2026-10-02", in: rows) == quote("USD", 1, "21.795"))
    }

    @Test func unitAmountsComeFromTheHeader() throws {
        let rows = try cnbYearlyRows([2026])
        #expect(rate("JPY", on: "2026-10-16", in: rows) == quote("JPY", 100, "13.686"))
        #expect(rate("HUF", on: "2026-10-16", in: rows) == quote("HUF", 100, "6.701"))
        #expect(rate("IDR", on: "2026-10-16", in: rows) == quote("IDR", 1000, "1.201"))
        #expect(rate("XDR", on: "2026-10-16", in: rows) == quote("XDR", 1, "29.276"))
    }

    /// The ČNB declares rates on business days only, so the declaration days of a year are its business days.
    @Test(arguments: [(2022, "2022-12-31"), (2025, "2025-12-31"), (2026, "2026-10-16")])
    func declarationDaysAreExactlyTheBusinessDays(_ year: Int, _ lastDay: String) throws {
        let rows = try cnbYearlyRows([year])
        let first = civilDate("\(year)-01-01")
        let last = civilDate(lastDay)
        let businessDays = Set(
            (0...last.days(since: first)).map { first.adding(days: $0) }.filter(CzechCalendar.isBusinessDay))
        #expect(declarationDays(of: rows) == businessDays)
    }

    @Test func laterHeaderReplacesTheColumns() throws {
        let text = """
            Datum|1 USD|100 RUB
            01.03.2022|22,824|22,877
            Datum|1 USD
            02.03.2022|23,297
            """
        #expect(
            try CNBYearlyParser.parse(text) == [
                row("2022-03-01", "USD", 1, "22.824"),
                row("2022-03-01", "RUB", 100, "22.877"),
                row("2022-03-02", "USD", 1, "23.297"),
            ])
    }

    @Test func rowInTheOldLayoutAfterANewHeaderIsRejected() {
        let text = "Datum|1 USD|100 RUB\nDatum|1 USD\n02.03.2022|23,297|32,493\n"
        #expect(throws: CNBParseError.malformedRow) { try CNBYearlyParser.parse(text) }
    }

    @Test func emptyCellsAreSkipped() throws {
        let text = "Datum|1 USD|1 EUR|100 JPY\n03.01.2022|21,860||13,686\n04.01.2022|||\n05.01.2022||24,750|\n"
        #expect(
            try CNBYearlyParser.parse(text) == [
                row("2022-01-03", "USD", 1, "21.860"),
                row("2022-01-03", "JPY", 100, "13.686"),
                row("2022-01-05", "EUR", 1, "24.750"),
            ])
    }

    @Test func headerWithoutRowsGivesNoRows() throws {
        #expect(try CNBYearlyParser.parse("Datum|1 USD|1 EUR\n") == [])
    }

    @Test func lineEndingsAndBlankLinesDoNotMatter() throws {
        let expected = [row("2026-10-15", "USD", 1, "21.732"), row("2026-10-16", "USD", 1, "21.622")]
        let lines = ["Datum|1 USD", "15.10.2026|21,732", "16.10.2026|21,622"]
        #expect(try CNBYearlyParser.parse(lines.joined(separator: "\n")) == expected)
        #expect(try CNBYearlyParser.parse(lines.joined(separator: "\r\n") + "\r\n") == expected)
        #expect(try CNBYearlyParser.parse("\n" + lines.joined(separator: "\n\n") + "\n\n") == expected)
    }

    @Test func rateIsReadExactlyFromTheDecimalComma() throws {
        let rows = try CNBYearlyParser.parse("Datum|1 USD\n03.01.2022|21,860\n04.01.2022|30\n05.01.2022|0,001\n")
        #expect(rows.map(\.rate) == [decimal("21.86"), decimal("30"), decimal("0.001")])
        #expect(rows.map { DecimalMath.canonical($0.rate) } == ["21.86", "30", "0.001"])
    }

    @Test(arguments: [
        "31.02.2022|21,860|24,820",  // not a date
        "2022-01-03|21,860|24,820",  // not the ČNB's date format
        "3.1.2022|21,860|24,820",  // no leading zeros
        "03.01.22|21,860|24,820",  // a two-digit year
        "03.01.2022 |21,860|24,820",  // a space after the date
        "\u{0660}\u{0663}.\u{0660}\u{0661}.\u{0662}\u{0660}\u{0662}\u{0662}|21,860|24,820",  // Arabic-Indic digits
        "|21,860|24,820",  // no date
        "03.01.2022|21,860",  // a cell missing
        "03.01.2022",  // no cells at all
        " ",  // spaces are not an empty line
        "03.01.2022|21,860|24,820|1,000",  // a cell too many
        "03.01.2022|21,860|24,820|",  // an empty cell too many
        "03.01.2022|21.860|24,820",  // a decimal point
        "03.01.2022|1.234,50|24,820",  // a thousands separator
        "03.01.2022|1 234,50|24,820",  // a space as the thousands separator
        "03.01.2022|abc|24,820",
        "03.01.2022|21,|24,820",  // no digits after the comma
        "03.01.2022|,5|24,820",  // no digits before the comma
        "03.01.2022|21,6,2|24,820",  // two commas
        "03.01.2022| 21,860|24,820",  // a space in the cell
        "03.01.2022|21,860 |24,820",
        "03.01.2022|-21,860|24,820",  // negative
        "03.01.2022|+21,860|24,820",
        "03.01.2022|21,8e1|24,820",  // an exponent
        "03.01.2022|\u{FF12}\u{FF11},860|24,820",  // fullwidth digits
        "03.01.2022|0,000|24,820",  // not positive
        "03.01.2022|0|24,820",
        "03.01.2022|21,860|0,000",  // the same in a later cell
        "03.01.2022|21,860|-24,820",
        "03.01.2022|99999999999999999999999999999999999999999,5|24,820",  // more digits than a decimal holds
    ])
    func yearlyRowsThatAreNotRatesAreRejected(_ line: String) {
        // A valid header of two currencies, then the line.
        let text = "Datum|1 USD|1 EUR\n\(line)\n"
        #expect(throws: CNBParseError.malformedRow) { try CNBYearlyParser.parse(text) }
    }

    @Test(arguments: [
        "",  // nothing at all
        "\n\n",
        "03.01.2022|21,860|24,820\n",  // a row before any header
        "datum|1 USD|1 EUR\n03.01.2022|21,860|24,820\n",  // the first cell is not Datum
        "Datum\n",  // no currency columns
        "Datum|\n",  // an empty column title
        "Datum|1 USD|\n",  // an empty column title at the end
        "Datum|0 USD\n",  // a unit amount of zero
        "Datum|-1 USD\n",
        "Datum|+1 USD\n",
        "Datum|1,5 USD\n",
        "Datum|x USD\n",
        "Datum|99999999999999999999 USD\n",  // a unit amount no Int holds
        "Datum|USD\n",  // no unit amount
        "Datum|1\n",  // no currency code
        "Datum|1 usd\n",
        "Datum|1 US\n",
        "Datum|1 USDX\n",
        "Datum|1  USD\n",  // two spaces
        "Datum| 1 USD\n",
        "Datum|1 USD|1 US\n",
        "Datum|1 USD\n03.01.2022|21,860\nDatum|1 US\n",  // a later header has to be valid too
    ])
    func yearlyTextsWithoutAValidHeaderAreRejected(_ text: String) {
        #expect(throws: CNBParseError.malformedHeader) { try CNBYearlyParser.parse(text) }
    }

    // MARK: Daily file

    private static let dailyTitles = "země|měna|množství|kód|kurz"

    @Test func dailyFile() throws {
        let daily = try CNBDailyParser.parse(cnbFixture("cnb_denni_2026-10-16"))
        #expect(daily.declaredOn == civilDate("2026-10-16"))
        #expect(daily.rows.count == 5)
        #expect(daily.rows.allSatisfy { $0.declaredOn == civilDate("2026-10-16") })
        #expect(rate("USD", on: "2026-10-16", in: daily.rows) == quote("USD", 1, "21.622"))
        #expect(rate("JPY", on: "2026-10-16", in: daily.rows) == quote("JPY", 100, "13.686"))
        #expect(rate("EUR", on: "2026-10-16", in: daily.rows) == quote("EUR", 1, "24.325"))
        #expect(rate("AUD", on: "2026-10-16", in: daily.rows) == quote("AUD", 1, "15.045"))
        #expect(rate("GBP", on: "2026-10-16", in: daily.rows) == quote("GBP", 1, "28.839"))
    }

    @Test func dailyRowsAreTheRowsOfTheYearlyFileForTheSameDay() throws {
        let daily = try CNBDailyParser.parse(cnbFixture("cnb_denni_2026-10-16"))
        let rowsOfTheYear = try cnbYearlyRows([2026])
        for dailyRow in daily.rows {
            #expect(rowsOfTheYear.contains(dailyRow), "\(dailyRow.currency)")
        }
    }

    @Test func dailyLineEndingsAndBlankLinesDoNotMatter() throws {
        let lines = ["16.10.2026 #200", Self.dailyTitles, "USA|dolar|1|USD|21,622", "Japonsko|jen|100|JPY|13,686"]
        let expected = [row("2026-10-16", "USD", 1, "21.622"), row("2026-10-16", "JPY", 100, "13.686")]
        for text in [
            lines.joined(separator: "\n"),
            lines.joined(separator: "\r\n") + "\r\n",
            lines.joined(separator: "\n\n") + "\n\n",
        ] {
            let daily = try CNBDailyParser.parse(text)
            #expect(daily.declaredOn == civilDate("2026-10-16"))
            #expect(daily.rows == expected)
        }
    }

    @Test func dailyFileWithoutRatesGivesNoRows() throws {
        let daily = try CNBDailyParser.parse("16.10.2026 #200\n\(Self.dailyTitles)\n")
        #expect(daily.declaredOn == civilDate("2026-10-16"))
        #expect(daily.rows == [])
    }

    @Test(arguments: [
        "",
        "16.10.2026",  // no sequence number
        "16.10.2026 200",  // no #
        "16.10.2026 #",
        "16.10.2026 #x",
        "16.10.2026 #0",
        "16.10.2026 #-1",
        "16.10.2026 #2 0",
        "16.10.2026  #200",
        "16.10.2026 #200 ",
        " 16.10.2026 #200",
        "16.10.2026#200",
        "31.02.2026 #200",
        "2026-10-16 #200",
        "16.10.26 #200",
        "#200",
        "země|měna|množství|kód|kurz",  // the titles where the date belongs
        "USA|dolar|1|USD|21,622",
    ])
    func dailyTextsWithoutAValidFirstLineAreRejected(_ firstLine: String) {
        let text = "\(firstLine)\n\(Self.dailyTitles)\nUSA|dolar|1|USD|21,622\n"
        #expect(throws: CNBParseError.malformedHeader) { try CNBDailyParser.parse(text) }
    }

    @Test(arguments: [
        "16.10.2026 #200\n",  // no titles
        "16.10.2026 #200\nUSA|dolar|1|USD|21,622\n",  // a rate where the titles belong
        "16.10.2026 #200\nzemě|měna|kód|množství|kurz\nUSA|dolar|USD|1|21,622\n",  // the columns moved
        "16.10.2026 #200\nzemě|měna|množství|kód|kurz|rok\nUSA|dolar|1|USD|21,622|2026\n",  // a column added
        "16.10.2026 #200\nzemě|měna|množství|kód\nUSA|dolar|1|USD\n",  // a column dropped
        "16.10.2026 #200\n\n",
    ])
    func dailyTextsWithoutTheExpectedColumnTitlesAreRejected(_ text: String) {
        #expect(throws: CNBParseError.malformedHeader) { try CNBDailyParser.parse(text) }
    }

    @Test(arguments: [
        "USA|dolar|0|USD|21,622",  // a unit amount of zero
        "USA|dolar|-1|USD|21,622",
        "USA|dolar|+1|USD|21,622",
        "USA|dolar|1,5|USD|21,622",
        "USA|dolar||USD|21,622",
        "USA|dolar|jedna|USD|21,622",
        "USA|dolar|99999999999999999999|USD|21,622",
        "USA|dolar|1|usd|21,622",
        "USA|dolar|1|US|21,622",
        "USA|dolar|1|USDX|21,622",
        "USA|dolar|1||21,622",
        "USA|dolar|1|USD|21.622",
        "USA|dolar|1|USD|1.234,50",
        "USA|dolar|1|USD|-21,622",
        "USA|dolar|1|USD|0,000",
        "USA|dolar|1|USD|",  // no rate: unlike the yearly file, an empty cell is no row to skip
        "USA|dolar|1|USD|abc",
        "USA|dolar|1|USD",  // a cell missing
        "USA|dolar|1",
        "USA|dolar|1|USD|21,622|x",  // a cell too many
        " ",  // spaces are not an empty line
    ])
    func dailyRowsThatAreNotRatesAreRejected(_ line: String) {
        // A valid first line, titles and row, then the line.
        let text = "16.10.2026 #200\n\(Self.dailyTitles)\nEMU|euro|1|EUR|24,325\n\(line)\n"
        #expect(throws: CNBParseError.malformedRow) { try CNBDailyParser.parse(text) }
    }

    // MARK: Rows

    @Test func rowConvertsToAnExchangeRate() {
        let yen = row("2026-10-16", "JPY", 100, "13.686")
        #expect(yen.exchangeRate == ExchangeRate(currency: CurrencyCode("JPY")!, amount: 100, rate: decimal("13.686")))
        // 100 JPY cost 13,686 Kč, so 25 000 JPY (2 500 000 hundredths) are 3 421,50 Kč, which is 342 150 haléře.
        #expect(yen.exchangeRate.czkHalere(fromMinor: 2_500_000) == 342_150)
    }
}
