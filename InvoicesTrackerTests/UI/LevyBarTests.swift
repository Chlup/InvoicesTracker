import CoreGraphics
import Foundation
import Testing
@testable import InvoicesTracker

/// The bar of the levies ("Pruh odvodů"): how its three parts share its width and where the popover of a part stands,
/// and what the builder writes into it from the balances of a year. The sample year is the engine's regression year as
/// of 17. 10. 2026, whose figures were worked out for the same data by a separate implementation of the rules; the
/// other years are those of the tests of Výpočet. In every expected string `\u{00A0}` is the no-break space.
struct LevyBarTests {
    // MARK: How the parts share the bar

    @Test func positiveLeviesShareTheBarInProportionWithTwoPointGaps() {
        let weights: [Int64] = [94_440, 159_279, 66_945]

        let widths = LevyBarLayout.partWidths(weights: weights, width: 404)

        // Two gaps of 2 points leave 400 for the three parts.
        #expect(widths.count == 3)
        #expect(abs(widths.reduce(0, +) - 400) < 0.001)
        let total = CGFloat(weights.reduce(0, +))
        for (width, weight) in zip(widths, weights) {
            #expect(abs(width - 400 * CGFloat(weight) / total) <= 0.5, "\(width) for \(weight)")
            #expect(width >= 4)
        }
    }

    @Test func aSmallLevyKeepsFourPoints() {
        let widths = LevyBarLayout.partWidths(weights: [100, 1_000_000, 1_000_000], width: 404)

        #expect(widths[0] == 4)
        // The other two share the 396 points that are left in proportion.
        #expect(abs(widths[1] - 198) < 0.001)
        #expect(abs(widths[2] - 198) < 0.001)
    }

    @Test func aTaxBonusOrAZeroLevyGetsNoPartAndNoGap() {
        #expect(LevyBarLayout.partWidths(weights: [-37_524, 100, 100], width: 202) == [0, 100, 100])
        #expect(LevyBarLayout.partWidths(weights: [100, 0, 100], width: 202) == [100, 0, 100])
        // A part alone has the whole bar, with no gap at all.
        #expect(LevyBarLayout.partWidths(weights: [0, 5, -1], width: 300) == [0, 300, 0])
    }

    @Test func allZeroLeviesLeaveAnEmptyTrack() {
        #expect(LevyBarLayout.partWidths(weights: [0, 0, 0], width: 300) == [0, 0, 0])
        #expect(LevyBarLayout.partWidths(weights: [-37_524, 0, 0], width: 300) == [0, 0, 0])
    }

    @Test func aBarTooNarrowForTheLeastWidthOfEachPartSharesItEqually() {
        // 10 points less the two gaps leave 6, less than 4 for each of three parts.
        #expect(LevyBarLayout.partWidths(weights: [1, 1, 1_000], width: 10) == [2, 2, 2])
    }

    @Test func aPartIsCentredWhereItIsDrawn() {
        // Three parts of 400 points with the two gaps of 2 between them.
        #expect(LevyBarLayout.partCentres(widths: [100, 200, 96]) == [50, 202, 352])
        // A part of no width lies where the next part begins.
        #expect(LevyBarLayout.partCentres(widths: [0, 100, 100]) == [0, 50, 152])
        #expect(LevyBarLayout.partCentres(widths: [100, 0, 100]) == [50, 102, 152])
    }

    @Test func thePopoverIsCentredOnItsPartAndKeptInsideThePanel() {
        // The popover is 260 points wide, centred on its part unless that puts it out of the panel at either end.
        #expect(LevyBarLayout.popoverX(centredOn: 200, panelWidth: 404) == 70)
        #expect(LevyBarLayout.popoverX(centredOn: 20, panelWidth: 404) == 0)
        #expect(LevyBarLayout.popoverX(centredOn: 380, panelWidth: 404) == 144)
        // A panel narrower than the popover has it at its leading edge.
        #expect(LevyBarLayout.popoverX(centredOn: 100, panelWidth: 200) == 0)
    }

    // MARK: The names of the authorities

    @Test func anAuthorityHasItsFullNameItsShortNameAndItsOffice() {
        #expect(Authority.allCases.map(\.title) == ["Daň z příjmů", "Sociální pojištění", "Zdravotní pojištění"])
        #expect(Authority.allCases.map(\.shortTitle) == ["Daň", "Sociální", "Zdravotní"])
        #expect(Authority.allCases.map(\.office) == ["Finanční úřad", "ČSSZ", "VZP"])
        // The columns and tiles of Výpočet name the authorities by the same short names.
        #expect(Authority.allCases.map { ComputationBuilder.shortName(of: $0) } == ["Daň", "Sociální", "Zdravotní"])
    }

