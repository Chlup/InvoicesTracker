import CryptoKit
import Foundation
import Testing
import os
@testable import InvoicesTracker

/// Seals and opens like `SoftwareKeyProtector` and takes the same slots for its own, unless the test says otherwise:
/// while `openFailure` is set, opening a slot throws it — a Touch ID prompt that was dismissed (`.userCancelled`), a
/// device key this Mac cannot use (`.deviceKeyUnusable`) — and while `sealFailure` is set, sealing throws it. A test
/// changes them between the steps of one app model, as a person who tries again would.
final class ScriptedKeyProtector: DeviceKeyProtector {
    private struct Failures {
        var open: KeyError?
        var seal: KeyError?
    }

    private let failures: OSAllocatedUnfairLock<Failures>

    init(openFailure: KeyError? = nil, sealFailure: KeyError? = nil) {
        failures = OSAllocatedUnfairLock(initialState: Failures(open: openFailure, seal: sealFailure))
    }

    /// What opening a slot throws, or nil when it opens the slot.
    var openFailure: KeyError? {
        get { failures.withLock { $0.open } }
        set { failures.withLock { $0.open = newValue } }
    }

    /// What sealing a data key throws, or nil when it seals it.
    var sealFailure: KeyError? {
        get { failures.withLock { $0.seal } }
        set { failures.withLock { $0.seal = newValue } }
    }

    var name: String {
        SoftwareKeyProtector().name
    }

    func seal(_ dek: SymmetricKey, userPresence: Bool) throws -> DeviceSlot {
        if let failure = sealFailure {
            throw failure
        }
        return try SoftwareKeyProtector().seal(dek, userPresence: userPresence)
    }

    func canOpen(_ slot: DeviceSlot) -> Bool {
        SoftwareKeyProtector().canOpen(slot)
    }

    func open(_ slot: DeviceSlot, reason: String) async throws -> SymmetricKey {
        if let failure = openFailure {
            throw failure
        }
        return try await SoftwareKeyProtector().open(slot, reason: reason)
    }
}

/// The software protector of this Mac that counts the prompts it shows: like the Secure Enclave, it asks for Touch ID
/// or the password before it knows whether the key of a slot with user presence loads, and only then fails for a slot
/// it cannot open. It takes the slots `SoftwareKeyProtector` takes for its own.
final class PromptCountingProtector: DeviceKeyProtector {
    private let count = OSAllocatedUnfairLock(initialState: 0)

    /// How many times opening a slot asked the person.
    var prompts: Int {
        count.withLock { $0 }
    }

    var name: String {
        SoftwareKeyProtector().name
    }

    func seal(_ dek: SymmetricKey, userPresence: Bool) throws -> DeviceSlot {
        try SoftwareKeyProtector().seal(dek, userPresence: userPresence)
    }

    func canOpen(_ slot: DeviceSlot) -> Bool {
        SoftwareKeyProtector().canOpen(slot)
    }

    func open(_ slot: DeviceSlot, reason: String) async throws -> SymmetricKey {
        if slot.userPresence {
            count.withLock { $0 += 1 }
        }
        return try await SoftwareKeyProtector().open(slot, reason: reason)
    }
}

/// The software protector of another Mac: it seals and opens like `SoftwareKeyProtector`, under a name of its own, so
/// neither opens the slots of the other, as the Secure Enclaves of two Macs do not.
struct OtherMacProtector: DeviceKeyProtector {
    var name: String {
        "software-other-mac"
    }

    func seal(_ dek: SymmetricKey, userPresence: Bool) throws -> DeviceSlot {
        var slot = try SoftwareKeyProtector().seal(dek, userPresence: userPresence)
        slot.protector = name
        return slot
    }

    func canOpen(_ slot: DeviceSlot) -> Bool {
        slot.protector == name && SoftwareKeyProtector().canOpen(asSoftware(slot))
    }

    func open(_ slot: DeviceSlot, reason: String) async throws -> SymmetricKey {
        guard slot.protector == name else {
            throw KeyError.deviceKeyUnusable
        }
        return try await SoftwareKeyProtector().open(asSoftware(slot), reason: reason)
    }

    private func asSoftware(_ slot: DeviceSlot) -> DeviceSlot {
        var software = slot
        software.protector = SoftwareKeyProtector().name
        return software
    }
}

/// Stands in for Touch ID or the Mac password when the app asks the person to prove who they are
/// (`OwnerAuthenticator`): it answers `answer`, which is true unless the test says otherwise, and keeps the reason of
/// every prompt, in order. A test can hold the prompts at a gate, as a person who has not answered yet.
final class ScriptedOwnerAuthenticator: OwnerAuthenticator {
    private struct State {
        var answer: Bool
        var reasons: [String] = []
        var gate: Gate?
    }

    private let state: OSAllocatedUnfairLock<State>

