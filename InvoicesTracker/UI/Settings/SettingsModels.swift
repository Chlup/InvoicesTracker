import Foundation

/// A tab of Nastavení.
nonisolated enum SettingsTab: CaseIterable, Hashable, Sendable {
    /// Aplikace: the appearance, the rates and the licences.
    case application

    /// Moje údaje: the supplier's details and bank accounts.
    case supplier

    /// Zabezpečení a zálohy: Touch ID, the recovery code and the backups.
    case security

    /// Rok Y: the settings of the selected year.
    case year

    /// The title of the tab in the segmented control, when `year` is the selected year.
    func title(year: Int) -> String {
        switch self {
        case .application: "Aplikace"
        case .supplier: "Moje údaje"
        case .security: "Zabezpečení a zálohy"
        case .year: "Rok \(year)"
        }
    }
}

/// What the rest of the app asks Nastavení to do: a command of the menu asks Zabezpečení a zálohy, and a notice or the
/// sheet of a uniform rate that was found asks Rok.
nonisolated enum SettingsAction: Hashable, Sendable {
    /// Exportovat zálohu…: the save panel, and the export to the file chosen in it.
    case exportBackup

    /// Obnovit ze zálohy…: the sheet of the restore.
    case restoreBackup

    /// Zadat ručně: the form of the uniform rate of the year, in Nastavení › Rok.
    case enterUniformRate
}

/// The words of Nastavení that are put together from what the app knows: times of the day, days of the week and the
/// moments of backups. Times are those of the Mac's time zone unless said otherwise.
nonisolated enum SettingsTexts {
    /// "14:36", "9:05": the hour without a leading zero and the minutes with one, in `timeZone`.
    static func clockTime(_ instant: Date, timeZone: TimeZone) -> String {
        let (hour, minute) = hourAndMinute(of: instant, in: timeZone)
        return "\(hour):" + (minute < 10 ? "0" : "") + "\(minute)"
    }

    /// "ve 14:36", "v 9:05": the time with the preposition Czech gives it, "ve" before the hours that start with a
    /// consonant cluster (ve dvě, ve tři, ve čtyři, ve dvanáct, ve třináct, ve čtrnáct, ve dvacet to ve třiadvacet).
    static func atClockTime(_ instant: Date, timeZone: TimeZone) -> String {
        let (hour, _) = hourAndMinute(of: instant, in: timeZone)
        return ([2, 3, 4, 12, 13, 14, 20, 21, 22, 23].contains(hour) ? "ve " : "v ")
            + clockTime(instant, timeZone: timeZone)
    }

    /// "v pondělí", "ve středu": the day of the week of `day` with its preposition.
    static func weekdayWithPreposition(_ day: CivilDate) -> String {
        [
            "v pondělí", "v úterý", "ve středu", "ve čtvrtek", "v pátek", "v sobotu", "v neděli",
        ][day.weekday - 1]
    }

    /// When a backup was made, as a sentence names it: "dnes 14:05" on `today`, otherwise "15. 10. 2026 18:40".
    static func backupMoment(_ instant: Date, today: CivilDate, timeZone: TimeZone) -> String {
        let day = CivilDate.today(now: instant, timeZone: timeZone)
        return (day == today ? "dnes" : CzechFormat.date(day)) + " " + clockTime(instant, timeZone: timeZone)
    }

    /// When a backup was made, as a list of backups names it: "Dnes 14:05", "Včera 21:14", otherwise
    /// "15. 10. 2026 18:40".
    static func backupTitle(_ instant: Date, today: CivilDate, timeZone: TimeZone) -> String {
        let day = CivilDate.today(now: instant, timeZone: timeZone)
        let name =
            if day == today {
                "Dnes"
            } else if day == today.adding(days: -1) {
                "Včera"
            } else {
                CzechFormat.date(day)
            }
        return name + " " + clockTime(instant, timeZone: timeZone)
    }

    private static func hourAndMinute(of instant: Date, in timeZone: TimeZone) -> (hour: Int, minute: Int) {
        let utcSeconds = Int(instant.timeIntervalSince1970.rounded(.down))
        let localSeconds = utcSeconds + timeZone.secondsFromGMT(for: instant)
        let secondOfDay = (localSeconds % 86_400 + 86_400) % 86_400
        return (secondOfDay / 3600, secondOfDay % 3600 / 60)
    }
}
