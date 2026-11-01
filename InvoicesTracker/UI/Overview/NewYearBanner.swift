import SwiftUI

/// The banner at the top of Přehled when the day moved into a new year: a note of the information tone that says which
/// year began and which is closed, and offers to show the closed one or to close the note. VoiceOver is told of it
/// once, by the model, when the new year begins (`AppModel.newYearBanner`), not each time Přehled shows it, and reads
/// the sentence and reaches each button on its own.
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
        Note(.info, icon: .info, title: Self.text(finishedYear: finishedYear), text: "") {
            HStack(spacing: 8) {
                Button(Self.showTitle(finishedYear: finishedYear), action: showFinishedYear)
                    .buttonStyle(CapsuleButtonStyle(.secondary, size: .small))
                Button("Zavřít", action: close)
                    .buttonStyle(CapsuleButtonStyle(.secondary, size: .small))
            }
        }
    }
}
