import AppKit
import Observation
import SwiftUI
import Testing
@testable import InvoicesTracker

/// The confirmations that the window of the app asks itself, made as the app makes it, on the data of `EditorFixture`:
/// the deletion of an invoice, and "Zahodit rozepsanou fakturu?" for a choice made outside the chooser. Each is a
/// dialog inside the window, over the sidebar and the page and under the toolbar, never a sheet: a card 520 points
/// wide, centred, 48 points under the toolbar. Esc closes it as its Zrušit does, and the keyboard focus stays in it.
///
/// The dialogs are found as VoiceOver reads them. VoiceOver's tree shows a dialog a moment before its views are in the
/// window, and only then does it take Esc and have its field, so a test waits for those views before it types or
/// presses a key (`waitUntilTheDialogIsInTheWindow(_:)`, `focusedNumberField(in:)`). A test that tells where the focus
/// is, or puts it in a field, takes its turn among the tests that type into a window (`whileTypingAlone`): the text
/// fields of all windows share one field editor. How the dialog keeps the focus is also looked at on a dialog of its
/// own, under a layer that the window can put over it (`DialogUnderALayer`).
@Suite(.serialized, .settlesBackups)
@MainActor
struct WindowDialogTests {
    /// What a page needs is measured in the font it is set in, so the fonts are registered before any test, as the app
    /// does at its launch.
    init() {
        InvoiceFonts.register()
    }

    /// The invoice 20260901 of `EditorFixture`, paid in dollars by Bravo.
    private static let invoiceID: Int64 = 10
    private static let title = "Smazat fakturu 20260901?"

    // MARK: The deletion of an invoice

