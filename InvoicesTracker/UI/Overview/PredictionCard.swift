import SwiftUI

/// The card of Přehled with the estimate of the whole year. Its header row has the title with the pill "odhad" and the
/// line that says what the estimate counts, and at the right end the button that opens Odhad odvodů for the rest; where
/// the row has not the room for both, the button stands under the title. Under the header stand the four figures (the
/// year's income, its tax and insurance, what is left to settle with the returns, and the net income per month) in
/// equal columns of at least 190 points: all four side by side where the card is wide enough for them, otherwise as
/// many as fit, with the rest in rows under them. Under the figures, past a thin divider, stands the chart of the
/// year's months (`PredictionChart`), when the card has them.
struct PredictionCard: View {
    let card: PredictionCardData

    /// Odhad odvodů: opens the screen of the estimate.
    let showPrediction: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            AdaptiveColumns(minimumColumnWidth: 190, spacing: 24) {
                figures
            }
            if !card.chart.isEmpty {
                Divider()
                PredictionChart(months: card.chart)
            }
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 16)
        .card()
        .accessibilityElement(children: .contain)
        .accessibilityLabel(card.head)
    }

    // MARK: Parts

    /// The title and the button in a row, the button at the right end; the button under the title where the row does
    /// not fit.
    private var header: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .center, spacing: 28) {
                title
                Spacer(minLength: 0)
                button
            }
            VStack(alignment: .leading, spacing: 10) {
                title
                button
            }
        }
    }

    /// The title with its pill, and the line under it.
    private var title: some View {
        VStack(alignment: .leading, spacing: 3) {
            FlowLayout(spacing: 8) {
                Text(verbatim: card.head)
                    .font(.title3.weight(.semibold))
                    .accessibilityAddTraits(.isHeader)
                Text("odhad")
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(Color(.simulationText))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 1)
                    .background(Color(.simulationBackground), in: Capsule())
            }
            Text(verbatim: card.sub)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var figures: some View {
        ForEach(card.stats) { stat in
            StatView(stat: stat)
        }
    }

    private var button: some View {
        Button(action: showPrediction) {
            HStack(spacing: 6) {
                Text("Odhad odvodů")
                Image(systemName: "arrow.right")
                    .accessibilityHidden(true)
            }
        }
        .buttonStyle(.bordered)
        .buttonBorderShape(.capsule)
        .controlSize(.large)
    }
}

/// One of the four figures: a caption, the figure in bold and what it is made of.
private struct StatView: View {
    let stat: PredictionMini

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(verbatim: stat.label)
                .font(.callout)
                .foregroundStyle(.secondary)
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(verbatim: stat.value)
                    .font(.title2.weight(.bold))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                if let share = stat.share {
                    Text(verbatim: share)
                        .font(.callout.weight(.semibold))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .fixedSize()
                }
            }
            Text(verbatim: stat.sub)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}
