import Foundation

/// How the income of a year is converted to crowns. One method for the whole year, never mixed.
nonisolated enum IncomeFXMethod: String, Sendable, Hashable, Codable {
    /// At the ČNB rate of the day the money was received.
    case cnbDaily

    /// At the uniform annual rate of the GFŘ.
    case uniform
}

/// What the person set for one year: the flat-rate expenses, the months of the activity, the advances paid, the
/// deductions, the spouse and the choices that change how the levies are worked out.
nonisolated struct YearSettings: Sendable, Hashable, Codable {
    var year: Int

    /// The flat-rate expense percentage: 80, 60, 40 or 30.
    var expensePercent = 60

    /// Stored, with no effect on the computation.
    var reducedSocialBase = false

    /// The first and the last month, 1 to 12, in which the self-employment was carried on.
    var activityFrom = 1
    var activityTo = 12

    /// The months, 1 to 12, of the activity in which it was a secondary one.
    var secondaryMonths: Set<Int> = []

    /// The months, 1 to 12, in which the health insurance minimum does not apply.
    var healthExemptMonths: Set<Int> = []
    var advances = AdvancePlan.empty
    var deductions = Deductions()
    var taxpayerCredit = true
    var incomeFXMethod = IncomeFXMethod.cnbDaily

    /// The spouse of the year, or nil for none. A year never takes the spouse of another year.
    var spouse: SpouseYear?

    /// The activity of each of the twelve months, January first: inactive outside `activityFrom…activityTo`,
    /// otherwise secondary in `secondaryMonths` and main in every other month.
    func monthActivities() -> [MonthActivity] {
        (1...12).map { month in
            if month < activityFrom || month > activityTo {
                MonthActivity.inactive
            } else if secondaryMonths.contains(month) {
                MonthActivity.secondary
            } else {
                MonthActivity.main
            }
        }
    }
}