    @Test func deletingAnInvoiceAsksInsideTheWindow() async throws {
        try await whileTypingAlone {
            try await EditorFixture.with { f in
                try await withAppWindow(of: f.app, size: AppWindowSize.minimum) { window in
                    try await withAccessibilityElements {
                        try await askToDeleteTheInvoice(of: f.app, in: window)

                        #expect(window.attachedSheet == nil)
                        #expect(frameOfText(startingWith: Self.title, in: window) != nil)
                        #expect(frameOfText(startingWith: "Smazání nejde vrátit zpět.", in: window) != nil)
                        #expect(accessibilityButton(labelled: "Smazat natrvalo", in: window) != nil)
                        expectInsideTheContentArea(try #require(dialogFrame(in: window)), of: window)
                        // VoiceOver names the dialog by its title as it comes into it.
                        #expect(dialogLabel(in: window) == Self.title)
                    }
                }
            }
        }
    }

    /// The dialog is a card of the design over the scrim: the colour of a card with the corners of a card, 16 points,
    /// not the 22 of the old dialog. Its note is the red note of the design, rounded as a panel is (10 points), and its
    /// two buttons are the capsules of a dialog, 32 points tall: Zrušit on the grey fill, and Smazat natrvalo in solid
    /// red once the number is typed. The pixels are those of the window, in a light and in a dark appearance.
    @Test(arguments: [ColorScheme.light, .dark])
    func theDeletionDialogIsACardOfTheDesignWithARedNoteAndTwoCapsules(scheme: ColorScheme) async throws {
        try await whileTypingAlone {
            try await EditorFixture.with { f in
                try await withAppWindow(of: f.app, size: AppWindowSize.minimum) { window in
                    window.appearance = appearance(of: scheme)
                    window.makeKeyAndOrderFront(nil)
                    try await withAccessibilityElements {
                        try await askToDeleteTheInvoice(of: f.app, in: window)
                        let field = try await focusedNumberField(in: window)
                        try await layOut(window)
                        let card = try pictureFrame(ofScreenFrame: try #require(dialogFrame(in: window)), in: window)
                        let noteFrame = try #require(
                            frameOfText(startingWith: "Smazání nejde vrátit zpět.", in: window))
                        let note = try pictureFrame(ofScreenFrame: noteFrame, in: window)
                        let cardColour = try OffscreenPicture.bytes(of: Palette.bgCard, in: scheme)
                        let tint = try OffscreenPicture.bytes(of: Palette.redTint, in: scheme)
                        let fill = try OffscreenPicture.bytes(of: Palette.fill, in: scheme)
                        let red = try OffscreenPicture.bytes(of: Palette.red, in: scheme)
                        let before = try OffscreenPicture(of: window)
                        // The field of the number, as the picture counts its frame: framed in red only once the number
                        // is typed.
                        let fieldInWindow = frameInWindow(field)
                        let contentHeight = try #require(window.contentView).bounds.height
                        let fieldRoom = CGRect(
                            x: fieldInWindow.minX - 2, y: contentHeight - fieldInWindow.maxY - 2,
                            width: fieldInWindow.width + 4, height: fieldInWindow.height + 4)
                        #expect(before.count(near: red, in: fieldRoom, by: 4) == 0, "\(scheme): the field is red early")

                        // Where nothing stands, the dialog is the colour of a card; outside the corner of 16 points the
                        // scrim over the page shows, and just inside it the card does (a corner of 22 would still be
                        // outside there).
                        #expect(
                            pixelIs(cardColour, at: CGPoint(x: card.maxX - 30, y: card.minY + 40), in: before),
                            "\(scheme): the dialog is not the colour of a card")
                        #expect(
                            !pixelIs(cardColour, at: CGPoint(x: card.minX + 3.5, y: card.minY + 3.5), in: before),
                            "\(scheme): the corner of the card is not rounded")
                        #expect(
                            pixelIs(cardColour, at: CGPoint(x: card.minX + 5.5, y: card.minY + 5.5), in: before),
                            "\(scheme): the corner of the card is rounded by more than 16 points")
                        // The note is red-tinted and rounded by 10 points: its corner is inside at 4 points.
                        #expect(
                            pixelIs(tint, at: CGPoint(x: note.minX + 4, y: note.minY + 4), in: before),
                            "\(scheme): the note is not the red tint of the design, rounded by 10 points")
                        for label in ["Zrušit", "Smazat natrvalo"] {
                            let height = try #require(
                                accessibilityButton(labelled: label, in: window)?.accessibilityFrame?(), "No \(label)")
                                .height
                            #expect(abs(height - 32) < 0.5, "\(scheme): \(label) is \(height) points tall")
                        }
                        let cancel = try pictureFrame(
                            ofScreenFrame: try #require(
                                accessibilityButton(labelled: "Zrušit", in: window)?.accessibilityFrame?()),
                            in: window)
                        #expect(
                            pixelIs(fill, at: CGPoint(x: cancel.minX + 10, y: cancel.midY), in: before),
                            "\(scheme): Zrušit is not on the grey fill")

                        try type("20260901", into: field, in: window)
                        let delete = try #require(accessibilityButton(labelled: "Smazat natrvalo", in: window))
                        try await waitUntil { delete.isAccessibilityEnabled?() == true }
                        try await layOut(window)
                        let deleteFrame = try pictureFrame(
                            ofScreenFrame: try #require(delete.accessibilityFrame?()), in: window)
                        let after = try OffscreenPicture(of: window)
                        #expect(
                            pixelIs(red, at: CGPoint(x: deleteFrame.minX + 10, y: deleteFrame.midY), in: after),
                            "\(scheme): Smazat natrvalo is not solid red")
                        #expect(
                            after.count(near: red, in: fieldRoom, by: 4) > 100,
                            "\(scheme): the field is not framed in red once the number is typed")
                    }
                }
            }
        }
    }

    /// What the dialog dims is dimmed with the scrim of the palette (`Palette.scrim`): over a page of the colour of the
    /// window, the page shows as that colour under the scrim, the same 32 % of the same grey in a light and in a dark
    /// window, as the prototype draws it.
    @Test(arguments: [ColorScheme.light, .dark])
    func theDialogDimsThePageWithTheScrimOfThePalette(scheme: ColorScheme) async throws {
        try await whileTypingAlone {
            try await withHostedView(DialogOverAPage(), size: CGSize(width: 900, height: 600)) { window in
                window.appearance = appearance(of: scheme)
                try await withAccessibilityElements {
                    try await waitUntil { dialogFrame(in: window) != nil }
                    try await layOut(window)
                    let picture = try OffscreenPicture(of: window)
                    let page = try OffscreenPicture.bytes(of: Palette.bgWindow, in: scheme)
                    var environment = EnvironmentValues()
                    environment.colorScheme = scheme
                    let scrim = Palette.scrim.resolve(in: environment)
                    let opacity = Double(scrim.opacity)
                    let grey = [scrim.red, scrim.green, scrim.blue].map { Double($0) * 255 }
                    let dimmed = zip(page, grey).map { Int((Double($0) * (1 - opacity) + $1 * opacity).rounded()) }

                    #expect(abs(opacity - 0.32) < 0.005, "The scrim is \(opacity) of its grey")
                    // Left of the card, which is 520 points wide and centred, and under its top.
                    #expect(
                        pixelIs(dimmed, at: CGPoint(x: 20, y: 300), in: picture, within: 3),
                        "\(scheme): the page is \(picture.bytes(at: CGPoint(x: 20, y: 300))), not \(dimmed)")
                }
            }
        }
    }

    /// The field of the number takes the focus when the dialog opens, and keeps it: Tab goes round the dialog alone, as
    /// the sidebar, the page and the toolbar behind it take no focus. (With the keyboard navigation of the Mac off, as
    /// it is by default, the field is the one view of the dialog that takes the focus.)
    @Test func theDeletionDialogTakesTheFocusAndKeepsIt() async throws {
        try await whileTypingAlone {
            try await EditorFixture.with { f in
                try await withAppWindow(of: f.app, size: AppWindowSize.minimum) { window in
                    window.makeKeyAndOrderFront(nil)
                    try await withAccessibilityElements {
                        try await askToDeleteTheInvoice(of: f.app, in: window)

                        let field = try await focusedNumberField(in: window)
                        for _ in 0..<3 {
                            try pressKey("\t", keyCode: 48, in: window)
                            try await layOut(window)
                            #expect(
                                hasFocus(field, in: window),
                                "The focus went to \(String(describing: window.firstResponder))")
                        }
                    }
                }
            }
        }
    }

    /// Esc, pressed while the number is being typed, closes the dialog as Zrušit does: nothing is deleted, and the
    /// detail of the invoice is still open.
    @Test func escClosesTheDeletionDialogAndDeletesNothing() async throws {
        try await whileTypingAlone {
            try await EditorFixture.with { f in
                try await withAppWindow(of: f.app, size: AppWindowSize.minimum) { window in
                    window.makeKeyAndOrderFront(nil)
                    try await withAccessibilityElements {
                        try await askToDeleteTheInvoice(of: f.app, in: window)
                        let field = try await focusedNumberField(in: window)
                        try type("2026", into: field, in: window)

                        try pressKey("\u{1B}", keyCode: 53, in: window)

                        try await waitUntil { frameOfText(startingWith: Self.title, in: window) == nil }
                        #expect(dialogFrame(in: window) == nil)
                        #expect(try await f.database.invoice(id: Self.invoiceID) != nil)
                        #expect(accessibilityButton(labelled: "Smazat fakturu…", in: window) != nil)
                    }
                }
            }
        }
    }

    /// The number typed into the dialog enables Smazat natrvalo, which deletes the invoice, closes the dialog and the
    /// detail, and says so in the banner.
    @Test func theNumberTypedIntoTheDialogDeletesTheInvoice() async throws {
        try await whileTypingAlone {
            try await EditorFixture.with { f in
                try await withAppWindow(of: f.app, size: AppWindowSize.minimum) { window in
                    window.makeKeyAndOrderFront(nil)
                    try await withAccessibilityElements {
                        try await askToDeleteTheInvoice(of: f.app, in: window)
                        let field = try await focusedNumberField(in: window)
                        let delete = try #require(accessibilityButton(labelled: "Smazat natrvalo", in: window))
                        #expect(delete.isAccessibilityEnabled?() == false)

                        try type("20260901", into: field, in: window)

                        try await waitUntil { delete.isAccessibilityEnabled?() == true }
                        #expect(delete.accessibilityPerformPress?() == true)
                        try await waitUntil { frameOfText(startingWith: Self.title, in: window) == nil }
                        #expect(try await f.database.invoice(id: Self.invoiceID) == nil)
                        #expect(f.app.banner?.text == "Faktura 20260901 byla smazána.")
                        #expect(dialogFrame(in: window) == nil)
                    }
                }
            }
        }
    }

    /// A dialog of Faktury goes with Faktury: when another screen takes its place, nothing is left over it, nor over
    /// Faktury and the detail of the invoice when they are shown again.
    @Test func theDeletionDialogGoesWithTheScreen() async throws {
        try await whileTypingAlone {
            try await EditorFixture.with { f in
                try await withAppWindow(of: f.app, size: AppWindowSize.minimum) { window in
                    try await withAccessibilityElements {
                        try await askToDeleteTheInvoice(of: f.app, in: window)

                        f.app.screen = .overview
                        try await waitUntil { window.title == "Přehled" }
                        try await waitUntil { dialogFrame(in: window) == nil }
                        f.app.openInvoice(Self.invoiceID)
                        try await waitUntil { accessibilityButton(labelled: "Smazat fakturu…", in: window) != nil }
                        try await layOut(window)

                        #expect(dialogFrame(in: window) == nil)
                        #expect(frameOfText(startingWith: Self.title, in: window) == nil)
                        #expect(try await f.database.invoice(id: Self.invoiceID) != nil)
                    }
                }
            }
        }
    }

    // MARK: The invoice that is being written

    /// Faktury with the detail of an invoice is chosen on Přehled while an invoice is being written: the window asks
    /// "Zahodit rozepsanou fakturu?" in a dialog of its own, and Esc is Pokračovat v úpravách.
    @Test func discardingAnUnsavedInvoiceAsksInsideTheWindow() async throws {
        // The editor puts the focus in its fields when it opens, so the test takes its turn among the tests that type.
        try await whileTypingAlone {
            try await EditorFixture.with { f in
                try await withAppWindow(of: f.app, size: AppWindowSize.minimum) { window in
                    f.app.startNewInvoice(templateID: f.dollarTemplate.id)
                    try await waitUntil { f.app.editor != nil }
                    f.app.editor?.note = "Typed note"
                    f.app.screen = .overview
                    try await waitUntil { window.title == "Přehled" }
                    try await withAccessibilityElements {
                        f.app.openInvoice(Self.invoiceID)

                        try await waitUntil {
                            frameOfText(startingWith: "Zahodit rozepsanou fakturu?", in: window) != nil
                        }
                        try await waitUntilTheDialogIsInTheWindow(window)
                        #expect(window.attachedSheet == nil)
                        #expect(accessibilityButton(labelled: "Zahodit", in: window) != nil)
                        #expect(accessibilityButton(labelled: "Pokračovat v úpravách", in: window) != nil)
                        expectInsideTheContentArea(try #require(dialogFrame(in: window)), of: window)
                        #expect(dialogLabel(in: window) == "Zahodit rozepsanou fakturu?")

                        #expect(try press(.escape, in: window))
                        try await waitUntil { window.title == "Nová faktura" }
                        #expect(f.app.pendingDiscard == nil)
                        #expect(f.app.editor?.note == "Typed note")
                        #expect(dialogFrame(in: window) == nil)
                    }
                }
            }
        }
    }

    /// Zrušit of the editor asks over the editor while a field of it is being typed in: the field loses the focus,
    /// and Tab gives it to no view behind the dialog, neither a field of the editor nor the list of the sidebar.
    @Test func theQuestionOverTheEditorTakesTheFocusFromItsFields() async throws {
        try await whileTypingAlone {
            try await EditorFixture.with { f in
                try await withAppWindow(of: f.app, size: AppWindowSize.minimum) { window in
                    window.makeKeyAndOrderFront(nil)
                    f.app.startNewInvoice(templateID: f.dollarTemplate.id)
                    try await waitUntil { field(withPlaceholder: "Splatnost ve dnech", in: window) != nil }
                    let dueDays = try #require(field(withPlaceholder: "Splatnost ve dnech", in: window))
                    try type("45", into: dueDays, in: window)
                    try await waitUntil { f.app.editorHasChanges }
                    #expect(hasFocus(dueDays, in: window))

                    f.app.leaveEditor()

                    try await withAccessibilityElements {
                        try await waitUntilTheDialogIsInTheWindow(window)
                        let dialog = try #require(dialogFrame(in: window))
                        try await waitUntil { focusBehind(dialog, in: window) == nil }
                        for _ in 0..<3 {
                            try pressKey("\t", keyCode: 48, in: window)
                            try await layOut(window)
                            #expect(focusBehind(dialog, in: window) == nil)
                        }

                        #expect(try press(.escape, in: window))
                        try await waitUntil { dialogFrame(in: window) == nil }
                    }
                    #expect(f.app.pendingDiscard == nil)
                    #expect(dueDays.stringValue == "45")
                }
            }
        }
    }

    // MARK: The focus under a layer over the dialog

    /// A layer that the window puts over a dialog, such as a lock, disables the dialog under it: the dialog then leaves
    /// the focus to the layer. While nothing covers the dialog, the same field outside the card does not keep the
    /// focus, which goes back into the card.
    @Test func aLayerOverTheDialogThatDisablesItKeepsTheFocusThatItTakes() async throws {
        try await whileTypingAlone {
            let layer = DialogUnderALayer.Layer()
            try await withHostedView(DialogUnderALayer(layer: layer)) { window in
                try await waitUntil { DialogUnderALayer.fieldsAreIn(window) }
                let first = try #require(field(withPlaceholder: DialogUnderALayer.first, in: window))
                let above = try #require(field(withPlaceholder: DialogUnderALayer.above, in: window))
                #expect(window.makeFirstResponder(first))
                try await layOut(window)
                #expect(window.makeFirstResponder(above))
                try await waitUntil { hasFocus(first, in: window) }

                layer.coversTheDialog = true
                try await layOut(window)
                #expect(window.makeFirstResponder(above))
                try await layOut(window)

                #expect(
                    hasFocus(above, in: window), "The focus went to \(String(describing: window.firstResponder))")
            }
        }
    }

    /// The focus that leaves the card is sent back once the change of the focus is over, and only if it is still
    /// outside the card then. A focus that has come back into another field of the card meanwhile, as an update of
    /// SwiftUI moves it, stays there; one that has left the view outside the card for the window stays with the window.
    @Test func aFocusThatHasLeftTheViewOutsideTheCardMeanwhileIsNotMovedAgain() async throws {
        try await whileTypingAlone {
            try await withHostedView(DialogUnderALayer(layer: DialogUnderALayer.Layer())) { window in
                try await waitUntil { DialogUnderALayer.fieldsAreIn(window) }
                let first = try #require(field(withPlaceholder: DialogUnderALayer.first, in: window))
                let second = try #require(field(withPlaceholder: DialogUnderALayer.second, in: window))
                let above = try #require(field(withPlaceholder: DialogUnderALayer.above, in: window))
                #expect(window.makeFirstResponder(first))
                try await layOut(window)

                // Out of the card and into its other field, in one turn of the run loop.
                #expect(window.makeFirstResponder(above))
                #expect(window.makeFirstResponder(second))
                try await layOut(window)
                #expect(
                    hasFocus(second, in: window), "The focus went to \(String(describing: window.firstResponder))")

                // Out of the card and on to the window, in one turn of the run loop.
                #expect(window.makeFirstResponder(above))
                #expect(window.makeFirstResponder(nil))
                try await layOut(window)
                #expect(
                    window.firstResponder === window,
                    "The focus went to \(String(describing: window.firstResponder))")
            }
        }
    }

    // MARK: Helpers

    /// Opens the detail of the invoice 20260901 on Faktury and presses its Smazat fakturu…, as a click does, and waits
    /// for what the window asks, until it is in the window (`waitUntilTheDialogIsInTheWindow(_:)`).
    private func askToDeleteTheInvoice(of app: AppModel, in window: NSWindow) async throws {
        app.openInvoice(Self.invoiceID)
        try await waitUntil { accessibilityButton(labelled: "Smazat fakturu…", in: window) != nil }
        let delete = try #require(accessibilityButton(labelled: "Smazat fakturu…", in: window))
        #expect(delete.accessibilityPerformPress?() == true)
        try await waitUntil { frameOfText(startingWith: Self.title, in: window) != nil }
        try await waitUntilTheDialogIsInTheWindow(window)
    }

    /// Waits until the dialog that VoiceOver reads in `window` is in the window as views of AppKit too: until a view of
    /// the window has the frame of the card, as the view that keeps the focus in the card has. VoiceOver's tree shows
    /// the dialog a moment before, and the dialog takes Esc only from then on. Its hidden button of Esc is no view of
    /// AppKit to wait for: SwiftUI keeps its keyboard shortcuts to itself.
    private func waitUntilTheDialogIsInTheWindow(_ window: NSWindow) async throws {
        try await waitUntil {
            guard let content = window.contentView, let frame = dialogFrame(in: window) else { return false }
            let card = window.convertFromScreen(frame)
            return views(under: content).contains { view in
                let viewFrame = frameInWindow(view)
                return (viewFrame.minX - card.minX).magnitude < 1 && (viewFrame.minY - card.minY).magnitude < 1
                    && (viewFrame.width - card.width).magnitude < 1
                    && (viewFrame.height - card.height).magnitude < 1
            }
        }
    }

    /// `view` and every view under it.
    private func views(under view: NSView) -> [NSView] {
        [view] + view.subviews.flatMap { views(under: $0) }
    }

    /// The field of the deletion dialog in `window` where the number is typed, once it is in the window as a text field
    /// of AppKit and has the focus, which it takes when the dialog opens: what is typed then goes into it.
    private func focusedNumberField(in window: NSWindow) async throws -> NSTextField {
        try await waitUntil { numberField(in: window).map { hasFocus($0, in: window) } ?? false }
        return try #require(numberField(in: window))
    }

    /// The frame of the dialog that is open in `window`, in the coordinates of the screen, or nil when none is.
    /// What VoiceOver names the card of the dialog of `window` by, or nil when there is no dialog.
    private func dialogLabel(in window: NSWindow) -> String? {
        accessibilityElement(identifiedBy: WindowDialog.accessibilityID, in: window)?.accessibilityLabel?()
    }

    private func dialogFrame(in window: NSWindow) -> CGRect? {
        accessibilityElement(identifiedBy: WindowDialog.accessibilityID, in: window)?.accessibilityFrame?()
    }

    /// Expects `card`, in the coordinates of the screen, inside the content area of `window`, under its toolbar: 48
    /// points under the toolbar's bottom edge, 520 points wide and centred.
    private func expectInsideTheContentArea(
        _ card: CGRect, of window: NSWindow, sourceLocation: SourceLocation = #_sourceLocation
    ) {
        let room = window.convertToScreen(window.contentLayoutRect)
        #expect(room.contains(card), "The dialog \(card) is not inside \(room)", sourceLocation: sourceLocation)
        #expect(
            (room.maxY - card.maxY - 48).magnitude < 1, "The dialog \(card) is not 48 points under the toolbar \(room)",
            sourceLocation: sourceLocation)
        #expect(
            (card.width - 520).magnitude < 1, "The dialog is \(card.width) points wide", sourceLocation: sourceLocation)
        #expect(
            (card.midX - room.midX).magnitude < 1, "The dialog \(card) is not centred in \(room)",
            sourceLocation: sourceLocation)
    }

    /// The field of the dialog in `window` where the number of the invoice is typed: the one whose placeholder is
    /// "Číslo faktury".
    private func numberField(in window: NSWindow) -> NSTextField? {
        field(withPlaceholder: "Číslo faktury", in: window)
    }

    /// The text field of `window` whose placeholder is `placeholder`.
    private func field(withPlaceholder placeholder: String, in window: NSWindow) -> NSTextField? {
        guard let content = window.contentView else { return nil }
        return editableTextFields(in: content).first { $0.placeholderString == placeholder }
    }

    /// The view of `window` that has the keyboard focus, as its type and its frame, when it is a view behind the
    /// dialog at `dialog` (in the coordinates of the screen): a field that is typed in stands for its field editor, and
    /// the view that hosts the whole content of the window, or the window itself, is behind nothing. Nil otherwise.
    private func focusBehind(_ dialog: CGRect, in window: NSWindow) -> String? {
        guard let responder = window.firstResponder else { return nil }
        let editor = responder as? NSTextView
        let view = editor?.isFieldEditor == true ? editor?.delegate as? NSView : responder as? NSView
        guard let view, view !== window.contentView else { return nil }
        let frame = window.convertToScreen(frameInWindow(view))
        let enabled = (view as? NSControl)?.isEnabled ?? true
        return enabled && dialog.contains(frame) ? nil : "\(Swift.type(of: view)) \(frame)"
    }

    /// Whether `field` has the keyboard focus in `window`: its field editor is the first responder.
    private func hasFocus(_ field: NSTextField, in window: NSWindow) -> Bool {
        field.currentEditor() != nil && window.firstResponder === field.currentEditor()
    }

    /// Types `text` into `field` as a person does: the field takes the focus and its text is replaced, and the change
    /// reaches the binding as the keys do.
    private func type(_ text: String, into field: NSTextField, in window: NSWindow) throws {
        #expect(window.makeFirstResponder(field))
        let editor = try #require(field.currentEditor() as? NSTextView)
        editor.selectAll(nil)
        editor.insertText(text, replacementRange: editor.selectedRange())
    }

    /// Presses the key with `keyCode`, which types `characters`, as the keyboard does: a key-down event handed to
    /// `window` as the application hands it the keys, to the view that has the focus. (The application gives keys to
    /// its key window, and a window of a test run is not that: the run is not the active application.)
    private func pressKey(_ characters: String, keyCode: UInt16, in window: NSWindow) throws {
        let event = try #require(
            NSEvent.keyEvent(
                with: .keyDown, location: .zero, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                windowNumber: window.windowNumber, context: nil, characters: characters,
                charactersIgnoringModifiers: characters, isARepeat: false, keyCode: keyCode))
        window.sendEvent(event)
    }
}

