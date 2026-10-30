import SwiftUI

/// The colours of the authorities, for the views. They come from the palette, whose colours are on the main actor, like
/// the views.
extension Authority {
    /// The colour of the authority — tax indigo, social teal, health raspberry — with a lighter, slightly more
    /// saturated variant in dark mode. What is still to pay is the same colour at a reduced opacity.
    var color: Color {
        switch self {
        case .tax: Palette.tax
        case .social: Palette.social
        case .health: Palette.health
        }
    }

    /// The pale tint of the colour of the authority, for the background of a pill or a row that belongs to it, and a
    /// deep one in dark mode.
    var tint: Color {
        switch self {
        case .tax: Palette.taxTint
        case .social: Palette.socialTint
        case .health: Palette.healthTint
        }
    }
}
