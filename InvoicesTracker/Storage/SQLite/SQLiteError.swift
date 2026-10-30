/// What can go wrong when talking to the database. The messages come from SQLite: they name tables,
/// columns and SQL fragments, but not stored values.
nonisolated enum SQLiteError: Error, Equatable {
    /// The file could not be opened, or the connection has been closed.
    case open(String)
    /// The SQL did not compile or does not match its arguments. The SQL text is part of the error, so values
    /// belong in bound arguments, not in the text.
    case prepare(String, sql: String)
    /// A statement failed while running.
    case step(String)
    /// A unique, not-null, check or foreign-key constraint was violated.
    case constraint(String)
    /// The file does not decrypt with this key (or is not a database at all).
    case wrongKey
    /// The linked library has no encryption (`PRAGMA cipher_version` is empty). Refusing to continue is
    /// what keeps the app from writing plaintext through a mistaken link against the system SQLite.
    case notSQLCipher
}
