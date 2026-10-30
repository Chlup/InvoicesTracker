import Foundation
import Observation

/// The model of Nastavení › Zabezpečení a zálohy: unlocking with Touch ID and the lock after inactivity, the recovery
/// code in force and a new one, and the backups — in this Mac, outside it, now, exported, and restored in place of the
/// data.
///
/// Every change of the keys, restore and backup says its result in the green banner of Nastavení. One that fails says
/// so in a short line on the card it was started from (`failure`), and changes nothing; a prompt of Touch ID that was
/// dismissed says nothing. The steps of the sheets (a new code, a restore) throw, and their sheets say what went wrong.
/// One step at a time across the app: while one runs (`isWorking`), whichever tab, sheet or command of the menu started
/// it, the tab starts no other, and one asked for meanwhile is refused as busy.
@MainActor
@Observable
final class SecurityTabModel {
    /// The card a failure is said on.
    enum Place: Hashable, Sendable {
        /// Odemykání.
        case unlocking

        /// Zálohy.
        case backups
    }

    /// A failure and the card it is said on.
    struct Failure: Equatable, Sendable {
        var place: Place
        var text: String
    }

    /// What a failure says when there is nothing particular to say of it.
    nonisolated static let genericFailure = WelcomeTexts.genericError

    // MARK: State

    /// What the last step that failed says, until the next one starts.
    private(set) var failure: Failure?

    /// Whether a step of Zabezpečení a zálohy runs: one this tab started, or one started before it was shown again
    /// (`AppModel.securityStepRunning`).
    var isWorking: Bool {
        app.securityStepRunning
    }

    /// The choice of Touch ID while the change it asks for is being made, so that the checkbox shows it meanwhile.
    private(set) var touchIDChoice: Bool?

    /// The recovery slot in force, which names the code: its number and the day it was made. Nil while the data is
    /// locked.
    private(set) var code: RecoverySlot?

    private let app: AppModel

    init(app: AppModel) {
        self.app = app
    }

    /// Reads which code is in force. The tab calls this whenever it loads again, and each step that changes the code
    /// calls it when it has.
    func load() {
        code = app.vault.keys?.newestRecoverySlot
    }

    // MARK: Odemykání

    /// Whether opening the app asks for Touch ID.
    var touchIDOn: Bool {
        touchIDChoice ?? app.appSettings.touchIDUnlock
    }

    /// The checkbox Odemykat přes Touch ID: it shows the choice at once, while the change is made (`setTouchID(_:)`).
    func chooseTouchID(_ on: Bool) {
        guard !isWorking, on != touchIDOn else { return }
        touchIDChoice = on
        Task { await setTouchID(on) }
    }

    /// Odemykat přes Touch ID: this Mac's key of the data is made anew with or without Touch ID, and a backup is made.
    func setTouchID(_ on: Bool) async {
        guard on != app.appSettings.touchIDUnlock else {
            touchIDChoice = nil
            return
        }
        touchIDChoice = on
        failure = nil
        defer { touchIDChoice = nil }
        do {
            let result = try await app.setTouchID(on)
            app.showBanner(
                Self.touchIDText(on: on, backupMade: result.outcome.backupMade)
                    + offMacFailure(result.offMacBackupMade))
        } catch {
            fail(on: .unlocking, error)
        }
    }

    /// "Odemykání přes Touch ID je zapnuté. Klíč tohoto Macu je nový a záloha je uložená."
    nonisolated static func touchIDText(on: Bool, backupMade: Bool) -> String {
        "Odemykání přes Touch ID je \(on ? "zapnuté" : "vypnuté"). Klíč tohoto Macu je nový"
            + (backupMade ? " a záloha je uložená." : ", zálohu se ale nepodařilo uložit.")
    }

    // MARK: Zamknout při nečinnosti

    /// After how long without activity the app locks. It stays as chosen while Touch ID is off, for when it is on
    /// again.
    var idleLock: IdleLockTime {
        app.appSettings.idleLock
    }

    /// Whether the menu Zamknout při nečinnosti can be used: only while the app is unlocked with Touch ID, as the lock
    /// asks for the same as the launch. Without it the app does not lock.
    var canChooseIdleLock: Bool {
        touchIDOn
    }

