import CryptoKit
import Foundation
import SQLCipher

/// A thin wrapper around one SQLCipher connection: statements with bound arguments, rows, transactions,
/// `user_version` and rekeying. Nothing else, and no mapping to model types.
///
/// Not `Sendable` and not thread-safe. One owner (an actor) holds the connection and serialises all access.
nonisolated final class SQLiteConnection {
    private var handle: OpaquePointer?

    /// Opens the database at `path` (creating it when missing) and unlocks it with the raw 256-bit `key`.
    ///
    /// Throws `.wrongKey` when the file does not decrypt with `key`, and `.notSQLCipher` when the linked
    /// library has no encryption, which would otherwise write plaintext.
    init(path: String, key: SymmetricKey) throws {
        var opened: OpaquePointer?
        // No FULLMUTEX: the owner serialises access, so SQLite's own per-connection mutex is not needed.
        let flags = SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_NOMUTEX
        guard sqlite3_open_v2(path, &opened, flags, nil) == SQLITE_OK, let database = opened else {
            let message = opened.map { String(cString: sqlite3_errmsg($0)) } ?? "Out of memory."
            sqlite3_close_v2(opened)
            throw SQLiteError.open(message)
        }
        handle = database
        do {
            try unlock(with: key)
        } catch {
            close()
            throw error
        }
    }

    deinit {
        close()
    }

    /// Closes the connection. Safe to call more than once; every later call on the connection throws.
    func close() {
        guard let database = handle else { return }
        handle = nil
        sqlite3_close_v2(database)
    }

    // MARK: Statements

    /// Runs one or more statements separated by semicolons. Rows they produce are ignored.
    func execute(_ sql: String) throws {
        let database = try openHandle()
        try sql.withCString { start in
            var next: UnsafePointer<CChar>? = start
            while let current = next, current.pointee != 0 {
                var prepared: OpaquePointer?
                guard sqlite3_prepare_v2(database, current, -1, &prepared, &next) == SQLITE_OK else {
                    throw makeError(.prepare(sql: sql), on: database)
                }
                defer { sqlite3_finalize(prepared) }
                // Nothing is prepared for trailing whitespace or comments.
                if let statement = prepared {
                    try stepToCompletion(statement, on: database)
                }
            }
        }
    }

    /// Runs one statement with `arguments` bound to its `?` placeholders. Rows it produces are ignored.
    func run(_ sql: String, _ arguments: [SQLValue] = []) throws {
        try withStatement(sql, arguments) { statement, database in
            try stepToCompletion(statement, on: database)
        }
    }

    /// Runs one statement with `arguments` bound to its `?` placeholders and returns all its rows.
    func query(_ sql: String, _ arguments: [SQLValue] = []) throws -> [SQLRow] {
        try withStatement(sql, arguments) { statement, database in
            var rows: [SQLRow] = []
            let columnCount = sqlite3_column_count(statement)
            while try step(statement, on: database) {
                var values: [SQLValue] = []
                for column in 0..<columnCount {
                    values.append(try value(of: statement, column: column))
                }
                rows.append(SQLRow(values: values))
            }
            return rows
        }
    }

    /// The first column of the first row, or `nil` when the statement returns no rows.
    func scalar(_ sql: String, _ arguments: [SQLValue] = []) throws -> SQLValue? {
        try withStatement(sql, arguments) { statement, database in
            guard try step(statement, on: database) else { return nil }
            return try value(of: statement, column: 0)
        }
    }

    /// Runs `body` in one `BEGIN IMMEDIATE` transaction: committed when it returns, rolled back when it throws.
    /// Transactions do not nest.
    func transaction<T>(_ body: () throws -> T) throws -> T {
        try execute("BEGIN IMMEDIATE")
        do {
            let result = try body()
            try execute("COMMIT")
            return result
        } catch {
            rollBack()
            throw error
        }
    }

    /// Whether a transaction is open: begun and not yet committed or rolled back.
    var isInTransaction: Bool {
        guard let database = handle else { return false }
        return sqlite3_get_autocommit(database) == 0
    }

    /// The row id of the most recent successful insert on this connection (0 before the first one).
    var lastInsertRowID: Int64 {
        guard let database = handle else { return 0 }
        return sqlite3_last_insert_rowid(database)
    }

    // MARK: Schema version

    func userVersion() throws -> Int {
        guard case .integer(let version)? = try scalar("PRAGMA user_version") else {
            throw SQLiteError.step("PRAGMA user_version returned no number.")
        }
        return Int(version)
    }

    func setUserVersion(_ version: Int) throws {
        // A pragma takes no bound arguments; an Int cannot carry SQL.
        try execute("PRAGMA user_version = \(version)")
    }

    // MARK: Encryption

    /// The SQLCipher version (for example "4.19.0 community"), or `nil` when this is not a SQLCipher
    /// library or the connection is closed.
    var cipherVersion: String? {
        guard case .text(let version)? = try? scalar("PRAGMA cipher_version"), !version.isEmpty else { return nil }
        return version
    }

    /// Re-encrypts the whole database with `key`. When this throws, the file keeps its old key throughout and the
    /// connection is closed: open the file again with the old key.
    ///
    /// A rekey that fails (another connection holds the lock for writing, the disk is full) leaves SQLCipher writing
    /// pages with the new key while the file has the old one, so the next write would leave a file that opens with
    /// neither. Closing the connection keeps that write from happening.
    func rekey(to key: SymmetricKey) throws {
        do {
            try applyKey("rekey", key)
        } catch {
            close()
            throw error
        }
        // The rewrite goes through the write-ahead log. Folding the log into the file means no page of it is
        // still encrypted with the old key. The key has changed at this point, so a checkpoint that cannot
        // finish must not be reported as a failed rekey.
        try? execute("PRAGMA wal_checkpoint(TRUNCATE)")
    }

    /// The raw key as the quoted SQLite blob literal that `PRAGMA key`, `PRAGMA rekey` and `ATTACH … KEY`
    /// take: `"x'<64 lowercase hex digits>'"`. A raw key skips the passphrase key derivation.
    static func keyLiteral(_ key: SymmetricKey) -> String {
        // Any other length would not be read as a raw key but as a passphrase.
        precondition(key.bitCount == 256, "A raw SQLCipher key has exactly 256 bits.")
        let hex = key.withUnsafeBytes { bytes in
            bytes.map { String(format: "%02x", $0) }.joined()
        }
        return "\"x'\(hex)'\""
    }

    // MARK: Library capabilities

    /// The options SQLite was compiled with, as `PRAGMA compile_options` lists them (for example "ENABLE_FTS5").
    func compileOptions() throws -> [String] {
        try query("PRAGMA compile_options").map { $0.text(0) }
    }

    /// Whether `fts5(…, tokenize='trigram')` works in this build, found out by creating and dropping a
    /// throwaway table in the connection's temporary schema.
    func supportsFTS5Trigram() -> Bool {
        do {
            try execute("CREATE VIRTUAL TABLE temp.fts_probe USING fts5(x, tokenize='trigram')")
        } catch {
            return false
        }
        // Temporary tables vanish with the connection, so a failed drop leaves nothing behind.
        try? execute("DROP TABLE temp.fts_probe")
        return true
    }
}

