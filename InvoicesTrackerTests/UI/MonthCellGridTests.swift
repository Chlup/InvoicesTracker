import AppKit
import SwiftUI
import Testing
@testable import InvoicesTracker

/// The twelve months of a client, laid out in rooms of different widths: in as many equal columns as hold cells of at
/// least 64 points with 6 between each two of them and divide the twelve cells, so that every row is full: 12 columns
/// from 834 points (all twelve in a row), 6 from 414 (January to June over July to December), 4 from 274, 3 from 204,
/// 2 from 134 and 1 below that. The rows are of one height, that of the tallest cell, and the gap between rows is 6
/// points as well. Asked for no width the grid asks for the twelve cells in a row.
@MainActor
struct MonthCellGridTests {
    /// Where the cells went in a room of some width, from the top left of the room, and the size the grid took.
    private struct Placed {
        var frames: [String: CGRect]
        var size: CGSize

        /// The cell `number`, 1 to 12.
        func cell(_ number: Int) -> CGRect {
            frames["cell \(number)"] ?? .null
        }

        /// How many columns the cells stand in: the left edges they have.
        var columns: Int {
            Set(frames.values.map { $0.minX.rounded() }).count
        }

        /// How many rows the cells stand in: the top edges they have.
        var rows: Int {
            Set(frames.values.map { $0.minY.rounded() }).count
        }
    }

    /// A cell as wide as its column and as high as its row, but at least `height` points, as a month's cell is.
    private func cell(_ number: Int, height: CGFloat) -> some View {
        LayoutPart(name: "cell \(number)")
            .frame(maxWidth: .infinity, minHeight: height, maxHeight: .infinity)
    }

    /// The grid of twelve cells named "cell 1" to "cell 12", the heights of which are `heights` (52 points each unless
    /// told otherwise).
    private func grid(heights: [CGFloat]) -> some View {
        MonthCellGrid {
            ForEach(heights.indices, id: \.self) { index in
                cell(index + 1, height: heights[index])
            }
        }
    }

    /// The grid laid out in a room of `width` points.
    private func place(heights: [CGFloat] = Array(repeating: 52, count: 12), in width: CGFloat) -> Placed {
        let hosting = NSHostingView(rootView: grid(heights: heights).frame(width: width, alignment: .topLeading))
        let size = hosting.fittingSize
        hosting.frame = CGRect(origin: .zero, size: size)
        hosting.layoutSubtreeIfNeeded()
        return Placed(frames: framesOfParts(in: hosting), size: size)
    }

