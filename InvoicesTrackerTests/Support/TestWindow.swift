import AppKit

/// The window the tests show the app and its views in. It can be closed to the pointer of the person who runs the
/// tests, which a test needs where it moves the pointer by hand (`movePointer(to:in:)`).
///
/// SwiftUI follows the pointer in a window only while it takes the pointer to be inside the window, and it takes
/// that from the window: it asks where the pointer is when it makes the area it follows the pointer in. So a hover
/// that a test brings about with events of its own works only while the real pointer happens to be over the window,
/// and not when the person has it somewhere else on the screen or is moving it over the window while the test runs.
/// A window that is closed to the real pointer takes no event of the real mouse (`NSWindow.ignoresMouseEvents`) and
/// says for itself where its pointer is, and the real one cannot change what the test has opened. The window is closed
/// as it is made, before its content is attached, because the area is made as the content comes to the window.
@MainActor
final class TestWindow: NSWindow {
    /// Where a window closed to the real pointer has its pointer until a test moves it: in the corner of the window,
    /// over nothing that reacts to the pointer, and inside the content.
    static let restingPointer = CGPoint(x: 4, y: 4)

    /// Where the window says its pointer is, in the coordinates of the window with the origin at its bottom left, or
    /// nil while it says where the real pointer is.
    private(set) var pointer: CGPoint?

    /// A window that shows `content`, closed to the real pointer when `isClosedToTheRealPointer` is true: it takes no
    /// event of the real mouse and says its pointer is in the corner (`restingPointer`). The window is made as
    /// `NSWindow(contentViewController:)` makes it, and the caller sets the rest.
    init(content: NSViewController, isClosedToTheRealPointer: Bool = false) {
        super.init(
            contentRect: .zero, styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered,
            defer: true)
        // The window is owned by the test: AppKit must not release it a second time when it is closed.
        isReleasedWhenClosed = false
        if isClosedToTheRealPointer {
            ignoresMouseEvents = true
            pointer = Self.restingPointer
        }
        contentViewController = content
    }

    /// Whether the window is closed to the real pointer.
    var isClosedToTheRealPointer: Bool {
        ignoresMouseEvents && pointer != nil
    }

    /// Says that the pointer of the window is at `point`, given in the coordinates of the window, as the pointer is
    /// when a test moves it there (`movePointer(to:in:)`).
    func putPointer(at point: CGPoint) {
        pointer = point
    }

    /// Takes the content of the window out and puts it back, once the window is on the screen and laid out. SwiftUI
    /// makes the area it follows the pointer in once, as a view comes to the window, and takes the pointer to be inside
    /// it only if the pointer is inside the view as large as the view is then. A view that comes to the window before
    /// it has its size, as every view hosted alone does and the columns of the window of the app do now and then,
    /// would never take the pointer to be inside it, whatever the window says. With the content back, the areas are
    /// made anew for the views as large as they are.
    func makeTheAreasOfThePointerAnew() async throws {
        guard let content = contentView else { return }
        try await layOut(self)
        contentView = NSView()
        try await layOut(self)
        contentView = content
        try await layOut(self)
    }

    /// Where the pointer is, in the coordinates of the window: the pointer of the window while it is closed to the
    /// real one, otherwise the real pointer.
    override var mouseLocationOutsideOfEventStream: NSPoint {
        pointer ?? super.mouseLocationOutsideOfEventStream
    }
}
