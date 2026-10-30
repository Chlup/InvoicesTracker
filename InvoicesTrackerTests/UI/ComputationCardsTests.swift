import Foundation
import Testing
@testable import InvoicesTracker

/// The rest of the page of Výpočet that the builder makes from the result of the tax engine, besides the sections: the
/// banner about the day the computation counts up to, the "Zbývá zaplatit" equation, the marginal levy, the thresholds
/// of the year, the assumptions, and the tags of the sections. The sample year is the engine's regression year as of
/// 17. 10. 2026; its figures and those of the other years were worked out for the same data by a separate
/// implementation of the rules (exact fractions, run in Python). In every expected string `\u{00A0}` is the no-break
/// space.
struct ComputationCardsTests {
    // MARK: Helpers

    private let sample = TaxEngineRegressionTests.sampleYear2026

    /// A year whose receipts are payments, each on a day (ISO) with its net amount in haléře.
    private func year(paying days: [(String, Int64)]) -> YearInput {
        var input = computationYearInput()
        input.receipts = days.enumerated().map { index, entry in
            Receipt(
                day: civilDate(entry.0), czkNetHalere: entry.1, czkVatHalere: 0, source: .invoice(Int64(index + 1)))
        }
        return input
    }

    private func isClose(_ actual: Double, _ expected: Double) -> Bool {
        abs(actual - expected) < 1e-9
    }

    /// The amounts with two decimals in `text`, in hundredths: "12,45" is 1245.
    private func hundredths(in text: String) -> [Int64] {
        guard let amount = try? Regex("(\\d{1,3}(?:\u{00A0}\\d{3})*),(\\d\\d)") else {
            return []
        }
        return text.matches(of: amount).compactMap { match in
            guard let whole = match.output[1].substring.flatMap({ Int64(String($0).filter(\.isNumber)) }),
                let fraction = match.output[2].substring.flatMap({ Int64($0) })
            else {
                return nil
            }
            return whole * 100 + fraction
        }
    }

    // MARK: The banner

