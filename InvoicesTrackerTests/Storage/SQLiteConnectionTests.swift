import CryptoKit
import Foundation
import Testing
@testable import InvoicesTracker

/// Swift Testing creates a new instance of the suite for every test, so each test gets its own
/// temporary directory, which is removed again when the instance goes away.
final class SQLiteConnectionTests {
    private struct Rollback: Error {}

    private let directory: URL

    init() throws {
        directory = try makeTemporaryDirectory()
    }

    deinit {
        removeTemporaryDirectory(directory)
    }

    private var databasePath: String {
        directory.appending(path: "test.sqlite").path(percentEncoded: false)
    }

    private static func isConstraint(_ error: any Error) -> Bool {
        guard case .constraint? = error as? SQLiteError else { return false }
        return true
    }

    private static func isPrepare(_ error: any Error) -> Bool {
        guard case .prepare? = error as? SQLiteError else { return false }
        return true
    }

    // MARK: Values

    @Test func roundTripsValues() throws {
        let connection = try SQLiteConnection(path: databasePath, key: randomKey())
        try connection.run("CREATE TABLE t(a INTEGER, b TEXT, c BLOB)")
        try connection.run(
            "INSERT INTO t(a, b, c) VALUES (?, ?, ?)",
            [.integer(42), .text("Příbram"), .blob(Data([1, 2, 3]))]
        )

        let rows = try connection.query("SELECT a, b, c FROM t")

        let row = try #require(rows.first)
        #expect(rows.count == 1)
        #expect(row[0] == .integer(42))
        #expect(row[1] == .text("Příbram"))
        #expect(row[2] == .blob(Data([1, 2, 3])))
    }

    @Test func roundTripsNullEmptyAndExtremeValues() throws {
        let connection = try SQLiteConnection(path: databasePath, key: randomKey())
        try connection.run("CREATE TABLE t(a INTEGER, b TEXT, c BLOB)")
        let sets: [[SQLValue]] = [
            [.null, .null, .null],
            [.integer(0), .text(""), .blob(Data())],
            [.integer(.max), .text("a\0b"), .blob(Data([0, 255, 0]))],
            [.integer(.min), .text("Příliš žluťoučký kůň 🙂"), .blob(Data(repeating: 7, count: 10_000))],
        ]
        for values in sets {
            try connection.run("INSERT INTO t(a, b, c) VALUES (?, ?, ?)", values)
        }

        let rows = try connection.query("SELECT a, b, c FROM t ORDER BY rowid")

        #expect(rows.map { [$0[0], $0[1], $0[2]] } == sets)
    }

    @Test func rowAccessorsConvertColumns() {
        let row = SQLRow(values: [
            .integer(7), .text("text"), .blob(Data([1, 2])), .null,
            .integer(1), .integer(0), .integer(-3),
        ])

        #expect(row.int64(0) == 7)
        #expect(row.optionalInt64(0) == 7)
        #expect(row.text(1) == "text")
        #expect(row.optionalText(1) == "text")
        #expect(row.blob(2) == Data([1, 2]))
        #expect(row.optionalBlob(2) == Data([1, 2]))
        #expect(row.optionalInt64(3) == nil)
        #expect(row.optionalText(3) == nil)
        #expect(row.optionalBlob(3) == nil)
        #expect(row[3] == .null)
        #expect(row.bool(4))
        #expect(!row.bool(5))
        #expect(row.bool(6))
    }

