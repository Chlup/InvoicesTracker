import AppKit

/// The window the tests show the app and its views in. It can be closed to the pointer of the person who runs the
/// tests, which a test needs where it moves the pointer by hand (`movePointer(to:in:)`); made like `NSWindow` makes it
/// (`init(contentViewController:)`), a window that is not closed is the window it was before.
///
/// SwiftUI decides whether it takes the pointer to be inside a view when it makes the area it follows the pointer in,
/// from where the window says the pointer is then, and afterwards only by the events that name the area, which AppKit
/// hands the window for its views. In an ordinary window both are the real pointer's, that of the person who runs the
/// tests: where it is when the area is made, and its own coming and going over the window while a test runs, which
/// would take away what the test has opened, or open what it has not. A window that is closed to the real pointer
/// (`closeToTheRealPointer()`) takes no event of the real mouse (`NSWindow.ignoresMouseEvents`), passes no event of the
/// pointer that reaches it all the same on to its views (`sendEvent(_:)`) and says for itself where its pointer is, so
/// the real pointer cannot change what the test has opened. The test hands the events of its own pointer to the view
/// itself (`movePointer(to:in:)`).
@MainActor
final class TestWindow: NSWindow {
    /// Where a window closed to the real pointer has its pointer until a test moves it: in the corner of the window,
    /// over nothing that reacts to the pointer, and inside the content.
    static let restingPointer = CGPoint(x: 4, y: 4)

    /// The events by which AppKit tells the views of a window about the pointer: the pointer coming into the area of
    /// a view or leaving it, moving, and the cursor to show over a view.
    private static let eventsOfThePointer: Set<NSEvent.EventType> = [
        .mouseEntered, .mouseExited, .mouseMoved, .cursorUpdate,
    ]

    /// Where the window says its pointer is, in the coordinates of the window with the origin at its bottom left, or
    /// nil while it says where the real pointer is.
    private(set) var pointer: CGPoint?

    /// Whether the window is closed to the real pointer.
    var isClosedToTheRealPointer: Bool {
        ignoresMouseEvents && pointer != nil
    }

    /// Closes the window to the real pointer: it takes no event of the real mouse, passes no event of the pointer on
    /// to its views and says its pointer is in the corner (`restingPointer`). Once the window is shown,
    /// `makeTheAreasOfThePointerAnew()` has its views make their areas anew with that pointer, as a precaution.
    func closeToTheRealPointer() {
        ignoresMouseEvents = true
        pointer = Self.restingPointer
    }

    /// Passes `event` on to the views of the window, as AppKit hands it to the window, except for an event of the
    /// pointer (`eventsOfThePointer`) while the window is closed to the real pointer. Such an event can only be the
    /// real pointer's, as a test hands the events of its own pointer to the view itself (`movePointer(to:in:)`), and it
    /// would change what the test has opened: the real pointer leaving the area of a view takes away what the pointer
    /// of the test has opened there, and SwiftUI then takes the pointer to be outside; the real pointer coming in
    /// opens what the test has not.
    override func sendEvent(_ event: NSEvent) {
        if isClosedToTheRealPointer, Self.eventsOfThePointer.contains(event.type) {
            return
        }
        super.sendEvent(event)
    }

    /// Says that the pointer of the window is at `point`, given in the coordinates of the window, as the pointer is
    /// when a test moves it there (`movePointer(to:in:)`).
    func putPointer(at point: CGPoint) {
        pointer = point
    }

    /// Takes the content of the window out and puts it back, once the window is on the screen and laid out, so that
    /// SwiftUI makes the areas it follows the pointer in anew: for the views as large as they are and, while the
    /// window is closed to the real pointer, with the pointer of the window. SwiftUI makes the area of a view as the
    /// view comes to the window, or later, when the view first shows something that follows the pointer, and decides
    /// then, from where the window says the pointer is, whether it takes the pointer to be inside; a view that comes to
    /// the window before it has its size, as every view hosted alone does and the columns of the window of the app do
    /// now and then, takes the pointer to be outside it. This is a precaution: a move of the test brings the pointer
    /// into the area by itself, whatever SwiftUI took it to be (`movePointer(to:in:)`).
    ///
    /// The window is what it was after it: it has the same content view controller, the hosting controller that the
    /// window of the app has for its content, in the same view, and the same frame. Assigning the content view of a
    /// window drops its controller, so the controller is set again. The content does leave the window and come back to
    /// it once, though: its views disappear and appear again, and the task of a view is cancelled and started anew. So
    /// a test calls this before it opens anything in the window, as `withAppWindow(of:size:ignoringTheRealPointer:_:)`
    /// does, and not after.
    func makeTheAreasOfThePointerAnew() async throws {
        guard let content = contentView else { return }
        let controller = contentViewController
        let originalFrame = frame
        try await layOut(self)
        contentView = NSView()
        try await layOut(self)
        if let controller {
            contentViewController = controller
        } else {
            contentView = content
        }
        if frame != originalFrame {
            setFrame(originalFrame, display: true)
        }
        try await layOut(self)
    }

    /// Where the pointer is, in the coordinates of the window: the pointer of the window while it is closed to the
    /// real one, otherwise the real pointer.
    override var mouseLocationOutsideOfEventStream: NSPoint {
        pointer ?? super.mouseLocationOutsideOfEventStream
    }
}