    /// Records an issue unless `actual` is `expected` to within a point in each of its numbers: AppKit rounds the
    /// frames of the views a layout places to whole points, and the columns of a width that does not divide evenly are
    /// not.
    private func expectFrame(
        _ actual: CGRect, _ expected: CGRect, _ comment: @autoclosure () -> String = "",
        sourceLocation: SourceLocation = #_sourceLocation
    ) {
        let differences = [
            actual.minX - expected.minX, actual.minY - expected.minY, actual.width - expected.width,
            actual.height - expected.height,
        ]
        #expect(
            differences.allSatisfy { $0.magnitude <= 1 }, "\(actual) is not \(expected) \(comment())",
            sourceLocation: sourceLocation)
    }

    // MARK: The columns

    @Test func from834PointsTheTwelveCellsStandInOneRowOfTwelveColumns() {
        // Twelve cells of 64 points and eleven gaps of 6 are 834 points.
        let placed = place(in: 834)

        #expect(placed.columns == 12, "laid out as \(placed.frames)")
        #expect(placed.rows == 1, "laid out as \(placed.frames)")
        for number in 1...12 {
            #expect(placed.cell(number) == CGRect(x: CGFloat(number - 1) * 70, y: 0, width: 64, height: 52))
        }
        #expect(placed.size == CGSize(width: 834, height: 52))
    }

    @Test func aPointLessThanThatTheMonthsStandInTwoFullRowsOfSixNotElevenAndOne() {
        // 833 points hold eleven cells of 64 and ten gaps of 6, but eleven is no divisor of twelve: the line takes
        // six, so that the second row is full as well, and the cells grow to fill the line.
        let placed = place(in: 833)
        let width = (833 - 5 * 6) / 6 as CGFloat

        #expect(placed.columns == 6, "laid out as \(placed.frames)")
        #expect(placed.rows == 2, "laid out as \(placed.frames)")
        #expect((placed.cell(6).maxX - 833).magnitude <= 1, "laid out as \(placed.frames)")
        for number in 1...6 {
            let x = CGFloat(number - 1) * (width + 6)
            expectFrame(placed.cell(number), CGRect(x: x, y: 0, width: width, height: 52), "(cell \(number))")
            expectFrame(placed.cell(number + 6), CGRect(x: x, y: 58, width: width, height: 52), "(cell \(number + 6))")
        }
        #expect(placed.size == CGSize(width: 833, height: 110))
    }

    @Test func at420PointsTheCellsStandInTwoRowsOfSix() {
        // 420 + 6 = 426 is six times 70 and a little over.
        let placed = place(in: 420)
        let width = (420 - 5 * 6) / 6 as CGFloat

        #expect(placed.columns == 6, "laid out as \(placed.frames)")
        #expect(placed.rows == 2, "laid out as \(placed.frames)")
        expectFrame(placed.cell(1), CGRect(x: 0, y: 0, width: width, height: 52))
        expectFrame(placed.cell(6), CGRect(x: 5 * (width + 6), y: 0, width: width, height: 52))
        expectFrame(placed.cell(7), CGRect(x: 0, y: 58, width: width, height: 52))
        expectFrame(placed.cell(12), CGRect(x: 5 * (width + 6), y: 58, width: width, height: 52))
        #expect(placed.size == CGSize(width: 420, height: 110))
    }

    @Test func theCellsStandInFullRowsOfEqualCellsWhereverTheColumnsChange() {
        // 12, 6, 4, 3, 2 and 1 columns, each in a width that is not the least that holds it, and 12 in the least.
        let columnsByWidth: [(width: CGFloat, columns: Int)] = [
            (834, 12), (833, 6), (776, 6), (420, 6), (349, 4), (209, 3), (139, 2), (69, 1),
        ]
        for (width, columns) in columnsByWidth {
            let placed = place(in: width)
            let rows = 12 / columns
            let cellWidth = (width - 6 * CGFloat(columns - 1)) / CGFloat(columns)

            #expect(placed.columns == columns, "\(placed.columns) columns in \(width) points")
            #expect(placed.rows == rows, "\(placed.rows) rows in \(width) points")
            for number in 1...12 {
                let row = CGFloat((number - 1) / columns)
                let column = CGFloat((number - 1) % columns)
                expectFrame(
                    placed.cell(number),
                    CGRect(x: column * (cellWidth + 6), y: row * 58, width: cellWidth, height: 52),
                    "(cell \(number) in \(width) points)")
            }
            let height = CGFloat(rows) * 52 + CGFloat(rows - 1) * 6
            #expect(placed.size == CGSize(width: width, height: height), "in \(width) points")
        }
    }

    @Test func theCellsAreOfOneWidthAndFillTheLineWhateverTheWidth() {
        // The least window shows the months of a client in 776 points, and those of the clients in the group of the
        // others, which is set in by 22, in 754. A large window has more than the twelve cells need.
        for width in [CGFloat(1_228), 1_000, 834, 776, 754, 600, 420, 349, 300, 209, 140, 139, 70, 64] {
            let placed = place(in: width)
            let widths = (1...12).map { placed.cell($0).width }

            // Of one width, to the whole points that AppKit rounds the frames to.
            #expect((widths.max() ?? 0) - (widths.min() ?? 0) <= 1, "the cells have the widths \(widths) in \(width)")
            #expect(placed.cell(1).minX == 0, "in \(width) points")
            // The cells of the first row reach the right edge of the room.
            #expect(((placed.frames.values.map(\.maxX).max() ?? 0) - width).magnitude <= 1, "in \(width) points")
        }
    }

    @Test func theColumnsAreTheLargestDivisorOfTwelveThatHoldsCellsOf64PointsWithGapsOf6() {
        // N columns of cells of 64 points with the N - 1 gaps of 6 between them need 70 N - 6 points. The columns are
        // the largest of 12, 6, 4, 3, 2 and 1 that needs no more than the width: 12 from 834, 6 from 414, 4 from 274,
        // 3 from 204, 2 from 134. The least window shows the months of a client in 776 points, which hold eleven cells
        // of 64 but are six columns, and those of the group of the others in 754.
        let columnsByWidth: [(width: CGFloat, columns: Int)] = [
            (1_600, 12), (835, 12), (834, 12), (833, 6), (776, 6), (754, 6), (694, 6), (420, 6), (414, 6), (413, 4),
            (349, 4), (274, 4), (273, 3), (209, 3), (204, 3), (203, 2), (139, 2), (134, 2), (133, 1), (69, 1), (64, 1),
            (40, 1),
        ]
        for (width, columns) in columnsByWidth {
            #expect(place(in: width).columns == columns, "in \(width) points")
        }
    }

    @Test func everyRowIsFullWhateverTheWidth() {
        // In any width from 40 to 1 300 points the columns divide twelve and every row has all of them.
        for width in stride(from: CGFloat(40), through: 1_300, by: 9) {
            let placed = place(in: width)
            let perRow = Dictionary(grouping: placed.frames.values) { $0.minY.rounded() }.values.map(\.count)

            #expect(12 % placed.columns == 0, "\(placed.columns) columns in \(width) points")
            #expect(perRow.allSatisfy { $0 == placed.columns }, "rows of \(perRow) cells in \(width) points")
        }
    }

    @Test func aRoomTooNarrowForTwoCellsHasOneColumnOfTwelveRows() {
        let placed = place(in: 100)

        #expect(placed.columns == 1, "laid out as \(placed.frames)")
        #expect(placed.rows == 12, "laid out as \(placed.frames)")
        #expect(placed.cell(12) == CGRect(x: 0, y: 11 * 58, width: 100, height: 52))
        #expect(placed.size == CGSize(width: 100, height: 12 * 52 + 11 * 6))
    }

    // MARK: The rows

    @Test func everyRowIsAsHighAsTheTallestCellAndTheCellsFillIt() {
        // The tall cell is in the first row alone of the two. The cells of the second row are as high as it too.
        var heights = [CGFloat](repeating: 52, count: 12)
        heights[2] = 63
        let placed = place(heights: heights, in: 420)

        #expect(placed.rows == 2, "laid out as \(placed.frames)")
        for number in 1...12 {
            #expect(placed.cell(number).height == 63, "cell \(number) of \(placed.frames)")
        }
        #expect(placed.cell(7).minY == 69, "laid out as \(placed.frames)")
        #expect(placed.size == CGSize(width: 420, height: 63 + 6 + 63))
    }

    @Test func aTallCellInTheLastRowMakesTheRowsAboveItAsHigh() {
        var heights = [CGFloat](repeating: 52, count: 12)
        heights[11] = 80
        let placed = place(heights: heights, in: 420)

        #expect(placed.cell(1).height == 80, "laid out as \(placed.frames)")
        #expect(placed.cell(7).minY == 86, "laid out as \(placed.frames)")
        #expect(placed.size == CGSize(width: 420, height: 80 + 6 + 80))
    }

    // MARK: The room asked for

    @Test func noWidthProposedAsksForTheTwelveCellsInARow() {
        let size = NSHostingView(rootView: grid(heights: Array(repeating: 52, count: 12))).fittingSize

        #expect(size == CGSize(width: 834, height: 52))
    }
}
