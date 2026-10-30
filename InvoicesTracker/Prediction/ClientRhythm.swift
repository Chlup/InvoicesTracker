import Foundation

/// How a client invoices and pays, as its issued invoices known at "now" show it: how long it takes to pay, how often
/// it is invoiced and whether regularly. The prediction of a year expects a
/// regular client's next invoices in the months of its rhythm.
nonisolated struct ClientRhythm: Sendable, Hashable {
    /// The usual days from the issue of an invoice to its payment: the lower median of the days from issue to payment
    /// of the invoices paid by "now", a payment before the issue counting as 0 days. Without such a payment it is the
    /// client's due days, or 14 for a client the app does not know.
    var delayDays: Int

    /// The usual days between two invoices: the lower median of the last four gaps between issue dates at most, 0 with
    /// fewer than two invoices.
    var intervalDays: Int

    /// Whether the next invoices can be expected from the rhythm: at least two invoices, an interval of at least 20
    /// days, and the last invoice no older than one and a half intervals.
    var isRegular: Bool

    /// The interval in months of 30,4 days, rounded, and at least 1.
    var step: Int

    /// The issue date of the last invoice, nil without one.
    var lastIssued: CivilDate?

    /// The rhythm of a client whose issued invoices known at `now` are `issued`, in any order and without drafts, whose
    /// due days are `dueDays` (nil for a client the app does not know). Amounts are selected independently.
    init(issued: [Invoice], now: CivilDate, dueDays: Int?) {
        let invoices = issued.sorted(by: Self.issuedEarlier)
        let interval = Self.interval(of: invoices)
        let last = invoices.last
        delayDays = Self.delay(of: invoices, now: now) ?? dueDays ?? 14
        intervalDays = interval
        lastIssued = last?.issueDate
        // No older than one and a half intervals: twice the age at most three intervals, in whole days.
        let isRecent = last.map { 2 * now.days(since: $0.issueDate) <= 3 * interval } ?? false
        isRegular = invoices.count >= 2 && interval >= 20 && isRecent
        // The interval in months of 30,4 days: 10 × interval / 304, exactly.
        step = max(1, Int(DecimalMath.halfUp(Decimal(interval) * 10 / 304)))
    }

    /// The months of `year` in which the app expects an invoice of its own accord: the months of the drafts,
    /// `draftMonths`, and for a regular client the months of its rhythm, every `step` months after the month of the
    /// last invoice.
    func automaticMonths(in year: Int, draftMonths: Set<Int>) -> Set<Int> {
        guard isRegular, let lastIssued else { return draftMonths }
        let lastMonth = lastIssued.year * 12 + lastIssued.month
        let rhythm = (1...12).filter { month in
            let distance = year * 12 + month - lastMonth
            return distance > 0 && distance % step == 0
        }
        return draftMonths.union(rhythm)
    }

    /// The day of `month` of `year` on which an invoice is likely issued: the day of the month of the last invoice, or
    /// the 31st without one, at most the month's last day.
    func usualIssueDate(month: Int, year: Int) -> CivilDate {
        let day = min(lastIssued?.day ?? 31, CivilDate.daysInMonth(year: year, month: month))
        guard let date = CivilDate(year: year, month: month, day: day) else {
            preconditionFailure("\(day). \(month). \(year) is not a date in the years 1 to 9999.")
        }
        return date
    }

    /// Whether `lhs` was issued before `rhs`; on the same day the one with the lower id is first.
    static func issuedEarlier(_ lhs: Invoice, _ rhs: Invoice) -> Bool {
        (lhs.issueDate, lhs.id) < (rhs.issueDate, rhs.id)
    }

    // MARK: Helpers

    /// The lower median of `values`: the one at (n − 1) / 2, rounded down, when they are in order. 0 for none.
    private static func lowerMedian(_ values: [Int]) -> Int {
        guard !values.isEmpty else { return 0 }
        return values.sorted()[(values.count - 1) / 2]
    }

    /// The usual delay of the invoices paid by `now`, nil when none is.
    private static func delay(of invoices: [Invoice], now: CivilDate) -> Int? {
        let delays = invoices.compactMap { invoice -> Int? in
            guard let payment = invoice.payment, payment.date <= now else { return nil }
            return max(0, payment.date.days(since: invoice.issueDate))
        }
        return delays.isEmpty ? nil : lowerMedian(delays)
    }

    /// The usual interval of `invoices`, which are in the order of issue.
    private static func interval(of invoices: [Invoice]) -> Int {
        let gaps = zip(invoices, invoices.dropFirst()).map { earlier, later in
            later.issueDate.days(since: earlier.issueDate)
        }
        return lowerMedian(Array(gaps.suffix(4)))
    }

}
