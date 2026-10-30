import Foundation
import Testing
@testable import InvoicesTracker

/// One scenario of the golden vectors: a year's input and every value the engine must produce for it. An independent
/// verifier computed the vectors with exact decimals, so they are the oracle for the engine.
///
/// Amounts are whole Kč unless the name says haléře. `months` has one character per month: `M` main activity, `S`
/// secondary activity, `-` no activity. The vectors assume the `S` months are exempt from the health minimum.
struct GoldenCase: Sendable {
    let year: Int
    let name: String
    let incomeHalere: Int64
    let expensePercent: Int
    let months: String
    let gifts: Int64
    let interestPaid: Int64
    let interestCap: Int64
    let interestMonths: Int
    let lifeInsurance: Int64
    let P: Int64
    let V: Int64
    let DZ: Int64
    let deductions: Int64
    let B: Int64
    let taxBefore: Int64
    let taxAfter: Int64
    let socialBase: Int64
    let socialInsurance: Int64
    let healthBaseHalere: Int64
    let healthInsurance: Int64
}

/// The social insurance of a year with both main and secondary months, worked out with the rows of the ČSSZ overview:
/// the profit and the months in, whether the secondary activity is insured, the assessment base and the insurance out.
struct MixedCase: Sendable {
    let year: Int
    let dz: Int64
    let mainMonths: Int
    let secondaryMonths: Int
    let secondaryInsured: Bool
    let socialBase: Int64
    let socialInsurance: Int64
}

extension GoldenCase: CustomTestStringConvertible {
    var testDescription: String {
        "\(year) \(name)"
    }
}

extension MixedCase: CustomTestStringConvertible {
    var testDescription: String {
        "\(year), profit \(dz), \(mainMonths) main and \(secondaryMonths) secondary months"
    }
}

