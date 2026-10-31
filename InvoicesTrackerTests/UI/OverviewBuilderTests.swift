import Foundation
import Testing
@testable import InvoicesTracker

/// What Přehled shows, as the builder works it out from a computed year. In every expected string `\u{00A0}` is the
/// no-break space.
struct OverviewBuilderTests {
    // MARK: Helpers

    /// The sample year of the engine's regression test as of a day.
    private func sampleResult(asOf day: String = "2026-10-17") -> TaxResult {
        TaxEngine.compute(TaxEngineRegressionTests.sampleYear2026, asOf: civilDate(day))
    }

    private func usd(_ rate: String) -> ExchangeRate {
        ExchangeRate(currency: .usd, amount: 1, rate: decimal(rate))
    }

    /// A row of the chart. Amounts are in minor units of the currency, and the payment in haléře.
    private func chartRow(
        id: Int64, issued: String, currency: CurrencyCode = .czk, net: Int64, vat: Int64 = 0,
        draft: Bool = false, inReview: Bool = false, paidOn: String? = nil, paymentNet: Int64? = nil,
        paymentVat: Int64? = nil, issueDayRate: ExchangeRate? = nil
    ) -> InvoiceChartRow {
        InvoiceChartRow(
            id: id, issueDate: civilDate(issued), isDraft: draft, inReview: inReview, currency: currency,
            netMinor: net, vatMinor: vat, paymentDate: paidOn.map(civilDate), paymentNetHalere: paymentNet,
            paymentVatHalere: paymentVat, issueDayRate: issueDayRate
        )
    }

    /// The paid dollar invoice of September (14 350,00 USD, 305 726,75 Kč on 2. 10.), the paid crown invoice of
    /// September (4 500,00 Kč and 945,00 Kč VAT, paid on 15. 10.) and a draft of October.
    private var sampleChartRows: [InvoiceChartRow] {
        [
            chartRow(
                id: 10, issued: "2026-09-30", currency: .usd, net: 1_435_000, paidOn: "2026-10-02",
                paymentNet: 30_572_675, paymentVat: 0, issueDayRate: usd("21.359")),
            chartRow(
                id: 11, issued: "2026-09-30", net: 450_000, vat: 94_500, paidOn: "2026-10-15",
                paymentNet: 450_000, paymentVat: 94_500),
            chartRow(
                id: 12, issued: "2026-10-16", currency: .usd, net: 1_204_000, draft: true,
                issueDayRate: usd("21.622")),
        ]
    }

    /// The VAT of the months of 2026 in haléře: the invoices of Alfa Systems of January to May, the crown invoices of
    /// August and September, nothing since.
    private let sampleVAT: [Int64] = [
        4_158_000, 3_402_000, 3_780_000, 3_780_000, 3_780_000, 0, 0, 94_500, 94_500, 0, 0, 0,
    ]

    private func effect(total: Int64, on day: String = "2026-10-15") -> ReceiptEffect {
        ReceiptEffect(
            receipt: Receipt(day: civilDate(day), czkNetHalere: 0, czkVatHalere: 0, source: .synthetic),
            tax: total, social: 0, health: 0, total: total
        )
    }

    /// The input of the builder. Unless a test gives a result, 2026 is the sample year of the engine's regression test
    /// and any other year is a year without receipts and advances.
    private func input(
        year: Int = 2026, asOf: String = "2026-10-17", today todayText: String = "2026-10-17",
        result: TaxResult? = nil, advances: AdvancePlan? = nil,
        latestReceipts: [(invoice: Invoice, effect: ReceiptEffect)] = [], chartMode: ChartMode = .months,
        chartWithVAT: Bool = false, chartRows: [InvoiceChartRow] = [], chartYears: [Int] = [2024, 2025, 2026],
        vatByMonth: [Int64]? = nil, vatToCheckMonths: Set<Int> = [], foreignCurrencies: [CurrencyCode] = [],
        uniformRates: [UniformRate] = [], yearsAtUniformRate: Set<Int> = [], prediction: PredictionOutcome? = nil,
        netIncomeResults: [Int: TaxResult] = [:], invoicePaymentEffects: [ReceiptEffect] = []
    ) -> OverviewInput {
        let isSampleYear = year == 2026
        let computed: TaxResult
        if let result {
            computed = result
        } else if isSampleYear {
            computed = sampleResult(asOf: asOf)
        } else {
            computed = TaxEngine.compute(yearInput(year: year, receipts: [], advances: .empty), asOf: civilDate(asOf))
        }
        return OverviewInput(
            year: year, asOf: civilDate(asOf), today: civilDate(todayText), result: computed,
            advances: advances ?? (isSampleYear ? TaxEngineRegressionTests.sampleYear2026.advances : .empty),
            latestReceipts: latestReceipts, chartMode: chartMode, chartWithVAT: chartWithVAT, chartRows: chartRows,
            chartYears: chartYears, vatByMonth: vatByMonth ?? sampleVAT, vatToCheckMonths: vatToCheckMonths,
            foreignCurrencies: foreignCurrencies, uniformRates: uniformRates, yearsAtUniformRate: yearsAtUniformRate,
            prediction: prediction, netIncomeResults: netIncomeResults, invoicePaymentEffects: invoicePaymentEffects
        )
    }

    /// What each payment of an invoice of the prediction sample's 2026 adds to the levies of the year on its own day:
    /// the engine's effect of each receipt of the sample's year whose source is an invoice.
    private var sampleInvoicePaymentEffects: [ReceiptEffect] {
        let year = PredictionSample.yearInput(year: 2026)
        return year.receipts.compactMap { receipt in
            guard case .invoice = receipt.source else { return nil }
            return TaxEngine.effect(of: receipt, in: year)
        }
    }

    /// The input of the chart by months for the prediction sample's 2026: its levies as of `asOf`, the effects of its
    /// payments (`sampleInvoicePaymentEffects`, plus `extraEffects`) and the same invoices as the rows of the chart.
    private func sampleMonthsInput(
        asOf: String = "2026-10-17", today: String = "2026-10-17", extraEffects: [ReceiptEffect] = []
    ) -> OverviewInput {
        let result = TaxEngine.compute(PredictionSample.yearInput(year: 2026), asOf: civilDate(asOf))
        return input(
            asOf: asOf, today: today, result: result, chartRows: SampleYear2026.chartRows,
            invoicePaymentEffects: sampleInvoicePaymentEffects + extraEffects)
    }

    /// A year of main activity at 60 % flat-rate expenses with the taxpayer credit and no deductions.
    private func yearInput(year: Int, receipts: [Receipt], advances: AdvancePlan) -> YearInput {
        YearInput(
            year: year, receipts: receipts, expensePercent: 60,
            months: [MonthActivity](repeating: .main, count: 12), healthExemptMonths: [], deductions: Deductions(),
            taxpayerCredit: true, advances: advances
        )
    }

    private func advances(social: Int64, health: Int64) -> AdvancePlan {
        AdvancePlan(
            social: [Int64](repeating: social, count: 12), health: [Int64](repeating: health, count: 12),
            tax: [Int64](repeating: 0, count: 12))
    }

    /// 2025 with the given receipts, computed to the end of the year, together with the advances it was computed with.
    private func year2025(
        receipts: [Receipt] = [], social: Int64, health: Int64
    ) -> (result: TaxResult, input: OverviewInput) {
        let plan = advances(social: social, health: health)
        let result = TaxEngine.compute(
            yearInput(year: 2025, receipts: receipts, advances: plan), asOf: civilDate("2025-12-31"))
        return (result, input(year: 2025, asOf: "2025-12-31", result: result, advances: plan))
    }

    /// 2021 with the given receipts, computed to the end of the year. 2021 is before the oldest year the app has rules
    /// for, so the engine works it out with the rules of 2022 (`TaxResult.rulesAreEstimate`).
    private func result2021(receipts: [Receipt]) -> TaxResult {
        TaxEngine.compute(yearInput(year: 2021, receipts: receipts, advances: .empty), asOf: civilDate("2021-12-31"))
    }

    /// The only payment of a 2021 that is worth 1 000 000 Kč without VAT, received on 30. 6. 2021.
    private var millionCrownsOf2021: Receipt {
        Receipt(day: civilDate("2021-06-30"), czkNetHalere: 100_000_000, czkVatHalere: 0, source: .synthetic)
    }

    /// The sentence that says 2021 is computed with the rules of 2022, as every screen words it.
    private let sentenceOf2021 = "Pravidla pro rok 2021 zatím nejsou v aplikaci – výpočet je odhad podle roku 2022."

    private func build(_ input: OverviewInput) -> OverviewData {
        OverviewBuilder.build(input)
    }

    // MARK: The key figure