    @Test func realValuesAreRejected() throws {
        // The app stores no floating point, so one coming out of a query is a mistake in the query.
        let connection = try SQLiteConnection(path: databasePath, key: randomKey())

        #expect(throws: SQLiteError.self) {
            _ = try connection.query("SELECT 1.5")
        }
        #expect(try connection.scalar("SELECT CAST(1.5 AS INTEGER)") == .integer(1))
    }

    @Test func scalarReturnsFirstColumnOfFirstRow() throws {
        let connection = try SQLiteConnection(path: databasePath, key: randomKey())
        try connection.run("CREATE TABLE t(a INTEGER, b TEXT)")
        try connection.run("INSERT INTO t(a, b) VALUES (1, 'one'), (2, 'two')")

        #expect(try connection.scalar("SELECT b, a FROM t ORDER BY a") == .text("one"))
        #expect(try connection.scalar("SELECT a FROM t WHERE a = ?", [.integer(2)]) == .integer(2))
        #expect(try connection.scalar("SELECT a FROM t WHERE a = ?", [.integer(3)]) == nil)
        #expect(try connection.scalar("SELECT max(a) FROM t WHERE a > ?", [.integer(9)]) == .null)
    }

    @Test func executeRunsSeveralStatements() throws {
        let connection = try SQLiteConnection(path: databasePath, key: randomKey())

        try connection.execute("""
            CREATE TABLE a(x INTEGER);
            INSERT INTO a(x) VALUES (1), (2);
            CREATE TABLE b(y INTEGER);
            INSERT INTO b(y) SELECT x * 10 FROM a; -- a trailing comment
            """)

        #expect(try connection.query("SELECT y FROM b ORDER BY y").map { $0.int64(0) } == [10, 20])
    }

    @Test func lastInsertRowIDFollowsInserts() throws {
        let connection = try SQLiteConnection(path: databasePath, key: randomKey())
        try connection.run("CREATE TABLE t(a INTEGER)")

        try connection.run("INSERT INTO t(a) VALUES (10)")
        #expect(connection.lastInsertRowID == 1)
        try connection.run("INSERT INTO t(a) VALUES (20)")
        #expect(connection.lastInsertRowID == 2)
    }

    // MARK: Errors

    @Test func invalidSQLIsReportedAsPrepareError() throws {
        let connection = try SQLiteConnection(path: databasePath, key: randomKey())

        #expect {
            try connection.run("SELEC 1")
        } throws: { error in
            guard case .prepare(let message, sql: "SELEC 1")? = error as? SQLiteError else { return false }
            return !message.isEmpty
        }
    }

    @Test func runAndQueryTakeExactlyOneStatement() throws {
        let connection = try SQLiteConnection(path: databasePath, key: randomKey())
        try connection.run("CREATE TABLE t(a INTEGER)")

        // SQLite itself would run the first statement and ignore the rest.
        #expect {
            try connection.run("INSERT INTO t(a) VALUES (1); INSERT INTO t(a) VALUES (2)")
        } throws: { Self.isPrepare($0) }
        #expect {
            _ = try connection.query("SELECT 1; SELECT 2")
        } throws: { Self.isPrepare($0) }
        #expect {
            try connection.run("   -- nothing here")
        } throws: { Self.isPrepare($0) }
        #expect(try connection.scalar("SELECT count(*) FROM t") == .integer(0))

        // A closing semicolon, whitespace and comments are not another statement.
        try connection.run("INSERT INTO t(a) VALUES (1); -- done\n  ")
        #expect(try connection.scalar("SELECT count(*) FROM t") == .integer(1))
    }

    @Test func argumentsMustMatchThePlaceholders() throws {
        let connection = try SQLiteConnection(path: databasePath, key: randomKey())
        try connection.run("CREATE TABLE t(a INTEGER, b INTEGER)")

        // SQLite itself would bind NULL to a placeholder that has no argument.
        #expect {
            try connection.run("INSERT INTO t(a, b) VALUES (?, ?)", [.integer(1)])
        } throws: { Self.isPrepare($0) }
        #expect {
            try connection.run("INSERT INTO t(a, b) VALUES (?, ?)", [.integer(1), .integer(2), .integer(3)])
        } throws: { Self.isPrepare($0) }
        #expect {
            try connection.run("INSERT INTO t(a, b) VALUES (1, 2)", [.integer(1)])
        } throws: { Self.isPrepare($0) }
        #expect(try connection.scalar("SELECT count(*) FROM t") == .integer(0))
    }

    @Test func constraintViolationsAreReportedAsConstraint() throws {
        let connection = try SQLiteConnection(path: databasePath, key: randomKey())
        try connection.execute("""
            CREATE TABLE parent(id INTEGER PRIMARY KEY, name TEXT NOT NULL UNIQUE);
            CREATE TABLE child(id INTEGER PRIMARY KEY, parent_id INTEGER NOT NULL REFERENCES parent(id));
            """)
        try connection.run("INSERT INTO parent(id, name) VALUES (1, 'x')")

        #expect {
            try connection.run("INSERT INTO parent(id, name) VALUES (1, 'y')")
        } throws: { Self.isConstraint($0) }
        #expect {
            try connection.run("INSERT INTO parent(id, name) VALUES (2, 'x')")
        } throws: { Self.isConstraint($0) }
        #expect {
            try connection.run("INSERT INTO parent(id, name) VALUES (3, ?)", [.null])
        } throws: { Self.isConstraint($0) }
        #expect {
            try connection.run("INSERT INTO child(id, parent_id) VALUES (1, 99)")
        } throws: { Self.isConstraint($0) }
        #expect {
            try connection.execute("INSERT INTO parent(id, name) VALUES (1, 'z')")
        } throws: { Self.isConstraint($0) }
    }

    @Test func closedConnectionThrowsInsteadOfCrashing() throws {
        let connection = try SQLiteConnection(path: databasePath, key: randomKey())

        connection.close()
        connection.close()

        #expect(throws: SQLiteError.self) {
            try connection.run("SELECT 1")
        }
        #expect(throws: SQLiteError.self) {
            try connection.execute("SELECT 1")
        }
        #expect(connection.cipherVersion == nil)
        #expect(connection.lastInsertRowID == 0)
    }

    // MARK: Encryption

    @Test func reportsCipherVersion() throws {
        let connection = try SQLiteConnection(path: databasePath, key: randomKey())

        #expect(connection.cipherVersion?.hasPrefix("4.") == true)
    }

    @Test func fileIsNotPlaintext() throws {
        let path = databasePath
        let sqliteHeader = Data("SQLite format 3\0".utf8)
        let plaintext = Data("Tajná Příbram".utf8)
        let connection = try SQLiteConnection(path: path, key: randomKey())
        try connection.run("CREATE TABLE t(a TEXT)")
        try connection.run("INSERT INTO t(a) VALUES (?)", [.text("Tajná Příbram 14350")])

        // Until the connection closes the new pages sit in the write-ahead log, which is encrypted too.
        let logWhileOpen = try #require(FileManager.default.contents(atPath: path + "-wal"))
        #expect(!logWhileOpen.isEmpty)
        #expect(logWhileOpen.range(of: plaintext) == nil)

        connection.close()

        let database = try #require(FileManager.default.contents(atPath: path))
        #expect(!database.isEmpty)
        #expect(!database.starts(with: sqliteHeader))
        #expect(database.range(of: plaintext) == nil)
        // SQLite deletes the log when the last connection closes; a leftover one must not hold plaintext either.
        if let logAfterClose = FileManager.default.contents(atPath: path + "-wal") {
            #expect(logAfterClose.range(of: plaintext) == nil)
        }
    }

    @Test func wrongKeyIsRejected() throws {
        let path = databasePath
        let key = randomKey()
        let connection = try SQLiteConnection(path: path, key: key)
        try connection.run("CREATE TABLE t(a INTEGER)")
        connection.close()

        #expect(throws: SQLiteError.wrongKey) {
            _ = try SQLiteConnection(path: path, key: randomKey())
        }

        // The refused attempt leaves the file as it was.
        let reopened = try SQLiteConnection(path: path, key: key)
        #expect(try reopened.scalar("SELECT count(*) FROM t") == .integer(0))
    }

    @Test func rekeyReplacesKey() throws {
        let path = databasePath
        let first = randomKey()
        let second = randomKey()
        let connection = try SQLiteConnection(path: path, key: first)
        try connection.run("CREATE TABLE t(a INTEGER)")
        try connection.run("INSERT INTO t(a) VALUES (5)")

        try connection.rekey(to: second)

        #expect(try connection.query("SELECT a FROM t").map { $0.int64(0) } == [5])
        connection.close()
        #expect(throws: SQLiteError.wrongKey) {
            _ = try SQLiteConnection(path: path, key: first)
        }
        let reopened = try SQLiteConnection(path: path, key: second)
        #expect(try reopened.query("SELECT a FROM t").map { $0.int64(0) } == [5])
    }

    @Test func rekeyLeavesNoPageEncryptedWithTheOldKey() throws {
        let path = databasePath
        let first = randomKey()
        let second = randomKey()
        let connection = try SQLiteConnection(path: path, key: first)
        try connection.run("CREATE TABLE t(a BLOB)")
        try connection.run("INSERT INTO t(a) VALUES (?)", [.blob(Data(repeating: 9, count: 50_000))])

        try connection.rekey(to: second)

        // Opened for the first time only now, from the file as it stands while the connection is still open,
        // so the old key must already be useless without waiting for the log to be folded in on close.
        let copyDirectory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(copyDirectory) }
        let copy = copyDirectory.appending(path: "copy.sqlite")
        try FileManager.default.copyItem(at: URL(filePath: path), to: copy)
        let copyPath = copy.path(percentEncoded: false)
        #expect(throws: SQLiteError.wrongKey) {
            _ = try SQLiteConnection(path: copyPath, key: first)
        }
        let reopened = try SQLiteConnection(path: copyPath, key: second)
        #expect(try reopened.scalar("SELECT count(*) FROM t") == .integer(1))
    }

    @Test func keyLiteralIsQuotedLowercaseHex() {
        let key = SymmetricKey(data: Data([0x00, 0x0F, 0xA0, 0xFF] + [UInt8](repeating: 0xBC, count: 28)))

        let literal = SQLiteConnection.keyLiteral(key)

        #expect(literal == "\"x'000fa0ff" + String(repeating: "bc", count: 28) + "'\"")
    }

    @Test func worksWithoutLicenceCode() throws {
        // Nothing here (or in the wrapper) sets a licence code; the Community build must not ask for one.
        let connection = try SQLiteConnection(path: databasePath, key: randomKey())
        try connection.run("CREATE TABLE t(a INTEGER)")
        try connection.run("INSERT INTO t(a) VALUES (1)")

        #expect(try connection.scalar("SELECT a FROM t") == .integer(1))
    }

    // MARK: Configuration

    @Test func opensInWALModeWithForeignKeysAndMemoryTemp() throws {
        let connection = try SQLiteConnection(path: databasePath, key: randomKey())

        #expect(try connection.scalar("PRAGMA journal_mode") == .text("wal"))
        #expect(try connection.scalar("PRAGMA foreign_keys") == .integer(1))
        #expect(try connection.scalar("PRAGMA temp_store") == .integer(2))
        #expect(try connection.scalar("PRAGMA cipher_memory_security") == .text("1"))
        // FULL: every commit, a rekey's too, is synced to the drive before the commit returns.
        #expect(try connection.scalar("PRAGMA synchronous") == .integer(2))
    }

    @Test func transactionRollsBackOnThrow() throws {
        let connection = try SQLiteConnection(path: databasePath, key: randomKey())
        try connection.run("CREATE TABLE t(a INTEGER)")
        try connection.run("INSERT INTO t(a) VALUES (1)")

        #expect(throws: Rollback.self) {
            try connection.transaction {
                try connection.run("INSERT INTO t(a) VALUES (2)")
                throw Rollback()
            }
        }

        #expect(try connection.query("SELECT a FROM t").map { $0.int64(0) } == [1])
        // No transaction was left open: a new one can begin.
        try connection.transaction {
            try connection.run("INSERT INTO t(a) VALUES (3)")
        }
        #expect(try connection.query("SELECT a FROM t ORDER BY a").map { $0.int64(0) } == [1, 3])
    }

    @Test func transactionCommitsAndReturnsTheResultOfItsBody() throws {
        let path = databasePath
        let key = randomKey()
        let connection = try SQLiteConnection(path: path, key: key)
        try connection.run("CREATE TABLE t(a INTEGER)")

        let rowID = try connection.transaction {
            try connection.run("INSERT INTO t(a) VALUES (1)")
            return connection.lastInsertRowID
        }

        #expect(rowID == 1)
        connection.close()
        let reopened = try SQLiteConnection(path: path, key: key)
        #expect(try reopened.scalar("SELECT count(*) FROM t") == .integer(1))
    }

    @Test func aTransactionIsOpenFromBeginToCommitOrRollback() throws {
        let connection = try SQLiteConnection(path: databasePath, key: randomKey())
        try connection.run("CREATE TABLE t(a INTEGER)")
        #expect(!connection.isInTransaction)

        try connection.transaction {
            #expect(connection.isInTransaction)
            try connection.run("INSERT INTO t(a) VALUES (1)")
        }
        #expect(!connection.isInTransaction)

        #expect(throws: Rollback.self) {
            try connection.transaction { throw Rollback() }
        }
        #expect(!connection.isInTransaction)

        try connection.execute("BEGIN")
        #expect(connection.isInTransaction)
        try connection.execute("ROLLBACK")
        #expect(!connection.isInTransaction)

        connection.close()
        #expect(!connection.isInTransaction)
    }

    @Test func userVersionRoundTrips() throws {
        let path = databasePath
        let key = randomKey()
        let connection = try SQLiteConnection(path: path, key: key)
        #expect(try connection.userVersion() == 0)

        try connection.setUserVersion(7)
        #expect(try connection.userVersion() == 7)
        connection.close()

        let reopened = try SQLiteConnection(path: path, key: key)
        #expect(try reopened.userVersion() == 7)
    }

    @Test func reportsCompileOptions() throws {
        let connection = try SQLiteConnection(path: databasePath, key: randomKey())

        let options = try connection.compileOptions()
        #expect(!options.isEmpty)

        // Trigram support differs between SQLCipher builds, so its value is not fixed here. It needs FTS5 though, so
        // the two answers must agree.
        let supportsTrigram = connection.supportsFTS5Trigram()
        #expect(
            !supportsTrigram || options.contains("ENABLE_FTS5"),
            "SQLCipher \(connection.cipherVersion ?? "?"): FTS5 trigram supported = \(supportsTrigram)")
    }

    @Test func trigramProbeLeavesNothingBehind() throws {
        let connection = try SQLiteConnection(path: databasePath, key: randomKey())

        _ = connection.supportsFTS5Trigram()

        #expect(try connection.scalar("SELECT count(*) FROM temp.sqlite_master") == .integer(0))
    }
}
