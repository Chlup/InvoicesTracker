import CryptoKit
import CryptoTokenKit
import Foundation
import LocalAuthentication
import os
import Security

/// Seals the data key to a device key of this Mac, and opens it again.
nonisolated protocol DeviceKeyProtector: Sendable {
    /// The kind of device key, stored in every slot this protector seals as `DeviceSlot.protector`.
    var name: String { get }

    /// Seals `dek` to a new device key. With `userPresence`, opening the slot needs Touch ID or the Mac's password.
    func seal(_ dek: SymmetricKey, userPresence: Bool) throws -> DeviceSlot

    /// Whether `slot` looks like one this protector can open: a slot of its kind with a device key it can load. Nothing
    /// is opened and nothing is asked of the person, so a slot it takes can still fail to open, and `open` then throws
    /// `KeyError.deviceKeyUnusable`.
    func canOpen(_ slot: DeviceSlot) -> Bool

    /// The data key sealed in `slot`. `reason`, which must not be empty, is shown in the Touch ID or password prompt.
    /// Throws `KeyError.userCancelled` when the prompt does not unlock (it is dismissed or authentication fails), so
    /// the app stays locked and can ask again, and `KeyError.deviceKeyUnusable` for every other failure, including a
    /// slot of another kind of protector.
    func open(_ slot: DeviceSlot, reason: String) async throws -> SymmetricKey
}

/// The device key in this Mac's Secure Enclave: a P-256 key agreement key that never leaves it. The slot keeps the
/// key's `dataRepresentation`, an opaque blob that only this Mac's Secure Enclave can use, so it is safe in a file.
nonisolated struct SecureEnclaveProtector: DeviceKeyProtector {
    var name: String {
        "secure-enclave"
    }

    func seal(_ dek: SymmetricKey, userPresence: Bool) throws -> DeviceSlot {
        let privateKey: SecureEnclave.P256.KeyAgreement.PrivateKey
        do {
            privateKey = try SecureEnclave.P256.KeyAgreement.PrivateKey(
                compactRepresentable: false,
                accessControl: try Self.accessControl(userPresence: userPresence)
            )
        } catch {
            #if DEBUG
            if !(error is KeyError) {
                Self.logger.error("Making a Secure Enclave key failed: \(Self.errorShape(error), privacy: .public)")
            }
            #endif
            throw KeyError.deviceKeyUnusable
        }
        let sealed = try DeviceSlotHPKE.seal(dek, to: privateKey.publicKey)
        return DeviceSlot(
            protector: name,
            keyBlob: privateKey.dataRepresentation,
            encapsulatedKey: sealed.encapsulatedKey,
            ciphertext: sealed.ciphertext,
            userPresence: userPresence
        )
    }

    /// Loads the key blob into a key of this Mac's Secure Enclave with a context that may not interact with the person,
    /// so no prompt can appear; any error is a no. The self-test of debug builds (`SecureEnclaveSelfTest`) checks this
    /// only for a slot without user presence. That it never prompts for a slot with user presence, and whether the
    /// blob of another Mac (or of a Secure Enclave that was reset) already fails here or only in `open` — which then
    /// throws `.deviceKeyUnusable`, so a caller falls back to the recovery code either way — are for a person to try at
    /// the Mac.
    func canOpen(_ slot: DeviceSlot) -> Bool {
        guard slot.protector == name else {
            return false
        }
        let context = LAContext()
        context.interactionNotAllowed = true
        do {
            _ = try SecureEnclave.P256.KeyAgreement.PrivateKey(
                dataRepresentation: slot.keyBlob,
                authenticationContext: context
            )
            return true
        } catch {
            return false
        }
    }

    /// Runs off the caller's actor. With user presence, LocalAuthentication asks for Touch ID or the password first:
    /// it reports a prompt that did not unlock as a documented `LAError`, and it waits without blocking a thread. The
    /// key agreement inside the Secure Enclave then uses the same authenticated context, so the person is asked once.
    @concurrent
    func open(_ slot: DeviceSlot, reason: String) async throws -> SymmetricKey {
        // LocalAuthentication raises an Objective-C exception for an empty reason.
        precondition(!reason.isEmpty, "The reason shown in the Touch ID or password prompt cannot be empty.")
        guard slot.protector == name else {
            throw KeyError.deviceKeyUnusable
        }
        let context = LAContext()
        context.localizedReason = reason
        do {
            if slot.userPresence {
                try await context.evaluateAccessControl(
                    try Self.accessControl(userPresence: true),
                    operation: .useKeyKeyExchange,
                    localizedReason: reason
                )
            }
            let privateKey = try SecureEnclave.P256.KeyAgreement.PrivateKey(
                dataRepresentation: slot.keyBlob,
                authenticationContext: context
            )
            return try DeviceSlotHPKE.open(slot, with: privateKey)
        } catch {
            let keyError = Self.keyError(for: error)
            #if DEBUG
            if keyError == .deviceKeyUnusable && !(error is KeyError) {
                let shape = Self.errorShape(error)
                Self.logger.error("Unrecognised error opening a Secure Enclave slot: \(shape, privacy: .public)")
            }
            #endif
            throw keyError
        }
    }

    /// The error that `open` reports for a failure: `.userCancelled` when the failure, or an error it wraps, says the
    /// prompt did not unlock (the person dismissed it, the app or the system took it down, or authentication
    /// failed), so the app stays locked and can ask again; otherwise `.deviceKeyUnusable`.
    static func keyError(for error: any Error) -> KeyError {
        isUnsuccessfulPrompt(error) ? .userCancelled : .deviceKeyUnusable
    }

    /// The LocalAuthentication codes of a prompt that did not unlock.
    private static let unsuccessfulPromptCodes = [
        LAError.Code.userCancel, .appCancel, .systemCancel, .authenticationFailed,
    ].map(\.rawValue)

    private static func isUnsuccessfulPrompt(_ error: any Error) -> Bool {
        let error = error as NSError
        switch error.domain {
        case LAErrorDomain where unsuccessfulPromptCodes.contains(error.code):
            return true
        // CryptoTokenKit runs the key operations of the Secure Enclave.
        case TKErrorDomain where error.code == TKError.Code.canceledByUser.rawValue:
            return true
        case NSOSStatusErrorDomain where error.code == Int(errSecUserCanceled):
            return true
        default:
            guard let underlying = error.userInfo[NSUnderlyingErrorKey] as? any Error else {
                return false
            }
            return isUnsuccessfulPrompt(underlying)
        }
    }

    #if DEBUG
    /// Records the shape of the errors that the mapping does not recognise, for the self-test of the Secure Enclave.
    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "InvoicesTracker", category: "Keys")

    /// The shape of an error, for the log: its domain and code, followed in parentheses by the shape of the error it
    /// wraps, if any. Never its descriptions.
    static func errorShape(_ error: any Error) -> String {
        let error = error as NSError
        let shape = "\(error.domain) \(error.code)"
        guard let underlying = error.userInfo[NSUnderlyingErrorKey] as? any Error else {
            return shape
        }
        return "\(shape) (\(errorShape(underlying)))"
    }
    #endif

    /// Using the key needs this Mac to be unlocked, and with `userPresence` also Touch ID or the Mac's password.
    private static func accessControl(userPresence: Bool) throws -> SecAccessControl {
        var flags: SecAccessControlCreateFlags = [.privateKeyUsage]
        if userPresence {
            flags.insert(.userPresence)
        }
        guard
            let accessControl = SecAccessControlCreateWithFlags(
                nil,
                kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
                flags,
                nil
            )
        else {
            throw KeyError.deviceKeyUnusable
        }
        return accessControl
    }
}

