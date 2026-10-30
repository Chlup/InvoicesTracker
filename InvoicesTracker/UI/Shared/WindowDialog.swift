import AppKit
import SwiftUI

/// The confirmations that the window asks itself, such as the deletion of an invoice, are dialogs inside the window
/// (`windowDialog(item:title:content:)`): a card over the sidebar and the page, under the toolbar, where a sheet would
/// drop from under the toolbar on glass that takes the colours of what is behind it.
enum WindowDialog {
    /// The identifier of the card, which the tests find it by.
    static let accessibilityID = "windowDialog"

    /// What dims the sidebar and the page under the card: rgba(28, 28, 34, 0.32).
    static let dimming = Color(.sRGB, red: 28 / 255, green: 28 / 255, blue: 34 / 255, opacity: 0.32)

    /// The hairline along the edge of the card: rgba(0, 0, 0, 0.18), and white of the same strength in a dark window,
    /// where the card is as dark as the page under it and black would not show.
    static let hairline = Color(
        nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
                ? NSColor(white: 1, alpha: 0.18) : NSColor(white: 0, alpha: 0.18)
        })
}

extension View {
    /// Shows `content` for `item`, while it is not nil, in a dialog inside the window: a card at most 520 points wide,
    /// centred 48 points under the toolbar, opaque, over the sidebar and the page. These are dimmed and take no click
    /// and no key meanwhile, the keyboard focus stays in the card (`FocusKeeper`), and VoiceOver reads the card alone,
    /// named by `title`, the title of the content for `item`. Esc sets `item` to nil, which is what the Zrušit of the
    /// content does. The toolbar is in the title bar, which no view of the window covers.
    ///
    /// It is applied to the content of the window (`RootView`), never as a sheet; an overlay that the window puts above
    /// it covers it. Such an overlay disables what it covers, the dialog with it, and the dialog then leaves the focus
    /// alone: the overlay has it.
    func windowDialog<Item: Identifiable, Content: View>(
        item: Binding<Item?>, title: @escaping (Item) -> String, @ViewBuilder content: @escaping (Item) -> Content
    ) -> some View {
        modifier(WindowDialogModifier(item: item, title: title, dialog: content))
    }
}

private struct WindowDialogModifier<Item: Identifiable, Dialog: View>: ViewModifier {
    @Binding var item: Item?
    let title: (Item) -> String
    let dialog: (Item) -> Dialog

    func body(content: Content) -> some View {
        content
            .disabled(item != nil)
            .accessibilityHidden(item != nil)
            .overlay {
                if let item {
                    WindowDialogCard(title: title(item), close: { self.item = nil }) {
                        dialog(item)
                    }
                    // Another item is another dialog, with nothing typed in it.
                    .id(item.id)
                }
            }
    }
}

/// The dimming over the content of the window, and the card of the dialog on it.
private struct WindowDialogCard<Dialog: View>: View {
    /// What VoiceOver names the card by: the title of the dialog.
    let title: String

    /// Esc.
    let close: () -> Void
    @ViewBuilder let dialog: Dialog

    private let shape = RoundedRectangle(cornerRadius: 22)

    var body: some View {
        ZStack(alignment: .top) {
            WindowDialog.dimming
                .ignoresSafeArea()
                .accessibilityHidden(true)
            card
                .padding(.top, 48)
                .padding(.horizontal, 16)
        }
    }

