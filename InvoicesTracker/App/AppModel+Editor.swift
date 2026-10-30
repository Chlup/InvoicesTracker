import Foundation

/// What the person chose that would throw away the invoice they are writing.
nonisolated enum DiscardCause: Hashable, Sendable {
    /// A choice in the chooser: a new invoice, blank or from the template with this id; or Nová faktura on the card of
    /// the client with `clientID`.
    case newInvoice(templateID: Int64?, clientID: Int64? = nil)

    /// Faktury with the detail of the invoice with this id.
    case openInvoice(Int64)

    /// Zrušit and the back arrow of the editor.
    case closeEditor

    /// Obnovit in the sheet that restores a backup while the data is open: the data the editor works on is replaced.
    /// The sheet asks the question itself, as the window cannot ask over a sheet.
    case restoreBackup
}

/// What the editor was made for: the request that is shown, and which new invoice it is.
nonisolated struct EditorKey: Equatable, Sendable {
    var request: EditorRequest?
    var generation: Int
}

/// Where the invoice editor is shown, what holds it and how it is left. The editor takes the place of the content of
/// Faktury while `editorRequest` is a new invoice or an invoice to edit, and it stays when the window shows other
/// screens; the chooser is a sheet over any screen.
extension AppModel {
    /// Whether the editor is open: a new invoice or an invoice to edit is asked for. The chooser is not the editor.
    var isEditorOpen: Bool {
        switch editorRequest {
        case .new, .edit: true
        case .chooser, nil: false
        }
    }

    /// Whether the toolbar shows the back arrow of the editor: while the editor is what Faktury shows. The editor that
    /// waits behind another screen has no arrow there.
    var showsEditorBackArrow: Bool {
        isEditorOpen && screen == .invoices
    }

    /// The editor that is on the screen: the one asked for, or, while the chooser is open over one, the one under it.
    var shownEditorRequest: EditorRequest? {
        switch editorRequest {
        case .new, .edit: editorRequest
        case .chooser: requestBeforeChooser
        case nil: nil
        }
    }

    /// What the editor that is wanted is made for. The window makes the editor again when it changes.
    var editorKey: EditorKey {
        EditorKey(request: shownEditorRequest, generation: editorGeneration)
    }

    /// Whether the editor holds something typed or chosen that is not saved: what a choice, a quit or an opened invoice
    /// would throw away.
    var editorHasChanges: Bool {
        editor?.hasChanges ?? false
    }

    // MARK: Making and releasing it

    /// Makes the editor for the request that is shown, unless it is made already: a window that is shown again, or a
    /// screen that is come back to, finds the editor as it was left. A request for an invoice that was deleted
    /// meanwhile says so (`editorProblem`). The chooser opened over the editor does not change it.
    func openEditor() async {
        let key = editorKey
        guard let request = key.request else {
            releaseEditor()
            return
        }
        if openedEditorKey == key {
            return
        }
        releaseEditor()
        var made: InvoiceEditorModel?
        var problem: String?
        do {
            if let opened = try await InvoiceEditorModel.opening(request, in: self) {
                await opened.load()
                if opened.loadFailed {
                    problem = "Fakturu se nepodařilo načíst."
                } else {
                    made = opened
                }
            } else {
                problem = "Faktura mezitím byla smazána."
            }
        } catch {
            Self.log("Opening the invoice editor", failedWith: error)
            problem = "Fakturu se nepodařilo načíst."
        }
        // The request moved on, or the window that waited for the editor was closed: this is not the editor to show.
        guard !Task.isCancelled, editorKey == key, openedEditorKey == nil else { return }
        editor = made
        editorProblem = problem
        openedEditorKey = key
    }

    /// Lets the editor go, with the problem that stands in its place.
    func releaseEditor() {
        editor = nil
        editorProblem = nil
        openedEditorKey = nil
    }

    // MARK: Leaving it

    /// Opens the editor on a new invoice, blank or from the template with this id, on Faktury (whichever screen the
    /// chooser was opened over), and closes the chooser. It is a new editor: what was typed in the editor the chooser
    /// was open over is gone, so the person is asked first when there is something typed (`pendingDiscard`).
    func startNewInvoice(templateID: Int64?) {
        choose(.newInvoice(templateID: templateID))
    }

    /// Opens the editor on a blank invoice for the client with this id, on Faktury (whichever screen it is asked on):
    /// Nová faktura on the row of a client in Odběratelé. It is a new editor like any other new invoice, so the person
    /// is asked first when there is something typed in the editor that is open (`pendingDiscard`).
    func startNewInvoice(forClient clientID: Int64) {
        choose(.newInvoice(templateID: nil, clientID: clientID))
    }

    /// Zrušit on the chooser: it closes, and the editor it was open over, if any, is there as it was. Does nothing
    /// while the chooser is not open.
    func cancelChooser() {
        guard editorRequest == .chooser else { return }
        editorRequest = requestBeforeChooser
    }

    /// Zrušit and the back arrow of the editor: closes it (`closeEditor()`), after the question "Zahodit rozepsanou
    /// fakturu?" when something typed in it would be lost.
    func leaveEditor() {
        choose(.closeEditor)
    }

    /// Closes the editor without saving, and shows Faktury: with the detail of the invoice that was being edited open,
    /// or, for a new invoice that was never saved, with no detail open.
    func closeEditor() {
        let request = shownEditorRequest
        editorRequest = nil
        screen = .invoices
        if case .edit(let id)? = request {
            pendingDetailInvoiceID = id
        }
    }

    /// Does what the person chose, after asking "Zahodit rozepsanou fakturu?" when it throws away what they typed in
    /// the editor: the question waits in `pendingDiscard` for `confirmDiscard()` or `cancelDiscard()`.
    func choose(_ cause: DiscardCause) {
        if editorHasChanges {
            pendingDiscard = cause
        } else {
            perform(cause)
        }
    }

    /// Zahodit: does what the person chose, and the editor with what was typed in it goes. Does nothing while no
    /// question is asked.
    func confirmDiscard() {
        guard let cause = pendingDiscard else { return }
        pendingDiscard = nil
        perform(cause)
    }

    /// Pokračovat v úpravách: nothing is thrown away. The chooser closes if it was open, and the window shows the
    /// editor as it was left, on Faktury. Does nothing while no question is asked.
    func cancelDiscard() {
        guard pendingDiscard != nil else { return }
        pendingDiscard = nil
        cancelChooser()
        screen = .invoices
    }

    private func perform(_ cause: DiscardCause) {
        switch cause {
        case .newInvoice(let templateID, let clientID):
            releaseEditor()
            screen = .invoices
            editorGeneration += 1
            editorRequest = .new(templateID: templateID, clientID: clientID)
        case .openInvoice(let id):
            editorRequest = nil
            screen = .invoices
            pendingDetailInvoiceID = id
        case .closeEditor:
            closeEditor()
        case .restoreBackup:
            // The restore that asked goes on once the editor is gone (`AppModel.restoreWhileOpen`).
            editorRequest = nil
        }
    }
}
