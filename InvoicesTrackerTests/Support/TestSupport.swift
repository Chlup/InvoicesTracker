import CryptoKit
import Foundation
import Testing
import os
@testable import InvoicesTracker

enum TestSupportError: Error {
    case fixtureNotFound(String)
}

/// Anchor class used to locate the test bundle (the app bundle is `Bundle.main` in a hosted run).
private final class BundleToken {}

/// What raising the limit of open files of the process came to.
enum FileLimitRaise: Equatable {
    /// The limit was as high as wanted, or as high as the hard limit allows to ask.
    case enough

    /// The soft limit was raised to this.
    case raised(to: UInt64)

    /// The limit could not be read, or the system refused the new one, with its error number (0 when it was not read).
    case refused(errorNumber: Int32)
}

/// Raises the soft limit of open files to `target`, or to the hard limit when that is lower, unless it is as high
/// already. `read` gives the soft and the hard limit, or nil when it cannot be read; `write` sets a new soft limit and
/// gives 0, or the error number of the system when it refuses.
func raiseOpenFileLimit(
    to target: UInt64 = 10_240,
    read: () -> (soft: UInt64, hard: UInt64)? = {
        var limit = rlimit()
        guard getrlimit(RLIMIT_NOFILE, &limit) == 0 else { return nil }
        return (UInt64(limit.rlim_cur), UInt64(limit.rlim_max))
    },
    write: (UInt64) -> Int32 = { soft in
        var limit = rlimit()
        guard getrlimit(RLIMIT_NOFILE, &limit) == 0 else { return errno }
        limit.rlim_cur = rlim_t(soft)
        return setrlimit(RLIMIT_NOFILE, &limit) == 0 ? 0 : errno
    }
) -> FileLimitRaise {
    guard let limits = read() else { return .refused(errorNumber: 0) }
    let wanted = min(target, limits.hard)
    guard limits.soft < wanted else { return .enough }
    let refusal = write(wanted)
    return refusal == 0 ? .raised(to: wanted) : .refused(errorNumber: refusal)
}

/// Raises the most files the test process may have open, once. The suite starts thousands of tests together, and each
/// holds the files of its database open until it ends, so the run has nearly as many files open at its peak as the
/// process may (2 560 at the start): a test that opens one more fails with "Too many open files", whatever it tests.
let openFileLimitRaise: FileLimitRaise = raiseOpenFileLimit()

/// Whether a failed raise was told already: it is told once, by the first test that makes a folder, as the tests that
/// fail for want of it fail for a reason that does not name it.
private let failedRaiseTold = OSAllocatedUnfairLock(initialState: false)

/// Removes the folders `TaxesTrackerTests-…` in `directory` that were made more than `age` before `now` and that
/// nothing removed: what a run that crashed left behind, in the temporary folder of the app container, where it stays.
/// Returns their names, sorted. Files, and folders of any other name, are left alone, and so is a folder that cannot be
/// read.
@discardableResult
func removeStaleTemporaryDirectories(
    in directory: URL, olderThan age: TimeInterval = 24 * 60 * 60, now: Date = Date()
) -> [String] {
    let keys: [URLResourceKey] = [.isDirectoryKey, .creationDateKey, .contentModificationDateKey]
    guard
        let entries = try? FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: keys, options: [])
    else {
        return []
    }
    var removed: [String] = []
    for entry in entries where entry.lastPathComponent.hasPrefix("TaxesTrackerTests-") {
        guard let values = try? entry.resourceValues(forKeys: Set(keys)), values.isDirectory == true,
            let made = values.creationDate ?? values.contentModificationDate, now.timeIntervalSince(made) > age
        else {
            continue
        }
        if (try? FileManager.default.removeItem(at: entry)) != nil {
            removed.append(entry.lastPathComponent)
        }
    }
    return removed.sorted()
}

/// Sweeps the temporary folder of the process once, at the first call: the start of the run, for the tests.
private let staleFoldersSwept: Void = {
    removeStaleTemporaryDirectories(in: FileManager.default.temporaryDirectory)
}()

