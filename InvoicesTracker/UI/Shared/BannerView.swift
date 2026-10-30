import SwiftUI

/// The green banner with the result of an action, at the top of its screen, with Zavřít to close it. VoiceOver reads it
/// out when it appears, or once the app is unlocked when it appears under the lock after inactivity.
struct BannerView: View {
    let text: String
    let close: () -> Void

    @Environment(AppModel.self) private var app: AppModel?

    var body: some View {
        HStack(spacing: 12) {
            Text(text)
                .fontWeight(.semibold)
                .foregroundStyle(Color(.bannerText))
                .frame(maxWidth: .infinity, alignment: .leading)
            Button("Zavřít", action: close)
                .buttonStyle(.bordered)
                .controlSize(.small)
                .tint(Color(.bannerText))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Color.green.opacity(0.15), in: RoundedRectangle(cornerRadius: 12))
        .accessibilityElement(children: .contain)
        .onAppear { announce(text) }
        .onChange(of: text) { _, newText in announce(newText) }
    }

    private func announce(_ text: String) {
        VoiceOverAnnouncement.post(text, by: app)
    }
}
