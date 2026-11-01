import SwiftUI

/// The sizes and gaps of the card of the estimate.
private nonisolated enum PredictionCardMetrics {
    /// The space between the parts of the card: the head, the figures under their hairline and the chart under its.
    static let spacing: CGFloat = 14

    /// The space between a hairline and the part under it.
    static let hairlineGap: CGFloat = 14

    /// The space between the figures, side by side.
    static let figureSpacing: CGFloat = 40

    /// The widest a figure is, so that its line of detail breaks there.
    static let figureMaximumWidth: CGFloat = 240

    /// The space between the title and the line under it.
    static let titleSpacing: CGFloat = 3

    /// The space between the head and the button where they stand side by side.
    static let headSpacing: CGFloat = 20

    /// The space between the title and the button where the button has gone under it.
    static let headLineSpacing: CGFloat = 10

    /// The space between the words of the button and its arrow.
    static let arrowGap: CGFloat = 6
}

/// The card of Přehled with the estimate of the whole year. Its head is the title and the line that says what the
/// estimate counts, with no pill: the title says it is an estimate, and no figure of the card carries the sign "≈". At
/// the right end of the head stands the button that opens Odhad odvodů for the rest; where the head has not the room
/// for both, the button stands under the title. Under a hairline stand the four figures (the year's income, its levies
/// with their share of the income, what is left to settle with the returns, and the net income per month), side by
/// side 40 points apart, each as wide as its words and at most 240 points, and on to further rows where they do not
/// fit. Under a second hairline stands the chart of the year's months (`PredictionChart`), when the card has them.
struct PredictionCard: View {
    let card: PredictionCardData

    /// Odhad odvodů: opens the screen of the estimate.
    let showPrediction: () -> Void

    var body: some View {
        Card(spacing: PredictionCardMetrics.spacing, label: "Odhad za celý rok") {
            header
            part {
                FigureRow(
                    spacing: PredictionCardMetrics.figureSpacing,
                    maxTileWidth: PredictionCardMetrics.figureMaximumWidth
                ) {
                    ForEach(card.stats) { stat in
                        FigureTile(
                            FigureTileData(label: stat.label, figure: stat.value, share: stat.share, note: stat.sub))
                    }
                }
            }
            if !card.chart.isEmpty {
                part {
                    PredictionChart(months: card.chart)
                }
            }
        }
    }

    // MARK: Parts

    /// `content` under a hairline, 14 points under it.
    private func part(@ViewBuilder _ content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: PredictionCardMetrics.hairlineGap) {
            Hairline()
            content()
        }
    }

    /// The title and the button in a row, the button at the right end; the button under the title where the row does
    /// not fit.
    private var header: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .center, spacing: PredictionCardMetrics.headSpacing) {
                title
                Spacer(minLength: 0)
                button
            }
            VStack(alignment: .leading, spacing: PredictionCardMetrics.headLineSpacing) {
                title
                button
            }
        }
    }

    /// The title, and the line under it.
    private var title: some View {
        VStack(alignment: .leading, spacing: PredictionCardMetrics.titleSpacing) {
            Text(verbatim: card.head)
                .font(Typography.title3)
                .foregroundStyle(Palette.text)
                .accessibilityAddTraits(.isHeader)
            Text(verbatim: card.sub)
                .font(Typography.callout)
                .foregroundStyle(Palette.text2)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// The way on to Odhad odvodů: the words and an arrow on a capsule of the grey fill, 28 points tall, as every button
    /// inside a card is.
    private var button: some View {
        Button(action: showPrediction) {
            HStack(spacing: PredictionCardMetrics.arrowGap) {
                Text("Odhad odvodů")
                Image(systemName: "arrow.right")
                    .accessibilityHidden(true)
            }
        }
        .buttonStyle(CapsuleButtonStyle(.secondary, size: .small))
    }
}
