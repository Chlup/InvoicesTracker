import SwiftUI

/// Lays its subviews out in rows like words in a paragraph: side by side at the size each asks for, and on to the next
/// row where the width proposed is used up. For a handful of chips or buttons that should wrap, not scroll. The gap
/// between rows is the one between the subviews of a row (`spacing`), unless `lineSpacing` gives another.
struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    /// The gap between rows, or nil for the same as `spacing`.
    var lineSpacing: CGFloat?

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = rows(for: subviews, width: proposal.width ?? .infinity)
        let width = rows.map(\.width).max() ?? 0
        let height = rows.map(\.height).reduce(0, +) + (lineSpacing ?? spacing) * CGFloat(max(0, rows.count - 1))
        return CGSize(width: width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var top = bounds.minY
        for row in rows(for: subviews, width: bounds.width) {
            var left = bounds.minX
            for index in row.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(
                    at: CGPoint(x: left, y: top + (row.height - size.height) / 2), anchor: .topLeading,
                    proposal: ProposedViewSize(size))
                left += size.width + spacing
            }
            top += row.height + (lineSpacing ?? spacing)
        }
    }

    /// One row: the subviews in it, and how wide and how high it is.
    private struct Row {
        var indices: [Int] = []
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    private func rows(for subviews: Subviews, width: CGFloat) -> [Row] {
        var rows: [Row] = []
        var current = Row()
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            let needed = current.indices.isEmpty ? size.width : current.width + spacing + size.width
            if needed > width, !current.indices.isEmpty {
                rows.append(current)
                current = Row()
            }
            current.width = current.indices.isEmpty ? size.width : current.width + spacing + size.width
            current.height = max(current.height, size.height)
            current.indices.append(index)
        }
        if !current.indices.isEmpty {
            rows.append(current)
        }
        return rows
    }
}
