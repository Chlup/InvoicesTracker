import CryptoKit
import Foundation
import Testing
@testable import InvoicesTracker

// MARK: - Invented data

/// What the suites below build their backups from. A software key protector stands in for the Secure Enclave.
private enum BackupFixtures {
    static let deviceName = "Testovací MacBook"

    /// A moment written in the Mac's own time zone and in the Gregorian calendar, whatever calendar the Mac is set to,
    /// so that the file name of a backup, which is made the same way, shows the same digits wherever the tests run.
    static func localDate(_ year: Int, _ month: Int, _ day: Int, _ hour: Int, _ minute: Int, _ second: Int) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .autoupdatingCurrent
        let components = DateComponents(
            year: year, month: month, day: day, hour: hour, minute: minute, second: second
        )
        guard let value = calendar.date(from: components) else {
            preconditionFailure("Not a date: \(components)")
        }
        return value
    }

    /// An invoice of invented data with its own number: `202609` and `number` as two digits.
    static func invoice(_ number: Int) -> Invoice {
        Invoice.fixture(number: "202609" + String(format: "%02d", number))
    }

    /// The key slots of `dek`: a software device slot and one recovery slot, together with that slot's code.
    static func keys(for dek: SymmetricKey) throws -> (keys: KeysFile, code: String) {
        let recovery = try KeyManager.makeRecoverySlot(for: dek, number: 1, created: civilDate("2026-10-17"))
        let keys = KeysFile(
            deviceSlot: try SoftwareKeyProtector().seal(dek, userPresence: true),
            recoverySlots: [recovery.slot]
        )
        return (keys, recovery.code)
    }

    /// The number of invoices in the encrypted file at `url`, which is opened with `key` as it stands.
    static func invoiceCount(in url: URL, key: SymmetricKey) throws -> Int64 {
        let connection = try SQLiteConnection(path: url.path(percentEncoded: false), key: key)
        guard case .integer(let count)? = try connection.scalar("SELECT count(*) FROM invoice") else {
            preconditionFailure("count(*) is a number.")
        }
        return count
    }

    /// The names of everything in `directory`, hidden files too, in alphabetical order.
    static func names(in directory: URL) throws -> [String] {
        try FileManager.default.contentsOfDirectory(atPath: directory.path(percentEncoded: false)).sorted()
    }

    /// Sets the date the file at `url` was last changed.
    static func setModified(_ url: URL, to date: Date) throws {
        try FileManager.default.setAttributes([.modificationDate: date], ofItemAtPath: url.path(percentEncoded: false))
    }

    /// Makes the file at `url` impossible to delete, or possible again: not even its owner can remove a file that has
    /// the "user immutable" flag.
    static func setLocked(_ url: URL, _ locked: Bool) throws {
        try FileManager.default.setAttributes([.immutable: locked], ofItemAtPath: url.path(percentEncoded: false))
    }

    /// Whether there is a file or folder at `url`.
    static func exists(_ url: URL) -> Bool {
        FileManager.default.fileExists(atPath: url.path(percentEncoded: false))
    }

    /// Sets the permissions of the file or folder at `url`, for example `0o555` for a folder nothing can be added to.
    static func setPermissions(_ mode: Int, on url: URL) throws {
        try FileManager.default.setAttributes([.posixPermissions: mode], ofItemAtPath: url.path(percentEncoded: false))
    }

    /// Makes every file under `directory` deletable again, so that the directory can be removed.
    static func unlockAll(in directory: URL) {
        guard let items = FileManager.default.enumerator(at: directory, includingPropertiesForKeys: nil) else { return }
        for case let url as URL in items {
            try? setLocked(url, false)
        }
    }

    /// Writes `bytes` to a hidden or visible file of the given name in `directory`, which is made when it is missing.
    @discardableResult
    static func write(_ bytes: String, as name: String, in directory: URL) throws -> URL {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appending(path: name)
        try Data(bytes.utf8).write(to: url)
        return url
    }

    /// The four bytes of `value` in big-endian order.
    static func bigEndian(_ value: UInt32) -> Data {
        Data([UInt8(value >> 24), UInt8((value >> 16) & 0xFF), UInt8((value >> 8) & 0xFF), UInt8(value & 0xFF)])
    }

    /// A file as the format lays it out, with whatever length, header bytes and magic the test wants.
    static func framed(
        length: UInt32,
        header: Data,
        database: Data = Data(),
        magic: Data = BackupFormat.magic
    ) -> Data {
        magic + bigEndian(length) + header + database
    }

    /// A file as the format lays it out, with the length that belongs to `header`.
    static func framed(header: Data, database: Data = Data()) -> Data {
        framed(length: UInt32(header.count), header: header, database: database)
    }
}

// MARK: - Snapshot

/// The encrypted copy of the whole database that a backup is made from.
struct SnapshotTests {
    @Test(arguments: availableSearchIndexKinds)
    func aSnapshotOpensWithTheSameKeyAndHoldsTheSchemaVersionTheInvoicesAndTheSearch(
        kind: SearchIndexKind
    ) async throws {
        let key = randomKey()
        let (database, directory) = try makeDatabase(searchIndex: kind, key: key)
        defer { removeTemporaryDirectory(directory) }
        try await database.saveInvoice(BackupFixtures.invoice(1))
        try await database.saveInvoice(BackupFixtures.invoice(2))
        let snapshot = directory.appending(path: "snapshot.sqlite")

        try await database.exportSnapshot(to: snapshot, key: key)

        // The file is not plaintext: neither the SQLite header nor an invoice's client can be found in it.
        let bytes = try #require(FileManager.default.contents(atPath: snapshot.path(percentEncoded: false)))
        #expect(!bytes.starts(with: Data("SQLite format 3\0".utf8)))
        #expect(bytes.range(of: Data("Alfa Systems".utf8)) == nil)
        // It opens with the key of the database and with no other. `sqlcipher_export` does not copy `user_version`.
        let copy = try SQLiteConnection(path: snapshot.path(percentEncoded: false), key: key)
        #expect(try copy.userVersion() == Schema.latestVersion)
        #expect(try copy.scalar("SELECT count(*) FROM invoice") == .integer(2))
        #expect(try copy.scalar("SELECT count(*) FROM invoice_item") == .integer(2))
        #expect(try copy.scalar("SELECT count(*) FROM invoice_search") == .integer(2))
        #expect(try copy.scalar("SELECT count(*) FROM uniform_rate WHERE origin = 'builtIn'") != .integer(0))
        copy.close()
        #expect(throws: SQLiteError.wrongKey) {
            _ = try SQLiteConnection(path: snapshot.path(percentEncoded: false), key: randomKey())
        }
        // A snapshot is a database the app opens as it is: nothing is left to migrate, and the search finds the
        // invoices in the copy of its table, whichever kind of table that is.
        let reopened = try Database(fileURL: snapshot, key: key)
        #expect(try await reopened.invoiceCount() == 2)
        #expect(try await reopened.schemaVersion() == Schema.latestVersion)
        #expect(await reopened.searchIndexKind == kind)
        let found = try await reopened.searchInvoiceIDs(
            "alfa systems", scope: .issued, year: 2026, asOf: civilDate("2026-10-17")
        )
        #expect(found.count == 2)
    }

    @Test func aSnapshotIsTheStateAtTheMomentOfTheExportAndChangesNothingInTheDatabase() async throws {
        let key = randomKey()
        let (database, directory) = try makeDatabase(key: key)
        defer { removeTemporaryDirectory(directory) }
        try await database.saveInvoice(BackupFixtures.invoice(1))
        try await database.saveInvoice(BackupFixtures.invoice(2))
        let first = directory.appending(path: "first.sqlite")
        let second = directory.appending(path: "second.sqlite")
        let writesBefore = await database.writeCount

        try await database.exportSnapshot(to: first, key: key)

        // Making a copy is not a change of the data, which is what asks for the next backup.
        #expect(await database.writeCount == writesBefore)
        // Nothing stays attached, so the next snapshot works, and the database goes on being written to.
        try await database.saveInvoice(BackupFixtures.invoice(3))
        try await database.exportSnapshot(to: second, key: key)
        #expect(try BackupFixtures.invoiceCount(in: first, key: key) == 2)
        #expect(try BackupFixtures.invoiceCount(in: second, key: key) == 3)
        #expect(try await database.invoiceCount() == 3)
    }

    @Test func aSnapshotCanBeEncryptedWithAnotherKeyThanTheDatabase() async throws {
        let (database, directory) = try makeDatabase()
        defer { removeTemporaryDirectory(directory) }
        try await database.saveInvoice(BackupFixtures.invoice(1))
        let other = randomKey()
        let snapshot = directory.appending(path: "snapshot.sqlite")

        try await database.exportSnapshot(to: snapshot, key: other)

        #expect(try BackupFixtures.invoiceCount(in: snapshot, key: other) == 1)
    }

    @Test func aSnapshotCanBeWrittenIntoAnEmptyFile() async throws {
        let key = randomKey()
        let (database, directory) = try makeDatabase(key: key)
        defer { removeTemporaryDirectory(directory) }
        try await database.saveInvoice(BackupFixtures.invoice(1))
        let snapshot = directory.appending(path: "snapshot.sqlite")
        try Data().write(to: snapshot)

        try await database.exportSnapshot(to: snapshot, key: key)

        #expect(try BackupFixtures.invoiceCount(in: snapshot, key: key) == 1)
    }

    @Test func aFailedExportLeavesTheDatabaseUsableAndNothingAttached() async throws {
        let key = randomKey()
        let (database, directory) = try makeDatabase(key: key)
        defer { removeTemporaryDirectory(directory) }
        try await database.saveInvoice(BackupFixtures.invoice(1))
        let snapshot = directory.appending(path: "snapshot.sqlite")
        try await database.exportSnapshot(to: snapshot, key: key)

        // The tables are in the file already, so copying them into it again fails after the file is attached.
        await #expect(throws: SQLiteError.self) {
            try await database.exportSnapshot(to: snapshot, key: key)
        }

        let again = directory.appending(path: "again.sqlite")
        try await database.exportSnapshot(to: again, key: key)
        try await database.saveInvoice(BackupFixtures.invoice(2))
        #expect(try BackupFixtures.invoiceCount(in: again, key: key) == 1)
        #expect(try await database.invoiceCount() == 2)
    }

    /// SQLite attaches a file inside a transaction but then refuses to detach it, which would leave it attached for
    /// good, so the snapshot is refused before anything is attached.
    @Test func aSnapshotInsideAWriteIsRefusedAndLeavesNothingAttached() async throws {
        let key = randomKey()
        let (database, directory) = try makeDatabase(key: key)
        defer { removeTemporaryDirectory(directory) }
        let snapshot = directory.appending(path: "snapshot.sqlite")

        await #expect(throws: SQLiteError.self) {
            try await database.exportInsideWrite(to: snapshot, key: key)
        }

        try await database.exportSnapshot(to: directory.appending(path: "later.sqlite"), key: key)
        #expect(!FileManager.default.fileExists(atPath: snapshot.path(percentEncoded: false)))
    }

    @Test func aSnapshotOfAClosedDatabaseThrows() async throws {
        let key = randomKey()
        let (database, directory) = try makeDatabase(key: key)
        defer { removeTemporaryDirectory(directory) }
        await database.close()

        await #expect(throws: SQLiteError.self) {
            try await database.exportSnapshot(to: directory.appending(path: "snapshot.sqlite"), key: key)
        }
    }
}

