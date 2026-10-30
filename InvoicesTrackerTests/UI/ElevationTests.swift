import AppKit
import SwiftUI
import Testing
@testable import InvoicesTracker

/// How a raised surface casts its shadow: the surface does, and what stands on it does not. A card, a search line, a
/// popover and the controls are drawn off-screen in a window of a dark or a light appearance and read pixel by pixel.
/// In a dark window the text is lighter than the surface it stands on, so a pixel of the surface that is darker than
/// the colour of the surface can only be the shadow of the text (or of whatever else stands on it). The drop shadow
/// under the edge of the surface has to be there all the same, and so has the ring along its edge.
@Suite
@MainActor
struct ElevationTests {
    // MARK: What the tests draw

    /// The room around the surface in a picture, in points, where its drop shadow falls.
    private let room: CGFloat = 30

    /// How many levels a pixel may be darker than the surface before it is a shadow. A surface is drawn flat, so the
    /// pixels of its interior differ by no more than the odd rounding.
    private let margin = 2

    /// The colour of a card in a window of `scheme`, as the bytes of a pixel drawn the way the tests draw everything.
    private func cardColour(in scheme: ColorScheme) throws -> [Int] {
        try OffscreenPicture.bytes(of: Palette.bgCard, in: scheme)
    }

    /// `view` standing on the background of the window with `room` points around it.
    private func onWindow(_ view: some View) -> some View {
        view
            .padding(room)
            .background(Palette.bgWindow)
    }

    /// A `Card` 220 by 80 points that holds `content` at 20 points from its top left, on the window.
    private func hostedCard(_ content: some View) -> some View {
        onWindow(
            Card(fillsHeight: true) {
                content
            }
            .frame(width: 220, height: 80))
    }

    /// A view of 220 by 80 points that holds `content` at 20 points from its top left and is given the look of a card
    /// with `card()`, on the window.
    private func viewWithCardLook(_ content: some View) -> some View {
        onWindow(
            content
                .padding(DesignMetrics.cardPadding)
                .frame(width: 220, height: 80, alignment: .topLeading)
                .card())
    }

    /// The frame of the card of `hostedCard(_:)` and of `viewWithCardLook(_:)` in the picture, in points from its top
    /// left.
    private var cardFrame: CGRect {
        CGRect(x: room, y: room, width: 220, height: 80)
    }

    /// The inside of the card in the picture, 6 points in from its edge: clear of the ring and of the corners, which
    /// are drawn over the window.
    private var cardInterior: CGRect {
        cardFrame.insetBy(dx: 6, dy: 6)
    }

    /// Whether the card of `picture` has the colour of a card where nothing stands on it, 6 points under its top edge.
    private func cardIsFlat(in picture: OffscreenPicture, as colour: [Int]) -> Bool {
        let bare = picture.bytes(at: CGPoint(x: cardFrame.midX, y: cardFrame.minY + 6))
        return zip(colour, bare).allSatisfy { abs($0 - $1) <= margin }
    }

    // MARK: A card

