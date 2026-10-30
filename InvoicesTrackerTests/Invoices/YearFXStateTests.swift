import Foundation
import Testing
@testable import InvoicesTracker

/// How a year converts its income in other currencies, worked out from the method chosen for it, its uniform rates
/// and the currencies it was paid in: the uniform rate only when it is chosen and the year has it for every currency
/// it was paid in, otherwise the ČNB rates of the days, with the reason the uniform rate cannot be used. Today is
/// 17. 10. 2026 unless a test says otherwise.
struct YearFXStateTests {
    // MARK: Helpers

    private func rate(
        _ code: String, _ value: String, year: Int = 2025, instruction: String = "GFŘ-D-75",
        origin: UniformRateOrigin = .builtIn
    ) -> UniformRate {
        UniformRate(
            year: year, currency: CurrencyCode(code)!, amount: 1, rate: decimal(value), instruction: instruction,
            sourceURL: nil, confirmedAt: nil, origin: origin)
    }

    private var published2025: [UniformRate] {
        [rate("EUR", "24.66"), rate("GBP", "28.89"), rate("USD", "21.84")]
    }

    private func state(
        year: Int = 2025, chosen: IncomeFXMethod = .uniform, rates: [UniformRate], paid: [CurrencyCode]
    ) -> YearFXState {
        YearFXState(year: year, chosen: chosen, rates: rates, paidCurrencies: paid, today: civilDate("2026-10-17"))
    }

    // MARK: Ready

