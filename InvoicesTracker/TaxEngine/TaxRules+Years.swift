import Foundation

// The rules of the supported years, checked against the primary sources on 17 October 2026, and checked last on
// 20 October 2026, when the spouse credit, the child tax benefit and the minimum wage were added: the consolidated
// texts of the acts, the government decrees on the average wage and the minimum wage, the amending acts, the Finanční
// správa form instructions and the ČSSZ and VZP publications.
//
// Where the values come from. The provisions below apply in every year; what is specific to one year is noted at that
// year's rules.
//
// - Average wage: the government decree of the year, which sets ⌈VVZ × koeficient⌉ (§ 23b odst. 4 zákona
//   č. 589/1992 Sb.).
// - Start of the 23 % band (taxBandThreshold): § 16 zákona č. 586/1992 Sb. It starts above 48 times the average wage
//   in 2022 and 2023, and above 36 times from 2024.
// - Taxpayer credit: § 35ba odst. 1 písm. a) zákona č. 586/1992 Sb., 30 840 Kč in every year.
// - Retirement products (retirementLimit, hasDIPAndLongTermCare): § 15 zákona č. 586/1992 Sb.
// - Social insurance (assessment share, minimum bases, decisive amount, maximum base): zákon č. 589/1992 Sb., § 5b,
//   § 7, § 14 and § 15a. The maximum is 48 times the average wage and is not prorated. The decisive amounts are the
//   values of the official tables: they are ⌈2.4 × VVZ × koeficient⌉ of the unrounded product, so they are not 2.4
//   times the rounded average wage, which would be 1 Kč too high in 2023 to 2025.
// - Health insurance (healthMinimumMonthlyBase, childCareHealthExemption): zákon č. 592/1992 Sb., § 3a. The minimum
//   base is half of the average wage, and it does not apply to a month in which, for the whole month, the person was
//   in one of the situations that exempt it (§ 3a odst. 3 and 4).
// - Rates, flat-rate expense caps and gift limits are the same in every year, so they are constants of `TaxRules`
//   with their sources: § 16 odst. 1, § 7 odst. 7 and § 15 odst. 1 zákona č. 586/1992 Sb., § 7 zákona č. 589/1992
//   Sb., § 2 odst. 2 zákona č. 592/1992 Sb., and for the 30 % cap on gifts zákon č. 128/2022 Sb., § 1 odst. 1,
//   extended by zákon č. 349/2023 Sb., Čl. CVII, and zákon č. 24/2025 Sb., Čl. X.
// - Spouse credit and child tax benefit, checked on 20 October 2026: § 35ba odst. 1 písm. b) and odst. 3 and § 35c
//   zákona č. 586/1992 Sb. The amounts are the same in every year: the spouse credit is 24 840 Kč a year (2 070 Kč a
//   month), the child benefit 15 204, 22 320 and 27 840 Kč a year (1 267, 1 860 and 2 320 Kč a month) for the first,
//   the second and the third and every further child, each doubled with ZTP/P; the spouse's own income for the year
//   may be 68 000 Kč at most, and a tax bonus is paid from 100 Kč (§ 35c odst. 3). From 2024 the conditions of the
//   spouse credit are in § 35bb, which adds a child under three in the household (zákon č. 349/2023 Sb.).
// - Minimum wage: the regulation in force on 1 January of the year, noted at that year's rules. The tax bonus asks for
//   an income of six times the minimum wage (§ 35c odst. 4 zákona č. 586/1992 Sb.).

