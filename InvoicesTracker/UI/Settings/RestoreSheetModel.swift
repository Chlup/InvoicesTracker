import Foundation
import Observation

/// A backup to choose in the sheet Obnovit ze zálohy: a local backup of this Mac, or a file the person chose.
nonisolated struct BackupChoice: Identifiable, Hashable, Sendable {
    let url: URL
    let header: BackupHeader

    /// "Dnes 14:05" for a local backup, the name of the file for another one.
    let title: String

    /// "automatická záloha v tomto Macu · 13 faktur", or which code a file of another Mac needs.
    let subtitle: String

    /// Whether the backup is one of the local backups.
    let isLocal: Bool

    var id: URL {
        url
    }
}

/// The model of the sheet Obnovit ze zálohy while the data is open: the local backups newest first, another file
/// ("Jiný soubor…"), which code the chosen backup needs, and the restore itself.
///
/// Whether this Mac opens a backup without its code (`Vault.canOpenWithDevice(_:)`) is one round trip to the Secure
/// Enclave, so it is asked for the chosen backup only, never for every row of the list. A backup that this Mac does not
/// open asks for the code named by its label; one whose device slot does not open after all asks for it then.
///
/// The invoice editor works on the data that a restore replaces: when it holds changes, Obnovit asks "Zahodit
/// rozepsanou fakturu?" first (`asksToDiscard`), and the restore goes on only after Zahodit.
@MainActor
@Observable
final class RestoreSheetModel {
    /// What the sheet says when the local backups cannot be listed.
    nonisolated static let listFailureText = "Zálohy v tomto Macu se nepodařilo načíst."

    // MARK: State

    /// The local backups, newest first, and the file chosen with Jiný soubor… after them.
    private(set) var choices: [BackupChoice] = []

    /// The backup chosen, or nil.
    private(set) var selection: BackupChoice?

    /// Whether this Mac opens the chosen backup without its code; nil until that is known.
    private(set) var opensWithThisMac: Bool?

    /// Whether the code is asked for although this Mac took the backup for its own: its device slot did not open it.
    private(set) var asksForCode = false

    /// The recovery code as typed. What the last attempt said goes when it changes.
    var typed = "" {
        didSet {
            if typed != oldValue {
                errorText = nil
            }
        }
    }

    /// What went wrong with the last step, in Czech, or nil.
    private(set) var errorText: String?

    /// Whether a step runs.
    private(set) var isWorking = false

    private let app: AppModel
    private let security: SecurityTabModel

    init(app: AppModel, security: SecurityTabModel) {
        self.app = app
        self.security = security
    }

    // MARK: What the sheet shows

    /// Whether the code of the chosen backup is asked for.
    var needsCode: Bool {
        asksForCode || opensWithThisMac == false
    }

    /// The label of the code that opens the chosen backup, such as "kód č. 1 z 17. 10. 2026", when it carries one.
    var codeLabel: String? {
        selection.flatMap { WelcomeTexts.backupCodeLabel($0.header) }
    }

    /// The label of the field of the code, which names the code.
    var codeFieldLabel: String {
        WelcomeTexts.codeFieldLabel(for: codeLabel)
    }

    /// "Obnoví se stav ze zálohy „Dnes 14:05“."
    var summary: String? {
        selection.map { "Obnoví se stav ze zálohy „\($0.title)“." }
    }

    /// What opens the chosen backup: this Mac, or the code named — for a backup of another Mac, and for one whose device
    /// slot this Mac took for its own and could not open after all.
    var keyText: String? {
        guard selection != nil, opensWithThisMac != nil else { return nil }
        let code = codeLabel ?? "kód pro obnovení"
        if asksForCode {
            return "Klíč tohoto Macu tuhle zálohu neotevřel – odemkne ji \(code)."
        }
        if needsCode {
            return "Záloha vznikla na jiném Macu – odemkne ji \(code)."
        }
        return app.appSettings.touchIDUnlock
            ? "Otevře se přes Touch ID tohoto Macu, kód není potřeba." : "Otevře ji tento Mac, kód není potřeba."
    }

    /// "Kód nesedí – tahle záloha potřebuje kód č. 1 z 17. 10. 2026.": what a code that does not open the chosen backup
    /// says, naming the code it needs.
    nonisolated static func wrongCodeText(label: String?) -> String {
        "Kód nesedí – tahle záloha potřebuje \(label ?? "kód pro obnovení, který platil, když vznikla")."
    }

    /// Whether Obnovit can be pressed: a backup is chosen, its code is typed when it needs one, and no step of
    /// Zabezpečení a zálohy runs, whichever started it (`AppModel.securityStepRunning`).
    var canRestore: Bool {
        selection != nil && opensWithThisMac != nil && !isWorking && !app.securityStepRunning
            && (!needsCode || !RecoveryCode.normalize(typed).isEmpty)
    }

