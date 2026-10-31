import CoreGraphics

/// The columns of the table of Faktury, and how wide each of them is in a table of a given width: the grid of the
/// design board, `84px minmax(72px, 1.4fr) 64px 64px minmax(108px, 1.1fr) minmax(96px, 1fr) minmax(90px, 0.9fr) 96px`,
/// with `DataTableMetrics.gap` between two columns and `DataTableMetrics.margin` at either end. Číslo, Vystaveno,
/// Zaplaceno and Stav have widths of their own, and the other four share what the table has left in the proportions
/// of their fractions, as a CSS grid shares it: a column whose share is less than its least width keeps that width,
/// and the others share the rest. They have no greatest width.
///
/// The widths of the board are raised where the cells need more: Bez DPH holds 999 999,99 in any currency in use
/// (`InvoiceAmountText`), Stav the widest pill of the list ("Čeká na platbu"), and a date column holds a date with its
/// year, "28. 12. 2026" (`InvoiceDateText`), while a row of the table prints one, which is a date of another year than
/// the one shown. The least width of the table is the least widths of its columns with the room between and around
/// them, which is a little more than the board's 764 points. Below it the table keeps it and scrolls sideways
/// (`InvoiceTableView`).
nonisolated struct InvoiceTableColumns: Sendable, Equatable {
    /// How a column takes its width.
    enum Width: Sendable, Equatable {
        /// A width of its own, in points.
        case fixed(CGFloat)

        /// A share of what is left, `fraction` of it in the proportions of the fractions of the columns, and at least
        /// `minimum` points.
        case flexible(minimum: CGFloat, fraction: CGFloat)

        /// The least width of the column: its own width, or the least width of its share.
        var minimum: CGFloat {
            switch self {
            case .fixed(let width): width
            case .flexible(let minimum, _): minimum
            }
        }
    }

    /// The least width of the table on the board, which the least widths of the columns raised for their cells exceed.
    static let boardMinimumWidth: CGFloat = 764

    /// The width of a date column whose rows print dates of the year shown, "31. 12.", and its name whole.
    static let dateWidth: CGFloat = 64

    /// The width of a date column with a date of another year among its rows, "28. 12. 2026".
    static let dateWithYearWidth: CGFloat = 80

    /// Číslo, Odběratel, Vystaveno, Zaplaceno, V Kč bez DPH, Bez DPH, Čistý příjem and Stav, in their order. Bez DPH
    /// has 104 points at least, not the board's 96, to hold "999 999,99 USD" and the other currencies with their
    /// widest codes; Stav has 98, not 96, to hold the pill "Čeká na platbu".
    let widths: [Width]

    /// The columns of a table whose rows print a date of issue of another year (`issueDatesShowYear`), a date of
    /// payment of another year (`paymentDatesShowYear`), both or neither.
    init(issueDatesShowYear: Bool = false, paymentDatesShowYear: Bool = false) {
        let date = { (withYear: Bool) in Width.fixed(withYear ? Self.dateWithYearWidth : Self.dateWidth) }
        widths = [
            .fixed(84), .flexible(minimum: 72, fraction: 1.4), date(issueDatesShowYear), date(paymentDatesShowYear),
            .flexible(minimum: 108, fraction: 1.1), .flexible(minimum: 104, fraction: 1),
            .flexible(minimum: 90, fraction: 0.9), .fixed(98),
        ]
    }

    /// The least width of the table: the least widths of its columns, with the room between them and at its ends, and
    /// never less than the board's.
    var minimumWidth: CGFloat {
        max(Self.boardMinimumWidth, widths.map(\.minimum).reduce(0, +) + roomAroundColumns)
    }

    /// The room the table takes besides its columns: between each two of them, and at its ends.
    private var roomAroundColumns: CGFloat {
        DataTableMetrics.gap * CGFloat(widths.count - 1) + 2 * DataTableMetrics.margin
    }

    /// The widths of the columns in a table `width` points wide, in their order; below `minimumWidth` those of a table
    /// of that width. A column of its own width has it. The flexible columns share the room left: each is its fraction
    /// of the room in the proportions of the fractions of those that share it, and a column whose part is less than
    /// its least width keeps that width and leaves the sharing, until every column that shares has at least its least
    /// width, as the fractions of a CSS grid are worked out.
    func columnWidths(inTableOf width: CGFloat) -> [CGFloat] {
        let room = max(width, minimumWidth) - roomAroundColumns
        var columns = widths.map(\.minimum)
        var sharing = widths.indices.filter { index in
            if case .flexible = widths[index] { return true }
            return false
        }
        var left = room - widths.indices.filter { !sharing.contains($0) }.map { columns[$0] }.reduce(0, +)
        while !sharing.isEmpty {
            // A CSS grid shares by fractions that add up to 1 at least, so fractions below that leave room unused.
            let fractions = max(1, sharing.map { fraction(of: $0) }.reduce(0, +))
            let share = left / fractions
            let tooNarrow = sharing.filter { share * fraction(of: $0) < widths[$0].minimum }
            guard !tooNarrow.isEmpty else {
                for index in sharing {
                    columns[index] = share * fraction(of: index)
                }
                break
            }
            for index in tooNarrow {
                left -= widths[index].minimum
            }
            sharing.removeAll { tooNarrow.contains($0) }
        }
        return columns
    }

    /// The fraction of the column at `index`, or nothing for a column of its own width.
    private func fraction(of index: Int) -> CGFloat {
        if case .flexible(_, let fraction) = widths[index] {
            return fraction
        }
        return 0
    }
}
