import CryptoKit
import Foundation
import Testing
@testable import InvoicesTracker

/// The database actor: opening, `write`, `read`, rekeying and closing. The write counter is tested with the schema.
struct DatabaseTests {
    // MARK: Opening

    @Test func aWrongKeyIsRefusedAndLeavesTheFileAsItWas() async throws {
        let key = randomKey()
        let (database, directory) = try makeDatabase(key: key)
        defer { removeTemporaryDirectory(directory) }
        await database.close()

        #expect(throws: SQLiteError.wrongKey) {
            _ = try Database(fileURL: database.fileURL, key: randomKey())
        }

        let reopened = try Database(fileURL: database.fileURL, key: key)
        #expect(try await reopened.schemaVersion() == Schema.latestVersion)
    }

    @Test func theFileIsNotPlaintext() async throws {
        let (database, directory) = try makeDatabase()
        defer { removeTemporaryDirectory(directory) }
        try await database.write {
            try $0.run("INSERT INTO app_settings(key, value) VALUES ('probe', ?)", [.text("Tajná Příbram 14350")])
        }
        await database.close()

        let bytes = try #require(FileManager.default.contents(atPath: database.fileURL.path(percentEncoded: false)))
        #expect(!bytes.starts(with: Data("SQLite format 3\0".utf8)))
        #expect(bytes.range(of: Data("Tajná Příbram".utf8)) == nil)
        #expect(bytes.range(of: Data("uniform_rate".utf8)) == nil)
    }

    // MARK: Write and read

    @Test func aWriteReturnsTheResultOfItsBodyAndKeepsItsChanges() async throws {
        let key = randomKey()
        let (database, directory) = try makeDatabase(key: key)
        defer { removeTemporaryDirectory(directory) }

        let rowID = try await database.write { connection in
            try connection.run(
                "INSERT INTO fetch_log(at, kind, target, ok, message) VALUES (1, 'cnbDaily', 'x', 1, '')"
            )
            return connection.lastInsertRowID
        }

        #expect(rowID == 1)
        await database.close()
        let reopened = try Database(fileURL: database.fileURL, key: key)
        #expect(try await reopened.integer("SELECT count(*) FROM fetch_log") == 1)
    }

    @Test func readSeesTheChangesOfEarlierWrites() async throws {
        let (database, directory) = try makeDatabase()
        defer { removeTemporaryDirectory(directory) }

        try await database.write { try $0.run("INSERT INTO app_settings(key, value) VALUES ('app', '{}')") }

        let value = try await database.read { try $0.scalar("SELECT value FROM app_settings WHERE key = 'app'") }
        #expect(value == .text("{}"))
    }

    @Test func readRunsWithoutATransactionAndWriteInsideOne() async throws {
        let (database, directory) = try makeDatabase()
        defer { removeTemporaryDirectory(directory) }

        // A transaction cannot begin inside another, so this only works where there is none.
        try await database.read { connection in
            try connection.execute("BEGIN")
            try connection.execute("ROLLBACK")
        }
        await #expect(throws: SQLiteError.self) {
            try await database.write { try $0.execute("BEGIN") }
        }
    }

    @Test func aWriteInsideAWriteFailsInsteadOfNesting() async throws {
        let (database, directory) = try makeDatabase()
        defer { removeTemporaryDirectory(directory) }

        // Transactions do not nest: the inner write is refused, and the outer one is rolled back with it.
        await #expect(throws: SQLiteError.self) {
            try await database.writeInsideWrite()
        }

        #expect(await database.writeCount == 0)
        #expect(try await database.integer("SELECT count(*) FROM meta WHERE key = 'outer'") == 0)
        // The database is still usable.
        try await database.write { try $0.run("INSERT INTO meta(key, value) VALUES ('after', '1')") }
        #expect(await database.writeCount == 1)
    }

    // MARK: Rekeying and closing

    @Test func rekeyReplacesTheKeyOfTheFile() async throws {
        let first = randomKey()
        let second = randomKey()
        let (database, directory) = try makeDatabase(key: first)
        defer { removeTemporaryDirectory(directory) }
        try await database.write { try $0.run("INSERT INTO meta(key, value) VALUES ('probe', '1')") }

        try await database.rekey(to: second)

        // The open database goes on working with the new key.
        try await database.write { try $0.run("INSERT INTO meta(key, value) VALUES ('probe2', '2')") }
        await database.close()
        #expect(throws: SQLiteError.wrongKey) {
            _ = try Database(fileURL: database.fileURL, key: first)
        }
        let reopened = try Database(fileURL: database.fileURL, key: second)
        #expect(try await reopened.integer("SELECT count(*) FROM meta WHERE key LIKE 'probe%'") == 2)
        #expect(try await reopened.schemaVersion() == Schema.latestVersion)
    }

    /// A rekey that cannot begin, because another connection holds the lock for writing, fails. SQLCipher has then
    /// switched the key it writes pages with, though the file keeps the old one: a page written after it would leave a
    /// file that opens with neither key. So the connection is closed instead, and the file opens with the old key as it
    /// was.
    @Test func aRekeyThatFailsClosesTheConnectionAndTheFileKeepsTheOldKey() async throws {
        let first = randomKey()
        let (database, directory) = try makeDatabase(key: first)
        defer { removeTemporaryDirectory(directory) }
        try await database.write { try $0.run("INSERT INTO meta(key, value) VALUES ('probe', '1')") }
        let writer = try SQLiteConnection(path: database.fileURL.path(percentEncoded: false), key: first)
        try writer.execute("BEGIN IMMEDIATE")

        await #expect(throws: SQLiteError.self) {
            try await database.rekey(to: randomKey())
        }

        try writer.execute("ROLLBACK")
        writer.close()
        await #expect(throws: SQLiteError.self) {
            try await database.write { try $0.run("INSERT INTO meta(key, value) VALUES ('probe2', '2')") }
        }
        let reopened = try Database(fileURL: database.fileURL, key: first)
        #expect(try await reopened.text("PRAGMA quick_check") == "ok")
        #expect(try await reopened.integer("SELECT count(*) FROM meta WHERE key LIKE 'probe%'") == 1)
    }

    @Test func aClosedDatabaseThrowsInsteadOfCrashing() async throws {
        let (database, directory) = try makeDatabase()
        defer { removeTemporaryDirectory(directory) }

        await database.close()
        await database.close()

        await #expect(throws: SQLiteError.self) {
            _ = try await database.schemaVersion()
        }
        await #expect(throws: SQLiteError.self) {
            try await database.write { try $0.run("INSERT INTO meta(key, value) VALUES ('a', '1')") }
        }
        await #expect(throws: SQLiteError.self) {
            _ = try await database.read { try $0.query("SELECT 1") }
        }
        #expect(await database.writeCount == 0)
    }
}

/// What a repository does wrong when it opens a transaction inside another one.
private extension Database {
    func writeInsideWrite() throws {
        try write { connection in
            try connection.run("INSERT INTO meta(key, value) VALUES ('outer', '1')")
            try write { _ in }
        }
    }
}
