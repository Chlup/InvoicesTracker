import AppKit
import SwiftUI

/// The question asked before the invoice that is being written is thrown away: by a choice in the chooser, by an
/// invoice that is opened in its place, by a restore of a backup, and by a quit. The window asks it in a dialog inside
/// itself (`discardQuestion(of:)`); the chooser and the sheet of a restore ask it for their own choices, in a box of
/// the sheet (`DiscardQuestionBox`), as the window cannot ask over a sheet; a quit asks in an alert of its own.
enum DiscardQuestion {
    static let title = "Zahodit rozepsanou fakturu?"
    static let discard = "Zahodit"
    static let keepEditing = "Pokračovat v úpravách"

    /// Asks in an alert of its own, as a quit has no window to ask in: true to discard. The safe answer, "Pokračovat
    /// v úpravách", is the one that Return gives.
    static func ask() -> Bool {
        let alert = NSAlert()
        alert.messageText = title
        alert.addButton(withTitle: keepEditing)
        let discardButton = alert.addButton(withTitle: discard)
        discardButton.hasDestructiveAction = true
        return alert.runModal() == .alertSecondButtonReturn
    }

    /// Whether the chooser asks the question, for its own choice, while it is open (`AppModel.pendingDiscard`).
    static func isAskedByChooser(_ app: AppModel) -> Bool {
        guard let cause = app.pendingDiscard, cause != .restoreBackup else { return false }
        return app.editorRequest == .chooser
    }

    /// The choice that waits for the answer while the window asks the question, or nil: the chooser's and the
    /// restore's are asked in their sheets. Closing the dialog (Esc) is Pokračovat v úpravách.
    fileprivate static func askedByWindow(_ app: AppModel) -> Binding<DiscardCause?> {
        Binding(
            get: {
                guard let cause = app.pendingDiscard, cause != .restoreBackup, app.editorRequest != .chooser else {
                    return nil
                }
                return cause
            },
            set: { cause in
                if cause == nil {
                    app.cancelDiscard()
                }
            })
    }
}

extension DiscardCause: Identifiable {
    /// A choice is a question of its own.
    nonisolated var id: Self {
        self
    }
}

extension View {
    /// Asks "Zahodit rozepsanou fakturu?" in a dialog inside the window (`windowDialog(item:title:content:)`), which
    /// VoiceOver names by it, while a choice of `app` waits for the answer, unless it is one that the chooser or the
    /// sheet of a restore asks itself.
    func discardQuestion(of app: AppModel) -> some View {
        windowDialog(item: DiscardQuestion.askedByWindow(app), title: { _ in DiscardQuestion.title }) { _ in
            DiscardQuestionDialog(keepEditing: { app.cancelDiscard() }, discard: { app.confirmDiscard() })
        }
    }
}

/// "Zahodit rozepsanou fakturu?" in the dialog of the window: Pokračovat v úpravách, which Esc is too, and the red
/// Zahodit.
private struct DiscardQuestionDialog: View {
    let keepEditing: () -> Void
    let discard: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(verbatim: DiscardQuestion.title)
                .font(.system(size: 17, weight: .bold))
            HStack(spacing: 8) {
                Spacer()
                Button(DiscardQuestion.keepEditing, action: keepEditing)
                    .buttonStyle(.bordered)
                Button(DiscardQuestion.discard, action: discard)
                    .buttonStyle(.borderedProminent)
                    .tint(.red)
            }
            .buttonBorderShape(.capsule)
            .controlSize(.large)
        }
    }
}

/// "Zahodit rozepsanou fakturu?" in a red box of a sheet that asks it itself, in place of its buttons: the chooser for
/// its choice, and the sheet of a restore. Esc is Pokračovat v úpravách.
struct DiscardQuestionBox: View {
    let keepEditing: () -> Void
    let discard: () -> Void

    var body: some View {
        ConfirmationBox(
            title: DiscardQuestion.title, cancelTitle: DiscardQuestion.keepEditing, cancel: keepEditing,
            confirmTitle: DiscardQuestion.discard, confirm: discard)
    }
}
