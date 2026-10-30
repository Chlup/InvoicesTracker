import SwiftUI

extension View {
    /// The card that holds a part of a screen: the background of content on a rounded rectangle with a hairline edge
    /// and a faint shadow. It is made of semantic colours, so it follows the appearance of the window.
    func screenCard(cornerRadius: CGFloat = 16) -> some View {
        background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: cornerRadius))
            .overlay(RoundedRectangle(cornerRadius: cornerRadius).strokeBorder(.separator))
            .shadow(color: .black.opacity(0.04), radius: 1.5, y: 1)
    }
}
