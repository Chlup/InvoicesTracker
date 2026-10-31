import Foundation
import Sparkle
import os

/// Sparkle's updater of the app, with Sparkle's standard windows, started once at launch. This object is its delegate:
/// it refuses the checks that `UpdateCheckPolicy` does not allow in this build, logs how each check ended, and keeps
/// `model` saying what the updater says, for the menu item and the settings card.
@MainActor
final class AppUpdater: NSObject, SPUUpdaterDelegate {
    /// Sparkle's controller of the updater and its windows, with this object as the updater's delegate. It is made on
    /// first use, as its delegate has to exist first; `init()` makes it and then starts it.
    private lazy var controller = SPUStandardUpdaterController(
        startingUpdater: false, updaterDelegate: self, userDriverDelegate: nil)

    /// What the menu item and the settings card show of the updater and ask of it. It is made on first use, which is in
    /// `init()`, from the updater of `controller`.
    private(set) lazy var model = UpdatesModel(updater: SparkleUpdater(controller.updater))

    /// The observations that read the updater again into `model` when it changes whether a check can start or whether
    /// it checks daily.
    private var observations: [NSKeyValueObservation] = []

    /// Where the updater's lines go in the log.
    private nonisolated static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "InvoicesTracker", category: "Updates")

    /// The updater the app starts once at launch, or nil when the app hosts the unit tests (`isRunningTests`), which
    /// must not check for updates.
    static func forLaunch(isRunningTests: Bool = AppEnvironment.isRunningTests) -> AppUpdater? {
        isRunningTests ? nil : AppUpdater()
    }

    /// The language of Sparkle's own windows: the first localization of Sparkle's bundle in the order of preference,
    /// or nil when there is none.
    nonisolated static var sparkleLanguage: String? {
        Bundle(for: SPUUpdater.self).preferredLocalizations.first
    }

    /// Makes Sparkle's updater and `model`, starts the updater once the observations keep `model` up to date, and logs
    /// whether it started. The start line is a `notice`, as unified logging keeps no `info` line, so that `log show`
    /// can find it after the launch.
    private override init() {
        super.init()
        let updater = controller.updater
        let model = self.model
        let refresh: @Sendable (SPUUpdater, NSKeyValueObservedChange<Bool>) -> Void = { _, _ in
            // Sparkle uses its updater on the main thread alone, so its changes are posted there.
            MainActor.assumeIsolated {
                model.refresh()
            }
        }
        observations = [
            updater.observe(\.canCheckForUpdates, changeHandler: refresh),
            updater.observe(\.automaticallyChecksForUpdates, changeHandler: refresh),
        ]
        controller.startUpdater()
        // The updater can check as soon as it has started. When it cannot start, the controller logs why and shows an
        // alert.
        if !updater.canCheckForUpdates {
            Self.logger.error("Sparkle's updater did not start")
        } else if UpdateCheckPolicy.refusesBackgroundChecks {
            Self.logger.notice("Sparkle's updater started, and this Debug build refuses its checks in the background")
        } else {
            Self.logger.notice("Sparkle's updater started")
        }
    }

    // MARK: SPUUpdaterDelegate

    /// Lets Sparkle make the check `updateCheck` unless `UpdateCheckPolicy` refuses its kind in this build. A refusal
    /// throws, and Sparkle then makes no check.
    func updater(_ updater: SPUUpdater, mayPerform updateCheck: SPUUpdateCheck) throws {
        let kind = UpdateCheckKind(updateCheck)
        guard UpdateCheckPolicy.allows(kind, refusingBackgroundChecks: UpdateCheckPolicy.refusesBackgroundChecks) else {
            throw RefusedUpdateCheck()
        }
    }

    /// Logs how the check `updateCheck` ended, and reads the updater into `model` again, as a check changes when the
    /// updater last checked. A check that found no new version, or that this build refused, ended as it should. Any
    /// other error is a failed cycle, which goes through `AppModel.log` (category App) with its domain and code alone.
    func updater(_ updater: SPUUpdater, didFinishUpdateCycleFor updateCheck: SPUUpdateCheck, error: (any Error)?) {
        let kind = String(describing: UpdateCheckKind(updateCheck))
        switch error {
        case nil:
            Self.logger.info("The \(kind, privacy: .public) update check finished")
        case is RefusedUpdateCheck:
            Self.logger.info("This Debug build refused the \(kind, privacy: .public) update check")
        case let error? where Self.foundNoNewVersion(error):
            Self.logger.info("The \(kind, privacy: .public) update check found no new version")
        case let error?:
            AppModel.log("The \(kind) update check", failedWith: error)
        }
        model.refresh()
    }

    /// Whether `error` is how Sparkle says that a check found no new version.
    private nonisolated static func foundNoNewVersion(_ error: any Error) -> Bool {
        let error = error as NSError
        return error.domain == SUSparkleErrorDomain && error.code == Int(SUError.noUpdateError.rawValue)
    }
}

/// The error that keeps Sparkle from making a check that `UpdateCheckPolicy` refuses in this build.
private nonisolated struct RefusedUpdateCheck: LocalizedError {
    /// Why, in English, for Sparkle's own log.
    var errorDescription: String? {
        "This Debug build does not check for updates in the background."
    }
}

private nonisolated extension UpdateCheckKind {
    /// The kind of Sparkle's check `check`. A kind of check that a later Sparkle adds counts as one in the background,
    /// which Debug builds refuse.
    init(_ check: SPUUpdateCheck) {
        switch check {
        case .updates:
            self = .userInitiated
        case .updatesInBackground:
            self = .background
        case .updateInformation:
            self = .informationOnly
        @unknown default:
            self = .background
        }
    }
}

/// Sparkle's updater as the app needs it (`AppUpdating`): each read, change and check goes through to Sparkle.
private final class SparkleUpdater: AppUpdating {
    /// Sparkle's updater.
    private let updater: SPUUpdater

    /// Makes the adapter of Sparkle's `updater`.
    init(_ updater: SPUUpdater) {
        self.updater = updater
    }

    /// Whether Sparkle's updater can check now.
    var canCheckForUpdates: Bool {
        updater.canCheckForUpdates
    }

    /// Whether Sparkle's updater checks once a day by itself. Sparkle keeps the choice in the app's user defaults.
    var automaticallyChecksForUpdates: Bool {
        get { updater.automaticallyChecksForUpdates }
        set { updater.automaticallyChecksForUpdates = newValue }
    }

    /// When Sparkle's updater last checked, which Sparkle keeps in the app's user defaults.
    var lastUpdateCheckDate: Date? {
        updater.lastUpdateCheckDate
    }

    /// Asks Sparkle's updater for a check, which shows its progress and its result in Sparkle's windows.
    func checkForUpdates() {
        updater.checkForUpdates()
    }
}
