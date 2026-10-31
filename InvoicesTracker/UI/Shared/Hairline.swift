import SwiftUI

/// The hairline of the design: a line one point thick across the whole width of its room, in the colour of the
/// separators of a card (`Palette.sep`). It stands between the parts of a card, such as the strip of the net income and
/// the chart under it, and above the rows of a list. With `isStrong` it is in the stronger colour of the separators
/// (`Palette.sepStrong`), as above the result of a bill and above the total of an invoice. VoiceOver does not read it.
struct Hairline: View {
    /// Whether the line is in the stronger colour of the separators and not in the ordinary one.
    var isStrong = false

    var body: some View {
        Rectangle()
            .fill(isStrong ? Palette.sepStrong : Palette.sep)
            .frame(height: 1)
            .accessibilityHidden(true)
    }
}
