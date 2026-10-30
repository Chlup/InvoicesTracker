#if DEBUG
import AppKit
import CryptoKit
import SwiftUI

/// The self-test of the Secure Enclave of this Mac. Only debug builds have it, under Vývoj › Ověřit Secure Enclave
/// (`DebugCommands`). It checks, in this order, that the protector of the Secure Enclave (`SecureEnclaveProtector`):
/// 1. seals a new random data key to a new device key, without user presence;
/// 2. takes the slot it made for its own without opening it (`canOpen`);
/// 3. opens the slot again;
/// 4. gives back the data key that was sealed.
///
/// It stops at the first step that fails and says what it found in one line of Czech (`run(using:)`):
/// - "Secure Enclave funguje." — every step worked.
/// - "Secure Enclave nefunguje: klíč se nepodařilo vytvořit (…)." — step 1 failed: in the brackets the case of the
///   `KeyError`, or the domain and the code of any other error.
/// - "Secure Enclave nefunguje: uložený klíč se v Secure Enclave nedá načíst." — step 2 said no.
/// - "Secure Enclave nefunguje: klíč se nepodařilo otevřít (…)." — step 3 failed, with the error as for step 1.
/// - "Secure Enclave nefunguje: otevřený klíč není ten, který se uložil." — step 4 got another key back.
///
/// The slot has no user presence, so the self-test never asks for Touch ID or the password, and it tells nothing of a
/// slot that has it: whether `canOpen` loads such a key without a prompt, how often the real unlock asks, what a
/// dismissed prompt gives (`KeyError.userCancelled`) and what the slot of another Mac gives are for a person to try at
/// the Mac, with Touch ID on. The device key it makes is not kept, and the data and its keys file are not touched.
@MainActor
enum SecureEnclaveSelfTest {
    /// What the self-test says when the Secure Enclave did what the app needs of it.
    static let works = "Secure Enclave funguje."

    /// Why a prompt would be shown, if there were one.
    private static let reason = "ověřit Secure Enclave"

    /// The self-test of this Mac's Secure Enclave: `run(using:)` with `SecureEnclaveProtector`.
    static func run() async -> String {
        await run(using: SecureEnclaveProtector())
    }

    /// The four steps of the self-test with `protector`: a new data key is sealed (without user presence), the slot is
    /// looked at without being opened (`canOpen`), opened, and the key that comes out is compared with the one that
    /// went in. Returns `works`, or the line of the first step that failed, with the error where there is one: the
    /// case of a `KeyError`, or the domain and the code of any other.
    static func run(using protector: any DeviceKeyProtector) async -> String {
        let key = SymmetricKey(size: .bits256)
        let slot: DeviceSlot
        do {
            slot = try protector.seal(key, userPresence: false)
        } catch {
            return failure("klíč se nepodařilo vytvořit", error)
        }
        guard protector.canOpen(slot) else {
            return "Secure Enclave nefunguje: uložený klíč se v Secure Enclave nedá načíst."
        }
        do {
            let opened = try await protector.open(slot, reason: reason)
            guard opened == key else {
                return "Secure Enclave nefunguje: otevřený klíč není ten, který se uložil."
            }
        } catch {
            return failure("klíč se nepodařilo otevřít", error)
        }
        return works
    }

    /// "Secure Enclave nefunguje: klíč se nepodařilo otevřít (userCancelled)."
    private static func failure(_ what: String, _ error: any Error) -> String {
        "Secure Enclave nefunguje: \(what) (\(shape(of: error)))."
    }

    /// What names `error` without saying more of it than the log would: the case of a `KeyError`, otherwise the domain
    /// and the code.
    private static func shape(of error: any Error) -> String {
        if error is KeyError {
            return String(describing: error)
        }
        let error = error as NSError
        return "\(error.domain) \(error.code)"
    }

    /// Shows `result` in an alert of its own, which the Debug menu does once the self-test has run.
    static func show(_ result: String) {
        let alert = NSAlert()
        alert.messageText = "Secure Enclave"
        alert.informativeText = result
        alert.addButton(withTitle: "Zavřít")
        alert.runModal()
    }
}

/// The menu "Vývoj", which only debug builds have beside the menus of the app: "Ověřit Secure Enclave" runs the
/// self-test of this Mac's Secure Enclave (`SecureEnclaveSelfTest`) and shows its one line in an alert titled
/// "Secure Enclave". It asks for nothing and changes nothing of the data.
struct DebugCommands: Commands {
    var body: some Commands {
        CommandMenu("Vývoj") {
            Button("Ověřit Secure Enclave") {
                Task {
                    SecureEnclaveSelfTest.show(await SecureEnclaveSelfTest.run())
                }
            }
        }
    }
}
#endif
