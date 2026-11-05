import SwiftUI

/// The sizes and gaps of the calculation of a year's estimate and the panel beside it, in points.
private nonisolated enum PredictionCalculationMetrics {
    /// The least width of each of the two blocks; the two and the gap between them need 712 points to stand side by
    /// side.
    static let minimumBlockWidth: CGFloat = 340

    /// The space between the two blocks side by side.
    static let blockSpacing: CGFloat = 32

    /// The space between the two blocks one under the other.
    static let stackedSpacing: CGFloat = 16

    /// The space between the sides of the panel and its content.
    static let panelHorizontal: CGFloat = 14

    /// The space above and below the content of the panel.
    static let panelVertical: CGFloat = 10

    /// The space between the title of the panel and the rule-less first row under it, which has 8 points of its own.
    static let titleBottom: CGFloat = 4
}

/// The calculation of a year's estimate and how its levies are paid (`PredictionCalculation`), as two blocks: the rows
/// of the calculation, and an inner panel (`insetPanel`) with its title, "Jak odvody zaplatíte", in body semibold,
/// which VoiceOver reads as a heading, and its rows under it. The blocks stand side by side in two columns of one
/// width, 32 points apart, where the room has the 712 points that two of their least width, 340, and the gap need, and
/// one under the other in the whole width, 16 points apart, where it has less (`TwoColumnStack`). VoiceOver reads each
/// row as one phrase.
struct PredictionCalculationView: View {
    let calculation: PredictionCalculation

    var body: some View {
        TwoColumnStack(
            minimumColumnWidth: PredictionCalculationMetrics.minimumBlockWidth,
            spacing: PredictionCalculationMetrics.blockSpacing,
            stackedSpacing: PredictionCalculationMetrics.stackedSpacing
        ) {
            BillRows(rows: calculation.rows)
        } right: {
            panel
        }
    }

    /// The panel of how the levies are paid: its title and its rows on the inset background.
    private var panel: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(verbatim: calculation.payTitle)
                .font(Typography.bodySemibold)
                .foregroundStyle(Palette.text)
                .accessibilityAddTraits(.isHeader)
                .padding(.bottom, PredictionCalculationMetrics.titleBottom)
            BillRows(rows: calculation.payRows)
        }
        .insetPanel(
            horizontal: PredictionCalculationMetrics.panelHorizontal,
            vertical: PredictionCalculationMetrics.panelVertical)
    }
}
