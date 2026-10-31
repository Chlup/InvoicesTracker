import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// Nastavení › Zabezpečení a zálohy: unlocking with Touch ID and the time of the lock after inactivity, the recovery
/// code in force with Vytvořit nový kód…, and the backups — in this Mac, outside it, Zálohovat teď, Exportovat zálohu…
/// and Obnovit ze zálohy…. The commands of the menu with the same names come here and run the same steps
/// (`AppModel.settingsAction`).
struct SecurityTab: View {
    let app: AppModel
    @State private var model: SecurityTabModel
    @State private var showsNewCode = false
    @State private var showsRestore = false

    /// What a backup file is called by the panels: the extension alone, which needs no declaration of a type.
    static let backupType = UTType(filenameExtension: "ttbackup", conformingTo: .data) ?? .data

    init(app: AppModel) {
        self.app = app
        _model = State(initialValue: SecurityTabModel(app: app))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DesignMetrics.cardSpacing) {
            if let notice = app.securityNotice {
                Note(.attention, icon: .warning, text: notice) {
                    closeNoticeButton
                }
            }
            AdaptiveColumns(minimumColumnWidth: 440, spacing: DesignMetrics.cardSpacing) {
                unlockingCard
                codeCard
            }
            backupsCard
        }
        .task(id: app.reloadKey) {
            model.load()
        }
        .onChange(of: app.settingsAction, initial: true) { _, action in
            // What the form of the uniform rate of Rok is asked is left for that tab.
            guard let action, action != .enterUniformRate else { return }
            app.settingsAction = nil
            // One step at a time, and one sheet: a command that comes while a step runs or a sheet is open waits for
            // nothing and does nothing.
            guard !model.isWorking, !showsNewCode, !showsRestore else { return }
            switch action {
            case .restoreBackup:
                showsRestore = true
            case .exportBackup:
                // Not in the middle of the update that brought the request.
                DispatchQueue.main.async { exportBackup() }
            case .enterUniformRate:
                break
            }
        }
        .sheet(isPresented: $showsNewCode) {
            NewRecoveryCodeSheet(model: model) {
                showsNewCode = false
            }
            .sheetChrome()
        }
        .sheet(isPresented: $showsRestore) {
            RestoreSheet(app: app, security: model) {
                showsRestore = false
            }
            .sheetChrome()
        }
    }

    private var closeNoticeButton: some View {
        Button("Zavřít") {
            app.securityNotice = nil
        }
        .settingsCardButton()
    }

    // MARK: Odemykání

    private var unlockingCard: some View {
        Card(title: "Odemykání") {
            Toggle(isOn: Binding(get: { model.touchIDOn }, set: { model.chooseTouchID($0) })) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Odemykat přes Touch ID")
                        .font(Typography.bodySemibold)
                        .foregroundStyle(Palette.text)
                    Text("Aplikace se zeptá na Touch ID nebo heslo k Macu při spuštění a po nečinnosti.")
                        .font(Typography.callout)
                        .foregroundStyle(Palette.text2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .toggleStyle(.checkbox)
            .disabled(model.isWorking)
            Hairline()
            idleLockRow
            Text(
                """
                Data jsou zašifrovaná vždy; klíč k nim chrání Secure Enclave tohoto Macu. Zapnutí nebo vypnutí \
                Touch ID dá datům nový klíč a hned uloží zálohu.
                """
            )
            .font(Typography.callout)
            .foregroundStyle(Palette.text3)
            .fixedSize(horizontal: false, vertical: true)
            if let failure = model.failure, failure.place == .unlocking {
                SettingsFailureLine(text: failure.text)
            }
        }
    }

    /// Zamknout při nečinnosti: the menu of the times, and under it what the lock does, that the app asks only at the
    /// launch (Nikdy), or, with the menu disabled, that the app does not lock without Touch ID.
    private var idleLockRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .center, spacing: 12) {
                // The menu carries the same name for VoiceOver.
                Text("Zamknout při nečinnosti")
                    .font(Typography.bodySemibold)
                    .foregroundStyle(model.canChooseIdleLock ? Palette.text : Palette.text4)
                    .accessibilityHidden(true)
                Spacer(minLength: 8)
                Picker("Zamknout při nečinnosti", selection: idleLockChoice) {
                    ForEach(IdleLockTime.allCases, id: \.self) { time in
                        Text(verbatim: time.label)
                            .tag(time)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .fixedSize()
                .disabled(!model.canChooseIdleLock)
            }
            Text(verbatim: model.idleLockNote)
                .font(Typography.callout)
                .foregroundStyle(Palette.text2)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// The time chosen in the menu, saved as it is chosen (`SecurityTabModel.setIdleLock(_:)`).
    private var idleLockChoice: Binding<IdleLockTime> {
        Binding(
            get: { model.idleLock },
            set: { time in
                Task { await model.setIdleLock(time) }
            }
        )
    }

    // MARK: Kód pro obnovení

    private var codeCard: some View {
        Card(title: "Kód pro obnovení") {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text("Platný kód")
                    .font(Typography.body)
                    .foregroundStyle(Palette.text2)
                Spacer(minLength: 8)
                Text(verbatim: model.codeCaption)
                    .font(Typography.bodySemibold)
                    .foregroundStyle(Palette.text)
            }
            .accessibilityElement(children: .combine)
            Text(
                """
                Otevře data na jiném Macu, po opravě tohoto Macu nebo ze zálohy. Aplikace ho znovu neukáže – když ho \
                ztratíte, vytvořte nový, dokud data ještě otevřete.
                """
            )
            .font(Typography.callout)
            .foregroundStyle(Palette.text3)
            .fixedSize(horizontal: false, vertical: true)
            if let olderBackups = model.olderBackupsText {
                Text(verbatim: olderBackups)
                    .font(Typography.callout)
                    .foregroundStyle(Palette.text2)
                    .fixedSize(horizontal: false, vertical: true)
                    .insetPanel(horizontal: 12, vertical: 10)
            }
            Button("Vytvořit nový kód…") {
                showsNewCode = true
            }
            .settingsCardButton()
            .disabled(model.isWorking || model.code == nil)
        }
    }

    // MARK: Zálohy

    private var backupsCard: some View {
        Card(
            title: "Zálohy", subtitle: "Šifrované – otevře je tento Mac, nebo kód pro obnovení platný v době zálohy",
            spacing: 6
        ) {
            VStack(alignment: .leading, spacing: 0) {
                backupRow(
                    "V tomto Macu",
                    detail: "šifrovaná kopie nejvýš jednou za hodinu po změně · uchovává se 30 posledních",
                    value: model.localBackupValue, valueColor: Palette.text, action: "Zobrazit ve Finderu",
                    perform: showLocalBackups)
                if let folder = model.offMacFolderName {
                    backupRow(
                        "Mimo tento Mac", detail: "\(folder) · jednou denně, uchovává se 30 posledních",
                        value: model.offMacValue,
                        valueColor: model.hasOffMacBackup ? Palette.greenText : Palette.orangeText,
                        action: "Změnit složku…", perform: chooseFolder)
                } else {
                    backupRow(
                        "Mimo tento Mac", detail: "externí disk, NAS nebo iCloud Drive", value: model.offMacValue,
                        valueColor: Palette.orangeText, action: "Vybrat složku…", perform: chooseFolder)
                }
            }
            if model.offMacFolderName == nil {
                Note(
                    .attention, icon: .warning,
                    text: """
                        Zálohy jsou zatím jen v tomto Macu. Když Mac přestane fungovat, pomůže jen záloha jinde – \
                        vyberte složku na externím disku, NAS nebo v iCloud Drive. Aplikace tam jednou denně uloží \
                        šifrovanou zálohu.
                        """
                )
                .padding(.top, 4)
            } else if model.showsOffMacReminder {
                Note(
                    .attention, icon: .warning,
                    text: """
                        Mimo tento Mac se už 30 dní nepodařilo uložit zálohu. Připojte disk se zvolenou složkou, nebo \
                        vyberte jinou.
                        """
                )
                .padding(.top, 4)
            }
            Text("Time Machine zálohuje i data aplikace. S kódem pro obnovení z ní obnovíte data i na novém Macu.")
                .font(Typography.callout)
                .foregroundStyle(Palette.text3)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 4)
            if let failure = model.failure, failure.place == .backups {
                SettingsFailureLine(text: failure.text)
            }
            Hairline()
                .padding(.top, 6)
            HStack(spacing: 8) {
                Button("Zálohovat teď") {
                    Task { await model.backupNow() }
                }
                Button("Exportovat zálohu…", action: exportBackup)
                Button("Obnovit ze zálohy…") {
                    showsRestore = true
                }
                if model.isWorking {
                    ProgressView()
                        .controlSize(.small)
                }
            }
            .settingsCardButton()
            .disabled(model.isWorking)
            .padding(.top, 6)
        }
    }

    /// A row of a place of the backups under a hairline: its name and what is kept there, the last backup, and what can
    /// be done there.
    private func backupRow(
        _ title: String, detail: String, value: String, valueColor: Color, action: String,
        perform: @escaping () -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Hairline()
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(verbatim: title)
                        .font(Typography.bodySemibold)
                        .foregroundStyle(Palette.text)
                    Text(verbatim: detail)
                        .font(Typography.callout)
                        .foregroundStyle(Palette.text3)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
                VStack(alignment: .trailing, spacing: 4) {
                    Text(verbatim: value)
                        .font(Typography.bodySemibold)
                        .foregroundStyle(valueColor)
                    Button(action, action: perform)
                        .settingsCardLink()
                        .disabled(model.isWorking)
                }
            }
            .padding(.vertical, 10)
        }
    }

    // MARK: Panels

    /// Zobrazit ve Finderu: the newest local backup selected in Finder, or the folder of the backups when there is none
    /// or they cannot be listed, which is logged.
    private func showLocalBackups() {
        var newest: URL?
        do {
            newest = try app.backups.localBackups().first?.url
        } catch {
            AppModel.log("Listing the local backups", failedWith: error)
        }
        if let newest {
            NSWorkspace.shared.activateFileViewerSelecting([newest])
        } else {
            NSWorkspace.shared.open(model.localBackupsFolder)
        }
    }

    /// Vybrat složku… / Změnit složku…: the panel of a folder, and the folder chosen in it for the backups outside the
    /// Mac.
    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Vybrat"
        panel.message = "Vyberte složku na externím disku, NAS nebo v iCloud Drive."
        guard panel.runModal() == .OK, let folder = panel.url else { return }
        Task { await model.chooseBackupFolder(folder) }
    }

    /// Exportovat zálohu…: the save panel, with the name of the day, and the export to the file chosen in it.
    private func exportBackup() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = model.exportFileName
        panel.allowedContentTypes = [Self.backupType]
        panel.canCreateDirectories = true
        panel.isExtensionHidden = false
        guard panel.runModal() == .OK, let file = panel.url else { return }
        Task { await model.exportBackup(to: file) }
    }
}
