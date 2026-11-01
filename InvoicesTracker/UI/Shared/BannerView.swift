import SwiftUI

/// The banner with the result of an action, at the top of its screen: a success note with the sentence in semibold and
/// Zavřít to close it. VoiceOver reads it out when it appears, or once the app is unlocked when it appears under the
/// lock after inactivity.
struct BannerView: View {
    let text: String
    let close: () -> Void

    @Environment(AppModel.self) private var app: AppModel?

    var body: some View {
        Note(.success, icon: .none, title: text, text: "") {
            Button("Zavřít", action: close)
                .buttonStyle(CapsuleButtonStyle(.secondary, size: .small))
        }
        .onAppear { announce(text) }
        .onChange(of: text) { _, newText in announce(newText) }
    }

    private func announce(_ text: String) {
        VoiceOverAnnouncement.post(text, by: app)
    }
}