    @Test func theBannerSaysWhatTheComputationCountsUpToTheDayShown() {
        #expect(
            computationPage(sample).banner
                == "Počítáno jen ze skutečně přijatých plateb od 1.\u{00A0}1. do 17.\u{00A0}10.\u{00A0}2026."
                + " Zálohy za leden až říjen bereme jako zaplacené v jejich měsíci."
                + " Odpočty a sleva na poplatníka se berou za celý rok,"
                + " minimální pojistné jen za uplynulé měsíce hlavní činnosti.")
    }

    @Test func inJanuaryTheBannerNamesOnlyJanuary() {
        #expect(
            computationPage(computationYearInput(), asOf: "2026-01-31").banner
                == "Počítáno jen ze skutečně přijatých plateb od 1.\u{00A0}1. do 31.\u{00A0}1.\u{00A0}2026."
                + " Zálohy za leden bereme jako zaplacené v jejich měsíci."
                + " Odpočty a sleva na poplatníka se berou za celý rok,"
                + " minimální pojistné jen za uplynulé měsíce hlavní činnosti.")
    }

    @Test func theBannerOfAYearInProgressCountsTheMinimumsForThePastMonthsOnly() {
        // Whatever day of the year in progress is shown, also its last one while the year is not over yet.
        for asOf in ["2026-01-31", "2026-06-30", "2026-12-31"] {
            let banner = computationPage(sample, asOf: asOf).banner

            #expect(banner.hasSuffix(", minimální pojistné jen za uplynulé měsíce hlavní činnosti."), "\(asOf)")
        }
    }

    @Test func aYearThatIsOverHasTheBannerOfTheWholeYear() {
        let page = computationPage(computationYearInput(year: 2025, netHalere: 450_000), asOf: "2025-12-31")

        #expect(
            page.banner == "Rok 2025 celý: všechny přijaté platby, všechny zálohy, odpočty a slevy za celý rok.")
    }

    @Test func aYearThatIsOverShownAsOfAMidYearDayHasTheBannerOfAYearInProgressUpToThatDay() {
        // The year 2025 is over, but as of 30. 6. 2025 it is a year with half of it still to come.
        let page = computationPage(computationYearInput(year: 2025, netHalere: 450_000), asOf: "2025-06-30")

        #expect(
            page.banner
                == "Počítáno jen ze skutečně přijatých plateb od 1.\u{00A0}1. do 30.\u{00A0}6.\u{00A0}2025."
                + " Zálohy za leden až červen bereme jako zaplacené v jejich měsíci."
                + " Odpočty a sleva na poplatníka se berou za celý rok,"
                + " minimální pojistné jen za uplynulé měsíce hlavní činnosti.")
    }

    @Test func aYearWithoutRulesHasTheBannerOfAYearInProgress() {
        let page = computationPage(
            computationYearInput(year: 2027), asOf: "2027-03-31", today: "2027-03-31")

        #expect(page.banner.hasPrefix("Počítáno jen ze skutečně přijatých plateb od 1.\u{00A0}1. do 31.\u{00A0}3."))
        #expect(page.banner.contains("Zálohy za leden až březen bereme"))
    }

    // MARK: The equation

    @Test func theEquationAddsWhatEachAuthorityStillHasToGetAndSaysWhereItGoes() {
        let equation = computationPage(sample).equation

        #expect(equation.heading == "Zbývá zaplatit k 17.\u{00A0}10.\u{00A0}2026")
        #expect(
            equation.caption == "sčítají se jen kladné zůstatky – přeplatek u jednoho úřadu nezaplatí dluh u jiného")
        #expect(equation.tiles.map(\.sign) == [.blank, .plus, .plus, .equals])
        #expect(equation.tiles.map(\.label) == ["Daň", "Sociální", "Zdravotní", "Zbývá zaplatit"])
        #expect(
            equation.tiles.map(\.value) == [
                "71\u{00A0}440", "33\u{00A0}019", "6\u{00A0}385", "110\u{00A0}844\u{00A0}Kč",
            ])
        #expect(equation.tiles.map(\.isResult) == [false, false, false, true])
        #expect(
            equation.split
                == "Z toho 53\u{00A0}685\u{00A0}Kč odejde naplánovanými zálohami do konce roku"
                + " a 57\u{00A0}159\u{00A0}Kč doplatíte po podání přiznání a přehledů.")
    }

    @Test func withoutIncomeEachAuthorityStillWantsItsMinimum() {
        // Nothing is received, so there is no tax; the insurances are the minimums of ten months.
        let equation = computationPage(computationYearInput()).equation

        #expect(equation.tiles.map(\.value) == ["0", "50\u{00A0}046", "33\u{00A0}053", "83\u{00A0}099\u{00A0}Kč"])
        #expect(
            equation.split
                == "Z toho 0\u{00A0}Kč odejde naplánovanými zálohami do konce roku"
                + " a 83\u{00A0}099\u{00A0}Kč doplatíte po podání přiznání a přehledů.")
    }

    @Test func aYearThatIsOverSaysWhatIsDueAndWhatTheAdvancesPaid() {
        // A payment of 4 500 Kč in 2025: no tax, social insurance 57 098 Kč and health insurance 37 712 Kč.
        let page = computationPage(
            computationYearInput(year: 2025, netHalere: 450_000, vatHalere: 94_500), asOf: "2025-12-31")

        #expect(page.equation.heading == "Doplatek za rok 2025")
        #expect(page.equation.tiles.map(\.label) == ["Daň", "Sociální", "Zdravotní", "Doplatek za rok"])
        #expect(
            page.equation.tiles.map(\.value) == [
                "0", "57\u{00A0}098", "37\u{00A0}712", "94\u{00A0}810\u{00A0}Kč",
            ])
        #expect(page.equation.split == "Zálohami se za rok zaplatilo 0\u{00A0}Kč.")
    }

    @Test func aYearThatIsOverSaysThatOverpaymentsAreReturned() {
        // 10 000 Kč of income tax advances were paid in March, and the tax is 0 Kč.
        var advances = AdvancePlan.empty
        advances.tax[2] = 10_000
        let page = computationPage(
            computationYearInput(year: 2025, netHalere: 450_000, vatHalere: 94_500, advances: advances),
            asOf: "2025-12-31")

        #expect(page.equation.tiles.map(\.value).last == "94\u{00A0}810\u{00A0}Kč")
        #expect(
            page.equation.split
                == "Zálohami se za rok zaplatilo 10\u{00A0}000\u{00A0}Kč,"
                + " přeplatky 10\u{00A0}000\u{00A0}Kč se vrací.")
    }

    /// The sample family in the whole of 2026, seen from 15. 1. 2027, with 120 000 Kč received on 20. 1. and 130 000 Kč
    /// on 20. 2. and no advances: the children's 37 524 Kč are a bonus, which is not an overpayment of advances.
    @Test func aYearThatIsOverWithABonusAndNoAdvancesSaysWhatComesBackIsTheBonus() {
        let page = computationPage(
            TaxEngineFamilyTests.input(TaxEngineFamilyTests.earlyReceipts), asOf: "2026-12-31", today: "2027-01-15")

        #expect(
            page.equation.split
                == "Zálohami se za rok zaplatilo 0\u{00A0}Kč,"
                + " vrátí se 37\u{00A0}524\u{00A0}Kč (z toho daňový bonus 37\u{00A0}524\u{00A0}Kč).")
    }

    /// The same family with 10 000 Kč of tax advances paid in January: the bonus comes back with the advances.
    @Test func aYearThatIsOverWithABonusAndAdvancesSaysWhatComesBackAndHowMuchOfItIsTheBonus() {
        var family = TaxEngineFamilyTests.input(TaxEngineFamilyTests.earlyReceipts)
        family.advances.tax[0] = 10_000

        let page = computationPage(family, asOf: "2026-12-31", today: "2027-01-15")

        #expect(
            page.equation.split
                == "Zálohami se za rok zaplatilo 10\u{00A0}000\u{00A0}Kč,"
                + " vrátí se 47\u{00A0}524\u{00A0}Kč (z toho daňový bonus 37\u{00A0}524\u{00A0}Kč).")
    }

    @Test func aYearThatIsOverShownAsOfAMidYearDaySaysWhatIsLeftAndWhereItGoesLikeAYearInProgress() {
        // A payment of 4 500 Kč in 2025, as of 30. 6. 2025: six months of the minimum insurance, 28 549 Kč of social
        // and 18 856 Kč of health insurance, no tax, and 1 000 Kč of social insurance advances in each month.
        var advances = AdvancePlan.empty
        advances.social = [Int64](repeating: 1_000, count: 12)
        let page = computationPage(
            computationYearInput(year: 2025, netHalere: 450_000, vatHalere: 94_500, advances: advances),
            asOf: "2025-06-30")

        #expect(page.equation.heading == "Zbývá zaplatit k 30.\u{00A0}6.\u{00A0}2025")
        #expect(page.equation.tiles.map(\.label) == ["Daň", "Sociální", "Zdravotní", "Zbývá zaplatit"])
        #expect(
            page.equation.tiles.map(\.value) == ["0", "22\u{00A0}549", "18\u{00A0}856", "41\u{00A0}405\u{00A0}Kč"])
        #expect(
            page.equation.split
                == "Z toho 6\u{00A0}000\u{00A0}Kč odejde naplánovanými zálohami do konce roku"
                + " a 35\u{00A0}405\u{00A0}Kč doplatíte po podání přiznání a přehledů.")
    }

    // MARK: The marginal levy

    @Test func theMarginalLevyOfTheSampleYearIsSplitByAuthority() {
        // 100 000 Kč more income: 15 000 Kč of tax, 16 060 Kč of social and 6 750 Kč of health insurance.
        let marginal = computationPage(sample).marginal

        #expect(marginal.total == "37,8\u{00A0}%")
        #expect(
            marginal.text
                == "Ze 100\u{00A0}Kč dalšího příjmu bez DPH odvedete 37,81\u{00A0}Kč:"
                + " daň 15,00 · sociální 16,06 · zdravotní 6,75.")
        #expect(marginal.shares.map(\.authority) == [.tax, .social, .health])
        #expect(isClose(marginal.shares[0].fraction, 0.3967204443268976))
        #expect(isClose(marginal.shares[1].fraction, 0.42475535572599843))
        #expect(isClose(marginal.shares[2].fraction, 0.17852419994710395))
    }

    @Test func aHighIncomeHasNoMarginalSocialInsuranceAndTheTopRateOfTax() {
        // 5 700 000 Kč: the social base is at its maximum, the profit is taxed at 23 % and health insurance has none.
        let marginal = computationPage(computationYearInput(netHalere: 570_000_000)).marginal

        #expect(marginal.total == "29,8\u{00A0}%")
        #expect(
            marginal.text
                == "Ze 100\u{00A0}Kč dalšího příjmu bez DPH odvedete 29,75\u{00A0}Kč:"
                + " daň 23,00 · sociální 0,00 · zdravotní 6,75.")
        #expect(isClose(marginal.shares[0].fraction, 0.773109243697479))
        #expect(marginal.shares[1].fraction == 0)
        #expect(isClose(marginal.shares[2].fraction, 0.226890756302521))
    }

    @Test func thePartsOfTheMarginalLevyAddUpToTheTotalShown() {
        // 1 125 000 Kč of income: 100 000 Kč more is 6 000 Kč of tax, 6 424 Kč of social and 22 Kč of health insurance,
        // 12,446 Kč of every hundred. Rounded one by one the parts are 6,00, 6,42 and 0,02, which make 12,44 and not
        // the 12,45 of the total, so the part with the largest remainder, the social insurance, gets the hundredth.
        let marginal = computationPage(computationYearInput(netHalere: 112_500_000)).marginal

        #expect(
            marginal.text
                == "Ze 100\u{00A0}Kč dalšího příjmu bez DPH odvedete 12,45\u{00A0}Kč:"
                + " daň 6,00 · sociální 6,43 · zdravotní 0,02.")
        #expect(marginal.total == "12,4\u{00A0}%")
    }

    /// The sample family as of 31. 1. 2026 with 120 000 Kč received (`TaxEngineFamilyTests`): 100 000 Kč more would
    /// reach the six minimum wages that pay the children's bonus, but the bonus is a step, not a rate, so the next
    /// crown is levied with it as it is: no tax, 6 424 Kč of social and 2 634 Kč of health insurance on 100 000 Kč. The
    /// parts rounded down leave a hundredth to the social insurance, the first of the two equal remainders.
    @Test func theMarginalLevyLeavesTheBonusAsItIs() {
        let marginal = computationPage(
            TaxEngineFamilyTests.input(TaxEngineFamilyTests.earlyReceipts), asOf: "2026-01-31"
        ).marginal

        #expect(marginal.total == "9,1\u{00A0}%")
        #expect(
            marginal.text
                == "Ze 100\u{00A0}Kč dalšího příjmu bez DPH odvedete 9,06\u{00A0}Kč:"
                + " daň 0,00 · sociální 6,43 · zdravotní 2,63.")
        #expect(marginal.shares[0].fraction == 0)
    }

    @Test func withoutIncomeNothingMoreIsLeviedAndTheBarIsEmpty() {
        // The minimums and the taxpayer credit take the first 100 000 Kč.
        let marginal = computationPage(computationYearInput()).marginal

        #expect(marginal.total == "0,0\u{00A0}%")
        #expect(
            marginal.text
                == "Ze 100\u{00A0}Kč dalšího příjmu bez DPH odvedete 0,00\u{00A0}Kč:"
                + " daň 0,00 · sociální 0,00 · zdravotní 0,00.")
        #expect(marginal.shares.map(\.fraction) == [0, 0, 0])
    }

    // MARK: The thresholds

    @Test func theThresholdsOfTheSampleYear() {
        let thresholds = computationPage(sample).thresholds

        #expect(thresholds.heading == "Hranice roku 2026")
        #expect(
            thresholds.bars.map(\.title) == [
                "Strop paušálu (příjmy 2\u{00A0}mil.\u{00A0}Kč)", "23% pásmo daně", "Strop sociálního pojištění",
            ])
        // The cap was reached with the payment of 2. 10.
        #expect(
            thresholds.bars.map(\.value) == [
                "dosažen 2.\u{00A0}10.", "zbývá 927\u{00A0}612", "zbývá 1\u{00A0}804\u{00A0}941",
            ])
        #expect(thresholds.bars.map(\.authority) == [nil, .tax, .social])
        #expect(thresholds.bars.map(\.isReached) == [true, false, false])
        #expect(thresholds.bars.map(\.isHighlighted) == [true, false, false])
        #expect(thresholds.bars[0].fraction == 1)
        #expect(isClose(thresholds.bars[1].fraction, 0.4737884697857741))
        #expect(isClose(thresholds.bars[2].fraction, 0.23207593889762493))
    }

    @Test func aSmallIncomeIsFarFromEveryThreshold() {
        // 100 001,50 Kč: 100 002 Kč of income, a tax base of 40 000 Kč, and the minimum of ten months as the social
        // base.
        let thresholds = computationPage(computationYearInput(netHalere: 10_000_150)).thresholds

        #expect(
            thresholds.bars.map(\.value) == [
                "zbývá 1\u{00A0}899\u{00A0}998", "zbývá 1\u{00A0}722\u{00A0}812", "zbývá 2\u{00A0}179\u{00A0}026",
            ])
        #expect(thresholds.bars.map(\.isReached) == [false, false, false])
        #expect(thresholds.bars.map(\.isHighlighted) == [false, false, false])
        #expect(isClose(thresholds.bars[0].fraction, 0.05000075))
        #expect(isClose(thresholds.bars[1].fraction, 0.022691018667901058))
        #expect(isClose(thresholds.bars[2].fraction, 0.07291900667796679))
    }

    @Test func aHighIncomeHasPassedEveryThreshold() {
        // 5 700 000 Kč, received on 2. 3.: the base is in the band of 23 % and the social base is at its maximum.
        let thresholds = computationPage(computationYearInput(netHalere: 570_000_000)).thresholds

        #expect(thresholds.bars.map(\.value) == ["dosažen 2.\u{00A0}3.", "překročeno", "dosažen"])
        #expect(thresholds.bars.map(\.isReached) == [true, true, true])
        // Only the cap of the expenses is set in green, as a reached limit; the other two stay grey.
        #expect(thresholds.bars.map(\.isHighlighted) == [true, false, false])
        #expect(thresholds.bars.map(\.fraction) == [1, 1, 1])
    }

    @Test func exactlyAtTheCapTheBarSaysItIsReachedAsTheExpensesDo() {
        // 2 000 000 Kč, received on 2. 3.: 60 % of it is exactly the cap, and the cap is reached.
        let page = computationPage(computationYearInput(netHalere: 200_000_000))

        #expect(page.thresholds.bars[0].value == "dosažen 2.\u{00A0}3.")
        #expect(page.thresholds.bars[0].isReached)
        #expect(page.thresholds.bars[0].fraction == 1)
        // One crown less is not.
        let short = computationPage(computationYearInput(netHalere: 199_999_900))
        #expect(short.thresholds.bars[0].value == "zbývá 1")
        #expect(!short.thresholds.bars[0].isReached)
    }

    @Test func withoutIncomeNothingIsUsedButTheMinimumOfTheSocialBase() {
        let thresholds = computationPage(computationYearInput()).thresholds

        #expect(
            thresholds.bars.map(\.value) == [
                "zbývá 2\u{00A0}000\u{00A0}000", "zbývá 1\u{00A0}762\u{00A0}812", "zbývá 2\u{00A0}179\u{00A0}026",
            ])
        #expect(thresholds.bars[0].fraction == 0)
        #expect(thresholds.bars[1].fraction == 0)
        #expect(isClose(thresholds.bars[2].fraction, 0.07291900667796679))
    }

    @Test func aYearThatIsOverHasTheThresholdsOfItsOwnRules() {
        // A payment of 4 500 Kč in 2025: the band starts at 1 676 052 Kč and the social maximum is 2 234 736 Kč.
        let thresholds = computationPage(
            computationYearInput(year: 2025, netHalere: 450_000, vatHalere: 94_500), asOf: "2025-12-31"
        ).thresholds

        #expect(thresholds.heading == "Hranice roku 2025")
        #expect(
            thresholds.bars.map(\.value) == [
                "zbývá 1\u{00A0}995\u{00A0}500", "zbývá 1\u{00A0}674\u{00A0}252", "zbývá 2\u{00A0}039\u{00A0}196",
            ])
        #expect(isClose(thresholds.bars[0].fraction, 0.00225))
        #expect(isClose(thresholds.bars[1].fraction, 0.0010739523594733337))
        #expect(isClose(thresholds.bars[2].fraction, 0.08750026848808987))
    }

    @Test func aYearWithoutRulesHasTheThresholdsOfTheYearItIsComputedWith() {
        // 2027 is computed with the rules of 2026; as of 31. 3. the minimum of three months is the social base.
        let thresholds = computationPage(
            computationYearInput(year: 2027), asOf: "2027-03-31", today: "2027-03-31"
        ).thresholds

        #expect(thresholds.heading == "Hranice roku 2027")
        #expect(
            thresholds.bars.map(\.value) == [
                "zbývá 2\u{00A0}000\u{00A0}000", "zbývá 1\u{00A0}762\u{00A0}812", "zbývá 2\u{00A0}298\u{00A0}999",
            ])
    }

    @Test func theCapOfTheExpensesIsTheSameIncomeAtEveryRate() {
        // 80 % of 2 000 000 Kč is 1 600 000 Kč, the cap of that rate, and so on down to 30 % and 600 000 Kč.
        for percent in [30, 40, 60, 80] {
            let page = computationPage(computationYearInput(percent: percent))

            #expect(page.thresholds.bars[0].title == "Strop paušálu (příjmy 2\u{00A0}mil.\u{00A0}Kč)")
        }
    }

    @Test func theCapIsReachedOnTheDayTheIncomeCrossedIt() {
        // 1 500 000 Kč on 2. 3. and 600 000 Kč on 1. 4. make 2 100 000 Kč: the cap of 2 000 000 Kč was reached on 1. 4.
        let reached = computationPage(year(paying: [("2026-03-02", 150_000_000), ("2026-04-01", 60_000_000)]))

        #expect(reached.thresholds.bars[0].value == "dosažen 1.\u{00A0}4.")
        #expect(reached.thresholds.bars[0].isReached)
    }

    @Test func receiptsOfTheDayItIsReachedAreAllCountedBeforeTheDayIsNamed() {
        // Two payments on 1. 6. make the 2 000 000 Kč together; the day is that one, not the day before.
        let page = computationPage(
            year(paying: [("2026-03-02", 50_000_000), ("2026-06-01", 100_000_000), ("2026-06-01", 50_000_000)]))

        #expect(page.thresholds.bars[0].value == "dosažen 1.\u{00A0}6.")
    }

    @Test func aCreditNoteThatTakesTheIncomeBelowTheCapTakesTheCapBack() {
        // The cap was crossed on 1. 4., and 200 000 Kč are credited back on 5. 5.: 1 900 000 Kč, 100 000 Kč short.
        var input = year(paying: [("2026-03-02", 150_000_000), ("2026-04-01", 60_000_000)])
        input.receipts.append(
            Receipt(day: civilDate("2026-05-05"), czkNetHalere: -20_000_000, czkVatHalere: 0, source: .adjustment(1)))
        let thresholds = computationPage(input).thresholds

        #expect(thresholds.bars[0].value == "zbývá 100\u{00A0}000")
        #expect(!thresholds.bars[0].isReached)
        #expect(isClose(thresholds.bars[0].fraction, 0.95))
    }

    @Test func incomeIsReachedToTheCrownRoundedHalfUpAsTheEngineRoundsIt() {
        // 1 999 999,50 Kč is 2 000 000 Kč for the engine, so the cap is reached; 1 999 999,49 Kč is 1 999 999 Kč.
        let reached = computationPage(year(paying: [("2026-03-02", 199_999_950)]))
        let short = computationPage(year(paying: [("2026-03-02", 199_999_949)]))

        #expect(reached.thresholds.bars[0].value == "dosažen 2.\u{00A0}3.")
        #expect(short.thresholds.bars[0].value == "zbývá 1")
    }

    @Test func receiptsAfterTheDayShownAreNotCounted() {
        // The cap is crossed on 1. 4.; seen from 1. 3. it is not.
        let input = year(paying: [("2026-03-02", 150_000_000), ("2026-04-01", 60_000_000)])

        #expect(computationPage(input, asOf: "2026-03-31").thresholds.bars[0].value == "zbývá 500\u{00A0}000")
        #expect(computationPage(input, asOf: "2026-04-01").thresholds.bars[0].value == "dosažen 1.\u{00A0}4.")
    }

    // MARK: The assumptions

    @Test func theAssumptionsNameTheExpenseRateAndHowForeignMoneyIsConverted() {
        let assumptions = computationPage(sample).assumptions

        #expect(
            assumptions.items.prefix(4) == [
                "Zálohy zaplacené v měsíci, ke kterému patří",
                "Bez zaměstnání a jiných zdanitelných příjmů",
                "Plátce DPH měsíčně, výdaje paušálem 60\u{00A0}%",
                "Cizí měny v Kč kurzem ČNB ke dni přijetí platby",
            ])
    }

    @Test func theAssumptionsSayTheMinimumsCountOnlyTheMonthsThroughTheDay() {
        let assumptions = computationPage(sample).assumptions

        #expect(assumptions.items.count == 5)
        #expect(
            assumptions.items.last
                == "Minimální pojistné jen za měsíce hlavní činnosti do data výpočtu – celý rok ukazuje Odhad odvodů")
    }

    // MARK: The tags of the sections

    @Test func theSectionsCarryTheTagsOfTheirHeaders() {
        let page = computationPage(sample)

        #expect(
            page.sections.map(\.tag) == ["11\u{00A0}plateb", "Finanční úřad", "ČSSZ", "VZP", "do 17.\u{00A0}10."])
    }

    @Test func theCountOfThePaymentsIsInTheTagAndNotInTheNoteOfTheFirstRow() throws {
        let income = try #require(computationPage(sample).sections.first)

        #expect(income.rows.first?.note == "1.\u{00A0}1. – 17.\u{00A0}10. · cizí měny v Kč ke dni přijetí")
    }

    // MARK: The page

    @Test func thePageHasTheFiveCardsOfTheBreakdownAndTheCardsAroundThem() {
        let page = computationPage(sample)
        let result = TaxEngine.compute(sample, asOf: civilDate("2026-10-17"))

        #expect(
            page.sections
                == ComputationBuilder.build(
                    result, input: sample, today: civilDate("2026-10-17"), incomeFXMethod: .cnbDaily))
        #expect(
            page.sections.map(\.title) == [
                "Příjmy a zisk", "Daň z příjmů", "Sociální pojištění", "Zdravotní pojištění", "Čistý příjem",
            ])
        #expect(page.year == 2026)
        #expect(!page.banner.isEmpty)
        #expect(page.equation.tiles.count == 4)
        #expect(page.marginal.shares.count == 3)
        #expect(page.thresholds.bars.count == 3)
        #expect(page.assumptions.items.count == 5)
    }

    // MARK: Whatever the year

    @Test func everyCardOfEveryYearAgreesWithTheEngine() {
        for scenario in computationGrid() {
            check(scenario)
        }
    }

    /// Builds the page of `scenario` and compares what the cards say with the result of the engine.
    private func check(_ scenario: ComputationScenario) {
        let input = scenario.input
        let result = TaxEngine.compute(input, asOf: civilDate(scenario.asOf))
        let page = ComputationBuilder.buildPage(
            result, input: input, today: civilDate("2026-10-17"), incomeFXMethod: .cnbDaily)
        let isOver = scenario.isOver
        let context = "\(input.year) \(scenario.asOf) \(input.expensePercent) % \(input.receipts.count)"
        #expect(page.year == input.year, "\(context)")

        // The banner.
        #expect(
            page.banner.hasPrefix(isOver ? "Rok \(input.year) celý:" : "Počítáno jen ze skutečně přijatých plateb od"),
            "\(context)")
        #expect(
            page.banner.hasSuffix(isOver ? "za celý rok." : "jen za uplynulé měsíce hlavní činnosti."), "\(context)")

        // The equation.
        let remaining = Authority.allCases.map { CzechFormat.grouped(result.balance($0).remaining) }
        #expect(Array(page.equation.tiles.map(\.value).prefix(3)) == remaining, "\(context)")
        #expect(page.equation.tiles.last?.value == CzechFormat.wholeKc(result.remainingTotal), "\(context)")
        #expect(page.equation.tiles.last?.isResult == true, "\(context)")
        #expect(page.equation.heading.hasPrefix(isOver ? "Doplatek za rok" : "Zbývá zaplatit k"), "\(context)")
        if isOver {
            #expect(page.equation.split.contains(CzechFormat.wholeKc(result.advancesPaidTotal)), "\(context)")
            #expect(page.equation.split.contains("přeplatky") == (result.overpaymentTotal > 0), "\(context)")
        } else {
            #expect(page.equation.split.contains(CzechFormat.wholeKc(result.leavesViaPlannedAdvances)), "\(context)")
            #expect(page.equation.split.contains(CzechFormat.wholeKc(result.settlementTotal)), "\(context)")
        }

        // The marginal levy: the shares fill the bar, or it is empty.
        #expect(page.marginal.total == CzechFormat.percent(result.marginalTotal), "\(context)")
        #expect(page.marginal.shares.map(\.authority) == Authority.allCases, "\(context)")
        let fractions = page.marginal.shares.map(\.fraction)
        #expect(fractions.allSatisfy { (0...1).contains($0) }, "\(context)")
        #expect(
            isClose(fractions.reduce(0, +), result.marginalTotal > 0 ? 1 : 0), "\(context) \(fractions)")
        // The parts in the sentence add up to the total in it, to the hundredth.
        let shown = hundredths(in: page.marginal.text)
        #expect(shown.count == 4, "\(context) \(page.marginal.text)")
        #expect(shown.dropFirst().reduce(0, +) == shown.first, "\(context) \(page.marginal.text)")
        let total = CzechFormat.rate(result.marginalTotal * 100, fractionDigits: 2)
        #expect(page.marginal.text.contains("odvedete \(total)\u{00A0}Kč"), "\(context)")
        // Each part is the engine's rate to the hundredth, or the next hundredth where the sum needed it.
        for (index, authority) in Authority.allCases.enumerated() where shown.count == 4 {
            let exact = (result.marginal[authority] ?? 0) * 10_000
            let part = Decimal(shown[index + 1])
            #expect(abs(NSDecimalNumber(decimal: part - exact).doubleValue) < 1, "\(context) \(authority)")
        }

        // The thresholds.
        let capIncome = result.expenseCap * 100 / Int64(input.expensePercent)
        let bars = page.thresholds.bars
        #expect(bars.count == 3, "\(context)")
        #expect(bars.allSatisfy { (0...1).contains($0.fraction) }, "\(context)")
        #expect(bars[0].isReached == (result.P >= capIncome), "\(context)")
        // The note of the expenses and the bar agree on whether the cap is reached.
        #expect(bars[0].isReached == (result.uncappedExpenses >= result.expenseCap), "\(context)")
        #expect(bars.map(\.isHighlighted) == [bars[0].isReached, false, false], "\(context)")
        #expect(
            bars[0].value.hasPrefix(
                bars[0].isReached ? "dosažen " : "zbývá \(CzechFormat.grouped(capIncome - result.P))"),
            "\(context)")
        #expect(bars[1].isReached == (result.B > result.rules.taxBandThreshold), "\(context)")
        #expect(
            bars[1].value
                == (bars[1].isReached
                    ? "překročeno" : "zbývá \(CzechFormat.grouped(result.rules.taxBandThreshold - result.B))"),
            "\(context)")
        #expect(bars[2].isReached == (result.social.base >= result.social.maximumBase), "\(context)")
        #expect(
            bars[2].value
                == (bars[2].isReached
                    ? "dosažen" : "zbývá \(CzechFormat.grouped(result.social.maximumBase - result.social.base))"),
            "\(context)")
        #expect(page.thresholds.heading == "Hranice roku \(input.year)", "\(context)")

        // The assumptions and the tags.
        #expect(page.assumptions.items[2].hasSuffix("\(input.expensePercent)\u{00A0}%"), "\(context)")
        #expect(page.sections.first?.tag?.contains("plat") == true, "\(context)")
    }
}
