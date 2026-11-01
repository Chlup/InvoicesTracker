import Testing
@testable import InvoicesTracker

/// Sparkle's updater as the app starts it.
@MainActor
struct AppUpdaterTests {
    /// The app hosts the unit tests, so it starts no updater, and no test checks for updates.
    @Test func noUpdaterStartsUnderTheTestHost() {
        #expect(AppUpdater.forLaunch(isRunningTests: true) == nil)
    }

    /// Sparkle's own windows, such as the offer of a new version, speak Czech, as the app does.
    @Test func sparklesWindowsSpeakCzech() {
        #expect(AppUpdater.sparkleLanguage == "cs")
    }
}
