import Foundation

/// Source of the current time, injected wherever behavior depends on "now" so tests can control it.
nonisolated protocol AppClock: Sendable {
    func now() -> Date
}

nonisolated struct SystemClock: AppClock {
    func now() -> Date {
        Date()
    }
}
