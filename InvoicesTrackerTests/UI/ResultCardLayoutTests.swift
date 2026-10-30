import AppKit
import SwiftUI
import Testing
@testable import InvoicesTracker

/// The result card laid out in rooms of different widths, and the row of figures under it. The card puts its two parts
/// side by side, in columns of one width, where the room inside its padding of 20 points has the 788 points that two
/// columns of the least width of 380 and the gap of 28 between them take, and one above the other, with 20 points
/// between, where it has less. The part under the hairline has the whole width in either case. The figures of a row sit
/// next to each other with the same gap, and go on to the next row where they do not fit.
@MainActor
struct ResultCardLayoutTests {
    /// Where the parts went in a room of some width, from the top left of the room, and the size the card took.
    private struct Placed {
        var frames: [String: CGRect]
        var size: CGSize
    }

    /// A part as wide as the room it is given and `height` points high.
    private func part(_ name: String, height: CGFloat) -> some View {
        LayoutPart(name: name)
            .frame(maxWidth: .infinity)
            .frame(height: height)
    }

    /// A result card whose parts are 100 (leading), 60 (trailing) and 40 (below) points high.
    private func resultCard() -> some View {
        ResultCard(label: "Výsledek") {
            part("left", height: 100)
        } trailing: {
            part("right", height: 60)
        } below: {
            part("below", height: 40)
        }
    }

    /// The same without a part under the hairline.
    private func resultCardWithoutBelow() -> some View {
        ResultCard(label: "Výsledek") {
            part("left", height: 100)
        } trailing: {
            part("right", height: 60)
        }
    }

    /// `view` laid out in a room of `width` points.
    private func place(_ view: some View, width: CGFloat) -> Placed {
        let hosting = NSHostingView(rootView: view.frame(width: width, alignment: .topLeading))
        let size = hosting.fittingSize
        hosting.frame = CGRect(origin: .zero, size: size)
        hosting.layoutSubtreeIfNeeded()
        return Placed(frames: framesOfParts(in: hosting), size: size)
    }

    /// The card laid out so that the room inside its padding is `innerWidth` points wide.
    private func place(_ card: some View, innerWidth: CGFloat) -> Placed {
        place(card, width: innerWidth + 2 * 20)
    }

    // MARK: Two columns, or one

    @Test func theResultCardPutsItsTwoPartsSideBySideWhenTwoColumnsOf380Fit() throws {
        let placed = place(resultCard(), innerWidth: 900)
        let left = try #require(placed.frames["left"])
        let right = try #require(placed.frames["right"])
        let below = try #require(placed.frames["below"])

        #expect(left.minX < right.minX, "laid out as \(placed.frames)")
        #expect(left.minY == right.minY, "laid out as \(placed.frames)")
        #expect(below.minY > max(left.maxY, right.maxY), "laid out as \(placed.frames)")
        #expect(below.width == 900, "laid out as \(placed.frames)")

        // Two columns of one width, (900 − 28) ÷ 2, in the padding of 20 points, with the gap of 28 between them.
        #expect(left == CGRect(x: 20, y: 20, width: 436, height: 100))
        #expect(right == CGRect(x: 484, y: 20, width: 436, height: 60))
        // The taller column, 20 points of room, the hairline of 1 point, 16 points, then the part under it.
        #expect(below == CGRect(x: 20, y: 157, width: 900, height: 40))
        #expect(placed.size == CGSize(width: 940, height: 217))
    }

    @Test func theResultCardStacksItsPartsWhenTheyDoNotFit() throws {
        let placed = place(resultCard(), innerWidth: 780)
        let left = try #require(placed.frames["left"])
        let right = try #require(placed.frames["right"])
        let below = try #require(placed.frames["below"])

        #expect(right.minY > left.maxY, "laid out as \(placed.frames)")
        #expect(left.minX == right.minX, "laid out as \(placed.frames)")
        #expect(below.width == 780, "laid out as \(placed.frames)")

        // Each part has the whole room, 20 points apart, and the part under the hairline follows the second.
        #expect(left == CGRect(x: 20, y: 20, width: 780, height: 100))
        #expect(right == CGRect(x: 20, y: 140, width: 780, height: 60))
        #expect(below == CGRect(x: 20, y: 237, width: 780, height: 40))
        #expect(placed.size == CGSize(width: 820, height: 297))
    }

    @Test func resultCardLayoutStandsSideBySideFrom788() {
        #expect(ResultCardLayout.standsSideBySide(innerWidth: 788))
        #expect(!ResultCardLayout.standsSideBySide(innerWidth: 787))
        #expect(ResultCardLayout.minimumColumnWidth == 380)
        #expect(ResultCardLayout.columnGap == 28)
        #expect(2 * ResultCardLayout.minimumColumnWidth + ResultCardLayout.columnGap == 788)
    }

