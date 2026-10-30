import CoreGraphics

/// The columns of the table of Faktury, and how wide each of them is in a table of a given width. Each column has a
/// least, an ideal and a greatest width. In the least width of the table every column has its least width; up to the
/// ideal width of the table the columns grow together from their least widths to their ideal ones; and beyond it they
/// share what is left equally, each up to its greatest width, Odběratel without one. Below its least width the table
/// keeps it and scrolls sideways (`InvoiceTableView`).
nonisolated enum InvoiceTableColumns {
    /// How wide a column may be.
    struct Width: Sendable, Equatable {
        var minimum: CGFloat
        var ideal: CGFloat
        var maximum: CGFloat
    }

    /// Číslo, Odběratel, Vystaveno, Zaplaceno, Bez DPH, V Kč, Čistý příjem and Stav. The least widths of Číslo and of
    /// the amounts hold the widest number in use and 999 999,99 with its currency whole (`InvoiceNumberText`,
    /// `InvoiceAmountText`), those of Vystaveno, Zaplaceno and Čistý příjem their names (`InvoiceColumnTitle`), that of
    /// V Kč the line under an estimate, "ČNB k vystavení 21,622" (`InvoiceCaptionText`), and that of Čistý příjem
    /// 999 999 Kč with the sign of an estimate (`InvoiceNetIncomeText`) and the lines under it, "odvody snížila",
    /// "odvody 100,0 %" and "odhad". The line under a payment at the uniform rate, such as "jednotný kurz 21,840 ·
    /// 2. 10.", is longer and may be cut short at the least width. Odběratel gives them the room, cutting a long name
    /// short, so that the least width of the table, 820 points, is the page of the least window with the detail closed.
    static let widths: [Width] = [
        Width(minimum: 84, ideal: 92, maximum: 140),
        Width(minimum: 70, ideal: 220, maximum: .infinity),
        Width(minimum: 62, ideal: 84, maximum: 110),
        Width(minimum: 62, ideal: 84, maximum: 110),
        Width(minimum: 104, ideal: 116, maximum: 160),
        Width(minimum: 118, ideal: 140, maximum: 190),
        Width(minimum: 104, ideal: 116, maximum: 160),
        Width(minimum: 120, ideal: 150, maximum: 200),
    ]

    /// The room between two columns.
    static let spacing: CGFloat = 8

    /// The room before the first column and after the last.
    static let margin: CGFloat = 20

    /// The room at the start of Stav, before its title and its pill. The amounts of Čistý příjem end at the right edge
    /// of their column, so without it the pill would stand only `spacing` from them.
    static let statusInset: CGFloat = 16

    /// The least width of the table: the least widths of its columns, with the room between them and at its ends.
    static var minimumWidth: CGFloat {
        widths.map(\.minimum).reduce(0, +) + roomAroundColumns
    }

    /// The room the table takes besides its columns: between each two of them, and at its ends.
    private static var roomAroundColumns: CGFloat {
        spacing * CGFloat(widths.count - 1) + 2 * margin
    }

    /// The widths of the columns in a table `width` points wide, in their order. Below `minimumWidth` they are the
    /// least widths.
    static func columnWidths(inTableOf width: CGFloat) -> [CGFloat] {
        let room = width - roomAroundColumns
        let least = widths.map(\.minimum).reduce(0, +)
        let ideal = widths.map(\.ideal).reduce(0, +)
        guard room > least else {
            return widths.map(\.minimum)
        }
        guard room > ideal else {
            let share = (room - least) / (ideal - least)
            return widths.map { $0.minimum + ($0.ideal - $0.minimum) * share }
        }
        // Beyond the ideal widths, what is left goes to the columns in equal shares; a column that reaches its greatest
        // width keeps it, and the rest of its share goes to the others.
        var columns = widths.map(\.ideal)
        var left = room - ideal
        while left > 0.001 {
            let growing = columns.indices.filter { columns[$0] < widths[$0].maximum }
            guard !growing.isEmpty else { break }
            let share = left / CGFloat(growing.count)
            for index in growing {
                let added = min(share, widths[index].maximum - columns[index])
                columns[index] += added
                left -= added
            }
        }
        return columns
    }
}
