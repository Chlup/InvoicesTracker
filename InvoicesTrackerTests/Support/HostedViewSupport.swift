import AppKit
import SwiftUI
import Testing

/// Shows `view` alone in a window, laid out, and gives the window to `body`; closes it afterwards. The window is the
/// kind a sheet or a card is shown in, `size` points of content. Like the window of the app (`withAppWindow`), it is
/// never a tab of another window, so it keeps its size while the windows of other tests change theirs. A field of
/// `view` can take the focus as the window shows it, as the field of a recovery code does, and with the focus the field
/// editor that the fields of all windows share. So the window is shown and closed in the turn of the test to type into
/// a window (`whileTypingAlone(_:)`).
@MainActor
func withHostedView<Content: View>(
    _ view: Content, size: CGSize = CGSize(width: 900, height: 700), _ body: (NSWindow) async throws -> Void
) async throws {
    try await whileTypingAlone {
        let controller = NSHostingController(rootView: view)
        let window = NSWindow(contentViewController: controller)
        window.styleMask = [.titled, .closable, .resizable]
        window.tabbingMode = .disallowed
        window.setContentSize(size)
        window.makeKeyAndOrderFront(nil)
        defer { window.close() }
        try await layOut(window)
        try await body(window)
    }
}

/// The keys a test presses, with what the key types and the code of the key.
enum PressedKey {
    case escape
    case `return`

    fileprivate var characters: String {
        switch self {
        case .escape: "\u{1b}"
        case .return: "\r"
        }
    }

    fileprivate var keyCode: UInt16 {
        switch self {
        case .escape: 53
        case .return: 36
        }
    }
}

/// Presses `key` in `window` as a person does, so that it is the real shortcuts of the buttons that answer it: returns
/// whether a shortcut took it. A key that nothing takes is no error; it is what the test looks at.
@MainActor
func press(_ key: PressedKey, in window: NSWindow) throws -> Bool {
    let event = try #require(
        NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: window.windowNumber, context: nil, characters: key.characters,
            charactersIgnoringModifiers: key.characters, isARepeat: false, keyCode: key.keyCode))
    return window.performKeyEquivalent(with: event)
}
