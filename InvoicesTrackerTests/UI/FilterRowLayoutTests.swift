import AppKit
import SwiftUI
import Testing
@testable import InvoicesTracker

/// The filter row of Faktury, laid out in rooms of different widths: the segment of the scope (184 × 32 points), the
/// chips (534 × 28) and the search (170 to 280 × 32) in one line where they fit, with the search at the end of the line
/// and as wide as the room left allows, as the prototype's row of flexible boxes lays them out. Where they do not fit
/// the row wraps like words in a paragraph: the search goes to a line of its own when its 170 points are not left after
/// the chips, and the chips go to the line under the segment when they do not fit beside it. The search is at the end
/// of its line, flush with the right edge, in every case.
@MainActor
struct FilterRowLayoutTests {
    /// Where the parts of the row went in a room of `width` points, from the top left of the room.
    private struct Placed {
        var frames: [String: CGRect]
        var height: CGFloat

        /// The names of the parts line by line, from the top, each line from the left.
        var lines: [[String]] {
            let byLine = Dictionary(grouping: frames.keys) { frames[$0]?.midY.rounded() ?? 0 }
            return byLine.keys.sorted().map { line in
                (byLine[line] ?? []).sorted { (frames[$0]?.minX ?? 0) < (frames[$1]?.minX ?? 0) }
            }
        }
    }

    private func row() -> some View {
        FilterRowLayout(spacing: 12, lineSpacing: 10) {
            LayoutPart(name: "segment")
                .frame(width: 184, height: 32)
            LayoutPart(name: "chips")
                .frame(width: 534, height: 28)
            LayoutPart(name: "search")
                .frame(minWidth: 170, maxWidth: 280)
                .frame(height: 32)
        }
    }

    /// The row laid out in a room of `width` points.
    private func place(in width: CGFloat) -> Placed {
        let hosting = NSHostingView(rootView: row().frame(width: width, alignment: .topLeading))
        let height = hosting.fittingSize.height
        hosting.frame = CGRect(x: 0, y: 0, width: width, height: height)
        hosting.layoutSubtreeIfNeeded()
        return Placed(frames: framesOfParts(in: hosting), height: height)
    }

    @Test func allThreeStandInOneLineInALargeWindowWithTheSearchAtTheEnd() {
        let placed = place(in: 1_320)

        #expect(placed.lines == [["segment", "chips", "search"]])
        #expect(placed.frames["segment"] == CGRect(x: 0, y: 0, width: 184, height: 32))
        #expect(placed.frames["chips"] == CGRect(x: 196, y: 2, width: 534, height: 28))
        // The room left is more than the search needs: it takes its greatest width and keeps to the end of the line.
        #expect(placed.frames["search"] == CGRect(x: 1_040, y: 0, width: 280, height: 32))
        #expect(placed.height == 32)
    }

    @Test func theSearchTakesTheRoomThatIsLeftWhereItIsBetweenItsLeastAndItsGreatestWidth() {
        // The segment and the chips take 730 points and the gap 12: 234 are left of 976.
        let placed = place(in: 976)

        #expect(placed.lines == [["segment", "chips", "search"]])
        #expect(placed.frames["search"] == CGRect(x: 742, y: 0, width: 234, height: 32))
    }

    /// The page of the least window is 828 points wide, and so is the filter row, with the detail open too: the detail
    /// stands beside the table, under the row. 730 points for the segment and the chips leave 86 for the search, which
    /// needs 170, so it has a line of its own, at its greatest width and at the end of the line.
    @Test func theSearchHasALineOfItsOwnInTheLeastWindow() {
        let placed = place(in: 828)

        #expect(placed.lines == [["segment", "chips"], ["search"]])
        // The first line is as high as the segment, and the line of the search is under it with the gap between.
        #expect(placed.frames["search"] == CGRect(x: 548, y: 42, width: 280, height: 32))
        #expect(placed.height == 74)
    }

    @Test func theChipsGoUnderTheSegmentAndTheSearchStaysWithThemWhereItHasItsLeastWidthThere() {
        // At 720 points the segment and the chips do not fit one line (730): the chips are on the second line, and 720
        // less the chips and the gap leaves the search 174.
        let placed = place(in: 720)

        #expect(placed.lines == [["segment"], ["chips", "search"]])
        #expect(placed.frames["segment"] == CGRect(x: 0, y: 0, width: 184, height: 32))
        #expect(placed.frames["chips"] == CGRect(x: 0, y: 44, width: 534, height: 28))
        #expect(placed.frames["search"] == CGRect(x: 546, y: 42, width: 174, height: 32))
        #expect(placed.height == 74)
    }

    @Test func theSegmentTheChipsAndTheSearchAreThreeLinesWhereTheChipsLeaveTheSearchTooLittle() {
        // 534 points for the chips leave 154 of 700 for the search: it has a line of its own, at the end of it.
        let placed = place(in: 700)

        #expect(placed.lines == [["segment"], ["chips"], ["search"]])
        #expect(placed.frames["search"] == CGRect(x: 420, y: 80, width: 280, height: 32))
        #expect(placed.height == 112)
    }

    @Test func theSearchKeepsItsLeastWidthInARoomThatIsNarrowerThanThat() {
        // Nothing fits 150 points: every part has a line, and the search starts at the left edge rather than hang out
        // of the room on that side.
        let placed = place(in: 150)

        #expect(placed.lines == [["segment"], ["chips"], ["search"]])
        #expect(placed.frames["search"] == CGRect(x: 0, y: 80, width: 170, height: 32))
    }

    @Test func theRowAsksForTheWidthOfAllThreeInOneLineWhenItIsAskedForNoWidth() {
        // 184 + 12 + 534 + 12 + 280, as high as the segment and the search.
        let size = NSHostingView(rootView: row()).fittingSize

        #expect(size == CGSize(width: 1_022, height: 32))
    }
}
