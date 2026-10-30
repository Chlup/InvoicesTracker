import CryptoKit
import Foundation

/// What the header of a backup tells of the data in it.
nonisolated struct ContentSummary: Sendable, Equatable {
    /// The invoices, drafts included.
    var invoiceCount: Int
    var clientCount: Int

    /// The first and the last year with data (`Database.yearsWithData()`), or nil while there is none.
    var years: ClosedRange<Int>?
}

extension Database {
    /// The numbers a backup's header shows, read in one call, so that they describe the data as of one moment: how many
    /// invoices and clients there are, and the first and the last year with data.
    func contentSummary() throws -> ContentSummary {
        let years = try yearsWithData()
        let range: ClosedRange<Int>? =
            if let first = years.first, let last = years.last {
                first...last
            } else {
                nil
            }
        return ContentSummary(invoiceCount: try invoiceCount(), clientCount: try clientCount(), years: range)
    }

    /// Writes a copy of the whole database to the new file `url`, encrypted with `key`: the file opens with `key` as a
    /// database of the same schema version and with the same data. The copy is one point in time, because it is made
    /// on the actor, where no write can come in between, in one transaction.
    ///
    /// `url` has to be a file that does not exist yet (or an empty one). When this throws, a partly written file may
    /// be left at `url` for the caller to remove, and the database is as it was. Making a copy is not a change of the
    /// data: it does not count in `writeCount`.
    func exportSnapshot(to url: URL, key: SymmetricKey) throws {
        try read { connection in
            try connection.exportSnapshot(to: url, key: key)
        }
    }
}

/// The snapshot as a step on the connection, for `Database.exportSnapshot(to:key:)`.
///
/// It attaches the new file and detaches it again, and SQLite refuses to detach a file that is in the transaction
/// that is open, so it is not the body of a `Database.write`. It must not be called while a `write` is open: from
/// outside the actor that cannot happen, because the actor runs one call at a time, and from inside a `write` body it
/// is refused before anything is attached.
nonisolated extension SQLiteConnection {
    func exportSnapshot(to url: URL, key: SymmetricKey) throws {
        guard !isInTransaction else {
            throw SQLiteError.step("A snapshot cannot be made inside a transaction.")
        }
        // `sqlcipher_export` does not copy `user_version`.
        let schemaVersion = try userVersion()
        try attachSnapshot(url, key: key)
        do {
            try transaction {
                try run("SELECT sqlcipher_export('backup')")
                try execute("PRAGMA backup.user_version = \(schemaVersion)")
            }
        } catch {
            // The export failed and that is the error to report, so a failed detach has nothing to add to it.
            try? execute("DETACH DATABASE backup")
            throw error
        }
        try execute("DETACH DATABASE backup")
    }

    /// Attaches the file `url` as the schema `backup`, encrypted with `key`. The file is created when it is missing.
    private func attachSnapshot(_ url: URL, key: SymmetricKey) throws {
        do {
            // The path is bound. The key is part of the text, as in `PRAGMA key`: a statement that does not compile
            // carries its text in the error, so the key is taken out of that text again.
            try run(
                "ATTACH DATABASE ? AS backup KEY \(SQLiteConnection.keyLiteral(key))",
                [.text(url.path(percentEncoded: false))]
            )
        } catch SQLiteError.prepare(let message, _) {
            throw SQLiteError.prepare(message, sql: "ATTACH DATABASE ? AS backup KEY <key>")
        }
    }
}
