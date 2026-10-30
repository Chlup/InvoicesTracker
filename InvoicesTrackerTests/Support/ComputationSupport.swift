import Foundation
import Testing
@testable import InvoicesTracker

/// The year of the tests of Výpočet: one payment of `netHalere` (and `vatHalere` of VAT) on 2. 3. and, when there is
/// one, an income adjustment on 3. 3., at 60 % flat-rate expenses with the main activity all year, the taxpayer credit
/// and no advances unless given.
func computationYearInput(
    year: Int = 2026, netHalere: Int64 = 0, vatHalere: Int64 = 0, adjustmentHalere: Int64 = 0,
    months: [MonthActivity] = [MonthActivity](repeating: .main, count: 12), percent: Int = 60,
    deductions: Deductions = Deductions(), credit: Bool = true, advances: AdvancePlan = .empty
) -> YearInput {
    var receipts: [Receipt] = []
    if netHalere != 0 || vatHalere != 0 {
        receipts.append(
            Receipt(
                day: civilDate("\(year)-03-02"), czkNetHalere: netHalere, czkVatHalere: vatHalere,
                source: .invoice(1)))
    }
    if adjustmentHalere != 0 {
        receipts.append(
            Receipt(
                day: civilDate("\(year)-03-03"), czkNetHalere: adjustmentHalere, czkVatHalere: 0,
                source: .adjustment(1)))
    }
    return YearInput(
        year: year, receipts: receipts, expensePercent: percent, months: months, healthExemptMonths: [],
        deductions: deductions, taxpayerCredit: credit, advances: advances)
}

/// Twelve months of secondary activity, and eight of main followed by four of secondary.
let computationSecondaryYear = [MonthActivity](repeating: .secondary, count: 12)
let computationMixedYear =
    [MonthActivity](repeating: .main, count: 8) + [MonthActivity](repeating: .secondary, count: 4)

/// The whole page of Výpočet for `input` as of `asOf`, built from what the engine works out for it, for a year that
/// converts its income in other currencies by `conversion`, with its uniform rate from `uniformSource`.
func computationPage(
    _ input: YearInput, asOf: String = "2026-10-17", today: String = "2026-10-17",
    conversion: IncomeFXMethod = .cnbDaily, uniformSource: String? = nil
) -> ComputationPage {
    let result = TaxEngine.compute(input, asOf: civilDate(asOf))
    return ComputationBuilder.buildPage(
        result, input: input, today: civilDate(today), incomeFXMethod: conversion, uniformSource: uniformSource)
}

/// A year to build the page for: the input and the day shown.
struct ComputationScenario {
    var input: YearInput
    var asOf: String

    /// Whether the page shows a year that is over, as of 17. 10. 2026: a year before 2026 shown as of its last day. Any
    /// other day of such a year is the year as it was that day.
    var isOver: Bool {
        input.year < 2026 && asOf.hasSuffix("-12-31")
    }
}

/// A grid of years: every year with rules and the one after them (an estimate), what was received, the activity of the
/// months, three days of the year, three rates of the expenses and two sets of deductions. The year of the tests is
/// 2026, so the years before it are over when they are shown as of their last day.
func computationGrid() -> [ComputationScenario] {
    let incomes: [Int64] = [0, 1, 99_950, 10_000_150, 123_456_789, 570_000_000, 5_000_000_000]
    let activities: [[MonthActivity]] = [
        [MonthActivity](repeating: .main, count: 12), computationMixedYear, computationSecondaryYear,
        [MonthActivity](repeating: .inactive, count: 3) + [MonthActivity](repeating: .main, count: 9),
        [MonthActivity](repeating: .inactive, count: 12),
    ]
    let claims = [Deductions(), Deductions(mortgageInterestPaid: 90_000, lifeInsurance: 5_000, gifts: 3_000)]
    var scenarios: [ComputationScenario] = []
    for year in 2022...2027 {
        for income in incomes {
            for months in activities {
                for day in ["\(year)-01-31", "\(year)-06-30", "\(year)-12-31"] {
                    for percent in [30, 60, 80] {
                        for claim in claims {
                            let input = computationYearInput(
                                year: year, netHalere: income, vatHalere: income / 5,
                                adjustmentHalere: income > 99_950 ? -12_345 : 0, months: months, percent: percent,
                                deductions: claim)
                            scenarios.append(ComputationScenario(input: input, asOf: day))
                        }
                    }
                }
            }
        }
    }
    return scenarios
}
