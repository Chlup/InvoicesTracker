import AppKit
import Foundation
import Network
import os

/// What made the refresh run.
nonisolated enum RefreshTrigger: String, Sendable {
    case launch
    case wake
    case dayChanged
    case clockChanged
    case timeZoneChanged
    case becameActive

    /// The network became usable after it was not. It does not wait out a back-off after failed requests, which most
    /// likely failed for want of it, but it keeps the one search for a uniform rate a day.
    case networkAvailable

    case timer

    /// Something the refresh depends on changed in the app: the reporting cutoff follows the real month again (which
    /// makes midnight a wake), or uniform rates were stored or removed (which changes the line of the uniform rate, and
    /// whether it is looked for). An ordinary run.
    case settingsChanged

    /// The person asked for a check ("Zkontrolovat teď"). It does not wait out a back-off after failed requests, and
    /// it looks for a uniform rate that is due even if it was looked for today already.
    case manual
}

nonisolated extension RefreshTrigger {
    /// The trigger of the one run that stands for `queued` and `trigger` together: a manual check if either of them is
    /// one, else the network coming back if either of them is that, else `trigger`, the later one.
    static func coalescing(_ queued: RefreshTrigger?, _ trigger: RefreshTrigger) -> RefreshTrigger {
        if queued == .manual || trigger == .manual {
            return .manual
        }
        if queued == .networkAvailable || trigger == .networkAvailable {
            return .networkAvailable
        }
        return trigger
    }
}

/// Keeps the app current while it runs, also with the window closed or the app in the background: "today" and the
/// reporting cutoff that follows it, the ČNB rates and, from 2 January to 31 March, the uniform rate of the finished
/// year. Nothing polls.
///
/// Every trigger (launch, wake from sleep, a new day, a change of the clock or of the time zone, the app becoming
/// active, the network coming back, the one timer, a change of the settings, a manual check) runs the same idempotent
/// "refresh what is due". Runs never overlap: the triggers that come during a run make one run after it. Only a run
/// that `stop()` cancelled may still be ending when the first run after a restart begins; it starts no save of its
/// state, sets no timer and calls nothing back. A save that was already in flight when `stop()` arrived still lands.
///
/// 1. Today in the time zone of the Mac is compared with the day of the run before, and a new day goes to
///    `onDayChanged`.
/// 2. `RefreshPlanner` says what is due, from the stored state and the facts of the database.
/// 3. The missing ČNB rates are fetched and stored, and so are the yearly files that provisional payments wait for:
///    years behind the newest cached declaration whose rates the ČNB has declared, such as a year an import could not
///    fetch. Every request goes to the fetch log, and `onRatesUpdated` is called when the newest cached declaration
///    moved or the file of such a year was stored. A day whose file says an earlier day (its rates are not out yet, or
///    the ČNB declared nothing that day) is done for the run; the timer tries again later.
/// 4. The uniform rate of the finished year is looked for (see `RefreshCoordinator+Uniform.swift`), and what is found
///    goes to `onUniformRateFound`, which asks the person to confirm it. The coordinator never stores a uniform rate.
/// 5. The state is saved under `refresh_state` in `app_settings` and the one timer is set to the next wake.
///
/// The requests and the reading of the files run away from the main actor, at utility priority for the triggers
/// that do not come from the person; the status and the callbacks are updated on the main actor.
@MainActor
final class RefreshCoordinator {
    /// What Nastavení › Aplikace shows of the refresh.
    let status: RefreshStatus

    /// Called with the new day when the calendar day in the time zone of the Mac has changed since the last run, also
    /// when the clock was set back.
    var onDayChanged: (@MainActor (CivilDate) -> Void)?

    /// Called when new ČNB rates were stored: once in a run in which the newest cached declaration moved or the yearly
    /// file of a year that provisional payments wait for was stored, and after `fetchYears(_:)` stored rates, which may
    /// be those of a year long past.
    var onRatesUpdated: (@MainActor () -> Void)?

    /// Called with the uniform rates of a finished year that were found, for the person to confirm. Nothing is stored.
    var onUniformRateFound: (@MainActor (GFRFinding) -> Void)?

    /// Called with a year whose uniform rate was not found by 31 March of the next year: it has to be entered by hand.
    var onUniformRateReminder: (@MainActor (Int) -> Void)?

