import AppKit
import SwiftUI
import Testing
@testable import InvoicesTracker

/// The filter row of Faktury, laid out in rooms of different widths: the scope picker (328 × 24 points), the chips
/// (514 × 28) and the search (220 to 300 × 32) in one line where they fit, with the search at the end of the line and
/// as wide as the room left allows. Where they do not fit the row wraps like words in a paragraph: the chips go to the
/// line under the scope, and the search goes on to the line of the chips if it has its 220 points there, otherwise to
/// a line of its own. The search is at the end of its line, flush with the right edge, in every case.
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
            LayoutPart(name: "scope")
                .frame(width: 328, height: 24)
            LayoutPart(name: "chips")
                .frame(width: 514, height: 28)
            LayoutPart(name: "search")
                .frame(minWidth: 220, maxWidth: 300)
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

        #expect(placed.lines == [["scope", "chips", "search"]])
        #expect(placed.frames["scope"] == CGRect(x: 0, y: 4, width: 328, height: 24))
        #expect(placed.frames["chips"] == CGRect(x: 340, y: 2, width: 514, height: 28))
        // The room left is more than the search needs: it takes its greatest width and keeps to the end of the line.
        #expect(placed.frames["search"] == CGRect(x: 1_020, y: 0, width: 300, height: 32))
        #expect(placed.height == 32)
    }

    @Test func theSearchTakesTheRoomThatIsLeftWhereItIsBetweenItsLeastAndItsGreatestWidth() {
        // The scope and the chips take 854 points and the gap 12: 234 are left.
        let placed = place(in: 1_100)

        #expect(placed.lines == [["scope", "chips", "search"]])
        #expect(placed.frames["search"] == CGRect(x: 866, y: 0, width: 234, height: 32))
    }

    @Test func theSearchGoesToALineOfItsOwnWhereTheScopeAndTheChipsLeaveItLessThanItsLeastWidth() {
        // 854 points for the scope and the chips, 12 for the gap: 134 are left of 1 000, and the search needs 220.
        let placed = place(in: 1_000)

        #expect(placed.lines == [["scope", "chips"], ["search"]])
        // The first line is as high as the chips, and the line of the search is under it with the gap between.
        #expect(placed.frames["search"] == CGRect(x: 700, y: 38, width: 300, height: 32))
        #expect(placed.height == 70)
    }

    @Test func theChipsGoUnderTheScopeAndTheSearchStaysWithThemWhereItHasItsLeastWidthThere() {
        // At 820 points the scope and the chips do not fit one line (854): the chips are on the second line, and 820
        // less the chips and the gap leaves the search 294.
        let placed = place(in: 820)

        #expect(placed.lines == [["scope"], ["chips", "search"]])
        #expect(placed.frames["scope"] == CGRect(x: 0, y: 0, width: 328, height: 24))
        #expect(placed.frames["chips"] == CGRect(x: 0, y: 36, width: 514, height: 28))
        #expect(placed.frames["search"] == CGRect(x: 526, y: 34, width: 294, height: 32))
        #expect(placed.height == 66)
    }

    @Test func theScopeTheChipsAndTheSearchAreThreeLinesAtTheLeastRoomWithTheDetailOpen() {
        // 514 points for the chips leave 6 of 520: the search has a line of its own, at the end of it.
        let placed = place(in: 520)

        #expect(placed.lines == [["scope"], ["chips"], ["search"]])
        #expect(placed.frames["search"] == CGRect(x: 220, y: 72, width: 300, height: 32))
        #expect(placed.height == 104)
    }

    @Test func theSearchKeepsItsLeastWidthInARoomThatIsNarrowerThanThat() {
        // Nothing fits 200 points: every part has a line, and the search starts at the left edge rather than hang out
        // of the room on that side.
        let placed = place(in: 200)

        #expect(placed.lines == [["scope"], ["chips"], ["search"]])
        #expect(placed.frames["search"] == CGRect(x: 0, y: 72, width: 220, height: 32))
    }

    @Test func theRowAsksForTheWidthOfAllThreeInOneLineWhenItIsAskedForNoWidth() {
        // 328 + 12 + 514 + 12 + 300, as high as the search.
        let size = NSHostingView(rootView: row()).fittingSize

        #expect(size == CGSize(width: 1_166, height: 32))
    }
}
