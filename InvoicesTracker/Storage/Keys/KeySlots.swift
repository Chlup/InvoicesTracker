import Foundation

/// The data key wrapped with the key of one recovery code.
nonisolated struct RecoverySlot: Codable, Hashable, Sendable {
    /// The sequence number of the code: 1 for the first code, 2 for the code that replaced it, and so on.
    var number: Int

    /// The day the code was made.
    var created: CivilDate

    /// The random salt of the key derivation, 16 bytes.
    var salt: Data

    /// The data key wrapped with AES Key Wrap (RFC 3394).
    var wrappedKey: Data

    /// The name the code is shown and asked for by, such as "kód č. 2 z 17. 10. 2026": its number and date, nothing
    /// derived from the secret.
    var label: String {
        "kód č. \(number) z \(CzechFormat.date(created))"
    }
}

/// The data key sealed to a device key of this Mac, which alone can open it.
nonisolated struct DeviceSlot: Codable, Hashable, Sendable {
    /// The kind of device key: `"secure-enclave"`, or `"software"` in tests. It is the `name` of the
    /// `DeviceKeyProtector` that sealed the slot.
    var protector: String

    /// The device key as the protector keeps it. For the Secure Enclave it is an opaque blob that only this Mac's
    /// Secure Enclave can use.
    var keyBlob: Data

    /// The HPKE encapsulated key: the sender's ephemeral public key.
    var encapsulatedKey: Data

    /// The data key sealed with HPKE.
    var ciphertext: Data

    /// Whether opening the slot needs Touch ID or the Mac's password.
    var userPresence: Bool
}

/// The keys file `InvoicesTracker.keys`: the data key in key slots. Nothing in it opens the data without this Mac's
/// Secure Enclave or a recovery code.
///
/// While the data key is being replaced (a new recovery code, a restore), the file holds the slots of two keys: its
/// own slots hold the new key and `previous` the old one. The database is encrypted with one of them at every moment,
/// so whenever the app is cut off, a slot on disk opens it; opening the database tells which key is in force.
nonisolated struct KeysFile: Codable, Hashable, Sendable {
    /// The layout of the file this version of the app reads and writes.
    static let currentFormatVersion = 1

    var formatVersion = KeysFile.currentFormatVersion
    var deviceSlot: DeviceSlot?
    var recoverySlots: [RecoverySlot]

    /// The slots of the data key that is being replaced, while a change of the key is under way; nil otherwise. The
    /// file leaves the field out when it is nil, so a file without a change under way reads and writes as it always
    /// has.
    var previous: PreviousKeySlots?

    /// The slot of the newest recovery code, which has the highest number. Only the file's own slots count.
    var newestRecoverySlot: RecoverySlot? {
        recoverySlots.max { $0.number < $1.number }
    }
}

/// The slots of the data key that a change of the key is replacing, which the keys file keeps until the change is
/// finished.
nonisolated struct PreviousKeySlots: Codable, Hashable, Sendable {
    var deviceSlot: DeviceSlot?
    var recoverySlots: [RecoverySlot]
}

nonisolated extension KeysFile {
    /// The slots of each data key in the file, each set as a keys file of its own: while a change is under way the
    /// slots of the key being replaced come first, then the file's own; otherwise the file's own alone.
    var slotSets: [KeysFile] {
        let own = KeysFile(deviceSlot: deviceSlot, recoverySlots: recoverySlots)
        guard let previous else {
            return [own]
        }
        return [KeysFile(deviceSlot: previous.deviceSlot, recoverySlots: previous.recoverySlots), own]
    }

    /// The keys file of a change under way: these slots, which hold the new data key, and those of `old` as the slots
    /// of the key being replaced.
    func replacing(_ old: KeysFile) -> KeysFile {
        var file = self
        file.previous = PreviousKeySlots(deviceSlot: old.deviceSlot, recoverySlots: old.recoverySlots)
        return file
    }
}
