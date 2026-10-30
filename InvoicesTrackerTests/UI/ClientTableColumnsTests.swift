import CoreGraphics
import Testing
@testable import InvoicesTracker

/// How wide the columns of the table of Odběratelé are in a table of a given width: Odběratel, Měna a DPH, Jazyk
/// faktury, Rok Y and the chevron, 14 points apart, then 16 points and the 112 of the button Nová faktura, with 20
/// points before the first column and after the button. Odběratel, Měna a DPH and Rok Y share the room in the
/// proportion of 2 to 1,3 to 1,2, as the fractions of a grid do, none of them narrower than its least width; Jazyk
/// faktury and the chevron keep their widths.
struct ClientTableColumnsTests {
    private let least: [CGFloat] = [150, 176, 84, 166, 14]

    /// The width of a table whose columns are `columns` wide: the columns, 4 gaps of 14 points, the 16 points before
    /// the button and its 112, and 2 margins of 20.
    private func width(holding columns: [CGFloat]) -> CGFloat {
        columns.reduce(0, +) + 4 * 14 + 16 + 112 + 2 * 20
    }

    @Test func theLeastWidthOfTheTableIsTheLeastWidthsOfItsColumnsWithTheRoomBetweenAndAroundThem() {
        #expect(least.reduce(0, +) == 590)
        #expect(ClientTableColumns.minimumWidth == 814)
        #expect(ClientTableColumns.columnWidths(inTableOf: 814) == least)
    }

    @Test func belowItsLeastWidthTheColumnsKeepTheirLeastWidths() {
        for table: CGFloat in [0, 300, 700, 813] {
            #expect(ClientTableColumns.columnWidths(inTableOf: table) == least, "a table of \(table)")
        }
    }

    /// The card of the page of the least window with the sidebar as wide as it starts is 820 points wide, 6 more than
    /// the least width of the table: Odběratel gets them, and the other columns keep their least widths.
    @Test func inTheCardOfTheLeastWindowOdberatelHasTheLeastWidthAndTheRoomThatIsLeft() throws {
        let columns = ClientTableColumns.columnWidths(inTableOf: 820)

        let expected: [CGFloat] = [156, 176, 84, 166, 14]
        try #require(columns.count == expected.count, "\(columns)")
        for (column, wanted) in zip(columns, expected) {
            #expect((column - wanted).magnitude < 0.001, "\(columns) is not \(expected)")
        }
    }

    /// A table of 2 000 points: no column is held to its least width, so the three that grow have 2 : 1,3 : 1,2 of what
    /// is left when the other two have their 98 points.
    @Test func columnsThatGrowShareTheRoomInTheProportionOfTheirWeights() throws {
        let unit = (2_000 - width(holding: [0, 0, 0, 0, 0]) - 84 - 14) / 4.5

        let columns = ClientTableColumns.columnWidths(inTableOf: 2_000)

        let expected: [CGFloat] = [2 * unit, 1.3 * unit, 84, 1.2 * unit, 14]
        try #require(columns.count == expected.count, "\(columns)")
        for (column, wanted) in zip(columns, expected) {
            #expect((column - wanted).magnitude < 0.001, "\(columns) is not \(expected)")
        }
    }

    /// A table of 940 points: Rok Y would have 164,8 points by its weight, less than its least width, so it keeps 166
    /// and the other two share what is left in the proportion of their weights.
    @Test func aColumnWhoseShareIsUnderItsLeastWidthKeepsItAndTheOthersShareTheRest() throws {
        let columns = ClientTableColumns.columnWidths(inTableOf: 940)

        try #require(columns.count == 5, "\(columns)")
        let left = 940 - width(holding: [0, 0, 0, 0, 0]) - 84 - 14 - 166
        #expect(columns[3] == 166)
        #expect((columns[0] - left * 2 / 3.3).magnitude < 0.001)
        #expect((columns[1] - left * 1.3 / 3.3).magnitude < 0.001)
        #expect(columns[2] == 84 && columns[4] == 14)
    }

    @Test func theColumnsFillTheTableEachNotNarrowerThanItsLeastWidth() throws {
        for table in stride(from: CGFloat(814), through: 3_000, by: 37) {
            let columns = ClientTableColumns.columnWidths(inTableOf: table)
            try #require(columns.count == least.count, "a table of \(table): \(columns)")
            #expect((width(holding: columns) - table).magnitude < 0.001, "a table of \(table)")
            for index in columns.indices {
                #expect(columns[index] >= least[index] - 0.001, "column \(index) in a table of \(table)")
            }
        }
    }

    @Test func noColumnNarrowsAsTheTableWidens() throws {
        var previous = ClientTableColumns.columnWidths(inTableOf: 814)
        for table in stride(from: CGFloat(820), through: 3_000, by: 10) {
            let columns = ClientTableColumns.columnWidths(inTableOf: table)
            try #require(columns.count == previous.count && columns.count == least.count, "a table of \(table)")
            for index in columns.indices {
                #expect(columns[index] >= previous[index] - 0.001, "column \(index) in a table of \(table)")
            }
            previous = columns
        }
    }
}
