import SwiftUI

/// The sheet Obnovit ze zálohy while the data is open: the local backups to choose from, Jiný soubor…, what the chosen
/// backup restores and what opens it, the field of its code when this Mac does not open it, and Obnovit. The data that
/// is open is saved as a backup first (`RestoreSheetModel`). With an invoice being written, Obnovit asks "Zahodit
/// rozepsanou fakturu?" in a box in place of the buttons, and the choice of the backup waits for the answer.
struct RestoreSheet: View {
    @State private var model: RestoreSheetModel
    @State private var showsImporter = false

    /// Closes the sheet.
    let close: () -> Void

    init(app: AppModel, security: SecurityTabModel, close: @escaping () -> Void) {
        _model = State(initialValue: RestoreSheetModel(app: app, security: security))
        self.close = close
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            SheetHeader(title: "Obnovit ze zálohy", subtitle: "Současná data se nejdřív uloží jako záloha")
            choicesList
            Button("Jiný soubor…") {
                showsImporter = true
            }
            .settingsCardButton()
            .disabled(choiceWaits)
            if let summary = model.summary {
                summaryBox(summary)
            }
            if model.needsCode {
                RecoveryCodeField(
                    label: model.codeFieldLabel, text: $model.typed, errorText: model.errorText, submit: restore)
            } else if let errorText = model.errorText {
                SettingsFailureLine(text: errorText)
            }
            if model.asksToDiscard {
                DiscardQuestionBox(
                    keepEditing: { model.keepEditing() },
                    discard: {
                        // Answered before the restore goes on, which asks again while the editor holds changes.
                        model.discard()
                        restore()
                    })
            } else {
                footer
            }
        }
        .padding(.top, 22)
        .padding(.horizontal, 24)
        .padding(.bottom, 20)
        .frame(width: 560)
        .onAppear {
            model.load()
        }
        .fileImporter(isPresented: $showsImporter, allowedContentTypes: [SecurityTab.backupType]) { result in
            switch result {
            case .success(let url):
                Task { await model.chooseFile(url) }
            case .failure(let error):
                // A panel that was dismissed is not a failure.
                guard (error as? CocoaError)?.code != .userCancelled else { return }
                AppModel.log("Choosing a backup file", failedWith: error)
            }
        }
    }

    /// Whether the backup cannot be chosen for now: a step runs, or the question about the invoice that is being
    /// written waits for its answer.
    private var choiceWaits: Bool {
        model.isWorking || model.asksToDiscard
    }

    // MARK: The backups

    private var choicesList: some View {
        ScrollView {
            VStack(spacing: 6) {
                ForEach(model.choices) { choice in
                    ChoiceRow(choice: choice, isChosen: model.selection == choice) {
                        Task { await model.select(choice) }
                    }
                }
                if model.choices.isEmpty {
                    Text("V tomto Macu zatím žádná záloha není.")
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 6)
                }
            }
            .padding(2)
        }
        .frame(maxHeight: 250)
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Zálohy")
        .disabled(choiceWaits)
    }

    private func summaryBox(_ summary: String) -> some View {
        SettingsBox(kind: .note) {
            Text(verbatim: summary)
            if let keyText = model.keyText {
                Text(verbatim: keyText)
                    .font(.callout)
            }
            Text("Současná data se nejdřív uloží jako záloha – nic se neztratí.")
                .font(.callout)
                .foregroundStyle(Color(.bannerText))
        }
    }

    private var footer: some View {
        HStack(spacing: 8) {
            Spacer()
            if model.isWorking {
                ProgressView()
                    .controlSize(.small)
            }
            Button("Zrušit", action: close)
                .buttonStyle(.bordered)
                .keyboardShortcut(.cancelAction)
                .disabled(model.isWorking)
            Button("Obnovit", action: restore)
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(!model.canRestore)
        }
        .buttonBorderShape(.capsule)
        .controlSize(.large)
    }

    /// Obnovit, and Return in the field of the code.
    private func restore() {
        Task {
            if await model.restore() {
                close()
            }
        }
    }
}

/// A backup to choose: when it was made, or the name of its file, and what it holds or what opens it. The chosen one is
/// tinted, and VoiceOver reads it as selected.
private struct ChoiceRow: View {
    let choice: BackupChoice
    let isChosen: Bool
    let choose: () -> Void

    var body: some View {
        Button(action: choose) {
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: choice.title)
                    .fontWeight(.semibold)
                Text(verbatim: choice.subtitle)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                isChosen ? Color.accentColor.opacity(0.12) : Color.secondary.opacity(0.08),
                in: RoundedRectangle(cornerRadius: 12)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(isChosen ? Color.accentColor : Color.secondary.opacity(0.2), lineWidth: isChosen ? 1.5 : 1)
            )
            .contentShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isChosen ? .isSelected : [])
    }
}
