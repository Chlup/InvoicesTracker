import Foundation
import Testing
@testable import InvoicesTracker

/// The backups a write starts, which the screen that wrote does not wait for, and the backup outside the Mac when its
/// folder does not answer: an automatic one resolves the folder without any UI of the system and waits an hour after
/// one that failed, one the person asked for may show the system's UI and never waits, and a backup that a wait gave up
/// on is not waited for again. Every test has its own folder, the clock is at noon of 17 October 2026 in the Mac's time
/// zone, and the folder outside the Mac is a folder in the test's folder, resolved through a recording resolver.
@Suite(.settlesBackups)
@MainActor
struct AppModelBackupTests {
    private static let day: TimeInterval = 24 * 60 * 60

    /// An app model that has gone through the first launch, with a folder outside the Mac set and its first backup made
    /// (at noon of 17 October 2026, through `resolver`). Returns the app and the folder.
    private func appWithFolder(
        in directory: URL, clock: ManualClock, resolver: RecordingFolderResolver,
        scheduler: ManualScheduler = ManualScheduler(),
        sleep: @escaping @Sendable (Duration) async throws -> Void = patientWait
    ) async throws -> (app: AppModel, folder: URL) {
        let app = try await makeSettingsApp(
            in: directory, clock: clock, scheduler: scheduler, sleep: sleep, resolveBookmark: resolver.resolve)
        let folder = directory.appending(path: "NAS", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        #expect(try await app.setBackupFolder(folder))
        return (app, folder)
    }

    /// The backups in `folder`.
    private func backupCount(in folder: URL) throws -> Int {
        try FileManager.default.contentsOfDirectory(atPath: folder.path(percentEncoded: false))
            .filter { $0.hasSuffix(".ttbackup") }.count
    }

    private let automatic: URL.BookmarkResolutionOptions = [.withSecurityScope, .withoutUI]
    private let asked: URL.BookmarkResolutionOptions = [.withSecurityScope]

    // MARK: A write does not wait for its backups

    @Test(.hangGuard)
    func aSheetSaveReturnsWhileTheBackupOutsideTheMacIsHeldUp() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let clock = ManualClock(localNoon(2026, 10, 17))
        let resolver = RecordingFolderResolver()
        let (app, folder) = try await appWithFolder(in: directory, clock: clock, resolver: resolver)
        // A day later the daily backup outside the Mac is due, and the share does not answer.
        clock.advance(by: Self.day)
        let gate = Gate()
        resolver.hold(at: gate)
        let form = ClientFormModel(app: app, client: nil)
        form.name = "Epsilon Group a.s."

        let saving = Task.immediate { try await form.save() }
        try await waitUntil { !form.isSaving }

        // The client is saved and the sheet can close, while the backup it started waits for the folder.
        #expect(try await #require(app.database).clients().contains { $0.name == "Epsilon Group a.s." })
        await gate.untilARequestWaits()
        #expect(app.offMacBackupRun != nil)
        #expect(!form.isSaving)
        await gate.open()
        _ = try await saving.value
        await app.backupsAfterWrite?.value
        // The backup that waited is made and recorded.
        #expect(try backupCount(in: folder) == 2)
        #expect(app.appSettings.lastOffMacBackup == clock.now())
        #expect(app.appSettings.lastLocalBackup == clock.now())
    }

    @Test func onlyOneLocalBackupRunsAtATimeAndAChangeMadeMeanwhileWaitsForTheNextOne() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let clock = ManualClock(localNoon(2026, 10, 17))
        let scheduler = ManualScheduler()
        let app = try await makeSettingsApp(in: directory, clock: clock, scheduler: scheduler)
        await app.markChangeWaitingForBackup()

        // The backup of a change runs. Another one asked for meanwhile, as by the wake of the backup, makes none, and
        // neither does the write that comes while it runs.
        let running = Task.immediate { await app.backUpLocallyIfDue() }
        let meanwhile = Task.immediate { await app.backUpLocallyIfDue() }
        await app.didWrite()
        await running.value
        await meanwhile.value
        await app.backupsAfterWrite?.value

