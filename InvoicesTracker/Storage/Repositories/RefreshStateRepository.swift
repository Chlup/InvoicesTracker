import Foundation

/// The key in `app_settings` under which `RefreshState` is kept, as JSON. It is a row of its own, so the refresh never
/// writes over a change of `AppSettings` made at the same time.
private nonisolated let refreshStateKey = "refresh_state"

/// The state of the refresh that keeps the rates current.
extension Database {
    /// The stored state, or nil when none has been saved yet.
    /// - Throws: `DecodingError` when the stored JSON is not a state, and the errors of the database.
    func refreshState() throws -> RefreshState? {
        try read { connection in
            try Self.storedRefreshState(in: connection)
        }
    }

    /// Saves `s`, replacing the stored state.
    func saveRefreshState(_ s: RefreshState) throws {
        try write { connection in
            try Self.store(s, in: connection)
        }
    }

    /// Makes the stored state forget that the search for the uniform rate of `year` gave up
    /// (`RefreshState.gaveUpUniform`), in one transaction, so that a run that reads it looks for the rate again when it
    /// is due. Nothing is written when no state is stored or when it has not given up on the year.
    /// - Throws: `DecodingError` when the stored JSON is not a state, and the errors of the database.
    func forgetGivingUpUniformSearch(year: Int) throws {
        try write { connection in
            guard var state = try Self.storedRefreshState(in: connection), state.gaveUpUniform.contains(year) else {
                return
            }
            state.gaveUpUniform.remove(year)
            try Self.store(state, in: connection)
        }
    }

    private nonisolated static func storedRefreshState(in connection: SQLiteConnection) throws -> RefreshState? {
        let stored = try connection.scalar("SELECT value FROM app_settings WHERE key = ?", [.text(refreshStateKey)])
        guard case .text(let json)? = stored else { return nil }
        return try JSONDecoder().decode(RefreshState.self, from: Data(json.utf8))
    }

    private nonisolated static func store(_ state: RefreshState, in connection: SQLiteConnection) throws {
        let json = String(decoding: try JSONEncoder().encode(state), as: UTF8.self)
        try connection.run(
            """
            INSERT INTO app_settings(key, value) VALUES (?, ?)
            ON CONFLICT(key) DO UPDATE SET value = excluded.value
            """,
            [.text(refreshStateKey), .text(json)]
        )
    }
}
