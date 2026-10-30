import SwiftUI

/// Lays its subviews out in rows like words in a paragraph: side by side at the size each asks for, and on to the next
/// row where the width proposed is used up. For a handful of chips or buttons that should wrap, not scroll. The gap
/// between rows is the one between the subviews of a row (`spacing`), unless `lineSpacing` gives another.
///
/// The subviews of a row line up at their middle, or by `alignment` where it is another: at the top, as the figures of
/// a row of tiles do, when the tiles differ in height. A subview that is flexible in its width, such as text that
/// breaks its lines, is asked for the width it wants, or for no more than `maximumSubviewWidth` where that is given.
struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    /// The gap between rows, or nil for the same as `spacing`.
    var lineSpacing: CGFloat?

    /// How the subviews of a row line up against each other.
    var alignment = VerticalAlignment.center

    /// The greatest width a subview is asked for, or nil for the width it wants. A subview is never asked for more than
    /// the width of the layout either, so one that is flexible has the room there is where there is less than this.
    var maximumSubviewWidth: CGFloat?

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = rows(for: subviews, width: proposal.width ?? .infinity)
        let width = rows.map(\.width).max() ?? 0
        let height = rows.map(\.height).reduce(0, +) + (lineSpacing ?? spacing) * CGFloat(max(0, rows.count - 1))
        return CGSize(width: width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let request = request(width: bounds.width)
        var top = bounds.minY
        for row in rows(for: subviews, width: bounds.width) {
            var left = bounds.minX
            for index in row.indices {
                let dimensions = subviews[index].dimensions(in: request)
                subviews[index].place(
                    at: CGPoint(x: left, y: top + row.above - dimensions[alignment]), anchor: .topLeading,
                    proposal: ProposedViewSize(width: dimensions.width, height: dimensions.height))
                left += dimensions.width + spacing
            }
            top += row.height + (lineSpacing ?? spacing)
        }
    }

    /// One row: the subviews in it, how wide it is, and how far it reaches above and below the line the subviews are
    /// aligned on, which makes it as high as the tallest of them where they line up at the top, the middle or the
    /// bottom.
    private struct Row {
        var indices: [Int] = []
        var width: CGFloat = 0
        var above: CGFloat = 0
        var below: CGFloat = 0

        var height: CGFloat {
            above + below
        }
    }

    /// The size every subview is asked for in a layout of `width` points: none, or no more than the greatest width. A
    /// layout asked for the least room it needs, a width of nothing, holds a subview to the greatest width alone.
    private func request(width: CGFloat) -> ProposedViewSize {
        guard let maximumSubviewWidth else { return .unspecified }
        return ProposedViewSize(width: width > 0 ? min(maximumSubviewWidth, width) : maximumSubviewWidth, height: nil)
    }

    /// The rows the subviews fall into in a layout of `width` points: a subview goes on to the next row where the row
    /// it would stand in has no room left for it, and every row has at least one.
    private func rows(for subviews: Subviews, width: CGFloat) -> [Row] {
        let request = request(width: width)
        var rows: [Row] = []
        var current = Row()
        for index in subviews.indices {
            let dimensions = subviews[index].dimensions(in: request)
            let needed = current.indices.isEmpty ? dimensions.width : current.width + spacing + dimensions.width
            if needed > width, !current.indices.isEmpty {
                rows.append(current)
                current = Row()
            }
            current.width = current.indices.isEmpty ? dimensions.width : current.width + spacing + dimensions.width
            current.above = max(current.above, dimensions[alignment])
            current.below = max(current.below, dimensions.height - dimensions[alignment])
            current.indices.append(index)
        }
        if !current.indices.isEmpty {
            rows.append(current)
        }
        return rows
    }
}
