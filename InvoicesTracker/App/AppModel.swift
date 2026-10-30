import Foundation
import Observation
import SystemConfiguration
import os

// MARK: - What the window shows

/// What the window shows: the full-window states before the data is open, and the app itself once it is.
nonisolated enum AppPhase: Equatable, Sendable {
    /// The app has just started and looks at what there is.
    case starting

    /// There is no data yet: the person starts with empty data or restores a backup.
    case welcome

    /// A step of the start with empty data.
    case onboarding(OnboardingStep)

    /// The data is there, and the Touch ID or password prompt did not unlock it.
    case locked

    /// The device key of this Mac does not open the data (the data came from another Mac, the Mac was repaired, the
    /// slot is damaged): only the recovery code opens it.
    case newMac

    /// The files of the data do not belong together, or the data cannot be opened. The text says why, in Czech.
    case damaged(String)

    /// The data was saved by a newer version of the app than this one: it opens in that version or a newer one, and
    /// nothing else helps.
    case newerVersion

    /// The data is open.
    case ready
}

/// A step of the start with empty data.
nonisolated enum OnboardingStep: Equatable, Sendable {
    /// The recovery code to store, with its label, such as "kód č. 1 z 17. 10. 2026", and the number and the day of the
    /// code that the label is made of, for the caption of the step. Nothing is on disk until the person has stored it.
    case recoveryCode(code: String, label: String, number: Int, created: CivilDate)

    /// The supplier's details printed on the invoices.
    case supplier

    /// The offer to import the invoices from Fakturoid.
    case importOffer
}

/// A green banner with the result of an action, at the top of the screen it belongs to.
nonisolated struct AppBanner: Equatable, Sendable {
    var text: String
    var screen: Screen
}

/// What the data a screen shows depends on. A screen loads again whenever it changes.
nonisolated struct ReloadKey: Hashable, Sendable {
    var year: Int

    /// The reporting cutoff (`AppModel.asOf`).
    var asOf: CivilDate

    /// The real today. The cutoff stays the same for the whole month, but what has been received, the statuses of the
    /// invoices and the prediction follow the day, so the screens load again when it changes.
    var today: CivilDate

    /// Changes with every write of the data.
    var dataVersion: Int
    var search: String
}

/// What the invoice editor is asked to show.
nonisolated enum EditorRequest: Equatable, Sendable {
    /// The choice between a blank invoice and a template.
    case chooser

    /// A new invoice: blank, or from the template with this id. A blank one starts with the client with `clientID`
    /// (Nová faktura on the row of a client in Odběratelé) rather than with the first client.
    case new(templateID: Int64?, clientID: Int64? = nil)

    /// The invoice with this id.
    case edit(Int64)
}

// MARK: - App model

/// The heart of the app: what the window shows, the open data, the reporting cutoff with the years to choose from, and
/// what follows every write.
///
/// - The phase goes from the launch through the first launch, the recovery code or unlocking to `.ready`, where the
///   data is open (`database`) and the refresh keeps it current.
/// - The screens show the selected year with the invoices issued up to the reporting cutoff (`asOf`), the last day of
///   the current month for the current year, and the money received up to the real today (`receivedThrough`). Each
///   loads only what it shows from `database`, again whenever `reloadKey` changes, and calls `didWrite()` after it has
///   written to it, which reloads the screens and starts the backups that are due.
/// - `vault` opens the data and changes its keys, and `backups` makes the backups.
@MainActor
@Observable
final class AppModel {
    // MARK: State

    private(set) var phase = AppPhase.starting

    /// The screen of the window. A banner of another screen closes when it changes. The invoice editor does not: it is
    /// shown in the place of Faktury, and is there as it was left when the window comes back to Faktury.
    var screen = Screen.overview {
        didSet {
            if let banner, banner.screen != screen {
                self.banner = nil
            }
        }
    }

    /// The tab of Nastavení. The banner of Nastavení belongs to the tab it came from and closes when another tab is
    /// chosen.
    var settingsTab = SettingsTab.application {
        didSet {
            if settingsTab != oldValue, banner?.screen == .settings {
                banner = nil
            }
        }
    }

    /// What a command of the menu asked Nastavení › Zabezpečení a zálohy to do, until the tab does it.
    var settingsAction: SettingsAction?

    /// Whether a step of Zabezpečení a zálohy runs: a backup now, an export, a folder outside the Mac, a change of the
    /// keys with the backups that follow it, or a restore. One at a time across the app, whichever screen, sheet or
    /// command of the menu asks for it (`runSecurityStep(_:)`).
    private(set) var securityStepRunning = false

    /// What Nastavení › Zabezpečení a zálohy says, until it is closed, of a change of the keys or a restore that a lock
    /// cut off: what it left in force, once the data is open again.
    var securityNotice: String?

    /// The change of the keys or the restore that failed after the vault had locked the data, until the next unlock
    /// of the same data says what it left in force (`settle(_:in:)`). Any other data that is opened forgets it.
    @ObservationIgnored var interruptedChange: InterruptedChange?

    /// The reporting cutoff: the selected year and the day the invoices issued up to are reported as of. For the
    /// current year it is the last day of the real current month, kept up automatically (`AsOfState`). It is not today.
    private(set) var asOf: AsOfState

    /// The real today in the time zone of the Mac. It decides what has been received, the statuses of the invoices and
    /// the prediction, and the dates a new invoice starts with.
    private(set) var today: CivilDate

    /// The day the money of the year shown counts as received by: the reporting cutoff, but never a day after the real
    /// today in the current year, as an invoice issued later this month is no money received yet and a payment or an
    /// adjustment dated later is not income yet.
    var receivedThrough: CivilDate {
        asOf.asOf.year == today.year ? min(asOf.asOf, today) : asOf.asOf
    }