    @Test func theSampleYearShowsWhatIsLeftToPayAsOfTheChosenDay() {
        let data = build(input())

        #expect(data.keyFigure.eyebrow == "Zbývá zaplatit")
        #expect(data.keyFigure.figure == "110\u{00A0}844\u{00A0}Kč")
        #expect(
            data.keyFigure.sentence
                == "Odvody z příjmů od 1.\u{00A0}1. do 17.\u{00A0}10.\u{00A0}2026"
                + " po odečtení záloh za leden až říjen.")
        // What is left to pay is not the levies: their total and their share of the income stand with the bar, and no
        // part of the sentence is set apart.
        #expect(data.keyFigure.share == nil)
        #expect(data.keyFigure.sentenceEmphasis == nil)
        #expect(data.levies.total == "320\u{00A0}664\u{00A0}Kč")
        #expect(data.levies.header == "Odvody z příjmů do 17.\u{00A0}10.")
    }

    @Test func aChosenDayAfterTheStartOfTheYearNamesTheLastMonthOfAdvancesThatCount() {
        let data = build(input(asOf: "2026-09-30"))

        #expect(
            data.keyFigure.sentence
                == "Odvody z příjmů od 1.\u{00A0}1. do 30.\u{00A0}9.\u{00A0}2026"
                + " po odečtení záloh za leden až září.")
        #expect(data.levies.header == "Odvody z příjmů do 30.\u{00A0}9.")
    }

    @Test func theHeadingLeavesOutTheYearOfTheSelectedYearWhateverTodayIs() {
        // A simulation in the year after the current one: the year is the one of the screen, so the header of the bar
        // does not repeat it, while the sentence under the amount always writes the day with its year.
        let data = build(input(year: 2027, asOf: "2027-03-31"))

        #expect(data.levies.header == "Odvody z příjmů do 31.\u{00A0}3.")
        let sentence = data.keyFigure.sentence ?? ""
        #expect(sentence.contains("do 31.\u{00A0}3.\u{00A0}2027 po odečtení"))
        #expect(sentence.hasSuffix("za leden až březen."))
    }

    // MARK: January

    @Test func inJanuaryTheSentenceNamesJanuaryOnceAndInLaterMonthsTheMonthsFromJanuary() {
        let january = build(input(asOf: "2026-01-15")).keyFigure
        let february = build(input(asOf: "2026-02-03")).keyFigure
        let december = build(input(asOf: "2026-12-31")).keyFigure

        #expect(
            january.sentence
                == "Odvody z příjmů od 1.\u{00A0}1. do 15.\u{00A0}1.\u{00A0}2026 po odečtení záloh za leden.")
        #expect(
            february.sentence
                == "Odvody z příjmů od 1.\u{00A0}1. do 3.\u{00A0}2.\u{00A0}2026"
                + " po odečtení záloh za leden až únor.")
        #expect(december.sentence?.hasSuffix("po odečtení záloh za leden až prosinec.") == true)
    }

    // MARK: The levy bar

    /// The bar of Přehled is the one the shared builder makes of the balances of the year, as Výpočet makes it: the
    /// header names the day, the total and its share stand in the header because the key figure is not the levies, and
    /// a year in progress words the last row of each popover "Zbývá".
    @Test func theLevyBarIsThatOfTheSharedBuilderForTheBalancesOfTheYear() {
        let overview = input()

        let data = build(overview)

        #expect(
            data.levies
                == LevyBarBuilder.balances(
                    of: overview.result, kind: .toDate(isOver: false), header: "Odvody z příjmů do 17.\u{00A0}10.",
                    showsTotal: true))
        #expect(data.levies.parts.map { $0.rows.last?.label } == ["Zbývá", "Zbývá", "Zbývá"])
    }

    /// A year that is over words the bar by the year, and the last row of each popover "Doplatek".
    @Test func theLevyBarOfAYearThatIsOverNamesTheYearAndTheDoplatek() {
        let (result, overview) = year2025(social: 10_000, health: 6_000)

        let data = build(overview)

        #expect(
            data.levies
                == LevyBarBuilder.balances(
                    of: result, kind: .toDate(isOver: true), header: "Odvody za rok 2025", showsTotal: true))
        #expect(data.levies.parts.map { $0.rows.first?.label } == ["Odvody za rok", "Odvody za rok", "Odvody za rok"])
    }

    /// Přehled and Výpočet show one bar: for the same year as of the same day the two builders make equal data, in a
    /// year in progress and in a year that is over.
    @Test func theLevyBarIsTheOneVypocetShowsForTheSameYearAndDay() {
        let today = civilDate("2026-10-17")
        let current = TaxEngineRegressionTests.sampleYear2026
        let currentResult = TaxEngine.compute(current, asOf: today)
        let currentPage = ComputationBuilder.buildPage(
            currentResult, input: current, today: today, incomeFXMethod: .cnbDaily)
        #expect(build(input(result: currentResult)).levies == currentPage.levies)

        let past = PredictionSample.yearInput(year: 2025)
        let pastResult = TaxEngine.compute(past, asOf: civilDate("2025-12-31"))
        let pastPage = ComputationBuilder.buildPage(pastResult, input: past, today: today, incomeFXMethod: .cnbDaily)
        #expect(build(input(year: 2025, asOf: "2025-12-31", result: pastResult)).levies == pastPage.levies)
    }

    @Test func eachAuthorityGetsAPartWithWhatTheAdvancesPaidAndWhatRemains() {
        let parts = build(input()).levies.parts

        #expect(parts.map(\.authority) == [.tax, .social, .health])
        #expect(parts.map(\.weight) == [94_440, 159_279, 66_945])
        #expect(
            parts.map(\.legendValue) == [
                "94\u{00A0}440\u{00A0}Kč", "159\u{00A0}279\u{00A0}Kč", "66\u{00A0}945\u{00A0}Kč",
            ])
        // The levy, the advances of January through October and what is left of the levy.
        #expect(
            parts[0].rows == [
                LevyPopoverRow(label: "Odvody z příjmů", value: "94\u{00A0}440\u{00A0}Kč", style: .strong),
                LevyPopoverRow(label: "Zaplaceno zálohami", value: "23\u{00A0}000\u{00A0}Kč", style: .muted),
                LevyPopoverRow(label: "Zbývá", value: "71\u{00A0}440\u{00A0}Kč", style: .strong),
            ])
        #expect(
            parts[1].rows == [
                LevyPopoverRow(label: "Odvody z příjmů", value: "159\u{00A0}279\u{00A0}Kč", style: .strong),
                LevyPopoverRow(label: "Zaplaceno zálohami", value: "126\u{00A0}260\u{00A0}Kč", style: .muted),
                LevyPopoverRow(label: "Zbývá", value: "33\u{00A0}019\u{00A0}Kč", style: .strong),
            ])
        #expect(
            parts[2].rows == [
                LevyPopoverRow(label: "Odvody z příjmů", value: "66\u{00A0}945\u{00A0}Kč", style: .strong),
                LevyPopoverRow(label: "Zaplaceno zálohami", value: "60\u{00A0}560\u{00A0}Kč", style: .muted),
                LevyPopoverRow(label: "Zbývá", value: "6\u{00A0}385\u{00A0}Kč", style: .strong),
            ])
    }

    /// The tax of 94 440 Kč is 4,3 % of the income of 2 191 771 Kč, and VoiceOver reads that with the rows of its item
    /// of the legend, and the bar as a picture named by its three parts.
    @Test func theLevyBarSpeaksForVoiceOverWithTheSameNumbers() {
        let levies = build(input()).levies

        #expect(
            levies.accessibilityLabel
                == "Odvody z příjmů do 17.\u{00A0}10.: Daň z příjmů 94\u{00A0}440\u{00A0}Kč,"
                + " Sociální pojištění 159\u{00A0}279\u{00A0}Kč, Zdravotní pojištění 66\u{00A0}945\u{00A0}Kč")
        #expect(
            levies.parts[0].accessibilityLabel
                == "Daň z příjmů: odvody z příjmů 94\u{00A0}440\u{00A0}Kč, zaplaceno zálohami 23\u{00A0}000\u{00A0}Kč,"
                + " zbývá 71\u{00A0}440\u{00A0}Kč, 4,3\u{00A0}% z příjmů bez DPH")
    }

    @Test func advancesAboveTheLevyShowAnOverpaymentAndNothingOwedShowsNothingToPay() {
        let (result, overview) = year2025(social: 10_000, health: 6_000)
        let parts = build(overview).levies.parts

        let social = result.balance(.social)
        #expect(social.overpayment > 0)
        #expect(
            parts[1].rows == [
                LevyPopoverRow(
                    label: "Odvody za rok", value: CzechFormat.wholeKc(social.liability), style: .strong),
                LevyPopoverRow(label: "Zaplaceno zálohami", value: "120\u{00A0}000\u{00A0}Kč", style: .muted),
                LevyPopoverRow(
                    label: "Přeplatek", value: CzechFormat.wholeKc(social.overpayment), style: .positive),
            ])

        // No income, so no tax and no tax advances: nothing is owed and nothing remains, in the words of a year that
        // is over, and the part has no width in the bar.
        #expect(parts[0].weight == 0)
        #expect(parts[0].legendValue == "0\u{00A0}Kč")
        #expect(
            parts[0].rows == [
                LevyPopoverRow(label: "Odvody za rok", value: "0\u{00A0}Kč", style: .strong),
                LevyPopoverRow(label: "Zaplaceno zálohami", value: "0\u{00A0}Kč", style: .muted),
                LevyPopoverRow(label: "Doplatek", value: "0\u{00A0}Kč", style: .strong),
            ])
    }

    /// Přehled as of 28. 2. 2026 for the sample family with 120 000 Kč received on 20. 1. and 130 000 Kč on 20. 2., and
    /// a tax advance of 10 000 Kč paid in January: the children's 37 524 Kč are a bonus.
    private func inputWithABonus() -> OverviewInput {
        var family = TaxEngineFamilyTests.input(TaxEngineFamilyTests.earlyReceipts)
        family.advances.tax[0] = 10_000
        let result = TaxEngine.compute(family, asOf: civilDate("2026-02-28"))
        return input(asOf: "2026-02-28", result: result, advances: family.advances)
    }

    /// In `inputWithABonus()` the part of the tax is a bonus: its weight is below zero, so the bar draws no part for
    /// it, the legend reads the bonus where the tax would be, and the tax office returns the advance with it,
    /// 47 524 Kč, which the last row of its popover names "Vrátí se" in green. The bonus is a negative part of the
    /// income of 250 000 Kč, and VoiceOver reads it so.
    @Test func aBonusIsAPartBelowZeroThatReadsBonusAndComesBack() {
        let tax = build(inputWithABonus()).levies.parts[0]

        #expect(tax.weight == -37_524)
        #expect(tax.weight < 0)
        #expect(tax.legendValue == "bonus 37\u{00A0}524\u{00A0}Kč")
        #expect(
            tax.rows == [
                LevyPopoverRow(label: "Odvody z příjmů", value: "bonus 37\u{00A0}524\u{00A0}Kč", style: .strong),
                LevyPopoverRow(label: "Zaplaceno zálohami", value: "10\u{00A0}000\u{00A0}Kč", style: .muted),
                LevyPopoverRow(label: "Vrátí se", value: "47\u{00A0}524\u{00A0}Kč", style: .positive),
            ])
        #expect(tax.shareLine == "\u{2212}15,0\u{00A0}% z příjmů bez DPH")
        #expect(
            tax.accessibilityLabel
                == "Daň z příjmů: odvody z příjmů bonus 37\u{00A0}524\u{00A0}Kč,"
                + " zaplaceno zálohami 10\u{00A0}000\u{00A0}Kč, vrátí se 47\u{00A0}524\u{00A0}Kč,"
                + " \u{2212}15,0\u{00A0}% z příjmů bez DPH")
    }

    /// As of 31. 1. the same family has 120 000 Kč of income, below the six minimum wages that pay the bonus. What the
    /// next crown costs leaves the bonus as it is, so it is the 9,1 % of the insurances, not the bonus that 100 000 Kč
    /// more would bring at once.
    @Test func theNextCrownLeavesTheBonusAsItIs() {
        let family = TaxEngineFamilyTests.input(TaxEngineFamilyTests.earlyReceipts)
        let result = TaxEngine.compute(family, asOf: civilDate("2026-01-31"))

        let tiles = build(input(asOf: "2026-01-31", result: result, advances: family.advances)).tiles

        #expect(tiles[2].label == "Mezní odvod")
        #expect(tiles[2].figure == "9,1\u{00A0}%")
    }

    /// The tax after the credits as every screen writes it: in crowns, and as the bonus it is while it is below zero.
    @Test func theTaxAfterTheCreditsIsABonusWhileItIsBelowZero() {
        #expect(BuilderText.taxOrBonus(94_440) == "94\u{00A0}440\u{00A0}Kč")
        #expect(BuilderText.taxOrBonus(0) == "0\u{00A0}Kč")
        #expect(BuilderText.taxOrBonus(-37_524) == "bonus 37\u{00A0}524\u{00A0}Kč")
    }

    // MARK: The shares of the levies

    /// The sample year of the prediction as of 17. 10. 2026: the three levies take 11,8 % of the income, the tax 1,5 %,
    /// the social insurance 7,3 % and the health insurance 3,0 %, which add up to the 11,8 %. The header of the bar
    /// says the first beside its total and the popover of each part the share of its authority, and VoiceOver reads it
    /// with the rows of the item of the legend.
    @Test func theSharesOfTheLeviesAreOfTheIncome() {
        let result = TaxEngine.compute(PredictionSample.yearInput(year: 2026), asOf: civilDate("2026-10-17"))

        let levies = build(input(result: result)).levies

        #expect(levies.totalShare == "11,8\u{00A0}% z příjmů")
        #expect(
            levies.parts.map(\.shareLine) == [
                "1,5\u{00A0}% z příjmů bez DPH", "7,3\u{00A0}% z příjmů bez DPH", "3,0\u{00A0}% z příjmů bez DPH",
            ])
        let label = levies.parts[0].accessibilityLabel
        #expect(
            label.hasPrefix("Daň z příjmů: odvody z příjmů 32\u{00A0}076\u{00A0}Kč, zaplaceno zálohami "), "\(label)")
        #expect(label.hasSuffix("1,5\u{00A0}% z příjmů bez DPH"), "\(label)")
    }

    /// With the bonus of `inputWithABonus()` the tax is below zero, and so is its part of the income of 250 000 Kč: the
    /// bonus is 15,0 % of it. The share is shown as it is, with the minus sign, and so is the share of the three
    /// levies, which the bonus takes below zero.
    @Test func aTaxBonusHasANegativeShare() {
        let levies = build(inputWithABonus()).levies

        #expect(levies.parts[0].shareLine == "\u{2212}15,0\u{00A0}% z příjmů bez DPH")
        #expect(levies.totalShare == "\u{2212}5,9\u{00A0}% z příjmů")
    }

    /// A year without income has nothing for the levies to take a part of, though the insurance has a minimum: no
    /// share is shown, and VoiceOver reads the items of the legend without one.
    @Test func withoutIncomeNoShareIsShown() {
        let levies = build(input(year: 2025, asOf: "2025-12-31")).levies

        #expect(levies.totalShare == nil)
        #expect(levies.parts.map(\.shareLine) == [nil, nil, nil])
        for part in levies.parts {
            #expect(!part.accessibilityLabel.contains("bez DPH"), "\(part.accessibilityLabel)")
        }
    }

    // MARK: The tiles under the key figure

    @Test func theTilesAreWhatTheAdvancesStillPayWhatTheReturnsPayAndTheNextCrown() {
        let tiles = build(input()).tiles

        #expect(
            tiles == [
                FigureTileData(
                    label: "Odejde zálohami", figure: "53\u{00A0}685\u{00A0}Kč", note: "do konce roku podle plánu"),
                FigureTileData(
                    label: "Doplatek", figure: "57\u{00A0}159\u{00A0}Kč", note: "s přiznáním a přehledy za rok 2026"),
                FigureTileData(label: "Mezní odvod", figure: "37,8\u{00A0}%", note: "z další koruny příjmu"),
            ])
    }

    /// With no advance left to plan nothing leaves by them, and the whole of what is left is paid with the return and
    /// the overviews: the first tile reads 0 Kč and the second the figure of the card, as the design draws them.
    @Test func withNoAdvancesLeftToPlanNothingLeavesAndTheDoplatekIsTheKeyFigure() {
        let data = build(input(asOf: "2026-12-31", today: "2026-12-31"))

        #expect(data.tiles.map(\.label) == ["Odejde zálohami", "Doplatek", "Mezní odvod"])
        #expect(data.tiles[0].figure == "0\u{00A0}Kč")
        #expect(data.tiles[1].figure == data.keyFigure.figure)
    }

    // MARK: Past years

    @Test func aPastYearWithNothingLeftSaysEverythingIsCoveredAndNamesTheOverpayment() {
        let (result, overview) = year2025(social: 10_000, health: 6_000)
        #expect(result.remainingTotal == 0)
        #expect(result.overpaymentTotal > 0)

        let data = build(overview)
        let over = CzechFormat.wholeKc(result.overpaymentTotal)

        #expect(data.keyFigure.eyebrow == "Vše pokryto zálohami")
        #expect(data.keyFigure.figure == "0\u{00A0}Kč")
        #expect(data.levies.total == CzechFormat.wholeKc(result.liabilityTotal))
        #expect(
            data.keyFigure.sentence
                == "Odvody za celý rok 2025 po odečtení všech záloh. "
                + "U některého úřadu zálohy převýšily povinnost o " + over + " – ten přeplatek se vrací.")
        #expect(data.levies.header == "Odvody za rok 2025")
        #expect(
            data.tiles == [
                FigureTileData(
                    label: "Zaplaceno zálohami", figure: CzechFormat.wholeKc(result.advancesPaidTotal),
                    note: "za celý rok 2025"),
                FigureTileData(label: "Doplatek", figure: "0\u{00A0}Kč", note: "s přiznáním a přehledy"),
                FigureTileData(label: "Přeplatky", figure: over, note: "vrací se po přehledech"),
            ])
    }

    /// The sample family in the whole of 2026, seen from 15. 1. 2027, with 120 000 Kč received on 20. 1. and
    /// 130 000 Kč on 20. 2. and `taxAdvance` paid to the tax office in January: the children's 37 524 Kč are a bonus,
    /// which comes back with the advances that the tax and the insurances did not need.
    private func finishedYearWithABonus(taxAdvance: Int64) -> (result: TaxResult, overview: OverviewInput) {
        var family = TaxEngineFamilyTests.input(TaxEngineFamilyTests.earlyReceipts)
        family.advances.tax[0] = taxAdvance
        let result = TaxEngine.compute(family, asOf: civilDate("2026-12-31"))
        return (
            result,
            input(asOf: "2026-12-31", today: "2027-01-15", result: result, advances: family.advances)
        )
    }

    /// The bonus is not an overpayment of advances: a finished year with a bonus and no advances says what comes back
    /// and that it is the bonus, and the part of the tax is a bonus whose last row is "Vrátí se".
    @Test func aFinishedYearWithABonusAndNoAdvancesSaysThatTheBonusComesBack() {
        let (result, overview) = finishedYearWithABonus(taxAdvance: 0)
        #expect(result.childBonus == 37_524 && result.overpaymentTotal == 37_524)

        let data = build(overview)

        #expect(
            data.keyFigure.sentence
                == "Odvody za celý rok 2026 po odečtení všech záloh."
                + " Vrátí se 37\u{00A0}524\u{00A0}Kč – daňový bonus 37\u{00A0}524\u{00A0}Kč.")
        #expect(
            data.tiles[2]
                == FigureTileData(
                    label: "Vrátí se", figure: "37\u{00A0}524\u{00A0}Kč", note: "daňový bonus a přeplatky"))
        let tax = data.levies.parts[0]
        #expect(tax.weight < 0)
        #expect(
            tax.rows.last == LevyPopoverRow(label: "Vrátí se", value: "37\u{00A0}524\u{00A0}Kč", style: .positive))
    }

    /// With the bonus come the advances the tax did not need: what comes back is both, and the sentence names each.
    @Test func aFinishedYearWithABonusAndAdvancesSaysThatTheBonusAndTheOverpaidAdvancesComeBack() {
        let (result, overview) = finishedYearWithABonus(taxAdvance: 10_000)
        #expect(result.childBonus == 37_524 && result.overpaymentTotal == 47_524)

        let data = build(overview)

        #expect(
            data.keyFigure.sentence
                == "Odvody za celý rok 2026 po odečtení všech záloh."
                + " Vrátí se 47\u{00A0}524\u{00A0}Kč – daňový bonus 37\u{00A0}524\u{00A0}Kč"
                + " a přeplatky záloh 10\u{00A0}000\u{00A0}Kč.")
        #expect(
            data.tiles[2]
                == FigureTileData(
                    label: "Vrátí se", figure: "47\u{00A0}524\u{00A0}Kč", note: "daňový bonus a přeplatky"))
    }

    /// The design draws the Doplatek of a year that is over twice, in the eyebrow and in the second tile: both stay.
    @Test func aPastYearWithSomethingToPayNamesTheYearAndSaysNothingAboutAnOverpayment() {
        let receipt = Receipt(
            day: civilDate("2025-03-01"), czkNetHalere: 100_000_000, czkVatHalere: 0, source: .invoice(1))
        let (result, overview) = year2025(receipts: [receipt], social: 1_000, health: 1_000)
        #expect(result.remainingTotal > 0)
        #expect(result.overpaymentTotal == 0)

        let data = build(overview)

        #expect(data.keyFigure.eyebrow == "Doplatek za rok 2025")
        #expect(data.keyFigure.figure == CzechFormat.wholeKc(result.remainingTotal))
        #expect(data.keyFigure.sentence == "Odvody za celý rok 2025 po odečtení všech záloh.")
        #expect(data.tiles[1].figure == data.keyFigure.figure)
        #expect(data.tiles[2].figure == "0\u{00A0}Kč")
    }

    @Test func aPastYearShownAsOfAMidYearDayIsAYearInProgressAsOfThatDay() {
        // 2025 as of 30. 6. 2025, seen from 17. 10. 2026: a payment of 1 000 000 Kč on 1. 3. and 1 000 Kč of social and
        // of health insurance advances in each month, six paid and six to come.
        let receipt = Receipt(
            day: civilDate("2025-03-01"), czkNetHalere: 100_000_000, czkVatHalere: 0, source: .invoice(1))
        let plan = advances(social: 1_000, health: 1_000)
        let result = TaxEngine.compute(
            yearInput(year: 2025, receipts: [receipt], advances: plan), asOf: civilDate("2025-06-30"))
        #expect(result.remainingTotal > 0)
        let overview = input(year: 2025, asOf: "2025-06-30", result: result, advances: plan)

        let data = build(overview)

        #expect(data.keyFigure.eyebrow == "Zbývá zaplatit")
        #expect(data.keyFigure.figure == CzechFormat.wholeKc(result.remainingTotal))
        #expect(
            data.keyFigure.sentence
                == "Odvody z příjmů od 1.\u{00A0}1. do 30.\u{00A0}6.\u{00A0}2025"
                + " po odečtení záloh za leden až červen.")
        #expect(data.levies.header == "Odvody z příjmů do 30.\u{00A0}6.")
        #expect(
            data.tiles == [
                FigureTileData(
                    label: "Odejde zálohami", figure: CzechFormat.wholeKc(result.leavesViaPlannedAdvances),
                    note: "do konce roku podle plánu"),
                FigureTileData(
                    label: "Doplatek", figure: CzechFormat.wholeKc(result.settlementTotal),
                    note: "s přiznáním a přehledy za rok 2025"),
                FigureTileData(
                    label: "Mezní odvod", figure: CzechFormat.percent(result.marginalTotal),
                    note: "z další koruny příjmu"),
            ])
        // What is still to come as of that day is listed, the advances of July first.
        #expect(data.upcoming.count == 4)
        #expect(data.upcoming.first?.title == "Zálohy za červenec")
    }

    @Test func theMonthsOfAPastYearShownAsOfAMidYearDayAreCutAtThatDay() {
        let columns = build(input(year: 2025, asOf: "2025-06-30")).columns

        let before = [Bool](repeating: false, count: 5)
        let after = [Bool](repeating: false, count: 6)
        #expect(columns.map(\.isCurrent) == before + [true] + after)
        #expect(columns.map(\.isFuture) == after + [Bool](repeating: true, count: 6))
        #expect(columns.map(\.hasLinePoint) == [Bool](repeating: true, count: 6) + after)
    }

    @Test func theYearsChartOfAPastYearShownAsOfAMidYearDayIsCutAtThatDayAndNotAtToday() {
        // Issued 31. 3. 2025 and paid on 5. 9. 2025: as of 30. 6. 2025 the money has not been received, as of the end
        // of the year it has.
        let rows = [
            chartRow(
                id: 1, issued: "2025-03-31", net: 450_000, paidOn: "2025-09-05", paymentNet: 450_000, paymentVat: 0)
        ]

        let midYear = build(input(year: 2025, asOf: "2025-06-30", chartMode: .years, chartRows: rows)).columns
        let yearEnd = build(input(year: 2025, asOf: "2025-12-31", chartMode: .years, chartRows: rows)).columns

        #expect(midYear[1].issuedNetHalere == 450_000)
        #expect(midYear[1].receivedNetHalere == 0)
        #expect(yearEnd[1].receivedNetHalere == 450_000)
    }

    @Test func aPastYearHasNoUpcomingPayments() {
        // The advances of the past year have all been paid and its VAT filings are due long ago.
        let (_, overview) = year2025(social: 10_000, health: 6_000)

        #expect(build(overview).upcoming.isEmpty)
    }

    // MARK: Upcoming payments

    @Test func theNextFourPaymentsAreAdvancesAndVATFilingsInTheOrderOfTheirDays() {
        let upcoming = build(input()).upcoming

        #expect(upcoming.count == 4)

        #expect(upcoming[0].title == "DPH za září")
        #expect(upcoming[0].date == civilDate("2026-10-26"))
        #expect(upcoming[0].day == "26")
        #expect(upcoming[0].month == "říj")
        #expect(upcoming[0].amount == "945,00\u{00A0}Kč")
        #expect(upcoming[0].subtitle == "přiznání a kontrolní hlášení · mimo odvody z příjmů")
        #expect(upcoming[0].isVAT)

        #expect(upcoming[1].title == "Zálohy za listopad")
        #expect(upcoming[1].date == civilDate("2026-11-01"))
        #expect(upcoming[1].day == "lis")
        #expect(upcoming[1].month == "2026")
        #expect(upcoming[1].amount == "17\u{00A0}630\u{00A0}Kč")
        #expect(upcoming[1].subtitle == "sociální 12\u{00A0}150 · zdravotní 5\u{00A0}480")
        #expect(!upcoming[1].isVAT)

        #expect(upcoming[2].title == "DPH za říjen")
        #expect(upcoming[2].date == civilDate("2026-11-25"))
        #expect(upcoming[2].amount == "0\u{00A0}Kč")
        #expect(upcoming[2].subtitle == "podat přiznání · nic k úhradě")
        #expect(upcoming[2].isVAT)

        #expect(upcoming[3].title == "Zálohy za prosinec")
        #expect(upcoming[3].amount == "40\u{00A0}630\u{00A0}Kč")
        #expect(upcoming[3].subtitle == "sociální 12\u{00A0}150 · zdravotní 5\u{00A0}480 · daň 23\u{00A0}000")
    }

    @Test func theVATOfAMonthWithAnInvoiceToCheckSaysThatItIsNotCounted() throws {
        let upcoming = build(input(vatToCheckMonths: [9])).upcoming

        let september = try #require(upcoming.first { $0.title == "DPH za září" })
        #expect(september.subtitle == "faktury ke kontrole nejsou započtené")
        #expect(september.amount == "945,00\u{00A0}Kč")
        // October has none to check: its usual line.
        #expect(upcoming.first { $0.title == "DPH za říjen" }?.subtitle == "podat přiznání · nic k úhradě")
        // Without any to check, September has its usual line too.
        #expect(
            build(input()).upcoming.first { $0.title == "DPH za září" }?.subtitle
                == "přiznání a kontrolní hlášení · mimo odvody z příjmů")
    }

    @Test func aVATFilingDueNextYearShowsTheYearAndOneDueOnAHolidayMovesToTheNextWorkingDay() {
        // On 10 December: the November return is due on 25. 12., a holiday, so on Monday 28. 12.; December's is due on
        // Monday 25. 1. 2027. No advance is left for 2026. (The return for September, due on a Sunday, moves to the
        // Monday in the sample year above.)
        let upcoming = build(input(asOf: "2026-12-10", today: "2026-12-10")).upcoming

        #expect(upcoming.map(\.title) == ["DPH za listopad", "DPH za prosinec"])
        #expect(upcoming.map(\.date) == [civilDate("2026-12-28"), civilDate("2027-01-25")])
        #expect(upcoming.map(\.day) == ["28", "25"])
        #expect(upcoming.map(\.month) == ["pro", "led 27"])
    }

    @Test func aVATFilingDueOnTheChosenDayIsNotListedAnymoreButTheDayBeforeItIs() {
        // The return for September is due on Monday 26. 10. 2026.
        let onTheDay = build(input(asOf: "2026-10-26", today: "2026-10-26")).upcoming
        let theDayBefore = build(input(asOf: "2026-10-25", today: "2026-10-25")).upcoming

        #expect(!onTheDay.contains { $0.title == "DPH za září" })
        #expect(theDayBefore.first?.title == "DPH za září")
    }

    @Test func aMonthWithoutAnyAdvanceIsLeftOut() {
        // Only September has advances after the chosen day.
        var advances = AdvancePlan.empty
        advances.social[8] = 5_000
        advances.tax[8] = 7_000

        let noVAT = [Int64](repeating: 0, count: 12)
        let overview = input(asOf: "2026-08-15", today: "2026-08-15", advances: advances, vatByMonth: noVAT)
        let upcoming = build(overview).upcoming

        let advanceItems = upcoming.filter { !$0.isVAT }
        #expect(advanceItems.map(\.title) == ["Zálohy za září"])
        #expect(advanceItems[0].subtitle == "sociální 5\u{00A0}000 · daň 7\u{00A0}000")
        #expect(advanceItems[0].amount == "12\u{00A0}000\u{00A0}Kč")
    }

    // MARK: The net income above the chart

    /// The sample year of the prediction as of 17. 10. 2026: the three levies take 11,8 % of the income, so the net
    /// income of the year so far is 88,2 % of it, 1 933 471 Kč, which over the ten months from January through October
    /// is 193 347 Kč a month.
    @Test func theStripSaysTheNetIncomeOfTheYearSoFar() {
        let result = TaxEngine.compute(PredictionSample.yearInput(year: 2026), asOf: civilDate("2026-10-17"))

        let strip = build(input(result: result)).netIncome

        #expect(
            strip
                == OverviewNetIncome(
                    yearLabel: "Čistý příjem od 1.\u{00A0}1. do 17.\u{00A0}10.",
                    yearValue: "1\u{00A0}933\u{00A0}471\u{00A0}Kč",
                    yearSub: "88,2\u{00A0}% příjmů bez DPH po odvodech",
                    monthLabel: "Čistý příjem průměrně za měsíc", monthValue: "193\u{00A0}347\u{00A0}Kč",
                    monthSub: "průměr za leden–říjen"))
    }

    /// 2025 of the prediction sample shown as of its last day, from the autumn of 2026: the strip is about the whole
    /// year, 81,7 % of its income, and the average is over its twelve months.
    @Test func aYearShownAsOfItsLastDayHasTheNetIncomeOfTheWholeYear() {
        let result = TaxEngine.compute(PredictionSample.yearInput(year: 2025), asOf: civilDate("2025-12-31"))

        let strip = build(input(year: 2025, asOf: "2025-12-31", result: result)).netIncome

        #expect(strip.yearLabel == "Čistý příjem za rok 2025")
        #expect(strip.yearValue == "2\u{00A0}393\u{00A0}295\u{00A0}Kč")
        #expect(strip.yearSub == "81,7\u{00A0}% příjmů bez DPH po odvodech")
        #expect(strip.monthLabel == "Čistý příjem průměrně za měsíc")
        #expect(strip.monthValue == "199\u{00A0}441\u{00A0}Kč")
        #expect(strip.monthSub == "průměr za celý rok")
    }

    /// The current year of the prediction sample shown as of 31. 12. 2026, on that very day: the year is not over until
    /// the day after, so the header of the bar still words it as a year in progress, but the strip is about the whole
    /// year, as it keys on the day shown being the last of the year and not on the year being over. It counts the
    /// 2 191 771 Kč received by 17. 10. against levies of 258 300 Kč: a net income of 1 933 471 Kč, and 161 123 Kč a
    /// month over the twelve months.
    @Test func theCurrentYearShownAsOfItsLastDayIsCountedAsTheWholeYear() {
        let result = TaxEngine.compute(PredictionSample.yearInput(year: 2026), asOf: civilDate("2026-12-31"))

        let data = build(input(year: 2026, asOf: "2026-12-31", today: "2026-12-31", result: result))

        #expect(data.netIncome.yearLabel == "Čistý příjem za rok 2026")
        #expect(data.netIncome.yearValue == "1\u{00A0}933\u{00A0}471\u{00A0}Kč")
        #expect(data.netIncome.monthValue == "161\u{00A0}123\u{00A0}Kč")
        #expect(data.netIncome.monthSub == "průměr za celý rok")
        #expect(data.levies.header == "Odvody z příjmů do 31.\u{00A0}12.")
    }

    /// A year with no payment yet, as of 15. 1.: there is no income to give a share of, so the strip says only what the
    /// figure is, and the minimum insurance of January leaves a loss, which the strip shows with the minus sign. The
    /// average over the one month is the same figure.
    @Test func beforeTheFirstPaymentTheStripHasNoShare() {
        let result = TaxEngine.compute(
            yearInput(year: 2026, receipts: [], advances: .empty), asOf: civilDate("2026-01-15"))

        let strip = build(input(year: 2026, asOf: "2026-01-15", result: result)).netIncome

        #expect(strip.yearLabel == "Čistý příjem od 1.\u{00A0}1. do 15.\u{00A0}1.")
        #expect(strip.yearSub == "příjmy bez DPH po odvodech")
        #expect(strip.monthSub == "průměr za leden")
        #expect(strip.yearValue.hasPrefix("\u{2212}"), "\(strip.yearValue)")
        #expect(strip.yearValue == strip.monthValue)
    }

    /// With the bonus of `inputWithABonus()` the three levies are below zero, so the net income is more than the income
    /// of 250 000 Kč: the levies take −5,9 % of it, and the part that is left, shown as it is, is above 100 %.
    @Test func aTaxBonusTakesTheNetIncomeAboveTheIncome() {
        let strip = build(inputWithABonus()).netIncome

        #expect(strip.yearLabel == "Čistý příjem od 1.\u{00A0}1. do 28.\u{00A0}2.")
        #expect(strip.yearSub == "105,9\u{00A0}% příjmů bez DPH po odvodech")
        #expect(strip.monthSub == "průměr za leden–únor")
        #expect(!strip.yearValue.hasPrefix("\u{2212}"), "\(strip.yearValue)")
    }

    /// The day before the last day of the year is still a year in progress, though it is in December: the label names
    /// the days so far, and the average is said to be over the months from January through December, not over the
    /// whole year.
    @Test func theDayBeforeTheLastDayOfTheYearIsNotTheWholeYear() {
        let result = TaxEngine.compute(PredictionSample.yearInput(year: 2025), asOf: civilDate("2025-12-30"))

        let strip = build(input(year: 2025, asOf: "2025-12-30", result: result)).netIncome

        #expect(strip.yearLabel == "Čistý příjem od 1.\u{00A0}1. do 30.\u{00A0}12.")
        #expect(strip.monthSub == "průměr za leden–prosinec")
    }

    /// The strip is about the levies, not about the chart: grouping the chart by years and drawing it with VAT leaves
    /// it as it is.
    @Test func theStripIsTheSameInBothViewsAndWithVAT() {
        let months = build(input(chartMode: .months, chartWithVAT: false)).netIncome
        let years = build(input(chartMode: .years, chartWithVAT: true)).netIncome

        #expect(years == months)
    }

    // MARK: The chart by months

    @Test func theMonthsChartHasOneColumnPerMonthAndTheDraftCountsNowhere() {
        let columns = build(input(chartRows: sampleChartRows)).columns

        #expect(columns.count == 12)
        #expect(
            columns.map(\.label)
                == ["led", "úno", "bře", "dub", "kvě", "čvn", "čvc", "srp", "zář", "říj", "lis", "pro"])
        #expect(columns[0].title == "Leden 2026")
        #expect(columns[8].title == "Září 2026")
        #expect(columns[9].title == "Říjen 2026")

        // September: the dollar invoice at what was paid for it plus the crown invoice.
        #expect(columns[8].issuedNetHalere == 31_022_675)
        #expect(columns[8].issuedGrossHalere == 31_117_175)
        #expect(columns[8].receivedNetHalere == 0)
        // October: the money arrives; the draft of October is not issued.
        #expect(columns[9].issuedNetHalere == 0)
        #expect(columns[9].issuedGrossHalere == 0)
        #expect(columns[9].receivedNetHalere == 31_022_675)
        #expect(columns[9].receivedGrossHalere == 31_117_175)
    }

    @Test func theMonthsAfterTheChosenDayAreFutureAndHaveNoPointOnTheLine() {
        let columns = build(input(chartRows: sampleChartRows)).columns

        #expect(columns.map(\.isFuture) == (0..<12).map { $0 > 9 })
        #expect(columns.map(\.isCurrent) == (0..<12).map { $0 == 9 })
        #expect(columns.map(\.hasLinePoint) == (0..<12).map { $0 <= 9 })
    }

    @Test func aDayEarlierInTheYearMovesTheCurrentMonthAndHidesWhatComesAfterIt() {
        let columns = build(input(asOf: "2026-09-30", chartRows: sampleChartRows)).columns

        #expect(columns.map(\.isCurrent) == (0..<12).map { $0 == 8 })
        #expect(columns.map(\.isFuture) == (0..<12).map { $0 > 8 })
        // Nothing after the day counts: the payments of October have not been received.
        #expect(columns[9].receivedNetHalere == 0)
        // The dollar invoice is not paid yet on that day, so it is worth what its issue day's rate makes it.
        let expected: Int64 = 30_650_165 + 450_000
        #expect(columns[8].issuedNetHalere == expected)
    }

    @Test func aPastYearHasNoCurrentMonthAndNoFutureMonths() {
        let rows = [
            chartRow(
                id: 1, issued: "2025-03-31", net: 450_000, paidOn: "2025-04-05", paymentNet: 450_000, paymentVat: 0)
        ]

        let columns = build(input(year: 2025, asOf: "2025-12-31", chartRows: rows)).columns

        #expect(columns.count == 12)
        #expect(columns.allSatisfy { !$0.isFuture && !$0.isCurrent && $0.hasLinePoint })
        #expect(columns[2].issuedNetHalere == 450_000)
        #expect(columns[3].receivedNetHalere == 450_000)
    }

    @Test func anUnpaidInvoiceInAForeignCurrencyIsAnEstimateAtTheRateOfItsIssueDay() {
        let rows = [
            chartRow(id: 1, issued: "2026-10-05", currency: .usd, net: 1_204_000, issueDayRate: usd("21.622"))
        ]

        let october = build(input(chartRows: rows)).columns[9]

        #expect(october.issuedNetHalere == 26_032_888)
        #expect(october.issuedGrossHalere == 26_032_888)
        #expect(october.receivedNetHalere == 0)
    }

    @Test func theEstimateOfAnUnpaidForeignInvoiceWithVATConvertsTheVATAtTheSameRate() {
        // 10 000,00 USD and 2 100,00 USD VAT at 21,622: 216 220,00 Kč and 45 406,20 Kč.
        let rows = [
            chartRow(
                id: 1, issued: "2026-10-05", currency: .usd, net: 1_000_000, vat: 210_000,
                issueDayRate: usd("21.622"))
        ]

        let october = build(input(chartRows: rows)).columns[9]

        #expect(october.issuedNetHalere == 21_622_000)
        #expect(october.issuedGrossHalere == 26_162_620)
    }

    @Test func anUnpaidForeignInvoiceWhoseRateIsNotKnownIsWorthNothingInTheChartYet() {
        let rows = [chartRow(id: 1, issued: "2026-10-05", currency: .usd, net: 1_204_000)]

        let october = build(input(chartRows: rows)).columns[9]

        #expect(october.issuedNetHalere == 0)
    }

    @Test func aPaymentAfterTheChosenDayIsNotReceivedYetAndTheInvoiceIsAnEstimate() {
        let rows = [sampleChartRows[0]]

        let columns = build(input(asOf: "2026-10-01", chartRows: rows)).columns

        // 14 350,00 USD at 21,359 (the rate of 30. 9.) is 306 501,65 Kč; the payment of 2. 10. is still to come.
        #expect(columns[8].issuedNetHalere == 30_650_165)
        #expect(columns[9].receivedNetHalere == 0)
        #expect(columns[9].receivedGrossHalere == 0)
    }

    @Test func anInvoiceIssuedAfterTheChosenDayIsNotInTheChartYet() {
        let rows = [chartRow(id: 1, issued: "2026-10-05", net: 450_000, vat: 94_500)]

        let columns = build(input(asOf: "2026-10-01", chartRows: rows)).columns

        #expect(columns.allSatisfy { $0.issuedNetHalere == 0 })
    }

    @Test func anInvoiceInReviewCountsNowhere() {
        let rows = [
            chartRow(
                id: 1, issued: "2026-09-30", net: 450_000, vat: 94_500, inReview: true, paidOn: "2026-10-15",
                paymentNet: 450_000, paymentVat: 94_500)
        ]

        let columns = build(input(chartRows: rows)).columns

        #expect(columns.allSatisfy { $0.issuedNetHalere == 0 && $0.receivedNetHalere == 0 })
    }

    @Test func aPaymentOfADraftIsNotReceivedMoney() {
        let rows = [
            chartRow(
                id: 1, issued: "2026-09-30", net: 450_000, draft: true, paidOn: "2026-10-15", paymentNet: 450_000,
                paymentVat: 0)
        ]

        let columns = build(input(chartRows: rows)).columns

        #expect(columns.allSatisfy { $0.issuedNetHalere == 0 && $0.receivedNetHalere == 0 })
    }

    @Test func aRowIssuedInAnotherYearIsNoBarOfTheYearButItsPaymentIsMoneyReceivedInIt() {
        // Issued 30. 12. 2025 and paid 2. 1. 2026: the chart of 2026 has the money in January and no bar.
        let rows = [
            chartRow(
                id: 1, issued: "2025-12-30", net: 1_000_000, vat: 210_000, paidOn: "2026-01-02", paymentNet: 1_000_000,
                paymentVat: 210_000)
        ]

        let columns = build(input(chartRows: rows)).columns

        #expect(columns.allSatisfy { $0.issuedNetHalere == 0 })
        #expect(columns[0].receivedNetHalere == 1_000_000)
        #expect(columns[0].receivedGrossHalere == 1_210_000)
        #expect(columns[1...].allSatisfy { $0.receivedNetHalere == 0 })
    }

    @Test func aRowPaidInAnotherYearIsABarOfItsIssueYearButNotMoneyReceived() {
        // Issued 30. 12. 2025, viewed in the months of 2025: the bar is in December and the payment of 2026 is not
        // received in 2025.
        let rows = [
            chartRow(
                id: 1, issued: "2025-12-30", net: 1_000_000, vat: 210_000, paidOn: "2026-01-02", paymentNet: 1_000_000,
                paymentVat: 210_000)
        ]

        let columns = build(input(year: 2025, asOf: "2025-12-31", chartRows: rows)).columns

        #expect(columns[11].issuedNetHalere == 1_000_000)
        #expect(columns.allSatisfy { $0.receivedNetHalere == 0 })
    }

    // MARK: The chart by years

    @Test func theYearsChartHasOneColumnPerYearOfTheListAndTheSelectedYearIsTheCurrentOne() {
        let columns = build(input(chartMode: .years, chartYears: [2024, 2025, 2026])).columns

        #expect(columns.map(\.label) == ["2024", "2025", "2026"])
        #expect(columns.map(\.title) == ["Rok 2024", "Rok 2025", "Rok 2026"])
        #expect(columns.map(\.isCurrent) == [false, false, true])
        #expect(columns.allSatisfy { !$0.isFuture && $0.hasLinePoint })
    }

    @Test func theYearsChartPutsABarInTheYearOfIssueAndMoneyInTheYearOfPayment() {
        // Issued 30. 12. 2025 and paid 2. 1. 2026.
        let rows = [
            chartRow(
                id: 1, issued: "2025-12-30", net: 1_000_000, vat: 210_000, paidOn: "2026-01-02", paymentNet: 1_000_000,
                paymentVat: 210_000),
            chartRow(
                id: 2, issued: "2024-05-31", net: 400_000, paidOn: "2024-06-10", paymentNet: 400_000, paymentVat: 0),
        ]

        let columns = build(input(chartMode: .years, chartRows: rows)).columns

        #expect(columns.map(\.issuedNetHalere) == [400_000, 1_000_000, 0])
        #expect(columns.map(\.receivedNetHalere) == [400_000, 0, 1_000_000])
        #expect(columns.map(\.receivedGrossHalere) == [400_000, 0, 1_210_000])
    }

    @Test func rowsOfYearsThatAreNotInTheListAreLeftOut() {
        let rows = [
            chartRow(
                id: 1, issued: "2023-05-31", net: 400_000, paidOn: "2023-06-10", paymentNet: 400_000, paymentVat: 0)
        ]

        let columns = build(input(chartMode: .years, chartRows: rows, chartYears: [2025, 2026])).columns

        #expect(columns.count == 2)
        #expect(columns.allSatisfy { $0.issuedNetHalere == 0 && $0.receivedNetHalere == 0 })
    }

    @Test func theYearsChartIsCutAtTheChosenDayForTheCurrentYear() {
        // Today is 17. 10. 2026 and the day is 30. 9.: a payment of 2. 10. is not received, and the dollar invoice is
        // an estimate at the rate of its issue day.
        let columns = build(input(asOf: "2026-09-30", chartMode: .years, chartRows: [sampleChartRows[0]])).columns

        #expect(columns[2].issuedNetHalere == 30_650_165)
        #expect(columns[2].receivedNetHalere == 0)
    }

    @Test func theYearsChartOfAPastYearIsCutAtTodayNotAtTheEndOfThatYear() {
        // Issued 30. 12. 2025 in dollars and paid on 2. 1. 2026. Viewed from 2025 in the years chart, the payment has
        // been received by today and the bar is worth what was paid; the months of 2025 count it as an estimate.
        let rows = [
            chartRow(
                id: 1, issued: "2025-12-30", currency: .usd, net: 100_000, paidOn: "2026-01-02", paymentNet: 2_450_000,
                paymentVat: 0, issueDayRate: usd("24.000"))
        ]

        let years = build(input(year: 2025, asOf: "2025-12-31", chartMode: .years, chartRows: rows)).columns
        let months = build(input(year: 2025, asOf: "2025-12-31", chartMode: .months, chartRows: rows)).columns

        #expect(years[1].issuedNetHalere == 2_450_000)
        #expect(years[1].receivedNetHalere == 0)
        #expect(years[2].receivedNetHalere == 2_450_000)
        #expect(months[11].issuedNetHalere == 2_400_000)
    }

    // MARK: The net income in the chart

    /// The net income of a year of the years chart is counted to the last day of the year, and that of the year of the
    /// cut to the cut, as the amounts of the chart are; a year after the cut has none yet. The cut is the chosen day,
    /// except in the years chart of a year that is over, which is cut at today so that the money received since the end
    /// of that year is in it.
    @Test func theNetIncomeOfAYearIsCountedToItsLastDayOrToTheCut() {
        let cut = civilDate("2026-10-17")

        #expect(OverviewBuilder.netIncomeDay(ofYear: 2025, cut: cut) == civilDate("2025-12-31"))
        #expect(OverviewBuilder.netIncomeDay(ofYear: 2022, cut: cut) == civilDate("2022-12-31"))
        #expect(OverviewBuilder.netIncomeDay(ofYear: 2026, cut: cut) == cut)
        #expect(OverviewBuilder.netIncomeDay(ofYear: 2026, cut: civilDate("2025-06-30")) == nil)
        #expect(OverviewBuilder.netIncomeDay(ofYear: 2027, cut: cut) == nil)
        // The cut on the last day of a year is that day, and on the first day of the next year the one before it is
        // already a whole year.
        #expect(OverviewBuilder.netIncomeDay(ofYear: 2025, cut: civilDate("2025-12-31")) == civilDate("2025-12-31"))
        #expect(OverviewBuilder.netIncomeDay(ofYear: 2025, cut: civilDate("2026-01-01")) == civilDate("2025-12-31"))
        #expect(OverviewBuilder.netIncomeDay(ofYear: 2026, cut: civilDate("2026-01-01")) == civilDate("2026-01-01"))

        let today = civilDate("2026-10-17")
        let lastDay = civilDate("2025-12-31")
        let midYear = civilDate("2025-06-30")
        #expect(OverviewBuilder.chartCut(asOf: lastDay, today: today, mode: .years) == today)
        #expect(OverviewBuilder.chartCut(asOf: midYear, today: today, mode: .years) == midYear)
        #expect(OverviewBuilder.chartCut(asOf: lastDay, today: today, mode: .months) == lastDay)
        // The current year is cut at the chosen day, also when that is its last day, as a simulation.
        #expect(OverviewBuilder.chartCut(asOf: today, today: today, mode: .years) == today)
        let simulated = civilDate("2026-12-31")
        #expect(OverviewBuilder.chartCut(asOf: simulated, today: today, mode: .years) == simulated)
    }

    /// The sample year of the prediction as of 17. 10. 2026: its average net income per month, over the ten months from
    /// January through October, is in the hover box of every month.
    @Test func inTheMonthsChartEveryColumnHasTheAverageOfTheSelectedYear() {
        let result = TaxEngine.compute(PredictionSample.yearInput(year: 2026), asOf: civilDate("2026-10-17"))

        let columns = build(input(result: result)).columns

        let average = ChartNetAverage(
            label: "Průměrný čistý příjem za měsíc v roce 2026 (leden–říjen)", value: "193\u{00A0}347\u{00A0}Kč")
        #expect(columns.map(\.netAverage) == [ChartNetAverage?](repeating: average, count: 12))
    }

    /// What a payment of an invoice of `net` haléře, received on `day` (`YYYY-MM-DD`), adds to the levies when they
    /// grow by `levies` whole Kč on that day.
    private func invoicePayment(on day: String, net: Int64, levies: Int64) -> ReceiptEffect {
        ReceiptEffect(
            receipt: Receipt(day: civilDate(day), czkNetHalere: net, czkVatHalere: 0, source: .invoice(90)),
            tax: levies, social: 0, health: 0, total: levies)
    }

    /// The prediction sample's 2026 as of 17. 10. 2026, today, in the chart by months: each month has the sum of what
    /// the invoices paid in it leave after the levies their payments added, in haléře. The figures were worked out for
    /// the same data by a separate implementation. A month with no payment has 0, and so has every month after the day
    /// shown, which has no point on the line yet.
    @Test func eachMonthHasTheNetIncomeOfTheInvoicesPaidInIt() {
        let columns = build(sampleMonthsInput()).columns

        #expect(
            columns.map(\.netIncomeHalere) == [
                0, 25_340_100, 17_752_100, 38_383_100, 19_084_000, 0, 26_188_500, 23_197_360, 23_716_800,
                21_981_075, 0, 0,
            ])
        #expect(columns[1].netIncomeText == "253\u{00A0}401\u{00A0}Kč")
        #expect(columns[1].netIncomeNote == "součet za faktury zaplacené v měsíci")
        #expect(columns[1].accessibilityLabel.contains("; čistý příjem 253\u{00A0}401\u{00A0}Kč;"))
        #expect(columns[10].netIncomeText == "0\u{00A0}Kč" && columns[10].hasLinePoint == false)
        #expect(IncomeChartLayout.largestAmount(in: columns, withVAT: false) >= 25_340_100)
    }

    /// A reporting day after today cannot turn future payments into received net income. November and December
    /// remain at zero while real today is 17 October, even when the reporting cutoff is 30 November.
    @Test func aDayShownAfterTodayCountsThePaymentsOnlyUpToToday() {
        // 100 000,00 Kč that add 20 000 Kč to the levies leave 80 000,00 Kč.
        let november = invoicePayment(on: "2026-11-10", net: 10_000_000, levies: 20_000)
        let december = invoicePayment(on: "2026-12-05", net: 10_000_000, levies: 20_000)

        let simulated = build(
            sampleMonthsInput(asOf: "2026-11-30", today: "2026-10-17", extraEffects: [november, december])
        ).columns
        let now = build(sampleMonthsInput(extraEffects: [november, december])).columns

        #expect(simulated[9].netIncomeHalere == 21_981_075)
        #expect(simulated[10].netIncomeHalere == 0)
        #expect(simulated[10].netIncomeText == "0\u{00A0}Kč")
        #expect(simulated[10].hasLinePoint)
        #expect(simulated[11].netIncomeHalere == 0 && simulated[11].hasLinePoint == false)
        #expect(now.map(\.netIncomeHalere) == build(sampleMonthsInput()).columns.map(\.netIncomeHalere))
    }

    /// A past year shown as of its last day has every payment of the year in its months, and shown as of a day earlier
    /// in the year only the payments up to that day: the later ones are not counted.
    @Test func theMonthsCountThePaymentsUpToTheDayShownAndNoFurther() {
        let early = invoicePayment(on: "2025-03-10", net: 5_000_000, levies: 10_000)
        let late = invoicePayment(on: "2025-09-10", net: 7_000_000, levies: 10_000)
        let wholeYear = build(input(year: 2025, asOf: "2025-12-31", invoicePaymentEffects: [early, late])).columns
        let untilJune = build(input(year: 2025, asOf: "2025-06-30", invoicePaymentEffects: [early, late])).columns

        #expect(wholeYear.map(\.netIncomeHalere) == [0, 0, 4_000_000, 0, 0, 0, 0, 0, 6_000_000, 0, 0, 0])
        #expect(untilJune.map(\.netIncomeHalere) == [0, 0, 4_000_000, 0, 0, 0, 0, 0, 0, 0, 0, 0])
        #expect(wholeYear.allSatisfy { $0.hasLinePoint })
        #expect(untilJune.map(\.hasLinePoint) == (0..<12).map { $0 <= 5 })
    }

    /// A payment that the levies take more of than it brings, as the insurance has a minimum, leaves less than
    /// nothing: the month keeps its negative net, written with the minus sign, and the scale does not follow it below
    /// zero.
    @Test func aMonthWhoseLeviesAreMoreThanItsPaymentsKeepsItsNegativeNet() {
        // 5 000,00 Kč that add 6 000 Kč to the levies leave −1 000,00 Kč.
        let payment = invoicePayment(on: "2026-10-05", net: 500_000, levies: 6_000)

        let columns = build(input(invoicePaymentEffects: [payment])).columns

        #expect(columns[9].netIncomeHalere == -100_000)
        #expect(columns[9].netIncomeText == "\u{2212}1\u{00A0}000\u{00A0}Kč")
        #expect(columns[9].accessibilityLabel.contains("; čistý příjem \u{2212}1\u{00A0}000\u{00A0}Kč;"))
        #expect(IncomeChartLayout.largestAmount(in: columns, withVAT: false) == 0)
    }

    /// The months chart is about the selected year alone: the results of other years that the input holds are not
    /// read, and neither do the months follow the chart's VAT, as the net income is always without it.
    @Test func theMonthsChartIgnoresOtherYearsAndTheChartsVATForItsNetIncome() {
        let whole2025 = TaxEngine.compute(PredictionSample.yearInput(year: 2025), asOf: civilDate("2025-12-31"))
        let plain = build(sampleMonthsInput()).columns
        var other = sampleMonthsInput()
        other.chartWithVAT = true
        other.netIncomeResults = [2025: whole2025]

        let columns = build(other).columns

        #expect(plain[1].netIncomeHalere == 25_340_100)
        #expect(columns.map(\.netIncomeHalere) == plain.map(\.netIncomeHalere))
        #expect(columns.map(\.netIncomeText) == plain.map(\.netIncomeText))
        #expect(columns.allSatisfy { $0.netAverage?.value == "193\u{00A0}347\u{00A0}Kč" })
    }

    /// 2021 is before the oldest year the app has rules for, so the engine works it out with the rules of 2022: the net
    /// income of every month is marked as an estimate, also that of a month with no payment, and not only in the
    /// footer.
    @Test func aYearWithAnotherYearsRulesMarksTheNetOfEveryMonth() {
        let r2021 = result2021(receipts: [millionCrownsOf2021])
        #expect(r2021.rulesAreEstimate)
        let payment = Receipt(
            day: civilDate("2021-06-30"), czkNetHalere: 100_000_000, czkVatHalere: 0, source: .invoice(1))
        let effect = TaxEngine.effect(of: payment, in: yearInput(year: 2021, receipts: [payment], advances: .empty))

        let columns = build(
            input(year: 2021, asOf: "2021-12-31", result: r2021, invoicePaymentEffects: [effect])
        ).columns

        let texts = columns.map { $0.netIncomeText ?? "" }
        #expect(texts.allSatisfy { $0.hasPrefix("≈\u{00A0}") }, "\(texts)")
        #expect(columns[5].netIncomeText == "≈\u{00A0}" + PredictionBuilder.kc(ofHalere: effect.netHalere))
        #expect(columns[0].netIncomeText == "≈\u{00A0}0\u{00A0}Kč")
        #expect(columns[5].accessibilityLabel.contains("; čistý příjem ≈\u{00A0}"))
    }

    /// 2025 as a whole year and 2026 as of 17. 10. 2026, from the autumn of 2026: each year has the net income it
    /// leaves, in haléře, and its average per month, over the months it is counted for; a year without a result, 2024,
    /// has neither. The figures of 2026, the selected year, are those of the strip above the chart.
    @Test func inTheYearsChartEachYearHasItsNetIncome() {
        let whole2025 = TaxEngine.compute(PredictionSample.yearInput(year: 2025), asOf: civilDate("2025-12-31"))
        let soFar2026 = TaxEngine.compute(PredictionSample.yearInput(year: 2026), asOf: civilDate("2026-10-17"))

        let columns = build(
            input(
                result: soFar2026, chartMode: .years, chartYears: [2024, 2025, 2026],
                netIncomeResults: [2025: whole2025, 2026: soFar2026])
        ).columns

        #expect(columns.map(\.netIncomeHalere) == [nil, 239_329_500, 193_347_100])
        #expect(
            columns.map(\.netAverage) == [
                nil,
                ChartNetAverage(
                    label: "Průměrný čistý příjem za měsíc v roce 2025", value: "199\u{00A0}441\u{00A0}Kč"),
                ChartNetAverage(
                    label: "Průměrný čistý příjem za měsíc v roce 2026 (leden–říjen)",
                    value: "193\u{00A0}347\u{00A0}Kč"),
            ])
        #expect(
            columns[1].accessibilityLabel.hasSuffix(
                "; čistý příjem 2\u{00A0}393\u{00A0}295\u{00A0}Kč; "
                    + "Průměrný čistý příjem za měsíc v roce 2025 199\u{00A0}441\u{00A0}Kč"))
        // A year without a result says nothing of net income.
        #expect(!columns[0].accessibilityLabel.contains("čistý příjem"), "\(columns[0].accessibilityLabel)")
    }

    /// The hover box of a year of the years chart says what its net income covers under the row: the whole year for a
    /// year worked out for its last day, otherwise the span from 1. 1. to the day it was worked out for. A year
    /// without a result has no net income, so no words for it either.
    @Test func theYearsChartSaysWhatTheNetOfEachYearCovers() {
        let whole2025 = TaxEngine.compute(PredictionSample.yearInput(year: 2025), asOf: civilDate("2025-12-31"))
        let soFar2026 = TaxEngine.compute(PredictionSample.yearInput(year: 2026), asOf: civilDate("2026-10-17"))

        let columns = build(
            input(
                result: soFar2026, chartMode: .years, chartYears: [2024, 2025, 2026],
                netIncomeResults: [2025: whole2025, 2026: soFar2026])
        ).columns

        #expect(
            columns.map(\.netIncomeNote) == [
                nil, "za celý rok, po odvodech", "od 1.\u{00A0}1. do 17.\u{00A0}10., po odvodech",
            ])
    }

    /// A year whose levies are more than its income, 2025 without a payment, has a net income below zero, which the
    /// column keeps as it is, with the minus sign: the chart draws its point at zero, but the hover box tells the
    /// figure.
    @Test func aYearWhoseLeviesAreMoreThanItsIncomeKeepsItsNegativeNetIncomeInTheChart() {
        let result = TaxEngine.compute(
            yearInput(year: 2025, receipts: [], advances: .empty), asOf: civilDate("2025-12-31"))
        #expect(result.P == 0)
        #expect(result.liabilityTotal > 0)

        let column = build(
            input(
                year: 2025, asOf: "2025-12-31", result: result, chartMode: .years, chartYears: [2025],
                netIncomeResults: [2025: result])
        ).columns[0]

        #expect(column.netIncomeHalere == -result.liabilityTotal * 100)
        let loss = CzechFormat.wholeKc(result.liabilityTotal)
        #expect(column.accessibilityLabel.contains("; čistý příjem \u{2212}" + loss), "\(column.accessibilityLabel)")
        #expect(column.netAverage?.value.hasPrefix("\u{2212}") == true)
    }

    /// 2021 and 2026 in the chart by years: 2021 is before the oldest year the app has rules for, so the engine works
    /// it out with the rules of 2022, and its hover box and what VoiceOver reads put the sign of an estimate before its
    /// net income and its average and add the sentence of the warning of the screens, here for a payment of
    /// 1 000 000 Kč. Its point stays on the line of the chart. 2026 has rules of its own and reads as it did.
    @Test func aYearComputedWithTheRulesOfAnotherYearIsMarkedInTheChartByYears() {
        let r2026 = TaxEngine.compute(PredictionSample.yearInput(year: 2026), asOf: civilDate("2026-10-17"))
        let r2021 = result2021(receipts: [millionCrownsOf2021])
        #expect(r2021.rulesAreEstimate)
        #expect(r2021.rules.year == 2022)

        let columns = build(
            input(
                result: r2026, chartMode: .years, chartYears: [2021, 2026],
                netIncomeResults: [2021: r2021, 2026: r2026])
        ).columns

        #expect(columns[0].netIncomeHalere == 88_092_200)
        #expect(columns[0].netIncomeText == "≈\u{00A0}880\u{00A0}922\u{00A0}Kč")
        #expect(
            columns[0].netAverage
                == ChartNetAverage(
                    label: "Průměrný čistý příjem za měsíc v roce 2021", value: "≈\u{00A0}73\u{00A0}410\u{00A0}Kč",
                    note: sentenceOf2021))
        #expect(
            columns[0].accessibilityLabel.hasSuffix(
                "; čistý příjem ≈\u{00A0}880\u{00A0}922\u{00A0}Kč; "
                    + "Průměrný čistý příjem za měsíc v roce 2021 ≈\u{00A0}73\u{00A0}410\u{00A0}Kč; " + sentenceOf2021),
            "\(columns[0].accessibilityLabel)")
        #expect(columns[1].netIncomeText == "1\u{00A0}933\u{00A0}471\u{00A0}Kč")
        #expect(columns[1].netAverage?.value == "193\u{00A0}347\u{00A0}Kč")
        #expect(columns[1].netAverage?.note == nil)
    }

    /// 2027 is after the newest year the app has rules for, so the engine works it out with the rules of 2026. Once
    /// 2026 is finished and 2027 has begun, the chart by years marks 2027 as an estimate and keeps its point on the
    /// line, and leaves 2026, which has rules of its own, as it was.
    @Test func aLaterYearComputedWithTheRulesOfTheSelectedOneIsMarkedWhenThatYearIsFinished() {
        let january = Receipt(
            day: civilDate("2027-01-10"), czkNetHalere: 20_000_000, czkVatHalere: 0, source: .synthetic)
        let r2027 = TaxEngine.compute(
            yearInput(year: 2027, receipts: [january], advances: .empty), asOf: civilDate("2027-01-15"))
        #expect(r2027.rulesAreEstimate)
        #expect(r2027.rules.year == 2026)
        let whole2026 = TaxEngine.compute(PredictionSample.yearInput(year: 2026), asOf: civilDate("2026-12-31"))

        let columns = build(
            input(
                year: 2026, asOf: "2026-12-31", today: "2027-01-15", result: whole2026, chartMode: .years,
                chartYears: [2026, 2027], netIncomeResults: [2026: whole2026, 2027: r2027])
        ).columns

        #expect(columns[1].netIncomeHalere == NetIncome(r2027).yearKc * 100)
        #expect(columns[1].netIncomeText?.hasPrefix("≈\u{00A0}") == true, "\(columns[1])")
        #expect(columns[1].netAverage?.value.hasPrefix("≈\u{00A0}") == true, "\(columns[1])")
        #expect(
            columns[1].netAverage?.note
                == "Pravidla pro rok 2027 zatím nejsou v aplikaci – výpočet je odhad podle roku 2026.")
        #expect(columns[0].netIncomeText == "1\u{00A0}933\u{00A0}471\u{00A0}Kč")
        #expect(columns[0].netAverage?.note == nil)
    }

    /// A year computed with the rules of another year whose levies are more than its income, 2021 without a payment,
    /// has a net income below zero. The sign of the estimate stands before the minus sign, in the row of the hover box
    /// and in the average.
    @Test func aLossOfAYearComputedWithTheRulesOfAnotherYearPutsTheSignBeforeTheMinus() {
        let result = result2021(receipts: [])
        #expect(result.rulesAreEstimate)
        #expect(result.P == 0)
        #expect(result.liabilityTotal > 0)

        let column = build(
            input(
                year: 2021, asOf: "2021-12-31", result: result, chartMode: .years, chartYears: [2021],
                netIncomeResults: [2021: result])
        ).columns[0]

        #expect(column.netIncomeText?.hasPrefix("≈\u{00A0}\u{2212}") == true, "\(column)")
        #expect(column.netAverage?.value.hasPrefix("≈\u{00A0}\u{2212}") == true, "\(column)")
    }

    /// The selected year in the chart by months: every month has the footer of that year, so a year computed with the
    /// rules of another year marks the footer of every month, in the hover box and for VoiceOver.
    @Test func aSelectedYearComputedWithTheRulesOfAnotherYearMarksTheFooterOfEveryMonth() {
        let r2021 = result2021(receipts: [millionCrownsOf2021])

        let columns = build(input(year: 2021, asOf: "2021-12-31", result: r2021)).columns

        let average = ChartNetAverage(
            label: "Průměrný čistý příjem za měsíc v roce 2021", value: "≈\u{00A0}73\u{00A0}410\u{00A0}Kč",
            note: sentenceOf2021)
        #expect(columns.map(\.netAverage) == [ChartNetAverage?](repeating: average, count: 12))
        #expect(
            columns.allSatisfy {
                $0.accessibilityLabel.hasSuffix(
                    "; Průměrný čistý příjem za měsíc v roce 2021 ≈\u{00A0}73\u{00A0}410\u{00A0}Kč; " + sentenceOf2021)
            })
    }

    /// The scale holds the net income that the chart draws: a net income above the other amounts raises it, and one
    /// below zero is drawn at zero, so it does not.
    @Test func theScaleFitsTheNetIncomeButNotBelowZero() {
        func column(net: Int64?) -> ChartColumn {
            ChartColumn(
                label: "2026", title: "Rok 2026", issuedNetHalere: 0, issuedGrossHalere: 0, receivedNetHalere: 1_000,
                receivedGrossHalere: 1_000, isFuture: false, isCurrent: true, hasLinePoint: true, netIncomeHalere: net)
        }

        #expect(IncomeChartLayout.largestAmount(in: [column(net: 5_000)], withVAT: false) == 5_000)
        #expect(IncomeChartLayout.largestAmount(in: [column(net: -50_000)], withVAT: false) == 1_000)
        #expect(IncomeChartLayout.largestAmount(in: [column(net: nil)], withVAT: false) == 1_000)
        #expect(IncomeChartLayout.largestAmount(in: [], withVAT: false) == 0)
    }

    /// The largest amount is that of the series drawn: what was issued and received with VAT or without, and the net
    /// income, which is always without VAT, from the column that has the most of it.
    @Test func theScaleFollowsTheVATOfTheChartForTheBarsAndTheLineButNotForTheNetIncome() {
        let small = ChartColumn(
            label: "2025", title: "Rok 2025", issuedNetHalere: 2_000, issuedGrossHalere: 2_420,
            receivedNetHalere: 1_000, receivedGrossHalere: 1_210, isFuture: false, isCurrent: false,
            hasLinePoint: true)
        let bigNet = ChartColumn(
            label: "2026", title: "Rok 2026", issuedNetHalere: 100, issuedGrossHalere: 121, receivedNetHalere: 100,
            receivedGrossHalere: 121, isFuture: false, isCurrent: true, hasLinePoint: true, netIncomeHalere: 2_450)

        #expect(IncomeChartLayout.largestAmount(in: [small], withVAT: false) == 2_000)
        #expect(IncomeChartLayout.largestAmount(in: [small], withVAT: true) == 2_420)
        #expect(IncomeChartLayout.largestAmount(in: [small, bigNet], withVAT: false) == 2_450)
        #expect(IncomeChartLayout.largestAmount(in: [small, bigNet], withVAT: true) == 2_450)
    }

    // MARK: The sample year

    /// The twelve invoices of the sample year as of 17. 10. 2026. What each column reads out was worked out for the
    /// same data by a separate implementation, in crowns and haléře; here every amount is that figure in whole Kč,
    /// rounded half up, as the hover boxes of the charts and VoiceOver tell it.
    @Test func theMonthsChartOfTheSampleYearReadsOutAsWorkedOutSeparately() {
        let columns = build(input(chartRows: SampleYear2026.chartRows)).columns

        let readOut: [(String, String)] = [
            (
                "Leden 2026: vystaveno 220\u{00A0}000\u{00A0}Kč bez DPH, 266\u{00A0}200\u{00A0}Kč s DPH; ",
                "přijato 0\u{00A0}Kč bez DPH, 0\u{00A0}Kč s DPH"
            ),
            (
                "Únor 2026: vystaveno 190\u{00A0}000\u{00A0}Kč bez DPH, 229\u{00A0}900\u{00A0}Kč s DPH; ",
                "přijato 220\u{00A0}000\u{00A0}Kč bez DPH, 266\u{00A0}200\u{00A0}Kč s DPH"
            ),
            (
                "Březen 2026: vystaveno 210\u{00A0}000\u{00A0}Kč bez DPH, 254\u{00A0}100\u{00A0}Kč s DPH; ",
                "přijato 190\u{00A0}000\u{00A0}Kč bez DPH, 229\u{00A0}900\u{00A0}Kč s DPH"
            ),
            (
                "Duben 2026: vystaveno 210\u{00A0}000\u{00A0}Kč bez DPH, 254\u{00A0}100\u{00A0}Kč s DPH; ",
                "přijato 420\u{00A0}000\u{00A0}Kč bez DPH, 508\u{00A0}200\u{00A0}Kč s DPH"
            ),
            (
                "Květen 2026: vystaveno 210\u{00A0}000\u{00A0}Kč bez DPH, 254\u{00A0}100\u{00A0}Kč s DPH; ",
                "přijato 210\u{00A0}000\u{00A0}Kč bez DPH, 254\u{00A0}100\u{00A0}Kč s DPH"
            ),
            (
                "Červen 2026: vystaveno 288\u{00A0}806\u{00A0}Kč bez DPH, 288\u{00A0}806\u{00A0}Kč s DPH; ",
                "přijato 0\u{00A0}Kč bez DPH, 0\u{00A0}Kč s DPH"
            ),
            (
                "Červenec 2026: vystaveno 268\u{00A0}806\u{00A0}Kč bez DPH, 268\u{00A0}806\u{00A0}Kč s DPH; ",
                "přijato 288\u{00A0}806\u{00A0}Kč bez DPH, 288\u{00A0}806\u{00A0}Kč s DPH"
            ),
            (
                "Srpen 2026: vystaveno 283\u{00A0}933\u{00A0}Kč bez DPH, 284\u{00A0}878\u{00A0}Kč s DPH; ",
                "přijato 273\u{00A0}306\u{00A0}Kč bez DPH, 274\u{00A0}251\u{00A0}Kč s DPH"
            ),
            (
                "Září 2026: vystaveno 310\u{00A0}227\u{00A0}Kč bez DPH, 311\u{00A0}172\u{00A0}Kč s DPH; ",
                "přijato 279\u{00A0}433\u{00A0}Kč bez DPH, 279\u{00A0}433\u{00A0}Kč s DPH"
            ),
            (
                "Říjen 2026: vystaveno 0\u{00A0}Kč bez DPH, 0\u{00A0}Kč s DPH; ",
                "přijato 310\u{00A0}227\u{00A0}Kč bez DPH, 311\u{00A0}172\u{00A0}Kč s DPH"
            ),
            (
                "Listopad 2026: vystaveno 0\u{00A0}Kč bez DPH, 0\u{00A0}Kč s DPH; ",
                "přijato 0\u{00A0}Kč bez DPH, 0\u{00A0}Kč s DPH"
            ),
            (
                "Prosinec 2026: vystaveno 0\u{00A0}Kč bez DPH, 0\u{00A0}Kč s DPH; ",
                "přijato 0\u{00A0}Kč bez DPH, 0\u{00A0}Kč s DPH"
            ),
        ]
        // Every month also reads out its net income, 0 Kč here as the input holds no payment's effect on the levies
        // (the figures are tested with them, `eachMonthHasTheNetIncomeOfTheInvoicesPaidInIt`), and the average net
        // income per month of the year so far, which the engine's levies of the sample year give: its income of
        // 2 191 771 Kč less the 320 664 Kč of levies is 1 871 107 Kč, over the ten months from January through October.
        let net = "; čistý příjem 0\u{00A0}Kč"
        let average = "; Průměrný čistý příjem za měsíc v roce 2026 (leden–říjen) 187\u{00A0}111\u{00A0}Kč"
        #expect(columns.map(\.accessibilityLabel) == readOut.map { $0.0 + $0.1 + net + average })
    }

    /// The same payments with what the engine says each adds to the levies. A separate implementation lists the same
    /// five receipts, in this order, with the same amounts and effects.
    @Test func theLatestReceiptsOfTheSampleYearAreTheFiveNewestWithTheirEffectOnTheLevies() {
        let overview = input(latestReceipts: receiptsWithEffects(of: SampleYear2026.invoices))

        let latest = build(overview).latestReceipts

        #expect(latest.map(\.date) == [
            "15.\u{00A0}10.", "2.\u{00A0}10.", "9.\u{00A0}9.", "26.\u{00A0}8.", "7.\u{00A0}8.",
        ])
        #expect(latest.map(\.number) == [
            "20260902", "20260901", "20260802", "20260801", "20260701",
        ])
        #expect(latest.map(\.client) == [
            "Cetus Data s.r.o.", "Bravo Labs, Inc.", "Bravo Labs, Inc.", "Cetus Data s.r.o.", "Bravo Labs, Inc.",
        ])
        let original = [
            "5\u{00A0}445,00\u{00A0}Kč vč. DPH 945,00", "14\u{00A0}350,00\u{00A0}USD · kurz 21,305",
            "13\u{00A0}300,00\u{00A0}USD · kurz 21,010", "5\u{00A0}445,00\u{00A0}Kč vč. DPH 945,00",
            "12\u{00A0}880,00\u{00A0}USD · kurz 20,870",
        ]
        #expect(latest.map(\.original) == original)
        let czk = [
            "4\u{00A0}500,00\u{00A0}Kč", "305\u{00A0}726,75\u{00A0}Kč", "279\u{00A0}433,00\u{00A0}Kč",
            "4\u{00A0}500,00\u{00A0}Kč", "268\u{00A0}805,60\u{00A0}Kč",
        ]
        #expect(latest.map(\.czk) == czk)
        let effect = [
            "+1\u{00A0}702\u{00A0}Kč", "+88\u{00A0}714\u{00A0}Kč", "+42\u{00A0}265\u{00A0}Kč", "+681\u{00A0}Kč",
            "+40\u{00A0}651\u{00A0}Kč",
        ]
        #expect(latest.map(\.effect) == effect)
    }

    /// Each payment of the invoices, with what the engine says it adds to the levies of the sample year.
    private func receiptsWithEffects(of invoices: [Invoice]) -> [(invoice: Invoice, effect: ReceiptEffect)] {
        invoices.compactMap { invoice in
            guard let payment = invoice.payment else { return nil }
            let receipt = Receipt(
                day: payment.date, czkNetHalere: payment.czkNetHalere, czkVatHalere: payment.czkVatHalere,
                source: .invoice(invoice.id))
            let effect = TaxEngine.effect(of: receipt, in: TaxEngineRegressionTests.sampleYear2026)
            return (invoice: invoice, effect: effect)
        }
    }

    // MARK: Chart texts

    @Test func theChartSubtitleSaysWhatIsShownAndHowForeignMoneyIsConverted() {
        let conversion = " · cizí měny kurzem ČNB ke dni platby, nezaplacené kurzem ČNB ke dni vystavení"
        let hover = " · podrobnosti po najetí myší"
        #expect(build(input()).chartSubtitle == "Rok 2026 po měsících · v Kč bez DPH" + conversion + hover)
        #expect(
            build(input(chartMode: .years, chartWithVAT: true)).chartSubtitle
                == "Po letech · v Kč s DPH" + conversion + hover)
    }

    /// The money received in a year that converts it at its uniform rate is in the chart at that rate, and the line
    /// under the title says so: of the year of the months, or of any year of the years chart.
    @Test func theChartSubtitleNamesTheUniformRateOfTheYearsThatUseIt() {
        let unpaid = ", nezaplacené kurzem ČNB ke dni vystavení"
        let hover = " · podrobnosti po najetí myší"

        #expect(
            build(input(yearsAtUniformRate: [2026])).chartSubtitle
                == "Rok 2026 po měsících · v Kč bez DPH · přijaté v cizí měně jednotným kurzem 2026" + unpaid + hover)
        #expect(
            build(input(chartMode: .years, chartWithVAT: true, yearsAtUniformRate: [2025])).chartSubtitle
                == "Po letech · v Kč s DPH · přijaté v cizí měně přepočtem zvoleným pro svůj rok" + unpaid + hover)
        // The months of 2026 are about 2026 alone, and the years chart about the years it has.
        #expect(
            build(input(yearsAtUniformRate: [2025])).chartSubtitle
                == "Rok 2026 po měsících · v Kč bez DPH · cizí měny kurzem ČNB ke dni platby" + unpaid + hover)
        #expect(
            build(input(chartMode: .years, chartYears: [2025, 2026], yearsAtUniformRate: [2024])).chartSubtitle
                == "Po letech · v Kč bez DPH · cizí měny kurzem ČNB ke dni platby" + unpaid + hover)
    }

    @Test func aColumnSpeaksForVoiceOverWithBothSeriesWithAndWithoutVAT() {
        let columns = build(input(chartRows: sampleChartRows)).columns

        let expected =
            "Září 2026: vystaveno 310\u{00A0}227\u{00A0}Kč bez DPH, 311\u{00A0}172\u{00A0}Kč s DPH; "
            + "přijato 0\u{00A0}Kč bez DPH, 0\u{00A0}Kč s DPH; čistý příjem 0\u{00A0}Kč; "
            + "Průměrný čistý příjem za měsíc v roce 2026 (leden–říjen) 187\u{00A0}111\u{00A0}Kč"
        #expect(columns[8].accessibilityLabel == expected)
    }

    /// The hover box of a column and VoiceOver tell its amounts in whole Kč, rounded half up, while the column keeps
    /// them in haléře for the chart to draw: September of the sample year issued 310 226,75 Kč without VAT and
    /// 311 171,75 Kč with it, and received 279 433,00 Kč.
    @Test func aColumnTellsItsAmountsInWholeCrownsAndKeepsThemInHalereForTheChart() {
        let september = build(input(chartRows: SampleYear2026.chartRows)).columns[8]

        #expect(september.issuedNetHalere == 31_022_675 && september.issuedGrossHalere == 31_117_175)
        #expect(september.issuedNetText == "310\u{00A0}227\u{00A0}Kč")
        #expect(september.issuedGrossText == "311\u{00A0}172\u{00A0}Kč")
        #expect(september.receivedNetText == "279\u{00A0}433\u{00A0}Kč")
        #expect(september.receivedGrossText == "279\u{00A0}433\u{00A0}Kč")
    }

    /// Half a crown is rounded up, as everywhere else in whole Kč (`DecimalMath.halfUp`).
    @Test func halfACrownInAColumnIsRoundedUp() {
        let column = ChartColumn(
            label: "zář", title: "Září 2026", issuedNetHalere: 100_050, issuedGrossHalere: 100_049,
            receivedNetHalere: 99, receivedGrossHalere: 50, isFuture: false, isCurrent: false, hasLinePoint: true)

        #expect(column.issuedNetText == "1\u{00A0}001\u{00A0}Kč")
        #expect(column.issuedGrossText == "1\u{00A0}000\u{00A0}Kč")
        #expect(column.receivedNetText == "1\u{00A0}Kč")
        #expect(column.receivedGrossText == "1\u{00A0}Kč")
    }

    /// An issued amount that is only approximate keeps the sign "≈" in the hover box and for VoiceOver of the chart of
    /// Příjmy, where it is a lone estimate among actual figures; the received amounts never have it. An unpaid invoice
    /// in dollars is worth the latest declared rate while the rate of its day of issue is not declared yet.
    @Test func anApproximateIssuedAmountKeepsItsSignInTheChartOfPrijmy() {
        var provisional = chartRow(
            id: 99, issued: "2026-10-10", currency: .usd, net: 1_000_000, issueDayRate: usd("21.5"))
        provisional.issueDayRateIsProvisional = true

        let october = build(input(chartRows: [provisional])).columns[9]

        #expect(october.issuedIsApproximate)
        #expect(october.issuedNetText == "≈\u{00A0}215\u{00A0}000\u{00A0}Kč")
        #expect(october.issuedGrossText == "≈\u{00A0}215\u{00A0}000\u{00A0}Kč")
        #expect(october.receivedNetText == "0\u{00A0}Kč" && october.receivedGrossText == "0\u{00A0}Kč")
        #expect(
            october.accessibilityLabel.contains(
                "vystaveno ≈\u{00A0}215\u{00A0}000\u{00A0}Kč bez DPH, ≈\u{00A0}215\u{00A0}000\u{00A0}Kč s DPH;"))
    }

    // MARK: The uniform rate of the year

    private func uniformRate(
        _ code: String, _ rate: String, amount: Int = 1, year: Int = 2025, instruction: String = "GFŘ-D-75",
        origin: UniformRateOrigin = .builtIn
    ) -> UniformRate {
        UniformRate(
            year: year, currency: CurrencyCode(code)!, amount: amount, rate: decimal(rate), instruction: instruction,
            sourceURL: nil, confirmedAt: nil, origin: origin
        )
    }

    private func builtIn2025() -> [UniformRate] {
        BuiltInUniformRates.rates(year: 2025).map { entry in
            UniformRate(
                year: 2025, currency: entry.currency, amount: entry.amount, rate: entry.rate,
                instruction: BuiltInUniformRates.instructions[2025]!, sourceURL: nil, confirmedAt: nil,
                origin: .builtIn
            )
        }
    }

    @Test func thereIsNoUniformLineUntilTheRateOfTheYearIsKnown() {
        // 2026: the rate comes out in January 2027, and the year has a dollar invoice.
        #expect(build(input(foreignCurrencies: [.usd], uniformRates: [])).uniformLine == nil)
    }

    @Test func theUniformLineListsTheRateOfEveryForeignCurrencyOfTheYear() throws {
        let data = build(
            input(year: 2025, asOf: "2025-12-31", foreignCurrencies: [.usd], uniformRates: builtIn2025()))

        let line = try #require(data.uniformLine)
        #expect(line.title == "Jednotný kurz za rok 2025")
        #expect(line.rates == ["1\u{00A0}USD = 21,84\u{00A0}Kč"])
        #expect(line.source == "pokyn GFŘ-D-75 · příjmy se přepočítávají denním kurzem ČNB")
    }

    @Test func theUniformLineIsAlphabeticalAndQuotesTheAmountOfAHundredUnits() throws {
        let jpy = CurrencyCode("JPY")!
        let data = build(
            input(year: 2025, asOf: "2025-12-31", foreignCurrencies: [.usd, jpy], uniformRates: builtIn2025()))

        let line = try #require(data.uniformLine)
        #expect(line.rates == ["100\u{00A0}JPY = 14,59\u{00A0}Kč", "1\u{00A0}USD = 21,84\u{00A0}Kč"])
    }

    @Test func aCurrencyWithoutAnInvoiceInTheYearIsNotListedEvenWhenItsRateIsKnown() throws {
        // The year has a draft in euros only, which the list of currencies of the year leaves out.
        let data = build(
            input(year: 2025, asOf: "2025-12-31", foreignCurrencies: [.usd], uniformRates: builtIn2025()))

        let line = try #require(data.uniformLine)
        #expect(!line.rates.contains { $0.contains("EUR") })
    }

    @Test func aCurrencyWhoseRateIsNotKnownIsLeftOutOfTheLine() throws {
        let data = build(
            input(
                year: 2025, asOf: "2025-12-31", foreignCurrencies: [.eur, .usd],
                uniformRates: [uniformRate("USD", "21.84")]))

        let line = try #require(data.uniformLine)
        #expect(line.rates == ["1\u{00A0}USD = 21,84\u{00A0}Kč"])
    }

    @Test func noForeignCurrencyMeansNoLineEvenWithRatesStored() {
        let overview = input(year: 2025, asOf: "2025-12-31", foreignCurrencies: [], uniformRates: builtIn2025())

        #expect(build(overview).uniformLine == nil)
    }

    @Test func theLineNamesTheYearsIncomeConversionAndTheSourceOfAManualRate() throws {
        let manual = uniformRate("USD", "21.9", year: 2026, instruction: "", origin: .manual)

        let data = build(
            input(foreignCurrencies: [.usd], uniformRates: [manual], yearsAtUniformRate: [2026]))

        let line = try #require(data.uniformLine)
        #expect(line.title == "Jednotný kurz za rok 2026")
        #expect(line.rates == ["1\u{00A0}USD = 21,90\u{00A0}Kč"])
        #expect(line.source == "zadáno ručně · příjmy se přepočítávají jednotným kurzem")
    }

    @Test func aManualRateWithAnInstructionNamesItAndSaysItWasEnteredByHand() throws {
        let manual = uniformRate("USD", "21.9", year: 2026, instruction: "GFŘ-D-90", origin: .manual)

        let line = try #require(build(input(foreignCurrencies: [.usd], uniformRates: [manual])).uniformLine)

        #expect(line.source.hasPrefix("pokyn GFŘ-D-90, zadáno ručně · "))
    }

    /// Where uniform rates are from, as every screen says it: the instruction of official ones, and for rates entered
    /// by hand that they were, with their instruction when they have one.
    @Test func theSourceOfUniformRatesAlwaysMarksThoseEnteredByHand() {
        let builtIn = uniformRate("USD", "21.84", year: 2025, instruction: "GFŘ-D-75", origin: .builtIn)
        let fetched = uniformRate("USD", "20.9", year: 2026, instruction: "GFŘ-D-99", origin: .fetched)
        let named = uniformRate("USD", "21.9", year: 2026, instruction: " GFŘ-D-80 ", origin: .manual)
        let unnamed = uniformRate("EUR", "24.5", year: 2026, instruction: "", origin: .manual)

        #expect(BuilderText.uniformSource(of: [builtIn]) == "pokyn GFŘ-D-75")
        #expect(BuilderText.uniformSource(of: [fetched]) == "pokyn GFŘ-D-99")
        #expect(BuilderText.uniformSource(of: [named]) == "pokyn GFŘ-D-80, zadáno ručně")
        #expect(BuilderText.uniformSource(of: [unnamed]) == "zadáno ručně")
        // The same source is said once.
        #expect(BuilderText.uniformSource(of: [named, named]) == "pokyn GFŘ-D-80, zadáno ručně")
        #expect(BuilderText.uniformSource(instruction: "GFŘ-D-80", origin: .manual) == "pokyn GFŘ-D-80, zadáno ručně")
        #expect(BuilderText.uniformSource(instruction: nil, origin: .manual) == "zadáno ručně")
        #expect(BuilderText.uniformSource(instruction: "GFŘ-D-75", origin: .builtIn) == "pokyn GFŘ-D-75")
        #expect(BuilderText.uniformSource(instruction: nil, origin: .fetched) == nil)
    }

    // MARK: The latest receipts

    private func paidInvoice(
        id: Int64, number: String, paidOn day: String, payment: Payment? = nil, client: String = "Alfa Systems s.r.o."
    ) -> Invoice {
        var invoice = Invoice.fixture(number: number, payment: payment ?? .fixture(on: day))
        invoice.id = id
        invoice.client.name = client
        return invoice
    }

    @Test func theLatestReceiptsAreTheFiveNewestOfTheYearUpToTheChosenDay() {
        let days = [
            "2026-08-07", "2026-10-15", "2026-07-07", "2026-11-05", "2026-10-02", "2025-12-20", "2026-09-09",
            "2026-08-26",
        ]
        let receipts = days.enumerated().map { index, day in
            (
                invoice: paidInvoice(id: Int64(index + 1), number: "2026090\(index + 1)", paidOn: day),
                effect: effect(total: Int64(1_000 * (index + 1)), on: day)
            )
        }

        let latest = build(input(latestReceipts: receipts)).latestReceipts

        // Not the payment of 5. 11. (after the day) and not that of 2025; the five newest of the rest.
        #expect(latest.map(\.number) == ["20260902", "20260905", "20260907", "20260908", "20260901"])
        #expect(
            latest.map(\.date) == ["15.\u{00A0}10.", "2.\u{00A0}10.", "9.\u{00A0}9.", "26.\u{00A0}8.", "7.\u{00A0}8."])
        #expect(latest.map(\.invoiceID) == [2, 5, 7, 8, 1])
    }

    @Test func aReceiptOfAnotherYearIsNotListedEvenWhenThereAreFewReceipts() {
        let receipts = [("2026-10-15", 1), ("2025-12-20", 2)].map { day, id in
            (invoice: paidInvoice(id: Int64(id), number: "2026090\(id)", paidOn: day), effect: effect(total: 1_000))
        }

        let latest = build(input(latestReceipts: receipts)).latestReceipts

        #expect(latest.map(\.invoiceID) == [1])
    }

    @Test func receiptsOfTheSameDayKeepTheirOrder() {
        let receipts = [1, 2, 3].map { index in
            (
                invoice: paidInvoice(id: Int64(index), number: "2026090\(index)", paidOn: "2026-10-15"),
                effect: effect(total: 1_000)
            )
        }

        let latest = build(input(latestReceipts: receipts)).latestReceipts

        #expect(latest.map(\.invoiceID) == [1, 2, 3])
    }

    @Test func aReceiptInACrownInvoiceShowsTheAmountWithVATAndWhatItAddsToTheLevies() throws {
        let invoice = paidInvoice(id: 11, number: "20260902", paidOn: "2026-10-15", client: "Cetus Data s.r.o.")

        let latest = build(input(latestReceipts: [(invoice: invoice, effect: effect(total: 8_000))])).latestReceipts

        let receipt = try #require(latest.first)
        #expect(receipt.invoiceID == 11)
        #expect(receipt.date == "15.\u{00A0}10.")
        #expect(receipt.number == "20260902")
        #expect(receipt.client == "Cetus Data s.r.o.")
        #expect(receipt.original == "5\u{00A0}445,00\u{00A0}Kč vč. DPH 945,00")
        #expect(receipt.czk == "4\u{00A0}500,00\u{00A0}Kč")
        #expect(receipt.effect == "+8\u{00A0}000\u{00A0}Kč")
    }

    @Test func aReceiptInACrownInvoiceWithoutVATHasNoVATPart() throws {
        var invoice = paidInvoice(id: 11, number: "20260902", paidOn: "2026-10-15")
        invoice.vatMode = .none
        invoice.payment = .fixture(on: "2026-10-15", net: 450_000, vat: 0)

        let latest = build(input(latestReceipts: [(invoice: invoice, effect: effect(total: 8_000))])).latestReceipts

        #expect(try #require(latest.first).original == "4\u{00A0}500,00\u{00A0}Kč")
    }

    @Test func aReceiptInADollarInvoiceShowsTheAmountInDollarsAndTheRateOfTheDay() throws {
        var invoice = SearchFixtures.dollarInvoice()
        invoice.id = 10

        let latest = build(input(latestReceipts: [(invoice: invoice, effect: effect(total: 21_000))])).latestReceipts

        let receipt = try #require(latest.first)
        #expect(receipt.date == "2.\u{00A0}10.")
        #expect(receipt.original == "14\u{00A0}350,00\u{00A0}USD · kurz 21,305")
        #expect(receipt.czk == "305\u{00A0}726,75\u{00A0}Kč")
        #expect(receipt.effect == "+21\u{00A0}000\u{00A0}Kč")
    }

    @Test func anAmountFromTheBankIsShownAsEnteredByHand() throws {
        var invoice = SearchFixtures.dollarInvoice()
        invoice.id = 10
        invoice.payment = .fixture(
            on: "2026-10-02", conversion: .bankCZK, net: 30_600_000, vat: 0, bankCZKTotalHalere: 30_600_000)

        let receipt = try #require(
            build(input(latestReceipts: [(invoice: invoice, effect: effect(total: 1))])).latestReceipts.first)

        #expect(receipt.original == "14\u{00A0}350,00\u{00A0}USD · zadáno ručně")
        #expect(receipt.czk == "306\u{00A0}000,00\u{00A0}Kč")
    }

    @Test func aProvisionalPaymentIsMarkedAsAnEstimate() throws {
        var invoice = SearchFixtures.dollarInvoice()
        invoice.id = 10
        // 14 350,00 USD at the rate of the invoice, 21,622, until the rate of the day is declared.
        invoice.payment = .fixture(
            on: "2026-10-02", conversion: .cnbDaily, net: 31_027_570, vat: 0,
            rate: storedRate("USD", "21.622", declaredOn: "2026-09-30"), provisional: true)

        let receipt = try #require(
            build(input(latestReceipts: [(invoice: invoice, effect: effect(total: 1))])).latestReceipts.first)

        #expect(receipt.czk == "≈ 310\u{00A0}275,70\u{00A0}Kč")
        #expect(receipt.original == "14\u{00A0}350,00\u{00A0}USD · kurz 21,622")
    }

    @Test func aReceiptOfAPastYearLeavesOutThatYearLikeEveryOtherReceiptOfTheScreen() throws {
        // Viewed from 2025, in 2026: the year of the screen is 2025, so its dates have no year.
        let invoice = paidInvoice(id: 1, number: "20250901", paidOn: "2025-10-10")
        var overview = year2025(social: 10_000, health: 6_000).input
        overview.latestReceipts = [(invoice: invoice, effect: effect(total: 2_000, on: "2025-10-10"))]

        let latest = build(overview).latestReceipts

        #expect(try #require(latest.first).date == "10.\u{00A0}10.")
    }

    @Test func aReceiptThatLowersTheLeviesShowsTheMinusSign() throws {
        let invoice = paidInvoice(id: 1, number: "20260901", paidOn: "2026-10-15")

        let latest = build(input(latestReceipts: [(invoice: invoice, effect: effect(total: -500))])).latestReceipts

        #expect(try #require(latest.first).effect == "\u{2212}500\u{00A0}Kč")
    }

    @Test func anInvoiceInReviewAndADraftAreNotAmongTheLatestReceipts() {
        var inReview = paidInvoice(id: 1, number: "20260901", paidOn: "2026-10-15")
        inReview.review = ReviewFlag(reason: "záporná částka")
        var draft = paidInvoice(id: 2, number: "20260902", paidOn: "2026-10-14")
        draft.status = .draft
        let paid = paidInvoice(id: 3, number: "20260903", paidOn: "2026-10-13")
        let receipts = [inReview, draft, paid].map { (invoice: $0, effect: effect(total: 1_000)) }

        let latest = build(input(latestReceipts: receipts)).latestReceipts

        #expect(latest.map(\.invoiceID) == [3])
    }

    @Test func aDayWithoutAReceiptHasNoLatestReceipts() {
        #expect(build(input()).latestReceipts.isEmpty)
    }

    // MARK: The estimate of the whole year

    /// The estimate of the prediction sample's 2026 as of Saturday 17. 10. 2026: 2 743 156,99 Kč of income, of which
    /// 2 191 771,35 Kč has come, levies of 114 786, 247 832 and 104 164 Kč, and advances of 268 080 Kč. The figures
    /// were worked out for the same data by a separate implementation.
    private func sampleEstimate() throws -> PredictionOutcome {
        try PredictionSample.outcome(year: 2026)
    }

    /// The prediction sample's 2026 without its clients, invoices, templates and receipts: no income, the minimum
    /// insurance of the whole year (99 720 Kč), and advances that pay 168 360 Kč more than that.
    private func estimateWithoutIncome() throws -> PredictionOutcome {
        var empty = PredictionSample.input(year: 2026)
        empty.clients = []
        empty.invoices = []
        empty.templates = []
        empty.receipts = []
        return try PredictionSample.outcome(of: empty)
    }

    @Test func theCardSaysTheYearsEstimate() throws {
        let card = try #require(build(input(prediction: try sampleEstimate())).prediction)

        #expect(card.head == "Odhad za celý rok 2026")
        #expect(card.sub == "z faktur do 17.\u{00A0}10.\u{00A0}2026 · co ještě do 31.\u{00A0}12. přijde")
        #expect(
            card.stats == [
                PredictionMini(
                    label: "Příjmy za rok", value: "2\u{00A0}743\u{00A0}157\u{00A0}Kč",
                    sub: "z toho přišlo 2\u{00A0}191\u{00A0}771\u{00A0}Kč"),
                PredictionMini(
                    label: "Odvody", value: "466\u{00A0}782\u{00A0}Kč",
                    share: "17,0\u{00A0}%",
                    sub: "daň 114\u{00A0}786 · sociální 247\u{00A0}832 · zdravotní 104\u{00A0}164"),
                PredictionMini(
                    label: "Doplatek", value: "198\u{00A0}702\u{00A0}Kč",
                    sub: "po zálohách 268\u{00A0}080\u{00A0}Kč za celý rok"),
                PredictionMini(
                    label: "Čistý příjem průměrně za měsíc", value: "189\u{00A0}698\u{00A0}Kč",
                    sub: "za celý rok 2\u{00A0}276\u{00A0}375\u{00A0}Kč"),
            ])
    }

    @Test func theCardShowsOnlyForTheCurrentYearWhileItsEstimateIsOpen() throws {
        let estimate = try sampleEstimate()

        // The input has no estimate unless it is given one.
        #expect(build(input()).prediction == nil)
        #expect(build(input(prediction: estimate)).prediction != nil)

        // The last day of the year closes the estimate of the current year.
        let lastDay = try PredictionSample.outcome(year: 2026, today: civilDate("2026-12-31"))
        #expect(lastDay.prediction.isClosed)
        #expect(build(input(today: "2026-12-31", prediction: lastDay)).prediction == nil)

        // A past year is closed, and the estimate of the current year is none for a year that is not the current one.
        let past = try PredictionSample.outcome(year: 2025)
        #expect(past.prediction.isClosed)
        #expect(build(input(year: 2025, asOf: "2025-12-31", prediction: past)).prediction == nil)
        #expect(build(input(year: 2025, asOf: "2025-12-31", prediction: estimate)).prediction == nil)
    }

    @Test func theCardIsTheSameWhateverDayIsShown() throws {
        let estimate = try sampleEstimate()
        let atToday = try #require(build(input(prediction: estimate)).prediction)

        // Earlier in the year, and a day that is yet to come, which is a simulation.
        for day in ["2026-03-31", "2026-12-31"] {
            #expect(build(input(asOf: day, prediction: estimate)).prediction == atToday)
        }
    }

    /// Nothing owed and something overpaid is an overpayment. Anything else is a sum to pay: also when nothing is owed
    /// and nothing is overpaid, and when one authority is overpaid and another is owed.
    @Test func theCardNamesAnOverpaymentOnlyWhereNothingIsOwed() throws {
        let overpaid = try #require(build(input(prediction: try estimateWithoutIncome())).prediction)

        #expect(
            overpaid.stats == [
                PredictionMini(label: "Příjmy za rok", value: "0\u{00A0}Kč", sub: "z toho přišlo 0\u{00A0}Kč"),
                PredictionMini(
                    label: "Odvody", value: "99\u{00A0}720\u{00A0}Kč",
                    sub: "daň 0 · sociální 60\u{00A0}056 · zdravotní 39\u{00A0}664"),
                PredictionMini(label: "Přeplatek", value: "168\u{00A0}360\u{00A0}Kč", sub: "zálohy převýší odvody"),
                PredictionMini(
                    label: "Čistý příjem průměrně za měsíc", value: "\u{2212}8\u{00A0}310\u{00A0}Kč",
                    sub: "za celý rok \u{2212}99\u{00A0}720\u{00A0}Kč"),
            ])

        // Advances that pay exactly the levies leave nothing to settle: that is a sum of nothing to pay.
        let none = [Int64](repeating: 0, count: 12)
        var taxInput = PredictionSample.yearInput(year: 2026)
        taxInput.receipts = []
        taxInput.advances = AdvancePlan(
            social: [60_056] + none.dropFirst(), health: [39_664] + none.dropFirst(), tax: none)
        let exact = try PredictionOutcome.make(
            prediction: try estimateWithoutIncome().prediction, yearInput: taxInput)
        #expect(
            try #require(build(input(prediction: exact)).prediction).stats[2]
                == PredictionMini(
                    label: "Doplatek", value: "0\u{00A0}Kč",
                    sub: "po zálohách 99\u{00A0}720\u{00A0}Kč za celý rok"))

        // On 30. 12. the tax advances pay more than the tax while the insurance is owed: an overpayment at one
        // authority does not lower what another is owed, so the card names what is owed and no overpayment.
        let mixed = try PredictionSample.outcome(year: 2026, today: civilDate("2026-12-30"))
        #expect(!mixed.prediction.isClosed)
        #expect(mixed.owedTotal > 0 && mixed.overpaidTotal > 0)
        let settlement = try #require(build(input(today: "2026-12-30", prediction: mixed)).prediction).stats[2]
        #expect(settlement.label == "Doplatek")
        #expect(settlement.value == CzechFormat.wholeKc(mixed.owedTotal))
        #expect(settlement.sub == "po zálohách " + CzechFormat.wholeKc(mixed.result.advancesPaidTotal) + " za celý rok")
    }

    /// A single payment of 200 000 Kč leaves the tax at nothing, and the children's 37 524 Kč are paid as a bonus: the
    /// tax reads as a bonus in the split of the levies, as it does everywhere else.
    @Test func aTaxBonusReadsAsABonusInTheSplitOfTheLevies() throws {
        let client = Client(id: 1, name: "Jediný s.r.o.", dueDays: 14)
        var invoice = Invoice.fixture(
            number: "20260301", issued: "2026-03-01", duzp: "2026-03-01", dueDate: "2026-03-15",
            items: [.fixture("1", at: 20_000_000)],
            payment: Payment.fixture(on: "2026-03-10", net: 20_000_000, vat: 0))
        invoice.id = 1
        invoice.clientID = client.id
        var single = PredictionSample.input(year: 2026)
        single.clients = [client]
        single.invoices = [invoice]
        single.templates = []
        single.receipts = PredictionSample.receipts(of: [invoice], year: 2026)
        let estimate = try PredictionSample.outcome(of: single)

        let levies = try #require(build(input(prediction: estimate)).prediction).stats[1]

        let social = CzechFormat.grouped(estimate.result.balance(.social).liability)
        let health = CzechFormat.grouped(estimate.result.balance(.health).liability)
        #expect(levies.label == "Odvody")
        #expect(levies.value == CzechFormat.wholeKc(estimate.result.liabilityTotal))
        #expect(levies.sub == "daňový bonus 37\u{00A0}524 · sociální \(social) · zdravotní \(health)")
    }

    /// The card is an area of estimates as a whole, so none of its texts carries the sign "≈": not the head, the line
    /// under it, the labels, the four figures, the share beside one of them, the lines under them, and not the months
    /// of its chart, also a month whose issued amount is approximate: that month says so in its note alone.
    @Test func theEstimateCardHasNoApproximationSign() throws {
        // October also has an invoice in dollars that waits for its payment and for the rate of its day, so that it is
        // worth the latest declared rate: an approximate amount, which the note under the figures of the month
        // explains.
        var provisional = chartRow(
            id: 99, issued: "2026-10-10", currency: .usd, net: 1_000_000, issueDayRate: usd("21.5"))
        provisional.issueDayRateIsProvisional = true
        let rows = SampleYear2026.chartRows + [provisional]
        for estimate in [try sampleEstimate(), try estimateWithoutIncome()] {
            let card = try #require(build(input(chartRows: rows, prediction: estimate)).prediction)
            #expect(card.chart[9].issuedActualIsApproximate)
            #expect(card.chart[9].notes.contains(ChartColumn.approximateIssuedNote))
            let figures = card.stats.flatMap { [$0.label, $0.value, $0.share ?? "", $0.sub] }
            let months = card.chart.flatMap { month in
                [
                    month.title, month.issuedActualText, month.issuedEstimateText, month.receivedActualText,
                    month.receivedEstimateText, month.netActualText, month.netEstimateText, month.accessibilityLabel,
                ] + month.notes
            }
            #expect(!card.chart.isEmpty)
            for text in [card.head, card.sub] + figures + months {
                #expect(!text.contains("≈"), "\(text)")
            }
        }
    }

    /// The tax and the insurance of the year are "Odvody", and the share of the income they take stands beside the
    /// figure as its own part of the tile, "17,0 %". The sum owed beyond the advances is "Doplatek", and what the
    /// advances overpay "Přeplatek". The old names are gone.
    @Test func theEstimateCardNamesOdvodyWithItsShare() throws {
        let card = try #require(build(input(prediction: try sampleEstimate())).prediction)

        let levies = card.stats[1]
        #expect(levies.label == "Odvody")
        #expect(levies.value == "466\u{00A0}782\u{00A0}Kč")
        #expect(levies.share == "17,0\u{00A0}%")
        #expect(card.stats.map(\.label) == ["Příjmy za rok", "Odvody", "Doplatek", "Čistý příjem průměrně za měsíc"])
        // Only the levies have a share of the income.
        #expect(card.stats.map { $0.share == nil } == [true, false, true, true])
        let overpaid = try #require(build(input(prediction: try estimateWithoutIncome())).prediction)
        #expect(
            overpaid.stats.map(\.label) == ["Příjmy za rok", "Odvody", "Přeplatek", "Čistý příjem průměrně za měsíc"])
    }

    /// An estimate that is not complete has dashes for its figures and says why under each, under the same labels as
    /// the complete one; the income that has come is still told.
    @Test func anIncompleteEstimateHasDashesUnderTheSameLabels() throws {
        var forecast = PredictionSample.input(year: 2026)
        forecast.averageRates = [:]
        let waitingClient = Client(id: 4, name: "Čekající", dueDays: 14)
        var waiting = Invoice.fixture(
            number: "WAITING-1", issued: "2026-10-01", duzp: "2026-10-01", dueDate: "2026-10-15",
            items: [.fixture("1", at: 1_000_000)])
        waiting.clientID = waitingClient.id
        forecast.clients.append(waitingClient)
        forecast.invoices.append(waiting)
        let outcome = try PredictionOutcome.make(
            prediction: IncomePrediction.make(forecast), yearInput: PredictionSample.yearInput(year: 2026))
        try #require(!outcome.prediction.isComplete)

        let card = try #require(build(input(prediction: outcome)).prediction)

        #expect(card.stats.map(\.label) == ["Příjmy za rok", "Odvody", "Doplatek", "Čistý příjem průměrně za měsíc"])
        #expect(card.stats.allSatisfy { $0.value == "—" && $0.share == nil })
        #expect(card.stats[0].sub.hasPrefix("z toho přišlo "))
        #expect(card.stats.dropFirst().allSatisfy { $0.sub.hasPrefix("Odhad je neúplný: ") })
        #expect(card.sub.hasPrefix("Odhad je neúplný: "))
        for stat in card.stats {
            #expect(!stat.value.contains("≈") && !stat.sub.contains("≈"))
        }
    }

    /// An incomplete forecast suppresses its combined chart without hiding the ordinary actual-income chart.
    @Test func anIncompleteForecastKeepsTheActualChartAndOmitsItsEstimateChart() throws {
        var forecast = PredictionSample.input(year: 2026)
        forecast.averageRates = [:]
        let outcome = try PredictionOutcome.make(
            prediction: IncomePrediction.make(forecast), yearInput: PredictionSample.yearInput(year: 2026))
        let page = OverviewBuilder.build(input(chartRows: sampleChartRows, prediction: outcome))
        #expect(page.prediction?.chart.isEmpty == true)
        #expect(page.columns.count == 12)
        #expect(page.columns == OverviewBuilder.build(input(chartRows: sampleChartRows)).columns)
    }

    /// Unknown December issuance paid in January suppresses its chart while the complete annual figures remain.
    @Test(arguments: [false, true])
    func unknownNextYearPaymentsDoNotPublishCompleteIssuance(_ hasKnownDraft: Bool) throws {
        let client = Client(id: 1, name: "Prosinec", dueDays: 30)
        var unknown = Invoice.fixture(
            number: "NEXT-1", currency: .usd, issued: "2026-12-20", duzp: "2026-12-20",
            dueDate: "2027-01-19", items: [.fixture("1", at: 10_000)], vatMode: .none, status: .draft)
        unknown.clientID = client.id
        var invoices = [unknown]
        if hasKnownDraft {
            var known = Invoice.fixture(
                number: "NEXT-2", issued: "2026-12-20", duzp: "2026-12-20",
                dueDate: "2027-01-19", items: [.fixture("1", at: 100_000)], vatMode: .none, status: .draft)
            known.clientID = client.id
            invoices.append(known)
        }
        var forecast = PredictionSample.input(year: 2026)
        forecast.clients = [client]
        forecast.invoices = invoices
        forecast.templates = []
        forecast.receipts = []
        forecast.rates = [:]
        forecast.averageRates = [:]
        var yearInput = PredictionSample.yearInput(year: 2026)
        yearInput.receipts = []
        let outcome = try PredictionOutcome.make(prediction: IncomePrediction.make(forecast), yearInput: yearInput)
        try #require(outcome.prediction.isComplete)
        try #require(outcome.prediction.hasUnknownNextYearAmount)
        #expect(outcome.prediction.expectedInvoices.first?.payDay == civilDate("2027-01-19"))
        let page = OverviewBuilder.build(input(chartRows: sampleChartRows, prediction: outcome))
        let card = try #require(page.prediction)
        #expect(card.chart.isEmpty)
        #expect(card.stats[0].value == "0\u{00A0}Kč")
        #expect(card.stats.allSatisfy { $0.value != "—" })
        #expect(page.columns == OverviewBuilder.build(input(chartRows: sampleChartRows)).columns)
    }

}
