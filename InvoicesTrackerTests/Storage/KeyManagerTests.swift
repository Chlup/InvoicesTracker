import CryptoKit
import Foundation
import LocalAuthentication
import Security
import Testing
@testable import InvoicesTracker

/// The data key's slots: sealing it to a device key, unlocking with the device or with the recovery code, and the
/// keys file. A software key protector stands in for the Secure Enclave.
struct KeyManagerTests {
    private let reason = "Odemknout data"

    // MARK: Device key protectors

    @Test func theSoftwareProtectorOpensWhatItSealed() async throws {
        let protector = SoftwareKeyProtector()
        let dek = randomKey()

        let slot = try protector.seal(dek, userPresence: true)

        #expect(slot.protector == "software")
        #expect(slot.userPresence)
        #expect(try await protector.open(slot, reason: reason) == dek)
    }

    /// The device slot is HPKE (RFC 9180) in base mode with DHKEM(P-256, HKDF-SHA256), HKDF-SHA256 and AES-256-GCM,
    /// the info "TaxesTracker data key v1" and the 32 bytes of the data key as the plaintext. Opening a slot with
    /// CryptoKit's HPKE directly pins that layout.
    @Test func aDeviceSlotIsTheDataKeySealedWithHPKEInBaseMode() throws {
        let dek = randomKey()
        let slot = try SoftwareKeyProtector().seal(dek, userPresence: false)

        var recipient = try HPKE.Recipient(
            privateKey: try P256.KeyAgreement.PrivateKey(rawRepresentation: slot.keyBlob),
            ciphersuite: .P256_SHA256_AES_GCM_256,
            info: Data("TaxesTracker data key v1".utf8),
            encapsulatedKey: slot.encapsulatedKey
        )

        #expect(SymmetricKey(data: try recipient.open(slot.ciphertext)) == dek)
    }

    /// A slot sealed once with the info "TaxesTracker data key v1" still opens. Its bytes were made with CryptoKit's
    /// HPKE and are kept as they are, so a change of the info — also when the app is renamed — fails here: it would
    /// make every device slot ever sealed unusable.
    @Test func aDeviceSlotSealedWithTheFixedInfoStillOpens() async throws {
        let slot = DeviceSlot(
            protector: "software",
            keyBlob: hexData("0102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f20"),
            encapsulatedKey: hexData(
                "04e1514f57196e6f9bafc56b0f9b7429db305aad8083c5bbba58f3395b4d1c46fe"
                    + "73b08d61eb67552f1efc0c71a3c98f756e28afe750b2be0781d4e1fd27f3b0f7"),
            ciphertext: hexData(
                "256bdee65cd15902e9cf1c42d73744dff66746a989fde95b"
                    + "8052c790ac0345c87b7d76bf2f3010f51d809cc21512c5d7"),
            userPresence: false
        )

        #expect(try await SoftwareKeyProtector().open(slot, reason: reason) == SymmetricKey(data: Data(0x40..<0x60)))
    }