nonisolated extension TaxRules {
    /// The rules of every supported year, by year. Adding a year means adding its rules here and widening
    /// `supportedYears`.
    static let byYear: [Int: TaxRules] = Dictionary(
        uniqueKeysWithValues: [rules2022, rules2023, rules2024, rules2025, rules2026].map { ($0.year, $0) }
    )

    /// The day the rules were last checked: with the spouse credit, the child tax benefit and the minimum wage.
    private static let commonVerification = "ověřeno 20.\u{00A0}10.\u{00A0}2026"

    /// The sources every year shares, then the government decree that sets the average wage of the year and the
    /// regulation of the minimum wage of the year, then whatever only some years have.
    private static func legalSources(
        averageWageDecree decree: String, minimumWage: String, other: [String] = []
    ) -> [String] {
        [
            "zákon č. 586/1992 Sb. (daň z příjmů), § 7 odst. 7, § 15, § 16, § 35ba, § 35c",
            "zákon č. 589/1992 Sb. (sociální pojištění), § 5b, § 7, § 14, § 15a, § 23b",
            "zákon č. 592/1992 Sb. (zdravotní pojištění), § 2, § 3a",
            "nařízení vlády č. \(decree) Sb. (průměrná mzda)",
            "\(minimumWage) (minimální mzda)",
            "zákon č. 128/2022 Sb., § 1 odst. 1, prodloužený zákonem č. 349/2023 Sb., Čl. CVII, "
                + "a zákonem č. 24/2025 Sb., Čl. X (strop darů)",
        ] + other
    }

    /// From 2024 the conditions of the spouse credit are in a section of their own.
    private static let spouseCreditFrom2024 = "zákon č. 586/1992 Sb., § 35bb (sleva na manžela od roku 2024)"

    // MARK: 2022

    /// Average wage: nařízení vlády č. 356/2021 Sb.; minimum wage: nařízení vlády č. 405/2021 Sb. The 23 % band starts
    /// above 48 times the average wage, pension savings and life insurance have separate limits, DIP and long-term care
    /// insurance do not exist yet, and the spouse credit needs no child.
    private static let rules2022 = TaxRules(
        year: 2022,
        averageWage: 38_911,
        taxBandThreshold: 1_867_728,
        taxpayerCredit: 30_840,
        retirementLimit: .separate(pensionSavings: 24_000, lifeInsurance: 24_000),
        hasDIPAndLongTermCare: false,
        socialAssessmentPercent: DecimalMath.decimal("0.50")!,
        socialMinimumMonthlyMain: 9_728,
        socialMinimumMonthlySecondary: 3_892,
        socialDecisiveAmount: 93_387,
        socialMaximumAnnualBase: 1_867_728,
        healthMinimumMonthlyBase: DecimalMath.decimal("19455.50")!,
        childCareHealthExemption: true,
        spouseCreditMonthly: 2_070,
        childMonthly: [1_267, 1_860, 2_320],
        minimumWage: 16_200,
        spouseIncomeLimit: 68_000,
        spouseNeedsYoungChild: false,
        bonusMinimum: 100,
        verification: commonVerification,
        sources: legalSources(averageWageDecree: "356/2021", minimumWage: "nařízení vlády č. 405/2021 Sb.")
    )

    // MARK: 2023

    /// Average wage: nařízení vlády č. 290/2022 Sb.; minimum wage: nařízení vlády č. 465/2022 Sb. The rules are those
    /// of 2022 with the new amounts.
    private static let rules2023 = TaxRules(
        year: 2023,
        averageWage: 40_324,
        taxBandThreshold: 1_935_552,
        taxpayerCredit: 30_840,
        retirementLimit: .separate(pensionSavings: 24_000, lifeInsurance: 24_000),
        hasDIPAndLongTermCare: false,
        socialAssessmentPercent: DecimalMath.decimal("0.50")!,
        socialMinimumMonthlyMain: 10_081,
        socialMinimumMonthlySecondary: 4_033,
        socialDecisiveAmount: 96_777,
        socialMaximumAnnualBase: 1_935_552,
        healthMinimumMonthlyBase: DecimalMath.decimal("20162.00")!,
        childCareHealthExemption: true,
        spouseCreditMonthly: 2_070,
        childMonthly: [1_267, 1_860, 2_320],
        minimumWage: 17_300,
        spouseIncomeLimit: 68_000,
        spouseNeedsYoungChild: false,
        bonusMinimum: 100,
        verification: commonVerification,
        sources: legalSources(averageWageDecree: "290/2022", minimumWage: "nařízení vlády č. 465/2022 Sb.")
    )

    // MARK: 2024

    /// Average wage: nařízení vlády č. 286/2023 Sb.; minimum wage: nařízení vlády č. 396/2023 Sb. From 2024 the 23 %
    /// band starts above 36 times the average wage, the social assessment base is 55 % of the profit, one limit covers
    /// all retirement products, DIP and long-term care insurance exist, and the spouse credit counts only the months
    /// with a child under three in the household.
    private static let rules2024 = TaxRules(
        year: 2024,
        averageWage: 43_967,
        taxBandThreshold: 1_582_812,
        taxpayerCredit: 30_840,
        retirementLimit: .combined(48_000),
        hasDIPAndLongTermCare: true,
        socialAssessmentPercent: DecimalMath.decimal("0.55")!,
        socialMinimumMonthlyMain: 13_191,
        socialMinimumMonthlySecondary: 4_837,
        socialDecisiveAmount: 105_520,
        socialMaximumAnnualBase: 2_110_416,
        healthMinimumMonthlyBase: DecimalMath.decimal("21983.50")!,
        childCareHealthExemption: true,
        spouseCreditMonthly: 2_070,
        childMonthly: [1_267, 1_860, 2_320],
        minimumWage: 18_900,
        spouseIncomeLimit: 68_000,
        spouseNeedsYoungChild: true,
        bonusMinimum: 100,
        verification: commonVerification,
        sources: legalSources(
            averageWageDecree: "286/2023", minimumWage: "nařízení vlády č. 396/2023 Sb.",
            other: [spouseCreditFrom2024]
        )
    )

    // MARK: 2025

    /// Average wage: nařízení vlády č. 282/2024 Sb.; minimum wage: nařízení vlády č. 285/2024 Sb. with sdělení MPSV
    /// č. 286/2024 Sb. The rules are those of 2024 with the new amounts.
    private static let rules2025 = TaxRules(
        year: 2025,
        averageWage: 46_557,
        taxBandThreshold: 1_676_052,
        taxpayerCredit: 30_840,
        retirementLimit: .combined(48_000),
        hasDIPAndLongTermCare: true,
        socialAssessmentPercent: DecimalMath.decimal("0.55")!,
        socialMinimumMonthlyMain: 16_295,
        socialMinimumMonthlySecondary: 5_122,
        socialDecisiveAmount: 111_736,
        socialMaximumAnnualBase: 2_234_736,
        healthMinimumMonthlyBase: DecimalMath.decimal("23278.50")!,
        childCareHealthExemption: true,
        spouseCreditMonthly: 2_070,
        childMonthly: [1_267, 1_860, 2_320],
        minimumWage: 20_800,
        spouseIncomeLimit: 68_000,
        spouseNeedsYoungChild: true,
        bonusMinimum: 100,
        verification: commonVerification,
        sources: legalSources(
            averageWageDecree: "282/2024", minimumWage: "nařízení vlády č. 285/2024 Sb. a sdělení MPSV č. 286/2024 Sb.",
            other: [spouseCreditFrom2024]
        )
    )

    // MARK: 2026

    /// Average wage: nařízení vlády č. 365/2025 Sb.; minimum wage: nařízení vlády č. 285/2024 Sb., which sets its
    /// coefficient for 2026 too, with sdělení MPSV č. 356/2025 Sb., as for 2025. The main-activity social minimum of
    /// 17 139 Kč a month is the one of zákon č. 90/2026 Sb., Čl. II bod 5, which applies it to the whole 2026 annual
    /// overview. Caring full-day for a child under 7 is no longer a reason for a month without the health minimum
    /// (§ 3a odst. 3 and 4 zákona č. 592/1992 Sb.).
    private static let rules2026 = TaxRules(
        year: 2026,
        averageWage: 48_967,
        taxBandThreshold: 1_762_812,
        taxpayerCredit: 30_840,
        retirementLimit: .combined(48_000),
        hasDIPAndLongTermCare: true,
        socialAssessmentPercent: DecimalMath.decimal("0.55")!,
        socialMinimumMonthlyMain: 17_139,
        socialMinimumMonthlySecondary: 5_387,
        socialDecisiveAmount: 117_521,
        socialMaximumAnnualBase: 2_350_416,
        healthMinimumMonthlyBase: DecimalMath.decimal("24483.50")!,
        childCareHealthExemption: false,
        spouseCreditMonthly: 2_070,
        childMonthly: [1_267, 1_860, 2_320],
        minimumWage: 22_400,
        spouseIncomeLimit: 68_000,
        spouseNeedsYoungChild: true,
        bonusMinimum: 100,
        verification: commonVerification,
        sources: legalSources(
            averageWageDecree: "365/2025", minimumWage: "nařízení vlády č. 285/2024 Sb. a sdělení MPSV č. 356/2025 Sb.",
            other: [
                spouseCreditFrom2024, "zákon č. 90/2026 Sb., Čl. II bod 5 (minimální vyměřovací základ za rok 2026)",
            ]
        )
    )
}
