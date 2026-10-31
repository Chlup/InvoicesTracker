import SwiftUI

/// The sizes and gaps of the result card of the Simulátor that its parts do not set themselves, in points.
private nonisolated enum SimulatorResultCardMetrics {
    /// The space between the parts of the card: the key figure, the bar of the levies, and the net income and the
    /// marginal levy under their hairlines.
    static let partSpacing: CGFloat = 14

    /// The space between a hairline and the part under it.
    static let belowHairline: CGFloat = 12

    /// The space between the dot of the net income and its words.
    static let dotGap: CGFloat = 6

    /// The space between the words of the net income and its amount where they stand on one line.
    static let amountGap: CGFloat = 12

    /// The space between the line of the net income and the line under it.
    static let lineGap: CGFloat = 3

    /// The space between the words of the net income and its amount where the amount has gone under them.
    static let wrappedGap: CGFloat = 4

    /// The size of the dot of the net income.
    static let dotSize: CGFloat = 8
}

/// The result of the simulation, in one card of the column beside the inputs: the key figure with the levies of the
/// year, their share of the income and what they are a month; the bar of the levies by authority, whose popover hangs
/// out over what follows it in the card; under a hairline what the income leaves after the levies; and under another
/// the marginal levy, in the compact form of Výpočet's card. The card is the width of its column, 360 points beside the
/// inputs, and its parts stand one under the other, 14 points apart.
///
/// The popover of the bar is drawn above what follows the bar in the card (the bar is drawn above its siblings), and
/// nothing clips it: the card is the background of its content. VoiceOver reads the card as a group under "Kolik
/// zaplatíte".
struct SimulatorResultCard: View {
    let summary: SimulatorSummary

    var body: some View {
        VStack(alignment: .leading, spacing: SimulatorResultCardMetrics.partSpacing) {
            KeyFigureView(summary.keyFigure, sentenceFont: Typography.callout)
            // The bar draws itself above what follows it, so its popover hangs below its legend over the net income and
            // the marginal levy.
            LevyBarView(summary.levyBar)
            underHairline {
                SimulatorNetIncomeView(netIncome: summary.netIncome)
            }
            underHairline {
                MarginalCard(marginal: summary.marginal, compact: true)
            }
        }
        .padding(DesignMetrics.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Kolik zaplatíte")
    }

    /// `content` under a hairline of the width of the card, 12 points below it.
    private func underHairline<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: SimulatorResultCardMetrics.belowHairline) {
            Hairline()
            content()
        }
    }
}

/// What the income leaves after the levies: the green dot of the net income and the words "Čistý příjem průměrně za
/// měsíc" in headline, the average per month in the title style at the end of their line, or under them where the two
/// do not fit one line, and under them the sum of the year with the reminder that the real expenses are not taken off,
/// in callout and tertiary text. The amount is in the colour of text whatever its sign: the levies being more than the
/// income is not a warning here. VoiceOver reads the three as one phrase.
struct SimulatorNetIncomeView: View {
    let netIncome: SimulatorNetIncome

    var body: some View {
        let words = HStack(spacing: SimulatorResultCardMetrics.dotGap) {
            Circle()
                .fill(Palette.green)
                .frame(width: SimulatorResultCardMetrics.dotSize, height: SimulatorResultCardMetrics.dotSize)
                .accessibilityHidden(true)
            Text(verbatim: netIncome.label)
                .font(Typography.headline)
                .foregroundStyle(Palette.text)
        }
        let amount = Text(verbatim: netIncome.amount)
            .font(Typography.title)
            .monospacedDigit()
            .foregroundStyle(Palette.text)
        return VStack(alignment: .leading, spacing: SimulatorResultCardMetrics.lineGap) {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .firstTextBaseline, spacing: SimulatorResultCardMetrics.amountGap) {
                    words
                    Spacer(minLength: 0)
                    amount
                }
                VStack(alignment: .leading, spacing: SimulatorResultCardMetrics.wrappedGap) {
                    words
                    amount
                }
            }
            Text(verbatim: netIncome.sub)
                .font(Typography.callout)
                .monospacedDigit()
                .foregroundStyle(Palette.text3)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }
}
