import Foundation

nonisolated enum Appearance: String, Sendable, Hashable, Codable {
    /// Follow the system.
    case system
    case light
    case dark
}

/// What the Přehled chart shows on its horizontal axis.
nonisolated enum ChartMode: String, Sendable, Hashable, Codable {
    case months
    case years
}

/// After how long without activity the app locks (Nastavení › Zabezpečení a zálohy › Zamknout při nečinnosti): a number
/// of minutes, or never. The settings store the minutes, 0 for never.
nonisolated enum IdleLockTime: Int, Codable, CaseIterable, Sendable {
    case oneMinute = 1
    case fiveMinutes = 5
    case tenMinutes = 10
    case fifteenMinutes = 15
    case thirtyMinutes = 30
    case oneHour = 60
    case never = 0

    /// How long without activity locks the app, or nil for never.
    var interval: TimeInterval? {
        self == .never ? nil : TimeInterval(rawValue) * 60
    }

    /// "Po 10 minutách": the item of the menu.
    var label: String {
        switch self {
        case .oneMinute: "Po 1 minutě"
        case .fiveMinutes: "Po 5 minutách"
        case .tenMinutes: "Po 10 minutách"
        case .fifteenMinutes: "Po 15 minutách"
        case .thirtyMinutes: "Po 30 minutách"
        case .oneHour: "Po 1 hodině"
        case .never: "Nikdy"
        }
    }

    /// "po 10 minutách", with a no-break space after the number: when the app locks, as the texts of the lock say it
    /// ("Zamkl se po 10 minutách nečinnosti…"). Nil for never, when the app does not lock.
    var afterText: String? {
        switch self {
        case .oneMinute: "po 1\u{00A0}minutě"
        case .fiveMinutes: "po 5\u{00A0}minutách"
        case .tenMinutes: "po 10\u{00A0}minutách"
        case .fifteenMinutes: "po 15\u{00A0}minutách"
        case .thirtyMinutes: "po 30\u{00A0}minutách"
        case .oneHour: "po 1\u{00A0}hodině"
        case .never: nil
        }
    }
}

/// The choices the person made for the app itself. They are kept as one JSON value in `app_settings`.
nonisolated struct AppSettings: Sendable, Hashable, Codable {
    var appearance = Appearance.system

    /// Whether opening the app asks for Touch ID, and so whether the app locks after inactivity (`idleLock`).
    var touchIDUnlock = true

    /// After how long without activity the app locks while it is unlocked with Touch ID. Settings stored before the
    /// choice existed read as the default, 10 minutes.
    var idleLock = IdleLockTime.tenMinutes

    /// The security-scoped bookmark of the folder for the backups kept off this Mac.
    var backupFolderBookmark: Data?

    /// The name of that folder, to show.
    var backupFolderName: String?
    var lastLocalBackup: Date?
    var lastOffMacBackup: Date?

    /// Since when a change waits for the local backup: the moment of the first change that no local backup holds yet.
    /// Nil when the local backups hold every change. It is kept across launches, so a change made shortly before the
    /// app quits is backed up after the next launch.
    var localBackupPendingSince: Date?
    var chartMode = ChartMode.months

    /// Whether the chart shows amounts with VAT.
    var chartWithVAT = false

    /// The label of the recovery code that the code in force replaced, such as "kód č. 1 z 17. 10. 2026": the backups
    /// made before the change, Time Machine's too, still need it. Nil while the first code is in force. It names the
    /// code, and nothing of it is derived from the code.
    var replacedRecoveryCodeLabel: String?

    /// The number of that code, which tells whether it is the code just before the one in force: settings that come
    /// back with a restored backup can name a code of another time.
    var replacedRecoveryCodeNumber: Int?

    /// When the folder of the backups outside the Mac was chosen: the reminder of those backups counts from it while
    /// the folder has no backup yet.
    var backupFolderChosen: Date?
}

nonisolated extension AppSettings {
    /// Reads settings written by this or an earlier version of the app. A field the stored JSON does not have takes
    /// its default, so a field added later never makes the settings already stored unreadable.
    init(from decoder: any Decoder) throws {
        self.init()
        let values = try decoder.container(keyedBy: CodingKeys.self)
        appearance = try values.decodeIfPresent(Appearance.self, forKey: .appearance) ?? appearance
        touchIDUnlock = try values.decodeIfPresent(Bool.self, forKey: .touchIDUnlock) ?? touchIDUnlock
        idleLock = try values.decodeIfPresent(IdleLockTime.self, forKey: .idleLock) ?? idleLock
        backupFolderBookmark = try values.decodeIfPresent(Data.self, forKey: .backupFolderBookmark)
        backupFolderName = try values.decodeIfPresent(String.self, forKey: .backupFolderName)
        lastLocalBackup = try values.decodeIfPresent(Date.self, forKey: .lastLocalBackup)
        lastOffMacBackup = try values.decodeIfPresent(Date.self, forKey: .lastOffMacBackup)
        localBackupPendingSince = try values.decodeIfPresent(Date.self, forKey: .localBackupPendingSince)
        chartMode = try values.decodeIfPresent(ChartMode.self, forKey: .chartMode) ?? chartMode
        chartWithVAT = try values.decodeIfPresent(Bool.self, forKey: .chartWithVAT) ?? chartWithVAT
        replacedRecoveryCodeLabel = try values.decodeIfPresent(String.self, forKey: .replacedRecoveryCodeLabel)
        replacedRecoveryCodeNumber = try values.decodeIfPresent(Int.self, forKey: .replacedRecoveryCodeNumber)
        backupFolderChosen = try values.decodeIfPresent(Date.self, forKey: .backupFolderChosen)
    }
}