/// What a repository does wrong when it asks for a snapshot from the body of a write, and a way to break the database
/// in the middle of a backup.
private extension Database {
    func exportInsideWrite(to url: URL, key: SymmetricKey) throws {
        try write { _ in
            try exportSnapshot(to: url, key: key)
        }
    }

    /// Takes away the table the number of invoices is read from.
    func dropInvoiceTable() throws {
        try write { try $0.execute("DROP TABLE invoice") }
    }
}

// MARK: - Backup file

/// The `.ttbackup` file: magic, header length, header, database bytes.
final class BackupFormatTests {
    private let directory: URL

    init() throws {
        directory = try makeTemporaryDirectory()
    }

    deinit {
        removeTemporaryDirectory(directory)
    }

    private func makeHeader(
        formatVersion: Int = 1,
        created: Date = date("2026-10-17T12:05:12Z"),
        clientCount: Int? = nil,
        years: ClosedRange<Int>? = nil,
        deviceName: String = BackupFixtures.deviceName,
        keys: KeysFile = KeysFile(recoverySlots: [])
    ) -> BackupHeader {
        BackupHeader(
            formatVersion: formatVersion, created: created, appVersion: "1.0", schemaVersion: 1, invoiceCount: 2,
            clientCount: clientCount, years: years, deviceName: deviceName, keys: keys
        )
    }

    /// A file of `bytes` named `name` in the test's directory.
    private func makeFile(_ name: String, _ bytes: Data) throws -> URL {
        let url = directory.appending(path: name)
        try bytes.write(to: url)
        return url
    }

    // MARK: Layout and round trip

    @Test func theHeaderAndTheDatabaseBytesComeBackExactly() throws {
        let dek = randomKey()
        let header = makeHeader(keys: try BackupFixtures.keys(for: dek).keys)
        // More than two copy chunks, so the borders of the chunks are crossed.
        let database = KeyManager.randomBytes(count: 2_500_000)
        let databaseFile = try makeFile("snapshot.sqlite", database)
        let backup = directory.appending(path: "backup.ttbackup")

        try BackupFormat.write(header: header, databaseFile: databaseFile, to: backup)

        #expect(try BackupFormat.readHeader(from: backup) == header)
        let extracted = directory.appending(path: "extracted.sqlite")
        try BackupFormat.extractDatabase(from: backup, to: extracted)
        #expect(try Data(contentsOf: extracted) == database)
        // The file the backup was made from is not touched.
        #expect(try Data(contentsOf: databaseFile) == database)
    }

    /// The layout of the file. Changing it would leave the backups already written unreadable.
    @Test func theFileIsTheMagicTheBigEndianLengthTheSortedHeaderJSONAndTheDatabase() throws {
        let database = Data((0..<300).map { UInt8(truncatingIfNeeded: $0 * 7) })
        let databaseFile = try makeFile("snapshot.sqlite", database)
        let backup = directory.appending(path: "backup.ttbackup")

        try BackupFormat.write(header: makeHeader(), databaseFile: databaseFile, to: backup)

        let json =
            #"{"appVersion":"1.0","created":"2026-10-17T12:05:12Z","deviceName":"Testovací MacBook","#
            + #""formatVersion":1,"invoiceCount":2,"keys":{"formatVersion":1,"recoverySlots":[]},"schemaVersion":1}"#
        #expect(BackupFormat.magic == Data("TTBACKUP1".utf8))
        #expect(try Data(contentsOf: backup) == BackupFixtures.framed(header: Data(json.utf8), database: database))
        // The length is 4 bytes in big endian, whatever the byte order of this Mac is.
        let length = try Data(contentsOf: backup).dropFirst(9).prefix(4)
        #expect(length == BackupFixtures.bigEndian(UInt32(json.utf8.count)))
    }

    @Test func theCountOfClientsAndTheYearsOfTheDataComeBackExactly() throws {
        let databaseFile = try makeFile("snapshot.sqlite", Data(repeating: 7, count: 300))
        let backup = directory.appending(path: "backup.ttbackup")
        let header = makeHeader(clientCount: 3, years: 2024...2026)

        try BackupFormat.write(header: header, databaseFile: databaseFile, to: backup)

        let read = try BackupFormat.readHeader(from: backup)
        #expect(read == header)
        #expect(read.clientCount == 3)
        #expect(read.years == 2024...2026)
        // They are plain fields of the JSON, so that nothing but this version of the app has to read them.
        let json =
            #"{"appVersion":"1.0","clientCount":3,"created":"2026-10-17T12:05:12Z","deviceName":"Testovací MacBook","#
            + #""formatVersion":1,"invoiceCount":2,"keys":{"formatVersion":1,"recoverySlots":[]},"schemaVersion":1,"#
            + #""years":[2024,2026]}"#
        #expect(try Data(contentsOf: backup).dropFirst(13).prefix(json.utf8.count) == Data(json.utf8))
    }

    /// A backup written before the header counted the clients and named the years still reads: the fields are missing.
    @Test func aHeaderWithoutTheCountOfClientsAndTheYearsStillReads() throws {
        let json =
            #"{"appVersion":"1.0","created":"2026-10-17T12:05:12Z","deviceName":"Testovací MacBook","#
            + #""formatVersion":1,"invoiceCount":13,"keys":{"formatVersion":1,"recoverySlots":[]},"schemaVersion":1}"#
        let backup = try makeFile(
            "old.ttbackup", BackupFixtures.framed(header: Data(json.utf8), database: Data(repeating: 1, count: 100)))

        let header = try BackupFormat.readHeader(from: backup)

        #expect(header.invoiceCount == 13)
        #expect(header.clientCount == nil)
        #expect(header.years == nil)
        #expect(header.deviceName == BackupFixtures.deviceName)
    }

    /// The two fields only describe the backup, so a value that cannot be read does not make the backup unreadable.
    @Test func aCountOfClientsOrYearsThatCannotBeReadAreMissingAndTheBackupStillReads() throws {
        let json =
            #"{"appVersion":"1.0","clientCount":"three","created":"2026-10-17T12:05:12Z","#
            + #""deviceName":"Testovací MacBook","formatVersion":1,"invoiceCount":13,"#
            + #""keys":{"formatVersion":1,"recoverySlots":[]},"schemaVersion":1,"years":[2026,2024]}"#
        let backup = try makeFile(
            "odd.ttbackup", BackupFixtures.framed(header: Data(json.utf8), database: Data(repeating: 1, count: 100)))

        let header = try BackupFormat.readHeader(from: backup)

        #expect(header.invoiceCount == 13)
        #expect(header.clientCount == nil)
        #expect(header.years == nil)
    }

