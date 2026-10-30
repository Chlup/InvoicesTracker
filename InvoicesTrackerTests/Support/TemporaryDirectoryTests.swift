import Foundation
import Testing

/// What the tests do about the process they run in and the folders they leave: the limit of open files is raised once
/// and a raise that fails is told, and the folders of runs that crashed, which nothing removed, are swept away at the
/// start of a run.
struct TemporaryDirectoryTests {
    // MARK: The limit of open files

    /// A system whose soft limit is `soft` and hard limit `hard`, which takes a new soft limit or refuses it with
    /// `refusal`, as the error number of the system; the soft limits it was asked to set are in `asked`.
    private final class FakeSystem: @unchecked Sendable {
        var soft: UInt64
        let hard: UInt64
        let refusal: Int32?
        private(set) var asked: [UInt64] = []

        init(soft: UInt64, hard: UInt64, refusal: Int32? = nil) {
            self.soft = soft
            self.hard = hard
            self.refusal = refusal
        }

        func raise(to target: UInt64 = 10_240) -> FileLimitRaise {
            raiseOpenFileLimit(
                to: target, read: { (soft: self.soft, hard: self.hard) },
                write: { newSoft in
                    self.asked.append(newSoft)
                    if let refusal = self.refusal {
                        return refusal
                    }
                    self.soft = newSoft
                    return 0
                })
        }
    }

    @Test func aLimitThatIsHighEnoughIsLeftAlone() {
        let system = FakeSystem(soft: 10_240, hard: 20_000)

        #expect(system.raise() == .enough)
        #expect(system.asked.isEmpty)
    }

    @Test func aLowLimitIsRaisedToTheTarget() {
        let system = FakeSystem(soft: 2_560, hard: 1_000_000)

        #expect(system.raise() == .raised(to: 10_240))
        #expect(system.asked == [10_240])
    }

    @Test func theLimitIsNeverRaisedAboveTheHardLimit() {
        let system = FakeSystem(soft: 256, hard: 4_096)

        #expect(system.raise() == .raised(to: 4_096))
        #expect(system.asked == [4_096])
    }

    @Test func aRaiseThatTheSystemRefusesIsReportedWithItsErrorNumber() {
        let system = FakeSystem(soft: 2_560, hard: 1_000_000, refusal: EPERM)

        #expect(system.raise() == .refused(errorNumber: EPERM))
    }

    @Test func aLimitThatCannotBeReadIsReportedAsRefused() {
        let result = raiseOpenFileLimit(to: 10_240, read: { nil }, write: { _ in 0 })

        #expect(result == .refused(errorNumber: 0))
    }

    // MARK: Folders of earlier runs

    /// Makes a folder `name` in `directory` that was made `age` seconds before `now`.
    private func folder(_ name: String, madeAgo age: TimeInterval, now: Date, in directory: URL) throws {
        let url = directory.appending(path: name, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        try FileManager.default.setAttributes(
            [.creationDate: now.addingTimeInterval(-age), .modificationDate: now.addingTimeInterval(-age)],
            ofItemAtPath: url.path(percentEncoded: false))
    }

    @Test func foldersOfEarlierRunsOlderThanADayAreRemovedAndNothingElse() throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let now = Date()
        let hour: TimeInterval = 3_600
        try folder("TaxesTrackerTests-two-days", madeAgo: 48 * hour, now: now, in: directory)
        try folder("TaxesTrackerTests-a-day-and-an-hour", madeAgo: 25 * hour, now: now, in: directory)
        try folder("TaxesTrackerTests-23-hours", madeAgo: 23 * hour, now: now, in: directory)
        try folder("TaxesTrackerTests-just-now", madeAgo: 5, now: now, in: directory)
        try folder("SomethingElse-two-days", madeAgo: 48 * hour, now: now, in: directory)
        // A file that has the name of a folder of the tests is not one.
        let file = directory.appending(path: "TaxesTrackerTests-a-file")
        try Data("x".utf8).write(to: file)
        try FileManager.default.setAttributes(
            [.creationDate: now.addingTimeInterval(-48 * hour)], ofItemAtPath: file.path(percentEncoded: false))

        let removed = removeStaleTemporaryDirectories(in: directory, now: now)

        #expect(removed == ["TaxesTrackerTests-a-day-and-an-hour", "TaxesTrackerTests-two-days"])
        let left = try FileManager.default.contentsOfDirectory(atPath: directory.path(percentEncoded: false)).sorted()
        #expect(
            left == [
                "SomethingElse-two-days", "TaxesTrackerTests-23-hours", "TaxesTrackerTests-a-file",
                "TaxesTrackerTests-just-now",
            ])
    }

    @Test func aFolderThatIsRemovedWithItsContents() throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let now = Date()
        try folder("TaxesTrackerTests-stale", madeAgo: 48 * 3_600, now: now, in: directory)
        let inside = directory.appending(path: "TaxesTrackerTests-stale/InvoicesTracker.sqlite")
        try Data("database".utf8).write(to: inside)

        let removed = removeStaleTemporaryDirectories(in: directory, now: now)

        #expect(removed == ["TaxesTrackerTests-stale"])
        #expect(!FileManager.default.fileExists(atPath: inside.path(percentEncoded: false)))
    }

    @Test func aFolderThatDoesNotExistHasNothingToSweep() throws {
        let missing = FileManager.default.temporaryDirectory.appending(path: "TaxesTrackerTests-missing-\(UUID())")

        #expect(removeStaleTemporaryDirectories(in: missing).isEmpty)
    }
}
