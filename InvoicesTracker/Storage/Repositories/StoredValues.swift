import Foundation

/// A stored value that cannot be read back: a text that is not a date, a currency code, a decimal or a set of months,
/// or a raw value that no case of the enum has. The app never writes such a value, so the file was changed by
/// something else or is damaged. The error names the column of the result and what was expected, never the value.
nonisolated enum StoredValueError: Error, Equatable {
    case unreadable(column: Int, expected: String)
}

/// The values the repositories bind, written the way the schema says (see `Schema`): a flag is 0 or 1, an instant is
/// whole seconds since 1 January 1970 UTC, a date is `YYYY-MM-DD`, an exact decimal is its canonical text, an enum is
/// its raw value, a set of months is its months in ascending order separated by commas, and a range of months is two
/// columns, its first and its last month.
nonisolated extension SQLValue {
    static func int(_ value: Int) -> SQLValue {
        .integer(Int64(value))
    }

    static func flag(_ value: Bool) -> SQLValue {
        .integer(value ? 1 : 0)
    }

    static func optionalText(_ value: String?) -> SQLValue {
        value.map { SQLValue.text($0) } ?? .null
    }

    /// The part of a second is dropped.
    static func instant(_ date: Date) -> SQLValue {
        .integer(Int64(date.timeIntervalSince1970.rounded(.down)))
    }

    static func optionalInstant(_ date: Date?) -> SQLValue {
        date.map { SQLValue.instant($0) } ?? .null
    }

    static func day(_ day: CivilDate) -> SQLValue {
        .text(day.iso)
    }

    static func currency(_ currency: CurrencyCode) -> SQLValue {
        .text(currency.code)
    }

    static func decimal(_ value: Decimal) -> SQLValue {
        .text(DecimalMath.canonical(value))
    }

    static func choice<Value: RawRepresentable>(_ value: Value) -> SQLValue where Value.RawValue == String {
        .text(value.rawValue)
    }

    /// The months in ascending order separated by commas, with no spaces, and an empty text for none.
    static func months(_ months: Set<Int>) -> SQLValue {
        .text(months.sorted().map { String($0) }.joined(separator: ","))
    }

    /// The two columns of a range of months: its first and its last month, both NULL for none.
    static func monthRangeColumns(_ range: MonthRange?) -> [SQLValue] {
        guard let range else { return [.null, .null] }
        return [.int(range.from), .int(range.to)]
    }
}

/// The same values read back. A reader of a column that can hold a value the app never wrote (a date, a currency
/// code, a decimal, an enum, a set or a range of months) throws `StoredValueError` instead of stopping the app. The
/// others follow the contract of `SQLRow`: the schema guarantees the type of the column.
nonisolated extension SQLRow {
    func int(_ i: Int) -> Int {
        Int(int64(i))
    }

    func instant(_ i: Int) -> Date {
        Date(timeIntervalSince1970: Double(int64(i)))
    }

    func optionalInstant(_ i: Int) -> Date? {
        optionalInt64(i).map { Date(timeIntervalSince1970: Double($0)) }
    }

    func day(_ i: Int) throws -> CivilDate {
        guard let value = CivilDate(iso: text(i)) else {
            throw StoredValueError.unreadable(column: i, expected: "date")
        }
        return value
    }

    func currency(_ i: Int) throws -> CurrencyCode {
        guard let value = CurrencyCode(text(i)) else {
            throw StoredValueError.unreadable(column: i, expected: "currency code")
        }
        return value
    }

    func decimal(_ i: Int) throws -> Decimal {
        guard let value = DecimalMath.decimal(text(i)) else {
            throw StoredValueError.unreadable(column: i, expected: "decimal")
        }
        return value
    }

    func choice<Value: RawRepresentable>(_ i: Int) throws -> Value where Value.RawValue == String {
        guard let value = Value(rawValue: text(i)) else {
            throw StoredValueError.unreadable(column: i, expected: String(describing: Value.self))
        }
        return value
    }

    /// Months 1 to 12 written as `SQLValue.months` does.
    func months(_ i: Int) throws -> Set<Int> {
        let stored = text(i)
        if stored.isEmpty { return [] }
        var months: Set<Int> = []
        for part in stored.split(separator: ",", omittingEmptySubsequences: false) {
            guard let month = Int(part), (1...12).contains(month) else {
                throw StoredValueError.unreadable(column: i, expected: "months")
            }
            months.insert(month)
        }
        return months
    }

    /// The range of months in the two columns from `i`, written as `SQLValue.monthRangeColumns` does, or nil when both
    /// are NULL.
    func optionalMonthRange(_ i: Int) throws -> MonthRange? {
        switch (optionalInt64(i), optionalInt64(i + 1)) {
        case (nil, nil):
            return nil
        case (let from?, let to?) where MonthRange(from: Int(from), to: Int(to)).isValid:
            return MonthRange(from: Int(from), to: Int(to))
        default:
            throw StoredValueError.unreadable(column: i, expected: "range of months")
        }
    }

    /// The same for a range that is always there.
    func monthRange(_ i: Int) throws -> MonthRange {
        guard let range = try optionalMonthRange(i) else {
            throw StoredValueError.unreadable(column: i, expected: "range of months")
        }
        return range
    }
}
