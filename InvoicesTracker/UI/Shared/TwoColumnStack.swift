import SwiftUI

/// Two stacks of views laid out as two columns of one width. Where the width has room for both columns at
/// `minimumColumnWidth` and the gap between them, 856 points as it is by default, they stand side by side, aligned at
/// the top; where it has less, they come one under the other, the left stack first, `stackedSpacing` points apart (as
/// far apart as the columns are unless told otherwise). Each stack is a column that runs on by itself, with `spacing`
/// between its views, so the shorter one just ends earlier and leaves no hole. Cards in the rows of `AdaptiveColumns`
/// over one list would make a card wait for the tallest of its row, and would change columns as the width changes.
/// Výpočet and Simulátor keep the tax on the left and the insurances on the right so.
struct TwoColumnStack<Left: View, Right: View>: View {
    let minimumColumnWidth: CGFloat
    let spacing: CGFloat

    /// The space between the two stacks where they come one under the other.
    let stackedSpacing: CGFloat
    private let left: Left
    private let right: Right

    init(
        minimumColumnWidth: CGFloat = 420, spacing: CGFloat = 16, stackedSpacing: CGFloat? = nil,
        @ViewBuilder left: () -> Left, @ViewBuilder right: () -> Right
    ) {
        self.minimumColumnWidth = minimumColumnWidth
        self.spacing = spacing
        self.stackedSpacing = stackedSpacing ?? spacing
        self.left = left()
        self.right = right()
    }

    var body: some View {
        TwoColumnLayout(
            minimumColumnWidth: minimumColumnWidth, spacing: spacing, stackedSpacing: stackedSpacing
        ) {
            VStack(alignment: .leading, spacing: spacing) {
                left
            }
            VStack(alignment: .leading, spacing: spacing) {
                right
            }
        }
    }
}

/// Places the two stacks of a `TwoColumnStack`, its two subviews: side by side in columns of one width, or the left one
/// above the right one in the whole width. A stack is as high as it is in its column, and the layout as high as the
/// taller of the two side by side, or as the two and the gap between them.
private struct TwoColumnLayout: Layout {
    let minimumColumnWidth: CGFloat
    let spacing: CGFloat
    let stackedSpacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        guard subviews.count == 2 else { return .zero }
        let width = availableWidth(proposal)
        let sizes = sizes(subviews, width: width)
        if isBeside(width) {
            return CGSize(width: width, height: max(sizes.left.height, sizes.right.height))
        }
        return CGSize(width: width, height: sizes.left.height + stackedSpacing + sizes.right.height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        guard subviews.count == 2 else { return }
        if isBeside(bounds.width) {
            let columnWidth = columnWidth(in: bounds.width)
            subviews[0].place(
                at: CGPoint(x: bounds.minX, y: bounds.minY), anchor: .topLeading,
                proposal: ProposedViewSize(width: columnWidth, height: nil))
            subviews[1].place(
                at: CGPoint(x: bounds.minX + columnWidth + spacing, y: bounds.minY), anchor: .topLeading,
                proposal: ProposedViewSize(width: columnWidth, height: nil))
        } else {
            let heightOfLeft = sizes(subviews, width: bounds.width).left.height
            subviews[0].place(
                at: CGPoint(x: bounds.minX, y: bounds.minY), anchor: .topLeading,
                proposal: ProposedViewSize(width: bounds.width, height: nil))
            subviews[1].place(
                at: CGPoint(x: bounds.minX, y: bounds.minY + heightOfLeft + stackedSpacing), anchor: .topLeading,
                proposal: ProposedViewSize(width: bounds.width, height: nil))
        }
    }

    /// The width to lay out in: the one proposed, or for none the width of the two columns side by side. A proposal of
    /// no width at all is the question for the least room the stacks need: one column of the least width, not the
    /// height that the stacks would have at a width of nothing.
    private func availableWidth(_ proposal: ProposedViewSize) -> CGFloat {
        if let width = proposal.width, width.isFinite {
            return width > 0 ? width : minimumColumnWidth
        }
        return 2 * minimumColumnWidth + spacing
    }

    private func isBeside(_ width: CGFloat) -> Bool {
        width >= 2 * minimumColumnWidth + spacing
    }

    private func columnWidth(in width: CGFloat) -> CGFloat {
        (width - spacing) / 2
    }

    /// The sizes of the two stacks in `width`: each in a column of its own side by side, each in the whole width where
    /// they stand one above the other.
    private func sizes(_ subviews: Subviews, width: CGFloat) -> (left: CGSize, right: CGSize) {
        let proposal = ProposedViewSize(width: isBeside(width) ? columnWidth(in: width) : width, height: nil)
        return (subviews[0].sizeThatFits(proposal), subviews[1].sizeThatFits(proposal))
    }
}
