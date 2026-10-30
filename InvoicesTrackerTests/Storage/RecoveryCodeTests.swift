import CryptoKit
import Foundation
import Testing
@testable import InvoicesTracker

/// The recovery code: how its secret is shown and typed back, the key wrap it opens, and the label of its slot.
struct RecoveryCodeTests {
    // MARK: Showing and typing the code

    @Test func aSecretIsShownAsEightGroupsOfFourBase32Characters() {
        #expect(RecoveryCode.display(Data(0..<20)) == "AAAQ-EAYE-AUDA-OCAJ-BIFQ-YDIO-B4IB-CEQT")
        #expect(RecoveryCode.display(Data(repeating: 0xFF, count: 20)) == "7777-7777-7777-7777-7777-7777-7777-7777")
    }

    @Test func typingIgnoresCaseSpacesDashesAndDots() {
        #expect(RecoveryCode.secret(from: "aaaq eayE-auda.ocaj bifq ydio b4ib ceqt") == Data(0..<20))
    }

    @Test func normalizingUppercasesReadsZeroAsOAndOneAsIAndDropsEverythingElse() {
        #expect(RecoveryCode.normalize("k7qf-2mwx 0 1") == "K7QF2MWXOI")
        // 8 and 9 are not Base32 digits, and other letters with diacritics (here those of the Czech number row's
        // 8, 9 and 0 keys, and ů), no-break spaces and dashes are not code characters either.
        #expect(RecoveryCode.normalize("8 9 á í é ů\u{00A0}\u{2013}a") == "A")
    }

    // MARK: The Czech keyboard

    /// Without Shift, the Czech keyboard's number row types ě š č ř ž ý where 2 to 7 are, and + where 1 is (and 1
    /// reads as I). None of them is a code character, so reading them as the digits is unambiguous.
    @Test func theCzechNumberRowWithoutShiftReadsAsTheDigits() {
        #expect(RecoveryCode.normalize("+ěščřžý") == "I234567")
        #expect(RecoveryCode.normalize("ĚŠČŘŽÝ") == "234567")
    }

    @Test func aCodeTypedEntirelyOnTheCzechNumberRowDecodes() {
        #expect(
            RecoveryCode.secret(from: "ýýýý-ýýýý-ýýýý-ýýýý-ýýýý-ýýýý-ýýýý-ýýýý") == Data(repeating: 0xFF, count: 20)
        )
    }

    /// The secret was decoded with Python's `base64.b32decode`, not with this code.
    @Test func aCodeWithCzechDigitsInMixedCaseDecodes() {
        let secret = hexData("d6f9df7c0110c8531d0952d8d73e1194e95b5f19")

        #expect(RecoveryCode.secret(from: "2345-67AB-CDEF-GHIJ-KLMN-OPQR-STUV-WXYZ") == secret)
        #expect(RecoveryCode.secret(from: "ěščř-žýab-cdef-gh+j-klmn-opqr-stuv-wxyz") == secret)
        #expect(RecoveryCode.secret(from: "ĚšČř-ŽýAb-CdEf-Gh+J-kLmN-oPqR-sTuV-wXyZ") == secret)
    }

    /// A letter and a combining caron or acute accent read like the precomposed letter.
    @Test func decomposedCzechLettersReadLikeComposedOnes() {
        let secret = hexData("d6f9df7c0110c8531d0952d8d73e1194e95b5f19")
        let decomposed = "e\u{030C}s\u{030C}c\u{030C}r\u{030C}-z\u{030C}y\u{0301}ab-cdef-gh+j-klmn-opqr-stuv-wxyz"

        #expect(RecoveryCode.secret(from: decomposed) == secret)
        #expect(RecoveryCode.normalize("E\u{030C}S\u{030C}C\u{030C}R\u{030C}Z\u{030C}Y\u{0301}") == "234567")
    }

    @Test func aCodeWithoutExactly32CharactersIsNoSecret() {
        #expect(RecoveryCode.secret(from: "AAAQ-EAYE") == nil)
        #expect(RecoveryCode.secret(from: "AAAQ-EAYE-AUDA-OCAJ-BIFQ-YDIO-B4IB-CEQ") == nil)
        #expect(RecoveryCode.secret(from: "AAAQ-EAYE-AUDA-OCAJ-BIFQ-YDIO-B4IB-CEQTA") == nil)
        #expect(RecoveryCode.secret(from: "") == nil)
    }

    @Test func aRandomSecretHas160BitsAndComesBackFromItsCode() {
        let secret = RecoveryCode.randomSecret()

        #expect(secret.count == 20)
        #expect(secret != RecoveryCode.randomSecret())
        #expect(RecoveryCode.secret(from: RecoveryCode.display(secret)) == secret)
    }

    // MARK: Key wrap

    @Test func theDataKeyUnwrapsWithTheSecretAndSaltItWasWrappedWith() throws {
        let dek = randomKey()
        let secret = RecoveryCode.randomSecret()
        let salt = Data(0xA0..<0xB0)

        let wrapped = try RecoveryCode.wrap(dek, secret: secret, salt: salt)

        #expect(try RecoveryCode.unwrap(wrapped, secret: secret, salt: salt) == dek)
    }

    /// The key-encryption key is HKDF-SHA256 of the secret with the salt and the info "TaxesTracker recovery v1",
    /// and the data key is wrapped with AES Key Wrap (RFC 3394). The expected bytes were computed with OpenSSL
    /// (`openssl kdf … HKDF`, then `openssl enc -id-aes256-wrap`) rather than CryptoKit, and they pin the layout of
    /// every recovery slot ever written.
    @Test func theWrapIsAESKeyWrapUnderAnHKDFSHA256Key() throws {
        let wrapped = try RecoveryCode.wrap(
            SymmetricKey(data: Data(0x40..<0x60)),
            secret: Data(0..<20),
            salt: Data(0xA0..<0xB0)
        )

        #expect(wrapped == hexData("6607a12e40f9080f9fc1b9acba9efd91ebb15d3b67fea7cb9d39c7cc93ad87a587efc3ef97269945"))
    }

    @Test func anotherSecretIsAWrongRecoveryCode() throws {
        let salt = Data(0xA0..<0xB0)
        let wrapped = try RecoveryCode.wrap(randomKey(), secret: Data(0..<20), salt: salt)

        #expect(throws: KeyError.wrongRecoveryCode) {
            _ = try RecoveryCode.unwrap(wrapped, secret: Data(1...20), salt: salt)
        }
    }

    @Test func anotherSaltIsAWrongRecoveryCode() throws {
        let secret = Data(0..<20)
        let wrapped = try RecoveryCode.wrap(randomKey(), secret: secret, salt: Data(0xA0..<0xB0))

        #expect(throws: KeyError.wrongRecoveryCode) {
            _ = try RecoveryCode.unwrap(wrapped, secret: secret, salt: Data(0xB0..<0xC0))
        }
    }

    // MARK: Slot label

    @Test func aRecoverySlotIsLabelledWithItsNumberAndDate() {
        let slot = RecoverySlot(number: 1, created: civilDate("2026-10-17"), salt: Data(), wrappedKey: Data())

        #expect(slot.label == "kód č. 1 z 17.\u{00A0}10.\u{00A0}2026")
    }
}