    @Test func theCardSwitchesToTwoColumnsAtTheWidthTheLayoutNames() throws {
        let narrow = place(resultCard(), innerWidth: 787)
        let wide = place(resultCard(), innerWidth: 788)
        let stackedRight = try #require(narrow.frames["right"])
        let wideLeft = try #require(wide.frames["left"])
        let wideRight = try #require(wide.frames["right"])

        // One short of the width, the right part is under the left one.
        #expect(stackedRight.minX == 20, "laid out as \(narrow.frames)")
        #expect(stackedRight.minY == 140, "laid out as \(narrow.frames)")
        // At the width, two columns of the least width of 380 points.
        #expect(wideLeft == CGRect(x: 20, y: 20, width: 380, height: 100))
        #expect(wideRight == CGRect(x: 428, y: 20, width: 380, height: 60))
    }

    /// The same card with the gap between its rows set to `rowGap` points, with a part under the hairline unless
    /// `withBelow` is false.
    private func resultCard(rowGap: CGFloat, withBelow: Bool = true) -> some View {
        Group {
            if withBelow {
                ResultCard(label: "Výsledek", rowGap: rowGap) {
                    part("left", height: 100)
                } trailing: {
                    part("right", height: 60)
                } below: {
                    part("below", height: 40)
                }
            } else {
                ResultCard(label: "Výsledek", rowGap: rowGap) {
                    part("left", height: 100)
                } trailing: {
                    part("right", height: 60)
                }
            }
        }
    }

    @Test func theRowGapOfACardIs20PointsUnlessItIsGiven() {
        let byDefault = place(resultCard(), innerWidth: 780)
        let given = place(resultCard(rowGap: ResultCardLayout.rowGap), innerWidth: 780)

        #expect(ResultCardLayout.rowGap == 20)
        #expect(byDefault.frames == given.frames)
        #expect(byDefault.size == given.size)
    }

    @Test func aRowGapOf28PutsThe28PointsBetweenTheStackedPartsAndAboveTheHairline() throws {
        // Výpočet has the gap of 28 on both axes: the parts that do not fit side by side are 28 points apart, and so
        // are the parts and the hairline that follows them.
        let stacked = place(resultCard(rowGap: 28), innerWidth: 780)
        let left = try #require(stacked.frames["left"])
        let right = try #require(stacked.frames["right"])
        let below = try #require(stacked.frames["below"])

        #expect(left == CGRect(x: 20, y: 20, width: 780, height: 100))
        #expect(right == CGRect(x: 20, y: 148, width: 780, height: 60))
        // The second part ends at 208; 28 points of room, the hairline of 1 point, 16 points, then the part under it.
        #expect(below == CGRect(x: 20, y: 253, width: 780, height: 40))
        #expect(stacked.size == CGSize(width: 820, height: 313))

        // Side by side the gap between the columns is the 28 points it is anyway, and the taller column, the room and
        // the hairline follow.
        let beside = place(resultCard(rowGap: 28), innerWidth: 900)
        #expect(beside.frames["left"] == CGRect(x: 20, y: 20, width: 436, height: 100))
        #expect(beside.frames["right"] == CGRect(x: 484, y: 20, width: 436, height: 60))
        #expect(beside.frames["below"] == CGRect(x: 20, y: 165, width: 900, height: 40))
    }

    @Test func aRowGapOf28WithNothingUnderTheHairlineIsOnlyBetweenTheStackedParts() {
        let stacked = place(resultCard(rowGap: 28, withBelow: false), innerWidth: 780)
        let beside = place(resultCard(rowGap: 28, withBelow: false), innerWidth: 900)

        #expect(stacked.size == CGSize(width: 820, height: 20 + 100 + 28 + 60 + 20))
        #expect(stacked.frames["right"] == CGRect(x: 20, y: 148, width: 780, height: 60))
        // Side by side the card is as high as the taller column and its padding, whatever the gap between rows is.
        #expect(beside.size == CGSize(width: 940, height: 140))
    }

