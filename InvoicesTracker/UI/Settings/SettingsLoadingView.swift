import SwiftUI

/// What the tabs Moje údaje and Rok of Nastavení show in place of their cards until they have read their data for the
/// first time: a small progress indicator and "Načítám…". It is at least 160 points tall and as wide as the room it is
/// given, so that the page keeps its size while the cards are on their way and does not jump when they come.
struct SettingsLoadingView: View {
    var body: some View {
        HStack(spacing: 8) {
            // The words say what the indicator would, so VoiceOver reads them once.
            ProgressView()
                .controlSize(.small)
                .accessibilityHidden(true)
            Text("Načítám…")
                .font(Typography.body)
                .foregroundStyle(Palette.text2)
        }
        .frame(maxWidth: .infinity, minHeight: 160)
    }
}
