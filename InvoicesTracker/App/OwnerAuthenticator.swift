import Foundation
import LocalAuthentication

/// Asks the person to prove that this Mac is theirs, with Touch ID or the password of the Mac, and tells whether they
/// did. It opens nothing and decrypts nothing: the lock after inactivity unlocks with it while the data stays open
/// (`AppModel.unlockAfterIdle()`).
nonisolated protocol OwnerAuthenticator: Sendable {
    /// Whether the person proved it. `reason`, which must not be empty, is shown in the prompt. False when the prompt
    /// was dismissed, did not unlock, or could not be shown.
    func authenticate(reason: String) async -> Bool
}

/// Touch ID or the password of the Mac, as LocalAuthentication asks for them (`.deviceOwnerAuthentication`): Touch ID
/// or a paired Apple Watch when there is one, and the password of the Mac always.
nonisolated struct DeviceOwnerAuthenticator: OwnerAuthenticator {
    /// Runs off the caller's actor, and the prompt waits without blocking a thread. A failure other than the person
    /// dismissing the prompt is logged, with the domain and the code of the error alone.
    @concurrent
    func authenticate(reason: String) async -> Bool {
        // LocalAuthentication raises an Objective-C exception for an empty reason.
        precondition(!reason.isEmpty, "The reason shown in the Touch ID or password prompt cannot be empty.")
        let context = LAContext()
        do {
            return try await context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason)
        } catch {
            let error = error as NSError
            if error.domain != LAErrorDomain || error.code != LAError.Code.userCancel.rawValue {
                AppModel.log("Asking for Touch ID or the password", failedWith: error)
            }
            return false
        }
    }
}