    @Test func writingReplacesAnExistingFileWholeAndLeavesNoTemporaryFile() throws {
        let backup = directory.appending(path: "backup.ttbackup")
        let first = try makeFile("first.sqlite", Data(repeating: 1, count: 5_000))
        let second = try makeFile("second.sqlite", Data(repeating: 2, count: 300))
        let later = makeHeader(created: date("2026-10-18T08:00:00Z"))
        try BackupFormat.write(header: makeHeader(), databaseFile: first, to: backup)

        try BackupFormat.write(header: later, databaseFile: second, to: backup)

        let extracted = directory.appending(path: "extracted.sqlite")
        try BackupFormat.extractDatabase(from: backup, to: extracted)
        #expect(try Data(contentsOf: extracted) == Data(repeating: 2, count: 300))
        #expect(try BackupFormat.readHeader(from: backup) == later)
        #expect(
            try BackupFixtures.names(in: directory)
                == ["backup.ttbackup", "extracted.sqlite", "first.sqlite", "second.sqlite"]
        )
    }

    @Test func aWriteThatFailsKeepsTheOldFileAndLeavesNoTemporaryFile() throws {
        let backup = directory.appending(path: "backup.ttbackup")
        let database = try makeFile("snapshot.sqlite", Data(repeating: 1, count: 500))
        try BackupFormat.write(header: makeHeader(), databaseFile: database, to: backup)
        let before = try Data(contentsOf: backup)

        #expect(throws: CocoaError.self) {
            try BackupFormat.write(
                header: makeHeader(), databaseFile: directory.appending(path: "missing.sqlite"), to: backup
            )
        }
        // Not even a folder to write into: nothing can be made, and the error says why.
        #expect(throws: CocoaError.self) {
            try BackupFormat.write(
                header: makeHeader(), databaseFile: database,
                to: directory.appending(path: "no such folder/backup.ttbackup")
            )
        }

        #expect(try Data(contentsOf: backup) == before)
        #expect(try BackupFixtures.names(in: directory) == ["backup.ttbackup", "snapshot.sqlite"])
    }

    @Test func aHeaderIsWrittenUpToTheLimitReadHeaderEnforcesAndNotOneByteMore() throws {
        let database = try makeFile("snapshot.sqlite", Data(repeating: 1, count: 500))
        let backup = directory.appending(path: "backup.ttbackup")
        // The length of the JSON of a header with no device name, from a backup written with one.
        try BackupFormat.write(header: makeHeader(deviceName: ""), databaseFile: database, to: backup)
        let lengthField = try Data(contentsOf: backup).dropFirst(BackupFormat.magic.count).prefix(4)
        let emptyNameLength = lengthField.reduce(0) { $0 << 8 | Int($1) }
        let exactName = String(repeating: "x", count: BackupFormat.maximumHeaderLength - emptyNameLength)
        let atTheLimit = makeHeader(deviceName: exactName)

        try BackupFormat.write(header: atTheLimit, databaseFile: database, to: backup)

        #expect(try BackupFormat.readHeader(from: backup) == atTheLimit)
        let before = try Data(contentsOf: backup)
        let namesBefore = try BackupFixtures.names(in: directory)
        // One byte more: refused whether there is a file to replace or not, and nothing is created or changed.
        let tooLong = makeHeader(deviceName: exactName + "x")
        #expect(throws: BackupError.notABackup) {
            try BackupFormat.write(header: tooLong, databaseFile: database, to: backup)
        }
        #expect(throws: BackupError.notABackup) {
            let other = directory.appending(path: "new.ttbackup")
            try BackupFormat.write(header: tooLong, databaseFile: database, to: other)
        }
        #expect(try Data(contentsOf: backup) == before)
        #expect(try BackupFixtures.names(in: directory) == namesBefore)
    }

    // MARK: Files that are not backups

    fileprivate struct MalformedFile: Sendable, CustomTestStringConvertible {
        let name: String
        let bytes: Data

        init(_ name: String, _ bytes: Data) {
            self.name = name
            self.bytes = bytes
        }

        var testDescription: String { name }
    }

    fileprivate static let malformedFiles: [MalformedFile] = {
        let magic = BackupFormat.magic
        let json = Data(#"{"formatVersion":1}"#.utf8)
        let database = Data(repeating: 0x5A, count: 64)
        return [
            MalformedFile("an empty file", Data()),
            MalformedFile("an SQLite file", Data("SQLite format 3\0".utf8) + Data(repeating: 0, count: 4_096)),
            MalformedFile(
                "another magic",
                BackupFixtures.framed(
                    length: UInt32(json.count), header: json, database: database, magic: Data("TTBACKUP2".utf8)
                )
            ),
            MalformedFile("a cut magic", magic.prefix(5)),
            MalformedFile("the magic only", magic),
            MalformedFile("a cut length", magic + Data([0, 0])),
            MalformedFile("a length and no header", BackupFixtures.framed(length: 20, header: Data())),
            MalformedFile("a cut header", BackupFixtures.framed(length: UInt32(json.count), header: json.prefix(5))),
            MalformedFile(
                "a header longer than the file",
                BackupFixtures.framed(length: .max, header: Data(), database: database)
            ),
            MalformedFile(
                "a header above 1 MiB",
                BackupFixtures.framed(length: 2 << 20, header: Data(repeating: 0x20, count: (2 << 20) + 100))
            ),
            MalformedFile(
                "a header that is not JSON", BackupFixtures.framed(header: Data("not json".utf8), database: database)
            ),
            MalformedFile("JSON that is not a header", BackupFixtures.framed(header: json, database: database)),
            MalformedFile("a header and no database", BackupFixtures.framed(header: json)),
        ]
    }()

    @Test(arguments: malformedFiles)
    fileprivate func aFileThatIsNotABackupIsRejectedAndNothingIsExtracted(_ file: MalformedFile) throws {
        let backup = try makeFile("damaged.ttbackup", file.bytes)
        let target = directory.appending(path: "extracted.sqlite")

        #expect(throws: BackupError.notABackup) {
            _ = try BackupFormat.readHeader(from: backup)
        }
        #expect(throws: BackupError.notABackup) {
            try BackupFormat.extractDatabase(from: backup, to: target)
        }
        #expect(try BackupFixtures.names(in: directory) == ["damaged.ttbackup"])
    }

    @Test func aBackupOfANewerFormatIsNotReadable() throws {
        let database = try makeFile("snapshot.sqlite", Data(repeating: 1, count: 500))
        let backup = directory.appending(path: "backup.ttbackup")
        try BackupFormat.write(header: makeHeader(formatVersion: 2), databaseFile: database, to: backup)

        #expect(throws: BackupError.notABackup) {
            _ = try BackupFormat.readHeader(from: backup)
        }
    }

    @Test func aMissingFileIsAnErrorOfTheFileSystemAndNotAFileThatIsNotABackup() {
        let missing = directory.appending(path: "missing.ttbackup")

        #expect(throws: CocoaError.self) {
            _ = try BackupFormat.readHeader(from: missing)
        }
        #expect(throws: CocoaError.self) {
            try BackupFormat.extractDatabase(from: missing, to: directory.appending(path: "extracted.sqlite"))
        }
    }

    @Test func extractingToAFileThatCannotBeWrittenLeavesNothingBehind() throws {
        let database = try makeFile("snapshot.sqlite", Data(repeating: 1, count: 500))
        let backup = directory.appending(path: "backup.ttbackup")
        try BackupFormat.write(header: makeHeader(), databaseFile: database, to: backup)

        #expect(throws: CocoaError.self) {
            try BackupFormat.extractDatabase(from: backup, to: directory.appending(path: "no such folder/db.sqlite"))
        }

        #expect(try BackupFixtures.names(in: directory) == ["backup.ttbackup", "snapshot.sqlite"])
    }
}

// MARK: - Backup service

/// Making backups, keeping the newest, listing them, writing to the folder outside the Mac and the rules for when a
/// backup is due.
@MainActor
struct BackupServiceTests {
    // MARK: Set-up

    /// A database with invoices, its keys, a service that backs it up into `Backups/` beside it, and the clock that
    /// service reads. `directory` is the test's to remove.
    private struct Setup {
        let database: Database
        let key: SymmetricKey
        let keys: KeysFile
        let recoveryCode: String
        let directory: URL
        let backupsDirectory: URL
        let clock: ManualClock
        let service: BackupService

        /// Makes a backup into `target` (the local backups folder unless given) at the clock's time, and checks that
        /// tidying up went well.
        @discardableResult
        func makeBackup(into target: URL? = nil) async throws -> URL {
            let result = try await makeBackupResult(into: target)
            #expect(result.cleanupError == nil)
            return result.url
        }

        /// The same, with the result as it is.
        func makeBackupResult(into target: URL? = nil) async throws -> BackupResult {
            try await service.makeBackup(database: database, key: key, keys: keys, into: target)
        }

        /// Makes a backup in the folder the bookmark points to, and checks that tidying up went well.
        @discardableResult
        func makeOffMacBackup(bookmark: Data) async throws -> URL {
            let result = try await service.writeOffMacBackup(
                database: database, key: key, keys: keys, bookmark: bookmark, withoutUI: false
            )
            #expect(result.cleanupError == nil)
            return result.url
        }

        /// Exports a backup to `fileURL`.
        func exportBackup(to fileURL: URL) async throws {
            try await service.exportBackup(database: database, key: key, keys: keys, to: fileURL)
        }
    }

    private static let start = BackupFixtures.localDate(2026, 10, 17, 14, 5, 12)

    private func makeSetup(invoices: Int = 2, keep: Int = 30, at time: Date = start) async throws -> Setup {
        let key = randomKey()
        let (database, directory) = try makeDatabase(key: key)
        do {
            for number in 0..<invoices {
                try await database.saveInvoice(BackupFixtures.invoice(number + 1))
            }
            let (keys, code) = try BackupFixtures.keys(for: key)
            let clock = ManualClock(time)
            let backups = directory.appending(path: "Backups", directoryHint: .isDirectory)
            return Setup(
                database: database, key: key, keys: keys, recoveryCode: code, directory: directory,
                backupsDirectory: backups, clock: clock,
                service: BackupService(
                    backupsDirectory: backups, clock: clock, appVersion: "1.0",
                    deviceName: BackupFixtures.deviceName, keep: keep
                )
            )
        } catch {
            removeTemporaryDirectory(directory)
            throw error
        }
    }

