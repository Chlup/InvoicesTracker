import Foundation
import Testing
@testable import InvoicesTracker

struct PreliminaryUniformRatesTests {
    // MARK: Helpers

    /// A table of rows declared on `day`, each with its rate for an amount of 1. A nil rate leaves the currency out.
    private func rows(_ day: String, usd: String?, eur: String?) -> [CNBRateRow] {
        var rows: [CNBRateRow] = []
        if let usd {
            rows.append(CNBRateRow(declaredOn: civilDate(day), currency: .usd, amount: 1, rate: decimal(usd)))
        }
        if let eur {
            rows.append(CNBRateRow(declaredOn: civilDate(day), currency: .eur, amount: 1, rate: decimal(eur)))
        }
        return rows
    }

    /// The month-end rows of 2025 as the ČNB declared them: the declaration day, USD and EUR.
    private static let rates2025: [(day: String, usd: String, eur: String)] = [
        ("2025-01-31", "24.214", "25.170"), ("2025-02-28", "24.034", "25.025"),
        ("2025-03-31", "23.079", "24.965"), ("2025-04-30", "21.905", "24.930"),
        ("2025-05-30", "21.967", "24.930"), ("2025-06-30", "21.127", "24.750"),
        ("2025-07-31", "21.468", "24.570"), ("2025-08-29", "20.967", "24.445"),
        ("2025-09-30", "20.727", "24.340"), ("2025-10-31", "21.062", "24.335"),
        ("2025-11-28", "20.895", "24.170"), ("2025-12-31", "20.632", "24.245")
    ]

    private func table2025(without days: [String] = []) -> RateTable {
        let all = Self.rates2025.filter { !days.contains($0.day) }.flatMap { rows($0.day, usd: $0.usd, eur: $0.eur) }
        return RateTable(rows: all)
    }

    private func compute(_ table: RateTable, year: Int, today: String) -> PreliminaryUniformRates.Computation {
        PreliminaryUniformRates.compute(year: year, today: civilDate(today)) { table.lookup($0, on: $1) }
    }

    private func rates(_ computation: PreliminaryUniformRates.Computation) -> [UniformRate] {
        guard case .rates(let rates) = computation.outcome else {
            Issue.record("Expected rates, got \(computation.outcome).")
            return []
        }
        return rates
    }

    // MARK: Tests

    @Test func theTwelveMonthEndRatesOf2025GiveTheRatesOfGFRD75() {
        let computation = compute(table2025(), year: 2025, today: "2026-01-08")
        let rates = rates(computation)
        #expect(rates.map(\.currency) == [.usd, .eur])
        #expect(rates.map(\.rate) == [decimal("21.84"), decimal("24.66")])
        #expect(rates.allSatisfy { $0.computedMonths == 12 && $0.amount == 1 && $0.instruction == "" })
        #expect(rates.allSatisfy { $0.origin == .computed && $0.year == 2025 })
        #expect(rates.allSatisfy { $0.sourceURL == nil && $0.confirmedAt == nil })
        #expect(computation.endedMonths == 12)
    }

    @Test func aMonthThatEndsOnAWeekendUsesTheRateDeclaredTheFridayBefore() {
        let computation = compute(table2025(), year: 2025, today: "2025-06-15")
        let may = computation.months[4]
        #expect(may.lastDay == civilDate("2025-05-31"))
        #expect(may.hasEnded)
        #expect(may.rates[.usd] == .declared(ExchangeRate(currency: .usd, amount: 1, rate: decimal("21.967")),
                                             declaredOn: civilDate("2025-05-30")))
    }

    @Test func aMonthThatEndsAfterAHolidayUsesTheLastBusinessDayBefore() {
        #expect(CzechCalendar.isPublicHoliday(civilDate("2024-03-29")))
        let table = RateTable(rows: rows("2024-03-28", usd: "23.200", eur: "25.100"))
        let computation = compute(table, year: 2024, today: "2024-04-02")
        let march = computation.months[2]
        #expect(march.lastDay == civilDate("2024-03-31"))
        #expect(march.rates[.usd] == .declared(ExchangeRate(currency: .usd, amount: 1, rate: decimal("23.200")),
                                               declaredOn: civilDate("2024-03-28")))
    }

    @Test func aMonthCountsFromTheDayAfterItsLastDay() {
        let table = table2025()
        #expect(compute(table, year: 2025, today: "2025-01-31").outcome == .none)
        let next = compute(table, year: 2025, today: "2025-02-01")
        #expect(next.endedMonths == 1)
        let rates = rates(next)
        #expect(rates.map(\.rate) == [decimal("24.21"), decimal("25.17")])
        #expect(rates.allSatisfy { $0.computedMonths == 1 })
    }

    @Test func aMissingMonthEndRateMakesTheComputationIncomplete() {
        let table = table2025(without: ["2025-04-30"])
        #expect(compute(table, year: 2025, today: "2026-01-08").outcome == .incomplete)
        #expect(compute(table, year: 2025, today: "2025-04-15").endedMonths == 3)
        #expect(compute(table, year: 2025, today: "2025-04-15").outcome != .incomplete)
    }

    @Test func aCurrencyTheCNBDoesNotQuoteThatDayGetsNoRate() {
        var all = Self.rates2025.filter { $0.day != "2025-03-31" }.flatMap { rows($0.day, usd: $0.usd, eur: $0.eur) }
        all += rows("2025-03-31", usd: "23.079", eur: nil)
        let computation = compute(RateTable(rows: all), year: 2025, today: "2026-01-08")
        #expect(rates(computation).map(\.currency) == [.usd])
    }

    @Test func theMeanIsRoundedHalfAwayFromZero() {
        let table = RateTable(
            rows: rows("2025-01-31", usd: "21.010", eur: "25.000") + rows("2025-02-28", usd: "21.000", eur: "25.000")
        )
        let rates = rates(compute(table, year: 2025, today: "2025-03-01"))
        #expect(rates.first?.rate == decimal("21.01"))
        #expect(rates.first?.computedMonths == 2)
    }

    @Test func everyMonthIsListedWithItsLastDay() {
        let computation = compute(table2025(), year: 2024, today: "2024-03-15")
        #expect(computation.months.count == 12)
        #expect(computation.months.map(\.month) == Array(1...12))
        #expect(computation.months[1].lastDay == civilDate("2024-02-29"))
        let ended = [Bool](repeating: true, count: 2) + [Bool](repeating: false, count: 10)
        #expect(computation.months.map(\.hasEnded) == ended)
        #expect(computation.months[2].rates.isEmpty)
        #expect(!computation.months[0].rates.isEmpty)
        #expect(computation.year == 2024)
    }
}