    /// What the row of the menu says under it: what the lock does, that the app asks only at the launch (Nikdy), or
    /// that it does not lock without Touch ID.
    var idleLockNote: String {
        guard canChooseIdleLock else { return "Bez odemykání přes Touch ID se aplikace nezamyká." }
        guard idleLock != .never else {
            return "Aplikace se zeptá jen při spuštění a pak zůstane odemčená, dokud ji neukončíte."
        }
        return "Zamčená aplikace skryje všechna data. Po odemčení budete tam, kde jste skončili – i s rozepsanou"
            + " fakturou."
    }

    /// Zamknout při nečinnosti: the app locks after `time` without activity from now on. Only the settings change: the
    /// data gets no new key, and no backup is made. The banner says it. Does nothing without Touch ID, and for the time
    /// that is chosen already.
    func setIdleLock(_ time: IdleLockTime) async {
        guard canChooseIdleLock, time != idleLock else { return }
        failure = nil
        do {
            try await app.changeAppSettings { $0.idleLock = time }
            app.showBanner(Self.idleLockText(time))
        } catch {
            fail(on: .unlocking, error)
        }
    }

    /// "Aplikace se zamkne po 10 minutách nečinnosti.", or for Nikdy that only the launch asks: the banner of a new
    /// time.
    nonisolated static func idleLockText(_ time: IdleLockTime) -> String {
        guard let after = time.afterText else {
            return "Aplikace se po nečinnosti nezamyká – Touch ID nebo heslo chce jen při spuštění."
        }
        return "Aplikace se zamkne \(after) nečinnosti."
    }

    // MARK: Kód pro obnovení

    /// "č. 1 · vytvořen 17. 10. 2026": the code in force, as its card names it.
    var codeCaption: String {
        guard let code else { return "—" }
        return "č. \(code.number) · vytvořen \(CzechFormat.date(code.created))"
    }

    /// The label of the code in force, such as "kód č. 1 z 17. 10. 2026".
    var codeLabel: String? {
        code?.label
    }

    /// Which code the backups made before the code in force need, once a new code has replaced one: "Zálohy vytvořené
    /// do 18. 10. 2026 (i v Time Machine) dál otevře jen kód č. 1 z 17. 10. 2026." Nil while the first code is in
    /// force, and when the settings name a code that is not the one just before the code in force (they came back with
    /// a restored backup of another time).
    var olderBackupsText: String? {
        let settings = app.appSettings
        guard let code, let replaced = settings.replacedRecoveryCodeLabel,
            settings.replacedRecoveryCodeNumber == code.number - 1
        else {
            return nil
        }
        return "Zálohy vytvořené do \(CzechFormat.date(code.created)) (i v Time Machine) dál otevře jen \(replaced)."
    }

    /// Vytvořit nový kód in the sheet: the new code to show, numbered after the one in force and dated today. Nothing
    /// changes until `commitNewCode(_:)`; a sheet that is closed before that leaves the code in force as it is. Throws
    /// `VaultError.locked` while the data is locked.
    func createNewCode() throws -> PendingRecoveryCode {
        try app.vault.prepareNewRecoveryCode()
    }

    /// Hotovo in the sheet, once the person has stored the new code: the data gets a new key, the new code is in force
    /// and a backup is made. Throws `VaultError.busy` while another step runs, and what the vault throws
    /// (`failureText(_:)` says it); nothing changes then, unless the vault locked the data, and then the app locks.
    func commitNewCode(_ pending: PendingRecoveryCode) async throws {
        failure = nil
        let result = try await app.commitNewRecoveryCode(pending)
        load()
        app.showBanner(
            Self.newCodeText(number: pending.number, outcome: result.outcome) + offMacFailure(result.offMacBackupMade))
    }

    /// "Platí nový kód č. 2. Data dostala nový klíč a záloha je uložená. Starší zálohy otevře kód č. 1 z …"
    nonisolated static func newCodeText(number: Int, outcome: NewCodeOutcome) -> String {
        "Platí nový kód č. \(number). Data dostala nový klíč"
            + (outcome.backupMade ? " a záloha je uložená." : ", zálohu se ale nepodařilo uložit.")
            + (outcome.previousLabel.isEmpty ? "" : " Starší zálohy otevře \(outcome.previousLabel).")
    }

