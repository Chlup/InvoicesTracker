import Foundation
import Testing
@testable import InvoicesTracker

struct AppEnvironmentTests {
    @Test func detectsHostedTestRun() {
        #expect(AppEnvironment.isRunningTests)
    }

    @Test func usesFinalBundleIdentifier() {
        #expect(Bundle.main.bundleIdentifier == "info.chlup.InvoicesTracker")
    }

    @Test func manualClockAdvances() {
        let clock = ManualClock(date("2026-10-16T12:00:00Z"))
        clock.advance(by: 60)
        #expect(clock.now() == date("2026-10-16T12:01:00Z"))
    }
}