    /// A service for the rules, which look at the clock and nothing else.
    private func makeRulesService(_ clock: ManualClock) -> BackupService {
        BackupService(
            backupsDirectory: FileManager.default.temporaryDirectory.appending(path: "TaxesTrackerTests-unused"),
            clock: clock, appVersion: "1.0", deviceName: BackupFixtures.deviceName
        )
    }

    /// An empty folder in the test's directory, and a bookmark that points to it.
    private func makeOffMacFolder(in directory: URL) throws -> (folder: URL, bookmark: Data) {
        let folder = directory.appending(path: "Off the Mac", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return (folder, try BackupService.makeBookmark(for: folder))
    }

    // MARK: Making a backup

    @Test func aBackupIsNamedAfterTheClockInLocalTimeAndKeepsTheSecondsOfItsMoment() async throws {
        // The folder does not exist yet, and the clock is a fraction after the second.
        let setup = try await makeSetup(at: Self.start.addingTimeInterval(0.7))
        defer { removeTemporaryDirectory(setup.directory) }

        let result = try await setup.makeBackupResult()
        let url = result.url

        #expect(result.cleanupError == nil)
        // The moment of the backup, which is the time to record as the last backup, is the one its header has.
        #expect(result.created == Self.start)
        #expect(url.lastPathComponent == "InvoicesTracker 2026-10-17 14-05-12.ttbackup")
        #expect(
            url.deletingLastPathComponent().resolvingSymlinksInPath()
                == setup.backupsDirectory.resolvingSymlinksInPath()
        )
        let header = try BackupFormat.readHeader(from: url)
        #expect(
            header
                == BackupHeader(
                    created: Self.start, appVersion: "1.0", schemaVersion: Schema.latestVersion, invoiceCount: 2,
                    clientCount: 0, years: 2026...2026, deviceName: BackupFixtures.deviceName, keys: setup.keys
                )
        )
    }

    @Test func theHeaderCountsTheClientsAndNamesTheFirstAndTheLastYearWithData() async throws {
        let setup = try await makeSetup(invoices: 1)
        defer { removeTemporaryDirectory(setup.directory) }
        try await setup.database.saveClient(Client(name: "Alfa Systems s.r.o."))
        try await setup.database.saveClient(Client(name: "Bravo Labs, Inc."))
        try await setup.database.saveInvoice(
            Invoice.fixture(number: "20240301", duzp: "2024-03-31", dueDate: "2024-04-14"))
        // A draft belongs to no year, and a payment makes its own year one with data.
        try await setup.database.saveInvoice(
            Invoice.fixture(number: "20230401", duzp: "2023-04-30", dueDate: "2023-05-14", status: .draft))
        try await setup.database.saveInvoice(
            Invoice.fixture(
                number: "20261201", duzp: "2026-12-31", dueDate: "2027-01-14",
                payment: Payment.fixture(on: "2027-01-02")))

        let url = try await setup.makeBackup()

        let header = try BackupFormat.readHeader(from: url)
        #expect(header.invoiceCount == 4)
        #expect(header.clientCount == 2)
        #expect(header.years == 2024...2027)
    }

    @Test func theHeaderOfABackupOfEmptyDataCountsNothingAndNamesNoYear() async throws {
        let setup = try await makeSetup(invoices: 0)
        defer { removeTemporaryDirectory(setup.directory) }

        let url = try await setup.makeBackup()

        let header = try BackupFormat.readHeader(from: url)
        #expect(header.invoiceCount == 0)
        #expect(header.clientCount == 0)
        #expect(header.years == nil)
    }

    @Test func theBackupHoldsTheDatabaseAndNoSnapshotIsLeftBehind() async throws {
        let setup = try await makeSetup()
        defer { removeTemporaryDirectory(setup.directory) }

        let url = try await setup.makeBackup()

        #expect(try BackupFixtures.names(in: setup.backupsDirectory) == [url.lastPathComponent])
        // Only the header is readable: the invoices are in the encrypted part.
        let bytes = try Data(contentsOf: url)
        #expect(bytes.range(of: Data("Alfa Systems".utf8)) == nil)
        #expect(bytes.range(of: Data("SQLite format 3".utf8)) == nil)
        let extracted = setup.directory.appending(path: "extracted.sqlite")
        try BackupFormat.extractDatabase(from: url, to: extracted)
        let restored = try Database(fileURL: extracted, key: setup.key)
        #expect(try await restored.invoiceCount() == 2)
        #expect(try await restored.schemaVersion() == Schema.latestVersion)
    }

    /// What a restore does with a backup: the keys in the header, the recovery code, the data key, the database.
    @Test func aBackupOpensWithTheRecoveryCodeAndNothingElse() async throws {
        let setup = try await makeSetup()
        defer { removeTemporaryDirectory(setup.directory) }
        let url = try await setup.makeBackup()

        let header = try BackupFormat.readHeader(from: url)
        let unlocked = try KeyManager.unlock(header.keys, recoveryCode: setup.recoveryCode)
        let extracted = setup.directory.appending(path: "extracted.sqlite")
        try BackupFormat.extractDatabase(from: url, to: extracted)

        #expect(try BackupFixtures.invoiceCount(in: extracted, key: unlocked.dek) == 2)
    }

    @Test func backupsMadeInTheSameSecondGetNumberedNamesAndListNewestFirst() async throws {
        let setup = try await makeSetup(invoices: 1)
        defer { removeTemporaryDirectory(setup.directory) }
        var urls: [URL] = []

        for number in 2...4 {
            urls.append(try await setup.makeBackup())
            try await setup.database.saveInvoice(BackupFixtures.invoice(number))
        }

        let stem = "InvoicesTracker 2026-10-17 14-05-12"
        #expect(urls.map(\.lastPathComponent) == ["\(stem).ttbackup", "\(stem) 2.ttbackup", "\(stem) 3.ttbackup"])
        // The clock gives the three the same moment, so the number in the name tells which is newer.
        let listing = try setup.service.localBackups()
        #expect(
            listing.map(\.url.lastPathComponent) == ["\(stem) 3.ttbackup", "\(stem) 2.ttbackup", "\(stem).ttbackup"]
        )
        #expect(listing.map(\.header.invoiceCount) == [3, 2, 1])
    }

    @Test func tenBackupsInTheSameSecondAreListedInTheOrderTheyWereMadeIn() async throws {
        let setup = try await makeSetup(invoices: 0)
        defer { removeTemporaryDirectory(setup.directory) }

        for number in 1...11 {
            try await setup.database.saveInvoice(BackupFixtures.invoice(number))
            try await setup.makeBackup()
        }

        // "… 10" and "… 11" come after "… 9", though comparing the characters would put them before "… 2".
        #expect(try setup.service.localBackups().map(\.header.invoiceCount) == Array((1...11).reversed()))
    }

    @Test func backupsStartedTogetherNeverShareAName() async throws {
        let setup = try await makeSetup()
        defer { removeTemporaryDirectory(setup.directory) }

        async let first = setup.makeBackup()
        async let second = setup.makeBackup()
        async let third = setup.makeBackup()
        let urls = try await [first, second, third]

        #expect(Set(urls.map(\.lastPathComponent)).count == 3)
        #expect(try BackupFixtures.names(in: setup.backupsDirectory) == urls.map(\.lastPathComponent).sorted())
    }

    @Test func aBackupThatFailsAfterTheSnapshotLeavesNothingBehind() async throws {
        let setup = try await makeSetup()
        defer { removeTemporaryDirectory(setup.directory) }
        // Without its table the number of invoices cannot be read, which a backup asks once the snapshot is written.
        try await setup.database.dropInvoiceTable()

        await #expect(throws: SQLiteError.self) {
            try await setup.makeBackup()
        }

        #expect(try BackupFixtures.names(in: setup.backupsDirectory) == [])
    }

    // MARK: Keeping the newest

    @Test func afterThirtyTwoBackupsTheNewestThirtyRemain() async throws {
        let setup = try await makeSetup()
        defer { removeTemporaryDirectory(setup.directory) }

        for _ in 1...32 {
            try await setup.makeBackup()
            setup.clock.advance(by: 60)
        }

        let listing = try setup.service.localBackups()
        #expect(listing.count == 30)
        #expect(try BackupFixtures.names(in: setup.backupsDirectory).count == 30)
        // The 32nd was made 31 minutes after the 1st, the 3rd two minutes after it.
        #expect(listing.first?.header.created == Self.start.addingTimeInterval(31 * 60))
        #expect(listing.last?.header.created == Self.start.addingTimeInterval(2 * 60))
        #expect(listing.first?.url.lastPathComponent == "InvoicesTracker 2026-10-17 14-36-12.ttbackup")
        #expect(listing.last?.url.lastPathComponent == "InvoicesTracker 2026-10-17 14-07-12.ttbackup")
    }

    /// A backup can be told to spare a file, such as the backup being restored, however old it is; the next backup
    /// that is not told so treats it like any other.
    @Test func aBackupSparesTheFileItIsToldToSpare() async throws {
        let setup = try await makeSetup(keep: 2)
        defer { removeTemporaryDirectory(setup.directory) }
        let oldest = try await setup.makeBackup()
        setup.clock.advance(by: 60)
        try await setup.makeBackup()
        setup.clock.advance(by: 60)

        let spared = try await setup.service.makeBackup(
            database: setup.database, key: setup.key, keys: setup.keys, sparing: oldest
        )

        #expect(spared.cleanupError == nil)
        #expect(BackupFixtures.exists(oldest))
        #expect(try setup.service.localBackups().count == 3)
        setup.clock.advance(by: 60)
        try await setup.makeBackup()
        #expect(!BackupFixtures.exists(oldest))
        #expect(try setup.service.localBackups().count == 2)
    }

    @Test func backupsAreKeptByTheDateInTheirHeaderAndNotByWhenTheFileWasMade() async throws {
        let setup = try await makeSetup(keep: 2)
        defer { removeTemporaryDirectory(setup.directory) }
        let noon = BackupFixtures.localDate(2026, 10, 17, 12, 0, 0)
        let ten = BackupFixtures.localDate(2026, 10, 17, 10, 0, 0)
        let eleven = BackupFixtures.localDate(2026, 10, 17, 11, 0, 0)

        for time in [noon, ten, eleven] {
            setup.clock.set(time)
            try await setup.makeBackup()
        }

        // The one dated 10:00 was made before the last one, and is the oldest.
        #expect(try setup.service.localBackups().map(\.header.created) == [noon, eleven])
    }

    @Test func theBackupJustMadeIsNeverDeletedEvenWhenTheClockWentBack() async throws {
        let setup = try await makeSetup(keep: 2)
        defer { removeTemporaryDirectory(setup.directory) }
        let noon = BackupFixtures.localDate(2026, 10, 17, 12, 0, 0)
        for time in [noon, BackupFixtures.localDate(2026, 10, 17, 11, 0, 0)] {
            setup.clock.set(time)
            try await setup.makeBackup()
        }

        // The clock was wrong and has been put right: this backup is older than the two before it.
        setup.clock.set(BackupFixtures.localDate(2026, 10, 17, 10, 0, 0))
        let url = try await setup.makeBackup()

        #expect(FileManager.default.fileExists(atPath: url.path(percentEncoded: false)))
        #expect(try setup.service.localBackups().count == 3)
        // The next one finds it among the oldest.
        let afternoon = BackupFixtures.localDate(2026, 10, 17, 13, 0, 0)
        setup.clock.set(afternoon)
        try await setup.makeBackup()
        #expect(try setup.service.localBackups().map(\.header.created) == [afternoon, noon])
    }

    @Test func filesThatAreNotReadableBackupsAreNeverDeleted() async throws {
        let setup = try await makeSetup(keep: 1)
        defer { removeTemporaryDirectory(setup.directory) }
        try FileManager.default.createDirectory(at: setup.backupsDirectory, withIntermediateDirectories: true)
        let damaged = setup.backupsDirectory.appending(path: "Damaged.ttbackup")
        let notes = setup.backupsDirectory.appending(path: "Notes.txt")
        try Data("not a backup".utf8).write(to: damaged)
        try Data("not mine".utf8).write(to: notes)
        // Both are older than the backups, whatever the clock of the test says.
        for file in [damaged, notes] {
            try FileManager.default.setAttributes(
                [.modificationDate: Date(timeIntervalSince1970: 1_000_000_000)],
                ofItemAtPath: file.path(percentEncoded: false)
            )
        }

        for _ in 1...3 {
            try await setup.makeBackup()
            setup.clock.advance(by: 60)
        }

        #expect(try Data(contentsOf: damaged) == Data("not a backup".utf8))
        #expect(try Data(contentsOf: notes) == Data("not mine".utf8))
        #expect(try setup.service.localBackups().map(\.header.created) == [Self.start.addingTimeInterval(120)])
        #expect(try BackupFixtures.names(in: setup.backupsDirectory).count == 3)
    }

    @Test func aDirectoryOfItsOwnIsKeptApartFromTheLocalBackups() async throws {
        let setup = try await makeSetup(keep: 2)
        defer { removeTemporaryDirectory(setup.directory) }
        let other = setup.directory.appending(path: "Elsewhere", directoryHint: .isDirectory)

        try await setup.makeBackup()
        for _ in 1...3 {
            setup.clock.advance(by: 60)
            try await setup.makeBackup(into: other)
        }

        #expect(try setup.service.localBackups().count == 1)
        #expect(try BackupFixtures.names(in: other).count == 2)
        #expect(try BackupFixtures.names(in: other).allSatisfy { $0.hasSuffix(".ttbackup") })
    }

    /// A damaged file is not a backup, so it takes no place among the newest to keep. Counting it would push good
    /// backups out, and a folder with `keep` damaged files would end up with nothing readable.
    @Test func recentDamagedFilesDoNotTakeThePlaceOfTheBackupsToKeep() async throws {
        let setup = try await makeSetup(keep: 2)
        defer { removeTemporaryDirectory(setup.directory) }
        // One under a name of the kind the service gives, one under any other, both changed after every backup below.
        let damaged = [
            try BackupFixtures.write("not a backup", as: "Damaged.ttbackup", in: setup.backupsDirectory),
            try BackupFixtures.write(
                "not a backup either", as: "InvoicesTracker 2026-10-17 14-30-00.ttbackup", in: setup.backupsDirectory
            ),
        ]
        for file in damaged {
            try BackupFixtures.setModified(file, to: Self.start.addingTimeInterval(3600))
        }

        for _ in 1...4 {
            try await setup.makeBackup()
            setup.clock.advance(by: 60)
        }

        // The two newest backups stay, and so do both damaged files.
        #expect(try setup.service.localBackups().map(\.header.created) == [180, 120].map { Self.start + $0 })
        #expect(try Data(contentsOf: damaged[0]) == Data("not a backup".utf8))
        #expect(try Data(contentsOf: damaged[1]) == Data("not a backup either".utf8))
        #expect(try BackupFixtures.names(in: setup.backupsDirectory).count == 4)
    }

    /// Backups under other names (a hand-made export, another Mac's, a copy someone renamed) are not the service's to
    /// count or to delete, whether they are older or newer than its own.
    @Test func backupsUnderOtherNamesAreNeverCountedOrDeleted() async throws {
        let setup = try await makeSetup(keep: 1)
        defer { removeTemporaryDirectory(setup.directory) }
        let folder = setup.backupsDirectory
        let strangers = [
            "Export 2026-03-01.ttbackup",
            "MacBook Air 2026-03-01 08-00-00.ttbackup",
            "InvoicesTracker 2026-03-01 08-00-00 copy.ttbackup",
            "InvoicesTracker 2026-03-01 08-00-01 (2).ttbackup",
            "InvoicesTracker 2026-03-01 08-00-02 2 3.ttbackup",
            "InvoicesTracker 2026-03-01.ttbackup",
            "invoicestracker 2026-03-01 08-00-03.ttbackup",
            "InvoicesTracker 2026-03-01 08-00-04.TTBACKUP",
        ]
        // Half of them are older than the service's own backups below, half newer.
        for (index, name) in strangers.enumerated() {
            setup.clock.set(Self.start.addingTimeInterval(index < 4 ? -30 * 86_400 : 30 * 86_400))
            try await setup.exportBackup(to: folder.appending(path: name))
        }
        let before = try contents(of: folder)

        setup.clock.set(Self.start)
        for _ in 1...3 {
            try await setup.makeBackup()
            setup.clock.advance(by: 60)
        }

        // Of its own backups the service kept the newest one, and none of the others was counted or touched.
        let newest = "InvoicesTracker 2026-10-17 14-07-12.ttbackup"
        #expect(try BackupFixtures.names(in: folder) == (strangers + [newest]).sorted())
        let after = try contents(of: folder)
        for name in strangers {
            #expect(after[name] == before[name])
        }
    }

    /// The backup is made when old ones cannot be deleted, and the caller is told so it can record the backup.
    @Test func aBackupThatWasWrittenIsReportedEvenWhenOldBackupsCannotBeDeleted() async throws {
        let setup = try await makeSetup(keep: 3)
        defer {
            BackupFixtures.unlockAll(in: setup.directory)
            removeTemporaryDirectory(setup.directory)
        }
        var made: [URL] = []
        for _ in 1...3 {
            made.append(try await setup.makeBackup())
            setup.clock.advance(by: 60)
        }
        // The oldest cannot be deleted. A service that keeps one backup finds three to delete.
        try BackupFixtures.setLocked(made[0], true)
        let strict = BackupService(
            backupsDirectory: setup.backupsDirectory, clock: setup.clock, appVersion: "1.0",
            deviceName: BackupFixtures.deviceName, keep: 1
        )

        let result = try await strict.makeBackup(database: setup.database, key: setup.key, keys: setup.keys)

        #expect(result.cleanupError != nil)
        #expect(try BackupFormat.readHeader(from: result.url).invoiceCount == 2)
        // Every deletion was tried: the two that could be deleted are gone, the other stays.
        #expect(
            try BackupFixtures.names(in: setup.backupsDirectory)
                == [made[0].lastPathComponent, result.url.lastPathComponent].sorted()
        )
    }

    // MARK: Leftovers

    /// A leftover of a backup that was cut short is a whole copy of the data, encrypted, so it does not stay for good:
    /// the hidden temporary files of the service that are more than a day old go when a backup starts, from the local
    /// folder and from the folder the backup goes to.
    @Test func hiddenTemporaryFilesMoreThanADayOldAreRemovedWhenABackupStarts() async throws {
        let setup = try await makeSetup()
        defer { removeTemporaryDirectory(setup.directory) }
        let local = setup.backupsDirectory
        let other = setup.directory.appending(path: "Elsewhere", directoryHint: .isDirectory)
        let day: TimeInterval = 86_400
        func uuid() -> String { UUID().uuidString }

        // Old enough to go, in both folders.
        let old = [
            try BackupFixtures.write("a", as: ".snapshot-\(uuid()).tmp", in: local),
            try BackupFixtures.write("b", as: ".export.\(uuid()).partial", in: local),
            try BackupFixtures.write(
                "c", as: ".InvoicesTracker 2026-10-15 09-00-00.ttbackup.\(uuid()).partial", in: other
            ),
            try BackupFixtures.write("d", as: ".snapshot-\(uuid()).tmp", in: other),
        ]
        for file in old {
            try BackupFixtures.setModified(file, to: Self.start.addingTimeInterval(-day - 1))
        }
        // Younger than a day: a backup may be in the middle of being made.
        let young = [
            try BackupFixtures.write("e", as: ".snapshot-\(uuid()).tmp", in: local),
            try BackupFixtures.write("f", as: ".export.\(uuid()).partial", in: other),
            try BackupFixtures.write("g", as: ".snapshot-\(uuid()).tmp", in: other),
        ]
        try BackupFixtures.setModified(young[0], to: Self.start.addingTimeInterval(-3600))
        try BackupFixtures.setModified(young[1], to: Self.start.addingTimeInterval(-day + 1))
        try BackupFixtures.setModified(young[2], to: Self.start)
        // Not temporary files of the service, however old.
        let strangers = [
            try BackupFixtures.write("h", as: ".DS_Store", in: other),
            try BackupFixtures.write("i", as: ".snapshot-no-uuid.tmp", in: local),
            try BackupFixtures.write("j", as: ".hidden.partial", in: other),
            try BackupFixtures.write("k", as: "snapshot-\(uuid()).tmp", in: local),
            try BackupFixtures.write(
                "l", as: "InvoicesTracker 2026-10-15 09-00-00.ttbackup.\(uuid()).partial", in: other
            ),
        ]
        for file in strangers {
            try BackupFixtures.setModified(file, to: Self.start.addingTimeInterval(-30 * day))
        }

        let result = try await setup.makeBackupResult(into: other)

        #expect(result.cleanupError == nil)
        #expect(try BackupFormat.readHeader(from: result.url).invoiceCount == 2)
        for file in old {
            #expect(!BackupFixtures.exists(file), "\(file.lastPathComponent)")
        }
        for file in young + strangers {
            #expect(BackupFixtures.exists(file), "\(file.lastPathComponent)")
        }
    }

    @Test func aLeftoverThatCannotBeRemovedIsReportedAndDoesNotStopTheBackup() async throws {
        let setup = try await makeSetup()
        defer {
            BackupFixtures.unlockAll(in: setup.directory)
            removeTemporaryDirectory(setup.directory)
        }
        let stuck = try BackupFixtures.write("a", as: ".snapshot-\(UUID().uuidString).tmp", in: setup.backupsDirectory)
        try BackupFixtures.setModified(stuck, to: Self.start.addingTimeInterval(-2 * 86_400))
        try BackupFixtures.setLocked(stuck, true)

        let result = try await setup.makeBackupResult()

        #expect(result.cleanupError != nil)
        #expect(try BackupFormat.readHeader(from: result.url).invoiceCount == 2)
        #expect(BackupFixtures.exists(stuck))
    }

    // MARK: Export

    /// Every file of `folder`, hidden ones too, by name.
    private func contents(of folder: URL) throws -> [String: Data] {
        var files: [String: Data] = [:]
        for name in try BackupFixtures.names(in: folder) {
            files[name] = try Data(contentsOf: folder.appending(path: name))
        }
        return files
    }

    @Test func anExportWritesOneFileAndLeavesTheRestOfTheFolderAlone() async throws {
        let setup = try await makeSetup(keep: 1)
        defer { removeTemporaryDirectory(setup.directory) }
        let folder = setup.directory.appending(path: "Exports", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        // What the person keeps there: backups under the service's own kind of names, more than the service keeps
        // (made by another one that keeps more), some notes, and a hidden file that looks like an old leftover.
        let archivist = BackupService(
            backupsDirectory: setup.backupsDirectory, clock: setup.clock, appVersion: "1.0",
            deviceName: BackupFixtures.deviceName, keep: 30
        )
        setup.clock.set(Self.start.addingTimeInterval(-3 * 86_400))
        for _ in 1...3 {
            let result = try await archivist.makeBackup(
                database: setup.database, key: setup.key, keys: setup.keys, into: folder
            )
            #expect(result.cleanupError == nil)
            setup.clock.advance(by: 3600)
        }
        try BackupFixtures.write("Do not touch", as: "Notes.txt", in: folder)
        let lookalike = try BackupFixtures.write("old", as: ".snapshot-\(UUID().uuidString).tmp", in: folder)
        try BackupFixtures.setModified(lookalike, to: Self.start.addingTimeInterval(-5 * 86_400))
        let before = try contents(of: folder)
        setup.clock.set(Self.start)
        let destination = folder.appending(path: "For the accountant.ttbackup")

        try await setup.exportBackup(to: destination)

        // One new file, and every other byte of the folder as it was.
        let after = try contents(of: folder)
        #expect(Set(after.keys) == Set(before.keys).union(["For the accountant.ttbackup"]))
        for (name, bytes) in before {
            #expect(after[name] == bytes, "\(name)")
        }
        // The new file is a backup like any other.
        let header = try BackupFormat.readHeader(from: destination)
        #expect(header.created == Self.start)
        #expect(header.invoiceCount == 2)
        #expect(header.keys == setup.keys)
        let unlocked = try KeyManager.unlock(header.keys, recoveryCode: setup.recoveryCode)
        let extracted = setup.directory.appending(path: "extracted.sqlite")
        try BackupFormat.extractDatabase(from: destination, to: extracted)
        #expect(try BackupFixtures.invoiceCount(in: extracted, key: unlocked.dek) == 2)
        // It was made in the local folder, which is left empty and lists nothing.
        #expect(try BackupFixtures.names(in: setup.backupsDirectory) == [])
        #expect(try setup.service.localBackups().isEmpty)
    }

    @Test func anExportReplacesTheFileThePersonChoseWhole() async throws {
        let setup = try await makeSetup()
        defer { removeTemporaryDirectory(setup.directory) }
        let folder = setup.directory.appending(path: "Exports", directoryHint: .isDirectory)
        let destination = try BackupFixtures.write("something older", as: "Chosen.ttbackup", in: folder)

        try await setup.exportBackup(to: destination)
        #expect(try BackupFormat.readHeader(from: destination).created == Self.start)

        setup.clock.advance(by: 3600)
        try await setup.database.saveInvoice(BackupFixtures.invoice(3))
        try await setup.exportBackup(to: destination)

        let header = try BackupFormat.readHeader(from: destination)
        #expect(header.created == Self.start.addingTimeInterval(3600))
        #expect(header.invoiceCount == 3)
        #expect(try BackupFixtures.names(in: folder) == ["Chosen.ttbackup"])
    }

    @Test func anExportThatFailsChangesNothing() async throws {
        let setup = try await makeSetup()
        defer { removeTemporaryDirectory(setup.directory) }
        let folder = setup.directory.appending(path: "Exports", directoryHint: .isDirectory)
        let destination = try BackupFixtures.write("what the person had", as: "Chosen.ttbackup", in: folder)
        // Without its table the number of invoices cannot be read, which a backup asks once the snapshot is written.
        try await setup.database.dropInvoiceTable()

        await #expect(throws: SQLiteError.self) {
            try await setup.exportBackup(to: destination)
        }
        await #expect(throws: SQLiteError.self) {
            try await setup.exportBackup(to: folder.appending(path: "New.ttbackup"))
        }

        #expect(try BackupFixtures.names(in: folder) == ["Chosen.ttbackup"])
        #expect(try Data(contentsOf: destination) == Data("what the person had".utf8))
        #expect(try BackupFixtures.names(in: setup.backupsDirectory) == [])
    }

    // MARK: Listing

    @Test func localBackupsAreListedNewestFirstWithTheirHeaders() async throws {
        let setup = try await makeSetup(invoices: 1)
        defer { removeTemporaryDirectory(setup.directory) }
        // Nothing has been backed up, and not even the folder is there.
        #expect(try setup.service.localBackups().isEmpty)

        var urls: [URL] = []
        for number in 2...4 {
            urls.append(try await setup.makeBackup())
            try await setup.database.saveInvoice(BackupFixtures.invoice(number))
            setup.clock.advance(by: 60)
        }

        let listing = try setup.service.localBackups()
        #expect(listing.map(\.url.lastPathComponent) == urls.reversed().map(\.lastPathComponent))
        #expect(listing.map(\.header.invoiceCount) == [3, 2, 1])
        #expect(listing.map(\.header.created) == [120, 60, 0].map { Self.start.addingTimeInterval($0) })
        #expect(listing.allSatisfy { $0.header.keys == setup.keys })
        #expect(listing.allSatisfy { $0.header.deviceName == BackupFixtures.deviceName })
    }

    @Test func theListingLeavesOutFilesThatAreNotBackups() async throws {
        let setup = try await makeSetup()
        defer { removeTemporaryDirectory(setup.directory) }
        let url = try await setup.makeBackup()
        try Data("not a backup".utf8).write(to: setup.backupsDirectory.appending(path: "Damaged.ttbackup"))
        try Data("not mine".utf8).write(to: setup.backupsDirectory.appending(path: "Notes.txt"))
        try FileManager.default.createDirectory(
            at: setup.backupsDirectory.appending(path: "Folder.ttbackup", directoryHint: .isDirectory),
            withIntermediateDirectories: true
        )

        #expect(try setup.service.localBackups().map(\.url.lastPathComponent) == [url.lastPathComponent])
    }

    // MARK: When a backup is due

    @Test func anOffMacBackupIsDueOnceADayHasPassedSinceTheLastOne() {
        let last = date("2026-10-17T12:00:00Z")
        let clock = ManualClock(last)
        let service = makeRulesService(clock)

        clock.set(last.addingTimeInterval(23 * 3600))
        #expect(!service.isOffMacBackupDue(last: last))
        clock.set(last.addingTimeInterval(24 * 3600 - 1))
        #expect(!service.isOffMacBackupDue(last: last))
        clock.set(last.addingTimeInterval(24 * 3600))
        #expect(service.isOffMacBackupDue(last: last))
        clock.set(last.addingTimeInterval(25 * 3600))
        #expect(service.isOffMacBackupDue(last: last))
        // None yet is due, not a reminder.
        #expect(service.isOffMacBackupDue(last: nil))
    }

    @Test func aReminderComesWhenAFolderIsSetAndThirtyDaysPassedWithoutAnOffMacBackup() {
        let last = date("2026-09-01T12:00:00Z")
        let clock = ManualClock(last)
        let service = makeRulesService(clock)

        clock.set(last.addingTimeInterval(29 * 86_400))
        #expect(!service.needsOffMacReminder(last: last, folderSet: true))
        clock.set(last.addingTimeInterval(30 * 86_400))
        #expect(service.needsOffMacReminder(last: last, folderSet: true))
        clock.set(last.addingTimeInterval(31 * 86_400))
        #expect(service.needsOffMacReminder(last: last, folderSet: true))
        // Without a folder there is nothing to remind of (the settings warn about that), and with a folder and no
        // backup yet the backup is simply due.
        #expect(!service.needsOffMacReminder(last: last, folderSet: false))
        #expect(!service.needsOffMacReminder(last: nil, folderSet: true))
        #expect(!service.needsOffMacReminder(last: nil, folderSet: false))
    }

    // MARK: The folder outside the Mac

    @Test func aBookmarkOfAFolderLetsTheServiceWriteABackupThere() async throws {
        let setup = try await makeSetup()
        defer { removeTemporaryDirectory(setup.directory) }
        let (folder, bookmark) = try makeOffMacFolder(in: setup.directory)

        let url = try await setup.makeOffMacBackup(bookmark: bookmark)

        #expect(url.deletingLastPathComponent().resolvingSymlinksInPath() == folder.resolvingSymlinksInPath())
        #expect(url.lastPathComponent == "InvoicesTracker 2026-10-17 14-05-12.ttbackup")
        #expect(try BackupFormat.readHeader(from: url).invoiceCount == 2)
        #expect(try BackupFixtures.names(in: folder) == [url.lastPathComponent])
        // The folder outside the Mac is not the local one.
        #expect(try setup.service.localBackups().isEmpty)
    }

    /// A folder outside the Mac may be shared with another Mac whose app names its backups the same way: the retention
    /// of this Mac ranks and deletes only the backups this Mac made, by the name of the Mac in their headers.
    @Test func theFolderOutsideTheMacKeepsTheBackupsOfAnotherMacWhateverTheirNumberAndAge() async throws {
        let setup = try await makeSetup()
        defer { removeTemporaryDirectory(setup.directory) }
        let (folder, bookmark) = try makeOffMacFolder(in: setup.directory)
        let body = try BackupFixtures.write("an invented database", as: "body.bin", in: setup.directory)
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = .autoupdatingCurrent
        formatter.dateFormat = "yyyy-MM-dd HH-mm-ss"
        /// A backup of the Mac named `device`, made `daysAgo` days before the start of the test, in the folder.
        func place(_ device: String, daysAgo: Int) throws {
            let created = Self.start.addingTimeInterval(-Double(daysAgo) * 86_400)
            let header = BackupHeader(
                created: created, appVersion: "1.0", schemaVersion: 1, invoiceCount: 1, deviceName: device,
                keys: setup.keys)
            let name = "InvoicesTracker \(formatter.string(from: created)).ttbackup"
            try BackupFormat.write(header: header, databaseFile: body, to: folder.appending(path: name))
        }
        // Ten of "Jiný Mac", older than all of this Mac's, which would be the first to go, and thirty-five of this Mac.
        for daysAgo in 41...50 {
            try place("Jiný Mac", daysAgo: daysAgo)
        }
        for daysAgo in 1...35 {
            try place(BackupFixtures.deviceName, daysAgo: daysAgo)
        }

        try await setup.makeOffMacBackup(bookmark: bookmark)

        let headers = try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)
            .map { try BackupFormat.readHeader(from: $0) }
        #expect(headers.filter { $0.deviceName == "Jiný Mac" }.count == 10)
        let own = headers.filter { $0.deviceName == BackupFixtures.deviceName }.map(\.created)
        // The newest thirty of this Mac: the one just made and those of the last 29 days.
        #expect(own.count == 30)
        #expect(own.min() == Self.start.addingTimeInterval(-29 * 86_400))
        #expect(own.contains(Self.start))
    }

    @Test func theFolderOutsideTheMacKeepsTheNewestBackupsToo() async throws {
        let setup = try await makeSetup(keep: 2)
        defer { removeTemporaryDirectory(setup.directory) }
        let (folder, bookmark) = try makeOffMacFolder(in: setup.directory)

        for _ in 1...3 {
            try await setup.makeOffMacBackup(bookmark: bookmark)
            setup.clock.advance(by: 86_400)
        }

        #expect(try BackupFixtures.names(in: folder).count == 2)
    }

    /// The snapshot is made by SQLite, with a journal and locks that a network share or a cloud folder may not support,
    /// so it is made in the local folder and only the finished backup is written to the other. A folder that cannot be
    /// written to shows it: it is the packing that fails, with an error of the file system, and not SQLite.
    @Test func theSnapshotIsMadeInTheLocalFolderAndOnlyTheFinishedBackupIsWrittenOutsideTheMac() async throws {
        let setup = try await makeSetup()
        let (folder, bookmark) = try makeOffMacFolder(in: setup.directory)
        defer {
            try? BackupFixtures.setPermissions(0o755, on: folder)
            removeTemporaryDirectory(setup.directory)
        }
        try BackupFixtures.setPermissions(0o555, on: folder)

        await #expect(throws: CocoaError.self) {
            try await setup.makeOffMacBackup(bookmark: bookmark)
        }

        #expect(try BackupFixtures.names(in: folder) == [])
        // The snapshot was made, and was removed again.
        #expect(try BackupFixtures.names(in: setup.backupsDirectory) == [])
    }

    @Test func aFolderThatIsGoneIsUnavailableAndWritesNothing() async throws {
        let setup = try await makeSetup()
        defer { removeTemporaryDirectory(setup.directory) }
        let (folder, bookmark) = try makeOffMacFolder(in: setup.directory)
        try FileManager.default.removeItem(at: folder)

        await #expect(throws: BackupError.folderUnavailable) {
            try await setup.makeOffMacBackup(bookmark: bookmark)
        }

        #expect(!FileManager.default.fileExists(atPath: folder.path(percentEncoded: false)))
    }

    @Test func dataThatIsNotABookmarkIsAnUnavailableFolder() async throws {
        let setup = try await makeSetup()
        defer { removeTemporaryDirectory(setup.directory) }

        await #expect(throws: BackupError.folderUnavailable) {
            try await setup.makeOffMacBackup(bookmark: Data("not a bookmark".utf8))
        }
        await #expect(throws: BackupError.folderUnavailable) {
            try await setup.makeOffMacBackup(bookmark: Data())
        }
    }
}

