import Foundation

/// The words of the card Aktualizace in Nastavení › Aplikace: the copy of the card, the version of the app and the
/// moment of the last check for a new version, which are put together from what the app and the updater know.
nonisolated enum UpdatesTexts {
    /// The title of the card.
    static let title = "Aktualizace"

    /// The line under the title: how often the app looks for a new version, and that it sends nothing else.
    static let subtitle = "Jednou denně se podívá, jestli je nová verze. Nic jiného se neodesílá."

    /// The name of the switch of the daily check.
    static let automaticLabel = "Kontrolovat automaticky"

    /// The title of the button that checks for a new version at once.
    static let checkNowTitle = "Zkontrolovat teď"

    /// The name VoiceOver and Voice Control give that button: its title, then the name of the card. The tab has another
    /// Zkontrolovat teď, the button of the rates (Kurzy), and the two must not be listed under one name. The button
    /// itself still shows `checkNowTitle` alone.
    static let checkNowAccessibilityLabel = "\(checkNowTitle) – \(title)"

    /// "1.7.0 (10)": the marketing version of the app and its build in parentheses.
    static func version(shortVersion: String, build: String) -> String {
        "\(shortVersion) (\(build))"
    }

    /// When the updater last checked for a new version, as the moment of a backup is told
    /// (`SettingsTexts.backupMoment`): "dnes 9:14" on the day of `now`, otherwise the date and the time, such as
    /// "15. 10. 2026 18:40". "zatím žádná" for a check that never ran. The day and the time are those of `timeZone`.
    static func lastCheck(_ date: Date?, now: Date, timeZone: TimeZone) -> String {
        guard let date else { return "zatím žádná" }
        return SettingsTexts.backupMoment(
            date, today: CivilDate.today(now: now, timeZone: timeZone), timeZone: timeZone)
    }

    /// The version of this app, "1.7.0 (10)": its marketing version and its build from its Info.plist. A value it lacks
    /// reads "?", as in the line under Nastavení in the sidebar.
    static var installedVersion: String {
        let info = Bundle.main.infoDictionary
        return version(
            shortVersion: info?["CFBundleShortVersionString"] as? String ?? "?",
            build: info?["CFBundleVersion"] as? String ?? "?")
    }
}