/// The vectors, copied verbatim from the verifier's output.
enum GoldenCases {
    static let all: [GoldenCase] = [
        // year, scenario, incomeHalere, expensePercent, months, gifts, interestPaid, interestCapPerYear, interestMonths, lifeInsurance -> P, V, DZ, deductions, B, taxBefore, taxAfter, socBase, socIns, healthBaseHalere, healthIns
        GoldenCase(year: 2022, name: "S1", incomeHalere: 30000000, expensePercent: 60, months: "MMMMMMMMMMMM", gifts: 0, interestPaid: 0, interestCap: 0, interestMonths: 12, lifeInsurance: 0, P: 300000, V: 180000, DZ: 120000, deductions: 0, B: 120000, taxBefore: 18000, taxAfter: 0, socialBase: 116736, socialInsurance: 34087, healthBaseHalere: 23346600, healthInsurance: 31518),
        GoldenCase(year: 2022, name: "S2", incomeHalere: 219177100, expensePercent: 60, months: "MMMMMMMMMMMM", gifts: 0, interestPaid: 219000, interestCap: 150000, interestMonths: 12, lifeInsurance: 6480, P: 2191771, V: 1200000, DZ: 991771, deductions: 156480, B: 835200, taxBefore: 125280, taxAfter: 94440, socialBase: 495886, socialInsurance: 144799, healthBaseHalere: 49588550, healthInsurance: 66945),
        GoldenCase(year: 2022, name: "S3", incomeHalere: 600000000, expensePercent: 60, months: "MMMMMMMMMMMM", gifts: 0, interestPaid: 0, interestCap: 0, interestMonths: 12, lifeInsurance: 0, P: 6000000, V: 1200000, DZ: 4800000, deductions: 0, B: 4800000, taxBefore: 954582, taxAfter: 923742, socialBase: 1867728, socialInsurance: 545377, healthBaseHalere: 240000000, healthInsurance: 324000),
        GoldenCase(year: 2022, name: "S4", incomeHalere: 100000000, expensePercent: 40, months: "MMMMMMMMMMMM", gifts: 50000, interestPaid: 0, interestCap: 0, interestMonths: 12, lifeInsurance: 0, P: 1000000, V: 400000, DZ: 600000, deductions: 50000, B: 550000, taxBefore: 82500, taxAfter: 51660, socialBase: 300000, socialInsurance: 87600, healthBaseHalere: 30000000, healthInsurance: 40500),
        GoldenCase(year: 2022, name: "S5a", incomeHalere: 20000000, expensePercent: 60, months: "SSSSSSSSSSSS", gifts: 0, interestPaid: 0, interestCap: 0, interestMonths: 12, lifeInsurance: 0, P: 200000, V: 120000, DZ: 80000, deductions: 0, B: 80000, taxBefore: 12000, taxAfter: 0, socialBase: 0, socialInsurance: 0, healthBaseHalere: 4000000, healthInsurance: 5400),
        GoldenCase(year: 2022, name: "S5b", incomeHalere: 30000000, expensePercent: 60, months: "SSSSSSSSSSSS", gifts: 0, interestPaid: 0, interestCap: 0, interestMonths: 12, lifeInsurance: 0, P: 300000, V: 180000, DZ: 120000, deductions: 0, B: 120000, taxBefore: 18000, taxAfter: 0, socialBase: 60000, socialInsurance: 17520, healthBaseHalere: 6000000, healthInsurance: 8100),
        GoldenCase(year: 2022, name: "S6", incomeHalere: 60000000, expensePercent: 60, months: "MMMMMMSSSSSS", gifts: 0, interestPaid: 0, interestCap: 0, interestMonths: 12, lifeInsurance: 0, P: 600000, V: 360000, DZ: 240000, deductions: 0, B: 240000, taxBefore: 36000, taxAfter: 5160, socialBase: 120000, socialInsurance: 35040, healthBaseHalere: 12000000, healthInsurance: 16200),
        GoldenCase(year: 2022, name: "S7", incomeHalere: 50000000, expensePercent: 60, months: "------MMMMMM", gifts: 0, interestPaid: 0, interestCap: 0, interestMonths: 12, lifeInsurance: 0, P: 500000, V: 300000, DZ: 200000, deductions: 0, B: 200000, taxBefore: 30000, taxAfter: 0, socialBase: 100000, socialInsurance: 29200, healthBaseHalere: 11673300, healthInsurance: 15759),
        GoldenCase(year: 2022, name: "S8", incomeHalere: 123456789, expensePercent: 60, months: "MMMMMMMMMMMM", gifts: 999, interestPaid: 0, interestCap: 0, interestMonths: 12, lifeInsurance: 0, P: 1234568, V: 740740, DZ: 493828, deductions: 0, B: 493800, taxBefore: 74070, taxAfter: 43230, socialBase: 246914, socialInsurance: 72099, healthBaseHalere: 24691400, healthInsurance: 33334),
        GoldenCase(year: 2022, name: "S8g", incomeHalere: 123456789, expensePercent: 60, months: "MMMMMMMMMMMM", gifts: 200000, interestPaid: 0, interestCap: 0, interestMonths: 12, lifeInsurance: 0, P: 1234568, V: 740740, DZ: 493828, deductions: 148148, B: 345600, taxBefore: 51840, taxAfter: 21000, socialBase: 246914, socialInsurance: 72099, healthBaseHalere: 24691400, healthInsurance: 33334),
        GoldenCase(year: 2023, name: "S1", incomeHalere: 30000000, expensePercent: 60, months: "MMMMMMMMMMMM", gifts: 0, interestPaid: 0, interestCap: 0, interestMonths: 12, lifeInsurance: 0, P: 300000, V: 180000, DZ: 120000, deductions: 0, B: 120000, taxBefore: 18000, taxAfter: 0, socialBase: 120972, socialInsurance: 35324, healthBaseHalere: 24194400, healthInsurance: 32663),
        GoldenCase(year: 2023, name: "S2", incomeHalere: 219177100, expensePercent: 60, months: "MMMMMMMMMMMM", gifts: 0, interestPaid: 219000, interestCap: 150000, interestMonths: 12, lifeInsurance: 6480, P: 2191771, V: 1200000, DZ: 991771, deductions: 156480, B: 835200, taxBefore: 125280, taxAfter: 94440, socialBase: 495886, socialInsurance: 144799, healthBaseHalere: 49588550, healthInsurance: 66945),
        GoldenCase(year: 2023, name: "S3", incomeHalere: 600000000, expensePercent: 60, months: "MMMMMMMMMMMM", gifts: 0, interestPaid: 0, interestCap: 0, interestMonths: 12, lifeInsurance: 0, P: 6000000, V: 1200000, DZ: 4800000, deductions: 0, B: 4800000, taxBefore: 949156, taxAfter: 918316, socialBase: 1935552, socialInsurance: 565182, healthBaseHalere: 240000000, healthInsurance: 324000),
        GoldenCase(year: 2023, name: "S4", incomeHalere: 100000000, expensePercent: 40, months: "MMMMMMMMMMMM", gifts: 50000, interestPaid: 0, interestCap: 0, interestMonths: 12, lifeInsurance: 0, P: 1000000, V: 400000, DZ: 600000, deductions: 50000, B: 550000, taxBefore: 82500, taxAfter: 51660, socialBase: 300000, socialInsurance: 87600, healthBaseHalere: 30000000, healthInsurance: 40500),
        GoldenCase(year: 2023, name: "S5a", incomeHalere: 20000000, expensePercent: 60, months: "SSSSSSSSSSSS", gifts: 0, interestPaid: 0, interestCap: 0, interestMonths: 12, lifeInsurance: 0, P: 200000, V: 120000, DZ: 80000, deductions: 0, B: 80000, taxBefore: 12000, taxAfter: 0, socialBase: 0, socialInsurance: 0, healthBaseHalere: 4000000, healthInsurance: 5400),
        GoldenCase(year: 2023, name: "S5b", incomeHalere: 30000000, expensePercent: 60, months: "SSSSSSSSSSSS", gifts: 0, interestPaid: 0, interestCap: 0, interestMonths: 12, lifeInsurance: 0, P: 300000, V: 180000, DZ: 120000, deductions: 0, B: 120000, taxBefore: 18000, taxAfter: 0, socialBase: 60000, socialInsurance: 17520, healthBaseHalere: 6000000, healthInsurance: 8100),
        GoldenCase(year: 2023, name: "S6", incomeHalere: 60000000, expensePercent: 60, months: "MMMMMMSSSSSS", gifts: 0, interestPaid: 0, interestCap: 0, interestMonths: 12, lifeInsurance: 0, P: 600000, V: 360000, DZ: 240000, deductions: 0, B: 240000, taxBefore: 36000, taxAfter: 5160, socialBase: 120486, socialInsurance: 35182, healthBaseHalere: 12097200, healthInsurance: 16332),
        GoldenCase(year: 2023, name: "S7", incomeHalere: 50000000, expensePercent: 60, months: "------MMMMMM", gifts: 0, interestPaid: 0, interestCap: 0, interestMonths: 12, lifeInsurance: 0, P: 500000, V: 300000, DZ: 200000, deductions: 0, B: 200000, taxBefore: 30000, taxAfter: 0, socialBase: 100000, socialInsurance: 29200, healthBaseHalere: 12097200, healthInsurance: 16332),
        GoldenCase(year: 2023, name: "S8", incomeHalere: 123456789, expensePercent: 60, months: "MMMMMMMMMMMM", gifts: 999, interestPaid: 0, interestCap: 0, interestMonths: 12, lifeInsurance: 0, P: 1234568, V: 740740, DZ: 493828, deductions: 0, B: 493800, taxBefore: 74070, taxAfter: 43230, socialBase: 246914, socialInsurance: 72099, healthBaseHalere: 24691400, healthInsurance: 33334),
        GoldenCase(year: 2023, name: "S8g", incomeHalere: 123456789, expensePercent: 60, months: "MMMMMMMMMMMM", gifts: 200000, interestPaid: 0, interestCap: 0, interestMonths: 12, lifeInsurance: 0, P: 1234568, V: 740740, DZ: 493828, deductions: 148148, B: 345600, taxBefore: 51840, taxAfter: 21000, socialBase: 246914, socialInsurance: 72099, healthBaseHalere: 24691400, healthInsurance: 33334),
        GoldenCase(year: 2024, name: "S1", incomeHalere: 30000000, expensePercent: 60, months: "MMMMMMMMMMMM", gifts: 0, interestPaid: 0, interestCap: 0, interestMonths: 12, lifeInsurance: 0, P: 300000, V: 180000, DZ: 120000, deductions: 0, B: 120000, taxBefore: 18000, taxAfter: 0, socialBase: 158292, socialInsurance: 46222, healthBaseHalere: 26380200, healthInsurance: 35614),
        GoldenCase(year: 2024, name: "S2", incomeHalere: 219177100, expensePercent: 60, months: "MMMMMMMMMMMM", gifts: 0, interestPaid: 219000, interestCap: 150000, interestMonths: 12, lifeInsurance: 6480, P: 2191771, V: 1200000, DZ: 991771, deductions: 156480, B: 835200, taxBefore: 125280, taxAfter: 94440, socialBase: 545475, socialInsurance: 159279, healthBaseHalere: 49588550, healthInsurance: 66945),
        GoldenCase(year: 2024, name: "S3", incomeHalere: 600000000, expensePercent: 60, months: "MMMMMMMMMMMM", gifts: 0, interestPaid: 0, interestCap: 0, interestMonths: 12, lifeInsurance: 0, P: 6000000, V: 1200000, DZ: 4800000, deductions: 0, B: 4800000, taxBefore: 977376, taxAfter: 946536, socialBase: 2110416, socialInsurance: 616242, healthBaseHalere: 240000000, healthInsurance: 324000),
        GoldenCase(year: 2024, name: "S4", incomeHalere: 100000000, expensePercent: 40, months: "MMMMMMMMMMMM", gifts: 50000, interestPaid: 0, interestCap: 0, interestMonths: 12, lifeInsurance: 0, P: 1000000, V: 400000, DZ: 600000, deductions: 50000, B: 550000, taxBefore: 82500, taxAfter: 51660, socialBase: 330000, socialInsurance: 96360, healthBaseHalere: 30000000, healthInsurance: 40500),
        GoldenCase(year: 2024, name: "S5a", incomeHalere: 20000000, expensePercent: 60, months: "SSSSSSSSSSSS", gifts: 0, interestPaid: 0, interestCap: 0, interestMonths: 12, lifeInsurance: 0, P: 200000, V: 120000, DZ: 80000, deductions: 0, B: 80000, taxBefore: 12000, taxAfter: 0, socialBase: 0, socialInsurance: 0, healthBaseHalere: 4000000, healthInsurance: 5400),
        GoldenCase(year: 2024, name: "S5b", incomeHalere: 30000000, expensePercent: 60, months: "SSSSSSSSSSSS", gifts: 0, interestPaid: 0, interestCap: 0, interestMonths: 12, lifeInsurance: 0, P: 300000, V: 180000, DZ: 120000, deductions: 0, B: 120000, taxBefore: 18000, taxAfter: 0, socialBase: 66000, socialInsurance: 19272, healthBaseHalere: 6000000, healthInsurance: 8100),
        GoldenCase(year: 2024, name: "S6", incomeHalere: 60000000, expensePercent: 60, months: "MMMMMMSSSSSS", gifts: 0, interestPaid: 0, interestCap: 0, interestMonths: 12, lifeInsurance: 0, P: 600000, V: 360000, DZ: 240000, deductions: 0, B: 240000, taxBefore: 36000, taxAfter: 5160, socialBase: 145146, socialInsurance: 42383, healthBaseHalere: 13190100, healthInsurance: 17807),
        GoldenCase(year: 2024, name: "S7", incomeHalere: 50000000, expensePercent: 60, months: "------MMMMMM", gifts: 0, interestPaid: 0, interestCap: 0, interestMonths: 12, lifeInsurance: 0, P: 500000, V: 300000, DZ: 200000, deductions: 0, B: 200000, taxBefore: 30000, taxAfter: 0, socialBase: 110000, socialInsurance: 32120, healthBaseHalere: 13190100, healthInsurance: 17807),
        GoldenCase(year: 2024, name: "S8", incomeHalere: 123456789, expensePercent: 60, months: "MMMMMMMMMMMM", gifts: 999, interestPaid: 0, interestCap: 0, interestMonths: 12, lifeInsurance: 0, P: 1234568, V: 740740, DZ: 493828, deductions: 0, B: 493800, taxBefore: 74070, taxAfter: 43230, socialBase: 271606, socialInsurance: 79309, healthBaseHalere: 26380200, healthInsurance: 35614),
        GoldenCase(year: 2024, name: "S8g", incomeHalere: 123456789, expensePercent: 60, months: "MMMMMMMMMMMM", gifts: 200000, interestPaid: 0, interestCap: 0, interestMonths: 12, lifeInsurance: 0, P: 1234568, V: 740740, DZ: 493828, deductions: 148148, B: 345600, taxBefore: 51840, taxAfter: 21000, socialBase: 271606, socialInsurance: 79309, healthBaseHalere: 26380200, healthInsurance: 35614),
        GoldenCase(year: 2025, name: "S1", incomeHalere: 30000000, expensePercent: 60, months: "MMMMMMMMMMMM", gifts: 0, interestPaid: 0, interestCap: 0, interestMonths: 12, lifeInsurance: 0, P: 300000, V: 180000, DZ: 120000, deductions: 0, B: 120000, taxBefore: 18000, taxAfter: 0, socialBase: 195540, socialInsurance: 57098, healthBaseHalere: 27934200, healthInsurance: 37712),
        GoldenCase(year: 2025, name: "S2", incomeHalere: 219177100, expensePercent: 60, months: "MMMMMMMMMMMM", gifts: 0, interestPaid: 219000, interestCap: 150000, interestMonths: 12, lifeInsurance: 6480, P: 2191771, V: 1200000, DZ: 991771, deductions: 156480, B: 835200, taxBefore: 125280, taxAfter: 94440, socialBase: 545475, socialInsurance: 159279, healthBaseHalere: 49588550, healthInsurance: 66945),
        GoldenCase(year: 2025, name: "S3", incomeHalere: 600000000, expensePercent: 60, months: "MMMMMMMMMMMM", gifts: 0, interestPaid: 0, interestCap: 0, interestMonths: 12, lifeInsurance: 0, P: 6000000, V: 1200000, DZ: 4800000, deductions: 0, B: 4800000, taxBefore: 969916, taxAfter: 939076, socialBase: 2234736, socialInsurance: 652543, healthBaseHalere: 240000000, healthInsurance: 324000),
        GoldenCase(year: 2025, name: "S4", incomeHalere: 100000000, expensePercent: 40, months: "MMMMMMMMMMMM", gifts: 50000, interestPaid: 0, interestCap: 0, interestMonths: 12, lifeInsurance: 0, P: 1000000, V: 400000, DZ: 600000, deductions: 50000, B: 550000, taxBefore: 82500, taxAfter: 51660, socialBase: 330000, socialInsurance: 96360, healthBaseHalere: 30000000, healthInsurance: 40500),
        GoldenCase(year: 2025, name: "S5a", incomeHalere: 20000000, expensePercent: 60, months: "SSSSSSSSSSSS", gifts: 0, interestPaid: 0, interestCap: 0, interestMonths: 12, lifeInsurance: 0, P: 200000, V: 120000, DZ: 80000, deductions: 0, B: 80000, taxBefore: 12000, taxAfter: 0, socialBase: 0, socialInsurance: 0, healthBaseHalere: 4000000, healthInsurance: 5400),
        GoldenCase(year: 2025, name: "S5b", incomeHalere: 30000000, expensePercent: 60, months: "SSSSSSSSSSSS", gifts: 0, interestPaid: 0, interestCap: 0, interestMonths: 12, lifeInsurance: 0, P: 300000, V: 180000, DZ: 120000, deductions: 0, B: 120000, taxBefore: 18000, taxAfter: 0, socialBase: 66000, socialInsurance: 19272, healthBaseHalere: 6000000, healthInsurance: 8100),
        GoldenCase(year: 2025, name: "S6", incomeHalere: 60000000, expensePercent: 60, months: "MMMMMMSSSSSS", gifts: 0, interestPaid: 0, interestCap: 0, interestMonths: 12, lifeInsurance: 0, P: 600000, V: 360000, DZ: 240000, deductions: 0, B: 240000, taxBefore: 36000, taxAfter: 5160, socialBase: 163770, socialInsurance: 47821, healthBaseHalere: 13967100, healthInsurance: 18856),
        GoldenCase(year: 2025, name: "S7", incomeHalere: 50000000, expensePercent: 60, months: "------MMMMMM", gifts: 0, interestPaid: 0, interestCap: 0, interestMonths: 12, lifeInsurance: 0, P: 500000, V: 300000, DZ: 200000, deductions: 0, B: 200000, taxBefore: 30000, taxAfter: 0, socialBase: 110000, socialInsurance: 32120, healthBaseHalere: 13967100, healthInsurance: 18856),
        GoldenCase(year: 2025, name: "S8", incomeHalere: 123456789, expensePercent: 60, months: "MMMMMMMMMMMM", gifts: 999, interestPaid: 0, interestCap: 0, interestMonths: 12, lifeInsurance: 0, P: 1234568, V: 740740, DZ: 493828, deductions: 0, B: 493800, taxBefore: 74070, taxAfter: 43230, socialBase: 271606, socialInsurance: 79309, healthBaseHalere: 27934200, healthInsurance: 37712),
        GoldenCase(year: 2025, name: "S8g", incomeHalere: 123456789, expensePercent: 60, months: "MMMMMMMMMMMM", gifts: 200000, interestPaid: 0, interestCap: 0, interestMonths: 12, lifeInsurance: 0, P: 1234568, V: 740740, DZ: 493828, deductions: 148148, B: 345600, taxBefore: 51840, taxAfter: 21000, socialBase: 271606, socialInsurance: 79309, healthBaseHalere: 27934200, healthInsurance: 37712),
        GoldenCase(year: 2026, name: "S1", incomeHalere: 30000000, expensePercent: 60, months: "MMMMMMMMMMMM", gifts: 0, interestPaid: 0, interestCap: 0, interestMonths: 12, lifeInsurance: 0, P: 300000, V: 180000, DZ: 120000, deductions: 0, B: 120000, taxBefore: 18000, taxAfter: 0, socialBase: 205668, socialInsurance: 60056, healthBaseHalere: 29380200, healthInsurance: 39664),
        GoldenCase(year: 2026, name: "S2", incomeHalere: 219177100, expensePercent: 60, months: "MMMMMMMMMMMM", gifts: 0, interestPaid: 219000, interestCap: 150000, interestMonths: 12, lifeInsurance: 6480, P: 2191771, V: 1200000, DZ: 991771, deductions: 156480, B: 835200, taxBefore: 125280, taxAfter: 94440, socialBase: 545475, socialInsurance: 159279, healthBaseHalere: 49588550, healthInsurance: 66945),
        GoldenCase(year: 2026, name: "S3", incomeHalere: 600000000, expensePercent: 60, months: "MMMMMMMMMMMM", gifts: 0, interestPaid: 0, interestCap: 0, interestMonths: 12, lifeInsurance: 0, P: 6000000, V: 1200000, DZ: 4800000, deductions: 0, B: 4800000, taxBefore: 962976, taxAfter: 932136, socialBase: 2350416, socialInsurance: 686322, healthBaseHalere: 240000000, healthInsurance: 324000),
        GoldenCase(year: 2026, name: "S4", incomeHalere: 100000000, expensePercent: 40, months: "MMMMMMMMMMMM", gifts: 50000, interestPaid: 0, interestCap: 0, interestMonths: 12, lifeInsurance: 0, P: 1000000, V: 400000, DZ: 600000, deductions: 50000, B: 550000, taxBefore: 82500, taxAfter: 51660, socialBase: 330000, socialInsurance: 96360, healthBaseHalere: 30000000, healthInsurance: 40500),
        GoldenCase(year: 2026, name: "S5a", incomeHalere: 20000000, expensePercent: 60, months: "SSSSSSSSSSSS", gifts: 0, interestPaid: 0, interestCap: 0, interestMonths: 12, lifeInsurance: 0, P: 200000, V: 120000, DZ: 80000, deductions: 0, B: 80000, taxBefore: 12000, taxAfter: 0, socialBase: 0, socialInsurance: 0, healthBaseHalere: 4000000, healthInsurance: 5400),
        GoldenCase(year: 2026, name: "S5b", incomeHalere: 30000000, expensePercent: 60, months: "SSSSSSSSSSSS", gifts: 0, interestPaid: 0, interestCap: 0, interestMonths: 12, lifeInsurance: 0, P: 300000, V: 180000, DZ: 120000, deductions: 0, B: 120000, taxBefore: 18000, taxAfter: 0, socialBase: 66000, socialInsurance: 19272, healthBaseHalere: 6000000, healthInsurance: 8100),
        GoldenCase(year: 2026, name: "S6", incomeHalere: 60000000, expensePercent: 60, months: "MMMMMMSSSSSS", gifts: 0, interestPaid: 0, interestCap: 0, interestMonths: 12, lifeInsurance: 0, P: 600000, V: 360000, DZ: 240000, deductions: 0, B: 240000, taxBefore: 36000, taxAfter: 5160, socialBase: 168834, socialInsurance: 49300, healthBaseHalere: 14690100, healthInsurance: 19832),
        GoldenCase(year: 2026, name: "S7", incomeHalere: 50000000, expensePercent: 60, months: "------MMMMMM", gifts: 0, interestPaid: 0, interestCap: 0, interestMonths: 12, lifeInsurance: 0, P: 500000, V: 300000, DZ: 200000, deductions: 0, B: 200000, taxBefore: 30000, taxAfter: 0, socialBase: 110000, socialInsurance: 32120, healthBaseHalere: 14690100, healthInsurance: 19832),
        GoldenCase(year: 2026, name: "S8", incomeHalere: 123456789, expensePercent: 60, months: "MMMMMMMMMMMM", gifts: 999, interestPaid: 0, interestCap: 0, interestMonths: 12, lifeInsurance: 0, P: 1234568, V: 740740, DZ: 493828, deductions: 0, B: 493800, taxBefore: 74070, taxAfter: 43230, socialBase: 271606, socialInsurance: 79309, healthBaseHalere: 29380200, healthInsurance: 39664),
        GoldenCase(year: 2026, name: "S8g", incomeHalere: 123456789, expensePercent: 60, months: "MMMMMMMMMMMM", gifts: 200000, interestPaid: 0, interestCap: 0, interestMonths: 12, lifeInsurance: 0, P: 1234568, V: 740740, DZ: 493828, deductions: 148148, B: 345600, taxBefore: 51840, taxAfter: 21000, socialBase: 271606, socialInsurance: 79309, healthBaseHalere: 29380200, healthInsurance: 39664),
    ]

