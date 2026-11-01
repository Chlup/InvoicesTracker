import AppKit
import SwiftUI

extension View {
    /// Covers a sheet while the app is locked after inactivity (`AppModel.isIdleLocked`); every sheet root has it, with
    /// the rest of the chrome of a sheet (`sheetChrome()`). A sheet cannot be hidden without losing what it holds, and
    /// the card of the lock of its window is under it, out of reach while the sheet is up. So the sheet keeps what it
    /// shows and what is typed in it under a lock of its own, which says that the app is locked and has Odemknout
    /// (`IdleLockCover`). The app model is that of the window the sheet is shown over (`RootView` puts it in the
    /// environment); a sheet shown elsewhere is shown as it is.
    func idleLockCover() -> some View {
        modifier(SheetIdleLockCover())
    }
}

/// The cover of a sheet, with the app model of its window.
private struct SheetIdleLockCover: ViewModifier {
    @Environment(AppModel.self) private var app: AppModel?

    func body(content: Content) -> some View {
        content.modifier(IdleLockCover(app: app, kind: .sheet))
    }
}

/// While the app is locked after inactivity, covers what it is applied to, which stays as it is under the cover, with
/// all that is typed in it: the content of the window under the card of the lock (`LockedView`), or a sheet under a
/// lock of its own. Under the cover nothing takes a click, a key or the focus — its views are disabled, which also
/// makes a dialog of the window let go of the focus — and VoiceOver reads the cover alone. The view that has the focus
/// gives it up as the lock comes, and has it again once the app is unlocked (`FocusUnderLock`).
struct IdleLockCover: ViewModifier {
    /// What is covered.
    enum Kind {
        /// The content of the window.
        case window

        /// A sheet over the window.
        case sheet
    }

    let app: AppModel?
    let kind: Kind

    func body(content: Content) -> some View {
        let locked = app?.isIdleLocked == true
        enabled(content, locked: locked)
            .allowsHitTesting(!locked)
            .accessibilityHidden(locked)
            .overlay {
                if locked, let app {
                    cover(of: app)
                }
            }
            .background(FocusUnderLock(app: app, isLocked: locked))
    }

    /// `content`, disabled while the app is locked. A sheet takes the environment of the window it is shown over, whose
    /// content the lock disables too, a moment apart from the sheet: so a sheet follows the lock itself, and its views
    /// are enabled again in the same update that takes its cover away.
    @ViewBuilder
    private func enabled(_ content: Content, locked: Bool) -> some View {
        switch kind {
        case .window:
            content.disabled(locked)
        case .sheet:
            content
                .environment(\.isEnabled, !locked)
                // Esc does not close it either: what is typed in it would be lost.
                .interactiveDismissDisabled(locked)
        }
    }

    @ViewBuilder
    private func cover(of app: AppModel) -> some View {
        switch kind {
        case .window:
            // Over the whole window, under the toolbar too, which the window empties under the lock.
            LockedView(model: app, kind: .inactivity)
                .background(Palette.bgWindow.ignoresSafeArea())
        case .sheet:
            SheetLock(app: app)
                // A sheet takes the environment of the window it is shown over, which the lock disables: its own lock
                // is the one thing in it that is enabled.
                .environment(\.isEnabled, true)
        }
    }
}

/// What a sheet shows while the app is locked after inactivity, over everything it holds and on its background, the
/// colour of a card: the lock, its title and Odemknout, which asks for Touch ID or the password of the Mac
/// (`AppModel.unlockAfterIdle()`) and is the default button of the sheet (Return). The text of the lock is there too
/// where the sheet is tall enough. Esc does nothing: the sheet would close with what is typed in it.
private struct SheetLock: View {
    let app: AppModel

    @State private var runner = StepRunner()

    var body: some View {
        ViewThatFits(in: .vertical) {
            lock(withText: true)
            lock(withText: false)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Palette.bgCard)
        .background(escape)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Zamčeno")
    }

    /// Esc: a button for its shortcut alone, which is not seen, clicked, reached with Tab or read by VoiceOver, and
    /// which does nothing. It takes Esc before the sheet would close by it.
    private var escape: some View {
        Button("") {}
            .keyboardShortcut(.cancelAction)
            .focusable(false)
            .opacity(0)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }

    private func lock(withText: Bool) -> some View {
        VStack(spacing: 10) {
            LockSymbol()
            Text(LockedView.title)
                .font(Typography.title2)
                .foregroundStyle(Palette.text)
                .accessibilityAddTraits(.isHeader)
            if withText {
                Text(verbatim: WelcomeTexts.idleLockText(app.appSettings.idleLock))
                    .font(Typography.body)
                    .foregroundStyle(Palette.text2)
                    .frame(maxWidth: LockedView.textWidth)
                    .fixedSize(horizontal: false, vertical: true)
            }
            UnlockButton(runner: runner) {
                await app.unlockAfterIdle()
            }
            .padding(.top, 6)
        }
        .multilineTextAlignment(.center)
    }
}

/// Which windows have the lock after inactivity over them, and whether a sheet goes without it. Every window of the app
/// and every sheet with `idleLockCover()` has a guard of the lock (`FocusUnderLock`), which notes its window here. A
/// sheet without one would show what it holds over the lock: as the lock comes, the window it is attached to stops a
/// debug build at it.
@MainActor
enum IdleLockSheets {
    /// The windows with a guard of the lock. A window that goes is forgotten.
    static let guarded = NSHashTable<NSWindow>.weakObjects()

    /// Whether `sheet`, attached to a window as the lock comes, would show what it holds over the lock: a sheet of the
    /// app's own — SwiftUI shows a sheet in a window, not in a panel — that has no guard of the lock. The panels of the
    /// system — alerts, the print panel, open and save panels — are none of these: they show no data, or the lock
    /// cancels them.
    static func isUncovered(_ sheet: NSWindow, among guarded: NSHashTable<NSWindow>) -> Bool {
        !(sheet is NSPanel) && !guarded.contains(sheet)
    }
}