    init(answer: Bool = true) {
        state = OSAllocatedUnfairLock(initialState: State(answer: answer))
    }

    /// What the next prompt answers: whether the person proved who they are.
    var answer: Bool {
        get { state.withLock { $0.answer } }
        set { state.withLock { $0.answer = newValue } }
    }

    /// The reason of every prompt so far, in order.
    var reasons: [String] {
        state.withLock { $0.reasons }
    }

    /// Holds every prompt from now on at `gate` until it opens.
    func hold(at gate: Gate) {
        state.withLock { $0.gate = gate }
    }

    func authenticate(reason: String) async -> Bool {
        let gate = state.withLock { state -> Gate? in
            state.reasons.append(reason)
            return state.gate
        }
        await gate?.pass()
        return answer
    }
}

/// The time of the lock after inactivity kept outside the data (`IdleLockMirror`), in memory: nothing until the app
/// or the test writes it.
final class MemoryIdleLockMirror: IdleLockMirror {
    private let time = OSAllocatedUnfairLock<IdleLockTime?>(initialState: nil)

    func read() -> IdleLockTime? {
        time.withLock { $0 }
    }

    func write(_ newTime: IdleLockTime) {
        time.withLock { $0 = newTime }
    }
}

/// Noon of the day in the Mac's own time zone and in the Gregorian calendar. An app model of the tests has its clock at
/// such a noon and the Mac's time zone, so its day is the day of the vault too, which dates the recovery codes in the
/// Mac's time zone, wherever the tests run.
func localNoon(_ year: Int, _ month: Int, _ day: Int) -> Date {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = .autoupdatingCurrent
    guard let value = calendar.date(from: DateComponents(year: year, month: month, day: day, hour: 12)) else {
        preconditionFailure("Not a day: \(year)-\(month)-\(day)")
    }
    return value
}

/// A wait that lasts until the task that waits is cancelled: an hour is longer than a test, and in a full run of the
/// suite the process is so busy that any shorter limit of the app could run out before the work it bounds is done.
let patientWait: @Sendable (Duration) async throws -> Void = { _ in
    try await Task.sleep(for: .seconds(3_600))
}

/// An app model of the data in the folder `Data` inside `directory`, as one launch of the app makes it: `device` stands
/// in for the Secure Enclave, `authenticator` for the prompt of Touch ID or the password (which says yes unless given),
/// the clock is at noon of 17 October 2026 unless given, the time zone is the Mac's, the server answers nothing unless
/// given, the refresh is made but not started unless `startsRefresh`, the lock after inactivity is checked only when
/// the test checks it and no window watches the activity in the app unless `startsIdleChecks`, no open or save panel is
/// ever up for it unless the test says so (`AppModel.modalPanelIsUp`), the wakes of the Mac and the changes of its
/// clock come to centers of the model's own (`AppDependencies.workspaceNotifications`, `systemNotifications`), what the
/// app bounds with a wait (`AppDependencies.sleep`) is bounded by one that lasts until it is cancelled unless `sleep`
/// says otherwise, the bookmark of the folder outside the Mac is resolved by the system unless `resolveBookmark` says
/// otherwise, the time of the lock after inactivity is kept outside the data in memory (`idleLockMirror`, empty unless
/// given), and neither a print panel nor a menu of the test host is closed when the model locks
/// (`AppModel.cancelPrintPanel`, `closeOpenMenu`). A test of a suite with `.settlesBackups` waits for the backups of
/// the model when it ends (`TestLeftovers`).
@MainActor
func makeAppModel(
    in directory: URL,
    device: any DeviceKeyProtector = SoftwareKeyProtector(),
    authenticator: any OwnerAuthenticator = ScriptedOwnerAuthenticator(),
    clock: ManualClock = ManualClock(localNoon(2026, 10, 17)),
    http: any HTTPClient = StubHTTPClient(),
    scheduler: ManualScheduler = ManualScheduler(),
    startsRefresh: Bool = false,
    startsIdleChecks: Bool = false,
    sleep: @escaping @Sendable (Duration) async throws -> Void = patientWait,
    resolveBookmark: @escaping @Sendable (Data, URL.BookmarkResolutionOptions) async throws -> URL =
        BackupService.resolveBookmark,
    idleLockMirror: any IdleLockMirror = MemoryIdleLockMirror()
) -> AppModel {
    let app = AppModel(
        dependencies: AppDependencies(
            paths: VaultPaths(directory: directory.appending(path: "Data", directoryHint: .isDirectory)),
            device: device,
            authenticator: authenticator,
            clock: clock,
            http: http,
            scheduler: scheduler,
            timeZone: { TimeZone.autoupdatingCurrent },
            startsRefresh: startsRefresh,
            startsIdleChecks: startsIdleChecks,
            workspaceNotifications: NotificationCenter(),
            systemNotifications: NotificationCenter(),
            idleLockMirror: idleLockMirror,
            sleep: sleep,
            resolveBookmark: resolveBookmark
        )
    )
    // The panels of the test host's windows are none of the model's business.
    app.modalPanelIsUp = { false }
    app.cancelPrintPanel = {}
    app.closeOpenMenu = {}
    TestLeftovers.current?.add(app)
    return app
}