    static let mixed: [MixedCase] = [
        // extra mixed-year vectors (ČSSZ rows): year, DZ, main months, secondary months -> insured, base, insurance
        MixedCase(year: 2022, dz: 240000, mainMonths: 6, secondaryMonths: 6, secondaryInsured: true, socialBase: 120000, socialInsurance: 35040),
        MixedCase(year: 2024, dz: 240000, mainMonths: 6, secondaryMonths: 6, secondaryInsured: true, socialBase: 145146, socialInsurance: 42383),
        MixedCase(year: 2024, dz: 123457, mainMonths: 7, secondaryMonths: 5, secondaryInsured: true, socialBase: 120630, socialInsurance: 35224),
        MixedCase(year: 2024, dz: 1000003, mainMonths: 7, secondaryMonths: 5, secondaryInsured: true, socialBase: 550003, socialInsurance: 160601),
        MixedCase(year: 2025, dz: 90000, mainMonths: 6, secondaryMonths: 6, secondaryInsured: false, socialBase: 97770, socialInsurance: 28549),
    ]
}

/// The activity of each month from a pattern of twelve characters: `M` main, `S` secondary, `-` no activity. Traps on
/// anything else, because a bad literal in a test is a bug in the test.
func monthActivities(_ pattern: String) -> [MonthActivity] {
    let months = pattern.map { character -> MonthActivity in
        switch character {
        case "M": .main
        case "S": .secondary
        case "-": .inactive
        default: preconditionFailure("Not a month pattern: \(pattern)")
        }
    }
    precondition(months.count == 12, "A month pattern has twelve characters: \(pattern)")
    return months
}

