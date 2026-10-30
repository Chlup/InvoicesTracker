import Foundation

/// What the card after unlocking with the recovery code or restoring a backup tells: what was done, and which recovery
/// code stays valid. The wording is `WelcomeTexts.doneTitle(_:)` and `WelcomeTexts.doneText(_:touchID:)`.
nonisolated struct UnlockCompletion: Equatable, Sendable {
    enum Kind: Equatable, Sendable {
        /// The data that this Mac's device key could not open were opened with the recovery code, and this Mac knows
        /// them from now on.
        case unlocked

        /// A backup was restored: the day it was made, and how many invoices and clients it holds (the clients are nil
        /// for a backup that did not count them).
        case restored(created: CivilDate, invoiceCount: Int, clientCount: Int?)
    }

    var kind: Kind

    /// The label of the recovery code that opens the data now, such as "kód č. 1 z 17. 10. 2026", which stays valid.
    /// Nil when there is none to name.
    var codeLabel: String?

    /// The card after restoring the backup of `header`, whose day is the day in `timeZone`, the time zone of the Mac.
    static func restored(from header: BackupHeader, codeLabel: String?, in timeZone: TimeZone) -> UnlockCompletion {
        UnlockCompletion(
            kind: .restored(
                created: CivilDate.today(now: header.created, timeZone: timeZone), invoiceCount: header.invoiceCount,
                clientCount: header.clientCount),
            codeLabel: codeLabel)
    }
}

/// A backup file that the person has chosen, as the restore shows it before asking for anything.
nonisolated struct InspectedBackup: Equatable, Sendable {
    let url: URL
    let header: BackupHeader

    /// Whether this Mac opens the backup itself, so that no recovery code is asked for (`Vault.canOpenWithDevice(_:)`).
    let opensWithThisMac: Bool
}

extension AppModel {
    /// Runs `body` while the app has access to the file at `url` that the person chose in a panel or dropped on the
    /// window, as the sandbox asks of such a file. A file that needs no access (the tests', say) is used as it is.
    static func withSecurityScopedAccess<T>(to url: URL, _ body: () async throws -> T) async rethrows -> T {
        let isScoped = url.startAccessingSecurityScopedResource()
        defer {
            if isScoped {
                url.stopAccessingSecurityScopedResource()
            }
        }
        return try await body()
    }

    /// Looks at the backup file at `url`, which the person chose in the panel or dropped on the window: its header, and
    /// whether this Mac opens it without a recovery code. Throws `BackupError.notABackup` for a file that is not a
    /// backup this version of the app reads, `BackupError.newerSchema` for a backup of newer data, and the error of the
    /// file system for a file that cannot be read. Nothing is changed, and the person is asked for nothing.
    func inspectBackup(at url: URL) async throws -> InspectedBackup {
        try await Self.withSecurityScopedAccess(to: url) {
            let header = try vault.inspectBackup(url)
            return InspectedBackup(url: url, header: header, opensWithThisMac: await vault.canOpenWithDevice(header))
        }
    }
}