    /// "Nahradí kód č. 1 z 17. 10. 2026": the line under the title of the sheet of a new code.
    nonisolated static func newCodeSubtitle(replacing label: String) -> String {
        "Nahradí " + label
    }

    /// What the sheet of a new code explains before the code is made.
    nonisolated static func newCodeIntro(replacing label: String) -> String {
        "Data dostanou nový klíč a hned se uloží záloha. Současná data pak otevře jen nový kód – \(label) je přestane"
            + " otevírat."
    }

    /// The warning of the sheet of a new code about the backups made with the code it replaces.
    nonisolated static func newCodeWarning(replacing label: String) -> String {
        "Zálohy vytvořené do dneška (i v Time Machine) dál otevře jen \(label). Starý kód proto zatím nezahazujte."
    }

    // MARK: Zálohy

    /// The last local backup: "poslední dnes 14:05", or "zatím žádná".
    var localBackupValue: String {
        app.appSettings.lastLocalBackup.map { "poslední " + moment($0) } ?? "zatím žádná"
    }

    /// The name of the folder of the backups outside the Mac, or nil while none is set.
    var offMacFolderName: String? {
        guard app.appSettings.backupFolderBookmark != nil else { return nil }
        return app.appSettings.backupFolderName ?? ""
    }

    /// The last backup outside the Mac: "poslední dnes 14:05", "zatím žádná", or "nenastaveno" while no folder is set.
    var offMacValue: String {
        guard offMacFolderName != nil else { return "nenastaveno" }
        return app.appSettings.lastOffMacBackup.map { "poslední " + moment($0) } ?? "zatím žádná"
    }

    /// Whether the folder of the backups outside the Mac has a backup yet: until then its "zatím žádná" is a warning.
    var hasOffMacBackup: Bool {
        app.appSettings.lastOffMacBackup != nil
    }

    /// Whether the backups outside the Mac have failed for 30 days, or the folder has had none for 30 days since it was
    /// chosen.
    var showsOffMacReminder: Bool {
        app.needsOffMacReminder
    }

    /// The local backups, for Zobrazit ve Finderu.
    var localBackupsFolder: URL {
        app.vault.paths.backups
    }

    /// "InvoicesTracker 2026-10-17.ttbackup": the name the save panel of an export proposes. It has the day alone, so it
    /// is never taken for one of the app's own backups, which a pruning could delete.
    var exportFileName: String {
        "InvoicesTracker \(app.today.iso).ttbackup"
    }

    /// Zálohovat teď: a local backup at once, and one outside the Mac when a folder is set.
    func backupNow() async {
        failure = nil
        do {
            let outcome = try await app.backUpNow()
            app.showBanner(Self.backedUpText(moment: moment(outcome.created), folder: offMacFolderName, outcome: outcome))
        } catch {
            fail(on: .backups, error)
        }
    }

    /// "Záloha uložena dnes 15:20 v tomto Macu." and the folder outside the Mac when there is one.
    nonisolated static func backedUpText(moment: String, folder: String?, outcome: BackupNowOutcome) -> String {
        let made = "Záloha uložena \(moment)"
        switch (outcome.offMac, folder) {
        case (true?, let folder?):
            return made + " – v tomto Macu i do \(folder)."
        case (false?, let folder?):
            return made + " v tomto Macu." + offMacFailureText(folder: folder)
        default:
            return made + " v tomto Macu."
        }
    }

    /// " Do iCloud Drive › InvoicesTracker ji uložit nešlo – zkontrolujte, že je složka dostupná.": what a banner adds
    /// when the backup outside the Mac that a step made too failed.
    nonisolated static func offMacFailureText(folder: String) -> String {
        " Do \(folder) ji uložit nešlo – zkontrolujte, že je složka dostupná."
    }

    /// What the banner of a change of the keys adds of the backup outside the Mac that followed it: nothing when it was
    /// made or when no folder is set.
    private func offMacFailure(_ made: Bool?) -> String {
        guard made == false else { return "" }
        return Self.offMacFailureText(folder: offMacFolderName ?? "")
    }

