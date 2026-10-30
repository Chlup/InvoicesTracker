import SwiftUI

/// The sizes of the result card and the rule that decides between its two layouts.
nonisolated enum ResultCardLayout {
    /// The least width of one of the two columns.
    static let minimumColumnWidth: CGFloat = 380

    /// The space between the two columns.
    static let columnGap: CGFloat = 28

    /// The space between the two parts where they stand one above the other, and between them and the hairline.
    static let rowGap: CGFloat = 20

    /// The space between the hairline and the part under it.
    static let belowGap: CGFloat = 16

    /// Whether the parts stand side by side in a room of `innerWidth` points, the width inside the padding of the
    /// card: they do where two columns of the least width and the gap between them fit, and one above the other
    /// where they do not.
    static func standsSideBySide(innerWidth: CGFloat) -> Bool {
        innerWidth >= 2 * minimumColumnWidth + columnGap
    }
}

/// The card that opens a report: two parts of one width, side by side where the room has two columns of 380 points and
/// the gap of 28 between them, such as the key figure and the bar of the levies, and one above the other, 20 points
/// apart, where it has less. A part may follow under a hairline, over the whole width, such as a second figure or a row
/// of tiles.
///
/// What hangs out of a part, such as the popover of the levy bar (`LevyBarView`), is drawn over the hairline, the part
/// under it and the edge of the card: the two parts are drawn above the rest, and the look of the card under all of its
/// content. To cover what follows the card on a page as well, the page draws the card above it (a higher `zIndex`).
///
/// VoiceOver reads the card as a group under `label`.
struct ResultCard<Leading: View, Trailing: View, Below: View>: View {
    let label: String
    private let leading: Leading
    private let trailing: Trailing
    private let below: Below
    private let hasBelow: Bool

    /// A card named `label` with `leading` and `trailing` side by side, and `below` under a hairline.
    init(
        label: String, @ViewBuilder leading: () -> Leading, @ViewBuilder trailing: () -> Trailing,
        @ViewBuilder below: () -> Below
    ) {
        self.label = label
        self.leading = leading()
        self.trailing = trailing()
        self.below = below()
        hasBelow = true
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ResultColumns {
                VStack(alignment: .leading, spacing: DesignMetrics.innerSpacing) {
                    leading
                }
                VStack(alignment: .leading, spacing: DesignMetrics.innerSpacing) {
                    trailing
                }
            }
            .zIndex(1)
            if hasBelow {
                Rectangle()
                    .fill(Palette.sep)
                    .frame(height: 1)
                    .padding(.top, ResultCardLayout.rowGap)
                below
                    .padding(.top, ResultCardLayout.belowGap)
            }
        }
        .padding(DesignMetrics.cardPadding)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background {
            // The look of the card, with its ring, lies under the content rather than over it, as no content of the
            // card reaches its edge but what hangs out of a part.
            Color.clear
                .card()
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(label)
    }
}

/// A result card with nothing under its two parts.
extension ResultCard where Below == EmptyView {
    /// A card named `label` with `leading` and `trailing` side by side, and no part under a hairline.
    init(label: String, @ViewBuilder leading: () -> Leading, @ViewBuilder trailing: () -> Trailing) {
        self.label = label
        self.leading = leading()
        self.trailing = trailing()
        below = EmptyView()
        hasBelow = false
    }
}

/// Places the two parts of a result card, its two subviews: side by side in columns of one width, aligned at the top,
/// or the first one above the second in the whole width. The layout is as high as the taller of the two side by side,
/// or as the two and the gap between them.
private struct ResultColumns: Layout {
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        guard subviews.count == 2 else { return .zero }
        let width = availableWidth(proposal)
        let sizes = sizes(subviews, width: width)
        if ResultCardLayout.standsSideBySide(innerWidth: width) {
            return CGSize(width: width, height: max(sizes.leading.height, sizes.trailing.height))
        }
        return CGSize(width: width, height: sizes.leading.height + ResultCardLayout.rowGap + sizes.trailing.height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        guard subviews.count == 2 else { return }
        if ResultCardLayout.standsSideBySide(innerWidth: bounds.width) {
            let columnWidth = columnWidth(in: bounds.width)
            subviews[0].place(
                at: CGPoint(x: bounds.minX, y: bounds.minY), anchor: .topLeading,
                proposal: ProposedViewSize(width: columnWidth, height: nil))
            subviews[1].place(
                at: CGPoint(x: bounds.minX + columnWidth + ResultCardLayout.columnGap, y: bounds.minY),
                anchor: .topLeading, proposal: ProposedViewSize(width: columnWidth, height: nil))
        } else {
            let heightOfLeading = sizes(subviews, width: bounds.width).leading.height
            subviews[0].place(
                at: CGPoint(x: bounds.minX, y: bounds.minY), anchor: .topLeading,
                proposal: ProposedViewSize(width: bounds.width, height: nil))
            subviews[1].place(
                at: CGPoint(x: bounds.minX, y: bounds.minY + heightOfLeading + ResultCardLayout.rowGap),
                anchor: .topLeading, proposal: ProposedViewSize(width: bounds.width, height: nil))
        }
    }

    /// The width to lay out in: the one proposed, or for none the width of the two columns side by side. A proposal of
    /// no width at all is the question for the least room the parts need: one column of the least width, not the
    /// height that the parts would have at a width of nothing.
    private func availableWidth(_ proposal: ProposedViewSize) -> CGFloat {
        if let width = proposal.width, width.isFinite {
            return width > 0 ? width : ResultCardLayout.minimumColumnWidth
        }
        return 2 * ResultCardLayout.minimumColumnWidth + ResultCardLayout.columnGap
    }

    private func columnWidth(in width: CGFloat) -> CGFloat {
        (width - ResultCardLayout.columnGap) / 2
    }

    /// The sizes of the two parts in `width`: each in a column of its own side by side, each in the whole width where
    /// they stand one above the other.
    private func sizes(_ subviews: Subviews, width: CGFloat) -> (leading: CGSize, trailing: CGSize) {
        let beside = ResultCardLayout.standsSideBySide(innerWidth: width)
        let proposal = ProposedViewSize(width: beside ? columnWidth(in: width) : width, height: nil)
        return (subviews[0].sizeThatFits(proposal), subviews[1].sizeThatFits(proposal))
    }
}
