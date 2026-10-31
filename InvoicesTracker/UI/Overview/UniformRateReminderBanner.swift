import SwiftUI

/// The banner at the top of Přehled that reminds the person to enter the uniform rate of a finished year by hand: the
/// search for it ended on 31 March without finding it. A note of the attention tone, in orange, with the buttons Zadat
/// ručně, which shows the form in Nastavení › Rok, and Zavřít. VoiceOver is told of it by the app model when the
/// reminder comes (`AppModel.uniformRateReminderYear`), and reads the sentence and reaches each button on its own.
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
        Note(.attention, icon: .warning, title: Self.text(year: year), text: "") {
            HStack(spacing: 8) {
                Button("Zadat ručně", action: enterManually)
                    .buttonStyle(CapsuleButtonStyle(.secondary, size: .small))
                Button("Zavřít", action: close)
                    .buttonStyle(CapsuleButtonStyle(.secondary, size: .small))
            }
        }
    }
}
