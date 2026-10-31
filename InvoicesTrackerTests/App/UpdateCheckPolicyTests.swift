import Testing
@testable import InvoicesTracker

/// Which update checks the updater may make. The tests run in a Debug build, which refuses the daily check in the
/// background and allows the check the person asks for.
struct UpdateCheckPolicyTests {
    /// This Debug build refuses background checks alone, and a build that does not refuse them allows them.
    @Test func debugBuildsRefuseBackgroundChecksButNotManualOnes() {
        #expect(UpdateCheckPolicy.refusesBackgroundChecks)
        #expect(!UpdateCheckPolicy.allows(.background, refusingBackgroundChecks: true))
        #expect(UpdateCheckPolicy.allows(.userInitiated, refusingBackgroundChecks: true))
        #expect(UpdateCheckPolicy.allows(.informationOnly, refusingBackgroundChecks: true))
        #expect(UpdateCheckPolicy.allows(.background, refusingBackgroundChecks: false))
    }
}
