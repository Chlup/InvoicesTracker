import AppKit
import SwiftUI
import Testing
@testable import InvoicesTracker

/// Zálohy a odpočty in the window of the app, made as the app makes it, on the data of `EditorFixture`: the sample year
/// 2026 is stored, and the app is as of 17. 10. 2026. A typed text that the pause reads and refuses keeps its field
/// focused, so the keys that follow still go into the field: its message must not move the fields around it.
///
/// The fields are found by the labels VoiceOver reads them under, and the message by its words. A test types in its
/// turn among the tests that type into a window (`whileTypingAlone`): the text fields of all windows share one field
/// editor.
@Suite(.serialized, .settlesBackups)
@MainActor
struct AdvancesWindowTests {
    /// What a page needs is measured in the font it is set in, so the fonts are registered before any test, as the app
    /// does at its launch.
    init() {
        InvoiceFonts.register()
    }

    // MARK: Refused texts

    /// The life insurance pauses in the middle of "13 340", in a window whose fields of the savings stand in two
    /// columns (1 180 points wide) and in one whose fields stand in a row (1 570 points). The text so far is refused,
    /// and its message, which is longer than the title of the field, comes under the field. The fields of the savings
    /// stay where they are, so the field keeps the focus. The rest of the amount is typed into it and saved, and the
    /// message goes without the focus going.
    @Test(arguments: [CGFloat(1_180), 1_570])
    func aRefusedSavingsAmountKeepsItsFieldFocused(windowWidth: CGFloat) async throws {
        try await whileTypingAlone {
            try await EditorFixture.with { f in
                try await withAppWindow(of: f.app, size: CGSize(width: windowWidth, height: 720)) { window in
                    try await showAdvances(of: f.app, in: window)
                    try await withAccessibilityElements {
                        let label = "Soukromé životní pojištění (Kč za rok)"
                        try await waitUntil { textField(labelled: label, in: window) != nil }
                        let field = try #require(textField(labelled: label, in: window))

                        try type("13 3", into: field, in: window)
                        try await waitUntil { showsText(AdvancesModel.wholeKcMessage, in: window) }
                        try await expectSettled(window) { focusProblems(of: field, in: window) }

                        try typeOn("40", into: field)
                        try await waitUntil {
                            try await f.database.yearSettings(2026).deductions.lifeInsurance == 13_340
                        }
                        try await waitUntil { !showsText(AdvancesModel.wholeKcMessage, in: window) }
                        try await expectSettled(window) { focusProblems(of: field, in: window) }
                    }
                }
            }
        }
    }

    // MARK: The note of the rate of 30 %

    /// The sentence under the menu of the rate while 30 % is chosen.
    private static let rentNote = "Běžný pronájem podle § 9 aplikace nepočítá – není to příjem z podnikání."

    /// The note that ordinary rent is not counted stands in the window while 30 % is chosen, where the rate stands over
    /// the reduced base (the least room) and where the two stand side by side (a large window). The sample year has
    /// 60 %, which has no note, and the note goes when the rate is back at it.
    @Test(arguments: [AppWindowSize.minimum, AppWindowSize.large])
    func theNoteOfOrdinaryRentIsInTheWindowWhile30PercentIsChosen(size: CGSize) async throws {
        try await EditorFixture.with { f in
            try await withAppWindow(of: f.app, size: size) { window in
                try await showAdvances(of: f.app, in: window)
                try await withAccessibilityElements {
                    // The page is there once the settings are read.
                    try await waitUntil { frameOfCard(labelled: "Zálohy", in: window) != nil }
                    #expect(!showsText(Self.rentNote, in: window))

                    try await store(expensePercent: 30, in: f)
                    try await waitUntil { showsText(Self.rentNote, in: window) }

                    try await store(expensePercent: 60, in: f)
                    try await waitUntil { !showsText(Self.rentNote, in: window) }
                }
            }
        }
    }

    // MARK: Helpers

    /// Chooses `percent` for the flat-rate expenses of 2026 in the data and tells the app, so that the screen reads it.
    private func store(expensePercent percent: Int, in f: EditorFixture) async throws {
        try await f.database.updateYearSettings(2026) { $0.expensePercent = percent }
        await f.app.didWriteAndBackUp()
    }

    /// Shows Zálohy a odpočty in `window`, which is made the key window as a person's click makes it.
    private func showAdvances(of app: AppModel, in window: NSWindow) async throws {
        window.makeKeyAndOrderFront(nil)
        app.screen = .advances
        try await waitUntil { window.title == "Zálohy a odpočty" }
        try await layOut(window)
    }

    /// Types `text` into `field` as a person does: the field takes the focus and its text is replaced, and the change
    /// reaches the binding as the keys do.
    private func type(_ text: String, into field: NSTextField, in window: NSWindow) throws {
        #expect(window.makeFirstResponder(field))
        let editor = try #require(field.currentEditor() as? NSTextView)
        editor.selectAll(nil)
        editor.insertText(text, replacementRange: editor.selectedRange())
    }

    /// Types `text` on at the end of what `field`, which has the focus, holds.
    private func typeOn(_ text: String, into field: NSTextField) throws {
        let editor = try #require(field.currentEditor() as? NSTextView)
        editor.insertText(text, replacementRange: editor.selectedRange())
    }

    /// What is wrong with the focus of `field` in `window`, in words: the field is gone from the window, or another
    /// view has the focus. Empty while the field is being typed in.
    private func focusProblems(of field: NSTextField, in window: NSWindow) -> [String] {
        guard field.window === window else {
            return ["The field is no longer in the window"]
        }
        guard let editor = field.currentEditor(), window.firstResponder === editor else {
            return ["The field lost the focus to \(String(describing: window.firstResponder))"]
        }
        return []
    }
}