    // The clock, the database and the finder of uniform rates are also used by `RefreshCoordinator+Uniform.swift`.
    let clock: any AppClock
    let database: Database
    let gfr: GFRFetcher

    /// The instruction of a uniform rate found since the app started that waits for confirmation, by year. Kept up to
    /// date by `RefreshCoordinator+Uniform.swift`.
    var foundUniformInstructions: [Int: String] = [:]

    /// The latest error of the search for a uniform rate, which is part of `status.lastError`. Kept up to date by
    /// `RefreshCoordinator+Uniform.swift`.
    var uniformError: String?

    private let scheduler: any RefreshScheduler
    private let cnb: CNBFetcher
    private let currentYear: @MainActor () -> Int
    private let followsToday: @MainActor () -> Bool
    private let timeZone: @MainActor () -> TimeZone

    /// The state as the latest run left it, read from the database by the first run.
    private var state: RefreshState?

    /// The years whose uniform rates were removed since the latest run kept its state (`searchAgain(for:)`): the next
    /// run forgets that their search gave up, and so does a run in progress before it keeps its state.
    private var yearsToSearchAgain: Set<Int> = []

    /// The day in the time zone of the Mac that the latest run saw.
    private var lastSeenDay: CivilDate?

    /// The timer that is set. There is never more than one.
    private var timer: (any RefreshCancellable)?

    /// The run in progress.
    private var current: Task<Void, Never>?

    /// The one run that waits for the run in progress, and the trigger it runs with.
    private var queued: QueuedRun?

    /// Whether `stop()` was called: nothing runs and no timer is set until `start()`.
    private var stopped = false

    /// The latest error of the ČNB rates, which is part of `status.lastError`.
    private var cnbError: String?

    private var observers: [(center: NotificationCenter, token: any NSObjectProtocol)] = []
    private var pathMonitor: NWPathMonitor?

    /// Whether the network was usable at the latest report of the path monitor. Nil before the first report.
    private var networkSatisfied: Bool?

