import Foundation

/// The wait before a save of a screen that saves what is typed a moment after the last key (Zálohy a odpočty,
/// Nastavení › Moje údaje). Every key starts the wait again (`restart(after:then:)`), so a text typed key by key is
/// read once the typing has stopped; when the wait has run out, the save it was started with runs. A save made sooner
/// (Return, leaving the field or the screen, another year) stops the wait first (`cancel()`), as that save takes what
/// the wait would have.
@MainActor
final class DebounceTimer {
    /// How the delay is waited out. A test replaces it with a wait that it ends itself.
    typealias Wait = @Sendable (Duration) async throws -> Void

    private let wait: Wait

    /// The wait that runs, if one does. There is never more than one.
    private var timer: Task<Void, Never>?

    init(wait: @escaping Wait) {
        self.wait = wait
    }

    /// Starts the wait again, in place of the one that runs, and runs `save` when `delay` is over. No delay at all is
    /// no wait: `save` runs as soon as the task can.
    func restart(after delay: Duration, then save: @escaping @MainActor () async -> Void) {
        timer?.cancel()
        timer = Task {
            if delay > .zero {
                do {
                    try await wait(delay)
                } catch {
                    // The wait was started again, or a save is made now: that one saves.
                    return
                }
            }
            // The wait can end although the timer was replaced, when it had run out as the next key came: the timer
            // that replaced it saves, and this one must neither read the text nor take the place of that one.
            guard !Task.isCancelled else { return }
            timer = nil
            await save()
        }
    }

    /// Stops the wait that runs, if one does, without its save.
    func cancel() {
        timer?.cancel()
        timer = nil
    }
}
