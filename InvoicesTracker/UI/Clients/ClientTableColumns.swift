import CoreGraphics

/// The columns of the table of Odběratelé, and how wide each of them is in a table of a given width. A row has five:
/// Odběratel, Měna a DPH, Jazyk faktury, Rok Y and the chevron, with 14 points between each two of them. After them
/// come 16 points and the room of the button Nová faktura, and the row has 20 points before its first column and
/// after the button.
///
/// Odběratel, Měna a DPH and Rok Y share the room in the proportion of their weights, as the fractions of a grid do,
/// none of them narrower than its least width; Jazyk faktury and the chevron keep their widths. In the least width of
/// the table every column has its least width. Below it the table keeps that width and scrolls sideways
/// (`ClientTableView`).
nonisolated enum ClientTableColumns {
    /// A column of a row.
    struct Column: Sendable, Equatable {
        /// The least width. A column with no weight has no other.
        var minimum: CGFloat

        /// The part of the room that the columns with a weight share that falls to this one, in the proportion of the
        /// weights. A column with none keeps its least width.
        var weight: CGFloat
    }

    /// Odběratel, Měna a DPH, Jazyk faktury, Rok Y and the chevron. The least widths of all but Odběratel hold what
    /// their cells say whole (`ClientTableViewTests` measures them): in Měna a DPH the widest tag of a currency with
    /// "přenesená povinnost", in Jazyk faktury its name, in Rok Y the longest of its two lines. Odběratel gives way:
    /// its name and the line under it are cut short, so that the least width of the table, 814 points, fits the card
    /// of the page of the least window (820 points).
    static let columns: [Column] = [
        Column(minimum: 150, weight: 2),
        Column(minimum: 176, weight: 1.3),
        Column(minimum: 84, weight: 0),
        Column(minimum: 166, weight: 1.2),
        Column(minimum: 14, weight: 0),
    ]

    /// The room between two columns of a row.
    static let columnGap: CGFloat = 14

    /// The room between the chevron and the button Nová faktura.
    static let buttonGap: CGFloat = 16

    /// The room of the button Nová faktura, which stands at the end of it.
    static let buttonRoom: CGFloat = 112

    /// The room before the first column and after the button.
    static let margin: CGFloat = 20

    /// The least width of the table: the least widths of its columns, with the room between them and around them.
    static var minimumWidth: CGFloat {
        columns.map(\.minimum).reduce(0, +) + roomAroundColumns
    }

    /// The room a row takes besides its columns.
    private static var roomAroundColumns: CGFloat {
        columnGap * CGFloat(columns.count - 1) + buttonGap + buttonRoom + 2 * margin
    }

    /// The widths of the columns in a table `width` points wide, in their order. Below `minimumWidth` they are the
    /// least widths.
    static func columnWidths(inTableOf width: CGFloat) -> [CGFloat] {
        var widths = columns.map(\.minimum)
        var sharing = columns.indices.filter { columns[$0].weight > 0 }
        let kept = columns.indices.filter { columns[$0].weight == 0 }.map { widths[$0] }.reduce(0, +)
        var room = max(width, minimumWidth) - roomAroundColumns - kept
        // A column whose share of the room is under its least width keeps that width, and the others share what is
        // left of the room.
        while !sharing.isEmpty {
            let unit = room / sharing.map { columns[$0].weight }.reduce(0, +)
            guard let held = sharing.first(where: { columns[$0].weight * unit < columns[$0].minimum }) else {
                for index in sharing {
                    widths[index] = columns[index].weight * unit
                }
                break
            }
            room -= columns[held].minimum
            sharing.removeAll { $0 == held }
        }
        return widths
    }
}
