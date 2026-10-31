import CoreGraphics
import Testing
@testable import InvoicesTracker

/// How wide the columns of the table of Odběratelé are in a table of a given width: Odběratel, Měna a DPH, Šablony and
/// Přijato Y, on the grid of the prototype, 12 points apart, with 16 points before the first and after the last. They
/// share the room in the proportions 2 : 1,3 : 0,8 : 1, as the fractions of a CSS grid do, and a column whose share is
/// less than its least width keeps that width while the others share the rest.
struct ClientTableColumnsTests {
    /// The least width of every column: the prototype's, with Měna a DPH raised from 130 to hold the widest chip of a
    /// currency with the longest VAT text (`ClientTableViewTests`).
    private let least: [CGFloat] = [150, 176, 76, 110]

    /// The share of each column of the room.
    private let fractions: [CGFloat] = [2, 1.3, 0.8, 1]

    /// The width of a table whose columns are `columns` wide: the columns, 3 gaps of 12 points and 2 margins of 16.
    private func width(holding columns: [CGFloat]) -> CGFloat {
        columns.reduce(0, +) + 3 * 12 + 2 * 16
    }

    private func isClose(_ found: [CGFloat], to expected: [CGFloat]) -> Bool {
        found.count == expected.count && zip(found, expected).allSatisfy { ($0 - $1).magnitude < 0.001 }
    }

    // MARK: The least width

    @Test func theColumnsAreTheGridOfThePrototypeWithMenaADphRaised() {
        #expect(ClientTableColumns.columns.map(\.minimum) == least)
        #expect(ClientTableColumns.columns.map(\.fraction) == fractions)
        #expect(ClientTableColumns.gap == 12)
        #expect(DataTableMetrics.margin == 16)
    }

    /// The least width of the table is the least widths of its columns with the room between and around them, 580
    /// points: 512 of columns, 36 of gaps and 32 of margins. The prototype's table is at least 540 points wide; Měna a
    /// DPH, raised by 46 points, makes this one wider.
    @Test func theLeastWidthOfTheTableIsTheLeastWidthsOfItsColumnsWithTheRoomBetweenAndAroundThem() {
        #expect(least.reduce(0, +) == 512)
        #expect(ClientTableColumns.minimumWidth == 580)
        #expect(isClose(ClientTableColumns.columnWidths(inTableOf: 580), to: least))
    }

    @Test func belowItsLeastWidthTheColumnsKeepTheirLeastWidths() {
        for table: CGFloat in [0, 300, 512, 540, 579] {
            #expect(isClose(ClientTableColumns.columnWidths(inTableOf: table), to: least), "a table of \(table)")
        }
    }

    // MARK: Sharing the room

    /// A table of 2 000 points: no column is held to its least width, so the four have 2 : 1,3 : 0,8 : 1 of the room
    /// that the gaps and the margins leave.
    @Test func theColumnsShareTheRoomInTheProportionsOfTheirFractions() throws {
        let unit = (2_000 - width(holding: [0, 0, 0, 0])) / 5.1

        let columns = ClientTableColumns.columnWidths(inTableOf: 2_000)

        let expected = fractions.map { $0 * unit }
        #expect(isClose(columns, to: expected), "\(columns) is not \(expected)")
    }

    /// A table of 700 points: Měna a DPH would have 161 points by its fraction, less than its least width, so it keeps
    /// 176 and the other three share what is left in the proportions of their fractions.
    @Test func aColumnWhoseShareIsUnderItsLeastWidthKeepsItAndTheOthersShareTheRest() throws {
        let columns = ClientTableColumns.columnWidths(inTableOf: 700)

        let unit = (700 - width(holding: [0, 0, 0, 0]) - 176) / 3.8
        let expected = [2 * unit, 176, 0.8 * unit, unit]
        #expect(isClose(columns, to: expected), "\(columns) is not \(expected)")
        #expect(columns[0] > least[0] && columns[2] > least[2] && columns[3] > least[3])
    }

    /// In the card of the least window with the detail closed, 828 points, no column is held.
    @Test func inTheCardOfTheLeastWindowEveryColumnHasItsShare() {
        let unit = (828 - width(holding: [0, 0, 0, 0])) / 5.1

        let columns = ClientTableColumns.columnWidths(inTableOf: 828)

        #expect(isClose(columns, to: fractions.map { $0 * unit }), "\(columns)")
    }

    @Test func theColumnsFillTheTableEachNotNarrowerThanItsLeastWidth() throws {
        for table in stride(from: CGFloat(580), through: 3_000, by: 37) {
            let columns = ClientTableColumns.columnWidths(inTableOf: table)
            try #require(columns.count == least.count, "a table of \(table): \(columns)")
            #expect((width(holding: columns) - table).magnitude < 0.001, "a table of \(table)")
            for index in columns.indices {
                #expect(columns[index] >= least[index] - 0.001, "column \(index) in a table of \(table)")
            }
        }
    }

    @Test func noColumnNarrowsAsTheTableWidens() throws {
        var previous = ClientTableColumns.columnWidths(inTableOf: 580)
        for table in stride(from: CGFloat(585), through: 3_000, by: 5) {
            let columns = ClientTableColumns.columnWidths(inTableOf: table)
            try #require(columns.count == previous.count && columns.count == least.count, "a table of \(table)")
            for index in columns.indices {
                #expect(columns[index] >= previous[index] - 0.001, "column \(index) in a table of \(table)")
            }
            previous = columns
        }
    }
}
