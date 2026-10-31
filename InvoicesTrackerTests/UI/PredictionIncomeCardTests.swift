import SwiftUI
import Testing
@testable import InvoicesTracker

/// The card Příjmy of Odhad odvodů, drawn off-screen in a light and in a dark window: the bar of the income and the
/// swatches of its legend (the money received is the grey of secondary text, what waits for its payment is the accent,
/// and what is only expected is hatched (`Hatching`); the track under the parts is the fill of a bar, the bar is 14
/// points high and its corners are rounded by 5, and the swatch of a part is a square of 10 points rounded by 3), and
/// the green dot that marks the net income.
@Suite
@MainActor
struct PredictionIncomeCardTests {
    /// A ground that no part of the bar has.
    private let ground = Color(red: 1, green: 0, blue: 1)

    private func parts(_ fractions: [Double]) -> [PredictionPart] {
        zip([PredictionPartKind.received, .waiting, .expected], fractions).map { kind, fraction in
            PredictionPart(kind: kind, text: "", value: "", fraction: fraction)
        }
    }

    private func bar(_ fractions: [Double], in scheme: ColorScheme) throws -> OffscreenPicture {
        try OffscreenPicture(
            of: PredictionIncomeBar(parts: parts(fractions)).frame(width: 400).background(ground), in: scheme)
    }

    private func isNear(_ bytes: [Int], _ colour: [Int]) -> Bool {
        zip(bytes, colour).allSatisfy { abs($0 - $1) <= 6 }
    }

    /// The bar is 14 points high.
    @Test func theBarIs14PointsHigh() throws {
        let picture = try bar([0.5, 0.25, 0.25], in: .light)

        #expect(picture.size == CGSize(width: 400, height: 14))
    }

    /// Received, waiting and expected stand one after the other, each as wide as its part of the income: 200, 100 and
    /// 100 points of 400. The first is the grey of secondary text, the second the accent, and the third the stripes
    /// and the ground of the hatching.
    @Test(arguments: [ColorScheme.light, ColorScheme.dark])
    func thePartsAreGreyAccentAndHatching(scheme: ColorScheme) throws {
        let picture = try bar([0.5, 0.25, 0.25], in: scheme)
        let grey = try OffscreenPicture.bytes(of: Palette.text2, in: scheme)
        let accent = try OffscreenPicture.bytes(of: Palette.accent, in: scheme)
        let stripe = try OffscreenPicture.bytes(of: Palette.hatchStripe, in: scheme)
        let hatchGround = try OffscreenPicture.bytes(of: Palette.hatchGround, in: scheme)

        #expect(isNear(picture.bytes(at: CGPoint(x: 100, y: 7)), grey), "received")
        #expect(isNear(picture.bytes(at: CGPoint(x: 250, y: 7)), accent), "waiting")
        // The last 8 points are left out: the end of the bar is rounded, and shows the ground at its corners.
        let expected = CGRect(x: 302, y: 0, width: 90, height: 14)
        #expect(picture.count(near: stripe, in: expected, by: 6) > 300, "The stripes of the expected part are missing")
        #expect(picture.count(near: hatchGround, in: expected, by: 6) > 300, "Its ground is missing")
        // The three parts are all there is: not the ground that the bar stands on.
        let magenta = try OffscreenPicture.bytes(of: ground, in: scheme)
        #expect(picture.count(near: magenta, in: expected, by: 6) == 0)
    }

    /// What no part fills is the track, in the fill of a bar: the parts of 30 % leave the rest of 400 points to it.
    @Test(arguments: [ColorScheme.light, ColorScheme.dark])
    func theTrackIsTheFillOfABar(scheme: ColorScheme) throws {
        let picture = try bar([0.3, 0, 0], in: scheme)
        let track = try OffscreenPicture.bytes(of: Palette.fill, in: scheme)

        let grey = try OffscreenPicture.bytes(of: Palette.text2, in: scheme)
        #expect(isNear(picture.bytes(at: CGPoint(x: 300, y: 7)), track))
        #expect(isNear(picture.bytes(at: CGPoint(x: 60, y: 7)), grey))
    }