// MARK: - Restoring a backup of an earlier version

/// A backup that an earlier version of the app made holds a database of an earlier schema, which the restore brings up
/// to date.
@MainActor
struct BackupTests {
    @Test func aVersionOneBackupRestoresAndMigrates() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        // The database of a backup made before the family was kept: schema version 1, with an invoice and the
        // settings of two years.
        let key = randomKey()
        let file = directory.appending(path: "version1.sqlite")
        let old = try SQLiteConnection(path: file.path(percentEncoded: false), key: key)
        try Migrator.migrate(old, searchIndex: .plain, upTo: 1)
        try old.transaction {
            try SchemaRows.invoice(old, id: 1, digits: "20260901")
            try SchemaRows.yearSettingsBeforeVersionThree(old, year: 2025, expensePercent: 40)
            try SchemaRows.yearSettingsBeforeVersionThree(old, year: 2026, expensePercent: 80)
            try SchemaRows.advanceMonth(old, year: 2026, month: 3, social: 4_759)
        }
        old.close()
        let (keys, code) = try BackupFixtures.keys(for: key)
        let backup = directory.appending(path: "Version 1.ttbackup")
        try BackupFormat.write(
            header: BackupHeader(
                created: BackupFixtures.localDate(2026, 10, 1, 9, 30, 0), appVersion: "1.0", schemaVersion: 1,
                invoiceCount: 1, deviceName: BackupFixtures.deviceName, keys: keys
            ),
            databaseFile: file, to: backup
        )
        // The data of this Mac: none yet.
        let clock = ManualClock(BackupFixtures.localDate(2026, 10, 21, 12, 0, 0))
        let paths = VaultPaths(directory: directory.appending(path: "Data", directoryHint: .isDirectory))
        let vault = Vault(
            paths: paths, device: SoftwareKeyProtector(),
            backups: BackupService(
                backupsDirectory: paths.backups, clock: clock, appVersion: "1.0", deviceName: BackupFixtures.deviceName
            ),
            clock: clock
        )

