import SwiftUI

/// The widths of the sentences of the result card of Odhad odvodů, which the design sets wider than those of the other
/// screens, in points.
private nonisolated enum PredictionResultCardMetrics {
    /// The widest the sentence under the key figure is set: 34 em of its 13-point type.
    static let keyFigureSentenceWidth: CGFloat = 442

    /// The widest the sentence under what is left to settle is set: 36 em of its 13-point type.
    static let dueSentenceWidth: CGFloat = 468
}

/// The result card of Odhad odvodů: the levies of the whole year as the key figure at the left, with their share of the
/// income beside it and the sentence that says what they are made from, and the bar of the levies by authority at the
/// right, or under the key figure where the card is too narrow for two columns. Under a hairline, over the whole width,
/// stands what is left to settle beyond the year's advances (or what they overpay) as a second key figure. The card is
/// the shared result card (`ResultCard`); the texts are the builder's (`PredictionBuilder`).
///
/// The popover of the bar hangs below its legend and may reach out of the card over what follows it, so the page draws
/// the card above the cards under it and does not clip it. VoiceOver reads the card as a group under "Výsledek".
struct PredictionResultCard: View {
    let page: PredictionPage

    var body: some View {
        ResultCard(label: "Výsledek") {
            KeyFigureView(page.keyFigure, sentenceMaximumWidth: PredictionResultCardMetrics.keyFigureSentenceWidth)
        } trailing: {
            LevyBarView(page.levyBar)
        } below: {
            KeyFigureView(page.due, sentenceMaximumWidth: PredictionResultCardMetrics.dueSentenceWidth)
        }
    }
}
