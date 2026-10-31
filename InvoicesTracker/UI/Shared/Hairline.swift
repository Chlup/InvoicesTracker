import SwiftUI

/// The hairline of the design: a line one point thick across the whole width of its room, in the colour of the
/// separators of a card (`Palette.sep`). It stands between the parts of a card, such as the strip of the net income and
/// the chart under it, and above the rows of a list. VoiceOver does not read it.
struct Hairline: View {
    var body: some View {
        Rectangle()
            .fill(Palette.sep)
            .frame(height: 1)
            .accessibilityHidden(true)
    }
}
