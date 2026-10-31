import AppKit
import CoreGraphics
import Foundation
import SwiftUI
import Testing
@testable import InvoicesTracker

/// The numbers and texts that the views of Přehled draw from, apart from what the builder works out: the scale and the
/// lines of the income chart, the size of its tooltip and where it goes, the tooltip's row for the net income with the
/// note under it and its footer for the average, with the sentence under it for a year computed with the rules of
/// another year, the legend of the chart, whose keys wrap whole onto a further row where the card has no room for them
/// side by side, and the New Year banner. The expected scale and line texts were worked out for the same amounts by a
/// separate implementation, run in node. In every expected string `\u{00A0}` is the no-break space.
struct OverviewViewTextTests {
    // MARK: The scale of the chart

    @Test(arguments: [
        (0 as Int64, 10_000_000 as Int64), (-5, 10_000_000),
        (100, 100), (4_000, 4_000), (40_000, 40_000), (399_999, 400_000), (1_000_000, 1_000_000),
        (4_000_000, 4_000_000), (5_000_000, 6_000_000), (9_999_999, 10_000_000), (22_000_000, 24_000_000),
        (23_900_000, 24_000_000), (37_000_000, 40_000_000), (40_000_000, 40_000_000), (40_000_001, 48_000_000),
        (52_000_000, 60_000_000), (61_000_000, 80_000_000), (100_000_000, 100_000_000),
        (123_456_789, 160_000_000), (400_000_000, 400_000_000), (999_999_999, 1_000_000_000),
        (1_500_000_000, 1_600_000_000),
    ])
    func theTopOfTheChartIsFourEqualStepsOfRoundSize(largest: Int64, top: Int64) {
        #expect(IncomeChartLayout.top(forLargest: largest) == top)
    }

    @Test func theTopIsNeverBelowTheLargestAmount() {
        for largest in stride(from: Int64(1), to: 3_000_000_000, by: 7_654_321) {
            #expect(IncomeChartLayout.top(forLargest: largest) >= largest)
        }
    }

    @Test(arguments: [
        (0 as Int64, "0"), (50, "0,1\u{00A0}tis."), (100, "0,1\u{00A0}tis."), (249, "0,2\u{00A0}tis."),
        (250, "0,3\u{00A0}tis."), (1_000, "1\u{00A0}tis."), (1_250, "1,3\u{00A0}tis."), (2_500, "2,5\u{00A0}tis."),
        (12_500, "12,5\u{00A0}tis."), (25_000, "25\u{00A0}tis."), (50_000, "50\u{00A0}tis."),
        (75_000, "75\u{00A0}tis."), (99_950, "100\u{00A0}tis."), (100_000, "100\u{00A0}tis."),
        (125_000, "125\u{00A0}tis."), (400_000, "400\u{00A0}tis."), (1_000_000, "1\u{00A0}mil."),
        (1_250_000, "1,25\u{00A0}mil."), (1_500_000, "1,5\u{00A0}mil."), (2_000_000, "2\u{00A0}mil."),
        (2_500_000, "2,5\u{00A0}mil."), (10_000_000, "10\u{00A0}mil."), (12_345_678, "12,35\u{00A0}mil."),
    ])
    func aLineOfTheChartIsWrittenInThousandsOrMillions(kc: Int64, text: String) {
        #expect(IncomeChartLayout.label(forKc: kc) == text)
    }

    // MARK: Where things go

    @Test func theTooltipIsRightOfAColumnInTheLeftHalfAndLeftOfItInTheRightHalf() {
        // 12 columns of 83,33 points in a plot of 1 000: a tooltip 400 points wide is 8 away from the column.
        let first = IncomeChartLayout.tooltipLeading(column: 0, of: 12, plotWidth: 1_000, tooltipWidth: 400)
        let sixth = IncomeChartLayout.tooltipLeading(column: 5, of: 12, plotWidth: 1_000, tooltipWidth: 400)
        let seventh = IncomeChartLayout.tooltipLeading(column: 6, of: 12, plotWidth: 1_000, tooltipWidth: 400)
        let last = IncomeChartLayout.tooltipLeading(column: 11, of: 12, plotWidth: 1_000, tooltipWidth: 400)

        #expect(abs(first - 91.33) < 0.01)
        #expect(abs(sixth - 508) < 0.01)
        #expect(abs(seventh - 92) < 0.01)
        #expect(abs(last - 508.67) < 0.01)
    }

