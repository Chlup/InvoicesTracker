import SwiftUI

/// The banner at the top of Přehled when the day moved into a new year: it says which year began and which is closed,
/// and offers to show the closed one. VoiceOver is told of it once, by the model, when the new year begins
/// (`AppModel.newYearBanner`), not each time Přehled shows it.
struct NewYearBanner: View {
    /// The year that is over.
    let finishedYear: Int

    /// Zobrazit rok …: shows the year that is over.
    let showFinishedYear: () -> Void

    /// Zavřít: closes the banner and stays on the new year.
    let close: () -> Void

    /// "Začal rok 2027 — rok 2026 je uzavřený".
    nonisolated static func text(finishedYear: Int) -> String {
        "Začal rok \(finishedYear + 1) — rok \(finishedYear) je uzavřený"
    }

    /// "Zobrazit rok 2026".
    nonisolated static func showTitle(finishedYear: Int) -> String {
        "Zobrazit rok \(finishedYear)"
    }

    var body: some View {
        let text = Self.text(finishedYear: finishedYear)
        HStack(spacing: 12) {
            Image(systemName: "calendar.badge.checkmark")
                .foregroundStyle(.tint)
                .accessibilityHidden(true)
            Text(text)
                .fontWeight(.semibold)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button(Self.showTitle(finishedYear: finishedYear), action: showFinishedYear)
                .buttonStyle(.bordered)
                .controlSize(.small)
            Button("Zavřít", action: close)
                .buttonStyle(.bordered)
                .controlSize(.small)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
        .accessibilityElement(children: .contain)
    }
}
