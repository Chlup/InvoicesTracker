import SwiftUI

/// Says a text to VoiceOver, which reads it out at its next chance. The models that tell of a change of state do it
/// with this (`AppModel.announce`), not the views by what they happen to show first.
@MainActor
enum VoiceOverAnnouncement {
    static func post(_ text: String) {
        AccessibilityNotification.Announcement(text).post()
    }

    /// Says `text` for a view that shows it, such as a banner or a line of a failure as it appears: through `app`, the
    /// app model of the window the view is in, which holds the text back while the app is locked after inactivity and
    /// the lock hides the view (`AppModel.announceWhenUnlocked(_:)`), or at once for a view outside that window.
    static func post(_ text: String, by app: AppModel?) {
        if let app {
            app.announceWhenUnlocked(text)
        } else {
            post(text)
        }
    }
}
