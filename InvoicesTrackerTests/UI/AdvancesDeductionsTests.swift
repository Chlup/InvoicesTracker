import Foundation
import Testing
@testable import InvoicesTracker

/// The model of Zálohy a odpočty, its part that is about the tax: the rate of the flat-rate expenses, the reduced base
/// and the taxpayer credit, the deductions with their limits and the messages under their fields, the fields of DIP and
/// long-term care insurance and the hint about refunded advances that belong to some years only, and the impact of the
/// deductions on the tax with the hints of the form. The data is the sample year of the engine's regression test,
/// stored in a temporary database; the app is as of 17. 10. 2026. In every expected string `\u{00A0}` is the no-break
/// space.
@Suite(.settlesBackups)
@MainActor
struct AdvancesDeductionsTests {
    /// Writes an expense rate into the table of 2026 that the tables refuse, which is how the data is changed outside
    /// the app.
    private nonisolated func storeExpensePercent(_ percent: Int, in database: Database) async throws {
        try await database.write { connection in
            try connection.run("PRAGMA ignore_check_constraints = ON")
            try connection.run(
                "UPDATE year_settings SET expense_percent = ? WHERE year = ?",
                [.integer(Int64(percent)), .integer(2026)])
            try connection.run("PRAGMA ignore_check_constraints = OFF")
        }
    }

    // MARK: The rate, the reduced base and the credit

    @Test func theExpenseRateIsSavedAndOnlyTheFourRatesAreTaken() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let app = try await makeAdvancesApp(in: directory)
        let model = await loadedAdvancesModel(of: app)

        for percent in [80, 40, 30, 60] {
            model.setExpensePercent(percent)
            await model.saveNow()
            #expect(try await storedYear(2026, in: app).expensePercent == percent)
        }

        let versionBefore = app.dataVersion
        for refused in [0, 50, 70, 100, -60] {
            model.setExpensePercent(refused)
        }
        await model.saveNow()

