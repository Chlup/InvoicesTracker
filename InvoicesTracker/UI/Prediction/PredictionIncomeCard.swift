import SwiftUI

/// The sizes and gaps of the card Příjmy that its parts do not set themselves, in points.
private nonisolated enum PredictionIncomeCardMetrics {
    /// The space between a hairline and the part under it.
    static let hairlineGap: CGFloat = 14

    /// The space between the heading of the composition of the income, its bar and the legend of the bar.
    static let compositionSpacing: CGFloat = 10

    /// The space between two items of the legend of the bar on a row, and between two rows.
    static let legendSpacing: CGFloat = 24
    static let legendLineSpacing: CGFloat = 6

    /// The space between the swatch of an item of the legend, its words and its amount.
    static let legendItemSpacing: CGFloat = 6
}

/// The card Příjmy of Odhad odvodů: under its title and the line that says what the estimate counts, a hairline and
/// the calculation of the year (the income less the levies, what that leaves and that per month, under the green dot)
/// beside the panel of how the levies are paid, or one under the other where the card is too narrow for both
/// (`PredictionCalculationView`); then a hairline, the heading "Z čeho se příjmy roku skládají" in callout and
/// secondary text, the bar of the income and its legend in one line that wraps, and, where some money is paid only in
/// the next year, the note about it in the tone of an estimate.
///
/// VoiceOver reads the card as a group under "Příjmy", each row of the calculation and of the panel and each item of
/// the legend as one phrase, the title of the panel as a heading, and the bar as a picture named by the head of the
/// income and its total.
struct PredictionIncomeCard: View {
    let page: PredictionPage

    var body: some View {
        Card(title: "Příjmy", subtitle: page.incomeSub) {
            part {
                PredictionCalculationView(calculation: page.calculation)
            }
            part {
                VStack(alignment: .leading, spacing: PredictionIncomeCardMetrics.compositionSpacing) {
                    Text(verbatim: "Z čeho se příjmy roku skládají")
                        .font(Typography.callout)
                        .foregroundStyle(Palette.text2)
                    PredictionIncomeBar(parts: page.parts)
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel("\(page.incomeHead): \(page.incomeTotal)")
                        .accessibilityAddTraits(.isImage)
                    legend
                }
            }
            if let note = page.nextYearNote {
                Note(.attention, icon: .none, text: note)
            }
        }
    }

    /// `content` under a hairline, 14 points under it.
    private func part(@ViewBuilder _ content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: PredictionIncomeCardMetrics.hairlineGap) {
            Hairline()
            content()
        }
    }

    /// An item for each part of the income, one after the other in a line that wraps.
    private var legend: some View {
        FlowLayout(
            spacing: PredictionIncomeCardMetrics.legendSpacing,
            lineSpacing: PredictionIncomeCardMetrics.legendLineSpacing
        ) {
            ForEach(page.parts) { part in
                HStack(spacing: PredictionIncomeCardMetrics.legendItemSpacing) {
                    PredictionPartSwatch(kind: part.kind)
                    Text(verbatim: part.text)
                        .font(Typography.callout)
                        .foregroundStyle(Palette.text2)
                    Text(verbatim: part.value)
                        .font(Typography.calloutSemibold)
                        .foregroundStyle(Palette.text)
                }
                .monospacedDigit()
                .accessibilityElement(children: .combine)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - The bar

/// The sizes of the bar of the income and of the swatches of its legend, in points.
private nonisolated enum PredictionIncomeBarMetrics {
    /// The height of the bar, and the radius of its corners.
    static let height: CGFloat = 14
    static let radius: CGFloat = 5

    /// The side of the swatch of a part in the legend, and the radius of its corners.
    static let swatch: CGFloat = 10
    static let swatchRadius: CGFloat = 3
}

/// The fill of a part of the income: the money received is the grey of secondary text, what waits for its payment is
/// the accent, and what is only expected is hatched (`HatchedFill`).
private struct PredictionPartFill: View {
    let kind: PredictionPartKind

    var body: some View {
        switch kind {
        case .received:
            Rectangle().fill(Palette.text2)
        case .waiting:
            Rectangle().fill(Palette.accent)
        case .expected:
            HatchedFill()
        }
    }
}

/// The parts of the income one after the other on a track, each as wide as its part of the whole; nothing is drawn of
/// what is not there, so a bar of parts that add up to less than the whole shows the track at its end. The bar is 14
/// points high with its corners rounded by 5, and the track is the fill of a bar.
struct PredictionIncomeBar: View {
    let parts: [PredictionPart]

    var body: some View {
        GeometryReader { proxy in
            HStack(spacing: 0) {
                ForEach(parts) { part in
                    PredictionPartFill(kind: part.kind)
                        .frame(width: proxy.size.width * part.fraction)
                }
                Spacer(minLength: 0)
            }
        }
        .frame(height: PredictionIncomeBarMetrics.height)
        .background(Palette.fill)
        .clipShape(RoundedRectangle(cornerRadius: PredictionIncomeBarMetrics.radius))
    }
}

/// The swatch of a part in the legend of the bar: a square of 10 points, rounded by 3, in the fill of the part. It is
/// only for the eyes.
struct PredictionPartSwatch: View {
    let kind: PredictionPartKind

    var body: some View {
        PredictionPartFill(kind: kind)
            .frame(width: PredictionIncomeBarMetrics.swatch, height: PredictionIncomeBarMetrics.swatch)
            .clipShape(RoundedRectangle(cornerRadius: PredictionIncomeBarMetrics.swatchRadius))
            .accessibilityHidden(true)
    }
}
