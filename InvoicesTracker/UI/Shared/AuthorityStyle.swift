import SwiftUI

/// The colours of the authorities, for the views. The asset catalog's colours are on the main actor, like the views.
extension Authority {
    /// The colour of the authority — tax indigo, social teal, health raspberry — from the asset catalog, with a
    /// lighter, slightly more saturated variant in dark mode. What is still to pay is the same colour at a reduced
    /// opacity.
    var color: Color {
        switch self {
        case .tax: Color(.tax)
        case .social: Color(.social)
        case .health: Color(.health)
        }
    }
}