    // MARK: The bar of the balances

    /// The sample year as of 17. 10. 2026: the result of Výpočet and Přehled.
    private let sample = TaxEngine.compute(TaxEngineRegressionTests.sampleYear2026, asOf: civilDate("2026-10-17"))

    private let header = "Odvody z příjmů do 17.\u{00A0}10."

    /// The labels of the rows of the popover of each part, tax first.
    private func rowLabels(of data: LevyBarData) -> [[String]] {
        data.parts.map { $0.rows.map(\.label) }
    }

    @Test func theBalancesBarOfAYearInProgressNamesWhatIsLeft() {
        let data = LevyBarBuilder.balances(of: sample, kind: .toDate(isOver: false), header: header, showsTotal: true)

        #expect(data.header == header)
        #expect(data.total == "320\u{00A0}664\u{00A0}Kč")
        #expect(data.totalShare == "14,6\u{00A0}% z příjmů")
        #expect(data.parts.map(\.authority) == [.tax, .social, .health])
        #expect(data.parts.map(\.id) == [.tax, .social, .health])
        #expect(data.parts.map(\.weight) == [94_440, 159_279, 66_945])
        #expect(
            data.parts.map(\.legendValue) == [
                "94\u{00A0}440\u{00A0}Kč", "159\u{00A0}279\u{00A0}Kč", "66\u{00A0}945\u{00A0}Kč",
            ])
        #expect(
            data.parts[0].rows == [
                LevyPopoverRow(label: "Odvody z příjmů", value: "94\u{00A0}440\u{00A0}Kč", style: .strong),
                LevyPopoverRow(label: "Zaplaceno zálohami", value: "23\u{00A0}000\u{00A0}Kč", style: .muted),
                LevyPopoverRow(label: "Zbývá", value: "71\u{00A0}440\u{00A0}Kč", style: .strong),
            ])
        // The insurance advances through October: 4 × 13 340 and 6 × 12 150 Kč, 4 × 6 920 and 6 × 5 480 Kč.
        #expect(
            data.parts[1].rows == [
                LevyPopoverRow(label: "Odvody z příjmů", value: "159\u{00A0}279\u{00A0}Kč", style: .strong),
                LevyPopoverRow(label: "Zaplaceno zálohami", value: "126\u{00A0}260\u{00A0}Kč", style: .muted),
                LevyPopoverRow(label: "Zbývá", value: "33\u{00A0}019\u{00A0}Kč", style: .strong),
            ])
        #expect(
            data.parts[2].rows == [
                LevyPopoverRow(label: "Odvody z příjmů", value: "66\u{00A0}945\u{00A0}Kč", style: .strong),
                LevyPopoverRow(label: "Zaplaceno zálohami", value: "60\u{00A0}560\u{00A0}Kč", style: .muted),
                LevyPopoverRow(label: "Zbývá", value: "6\u{00A0}385\u{00A0}Kč", style: .strong),
            ])
        // The shares add up to the 14,6 % of the three together.
        #expect(
            data.parts.map(\.shareLine) == [
                "4,3\u{00A0}% z příjmů bez DPH", "7,3\u{00A0}% z příjmů bez DPH", "3,0\u{00A0}% z příjmů bez DPH",
            ])
        #expect(data.parts.allSatisfy { $0.note == nil })
        #expect(
            data.accessibilityLabel.hasPrefix(
                "Odvody z příjmů do 17.\u{00A0}10.: Daň z příjmů 94\u{00A0}440\u{00A0}Kč"))
        #expect(
            data.accessibilityLabel
                == "Odvody z příjmů do 17.\u{00A0}10.: Daň z příjmů 94\u{00A0}440\u{00A0}Kč,"
                + " Sociální pojištění 159\u{00A0}279\u{00A0}Kč, Zdravotní pojištění 66\u{00A0}945\u{00A0}Kč")
    }

    @Test func aLegendItemReadsTheRowsOfItsPopoverAndItsShare() {
        let data = LevyBarBuilder.balances(of: sample, kind: .toDate(isOver: false), header: header, showsTotal: true)

        #expect(
            data.parts.map(\.accessibilityLabel) == [
                "Daň z příjmů: odvody z příjmů 94\u{00A0}440\u{00A0}Kč, zaplaceno zálohami 23\u{00A0}000\u{00A0}Kč,"
                    + " zbývá 71\u{00A0}440\u{00A0}Kč, 4,3\u{00A0}% z příjmů bez DPH",
                "Sociální pojištění: odvody z příjmů 159\u{00A0}279\u{00A0}Kč, zaplaceno zálohami"
                    + " 126\u{00A0}260\u{00A0}Kč, zbývá 33\u{00A0}019\u{00A0}Kč, 7,3\u{00A0}% z příjmů bez DPH",
                "Zdravotní pojištění: odvody z příjmů 66\u{00A0}945\u{00A0}Kč, zaplaceno zálohami"
                    + " 60\u{00A0}560\u{00A0}Kč, zbývá 6\u{00A0}385\u{00A0}Kč, 3,0\u{00A0}% z příjmů bez DPH",
            ])
    }

    @Test func aLegendItemReadsTheNoteOfItsPartToo() {
        let rows = [LevyPopoverRow(label: "Za rok", value: "50\u{00A0}046\u{00A0}Kč", style: .strong)]

        #expect(
            LevyBarBuilder.accessibilityLabel(of: .social, rows: rows, shareLine: nil, note: "platíte minimum")
                == "Sociální pojištění: za rok 50\u{00A0}046\u{00A0}Kč, platíte minimum")
        #expect(
            LevyBarBuilder.accessibilityLabel(of: .health, rows: rows, shareLine: nil, note: nil)
                == "Zdravotní pojištění: za rok 50\u{00A0}046\u{00A0}Kč")
    }

    @Test func aFinishedYearSaysDoplatekAndOdvodyZaRok() {
        // 2025 with 600 000 Kč and no advances, as of its last day: all of each levy is the doplatek.
        let result = TaxEngine.compute(
            computationYearInput(year: 2025, netHalere: 60_000_000), asOf: civilDate("2025-12-31"))

        let data = LevyBarBuilder.balances(
            of: result, kind: .toDate(isOver: true), header: "Odvody za rok 2025", showsTotal: true)

        let finished = ["Odvody za rok", "Zaplaceno zálohami", "Doplatek"]
        #expect(rowLabels(of: data) == [finished, finished, finished])
        for (part, authority) in zip(data.parts, Authority.allCases) {
            let balance = result.balance(authority)
            #expect(
                part.rows.last
                    == LevyPopoverRow(label: "Doplatek", value: CzechFormat.wholeKc(balance.remaining), style: .strong))
            #expect(balance.remaining == balance.liability)
        }
        #expect(data.total == CzechFormat.wholeKc(result.liabilityTotal))
    }

    @Test func aWholeYearBarSaysZalohyZaRok() {
        // The sample year as of its last day: the plan pays 46 000 Kč of tax advances, 150 560 Kč of social insurance
        // (4 × 13 340 and 8 × 12 150) and 71 520 Kč of health insurance (4 × 6 920 and 8 × 5 480), which is more than
        // the 66 945 Kč the health insurance comes to.
        let result = TaxEngine.compute(TaxEngineRegressionTests.sampleYear2026, asOf: civilDate("2026-12-31"))

        let data = LevyBarBuilder.balances(
            of: result, kind: .wholeYear, header: "Odvody za celý rok 2026 podle úřadů", showsTotal: false)

        #expect(
            rowLabels(of: data) == [
                ["Odvody za rok", "Zálohy za rok", "Doplatek"],
                ["Odvody za rok", "Zálohy za rok", "Doplatek"],
                ["Odvody za rok", "Zálohy za rok", "Přeplatek"],
            ])
        #expect(
            data.parts[0].rows == [
                LevyPopoverRow(label: "Odvody za rok", value: "94\u{00A0}440\u{00A0}Kč", style: .strong),
                LevyPopoverRow(label: "Zálohy za rok", value: "46\u{00A0}000\u{00A0}Kč", style: .muted),
                LevyPopoverRow(label: "Doplatek", value: "48\u{00A0}440\u{00A0}Kč", style: .strong),
            ])
        #expect(
            data.parts[1].rows.suffix(2) == [
                LevyPopoverRow(label: "Zálohy za rok", value: "150\u{00A0}560\u{00A0}Kč", style: .muted),
                LevyPopoverRow(label: "Doplatek", value: "8\u{00A0}719\u{00A0}Kč", style: .strong),
            ])
        #expect(
            data.parts[2].rows.suffix(2) == [
                LevyPopoverRow(label: "Zálohy za rok", value: "71\u{00A0}520\u{00A0}Kč", style: .muted),
                LevyPopoverRow(label: "Přeplatek", value: "4\u{00A0}575\u{00A0}Kč", style: .positive),
            ])
        // The key figure beside the bar shows the total, so the bar does not.
        #expect(data.total == nil)
        #expect(data.totalShare == nil)
        #expect(data.header == "Odvody za celý rok 2026 podle úřadů")
    }

    @Test func aTaxBonusIsLegendedAsABonusAndReturnsInGreen() throws {
        // The sample family with 120 000 Kč received on 20. 1. and 130 000 Kč on 20. 2. 2026, and a tax advance of
        // 10 000 Kč paid in January: as of 28. 2. the children's 37 524 Kč are all a tax bonus, and the tax office
        // returns the advance with the bonus.
        var input = TaxEngineFamilyTests.input(TaxEngineFamilyTests.earlyReceipts)
        input.advances.tax[0] = 10_000
        let result = TaxEngine.compute(input, asOf: civilDate("2026-02-28"))
        #expect(result.childBonus > 0)
        #expect(result.balance(.tax).liability < 0)

        let data = LevyBarBuilder.balances(
            of: result, kind: .toDate(isOver: false), header: "Odvody z příjmů do 28.\u{00A0}2.", showsTotal: true)

        let tax = try #require(data.parts.first)
        #expect(tax.authority == .tax)
        #expect(tax.weight < 0)
        #expect(tax.weight == -37_524)
        #expect(tax.legendValue.hasPrefix("bonus "))
        #expect(tax.legendValue == "bonus 37\u{00A0}524\u{00A0}Kč")
        #expect(
            tax.rows == [
                LevyPopoverRow(label: "Odvody z příjmů", value: "bonus 37\u{00A0}524\u{00A0}Kč", style: .strong),
                LevyPopoverRow(label: "Zaplaceno zálohami", value: "10\u{00A0}000\u{00A0}Kč", style: .muted),
                LevyPopoverRow(label: "Vrátí se", value: "47\u{00A0}524\u{00A0}Kč", style: .positive),
            ])
        #expect(
            tax.rows.last == LevyPopoverRow(
                label: "Vrátí se", value: CzechFormat.wholeKc(result.balance(.tax).overpayment), style: .positive))
        #expect(tax.shareLine?.hasPrefix("\u{2212}") == true)
        #expect(tax.accessibilityLabel.hasPrefix("Daň z příjmů: odvody z příjmů bonus 37\u{00A0}524\u{00A0}Kč,"))
        #expect(tax.accessibilityLabel.contains(", vrátí se 47\u{00A0}524\u{00A0}Kč, \u{2212}"))
        #expect(data.accessibilityLabel.hasPrefix("Odvody z příjmů do 28.\u{00A0}2.: Daň z příjmů bonus 37\u{00A0}524"))
    }

    @Test func anOverpaidAuthorityReadsPreplatek() {
        // The tax is 0 Kč and 10 000 Kč of income tax advances were paid in March. The social insurance is 50 046 Kč
        // and 60 000 Kč were paid in March, the health insurance 33 053 Kč and 40 000 Kč.
        var advances = AdvancePlan.empty
        advances.tax[2] = 10_000
        advances.social[2] = 60_000
        advances.health[2] = 40_000
        let result = TaxEngine.compute(
            computationYearInput(netHalere: 10_000_150, advances: advances), asOf: civilDate("2026-10-17"))

        let data = LevyBarBuilder.balances(of: result, kind: .toDate(isOver: false), header: header, showsTotal: true)

        #expect(
            data.parts.map { $0.rows.last } == [
                LevyPopoverRow(label: "Přeplatek", value: "10\u{00A0}000\u{00A0}Kč", style: .positive),
                LevyPopoverRow(label: "Přeplatek", value: "9\u{00A0}954\u{00A0}Kč", style: .positive),
                LevyPopoverRow(label: "Přeplatek", value: "6\u{00A0}947\u{00A0}Kč", style: .positive),
            ])
        // A tax of nothing draws no part, and its legend says so.
        #expect(data.parts[0].weight == 0)
        #expect(data.parts[0].legendValue == "0\u{00A0}Kč")
    }

    @Test func withoutIncomeTheBarHasNoShares() {
        // Nothing received by the end of January: the minimum insurance is due, but there is no income to take a
        // share of.
        let result = TaxEngine.compute(computationYearInput(), asOf: civilDate("2026-01-31"))

        let data = LevyBarBuilder.balances(
            of: result, kind: .toDate(isOver: false), header: "Odvody z příjmů do 31.\u{00A0}1.", showsTotal: true)

        #expect(data.total == CzechFormat.wholeKc(result.liabilityTotal))
        #expect(data.totalShare == nil)
        #expect(data.parts.allSatisfy { $0.shareLine == nil })
        #expect(data.parts[0].accessibilityLabel.hasSuffix("zbývá 0\u{00A0}Kč"))
    }
}
