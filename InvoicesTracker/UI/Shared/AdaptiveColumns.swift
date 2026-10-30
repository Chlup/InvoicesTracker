import SwiftUI

/// Lays its subviews out in equal columns that fill the width: as many columns as fit at `minimumColumnWidth`, and never
/// more than there are subviews, so that two cards in a wide window share it and in a narrow one stand one under the
/// other. (A `LazyVGrid` with an adaptive column keeps the columns that are empty, which would leave the width unused.)
/// The columns are aligned at the top, and a row is as high as its highest subview. With `equalRowHeights` every
/// subview of a row is also offered the height of the row, which a subview that fills the room it is offered takes, so
/// that cards side by side are of one height; the others keep their own.
struct AdaptiveColumns: Layout {
    let minimumColumnWidth: CGFloat
    let spacing: CGFloat
    var equalRowHeights = false

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        guard !subviews.isEmpty else { return .zero }
        let width = availableWidth(proposal, count: subviews.count)
        let columns = columnCount(width: width, count: subviews.count)
        let heights = rowHeights(subviews, columns: columns, columnWidth: columnWidth(width: width, columns: columns))
        return CGSize(width: width, height: heights.reduce(0, +) + spacing * CGFloat(heights.count - 1))
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        guard !subviews.isEmpty else { return }
        let columns = columnCount(width: bounds.width, count: subviews.count)
        let width = columnWidth(width: bounds.width, columns: columns)
        let heights = rowHeights(subviews, columns: columns, columnWidth: width)
        var top = bounds.minY
        for (row, height) in heights.enumerated() {
            for column in 0..<columns {
                let index = row * columns + column
                guard index < subviews.count else { break }
                subviews[index].place(
                    at: CGPoint(x: bounds.minX + CGFloat(column) * (width + spacing), y: top), anchor: .topLeading,
                    proposal: ProposedViewSize(width: width, height: equalRowHeights ? height : nil))
            }
            top += height + spacing
        }
    }

    /// The width to lay out in: the one proposed, or for none the width of all the subviews side by side. A proposal of
    /// no width at all is the question for the least room the columns need: one column of the least width, not the
    /// height that the subviews would have at a width of nothing.
    private func availableWidth(_ proposal: ProposedViewSize, count: Int) -> CGFloat {
        if let width = proposal.width, width.isFinite {
            return width > 0 ? width : minimumColumnWidth
        }
        return minimumColumnWidth * CGFloat(count) + spacing * CGFloat(count - 1)
    }

    private func columnCount(width: CGFloat, count: Int) -> Int {
        let fitting = Int(((width + spacing) / (minimumColumnWidth + spacing)).rounded(.down))
        return min(count, max(1, fitting))
    }

    private func columnWidth(width: CGFloat, columns: Int) -> CGFloat {
        (width - spacing * CGFloat(columns - 1)) / CGFloat(columns)
    }

    /// The height of each row: that of its highest subview at the width of a column.
    private func rowHeights(_ subviews: Subviews, columns: Int, columnWidth: CGFloat) -> [CGFloat] {
        let heights = subviews.map { $0.sizeThatFits(ProposedViewSize(width: columnWidth, height: nil)).height }
        return stride(from: 0, to: heights.count, by: columns).map { start in
            heights[start..<min(start + columns, heights.count)].max() ?? 0
        }
    }
}