/// A dialog of the window over a page that is the background of the window, with nothing else in it.
private struct DialogOverAPage: View {
    /// The one dialog that is shown.
    struct Shown: Identifiable {
        let id = 1
    }

    @State private var shown: Shown? = Shown()

    var body: some View {
        Palette.bgWindow
            .windowDialog(item: $shown, title: { _ in "Dialog nad stránkou" }) { _ in
                Text(verbatim: "Obsah")
            }
    }
}

/// A dialog of the window with two fields, over an empty page, and a field outside the card in a layer over both: it
/// stands for a layer that the window can put over a dialog, such as a lock, which disables the page and the dialog
/// under it while it covers them (`Layer.coversTheDialog`).
private struct DialogUnderALayer: View {
    /// Whether the layer covers the dialog.
    @MainActor
    @Observable
    final class Layer {
        var coversTheDialog = false
    }

    /// The one dialog that is shown.
    struct Shown: Identifiable {
        let id = 1
    }

    /// The placeholders the fields are found by.
    static let first = "První pole dialogu"
    static let second = "Druhé pole dialogu"
    static let above = "Pole nad dialogem"

    /// Whether the three fields are in `window` as text fields of AppKit, which they are a moment after the view is
    /// shown.
    static func fieldsAreIn(_ window: NSWindow) -> Bool {
        guard let content = window.contentView else { return false }
        let placeholders = Set(editableTextFields(in: content).compactMap(\.placeholderString))
        return placeholders.isSuperset(of: [first, second, above])
    }

    let layer: Layer
    @State private var shown: Shown? = Shown()
    @State private var firstText = ""
    @State private var secondText = ""
    @State private var aboveText = ""

    var body: some View {
        Color.clear
            .windowDialog(item: $shown, title: { _ in "Dialog pod vrstvou" }) { _ in
                VStack(spacing: 8) {
                    TextField(Self.first, text: $firstText)
                    TextField(Self.second, text: $secondText)
                }
            }
            .disabled(layer.coversTheDialog)
            .overlay(alignment: .bottom) {
                TextField(Self.above, text: $aboveText)
                    .frame(width: 200)
                    .padding(.bottom, 40)
            }
    }
}
