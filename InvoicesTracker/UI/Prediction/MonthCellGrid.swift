import SwiftUI

/// Lays the cells of a client's months out in equal columns that fill the width, in full rows: the columns are as many
/// as divide the number of cells and have room for cells of at least `minimumCellWidth` points with `spacing` between
/// each two of them. For the twelve months of a year that is 12 columns from 834 points (all in one row), 6 from 414
/// (January to June over July to December), 4 from 274, 3 from 204, 2 from 134 and 1 below that, so that no row is left
/// with a lone cell. Every row is as high as the tallest cell, and every cell is offered the height of its row, which
/// a cell that fills the room it is offered takes. (A `LazyVGrid` with an adaptive column keeps the columns that are
/// empty, which would leave the width unused and the cells narrow.)
struct MonthCellGrid: Layout {
    var minimumCellWidth: CGFloat = 64
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        guard !subviews.isEmpty else { return .zero }
        let width = availableWidth(proposal, count: subviews.count)
        let columns = columnCount(width: width, count: subviews.count)
        let height = rowHeight(subviews, cellWidth: cellWidth(width: width, columns: columns))
        let rows = rowCount(subviews.count, columns: columns)
        return CGSize(width: width, height: CGFloat(rows) * height + CGFloat(rows - 1) * spacing)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        guard !subviews.isEmpty else { return }
        let columns = columnCount(width: bounds.width, count: subviews.count)
        let width = cellWidth(width: bounds.width, columns: columns)
        let height = rowHeight(subviews, cellWidth: width)
        for index in subviews.indices {
            let row = index / columns
            let column = index % columns
            subviews[index].place(
                at: CGPoint(
                    x: bounds.minX + CGFloat(column) * (width + spacing),
                    y: bounds.minY + CGFloat(row) * (height + spacing)),
                anchor: .topLeading, proposal: ProposedViewSize(width: width, height: height))
        }
    }

    /// The width to lay out in: the one proposed, or for none the width of all the cells in a row. A proposal of no
    /// width at all is the question for the least room the cells need: one column of the least width, not the height
    /// that the cells would have at a width of nothing.
    private func availableWidth(_ proposal: ProposedViewSize, count: Int) -> CGFloat {
        if let width = proposal.width, width.isFinite {
            return width > 0 ? width : minimumCellWidth
        }
        return minimumCellWidth * CGFloat(count) + spacing * CGFloat(count - 1)
    }

    /// How many columns the cells stand in: the largest divisor of their number that is not more than the number of
    /// cells of the least width that the width holds. With twelve cells a width of 834 points holds twelve cells of 64
    /// points, and 833 holds eleven, which is no divisor of twelve, so the cells stand in six columns.
    private func columnCount(width: CGFloat, count: Int) -> Int {
        let holds = min(count, max(1, Int(((width + spacing) / (minimumCellWidth + spacing)).rounded(.down))))
        return (1...holds).reversed().first { count % $0 == 0 } ?? 1
    }

    private func rowCount(_ count: Int, columns: Int) -> Int {
        (count + columns - 1) / columns
    }

    private func cellWidth(width: CGFloat, columns: Int) -> CGFloat {
        (width - spacing * CGFloat(columns - 1)) / CGFloat(columns)
    }

    /// The height of every row: that of the tallest cell at the width of a column.
    private func rowHeight(_ subviews: Subviews, cellWidth: CGFloat) -> CGFloat {
        subviews.map { $0.sizeThatFits(ProposedViewSize(width: cellWidth, height: nil)).height }.max() ?? 0
    }
}
