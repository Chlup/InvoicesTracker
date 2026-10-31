import CoreGraphics

/// The columns of the table of Odběratelé, and how wide each of them is in a table of a given width: the grid of the
/// prototype, `minmax(150px, 2fr) minmax(130px, 1.3fr) minmax(76px, 0.8fr) minmax(110px, 1fr)`, with `gap` between two
/// columns and `DataTableMetrics.margin` at either end. The four share the room of the table in the proportions of
/// their fractions, as a CSS grid shares it: a column whose share is less than its least width keeps that width, and
/// the others share the rest. They have no greatest width.
///
/// The least width of Měna a DPH is raised from the prototype's 130 points to 176, which holds the widest chip of a
/// currency with the longest VAT text whole, "BGN" with "přenesená povinnost" (`ClientTableViewTests` measures it);
/// the other least widths hold what their cells say as they are, and Odběratel gives way, its name cut short. So the
/// least width of the table is 580 points, where the prototype's is 540, and below it the table keeps that width and
/// scrolls sideways (`ClientTableView`), as it does in the least window with the detail open.
nonisolated enum ClientTableColumns {
    /// A column of a row.
    struct Column: Sendable, Equatable {
        /// The least width.
        var minimum: CGFloat

        /// The part of the room that falls to this column, in the proportions of the fractions of the columns that
        /// share it.
        var fraction: CGFloat
    }

    /// Odběratel, Měna a DPH, Šablony and Přijato Y.
    static let columns: [Column] = [
        Column(minimum: 150, fraction: 2),
        Column(minimum: 176, fraction: 1.3),
        Column(minimum: 76, fraction: 0.8),
        Column(minimum: 110, fraction: 1),
    ]

    /// The room between two columns: 12 points, as the grid of the prototype has it for this table.
    static let gap: CGFloat = 12

    /// The least width of the table: the least widths of its columns, with the room between them and at its ends.
    static var minimumWidth: CGFloat {
        columns.map(\.minimum).reduce(0, +) + roomAroundColumns
    }

    /// The room a row takes besides its columns: between each two of them, and at its ends.
    private static var roomAroundColumns: CGFloat {
        gap * CGFloat(columns.count - 1) + 2 * DataTableMetrics.margin
    }

    /// The widths of the columns in a table `width` points wide, in their order; below `minimumWidth` those of a table
    /// of that width. Each column is its fraction of the room in the proportions of the fractions of the columns that
    /// share it, and a column whose part is less than its least width keeps that width and leaves the sharing, until
    /// every column that shares has at least its least width, as the fractions of a CSS grid are worked out.
    static func columnWidths(inTableOf width: CGFloat) -> [CGFloat] {
        var widths = columns.map(\.minimum)
        var sharing = Array(columns.indices)
        var left = max(width, minimumWidth) - roomAroundColumns
        while !sharing.isEmpty {
            let share = left / sharing.map { columns[$0].fraction }.reduce(0, +)
            let tooNarrow = sharing.filter { share * columns[$0].fraction < columns[$0].minimum }
            guard !tooNarrow.isEmpty else {
                for index in sharing {
                    widths[index] = share * columns[index].fraction
                }
                break
            }
            for index in tooNarrow {
                left -= columns[index].minimum
            }
            sharing.removeAll { tooNarrow.contains($0) }
        }
        return widths
    }
}
