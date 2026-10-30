import AppKit
import SwiftUI
import Testing
@testable import InvoicesTracker

/// The layout of the client chips of the editor: side by side where they fit, and on the next row where they do not,
/// with the gap between rows the one between the boxes of a row unless it is given. The boxes of a row line up at the
/// middle, or at the top where the layout is told so, and a box can be held to a greatest width.
@MainActor
struct FlowLayoutTests {
    /// The size `FlowLayout` takes for `count` boxes of 100 × 20 points with 6 points between them, in `width` points.
    private func size(of count: Int, in width: CGFloat) -> CGSize {
        size(of: count, in: width, layout: FlowLayout(spacing: 6))
    }

    /// The size `layout` takes for `count` boxes of 100 × 20 points, in `width` points.
    private func size(of count: Int, in width: CGFloat, layout: FlowLayout) -> CGSize {
        let view = layout {
            ForEach(0..<count, id: \.self) { _ in
                Color.clear
                    .frame(width: 100, height: 20)
            }
        }
        .frame(width: width, alignment: .leading)
        return NSHostingView(rootView: view).fittingSize
    }

    @Test func boxesThatFitAreOnOneRow() {
        let size = size(of: 3, in: 400)

        #expect(size.height == 20)
    }

    @Test func boxesThatDoNotFitGoOnToTheNextRow() {
        // Two boxes and the gap are 206 points: a third one does not fit 250.
        #expect(size(of: 3, in: 250).height == 46)
        // 100 points each, one row of two and one of one, or one on each row at 150.
        #expect(size(of: 3, in: 150).height == 72)
        #expect(size(of: 5, in: 330).height == 46)
    }

    @Test func aBoxThatIsWiderThanTheWidthStillHasARowOfItsOwn() {
        #expect(size(of: 2, in: 60).height == 46)
    }

    @Test func noBoxesTakeNoRoom() {
        #expect(size(of: 0, in: 300).height == 0)
    }

    @Test func theGapBetweenRowsIsTheGapBetweenBoxesUnlessItIsGiven() {
        // Two boxes and the gap of 16 are 216 points: a third one goes on to a row of its own in 250. Two rows of 20
        // points and the gap between them: 56 where the gap is 16, 46 where it is 6 and 52 where it is 12.
        #expect(size(of: 3, in: 250, layout: FlowLayout(spacing: 16)).height == 56)
        #expect(size(of: 3, in: 250, layout: FlowLayout(spacing: 16, lineSpacing: 6)).height == 46)
        #expect(size(of: 3, in: 250, layout: FlowLayout(spacing: 6, lineSpacing: 12)).height == 52)
        // The gap between boxes is as given whichever the gap between rows is: two boxes and the gap fit 216 points.
        #expect(size(of: 2, in: 216, layout: FlowLayout(spacing: 16, lineSpacing: 6)).height == 20)
        #expect(size(of: 2, in: 215, layout: FlowLayout(spacing: 16, lineSpacing: 6)).height == 46)
    }

    // MARK: Boxes of different heights

    /// Where `layout` puts a box of 100 × 20 points and one of 100 × 40, from the top left of a room of 400 points.
    private func place(_ layout: FlowLayout) -> [String: CGRect] {
        let view = layout {
            LayoutPart(name: "short")
                .frame(width: 100, height: 20)
            LayoutPart(name: "tall")
                .frame(width: 100, height: 40)
        }
        .frame(width: 400, alignment: .topLeading)
        let hosting = NSHostingView(rootView: view)
        hosting.frame = CGRect(origin: .zero, size: hosting.fittingSize)
        hosting.layoutSubtreeIfNeeded()
        return framesOfParts(in: hosting)
    }

    @Test func boxesOfOneRowAreCentredUnlessTheLayoutIsToldOtherwise() {
        let centred = place(FlowLayout(spacing: 6))

        #expect(centred["short"] == CGRect(x: 0, y: 10, width: 100, height: 20), "laid out as \(centred)")
        #expect(centred["tall"] == CGRect(x: 106, y: 0, width: 100, height: 40), "laid out as \(centred)")
        #expect(place(FlowLayout(spacing: 6, alignment: .center)) == centred)
    }

    @Test func boxesOfOneRowCanLineUpAtTheTopOrAtTheBottom() {
        let top = place(FlowLayout(spacing: 6, alignment: .top))
        let bottom = place(FlowLayout(spacing: 6, alignment: .bottom))

        #expect(top["short"] == CGRect(x: 0, y: 0, width: 100, height: 20), "laid out as \(top)")
        #expect(top["tall"] == CGRect(x: 106, y: 0, width: 100, height: 40), "laid out as \(top)")
        #expect(bottom["short"] == CGRect(x: 0, y: 20, width: 100, height: 20), "laid out as \(bottom)")
        #expect(bottom["tall"] == CGRect(x: 106, y: 0, width: 100, height: 40), "laid out as \(bottom)")
    }

    // MARK: A greatest width of a box

    /// Where `layout` puts two boxes that ask for 500 points when they are asked for no width, and take the width they
    /// are given when they are asked for one, as text that breaks its lines does, in a room of `width` points.
    private func placeFlexibleBoxes(in layout: FlowLayout, width: CGFloat) -> [String: CGRect] {
        let view = layout {
            LayoutPart(name: "first")
                .frame(minWidth: 0, idealWidth: 500, maxWidth: .infinity)
                .frame(height: 20)
            LayoutPart(name: "second")
                .frame(minWidth: 0, idealWidth: 500, maxWidth: .infinity)
                .frame(height: 20)
        }
        .frame(width: width, alignment: .topLeading)
        let hosting = NSHostingView(rootView: view)
        hosting.frame = CGRect(origin: .zero, size: hosting.fittingSize)
        hosting.layoutSubtreeIfNeeded()
        return framesOfParts(in: hosting)
    }

    @Test func aBoxIsAskedForTheWidthItWantsUnlessTheLayoutHoldsItToAGreatestOne() {
        // Two boxes of 500 points and the gap of 6 are 1 006 points: they do not fit 800, and each has a row.
        let free = placeFlexibleBoxes(in: FlowLayout(spacing: 6), width: 800)
        #expect(free["first"] == CGRect(x: 0, y: 0, width: 500, height: 20), "laid out as \(free)")
        #expect(free["second"] == CGRect(x: 0, y: 26, width: 500, height: 20), "laid out as \(free)")

        // Held to 300 points each they do fit, side by side with the gap between them ...
        let held = FlowLayout(spacing: 6, maximumSubviewWidth: 300)
        let beside = placeFlexibleBoxes(in: held, width: 800)
        #expect(beside["first"] == CGRect(x: 0, y: 0, width: 300, height: 20), "laid out as \(beside)")
        #expect(beside["second"] == CGRect(x: 306, y: 0, width: 300, height: 20), "laid out as \(beside)")

        // ... and are no wider than that, however much room there is.
        #expect(placeFlexibleBoxes(in: held, width: 2_000) == beside)
    }

    @Test func aBoxIsNeverAskedForMoreThanTheRoomThereIs() {
        // The greatest width is 300 and the room 250: a box has the room, and the next one goes to the next row.
        let held = FlowLayout(spacing: 6, maximumSubviewWidth: 300)
        let narrow = placeFlexibleBoxes(in: held, width: 250)

        #expect(narrow["first"] == CGRect(x: 0, y: 0, width: 250, height: 20), "laid out as \(narrow)")
        #expect(narrow["second"] == CGRect(x: 0, y: 26, width: 250, height: 20), "laid out as \(narrow)")
    }
}
