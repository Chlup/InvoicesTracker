import CryptoKit
import Foundation
import Testing
import os
@testable import InvoicesTracker

/// The self-test of the Secure Enclave that the Debug menu runs: it seals a random data key, opens it again and
/// compares. A software protector stands in for the Secure Enclave, so nothing here touches the real one; the test of
/// the real one is the menu item itself.
@MainActor
struct SecureEnclaveSelfTestTests {
    /// A protector that records how it was used and otherwise behaves like the software one.
    private final class RecordingProtector: DeviceKeyProtector {
        struct Calls: Sendable {
            var sealedWithUserPresence: [Bool] = []
            var openReasons: [String] = []
            var canOpenAsked = 0
        }

        private let calls = OSAllocatedUnfairLock(initialState: Calls())

        var recorded: Calls {
            calls.withLock { $0 }
        }

        var name: String {
            SoftwareKeyProtector().name
        }

        func seal(_ dek: SymmetricKey, userPresence: Bool) throws -> DeviceSlot {
            calls.withLock { $0.sealedWithUserPresence.append(userPresence) }
            return try SoftwareKeyProtector().seal(dek, userPresence: userPresence)
        }

        func canOpen(_ slot: DeviceSlot) -> Bool {
            calls.withLock { $0.canOpenAsked += 1 }
            return SoftwareKeyProtector().canOpen(slot)
        }

        func open(_ slot: DeviceSlot, reason: String) async throws -> SymmetricKey {
            calls.withLock { $0.openReasons.append(reason) }
            return try await SoftwareKeyProtector().open(slot, reason: reason)
        }
    }

    /// A protector that opens every slot to a key of its own, as a broken Secure Enclave might.
    private struct OtherKeyProtector: DeviceKeyProtector {
        var name: String {
            SoftwareKeyProtector().name
        }

        func seal(_ dek: SymmetricKey, userPresence: Bool) throws -> DeviceSlot {
            try SoftwareKeyProtector().seal(dek, userPresence: userPresence)
        }

        func canOpen(_ slot: DeviceSlot) -> Bool {
            true
        }

        func open(_ slot: DeviceSlot, reason: String) async throws -> SymmetricKey {
            SymmetricKey(size: .bits256)
        }
    }

    /// A protector that seals but says that it cannot open what it sealed.
    private struct UnloadableProtector: DeviceKeyProtector {
        var name: String {
            SoftwareKeyProtector().name
        }

        func seal(_ dek: SymmetricKey, userPresence: Bool) throws -> DeviceSlot {
            try SoftwareKeyProtector().seal(dek, userPresence: userPresence)
        }

        func canOpen(_ slot: DeviceSlot) -> Bool {
            false
        }

        func open(_ slot: DeviceSlot, reason: String) async throws -> SymmetricKey {
            Issue.record("A slot that cannot be loaded is not opened")
            throw KeyError.deviceKeyUnusable
        }
    }

    @Test func aProtectorThatOpensWhatItSealedWorks() async {
        let result = await SecureEnclaveSelfTest.run(using: SoftwareKeyProtector())

        #expect(result == "Secure Enclave funguje.")
    }

    @Test func theKeyIsSealedWithoutUserPresenceSoNoPromptCanComeUp() async {
        let protector = RecordingProtector()

        _ = await SecureEnclaveSelfTest.run(using: protector)

        let recorded = protector.recorded
        #expect(recorded.sealedWithUserPresence == [false])
        // The slot is checked without a prompt first, and opened with a reason the prompt would show.
        #expect(recorded.canOpenAsked == 1)
        #expect(recorded.openReasons.count == 1)
        #expect(recorded.openReasons.allSatisfy { !$0.isEmpty })
    }

    @Test func eachRunSealsAKeyOfItsOwn() async {
        let first = KeyCatcher()
        let second = KeyCatcher()

        _ = await SecureEnclaveSelfTest.run(using: first)
        _ = await SecureEnclaveSelfTest.run(using: second)

        #expect(first.keys.count == 1 && second.keys.count == 1)
        #expect(first.keys != second.keys)
        // A data key is 32 bytes.
        #expect(first.keys.first?.count == 32)
    }

    /// A software protector that remembers the bytes of every key it is asked to seal.
    private final class KeyCatcher: DeviceKeyProtector {
        private let sealed = OSAllocatedUnfairLock(initialState: [Data]())

        var keys: [Data] {
            sealed.withLock { $0 }
        }

        var name: String {
            SoftwareKeyProtector().name
        }

        func seal(_ dek: SymmetricKey, userPresence: Bool) throws -> DeviceSlot {
            sealed.withLock { $0.append(dek.withUnsafeBytes { Data($0) }) }
            return try SoftwareKeyProtector().seal(dek, userPresence: userPresence)
        }

        func canOpen(_ slot: DeviceSlot) -> Bool {
            SoftwareKeyProtector().canOpen(slot)
        }

        func open(_ slot: DeviceSlot, reason: String) async throws -> SymmetricKey {
            try await SoftwareKeyProtector().open(slot, reason: reason)
        }
    }

    @Test func aKeyThatCannotBeSealedIsReportedWithTheError() async {
        let result = await SecureEnclaveSelfTest.run(using: ScriptedKeyProtector(sealFailure: .deviceKeyUnusable))

        #expect(result == "Secure Enclave nefunguje: klíč se nepodařilo vytvořit (deviceKeyUnusable).")
    }

    @Test func aDismissedPromptIsReportedAsUserCancelled() async {
        let result = await SecureEnclaveSelfTest.run(using: ScriptedKeyProtector(openFailure: .userCancelled))

        #expect(result == "Secure Enclave nefunguje: klíč se nepodařilo otevřít (userCancelled).")
    }

    @Test func aKeyThatCannotBeOpenedIsReportedWithTheError() async {
        let result = await SecureEnclaveSelfTest.run(using: ScriptedKeyProtector(openFailure: .deviceKeyUnusable))

        #expect(result == "Secure Enclave nefunguje: klíč se nepodařilo otevřít (deviceKeyUnusable).")
    }

    @Test func aKeyThatOpensToAnotherKeyIsReported() async {
        let result = await SecureEnclaveSelfTest.run(using: OtherKeyProtector())

        #expect(result == "Secure Enclave nefunguje: otevřený klíč není ten, který se uložil.")
    }

    @Test func aKeyThatTheSecureEnclaveCannotLoadIsReportedWithoutOpeningIt() async {
        let result = await SecureEnclaveSelfTest.run(using: UnloadableProtector())

        #expect(result == "Secure Enclave nefunguje: uložený klíč se v Secure Enclave nedá načíst.")
    }
}
