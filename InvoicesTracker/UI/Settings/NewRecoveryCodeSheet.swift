import SwiftUI

/// The sheet Nový kód pro obnovení, in two steps: what a new code does, with the warning that the older backups still
/// need the code in force; then the new code to print or copy, the person's word that it is stored away from this Mac,
/// and Hotovo, which puts it in force (`SecurityTabModel.commitNewCode(_:)`). Until Hotovo nothing changes: Zrušit, at
/// either step, leaves the code in force as it is.
struct NewRecoveryCodeSheet: View {
    let model: SecurityTabModel

    /// Closes the sheet.
    let close: () -> Void

    /// The new code, once it is made; nil on the first step.
    @State private var pending: PendingRecoveryCode?
    @State private var stored = false
    @State private var errorText: String?
    @State private var isWorking = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            SheetHeader(
                title: "Nový kód pro obnovení", subtitle: SecurityTabModel.newCodeSubtitle(replacing: replacedLabel))
            if let pending {
                codeStep(pending)
            } else {
                introStep
            }
        }
        .padding(.top, 22)
        .padding(.horizontal, 24)
        .padding(.bottom, 20)
        .frame(width: 560)
    }

    /// The label of the code in force, which the new one replaces.
    private var replacedLabel: String {
        model.codeLabel ?? "kód pro obnovení"
    }

    // MARK: The steps

    private var introStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(verbatim: SecurityTabModel.newCodeIntro(replacing: replacedLabel))
                .font(Typography.body)
                .foregroundStyle(Palette.text2)
                .fixedSize(horizontal: false, vertical: true)
            Note(.attention, icon: .warning, text: SecurityTabModel.newCodeWarning(replacing: replacedLabel))
            if let errorText {
                SettingsFailureLine(text: errorText)
            }
            footer(goTitle: "Vytvořit nový kód", goDisabled: false, go: makeCode)
        }
    }

    private func codeStep(_ pending: PendingRecoveryCode) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            RecoveryCodeCard(
                code: pending.code, caption: WelcomeTexts.codeCaption(number: pending.number, created: pending.created),
                note: "32 znaků", label: pending.label, accessibilityName: "Nový kód pro obnovení", groupFontSize: 17)
            Toggle(isOn: $stored) {
                Text("Nový kód mám uložený mimo tento Mac")
                    .font(Typography.bodySemibold)
                    .foregroundStyle(Palette.text)
            }
            .toggleStyle(.checkbox)
            .insetPanel(horizontal: 14, vertical: 12)
            .disabled(isWorking)
            if let errorText {
                SettingsFailureLine(text: errorText)
            }
            footer(goTitle: "Hotovo", goDisabled: !stored) {
                commit(pending)
            }
        }
    }

    /// Zrušit and the button that goes on, 32 points tall as the buttons of a dialog are, with 4 points over them:
    /// Zrušit on the grey fill, the other in the accent.
    private func footer(goTitle: String, goDisabled: Bool, go: @escaping () -> Void) -> some View {
        HStack(spacing: 8) {
            Spacer()
            if isWorking {
                ProgressView()
                    .controlSize(.small)
            }
            Button("Zrušit", action: close)
                .buttonStyle(CapsuleButtonStyle(.secondary))
                .keyboardShortcut(.cancelAction)
                .disabled(isWorking)
            Button(goTitle, action: go)
                .buttonStyle(CapsuleButtonStyle(.primary))
                .keyboardShortcut(.defaultAction)
                // One step at a time across the app: not while a backup or a restore runs.
                .disabled(goDisabled || isWorking || model.isWorking)
        }
        .padding(.top, 4)
    }

    // MARK: Actions

    /// Vytvořit nový kód: the new code to show. Nothing is written.
    private func makeCode() {
        do {
            pending = try model.createNewCode()
            stored = false
            errorText = nil
        } catch {
            errorText = SecurityTabModel.failureText(error)
        }
    }

    /// Hotovo: the new code is put in force and the sheet closes. A code made before another change of the keys is
    /// refused, and the sheet goes back to its first step to make a new one.
    private func commit(_ pending: PendingRecoveryCode) {
        guard !isWorking else { return }
        isWorking = true
        errorText = nil
        Task {
            defer { isWorking = false }
            do {
                try await model.commitNewCode(pending)
                close()
            } catch {
                errorText = SecurityTabModel.failureText(error)
                if error as? VaultError == .outdatedCode {
                    self.pending = nil
                }
            }
        }
    }
}