    @Test func aYearWithTheRateOfEveryCurrencyItWasPaidInUsesTheMethodChosen() {
        let uniform = state(rates: published2025, paid: [.eur, .usd])
        let daily = state(chosen: .cnbDaily, rates: published2025, paid: [.eur, .usd])

        let ready = UniformAvailability.ready(
            usd: decimal("21.84"), eur: decimal("24.66"), instruction: "GFŘ-D-75", origin: .builtIn)
        #expect(
            uniform
                == YearFXState(
                    year: 2025, chosen: .uniform, effective: .uniform, uniform: ready, hasForeignPayments: true))
        #expect(
            daily
                == YearFXState(
                    year: 2025, chosen: .cnbDaily, effective: .cnbDaily, uniform: ready, hasForeignPayments: true))
    }

    @Test func aYearWithoutForeignPaymentsCanTakeAnyRateItHasAndTheChoiceChangesNothing() {
        let typed = rate("USD", "21.9", year: 2026, instruction: "", origin: .manual)

        let withRate = state(year: 2026, rates: [typed], paid: [])
        let withoutRate = state(year: 2026, rates: [], paid: [])

        #expect(withRate.uniform == .ready(usd: decimal("21.9"), eur: nil, instruction: nil, origin: .manual))
        #expect(withRate.effective == .uniform)
        #expect(withRate.hasForeignPayments == false)
        #expect(withoutRate.uniform == .notPublishedYet(year: 2026))
        #expect(withoutRate.effective == .cnbDaily)
        #expect(withoutRate.hasForeignPayments == false)
    }

    @Test func theInstructionAndWhereTheRatesAreFromAreThoseOfTheRatesOfDollarsAndEuros() {
        // Dollars and euros entered by hand with an instruction of their own over the published table of the year.
        let rates = [
            rate("EUR", "24.7", instruction: "GFŘ-D-80", origin: .manual), rate("GBP", "28.89"),
            rate("USD", "21.9", instruction: "GFŘ-D-80", origin: .manual),
        ]

        #expect(
            state(rates: rates, paid: [.gbp]).uniform
                == .ready(usd: decimal("21.9"), eur: decimal("24.7"), instruction: "GFŘ-D-80", origin: .manual))
        // A year with neither takes the instruction of the rates it has.
        #expect(
            state(rates: [rate("GBP", "28.89")], paid: [.gbp]).uniform
                == .ready(usd: nil, eur: nil, instruction: "GFŘ-D-75", origin: .builtIn))
    }

    // MARK: Not ready

    @Test func aCurrencyWithoutItsRateKeepsTheYearOnDailyRatesAndIsNamed() {
        let typed = rate("USD", "21.9", year: 2026, instruction: "", origin: .manual)

        let fxState = state(year: 2026, rates: [typed], paid: [.eur, .gbp, .usd])

        // The first currency without a rate, by code.
        #expect(fxState.uniform == .missingCurrency(.eur))
        #expect(fxState.chosen == .uniform)
        #expect(fxState.effective == .cnbDaily)
        #expect(fxState.hasForeignPayments)
    }

    @Test func aYearWithoutAnyRateWaitsForItWhileItIsCurrentAndDoesNotHaveItOnceItIsOver() {
        let current = state(year: 2026, rates: [], paid: [.usd])
        let past = state(year: 2024, rates: [], paid: [.usd])
        let later = state(year: 2027, rates: [], paid: [.usd])

        #expect(current.uniform == .notPublishedYet(year: 2026))
        #expect(past.uniform == .notInApp(year: 2024))
        #expect(later.uniform == .notPublishedYet(year: 2027))
        for fxState in [current, past, later] {
            #expect(fxState.effective == .cnbDaily)
            #expect(fxState.chosen == .uniform)
        }
    }

    /// A year without its rate waits for the GFŘ until the app starts looking for the rate on 2 January of the next
    /// year, is looked for until 31 March, and from 1 April lacks a rate that has to be entered.
    @Test func aYearWithoutItsRateFollowsTheSearchOfTheAppForIt() {
        func availability(of year: Int, on day: String) -> UniformAvailability {
            YearFXState(year: year, chosen: .uniform, rates: [], paidCurrencies: [.usd], today: civilDate(day)).uniform
        }

        #expect(availability(of: 2025, on: "2025-12-31") == .notPublishedYet(year: 2025))
        #expect(availability(of: 2025, on: "2026-01-01") == .notPublishedYet(year: 2025))
        #expect(availability(of: 2025, on: "2026-01-02") == .searchedFor(year: 2025))
        #expect(availability(of: 2025, on: "2026-03-31") == .searchedFor(year: 2025))
        #expect(availability(of: 2025, on: "2026-04-01") == .notInApp(year: 2025))
        // The search for an earlier year ended a year before.
        #expect(availability(of: 2024, on: "2026-03-31") == .notInApp(year: 2024))
        #expect(availability(of: 2026, on: "2026-04-01") == .notPublishedYet(year: 2026))
    }

    /// The app looks for the uniform rate of a year from 2 January to 31 March of the next one, the GFŘ publishing it
    /// in January: before that it has not started, and from 1 April it is over, the day the year stops waiting for its
    /// rate.
    @Test func theAppLooksForTheRateOfAYearFrom2JanuaryTo31MarchOfTheNextOne() {
        let days = ["2026-10-17", "2026-12-31", "2027-01-01", "2027-01-02", "2027-03-31", "2027-04-01", "2028-01-02"]

        let stages = days.map { UniformRateSearch(year: 2026, today: civilDate($0)) }

        #expect(stages == [.notStarted, .notStarted, .notStarted, .looking, .looking, .over, .over])
        #expect(UniformRateSearch.firstDay(of: 2026) == civilDate("2027-01-02"))
        #expect(UniformRateSearch.lastDay(of: 2026) == civilDate("2027-03-31"))
        // A year without its rate waits for it until the search starts, is looked for while it runs, and lacks it once
        // the search is over.
        let availabilities = days.map { day in
            UniformAvailability(year: 2026, rates: [], paidCurrencies: [.usd], today: civilDate(day))
        }
        #expect(
            availabilities == [
                .notPublishedYet(year: 2026), .notPublishedYet(year: 2026), .notPublishedYet(year: 2026),
                .searchedFor(year: 2026), .searchedFor(year: 2026), .notInApp(year: 2026), .notInApp(year: 2026),
            ])
    }

    @Test func crownsAndRatesThatAreNoneOrOfAnotherYearDoNotCount() {
        let wrongYear = rate("USD", "21.84", year: 2024)
        let zero = rate("EUR", "0")

        // Crowns need no rate.
        #expect(state(rates: published2025, paid: [.czk, .usd]).uniform.isReady)
        #expect(state(rates: [rate("USD", "21.84")], paid: [.czk]).hasForeignPayments == false)
        // A rate of another year, or of nothing, is no rate of the year.
        #expect(state(rates: [wrongYear], paid: [.usd]).uniform == .notInApp(year: 2025))
        #expect(state(rates: [rate("USD", "21.84"), zero], paid: [.eur, .usd]).uniform == .missingCurrency(.eur))
    }
}

private extension CurrencyCode {
    static let gbp = CurrencyCode("GBP")!
}
