import SwiftUI

/// The sizes and gaps of the strip of the net income.
private nonisolated enum NetIncomeStripMetrics {
    /// The space between the two figures where they stand side by side.
    static let figureSpacing: CGFloat = 48

    /// The space between a hairline and the figures.
    static let padding: CGFloat = 12
}

/// The strip above the chart of the card "Příjmy": between two hairlines, the net income of the year so far and its
/// average per month, two figure tiles side by side 48 points apart, each as wide as its words and never stretched. A
/// tile is the words that say what the figure is, the figure in bold and a line that says what it is of; the words of
/// the first one start with a short line in the colour of the net income, like the key of the net income in the legend
/// of the chart. Where the card has no room for both side by side the second goes under the first. VoiceOver reads each
/// tile with its words as one phrase.
struct NetIncomeStrip: View {
    let netIncome: OverviewNetIncome

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Hairline()
            FigureRow(spacing: NetIncomeStripMetrics.figureSpacing) {
                FigureTile(
                    FigureTileData(
                        label: netIncome.yearLabel, figure: netIncome.yearValue, note: netIncome.yearSub,
                        marksNetIncome: true, marker: .line))
                FigureTile(
                    FigureTileData(label: netIncome.monthLabel, figure: netIncome.monthValue, note: netIncome.monthSub))
            }
            .padding(.vertical, NetIncomeStripMetrics.padding)
            Hairline()
        }
    }
}
