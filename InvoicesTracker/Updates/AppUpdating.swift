import Foundation

/// What the app needs of an updater: whether a check can start now, whether the updater checks for a new version once
/// a day by itself, when it last checked, and a check that the person asks for. The app's updater is Sparkle's
/// (`AppUpdater`); the tests put their own in its place.
@MainActor
protocol AppUpdating: AnyObject {
    /// Whether a check can start now. It cannot while the updater is busy, such as while it downloads the feed or an
    /// update by itself.
    var canCheckForUpdates: Bool { get }

    /// Whether the updater checks for a new version once a day by itself. The updater keeps the choice.
    var automaticallyChecksForUpdates: Bool { get set }

    /// When the updater last checked for a new version, or nil when it never has.
    var lastUpdateCheckDate: Date? { get }

    /// Checks for a new version now, as the person asked, and shows what it finds in the updater's own windows.
    func checkForUpdates()
}