/// The year input of a golden case: one receipt of the whole income on 15 June, the months of the pattern with the
/// secondary months exempt from the health minimum, the deductions of the case, the taxpayer credit and no advances.
func input(for c: GoldenCase) -> YearInput {
    let months = monthActivities(c.months)
    return YearInput(
        year: c.year,
        receipts: [
            Receipt(
                day: civilDate("\(c.year)-06-15"),
                czkNetHalere: c.incomeHalere,
                czkVatHalere: 0,
                source: .synthetic
            )
        ],
        expensePercent: c.expensePercent,
        months: months,
        healthExemptMonths: Set((1...12).filter { months[$0 - 1] == .secondary }),
        deductions: Deductions(
            mortgageInterestPaid: c.interestPaid,
            mortgageMonths: c.interestMonths,
            mortgageCap: c.interestCap == 300_000 ? .before2021 : .after2021,
            lifeInsurance: c.lifeInsurance,
            gifts: c.gifts
        ),
        taxpayerCredit: true,
        advances: .empty
    )
}

/// A year input with 60 % flat-rate expenses, the taxpayer credit and no advances. By default every month is main
/// activity, no month is exempt from the health minimum and nothing is deducted.
func yearInput(
    _ year: Int,
    receipts: [Receipt],
    months: String = "MMMMMMMMMMMM",
    deductions: Deductions = Deductions()
) -> YearInput {
    YearInput(
        year: year,
        receipts: receipts,
        expensePercent: 60,
        months: monthActivities(months),
        healthExemptMonths: [],
        deductions: deductions,
        taxpayerCredit: true,
        advances: .empty
    )
}

