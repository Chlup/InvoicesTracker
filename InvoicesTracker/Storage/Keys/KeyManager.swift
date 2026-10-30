import CryptoKit
import Foundation
import os
import Security

/// The data key and its slots: a new data key and recovery code, unlocking the data key with this Mac's device key
/// or with a recovery code, and reading and writing the keys file.
nonisolated enum KeyManager {
    /// A data key has 256 bits: the raw key that SQLCipher takes.
    static let dataKeyByteCount = 32

    /// Every recovery slot salts its key derivation with 128 random bits of its own.
    private static let saltByteCount = 16

    /// A new random data key.
    static func newDataKey() -> SymmetricKey {
        SymmetricKey(data: randomBytes(count: dataKeyByteCount))
    }

    /// A new recovery code, and the slot that holds `dek` wrapped with it. The code is shown once and never stored.
    static func makeRecoverySlot(
        for dek: SymmetricKey,
        number: Int,
        created: CivilDate
    ) throws -> (slot: RecoverySlot, code: String) {
        let secret = RecoveryCode.randomSecret()
        let salt = randomBytes(count: saltByteCount)
        let slot = RecoverySlot(
            number: number,
            created: created,
            salt: salt,
            wrappedKey: try RecoveryCode.wrap(dek, secret: secret, salt: salt)
        )
        return (slot, RecoveryCode.display(secret))
    }

    /// The data key in the device slot of `keys`, opened by `device` (`reason` is shown if it asks for Touch ID or the
    /// password). Throws `KeyError.noDeviceSlot` when there is no device slot, and what `device.open` throws.
    static func unlock(_ keys: KeysFile, device: any DeviceKeyProtector, reason: String) async throws -> SymmetricKey {
        guard let slot = keys.deviceSlot else {
            throw KeyError.noDeviceSlot
        }
        return try await device.open(slot, reason: reason)
    }

    /// The data key in the recovery slot that the typed `recoveryCode` opens, and that slot; every slot is tried.
    /// Throws `KeyError.malformedRecoveryCode` unless the code normalizes to 32 characters, and
    /// `KeyError.wrongRecoveryCode` when it opens no slot.
    static func unlock(_ keys: KeysFile, recoveryCode: String) throws -> (dek: SymmetricKey, slot: RecoverySlot) {
        guard let secret = RecoveryCode.secret(from: recoveryCode) else {
            throw KeyError.malformedRecoveryCode
        }
        for slot in keys.recoverySlots {
            do {
                return (try RecoveryCode.unwrap(slot.wrappedKey, secret: secret, salt: slot.salt), slot)
            } catch KeyError.wrongRecoveryCode {
                continue
            }
        }
        throw KeyError.wrongRecoveryCode
    }

    /// The keys file at `url`, or nil when there is no file. Throws `KeyError.keysFileDamaged` when the file is not a
    /// keys file this version of the app can read, and the error of reading it when it cannot be read.
    static func load(_ url: URL) throws -> KeysFile? {
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch CocoaError.fileReadNoSuchFile {
            return nil
        }
        let keys: KeysFile
        do {
            keys = try JSONDecoder().decode(KeysFile.self, from: data)
        } catch {
            throw KeyError.keysFileDamaged
        }
        guard keys.formatVersion == KeysFile.currentFormatVersion else {
            throw KeyError.keysFileDamaged
        }
        return keys
    }

    /// Writes `keys` to `url` as pretty-printed JSON with sorted keys, and returns once the new file is on the drive
    /// itself. The file is replaced in one step: a reader finds the old keys or the new ones, never a mix or an empty
    /// file, also after a crash of the whole system (a panic, a power failure).
    ///
    /// The new keys go to a hidden file beside `url`, which is flushed to the drive with `F_FULLFSYNC` (that empties
    /// the drive's own cache too) and then renamed over `url`; then the folder is flushed, so that the rename is on the
    /// drive before anything written after this. A change of the data key relies on that order: the keys file that
    /// holds both keys is on the drive before the database gets the new one. When this throws, `url` is as it was.
    ///
    /// Once the rename is done the new keys are in place, so a folder that cannot be flushed after it is logged (by
    /// the domain and code of the error) and does not make this throw; the rename then reaches the drive whenever the
    /// system writes the folder.
    static func save(_ keys: KeysFile, to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(keys)
        let folder = url.deletingLastPathComponent()
        let temporary = folder.appending(path: ".\(url.lastPathComponent).\(UUID().uuidString).tmp")
        do {
            try data.write(to: temporary, options: .withoutOverwriting)
            try flushToDrive(temporary)
            guard rename(temporary.path(percentEncoded: false), url.path(percentEncoded: false)) == 0 else {
                throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
            }
        } catch {
            try? FileManager.default.removeItem(at: temporary)
            throw error
        }
        do {
            try flushToDrive(folder)
        } catch {
            let error = error as NSError
            logger.error(
                "Flushing the folder of the keys file failed: \(error.domain, privacy: .public) \(error.code)"
            )
        }
    }

    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "InvoicesTracker", category: "Keys")

    /// Flushes the file or folder at `url` to the drive: with `F_FULLFSYNC`, which also empties the drive's cache, or
    /// with `fsync` on a file system that does not offer it.
    private static func flushToDrive(_ url: URL) throws {
        let descriptor = open(url.path(percentEncoded: false), O_RDONLY)
        guard descriptor >= 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
        defer { close(descriptor) }
        guard fcntl(descriptor, F_FULLFSYNC) == 0 || fsync(descriptor) == 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
    }

    /// `count` bytes from the system's cryptographically secure random number generator. Traps when the generator
    /// fails: no key can be made without it, and there is nothing sensible to do instead.
    static func randomBytes(count: Int) -> Data {
        var bytes = [UInt8](repeating: 0, count: count)
        let status = SecRandomCopyBytes(kSecRandomDefault, count, &bytes)
        guard status == errSecSuccess else {
            preconditionFailure("The system random number generator failed with status \(status).")
        }
        return Data(bytes)
    }
}