    /// Whether the question "Zahodit rozepsanou fakturu?" waits for an answer.
    var asksToDiscard: Bool {
        app.pendingDiscard == .restoreBackup
    }

    // MARK: Choosing

    /// Lists the local backups, newest first. A failure is logged and said in `errorText`.
    func load() {
        do {
            let today = app.today
            let timeZone = app.dependencies.timeZone()
            let local = try app.backups.localBackups().map {
                Self.choice(
                    for: $0.url, header: $0.header, isLocal: true, opensWithThisMac: true, today: today,
                    timeZone: timeZone)
            }
            choices = local + choices.filter { !$0.isLocal }
        } catch {
            AppModel.log("Listing the local backups", failedWith: error)
            errorText = Self.listFailureText
        }
    }

    /// Chooses `choice`, and finds out whether this Mac opens it without its code.
    func select(_ choice: BackupChoice) async {
        guard !isWorking else { return }
        selection = choice
        opensWithThisMac = nil
        asksForCode = false
        typed = ""
        errorText = nil
        let opens = await app.vault.canOpenWithDevice(choice.header)
        guard selection == choice else { return }
        opensWithThisMac = opens
    }

    /// Jiný soubor…: looks at the file at `url` that the person chose, adds it after the local backups and chooses it.
    /// A file that is no backup is said in `errorText`.
    func chooseFile(_ url: URL) async {
        guard !isWorking else { return }
        errorText = nil
        do {
            let inspected = try await app.inspectBackup(at: url)
            let choice = Self.choice(
                for: url, header: inspected.header, isLocal: false, opensWithThisMac: inspected.opensWithThisMac,
                today: app.today, timeZone: app.dependencies.timeZone())
            choices = choices.filter { $0.isLocal && $0.url != url } + [choice]
            selection = choice
            opensWithThisMac = inspected.opensWithThisMac
            asksForCode = false
            typed = ""
        } catch {
            AppModel.log("Looking at a backup file", failedWith: error)
            errorText = WelcomeTexts.errorText(error, codeLabel: nil, forBackup: true)
        }
    }

    /// The choice of the backup at `url` with `header`: a local backup by when it was made and what it holds, another
    /// file by its name and what opens it.
    nonisolated static func choice(
        for url: URL, header: BackupHeader, isLocal: Bool, opensWithThisMac: Bool, today: CivilDate,
        timeZone: TimeZone
    ) -> BackupChoice {
        if isLocal {
            return BackupChoice(
                url: url, header: header,
                title: SettingsTexts.backupTitle(header.created, today: today, timeZone: timeZone),
                subtitle: "automatická záloha v tomto Macu · " + WelcomeTexts.invoiceCount(header.invoiceCount),
                isLocal: true)
        }
        let subtitle =
            opensWithThisMac
            ? "soubor zálohy · otevře ho tento Mac"
            : "soubor z jiného Macu · potřebuje " + (WelcomeTexts.backupCodeLabel(header) ?? "kód pro obnovení")
        return BackupChoice(
            url: url, header: header, title: url.lastPathComponent, subtitle: subtitle, isLocal: false)
    }

    // MARK: Restoring

    /// Obnovit: restores the chosen backup in place of the data and returns true once it is done, for the sheet to
    /// close. With the invoice editor holding changes it asks "Zahodit rozepsanou fakturu?" first and returns false; the
    /// answer goes on with `discard()` and Obnovit again, or `keepEditing()`. A restore that fails returns false and
    /// says why in `errorText`; one whose device slot did not open asks for the code.
    func restore() async -> Bool {
        guard canRestore, let choice = selection else { return false }
        if app.editorHasChanges {
            app.choose(.restoreBackup)
            return false
        }
        isWorking = true
        errorText = nil
        defer { isWorking = false }
        do {
            try await security.restore(from: choice, code: needsCode ? typed : nil)
            return true
        } catch KeyError.wrongRecoveryCode where !needsCode {
            // This Mac's device key did not open the backup after all: its code is asked for.
            asksForCode = true
            return false
        } catch KeyError.wrongRecoveryCode, KeyError.malformedRecoveryCode {
            errorText = Self.wrongCodeText(label: codeLabel)
            return false
        } catch {
            AppModel.log("Restoring a backup", failedWith: error)
            errorText = WelcomeTexts.errorText(error, codeLabel: codeLabel, forBackup: true)
            return false
        }
    }

    /// Zahodit: the invoice that was being written goes, at once, so that the question is answered before the dialog
    /// that asked it closes. The restore goes on with `restore()`.
    func discard() {
        guard asksToDiscard else { return }
        app.confirmDiscard()
    }

    /// Pokračovat v úpravách: nothing is thrown away, and the window shows the editor.
    func keepEditing() {
        guard asksToDiscard else { return }
        app.cancelDiscard()
    }
}
