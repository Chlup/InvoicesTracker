import Foundation

/// What can go wrong with a backup. No case carries a path, a key or a code.
nonisolated enum BackupError: Error, Equatable {
    /// The file is not a backup this version of the app can read: it does not start with the magic, is cut short, has
    /// a header that cannot be read, or was written in a format this version does not know.
    case notABackup

    /// The backup holds a database of a newer schema than this version of the app knows, the number being the schema
    /// version of the backup. Restoring it could misread or damage the data. Nothing in the backup files throws this:
    /// whoever restores a backup compares `BackupHeader.schemaVersion` with `Schema.latestVersion`.
    case newerSchema(Int)

    /// The folder outside the Mac cannot be reached: the bookmark does not resolve (the folder was deleted, the disk
    /// or the network share is not connected), or the system refuses access to it.
    case folderUnavailable
}

/// The header of a backup file: what made the backup and when, what the database holds, and the key slots the data key
/// of the database is wrapped in. The slots are as they were when the backup was made, so a backup is opened with the
/// recovery code that was valid then.
nonisolated struct BackupHeader: Codable, Hashable, Sendable {
    /// The layout of the file this version of the app reads and writes.
    static let currentFormatVersion = 1

    var formatVersion = BackupHeader.currentFormatVersion

    /// The moment the backup was made, to the second: it is coded as an ISO 8601 timestamp without a fraction.
    var created: Date
    var appVersion: String

    /// The `user_version` of the database in the backup. A database of an older schema is migrated once it is
    /// restored.
    var schemaVersion: Int

    /// The number of invoices in the database, drafts included, for the list of backups to show.
    var invoiceCount: Int

    /// The number of clients in the database, for the file card of a restore to show. Nil in the header of a backup
    /// made before it was counted, which is left out of the JSON and read as nil.
    var clientCount: Int?

    /// The first and the last year with data, for the file card of a restore to show (`Database.yearsWithData()`). Nil
    /// when the database has no year yet, and in the header of a backup made before the years were named.
    var years: ClosedRange<Int>?

    /// The name of the Mac the backup was made on.
    var deviceName: String
    var keys: KeysFile
}

nonisolated extension BackupHeader {
    /// Reads a header written by this or an earlier version of the app. What the header tells only for the file card of
    /// a restore, the clients and the years, never makes it unreadable: a field that is missing, or that cannot be
    /// read, is nil, so that a backup is never refused for what it only describes.
    init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        formatVersion = try values.decode(Int.self, forKey: .formatVersion)
        created = try values.decode(Date.self, forKey: .created)
        appVersion = try values.decode(String.self, forKey: .appVersion)
        schemaVersion = try values.decode(Int.self, forKey: .schemaVersion)
        invoiceCount = try values.decode(Int.self, forKey: .invoiceCount)
        clientCount = try? values.decodeIfPresent(Int.self, forKey: .clientCount)
        years = try? values.decodeIfPresent(ClosedRange<Int>.self, forKey: .years)
        deviceName = try values.decode(String.self, forKey: .deviceName)
        keys = try values.decode(KeysFile.self, forKey: .keys)
    }
}

