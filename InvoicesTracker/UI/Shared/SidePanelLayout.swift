import SwiftUI

/// Lays out a column and a panel beside it: the panel is `sideWidth` wide on the right and the column takes the rest,
/// as long as the column keeps `mainMinimumWidth`; where the width is less, the panel comes under the column. Both are
/// aligned at the top. Zálohy a odpočty puts the impact of the deductions beside them so, and Simulátor what the year
/// costs beside its inputs.
struct SidePanelLayout: Layout {
    let sideWidth: CGFloat
    let mainMinimumWidth: CGFloat
    let spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        guard subviews.count == 2 else { return .zero }
        let width = availableWidth(proposal)
        let sizes = sizes(subviews, width: width)
        if isBeside(width) {
            return CGSize(width: width, height: max(sizes.main.height, sizes.side.height))
        }
        return CGSize(width: width, height: sizes.main.height + spacing + sizes.side.height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        guard subviews.count == 2 else { return }
        let sizes = sizes(subviews, width: bounds.width)
        if isBeside(bounds.width) {
            let mainWidth = bounds.width - spacing - sideWidth
            subviews[0].place(
                at: CGPoint(x: bounds.minX, y: bounds.minY), anchor: .topLeading,
                proposal: ProposedViewSize(width: mainWidth, height: nil))
            subviews[1].place(
                at: CGPoint(x: bounds.maxX - sideWidth, y: bounds.minY), anchor: .topLeading,
                proposal: ProposedViewSize(width: sideWidth, height: nil))
        } else {
            subviews[0].place(
                at: CGPoint(x: bounds.minX, y: bounds.minY), anchor: .topLeading,
                proposal: ProposedViewSize(width: bounds.width, height: nil))
            subviews[1].place(
                at: CGPoint(x: bounds.minX, y: bounds.minY + sizes.main.height + spacing), anchor: .topLeading,
                proposal: ProposedViewSize(width: bounds.width, height: nil))
        }
    }

    /// The width to lay out in: the one proposed, or for none the width of the two side by side.
    private func availableWidth(_ proposal: ProposedViewSize) -> CGFloat {
        if let width = proposal.width, width.isFinite {
            return width
        }
        return mainMinimumWidth + spacing + sideWidth
    }

    private func isBeside(_ width: CGFloat) -> Bool {
        width >= mainMinimumWidth + spacing + sideWidth
    }

    /// The sizes of the column and of the panel at their widths in `width`.
    private func sizes(_ subviews: Subviews, width: CGFloat) -> (main: CGSize, side: CGSize) {
        if isBeside(width) {
            return (
                subviews[0].sizeThatFits(ProposedViewSize(width: width - spacing - sideWidth, height: nil)),
                subviews[1].sizeThatFits(ProposedViewSize(width: sideWidth, height: nil))
            )
        }
        return (
            subviews[0].sizeThatFits(ProposedViewSize(width: width, height: nil)),
            subviews[1].sizeThatFits(ProposedViewSize(width: width, height: nil))
        )
    }
}