    /// The corners of the bar are rounded by 5 points: the ground that shows at each of its four corners, 6 points
    /// square, is as much as shows round a rectangle of that radius, and clearly less than round one of 8 points.
    @Test func theCornersAreRoundedByFivePoints() throws {
        let picture = try bar([1, 0, 0], in: .light)
        let magenta = try OffscreenPicture.bytes(of: ground, in: .light)
        func cut(_ radius: CGFloat) throws -> OffscreenPicture {
            let rounded = RoundedRectangle(cornerRadius: radius).fill(Color.black).frame(width: 400, height: 14)
            return try OffscreenPicture(of: rounded.background(ground), in: .light)
        }
        let corners = [
            CGRect(x: 0, y: 0, width: 6, height: 6), CGRect(x: 394, y: 0, width: 6, height: 6),
            CGRect(x: 0, y: 8, width: 6, height: 6), CGRect(x: 394, y: 8, width: 6, height: 6),
        ]
        let wanted = try cut(5)
        let tooRound = try cut(8)

        for corner in corners {
            let expected = wanted.count(near: magenta, in: corner, by: 6)
            #expect(tooRound.count(near: magenta, in: corner, by: 6) > expected + 4, "\(corner)")
            let found = picture.count(near: magenta, in: corner, by: 6)
            #expect((found - expected).magnitude <= 2, "\(corner) shows \(found) pixels of ground, not \(expected)")
        }
    }

    // MARK: The net income

    /// The net income is marked by a green dot of 8 points, as the card of Odhad odvodů marks it, and not by the line
    /// of 16 by 3 points that the strip of Přehled has: nothing else in the card is green, so the green pixels of the
    /// card fit a square of 8 points.
    @Test(arguments: [ColorScheme.light, ColorScheme.dark])
    func theNetIncomeIsMarkedByADotOf8Points(scheme: ColorScheme) throws {
        let page = try PredictionSample.page(year: 2026)
        let card = PredictionIncomeCard(page: page).frame(width: 800).background(Palette.bgCard)
        let green = try OffscreenPicture.bytes(of: Palette.green, in: scheme)

        let extent = try #require(try OffscreenPicture(of: card, in: scheme).extent(near: green, by: 6))

        #expect((extent.width - 8).magnitude <= 1, "The mark is \(extent.width) points wide")
        #expect((extent.height - 8).magnitude <= 1, "The mark is \(extent.height) points high")
    }

    // MARK: The swatches

    /// The swatch of a part in the legend is 10 points square: the grey, the accent, or the hatching.
    @Test(arguments: [ColorScheme.light, ColorScheme.dark])
    func theSwatchesOfTheLegendHaveTheColoursOfTheParts(scheme: ColorScheme) throws {
        let grey = try OffscreenPicture.bytes(of: Palette.text2, in: scheme)
        let accent = try OffscreenPicture.bytes(of: Palette.accent, in: scheme)
        let stripe = try OffscreenPicture.bytes(of: Palette.hatchStripe, in: scheme)

        let magenta = try OffscreenPicture.bytes(of: ground, in: scheme)

        for (kind, colour) in [(PredictionPartKind.received, grey), (.waiting, accent), (.expected, stripe)] {
            let picture = try OffscreenPicture(of: PredictionPartSwatch(kind: kind).background(ground), in: scheme)
            #expect(picture.size == CGSize(width: 10, height: 10), "\(kind) is \(picture.size)")
            if kind == .expected {
                #expect(picture.count(near: stripe, in: CGRect(x: 0, y: 0, width: 10, height: 10), by: 6) > 20)
            } else {
                #expect(isNear(picture.bytes(at: CGPoint(x: 5, y: 5)), colour), "\(kind)")
            }
            #expect(isNear(picture.bytes(at: CGPoint(x: 0.25, y: 0.25)), magenta), "The corner of \(kind) is not cut")
        }
    }
}
