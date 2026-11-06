import Foundation
import os
import Testing
@testable import InvoicesTracker

/// Keeps a database busy until `end()`, so that what is asked of it meanwhile waits: for a test that needs a read or a
/// write to be still running while something else happens. The hold runs on the actor of the database and keeps its
/// thread while it waits, so the test must wait for nothing that needs the database until it ends the hold: either the
/// database is one that nothing the test waits for needs any more, such as one that a restore has closed and replaced,
/// or the test ends the hold before it waits for what it asked of the database. A test also ends the hold in a
/// `defer`, so that one that stops early does not leave the database held. If the database never runs the hold, the
/// init records an issue after 5 seconds and returns, so that the test ends instead of hanging.
final class DatabaseHold: Sendable {
    private let release = DispatchSemaphore(value: 0)
    private let isHolding = OSAllocatedUnfairLock(initialState: false)

    /// Holds `database`, and returns once the hold runs on its actor: whatever is asked of the database from now on
    /// waits for `end()`. It also returns, with an issue recorded, when the hold has not started after 5 seconds.
    init(_ database: Database) {
        Task.detached { [release, isHolding] in
            _ = try? await database.read { _ in
                isHolding.withLock { $0 = true }
                release.wait()
            }
            isHolding.withLock { $0 = true }
        }
        let deadline = Date.now.addingTimeInterval(5)
        while !isHolding.withLock({ $0 }) {
            guard Date.now < deadline else {
                Issue.record("The hold on the database did not start within 5 seconds.")
                return
            }
            Thread.sleep(forTimeInterval: 0.001)
        }
    }

    /// Ends the hold: what was asked of the database runs. Ending it again does nothing more.
    func end() {
        release.signal()
    }
}