#if DEBUG
/// A software P-256 key kept in the slot itself, so it protects nothing: it stands in for the Secure Enclave in
/// tests, and only debug builds have it. It seals and opens exactly like `SecureEnclaveProtector`, records
/// `userPresence` without asking for it, and refuses an empty `reason` the same way.
nonisolated struct SoftwareKeyProtector: DeviceKeyProtector {
    var name: String {
        "software"
    }

    func seal(_ dek: SymmetricKey, userPresence: Bool) throws -> DeviceSlot {
        let privateKey = P256.KeyAgreement.PrivateKey()
        let sealed = try DeviceSlotHPKE.seal(dek, to: privateKey.publicKey)
        return DeviceSlot(
            protector: name,
            keyBlob: privateKey.rawRepresentation,
            encapsulatedKey: sealed.encapsulatedKey,
            ciphertext: sealed.ciphertext,
            userPresence: userPresence
        )
    }

    /// A software slot whose key blob is a P-256 key.
    func canOpen(_ slot: DeviceSlot) -> Bool {
        slot.protector == name && (try? P256.KeyAgreement.PrivateKey(rawRepresentation: slot.keyBlob)) != nil
    }

    func open(_ slot: DeviceSlot, reason: String) async throws -> SymmetricKey {
        precondition(!reason.isEmpty, "The reason shown in the Touch ID or password prompt cannot be empty.")
        guard slot.protector == name else {
            throw KeyError.deviceKeyUnusable
        }
        do {
            let privateKey = try P256.KeyAgreement.PrivateKey(rawRepresentation: slot.keyBlob)
            return try DeviceSlotHPKE.open(slot, with: privateKey)
        } catch {
            throw KeyError.deviceKeyUnusable
        }
    }
}
#endif

/// HPKE (RFC 9180) as every device slot uses it: base mode with DHKEM(P-256, HKDF-SHA256), HKDF-SHA256 and
/// AES-256-GCM, and the 32 bytes of the data key as the plaintext.
private nonisolated enum DeviceSlotHPKE {
    static let ciphersuite = HPKE.Ciphersuite.P256_SHA256_AES_GCM_256

    /// What the sealed key is for. It is a fixed part of the data format, not the name of the app: changing it, also
    /// when the app is renamed, would make every device slot ever sealed unusable.
    static let info = Data("TaxesTracker data key v1".utf8)

    static func seal(
        _ dek: SymmetricKey,
        to publicKey: P256.KeyAgreement.PublicKey
    ) throws -> (encapsulatedKey: Data, ciphertext: Data) {
        var sender = try HPKE.Sender(recipientKey: publicKey, ciphersuite: ciphersuite, info: info)
        let ciphertext = try dek.withUnsafeBytes { try sender.seal($0) }
        return (sender.encapsulatedKey, ciphertext)
    }

    /// The data key sealed in `slot`. With a Secure Enclave key the key agreement runs inside the Secure Enclave,
    /// which asks for authentication when the key needs it and the context has not given it yet.
    static func open(_ slot: DeviceSlot, with privateKey: some HPKEDiffieHellmanPrivateKey) throws -> SymmetricKey {
        var recipient = try HPKE.Recipient(
            privateKey: privateKey,
            ciphersuite: ciphersuite,
            info: info,
            encapsulatedKey: slot.encapsulatedKey
        )
        let plaintext = try recipient.open(slot.ciphertext)
        // Base mode does not authenticate the sender, and anyone with the public key can seal something to it.
        guard plaintext.count == KeyManager.dataKeyByteCount else {
            throw KeyError.deviceKeyUnusable
        }
        return SymmetricKey(data: plaintext)
    }
}