/// Resolves the bookmark of the folder outside the Mac as the system does, and records the options of every
/// resolution, in order: whether a backup asked for it with the system's UI or without. A test can make the folder fail
/// to resolve, as a disk that is not connected, or hold every resolution from then on at a gate, as a share that does
/// not answer.
final class RecordingFolderResolver: Sendable {
    private struct State {
        var options: [URL.BookmarkResolutionOptions] = []
        var failing = false
        var gate: Gate?
    }

    private let state = OSAllocatedUnfairLock(uncheckedState: State())

    /// The options of every resolution so far, in order.
    var options: [URL.BookmarkResolutionOptions] {
        state.withLockUnchecked { $0.options }
    }

    /// Whether the folder fails to resolve from now on.
    var failing: Bool {
        get { state.withLockUnchecked { $0.failing } }
        set { state.withLockUnchecked { $0.failing = newValue } }
    }

    /// Holds every resolution from now on at `gate` until it opens.
    func hold(at gate: Gate) {
        state.withLockUnchecked { $0.gate = gate }
    }

    /// The resolution as the app takes it.
    var resolve: @Sendable (Data, URL.BookmarkResolutionOptions) async throws -> URL {
        { [self] bookmark, options in
            let gate = state.withLockUnchecked { state -> Gate? in
                state.options.append(options)
                return state.gate
            }
            await gate?.pass()
            if failing {
                throw BackupError.folderUnavailable
            }
            return try await BackupService.resolveBookmark(bookmark, options: options)
        }
    }
}

/// Launches `model` on a folder without data and goes through the first launch as a person who starts with empty data:
/// the recovery code is stored, the supplier skipped and the import declined. The model is then ready, on Přehled.
/// Returns the recovery code.
@MainActor
@discardableResult
func startFresh(_ model: AppModel) async throws -> String {
    await model.launch()
    try await model.startFresh()
    guard case .onboarding(.recoveryCode(let code, _, _, _)) = model.phase else {
        throw AppModelTestError.unexpectedPhase(model.phase)
    }
    try await model.finishRecoveryCodeStep(touchID: true)
    model.skipSupplierStep()
    model.finishOnboarding(importNow: false)
    guard model.phase == .ready else {
        throw AppModelTestError.unexpectedPhase(model.phase)
    }
    return code
}

enum AppModelTestError: Error {
    case unexpectedPhase(AppPhase)
}

extension AppModel {
    /// Tells the model of a write, as a screen does (`didWrite()`), and waits for the backups that the write started,
    /// which the screen does not wait for: for a test that looks at what they made or recorded.
    func didWriteAndBackUp() async {
        await didWrite()
        await backupsAfterWrite?.value
    }
}

/// Waits until `condition` holds, looking every few milliseconds: for what an app model does in a task of its own, such
/// as the backup that an armed wake starts or the work a callback of the refresh starts. Records an issue when it does
/// not hold within `timeout`. Only the time that the loop ran counts (`holdsWithin(_:every:_:)`).
@MainActor
func waitUntil(
    timeout: Duration = .seconds(10),
    sourceLocation: SourceLocation = #_sourceLocation,
    _ condition: @MainActor () async throws -> Bool
) async throws {
    guard try await holdsWithin(timeout, condition) else {
        Issue.record("The condition did not hold within \(timeout).", sourceLocation: sourceLocation)
        return
    }
}

/// Looks at `condition` at once and then every `interval` until it holds, and tells whether it held within `timeout`;
/// it records no issue, so a test that wants its own words for a condition that did not hold can use it, as
/// `waitUntil(timeout:sourceLocation:_:)` and `expectContainers(_:in:_:sourceLocation:)` do. Only the time that the
/// loop ran counts, at most 50 milliseconds for each look, or `interval` where that is longer: in a full run of the
/// suite the process is so busy that one look can wait seconds for its turn, and the condition has had no time to hold
/// in that. A condition that never holds is still given up on, `timeout` after the process is calm.
@MainActor
func holdsWithin(
    _ timeout: Duration = .seconds(10), every interval: Duration = .milliseconds(5),
    _ condition: @MainActor () async throws -> Bool
) async throws -> Bool {
    let clock = ContinuousClock()
    let charge = max(.milliseconds(50), interval)
    var remaining = timeout
    var lookedAt = clock.now
    while !(try await condition()) {
        let now = clock.now
        remaining -= min(now - lookedAt, charge)
        lookedAt = now
        guard remaining > .zero else { return false }
        try await Task.sleep(for: interval)
    }
    return true
}
