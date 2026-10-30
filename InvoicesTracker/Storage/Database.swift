import CryptoKit
import Foundation

/// Which kind of table `invoice_search` is.
nonisolated enum SearchIndexKind: String, Sendable {
    /// Only ever a request, never what a database has: full-text search when the SQLCipher build has FTS5 with the
    /// trigram tokenizer, otherwise a plain table.
    case automatic

    /// An FTS5 table with the trigram tokenizer.
    case fts5

    /// An ordinary table that is searched with `LIKE`.
    case plain
}

/// The database: the one place that holds the encrypted connection. Every read and write of the app goes through
/// this actor, so statements never run at the same time.
///
/// Repositories are `extension Database` files that reach the connection with `write` and `read`. They have no
/// other way to it.
actor Database {
    nonisolated let fileURL: URL

    private let connection: SQLiteConnection

    /// The kind of `invoice_search` the database has: `.fts5` or `.plain`, as it was created. A database keeps the
    /// kind it was created with, whatever a later open asks for.
    private(set) var searchIndexKind: SearchIndexKind

    /// How many `write` calls have been committed since the database was opened. A change of the data is what asks
    /// for a new backup.
    private(set) var writeCount = 0

    /// Opens the database at `fileURL` with the raw key `key`, creating it when it is missing, and migrates it to the
    /// latest schema. `searchIndex` only matters for a database that is created now.
    ///
    /// Throws `SQLiteError.wrongKey` when the file does not open with `key`, and `SchemaError.newerThanApp` for a
    /// file written by a newer version of the app.
    init(fileURL: URL, key: SymmetricKey, searchIndex: SearchIndexKind = .automatic) throws {
        let connection = try SQLiteConnection(path: fileURL.path(percentEncoded: false), key: key)
        let kind: SearchIndexKind
        do {
            try Migrator.migrate(connection, searchIndex: searchIndex)
            kind = try Schema.recordedSearchIndexKind(in: connection)
        } catch {
            connection.close()
            throw error
        }
        self.fileURL = fileURL
        self.connection = connection
        self.searchIndexKind = kind
    }

    /// The `user_version` of the database, which is `Schema.latestVersion` once it is open.
    func schemaVersion() throws -> Int {
        try connection.userVersion()
    }

    /// Re-encrypts the whole database with `key`. When this throws, the file keeps its old key and the database is
    /// closed (see `SQLiteConnection.rekey(to:)`): every later call throws, and the file has to be opened again with
    /// the old key.
    func rekey(to key: SymmetricKey) throws {
        try connection.rekey(to: key)
    }

    /// Closes the connection. Every later call throws.
    func close() {
        connection.close()
    }

    /// Runs `body` in one transaction: committed when it returns and rolled back when it throws, and counted in
    /// `writeCount` only after the commit.
    ///
    /// For the repositories, which are inside the actor. Transactions do not nest, so a repository function that
    /// calls `write` must never be called from the body of another `write`: that body takes the connection it is
    /// given and uses it directly.
    func write<T>(_ body: (SQLiteConnection) throws -> T) throws -> T {
        let result = try connection.transaction { try body(connection) }
        writeCount += 1
        return result
    }

    /// Runs `body` with the connection and no transaction of its own. It sees the changes of the `write` it is
    /// called from, if any. Nothing else can write while it runs.
    func read<T>(_ body: (SQLiteConnection) throws -> T) throws -> T {
        try body(connection)
    }
}
