/// What can go wrong with the keys that protect the data key. No case carries key material or a code.
nonisolated enum KeyError: Error, Equatable {
    /// The recovery code is well formed but opens none of the recovery slots.
    case wrongRecoveryCode

    /// The typed recovery code does not come down to the 32 characters of a code.
    case malformedRecoveryCode

    /// The Touch ID or password prompt did not unlock: it was dismissed (by the person, the app or the system), or
    /// authentication failed. The app stays locked and can ask again.
    case userCancelled

    /// The device slot cannot be opened on this Mac: it was sealed on another Mac or by another kind of protector,
    /// the device key is gone, or the slot is damaged. Only a recovery code opens the data now.
    case deviceKeyUnusable

    /// The keys file is there, but it is not a keys file this version of the app can read.
    case keysFileDamaged

    /// The keys file has no device slot to open.
    case noDeviceSlot
}
