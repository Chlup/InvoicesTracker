import Foundation

/// Nastavení as the rest of the app asks for it: a tab of it, and what a command of the menu asks it to do.
extension AppModel {
    /// Shows Nastavení on `tab`.
    func showSettings(_ tab: SettingsTab) {
        screen = .settings
        settingsTab = tab
    }

    /// Exportovat zálohu… and Obnovit ze zálohy… of the menu: Nastavení › Zabezpečení a zálohy is shown and does
    /// `action` (`settingsAction`), so that its result is said where the backups are. Does nothing while a step of that
    /// tab runs: one at a time across the app. Zadat ručně shows Nastavení › Rok, which opens the form of the uniform
    /// rate.
    func request(_ action: SettingsAction) {
        switch action {
        case .exportBackup, .restoreBackup:
            guard !securityStepRunning else { return }
            showSettings(.security)
        case .enterUniformRate:
            showSettings(.year)
        }
        settingsAction = action
    }
}
