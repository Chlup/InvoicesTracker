import SwiftUI

/// The sizes and gaps of the result card of Přehled that its parts do not set themselves, in points.
private nonisolated enum OverviewResultCardMetrics {
    /// The space between the two buttons under the key figure, and between their rows where they do not fit one.
    static let buttonSpacing: CGFloat = 8

    /// The space between the text of the first button and its arrow.
    static let arrowGap: CGFloat = 6
}

/// The card that opens Přehled: what is left to pay as the key figure, with the sentence under it and the way on to the
/// computation and to the plan of advances, the bar of the levies by authority beside it (or under it, where the card
/// is too narrow for two columns), and under a hairline the tiles of what the advances still pay, what is settled with
/// the return and what the next crown costs (or, in a year that is over, what the advances paid and what comes back).
/// The sentence stands 12 points under the line of the figure, as Přehled's design sets it (`KeyFigureSpacing`). The
/// card is the shared result card (`ResultCard`); the texts are the builder's (`OverviewBuilder`).
///
/// The popover of the bar hangs out of the card over what follows it, so the page draws the card above the cards under
/// it and does not clip it. VoiceOver reads the card as a group under "Kolik zbývá zaplatit".
struct OverviewResultCard: View {
    let keyFigure: KeyFigureData
    let levies: LevyBarData
    let tiles: [FigureTileData]

    /// Jak se to počítá.
    let showComputation: () -> Void

    /// Upravit plán záloh.
    let editAdvances: () -> Void

    var body: some View {
        ResultCard(label: "Kolik zbývá zaplatit") {
            KeyFigureView(keyFigure, spacing: .overview)
            buttons
        } trailing: {
            LevyBarView(levies)
        } below: {
            FigureRow {
                ForEach(tiles.indices, id: \.self) { index in
                    FigureTile(tiles[index])
                }
            }
        }
    }

    /// The way on to the computation, in the accent, and to the plan of advances, on the grey fill, as capsules of the
    /// height of a button inside a card. They stand side by side, and one under the other where the card is too narrow.
    private var buttons: some View {
        FlowLayout(spacing: OverviewResultCardMetrics.buttonSpacing) {
            Button(action: showComputation) {
                HStack(spacing: OverviewResultCardMetrics.arrowGap) {
                    Text("Jak se to počítá")
                    Image(systemName: "arrow.right")
                        .accessibilityHidden(true)
                }
            }
            .buttonStyle(CapsuleButtonStyle(.primary, size: .small))
            Button("Upravit plán záloh", action: editAdvances)
                .buttonStyle(CapsuleButtonStyle(.secondary, size: .small))
        }
    }
}
