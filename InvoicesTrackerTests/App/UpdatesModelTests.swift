import Foundation
import Testing
@testable import InvoicesTracker

/// What the app shows of its updater and asks of it: the model says what the updater says, asks it for a check only
/// while it can check, and passes the switch of the daily check on to it.
@MainActor
struct UpdatesModelTests {
    /// A new model says whether the updater can check, whether it checks daily and when it last checked.
    @Test func theModelMirrorsTheUpdater() {
        let fake = FakeUpdater(canCheck: true, automatic: true, lastCheck: Date(timeIntervalSince1970: 1_000))
        let model = UpdatesModel(updater: fake)
        #expect(model.canCheck)
        #expect(model.checksAutomatically)
        #expect(model.lastCheck == Date(timeIntervalSince1970: 1_000))
    }

    /// Zkontrolovat teď asks for nothing while the updater cannot check, and for one check once it can.
    @Test func checkingNowAsksTheUpdaterOnlyWhenItCan() {
        let fake = FakeUpdater(canCheck: false, automatic: true, lastCheck: nil)
        let model = UpdatesModel(updater: fake)
        model.checkNow()
        #expect(fake.checkCount == 0)
        fake.canCheckForUpdates = true
        model.refresh()
        model.checkNow()
        #expect(fake.checkCount == 1)
    }

    /// Turning Kontrolovat automaticky off turns the updater's daily check off, and the model says so.
    @Test func turningTheDailyCheckOffReachesTheUpdater() {
        let fake = FakeUpdater(canCheck: true, automatic: true, lastCheck: nil)
        let model = UpdatesModel(updater: fake)
        model.setChecksAutomatically(false)
        #expect(fake.automaticallyChecksForUpdates == false)
        #expect(model.checksAutomatically == false)
    }
}
