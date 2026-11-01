import Foundation
import Observation

/// What the app shows of its updater and asks of it, for the menu item Zkontrolovat aktualizace… and the card
/// Aktualizace in Nastavení. The updater owns the state: the model says what the updater said when it last read it,
/// and reads it again after each of its own calls and whenever `refresh()` is called.
@MainActor
@Observable
final class UpdatesModel {
    /// Whether a check can start now.
    private(set) var canCheck: Bool

    /// Whether the updater checks for a new version once a day by itself.
    private(set) var checksAutomatically: Bool

    /// When the updater last checked for a new version, or nil when it never has.
    private(set) var lastCheck: Date?

    /// The updater the model reads and asks.
    @ObservationIgnored private let updater: any AppUpdating

    /// Makes the model of `updater`, which says what the updater says now.
    init(updater: any AppUpdating) {
        self.updater = updater
        canCheck = updater.canCheckForUpdates
        checksAutomatically = updater.automaticallyChecksForUpdates
        lastCheck = updater.lastUpdateCheckDate
    }

    /// Asks the updater to check for a new version now, which shows what it finds in its own windows. Does nothing
    /// while `canCheck` is false. Reads the updater again either way.
    func checkNow() {
        if canCheck {
            updater.checkForUpdates()
        }
        refresh()
    }

    /// Turns the daily check of the updater on or off, and reads the updater again. The updater keeps the choice.
    func setChecksAutomatically(_ isOn: Bool) {
        updater.automaticallyChecksForUpdates = isOn
        refresh()
    }

    /// Reads the updater again: whether it can check now, whether it checks daily, and when it last checked.
    func refresh() {
        canCheck = updater.canCheckForUpdates
        checksAutomatically = updater.automaticallyChecksForUpdates
        lastCheck = updater.lastUpdateCheckDate
    }
}
