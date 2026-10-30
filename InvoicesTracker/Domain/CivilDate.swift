import Foundation

/// A calendar date with no time of day and no time zone, in the proleptic Gregorian calendar, for the years 1 to 9999.
/// Business dates (issue, due and payment dates) are `CivilDate`s, so a clock change can never move them.
/// It is coded as the string `"YYYY-MM-DD"`.
///
/// All arithmetic counts whole days, so it is exact and does not depend on `Calendar`.
nonisolated struct CivilDate: Hashable, Comparable, Sendable, Codable, CustomStringConvertible {
    let year: Int
    let month: Int
    let day: Int

    private static let supportedYears = 1...9999
    private static let firstEpochDay = daysFromCivil(year: 1, month: 1, day: 1)
    private static let lastEpochDay = daysFromCivil(year: 9999, month: 12, day: 31)

    /// Returns nil unless the date exists.
    init?(year: Int, month: Int, day: Int) {
        guard Self.supportedYears.contains(year),
            (1...12).contains(month),
            (1...Self.daysInMonth(year: year, month: month)).contains(day)
        else {
            return nil
        }
        self.year = year
        self.month = month
        self.day = day
    }

    /// Parses exactly `YYYY-MM-DD`: four, two and two ASCII digits separated by hyphens, and nothing else.
    init?(iso: String) {
        let bytes = Array(iso.utf8)
        let hyphen = UInt8(ascii: "-")
        guard bytes.count == 10, bytes[4] == hyphen, bytes[7] == hyphen,
            let year = Self.number(bytes[0..<4]),
            let month = Self.number(bytes[5..<7]),
            let day = Self.number(bytes[8..<10])
        else {
            return nil
        }
        self.init(year: year, month: month, day: day)
    }

    /// For components that are known to form a date.
    private init(validYear year: Int, month: Int, day: Int) {
        self.year = year
        self.month = month
        self.day = day
    }

    /// The date `epochDay` days after 1 January 1970. Traps outside the years 1 to 9999.
    private init(epochDay: Int) {
        precondition(
            (Self.firstEpochDay...Self.lastEpochDay).contains(epochDay),
            "The date is outside the years 1 to 9999."
        )
        // Howard Hinnant's civil_from_days. Counting from 1 March puts the leap day at the end of the year.
        let shifted = epochDay + 719_468
        let era = shifted / 146_097
        let dayOfEra = shifted - era * 146_097
        let yearOfEra = (dayOfEra - dayOfEra / 1460 + dayOfEra / 36_524 - dayOfEra / 146_096) / 365
        let dayOfYear = dayOfEra - (365 * yearOfEra + yearOfEra / 4 - yearOfEra / 100)
        let monthFromMarch = (5 * dayOfYear + 2) / 153
        let month = monthFromMarch < 10 ? monthFromMarch + 3 : monthFromMarch - 9
        self.init(
            validYear: yearOfEra + era * 400 + (month <= 2 ? 1 : 0),
            month: month,
            day: dayOfYear - (153 * monthFromMarch + 2) / 5 + 1
        )
    }

    var iso: String {
        "\(Self.padded(year, width: 4))-\(Self.padded(month, width: 2))-\(Self.padded(day, width: 2))"
    }

    var description: String {
        iso
    }

    /// The date `days` calendar days later, or earlier when negative.
    /// Traps if the result is outside the years 1 to 9999.
    func adding(days: Int) -> CivilDate {
        CivilDate(epochDay: epochDay + days)
    }

    /// The number of days from `other` to this date, negative when this date is earlier.
    func days(since other: CivilDate) -> Int {
        epochDay - other.epochDay
    }

    /// The ISO 8601 weekday: 1 is Monday, 7 is Sunday.
    var weekday: Int {
        // Day 0, 1 January 1970, was a Thursday, which is 4.
        ((epochDay + 3) % 7 + 7) % 7 + 1
    }

    var startOfMonth: CivilDate {
        CivilDate(validYear: year, month: month, day: 1)
    }

    var endOfMonth: CivilDate {
        CivilDate(validYear: year, month: month, day: Self.daysInMonth(year: year, month: month))
    }

    /// Traps unless `month` is 1 to 12.
    static func daysInMonth(year: Int, month: Int) -> Int {
        precondition((1...12).contains(month), "A month is 1 to 12.")
        switch month {
        case 2: return isLeapYear(year) ? 29 : 28
        case 4, 6, 9, 11: return 30
        default: return 31
        }
    }

    /// The date on the wall calendar of `timeZone` at the instant `now`. The zone's offset at that instant is
    /// used, so the answer is right on either side of a daylight-saving change.
    static func today(now: Date, timeZone: TimeZone) -> CivilDate {
        let localSeconds = now.timeIntervalSince1970 + Double(timeZone.secondsFromGMT(for: now))
        return CivilDate(epochDay: Int((localSeconds / 86_400).rounded(.down)))
    }

    static func < (lhs: CivilDate, rhs: CivilDate) -> Bool {
        (lhs.year, lhs.month, lhs.day) < (rhs.year, rhs.month, rhs.day)
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        let text = try container.decode(String.self)
        guard let parsed = CivilDate(iso: text) else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Expected a date written as YYYY-MM-DD."
            )
        }
        self = parsed
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(iso)
    }

    // MARK: Day counting

    /// Days since 1 January 1970 (negative before it).
    private var epochDay: Int {
        Self.daysFromCivil(year: year, month: month, day: day)
    }

    /// Howard Hinnant's days_from_civil, for years from 1 on.
    private static func daysFromCivil(year: Int, month: Int, day: Int) -> Int {
        let shiftedYear = month <= 2 ? year - 1 : year
        let era = shiftedYear / 400
        let yearOfEra = shiftedYear - era * 400
        let dayOfYear = (153 * ((month + 9) % 12) + 2) / 5 + day - 1
        let dayOfEra = yearOfEra * 365 + yearOfEra / 4 - yearOfEra / 100 + dayOfYear
        return era * 146_097 + dayOfEra - 719_468
    }

    private static func isLeapYear(_ year: Int) -> Bool {
        year % 4 == 0 && (year % 100 != 0 || year % 400 == 0)
    }

    // MARK: Text

    private static func number(_ digits: ArraySlice<UInt8>) -> Int? {
        var value = 0
        for byte in digits {
            guard (UInt8(ascii: "0")...UInt8(ascii: "9")).contains(byte) else { return nil }
            value = value * 10 + Int(byte - UInt8(ascii: "0"))
        }
        return value
    }

    private static func padded(_ value: Int, width: Int) -> String {
        let digits = String(value)
        return String(repeating: "0", count: max(0, width - digits.count)) + digits
    }
}
