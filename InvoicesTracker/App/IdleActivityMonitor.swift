import AppKit

/// Tells the app model of every activity of the person in the app's windows — a move of the pointer, a click, a drag, a
/// scroll, a key that is pressed, a gesture on the trackpad — so that the lock after inactivity counts from the latest
/// one, at the time of the app's clock (`AppModel.noteActivity(at:)`). It watches the events the app itself dispatches,
/// in all of its windows (a local monitor of NSEvent), never those of other apps, and lets them go on. The window
/// starts it when it shows and stops it when it goes.
@MainActor
final class IdleActivityMonitor {
    /// The events that are activity.
    static let activityEvents: NSEvent.EventTypeMask = [
        .mouseMoved, .leftMouseDown, .rightMouseDown, .otherMouseDown, .leftMouseDragged, .rightMouseDragged,
        .otherMouseDragged, .scrollWheel, .keyDown, .magnify, .smartMagnify, .rotate, .swipe,
    ]

    private let app: AppModel

    /// What NSEvent gave for the monitor while it watches, to remove it with.
    private var monitor: Any?

    init(app: AppModel) {
        self.app = app
    }

    isolated deinit {
        stop()
    }

    /// Whether it watches the events.
    var isRunning: Bool {
        monitor != nil
    }

    /// Starts watching the events. Starting it again while it watches does nothing.
    func start() {
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: Self.activityEvents) { [weak self] event in
            guard let self else { return event }
            return handle(event)
        }
    }

    /// Stops watching the events.
    func stop() {
        guard let monitor else { return }
        NSEvent.removeMonitor(monitor)
        self.monitor = nil
    }

    /// Notes `event` as activity and lets it go on unchanged; only the event that finds the time without activity up
    /// goes no further. It locks the app (`AppModel.noteActivity(at:)`), and it was meant for what the lock now hides:
    /// a click on a button, a key typed into a field.
    func handle(_ event: NSEvent) -> NSEvent? {
        let wasLocked = app.isIdleLocked
        app.noteActivity(at: app.dependencies.clock.now())
        return !wasLocked && app.isIdleLocked ? nil : event
    }

    /// Whether an open or save panel of the system is up now (`panelIsUp(modalWindow:windows:)`): the lock after
    /// inactivity does not come while one is.
    static func modalPanelIsUp() -> Bool {
        panelIsUp(modalWindow: NSApp.modalWindow, windows: NSApp.windows)
    }

    /// Whether an open or save panel is up, when `modalWindow` is the app-modal window, if any, and `windows` the
    /// windows of the app: one run with `runModal()`, or one on screen as a sheet of a window, as `fileImporter` shows
    /// it. A panel that is not on screen, such as one that was closed, holds nothing off. An open panel is a save panel
    /// too. An alert is no such panel: the app locks under it, the alert stays in front, and neither of its answers
    /// shows anything.
    static func panelIsUp(modalWindow: NSWindow?, windows: [NSWindow]) -> Bool {
        modalWindow is NSSavePanel || windows.contains { $0.isVisible && $0 is NSSavePanel }
    }
}
