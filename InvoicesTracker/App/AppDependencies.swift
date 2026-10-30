import AppKit
import Foundation

/// What the app model works with: where the data lives, the device key of this Mac, the prompt of Touch ID or the
/// password, the clock, the network, the timer of the refresh and of the lock after inactivity, the wakes of the Mac
/// and the time zone of the Mac. The app uses the real ones (`production()`); tests use a temporary folder, a software
/// key protector, a scripted prompt, a manual clock, a stub server, a manual scheduler and a notification center of
/// their own.
nonisolated struct AppDependencies: Sendable {
    var paths: VaultPaths
    var device: any DeviceKeyProtector

    /// Asks for Touch ID or the password of the Mac to unlock the app after inactivity, and opens nothing
    /// (`AppModel.unlockAfterIdle()`).
    var authenticator: any OwnerAuthenticator
    var clock: any AppClock
    var http: any HTTPClient
    var scheduler: any RefreshScheduler

    /// The time zone of the Mac, in which "today" and its midnight are counted. Asked for every time it is needed, so
    /// a change of the zone is seen.
    var timeZone: @Sendable () -> TimeZone

    /// Whether the refresh starts once the data is open. Off in tests, which drive it themselves.
    var startsRefresh: Bool

    /// Whether the lock after inactivity is checked by itself once the data is open: every 15 seconds on `scheduler`,
    /// and when the Mac wakes; and whether the window watches the activity in the app's windows, which the lock counts
    /// from (`IdleActivityMonitor`). Off in tests, which check the lock and tell of the activity themselves
    /// (`AppModel.checkIdleLock(now:)`, `noteActivity(at:)`) unless they turn it on.
    var startsIdleChecks: Bool

    /// Where the Mac tells that it woke from sleep (`NSWorkspace.didWakeNotification`), when the lock after inactivity
    /// is checked at once: the notification center of the workspace. A test gives a center of its own and posts the
    /// wake there.
    var workspaceNotifications: NotificationCenter

    /// Where the system tells that its clock was set (`.NSSystemClockDidChange`), when the timer of the checks of the
    /// lock after inactivity is set again: the default notification center. A test gives a center of its own and posts
    /// the change there.
    var systemNotifications: NotificationCenter

    /// Where the time of the lock after inactivity is kept outside the encrypted data, for the locked screen of a
    /// launch: the user defaults of the app. A test gives a copy in memory.
    var idleLockMirror: any IdleLockMirror

    /// Waits for the time it is given, and throws when the task that waits is cancelled. It bounds what could hang the
    /// app: the wait of a quit for the typed input to be saved, and the wait for a backup outside the Mac that runs.
    /// A test gives a wait that ends when it says.
    var sleep: @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) }

    /// Resolves the bookmark of the folder of the backups outside the Mac with the options a backup asks for
    /// (`BackupService.bookmarkResolutionOptions(withoutUI:)`): the system does (`BackupService.resolveBookmark`). A
    /// test records the options, or stands in for a folder that cannot be reached or does not answer.
    var resolveBookmark: @Sendable (Data, URL.BookmarkResolutionOptions) async throws -> URL =
        BackupService.resolveBookmark

    /// The data folder in Application Support, the Secure Enclave, LocalAuthentication, the system clock, the network,
    /// a dispatch timer and the notification center of the workspace, with the refresh and the checks of the lock after
    /// inactivity on. Throws when the data folder cannot be created.
    static func production() throws -> AppDependencies {
        AppDependencies(
            paths: VaultPaths(directory: try AppEnvironment.dataDirectory()),
            device: SecureEnclaveProtector(),
            authenticator: DeviceOwnerAuthenticator(),
            clock: SystemClock(),
            http: URLSessionHTTPClient(),
            scheduler: TimerScheduler(),
            timeZone: { TimeZone.current },
            startsRefresh: true,
            startsIdleChecks: true,
            workspaceNotifications: NSWorkspace.shared.notificationCenter,
            systemNotifications: NotificationCenter.default,
            idleLockMirror: DefaultsIdleLockMirror()
        )
    }
}