    /// The years to choose from, newest first: those with data and the current year, never one after it.
    private(set) var years: [Int]

    /// The text of the search of Faktury.
    var searchText = ""

    /// How many times Hledat (⌘F) has asked Faktury to focus its search field. The screen focuses the field whenever
    /// this grows.
    private(set) var searchFocusRequests = 0

    /// Whether a sheet or a dialog of Faktury is open: the payment of an invoice, its deletion or its PDF. The screen
    /// says so, because the commands of the menu cannot see the state of a screen.
    var invoiceSheetOpen = false

    /// The invoice whose deletion the window asks to confirm, in a dialog inside it over Faktury (`windowDialog`), or
    /// nil. Faktury asks for it, and it goes when Faktury does.
    var invoiceDeletion: InvoiceDeletionRequest?

    /// Grows with every write of the data, so that the screens load again.
    private(set) var dataVersion = 0

    /// What the screens load their data for.
    var reloadKey: ReloadKey {
        ReloadKey(year: asOf.year, asOf: asOf.asOf, today: today, dataVersion: dataVersion, search: searchText)
    }

    /// The banner of the latest action, until it is closed, the next banner comes or the screen changes.
    var banner: AppBanner?

    /// The year that finished when the reporting cutoff followed today into a new year, for Přehled to say so. The
    /// banner is told to VoiceOver when it comes (`announceWhenUnlocked(_:)`), once, not each time Přehled shows it.
    var newYearBanner: Int? {
        didSet {
            if let year = newYearBanner, year != oldValue {
                announceWhenUnlocked(NewYearBanner.text(finishedYear: year))
            }
        }
    }

    /// A year whose uniform rate was not found by 31 March of the next year: it has to be entered by hand. The reminder
    /// is told to VoiceOver when it comes (`announceWhenUnlocked(_:)`), and is read again from what the refresh keeps
    /// at every launch (`restoreUniformRateReminder(from:)`).
    var uniformRateReminderYear: Int? {
        didSet {
            if let year = uniformRateReminderYear, year != oldValue {
                announceWhenUnlocked(UniformRateReminderBanner.text(year: year))
            }
        }
    }

    /// Tells VoiceOver `text`, when a change of state asks for it. A test replaces it with one that records. The models
    /// tell VoiceOver through `announceWhenUnlocked(_:)`, which holds back what comes while the app is locked after
    /// inactivity.
    @ObservationIgnored var announce: @MainActor (String) -> Void = { VoiceOverAnnouncement.post($0) }

    // The lock after inactivity, which `AppModel+IdleLock.swift` checks.

    /// Whether the app is locked after inactivity (`checkIdleLock(now:)`), until the person proves who they are with
    /// Touch ID or the password of the Mac (`unlockAfterIdle()`). It locks the screen alone: the data stays open under
    /// it, and so do the screens, the sheets and what is typed in them, while the import, the downloads of the rates
    /// and the backups go on. What the app would show or say by itself waits for the unlock: the sheet of the uniform
    /// rate and what VoiceOver is told of a change.
    private(set) var isIdleLocked = false

    /// When the person was last active in the app's windows (`noteActivity(at:)`), or opened or unlocked the app: the
    /// lock after inactivity counts from it. It changes with every move of the pointer, so no view observes it.
    @ObservationIgnored private(set) var lastActivity: Date

    /// Whether an open or save panel of the system is up (`IdleActivityMonitor.modalPanelIsUp()`): the lock after
    /// inactivity does not come while one is, as it shows files, not the data, and the person may work in it without
    /// the app seeing it. An alert does not hold the lock off. A test replaces it.
    @ObservationIgnored var modalPanelIsUp: @MainActor () -> Bool = { IdleActivityMonitor.modalPanelIsUp() }

    /// Posted, with the app model as its object, as the app is about to lock after inactivity, before anything has
    /// followed the lock: a window notes where its keyboard focus is, to give it back once the app is unlocked
    /// (`IdleLockCover`).
    nonisolated static let idleLockWillCome = Notification.Name("InvoicesTracker.AppModel.idleLockWillCome")

    /// Cancels the print panel of a recovery code (`RecoveryCodePrinter.cancelPanel()`) as the app locks after
    /// inactivity: the panel shows the code, and stays above any window. The person prints again once the app is
    /// unlocked. It is called at the lock itself rather than by the window, which follows the lock only at its next
    /// update, and an app-modal panel may hold that update back. A test replaces it.
    @ObservationIgnored var cancelPrintPanel: @MainActor () -> Void = { RecoveryCodePrinter.cancelPanel() }

    /// Closes a menu that is open as the app locks after inactivity (`OpenMenu.close()`), without choosing anything in
    /// it: it would stay above the lock, with what it lists, and a choice in it would act under the lock. A test
    /// replaces it.
    @ObservationIgnored var closeOpenMenu: @MainActor () -> Void = { OpenMenu.shared.close() }

    /// The uniform rates whose sheet came while the app was locked after inactivity (`offerUniformRate(_:)`): it opens
    /// once the app is unlocked, if the rates still wait for the person then.
    @ObservationIgnored var uniformRateOfferAfterUnlock: GFRFinding?

    /// What VoiceOver was to be told while the app was locked after inactivity, in order: it is told once the app is
    /// unlocked.
    @ObservationIgnored private var heldAnnouncements: [String] = []

    /// Whether Touch ID or the password is being asked for to unlock the app after inactivity: another Odemknout asks
    /// nothing more meanwhile.
    @ObservationIgnored private var unlockingAfterIdle = false

    /// The timer of the next check of the lock after inactivity while the checks run, kept up to date by
    /// `AppModel+IdleLock.swift`.
    @ObservationIgnored var idleCheckWake: (any RefreshCancellable)?

