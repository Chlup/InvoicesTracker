import CoreGraphics
import Testing
@testable import InvoicesTracker

/// How wide the columns of the table of Faktury are in a table of a given width: Číslo, Odběratel, Vystaveno,
/// Zaplaceno, V Kč bez DPH, Bez DPH, Čistý příjem and Stav, on the grid of the design board, 8 points apart, with 16
/// points before the first and after the last. Číslo, the dates and Stav have widths of their own; the other four share
/// what is left in the proportions 1.4 : 1.1 : 1 : 0.9, as the fractions of a CSS grid do, and a column whose share is
/// less than its least width keeps that width while the others share the rest.
struct InvoiceTableColumnsTests {
    /// The least width of every column: the board's, with Bez DPH raised from 96 to hold 999 999,99 in the widest
    /// currency and Stav from 96 to hold the widest pill.
    private let least: [CGFloat] = [84, 72, 64, 64, 108, 104, 90, 98]

    /// The share of each column of the room left, or nil for a column with a width of its own.
    private let fractions: [CGFloat?] = [nil, 1.4, nil, nil, 1.1, 1, 0.9, nil]

    /// The width of a table whose columns are `columns` wide: the columns, 7 gaps of 8 points and 2 margins of 16.
    private func width(holding columns: [CGFloat]) -> CGFloat {
        columns.reduce(0, +) + 7 * 8 + 2 * 16
    }

    private func isClose(_ found: [CGFloat], to expected: [CGFloat]) -> Bool {
        found.count == expected.count && zip(found, expected).allSatisfy { ($0 - $1).magnitude < 0.001 }
    }

    // MARK: The least width