/// Creates a unique, empty folder under the temporary directory. Pair it with `removeTemporaryDirectory(_:)`. The first
/// call of a run raises the limit of open files, which is told with an issue when the system refuses it, and removes
/// the folders that crashed runs left behind. A test of a suite with `.settlesBackups` has the folder removed once more
/// after the backups it started (`TestLeftovers`).
func makeTemporaryDirectory() throws -> URL {
    if case .refused(let errorNumber) = openFileLimitRaise,
        failedRaiseTold.withLock({ told -> Bool in
            let first = !told
            told = true
            return first
        })
    {
        let message =
            "The limit of open files could not be raised (error \(errorNumber)): tests that hold many databases open"
            + " fail with \"Too many open files\" whatever they test."
        Issue.record(Comment(rawValue: message))
    }
    _ = staleFoldersSwept
    let url = FileManager.default.temporaryDirectory
        .appending(path: "TaxesTrackerTests-\(UUID().uuidString)", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    TestLeftovers.current?.add(folder: url)
    return url
}

func removeTemporaryDirectory(_ url: URL) {
    try? FileManager.default.removeItem(at: url)
}

/// A fresh random 256-bit key, for tests that need a database key.
func randomKey() -> SymmetricKey {
    SymmetricKey(size: .bits256)
}

/// A new database in a new temporary directory, opened with `key` (a fresh random one unless given). Returns the
/// database together with that directory, which holds the database file (`database.fileURL`) and its write-ahead log;
/// pair it with `removeTemporaryDirectory(_:)`. To open the file again, close the database and call
/// `Database(fileURL: database.fileURL, key: key)` with the same key.
func makeDatabase(
    searchIndex: SearchIndexKind = .automatic,
    key: SymmetricKey = randomKey()
) throws -> (Database, URL) {
    let directory = try makeTemporaryDirectory()
    do {
        let fileURL = directory.appending(path: "InvoicesTracker.sqlite")
        return (try Database(fileURL: fileURL, key: key, searchIndex: searchIndex), directory)
    } catch {
        removeTemporaryDirectory(directory)
        throw error
    }
}

extension Database {
    /// The first column of the first row of `sql` as a number, for tests that count rows.
    func integer(_ sql: String, _ arguments: [SQLValue] = []) throws -> Int64 {
        try read { connection in
            try connection.query(sql, arguments)[0].int64(0)
        }
    }

    /// The first column of the first row of `sql` as text, for tests that read a pragma such as `quick_check`.
    func text(_ sql: String) throws -> String {
        try read { connection in
            try connection.query(sql)[0].text(0)
        }
    }
}

/// Whether `error` is a violated unique, not-null, check or foreign-key constraint.
func isConstraintViolation(_ error: any Error) -> Bool {
    guard case .constraint? = error as? SQLiteError else { return false }
    return true
}

/// A clock that only moves when the test says so.
final class ManualClock: AppClock {
    private let current: OSAllocatedUnfairLock<Date>

    init(_ date: Date) {
        current = OSAllocatedUnfairLock(initialState: date)
    }

    func now() -> Date {
        current.withLock { $0 }
    }

    func set(_ date: Date) {
        current.withLock { $0 = date }
    }

    func advance(by interval: TimeInterval) {
        current.withLock { $0 += interval }
    }
}

extension Trait where Self == TimeLimitTrait {
    /// The limit of a test that waits for something that the test itself or the app brings about, such as a gate it
    /// opens or a timer that fires: it ends when that happens, however long the run takes to get there, and this limit
    /// only turns a wait that never ends into a failure. In a full run the process is so busy that the actor hops of
    /// such a test take seconds each, so the limit is far above what the whole run takes.
    static var hangGuard: Self {
        .timeLimit(.minutes(5))
    }
}

/// Looks a fixture file up in the test bundle. Resources are copied flat, so names must be unique.
func fixtureURL(_ name: String, _ ext: String) throws -> URL {
    guard let url = Bundle(for: BundleToken.self).url(forResource: name, withExtension: ext) else {
        throw TestSupportError.fixtureNotFound("\(name).\(ext)")
    }
    return url
}

/// Parses an ISO 8601 timestamp such as `"2026-10-16T12:35:00Z"`. Traps on malformed input,
/// because a bad literal in a test is a bug in the test.
func date(_ iso8601: String) -> Date {
    guard let value = ISO8601DateFormatter().date(from: iso8601) else {
        preconditionFailure("Not an ISO 8601 date: \(iso8601)")
    }
    return value
}

/// Parses plain POSIX decimal text such as `"21.84"`. Traps on malformed input, because a bad literal in a test is a
/// bug in the test: `Decimal(string:)` alone would read `"21,84"` as 21 without a word.
func decimal(_ text: String) -> Decimal {
    guard let value = DecimalMath.decimal(text) else {
        preconditionFailure("Not a plain decimal: \(text)")
    }
    return value
}

/// Parses a calendar date written as `"2026-10-17"`. Traps on malformed input, because a bad literal in a test is a
/// bug in the test.
func civilDate(_ iso: String) -> CivilDate {
    guard let value = CivilDate(iso: iso) else {
        preconditionFailure("Not a YYYY-MM-DD date: \(iso)")
    }
    return value
}

/// Parses bytes written as hexadecimal text such as `"00ff1a"`, two digits per byte. Traps on malformed input,
/// because a bad literal in a test is a bug in the test.
func hexData(_ hex: String) -> Data {
    let digits = Array(hex.utf8)
    precondition(digits.count % 2 == 0, "Hex text has two digits per byte: \(hex)")
    var bytes = Data(capacity: digits.count / 2)
    for start in stride(from: 0, to: digits.count, by: 2) {
        guard let high = hexDigitValue(digits[start]), let low = hexDigitValue(digits[start + 1]) else {
            preconditionFailure("Not hex text: \(hex)")
        }
        bytes.append(high << 4 | low)
    }
    return bytes
}

private func hexDigitValue(_ digit: UInt8) -> UInt8? {
    switch digit {
    case UInt8(ascii: "0")...UInt8(ascii: "9"): digit - UInt8(ascii: "0")
    case UInt8(ascii: "a")...UInt8(ascii: "f"): digit - UInt8(ascii: "a") + 10
    case UInt8(ascii: "A")...UInt8(ascii: "F"): digit - UInt8(ascii: "A") + 10
    default: nil
    }
}