    /// Exportovat zálohu…: one backup to `file`, which the person chose in the save panel.
    func exportBackup(to file: URL) async {
        failure = nil
        do {
            try await app.exportBackup(to: file)
            let folder = FileManager.default.displayName(
                atPath: file.deletingLastPathComponent().path(percentEncoded: false))
            app.showBanner(
                Self.exportedText(fileName: file.lastPathComponent, folder: folder, codeLabel: codeLabel))
        } catch {
            fail(on: .backups, error)
        }
    }

    /// "Záloha uložena jako „InvoicesTracker 2026-10-17.ttbackup“ do složky „Stažené soubory“. Otevře ji tento Mac nebo
    /// kód č. 1 z 17. 10. 2026."
    nonisolated static func exportedText(fileName: String, folder: String, codeLabel: String?) -> String {
        "Záloha uložena jako „\(fileName)“ do složky „\(folder)“. Otevře ji tento Mac nebo "
            + (codeLabel ?? "kód pro obnovení") + "."
    }

    /// Vybrat složku… / Změnit složku…: `folder`, chosen in the panel, takes the backups outside the Mac, and the first
    /// one is made there at once.
    func chooseBackupFolder(_ folder: URL) async {
        failure = nil
        do {
            let made = try await app.setBackupFolder(folder)
            let name = offMacFolderName ?? folder.lastPathComponent
            app.showBanner(
                "Zálohy se budou ukládat i do \(name). "
                    + (made ? "První je hotová." : "První se zatím uložit nepodařilo – zkontrolujte, že je složka dostupná."))
        } catch {
            fail(on: .backups, error)
        }
    }

    /// Obnovit in the sheet: restores the backup of `choice` in place of the data, with `code` when the backup needs
    /// one. The banner says what was restored and, when the data opens with another code now, which one. Throws
    /// `VaultError.busy` while another step runs, and what the restore throws (`AppModel.restoreWhileOpen`); the sheet
    /// says it.
    func restore(from choice: BackupChoice, code: String?) async throws {
        failure = nil
        let outcome = try await app.restoreWhileOpen(from: choice.url, recoveryCode: code, title: choice.title)
        load()
        app.showBanner(Self.restoredText(title: choice.title, outcome: outcome, keptFolder: offMacFolderName))
    }

    /// "Data jsou obnovená ze zálohy „Dnes 14:05“. Předchozí stav je uložený jako záloha." and, when the restored data
    /// opens with another code than the data before, which one, with the offer of a new code; and when the backup had
    /// another folder of the backups outside the Mac, that this Mac keeps its own, `keptFolder`, or none.
    nonisolated static func restoredText(title: String, outcome: RestoreOutcome, keptFolder: String?) -> String {
        var text = "Data jsou obnovená ze zálohy „\(title)“. Předchozí stav je uložený jako záloha."
        if outcome.codeChanged, let label = outcome.codeLabel {
            text += " Obnovená data otevírá \(label) – pokud ho nemáte po ruce, vytvořte nový kód."
        }
        if outcome.backupHadAnotherFolder {
            if let keptFolder {
                text += " Zálohy mimo tento Mac se dál ukládají do \(keptFolder), ne do složky ze zálohy."
            } else {
                text += " Složku pro zálohy mimo tento Mac aplikace ze zálohy nepřevzala."
            }
        }
        return text
    }

    // MARK: Helpers

    /// What the tab and the sheets say of `error`, or nil for a prompt of Touch ID that was dismissed.
    nonisolated static func failureText(_ error: any Error) -> String? {
        WelcomeTexts.errorText(error, codeLabel: nil, forBackup: false)
    }

    /// Says on `place` that a step failed with `error`, and logs it.
    private func fail(on place: Place, _ error: any Error) {
        AppModel.log("A step of the tab of security and backups", failedWith: error)
        failure = Self.failureText(error).map { Failure(place: place, text: $0) }
    }

    /// "dnes 14:05", or "15. 10. 2026 18:40": a moment of a backup in the time zone of the Mac.
    private func moment(_ instant: Date) -> String {
        SettingsTexts.backupMoment(instant, today: app.today, timeZone: app.dependencies.timeZone())
    }
}
