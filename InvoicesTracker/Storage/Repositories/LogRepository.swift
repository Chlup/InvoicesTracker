import Foundation

/// The log of the requests to public servers and the log of the imports.
extension Database {
    /// Adds an entry at the end of the fetch log.
    func appendFetchLog(_ entry: FetchLogEntry) throws {
        try write { connection in
            try connection.run(
                "INSERT INTO fetch_log(at, kind, target, ok, message) VALUES (?, ?, ?, ?, ?)",
                [.instant(entry.at), .choice(entry.kind), .text(entry.target), .flag(entry.ok), .text(entry.message)]
            )
        }
    }

    /// The newest `limit` entries of the fetch log, the newest first. The order is the order they were appended in,
    /// whatever their times are. Empty for a `limit` of zero or less.
    func recentFetchLog(limit: Int) throws -> [FetchLogEntry] {
        guard limit > 0 else { return [] }
        return try read { connection in
            try connection.query(
                "SELECT at, kind, target, ok, message FROM fetch_log ORDER BY id DESC LIMIT ?", [.int(limit)]
            ).map { try FetchLogEntry(row: $0) }
        }
    }

    /// Keeps the summary of an import, as the JSON bytes it was made into, with the time of the import. Every
    /// import is kept.
    func saveImportLog(_ json: Data, at date: Date) throws {
        try write { connection in
            try Database.insertImportLog(json, at: date, in: connection)
        }
    }

    /// The same inside a `write` that is open already, which takes the connection of it. An import keeps its summary in
    /// the transaction that made it.
    static func insertImportLog(_ json: Data, at date: Date, in connection: SQLiteConnection) throws {
        try connection.run("INSERT INTO import_log(at, json) VALUES (?, ?)", [.instant(date), .blob(json)])
    }

    /// The summary of the latest import, or nil if there has been none.
    func lastImportLog() throws -> (at: Date, json: Data)? {
        try read { connection in
            let rows = try connection.query("SELECT at, json FROM import_log ORDER BY id DESC LIMIT 1")
            return rows.first.map { (at: $0.instant(0), json: $0.blob(1)) }
        }
    }
}

private nonisolated extension FetchLogEntry {
    /// A row of `SELECT at, kind, target, ok, message`.
    init(row: SQLRow) throws {
        self.init(
            at: row.instant(0), kind: try row.choice(1), target: row.text(2), ok: row.bool(3), message: row.text(4)
        )
    }
}