/// A payment of whole crowns without VAT, made up for a test.
func payment(_ iso: String, kc: Int64) -> Receipt {
    Receipt(day: civilDate(iso), czkNetHalere: kc * 100, czkVatHalere: 0, source: .synthetic)
}

/// Checks every value a golden case pins down.
func expectResult(_ result: TaxResult, matches c: GoldenCase, sourceLocation: SourceLocation = #_sourceLocation) {
    #expect(result.P == c.P, "P", sourceLocation: sourceLocation)
    #expect(result.V == c.V, "V", sourceLocation: sourceLocation)
    #expect(result.DZ == c.DZ, "DZ", sourceLocation: sourceLocation)
    #expect(result.deductionsTotal == c.deductions, "deductions", sourceLocation: sourceLocation)
    #expect(result.B == c.B, "B", sourceLocation: sourceLocation)
    #expect(result.taxBeforeCredit == c.taxBefore, "tax before the credit", sourceLocation: sourceLocation)
    #expect(result.tax == c.taxAfter, "tax after the credit", sourceLocation: sourceLocation)
    #expect(result.social.base == c.socialBase, "social base", sourceLocation: sourceLocation)
    #expect(result.social.insurance == c.socialInsurance, "social insurance", sourceLocation: sourceLocation)
    #expect(result.health.baseHalere == c.healthBaseHalere, "health base", sourceLocation: sourceLocation)
    #expect(result.health.insurance == c.healthInsurance, "health insurance", sourceLocation: sourceLocation)
}
