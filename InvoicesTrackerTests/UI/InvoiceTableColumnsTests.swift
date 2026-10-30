import CoreGraphics
import Testing
@testable import InvoicesTracker

/// How wide the columns of the table of Faktury are in a table of a given width: Číslo, Odběratel, Vystaveno,
/// Zaplaceno, Bez DPH, V Kč, Čistý příjem and Stav, 8 points apart, with 20 points before the first and after the last.
/// They fill the table, each between its least and its greatest width, from their least widths in the least table to
/// their ideal ones, and beyond that Odběratel takes what the others cannot.
struct InvoiceTableColumnsTests {
    private let least: [CGFloat] = [84, 70, 62, 62, 104, 118, 104, 120]
    private let ideal: [CGFloat] = [92, 220, 84, 84, 116, 140, 116, 150]
    private let greatest: [CGFloat] = [140, .infinity, 110, 110, 160, 190, 160, 200]

    /// The width of a table whose columns are `columns` wide: the columns, 7 gaps of 8 points and 2 margins of 20.
    private func width(holding columns: [CGFloat]) -> CGFloat {
        columns.reduce(0, +) + 7 * 8 + 2 * 20
    }

    @Test func theLeastWidthOfTheTableIsTheLeastWidthsOfItsColumnsWithTheRoomBetweenAndAroundThem() {
        #expect(least.reduce(0, +) == 724)
        #expect(InvoiceTableColumns.minimumWidth == 820)
        #expect(InvoiceTableColumns.columnWidths(inTableOf: 820) == least)
    }

    @Test func belowItsLeastWidthTheColumnsKeepTheirLeastWidths() {
        for table: CGFloat in [0, 300, 484, 819] {
            #expect(InvoiceTableColumns.columnWidths(inTableOf: table) == least, "a table of \(table)")
        }
    }

    @Test func atItsIdealWidthEachColumnHasItsIdealWidth() {
        let table = width(holding: ideal)
        #expect(table == 1_098)
        let columns = InvoiceTableColumns.columnWidths(inTableOf: table)
        for (column, expected) in zip(columns, ideal) {
            #expect((column - expected).magnitude < 0.001)
        }
    }

    @Test func theColumnsFillTheTableEachWithinItsLeastAndGreatestWidth() {
        for table in stride(from: CGFloat(820), through: 3_000, by: 37) {
            let columns = InvoiceTableColumns.columnWidths(inTableOf: table)
            #expect((width(holding: columns) - table).magnitude < 0.001, "a table of \(table)")
            for index in columns.indices {
                #expect(columns[index] >= least[index] - 0.001, "column \(index) in a table of \(table)")
                #expect(columns[index] <= greatest[index] + 0.001, "column \(index) in a table of \(table)")
            }
        }
    }

    @Test func noColumnNarrowsAsTheTableWidens() {
        var previous = InvoiceTableColumns.columnWidths(inTableOf: 820)
        for table in stride(from: CGFloat(820), through: 3_000, by: 10) {
            let columns = InvoiceTableColumns.columnWidths(inTableOf: table)
            for index in columns.indices {
                #expect(columns[index] >= previous[index] - 0.001, "column \(index) in a table of \(table)")
            }
            previous = columns
        }
    }

    /// In a table of the page of a large window (1 320 points) every column is wider than its ideal width, and in one
    /// wider than all the greatest widths the others have theirs and Odběratel takes the rest.
    @Test func beyondItsIdealWidthTheColumnsShareTheRestAndOdberatelTakesWhatTheOthersCannot() {
        let large = InvoiceTableColumns.columnWidths(inTableOf: 1_320)
        for (column, expected) in zip(large, ideal) {
            #expect(column > expected)
        }

        let wide = InvoiceTableColumns.columnWidths(inTableOf: 3_000)
        for index in wide.indices where index != 1 {
            #expect((wide[index] - greatest[index]).magnitude < 0.001)
        }
        // 3 000 less the greatest widths of the other columns (1 070), the gaps (56) and the margins (40).
        #expect((wide[1] - 1_834).magnitude < 0.001)
    }
}
