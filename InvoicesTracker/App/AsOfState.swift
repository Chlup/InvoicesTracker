import Foundation

/// What happened to the reporting cutoff when the day changed.
nonisolated enum DayChange: Sendable, Hashable {
    /// Nothing moved: the state does not follow the automatic cutoff, or the cutoff is still the same day.
    case none

    /// The cutoff moved to the last day of the new month, inside the same year.
    case moved

    /// The state followed today into a new year. `finished` is the year it was on, which is now over.
    case newYear(finished: Int)
}

/// The reporting cutoff: the year the screens show and the day they report invoices issued up to, and whether that day
/// is the automatic one.
///
/// The automatic cutoff of the current year is the last day of the real current month, so that the invoices already
/// issued in the whole month are reported without a person choosing a day. The real today stays apart from it
/// (`AppModel.today`): it decides what has been received, the statuses of invoices and the prediction. Any other year
/// is shown as of its last day, and does not follow. The state follows the automatic cutoff after launch and after a
/// return to the current year, and stops following when another day of the year is picked through the internal API.
nonisolated struct AsOfState: Sendable, Hashable {
    var year: Int
    var asOf: CivilDate
    var followsToday: Bool

    /// The automatic cutoff for `today`: the last day of its month.
    static func automaticCutoff(today: CivilDate) -> CivilDate {
        today.endOfMonth
    }

    /// The state at launch: the current year, as of the last day of the current month, following it.
    static func launch(today: CivilDate) -> AsOfState {
        AsOfState(year: today.year, asOf: automaticCutoff(today: today), followsToday: true)
    }

    /// Shows year `y`. The current year is shown as of the last day of the current month and follows it; any other
    /// year is shown as of its last day and does not follow.
    mutating func selectYear(_ y: Int, today: CivilDate) {
        year = y
        if y == today.year {
            asOf = Self.automaticCutoff(today: today)
            followsToday = true
        } else {
            asOf = Self.lastDay(of: y)
            followsToday = false
        }
    }

    /// Shows `d` in the selected year. A day outside the year is moved to its first or last day. The state follows
    /// the automatic cutoff only when the day shown is the last day of the current month of the current year.
    mutating func pick(_ d: CivilDate, today: CivilDate) {
        asOf = min(max(d, Self.firstDay(of: year)), Self.lastDay(of: year))
        followsToday = year == today.year && asOf == Self.automaticCutoff(today: today)
    }

    /// Returns to the automatic cutoff: the current year as of the last day of the current month, following it.
    mutating func goToday(_ today: CivilDate) {
        self = AsOfState.launch(today: today)
    }

    /// Called when the calendar day changes, with the new day. A state that follows the automatic cutoff moves to the
    /// last day of the new month when the month changed, and at New Year to the new year; the year that finished is
    /// returned so that Přehled can say so. Another day of the same month changes nothing here. A state that does not
    /// follow stays exactly where it is.
    ///
    /// A clock that was set back moves a following state back to the earlier month without calling it a new year.
    @discardableResult
    mutating func dayChanged(to today: CivilDate) -> DayChange {
        guard followsToday else { return .none }
        let finished = year
        let newYear = today.year > finished
        guard newYear || Self.automaticCutoff(today: today) != asOf || today.year != year else { return .none }
        self = AsOfState.launch(today: today)
        return newYear ? .newYear(finished: finished) : .moved
    }

    /// Whether the screens show a year that is over: the day shown is the last day of a year before today's.
    func showsFinishedYear(today: CivilDate) -> Bool {
        Self.isFinishedYear(asOf: asOf, today: today)
    }

    /// Whether `asOf` is the last day of a year that is over by `today`. Any earlier day of such a year is the year as
    /// it was on that day, with the rest of it still to come, and the screens word it as a year in progress.
    static func isFinishedYear(asOf: CivilDate, today: CivilDate) -> Bool {
        asOf.year < today.year && asOf == lastDay(of: asOf.year)
    }

    // MARK: Helpers

    private static func firstDay(of year: Int) -> CivilDate {
        guard let day = CivilDate(year: year, month: 1, day: 1) else {
            preconditionFailure("1 January \(year) is not a date in the years 1 to 9999.")
        }
        return day
    }

    private static func lastDay(of year: Int) -> CivilDate {
        guard let day = CivilDate(year: year, month: 12, day: 31) else {
            preconditionFailure("31 December \(year) is not a date in the years 1 to 9999.")
        }
        return day
    }
}
