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
                    BackupChoiceRow(choice: choice, isChosen: model.selection == choice) {
                        Task { await model.select(choice) }
                    }
                }
                if model.choices.isEmpty {
                    Text("V tomto Macu zatím žádná záloha není.")
                        .font(Typography.body)
                        .foregroundStyle(Palette.text2)
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

    /// What the chosen backup restores and what opens it, on the inset background, and that nothing is lost: the data
    /// that is open is saved as a backup first.
    private func summaryBox(_ summary: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(verbatim: summary)
                .font(Typography.body)
                .foregroundStyle(Palette.text)
            if let keyText = model.keyText {
                Text(verbatim: keyText)
                    .font(Typography.callout)
                    .foregroundStyle(Palette.text2)
            }
            Text("Současná data se nejdřív uloží jako záloha – nic se neztratí.")
                .font(Typography.callout)
                .foregroundStyle(Palette.greenText)
        }
        .fixedSize(horizontal: false, vertical: true)
        .insetPanel(horizontal: 14, vertical: 12)
    }

    /// Zrušit and Obnovit, 32 points tall as the buttons of a dialog are: Zrušit on the grey fill, Obnovit in the
    /// accent.
    private var footer: some View {
        HStack(spacing: 8) {
            Spacer()
            if model.isWorking {
                ProgressView()
                    .controlSize(.small)
            }
            Button("Zrušit", action: close)
                .buttonStyle(CapsuleButtonStyle(.secondary))
                .keyboardShortcut(.cancelAction)
                .disabled(model.isWorking)
            Button("Obnovit", action: restore)
                .buttonStyle(CapsuleButtonStyle(.primary))
                .keyboardShortcut(.defaultAction)
                .disabled(!model.canRestore)
        }
        .padding(.top, 4)
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
/// on the pale blue of a selection with a ring of the accent 1,5 points wide, the others on the inset background with a
/// hairline ring; VoiceOver reads the chosen one as selected.
struct BackupChoiceRow: View {
    let choice: BackupChoice
    let isChosen: Bool
    let choose: () -> Void

    var body: some View {
        Button(action: choose) {
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: choice.title)
                    .font(Typography.bodySemibold)
                    .foregroundStyle(Palette.text)
                Text(verbatim: choice.subtitle)
                    .font(Typography.callout)
                    .foregroundStyle(Palette.text2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                isChosen ? Palette.accentTint : Palette.bgInset,
                in: RoundedRectangle(cornerRadius: DesignMetrics.panelRadius)
            )
            .overlay(
                RoundedRectangle(cornerRadius: DesignMetrics.panelRadius)
                    .strokeBorder(isChosen ? Palette.accent : Palette.fill, lineWidth: isChosen ? 1.5 : 1)
            )
            .contentShape(RoundedRectangle(cornerRadius: DesignMetrics.panelRadius))
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isChosen ? .isSelected : [])
    }
}
