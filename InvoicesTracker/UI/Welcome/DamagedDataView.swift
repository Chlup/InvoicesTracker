import SwiftUI

/// The data cannot be opened: the files of the data do not belong together, or they cannot be read. The text of the
/// phase says why. Nothing is deleted whatever the person chooses: a backup is restored in place of the data, or empty
/// data are started, and the files that are there are set aside in a folder beside them, as they are.
struct DamagedDataView: View {
    let model: AppModel

    /// Why the data cannot be opened, in Czech, as the phase has it.
    let reason: String

    @State private var restoring = false
    @State private var runner = StepRunner()

    var body: some View {
        if restoring {
            RestoreFlowView(model: model) {
                restoring = false
            }
        } else {
            WelcomeCard(label: "Data se nedají otevřít", width: 520) {
                VStack(spacing: 10) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 28, weight: .regular))
                        .foregroundStyle(.orange)
                        .frame(width: 64, height: 64)
                        .background(Color.orange.opacity(0.15), in: Circle())
                        .accessibilityHidden(true)
                    Text("Data se nedají otevřít")
                        .font(.title.weight(.bold))
                        .padding(.top, 4)
                        .accessibilityAddTraits(.isHeader)
                    Text(reason)
                        .fontWeight(.semibold)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(
                        """
                        Nic se nesmazalo ani nezměnilo. Máte-li zálohu, obnovte ji. Jinak můžete začít s prázdnými \
                        daty – dosavadní soubory se odloží do složky vedle dat, takže zůstanou na disku.
                        """
                    )
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: 400)
                    .fixedSize(horizontal: false, vertical: true)
                }
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                VStack(spacing: 10) {
                    WelcomeOptionRow(
                        systemImage: "arrow.counterclockwise", tint: .green, title: "Obnovit ze zálohy…",
                        detail: "Máte zálohu z InvoicesTracker (soubor .ttbackup).", isDisabled: runner.isWorking
                    ) {
                        restoring = true
                    }
                    WelcomeOptionRow(
                        systemImage: "plus", tint: .accentColor, title: "Začít s prázdnými daty",
                        detail: "Uložíte si nový kód pro obnovení a začnete znovu s prázdnými daty.",
                        isDisabled: runner.isWorking
                    ) {
                        Task { await runner.perform { try await model.startFresh() } }
                    }
                }
                if let errorText = runner.errorText {
                    WelcomeErrorLine(text: errorText)
                }
            }
        }
    }
}
