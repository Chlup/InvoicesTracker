import SwiftUI

/// "Tento Mac data zatím nezná": the data are on this Mac and its device key does not open them (they came from another
/// Mac, or this Mac was repaired), so the recovery code opens them, and from then on this Mac knows them. "Nemám kód"
/// explains that nothing else opens the data and offers the two ways out: a backup whose code the person has, or
/// empty data, with the encrypted data staying on disk. The locked screen leads here too, for "Odemknout kódem pro
/// obnovení…".
struct NewMacView: View {
    let model: AppModel

    @State private var typed = ""
    @State private var showsNoCode = false
    @State private var restoring = false

    /// The label of the code the data need, read once from the keys file.
    @State private var codeLabel: String?

    /// The step of the code that was typed, and the step of "Začít s prázdnými daty" in the panel of "Nemám kód": each
    /// says its own error, the one under its field and the other under its panel.
    @State private var runner = StepRunner()
    @State private var freshRunner = StepRunner()

    var body: some View {
        if restoring {
            RestoreFlowView(model: model) {
                restoring = false
            }
        } else {
            WelcomeCard(label: "Odemknout kódem") {
                RecoveryCodeAsk(
                    title: "Tento Mac data zatím nezná",
                    text: """
                        Data pocházejí z jiného Macu, nebo byl tento Mac opraven. Odemkněte je kódem pro obnovení – \
                        příště už bude stačit Touch ID.
                        """,
                    fieldLabel: WelcomeTexts.codeFieldLabel(for: codeLabel), typed: $typed, errorText: runner.errorText,
                    isWorking: runner.isWorking || freshRunner.isWorking,
                    backTitle: showsNoCode ? "Skrýt" : "Nemám kód",
                    back: { showsNoCode.toggle() },
                    submitTitle: "Odemknout",
                    submit: {
                        // One step at a time, whichever of the two the person starts.
                        guard !freshRunner.isWorking else { return }
                        Task {
                            await runner.perform(codeLabel: codeLabel, forBackup: false) {
                                try await model.unlock(recoveryCode: typed)
                            }
                        }
                    }
                ) {
                    if showsNoCode {
                        NoCodePanel(isDisabled: runner.isWorking || freshRunner.isWorking) {
                            restoring = true
                        } startFresh: {
                            guard !runner.isWorking else { return }
                            Task { await freshRunner.perform { try await model.startFresh() } }
                        }
                        if let errorText = freshRunner.errorText {
                            WelcomeErrorLine(text: errorText)
                        }
                    }
                }
            }
            .task { codeLabel = model.vault.requiredRecoveryLabel }
            // What the last attempt said is about the code that was typed then.
            .onChange(of: typed) { runner.errorText = nil }
        }
    }
}

/// "Bez kódu se tato data otevřít nedají": what the person can do without the code — restore a backup whose code they
/// have, or start with empty data, which leaves the encrypted data on disk.
struct NoCodePanel: View {
    var isDisabled = false

    /// Obnovit ze zálohy….
    let restore: () -> Void

    /// Začít s prázdnými daty.
    let startFresh: () -> Void

    var body: some View {
        WelcomeBox(spacing: 10) {
            Text("Bez kódu se tato data otevřít nedají")
                .fontWeight(.semibold)
            Text(
                """
                Nikdo jiný kód nemá – ani autor aplikace. Máte-li zálohu, ke které kód máte (třeba starší kód), \
                obnovte ji. Zašifrovaná data zůstanou na disku, takže když kód najdete, otevřete je i později.
                """
            )
            .font(.callout)
            .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 8) {
                Button("Obnovit ze zálohy…", action: restore)
                    .welcomeBoxButton()
                Button("Začít s prázdnými daty", action: startFresh)
                    .welcomeBoxButton()
            }
            .disabled(isDisabled)
        }
    }
}
