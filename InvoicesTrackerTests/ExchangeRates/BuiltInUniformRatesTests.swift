import Foundation
import Testing
@testable import InvoicesTracker

struct BuiltInUniformRatesTests {
    /// The tables as the GFŘ instructions print them: `CODE amount:rate`, the rate in crowns per `amount` units of the
    /// currency, with a decimal comma. The 2024 table is the one of GFŘ-D-65 as corrected by GFŘ-D-66.
    static let publishedTables: [Int: String] = [
        2022: """
            AUD 1:16,21 BGN 1:12,55 BRL 1:4,55 CAD 1:17,93 CHF 1:24,51 CNY 1:3,47 DKK 1:3,30 EUR 1:24,54
            GBP 1:28,72 HKD 1:2,99 HRK 1:3,25 HUF 100:6,26 IDR 1000:1,57 ILS 1:6,93 INR 100:29,69 ISK 100:17,31
            JPY 100:17,79 KRW 100:1,81 MXN 1:1,17 MYR 1:5,31 NOK 1:2,43 NZD 1:14,79 PHP 100:42,92 PLN 1:5,24
            RON 1:4,97 SEK 1:2,30 SGD 1:16,97 THB 100:66,68 TRY 1:1,42 USD 1:23,41 XDR 1:31,21 ZAR 1:1,43
            """,
        2023: """
            AUD 1:14,67 BGN 1:12,26 BRL 1:4,45 CAD 1:16,40 CHF 1:24,69 CNY 1:3,12 DKK 1:3,22 EUR 1:23,97
            GBP 1:27,59 HKD 1:2,83 HUF 100:6,30 IDR 1000:1,46 ILS 1:5,97 INR 100:26,80 ISK 100:16,16 JPY 100:15,67
            KRW 100:1,69 MXN 1:1,26 MYR 1:4,85 NOK 1:2,09 NZD 1:13,57 PHP 100:39,82 PLN 1:5,31 RON 1:4,84
            SEK 1:2,09 SGD 1:16,49 THB 100:63,56 TRY 1:0,94 USD 1:22,14 XDR 1:29,54 ZAR 1:1,20
            """,
        2024: """
            AUD 1:15,31 BGN 1:12,86 BRL 1:4,29 CAD 1:16,96 CHF 1:26,40 CNY 1:3,24 DKK 1:3,37 EUR 1:25,16
            GBP 1:29,78 HKD 1:2,98 HUF 100:6,34 IDR 1000:1,47 ILS 1:6,32 INR 100:27,80 ISK 100:16,89 JPY 100:15,35
            KRW 100:1,70 MXN 1:1,26 MYR 1:5,11 NOK 1:2,16 NZD 1:14,03 PHP 100:40,55 PLN 1:5,85 RON 1:5,06
            SEK 1:2,20 SGD 1:17,41 THB 100:66,21 TRY 100:70,48 USD 1:23,28 XDR 1:30,87 ZAR 1:1,27
            """,
        2025: """
            AUD 1:14,06 BGN 1:12,61 BRL 1:3,92 CAD 1:15,61 CHF 1:26,33 CNY 1:3,05 DKK 1:3,30 EUR 1:24,66
            GBP 1:28,80 HKD 1:2,80 HUF 100:6,22 IDR 1000:1,32 ILS 1:6,37 INR 100:25,03 ISK 100:17,06 JPY 100:14,59
            KRW 100:1,54 MXN 1:1,14 MYR 1:5,11 NOK 1:2,11 NZD 1:12,67 PHP 100:37,90 PLN 1:5,82 RON 1:4,89
            SEK 1:2,23 SGD 1:16,71 THB 100:66,45 TRY 100:55,11 USD 1:21,84 XDR 1:29,49 ZAR 1:1,22
            """,
    ]