/// Keeps the keyboard focus of its window off what the lock after inactivity covers. As the lock comes, the view that
/// has the focus, such as a field that is typed in, gives it up to the window, so that no key reaches it. While the
/// lock is on, a view under it that takes the focus gives it back at once: Tab reaches the list of the sidebar, which
/// stays in the loop of the Tab key though it is disabled. Once the app is unlocked, the view that had the focus has it
/// again, with what was selected in a field, unless the focus went elsewhere meanwhile.
///
/// Where the focus was is noted as the lock comes, before the window follows it: a field that the lock disables gives
/// up the focus by itself, and a sheet follows the window it is shown over, which the lock disables first.
private struct FocusUnderLock: NSViewRepresentable {
    let app: AppModel?
    let isLocked: Bool

    func makeNSView(context: Context) -> GuardView {
        let view = GuardView()
        view.app = app
        return view
    }

    func updateNSView(_ view: GuardView, context: Context) {
        view.isLocked = isLocked
    }

    final class GuardView: NSView {
        private var observation: NSKeyValueObservation?

        /// The app whose lock is followed: as it is about to come, the view that has the focus is noted. The center
        /// forgets the observation when this view goes.
        var app: AppModel? {
            didSet {
                NotificationCenter.default.removeObserver(self, name: AppModel.idleLockWillCome, object: nil)
                if let app {
                    NotificationCenter.default.addObserver(
                        self, selector: #selector(lockWillCome(_:)), name: AppModel.idleLockWillCome, object: app)
                }
            }
        }

        /// The view that had the focus when the lock came, and what was selected in it when it is a field.
        private weak var focusedView: NSView?
        private var selection: NSRange?

        /// Whether the lock is on.
        var isLocked = false {
            didSet {
                guard isLocked != oldValue else { return }
                if isLocked {
                    takeFocus()
                } else {
                    giveFocusBack()
                }
            }
        }

        /// A click goes to the views over it.
        override func hitTest(_ point: NSPoint) -> NSView? {
            nil
        }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let window {
                IdleLockSheets.guarded.add(window)
            }
            observation = window?.observe(\.firstResponder, options: [.new]) { [weak self] _, change in
                MainActor.assumeIsolated {
                    self?.focusMoved(to: change.newValue ?? nil)
                }
            }
            // A sheet that opens under the lock.
            if isLocked {
                takeFocus()
            }
        }

        /// The app is about to lock: the view that has the focus is noted while it still has it, and gives it up at
        /// once, before the window follows the lock, so that no key reaches it meanwhile. A sheet of the window without
        /// the lock over it is a mistake of the app, which a debug build stops at.
        @objc private func lockWillCome(_ notification: Notification) {
            noteFocus()
            window?.makeFirstResponder(nil)
            if let sheet = window?.attachedSheet, IdleLockSheets.isUncovered(sheet, among: IdleLockSheets.guarded) {
                assertionFailure("A sheet is shown without idleLockCover(): it would show what it holds over the lock.")
            }
        }

        /// Notes the view that has the focus, and what is selected in it when it is a field that is typed in.
        private func noteFocus() {
            guard let window else { return }
            let responder = window.firstResponder
            if let editor = responder as? NSTextView, editor.isFieldEditor {
                focusedView = editor.delegate as? NSView
                selection = editor.selectedRange()
            } else {
                focusedView = responder as? NSView
                selection = nil
            }
        }

        /// The view that has the focus gives it up to the window, which the lock keeps until it is unlocked.
        private func takeFocus() {
            guard let window else { return }
            if focusedView == nil {
                noteFocus()
            }
            window.makeFirstResponder(nil)
        }

        /// The view that had the focus has it again, once the views under the cover are enabled again, which SwiftUI
        /// does in the update that unlocks: unless the focus went elsewhere meanwhile, or the view is gone. A field
        /// gets back what was selected in it, or else the insertion point at the end of its text, never all of it
        /// selected: a key typed then would replace it.
        private func giveFocusBack() {
            guard let view = focusedView else { return }
            let range = selection
            focusedView = nil
            selection = nil
            DispatchQueue.main.async { [weak self] in
                guard let self, !isLocked, let window, view.window === window, window.firstResponder === window,
                    window.makeFirstResponder(view),
                    let editor = (view as? NSTextField)?.currentEditor() as? NSTextView
                else { return }
                let length = (editor.string as NSString).length
                if let range, NSMaxRange(range) <= length {
                    editor.setSelectedRange(range)
                } else {
                    editor.setSelectedRange(NSRange(location: length, length: 0))
                }
            }
        }

        /// While the lock is on, a view under it that took the focus gives it back to the window, once the change of
        /// the focus that is being told is over.
        private func focusMoved(to responder: NSResponder?) {
            guard isLocked, let responder, Self.isUnderTheLock(responder) else { return }
            DispatchQueue.main.async { [weak self] in
                guard let self, isLocked, let window, let current = window.firstResponder, Self.isUnderTheLock(current)
                else { return }
                window.makeFirstResponder(nil)
            }
        }

        /// Whether `responder` is a view under the lock, which has nothing that takes the focus but its buttons: a
        /// field that is typed in, a list, or a control that the lock disabled.
        private static func isUnderTheLock(_ responder: NSResponder) -> Bool {
            if let editor = responder as? NSTextView, editor.isFieldEditor {
                return true
            }
            if responder is NSTableView {
                return true
            }
            if let control = responder as? NSControl {
                return !control.isEnabled
            }
            return false
        }
    }
}
