import AppKit

/// The delegate of the app, for what SwiftUI has no scene hook for: a quit that has to ask first, and to wait, and the
/// menus followed from the launch. Closing the window asks nothing, as the invoice that is being written is kept by the
/// app (`AppModel.editor`) and is there when the window is opened again.
final class AppDelegate: NSObject, NSApplicationDelegate {
    /// The model of the app, which the window gives it when it shows.
    weak var model: AppModel?

    /// Asks "Zahodit rozepsanou fakturu?": true to discard. A test replaces it.
    var asksToDiscard: @MainActor () -> Bool = { DiscardQuestion.ask() }

    /// Tells the application that the quit may go on, once the typed input is saved. A test replaces it.
    var replyToQuit: @MainActor (Bool) -> Void = { NSApplication.shared.reply(toApplicationShouldTerminate: $0) }

    /// The saving of the typed input that a quit waits for, until it is over and the application is told.
    private(set) var flush: Task<Void, Never>?

    /// Follows the menus of the app from its launch, so that the lock after inactivity can close one that is open
    /// (`OpenMenu`).
    func applicationDidFinishLaunching(_ notification: Notification) {
        OpenMenu.shared.follow()
    }

    /// A quit with something typed in the invoice editor that is not saved asks first, and goes on only when the person
    /// says to discard it. A quit with text typed in a screen that saves a moment after the last key waits for it to be
    /// saved (`AppModel.flushUnsavedInput()`, at most a few seconds), and then goes on. A second quit while the first
    /// one waits for that asks nothing and starts no other saving: the quit is going on already.
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let model else { return .terminateNow }
        guard flush == nil else { return .terminateLater }
        if model.editorHasChanges, !asksToDiscard() {
            return .terminateCancel
        }
        guard model.hasUnsavedInput else { return .terminateNow }
        flush = Task {
            await model.flushUnsavedInput()
            flush = nil
            replyToQuit(true)
        }
        return .terminateLater
    }
}
