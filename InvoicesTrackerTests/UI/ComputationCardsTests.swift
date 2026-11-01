import Foundation
import Testing
@testable import InvoicesTracker

/// The rest of the page of Výpočet that the builder makes from the result of the tax engine, besides the sections: the
/// banner about the day the computation counts up to, the key figure of what is left to pay, the levy bar of Přehled,
/// the marginal levy, the thresholds of the year, the assumptions, and the tags of the sections. The sample year is the
/// engine's regression year as of 17. 10. 2026; its figures and those of the other years were worked out for the same
/// data by a separate implementation of the rules (exact fractions, run in Python). In every expected string
/// `\u{00A0}` is the no-break space.
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

    /// The part of the levy bar `levies` that is of `authority`, or a failure of the test where the bar has none.
    private func part(of authority: Authority, in levies: LevyBarData) throws -> LevyBarPart {
        try #require(levies.parts.first { $0.authority == authority }, "The bar has no part of \(authority)")
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

    // MARK: The key figure

    /// What the key figure says after what is left to pay: only positive balances are added.
    private let onlyPositiveBalances =
        " Sčítají se jen kladné zůstatky – přeplatek u jednoho úřadu nezaplatí dluh u jiného."

    @Test func theKeyFigureAddsWhatEachAuthorityStillHasToGetAndSaysWhereItGoes() {
        let keyFigure = computationPage(sample).keyFigure

        #expect(keyFigure.eyebrow == "Zbývá zaplatit k 17.\u{00A0}10.\u{00A0}2026")
        #expect(keyFigure.figure == "110\u{00A0}844\u{00A0}Kč")
        #expect(keyFigure.share == nil)
        #expect(keyFigure.sentenceEmphasis == nil)
        #expect(
            keyFigure.sentence
                == "Z toho 53\u{00A0}685\u{00A0}Kč odejde naplánovanými zálohami do konce roku"
                + " a 57\u{00A0}159\u{00A0}Kč doplatíte po podání přiznání a přehledů." + onlyPositiveBalances)
    }

    @Test func withoutIncomeEachAuthorityStillWantsItsMinimum() {
        // Nothing is received, so there is no tax; the insurances are the minimums of ten months. The figure is the
        // whole of the part that is paid after the return, and the sentence says "0 Kč" as it stands.
        let keyFigure = computationPage(computationYearInput()).keyFigure

        #expect(keyFigure.figure == "83\u{00A0}099\u{00A0}Kč")
        #expect(
            keyFigure.sentence
                == "Z toho 0\u{00A0}Kč odejde naplánovanými zálohami do konce roku"
                + " a 83\u{00A0}099\u{00A0}Kč doplatíte po podání přiznání a přehledů." + onlyPositiveBalances)
    }

    @Test func aYearThatIsOverSaysWhatIsDueAndWhatTheAdvancesPaid() {
        // A payment of 4 500 Kč in 2025: no tax, social insurance 57 098 Kč and health insurance 37 712 Kč.
        let keyFigure = computationPage(
            computationYearInput(year: 2025, netHalere: 450_000, vatHalere: 94_500), asOf: "2025-12-31"
        ).keyFigure

        #expect(keyFigure.eyebrow == "Doplatek za rok 2025")
        #expect(keyFigure.figure == "94\u{00A0}810\u{00A0}Kč")
        #expect(keyFigure.sentence == "Zálohami se za rok zaplatilo 0\u{00A0}Kč." + onlyPositiveBalances)
    }

    @Test func aYearThatIsOverSaysThatOverpaymentsAreReturned() {
        // 10 000 Kč of income tax advances were paid in March, and the tax is 0 Kč.
        var advances = AdvancePlan.empty
        advances.tax[2] = 10_000
        let keyFigure = computationPage(
            computationYearInput(year: 2025, netHalere: 450_000, vatHalere: 94_500, advances: advances),
            asOf: "2025-12-31"
        ).keyFigure

        #expect(keyFigure.figure == "94\u{00A0}810\u{00A0}Kč")
        #expect(
            keyFigure.sentence
                == "Zálohami se za rok zaplatilo 10\u{00A0}000\u{00A0}Kč,"
                + " přeplatky 10\u{00A0}000\u{00A0}Kč se vrací." + onlyPositiveBalances)
    }

    /// The sample family in the whole of 2026, seen from 15. 1. 2027, with 120 000 Kč received on 20. 1. and 130 000 Kč
    /// on 20. 2. and no advances: the children's 37 524 Kč are a bonus, which is not an overpayment of advances.
    @Test func aYearThatIsOverWithABonusAndNoAdvancesSaysWhatComesBackIsTheBonus() {
        let page = computationPage(
            TaxEngineFamilyTests.input(TaxEngineFamilyTests.earlyReceipts), asOf: "2026-12-31", today: "2027-01-15")

        #expect(
            page.keyFigure.sentence
                == "Zálohami se za rok zaplatilo 0\u{00A0}Kč,"
                + " vrátí se 37\u{00A0}524\u{00A0}Kč (z toho daňový bonus 37\u{00A0}524\u{00A0}Kč)."
                + onlyPositiveBalances)
    }

    /// The same family with 10 000 Kč of tax advances paid in January: the bonus comes back with the advances.
    @Test func aYearThatIsOverWithABonusAndAdvancesSaysWhatComesBackAndHowMuchOfItIsTheBonus() {
        var family = TaxEngineFamilyTests.input(TaxEngineFamilyTests.earlyReceipts)
        family.advances.tax[0] = 10_000

        let page = computationPage(family, asOf: "2026-12-31", today: "2027-01-15")

        #expect(
            page.keyFigure.sentence
                == "Zálohami se za rok zaplatilo 10\u{00A0}000\u{00A0}Kč,"
                + " vrátí se 47\u{00A0}524\u{00A0}Kč (z toho daňový bonus 37\u{00A0}524\u{00A0}Kč)."
                + onlyPositiveBalances)
    }

    @Test func aYearThatIsOverShownAsOfAMidYearDaySaysWhatIsLeftAndWhereItGoesLikeAYearInProgress() {
        // A payment of 4 500 Kč in 2025, as of 30. 6. 2025: six months of the minimum insurance, 28 549 Kč of social
        // and 18 856 Kč of health insurance, no tax, and 1 000 Kč of social insurance advances in each month.
        var advances = AdvancePlan.empty
        advances.social = [Int64](repeating: 1_000, count: 12)
        let keyFigure = computationPage(
            computationYearInput(year: 2025, netHalere: 450_000, vatHalere: 94_500, advances: advances),
            asOf: "2025-06-30"
        ).keyFigure

        #expect(keyFigure.eyebrow == "Zbývá zaplatit k 30.\u{00A0}6.\u{00A0}2025")
        #expect(keyFigure.figure == "41\u{00A0}405\u{00A0}Kč")
        #expect(
            keyFigure.sentence
                == "Z toho 6\u{00A0}000\u{00A0}Kč odejde naplánovanými zálohami do konce roku"
                + " a 35\u{00A0}405\u{00A0}Kč doplatíte po podání přiznání a přehledů." + onlyPositiveBalances)
    }

    // MARK: The levy bar

    @Test func theLevyBarOfTheSampleYearIsThatOfPrehled() throws {
        let page = computationPage(sample)
        let result = TaxEngine.compute(sample, asOf: civilDate("2026-10-17"))

        #expect(
            page.levies
                == LevyBarBuilder.balances(
                    of: result, kind: .toDate(isOver: false), header: "Odvody z příjmů do 17.\u{00A0}10.",
                    showsTotal: true))
        // The key figure beside the bar is what is left to pay, not the levies, so the bar shows their total and its
        // share of the income.
        #expect(page.levies.header == "Odvody z příjmů do 17.\u{00A0}10.")
        #expect(page.levies.total == "320\u{00A0}664\u{00A0}Kč")
        #expect(page.levies.totalShare == "14,6\u{00A0}% z příjmů")
        #expect(page.levies.parts.map(\.authority) == [.tax, .social, .health])
        #expect(page.levies.parts.map(\.weight) == [94_440, 159_279, 66_945])
        #expect(
            page.levies.parts.map(\.legendValue) == [
                "94\u{00A0}440\u{00A0}Kč", "159\u{00A0}279\u{00A0}Kč", "66\u{00A0}945\u{00A0}Kč",
            ])
        let rows = page.levies.parts.map { part in part.rows.map { "\($0.label): \($0.value)" } }
        #expect(
            rows == [
                [
                    "Odvody z příjmů: 94\u{00A0}440\u{00A0}Kč", "Zaplaceno zálohami: 23\u{00A0}000\u{00A0}Kč",
                    "Zbývá: 71\u{00A0}440\u{00A0}Kč",
                ],
                [
                    "Odvody z příjmů: 159\u{00A0}279\u{00A0}Kč", "Zaplaceno zálohami: 126\u{00A0}260\u{00A0}Kč",
                    "Zbývá: 33\u{00A0}019\u{00A0}Kč",
                ],
                [
                    "Odvody z příjmů: 66\u{00A0}945\u{00A0}Kč", "Zaplaceno zálohami: 60\u{00A0}560\u{00A0}Kč",
                    "Zbývá: 6\u{00A0}385\u{00A0}Kč",
                ],
            ])
        #expect(
            page.levies.parts.map(\.shareLine) == [
                "4,3\u{00A0}% z příjmů bez DPH", "7,3\u{00A0}% z příjmů bez DPH", "3,0\u{00A0}% z příjmů bez DPH",
            ])
    }

    @Test func theLevyBarOfAYearThatIsOverNamesTheLeviesOfTheYearAndTheDoplatek() throws {
        let page = computationPage(
            computationYearInput(year: 2025, netHalere: 450_000, vatHalere: 94_500), asOf: "2025-12-31")

        #expect(page.levies.header == "Odvody za rok 2025")
        let social = try part(of: .social, in: page.levies)
        #expect(social.rows.map(\.label) == ["Odvody za rok", "Zaplaceno zálohami", "Doplatek"])
        #expect(social.rows.map(\.value) == ["57\u{00A0}098\u{00A0}Kč", "0\u{00A0}Kč", "57\u{00A0}098\u{00A0}Kč"])
        #expect(social.rows.map(\.style) == [.strong, .muted, .strong])
    }

    @Test func aYearInProgressNamesTheLeviesToTheDayAndWhatIsLeft() throws {
        let page = computationPage(computationYearInput(year: 2025), asOf: "2025-06-30")

        #expect(page.levies.header == "Odvody z příjmů do 30.\u{00A0}6.")
        let social = try part(of: .social, in: page.levies)
        #expect(social.rows.map(\.label) == ["Odvody z příjmů", "Zaplaceno zálohami", "Zbývá"])
    }

    @Test func aTaxBonusIsAZeroWidthPartWithTheBonusInTheLegendAndWhatComesBackInGreen() throws {
        // The sample family's children's 37 524 Kč are paid as a bonus: the tax is below zero.
        let page = computationPage(
            TaxEngineFamilyTests.input(TaxEngineFamilyTests.earlyReceipts), asOf: "2026-12-31", today: "2027-01-15")
        let tax = try part(of: .tax, in: page.levies)

        #expect(tax.weight == -37_524)
        #expect(tax.weight < 0)
        #expect(tax.legendValue == "bonus 37\u{00A0}524\u{00A0}Kč")
        #expect(tax.rows.map(\.label) == ["Odvody za rok", "Zaplaceno zálohami", "Vrátí se"])
        #expect(
            tax.rows.map(\.value) == [
                "bonus 37\u{00A0}524\u{00A0}Kč", "0\u{00A0}Kč", "37\u{00A0}524\u{00A0}Kč",
            ])
        #expect(tax.rows.map(\.style) == [.strong, .muted, .positive])
        // The bonus is no levy: it takes nothing of the bar and is counted into the total of the levies as it is.
        #expect(LevyBarLayout.partWidths(weights: page.levies.parts.map(\.weight), width: 400)[0] == 0)
    }

    @Test func anOverpaymentIsInGreenUnderItsNameAndWhatIsLeftIsNot() throws {
        // 10 000 Kč of tax advances against no tax at all: the advances are an overpayment.
        var advances = AdvancePlan.empty
        advances.tax[2] = 10_000
        let page = computationPage(
            computationYearInput(year: 2025, netHalere: 450_000, vatHalere: 94_500, advances: advances),
            asOf: "2025-12-31")

        let tax = try part(of: .tax, in: page.levies)
        #expect(tax.rows.map(\.label) == ["Odvody za rok", "Zaplaceno zálohami", "Přeplatek"])
        #expect(tax.rows.last?.style == .positive)
        #expect(tax.rows.last?.value == "10\u{00A0}000\u{00A0}Kč")
        #expect(try part(of: .social, in: page.levies).rows.last?.style == .strong)
    }

    @Test func withoutIncomeTheLevyBarHasNoShareOfTheIncome() {
        // Nothing is received, so there is no income to take a share of; the minimum insurance is all there is.
        let page = computationPage(computationYearInput())

        #expect(page.levies.total != nil)
        #expect(page.levies.totalShare == nil)
        #expect(page.levies.parts.allSatisfy { $0.shareLine == nil })
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
        // Each part of the bar is the rate itself, 15 %, 16,06 % and 6,75 % of the whole width, so that the three
        // together fill 37,81 % of it, as much as the levy total is of a hundred crowns.
        #expect(isClose(marginal.shares[0].fraction, 0.15))
        #expect(isClose(marginal.shares[1].fraction, 0.1606))
        #expect(isClose(marginal.shares[2].fraction, 0.0675))
        #expect(isClose(marginal.shares.map(\.fraction).reduce(0, +), 0.3781))
    }

    @Test func aHighIncomeHasNoMarginalSocialInsuranceAndTheTopRateOfTax() {
        // 5 700 000 Kč: the social base is at its maximum, the profit is taxed at 23 % and health insurance has none.
        let marginal = computationPage(computationYearInput(netHalere: 570_000_000)).marginal

        #expect(marginal.total == "29,8\u{00A0}%")
        #expect(
            marginal.text
                == "Ze 100\u{00A0}Kč dalšího příjmu bez DPH odvedete 29,75\u{00A0}Kč:"
                + " daň 23,00 · sociální 0,00 · zdravotní 6,75.")
        #expect(isClose(marginal.shares[0].fraction, 0.23))
        #expect(marginal.shares[1].fraction == 0)
        #expect(isClose(marginal.shares[2].fraction, 0.0675))
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
        #expect(isClose(marginal.shares[1].fraction, 0.06424))
        #expect(isClose(marginal.shares[2].fraction, 0.02634))
    }

    @Test func theBarOfTheMarginalLevyHoldsTheRatesExactlyWhileTheTextRoundsThem() {
        // 1 125 000 Kč of income: the rates are 6 %, 6,424 % and 0,022 %. The text rounds them to the hundredth of a
        // crown and gives the largest remainder the hundredth that the sum needs, but the bar is drawn from the rates.
        let marginal = computationPage(computationYearInput(netHalere: 112_500_000)).marginal

        #expect(isClose(marginal.shares[0].fraction, 0.06))
        #expect(isClose(marginal.shares[1].fraction, 0.06424))
        #expect(isClose(marginal.shares[2].fraction, 0.00022))
    }

    @Test func aRateBelowZeroFillsNothingOfTheBarAndOneAboveOneFillsAllOfIt() {
        var result = TaxEngine.compute(sample, asOf: civilDate("2026-10-17"))
        result.marginal[.tax] = decimal("-0.05")
        result.marginal[.social] = decimal("1.5")
        result.marginal[.health] = decimal("0.0675")

        let shares = ComputationBuilder.marginal(of: result).shares

        #expect(shares.map(\.authority) == [.tax, .social, .health])
        #expect(shares[0].fraction == 0)
        #expect(shares[1].fraction == 1)
        #expect(isClose(shares[2].fraction, 0.0675))
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
        #expect(!page.keyFigure.figure.isEmpty)
        #expect(page.levies.parts.count == 3)
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

        // The key figure: what is left to pay, said by the sentence that adds only the positive balances.
        let keyFigure = page.keyFigure
        #expect(keyFigure.figure == CzechFormat.wholeKc(result.remainingTotal), "\(context)")
        #expect(keyFigure.eyebrow.hasPrefix(isOver ? "Doplatek za rok" : "Zbývá zaplatit k"), "\(context)")
        #expect(keyFigure.share == nil && keyFigure.sentenceEmphasis == nil, "\(context)")
        let sentence = keyFigure.sentence ?? ""
        #expect(sentence.hasSuffix(onlyPositiveBalances), "\(context)")
        if isOver {
            #expect(sentence.contains(CzechFormat.wholeKc(result.advancesPaidTotal)), "\(context)")
            // A bonus comes back with the advances, and the sentence names it instead of the overpayments.
            let returnsOverpayments = result.overpaymentTotal > 0 && result.childBonus == 0
            #expect(sentence.contains("přeplatky") == returnsOverpayments, "\(context)")
        } else {
            #expect(sentence.contains(CzechFormat.wholeKc(result.leavesViaPlannedAdvances)), "\(context)")
            #expect(sentence.contains(CzechFormat.wholeKc(result.settlementTotal)), "\(context)")
        }

        // The levy bar is the one of Přehled: the levies of each authority, as they are, and their sum.
        let levies = page.levies
        #expect(levies.parts.map(\.authority) == Authority.allCases, "\(context)")
        #expect(levies.parts.map(\.weight) == Authority.allCases.map { result.balance($0).liability }, "\(context)")
        #expect(levies.total == CzechFormat.wholeKc(result.liabilityTotal), "\(context)")
        let day = BuilderText.date(result.asOf, omittingYear: input.year)
        #expect(levies.header == (isOver ? "Odvody za rok \(input.year)" : "Odvody z příjmů do " + day), "\(context)")
        let lastRows = Authority.allCases.map { authority in
            let balance = result.balance(authority)
            if balance.overpayment > 0 {
                return balance.liability < 0 ? "Vrátí se" : "Přeplatek"
            }
            return isOver ? "Doplatek" : "Zbývá"
        }
        #expect(levies.parts.map { $0.rows.last?.label } == lastRows, "\(context)")

        // The marginal levy: each part of the bar is the rate of its authority, 0 to 1 of the whole width, so that the
        // parts fill as much of the bar as the levy total is of a hundred crowns.
        #expect(page.marginal.total == CzechFormat.percent(result.marginalTotal), "\(context)")
        #expect(page.marginal.shares.map(\.authority) == Authority.allCases, "\(context)")
        let fractions = page.marginal.shares.map(\.fraction)
        let rates = Authority.allCases.map { NSDecimalNumber(decimal: result.marginal[$0] ?? 0).doubleValue }
        #expect(fractions.allSatisfy { (0...1).contains($0) }, "\(context)")
        for (fraction, rate) in zip(fractions, rates) {
            #expect(isClose(fraction, min(1, max(0, rate))), "\(context) \(fractions) \(rates)")
        }
        if rates.allSatisfy({ $0 >= 0 }) {
            let total = NSDecimalNumber(decimal: result.marginalTotal).doubleValue
            #expect(isClose(fractions.reduce(0, +), total), "\(context) \(fractions) \(total)")
        }
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
