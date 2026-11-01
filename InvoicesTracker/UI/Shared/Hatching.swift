import SwiftUI

/// The hatching that marks an estimate, in a bar and in a chart: the part of the income that is only expected in the
/// composition bar of Odhad odvodů and the key of that part, and the part of a bar that is still to be issued in the
/// estimate chart of Přehled and its key. The design draws it as `repeating-linear-gradient(135deg, stripe 0 3px,
/// ground 3px 6px)`: stripes of the colour `Palette.hatchStripe`, 3 points across, with 3 points of
/// `Palette.hatchGround` between them, rising to the right, and the first stripe starting at the top left corner of
/// what is painted. Along a horizontal line the stripes repeat every `period` · √2 points, which is `period` points
/// across them.
///
/// There is one drawing (`draw(in:size:stripe:ground:)`). A view paints with it as a fill (`HatchedFill`), and a chart
/// paints with it as an `ImagePaint` (`paint(in:)`), because a mark of a chart takes a style and not a view.
nonisolated enum Hatching {
    /// The width of a stripe, and of the ground after it, across the stripes.
    static let stripeWidth: CGFloat = 3

    /// The width of a stripe and the ground after it together, across the stripes.
    static let period: CGFloat = 2 * stripeWidth

    /// The size of the tile of the paint of a chart, in points. One tile paints a whole bar of the estimate chart
    /// (46 points wide at most, and not as high as the chart, 220 points), so no seam of two tiles shows in it: the
    /// stripes are `period` · √2 points apart along a side, which no whole number of points is a multiple of.
    static let tileSize = CGSize(width: 48, height: 224)

    /// How much wider than across them the stripes are along a horizontal line, which they cross at 135 degrees.
    private static let slant = 2.0.squareRoot()

    /// Draws the hatching over a rectangle of `size` points from the origin of `context`: the ground first, then the
    /// stripes, each the band between two lines of the slope 135 degrees, `stripeWidth` apart across, one every
    /// `period`, starting at the top left corner. A band is cut by the rectangle, so a drawing in a context larger than
    /// `size` shows only its part.
    static func draw(in context: GraphicsContext, size: CGSize, stripe: Color, ground: Color) {
        var context = context
        let bounds = Path(CGRect(origin: .zero, size: size))
        context.clip(to: bounds)
        context.fill(bounds, with: .color(ground))
        // Along the top edge a stripe is `stripeWidth` · √2 points wide, and a stripe and the ground after it are
        // `period` · √2.
        let along = stripeWidth * slant
        var start: CGFloat = 0
        while start < size.width + size.height {
            var band = Path()
            band.move(to: CGPoint(x: start, y: 0))
            band.addLine(to: CGPoint(x: start + along, y: 0))
            band.addLine(to: CGPoint(x: start + along - size.height, y: size.height))
            band.addLine(to: CGPoint(x: start - size.height, y: size.height))
            band.closeSubpath()
            context.fill(band, with: .color(stripe))
            start += period * slant
        }
    }

    /// The tile that `paint(in:)` repeats: the hatching over `tileSize`, drawn with colours that are already worked out
    /// for an appearance, as the image draws them whenever it is drawn, apart from the main actor.
    static func tile(stripe: Color.Resolved, ground: Color.Resolved) -> Image {
        let size = tileSize
        let stripe = Color(stripe)
        let ground = Color(ground)
        return Image(size: size, opaque: true) { context in
            draw(in: context, size: size, stripe: stripe, ground: ground)
        }
    }

    /// The paint of a mark of a chart that stands for an estimate, in the colours of the appearance `environment`
    /// has. The pattern starts at the top left corner of the mark it paints, and a mark is no wider than 48 points and
    /// no higher than 224, which a tile is.
    @MainActor
    static func paint(in environment: EnvironmentValues) -> ImagePaint {
        ImagePaint(
            image: tile(
                stripe: Palette.hatchStripe.resolve(in: environment),
                ground: Palette.hatchGround.resolve(in: environment)))
    }
}

/// A fill with the hatching of an estimate, as large as the room it is given, with its stripes starting at its top left
/// corner. The corners are not rounded; the shape that clips the fill rounds them. VoiceOver does not read it.
struct HatchedFill: View {
    var body: some View {
        let stripe = Palette.hatchStripe
        let ground = Palette.hatchGround
        Canvas { context, size in
            Hatching.draw(in: context, size: size, stripe: stripe, ground: ground)
        }
        .accessibilityHidden(true)
    }
}