    /// What the notification centers keep of the observations of the wakes of the Mac and of the changes of its clock,
    /// made when the checks of the lock after inactivity first start (`AppModel+IdleLock.swift`).
    @ObservationIgnored var idleCheckObservations: [any NSObjectProtocol] = []

    /// The progress of an import that runs, such as "3/12", for the sidebar.
    var importBadge: String?

    /// Whether the section "Kdy čekám faktury" of Odhad odvodů is unfolded, and whether its group "Ostatní odběratelé"
    /// is. Both start folded and stay as the person left them while the app runs, whichever screen is shown and
    /// whichever year; neither is stored.
    var predictionMonthsOpen = false
    var predictionOthersOpen = false

    /// Uniform rates that were found and wait for the person to confirm them.
    var pendingUniformRate: GFRFinding?

    /// The uniform rates that the open sheet asks the person to confirm, or nil while no such sheet is open. The sheet
    /// opens when the refresh finds the rates; when the person puts it off, the rates stay in `pendingUniformRate` and
    /// the sheet comes again when the refresh finds them anew.
    var uniformRateOffer: GFRFinding?

    /// How the year shown converts its income in other currencies (`fxState(year:)`), as last read
    /// (`loadShownYearFX()`), for what the window says of it. Nil until it is read, and when it cannot be.
    private(set) var shownYearFX: YearFXState?

    /// How many reads of `shownYearFX` have started. Only the latest may show its result.
    @ObservationIgnored private var shownYearFXLoads = 0

    /// The latest conversion of payments asked for: a choice of how a year converts its income in other currencies, new
    /// ČNB rates, a uniform rate stored or removed, payments that changed, or the stand-ins of an earlier version. The
    /// next conversion waits for it, so that they run one at a time (`convertPaymentsInTurn(_:)`), which alone sets it.
    @ObservationIgnored var latestConversion: Task<Void, Never>?

    /// The model of the Import screen. The app holds it, not the screen, so that an import goes on and its progress is
    /// there to see while other screens are shown. Other data gets a new one (`adopt(_:)`).
    @ObservationIgnored lazy var importModel = ImportModel(app: self)

    /// The model of the Simulátor screen. The app holds it, not the screen, so that what was entered for a simulation
    /// stays while other screens are shown. Other data gets a new one (`adopt(_:)`), and so does a lock of the data
    /// (`lockAfterFailedChange(_:)`).
    @ObservationIgnored lazy var simulatorModel = SimulatorModel(app: self)

    /// What the invoice editor is asked to show, or nil when it is closed. The chooser opens over an editor that is
    /// open and leaves it where it is (`requestBeforeChooser`): choosing replaces it, and Zrušit shows it again. The
    /// editor itself goes when there is no request for one any more.
    var editorRequest: EditorRequest? {
        didSet {
            guard editorRequest != oldValue else { return }
            if editorRequest == .chooser {
                if let oldValue, oldValue != .chooser {
                    requestBeforeChooser = oldValue
                }
            } else {
                requestBeforeChooser = nil
            }
            if shownEditorRequest == nil {
                releaseEditor()
                pendingDiscard = nil
            }
        }
    }

    /// The editor the chooser is open over, which stays on the screen under it, or nil when the chooser is not open
    /// over one.
    private(set) var requestBeforeChooser: EditorRequest?

    /// How many new invoices the editor was asked for (`startNewInvoice(templateID:)`). A new invoice is a new editor,
    /// even when it asks for what the editor under the chooser asked for.
    var editorGeneration = 0

    /// The editor of the invoice that `shownEditorRequest` asks for, once it has been read (`openEditor()`). The app
    /// holds it, not the window: it stays while the window shows other screens, and when the window is closed and
    /// opened again. Kept up to date by `AppModel+Editor.swift`.
    var editor: InvoiceEditorModel?

    /// Why there is no editor for the request that is shown, when there is none: the invoice was deleted meanwhile, or
    /// could not be read. Kept up to date by `AppModel+Editor.swift`.
    var editorProblem: String?

    /// What the person chose that would throw away the invoice they are writing, until they answer the question
    /// "Zahodit rozepsanou fakturu?" (`confirmDiscard()` and `cancelDiscard()`).
    var pendingDiscard: DiscardCause?

    /// What the editor, or the problem in its place, was made for. Kept up to date by `AppModel+Editor.swift`.
    @ObservationIgnored var openedEditorKey: EditorKey?

    /// The invoice whose detail Faktury opens next.
    var pendingDetailInvoiceID: Int64?

    /// The choices of the person for the app, as stored in the open data; the defaults until the data is open.
    private(set) var appSettings = AppSettings()

    /// The card that follows unlocking with the recovery code or restoring a backup, until Pokračovat dismisses it
    /// (`dismissCompletion()`): the window shows it in place of the app, whose phase is `.ready` meanwhile.
    private(set) var completion: UnlockCompletion?

    /// The open data, or nil while it is locked.
    var database: Database?

    let dependencies: AppDependencies
    let vault: Vault
    let backups: BackupService

    /// The refresh of the open data, or nil while it is locked. It runs only when `dependencies.startsRefresh`.
    private(set) var refresh: RefreshCoordinator?

    /// One daily-rate loader shares fetches across prediction loads for the current vault and real day.
    @ObservationIgnored let predictionRateLoader = PredictionRateLoader()

    /// The screens that save typed input a moment after the last key, which a quit waits for (`flushUnsavedInput()`).
    let quitFlushes = QuitFlushes()

    /// The start with empty data whose code is shown, until the data is made. It lives only in memory.
    @ObservationIgnored private var pendingFreshStart: PendingFreshStart?

    /// The phase the start with empty data came from, which Zpět on the code step shows again.
    @ObservationIgnored private var phaseBeforeFreshStart = AppPhase.welcome

