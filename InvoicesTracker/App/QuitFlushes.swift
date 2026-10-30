import Foundation

/// The model of a screen that saves what the person types a moment after the last key, and so may hold input that no
/// save has taken yet when the app is quit.
@MainActor
protocol SavesTypedInput: AnyObject {
    /// Whether something typed or changed is not written yet: a text that waits for the typing to stop, a change that
    /// waits to be saved, or a save that runs.
    var hasUnsavedInput: Bool { get }

    /// Reads what was typed and saves it, and returns when it is written.
    func saveNow() async
}

/// What a quit waits for: the models of the screens that save typed input after a delay. A screen registers its model
/// once it has loaded (`register(_:)`), and a quit that finds input in any of them saves it before the app goes
/// (`flush(within:sleep:)`), as a text typed less than a moment before ⌘Q would be lost otherwise.
@MainActor
final class QuitFlushes {
    /// A registered model, held weakly: a screen that is gone saved what it had when it was left.
    private struct Entry {
        weak var saver: (any SavesTypedInput)?
    }

    private var entries: [Entry] = []

    /// Registers `saver`. A model that is registered already is not registered again.
    func register(_ saver: some SavesTypedInput) {
        entries.removeAll { $0.saver == nil }
        guard !entries.contains(where: { $0.saver === saver }) else { return }
        entries.append(Entry(saver: saver))
    }

    /// Whether any registered screen holds input that is not saved.
    var hasUnsavedInput: Bool {
        savers.contains { $0.hasUnsavedInput }
    }

    /// Saves the input of every registered screen that holds some, and returns when it is written, or when `limit` has
    /// run out, which `sleep` waits for: a save that hangs (a backup that follows it, on a disk that is gone) cannot
    /// keep the app from quitting. What is not written by then is lost, as a quit that was not waited for would lose
    /// it.
    func flush(within limit: Duration, sleep: @escaping @Sendable (Duration) async throws -> Void) async {
        let waiting = savers.filter(\.hasUnsavedInput)
        guard !waiting.isEmpty else { return }
        _ = await BoundedWait.result(
            of: {
                for saver in waiting {
                    await saver.saveNow()
                }
            }, within: limit, sleep: sleep)
    }

    /// The registered models that are still there.
    private var savers: [any SavesTypedInput] {
        entries.compactMap(\.saver)
    }
}

extension AppModel {
    /// How long a quit waits for the input of the screens to be saved.
    static let quitFlushLimit = Duration.seconds(3)

    /// Whether a screen holds input that is not saved: a quit has to wait for it (`flushUnsavedInput()`).
    var hasUnsavedInput: Bool {
        quitFlushes.hasUnsavedInput
    }

    /// Saves what the screens hold of the typed input, at most `quitFlushLimit`, for a quit to go on.
    func flushUnsavedInput() async {
        await quitFlushes.flush(within: Self.quitFlushLimit, sleep: dependencies.sleep)
    }
}