    @Test func theColumnsAreTheGridOfTheBoardWithTheTwoColumnsThatAreRaised() {
        let columns = InvoiceTableColumns()

        #expect(
            columns.widths == [
                .fixed(84), .flexible(minimum: 72, fraction: 1.4), .fixed(64), .fixed(64),
                .flexible(minimum: 108, fraction: 1.1), .flexible(minimum: 104, fraction: 1),
                .flexible(minimum: 90, fraction: 0.9), .fixed(98),
            ])
        #expect(DataTableMetrics.gap == 8)
        #expect(DataTableMetrics.margin == 16)
    }

    /// The board's table is at least 764 points wide; the two columns that are raised make the least width of this one
    /// the least widths of its columns with the room between and around them, 772 points.
    @Test func theLeastWidthOfTheTableIsTheLeastWidthsOfItsColumnsWithTheRoomBetweenAndAroundThem() {
        let columns = InvoiceTableColumns()

        #expect(least.reduce(0, +) == 684)
        #expect(columns.minimumWidth == 772)
        #expect(columns.minimumWidth > InvoiceTableColumns.boardMinimumWidth)
        #expect(InvoiceTableColumns.boardMinimumWidth == 764)
    }

    @Test func atTheLeastWidthOfTheTableEveryColumnHasItsLeastWidth() {
        let columns = InvoiceTableColumns()

        #expect(isClose(columns.columnWidths(inTableOf: 772), to: least))
    }

    @Test func belowItsLeastWidthTheColumnsKeepTheirLeastWidths() {
        for table: CGFloat in [0, 300, 492, 764, 771] {
            let found = InvoiceTableColumns().columnWidths(inTableOf: table)
            #expect(isClose(found, to: least), "a table of \(table): \(found)")
        }
    }

    // MARK: The fractions

    /// Once every flexible column has more than its least width (in a table of 856 points or more, where the share of
    /// a fraction reaches 104 points, the least width of Bez DPH), the room a wider table has more goes to them in the
    /// proportions 1.4 : 1.1 : 1 : 0.9, and none to the columns of a width of their own.
    @Test func theExtraRoomSplitsInTheProportionsOfTheFractions() {
        let columns = InvoiceTableColumns()
        let narrower = columns.columnWidths(inTableOf: 900)
        let wider = columns.columnWidths(inTableOf: 1_340)

        for index in least.indices {
            let grown = wider[index] - narrower[index]
            guard let fraction = fractions[index] else {
                #expect(grown.magnitude < 0.001, "column \(index) grew by \(grown)")
                continue
            }
            // 440 points more, shared by 4.4 fractions: 100 a fraction.
            #expect((grown - 100 * fraction).magnitude < 0.001, "column \(index) grew by \(grown)")
        }
        // At 900 points each flexible column is its fraction of the room they share: 900 less the other columns (310),
        // the gaps (56) and the margins (32) is 502 points, 114,09 a fraction.
        let share = CGFloat(502) / 4.4
        for index in least.indices {
            guard let fraction = fractions[index] else { continue }
            #expect((narrower[index] - share * fraction).magnitude < 0.001, "column \(index) is \(narrower[index])")
        }
    }

    /// A column whose share is less than its least width keeps that width, and the other flexible columns share what
    /// is left in their proportions. In a table of 850 points the room of the flexible columns is 452 points: a
    /// fraction would be 102,73 points, too little for Bez DPH (104 for its 1 fraction), which keeps 104; the other
    /// three share 348 points, 102,35 a fraction, which is enough for each of them.
    @Test func aColumnWhoseShareIsLessThanItsLeastWidthKeepsItAndTheOthersShareTheRest() {
        let found = InvoiceTableColumns().columnWidths(inTableOf: 850)

        let share = CGFloat(348) / 3.4
        let expected: [CGFloat] = [84, 1.4 * share, 64, 64, 1.1 * share, 104, 0.9 * share, 98]
        #expect(isClose(found, to: expected), "found \(found)")
        #expect((width(holding: found) - 850).magnitude < 0.001)
    }

    /// Just above the least width every column but Odběratel is still below its share, so Odběratel takes all the
    /// room the table has more: the column with the smallest least width for its fraction grows first.
    @Test func justAboveItsLeastWidthOdberatelTakesTheRoomFirst() {
        let found = InvoiceTableColumns().columnWidths(inTableOf: 800)

        #expect(isClose(found, to: [84, 100, 64, 64, 108, 104, 90, 98]), "found \(found)")
    }

    @Test func theColumnsFillTheTableEachWithAtLeastItsLeastWidth() {
        for table in stride(from: CGFloat(772), through: 3_000, by: 37) {
            let columns = InvoiceTableColumns().columnWidths(inTableOf: table)
            #expect((width(holding: columns) - table).magnitude < 0.001, "a table of \(table)")
            for index in columns.indices {
                #expect(columns[index] >= least[index] - 0.001, "column \(index) in a table of \(table)")
            }
        }
    }

    @Test func noColumnNarrowsAsTheTableWidens() {
        var previous = InvoiceTableColumns().columnWidths(inTableOf: 772)
        for table in stride(from: CGFloat(772), through: 3_000, by: 10) {
            let columns = InvoiceTableColumns().columnWidths(inTableOf: table)
            for index in columns.indices {
                #expect(columns[index] >= previous[index] - 0.001, "column \(index) in a table of \(table)")
            }
            previous = columns
        }
    }

    // MARK: Dates with their year

    /// A date of the shown year prints as "31. 12.", which 64 points hold; a date of another year prints its year,
    /// "28. 12. 2026", and its column is widened to 80 points while a row of the table prints one. The table is that
    /// much wider at least.
    @Test func aDateColumnWithAYearIsWidenedAndTheTableWithIt() {
        let issued = InvoiceTableColumns(issueDatesShowYear: true, paymentDatesShowYear: false)
        let paid = InvoiceTableColumns(issueDatesShowYear: false, paymentDatesShowYear: true)
        let both = InvoiceTableColumns(issueDatesShowYear: true, paymentDatesShowYear: true)

        #expect(InvoiceTableColumns.dateWidth == 64)
        #expect(InvoiceTableColumns.dateWithYearWidth == 80)
        #expect(issued.widths[2] == .fixed(80))
        #expect(issued.widths[3] == .fixed(64))
        #expect(paid.widths[2] == .fixed(64))
        #expect(paid.widths[3] == .fixed(80))
        #expect(issued.minimumWidth == 788)
        #expect(paid.minimumWidth == 788)
        #expect(both.minimumWidth == 804)
        #expect(isClose(both.columnWidths(inTableOf: 804), to: [84, 72, 80, 80, 108, 104, 90, 98]))
    }
}