    private var card: some View {
        dialog
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 22)
            .padding(.horizontal, 24)
            .padding(.bottom, 20)
            .frame(maxWidth: 520)
            .background {
                // The shadow is the card's alone, not one of every text on it.
                shape
                    .fill(Color(nsColor: .windowBackgroundColor))
                    .shadow(color: .black.opacity(0.28), radius: 30, y: 24)
            }
            .overlay(shape.strokeBorder(WindowDialog.hairline, lineWidth: 0.5))
            .background(escape)
            .background(FocusKeeper())
            .accessibilityElement(children: .contain)
            .accessibilityLabel(Text(verbatim: title))
            .accessibilityAddTraits(.isModal)
            .accessibilityIdentifier(WindowDialog.accessibilityID)
    }

    /// Esc: a button for its shortcut alone, which is not seen, clicked, reached with Tab or read by VoiceOver.
    private var escape: some View {
        Button("", action: close)
            .keyboardShortcut(.cancelAction)
            .focusable(false)
            .opacity(0)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

/// Keeps the keyboard focus of the window in the card it is the background of. The views behind the card are disabled,
/// but the list of the sidebar stays in the loop of the Tab key all the same: when the focus goes to a view behind the
/// card, it goes back to the view of the card that had it last, or, when none had it, to the window, so that no view
/// behind the card has it. A view that the focus is in when the card comes loses it in the same way.
///
/// It keeps the focus only while the card is enabled. A layer that the window puts over the dialog, such as a lock,
/// disables the dialog under it, and the focus is then the layer's to give.
private struct FocusKeeper: NSViewRepresentable {
    func makeNSView(context: Context) -> KeeperView {
        let view = KeeperView()
        view.keepsFocus = context.environment.isEnabled
        return view
    }

    func updateNSView(_ view: KeeperView, context: Context) {
        view.keepsFocus = context.environment.isEnabled
    }

    final class KeeperView: NSView {
        private var observation: NSKeyValueObservation?

        /// The view of the card that had the focus last.
        private weak var focusedInCard: NSView?

        /// Whether the focus is kept in the card: while the card is enabled. Once it is again, a focus that was left
        /// behind the card meanwhile is sent back.
        var keepsFocus = true {
            didSet {
                if keepsFocus, !oldValue {
                    focusMoved(to: window?.firstResponder)
                }
            }
        }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            observation = window?.observe(\.firstResponder, options: [.new]) { [weak self] _, change in
                MainActor.assumeIsolated {
                    self?.focusMoved(to: change.newValue ?? nil)
                }
            }
            // Once the card is laid out where it stays.
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                focusMoved(to: window?.firstResponder)
            }
        }

        /// Notes the view of the card that `responder` stands for, or sends the focus back when `responder` is behind
        /// the card. Does nothing while the focus is not kept.
        private func focusMoved(to responder: NSResponder?) {
            guard keepsFocus, let window, let view = focusedView(of: responder, in: window) else { return }
            if isBehindTheCard(view) {
                sendFocusBack(in: window)
            } else if isInTheCard(view) {
                focusedInCard = view
            }
        }

        /// Sends the focus of `window` back to the view of the card that had it last, or to the window: once the change
        /// of the focus that is being told is over, and only if the card is still in `window`, still keeps the focus,
        /// and the focus is still behind it then. A focus that has come back into the card meanwhile stays where it is.
        private func sendFocusBack(in window: NSWindow) {
            DispatchQueue.main.async { [weak self] in
                guard let self, keepsFocus, self.window === window,
                    let view = focusedView(of: window.firstResponder, in: window), isBehindTheCard(view)
                else { return }
                window.makeFirstResponder(focusedInCard?.window === window ? focusedInCard : nil)
            }
        }

        /// The view of `window` that `responder` stands for, or nil when it stands for none, such as the window itself.
        private func focusedView(of responder: NSResponder?, in window: NSWindow) -> NSView? {
            guard let responder, let view = Self.view(of: responder), view.window === window else { return nil }
            return view
        }

        /// Whether `view` is behind the card: a control that is disabled, as every control behind the card is,
        /// wherever it lies under it, or a view that is neither within the card nor around it, as the view that hosts
        /// the whole content of the window is.
        private func isBehindTheCard(_ view: NSView) -> Bool {
            if let control = view as? NSControl, !control.isEnabled {
                return true
            }
            let frame = view.convert(view.bounds, to: nil)
            return !card.contains(frame) && !frame.contains(card)
        }

        /// Whether `view` is a view of the card, which takes the focus: within it, and not this view.
        private func isInTheCard(_ view: NSView) -> Bool {
            view !== self && card.contains(view.convert(view.bounds, to: nil))
        }

        /// The frame of the card in the window.
        private var card: CGRect {
            convert(bounds, to: nil)
        }

        /// The view that `responder` stands for: the text field that a field editor edits, or `responder` itself.
        private static func view(of responder: NSResponder) -> NSView? {
            if let editor = responder as? NSTextView, editor.isFieldEditor {
                return editor.delegate as? NSView
            }
            return responder as? NSView
        }
    }
}
