import SwiftUI

/// The banner at the top of Přehled that reminds the person to enter the uniform rate of a finished year by hand: the
/// search for it ended on 31 March without finding it. It offers Zadat ručně, which shows the form in Nastavení › Rok,
/// and Zavřít. VoiceOver is told of it by the app model when the reminder comes (`AppModel.uniformRateReminderYear`).
struct UniformRateReminderBanner: View {
    /// The year whose rate was not found.
    let year: Int

    /// Zadat ručně: shows the form of the uniform rate in Nastavení › Rok.
    let enterManually: () -> Void

    /// Zavřít: closes the banner.
    let close: () -> Void

    /// "Jednotný kurz za rok 2026 se nepodařilo najít – zadejte ho ručně v Nastavení › Rok 2026."
    nonisolated static func text(year: Int) -> String {
        "Jednotný kurz za rok \(year) se nepodařilo najít – zadejte ho ručně v Nastavení › Rok \(year)."
    }

    var body: some View {
        let text = Self.text(year: year)
        HStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle")
                .foregroundStyle(.orange)
                .accessibilityHidden(true)
            Text(verbatim: text)
                .fontWeight(.semibold)
                .foregroundStyle(Color(.simulationText))
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button("Zadat ručně", action: enterManually)
                .buttonStyle(.bordered)
                .controlSize(.small)
            Button("Zavřít", action: close)
                .buttonStyle(.bordered)
                .controlSize(.small)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Color.orange.opacity(0.14), in: RoundedRectangle(cornerRadius: 12))
        .accessibilityElement(children: .contain)
    }
}
