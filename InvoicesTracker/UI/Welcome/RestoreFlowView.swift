import SwiftUI
import UniformTypeIdentifiers

/// Restoring a backup before the data is open: the backup file is chosen, shown on a card with the code that opens it,
/// and opened with that code — or without one, when this Mac opens it itself. The data of the backup is then open, and
/// the card that says so replaces this one (`AppModel.completion`).
///
/// The screen that offered the restore is what Zpět goes back to: `back` shows it again.
struct RestoreFlowView: View {
    let model: AppModel

    /// Zpět on the first step.
    let back: () -> Void

    /// The backup that was chosen and looked at, until another one is chosen.
    @State private var backup: InspectedBackup?

    /// Whether the code of the backup is asked for. Only a backup that this Mac does not open itself needs it.
    @State private var asksForCode = false

    @State private var typed = ""
    @State private var showsImporter = false
    @State private var isDropTarget = false
    @State private var runner = StepRunner()

    /// What a backup file is called by the panel: the extension alone, which needs no declaration of a type.
    private static let backupType = UTType(filenameExtension: "ttbackup", conformingTo: .data) ?? .data

    var body: some View {
        if let backup, asksForCode {
            codeStep(for: backup)
        } else {
            pickStep
        }
    }

    // MARK: Choosing the file

    private var pickStep: some View {
        WelcomeCard(label: "Obnovit ze zálohy") {
            WelcomeHeading(
                title: "Obnovit ze zálohy",
                text: """
                    Vyberte soubor zálohy InvoicesTracker (.ttbackup). Záloha je šifrovaná – odemkne ji kód pro \
                    obnovení, který platil, když vznikla.
                    """
            )
            if let backup {
                BackupFileCard(backup: backup, timeZone: model.dependencies.timeZone()) {
                    self.backup = nil
                    typed = ""
                    runner.errorText = nil
                }
            } else {
                dropZone
            }
            if let errorText = runner.errorText {
                WelcomeErrorLine(text: errorText)
            }
            WelcomeFooter(
                backTitle: "Zpět", back: back, backIsCancel: true, isWorking: runner.isWorking, goTitle: "Pokračovat",
                goDisabled: backup == nil
            ) {
                guard let backup else { return }
                proceed(with: backup)
            }
        }
        .fileImporter(isPresented: $showsImporter, allowedContentTypes: [Self.backupType]) { result in
            switch result {
            case .success(let url):
                choose(url)
            case .failure(let error):
                // A panel that was dismissed is not a failure.
                guard (error as? CocoaError)?.code != .userCancelled else { return }
                Task { await runner.perform { throw error } }
            }
        }
    }

    /// "Vybrat soubor zálohy…": the button that opens the panel, which a file can also be dropped on. It is the zone of
    /// the design: the accent tint with a ring of the soft accent, rounded as a panel is, and the ring in the accent
    /// itself while a file is over it.
    private var dropZone: some View {
        Button {
            showsImporter = true
        } label: {
            VStack(spacing: 6) {
                Image(systemName: "doc")
                    .font(Typography.symbolLight)
                    .foregroundStyle(Palette.accent)
                    .accessibilityHidden(true)
                Text("Vybrat soubor zálohy…")
                    .font(Typography.bodySemibold)
                    .foregroundStyle(Palette.text)
                Text("nebo ho sem přetáhněte")
                    .font(Typography.callout)
                    .foregroundStyle(Palette.text2)
            }
            .padding(.vertical, 30)
            .padding(.horizontal, 16)
            .frame(maxWidth: .infinity)
            .modifier(DropZoneLook(isTargeted: isDropTarget))
        }
        .buttonStyle(.plain)
        .disabled(runner.isWorking)
        .dropDestination(for: URL.self) { urls, _ in
            // Only a file: a link dragged from a browser is no backup.
            guard let url = urls.first(where: \.isFileURL) else { return false }
            choose(url)
            return true
        } isTargeted: {
            isDropTarget = $0
        }
    }

    /// Looks at the file that was chosen, or dropped, and shows it on the card. A file that is no backup is told so.
    private func choose(_ url: URL) {
        Task {
            await runner.perform {
                backup = try await model.inspectBackup(at: url)
            }
        }
    }

    /// Pokračovat: a backup that this Mac opens itself is restored now, asking only for Touch ID or the password when
    /// the device key needs it; any other asks for its code.
    private func proceed(with backup: InspectedBackup) {
        guard backup.opensWithThisMac else {
            asksForCode = true
            return
        }
        Task {
            await runner.perform(codeLabel: WelcomeTexts.backupCodeLabel(backup.header), forBackup: true) {
                do {
                    try await model.restoreAtWelcome(from: backup.url, recoveryCode: nil)
                } catch KeyError.wrongRecoveryCode {
                    // The device key of this Mac did not open the backup after all: its code is asked for.
                    asksForCode = true
                }
            }
        }
    }

    // MARK: The code

    /// "Odemkněte zálohu": the code that was valid when the backup was made, named, and the restore with it.
    private func codeStep(for backup: InspectedBackup) -> some View {
        let label = WelcomeTexts.backupCodeLabel(backup.header)
        return WelcomeCard(label: "Odemknout zálohu") {
            RecoveryCodeAsk(
                title: "Odemkněte zálohu",
                text: "Záloha je zašifrovaná. Odemkne ji kód pro obnovení, který platil, když záloha vznikla.",
                fieldLabel: WelcomeTexts.codeFieldLabel(for: label), typed: $typed, errorText: runner.errorText,
                isWorking: runner.isWorking, backTitle: "Zpět",
                back: {
                    typed = ""
                    runner.errorText = nil
                    asksForCode = false
                },
                backIsCancel: true,
                submitTitle: "Odemknout zálohu",
                submit: {
                    Task {
                        await runner.perform(codeLabel: label, forBackup: true) {
                            try await model.restoreAtWelcome(from: backup.url, recoveryCode: typed)
                        }
                    }
                }
            ) {
                EmptyView()
            }
        }
        // What the last attempt said is about the code that was typed then.
        .onChange(of: typed) { runner.errorText = nil }
    }
}

/// The card of the backup file that was chosen: its name, when and where it was made, what it holds, and which code
/// opens it (`WelcomeTexts.backupCard`), with the way to choose another file.
struct BackupFileCard: View {
    let backup: InspectedBackup

    /// The time zone of the Mac, which the time of the backup is shown in.
    let timeZone: TimeZone

    /// Vybrat jiný soubor.
    let chooseAnother: () -> Void

    var body: some View {
        let lines = WelcomeTexts.backupCard(
            backup.header, fileName: backup.url.lastPathComponent, opensWithThisMac: backup.opensWithThisMac,
            timeZone: timeZone)
        WelcomeBox(spacing: 4, horizontalPadding: 16, verticalPadding: 14) {
            Text(lines[0])
                .font(Typography.bodySemibold)
                .foregroundStyle(Palette.text)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
            ForEach(Array(lines.dropFirst().enumerated()), id: \.offset) { index, line in
                Text(line)
                    .font(Typography.callout)
                    // The last line, which names the code, is the one the next step is about.
                    .foregroundStyle(index == lines.count - 2 ? Palette.text : Palette.text2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Button("Vybrat jiný soubor", action: chooseAnother)
                .calloutLink()
                .padding(.top, 4)
        }
    }
}