/// The backup file `.ttbackup`: the magic `TTBACKUP1` (9 bytes of ASCII), the length of the header as a `UInt32` in big
/// endian, the header as JSON (UTF-8, sorted keys), and the bytes of the SQLCipher database, to the end of the file.
///
/// The database is copied in chunks and the header is read without it, so no call holds a database in memory.
nonisolated enum BackupFormat {
    static let magic = Data("TTBACKUP1".utf8)

    /// The longest header the format allows: 1 MiB. A length above it is not a length written by a backup, and `write`
    /// refuses a header whose JSON is longer.
    static let maximumHeaderLength = 1 << 20

    private static let lengthByteCount = 4
    private static let chunkByteCount = 1 << 20

    /// Writes the backup file `url` from `header` and the database file `databaseFile` (the snapshot, which is left as
    /// it is). The file is written beside `url` under another name and moved into place at the end, so a reader finds
    /// the file that was there or the whole new one. When this throws nothing is changed.
    ///
    /// A header whose JSON is longer than `maximumHeaderLength` is refused with `BackupError.notABackup` before
    /// anything is read or written, which is what `readHeader` would say of the file: this never writes a file that
    /// `readHeader` rejects.
    static func write(header: BackupHeader, databaseFile: URL, to url: URL) throws {
        let headerData = try encode(header)
        guard headerData.count <= maximumHeaderLength else {
            throw BackupError.notABackup
        }
        let input = try FileHandle(forReadingFrom: databaseFile)
        defer { try? input.close() }
        let partial = url.deletingLastPathComponent()
            .appending(path: ".\(url.lastPathComponent).\(UUID().uuidString).partial")
        try Data().write(to: partial)
        do {
            try fill(partial) { output in
                try output.write(contentsOf: magic)
                try output.write(contentsOf: lengthPrefix(of: headerData))
                try output.write(contentsOf: headerData)
                try copy(from: input, to: output)
            }
            try moveIntoPlace(partial, at: url)
        } catch {
            try? FileManager.default.removeItem(at: partial)
            throw error
        }
    }

    /// The header of the backup file at `url`, read without the database.
    ///
    /// Throws `BackupError.notABackup` when the file does not start with the magic, is cut short (the header ends
    /// beyond the file, or no database follows it), has a header above 1 MiB or one that is not a header of this format
    /// version. A file that cannot be read at all throws the error of the file system.
    static func readHeader(from url: URL) throws -> BackupHeader {
        let file = try FileHandle(forReadingFrom: url)
        defer { try? file.close() }
        return try readPreamble(of: file).header
    }

    /// Writes the database of the backup file `url` to `databaseFile`, which is created or emptied first. When this
    /// throws, that file is removed. Throws what `readHeader` throws, before `databaseFile` is touched.
    static func extractDatabase(from url: URL, to databaseFile: URL) throws {
        let input = try FileHandle(forReadingFrom: url)
        defer { try? input.close() }
        _ = try readPreamble(of: input)
        try Data().write(to: databaseFile)
        do {
            try fill(databaseFile) { output in
                try copy(from: input, to: output)
            }
        } catch {
            try? FileManager.default.removeItem(at: databaseFile)
            throw error
        }
    }
}

// MARK: - Reading

private nonisolated extension BackupFormat {
    /// Reads and checks the magic, the length and the header, and leaves `file` at the first byte of the database.
    static func readPreamble(of file: FileHandle) throws -> (header: BackupHeader, databaseOffset: UInt64) {
        let fileSize = try file.seekToEnd()
        try file.seek(toOffset: 0)
        let prefixLength = magic.count + lengthByteCount
        guard let prefix = try file.read(upToCount: prefixLength),
            prefix.count == prefixLength,
            prefix.prefix(magic.count) == magic
        else {
            throw BackupError.notABackup
        }
        let length = prefix.suffix(lengthByteCount).reduce(UInt32(0)) { $0 << 8 | UInt32($1) }
        let databaseOffset = UInt64(prefixLength) + UInt64(length)
        // The header ends inside the file and at least one byte of the database follows it. The length is checked
        // before anything is read, so a damaged one cannot ask for more memory than the format allows.
        guard length > 0, Int(length) <= maximumHeaderLength, databaseOffset < fileSize,
            let json = try file.read(upToCount: Int(length)),
            json.count == Int(length)
        else {
            throw BackupError.notABackup
        }
        let header: BackupHeader
        do {
            header = try decoder().decode(BackupHeader.self, from: json)
        } catch {
            throw BackupError.notABackup
        }
        guard header.formatVersion == BackupHeader.currentFormatVersion else {
            throw BackupError.notABackup
        }
        return (header, databaseOffset)
    }

    static func encode(_ header: BackupHeader) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(header)
    }

    static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}

// MARK: - Writing

private nonisolated extension BackupFormat {
    /// The length of the header as the four bytes the file holds: big endian.
    static func lengthPrefix(of header: Data) -> Data {
        withUnsafeBytes(of: UInt32(header.count).bigEndian) { Data($0) }
    }

    /// Copies what is left of `input` to `output` in chunks.
    static func copy(from input: FileHandle, to output: FileHandle) throws {
        while let chunk = try input.read(upToCount: chunkByteCount), !chunk.isEmpty {
            try output.write(contentsOf: chunk)
        }
    }

    /// Opens the existing file `url` for writing, lets `body` write it, and finishes it: flushed to the disk and
    /// closed, so a failure of either is reported. When `body` or the finishing throws, the file is closed and left as
    /// it is.
    static func fill(_ url: URL, _ body: (FileHandle) throws -> Void) throws {
        let output = try FileHandle(forWritingTo: url)
        do {
            try body(output)
            try output.synchronize()
            try output.close()
        } catch {
            try? output.close()
            throw error
        }
    }

    /// Renames `partial` to `url`, which replaces a file that is there in one step.
    static func moveIntoPlace(_ partial: URL, at url: URL) throws {
        guard rename(partial.path(percentEncoded: false), url.path(percentEncoded: false)) == 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
    }
}
