import Foundation
import Testing
import os
@testable import InvoicesTracker

/// What a test made that can outlive it: its app models and its temporary folders. A write starts its backups in a
/// task of its own (`AppModel.didWrite()`), and a test that does not wait for them can end, and remove its folder,
/// while they run; a backup that runs after that makes the folder again (`Data/Backups`), and the folder stays behind.
/// For the tests of a suite with the trait `.settlesBackups`, `makeAppModel` and `makeTemporaryDirectory()` tell the
/// one of the test that runs what they made, and the trait waits for the backups when the test ends and removes the
/// folders once more (`settle()`).
final class TestLeftovers: Sendable {
    /// The one of the test that runs, while `SettlesBackupsTrait` has made one for it; nil otherwise.
    @TaskLocal static var current: TestLeftovers?

    /// An app model of the test, held weakly: the test may look at whether its app goes. An app that has gone has no
    /// backup that runs, as a backup that runs holds its app.
    private struct Made {
        weak var app: AppModel?
    }

    private struct State {
        var apps: [Made] = []
        var folders: [URL] = []
    }

    private let state = OSAllocatedUnfairLock(initialState: State())

    /// Keeps `app` to wait for its backups when the test ends, if it is still there then.
    func add(_ app: AppModel) {
        state.withLock { $0.apps.append(Made(app: app)) }
    }

    /// Keeps `folder` to remove it again when the test ends.
    func add(folder: URL) {
        state.withLock { $0.folders.append(folder) }
    }

    /// Waits until the backups of every app model of the test have ended (`AppModel.settleBackups()`), and then
    /// removes the temporary folders of the test again: a backup that ended after the test removed a folder made it
    /// anew.
    @MainActor
    func settle() async {
        let (apps, folders) = state.withLock { ($0.apps, $0.folders) }
        for made in apps {
            await made.app?.settleBackups()
        }
        for folder in folders {
            removeTemporaryDirectory(folder)
        }
    }
}

extension AppModel {
    /// Waits until the backups that writes started have ended (`backupsAfterWrite`), those of writes made while it
    /// waits too, and the backup outside the Mac that runs, if one does.
    func settleBackups() async {
        while true {
            let afterWrites = backupsAfterWrite
            let outsideTheMac = offMacBackupRun
            await afterWrites?.value
            _ = await outsideTheMac?.value
            if backupsAfterWrite == afterWrites, offMacBackupRun == outsideTheMac {
                return
            }
        }
    }
}

/// The trait of a suite whose tests write through app models without waiting for the backups that the writes start:
/// each of its tests ends only once those backups have ended, and its temporary folders are then removed once more
/// (`TestLeftovers`), so that no backup leaves a folder of the test behind.
struct SettlesBackupsTrait: SuiteTrait, TestTrait, TestScoping {
    var isRecursive: Bool {
        true
    }

    /// A scope around each test, none around the suite.
    func scopeProvider(for test: Test, testCase: Test.Case?) -> Self? {
        testCase == nil ? nil : self
    }

    func provideScope(
        for test: Test, testCase: Test.Case?, performing function: @concurrent @Sendable () async throws -> Void
    ) async throws {
        let leftovers = TestLeftovers()
        do {
            try await TestLeftovers.$current.withValue(leftovers) {
                try await function()
            }
        } catch {
            await leftovers.settle()
            throw error
        }
        await leftovers.settle()
    }
}

extension Trait where Self == SettlesBackupsTrait {
    /// Each test of the suite waits for the backups its writes started before it ends (`SettlesBackupsTrait`).
    static var settlesBackups: Self {
        SettlesBackupsTrait()
    }
}