        let restored = try await vault.restore(from: backup, recoveryCode: code)

        #expect(try await restored.schemaVersion() == Schema.latestVersion)
        #expect(try await restored.invoiceCount() == 1)
        #expect(try await restored.storedSettingsYears() == [2025, 2026])
        let settings = try await restored.yearSettings(2026)
        #expect(settings.expensePercent == 80)
        #expect(settings.advances.social[2] == 4_759)
        #expect(settings.spouse == nil)
        #expect(try await restored.family(year: 2026) == FamilyYear(year: 2026, children: [], spouse: nil))
        // The restored data keeps a family from now on.
        let childYear = ChildYear(
            household: MonthRange(from: 1, to: 12), claimant: .me, order: 1, ztpp: nil, studies: nil
        )
        let id = try await restored.saveChild(
            Child(id: nil, name: "Anna", birthDate: civilDate("2019-09-03")), year: 2026, childYear: childYear
        )
        let spouse = SpouseYear(claim: true, months: MonthRange(from: 1, to: 12), ownIncomeKc: 0, ztpp: nil)
        try await restored.saveSpouse(spouse, year: 2026)
        let family = try await restored.family(year: 2026)
        #expect(family.children.map(\.child.id) == [id])
        #expect(family.children.map(\.year) == [childYear])
        #expect(family.spouse == spouse)
        await restored.close()
    }

    @Test func aVersionTwoBackupRestoresAndMigrates() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        // The database of a backup made before the months of the expected invoices were kept and the minimum insurance
        // stopped being a choice of the year: schema version 2, with a client and an invoice, the settings of two
        // years, one of which chose the whole year, and a child with a spouse.
        let key = randomKey()
        let file = directory.appending(path: "version2.sqlite")
        let old = try SQLiteConnection(path: file.path(percentEncoded: false), key: key)
        try Migrator.migrate(old, searchIndex: .plain, upTo: 2)
        try old.transaction {
            try SchemaRows.client(old, id: 1)
            try SchemaRows.invoice(old, id: 1, digits: "20260901", clientID: 1)
            try SchemaRows.yearSettingsBeforeVersionThree(old, year: 2025, expensePercent: 40)
            try SchemaRows.yearSettingsBeforeVersionThree(old, year: 2026, expensePercent: 80, mode: "wholeYear")
            try SchemaRows.advanceMonth(old, year: 2026, month: 3, social: 4_759)
            try SchemaRows.child(old, id: 1)
            try SchemaRows.childYear(old, childID: 1, year: 2026)
            try SchemaRows.spouse(old, year: 2026)
        }
        old.close()
        let (keys, code) = try BackupFixtures.keys(for: key)
        let backup = directory.appending(path: "Version 2.ttbackup")
        try BackupFormat.write(
            header: BackupHeader(
                created: BackupFixtures.localDate(2026, 10, 20, 9, 30, 0), appVersion: "1.0", schemaVersion: 2,
                invoiceCount: 1, deviceName: BackupFixtures.deviceName, keys: keys
            ),
            databaseFile: file, to: backup
        )
        // The data of this Mac: none yet.
        let clock = ManualClock(BackupFixtures.localDate(2026, 10, 24, 12, 0, 0))
        let paths = VaultPaths(directory: directory.appending(path: "Data", directoryHint: .isDirectory))
        let vault = Vault(
            paths: paths, device: SoftwareKeyProtector(),
            backups: BackupService(
                backupsDirectory: paths.backups, clock: clock, appVersion: "1.0", deviceName: BackupFixtures.deviceName
            ),
            clock: clock
        )

        let restored = try await vault.restore(from: backup, recoveryCode: code)

        #expect(try await restored.schemaVersion() == 3)
        #expect(try await restored.invoiceCount() == 1)
        #expect(try await restored.clientCount() == 1)
        #expect(try await restored.storedSettingsYears() == [2025, 2026])
        let settings = try await restored.yearSettings(2026)
        #expect(settings.expensePercent == 80)
        #expect(settings.advances.social[2] == 4_759)
        #expect(settings.spouse != nil)
        #expect(try await restored.family(year: 2026).children.map(\.child.id) == [1])
        // The settings of the years have lost the column of the minimum insurance, and the months of the expected
        // invoices start empty.
        let droppedColumn = "SELECT count(*) FROM pragma_table_info('year_settings') WHERE name = 'minimum_mode'"
        #expect(try await restored.integer(droppedColumn) == 0)
        #expect(try await restored.expectedInvoiceMonths(year: 2026).isEmpty)
        // The restored data keeps changes of months from now on.
        try await restored.setExpectedInvoiceMonth(year: 2026, clientID: 1, month: 7, expected: false)
        #expect(try await restored.expectedInvoiceMonths(year: 2026) == [1: [7: false]])
        await restored.close()
    }

    @Test func aBackupKeepsTheExpectedInvoiceMonths() async throws {
        let key = randomKey()
        let (database, directory) = try makeDatabase(key: key)
        defer { removeTemporaryDirectory(directory) }
        let alfaID = try await database.saveClient(SearchFixtures.alfa)
        let bravoID = try await database.saveClient(SearchFixtures.bravo)
        try await database.setExpectedInvoiceMonth(year: 2025, clientID: alfaID, month: 12, expected: true)
        try await database.setExpectedInvoiceMonth(year: 2026, clientID: alfaID, month: 3, expected: false)
        try await database.setExpectedInvoiceMonth(year: 2026, clientID: alfaID, month: 9, expected: true)
        try await database.setExpectedInvoiceMonth(year: 2026, clientID: bravoID, month: 3, expected: true)
        let (keys, _) = try BackupFixtures.keys(for: key)
        let service = BackupService(
            backupsDirectory: directory.appending(path: "Backups", directoryHint: .isDirectory),
            clock: ManualClock(BackupFixtures.localDate(2026, 10, 24, 12, 0, 0)), appVersion: "1.0",
            deviceName: BackupFixtures.deviceName
        )

        let backup = try await service.makeBackup(database: database, key: key, keys: keys)

        let extracted = directory.appending(path: "extracted.sqlite")
        try BackupFormat.extractDatabase(from: backup.url, to: extracted)
        let restored = try Database(fileURL: extracted, key: key)
        #expect(try await restored.expectedInvoiceMonths(year: 2025) == [alfaID: [12: true]])
        #expect(
            try await restored.expectedInvoiceMonths(year: 2026) == [alfaID: [3: false, 9: true], bravoID: [3: true]]
        )
        await restored.close()
    }

    @Test func aBackupKeepsTheFamily() async throws {
        let key = randomKey()
        let (database, directory) = try makeDatabase(key: key)
        defer { removeTemporaryDirectory(directory) }
        let anna = Child(id: nil, name: "Anna", birthDate: civilDate("2019-09-03"))
        try await database.saveChild(
            anna, year: 2025,
            childYear: ChildYear(
                household: MonthRange(from: 1, to: 12), claimant: .otherParent, order: 2,
                ztpp: MonthRange(from: 3, to: 12), studies: nil
            )
        )
        try await database.saveChild(
            Child(id: nil, name: "Tomáš", birthDate: civilDate("2024-04-12")), year: 2026,
            childYear: ChildYear(
                household: nil, claimant: .me, order: 1, ztpp: nil, studies: MonthRange(from: 9, to: 12)
            )
        )
        try await database.saveSpouse(
            SpouseYear(claim: true, months: MonthRange(from: 5, to: 12), ownIncomeKc: 12_000, ztpp: nil), year: 2026
        )
        let families = [try await database.family(year: 2025), try await database.family(year: 2026)]
        let (keys, _) = try BackupFixtures.keys(for: key)
        let service = BackupService(
            backupsDirectory: directory.appending(path: "Backups", directoryHint: .isDirectory),
            clock: ManualClock(BackupFixtures.localDate(2026, 10, 21, 12, 0, 0)), appVersion: "1.0",
            deviceName: BackupFixtures.deviceName
        )

        let backup = try await service.makeBackup(database: database, key: key, keys: keys)

        let extracted = directory.appending(path: "extracted.sqlite")
        try BackupFormat.extractDatabase(from: backup.url, to: extracted)
        let restored = try Database(fileURL: extracted, key: key)
        #expect([try await restored.family(year: 2025), try await restored.family(year: 2026)] == families)
        #expect(try await restored.storedSettingsYears() == [2025, 2026])
        await restored.close()
    }
}