    /// Whether the data of the start with empty data is being made.
    @ObservationIgnored private var makingFreshData = false

    /// Whether `launch()` ran.
    @ObservationIgnored private var launched = false

    /// The years with data, the oldest first, as last read from the database.
    @ObservationIgnored private var yearsWithData: [Int] = []

    // What the backups keep in memory, kept up to date by `AppModel+Backups.swift`.

    /// How many writes of the open data the screens told of (`didWrite()`), and how many of them the local backups hold
    /// for certain: those told of before the latest backup started.
    @ObservationIgnored var changeCount = 0
    @ObservationIgnored var changesBackedUp = 0

    /// The one wake that makes the local backup a change waits for, once its hour is up.
    @ObservationIgnored var localBackupWake: (any RefreshCancellable)?

    /// Whether a local backup is being made.
    @ObservationIgnored var makingLocalBackup = false

    /// The backup outside the Mac that is being made, whose result tells whether it was made; nil while none is. A
    /// backup there that cannot be skipped — after a change of the keys, of Zálohovat teď, or the first one in a new
    /// folder — waits for it to end and is then made anew (`backUpOffMac(afterTheRunningOne:)`).
    @ObservationIgnored var offMacBackupRun: Task<Bool, Never>?

    /// The backup outside the Mac that a wait gave up on (`offMacWaitLimit`) while it runs: nothing waits for it again
    /// until it ends.
    @ObservationIgnored var abandonedOffMacRun: Task<Bool, Never>?

    /// When the latest automatic backup outside the Mac failed, while no backup there has been made since: the next
    /// automatic one waits `offMacRetryInterval` after it. Kept in memory, so a launch tries again once.
    @ObservationIgnored var offMacAutomaticFailure: Date?

    /// The backups the writes started (`didWrite()`), which the writes do not wait for: each waits for the ones before
    /// it, so this one ends when all of them have. Only tests wait for it.
    @ObservationIgnored var backupsAfterWrite: Task<Void, Never>?

    /// What the Touch ID or password prompt gives as the reason when the app opens the data.
    static let unlockReason = "odemknout data InvoicesTracker"

