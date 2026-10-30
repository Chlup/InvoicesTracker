import AppKit

/// The menus of the app that are open: each from the beginning of its tracking to its end
/// (`NSMenu.didBeginTrackingNotification`, `didEndTrackingNotification`), whichever menu it is — one of the toolbar, of
/// a picker on a page, of the menu bar — and a submenu within it. The lock after inactivity closes them without
/// choosing anything (`AppModel.closeOpenMenu`): a menu stays above the lock, with what it lists, the years with data
/// say, and a choice in it would act under the lock.
@MainActor
final class OpenMenu: NSObject {
    /// The menus of the app, followed from its launch (`AppDelegate`).
    static let shared = OpenMenu(center: NotificationCenter.default)

    /// A menu that is open, which this does not keep alive.
    private struct Tracked {
        weak var menu: NSMenu?
    }

    /// Where the menus tell of their tracking: the default center, or a test's own.
    private let center: NotificationCenter

    /// The menus that are open, the outermost first.
    private var menus: [Tracked] = []

    init(center: NotificationCenter) {
        self.center = center
    }

    /// Whether the menus are followed.
    private(set) var isFollowing = false

    /// Starts following the menus. Starting again does nothing. The center tells of them on the main thread, where
    /// the menus are tracked, and forgets this when it goes.
    func follow() {
        guard !isFollowing else { return }
        isFollowing = true
        center.addObserver(self, selector: #selector(began(_:)), name: NSMenu.didBeginTrackingNotification, object: nil)
        center.addObserver(self, selector: #selector(ended(_:)), name: NSMenu.didEndTrackingNotification, object: nil)
    }

    /// Closes the menus that are open, the innermost first, as a click outside them does: nothing in them is chosen.
    /// Does nothing while none is.
    func close() {
        for tracked in menus.reversed() {
            tracked.menu?.cancelTrackingWithoutAnimation()
        }
    }

    @objc private func began(_ notification: Notification) {
        guard let menu = notification.object as? NSMenu else { return }
        menus.removeAll { $0.menu == nil || $0.menu === menu }
        menus.append(Tracked(menu: menu))
    }

    @objc private func ended(_ notification: Notification) {
        let menu = notification.object as? NSMenu
        menus.removeAll { $0.menu == nil || $0.menu === menu }
    }
}