    /// Reads a table in the `CODE amount:rate` form of `publishedTables`.
    func entries(_ table: String) -> [UniformRateEntry] {
        let tokens = table.split(whereSeparator: \.isWhitespace)
        precondition(tokens.count.isMultiple(of: 2), "Every currency needs a code and a quote.")
        return stride(from: 0, to: tokens.count, by: 2).map { index in
            let quote = tokens[index + 1].split(separator: ":")
            guard quote.count == 2,
                let currency = CurrencyCode(String(tokens[index])),
                let amount = Int(quote[0])
            else {
                preconditionFailure("Not a currency quote: \(tokens[index]) \(tokens[index + 1])")
            }
            return UniformRateEntry(
                currency: currency,
                amount: amount,
                rate: decimal(String(quote[1]).replacing(",", with: "."))
            )
        }
    }

    func entry(_ code: String, _ amount: Int, _ rate: String) -> UniformRateEntry {
        UniformRateEntry(currency: CurrencyCode(code)!, amount: amount, rate: decimal(rate))
    }

    /// The built-in entry of one currency in one year, if the year's table lists it.
    func builtIn(_ code: String, in year: Int) -> UniformRateEntry? {
        BuiltInUniformRates.rates(year: year).first { $0.currency.code == code }
    }

    // MARK: The tables

    @Test func tablesListEveryCurrencyOfTheirInstruction() {
        #expect(BuiltInUniformRates.rates(year: 2022).count == 32)
        #expect(BuiltInUniformRates.rates(year: 2023).count == 31)
        #expect(BuiltInUniformRates.rates(year: 2024).count == 31)
        #expect(BuiltInUniformRates.rates(year: 2025).count == 31)
    }

    @Test(arguments: [2026, 2021, 2027, 0, -2022, Int.max])
    func yearsWithoutAPublishedTableHaveNoRates(_ year: Int) {
        #expect(BuiltInUniformRates.rates(year: year) == [])
    }

    @Test(arguments: [2022, 2023, 2024, 2025])
    func everyRateIsAsPublished(_ year: Int) throws {
        let expected = entries(try #require(BuiltInUniformRatesTests.publishedTables[year]))
        let rates = BuiltInUniformRates.rates(year: year)
        #expect(rates.count == expected.count, "\(year) lists \(expected.count) currencies")
        let difference = Set(rates).symmetricDifference(expected)
        #expect(difference.isEmpty, "\(year) differs in \(difference.sorted { $0.currency < $1.currency })")
    }

    @Test(arguments: [2022, 2023, 2024, 2025])
    func eachCurrencyIsListedOncePerYear(_ year: Int) {
        let currencies = BuiltInUniformRates.rates(year: year).map(\.currency)
        #expect(Set(currencies).count == currencies.count)
    }

    @Test func publishedValuesOfNote() {
        #expect(builtIn("USD", in: 2025) == entry("USD", 1, "21.84"))
        #expect(builtIn("EUR", in: 2025) == entry("EUR", 1, "24.66"))
        // GFŘ-D-66 corrected the quoted amount of the Turkish lira in the 2024 table from 1 to 100 units.
        #expect(builtIn("TRY", in: 2024) == entry("TRY", 100, "70.48"))
        // The Croatian kuna is in the 2022 table only.
        #expect(builtIn("HRK", in: 2022) == entry("HRK", 1, "3.25"))
        #expect(builtIn("HRK", in: 2023) == nil)
        // Some currencies are quoted per 100 or 1000 units.
        #expect(builtIn("IDR", in: 2022) == entry("IDR", 1000, "1.57"))
        #expect(builtIn("HUF", in: 2022) == entry("HUF", 100, "6.26"))
        #expect(builtIn("JPY", in: 2025) == entry("JPY", 100, "14.59"))
    }

    // MARK: Instructions

    @Test func instructionsNameTheGFRPublicationOfEachYear() {
        #expect(BuiltInUniformRates.instructions[2025] == "GFŘ-D-75")
        #expect(
            BuiltInUniformRates.instructions == [2022: "GFŘ-D-60", 2023: "GFŘ-D-63", 2024: "GFŘ-D-65", 2025: "GFŘ-D-75"]
        )
        #expect(BuiltInUniformRates.instructions[2026] == nil)
    }

    @Test func onlyTheTurkishLiraOf2024WasCorrected() {
        #expect(BuiltInUniformRates.correctionNote == [2024: "TRY opraven pokynem GFŘ-D-66"])
    }
}