        #expect(model.settings?.expensePercent == 60)
        #expect(try await storedYear(2026, in: app).expensePercent == 60)
        #expect(app.dataVersion == versionBefore)
    }

    @Test func theReducedSocialBaseIsOnlyStored() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let app = try await makeAdvancesApp(in: directory)
        let model = await loadedAdvancesModel(of: app)
        let totalsBefore = model.impactTotals

        model.setReducedSocialBase(true)
        await model.saveNow()
        await model.load()

        #expect(try await storedYear(2026, in: app).reducedSocialBase)
        #expect(model.settings?.reducedSocialBase == true)
        #expect(model.impactTotals == totalsBefore)
        #expect(model.totals.yearSocial == 150_560)
    }

    @Test func theTaxpayerCreditIsSavedAndChangesTheTax() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let app = try await makeAdvancesApp(in: directory)
        let model = await loadedAdvancesModel(of: app)
        #expect(model.impactTotals?.taxWithKc == 94_440)

        model.setTaxpayerCredit(false)
        await model.saveNow()
        await model.load()

        #expect(try await storedYear(2026, in: app).taxpayerCredit == false)
        // 15 % of 835 200 Kč, without the 30 840 Kč credit.
        #expect(model.impactTotals?.taxWithKc == 125_280)
        // The credit is no deduction: the tax without deductions loses it too.
        #expect(model.impactTotals?.taxWithoutKc == 148_755)
        #expect(model.impactTotals?.savedKc == 23_475)
    }

    // MARK: Deductions

    @Test func theDeductionsAreSavedAsTheyAreGiven() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let app = try await makeAdvancesApp(in: directory)
        let model = await loadedAdvancesModel(of: app)
        let deductions = Deductions(
            mortgageInterestPaid: 120_000, mortgageMonths: 9, mortgageCap: .before2021, lifeInsurance: 18_000,
            pensionSavings: 12_000, dip: 24_000, longTermCare: 6_000, gifts: 5_000)

        let accepted = model.setDeductions(deductions)
        await model.saveNow()

        #expect(accepted)
        #expect(model.settings?.deductions == deductions)
        #expect(try await storedYear(2026, in: app).deductions == deductions)
        // The fields show what was set.
        #expect(model.deductionTexts[.mortgageInterest] == "120\u{00A0}000")
        #expect(model.deductionTexts[.mortgageMonths] == "9")
        #expect(model.deductionTexts[.dip] == "24\u{00A0}000")
        #expect(model.deductionTexts[.gifts] == "5\u{00A0}000")
    }

    @Test func deductionsTheEngineWouldRefuseAreNeverSaved() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let app = try await makeAdvancesApp(in: directory)
        let model = await loadedAdvancesModel(of: app)
        let versionBefore = app.dataVersion

        for broken in [
            Deductions(mortgageInterestPaid: -1), Deductions(mortgageMonths: 13), Deductions(mortgageMonths: -1),
            Deductions(lifeInsurance: -5), Deductions(pensionSavings: -5), Deductions(dip: -5),
            Deductions(longTermCare: -5), Deductions(gifts: -5),
            Deductions(gifts: 10_000_000_000), Deductions(pensionSavings: Int64.max),
        ] {
            #expect(!model.setDeductions(broken))
        }
        await model.saveNow()

        #expect(model.settings?.deductions == SampleYear2026.yearSettings.deductions)
        #expect(try await storedYear(2026, in: app).deductions == SampleYear2026.yearSettings.deductions)
        #expect(app.dataVersion == versionBefore)
    }

    @Test func aDeductionTextIsParsedInWholeCrownsAndSavedWhenItIsOne() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let app = try await makeAdvancesApp(in: directory)
        let model = await loadedAdvancesModel(of: app)
        // The regression year's deductions are shown as they are stored.
        #expect(model.deductionTexts[.mortgageInterest] == "219\u{00A0}000")
        #expect(model.deductionTexts[.mortgageMonths] == "12")
        #expect(model.deductionTexts[.lifeInsurance] == "6\u{00A0}480")
        #expect(model.deductionTexts[.pensionSavings] == "0")
        #expect(model.deductionTexts[.gifts] == "0")

        model.setDeductionText(.gifts, "20 000")
        model.setDeductionText(.pensionSavings, "12000")
        model.setDeductionText(.mortgageMonths, "10")
        await model.saveNow()

        #expect(model.deductionError(.gifts) == nil)
        let saved = try await storedYear(2026, in: app).deductions
        #expect(saved.gifts == 20_000)
        #expect(saved.pensionSavings == 12_000)
        #expect(saved.mortgageMonths == 10)
        // Nothing else of the deductions moved.
        #expect(saved.mortgageInterestPaid == 219_000)
        #expect(saved.lifeInsurance == 6_480)
        // The text stays as it was typed.
        #expect(model.deductionTexts[.pensionSavings] == "12000")
    }

    @Test(arguments: [
        DeductionField.mortgageInterest, .lifeInsurance, .pensionSavings, .dip, .longTermCare, .gifts,
    ])
    func aDeductionThatIsNotWholeCrownsIsRefusedWithTheMessage(field: DeductionField) async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let app = try await makeAdvancesApp(in: directory)
        let model = await loadedAdvancesModel(of: app)
        let versionBefore = app.dataVersion

        for text in ["13 340,50", "abc", "-5"] {
            model.setDeductionText(field, text)
            // The text is read when the typing stops.
            await model.saveNow()
            #expect(model.deductionError(field) == advancesWholeKcMessage)
            #expect(model.deductionTexts[field] == text)
        }

        #expect(model.settings?.deductions == SampleYear2026.yearSettings.deductions)
        #expect(app.dataVersion == versionBefore)

        // Nothing at all is no amount: the deduction is not claimed. The message stays until the text is read again.
        model.setDeductionText(field, "")
        await model.saveNow()
        #expect(model.deductionError(field) == nil)
        #expect(model.settings.map { field.amount(in: $0.deductions) } == 0)
    }

    @Test(arguments: ["13", "-1", "1,5", "abc", "99"])
    func theMonthsOfInterestAreAWholeNumberFromZeroToTwelve(text: String) async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let app = try await makeAdvancesApp(in: directory)
        let model = await loadedAdvancesModel(of: app)

        model.setDeductionText(.mortgageMonths, text)
        await model.saveNow()

        #expect(model.deductionError(.mortgageMonths) == "Zadejte počet měsíců od 0 do 12.")
        #expect(model.deductionTexts[.mortgageMonths] == text)
        #expect(try await storedYear(2026, in: app).deductions.mortgageMonths == 12)

        model.setDeductionText(.mortgageMonths, "0")
        await model.saveNow()
        #expect(model.deductionError(.mortgageMonths) == nil)
        #expect(try await storedYear(2026, in: app).deductions.mortgageMonths == 0)
    }

    @Test func aTypoInTheMonthsOfInterestIsNotSavedAsItsFirstDigit() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let app = try await makeAdvancesApp(in: directory)
        let model = await loadedAdvancesModel(of: app, saveDelay: .seconds(3_600))
        let versionBefore = app.dataVersion

        // 13 months are no months: the 1 before it must not be read, saved and left behind when the 3 follows.
        model.setDeductionText(.mortgageMonths, "1")
        #expect(model.deductionError(.mortgageMonths) == nil)
        #expect(model.settings?.deductions.mortgageMonths == 12)
        model.setDeductionText(.mortgageMonths, "13")
        #expect(model.deductionError(.mortgageMonths) == nil)
        await model.saveNow()

        #expect(model.deductionError(.mortgageMonths) == "Zadejte počet měsíců od 0 do 12.")
        #expect(model.deductionTexts[.mortgageMonths] == "13")
        #expect(model.settings?.deductions.mortgageMonths == 12)
        #expect(try await storedYear(2026, in: app).deductions.mortgageMonths == 12)
        #expect(app.dataVersion == versionBefore)
        // The limit for the months and the tax are those of 12 months.
        await model.load()
        #expect(model.deductionHints?.mortgageLimit == "limit 150\u{00A0}000\u{00A0}Kč za 12 měsíců")
        #expect(model.impactTotals?.taxWithKc == 94_440)
    }

    @Test func aDeductionTextIsReadWhenTheTypingStopsNotKeyByKey() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let app = try await makeAdvancesApp(in: directory)
        let model = await loadedAdvancesModel(of: app, saveDelay: .seconds(3_600))
        let versionBefore = app.dataVersion

        for text in ["2", "20", "20 ", "20 0", "20 00", "20 000"] {
            model.setDeductionText(.gifts, text)

            #expect(model.deductionError(.gifts) == nil, "\(text)")
            #expect(model.settings?.deductions.gifts == 0, "\(text)")
            #expect(app.dataVersion == versionBefore, "\(text)")
        }
        await model.saveNow()

        #expect(model.deductionError(.gifts) == nil)
        #expect(try await storedYear(2026, in: app).deductions.gifts == 20_000)
        #expect(app.dataVersion == versionBefore + 1)
    }

    @Test func aDeductionTextThatEndsRefusedSavesNothingNotEvenItsValidBeginning() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let app = try await makeAdvancesApp(in: directory)
        let model = await loadedAdvancesModel(of: app, saveDelay: .seconds(3_600))
        let versionBefore = app.dataVersion

        for text in ["5", "5 ", "5 0", "5 00", "5 000", "5 000,", "5 000,5"] {
            model.setDeductionText(.lifeInsurance, text)
        }
        await model.saveNow()

        #expect(model.deductionError(.lifeInsurance) == advancesWholeKcMessage)
        #expect(model.settings?.deductions.lifeInsurance == 6_480)
        #expect(try await storedYear(2026, in: app).deductions.lifeInsurance == 6_480)
        #expect(app.dataVersion == versionBefore)
    }

    @Test func theLimitCategoryOfTheMortgageIsSaved() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let app = try await makeAdvancesApp(in: directory)
        let model = await loadedAdvancesModel(of: app)

        model.setMortgageCap(.before2021)
        await model.saveNow()
        await model.load()

        #expect(try await storedYear(2026, in: app).deductions.mortgageCap == .before2021)
        #expect(model.settings?.deductions.mortgageCap == .before2021)
        // 219 000 Kč paid, 300 000 Kč allowed: all of it counts.
        #expect(model.impact.first?.appliedKc == 219_000)
        #expect(model.deductionHints?.mortgageOverLimit == nil)
    }

    @Test func aDeductionChangeKeepsTheDeductionsAnotherWriterChanged() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let app = try await makeAdvancesApp(in: directory)
        let model = await loadedAdvancesModel(of: app, saveDelay: .seconds(3_600))
        var other = try await storedYear(2026, in: app)
        other.deductions.dip = 11_000
        other.deductions.lifeInsurance = 3_000
        try await storeYear(other, in: app)

        model.setDeductionText(.gifts, "2 000")
        await model.saveNow()

        let saved = try await storedYear(2026, in: app).deductions
        #expect(saved.gifts == 2_000)
        #expect(saved.dip == 11_000)
        #expect(saved.lifeInsurance == 3_000)
    }

    @Test func theFieldsOfDIPAndLongTermCareAreForTheYearsFrom2024() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let app = try await makeAdvancesApp(in: directory)
        let model = AdvancesModel(app: app, saveDelay: .zero)

        for (year, shown) in [(2022, false), (2023, false), (2024, true), (2025, true), (2026, true)] {
            app.selectYear(year)
            #expect(model.showsDIPAndLongTermCare == shown, "\(year)")
        }
        // A year without rules of its own has those of the nearest year.
        app.selectYear(2021)
        #expect(!model.showsDIPAndLongTermCare)
    }

    @Test func theHintAboutRefundedAdvancesIsOnlyFor2026() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let app = try await makeAdvancesApp(in: directory)
        let model = AdvancesModel(app: app, saveDelay: .zero)

        #expect(
            model.refundHint
                == "Od července 2026 je minimální záloha nižší (zákon 90/2026 Sb.). Pokud vám ČSSZ vrátila část záloh"
                + " za leden až červen, snižte tyto měsíce o vrácenou částku – vrácená záloha se nepočítá jako"
                + " zaplacená.")
        for year in [2022, 2023, 2024, 2025, 2021] {
            app.selectYear(year)
            #expect(model.refundHint == nil, "\(year)")
        }
    }

    // MARK: The impact on the tax

    @Test func theImpactIsTheEffectOfEachDeductionOnTheTaxOfTheYear() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let app = try await makeAdvancesApp(in: directory)

        let model = await loadedAdvancesModel(of: app)

        // The sample year as of 17. 10. 2026: the profit is 991 771 Kč. The interest of 219 000 Kč allows 150 000 Kč,
        // which takes 22 500 Kč off the tax; the life insurance of 6 480 Kč takes 975 Kč off.
        #expect(
            model.impact == [
                ImpactLine(
                    kind: .mortgageInterest, title: "Úroky z úvěru na bydlení", claimedKc: 219_000,
                    appliedKc: 150_000, taxSavedKc: 22_500),
                ImpactLine(
                    kind: .retirementProducts, title: "Spoření a pojištění na stáří", claimedKc: 6_480,
                    appliedKc: 6_480, taxSavedKc: 975),
            ])
        #expect(model.impactTotals?.deductionsKc == 156_480)
        #expect(model.impactTotals?.taxWithoutKc == 117_915)
        #expect(model.impactTotals?.taxWithKc == 94_440)
        #expect(model.impactTotals?.savedKc == 23_475)
        #expect(model.impactError == nil)
    }

    @Test func theImpactCountsTheFamilyOfTheYear() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let app = try await makeAdvancesApp(in: directory)
        let database = try #require(app.database)
        for (name, born, order) in [("Anna", "2019-09-03", 1), ("Tomáš", "2024-04-12", 2)] {
            try await database.saveChild(
                Child(id: nil, name: name, birthDate: civilDate(born)), year: 2026,
                childYear: ChildYear(
                    household: MonthRange.wholeYear, claimant: .me, order: order, ztpp: nil, studies: nil))
        }
        try await database.saveSpouse(
            SpouseYear(claim: true, months: MonthRange.wholeYear, ownIncomeKc: 0, ztpp: nil), year: 2026)
        await app.didWriteAndBackUp()

        let model = await loadedAdvancesModel(of: app)

        // The sample year as of 17. 10. 2026: the 94 440 Kč of tax after the taxpayer credit, less the spouse credit
        // (24 840 Kč) and the children's 37 524 Kč, are 32 076 Kč. Without the deductions and without the credits of
        // the family, the taxpayer credit applied, the tax would be 117 915 Kč: the deductions save 23 475 Kč of it and
        // the family 62 364 Kč.
        #expect(model.impactTotals?.taxWithKc == 32_076)
        #expect(model.impactTotals?.taxWithoutKc == 117_915)
        #expect(model.impactTotals?.savedKc == 85_839)
        #expect(model.impactTotals?.spouseCreditKc == 24_840)
        #expect(model.impactTotals?.childBenefitKc == 37_524)
        #expect(model.impactError == nil)
    }

    @Test func theImpactFollowsASavedChange() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let app = try await makeAdvancesApp(in: directory)
        let model = await loadedAdvancesModel(of: app)

        model.setDeductionText(.mortgageInterest, "100 000")
        await model.saveNow()
        // The screen loads again after the write, because the data changed.
        await model.load()

        #expect(model.impact.first?.appliedKc == 100_000)
        #expect(model.impact.first?.taxSavedKc == 15_000)
        #expect(model.impact.last?.taxSavedKc == 975)
        #expect(model.impactTotals?.deductionsKc == 106_480)
        #expect(model.impactTotals?.taxWithKc == 101_940)
        #expect(model.impactTotals?.savedKc == 15_975)
    }

    @Test func theImpactIsWorkedOutWithWhatCouldNotBeSavedToo() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let app = try await makeAdvancesApp(in: directory)
        let database = try #require(app.database)
        let model = await loadedAdvancesModel(of: app)
        try await setDatabaseReadOnly(true, database)

        // A change that cannot be saved waits for the next save, and is what the person has meanwhile.
        model.setDeductions(Deductions(mortgageInterestPaid: 100_000, lifeInsurance: 6_480))
        await model.saveNow()
        await model.load()

        #expect(model.saveFailure != nil)
        #expect(model.impact.first?.appliedKc == 100_000)
        #expect(model.impactTotals?.taxWithKc == 101_940)

        try await setDatabaseReadOnly(false, database)
        await model.saveNow()
        #expect(try await storedYear(2026, in: app).deductions.mortgageInterestPaid == 100_000)
    }

    @Test func aLineIsOnlyThereForADeductionThatIsClaimed() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let app = try await makeAdvancesApp(in: directory)
        let model = await loadedAdvancesModel(of: app)

        model.setDeductions(Deductions())
        await model.saveNow()
        await model.load()

        #expect(model.impact.isEmpty)
        #expect(model.impactTotals?.deductionsKc == 0)
        #expect(model.impactTotals?.savedKc == 0)
        #expect(model.impactTotals?.taxWithKc == 117_915)
    }

    @Test func aStoredYearTheComputationWouldRefuseShowsItsLineInsteadOfNumbers() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let app = try await makeAdvancesApp(in: directory)
        let database = try #require(app.database)
        // Something other than the app, which the tables have a check against, changes a value.
        try await storeExpensePercent(55, in: database)

        let model = await loadedAdvancesModel(of: app)

        #expect(
            model.impactError
                == "Dopad na daň se nepodařilo spočítat – uložené hodnoty roku 2026 jsou neplatné.")
        #expect(model.impact.isEmpty)
        #expect(model.impactTotals == nil)
        #expect(model.deductionHints == nil)
        // The plan is still there to be corrected.
        #expect(model.settings?.expensePercent == 55)
        #expect(model.totals.yearSocial == 150_560)

        // Choosing a rate the engine takes brings the numbers back.
        model.setExpensePercent(60)
        await model.saveNow()
        await model.load()

        #expect(model.impactError == nil)
        #expect(model.impactTotals?.taxWithKc == 94_440)
    }

    @Test func theHintsOfTheFormComeFromTheSameComputation() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let app = try await makeAdvancesApp(in: directory)
        let model = await loadedAdvancesModel(of: app)

        let hints = try #require(model.deductionHints)

        #expect(hints.mortgageAllowed == "150\u{00A0}000\u{00A0}Kč")
        #expect(hints.mortgageOverLimit == "69\u{00A0}000\u{00A0}Kč")
        #expect(hints.mortgageLimit == "limit 150\u{00A0}000\u{00A0}Kč za 12 měsíců")
        #expect(hints.retirementAllowed == "6\u{00A0}480\u{00A0}Kč")
        #expect(hints.retirementLimits.map(\.title) == ["Společný limit"])
        #expect(hints.retirementLimits.map(\.usedText) == ["6\u{00A0}480 z 48\u{00A0}000\u{00A0}Kč"])
        #expect(hints.giftsAllowed == "0\u{00A0}Kč")
        #expect(hints.giftsNote == "od 1 000 Kč (nebo nad 2 % základu), nejvýš 30 % základu")
    }

    @Test func giftsBelowTheMinimumDoNotCountAndTheHintSaysSo() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let app = try await makeAdvancesApp(in: directory)
        let model = await loadedAdvancesModel(of: app)

        model.setDeductionText(.gifts, "500")
        await model.saveNow()
        await model.load()

        #expect(model.deductionHints?.giftsNote == "pod minimem – neuplatní se")
        #expect(model.deductionHints?.giftsAllowed == "0\u{00A0}Kč")
        let gifts = try #require(model.impact.last)
        #expect(gifts.kind == .gifts)
        #expect(gifts.claimedKc == 500)
        #expect(gifts.appliedKc == 0)
        #expect(gifts.taxSavedKc == 0)

        model.setDeductionText(.gifts, "20 000")
        await model.saveNow()
        await model.load()

        #expect(model.deductionHints?.giftsAllowed == "20\u{00A0}000\u{00A0}Kč")
        #expect(model.deductionHints?.giftsNote == "od 1 000 Kč (nebo nad 2 % základu), nejvýš 30 % základu")
        // 20 000 Kč off a base in the 15 % band.
        #expect(model.impact.last?.taxSavedKc == 3_000)
    }
}
