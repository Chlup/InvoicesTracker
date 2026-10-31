import Foundation
import Security
import Testing

/// The settings that let the app update itself through Sparkle: the keys in its Info.plist and the sandbox exception in
/// its entitlements. The tests are hosted in the app, so they read the real app's bundle and the entitlements of the
/// process they run in.
struct UpdateSettingsTests {
    /// The app asks the latest release of its repository for the feed and knows the public key that signs it.
    @Test func theAppReadsItsFeedFromTheLatestReleaseAndKnowsTheKey() {
        let info = Bundle.main.infoDictionary ?? [:]
        #expect(
            info["SUFeedURL"] as? String
                == "https://github.com/Chlup/InvoicesTracker/releases/latest/download/appcast.xml")
        #expect(info["SUPublicEDKey"] as? String == "yol1BhN1JRMlvNrXvE3hUMTn9AoNPRjzh4KIPxCTFJ8=")
    }

    /// The app looks for a new version once a day, and an update is never installed without asking first.
    @Test func theAppChecksDailyAndAsksBeforeInstalling() {
        let info = Bundle.main.infoDictionary ?? [:]
        #expect(info["SUEnableAutomaticChecks"] as? Bool == true)
        #expect(info["SUScheduledCheckInterval"] as? Int == 86_400)
        #expect(info["SUAllowsAutomaticUpdates"] as? Bool == false)
        #expect(info["SUAutomaticallyUpdate"] as? Bool == false)
    }

    /// The feed and the archives must be signed, an archive is verified before it is opened, and the installer runs
    /// through Sparkle's launcher service. The system profile is not sent, and the interval of Sparkle's recovery from
    /// a lost signing key stays at Sparkle's default, so neither of those two keys is set.
    @Test func theAppTrustsOnlySignedFeedsAndArchives() {
        let info = Bundle.main.infoDictionary ?? [:]
        #expect(info["SURequireSignedFeed"] as? Bool == true)
        #expect(info["SUVerifyUpdateBeforeExtraction"] as? Bool == true)
        #expect(info["SUEnableInstallerLauncherService"] as? Bool == true)
        #expect(info["SUEnableSystemProfiling"] == nil)
        #expect(info["SUSignedFeedFailureExpirationInterval"] == nil)
    }

    /// The Info.plist of the app carries exactly these nine Sparkle keys and no other key that begins with SU, so a key
    /// added later, such as SUEnableJavaScript or SUEnableDownloaderService, shows here and is decided on purpose.
    @Test func theAppCarriesExactlyTheNineSparkleKeys() {
        let info = Bundle.main.infoDictionary ?? [:]
        let keys = Set(info.keys.filter { $0.hasPrefix("SU") })
        #expect(
            keys == [
                "SUFeedURL",
                "SUPublicEDKey",
                "SUEnableAutomaticChecks",
                "SUScheduledCheckInterval",
                "SUAllowsAutomaticUpdates",
                "SUAutomaticallyUpdate",
                "SURequireSignedFeed",
                "SUVerifyUpdateBeforeExtraction",
                "SUEnableInstallerLauncherService",
            ])
    }

    /// The sandboxed app may look up the two services Sparkle's installer answers on, which are named after the
    /// bundle identifier.
    @Test func theSandboxedAppMayReachSparklesInstaller() {
        #expect(machLookupNames() == ["info.chlup.InvoicesTracker-spks", "info.chlup.InvoicesTracker-spki"])
    }

    /// The Mach service names named after the app's bundle identifier that the sandbox lets the running app look up,
    /// read from the entitlements of this process through the Security framework, the way the system reads them.
    /// Xcode adds the names of its own test services to the same entitlement when it builds the app for testing, so
    /// only the names that belong to the app are kept. The result is empty when there are none.
    private func machLookupNames() -> [String] {
        guard let task = SecTaskCreateFromSelf(nil), let identifier = Bundle.main.bundleIdentifier else {
            return []
        }
        let key = "com.apple.security.temporary-exception.mach-lookup.global-name"
        let value = SecTaskCopyValueForEntitlement(task, key as CFString, nil)
        let names = value as? [String] ?? []
        return names.filter { $0.hasPrefix("\(identifier)-") }
    }
}