        #expect(try app.backups.localBackups().count == 1)
        // The change written while the backup ran waits for the next one, an hour later.
        #expect(app.appSettings.localBackupPendingSince != nil)
        #expect(scheduler.armed == [clock.now() + BackupService.localBackupInterval])
    }

    // MARK: The backup outside the Mac when its folder does not answer

    @Test func automaticBackupsOutsideTheMacResolveTheFolderWithoutUIAndTheAskedForOnesMayShowIt() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let clock = ManualClock(localNoon(2026, 10, 17))
        let resolver = RecordingFolderResolver()
        // The first backup into the folder just chosen.
        let (app, _) = try await appWithFolder(in: directory, clock: clock, resolver: resolver)
        #expect(resolver.options == [asked])

        // After a write, a day later.
        clock.advance(by: Self.day)
        await app.didWrite()
        await app.backupsAfterWrite?.value
        #expect(resolver.options == [asked, automatic])

        // Zálohovat teď.
        _ = try await app.backUpNow()
        #expect(resolver.options == [asked, automatic, asked])

        // The daily check, a day later.
        clock.advance(by: Self.day)
        await app.backUpOffMacIfDue()
        #expect(resolver.options == [asked, automatic, asked, automatic])

        // After a change of the keys.
        _ = try await app.setTouchID(false)
        #expect(resolver.options == [asked, automatic, asked, automatic, asked])

        // After a restore, a day later.
        clock.advance(by: Self.day)
        let backup = try #require(try app.backups.localBackups().first)
        _ = try await app.restoreWhileOpen(from: backup.url, recoveryCode: nil)
        #expect(resolver.options == [asked, automatic, asked, automatic, asked, asked])

        // At the launch, a day later.
        let restored = try #require(app.database)
        await restored.close()
        clock.advance(by: Self.day)
        let relaunched = makeAppModel(in: directory, clock: clock, resolveBookmark: resolver.resolve)
        await relaunched.launch()
        #expect(relaunched.phase == .ready)
        #expect(resolver.options == [asked, automatic, asked, automatic, asked, asked, automatic])
    }

    @Test func afterAFailedAutomaticBackupOutsideTheMacTheNextAutomaticOneWaitsAnHourAndOneAskedForDoesNot()
        async throws
    {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let clock = ManualClock(localNoon(2026, 10, 17))
        let resolver = RecordingFolderResolver()
        let (app, folder) = try await appWithFolder(in: directory, clock: clock, resolver: resolver)
        clock.advance(by: Self.day)
        let failedAt = clock.now()
        // The disk is not connected.
        resolver.failing = true

        await app.didWrite()
        await app.backupsAfterWrite?.value
        #expect(resolver.options.count == 2)

        // Within the hour, neither a write nor the daily check tries again.
        clock.advance(by: 10 * 60)
        await app.didWrite()
        await app.backupsAfterWrite?.value
        await app.backUpOffMacIfDue()
        #expect(resolver.options.count == 2)

        // Zálohovat teď tries at once.
        let outcome = try await app.backUpNow()
        #expect(outcome.offMac == false)
        #expect(resolver.options.count == 3)

        // An hour after the failure a write tries again, and the disk is back.
        resolver.failing = false
        clock.set(failedAt + 60 * 60)
        await app.didWrite()
        await app.backupsAfterWrite?.value
        #expect(resolver.options.count == 4)
        #expect(try backupCount(in: folder) == 2)
        #expect(app.appSettings.lastOffMacBackup == clock.now())
    }

    @Test(.hangGuard)
    func aBackupOutsideTheMacThatAWaitGaveUpOnIsNotWaitedForAgainAndRecordsItselfWhenItEnds() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let clock = ManualClock(localNoon(2026, 10, 17))
        let resolver = RecordingFolderResolver()
        let limit = LimitSwitch()
        let (app, folder) = try await appWithFolder(
            in: directory, clock: clock, resolver: resolver, sleep: limit.wait)
        clock.advance(by: Self.day)
        // The share stops answering, and the automatic backup of a write starts and hangs there.
        let gate = Gate()
        resolver.hold(at: gate)
        let write = Task { await app.didWrite() }
        await gate.untilARequestWaits()
        // Its wait runs out.
        limit.runOut()
        await write.value
        await app.backupsAfterWrite?.value
        let hung = try #require(app.offMacBackupRun)
        let waits = limit.asked

        // Zálohovat teď does not wait for it again, and neither does a change of the keys.
        let outcome = try await app.backUpNow()
        #expect(outcome.offMac == false)
        let change = try await app.setTouchID(false)
        #expect(change.offMacBackupMade == false)
        #expect(limit.asked == waits)
        #expect(app.offMacBackupRun == hung)

        // When it ends at last, it records itself, and the next backup is free to run.
        await gate.open()
        _ = await hung.value
        #expect(app.offMacBackupRun == nil)
        #expect(app.appSettings.lastOffMacBackup == clock.now())
        #expect(try backupCount(in: folder) == 2)
    }
}
