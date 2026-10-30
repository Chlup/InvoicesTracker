import AppKit
import SwiftUI

extension View {
    /// Calls `action` whenever a text field of the window this view is in ends its editing: the person left it with
    /// Tab or Return, or clicked elsewhere. This is where the field itself ends the editing, so it does not wait for
    /// SwiftUI to notice the change of focus, and a field of another window does not call it. A form that saves what
    /// is typed a moment after the last key saves here at once.
    func onTextFieldEditingEnded(_ action: @escaping () -> Void) -> some View {
        modifier(TextFieldEditingEnd(action: action))
    }
}

private struct TextFieldEditingEnd: ViewModifier {
    let action: () -> Void

    /// The window the view is in, which tells its own fields from those of other windows.
    @State private var home = WindowHolder()

    func body(content: Content) -> some View {
        content
            .background(WindowReader { home.window = $0 })
            .onReceive(NotificationCenter.default.publisher(for: NSControl.textDidEndEditingNotification)) { note in
                guard let field = note.object as? NSControl, let window = home.window, field.window === window else {
                    return
                }
                action()
            }
    }
}

/// The window a view is in, held weakly: the window holds the view, and the view must not hold the window back.
private final class WindowHolder {
    weak var window: NSWindow?
}

/// Tells the window its view is in, once it is in one and whenever it moves to another.
private struct WindowReader: NSViewRepresentable {
    let didChange: (NSWindow?) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = TrackingView()
        view.didChange = didChange
        return view
    }

    func updateNSView(_ view: NSView, context: Context) {
        (view as? TrackingView)?.didChange = didChange
    }

    private final class TrackingView: NSView {
        var didChange: (NSWindow?) -> Void = { _ in }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            // Not in the middle of the update that put the view there.
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                didChange(window)
            }
        }
    }
}
