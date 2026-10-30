import AppKit
import Foundation
import Testing
@testable import InvoicesTracker

/// The lock after inactivity: while the app is unlocked with Touch ID, it locks once the time chosen in Nastavení ›
/// Zabezpečení a zálohy (10 minutes unless chosen) passes without a click, a key, a scroll or a move of the pointer in
/// its windows, the time the Mac sleeps included, and only Touch ID or the Mac password unlocks it again. It is a lock
/// of the screen alone: the data stays open under it, and what the app would show or say by itself waits for the
/// unlock. The clock is manual, at noon of 17. 10. 2026; the timer of the check, every 15 seconds, fires when the test
/// says; a scripted prompt stands in for Touch ID, and the wakes of the Mac are posted to a center of the app's own.
@Suite(.settlesBackups)
@MainActor
struct AppModelIdleLockTests {
    /// Whether an open or save panel of the system is up, as the test says.
    @MainActor
    private final class PanelState {
        var isUp = true
    }

    /// A menu that counts how many times its tracking was cancelled, as it is when it closes without a choice.
    private final class RecordingMenu: NSMenu {
        var cancellations = 0

        override func cancelTrackingWithoutAnimation() {
            cancellations += 1
        }
    }

    /// An open panel that is on screen, as one shown as a sheet of a window is, though the window server shows nothing.
    private final class ShownOpenPanel: NSOpenPanel {
        override var isVisible: Bool {
            true
        }
    }

    // MARK: Helpers

    /// An app model that has gone through the first launch with Touch ID on, at the time of `clock`, whose lock after
    /// inactivity is checked by itself: on the timer of `scheduler`, and on the wakes posted to its center. The prompt
    /// of Touch ID answers as `authenticator` says.
    private func makeApp(
        in directory: URL, clock: ManualClock, scheduler: ManualScheduler = ManualScheduler(),
        device: any DeviceKeyProtector = SoftwareKeyProtector(),
        authenticator: ScriptedOwnerAuthenticator = ScriptedOwnerAuthenticator()
    ) async throws -> AppModel {
        let app = makeAppModel(
            in: directory, device: device, authenticator: authenticator, clock: clock, scheduler: scheduler,
            startsIdleChecks: true)
        try await startFresh(app)
        return app
    }

    /// Fires the timer of the check, as it fires 15 seconds after it was set, and waits until the check has run: it
    /// sets the timer of the next one.
    private func checkOnTimer(_ scheduler: ManualScheduler) async throws {
        let asked = scheduler.wakes.count
        try #require(scheduler.fire())
        try await waitUntil { scheduler.wakes.count > asked }
    }

    /// Locks `app` after inactivity: its clock moves on by the 10 minutes of the default without any activity, and the
    /// check runs.
    private func lockAfterTenMinutes(_ app: AppModel, clock: ManualClock) throws {
        clock.advance(by: 10 * 60)
        app.checkIdleLock(now: clock.now())
        try #require(app.isIdleLocked)
    }