// MARK: - Opening

private nonisolated extension SQLiteConnection {
    func unlock(with key: SymmetricKey) throws {
        // Process-wide, and only effective for memory allocated after it is on, so it comes before the key.
        try execute("PRAGMA cipher_memory_security = ON")
        try applyKey("key", key)
        // Reading the schema is the first thing that needs the key: a wrong one (or a file that is not a
        // database) fails right here as .wrongKey.
        _ = try scalar("SELECT count(*) FROM sqlite_master")
        // Fail closed. The system SQLite ignores the key pragma and has no cipher version.
        guard cipherVersion != nil else { throw SQLiteError.notSQLCipher }
        try execute("PRAGMA journal_mode = WAL")
        // FULL syncs the write-ahead log at every commit, so a commit that returned survives a power failure.
        // Changing the data key relies on that: the rekey is on the drive before the keys file drops the old key.
        try execute("PRAGMA synchronous = FULL")
        try execute("PRAGMA foreign_keys = ON")
        try execute("PRAGMA temp_store = MEMORY")
    }

    /// Runs `PRAGMA key` or `PRAGMA rekey`. The error for a statement that fails to compile carries its SQL
    /// text, so the key is replaced by a placeholder there.
    func applyKey(_ pragma: String, _ key: SymmetricKey) throws {
        do {
            try execute("PRAGMA \(pragma) = \(Self.keyLiteral(key))")
        } catch SQLiteError.prepare(let message, _) {
            throw SQLiteError.prepare(message, sql: "PRAGMA \(pragma) = <key>")
        }
    }
}

// MARK: - Statements

