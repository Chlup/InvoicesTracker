import Foundation
@testable import InvoicesTracker

/// An updater for the tests, in the place of Sparkle's: it says what the test sets, keeps the daily-check switch it is
/// given, and counts the checks it is asked for instead of making any. Nothing tells the model when the test changes
/// it, so a test calls `UpdatesModel.refresh()` after a change, as `AppUpdater` does when Sparkle's updater changes.
@MainActor
final class FakeUpdater: AppUpdating {
    /// Whether a check can start now.
    var canCheckForUpdates: Bool

    /// Whether the updater checks for a new version once a day by itself.
    var automaticallyChecksForUpdates: Bool

    /// When the updater last checked for a new version, or nil when it never has.
    var lastUpdateCheckDate: Date?

    /// How many checks the updater was asked for.
    private(set) var checkCount = 0

    /// Makes an updater that can check now when `canCheck` is true, checks once a day by itself when `automatic` is
    /// true, and last checked at `lastCheck`.
    init(canCheck: Bool, automatic: Bool, lastCheck: Date?) {
        canCheckForUpdates = canCheck
        automaticallyChecksForUpdates = automatic
        lastUpdateCheckDate = lastCheck
    }

    /// Counts the check instead of making it.
    func checkForUpdates() {
        checkCount += 1
    }
}
