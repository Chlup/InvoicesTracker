import Dispatch
import Foundation

/// A timer that has been set. Cancelling it keeps it from firing; cancelling it again, or after it fired, does
/// nothing.
nonisolated protocol RefreshCancellable: Sendable {
    func cancel()
}

/// Sets the timer of the refresh. The coordinator keeps one timer at a time and cancels it before it sets the next, so
/// the scheduler itself keeps nothing.
nonisolated protocol RefreshScheduler: Sendable {
    /// Calls `fire` once at `date`, or up to `tolerance` seconds later, on a queue of its choice. A date that has
    /// passed fires at once.
    func schedule(
        at date: Date, tolerance: TimeInterval, _ fire: @escaping @Sendable () -> Void
    ) -> any RefreshCancellable
}

/// The scheduler of the app: a dispatch timer on a queue of utility priority. Its deadline is a time of the wall clock,
/// so a sleep of the Mac does not push it back and a change of the clock moves it with the clock. Its leeway is the
/// tolerance, which lets the system fire it together with other work.
nonisolated struct TimerScheduler: RefreshScheduler {
    func schedule(
        at date: Date, tolerance: TimeInterval, _ fire: @escaping @Sendable () -> Void
    ) -> any RefreshCancellable {
        let source = DispatchSource.makeTimerSource(queue: DispatchQueue.global(qos: .utility))
        source.schedule(wallDeadline: Self.wallTime(date), repeating: .never, leeway: Self.leeway(tolerance))
        source.setEventHandler(handler: fire)
        source.activate()
        return DispatchTimer(source: source)
    }

    /// `date` as a time of the wall clock.
    private static func wallTime(_ date: Date) -> DispatchWallTime {
        let seconds = date.timeIntervalSince1970
        let whole = seconds.rounded(.down)
        return DispatchWallTime(timespec: timespec(tv_sec: Int(whole), tv_nsec: Int((seconds - whole) * 1_000_000_000)))
    }

    private static func leeway(_ tolerance: TimeInterval) -> DispatchTimeInterval {
        .nanoseconds(Int(max(0, tolerance) * 1_000_000_000))
    }
}

/// A dispatch timer that `TimerScheduler` set. It stays set as long as this is kept, and is cancelled when this is
/// released.
private nonisolated final class DispatchTimer: RefreshCancellable {
    private let source: any DispatchSourceTimer

    init(source: any DispatchSourceTimer) {
        self.source = source
    }

    deinit {
        source.cancel()
    }

    func cancel() {
        source.cancel()
    }
}
