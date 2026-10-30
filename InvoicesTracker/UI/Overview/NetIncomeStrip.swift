import SwiftUI

/// The strip above the chart of the card "Příjmy": a divider and, under it, the net income of the year so far and its
/// average per month. Each of the two figures is the words that say what it is, the figure in bold and a line that says
/// what it is of; the words of the first one start with a short line in the colour of the net income. Where the card
/// has room for two columns of at least 220 points the figures stand side by side, otherwise one under the other.
/// VoiceOver reads each figure with its words as one phrase.
struct NetIncomeStrip: View {
    let netIncome: OverviewNetIncome

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Divider()
            AdaptiveColumns(minimumColumnWidth: 220, spacing: 24) {
                NetIncomeFigure(
                    label: netIncome.yearLabel, value: netIncome.yearValue, sub: netIncome.yearSub,
                    hasMarker: true)
                NetIncomeFigure(
                    label: netIncome.monthLabel, value: netIncome.monthValue, sub: netIncome.monthSub,
                    hasMarker: false)
            }
        }
    }
}

/// One of the two figures of the strip: the words that say what it is, the figure in bold and the line under it.
private struct NetIncomeFigure: View {
    let label: String
    let value: String
    let sub: String

    /// Whether the words start with a short line in the colour of the net income.
    let hasMarker: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                if hasMarker {
                    Capsule()
                        .fill(Color(.netIncome))
                        .frame(width: 16, height: 3)
                        .accessibilityHidden(true)
                }
                Text(verbatim: label)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Text(verbatim: value)
                .font(.system(size: 17, weight: .bold))
                .monospacedDigit()
            Text(verbatim: sub)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}
