import Foundation
import Testing
@testable import InvoicesTracker

/// The changes the screen of advances and deductions makes to the settings of a year, one field each: what each sets,
/// that it touches nothing else, and which of them replace one another while they wait to be saved.
struct YearSettingsEditTests {
    /// Settings in which every value differs from what the edits below set, so that a change shows.
    private static func settings() -> YearSettings {
        var settings = YearSettings(year: 2026)
        settings.expensePercent = 60
        settings.activityFrom = 2
        settings.activityTo = 11
        settings.healthExemptMonths = [3]
        settings.advances = AdvancePlan(
            social: (1...12).map { 1_000 + Int64($0) },
            health: (1...12).map { 2_000 + Int64($0) },
            tax: (1...12).map { 3_000 + Int64($0) })
        settings.deductions = Deductions(
            mortgageInterestPaid: 1, mortgageMonths: 2, mortgageCap: .after2021, lifeInsurance: 3, pensionSavings: 4,
            dip: 5, longTermCare: 6, gifts: 7)
        return settings
    }

    private static func applying(_ edit: YearSettingsEdit) -> YearSettings {
        var settings = Self.settings()
        edit.apply(to: &settings)
        return settings
    }

    @Test(arguments: AdvanceColumn.allCases, [1, 7, 12])
    func anAdvanceIsSetInItsOwnMonthAndColumnOnly(column: AdvanceColumn, month: Int) {
        let changed = Self.applying(.advance(column, month: month, kc: 99_999))

        var expected = Self.settings()
        switch column {
        case .social: expected.advances.social[month - 1] = 99_999
        case .health: expected.advances.health[month - 1] = 99_999
        case .tax: expected.advances.tax[month - 1] = 99_999
        }
        #expect(changed == expected)
    }

    @Test func theSecondaryActivityOfAMonthIsAddedAndTakenAway() {
        var settings = Self.settings()
        YearSettingsEdit.secondary(month: 7, on: true).apply(to: &settings)
        YearSettingsEdit.secondary(month: 8, on: true).apply(to: &settings)
        #expect(settings.secondaryMonths == [7, 8])

        YearSettingsEdit.secondary(month: 7, on: true).apply(to: &settings)
        #expect(settings.secondaryMonths == [7, 8])

        YearSettingsEdit.secondary(month: 7, on: false).apply(to: &settings)
        YearSettingsEdit.secondary(month: 9, on: false).apply(to: &settings)
        #expect(settings.secondaryMonths == [8])
    }

    @Test func theChoicesOfTheYearAreSetEachOnItsOwn() {
        var expected = Self.settings()
        expected.expensePercent = 80
        #expect(Self.applying(.expensePercent(80)) == expected)

        expected = Self.settings()
        expected.reducedSocialBase = true
        #expect(Self.applying(.reducedSocialBase(true)) == expected)

        expected = Self.settings()
        expected.taxpayerCredit = false
        #expect(Self.applying(.taxpayerCredit(false)) == expected)

        expected = Self.settings()
        expected.deductions.mortgageCap = .before2021
        #expect(Self.applying(.mortgageCap(.before2021)) == expected)
    }

    @Test(arguments: DeductionField.allCases)
    func aDeductionFieldIsSetAndTheOthersAreNot(field: DeductionField) {
        let changed = Self.applying(.deduction(field, value: 11))

        #expect(field.amount(in: changed.deductions) == 11)
        for other in DeductionField.allCases where other != field {
            #expect(other.amount(in: changed.deductions) == other.amount(in: Self.settings().deductions))
        }
        var rest = changed
        rest.deductions = Self.settings().deductions
        #expect(rest == Self.settings())
    }

    /// The card of the spouse sets the spouse whole, and its typed field the income alone, which a year without a
    /// spouse does not have.
    @Test func theSpouseIsSetWholeAndItsIncomeOnItsOwn() {
        let spouse = SpouseYear(claim: true, months: MonthRange(from: 2, to: 11), ownIncomeKc: 1_000, ztpp: nil)
        var expected = Self.settings()
        expected.spouse = spouse
        var settings = Self.applying(.spouse(spouse))
        #expect(settings == expected)

        YearSettingsEdit.spouseIncome(50_000).apply(to: &settings)
        expected.spouse?.ownIncomeKc = 50_000
        #expect(settings == expected)

        YearSettingsEdit.spouse(nil).apply(to: &settings)
        #expect(settings == Self.settings())
        #expect(Self.applying(.spouseIncome(50_000)) == Self.settings())
        #expect(YearSettingsEdit.spouse(nil).target == YearSettingsEdit.spouse(spouse).target)
        #expect(YearSettingsEdit.spouseIncome(1).target == YearSettingsEdit.spouseIncome(2).target)
        #expect(YearSettingsEdit.spouseIncome(1).target != YearSettingsEdit.spouse(spouse).target)
    }

    @Test func aMonthOutsideTheYearChangesNothing() {
        for month in [-1, 0, 13, 100] {
            #expect(Self.applying(.advance(.social, month: month, kc: 5)) == Self.settings())
            #expect(Self.applying(.advance(.tax, month: month, kc: 5)) == Self.settings())
            #expect(Self.applying(.secondary(month: month, on: true)) == Self.settings())
        }
    }

    @Test func editsOfTheSameThingReplaceOneAnotherAndOthersDoNot() {
        #expect(
            YearSettingsEdit.advance(.social, month: 3, kc: 1).target
                == YearSettingsEdit.advance(.social, month: 3, kc: 2).target)
        #expect(
            YearSettingsEdit.advance(.social, month: 3, kc: 1).target
                != YearSettingsEdit.advance(.health, month: 3, kc: 1).target)
        #expect(
            YearSettingsEdit.advance(.social, month: 3, kc: 1).target
                != YearSettingsEdit.advance(.social, month: 4, kc: 1).target)
        #expect(
            YearSettingsEdit.secondary(month: 3, on: true).target
                == YearSettingsEdit.secondary(month: 3, on: false).target)
        #expect(
            YearSettingsEdit.secondary(month: 3, on: true).target
                != YearSettingsEdit.secondary(month: 4, on: true).target)
        #expect(YearSettingsEdit.expensePercent(80).target == YearSettingsEdit.expensePercent(40).target)
        #expect(
            YearSettingsEdit.deduction(.gifts, value: 1).target == YearSettingsEdit.deduction(.gifts, value: 2).target)
        #expect(
            YearSettingsEdit.deduction(.gifts, value: 1).target != YearSettingsEdit.deduction(.dip, value: 1).target)
        #expect(YearSettingsEdit.taxpayerCredit(true).target != YearSettingsEdit.reducedSocialBase(true).target)
        #expect(YearSettingsEdit.mortgageCap(.after2021).target == YearSettingsEdit.mortgageCap(.before2021).target)
    }

    @Test func theTextsOfTheColumnsAreInTheOrderOfTheTable() {
        #expect(AdvanceColumn.allCases == [.social, .health, .tax])
        #expect(AdvanceColumn(rawValue: 0) == .social)
        #expect(AdvanceColumn(rawValue: 1) == .health)
        #expect(AdvanceColumn(rawValue: 2) == .tax)
        #expect(AdvanceColumn(rawValue: 3) == nil)
    }

    @Test func aMonthsFieldIsAMonthCountAndTheOthersAreCrowns() {
        #expect(DeductionField.mortgageMonths.isMonthCount)
        #expect(DeductionField.allCases.filter { !$0.isMonthCount }.count == 6)
    }
}