    @Test func aWiderTooltipStartsFurtherLeftOfTheColumnItStandsLeftOf() {
        // The seventh column of 12 in a plot of 1 000: its tooltip ends 8 points before the column, whatever its width.
        let narrow = IncomeChartLayout.tooltipLeading(column: 6, of: 12, plotWidth: 1_000, tooltipWidth: 340)
        let wide = IncomeChartLayout.tooltipLeading(column: 6, of: 12, plotWidth: 1_000, tooltipWidth: 440)

        #expect(abs(narrow - 152) < 0.01)
        #expect(abs(wide - 52) < 0.01)
    }

    @Test func theTooltipStaysInsideThePlot() {
        // Two columns of 150 points: the second one's tooltip would start left of the plot, and in a plot narrower than
        // the tooltip it starts at the left edge.
        #expect(IncomeChartLayout.tooltipLeading(column: 1, of: 2, plotWidth: 300, tooltipWidth: 400) == 0)
        #expect(IncomeChartLayout.tooltipLeading(column: 0, of: 2, plotWidth: 300, tooltipWidth: 400) == 0)
        // The one column of a plot would have its tooltip run out of the plot to the right: it ends at the edge.
        #expect(IncomeChartLayout.tooltipLeading(column: 0, of: 1, plotWidth: 1_000, tooltipWidth: 400) == 600)
    }

    /// A stand-in for the tooltip, `width` points wide and 60 high, that tells where it is placed.
    private struct Stand: Layout {
        let width: CGFloat
        let report: @MainActor (CGRect) -> Void

        func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
            CGSize(width: width, height: 60)
        }

