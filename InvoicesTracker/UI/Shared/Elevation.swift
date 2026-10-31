import SwiftUI

/// How far a surface stands off the page, as the design draws it: a ring half a point wide in the colour of its edge,
/// and a drop shadow under it. The colours are the shadow tokens of the asset catalog, so both follow the appearance
/// of the window, and both are on the main actor like the rest of the palette. The board has three levels (a card, a
/// control and a pop); the fourth, the paper, is the prototype's, for the page of an invoice.
enum Elevation {
    /// A card on the page.
    case card

    /// A button or another control that stands on a card or on the page.
    case control

    /// A bubble or a menu that floats above the page.
    case pop

    /// A sheet of paper that lies on a ground of its own, such as the page of an invoice in its preview and in the
    /// sheet that shows it: a soft shadow 8 points under it, 12 points wide, as the prototype draws the page (`0 8px
    /// 24px` at 10 %). None of the other levels is that: a card and a control cast a shadow of 1 point, and a bubble
    /// one that is lower, wider and darker. The prototype adds a tight shadow under the edge; the ring of this level,
    /// which is the ring of a control, would stand for it, but a sheet of paper covers all of the surface under it,
    /// its ring included, so it shows the soft shadow alone.
    case paper

    /// The width of the ring, in points.
    fileprivate static let ringWidth: CGFloat = 0.5

    /// The colour of the ring around a surface of this level.
    var ringColor: Color {
        switch self {
        case .card: Color(.tokenShadowCardRing)
        case .control, .paper: Color(.tokenShadowControlRing)
        case .pop: Color(.tokenShadowPopRing)
        }
    }

    /// The colour of the drop shadow under a surface of this level.
    var dropColor: Color {
        switch self {
        case .card: Color(.tokenShadowCardDrop)
        case .control: Color(.tokenShadowControlDrop)
        case .paper: Color(.tokenShadowPaperDrop)
        case .pop: Color(.tokenShadowPopDrop)
        }
    }

    /// How far below the surface its drop shadow lies, in points.
    var dropOffset: CGFloat {
        switch self {
        case .card, .control: 1
        case .paper: 8
        case .pop: 12
        }
    }

    /// How far the drop shadow spreads, in points.
    var dropRadius: CGFloat {
        switch self {
        case .card, .control: 1
        case .paper: 12
        case .pop: 16
        }
    }
}

extension InsettableShape {
    /// The shape drawn as a surface that stands off the page at `level`: filled with `fill`, with a ring half a point
    /// wide along its edge, and the drop shadow of the level under it. A card is `RoundedRectangle` of 16 points, a
    /// control is a `Capsule`, a bubble, a menu or a line on the window is a `RoundedRectangle` of 10, and the page of
    /// an invoice is a `RoundedRectangle` of 4.
    ///
    /// Only the shape casts the shadow. SwiftUI puts a shadow under everything that is drawn beneath it, each text and
    /// each figure on its own, so a shadow set on a view that holds content would be cast by the content too. Draw the
    /// surface as the background of the view that stands on it, never over it:
    ///
    ///     Text("Obsah")
    ///         .padding(20)
    ///         .background {
    ///             RoundedRectangle(cornerRadius: DesignMetrics.cardRadius)
    ///                 .surface(Palette.bgCard, elevation: .card)
    ///         }
    ///
    /// The ring lies under the content as well, so what hangs out over the edge of the surface, such as a popover on a
    /// card, covers it. The shape takes the room the background is given: the size of the view it is the background of.
    func surface(_ fill: some ShapeStyle, elevation level: Elevation) -> some View {
        self.fill(fill)
            .shadow(color: level.dropColor, radius: level.dropRadius, y: level.dropOffset)
            .overlay(strokeBorder(level.ringColor, lineWidth: Elevation.ringWidth))
    }
}
