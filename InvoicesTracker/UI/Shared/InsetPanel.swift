import SwiftUI

extension View {
    /// The look of an inner panel: the view padded by `horizontal` and `vertical` points on the inset background, on a
    /// rounded rectangle with the corners of a panel (10 points), and as wide as the room it is in. It is for what a
    /// card sets apart from the rest of its content without raising it, such as the helper that fills the months of
    /// the advances, the summary of the interest on a mortgage, the hint under the children and what a child comes to
    /// in a year. The colour is the palette's, so it follows the appearance of the window.
    ///
    /// With `ringed` the panel has the hairline of a card, one point wide along its edge, as the panel that holds a
    /// recovery code and the choices of the first screens do; the others have none.
    func insetPanel(horizontal: CGFloat, vertical: CGFloat, ringed: Bool = false) -> some View {
        padding(.horizontal, horizontal)
            .padding(.vertical, vertical)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                let shape = RoundedRectangle(cornerRadius: DesignMetrics.panelRadius)
                shape
                    .fill(Palette.bgInset)
                    .overlay {
                        if ringed {
                            shape.strokeBorder(Palette.sep, lineWidth: 1)
                        }
                    }
            }
    }
}