    @Test func theTextOfACardCastsNoShadowOfItsOwn() throws {
        let text = Text(verbatim: "Obsah karty")
            .font(Typography.body)
            .foregroundStyle(Palette.text)
        let picture = try OffscreenPicture(of: hostedCard(text), in: .dark)
        let colour = try cardColour(in: .dark)

        // The card has its colour, the text is drawn on it, lighter, and nothing in the card is darker than the card.
        #expect(cardIsFlat(in: picture, as: colour), "The card is not the colour of a card")
        #expect(picture.count(lighterThan: colour, in: cardInterior, by: margin) > 100, "The text is not drawn")
        #expect(
            picture.count(darkerThan: colour, in: cardInterior, by: margin) == 0,
            "The text casts a shadow on the card")
    }

    @Test func aViewGivenTheLookOfACardIsTheColourOfACardRightUpToWhatStandsOnIt() throws {
        // A block 60 by 20 points at 20 points from the top left of the card. Right under it and beside it the card has
        // its own colour, as it has anywhere else.
        let block = Rectangle()
            .fill(Palette.text)
            .frame(width: 60, height: 20)
        let picture = try OffscreenPicture(of: viewWithCardLook(block), in: .dark)
        let colour = try cardColour(in: .dark)
        let blockFrame = CGRect(x: cardFrame.minX + 20, y: cardFrame.minY + 20, width: 60, height: 20)

        let under = CGRect(x: blockFrame.minX, y: blockFrame.maxY, width: blockFrame.width, height: 4)
        let beside = CGRect(x: blockFrame.maxX, y: blockFrame.minY, width: 4, height: blockFrame.height + 4)
        #expect(cardIsFlat(in: picture, as: colour), "The card is not the colour of a card")
        #expect(picture.count(lighterThan: colour, in: blockFrame, by: margin) > 1_000, "The block is not drawn")
        #expect(picture.count(darkerThan: colour, in: under, by: margin) == 0, "A shadow under the block")
        #expect(picture.count(darkerThan: colour, in: beside, by: margin) == 0, "A shadow beside the block")
    }

    @Test func aCardStillCastsItsDropShadowUnderItsEdgeInALightAndInADarkWindow() throws {
        for scheme in [ColorScheme.light, .dark] {
            let picture = try OffscreenPicture(of: hostedCard(Color.clear), in: scheme)

            // The first row of pixels under the card is darker than the window further down, which no shadow reaches.
            let underEdge = picture.bytes(at: CGPoint(x: cardFrame.midX, y: cardFrame.maxY + 0.25))
            let faraway = picture.bytes(at: CGPoint(x: cardFrame.midX, y: cardFrame.maxY + 6))
            let deficit = zip(faraway, underEdge).map { $0 - $1 }.max() ?? 0
            #expect(deficit >= 4, "\(scheme): the window is \(faraway) and just under the card \(underEdge)")
        }
    }

    @Test func aCardStillHasItsHalfPointRingAlongItsEdgeInALightAndInADarkWindow() throws {
        for scheme in [ColorScheme.light, .dark] {
            let picture = try OffscreenPicture(of: hostedCard(Color.clear), in: scheme)
            let colour = try cardColour(in: scheme)

            // The last row of pixels of the card, which the ring is drawn on, differs from the card inside it.
            let onRing = picture.bytes(at: CGPoint(x: cardFrame.midX, y: cardFrame.maxY - 0.25))
            let difference = zip(onRing, colour).map { abs($0 - $1) }.max() ?? 0
            #expect(difference >= 8, "\(scheme): the card is \(colour) and its ring \(onRing)")
        }
    }

    // MARK: A search line

    @Test func theTextOfASearchLineCastsNoShadowOfItsOwn() throws {
        let line = SearchLine(text: "Hledání „cetus“: 2 z 12 faktur v roce 2026", otherYears: [], emptyText: "")
        let view = SearchLineView(line: line, showYear: { _ in }, clear: {})
            .frame(width: 700)
        let picture = try OffscreenPicture(of: onWindow(view), in: .dark)
        let colour = try cardColour(in: .dark)

        // The text stands at the leading side of the line, and the link that cancels the search at its trailing side.
        let text = CGRect(x: room + 16, y: room + 5, width: 360, height: 22)
        #expect(picture.count(lighterThan: colour, in: text, by: margin) > 100, "The text is not drawn")
        #expect(picture.count(darkerThan: colour, in: text, by: margin) == 0, "The text casts a shadow on the line")
    }

    // MARK: A popover

    @Test func theTextOfALevyPopoverCastsNoShadowOfItsOwn() throws {
        let data = LevyBarBuilder.balances(
            of: TaxEngine.compute(TaxEngineRegressionTests.sampleYear2026, asOf: civilDate("2026-10-17")),
            kind: .toDate(isOver: false), header: "Odvody z příjmů do 17.\u{00A0}10.", showsTotal: true)
        let width: CGFloat = 404
        let view = VStack(alignment: .leading, spacing: 0) {
            LevyBarView(data, showing: .social)
                .frame(width: width)
            Color.clear
                .frame(width: width, height: 220)
        }
        let picture = try OffscreenPicture(of: view.padding(20).background(Palette.bgWindow), in: .dark)
        let colour = try cardColour(in: .dark)

        // The popover hangs 8 points under the bar, centred on its part, and is 260 points wide. Its inside, 4 points
        // in from its edge down to 90 points under its top, holds the dot, the name and the first rows.
        let panelHeight = NSHostingView(rootView: LevyBarView(data).frame(width: width)).fittingSize.height
        let centres = LevyBarLayout.partCentres(
            widths: LevyBarLayout.partWidths(weights: data.parts.map(\.weight), width: width))
        let left = 20 + LevyBarLayout.popoverX(centredOn: centres[1], panelWidth: width)
        let top = 20 + panelHeight + LevyBarLayout.popoverGap
        let inside = CGRect(x: left + 4, y: top + 4, width: LevyBarLayout.popoverWidth - 8, height: 86)

        #expect(picture.count(lighterThan: colour, in: inside, by: margin) > 500, "The popover is not drawn")
        #expect(
            picture.count(darkerThan: colour, in: inside, by: margin) == 0, "The text casts a shadow on the popover")
    }

    // MARK: Controls

    /// The inside of the capsule of a control in `picture`, which has `room` points around it: 14 points in from the
    /// ends and 6 from the top and the bottom, where the capsule is the colour of a card around its label.
    private func capsuleInterior(of picture: OffscreenPicture) -> CGRect {
        CGRect(origin: .zero, size: picture.size).insetBy(dx: room + 14, dy: room + 6)
    }

    @Test func theLabelOfAButtonOnTheWindowCastsNoShadowOfItsOwn() throws {
        let button = Button("Zrušit hledání") {}
            .buttonStyle(CapsuleButtonStyle(.onWindow))
        let picture = try OffscreenPicture(of: onWindow(button), in: .dark)
        let colour = try cardColour(in: .dark)
        let inside = capsuleInterior(of: picture)

        #expect(picture.count(lighterThan: colour, in: inside, by: margin) > 100, "The label is not drawn")
        #expect(picture.count(darkerThan: colour, in: inside, by: margin) == 0, "The label casts a shadow")
    }

    @Test func theTitleOfAFilterChipThatIsNotChosenCastsNoShadowOfItsOwn() throws {
        let chip = FilterChip("Zaplacené", isSelected: false) {}
        let picture = try OffscreenPicture(of: onWindow(chip), in: .dark)
        let colour = try cardColour(in: .dark)
        let inside = capsuleInterior(of: picture)

        #expect(picture.count(lighterThan: colour, in: inside, by: margin) > 100, "The title is not drawn")
        #expect(picture.count(darkerThan: colour, in: inside, by: margin) == 0, "The title casts a shadow")
    }

    @Test func theTitleOfTheChosenSegmentCastsNoShadowOfItsOwn() throws {
        let control = SegmentedControl(
            "Které faktury", selection: .constant(1), segments: [(value: 1, title: "Vystavené")])
        let picture = try OffscreenPicture(of: onWindow(control), in: .dark)
        let colour = try cardColour(in: .dark)
        let inside = capsuleInterior(of: picture)

        #expect(picture.count(lighterThan: colour, in: inside, by: margin) > 100, "The title is not drawn")
        #expect(picture.count(darkerThan: colour, in: inside, by: margin) == 0, "The title casts a shadow")
    }
}