private nonisolated extension SQLiteConnection {
    func openHandle() throws -> OpaquePointer {
        guard let database = handle else { throw SQLiteError.open("The database connection is closed.") }
        return database
    }

    /// Ends the transaction a failed body or commit leaves behind. After some failures (a full disk, say)
    /// SQLite has already ended it itself, and then there is nothing to roll back.
    func rollBack() {
        guard let database = handle, sqlite3_get_autocommit(database) == 0 else { return }
        try? execute("ROLLBACK")
    }

    /// Prepares exactly one statement, binds `arguments`, runs `body` and finalizes the statement.
    func withStatement<Result>(
        _ sql: String,
        _ arguments: [SQLValue],
        _ body: (_ statement: OpaquePointer, _ database: OpaquePointer) throws -> Result
    ) throws -> Result {
        let database = try openHandle()
        return try sql.withCString { text in
            var prepared: OpaquePointer?
            var tail: UnsafePointer<CChar>?
            guard sqlite3_prepare_v2(database, text, -1, &prepared, &tail) == SQLITE_OK else {
                throw makeError(.prepare(sql: sql), on: database)
            }
            guard let statement = prepared else {
                throw SQLiteError.prepare("The SQL text contains no statement.", sql: sql)
            }
            defer { sqlite3_finalize(statement) }
            // SQLite would silently ignore everything after the first statement.
            if let tail, hasStatement(at: tail, on: database) {
                throw SQLiteError.prepare("Only one statement can be run at a time; use execute() for several.", sql: sql)
            }
            // SQLite would silently bind NULL to placeholders without an argument.
            let placeholders = Int(sqlite3_bind_parameter_count(statement))
            guard arguments.count == placeholders else {
                let message = "The statement has \(placeholders) placeholders but \(arguments.count) arguments were given."
                throw SQLiteError.prepare(message, sql: sql)
            }
            try bind(arguments, to: statement, sql: sql, on: database)
            return try body(statement, database)
        }
    }

    /// Whether the text holds another statement (and not just whitespace or comments).
    func hasStatement(at text: UnsafePointer<CChar>, on database: OpaquePointer) -> Bool {
        guard text.pointee != 0 else { return false }
        var prepared: OpaquePointer?
        let result = sqlite3_prepare_v2(database, text, -1, &prepared, nil)
        sqlite3_finalize(prepared)
        return result != SQLITE_OK || prepared != nil
    }

    func bind(_ arguments: [SQLValue], to statement: OpaquePointer, sql: String, on database: OpaquePointer) throws {
        for (offset, argument) in arguments.enumerated() {
            let index = Int32(offset + 1)
            let result: Int32
            switch argument {
            case .null:
                result = sqlite3_bind_null(statement, index)
            case .integer(let value):
                result = sqlite3_bind_int64(statement, index, value)
            case .text(let value):
                // The byte count is passed so that text with NUL characters is kept whole.
                result = sqlite3_bind_text64(
                    statement, index, value, sqlite3_uint64(value.utf8.count), Self.transient, UInt8(SQLITE_UTF8)
                )
            case .blob(let value):
                if value.isEmpty {
                    // A null pointer would be bound as NULL, not as an empty blob.
                    result = sqlite3_bind_zeroblob(statement, index, 0)
                } else {
                    result = value.withUnsafeBytes { bytes in
                        sqlite3_bind_blob64(statement, index, bytes.baseAddress, sqlite3_uint64(bytes.count), Self.transient)
                    }
                }
            }
            guard result == SQLITE_OK else { throw makeError(.prepare(sql: sql), on: database) }
        }
    }

    /// Steps to the next row. Returns `false` when the statement is done.
    func step(_ statement: OpaquePointer, on database: OpaquePointer) throws -> Bool {
        switch sqlite3_step(statement) {
        case SQLITE_ROW: return true
        case SQLITE_DONE: return false
        default: throw makeError(.step, on: database)
        }
    }

    func stepToCompletion(_ statement: OpaquePointer, on database: OpaquePointer) throws {
        while try step(statement, on: database) {}
    }

    func value(of statement: OpaquePointer, column: Int32) throws -> SQLValue {
        switch sqlite3_column_type(statement, column) {
        case SQLITE_INTEGER:
            return .integer(sqlite3_column_int64(statement, column))
        case SQLITE_TEXT:
            // SQLite wants the text read before its length is asked for.
            let bytes = sqlite3_column_text(statement, column)
            let count = Int(sqlite3_column_bytes(statement, column))
            guard let bytes, count > 0 else { return .text("") }
            return .text(String(decoding: UnsafeBufferPointer(start: bytes, count: count), as: UTF8.self))
        case SQLITE_BLOB:
            let bytes = sqlite3_column_blob(statement, column)
            let count = Int(sqlite3_column_bytes(statement, column))
            guard let bytes, count > 0 else { return .blob(Data()) }
            return .blob(Data(bytes: bytes, count: count))
        case SQLITE_NULL:
            return .null
        default:
            // SQLITE_FLOAT: the app stores none, so one in a result is a mistake in the query.
            throw SQLiteError.step("Column \(column) of the result is a floating-point number; cast it to INTEGER or TEXT in the query.")
        }
    }

    /// The call that failed has to be the most recent one on the connection when this runs.
    func makeError(_ stage: FailedStage, on database: OpaquePointer) -> SQLiteError {
        let message = String(cString: sqlite3_errmsg(database))
        // The low byte is the primary result code, whether or not extended codes are switched on.
        switch sqlite3_errcode(database) & 0xFF {
        case SQLITE_NOTADB:
            return .wrongKey
        case SQLITE_CONSTRAINT:
            return .constraint(message)
        default:
            switch stage {
            case .prepare(let sql): return .prepare(message, sql: sql)
            case .step: return .step(message)
            }
        }
    }

    enum FailedStage {
        case prepare(sql: String)
        case step
    }

    /// SQLITE_TRANSIENT: tells SQLite to copy the bound bytes, because Swift frees its buffer after the call.
    /// The header defines it as a macro around a pointer cast, which Swift cannot import.
    static var transient: sqlite3_destructor_type {
        unsafeBitCast(-1, to: sqlite3_destructor_type.self)
    }
}