    @Test func aFlippedCiphertextByteMakesTheDeviceKeyUnusable() async throws {
        let protector = SoftwareKeyProtector()
        var slot = try protector.seal(randomKey(), userPresence: false)
        slot.ciphertext[slot.ciphertext.startIndex] ^= 0x01

        await #expect(throws: KeyError.deviceKeyUnusable) {
            _ = try await protector.open(slot, reason: reason)
        }
    }

    @Test func aSlotOfAnotherKindOfProtectorIsUnusable() async throws {
        let protector = SoftwareKeyProtector()
        var slot = try protector.seal(randomKey(), userPresence: false)
        slot.protector = "secure-enclave"

        await #expect(throws: KeyError.deviceKeyUnusable) {
            _ = try await protector.open(slot, reason: reason)
        }
    }

    @Test func aSlotThatDoesNotHoldA256BitKeyIsUnusable() async throws {
        let privateKey = P256.KeyAgreement.PrivateKey()
        var sender = try HPKE.Sender(
            recipientKey: privateKey.publicKey,
            ciphersuite: .P256_SHA256_AES_GCM_256,
            info: Data("TaxesTracker data key v1".utf8)
        )
        let ciphertext = try sender.seal(Data(repeating: 0x5A, count: 16))
        let slot = DeviceSlot(
            protector: "software",
            keyBlob: privateKey.rawRepresentation,
            encapsulatedKey: sender.encapsulatedKey,
            ciphertext: ciphertext,
            userPresence: false
        )

        await #expect(throws: KeyError.deviceKeyUnusable) {
            _ = try await SoftwareKeyProtector().open(slot, reason: reason)
        }
    }

    /// Whether a protector can open a slot is told without opening it, so without a prompt: a slot of its own kind with
    /// a key it can load.
    @Test func theSoftwareProtectorTellsWithoutOpeningWhetherItCanOpenASlot() throws {
        let protector = SoftwareKeyProtector()
        let slot = try protector.seal(randomKey(), userPresence: true)
        var otherKind = slot
        otherKind.protector = "secure-enclave"
        var damaged = slot
        damaged.keyBlob = Data([1, 2, 3])

        #expect(protector.canOpen(slot))
        #expect(!protector.canOpen(otherKind))
        #expect(!protector.canOpen(damaged))
    }

    /// The kind is compared first, so this does not reach the Secure Enclave. Whether it loads a key of this Mac
    /// without a prompt, and refuses one of another Mac, is for the self-test of the running app to confirm.
    @Test func theSecureEnclaveProtectorCannotOpenASlotOfAnotherKind() throws {
        let slot = try SoftwareKeyProtector().seal(randomKey(), userPresence: false)

        #expect(!SecureEnclaveProtector().canOpen(slot))
    }

    // MARK: Secure Enclave errors

    /// A prompt that did not unlock (dismissed by the person, the app or the system, or failed) leaves the app locked,
    /// so it can ask again. Only a device key that this Mac cannot use leads to the recovery code.
    @Test(arguments: [LAError.Code.userCancel, .appCancel, .systemCancel, .authenticationFailed])
    func aPromptThatDidNotUnlockLeavesTheAppLocked(_ code: LAError.Code) {
        #expect(SecureEnclaveProtector.keyError(for: LAError(code)) == .userCancelled)
    }

    /// CryptoTokenKit, which runs the Secure Enclave's key operations, reports a dismissed prompt as
    /// `TKErrorCodeCanceledByUser`, -4 in the domain "CryptoTokenKit", with or without a LocalAuthentication error
    /// inside. The errors are built by hand from the values in the SDK headers.
    @Test func aCancellationReportedByAnotherFrameworkIsACancellation() {
        let tokenCancel = NSError(domain: "CryptoTokenKit", code: -4)
        let wrapped = NSError(
            domain: "CryptoTokenKit",
            code: -9,
            userInfo: [NSUnderlyingErrorKey: LAError(.userCancel)]
        )
        let securityStatus = NSError(domain: NSOSStatusErrorDomain, code: Int(errSecUserCanceled))

        #expect(SecureEnclaveProtector.keyError(for: tokenCancel) == .userCancelled)
        #expect(SecureEnclaveProtector.keyError(for: wrapped) == .userCancelled)
        #expect(SecureEnclaveProtector.keyError(for: securityStatus) == .userCancelled)
    }

    @Test func everyOtherFailureMakesTheDeviceKeyUnusable() {
        let corruptedKey = NSError(domain: "CryptoTokenKit", code: -3)
        let invalidatedKey = NSError(domain: "CryptoTokenKit", code: -10)
        let missingItem = NSError(domain: NSOSStatusErrorDomain, code: Int(errSecItemNotFound))

        #expect(SecureEnclaveProtector.keyError(for: LAError(.passcodeNotSet)) == .deviceKeyUnusable)
        #expect(SecureEnclaveProtector.keyError(for: corruptedKey) == .deviceKeyUnusable)
        #expect(SecureEnclaveProtector.keyError(for: invalidatedKey) == .deviceKeyUnusable)
        #expect(SecureEnclaveProtector.keyError(for: CryptoKitError.authenticationFailure) == .deviceKeyUnusable)
        #expect(SecureEnclaveProtector.keyError(for: missingItem) == .deviceKeyUnusable)
    }

    /// Debug builds log an unrecognised failure by its shape alone: the domain and code of the error and of each
    /// error it wraps, never its descriptions.
    @Test func anErrorIsLoggedByItsDomainsAndCodesOnly() {
        let inner = NSError(
            domain: LAErrorDomain,
            code: -1004,
            userInfo: [NSLocalizedDescriptionKey: "Not interactive"]
        )
        let error = NSError(
            domain: "CryptoTokenKit",
            code: -9,
            userInfo: [NSUnderlyingErrorKey: inner, NSLocalizedDescriptionKey: "setoken: unable to compute"]
        )

        #expect(SecureEnclaveProtector.errorShape(error) == "CryptoTokenKit -9 (com.apple.LocalAuthentication -1004)")
    }

    // MARK: New keys

    @Test func aNewDataKeyHas256Bits() {
        let dek = KeyManager.newDataKey()

        #expect(dek.bitCount == 256)
        #expect(dek != KeyManager.newDataKey())
    }

    @Test func aNewRecoverySlotHasItsNumberDateAndOwnSalt() throws {
        let dek = randomKey()

        let first = try KeyManager.makeRecoverySlot(for: dek, number: 2, created: civilDate("2026-10-17"))
        let second = try KeyManager.makeRecoverySlot(for: dek, number: 3, created: civilDate("2026-10-18"))

        #expect(first.slot.number == 2)
        #expect(first.slot.created == civilDate("2026-10-17"))
        #expect(first.slot.label == "kód č. 2 z 17.\u{00A0}10.\u{00A0}2026")
        #expect(first.slot.salt.count == 16)
        #expect(first.slot.salt != second.slot.salt)
        #expect(first.code.split(separator: "-").map(\.count) == [4, 4, 4, 4, 4, 4, 4, 4])
        #expect(first.code != second.code)
    }

    @Test func theNewestRecoverySlotIsTheOneWithTheHighestNumber() {
        func slot(_ number: Int) -> RecoverySlot {
            RecoverySlot(number: number, created: civilDate("2026-10-17"), salt: Data(), wrappedKey: Data())
        }

        #expect(KeysFile(recoverySlots: [slot(1), slot(3), slot(2)]).newestRecoverySlot == slot(3))
        #expect(KeysFile(recoverySlots: []).newestRecoverySlot == nil)
    }

    // MARK: Unlocking

    @Test func aKeysFileUnlocksToTheSameDataKeyWithTheDeviceAndWithTheCode() async throws {
        let dek = KeyManager.newDataKey()
        let protector = SoftwareKeyProtector()
        let recovery = try KeyManager.makeRecoverySlot(for: dek, number: 1, created: civilDate("2026-10-17"))
        let keys = KeysFile(deviceSlot: try protector.seal(dek, userPresence: true), recoverySlots: [recovery.slot])

        let byDevice = try await KeyManager.unlock(keys, device: protector, reason: reason)
        let byCode = try KeyManager.unlock(keys, recoveryCode: recovery.code)

        #expect(byDevice == dek)
        #expect(byCode.dek == dek)
        #expect(byCode.slot == recovery.slot)
    }

    @Test func aCodeTypedWithZeroForOStillUnlocks() throws {
        let dek = randomKey()
        let salt = Data(0xA0..<0xB0)
        let slot = RecoverySlot(
            number: 1,
            created: civilDate("2026-10-17"),
            salt: salt,
            wrappedKey: try RecoveryCode.wrap(dek, secret: Data(0..<20), salt: salt)
        )

        // The code of this secret is AAAQ-EAYE-AUDA-OCAJ-BIFQ-YDIO-B4IB-CEQT.
        let unlocked = try KeyManager.unlock(
            KeysFile(recoverySlots: [slot]),
            recoveryCode: "aaaq-eaye-auda-0caj-bifq-ydi0-b4ib-ceqt"
        )

        #expect(unlocked.dek == dek)
        #expect(unlocked.slot == slot)
    }

    @Test func theCodeOpensWhicheverRecoverySlotItBelongsTo() throws {
        let olderKey = randomKey()
        let newerKey = randomKey()
        let older = try KeyManager.makeRecoverySlot(for: olderKey, number: 1, created: civilDate("2026-10-17"))
        let newer = try KeyManager.makeRecoverySlot(for: newerKey, number: 2, created: civilDate("2026-10-18"))
        let keys = KeysFile(recoverySlots: [older.slot, newer.slot])

        let byOlderCode = try KeyManager.unlock(keys, recoveryCode: older.code)
        let byNewerCode = try KeyManager.unlock(keys, recoveryCode: newer.code)

        #expect(byOlderCode.dek == olderKey)
        #expect(byOlderCode.slot == older.slot)
        #expect(byNewerCode.dek == newerKey)
        #expect(byNewerCode.slot == newer.slot)
    }

    @Test func aWellFormedCodeThatOpensNoSlotIsWrong() throws {
        let recovery = try KeyManager.makeRecoverySlot(for: randomKey(), number: 1, created: civilDate("2026-10-17"))
        let keys = KeysFile(recoverySlots: [recovery.slot])

        #expect(throws: KeyError.wrongRecoveryCode) {
            _ = try KeyManager.unlock(keys, recoveryCode: "7777-7777-7777-7777-7777-7777-7777-7777")
        }
    }

    @Test func aCodeThatDoesNotNormalizeTo32CharactersIsMalformed() throws {
        let recovery = try KeyManager.makeRecoverySlot(for: randomKey(), number: 1, created: civilDate("2026-10-17"))
        let keys = KeysFile(recoverySlots: [recovery.slot])

        #expect(throws: KeyError.malformedRecoveryCode) {
            _ = try KeyManager.unlock(keys, recoveryCode: "AAAQ-EAYE")
        }
        #expect(throws: KeyError.malformedRecoveryCode) {
            _ = try KeyManager.unlock(keys, recoveryCode: recovery.code + "A")
        }
    }

    @Test func unlockingWithTheDeviceNeedsADeviceSlot() async throws {
        let recovery = try KeyManager.makeRecoverySlot(for: randomKey(), number: 1, created: civilDate("2026-10-17"))
        let keys = KeysFile(recoverySlots: [recovery.slot])

        await #expect(throws: KeyError.noDeviceSlot) {
            _ = try await KeyManager.unlock(keys, device: SoftwareKeyProtector(), reason: reason)
        }
    }

    // MARK: Keys file

    @Test func aKeysFileComesBackFromSaveAndLoad() throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let url = directory.appending(path: "InvoicesTracker.keys")
        let dek = randomKey()
        let recovery = try KeyManager.makeRecoverySlot(for: dek, number: 1, created: civilDate("2026-10-17"))
        let keys = KeysFile(
            deviceSlot: try SoftwareKeyProtector().seal(dek, userPresence: true),
            recoverySlots: [recovery.slot]
        )

        try KeyManager.save(keys, to: url)

        #expect(try KeyManager.load(url) == keys)
    }

    @Test func savingReplacesTheWholeFile() throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let url = directory.appending(path: "InvoicesTracker.keys")
        let dek = randomKey()
        let first = try KeyManager.makeRecoverySlot(for: dek, number: 1, created: civilDate("2026-10-17"))
        let second = try KeyManager.makeRecoverySlot(for: dek, number: 2, created: civilDate("2026-10-18"))
        let replacement = KeysFile(recoverySlots: [second.slot])

        try KeyManager.save(
            KeysFile(
                deviceSlot: try SoftwareKeyProtector().seal(dek, userPresence: true),
                recoverySlots: [first.slot, second.slot]
            ),
            to: url
        )
        try KeyManager.save(replacement, to: url)

        #expect(try KeyManager.load(url) == replacement)
    }

    /// The new keys are written to a file of their own beside the keys file and renamed over it, so a save leaves
    /// nothing else behind, and one that cannot replace the file leaves it, and the folder, as they were.
    @Test func aSaveLeavesNothingBesideTheKeysFileAndOneThatFailsChangesNothing() throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let url = directory.appending(path: "InvoicesTracker.keys")
        let recovery = try KeyManager.makeRecoverySlot(for: randomKey(), number: 1, created: civilDate("2026-10-17"))
        let keys = KeysFile(recoverySlots: [recovery.slot])

        try KeyManager.save(keys, to: url)
        try KeyManager.save(keys, to: url)

        #expect(try FileManager.default.contentsOfDirectory(atPath: directory.path(percentEncoded: false)) == [
            "InvoicesTracker.keys"
        ])

        // A folder with a file in it where the keys file would go cannot be replaced by a file.
        let blocked = directory.appending(path: "Blocked", directoryHint: .isDirectory)
        let target = blocked.appending(path: "InvoicesTracker.keys", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
        try Data("keep".utf8).write(to: target.appending(path: "inside"))

        #expect(throws: (any Error).self) {
            try KeyManager.save(keys, to: target)
        }
        #expect(try FileManager.default.contentsOfDirectory(atPath: blocked.path(percentEncoded: false)) == [
            "InvoicesTracker.keys"
        ])
        #expect(try Data(contentsOf: target.appending(path: "inside")) == Data("keep".utf8))
    }

    /// Once the new file is renamed over the keys file, the save has taken effect: a folder that cannot be flushed
    /// after that is logged, not reported as a failed save. Without read permission on the folder it cannot be opened
    /// to be flushed, while files can still be made, read and renamed in it.
    @Test func aSaveWhoseFolderCannotBeFlushedStillReplacesTheFile() throws {
        let directory = try makeTemporaryDirectory()
        let folder = directory.appending(path: "Write only", directoryHint: .isDirectory)
        defer {
            try? FileManager.default.setAttributes(
                [.posixPermissions: 0o755], ofItemAtPath: folder.path(percentEncoded: false)
            )
            removeTemporaryDirectory(directory)
        }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appending(path: "InvoicesTracker.keys")
        let first = try KeyManager.makeRecoverySlot(for: randomKey(), number: 1, created: civilDate("2026-10-17"))
        let second = try KeyManager.makeRecoverySlot(for: randomKey(), number: 2, created: civilDate("2026-10-18"))
        try KeyManager.save(KeysFile(recoverySlots: [first.slot]), to: url)
        let path = folder.path(percentEncoded: false)
        try FileManager.default.setAttributes([.posixPermissions: 0o300], ofItemAtPath: path)

        try KeyManager.save(KeysFile(recoverySlots: [second.slot]), to: url)

        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: path)
        #expect(try KeyManager.load(url) == KeysFile(recoverySlots: [second.slot]))
        #expect(try FileManager.default.contentsOfDirectory(atPath: folder.path(percentEncoded: false)) == [
            "InvoicesTracker.keys"
        ])
    }

    /// The layout of the keys file. Changing it would leave the keys files and backups already written unreadable.
    @Test func theKeysFileIsPrettyPrintedJSONWithSortedKeys() throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let url = directory.appending(path: "InvoicesTracker.keys")
        let keys = KeysFile(
            deviceSlot: DeviceSlot(
                protector: "software",
                keyBlob: Data([1, 2]),
                encapsulatedKey: Data([3]),
                ciphertext: Data([4]),
                userPresence: true
            ),
            recoverySlots: [
                RecoverySlot(number: 1, created: civilDate("2026-10-17"), salt: Data([5]), wrappedKey: Data([6]))
            ]
        )

        try KeyManager.save(keys, to: url)

        let text = String(decoding: try Data(contentsOf: url), as: UTF8.self)
        #expect(
            text == """
                {
                  "deviceSlot" : {
                    "ciphertext" : "BA==",
                    "encapsulatedKey" : "Aw==",
                    "keyBlob" : "AQI=",
                    "protector" : "software",
                    "userPresence" : true
                  },
                  "formatVersion" : 1,
                  "recoverySlots" : [
                    {
                      "created" : "2026-10-17",
                      "number" : 1,
                      "salt" : "BQ==",
                      "wrappedKey" : "Bg=="
                    }
                  ]
                }
                """
        )
    }

    /// While the data key is being replaced, the keys file holds the slots of the old key under "previous" as well; a
    /// file without a change under way leaves the field out (see the layout above), so it reads as it always has. The
    /// slots of each key come out as a keys file of their own, those of the old key first.
    @Test func theKeysFileOfAChangeUnderWayKeepsTheSlotsOfTheOldKeyUnderPrevious() throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let url = directory.appending(path: "InvoicesTracker.keys")
        let newDevice = DeviceSlot(
            protector: "software", keyBlob: Data([1]), encapsulatedKey: Data([2]), ciphertext: Data([3]),
            userPresence: true
        )
        let newRecovery = RecoverySlot(
            number: 2, created: civilDate("2026-10-18"), salt: Data([4]), wrappedKey: Data([5])
        )
        let oldDevice = DeviceSlot(
            protector: "software", keyBlob: Data([6]), encapsulatedKey: Data([7]), ciphertext: Data([8]),
            userPresence: false
        )
        let oldRecovery = RecoverySlot(
            number: 1, created: civilDate("2026-10-17"), salt: Data([9]), wrappedKey: Data([10])
        )
        let old = KeysFile(deviceSlot: oldDevice, recoverySlots: [oldRecovery])
        let keys = KeysFile(deviceSlot: newDevice, recoverySlots: [newRecovery]).replacing(old)

        try KeyManager.save(keys, to: url)

        #expect(try KeyManager.load(url) == keys)
        #expect(keys.previous == PreviousKeySlots(deviceSlot: oldDevice, recoverySlots: [oldRecovery]))
        #expect(keys.slotSets == [old, KeysFile(deviceSlot: newDevice, recoverySlots: [newRecovery])])
        #expect(old.slotSets == [old])
        #expect(keys.newestRecoverySlot == newRecovery)
        let text = String(decoding: try Data(contentsOf: url), as: UTF8.self)
        #expect(
            text == """
                {
                  "deviceSlot" : {
                    "ciphertext" : "Aw==",
                    "encapsulatedKey" : "Ag==",
                    "keyBlob" : "AQ==",
                    "protector" : "software",
                    "userPresence" : true
                  },
                  "formatVersion" : 1,
                  "previous" : {
                    "deviceSlot" : {
                      "ciphertext" : "CA==",
                      "encapsulatedKey" : "Bw==",
                      "keyBlob" : "Bg==",
                      "protector" : "software",
                      "userPresence" : false
                    },
                    "recoverySlots" : [
                      {
                        "created" : "2026-10-17",
                        "number" : 1,
                        "salt" : "CQ==",
                        "wrappedKey" : "Cg=="
                      }
                    ]
                  },
                  "recoverySlots" : [
                    {
                      "created" : "2026-10-18",
                      "number" : 2,
                      "salt" : "BA==",
                      "wrappedKey" : "BQ=="
                    }
                  ]
                }
                """
        )
    }

    /// The damaged files below that hold a recovery slot differ from this file in one field each.
    @Test func aKeysFileWithoutADeviceSlotLoads() throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let url = directory.appending(path: "InvoicesTracker.keys")
        let content =
            #"{"formatVersion":1,"recoverySlots":"#
            + #"[{"number":1,"created":"2026-10-17","salt":"BQ==","wrappedKey":"Bg=="}]}"#
        try Data(content.utf8).write(to: url)

        let slot = RecoverySlot(number: 1, created: civilDate("2026-10-17"), salt: Data([5]), wrappedKey: Data([6]))
        #expect(try KeyManager.load(url) == KeysFile(recoverySlots: [slot]))
    }

    @Test(arguments: [
        "",
        #"{"formatVersion":1,"recoverySlots":["#,
        "[]",
        "{}",
        #"{"formatVersion":1}"#,
        #"{"formatVersion":1,"recoverySlots":[{"number":1,"created":"17.10.2026","salt":"BQ==","wrappedKey":"Bg=="}]}"#,
        #"{"formatVersion":1,"recoverySlots":[{"number":1,"created":"2026-10-17","salt":"?","wrappedKey":"Bg=="}]}"#,
        #"{"formatVersion":1,"recoverySlots":[],"deviceSlot":{"protector":"software"}}"#,
        // The keys file of a newer version of the app, which this version cannot read.
        #"{"formatVersion":2,"recoverySlots":[]}"#,
    ])
    func aDamagedKeysFileIsReported(_ content: String) throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let url = directory.appending(path: "InvoicesTracker.keys")
        try Data(content.utf8).write(to: url)

        #expect(throws: KeyError.keysFileDamaged) {
            _ = try KeyManager.load(url)
        }
    }

    @Test func aMissingKeysFileIsNil() throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }

        #expect(try KeyManager.load(directory.appending(path: "InvoicesTracker.keys")) == nil)
    }
}
