import Foundation

/// After how long without activity the app locks, kept outside the encrypted data, for the locked screen of a launch,
/// which names it before the data is open (`AppModel.idleLockBeforeOpening`). It is a copy of `AppSettings.idleLock`,
/// which the app writes whenever it opens the data and whenever it saves the settings. It says nothing of the data.
nonisolated protocol IdleLockMirror: Sendable {
    /// The time last written, or nil when none has been written yet.
    func read() -> IdleLockTime?

    func write(_ time: IdleLockTime)
}

/// The copy in the user defaults of the app, or in the defaults of the suite `suiteName` when one is given: the minutes
/// of the time, 0 for Nikdy, as the settings store them. A number that is no time of the menu reads as nothing written.
nonisolated struct DefaultsIdleLockMirror: IdleLockMirror {
    /// The key of the minutes in the defaults.
    static let key = "idleLockMinutes"

    var suiteName: String?

    func read() -> IdleLockTime? {
        guard let minutes = defaults?.object(forKey: Self.key) as? Int else { return nil }
        return IdleLockTime(rawValue: minutes)
    }

    func write(_ time: IdleLockTime) {
        defaults?.set(time.rawValue, forKey: Self.key)
    }

    /// The defaults of the suite, or those of the app.
    private var defaults: UserDefaults? {
        guard let suiteName else { return UserDefaults.standard }
        return UserDefaults(suiteName: suiteName)
    }
}
