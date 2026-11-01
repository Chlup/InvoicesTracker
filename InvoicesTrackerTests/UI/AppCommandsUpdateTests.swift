import Testing
@testable import InvoicesTracker

/// Zkontrolovat aktualizace… in the app menu: the menu offers the check while the app has an updater that can start
/// one, and offers none when the app has no updater. The updater is `FakeUpdater`, so no test starts Sparkle.
@MainActor
struct AppCommandsUpdateTests {
    /// The app has no updater while it hosts the unit tests, so the menu has no check to offer.
    @Test func theMenuOffersNoCheckWithoutAnUpdater() {
        #expect(!AppCommands.offersUpdateCheck(nil))
    }

    /// The menu offers the check while Sparkle's updater can start one, stops offering it while the updater cannot,
    /// and offers it again once the updater can.
    @Test func theMenuOffersACheckWhileSparkleCanStartOne() {
        let updater = FakeUpdater(canCheck: true, automatic: true, lastCheck: nil)
        let updates = UpdatesModel(updater: updater)
        #expect(AppCommands.offersUpdateCheck(updates))

        updater.canCheckForUpdates = false
        updates.refresh()
        #expect(!AppCommands.offersUpdateCheck(updates))

        updater.canCheckForUpdates = true
        updates.refresh()
        #expect(AppCommands.offersUpdateCheck(updates))
    }
}
