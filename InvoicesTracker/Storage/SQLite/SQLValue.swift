import Foundation

/// A value bound to a statement or read from a result column. The app stores no floating-point numbers
/// (amounts are integer minor units, exact decimals are text), so there is no real case.
nonisolated enum SQLValue: Sendable, Hashable {
    case null
    case integer(Int64)
    case text(String)
    case blob(Data)
}

/// One row of a query result.
///
/// The typed accessors are for columns whose type the schema guarantees. Reading a column as a type it
/// does not hold (including `NULL` through a non-optional accessor) is a programming error and stops the
/// app with a message that names the column and the stored type, never the value.
nonisolated struct SQLRow: Sendable {
    let values: [SQLValue]

    subscript(_ i: Int) -> SQLValue {
        values[i]
    }

    func int64(_ i: Int) -> Int64 {
        guard let value = optionalInt64(i) else { unexpectedNull(i, expected: "INTEGER") }
        return value
    }

    func optionalInt64(_ i: Int) -> Int64? {
        switch values[i] {
        case .null: return nil
        case .integer(let value): return value
        case .text, .blob: unexpectedType(i, expected: "INTEGER")
        }
    }

    func text(_ i: Int) -> String {
        guard let value = optionalText(i) else { unexpectedNull(i, expected: "TEXT") }
        return value
    }

    func optionalText(_ i: Int) -> String? {
        switch values[i] {
        case .null: return nil
        case .text(let value): return value
        case .integer, .blob: unexpectedType(i, expected: "TEXT")
        }
    }

    func blob(_ i: Int) -> Data {
        guard let value = optionalBlob(i) else { unexpectedNull(i, expected: "BLOB") }
        return value
    }

    func optionalBlob(_ i: Int) -> Data? {
        switch values[i] {
        case .null: return nil
        case .blob(let value): return value
        case .integer, .text: unexpectedType(i, expected: "BLOB")
        }
    }

    /// SQLite has no boolean type; a flag is an integer that is zero or not.
    func bool(_ i: Int) -> Bool {
        int64(i) != 0
    }

    private func unexpectedNull(_ i: Int, expected: String) -> Never {
        preconditionFailure("Column \(i) is NULL, expected \(expected).")
    }

    private func unexpectedType(_ i: Int, expected: String) -> Never {
        preconditionFailure("Column \(i) holds \(values[i].storageClass), expected \(expected).")
    }
}

private nonisolated extension SQLValue {
    /// The SQLite name of the stored type, for messages that must not show the value.
    var storageClass: String {
        switch self {
        case .null: "NULL"
        case .integer: "INTEGER"
        case .text: "TEXT"
        case .blob: "BLOB"
        }
    }
}
