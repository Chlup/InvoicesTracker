import Foundation

/// The months in which a client is expected to send an invoice, as far as the person changed them. A row of
/// `expected_invoice_month` is a month of a client in a year in which the person's choice differs from the app's own,
/// so a month with no row is left to the app. The repository does not know the app's choice: whoever calls it decides
/// whether a value differs from it and so is stored, or equals it and so is deleted.
extension Database {
    /// The changes stored for `year`: for each client, by its id, the months 1 to 12 whose choice the person made, true
    /// for a month in which an invoice is expected and false for one in which it is not. A client with no change is not
    /// in the answer, and a year with none (or with no settings of its own) has an empty one.
    /// - Throws: `StoredValueError` when a stored month is not 1 to 12, and the errors of the database.
    func expectedInvoiceMonths(year: Int) throws -> [Int64: [Int: Bool]] {
        try read { connection in
            var changes: [Int64: [Int: Bool]] = [:]
            let rows = try connection.query(
                "SELECT client_id, month, expected FROM expected_invoice_month WHERE year = ?", [.int(year)]
            )
            for row in rows {
                let month = row.int(1)
                guard (1...12).contains(month) else {
                    throw StoredValueError.unreadable(column: 1, expected: "month")
                }
                changes[row.int64(0), default: [:]][month] = row.bool(2)
            }
            return changes
        }
    }

    /// Stores the choice for `month` of the client in `year`, replacing the one stored for that month, or deletes it
    /// when `expected` is nil, which leaves the month to the app again. A year without settings of its own gets them
    /// stored first, as `yearSettings(_:)` gives them, because the row belongs to the settings of the year; a deletion
    /// stores none. All in one transaction. A choice for a month that is not 1 to 12, or for a client that is not
    /// stored, is refused with `SQLiteError.constraint` and nothing is changed.
    func setExpectedInvoiceMonth(year: Int, clientID: Int64, month: Int, expected: Bool?) throws {
        try write { connection in
            guard let expected else {
                try connection.run(
                    "DELETE FROM expected_invoice_month WHERE year = ? AND client_id = ? AND month = ?",
                    [.int(year), .integer(clientID), .int(month)]
                )
                return
            }
            try storeYearSettingsIfMissing(year, in: connection)
            try connection.run(
                """
                INSERT INTO expected_invoice_month(year, client_id, month, expected) VALUES (?, ?, ?, ?)
                ON CONFLICT(year, client_id, month) DO UPDATE SET expected = excluded.expected
                """,
                [.int(year), .integer(clientID), .int(month), .flag(expected)]
            )
        }
    }

    /// Deletes every change stored for the client in `year`, which leaves all its months to the app again. A client
    /// with none is not an error.
    func clearExpectedInvoiceMonths(year: Int, clientID: Int64) throws {
        try write { connection in
            try connection.run(
                "DELETE FROM expected_invoice_month WHERE year = ? AND client_id = ?",
                [.int(year), .integer(clientID)]
            )
        }
    }
}
