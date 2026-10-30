import AppKit
import SwiftUI
import Testing
@testable import InvoicesTracker

/// The two stacks of the breakdown, laid out in rooms of different widths: side by side, of one width and aligned at
/// the top, where the room has the 856 points that two columns of the least width of 420 and the gap of 16 between
/// them take, and in one column, the left stack above the right one, where it has less. Each stack runs on by itself,
/// so that the shorter one ends earlier and leaves no holes beside the other. Asked for no width the stack asks for
/// both columns side by side, and asked for the least room it asks for one column of the least width.
@MainActor
struct TwoColumnStackTests {
    /// Where the cards went in a room of some width, from the top left of the room, and the size the stack took.
    private struct Placed {
        var frames: [String: CGRect]
        var size: CGSize
    }

    /// A card as wide as the column it is in and `height` points high.
    private func card(_ name: String, height: CGFloat) -> some View {
        LayoutPart(name: name)
            .frame(maxWidth: .infinity)
            .frame(height: height)
    }

    /// The stack of the cards with the heights `left` and `right`, named "left 1", "left 2", … and "right 1", …, in the
    /// least width and with the gap that the stack has by default.
    private func stack(left: [CGFloat], right: [CGFloat]) -> some View {
        TwoColumnStack {
            ForEach(left.indices, id: \.self) { index in
                card("left \(index + 1)", height: left[index])
            }
        } right: {
            ForEach(right.indices, id: \.self) { index in
                card("right \(index + 1)", height: right[index])
            }
        }
    }

    /// The stack laid out in a room of `width` points. Two cards of 100 points on each side unless told otherwise.
    private func place(left: [CGFloat] = [100, 100], right: [CGFloat] = [100, 100], in width: CGFloat) -> Placed {
        let hosting = NSHostingView(
            rootView: stack(left: left, right: right).frame(width: width, alignment: .topLeading))
        let size = hosting.fittingSize
        hosting.frame = CGRect(origin: .zero, size: size)
        hosting.layoutSubtreeIfNeeded()
        return Placed(frames: framesOfParts(in: hosting), size: size)
    }

    @Test func atTheThresholdTheColumnsStandSideBySide() throws {
        // Two columns of 420 points and the gap of 16 are 856 points.
        let placed = place(in: 856)
        let left = try #require(placed.frames["left 1"])
        let right = try #require(placed.frames["right 1"])

        #expect(right.minX >= left.maxX, "laid out as \(placed.frames)")
        #expect(right.minY == left.minY, "laid out as \(placed.frames)")
        // Each side is a column of its own, 420 points wide, and the gap of 16 runs between the cards of a side too.
        #expect(placed.frames["left 1"] == CGRect(x: 0, y: 0, width: 420, height: 100))
        #expect(placed.frames["left 2"] == CGRect(x: 0, y: 116, width: 420, height: 100))
        #expect(placed.frames["right 1"] == CGRect(x: 436, y: 0, width: 420, height: 100))
        #expect(placed.frames["right 2"] == CGRect(x: 436, y: 116, width: 420, height: 100))
        #expect(placed.size == CGSize(width: 856, height: 216))
    }

    @Test func belowTheThresholdTheColumnsStack() throws {
        let placed = place(in: 855)
        let order = ["left 1", "left 2", "right 1", "right 2"]
        let frames = try order.map { name in try #require(placed.frames[name]) }

        // One column, the left stack first: the same left edge, and each card under the one before.
        #expect(Set(frames.map(\.minX)) == [0], "laid out as \(placed.frames)")
        #expect(frames.map(\.minY) == frames.map(\.minY).sorted(), "laid out as \(placed.frames)")
        #expect(placed.frames["left 1"] == CGRect(x: 0, y: 0, width: 855, height: 100))
        #expect(placed.frames["left 2"] == CGRect(x: 0, y: 116, width: 855, height: 100))
        #expect(placed.frames["right 1"] == CGRect(x: 0, y: 232, width: 855, height: 100))
        #expect(placed.frames["right 2"] == CGRect(x: 0, y: 348, width: 855, height: 100))
        #expect(placed.size == CGSize(width: 855, height: 448))
    }

    @Test func theSidesKeepTheirOwnHeights() throws {
        // A short right side beside a tall left one: it ends higher, and its second card is under its first, not level
        // with the second card of the left side, which would leave a hole between them.
        let placed = place(left: [100, 100, 100], right: [40, 40], in: 856)
        let lastOfLeft = try #require(placed.frames["left 3"])
        let lastOfRight = try #require(placed.frames["right 2"])

        #expect(lastOfRight.maxY < lastOfLeft.maxY, "laid out as \(placed.frames)")
        #expect(placed.frames["right 1"] == CGRect(x: 436, y: 0, width: 420, height: 40))
        #expect(placed.frames["right 2"] == CGRect(x: 436, y: 56, width: 420, height: 40))
        #expect(placed.frames["left 2"] == CGRect(x: 0, y: 116, width: 420, height: 100))
        #expect(placed.size == CGSize(width: 856, height: 332))
    }

    @Test func theStackIsAsHighAsItsTallerSideWhicheverItIs() {
        // The right side is the taller one: its three cards and the two gaps, 332 points, and the left one ends early.
        let placed = place(left: [100], right: [100, 100, 100], in: 856)

        #expect(placed.size == CGSize(width: 856, height: 332))
        #expect(placed.frames["left 1"] == CGRect(x: 0, y: 0, width: 420, height: 100))
    }

    // MARK: The room asked for

    /// Asks its one subview for its size, for `proposal` (as a parent layout does), and tells the answer to `report`.
    private struct Asking: Layout {
        let proposal: ProposedViewSize
        let report: @MainActor (CGSize) -> Void

        func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
            guard let subview = subviews.first else { return .zero }
            let answer = subview.sizeThatFits(self.proposal)
            MainActor.assumeIsolated { report(answer) }
            return answer
        }

        func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
            subviews.first?.place(at: bounds.origin, anchor: .topLeading, proposal: ProposedViewSize(bounds.size))
        }
    }

    /// The size the stack answers when it is asked for it with `proposal`.
    private func answer(to proposal: ProposedViewSize) -> CGSize {
        var answered: CGSize?
        let view = Asking(proposal: proposal, report: { answered = $0 }) {
            stack(left: [100, 100], right: [100, 100])
        }
        _ = NSHostingView(rootView: view).fittingSize
        return answered ?? CGSize(width: -1, height: -1)
    }

    @Test func noWidthProposedAsksForBothColumnsSideBySide() {
        // Two columns of 420 points and the gap of 16, as high as the two cards of a side and the gap between them.
        #expect(answer(to: .unspecified) == CGSize(width: 856, height: 216))
    }

    @Test func aRequestForTheLeastRoomIsOneColumnOfTheLeastWidth() {
        let least = answer(to: .zero)

        // Not the height that the cards would have at a width of nothing: four cards and the three gaps, in 420 points.
        #expect(least == CGSize(width: 420, height: 448), "answered \(least)")
        #expect(least == answer(to: ProposedViewSize(width: 420, height: nil)))
    }
}