    private nonisolated static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "InvoicesTracker", category: "Refresh")

    /// A coordinator that does nothing until `start()` or `refresh(_:)` is called.
    ///
    /// - Parameters:
    ///   - currentYear: The current year of the app: the year of today in the time zone of the Mac.
    ///   - followsToday: Whether the reporting cutoff follows today (`AsOfState.followsToday`), which makes the next
    ///     midnight a wake.
    ///   - timeZone: The time zone of the Mac, in which "today" and its midnight are counted. The ČNB is always counted
    ///     in Prague time.
    init(
        clock: any AppClock, scheduler: any RefreshScheduler, cnb: CNBFetcher, gfr: GFRFetcher, database: Database,
        currentYear: @escaping @MainActor () -> Int, followsToday: @escaping @MainActor () -> Bool,
        timeZone: @escaping @MainActor () -> TimeZone = { .autoupdatingCurrent }
    ) {
        self.clock = clock
        self.scheduler = scheduler
        self.cnb = cnb
        self.gfr = gfr
        self.database = database
        self.currentYear = currentYear
        self.followsToday = followsToday
        self.timeZone = timeZone
        status = RefreshStatus(timeZone: timeZone())
    }

    isolated deinit {
        stop()
    }

    // MARK: Starting and stopping

    /// Whether the coordinator listens to the triggers: `start()` was called, and `stop()` has not been since. One that
    /// only `resume()` ran is not started.
    var isStarted: Bool {
        !observers.isEmpty
    }

    /// Starts listening to the triggers (wake from sleep, a new day, a change of the clock or of the time zone, the app
    /// becoming active, the network coming back) and runs the refresh of the launch. Calling it again while started
    /// does nothing.
    func start() {
        guard observers.isEmpty else { return }
        stopped = false
        observe(NSWorkspace.didWakeNotification, on: NSWorkspace.shared.notificationCenter, as: .wake)
        observe(.NSCalendarDayChanged, on: NotificationCenter.default, as: .dayChanged)
        observe(.NSSystemClockDidChange, on: NotificationCenter.default, as: .clockChanged)
        observe(.NSSystemTimeZoneDidChange, on: NotificationCenter.default, as: .timeZoneChanged)
        observe(NSApplication.didBecomeActiveNotification, on: NotificationCenter.default, as: .becameActive)
        let monitor = NWPathMonitor()
        monitor.pathUpdateHandler = { [weak self] path in
            let satisfied = path.status == .satisfied
            Task(priority: .utility) { @MainActor in
                await self?.networkChanged(satisfied: satisfied)
            }
        }
        monitor.start(queue: DispatchQueue(label: "InvoicesTracker.Refresh.network", qos: .utility))
        pathMonitor = monitor
        Task(priority: .utility) {
            // Stopped again before this task ran: a coordinator that is stopped does not launch.
            guard !stopped else { return }
            await resume()
        }
    }

    /// Ends a `stop()` and runs the refresh of a launch; returns when that run is over. `start()` calls it once it
    /// listens to the triggers.
    func resume() async {
        stopped = false
        await refresh(.launch)
    }

    /// Stops listening, cancels the timer and the runs in progress and waiting, and ignores any later `refresh(_:)`
    /// until `start()` or `resume()`. A cancelled run ends on its own without starting a save of its state, setting the
    /// timer or calling back, and nothing joins it: the first run after a restart starts afresh. A save that is already
    /// in flight when this is called still lands.
    func stop() {
        stopped = true
        current?.cancel()
        queued?.task.cancel()
        current = nil
        queued = nil
        timer?.cancel()
        timer = nil
        for observer in observers {
            observer.center.removeObserver(observer.token)
        }
        observers = []
        pathMonitor?.cancel()
        pathMonitor = nil
        networkSatisfied = nil
    }

    private func observe(_ name: Notification.Name, on center: NotificationCenter, as trigger: RefreshTrigger) {
        let token = center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
            if trigger == .timeZoneChanged {
                // `TimeZone.current` is cached until it is reset.
                NSTimeZone.resetSystemTimeZone()
            }
            Task(priority: .utility) { @MainActor in
                await self?.refresh(trigger)
            }
        }
        observers.append((center, token))
    }

    /// Takes a report of the path monitor. When the network becomes usable after it was not, it runs the refresh as
    /// `.networkAvailable` and returns when that run is over; the first report and reports that change nothing only
    /// note the state.
    func networkChanged(satisfied: Bool) async {
        let wasSatisfied = networkSatisfied
        networkSatisfied = satisfied
        guard satisfied, wasSatisfied == false else { return }
        await refresh(.networkAvailable)
    }

    // MARK: Refreshing

    /// A run that waits for the run in progress, and the trigger it will run with.
    private struct QueuedRun {
        let task: Task<Void, Never>
        var trigger: RefreshTrigger
    }

    /// Refreshes what is due. With no run in progress the run starts at once. Otherwise the trigger waits: all the
    /// triggers that come during one run make one run after it, which runs with the trigger that stands for them all
    /// (`RefreshTrigger.coalescing`). A cancelled run is never joined. Returns when the run that covers `trigger` is
    /// over.
    func refresh(_ trigger: RefreshTrigger) async {
        guard !stopped else { return }
        let run: Task<Void, Never>
        if var waiting = queued, !waiting.task.isCancelled {
            waiting.trigger = RefreshTrigger.coalescing(waiting.trigger, trigger)
            queued = waiting
            run = waiting.task
        } else if let current, !current.isCancelled {
            run = Task { [self] in
                await current.value
                // Cancelled by `stop()` while it waited: it does not start, and the run waiting now is another one.
                guard !Task.isCancelled else { return }
                await runQueued()
            }
            queued = QueuedRun(task: run, trigger: trigger)
        } else {
            run = Task { [self] in
                await perform(trigger)
            }
            current = run
        }
        await run.value
        if current == run {
            current = nil
        }
    }

    /// Starts the run that waited: it becomes the run in progress, with the trigger that stands for the triggers it
    /// collected.
    private func runQueued() async {
        guard let next = queued else { return }
        queued = nil
        current = next.task
        guard !stopped else { return }
        await perform(next.trigger)
    }

    private func perform(_ trigger: RefreshTrigger) async {
        // Cancelled by `stop()` before it started: it does nothing.
        guard !Task.isCancelled else { return }
        let now = clock.now()
        status.timeZone = timeZone()
        announceDayChange(now: now)
        var state = await storedState()
        status.cnbFetchedAt = state.lastCNBDownload
        do {
            try await updateFacts(of: &state, now: now)
        } catch {
            guard !Task.isCancelled else { return }
            Self.log("Reading the cached rates", failedWith: error)
            // Counted as a failed fetch, so that the timer backs off instead of trying again at once.
            state.cnbFailureCount += 1
            state.lastCNBFailure = now
            cnbError = "Uložené kurzy se nepodařilo načíst."
            showErrors()
            keep(&state, searchedAgainFromStart: [])
            armTimer(for: state)
            return
        }
        // The years whose uniform rates were removed are looked for again from this run on (`searchAgain(for:)`).
        let searchedAgain = yearsToSearchAgain
        state.gaveUpUniform.subtract(searchedAgain)
        let actions = RefreshPlanner.actionsDue(now: now, state: Self.planningState(state, for: trigger))

        let fetched = await fetchCNBRates(actions, now: now, state: &state)
        guard !Task.isCancelled else { return }
        if fetched.newestMoved {
            state.lastCNBDownload = clock.now()
        }
        status.cnbUpToDate = state.newestCNBDeclaration
        status.cnbFetchedAt = state.lastCNBDownload
        if fetched.newestMoved || fetched.paymentYearsStored {
            onRatesUpdated?()
        }

        await searchUniformRates(actions, now: now, state: &state)
        guard !Task.isCancelled else { return }
        showUniformLine(for: state)
        showErrors()

        keep(&state, searchedAgainFromStart: searchedAgain)
        do {
            try await database.saveRefreshState(state)
        } catch {
            Self.log("Saving the state of the refresh", failedWith: error)
        }
        guard !Task.isCancelled else { return }
        armTimer(for: state)
    }

    /// Keeps `state` as the state the latest run left. A year whose uniform rates were removed while the run went on
    /// (`searchAgain(for:)`) loses the end of its search, which the state of a run that began before still has; the
    /// years the run looked for again from its start, `searchedAgainFromStart`, keep what it found of them.
    private func keep(_ state: inout RefreshState, searchedAgainFromStart: Set<Int>) {
        state.gaveUpUniform.subtract(yearsToSearchAgain.subtracting(searchedAgainFromStart))
        yearsToSearchAgain = []
        self.state = state
    }

    /// The uniform rates of `year` were removed, so that the year has none: the search for them starts again where it
    /// ended without them (`RefreshState.gaveUpUniform`), and the year is looked for when it is due (`RefreshPlanner`).
    /// The stored state forgets the end at once, and so does the next run, or a run in progress before it keeps its
    /// state. A stored state that cannot be changed is logged: the run that keeps its state next stores it without the
    /// end. Whoever removed the rates starts the run (`RefreshTrigger.settingsChanged`).
    func searchAgain(for year: Int) async {
        yearsToSearchAgain.insert(year)
        do {
            try await database.forgetGivingUpUniformSearch(year: year)
        } catch {
            Self.log("Starting the search for a uniform rate again", failedWith: error)
        }
    }

    /// Fetches the yearly files of `years` at the request of a screen that needs rates the cache lacks: a year the
    /// cache does not hold, which the plan of a run never fetches, as it only goes on from the newest declaration.
    /// Every request is logged as a run logs it: a request that worked is logged as such before its rates are stored,
    /// and a failure to store them is logged apart, in the log of the app. A year that cannot be fetched is logged and
    /// does not keep the others from being fetched; it is the screen's to ask for it only once. Returns whether any
    /// rates were stored, and then the app is told (the payments that wait for a rate are converted, the screens load
    /// again). A `stop()` that comes while a file is on its way keeps its rates out of the cache, and nothing is told
    /// to the app after it; nothing is fetched after it.
    func fetchYears(_ years: [Int]) async -> Bool {
        guard !stopped else { return false }
        var stored = false
        for year in years {
            let url = CNBEndpoints.yearly(year)
            let rows: [CNBRateRow]
            do {
                rows = try await Self.fetchYear(year, from: cnb)
            } catch {
                guard !Task.isCancelled else { break }
                await logRequest(.cnbYearly, url, failedWith: error)
                continue
            }
            await logRequest(.cnbYearly, url, ok: true, message: "")
            guard !stopped else { break }
            do {
                try await database.insertCNBRates(rows)
                stored = stored || !rows.isEmpty
            } catch {
                Self.log("Storing the ČNB rates of a year", failedWith: error)
            }
        }
        guard stored, !stopped else { return stored }
        do {
            status.cnbUpToDate = try await database.newestCNBDeclaration()
        } catch {
            Self.log("Reading the cached rates", failedWith: error)
        }
        onRatesUpdated?()
        return stored
    }

    /// Tells the app of a new day in the time zone of the Mac. The first run only notes the day.
    private func announceDayChange(now: Date) {
        let today = CivilDate.today(now: now, timeZone: timeZone())
        let previous = lastSeenDay
        lastSeenDay = today
        if let previous, previous != today {
            onDayChanged?(today)
        }
    }

    /// The state the latest run left, or the stored one for the first run. A stored state that cannot be read is
    /// started afresh: it is bookkeeping, and the facts are read from the database again.
    private func storedState() async -> RefreshState {
        if let state {
            return state
        }
        do {
            return try await database.refreshState() ?? RefreshState()
        } catch {
            Self.log("Reading the state of the refresh", failedWith: error)
            return RefreshState()
        }
    }

    /// Brings the facts the plan rests on up to date: the newest cached declaration, the days of the provisional
    /// payments that wait for a rate, and whether the finished year has an official uniform rate, or rates entered by
    /// hand in its place. Drops what no longer matters: the retries of other days than today, and what is kept about
    /// the search of years that are not looked for any more.
    private func updateFacts(of state: inout RefreshState, now: Date) async throws {
        state.newestCNBDeclaration = try await database.newestCNBDeclaration()
        state.provisionalPaymentDays = try await database.provisionalPaymentDaysWithoutRate()
        let finished = currentYear() - 1
        let rates = try await database.uniformRates(year: finished)
        // Shipped with the app, or fetched and confirmed.
        let hasOfficialRate = rates.contains { $0.origin != .manual }
        state.finishedYearsWithoutUniformRate = hasOfficialRate ? [] : [finished]
        state.finishedYearsWithManualUniformRate = !hasOfficialRate && !rates.isEmpty ? [finished] : []
        let today = CzechCalendar.pragueDate(now)
        let open = Set(state.finishedYearsLookedForUniformRate)
        state.cnbRetrySlotsUsed = state.cnbRetrySlotsUsed.filter { $0.key == today }
        state.checkedIssues = state.checkedIssues.filter { open.contains($0.key) }
        state.gaveUpUniform = state.gaveUpUniform.filter { open.contains($0) }
        state.unreadableUniformPages = state.unreadableUniformPages.filter { open.contains($0.key) }
        foundUniformInstructions = foundUniformInstructions.filter { open.contains($0.key) }
    }

    /// `state` as `trigger` plans with it. A manual check and the network coming back do not wait out the back-off
    /// after failed requests; a manual check also looks for a uniform rate that was looked for today already.
    private static func planningState(_ state: RefreshState, for trigger: RefreshTrigger) -> RefreshState {
        var planned = state
        if trigger == .manual || trigger == .networkAvailable {
            planned.cnbFailureCount = 0
            planned.lastCNBFailure = nil
        }
        if trigger == .manual {
            planned.lastUniformCheck = nil
        }
        return planned
    }

    /// Sets the one timer to the next wake, in place of the timer before.
    private func armTimer(for state: RefreshState) {
        guard !stopped else { return }
        let wake = RefreshPlanner.nextWake(
            now: clock.now(), state: state, followsToday: followsToday(), localTimeZone: timeZone())
        timer?.cancel()
        timer = scheduler.schedule(at: wake, tolerance: RefreshPlanner.wakeTolerance) { [weak self] in
            Task(priority: .utility) { @MainActor in
                await self?.refresh(.timer)
            }
        }
    }

    // MARK: ČNB rates

    /// One file of the ČNB.
    private nonisolated enum CNBFile {
        case day(CivilDate)
        case year(Int)

        /// The yearly file of a year that provisional payments wait for.
        case paymentYear(Int)
    }

    /// A daily file that says a later day than the one asked for. It is not believed.
    private nonisolated struct CNBFileOfAnotherDay: Error {
        let declaredOn: CivilDate
    }

    /// What the ČNB files of a run brought.
    private struct CNBFetchOutcome {
        /// Whether the newest cached declaration moved.
        var newestMoved = false

        /// Whether the yearly file of a year that provisional payments wait for was stored.
        var paymentYearsStored = false
    }

    /// Fetches the ČNB files that `actions` ask for, the newest rates first and then the years that provisional
    /// payments wait for, each oldest first, stores their rates and logs every request. The first failure ends the
    /// fetching, so that no later day is stored after a hole.
    ///
    /// The outcome counts once for the run: a run with a failure adds one to the failures in a row that it started
    /// with, whatever succeeded before the failure, and only a run without a failure sets them back to none. Returns
    /// what the files brought.
    private func fetchCNBRates(
        _ actions: [RefreshAction], now: Date, state: inout RefreshState
    ) async -> CNBFetchOutcome {
        var files: [CNBFile] = []
        for action in actions {
            switch action {
            case .fetchCNBDays(let days): files += days.map { CNBFile.day($0) }
            case .fetchCNBYears(let years): files += years.map { CNBFile.year($0) }
            case .fetchCNBYearsForPayments(let years): files += years.map { CNBFile.paymentYear($0) }
            case .checkUniformRate, .uniformRateReminder: break
            }
        }
        guard !files.isEmpty else {
            // Nothing was asked: the error of an earlier run stays while the cache is behind.
            if let newest = state.newestCNBDeclaration, newest >= RefreshPlanner.expectedNewestDeclaration(now: now) {
                cnbError = nil
            }
            return CNBFetchOutcome()
        }
        let newestBefore = state.newestCNBDeclaration
        var outcome = CNBFetchOutcome()
        var failure: (any Error)?
        for file in files {
            do {
                if try await fetch(file, state: &state), case .paymentYear = file {
                    outcome.paymentYearsStored = true
                }
            } catch {
                guard !Task.isCancelled else { return CNBFetchOutcome() }
                failure = error
                break
            }
        }
        if let failure {
            state.cnbFailureCount += 1
            state.lastCNBFailure = clock.now()
            cnbError = Self.cnbErrorText(failure)
        } else {
            state.cnbFailureCount = 0
            state.lastCNBFailure = nil
            cnbError = nil
        }
        // The fetch of the newest rates used up the retries of the day whose times have come.
        let today = CzechCalendar.pragueDate(now)
        let fetchedNewestRates = files.contains { file in
            if case .paymentYear = file {
                return false
            }
            return true
        }
        if fetchedNewestRates, CzechCalendar.isBusinessDay(today),
            state.newestCNBDeclaration.map({ $0 < today }) ?? true
        {
            state.cnbRetrySlotsUsed[today] = max(
                state.cnbRetrySlotsUsed[today] ?? 0, RefreshPlanner.fetchTimesPassed(at: now))
        }
        if let newestAfter = state.newestCNBDeclaration {
            outcome.newestMoved = newestBefore.map { newestAfter > $0 } ?? true
        }
        return outcome
    }

    /// Fetches one file, logs the request and stores the rates when they are newer than the cache; the yearly file of
    /// a year that provisional payments wait for is stored whatever its days. A daily file that says a later day than
    /// the one asked for is not believed: nothing of it is stored, and it fails. Returns whether rates were stored.
    @discardableResult
    private func fetch(_ file: CNBFile, state: inout RefreshState) async throws -> Bool {
        let newest = state.newestCNBDeclaration
        switch file {
        case .day(let day):
            let url = CNBEndpoints.daily(day)
            let daily: (declaredOn: CivilDate, rows: [CNBRateRow])
            do {
                daily = try await Self.fetchDay(day, from: cnb)
            } catch {
                await logRequest(.cnbDaily, url, failedWith: error)
                throw error
            }
            let message = daily.declaredOn == day ? "" : "declared \(daily.declaredOn.iso)"
            guard daily.declaredOn <= day else {
                await logRequest(.cnbDaily, url, ok: false, message: message)
                throw CNBFileOfAnotherDay(declaredOn: daily.declaredOn)
            }
            await logRequest(.cnbDaily, url, ok: true, message: message)
            // The file of a day whose rates are not out yet is the file of an earlier day: nothing new.
            if let newest, daily.declaredOn <= newest {
                return false
            }
            try await database.insertCNBRates(daily.rows)
            state.newestCNBDeclaration = daily.declaredOn
            return !daily.rows.isEmpty
        case .year(let year), .paymentYear(let year):
            let url = CNBEndpoints.yearly(year)
            let rows: [CNBRateRow]
            do {
                rows = try await Self.fetchYear(year, from: cnb)
            } catch {
                await logRequest(.cnbYearly, url, failedWith: error)
                throw error
            }
            // A year that payments wait for is older than the newest declaration: what it brings is its own rates.
            let bringsNewer = rows.contains { row in newest.map { row.declaredOn > $0 } ?? true }
            let message: String
            if case .paymentYear = file {
                message = ""
            } else {
                message = bringsNewer ? "" : "no newer rates"
            }
            await logRequest(.cnbYearly, url, ok: true, message: message)
            try await database.insertCNBRates(rows)
            state.newestCNBDeclaration = try await database.newestCNBDeclaration()
            return !rows.isEmpty
        }
    }

    /// The daily file of `day`, downloaded and read away from the main actor.
    @concurrent
    private nonisolated static func fetchDay(
        _ day: CivilDate, from cnb: CNBFetcher
    ) async throws -> (declaredOn: CivilDate, rows: [CNBRateRow]) {
        try await cnb.fetchDay(day)
    }

    /// The yearly file of `year`, downloaded and read away from the main actor.
    @concurrent
    private nonisolated static func fetchYear(_ year: Int, from cnb: CNBFetcher) async throws -> [CNBRateRow] {
        try await cnb.fetchYear(year)
    }

    // MARK: Status

    /// The line of the uniform rate. While the finished year has no stored rate it is about that year: given up on
    /// after 31 March, found and waiting for confirmation, a page that cannot be read, or not out yet. Once a rate of
    /// it is stored, also one entered by hand, the line is about the current year.
    private func showUniformLine(for state: RefreshState) {
        guard let year = state.finishedYearsLookedForUniformRate.max() else {
            let year = currentYear()
            status.uniformYear = year
            status.uniformText = RefreshStatus.uniformNotOutText(year: year)
            return
        }
        status.uniformYear = year
        if state.gaveUpUniform.contains(year) {
            status.uniformText = RefreshStatus.uniformNotFoundText(year: year)
        } else if let instruction = foundUniformInstructions[year] {
            status.uniformText = RefreshStatus.uniformFoundText(year: year, instruction: instruction)
        } else if let page = state.unreadableUniformPages[year] {
            status.uniformText = RefreshStatus.uniformUnreadableText(year: year, url: page)
        } else {
            status.uniformText = RefreshStatus.uniformNotOutText(year: year)
        }
    }

    private func showErrors() {
        let errors = [cnbError, uniformError].compactMap { $0 }
        status.lastError = errors.isEmpty ? nil : errors.joined(separator: " ")
    }

    /// What `status.lastError` says about a failed fetch of ČNB rates.
    private static func cnbErrorText(_ error: any Error) -> String {
        switch error {
        case is SQLiteError, is StoredValueError: "Kurzy ČNB se nepodařilo uložit do databáze."
        default: "Kurzy ČNB se nepodařilo stáhnout: \(reason(error))."
        }
    }

    /// Why a request failed, in a few Czech words for the status.
    nonisolated static func reason(_ error: any Error) -> String {
        switch error {
        case HTTPError.offline: "není připojení k internetu"
        case HTTPError.status(let status): "server odpověděl chybou \(status)"
        case HTTPError.hostNotAllowed: "server přesměroval na neočekávanou adresu"
        case is CNBParseError: "soubor má neočekávaný formát"
        case is CNBFileOfAnotherDay: "soubor je z jiného dne"
        default: "spojení se nezdařilo"
        }
    }

    /// Logs that `step` failed, with the domain and the code of the error alone.
    nonisolated static func log(_ step: String, failedWith error: any Error) {
        let error = error as NSError
        logger.error(
            "\(step, privacy: .public) failed: \(error.domain, privacy: .public) \(error.code, privacy: .public)")
    }
}
