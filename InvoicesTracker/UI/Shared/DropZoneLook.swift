import SwiftUI

/// The look of a zone where files are dropped, which Import and the choice of a backup share: the accent tint with a
/// ring 1.5 points wide of the soft accent, on a rounded rectangle with the corners of a panel (10 points); while a
/// file is dragged over the zone the ring is the accent itself, which is all the design says of that state.
struct DropZoneLook: ViewModifier {
    /// Whether a file is being dragged over the zone.
    let isTargeted: Bool

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: DesignMetrics.panelRadius)
        content
            .background {
                shape
                    .fill(Palette.accentTint)
                    .overlay(shape.strokeBorder(isTargeted ? Palette.accent : Palette.accentSoft, lineWidth: 1.5))
            }
            .contentShape(shape)
    }
}
