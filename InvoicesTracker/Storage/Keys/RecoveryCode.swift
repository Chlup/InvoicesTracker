import CryptoKit
import Foundation

/// The recovery code: a random 160-bit secret shown once as 32 Base32 characters (RFC 4648) in eight groups of four,
/// such as `K7QF-2MWX-…`. A key derived from the secret wraps the data key in a recovery slot.
///
/// The secret is random, not a chosen password, so a fast key derivation is enough: there is nothing to guess but
/// all 2¹⁶⁰ secrets.
nonisolated enum RecoveryCode {
    /// A secret has 160 bits.
    private static let secretByteCount = 20

    /// A code has one character for every five bits of its secret.
    private static let characterCount = 32

    private static let groupLength = 4

    /// The RFC 4648 Base32 alphabet: the character for each value from 0 to 31.
    private static let alphabet = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZ234567".utf8)

    /// What the key-encryption key is derived for. It is a fixed part of the data format, not the name of the app:
    /// changing it, also when the app is renamed, would make every code ever shown useless.
    private static let derivationInfo = Data("TaxesTracker recovery v1".utf8)

    /// What the Czech keyboard types on the number row without Shift, read as the code characters of the keys'
    /// digits: ě š č ř ž ý (in either case, as with Caps Lock) as 2 to 7, and + as I, the way the 1 itself reads.
    /// None of them is a code character, so the reading is unambiguous.
    private static let czechNumberRow: [Character: UInt8] = [
        "+": UInt8(ascii: "I"),
        "ě": UInt8(ascii: "2"), "Ě": UInt8(ascii: "2"),
        "š": UInt8(ascii: "3"), "Š": UInt8(ascii: "3"),
        "č": UInt8(ascii: "4"), "Č": UInt8(ascii: "4"),
        "ř": UInt8(ascii: "5"), "Ř": UInt8(ascii: "5"),
        "ž": UInt8(ascii: "6"), "Ž": UInt8(ascii: "6"),
        "ý": UInt8(ascii: "7"), "Ý": UInt8(ascii: "7"),
    ]

    /// A new secret of 20 random bytes.
    static func randomSecret() -> Data {
        KeyManager.randomBytes(count: secretByteCount)
    }

    /// The code of a 20-byte secret: its Base32 text, which needs no padding, in eight groups of four characters
    /// joined by "-", such as `AAAQ-EAYE-AUDA-OCAJ-BIFQ-YDIO-B4IB-CEQT`.
    static func display(_ secret: Data) -> String {
        precondition(secret.count == secretByteCount, "A recovery secret has 20 bytes.")
        var characters: [UInt8] = []
        // The bits read but not written yet: fewer than five before a byte comes in, so at most twelve.
        var pending: UInt16 = 0
        var pendingCount = 0
        for byte in secret {
            pending = (pending << 8) | UInt16(byte)
            pendingCount += 8
            while pendingCount >= 5 {
                pendingCount -= 5
                characters.append(alphabet[Int((pending >> pendingCount) & 0x1F)])
            }
            pending &= (1 << pendingCount) - 1
        }
        return stride(from: 0, to: characters.count, by: groupLength)
            .map { String(decoding: characters[$0..<$0 + groupLength], as: UTF8.self) }
            .joined(separator: "-")
    }

    /// The code characters of typed text: letters uppercased, the digits 0 and 1 (which are not in the alphabet)
    /// read as the letters O and I they look like, the Czech keyboard's number row without Shift read as the keys'
    /// digits (ě š č ř ž ý as 2 to 7 and + as I, composed or decomposed), and everything else dropped: spaces,
    /// dashes, dots, the digits 8 and 9, and other letters with diacritics.
    static func normalize(_ input: String) -> String {
        var characters: [UInt8] = []
        // Composed first, so that an e followed by a combining caron is the ě of the number row.
        for character in input.precomposedStringWithCanonicalMapping {
            guard let symbol = codeCharacter(typed: character), alphabet.contains(symbol) else { continue }
            characters.append(symbol)
        }
        return String(decoding: characters, as: UTF8.self)
    }

    /// The secret of a typed code, or nil unless the code normalizes to exactly 32 characters.
    static func secret(from input: String) -> Data? {
        let characters = Array(normalize(input).utf8)
        guard characters.count == characterCount else { return nil }
        var secret = Data(capacity: secretByteCount)
        // The bits read but not written yet: fewer than eight before a character comes in, so at most twelve.
        var pending: UInt16 = 0
        var pendingCount = 0
        for character in characters {
            guard let value = alphabet.firstIndex(of: character) else { return nil }
            pending = (pending << 5) | UInt16(value)
            pendingCount += 5
            if pendingCount >= 8 {
                pendingCount -= 8
                secret.append(UInt8(truncatingIfNeeded: pending >> pendingCount))
                pending &= (1 << pendingCount) - 1
            }
        }
        return secret
    }

    /// The data key wrapped with AES Key Wrap (RFC 3394) under the key-encryption key of `secret` and `salt`.
    static func wrap(_ dek: SymmetricKey, secret: Data, salt: Data) throws -> Data {
        try AES.KeyWrap.wrap(dek, using: keyEncryptionKey(secret: secret, salt: salt))
    }

    /// The data key that `wrap` wrapped with the same secret and salt. Any other secret or salt, or a damaged wrapped
    /// key, fails the integrity check of the key wrap and throws `KeyError.wrongRecoveryCode`.
    static func unwrap(_ wrapped: Data, secret: Data, salt: Data) throws -> SymmetricKey {
        do {
            return try AES.KeyWrap.unwrap(wrapped, using: keyEncryptionKey(secret: secret, salt: salt))
        } catch {
            throw KeyError.wrongRecoveryCode
        }
    }

    /// A typed character read as a code character: a key of the Czech number row as the code character of its
    /// digit, and an ASCII character uppercased, with O for 0 and I for 1. Nil for any other character. Whether the
    /// result is in the alphabet is for the caller to check.
    private static func codeCharacter(typed character: Character) -> UInt8? {
        if let digit = czechNumberRow[character] {
            return digit
        }
        guard let ascii = character.asciiValue else { return nil }
        switch ascii {
        case UInt8(ascii: "0"): return UInt8(ascii: "O")
        case UInt8(ascii: "1"): return UInt8(ascii: "I")
        case UInt8(ascii: "a")...UInt8(ascii: "z"): return ascii - UInt8(ascii: "a") + UInt8(ascii: "A")
        default: return ascii
        }
    }

    /// HKDF-SHA256 (RFC 5869) of the secret, salted per slot.
    private static func keyEncryptionKey(secret: Data, salt: Data) -> SymmetricKey {
        HKDF<SHA256>.deriveKey(
            inputKeyMaterial: SymmetricKey(data: secret),
            salt: salt,
            info: derivationInfo,
            outputByteCount: 32
        )
    }
}
