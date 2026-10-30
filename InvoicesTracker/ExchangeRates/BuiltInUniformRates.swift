import Foundation

/// One currency of a uniform exchange rate table: `rate` crowns for `amount` units of `currency`, the way the GFŘ
/// prints it (100 HUF cost 6.26 Kč, so the entry is HUF, 100, 6.26).
nonisolated struct UniformRateEntry: Sendable, Hashable {
    let currency: CurrencyCode

    /// The number of units the rate is for: 1, 100 or 1000.
    let amount: Int

    /// The price of `amount` units of the currency, in crowns.
    let rate: Decimal
}

/// The uniform exchange rates (jednotné kurzy) that the GFŘ published for the tax periods 2022 to 2025.
///
/// Taxpayers who do not keep accounts convert foreign currency at the uniform rate that the GFŘ sets for the year
/// (§ 38 odst. 1 zákona č. 586/1992 Sb.). Every currency of each published table is listed. The table for 2026 is not
/// published yet, so none is built in.
nonisolated enum BuiltInUniformRates {
    /// The GFŘ instruction that published the table of each year.
    static let instructions: [Int: String] = [
        2022: "GFŘ-D-60",
        2023: "GFŘ-D-63",
        2024: "GFŘ-D-65",
        2025: "GFŘ-D-75",
    ]

    /// What was corrected in a year's table after it was published, in words the app can show.
    static let correctionNote: [Int: String] = [
        2024: "TRY opraven pokynem GFŘ-D-66",
    ]

    /// The rates of `year`, one entry per currency in no particular order. Empty for a year without a built-in table.
    static func rates(year: Int) -> [UniformRateEntry] {
        tables[year] ?? []
    }

    /// The table of `year` as the app stores it, one rate per currency in no particular order: each with the
    /// instruction that published the table, built in, without a source or a confirmation, as a new database has it.
    /// Empty for a year without a built-in table.
    static func uniformRates(year: Int) -> [UniformRate] {
        guard let instruction = instructions[year] else { return [] }
        return rates(year: year).map { entry in
            UniformRate(
                year: year, currency: entry.currency, amount: entry.amount, rate: entry.rate, instruction: instruction,
                sourceURL: nil, confirmedAt: nil, origin: .builtIn)
        }
    }

    private static let tables: [Int: [UniformRateEntry]] = [
        2022: table2022,
        2023: table2023,
        2024: table2024,
        2025: table2025,
    ]

    private static func entry(_ code: String, _ amount: Int, _ rateText: String) -> UniformRateEntry {
        guard let currency = CurrencyCode(code), let rate = DecimalMath.decimal(rateText) else {
            preconditionFailure("Not a uniform rate: \(code) \(amount) \(rateText)")
        }
        return UniformRateEntry(currency: currency, amount: amount, rate: rate)
    }

    // MARK: 2022

    /// Pokyn GFŘ-D-60 (č. j. 174/23/7100-10111-010440, Finanční zpravodaj 1/2023). This is the only table with the
    /// Croatian kuna (HRK).
    private static let table2022: [UniformRateEntry] = [
        entry("AUD", 1, "16.21"),
        entry("BGN", 1, "12.55"),
        entry("BRL", 1, "4.55"),
        entry("CAD", 1, "17.93"),
        entry("CHF", 1, "24.51"),
        entry("CNY", 1, "3.47"),
        entry("DKK", 1, "3.30"),
        entry("EUR", 1, "24.54"),
        entry("GBP", 1, "28.72"),
        entry("HKD", 1, "2.99"),
        entry("HRK", 1, "3.25"),
        entry("HUF", 100, "6.26"),
        entry("IDR", 1000, "1.57"),
        entry("ILS", 1, "6.93"),
        entry("INR", 100, "29.69"),
        entry("ISK", 100, "17.31"),
        entry("JPY", 100, "17.79"),
        entry("KRW", 100, "1.81"),
        entry("MXN", 1, "1.17"),
        entry("MYR", 1, "5.31"),
        entry("NOK", 1, "2.43"),
        entry("NZD", 1, "14.79"),
        entry("PHP", 100, "42.92"),
        entry("PLN", 1, "5.24"),
        entry("RON", 1, "4.97"),
        entry("SEK", 1, "2.30"),
        entry("SGD", 1, "16.97"),
        entry("THB", 100, "66.68"),
        entry("TRY", 1, "1.42"),
        entry("USD", 1, "23.41"),
        entry("XDR", 1, "31.21"),
        entry("ZAR", 1, "1.43"),
    ]

    // MARK: 2023

    /// Pokyn GFŘ-D-63 (č. j. 77/24/7100-10111-010440, Finanční zpravodaj 1/2024).
    private static let table2023: [UniformRateEntry] = [
        entry("AUD", 1, "14.67"),
        entry("BGN", 1, "12.26"),
        entry("BRL", 1, "4.45"),
        entry("CAD", 1, "16.40"),
        entry("CHF", 1, "24.69"),
        entry("CNY", 1, "3.12"),
        entry("DKK", 1, "3.22"),
        entry("EUR", 1, "23.97"),
        entry("GBP", 1, "27.59"),
        entry("HKD", 1, "2.83"),
        entry("HUF", 100, "6.30"),
        entry("IDR", 1000, "1.46"),
        entry("ILS", 1, "5.97"),
        entry("INR", 100, "26.80"),
        entry("ISK", 100, "16.16"),
        entry("JPY", 100, "15.67"),
        entry("KRW", 100, "1.69"),
        entry("MXN", 1, "1.26"),
        entry("MYR", 1, "4.85"),
        entry("NOK", 1, "2.09"),
        entry("NZD", 1, "13.57"),
        entry("PHP", 100, "39.82"),
        entry("PLN", 1, "5.31"),
        entry("RON", 1, "4.84"),
        entry("SEK", 1, "2.09"),
        entry("SGD", 1, "16.49"),
        entry("THB", 100, "63.56"),
        entry("TRY", 1, "0.94"),
        entry("USD", 1, "22.14"),
        entry("XDR", 1, "29.54"),
        entry("ZAR", 1, "1.20"),
    ]

    // MARK: 2024

    /// Pokyn GFŘ-D-65 (č. j. 87495/24/7100-10111-010440) as corrected by pokyn GFŘ-D-66
    /// (č. j. 8091/25/7100-10111-010440), which replaced it. The correction changed one thing: the Turkish lira is
    /// quoted for 100 units, not 1, at the same 70.48 Kč.
    private static let table2024: [UniformRateEntry] = [
        entry("AUD", 1, "15.31"),
        entry("BGN", 1, "12.86"),
        entry("BRL", 1, "4.29"),
        entry("CAD", 1, "16.96"),
        entry("CHF", 1, "26.40"),
        entry("CNY", 1, "3.24"),
        entry("DKK", 1, "3.37"),
        entry("EUR", 1, "25.16"),
        entry("GBP", 1, "29.78"),
        entry("HKD", 1, "2.98"),
        entry("HUF", 100, "6.34"),
        entry("IDR", 1000, "1.47"),
        entry("ILS", 1, "6.32"),
        entry("INR", 100, "27.80"),
        entry("ISK", 100, "16.89"),
        entry("JPY", 100, "15.35"),
        entry("KRW", 100, "1.70"),
        entry("MXN", 1, "1.26"),
        entry("MYR", 1, "5.11"),
        entry("NOK", 1, "2.16"),
        entry("NZD", 1, "14.03"),
        entry("PHP", 100, "40.55"),
        entry("PLN", 1, "5.85"),
        entry("RON", 1, "5.06"),
        entry("SEK", 1, "2.20"),
        entry("SGD", 1, "17.41"),
        entry("THB", 100, "66.21"),
        entry("TRY", 100, "70.48"),
        entry("USD", 1, "23.28"),
        entry("XDR", 1, "30.87"),
        entry("ZAR", 1, "1.27"),
    ]

    // MARK: 2025

    /// Pokyn GFŘ-D-75 (č. j. 95534/25/7100-10111-802540, Finanční zpravodaj 02/2026 of 14 January 2026).
    private static let table2025: [UniformRateEntry] = [
        entry("AUD", 1, "14.06"),
        entry("BGN", 1, "12.61"),
        entry("BRL", 1, "3.92"),
        entry("CAD", 1, "15.61"),
        entry("CHF", 1, "26.33"),
        entry("CNY", 1, "3.05"),
        entry("DKK", 1, "3.30"),
        entry("EUR", 1, "24.66"),
        entry("GBP", 1, "28.80"),
        entry("HKD", 1, "2.80"),
        entry("HUF", 100, "6.22"),
        entry("IDR", 1000, "1.32"),
        entry("ILS", 1, "6.37"),
        entry("INR", 100, "25.03"),
        entry("ISK", 100, "17.06"),
        entry("JPY", 100, "14.59"),
        entry("KRW", 100, "1.54"),
        entry("MXN", 1, "1.14"),
        entry("MYR", 1, "5.11"),
        entry("NOK", 1, "2.11"),
        entry("NZD", 1, "12.67"),
        entry("PHP", 100, "37.90"),
        entry("PLN", 1, "5.82"),
        entry("RON", 1, "4.89"),
        entry("SEK", 1, "2.23"),
        entry("SGD", 1, "16.71"),
        entry("THB", 100, "66.45"),
        entry("TRY", 100, "55.11"),
        entry("USD", 1, "21.84"),
        entry("XDR", 1, "29.49"),
        entry("ZAR", 1, "1.22"),
    ]
}
