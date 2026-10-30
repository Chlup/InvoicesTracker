import SwiftUI

/// The first launch: one centred card without a sidebar, "Vítejte v InvoicesTracker", with the two ways to begin — with
/// empty data, which goes on to the recovery code, and from a backup — and a note for a Mac that was restored whole.
struct WelcomeView: View {
    let model: AppModel

    @State private var restoring = false
    @State private var runner = StepRunner()

    var body: some View {
        if restoring {
            RestoreFlowView(model: model) {
                restoring = false
            }
        } else {
            WelcomeCard(label: "Vítejte") {
                VStack(spacing: 10) {
                    Image(systemName: "doc.text")
                        .font(.system(size: 30, weight: .regular))
                        .foregroundStyle(.white)
                        .frame(width: 64, height: 64)
                        .background(
                            LinearGradient(
                                colors: [Color.accentColor.opacity(0.75), Color.accentColor], startPoint: .top,
                                endPoint: .bottom),
                            in: RoundedRectangle(cornerRadius: 16)
                        )
                        .shadow(color: Color.accentColor.opacity(0.3), radius: 8, y: 4)
                        .accessibilityHidden(true)
                    Text("Vítejte v InvoicesTracker")
                        .font(.system(size: 24, weight: .bold))
                        .padding(.top, 4)
                        .accessibilityAddTraits(.isHeader)
                    Text(
                        """
                        Faktury, daň a pojištění na jednom místě. Data zůstávají jen v tomto Macu – aplikace je \
                        šifruje a klíč k nim chrání Secure Enclave tohoto Macu.
                        """
                    )
                    .frame(maxWidth: 400)
                    .fixedSize(horizontal: false, vertical: true)
                }
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                VStack(spacing: 10) {
                    WelcomeOptionRow(
                        systemImage: "plus", tint: .accentColor, title: "Začít s prázdnými daty",
                        detail: """
                            Uložíte si kód pro obnovení, vyplníte své údaje na faktury a můžete importovat faktury z \
                            Fakturoidu.
                            """,
                        isDisabled: runner.isWorking
                    ) {
                        Task { await runner.perform { try await model.startFresh() } }
                    }
                    WelcomeOptionRow(
                        systemImage: "arrow.counterclockwise", tint: .green, title: "Obnovit ze zálohy",
                        detail: "Máte zálohu z InvoicesTracker (soubor .ttbackup), třeba z jiného Macu.",
                        isDisabled: runner.isWorking
                    ) {
                        restoring = true
                    }
                }
                if let errorText = runner.errorText {
                    WelcomeErrorLine(text: errorText)
                }
                Text(
                    """
                    Obnovili jste celý Mac z Time Machine nebo jste data přenesli Průvodcem migrací? Pak je aplikace \
                    najde sama a zeptá se jen na kód pro obnovení.
                    """
                )
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity)
            }
        }
    }
}