    @Test func aCardWithNothingUnderTheHairlineEndsWithItsColumns() throws {
        let placed = place(resultCardWithoutBelow(), innerWidth: 900)

        // No room for a hairline and for a part under it: the padding, the taller column, the padding.
        #expect(placed.frames["below"] == nil)
        #expect(placed.size == CGSize(width: 940, height: 140))
        let stacked = place(resultCardWithoutBelow(), innerWidth: 780)
        #expect(stacked.size == CGSize(width: 820, height: 20 + 100 + 20 + 60 + 20))
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

    /// The size the card answers when it is asked for it with `proposal`.
    private func answer(to proposal: ProposedViewSize) -> CGSize {
        var answered: CGSize?
        let view = Asking(proposal: proposal, report: { answered = $0 }) {
            resultCard()
        }
        _ = NSHostingView(rootView: view).fittingSize
        return answered ?? CGSize(width: -1, height: -1)
    }

    @Test func noWidthProposedAsksForBothColumnsSideBySide() {
        // Two columns of 380 points and the gap of 28 in the padding of 20 points, as high as the side by side card.
        #expect(answer(to: .unspecified) == CGSize(width: 828, height: 217))
    }

    @Test func aRequestForTheLeastRoomIsOneColumnOfTheLeastWidth() {
        let least = answer(to: .zero)

        // Not the height that the parts would have at a width of nothing: one column of 380 points in the padding.
        #expect(least == CGSize(width: 420, height: 297), "answered \(least)")
        #expect(least == answer(to: ProposedViewSize(width: 420, height: nil)))
    }

    // MARK: Figures next to each other

    /// A row of three figures of 120 × 40 points with `spacing` between them, laid out in a room of `width` points.
    private func placeFigures(spacing: CGFloat = 48, in width: CGFloat) -> Placed {
        let row = FigureRow(spacing: spacing) {
            LayoutPart(name: "first")
                .frame(width: 120, height: 40)
            LayoutPart(name: "second")
                .frame(width: 120, height: 40)
            LayoutPart(name: "third")
                .frame(width: 120, height: 40)
        }
        return place(row, width: width)
    }

    @Test func figureTilesSitNextToEachOtherWithTheGapAndWrap() throws {
        // Three figures of 120 points and the two gaps of 48 are 456 points: at 400 the third one goes on to the next
        // row, under the first, 12 points below it.
        let wrapped = placeFigures(in: 400)
        let first = try #require(wrapped.frames["first"])
        let second = try #require(wrapped.frames["second"])
        let third = try #require(wrapped.frames["third"])

        #expect(second.minX - first.maxX == 48, "laid out as \(wrapped.frames)")
        #expect(second.minY == first.minY, "laid out as \(wrapped.frames)")
        #expect(third.minX == first.minX, "laid out as \(wrapped.frames)")
        #expect(third.minY == first.maxY + 12, "laid out as \(wrapped.frames)")

        // At 1 000 points all three sit in one row.
        let one = placeFigures(in: 1_000)
        let row = try ["first", "second", "third"].map { try #require(one.frames[$0]) }
        #expect(Set(row.map(\.minY)) == [0], "laid out as \(one.frames)")
        #expect(row.map(\.minX) == [0, 168, 336], "laid out as \(one.frames)")
        #expect(one.size.height == 40)
    }

    @Test func figuresStayInOneRowAtThePointWhereTheyJustFit() throws {
        let fits = placeFigures(in: 456)
        let tooNarrow = placeFigures(in: 455)
        // Two rows of 40 points and the gap of 12 between them.
        let twoRows: CGFloat = 40 + 12 + 40

        #expect(fits.size.height == 40, "laid out as \(fits.frames)")
        #expect(tooNarrow.size.height == twoRows, "laid out as \(tooNarrow.frames)")
        #expect(try #require(fits.frames["third"]).minX == 336)
    }

    @Test func theGapBetweenFiguresIsTheOneGiven() throws {
        let narrower = placeFigures(spacing: 40, in: 1_000)

        #expect(try #require(narrower.frames["second"]).minX == 160)
        #expect(try #require(narrower.frames["third"]).minX == 320)
    }

    @Test func figuresOfDifferentHeightsLineUpAtTheirTop() {
        // A tile with a note and one without: they start on one line, and the row is as high as the taller.
        let row = FigureRow {
            LayoutPart(name: "short")
                .frame(width: 120, height: 40)
            LayoutPart(name: "tall")
                .frame(width: 120, height: 60)
        }
        let placed = place(row, width: 1_000)

        #expect(placed.frames["short"] == CGRect(x: 0, y: 0, width: 120, height: 40), "laid out as \(placed.frames)")
        #expect(placed.frames["tall"] == CGRect(x: 168, y: 0, width: 120, height: 60), "laid out as \(placed.frames)")
        #expect(placed.size.height == 60)
    }

    /// A figure that takes the width it is given, as text does, and wants 500 points where it is given none.
    private func flexibleFigure(_ name: String) -> some View {
        LayoutPart(name: name)
            .frame(minWidth: 0, idealWidth: 500, maxWidth: .infinity)
            .frame(height: 40)
    }

    @Test func aRowHoldsItsFiguresToTheGreatestWidthItIsGiven() {
        let held = FigureRow(spacing: 48, maxTileWidth: 200) {
            flexibleFigure("first")
            flexibleFigure("second")
        }
        let free = FigureRow(spacing: 48) {
            flexibleFigure("first")
            flexibleFigure("second")
        }
        let beside = place(held, width: 1_000)
        let wrapped = place(free, width: 1_000)

        // Held to 200 points each they stand side by side, with the gap of 48 between them.
        #expect(beside.frames["first"] == CGRect(x: 0, y: 0, width: 200, height: 40), "laid out as \(beside.frames)")
        #expect(beside.frames["second"] == CGRect(x: 248, y: 0, width: 200, height: 40), "laid out as \(beside.frames)")
        // Not held they want 500 points each: two of them and the gap are 1 048, which a room of 1 000 cannot hold.
        #expect(wrapped.frames["second"]?.minY == 52, "laid out as \(wrapped.frames)")
    }
}