    /// A mouse event of `type` that no window gets: a move of the pointer, a press of a button or a drag.
    private func mouseEvent(_ type: NSEvent.EventType) throws -> NSEvent {
        try #require(
            NSEvent.mouseEvent(
                with: type, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil,
                eventNumber: 0, clickCount: type == .mouseMoved ? 0 : 1, pressure: type == .mouseMoved ? 0 : 1))
    }

    /// A press of the key A that no window gets.
    private func keyEvent() throws -> NSEvent {
        try #require(
            NSEvent.keyEvent(
                with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil,
                characters: "a", charactersIgnoringModifiers: "a", isARepeat: false, keyCode: 0))
    }

    /// A scroll of the wheel of the mouse by 10 points down, which no window gets.
    private func wheelEvent() throws -> NSEvent {
        let event = try #require(
            CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 1, wheel1: -10, wheel2: 0, wheel3: 0))
        return try #require(NSEvent(cgEvent: event))
    }

    // MARK: When it locks

    @Test func theAppLocksAfterTenMinutesWithoutActivity() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let clock = ManualClock(localNoon(2026, 10, 17))
        let scheduler = ManualScheduler()
        let app = try await makeApp(in: directory, clock: clock, scheduler: scheduler)
        let start = clock.now()
        let database = try #require(app.database)
        #expect(app.appSettings.idleLock == .tenMinutes)
        // The check runs every 15 seconds once the data is open.
        #expect(scheduler.armed == [start + 15])

        clock.set(start + 9 * 60 + 59)
        try await checkOnTimer(scheduler)

        #expect(!app.isIdleLocked)
        #expect(scheduler.armed == [start + 9 * 60 + 59 + 15])

        clock.set(start + 10 * 60)
        try await checkOnTimer(scheduler)

        #expect(app.isIdleLocked)
        // A lock of the screen: the data stays open, and the app shows what it showed under the lock.
        #expect(app.phase == .ready)
        #expect(app.database === database)
        #expect(app.vault.database === database)
    }

    @Test func activityRestartsTheCountdown() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let clock = ManualClock(localNoon(2026, 10, 17))
        let scheduler = ManualScheduler()
        let app = try await makeApp(in: directory, clock: clock, scheduler: scheduler)

        clock.advance(by: 9 * 60)
        app.noteActivity(at: clock.now())
        clock.advance(by: 9 * 60 + 59)
        try await checkOnTimer(scheduler)

        // 18 minutes 59 seconds since the data was opened, but 9 minutes 59 seconds since the activity.
        #expect(!app.isIdleLocked)

        clock.advance(by: 1)
        try await checkOnTimer(scheduler)

        #expect(app.isIdleLocked)
    }

    @Test func withTouchIDOffTheAppNeverLocks() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let clock = ManualClock(localNoon(2026, 10, 17))
        let scheduler = ManualScheduler()
        let app = try await makeApp(in: directory, clock: clock, scheduler: scheduler)
        _ = try await app.setTouchID(false)
        #expect(!app.appSettings.touchIDUnlock)
        #expect(app.appSettings.idleLock == .tenMinutes)

        clock.advance(by: 2 * 60 * 60)
        try await checkOnTimer(scheduler)

        #expect(!app.isIdleLocked)

        // With Touch ID on again, the same two hours lock it.
        _ = try await app.setTouchID(true)
        try await checkOnTimer(scheduler)

        #expect(app.isIdleLocked)
    }

    @Test func nikdyNeverLocks() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let clock = ManualClock(localNoon(2026, 10, 17))
        let scheduler = ManualScheduler()
        let app = try await makeApp(in: directory, clock: clock, scheduler: scheduler)
        await app.updateAppSettings { $0.idleLock = .never }
        #expect(app.appSettings.idleLock == .never)

        clock.advance(by: 24 * 60 * 60)
        try await checkOnTimer(scheduler)

        #expect(!app.isIdleLocked)

        await app.updateAppSettings { $0.idleLock = .oneHour }
        try await checkOnTimer(scheduler)

        #expect(app.isIdleLocked)
    }

    @Test func timeAsleepCounts() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let clock = ManualClock(localNoon(2026, 10, 17))
        let scheduler = ManualScheduler()
        let app = try await makeApp(in: directory, clock: clock, scheduler: scheduler)
        let timer = scheduler.armed
        app.noteActivity(at: clock.now())

        // The Mac sleeps for two hours, and wakes.
        clock.advance(by: 2 * 60 * 60)
        app.dependencies.workspaceNotifications.post(name: NSWorkspace.didWakeNotification, object: nil)

        try await waitUntil { app.isIdleLocked }
        // The wake checked it at once; the timer of the check had not fired.
        #expect(scheduler.armed == timer)
    }

    @Test func anOpenOrSavePanelThatIsUpWhenTheTimeIsUpCountsAsActivity() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let clock = ManualClock(localNoon(2026, 10, 17))
        let scheduler = ManualScheduler()
        let app = try await makeApp(in: directory, clock: clock, scheduler: scheduler)
        let panel = PanelState()
        app.modalPanelIsUp = { panel.isUp }

        clock.advance(by: 2 * 60 * 60)
        try await checkOnTimer(scheduler)

        // The panel shows files, not the data, and the person may work in it without the app seeing it.
        #expect(!app.isIdleLocked)

        panel.isUp = false
        try await checkOnTimer(scheduler)

        // The time counts from the check that found the panel up.
        #expect(!app.isIdleLocked)

        clock.advance(by: 9 * 60 + 59)
        try await checkOnTimer(scheduler)

        #expect(!app.isIdleLocked)

        clock.advance(by: 1)
        try await checkOnTimer(scheduler)

        #expect(app.isIdleLocked)
    }

    @Test func settingTheClockBackCountsTheTimeFromTheChange() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let clock = ManualClock(localNoon(2026, 10, 17))
        let scheduler = ManualScheduler()
        let app = try await makeApp(in: directory, clock: clock, scheduler: scheduler)

        // Five minutes after the data was opened, the clock of the Mac is set back by an hour.
        clock.advance(by: 5 * 60 - 60 * 60)
        app.dependencies.systemNotifications.post(name: .NSSystemClockDidChange, object: nil)

        // The timer of the check is set again from the new time: the one before would fire an hour late.
        try await waitUntil { scheduler.armed == [clock.now() + 15] }

        try await checkOnTimer(scheduler)

        // The latest activity, now in the future, counts as the time of that check.
        #expect(!app.isIdleLocked)

        clock.advance(by: 9 * 60 + 59)
        try await checkOnTimer(scheduler)

        #expect(!app.isIdleLocked)

        clock.advance(by: 1)
        try await checkOnTimer(scheduler)

        #expect(app.isIdleLocked)
    }

    /// The clock of the Mac set ahead past the time locks the app at the change, as the timer of the check would at its
    /// next turn: changes of the clock that come one after another cannot keep putting the check off.
    @Test func settingTheClockAheadPastTheTimeLocksTheAppAtOnce() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let clock = ManualClock(localNoon(2026, 10, 17))
        let scheduler = ManualScheduler()
        let app = try await makeApp(in: directory, clock: clock, scheduler: scheduler)

        // The clock of the Mac is set 10 minutes ahead; the timer of the check, set for 15 seconds after the opening,
        // has not fired.
        clock.advance(by: 10 * 60)
        app.dependencies.systemNotifications.post(name: .NSSystemClockDidChange, object: nil)

        try await waitUntil { app.isIdleLocked }
        // The timer is set again from the new time, as after any change of the clock.
        #expect(scheduler.armed == [clock.now() + 15])
    }

    @Test func activityAfterTheTimeIsUpLocksTheAppInsteadOfRestartingTheCountdown() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let clock = ManualClock(localNoon(2026, 10, 17))
        let app = makeAppModel(in: directory, clock: clock)
        try await startFresh(app)

        // The check that was due has not run yet: the person comes back before the timer of a Mac that has just woken,
        // or of an app in the background, fired.
        clock.advance(by: 10 * 60 + 5)
        app.noteActivity(at: clock.now())

        #expect(app.isIdleLocked)
    }

    @Test func theRuleLocksOnlyWhenEveryConditionHolds() {
        let start = localNoon(2026, 10, 17)
        let due = start + 10 * 60
        func outcome(
            phase: AppPhase = .ready, touchIDUnlock: Bool = true, time: IdleLockTime = .tenMinutes, now: Date,
            modalPanelIsUp: Bool = false
        ) -> IdleLockRule.Outcome {
            IdleLockRule.outcome(
                phase: phase, touchIDUnlock: touchIDUnlock, time: time, lastActivity: start, now: now,
                modalPanelIsUp: modalPanelIsUp)
        }

        #expect(outcome(now: due) == .lock)
        #expect(outcome(now: due - 1) == .nothing)
        // The data is not open: the launch, the first launch, the lock of the data.
        for phase in [AppPhase.starting, .welcome, .onboarding(.supplier), .locked, .newMac] {
            #expect(outcome(phase: phase, now: due + 3_600) == .nothing)
        }
        #expect(outcome(touchIDUnlock: false, now: due + 3_600) == .nothing)
        #expect(outcome(time: .never, now: due + 86_400) == .nothing)
        // An open or save panel that is up when the time is up: the person may work in it without the app seeing it.
        #expect(outcome(now: due + 3_600, modalPanelIsUp: true) == .panelCountsAsActivity)
        #expect(outcome(now: due - 1, modalPanelIsUp: true) == .nothing)
        #expect(outcome(time: .oneMinute, now: start + 60) == .lock)
        #expect(outcome(time: .oneHour, now: start + 3_599) == .nothing)
        #expect(outcome(time: .oneHour, now: start + 3_600) == .lock)
    }

    @Test func theMenuNamesEachTimeAndTheLockTextsSayIt() {
        #expect(
            IdleLockTime.allCases == [
                .oneMinute, .fiveMinutes, .tenMinutes, .fifteenMinutes, .thirtyMinutes, .oneHour, .never,
            ])
        #expect(
            IdleLockTime.allCases.map(\.label) == [
                "Po 1 minutě", "Po 5 minutách", "Po 10 minutách", "Po 15 minutách", "Po 30 minutách", "Po 1 hodině",
                "Nikdy",
            ])
        #expect(
            IdleLockTime.allCases.map(\.afterText) == [
                "po 1\u{00A0}minutě", "po 5\u{00A0}minutách", "po 10\u{00A0}minutách", "po 15\u{00A0}minutách",
                "po 30\u{00A0}minutách", "po 1\u{00A0}hodině", nil,
            ])
        #expect(IdleLockTime.allCases.map(\.interval) == [60, 300, 600, 900, 1_800, 3_600, nil])
    }

    // MARK: Unlocking

    @Test func unlockingAsksTheOwnerAndKeepsEverythingOpen() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let clock = ManualClock(localNoon(2026, 10, 17))
        let device = PromptCountingProtector()
        let authenticator = ScriptedOwnerAuthenticator(answer: true)
        let app = try await makeApp(in: directory, clock: clock, device: device, authenticator: authenticator)
        let database = try #require(app.database)
        let importModel = app.importModel
        let simulatorModel = app.simulatorModel
        let refresh = try #require(app.refresh)
        app.screen = .clients
        try lockAfterTenMinutes(app, clock: clock)
        clock.advance(by: 5 * 60)

        await app.unlockAfterIdle()

        #expect(!app.isIdleLocked)
        #expect(authenticator.reasons == [AppModel.unlockReason])
        // Only the prompt: the key of this Mac opened nothing again, and nothing was opened anew.
        #expect(device.prompts == 0)
        #expect(app.phase == .ready)
        #expect(app.database === database)
        #expect(app.vault.database === database)
        #expect(app.importModel === importModel)
        #expect(app.simulatorModel === simulatorModel)
        #expect(app.refresh === refresh)
        #expect(app.screen == .clients)

        // The countdown starts again at the unlock.
        clock.advance(by: 9 * 60 + 59)
        app.checkIdleLock(now: clock.now())
        #expect(!app.isIdleLocked)
        clock.advance(by: 1)
        app.checkIdleLock(now: clock.now())
        #expect(app.isIdleLocked)
    }

    @Test func aCancelledUnlockStaysLocked() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let clock = ManualClock(localNoon(2026, 10, 17))
        let authenticator = ScriptedOwnerAuthenticator(answer: false)
        let app = try await makeApp(in: directory, clock: clock, authenticator: authenticator)
        try lockAfterTenMinutes(app, clock: clock)

        await app.unlockAfterIdle()

        #expect(app.isIdleLocked)
        #expect(authenticator.reasons == [AppModel.unlockReason])
        #expect(app.database != nil)
        // Activity on the lock does not unlock it either.
        app.noteActivity(at: clock.now())
        #expect(app.isIdleLocked)

        // Trying again asks again.
        authenticator.answer = true
        await app.unlockAfterIdle()

        #expect(!app.isIdleLocked)
        #expect(authenticator.reasons.count == 2)
    }

    @Test(.hangGuard)
    func aSecondUnlockWhileThePromptIsUpAsksNothingMore() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let clock = ManualClock(localNoon(2026, 10, 17))
        let authenticator = ScriptedOwnerAuthenticator()
        let gate = Gate()
        authenticator.hold(at: gate)
        let app = try await makeApp(in: directory, clock: clock, authenticator: authenticator)
        try lockAfterTenMinutes(app, clock: clock)
        let first = Task { await app.unlockAfterIdle() }
        await gate.untilARequestWaits()

        // Odemknout once more while the prompt waits for the person.
        await app.unlockAfterIdle()

        #expect(authenticator.reasons.count == 1)
        #expect(app.isIdleLocked)
        await gate.open()
        await first.value
        #expect(!app.isIdleLocked)
    }

    // MARK: What waits for the unlock

    @Test func aUniformRateOfferWaitsUntilUnlocked() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let clock = ManualClock(localNoon(2026, 10, 17))
        let app = try await makeApp(in: directory, clock: clock)
        try await #require(app.database).execute("DELETE FROM uniform_rate WHERE year = 2025")
        let finding = try gfrFinding2025()
        try lockAfterTenMinutes(app, clock: clock)

        await app.offerUniformRate(finding)

        // The rates wait for the person, as always; their sheet waits for the unlock, as it would show them.
        #expect(app.pendingUniformRate == finding)
        #expect(app.uniformRateOffer == nil)

        await app.unlockAfterIdle()

        #expect(app.uniformRateOffer == finding)
    }

    @Test func voiceOverIsToldOfChangesOnlyOnceTheAppIsUnlocked() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let clock = ManualClock(localNoon(2026, 10, 17))
        let app = try await makeApp(in: directory, clock: clock)
        var announced: [String] = []
        app.announce = { announced.append($0) }
        try lockAfterTenMinutes(app, clock: clock)

        app.handleDayChanged(civilDate("2027-01-01"))
        app.uniformRateReminderYear = 2026

        #expect(app.newYearBanner == 2026)
        #expect(announced.isEmpty)

        await app.unlockAfterIdle()

        #expect(
            announced == [NewYearBanner.text(finishedYear: 2026), UniformRateReminderBanner.text(year: 2026)])
    }

    @Test func aRestoreThatEndsWhileTheAppIsLockedLeavesItLocked() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let clock = ManualClock(localNoon(2026, 10, 17))
        let app = try await makeApp(in: directory, clock: clock)
        try await #require(app.database).saveInvoice(Invoice.fixture())
        await app.didWriteAndBackUp()
        let backup = try #require(try app.backups.localBackups().first)
        try lockAfterTenMinutes(app, clock: clock)

        // A restore started before the lock, which ends under it.
        _ = try await app.restoreWhileOpen(from: backup.url, recoveryCode: nil)

        #expect(app.phase == .ready)
        #expect(app.isIdleLocked)
    }

    @Test func aLockOfTheDataTakesOverFromTheLockAfterInactivity() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let clock = ManualClock(localNoon(2026, 10, 17))
        let scheduler = ManualScheduler()
        let app = try await makeApp(in: directory, clock: clock, scheduler: scheduler)
        try lockAfterTenMinutes(app, clock: clock)

        app.lockAfterFailedChange(
            .newCode(number: 2, created: civilDate("2026-10-17"), replacedLabel: nil, replacedNumber: nil))

        // The locked screen of the data asks for Touch ID or the password itself.
        #expect(app.phase == .locked)
        #expect(!app.isIdleLocked)
        // Nothing is checked while the data is locked.
        #expect(scheduler.armed.isEmpty)
    }

    @Test func unlockingTheDataAfterItsLockStartsUnlockedWithTheChecksRunning() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let clock = ManualClock(localNoon(2026, 10, 17))
        let scheduler = ManualScheduler()
        let app = try await makeApp(in: directory, clock: clock, scheduler: scheduler)
        try lockAfterTenMinutes(app, clock: clock)
        // A new recovery code that was under way fails half way under the lock: the vault locks the data, and so does
        // the app.
        let trap = try VaultStepTrap.failingRekey(of: app)
        await #expect(throws: SQLiteError.self) {
            _ = try await app.commitNewRecoveryCode(try app.vault.prepareNewRecoveryCode())
        }
        trap.release()
        #expect(app.phase == .locked)
        #expect(!app.isIdleLocked)
        #expect(scheduler.armed.isEmpty)
        clock.advance(by: 60)

        // Odemknout on the locked screen of the data.
        await app.unlockWithDevice()

        #expect(app.phase == .ready)
        #expect(!app.isIdleLocked)
        #expect(scheduler.armed == [clock.now() + 15])
        clock.advance(by: 9 * 60 + 59)
        try await checkOnTimer(scheduler)
        #expect(!app.isIdleLocked)
    }

    @Test func dataOpenedUnderTheLockDropsWhatWaitedForTheUnlock() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let clock = ManualClock(localNoon(2026, 10, 17))
        let app = try await makeApp(in: directory, clock: clock)
        let database = try #require(app.database)
        try await database.execute("DELETE FROM uniform_rate WHERE year = 2025")
        let finding = try gfrFinding2025()
        var announced: [String] = []
        app.announce = { announced.append($0) }
        try lockAfterTenMinutes(app, clock: clock)
        await app.offerUniformRate(finding)
        app.uniformRateReminderYear = 2026

        // The data is opened anew under the lock, as at the end of a restore that started before it.
        await app.open(database)
        await app.unlockAfterIdle()

        // The sheet and the text were of the data as it was; the rates still wait in Nastavení.
        #expect(app.pendingUniformRate == finding)
        #expect(app.uniformRateOffer == nil)
        #expect(announced.isEmpty)
    }

    @Test func aSheetThatWaitedIsNotShownWhenItsRatesNoLongerWait() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let clock = ManualClock(localNoon(2026, 10, 17))
        let app = try await makeApp(in: directory, clock: clock)
        try await #require(app.database).execute("DELETE FROM uniform_rate WHERE year = 2025")
        try lockAfterTenMinutes(app, clock: clock)
        await app.offerUniformRate(try gfrFinding2025())

        // The rates of the year were stored meanwhile: nothing waits for them any more.
        app.noteUniformRatesStored(forYear: 2025)
        await app.unlockAfterIdle()

        #expect(app.pendingUniformRate == nil)
        #expect(app.uniformRateOffer == nil)
    }

    // MARK: What a launch knows of the lock

    /// The time of the lock is kept outside the data, for the locked screen of the next launch, which shows before the
    /// data is open: whenever the data opens, and whenever a time is chosen. Before anything has been kept, a launch
    /// knows the 10 minutes of the default.
    @Test func theTimeOfTheLockIsKeptOutsideTheDataWhenTheDataOpensAndWhenItIsChosen() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let mirror = MemoryIdleLockMirror()
        let app = makeAppModel(in: directory, idleLockMirror: mirror)
        #expect(app.idleLockBeforeOpening == .tenMinutes)

        try await startFresh(app)

        #expect(mirror.read() == .tenMinutes)

        await SecurityTabModel(app: app).setIdleLock(.oneHour)

        #expect(mirror.read() == .oneHour)
        #expect(app.idleLockBeforeOpening == .oneHour)

        // A launch that opens the data keeps what the data holds, whatever was kept before.
        mirror.write(.fiveMinutes)
        await app.database?.close()
        let next = makeAppModel(in: directory, idleLockMirror: mirror)
        #expect(next.idleLockBeforeOpening == .fiveMinutes)

        await next.launch()

        #expect(next.phase == .ready)
        #expect(mirror.read() == .oneHour)
    }

    /// The app keeps the time in its user defaults: here in a suite of the test's own, which it removes afterwards.
    /// A number that is no time of the menu reads as nothing kept.
    @Test func theTimeIsKeptInTheUserDefaults() {
        let suite = "InvoicesTrackerTests.idleLock.\(UUID().uuidString)"
        defer { UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite) }
        let mirror = DefaultsIdleLockMirror(suiteName: suite)
        #expect(mirror.read() == nil)

        mirror.write(.thirtyMinutes)

        #expect(mirror.read() == .thirtyMinutes)
        #expect(DefaultsIdleLockMirror(suiteName: suite).read() == .thirtyMinutes)

        mirror.write(.never)

        #expect(mirror.read() == .never)

        UserDefaults(suiteName: suite)?.set(7, forKey: DefaultsIdleLockMirror.key)

        #expect(mirror.read() == nil)
    }

    // MARK: What follows the lock

    /// What the windows were told as the lock came: whether the app was locked already at each notice.
    @MainActor
    private final class Notices {
        var lockedAtNotice: [Bool] = []
    }

    /// The windows are told that the lock is about to come before it does, while the focus is still where the person
    /// left it, and only then: once for each lock.
    @Test func theWindowsAreToldOfTheLockJustBeforeItComes() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let clock = ManualClock(localNoon(2026, 10, 17))
        let app = makeAppModel(in: directory, clock: clock)
        try await startFresh(app)
        let notices = Notices()
        let observation = NotificationCenter.default.addObserver(
            forName: AppModel.idleLockWillCome, object: app, queue: nil
        ) { _ in
            MainActor.assumeIsolated {
                notices.lockedAtNotice.append(app.isIdleLocked)
            }
        }
        defer { NotificationCenter.default.removeObserver(observation) }

        clock.advance(by: 10 * 60 - 1)
        app.checkIdleLock(now: clock.now())

        #expect(notices.lockedAtNotice.isEmpty)

        clock.advance(by: 1)
        app.checkIdleLock(now: clock.now())
        app.checkIdleLock(now: clock.now() + 60)

        #expect(app.isIdleLocked)
        #expect(notices.lockedAtNotice == [false])
    }

    // MARK: The print panel

    /// The print panel of a recovery code shows the code over the lock, so the lock cancels it as it comes, once.
    @Test func theLockCancelsThePrintPanelOfARecoveryCode() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let clock = ManualClock(localNoon(2026, 10, 17))
        let app = makeAppModel(in: directory, clock: clock)
        try await startFresh(app)
        var cancelled = 0
        app.cancelPrintPanel = { cancelled += 1 }

        clock.advance(by: 10 * 60 - 1)
        app.checkIdleLock(now: clock.now())

        #expect(cancelled == 0)

        clock.advance(by: 1)
        app.checkIdleLock(now: clock.now())

        #expect(app.isIdleLocked)
        #expect(cancelled == 1)

        app.noteActivity(at: clock.now() + 60)
        app.checkIdleLock(now: clock.now() + 120)

        #expect(cancelled == 1)
    }

    // MARK: Menus and sheets over the lock

    /// A menu that is open when the lock comes would stay over it, with what it lists — the years with data, say — and
    /// a choice in it would act under the lock: the lock closes it, once.
    @Test func theLockClosesTheMenuThatIsOpen() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let clock = ManualClock(localNoon(2026, 10, 17))
        let app = makeAppModel(in: directory, clock: clock)
        try await startFresh(app)
        var closed = 0
        app.closeOpenMenu = { closed += 1 }

        clock.advance(by: 10 * 60 - 1)
        app.checkIdleLock(now: clock.now())

        #expect(closed == 0)

        clock.advance(by: 1)
        app.checkIdleLock(now: clock.now())
        app.checkIdleLock(now: clock.now() + 60)

        #expect(app.isIdleLocked)
        #expect(closed == 1)
    }

    /// The menu that is open is followed from the beginning of its tracking to its end, a submenu within it too:
    /// closing then cancels its tracking, as a click outside it would, and once it has ended, closing leaves it be.
    @Test func theMenuThatIsOpenIsClosedAndOneThatEndedIsLeftBe() {
        let center = NotificationCenter()
        let menus = OpenMenu(center: center)
        menus.follow()
        let years = RecordingMenu(title: "Rok")
        let submenu = RecordingMenu(title: "Podnabídka")

        menus.close()

        #expect(years.cancellations == 0)

        center.post(name: NSMenu.didBeginTrackingNotification, object: years)
        center.post(name: NSMenu.didBeginTrackingNotification, object: submenu)
        center.post(name: NSMenu.didEndTrackingNotification, object: submenu)
        menus.close()

        #expect(years.cancellations == 1)

        center.post(name: NSMenu.didEndTrackingNotification, object: years)
        menus.close()

        #expect(years.cancellations == 1)
        #expect(submenu.cancellations == 0)
    }

    /// The app follows its menus from its launch (`AppDelegate`), so that the lock finds the one that is open.
    @Test func theAppFollowsItsMenusFromItsLaunch() {
        #expect(OpenMenu.shared.isFollowing)
    }

    /// A sheet that would show what it holds over the lock is a sheet of the app's own without the lock over it
    /// (`idleLockCover()`): SwiftUI shows a sheet in a window. The panels of the system — alerts, the print panel, open
    /// and save panels — show no data, or the lock cancels them.
    @Test func onlyASheetOfTheAppsOwnWithoutTheLockOverItIsUncovered() {
        let guarded = NSHashTable<NSWindow>.weakObjects()
        let sheet = NSWindow()
        let alert = NSAlert().window

        #expect(IdleLockSheets.isUncovered(sheet, among: guarded))
        #expect(!IdleLockSheets.isUncovered(alert, among: guarded))
        #expect(!IdleLockSheets.isUncovered(NSPanel(), among: guarded))
        #expect(!IdleLockSheets.isUncovered(NSSavePanel(), among: guarded))

        guarded.add(sheet)

        #expect(!IdleLockSheets.isUncovered(sheet, among: guarded))
    }

    // MARK: The activity monitor

    @Test func pointerKeysWheelAndGesturesAreActivityAndGoOnUnchanged() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let clock = ManualClock(localNoon(2026, 10, 17))
        let app = makeAppModel(in: directory, clock: clock)
        try await startFresh(app)
        let monitor = IdleActivityMonitor(app: app)
        #expect(
            IdleActivityMonitor.activityEvents == [
                .mouseMoved, .leftMouseDown, .rightMouseDown, .otherMouseDown, .leftMouseDragged, .rightMouseDragged,
                .otherMouseDragged, .scrollWheel, .keyDown, .magnify, .smartMagnify, .rotate, .swipe,
            ])

        for event in [
            try mouseEvent(.mouseMoved), try mouseEvent(.leftMouseDown), try mouseEvent(.leftMouseDragged),
            try wheelEvent(), try keyEvent(),
        ] {
            clock.advance(by: 9 * 60)

            #expect(monitor.handle(event) === event)

            // The countdown starts at the event, at the time of the app's clock: 9 minutes 59 seconds after it, more
            // than 10 minutes after the one before it, the app is not locked.
            app.checkIdleLock(now: clock.now() + 9 * 60 + 59)
            #expect(!app.isIdleLocked)
        }
        app.checkIdleLock(now: clock.now() + 10 * 60)
        #expect(app.isIdleLocked)
    }

    @Test func theEventThatFindsTheTimeUpLocksTheAppAndGoesNoFurther() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let clock = ManualClock(localNoon(2026, 10, 17))
        let app = makeAppModel(in: directory, clock: clock)
        try await startFresh(app)
        let monitor = IdleActivityMonitor(app: app)
        let click = try mouseEvent(.leftMouseDown)

        clock.advance(by: 10 * 60)

        // The click was meant for what the lock now hides.
        #expect(monitor.handle(click) == nil)
        #expect(app.isIdleLocked)
        // On the lock, the events go on: to its card and Odemknout.
        #expect(monitor.handle(click) === click)
        #expect(app.isIdleLocked)
    }

    @Test func onlyAnOpenOrSavePanelOnScreenHoldsTheLockOffNotAnAlert() {
        let window = NSWindow()
        let alert = NSAlert().window
        let savePanel = NSSavePanel()
        let openPanel = NSOpenPanel()

        // An alert run app-modally, such as "Zahodit rozepsanou fakturu?" at a quit: the app locks under it.
        #expect(!IdleActivityMonitor.panelIsUp(modalWindow: alert, windows: [window, alert]))
        // An open or save panel run with runModal(): it shows files, not the data.
        #expect(IdleActivityMonitor.panelIsUp(modalWindow: savePanel, windows: [window, savePanel]))
        #expect(IdleActivityMonitor.panelIsUp(modalWindow: openPanel, windows: [window, openPanel]))
        // One shown as a sheet of a window, as fileImporter shows it, is no modal window of the app.
        #expect(IdleActivityMonitor.panelIsUp(modalWindow: nil, windows: [window, ShownOpenPanel()]))
        // A panel that is not on screen, such as one that was never shown, holds nothing off.
        #expect(!IdleActivityMonitor.panelIsUp(modalWindow: nil, windows: [NSOpenPanel()]))
        #expect(!IdleActivityMonitor.panelIsUp(modalWindow: nil, windows: [window, openPanel, savePanel]))
        #expect(!IdleActivityMonitor.panelIsUp(modalWindow: nil, windows: [window, alert]))
        #expect(!IdleActivityMonitor.panelIsUp(modalWindow: nil, windows: []))
    }

    @Test func theMonitorWatchesTheEventsFromItsStartUntilItsStop() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let app = makeAppModel(in: directory)
        try await startFresh(app)
        let monitor = IdleActivityMonitor(app: app)
        #expect(!monitor.isRunning)

        monitor.start()
        monitor.start()

        #expect(monitor.isRunning)

        monitor.stop()

        #expect(!monitor.isRunning)
    }
}
