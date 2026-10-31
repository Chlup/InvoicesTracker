import AppKit
import SwiftUI
import Testing
@testable import InvoicesTracker

/// The hatching that marks an estimate: the paint of the part of a bar that is only expected, in the composition bar of
/// Odhad odvodů, its key, the bars of the estimate chart of Přehled and its key. The design draws it as
/// `repeating-linear-gradient(135deg, stripe 0 3px, ground 3px 6px)`: stripes of the colour `hatchStripe` that are 3
/// points across, with 3 points of `hatchGround` between them, at 135 degrees from the top left corner of what is
/// painted, so they rise to the right. The pictures are drawn off-screen in a light and in a dark window.
@Suite
@MainActor
struct HatchingTests {
    /// The two colours of the hatching in a window of `scheme`, as sRGB bytes.
    private func colours(in scheme: ColorScheme) throws -> (stripe: [Int], ground: [Int]) {
        (
            stripe: try OffscreenPicture.bytes(of: Palette.hatchStripe, in: scheme),
            ground: try OffscreenPicture.bytes(of: Palette.hatchGround, in: scheme)
        )
    }

    /// Whether `bytes` are the colour `expected` to within a few levels, which the edge of a stripe would not be.
    private func isNear(_ bytes: [Int], _ expected: [Int]) -> Bool {
        zip(bytes, expected).allSatisfy { abs($0 - $1) <= 6 }
    }

    /// The picture of a hatched fill of `size` in a window of `scheme`.
    private func picture(of size: CGSize, in scheme: ColorScheme) throws -> OffscreenPicture {
        try OffscreenPicture(of: HatchedFill().frame(width: size.width, height: size.height), in: scheme)
    }

    // MARK: The measures

    /// The stripe is 3 points across and the ground after it 3 more, which is the 6 of the period, as the design draws
    /// them (`repeating-linear-gradient(135deg, stripe 0 3px, ground 3px 6px)`). The other tests take their measures
    /// from here.
    @Test func theStripeIsThreePointsAcrossAndThePeriodSix() {
        #expect(Hatching.stripeWidth == 3)
        #expect(Hatching.period == 6)
    }

    // MARK: The fill of a view