    private nonisolated static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "InvoicesTracker", category: "App")

    init(dependencies: AppDependencies) {
        self.dependencies = dependencies
        let backups = BackupService(
            backupsDirectory: dependencies.paths.backups, clock: dependencies.clock, appVersion: Self.appVersion,
            deviceName: Self.deviceName, resolveBookmark: dependencies.resolveBookmark)
        self.backups = backups
        vault = Vault(
            paths: dependencies.paths, device: dependencies.device, backups: backups, clock: dependencies.clock)
        let today = CivilDate.today(now: dependencies.clock.now(), timeZone: dependencies.timeZone())
        self.today = today
        asOf = AsOfState.launch(today: today)
        years = [today.year]
        lastActivity = dependencies.clock.now()
    }

    // MARK: Launch and unlocking

    /// Opens what there is, once: the welcome when there is no data, the damaged screen when its files do not belong
    /// together, and otherwise the data, unlocked with the device key of this Mac (see `unlockWithDevice()`). The app
    /// starts on the current year, as of today. It also registers the fonts of the invoice page, except in a test.
    func launch() async {
        guard !launched else { return }
        launched = true
        if !AppEnvironment.isRunningTests {
            // The fonts of the invoice page, which no screen can show before the data is open. A test that needs them
            // registers them itself.
            InvoiceFonts.register()
        }
        today = currentDay()
        asOf = AsOfState.launch(today: today)
        years = Self.years(withData: yearsWithData, currentYear: today.year)
        switch vault.launchState() {
        case .firstLaunch:
            phase = .welcome
        case .damaged(let text):
            phase = .damaged(text)
        case .existing:
            await unlockWithDevice()
        }
    }

    /// Unlocks the data with the device key of this Mac, which asks for Touch ID or the password when it is on, and
    /// shows the app. A prompt that did not unlock leaves the app locked, a device key that does not open the data asks
    /// for the recovery code, and files that cannot be opened show the damaged screen.
    func unlockWithDevice() async {
        do {
            let change = interruptedChange
            let database = try await vault.unlockWithDevice(reason: Self.unlockReason)
            await open(database, interrupted: change)
        } catch KeyError.userCancelled {
            phase = .locked
        } catch KeyError.deviceKeyUnusable {
            phase = .newMac
        } catch VaultError.busy, VaultError.alreadyOpen {
            // Another step is opening the data, or it is open: that step shows what follows.
        } catch {
            Self.log("Unlocking with the device key", failedWith: error)
            phase = phaseAfterFailedOpening(error)
        }
    }

    /// Unlocks the data with the recovery code, where the device key of this Mac does not open it, and shows the app,
    /// behind the card that says so (`completion`); from then on the device key of this Mac opens it. Data that a newer
    /// version of the app saved shows the advice to update the app (`.newerVersion`), as at a launch. Throws
    /// `KeyError.malformedRecoveryCode` for text that is not a code and `KeyError.wrongRecoveryCode` for a code that
    /// does not open the data, and what else unlocking throws; nothing changes then.
    func unlock(recoveryCode: String) async throws {
        let change = interruptedChange
        let database: Database
        do {
            database = try await vault.unlockWithRecoveryCode(recoveryCode)
        } catch let error as SchemaError {
            guard case .newerThanApp = error else { throw error }
            Self.log("Unlocking with the recovery code", failedWith: error)
            phase = phaseAfterFailedOpening(error)
            return
        }
        await open(
            database, completing: UnlockCompletion(kind: .unlocked, codeLabel: vault.requiredRecoveryLabel),
            interrupted: change)
    }

    /// Restores the backup at `url` before the data is open — at the welcome, or where the data cannot be opened — and
    /// shows the app with the restored data, behind the card that says what was opened (`completion`). Data that is
    /// there and locked is set aside, not replaced. `recoveryCode` is needed for a backup that the device key of this
    /// Mac does not open. Does nothing for data that a newer version of the app saved (`.newerVersion`): only that
    /// version opens them, and nothing here sets them aside. Throws what `Vault.restore` throws.
    func restoreAtWelcome(from url: URL, recoveryCode: String?) async throws {
        guard phase != .newerVersion else { return }
        let (header, database) = try await Self.withSecurityScopedAccess(to: url) {
            (try vault.inspectBackup(url), try await vault.restore(from: url, recoveryCode: recoveryCode))
        }
        let completion = UnlockCompletion.restored(
            from: header, codeLabel: vault.requiredRecoveryLabel, in: dependencies.timeZone())
        await open(database, completing: completion, afterRestore: true)
    }

    /// Pokračovat on the card after unlocking with the recovery code or restoring a backup: the window shows the app.
    func dismissCompletion() {
        completion = nil
    }

    /// Odemknout kódem pro obnovení… on the locked screen: the screen of a Mac that does not know the data asks for the
    /// recovery code, which opens the data from there (`unlock(recoveryCode:)`). Does nothing in another phase.
    func useRecoveryCode() {
        guard phase == .locked else { return }
        phase = .newMac
    }

    // MARK: Starting with empty data

    /// The first step of a start with empty data: a new recovery code, shown with its label. Nothing is written until
    /// `finishRecoveryCodeStep(touchID:)`, and `cancelFreshStart()` goes back to the phase this came from: the welcome,
    /// or the screen of data this Mac cannot open. Does nothing for data that a newer version of the app saved
    /// (`.newerVersion`), which empty data would set aside. Throws `VaultError.alreadyOpen` while the data is open.
    func startFresh() async throws {
        guard phase != .newerVersion else { return }
        let pending = try vault.prepareFreshStart()
        if !isOnCodeStep {
            phaseBeforeFreshStart = phase
        }
        pendingFreshStart = pending
        phase = .onboarding(
            .recoveryCode(code: pending.code, label: pending.label, number: pending.number, created: pending.created))
    }

    /// Makes the data of the start with empty data once the person has stored its code, unlocked with Touch ID when
    /// `touchID` (the choice on the code step), and goes on to the supplier. Data that is there and cannot be opened is
    /// set aside, not replaced. When this throws, the code step stays with the same code, which can be confirmed
    /// again. Does nothing outside the code step.
    func finishRecoveryCodeStep(touchID: Bool) async throws {
        guard isOnCodeStep, !makingFreshData, let pending = pendingFreshStart else { return }
        makingFreshData = true
        defer { makingFreshData = false }
        let database = try await vault.startFresh(pending, touchID: touchID)
        pendingFreshStart = nil
        await adopt(database)
        phase = .onboarding(.supplier)
    }

    /// Zpět on the code step: the code is forgotten, and the phase the start came from is shown again. Nothing was
    /// written, so nothing changes on disk. Does nothing outside the code step, or while the data is being made.
    func cancelFreshStart() {
        guard isOnCodeStep, !makingFreshData else { return }
        pendingFreshStart = nil
        phase = phaseBeforeFreshStart
    }

    private var isOnCodeStep: Bool {
        if case .onboarding(.recoveryCode) = phase {
            return true
        }
        return false
    }

    /// Saves the supplier and, when given, the account for its currency (crowns), and goes on to the offer to import.
    /// An account of that currency that is there is replaced; the others stay. Throws `VaultError.locked` while the
    /// data is locked, and what the database throws; the step stays then.
    func saveSupplierStep(_ supplier: Supplier, czkAccount: BankAccount?) async throws {
        guard let database else { throw VaultError.locked }
        try await database.saveSupplier(supplier)
        if let czkAccount {
            var accounts = try await database.bankAccounts()
            if let index = accounts.firstIndex(where: { $0.currency == czkAccount.currency }) {
                accounts[index] = czkAccount
            } else {
                accounts.append(czkAccount)
            }
            try await database.saveBankAccounts(accounts)
        }
        await didWrite()
        if phase == .onboarding(.supplier) {
            phase = .onboarding(.importOffer)
        }
    }

    /// Goes on from the supplier step to the offer to import without saving a supplier. Does nothing on another step.
    func skipSupplierStep() {
        guard phase == .onboarding(.supplier) else { return }
        phase = .onboarding(.importOffer)
    }

    /// Ends the start with empty data from the offer to import and shows the app: Import when `importNow`, otherwise
    /// Přehled. Does nothing on another step.
    func finishOnboarding(importNow: Bool) {
        guard phase == .onboarding(.importOffer), database != nil else { return }
        screen = importNow ? .importer : .overview
        enterApp()
    }

    // MARK: Opening the data

    /// Takes the data the vault has just opened and shows the app on it, behind the card `completion` when there is
    /// one: it is set together with the phase, so that the app is never on screen before it. A change that an earlier
    /// session left waiting for the local backup is backed up when its hour is up, or the wake for it is armed; the
    /// backup outside the Mac is made when it is due, as an automatic one (`backUpOffMacIfDue(automatic:)`) unless the
    /// data is open `afterRestore`, which the person asked for.
    ///
    /// `change` is a change of the keys or a restore that a lock cut off, when this is the unlock of the same data:
    /// Nastavení › Zabezpečení a zálohy then says what it left in force (`settle(_:in:)`). Any other data that is
    /// opened forgets such a change without a word.
    ///
    /// Payments that earlier versions stored as stand-ins for a uniform rate are converted last
    /// (`convertUniformStandIns()`), after the backups, so that the backup outside the Mac goes as it would without
    /// them.
    func open(
        _ database: Database, completing completion: UnlockCompletion? = nil,
        interrupted change: InterruptedChange? = nil, afterRestore: Bool = false
    ) async {
        var notice: String?
        if let change {
            notice = await settle(change, in: database)
        }
        await adopt(database)
        await restoreUniformRateReminder(from: database)
        securityNotice = notice
        self.completion = completion
        enterApp()
        if notice != nil {
            showSettings(.security)
        }
        await backUpLocallyIfDue()
        await backUpOffMacIfDue(automatic: !afterRestore)
        await convertUniformStandIns()
    }

    /// Takes the data the vault has just opened, `database`: its settings and the years it has. Settings or years that
    /// cannot be read are logged, and the defaults and the current year stand in; the screens then show what they
    /// cannot read themselves. What waited for the local backup of other data is forgotten, and so are what Nastavení
    /// said of a change of the keys of the data before, a failed backup outside the Mac of that data and how its year
    /// shown converted its income. What waited for the unlock after inactivity is of the data before, and goes too.
    private func adopt(_ database: Database) async {
        self.database = database
        importModel = ImportModel(app: self)
        simulatorModel = SimulatorModel(app: self)
        uniformRateOffer = nil
        uniformRateOfferAfterUnlock = nil
        heldAnnouncements = []
        shownYearFX = nil
        securityNotice = nil
        interruptedChange = nil
        changeCount = 0
        changesBackedUp = 0
        offMacAutomaticFailure = nil
        cancelLocalBackupWake()
        do {
            take(try await database.appSettings())
        } catch {
            Self.log("Reading the settings", failedWith: error)
            appSettings = AppSettings()
        }
        yearsWithData = []
        await reloadYears()
    }

    /// Shows the app on the data that is open: "today" brought up to the clock (the data may have been locked over
    /// midnight), the lock after inactivity counting from now and checked when the app checks it, and a new refresh of
    /// the data, started when the app runs one. A lock after inactivity that is on stays on: a restore that ends under
    /// it opens the data here too.
    private func enterApp() {
        let day = currentDay()
        if day != today {
            handleDayChanged(day)
        }
        phase = .ready
        lastActivity = dependencies.clock.now()
        startIdleChecks()
        refresh?.stop()
        refresh = database.map { makeRefresh(for: $0) }
        if dependencies.startsRefresh {
            refresh?.start()
        }
    }

    /// Shows the locked screen after the vault locked the data in the middle of `change`, which failed (a restore whose
    /// database could not be put in place or opened, a new recovery code whose rekey failed): the refresh stops and the
    /// data is let go, with what was entered in the Simulátor, and unlocking opens what is on disk, as after a launch,
    /// and says what `change` left in force. The locked screen takes the place of a lock after inactivity, and asks for
    /// Touch ID or the password itself.
    func lockAfterFailedChange(_ change: InterruptedChange) {
        interruptedChange = change
        refresh?.stop()
        refresh = nil
        stopIdleChecks()
        endIdleLock()
        cancelLocalBackupWake()
        editorRequest = nil
        completion = nil
        database = nil
        // The inputs of a simulation, its children's names and days of birth among them, go with the data.
        simulatorModel = SimulatorModel(app: self)
        phase = .locked
    }

    /// What to show when the data did not open with `error`, after what there is on disk: the welcome when the files
    /// are gone, what the vault says about files that do not belong together, the advice to update the app for data of
    /// a newer version, and otherwise the damaged screen with why the data could not be opened.
    private func phaseAfterFailedOpening(_ error: any Error) -> AppPhase {
        switch vault.launchState() {
        case .firstLaunch:
            return .welcome
        case .damaged(let text):
            return .damaged(text)
        case .existing:
            if let error = error as? SchemaError, case .newerThanApp = error {
                return .newerVersion
            }
            return .damaged("Data se nepodařilo otevřít.")
        }
    }

    // MARK: The lock after inactivity

    /// The person did something in the app's windows at `date` (`IdleActivityMonitor`): the lock after inactivity
    /// counts from it. Activity that comes when the time is up already does not count: the check that was due locks the
    /// app first (`checkIdleLock(now:)`), as when the person comes back to a Mac that has just woken, or to an app
    /// whose timer waited in the background, before the check ran. Nothing counts while the app is locked: only
    /// unlocking does.
    func noteActivity(at date: Date) {
        guard !isIdleLocked else { return }
        checkIdleLock(now: date)
        if !isIdleLocked {
            lastActivity = date
        }
    }

    /// Locks the app after inactivity when it is due at `now` (`IdleLockRule`): the data is open, unlocking with Touch
    /// ID is on, and the time chosen in Nastavení has passed since the latest activity. The data, the models and the
    /// phase stay as they are; the windows are told just before (`idleLockWillCome`), the print panel of a recovery
    /// code is cancelled (`cancelPrintPanel`), a menu that is open closes (`closeOpenMenu`), and the windows cover the
    /// rest. While an open or save panel is up, the app does not lock, and the panel counts as activity: the time
    /// counts from now. A latest activity after `now`, which a clock set back leaves, counts as now too. The timer of
    /// the checks and the wakes of the Mac check it (`startIdleChecks()`), and so does activity (`noteActivity(at:)`).
    /// Does nothing while the app is locked.
    func checkIdleLock(now: Date) {
        guard !isIdleLocked else { return }
        if lastActivity > now {
            lastActivity = now
        }
        let outcome = IdleLockRule.outcome(
            phase: phase, touchIDUnlock: appSettings.touchIDUnlock, time: appSettings.idleLock,
            lastActivity: lastActivity, now: now, modalPanelIsUp: modalPanelIsUp())
        switch outcome {
        case .nothing:
            break
        case .panelCountsAsActivity:
            lastActivity = now
        case .lock:
            NotificationCenter.default.post(name: Self.idleLockWillCome, object: self)
            isIdleLocked = true
            cancelPrintPanel()
            closeOpenMenu()
        }
    }

    /// Odemknout on the card of the lock after inactivity: asks for Touch ID or the password of the Mac
    /// (`AppDependencies.authenticator`), and for nothing else — the data is open, and nothing is opened again or gets
    /// a new key. Once the person has proved who they are, the app is as it was left, the lock counts from now again,
    /// and what waited for the unlock follows: the sheet of the uniform rate, while its rates still wait for the
    /// person, and what VoiceOver was to be told. A prompt that is dismissed or fails leaves the app locked, and so
    /// does a lock of the data meanwhile, whose locked screen asks itself. Another Odemknout while the prompt is up
    /// asks nothing.
    func unlockAfterIdle() async {
        guard isIdleLocked, !unlockingAfterIdle else { return }
        unlockingAfterIdle = true
        let proven = await dependencies.authenticator.authenticate(reason: Self.unlockReason)
        unlockingAfterIdle = false
        guard proven, isIdleLocked else { return }
        isIdleLocked = false
        lastActivity = dependencies.clock.now()
        if let offer = uniformRateOfferAfterUnlock {
            uniformRateOfferAfterUnlock = nil
            if pendingUniformRate == offer {
                uniformRateOffer = offer
            }
        }
        let held = heldAnnouncements
        heldAnnouncements = []
        for text in held {
            announce(text)
        }
    }

    /// After how long without activity the app locks, as the locked screen of a launch can tell before the data is
    /// open: the time the app keeps outside the data (`AppDependencies.idleLockMirror`), or the default while it has
    /// kept none yet.
    var idleLockBeforeOpening: IdleLockTime {
        dependencies.idleLockMirror.read() ?? AppSettings().idleLock
    }

    /// Tells VoiceOver `text` (`announce`), or, while the app is locked after inactivity, once it is unlocked:
    /// VoiceOver would read out what the lock hides.
    func announceWhenUnlocked(_ text: String) {
        if isIdleLocked {
            heldAnnouncements.append(text)
        } else {
            announce(text)
        }
    }

    /// Ends the lock after inactivity without an unlock, as the data locks: the locked screen of the data asks for
    /// Touch ID or the password itself, and what waited for the unlock is about the data that is let go.
    private func endIdleLock() {
        isIdleLocked = false
        uniformRateOfferAfterUnlock = nil
        heldAnnouncements = []
    }

    // MARK: Years and the reporting cutoff

    /// Shows year `y`: the current year as of the last day of the current month, following it, and any other year as of
    /// its last day.
    func selectYear(_ y: Int) {
        let wasFollowing = asOf.followsToday
        asOf.selectYear(y, today: today)
        followingChanged(from: wasFollowing)
    }

    /// Shows day `d` of the selected year (a day outside it is moved to its first or last day). The last day of the
    /// current month follows the automatic cutoff again; any other day stops following it. Nothing in the window picks
    /// a day any more, the tests and the internal API do.
    func pickAsOf(_ d: CivilDate) {
        let wasFollowing = asOf.followsToday
        asOf.pick(d, today: today)
        followingChanged(from: wasFollowing)
    }

    /// Returns to the automatic cutoff: the current year as of the last day of the current month, following it.
    func goToday() {
        let wasFollowing = asOf.followsToday
        asOf.goToday(today)
        followingChanged(from: wasFollowing)
    }

    /// Takes a new day in the time zone of the Mac: the reporting cutoff moves to the last day of the new month when it
    /// follows the automatic cutoff and the month changed, at New Year into the new year, which `newYearBanner` then
    /// tells, and the year menu gets the new current year. The screens load again for the new day whether the cutoff
    /// moved or not (`ReloadKey`). A backup outside the Mac is made when one is due.
    func handleDayChanged(_ today: CivilDate) {
        self.today = today
        if case .newYear(let finished) = asOf.dayChanged(to: today) {
            newYearBanner = finished
        }
        years = Self.years(withData: yearsWithData, currentYear: today.year)
        if appSettings.backupFolderBookmark != nil {
            Task { await backUpOffMacIfDue() }
        }
    }

    /// The years to choose from: the years with data and the current year, never one after it, newest first. A year
    /// without rules of its own is there too: it is computed as an estimate.
    nonisolated static func years(withData: [Int], currentYear: Int) -> [Int] {
        Set(withData.filter { $0 <= currentYear }).union([currentYear]).sorted(by: >)
    }

    /// When the cutoff follows the automatic one again, the next midnight is a wake of the refresh again, so the
    /// refresh runs to set its timer.
    private func followingChanged(from wasFollowing: Bool) {
        guard asOf.followsToday, !wasFollowing, dependencies.startsRefresh, let refresh else { return }
        Task { await refresh.refresh(.settingsChanged) }
    }

    /// Reads the years with data again.
    private func reloadYears() async {
        if let database {
            do {
                yearsWithData = try await database.yearsWithData()
            } catch {
                Self.log("Reading the years with data", failedWith: error)
            }
        }
        years = Self.years(withData: yearsWithData, currentYear: today.year)
    }

    /// Today on the clock, in the time zone of the Mac.
    private func currentDay() -> CivilDate {
        CivilDate.today(now: dependencies.clock.now(), timeZone: dependencies.timeZone())
    }

    // MARK: Screens

    /// Shows Faktury with the detail of the invoice `id`. An editor that is open is closed for it, after the question
    /// "Zahodit rozepsanou fakturu?" when something typed in it would be lost (`pendingDiscard`).
    func openInvoice(_ id: Int64) {
        choose(.openInvoice(id))
    }

    /// Whether Hledat (⌘F) can focus the search field of Faktury: Faktury is shown with its list, not the editor, and
    /// neither a sheet nor the lock after inactivity is over the window or over Faktury, as the field is behind it
    /// then.
    var canFocusSearch: Bool {
        screen == .invoices && editorRequest == nil && !invoiceSheetOpen && uniformRateOffer == nil && !isIdleLocked
    }

    /// Hledat (⌘F): asks Faktury to focus its search field. Does nothing where there is no such field to reach
    /// (`canFocusSearch`).
    func focusSearch() {
        guard canFocusSearch else { return }
        searchFocusRequests += 1
    }

    /// Shows `text` in a green banner at the top of the screen that is shown, in place of any banner before it.
    func showBanner(_ text: String) {
        banner = AppBanner(text: text, screen: screen)
    }

    /// The method the year shown converts its income in other currencies with (`YearFXState.effective`), as the window
    /// names it: the ČNB rates of the days until it is read for that year.
    var shownYearFXMethod: IncomeFXMethod {
        guard let shownYearFX, shownYearFX.year == asOf.year else { return .cnbDaily }
        return shownYearFX.effective
    }

    /// Reads how the year shown converts its income in other currencies (`shownYearFX`), whenever what it depends on
    /// may have changed: the year shown, or the data. A failure is logged and leaves nothing read.
    func loadShownYearFX() async {
        shownYearFXLoads += 1
        let thisLoad = shownYearFXLoads
        let read: YearFXState?
        do {
            read = try await fxState(year: asOf.year)
        } catch {
            Self.log("Reading the conversion of the year shown", failedWith: error)
            read = nil
        }
        guard thisLoad == shownYearFXLoads else { return }
        shownYearFX = read
    }

    /// How many drafts were issued in the selected year: the badge of Faktury in the sidebar, what its Koncepty chip
    /// counts. 0 while the data is locked; a failure to read it is logged and shows no badge.
    func draftCountOfSelectedYear() async -> Int {
        guard let database else { return 0 }
        do {
            return try await database.draftCount(year: asOf.year)
        } catch {
            Self.log("Counting the drafts", failedWith: error)
            return 0
        }
    }

    // MARK: Writes and settings

    /// Tells the model that a screen has written to the data: the screens load again, the change waits for the local
    /// backup (kept in the settings, so that a quit does not lose it) and the year menu is read again. Then the backups
    /// that are due start, and the screen does not wait for them (`startBackupsAfterWrite()`): the local backup when an
    /// hour has passed since the last one, or else the wake for it is armed, and the backup outside the Mac when it is
    /// due and a folder for it is set.
    func didWrite() async {
        reloadScreens()
        changeCount += 1
        if appSettings.localBackupPendingSince == nil {
            await markChangeWaitingForBackup()
        }
        await reloadYears()
        startBackupsAfterWrite()
    }

    /// Makes the screens load again: after a write (`didWrite()`), or when what they show changed without one, as when
    /// new ČNB rates came.
    func reloadScreens() {
        dataVersion += 1
    }

    /// Runs `step` as the one step of Zabezpečení a zálohy that runs (`securityStepRunning`). Throws `VaultError.busy`,
    /// and runs nothing, while another one runs.
    func runSecurityStep<T>(_ step: () async throws -> T) async throws -> T {
        guard !securityStepRunning else { throw VaultError.busy }
        securityStepRunning = true
        defer { securityStepRunning = false }
        return try await step()
    }

    /// Changes the settings with `change` and saves them, in one transaction with the database, so that a change made
    /// elsewhere meanwhile is kept. A change that cannot be saved is logged and not shown. Does nothing while the data
    /// is locked.
    func updateAppSettings(_ change: @Sendable (inout AppSettings) -> Void) async {
        guard database != nil else { return }
        do {
            try await changeAppSettings(change)
        } catch {
            Self.log("Saving the settings", failedWith: error)
        }
    }

    /// Changes the settings with `change` and saves them, as `updateAppSettings(_:)` does, for a step that has to know
    /// whether they were saved. Throws `VaultError.locked` while the data is locked, and what the database throws;
    /// nothing changes then.
    func changeAppSettings(_ change: @Sendable (inout AppSettings) -> Void) async throws {
        guard let database else { throw VaultError.locked }
        let saved = try await database.updateAppSettings(change)
        // The data may have been replaced meanwhile (a restore): the settings shown are those of the data open now.
        if self.database === database {
            take(saved)
        }
    }

    /// Takes `settings`, as read from the open data or saved to it, as the settings of the app, and keeps their time of
    /// the lock after inactivity outside the data, for the locked screen of the next launch (`idleLockBeforeOpening`).
    private func take(_ settings: AppSettings) {
        appSettings = settings
        dependencies.idleLockMirror.write(settings.idleLock)
    }

    /// Reads the settings of the open data again, after a step that changed them in the data itself: the vault records
    /// the choice of Touch ID and the backup that follows a change of the keys. A failure is logged and the settings
    /// shown stay.
    func reloadAppSettings() async {
        guard let database else { return }
        do {
            let read = try await database.appSettings()
            if self.database === database {
                take(read)
            }
        } catch {
            Self.log("Reading the settings", failedWith: error)
        }
    }

    // MARK: Helpers

    /// The version of the app, for the header of a backup.
    private static var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
    }

    /// The name of this Mac, for the header of a backup: its computer name from the system configuration, which asks
    /// nothing of the network, or "Mac" when it has none.
    private static var deviceName: String {
        guard let name = SCDynamicStoreCopyComputerName(nil, nil) as String?, !name.isEmpty else {
            return "Mac"
        }
        return name
    }

    /// Logs that `step` failed, with the domain and the code of the error alone: its description could name a file or
    /// carry data.
    nonisolated static func log(_ step: String, failedWith error: any Error) {
        let error = error as NSError
        logger.error(
            "\(step, privacy: .public) failed: \(error.domain, privacy: .public) \(error.code, privacy: .public)")
    }
}
