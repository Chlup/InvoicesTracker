import SwiftUI

/// How far a surface stands off the page, as the design draws it: a ring half a point wide in the colour of its edge,
/// and a drop shadow under it. The colours are the shadow tokens of the asset catalog, so both follow the appearance
/// of the window, and both are on the main actor like the rest of the palette.
enum Elevation {
    /// A card on the page.
    case card

    /// A button or another control that stands on a card or on the page.
    case control

    /// A bubble or a menu that floats above the page.
    case pop

    /// The width of the ring, in points.
    fileprivate static let ringWidth: CGFloat = 0.5

    /// The colour of the ring around a surface of this level.
    var ringColor: Color {
        switch self {
        case .card: Color(.tokenShadowCardRing)
        case .control: Color(.tokenShadowControlRing)
        case .pop: Color(.tokenShadowPopRing)
        }
    }

    /// The colour of the drop shadow under a surface of this level.
    var dropColor: Color {
        switch self {
        case .card: Color(.tokenShadowCardDrop)
        case .control: Color(.tokenShadowControlDrop)
        case .pop: Color(.tokenShadowPopDrop)
        }
    }

    /// How far below the surface its drop shadow lies, in points.
    var dropOffset: CGFloat {
        switch self {
        case .card, .control: 1
        case .pop: 12
        }
    }

    /// How far the drop shadow spreads, in points.
    var dropRadius: CGFloat {
        switch self {
        case .card, .control: 1
        case .pop: 16
        }
    }
}

extension View {
    /// Raises the view off the page at `level`: a ring half a point wide that follows `shape`, and the drop shadow of
    /// the level. The shadow follows what the view draws, so apply it to a view that already has its background.
    func elevation(_ level: Elevation, in shape: some InsettableShape) -> some View {
        overlay(shape.strokeBorder(level.ringColor, lineWidth: Elevation.ringWidth))
            .shadow(color: level.dropColor, radius: level.dropRadius, y: level.dropOffset)
    }

    /// Raises the view off the page at `level`, in the shape the design gives that level: a card has the corners of a
    /// card, a control is a capsule, and a bubble or a menu has the corners of a panel. The shadow follows what the
    /// view draws, so apply it to a view that already has its background.
    @ViewBuilder
    func elevation(_ level: Elevation) -> some View {
        switch level {
        case .card: elevation(level, in: RoundedRectangle(cornerRadius: DesignMetrics.cardRadius))
        case .control: elevation(level, in: Capsule())
        case .pop: elevation(level, in: RoundedRectangle(cornerRadius: DesignMetrics.panelRadius))
        }
    }
}