        func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
            MainActor.assumeIsolated { report(bounds) }
        }
    }

    @Test @MainActor func theTooltipIsPlacedByItsOwnWidthFourPointsUnderTheTopOfThePlot() async throws {
        // The seventh of 12 columns in a plot of 1 000 by 300 points: the tooltip ends 8 points before the column.
        for (width, leading) in [(340 as CGFloat, 152 as CGFloat), (440, 52)] {
            var placed = CGRect.zero
            let plot = TooltipPlacement(column: 6, count: 12) {
                Stand(width: width, report: { placed = $0 }) {
                    Color.clear
                }
            }
            .frame(width: 1_000, height: 300, alignment: .topLeading)
            try await withHostedView(plot, size: CGSize(width: 1_000, height: 300)) { _ in }

            #expect(abs(placed.minX - leading) < 0.01, "a tooltip \(width) wide is at \(placed)")
            #expect(abs(placed.minY - 4) < 0.01, "a tooltip \(width) wide is at \(placed)")
            #expect(placed.width == width, "a tooltip \(width) wide is \(placed.width) wide")
        }
    }

    @Test func aBarIsAboutHalfOfItsColumnAtMostFortySixPointsWide() {
        #expect(IncomeChartLayout.barWidth(plotWidth: 600, columns: 12) == 28)
        #expect(IncomeChartLayout.barWidth(plotWidth: 1_000, columns: 12) == 46)
        #expect(IncomeChartLayout.barWidth(plotWidth: 800, columns: 3) == 46)
        #expect(IncomeChartLayout.barWidth(plotWidth: 800, columns: 0) == 0)
    }

    @Test func theColumnUnderThePointerIsFoundFromItsPositionInThePlot() {
        #expect(IncomeChartLayout.column(atX: 0, plotWidth: 1_200, columns: 12) == 0)
        #expect(IncomeChartLayout.column(atX: 99.9, plotWidth: 1_200, columns: 12) == 0)
        #expect(IncomeChartLayout.column(atX: 100, plotWidth: 1_200, columns: 12) == 1)
        #expect(IncomeChartLayout.column(atX: 1_199, plotWidth: 1_200, columns: 12) == 11)
        #expect(IncomeChartLayout.column(atX: -1, plotWidth: 1_200, columns: 12) == nil)
        #expect(IncomeChartLayout.column(atX: 1_200, plotWidth: 1_200, columns: 12) == nil)
        #expect(IncomeChartLayout.column(atX: 10, plotWidth: 1_200, columns: 0) == nil)
    }

    // MARK: The size of the tooltip

    @Test @MainActor func aMonthTooltipKeepsEveryLineOnOneLine() {
        // The four amounts of a month: 1 Kč each, and the most the columns of the chart hold, 99 999 999,99 Kč, which
        // are 100 000 000 Kč in whole Kč.
        func tooltip(allAmountsHalere halere: Int64) -> ChartTooltip {
            ChartTooltip(
                column: ChartColumn(
                    label: "zář", title: "Září 2026", issuedNetHalere: halere, issuedGrossHalere: halere,
                    receivedNetHalere: halere, receivedGrossHalere: halere, isFuture: false, isCurrent: false,
                    hasLinePoint: true))
        }
        let small = NSHostingView(rootView: tooltip(allAmountsHalere: 100)).fittingSize
        let large = NSHostingView(rootView: tooltip(allAmountsHalere: 9_999_999_999)).fittingSize

        // The tooltip is as wide as its lines are long, so that none of them wraps: it is no taller for large amounts.
        #expect((large.height - small.height).magnitude < 0.5, "\(large.height) points against \(small.height)")
        #expect(large.width > small.width, "\(large.width) points against \(small.width)")
    }

    @Test @MainActor func aYearTooltipKeepsItsRowsOnOneLineAndWrapsOnlyItsFooter() {
        // A year with its four amounts and its net income all at 1 Kč, or all at the most the columns of the chart
        // hold, 99 999 999,99 Kč (100 000 000 Kč in whole Kč), with the average of 2026 so far at 1 Kč, or at a figure
        // of nine digits.
        func tooltip(allAmountsHalere halere: Int64, average: String) -> ChartTooltip {
            ChartTooltip(
                column: ChartColumn(
                    label: "2026", title: "Rok 2026", issuedNetHalere: halere, issuedGrossHalere: halere,
                    receivedNetHalere: halere, receivedGrossHalere: halere, isFuture: false, isCurrent: true,
                    hasLinePoint: true, netIncomeHalere: halere,
                    netAverage: ChartNetAverage(
                        label: "Průměrný čistý příjem za měsíc v roce 2026 (leden–říjen)", value: average),
                    netIncomeText: PredictionBuilder.kc(ofHalere: halere)))
        }
        let small = NSHostingView(rootView: tooltip(allAmountsHalere: 100, average: "1\u{00A0}Kč")).fittingSize
        let large = NSHostingView(
            rootView: tooltip(allAmountsHalere: 9_999_999_999, average: "833\u{00A0}333\u{00A0}333\u{00A0}Kč")
        ).fittingSize

        // The rows are as wide as their amounts, so that none of them wraps, and the words of the footer wrap at a
        // fixed width, whatever the amount: the tooltip is no taller for large amounts, and wider than those words.
        #expect((large.height - small.height).magnitude < 0.5, "\(large.height) points against \(small.height)")
        #expect(large.width > small.width, "\(large.width) points against \(small.width)")
        #expect(small.width > ChartTooltip.footerWordsWidth, "\(small.width) points for the words of the footer")
    }

    @Test @MainActor func aYearTooltipWithTheRulesSentenceKeepsItsRowsOnOneLine() {
        // A year that the engine works out with the rules of another year, 2021, with its four amounts and its net
        // income all at 1 Kč, or all at the most the columns of the chart hold, 99 999 999,99 Kč (100 000 000 Kč in
        // whole Kč), the net income and the average marked as estimates, with the sentence about the rules under the
        // footer or without it.
        func size(allAmountsHalere halere: Int64, average: String, note: String?) -> CGSize {
            let tooltip = ChartTooltip(
                column: ChartColumn(
                    label: "2021", title: "Rok 2021", issuedNetHalere: halere, issuedGrossHalere: halere,
                    receivedNetHalere: halere, receivedGrossHalere: halere, isFuture: false, isCurrent: false,
                    hasLinePoint: true, netIncomeHalere: halere,
                    netAverage: ChartNetAverage(
                        label: "Průměrný čistý příjem za měsíc v roce 2021", value: average, note: note),
                    netIncomeText: "≈\u{00A0}" + PredictionBuilder.kc(ofHalere: halere)))
            return NSHostingView(rootView: tooltip).fittingSize
        }
        let sentence = "Pravidla pro rok 2021 zatím nejsou v aplikaci – výpočet je odhad podle roku 2022."
        let smallAverage = "≈\u{00A0}1\u{00A0}Kč"
        let largeAverage = "≈\u{00A0}833\u{00A0}333\u{00A0}333\u{00A0}Kč"
        let small = size(allAmountsHalere: 100, average: smallAverage, note: sentence)
        let large = size(allAmountsHalere: 9_999_999_999, average: largeAverage, note: sentence)
        let smallWithout = size(allAmountsHalere: 100, average: smallAverage, note: nil)
        let largeWithout = size(allAmountsHalere: 9_999_999_999, average: largeAverage, note: nil)

        // The rows are as wide as their amounts, so that none of them wraps, and the sentence wraps at the width of the
        // words of the footer, whatever the amounts: the tooltip is no taller for large amounts, wider than for small
        // ones, taller than without the sentence, and no wider for it.
        #expect((large.height - small.height).magnitude < 0.5, "\(large.height) points against \(small.height)")
        #expect(large.width > small.width, "\(large.width) points against \(small.width)")
        #expect(small.height > smallWithout.height + 10, "\(small.height) points against \(smallWithout.height)")
        #expect(large.height > largeWithout.height + 10, "\(large.height) points against \(largeWithout.height)")
        #expect(
            (small.width - smallWithout.width).magnitude < 0.5, "\(small.width) points against \(smallWithout.width)")
        #expect(
            (large.width - largeWithout.width).magnitude < 0.5, "\(large.width) points against \(largeWithout.width)")
    }

    @Test @MainActor func aNoteUnderTheNetIncomeKeepsEveryRowOnOneLineAndMakesTheTooltipNoWider() {
        // A month with its four amounts and its net income all at 1 Kč, or all at the most the columns of the chart
        // hold, 99 999 999,99 Kč (100 000 000 Kč in whole Kč), with the average of 2026 so far, and with a note under
        // the net income row or without one: the note of a month, which is a line, and a longer one, which wraps.
        func size(allAmountsHalere halere: Int64, note: String?) -> CGSize {
            let tooltip = ChartTooltip(
                column: ChartColumn(
                    label: "úno", title: "Únor 2026", issuedNetHalere: halere, issuedGrossHalere: halere,
                    receivedNetHalere: halere, receivedGrossHalere: halere, isFuture: false, isCurrent: false,
                    hasLinePoint: true, netIncomeHalere: halere,
                    netAverage: ChartNetAverage(
                        label: "Průměrný čistý příjem za měsíc v roce 2026 (leden–říjen)",
                        value: "193\u{00A0}347\u{00A0}Kč"),
                    netIncomeText: PredictionBuilder.kc(ofHalere: halere), netIncomeNote: note))
            return NSHostingView(rootView: tooltip).fittingSize
        }
        let note = "součet za faktury zaplacené v měsíci"
        let longNote = "od 1.\u{00A0}1. do 17.\u{00A0}10., po odvodech, spočítané z plateb všech faktur roku"
        let small = size(allAmountsHalere: 100, note: note)
        let large = size(allAmountsHalere: 9_999_999_999, note: note)
        let smallWithout = size(allAmountsHalere: 100, note: nil)
        let largeWithout = size(allAmountsHalere: 9_999_999_999, note: nil)
        let wrapped = size(allAmountsHalere: 100, note: longNote)

        // The rows are as wide as their amounts, so that none of them wraps: the tooltip is no taller for large
        // amounts. The note is a line of its own, which makes the tooltip taller and no wider, and a longer note wraps
        // at the width of the words of the footer, so it only grows taller.
        #expect((large.height - small.height).magnitude < 0.5, "\(large.height) points against \(small.height)")
        #expect(large.width > small.width, "\(large.width) points against \(small.width)")
        #expect(small.height > smallWithout.height + 10, "\(small.height) points against \(smallWithout.height)")
        #expect(large.height > largeWithout.height + 10, "\(large.height) points against \(largeWithout.height)")
        #expect(
            (small.width - smallWithout.width).magnitude < 0.5, "\(small.width) points against \(smallWithout.width)")
        #expect(
            (large.width - largeWithout.width).magnitude < 0.5, "\(large.width) points against \(largeWithout.width)")
        #expect(wrapped.height > small.height + 10, "\(wrapped.height) points against \(small.height)")
        #expect((wrapped.width - small.width).magnitude < 0.5, "\(wrapped.width) points against \(small.width)")
    }

    @Test @MainActor func aTooltipHasARowForTheNetIncomeAndAFooterForTheAverageOnlyWhereThereAreThey() {
        func height(netIncomeHalere: Int64?, hasAverage: Bool) -> CGFloat {
            let average =
                hasAverage
                ? ChartNetAverage(
                    label: "Průměrný čistý příjem za měsíc v roce 2026 (leden–říjen)",
                    value: "193\u{00A0}347\u{00A0}Kč")
                : nil
            let tooltip = ChartTooltip(
                column: ChartColumn(
                    label: "2026", title: "Rok 2026", issuedNetHalere: 100, issuedGrossHalere: 100,
                    receivedNetHalere: 100, receivedGrossHalere: 100, isFuture: false, isCurrent: true,
                    hasLinePoint: true, netIncomeHalere: netIncomeHalere, netAverage: average,
                    netIncomeText: netIncomeHalere.map { PredictionBuilder.kc(ofHalere: $0) }))
            return NSHostingView(rootView: tooltip).fittingSize.height
        }
        let plain = height(netIncomeHalere: nil, hasAverage: false)
        let withNet = height(netIncomeHalere: 100, hasAverage: false)
        let withAverage = height(netIncomeHalere: nil, hasAverage: true)
        let withBoth = height(netIncomeHalere: 100, hasAverage: true)

        // A month and a year with a result have both, and a year without one has neither.
        #expect(withNet > plain + 10, "\(withNet) points against \(plain)")
        #expect(withAverage > plain + 10, "\(withAverage) points against \(plain)")
        #expect((withBoth - withNet - withAverage + plain).magnitude < 0.5, "\(withBoth) points")
    }

    // MARK: The legend of the chart

    /// The three keys of the legend of the years chart, by the words each starts with: the bars, the line of what was
    /// received and the line of the net income.
    private static let legendKeys = ["Vystaveno (podle", "Přijato (podle", "Čistý příjem za rok (po odvodech"]

    /// The card "Příjmy" with the years chart of two years, `width` points wide.
    @MainActor
    private static func yearsChart(width: CGFloat) -> some View {
        func year(_ year: Int, isCurrent: Bool) -> ChartColumn {
            ChartColumn(
                label: String(year), title: "Rok \(year)", issuedNetHalere: 100_000_000, issuedGrossHalere: 121_000_000,
                receivedNetHalere: 90_000_000, receivedGrossHalere: 108_900_000, isFuture: false,
                isCurrent: isCurrent, hasLinePoint: true)
        }
        return IncomeChart(
            columns: [year(2025, isCurrent: false), year(2026, isCurrent: true)], subtitle: "Po letech · v Kč bez DPH",
            netIncome: OverviewNetIncome(
                yearLabel: "Čistý příjem od 1.\u{00A0}1. do 17.\u{00A0}10.",
                yearValue: "1\u{00A0}933\u{00A0}471\u{00A0}Kč",
                yearSub: "88,2\u{00A0}% příjmů bez DPH po odvodech",
                monthLabel: "Čistý příjem průměrně za měsíc", monthValue: "193\u{00A0}347\u{00A0}Kč",
                monthSub: "průměr za leden–říjen"),
            uniformLine: nil, mode: .years, withVAT: false, setMode: { _ in }, setWithVAT: { _ in }
        )
        .frame(width: width)
    }

    /// The card is 820 points wide at the least room, and the three keys of the years chart need about 850 (806 points
    /// inside the padding of 20): the third stands in a row of its own under the other two, and no key breaks in two.
    /// In a wide card the three stand side by side.
    @Test @MainActor func theKeysOfTheYearsLegendWrapWholeToASecondRowWhereTheCardHasNoRoomForThem() async throws {
        for (width, isOnTwoRows) in [(820 as CGFloat, true), (1_300, false)] {
            try await withHostedView(Self.yearsChart(width: width), size: CGSize(width: width, height: 600)) { window in
                try await withAccessibilityElements {
                    try await waitUntil {
                        Self.legendKeys.allSatisfy { frameOfText(startingWith: $0, in: window) != nil }
                    }
                    try await layOut(window)
                    let frames = Self.legendKeys.compactMap { frameOfText(startingWith: $0, in: window) }
                    try #require(frames.count == 3)
                    // A key of one line is as high as a line of text, 15 points; two lines would be twice that.
                    #expect(frames.allSatisfy { $0.height < 20 }, "\(frames) in a card \(width) points wide")
                    // The origin of the screen is at the bottom left, so what is under has the smaller y.
                    #expect((frames[0].midY - frames[1].midY).magnitude < 1, "\(frames) in a card \(width) wide")
                    let isUnder = frames[2].maxY < frames[0].minY
                    #expect(isUnder == isOnTwoRows, "\(frames) in a card \(width) points wide")
                    if !isOnTwoRows {
                        #expect((frames[0].midY - frames[2].midY).magnitude < 1, "\(frames) in a card \(width) wide")
                    }
                }
            }
        }
    }

    // MARK: The New Year banner

    @Test func theNewYearBannerSaysWhichYearBeganAndWhichIsClosed() {
        #expect(NewYearBanner.text(finishedYear: 2026) == "Začal rok 2027 — rok 2026 je uzavřený")
        #expect(NewYearBanner.showTitle(finishedYear: 2026) == "Zobrazit rok 2026")
        #expect(NewYearBanner.text(finishedYear: 2030) == "Začal rok 2031 — rok 2030 je uzavřený")
    }
}