    /// Along the diagonal from the top left corner, which is the direction of the gradient, the colour changes every
    /// `stripeWidth` points: the stripe first, then the ground, and so on, in a light and in a dark window. The points
    /// are the middles of the stripes and of the grounds, so no point is on an edge.
    @Test(arguments: [ColorScheme.light, ColorScheme.dark])
    func theColourChangesEveryThreePointsAlongTheDiagonalFromTheTopLeftCorner(scheme: ColorScheme) throws {
        let (stripe, ground) = try colours(in: scheme)
        let picture = try picture(of: CGSize(width: 60, height: 40), in: scheme)

        // The distance d along the diagonal is (x + y) / √2, so on the line x = y it is x · √2.
        for step in 0..<8 {
            let distance = Hatching.stripeWidth * (CGFloat(step) + 0.5)
            let along = distance / 2.0.squareRoot()
            let isStripe = step.isMultiple(of: 2)
            let found = picture.bytes(at: CGPoint(x: along, y: along))
            #expect(
                isNear(found, isStripe ? stripe : ground),
                "At \(distance) points the colour is \(found), not \(isStripe ? "the stripe" : "the ground")")
        }
    }

    /// The stripes repeat every `period` points across, which is `period` · √2 points along a horizontal line: the
    /// middles of the stripes and of the grounds on a row, from the fourth period on, have their colours in a light and
    /// in a dark window, and both colours are there.
    @Test(arguments: [ColorScheme.light, ColorScheme.dark])
    func theStripesRepeatEveryPeriodAcrossAndBothColoursAreThere(scheme: ColorScheme) throws {
        let (stripe, ground) = try colours(in: scheme)
        let picture = try picture(of: CGSize(width: 60, height: 40), in: scheme)
        let period = Hatching.period * 2.0.squareRoot()
        let row: CGFloat = 20

        for index in 3...5 {
            let start = CGFloat(index) * period
            // A stripe covers the first half of a period, from the line x + y = start, and the ground the second.
            let middleOfStripe = start + period / 4 - row
            let middleOfGround = start + 3 * period / 4 - row
            #expect(isNear(picture.bytes(at: CGPoint(x: middleOfStripe, y: row)), stripe), "stripe \(index)")
            #expect(isNear(picture.bytes(at: CGPoint(x: middleOfGround, y: row)), ground), "ground \(index)")
        }
        let whole = CGRect(x: 0, y: 0, width: 60, height: 40)
        #expect(picture.count(near: stripe, in: whole, by: 6) > 300, "The stripes are not there")
        #expect(picture.count(near: ground, in: whole, by: 6) > 300, "The ground is not there")
    }

    /// The two colours of the hatching differ from each other, and each of them from its colour in the other
    /// appearance, so that the tests above tell a stripe from the ground and a light window from a dark one.
    @Test func theTwoColoursDifferInEachAppearanceAndFromOneAppearanceToTheOther() throws {
        let light = try colours(in: .light)
        let dark = try colours(in: .dark)

        #expect(!isNear(light.stripe, dark.stripe))
        #expect(!isNear(light.ground, dark.ground))
        #expect(!isNear(light.stripe, light.ground))
    }

    /// The pattern starts at the top left corner of what is painted, whatever its size: a small key and a long bar
    /// begin with the stripe in the corner.
    @Test(arguments: [ColorScheme.light, ColorScheme.dark])
    func everyFillStartsWithAStripeInItsTopLeftCorner(scheme: ColorScheme) throws {
        let (stripe, _) = try colours(in: scheme)

        for size in [CGSize(width: 10, height: 10), CGSize(width: 200, height: 14)] {
            let picture = try picture(of: size, in: scheme)
            #expect(isNear(picture.bytes(at: CGPoint(x: 1, y: 0.5)), stripe), "corner of \(size)")
        }
    }

    // MARK: The paint of a chart

    /// The bars of a chart are painted with an `ImagePaint` made of the same drawing (`Hatching.paint`): along the
    /// diagonal from the corner of what it paints it is the stripe and the ground, `stripeWidth` points each, in a
    /// light and in a dark window.
    @Test(arguments: [ColorScheme.light, ColorScheme.dark])
    func thePaintOfAChartHasTheSameStripesAsTheFill(scheme: ColorScheme) throws {
        let (stripe, ground) = try colours(in: scheme)
        let picture = try OffscreenPicture(of: PaintedLikeTheChart(), in: scheme)

        for step in 0..<8 {
            let distance = Hatching.stripeWidth * (CGFloat(step) + 0.5)
            let along = distance / 2.0.squareRoot()
            let found = picture.bytes(at: CGPoint(x: along, y: along))
            #expect(isNear(found, step.isMultiple(of: 2) ? stripe : ground), "At \(distance) points: \(found)")
        }
    }

    /// The estimate chart of Přehled paints the part of a bar that is still to be issued with this hatching, in a light
    /// and in a dark window: the stripes of the token are in its picture, which the blue of the bars mixed with the
    /// card, as the chart drew them before, does not come within a few levels of.
    @Test(arguments: [ColorScheme.light, ColorScheme.dark])
    func theBarsOfTheEstimateChartAreHatchedWithIt(scheme: ColorScheme) throws {
        let (stripe, _) = try colours(in: scheme)
        let outcome = try PredictionSample.outcome(year: 2026)
        let year = PredictionSample.yearInput(year: 2026)
        let effects = year.receipts.compactMap { receipt -> ReceiptEffect? in
            guard case .invoice = receipt.source else { return nil }
            return TaxEngine.effect(of: receipt, in: year)
        }
        let months = PredictionChartBuilder.months(
            year: 2026, today: PredictionSample.sampleToday, rows: SampleYear2026.chartRows,
            paymentEffects: effects, prediction: outcome.prediction, expectedPayments: outcome.expectedPayments())
        #expect(months.contains { $0.issuedEstimateHalere > 0 }, "The sample has no month to come")
        let chart = PredictionChart(months: months).padding(16).frame(width: 900, height: 340)
            .background(Palette.bgCard)

        let picture = try OffscreenPicture(of: chart, in: scheme)

        let whole = CGRect(origin: .zero, size: picture.size)
        #expect(picture.count(near: stripe, in: whole, by: 4) > 150, "The chart has no stripes of the hatching")
    }
}

/// A rectangle painted the way the bars of the estimate chart are: with the paint of the hatching that the environment
/// of the view gives colours to.
private struct PaintedLikeTheChart: View {
    @Environment(\.self) private var environment

    var body: some View {
        Rectangle()
            .fill(Hatching.paint(in: environment))
            .frame(width: 60, height: 40)
    }
}
