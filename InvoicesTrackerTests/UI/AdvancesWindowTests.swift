import AppKit
import SwiftUI
import Testing
@testable import InvoicesTracker

/// Zálohy a odpočty in the window of the app, made as the app makes it, on the data of `EditorFixture`: the sample year
/// 2026 is stored, and the app is as of 17. 10. 2026. A typed text that the pause reads and refuses keeps its field
/// focused, so the keys that follow still go into the field: its message must not move the fields around it. The
/// helper that fills the months, the notes of the card and where the impact panel stands are read from the pixels and
/// the frames of the window, in a light and in a dark appearance.
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

    /// The titles of the four fields of the savings and insurance for old age, which VoiceOver reads the fields under.
    private static let savingsFields = [
        "Soukromé životní pojištění (Kč za rok)", "Penzijní spoření – částka k odpočtu z potvrzení",
        "Dlouhodobý investiční produkt (DIP)", "Pojištění dlouhodobé péče",
    ]

    /// What is wrong with the arrangement of the four fields of the savings in `window`, in words: they do not stand
    /// in `columns` columns, which the width of the cards lets them (`RetirementFieldGrid`). A column is a left edge
    /// the fields stand at. Empty when they do. Needs the accessibility elements.
    private func problems(ofTheSavingsFieldsIn window: NSWindow, standingIn columns: Int) -> [String] {
        var edges = Set<Int>()
        for title in Self.savingsFields {
            guard let frame = accessibilityElement(labelled: title, in: window)?.accessibilityFrame?() else {
                return ["No field \(title)"]
            }
            edges.insert(Int(frame.minX.rounded()))
        }
        return edges.count == columns
            ? [] : ["The fields stand in \(edges.count) columns, at \(edges.sorted()), not in \(columns)"]
    }

    /// The life insurance pauses in the middle of "13 340", in a window whose fields of the savings stand in two
    /// columns (1 200 points wide) and in one whose fields stand in a row of four (1 600 points), which the test
    /// asserts before it types: the arrangement is what the test is for. With the impact panel of 340 points beside the
    /// cards, one column stands from 1 150 points, two columns from 1 170 and the row from 1 570. The text so far is
    /// refused, and its message, which is longer than the title of the field, comes under the field. The fields of the
    /// savings stay where they are, so the field keeps the focus. The rest of the amount is typed into it and saved,
    /// and the message goes without the focus going.
    @Test(arguments: [(CGFloat(1_200), 2), (CGFloat(1_600), 4)])
    func aRefusedSavingsAmountKeepsItsFieldFocused(windowWidth: CGFloat, columns: Int) async throws {
        try await whileTypingAlone {
            try await EditorFixture.with { f in
                try await withAppWindow(of: f.app, size: CGSize(width: windowWidth, height: 720)) { window in
                    try await showAdvances(of: f.app, in: window)
                    try await withAccessibilityElements {
                        let label = Self.savingsFields[0]
                        try await waitUntil { textField(labelled: label, in: window) != nil }
                        let field = try #require(textField(labelled: label, in: window))
                        try await expectSettled(window) { problems(ofTheSavingsFieldsIn: window, standingIn: columns) }

                        try type("13 3", into: field, in: window)
                        try await waitUntil { showsText(AdvancesModel.wholeKcMessage, in: window) }
                        try await expectSettled(window) { focusProblems(of: field, in: window) }
                        #expect(problems(ofTheSavingsFieldsIn: window, standingIn: columns) == [])

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

    // MARK: The prefill helper

    /// The helper that fills the months is a neutral panel, on the inset background and not the orange one of the old
    /// design, and it holds its buttons: "Předvyplnit", a capsule in the accent, and "Zkopírovat z roku 2025" while the
    /// year before has a plan, a capsule in the colour of a card raised off the panel, both 28 points high, as the
    /// buttons inside a card are. The panel is read from the points around the buttons, which are its background and
    /// not the card's, and its note is in the grey of captions. The window is light or dark whatever the Mac is.
    @Test(arguments: [ColorScheme.light, .dark])
    func thePrefillHelperIsANeutralPanelWithAPrimaryButton(scheme: ColorScheme) async throws {
        try await EditorFixture.with { f in
            try await f.database.saveYearSettings(advancesYear2025())
            await f.app.didWriteAndBackUp()
            try await withAppWindow(of: f.app, size: AppWindowSize.large) { window in
                window.appearance = NSAppearance(named: scheme == .light ? .aqua : .darkAqua)
                try await showAdvances(of: f.app, in: window)
                try await withAccessibilityElements {
                    let copyTitle = "Zkopírovat z roku 2025"
                    try await waitUntil { accessibilityButton(labelled: copyTitle, in: window) != nil }
                    try await layOut(window)
                    let prefill = try #require(accessibilityButton(labelled: "Předvyplnit", in: window))
                    let copy = try #require(accessibilityButton(labelled: copyTitle, in: window))
                    let picture = try OffscreenPicture(of: window)
                    let inset = try OffscreenPicture.bytes(of: Palette.bgInset, in: scheme)
                    let accent = try OffscreenPicture.bytes(of: Palette.accent, in: scheme)
                    let card = try OffscreenPicture.bytes(of: Palette.bgCard, in: scheme)

                    let prefillFrame = try pictureFrame(of: try #require(prefill.accessibilityFrame?()), in: window)
                    let copyFrame = try pictureFrame(of: try #require(copy.accessibilityFrame?()), in: window)
                    #expect(abs(prefillFrame.height - 28) <= 0.5, "\(scheme): Předvyplnit is \(prefillFrame.height)")
                    #expect(abs(copyFrame.height - 28) <= 0.5, "\(scheme): the copy is \(copyFrame.height) tall")
                    // Each capsule is drawn in its own colour, 28 points tall.
                    let accented = try #require(
                        picture.extent(near: accent, in: prefillFrame.insetBy(dx: -2, dy: -2), by: 2),
                        "\(scheme): Předvyplnit is not in the accent")
                    #expect(abs(accented.height - 28) <= 1.5, "\(scheme): the accent capsule is \(accented.height)")
                    let raised = try #require(
                        picture.extent(near: card, in: copyFrame.insetBy(dx: -2, dy: -2), by: 2),
                        "\(scheme): the copy is not in the colour of a card")
                    #expect(abs(raised.height - 28) <= 1.5, "\(scheme): the raised capsule is \(raised.height)")
                    // The buttons stand on the inset background: the gap before the first, and the room over it.
                    for (name, point) in [
                        ("before Předvyplnit", CGPoint(x: prefillFrame.minX - 6, y: prefillFrame.midY)),
                        ("over Předvyplnit", CGPoint(x: prefillFrame.midX, y: prefillFrame.minY - 6)),
                        ("before the copy", CGPoint(x: copyFrame.minX - 6, y: copyFrame.midY)),
                    ] {
                        let found = picture.bytes(at: point)
                        #expect(
                            zip(found, inset).allSatisfy { abs($0 - $1) <= 2 },
                            "\(scheme): \(name) is \(found), not the inset background \(inset)")
                    }
                    // The note under them is in the colour of captions, and the colour of text is not in it.
                    let note = "Předvyplnit zapíše částky do všech měsíců"
                    let noteFrame = try pictureFrame(
                        of: try #require(frameOfText(startingWith: note, in: window)), in: window)
                    let caption = try OffscreenPicture.bytes(of: Palette.text3, in: scheme)
                    let text = try OffscreenPicture.bytes(of: Palette.text, in: scheme)
                    #expect(picture.count(near: caption, in: noteFrame, by: 8) > 40, "\(scheme): not a caption")
                    #expect(picture.count(near: text, in: noteFrame, by: 8) == 0, "\(scheme): the note is in text")
                }
            }
        }
    }

    // MARK: The hint about refunded advances

    /// The hint that advances for January to June may be refunded stands in the attention note of the design: the
    /// orange tint of a note, with its words in the colour of text, where the old box tinted its own words. VoiceOver
    /// reads the note as one phrase, so its frame is the note's, and a point just inside its corner is its tint.
    @Test func theHintAboutRefundedAdvancesIsAnAttentionNote() async throws {
        try await EditorFixture.with { f in
            try await withAppWindow(of: f.app, size: AppWindowSize.large) { window in
                window.appearance = NSAppearance(named: .aqua)
                try await showAdvances(of: f.app, in: window)
                try await withAccessibilityElements {
                    let hint = "Od července 2026 je minimální záloha nižší"
                    try await waitUntil { frameOfText(startingWith: hint, in: window) != nil }
                    try await layOut(window)
                    let note = try pictureFrame(
                        of: try #require(frameOfText(startingWith: hint, in: window)), in: window)
                    let picture = try OffscreenPicture(of: window)
                    let tint = try OffscreenPicture.bytes(of: Palette.orangeTint, in: .light)
                    let text = try OffscreenPicture.bytes(of: Palette.text, in: .light)

                    let corner = picture.bytes(at: CGPoint(x: note.minX + 4, y: note.minY + 4))
                    #expect(zip(corner, tint).allSatisfy { abs($0 - $1) <= 2 }, "The note is \(corner), not \(tint)")
                    #expect(picture.count(near: text, in: note, by: 8) > 40, "The words are not in the colour of text")
                }
            }
        }
    }

    // MARK: The failure of a save

    /// A change that cannot be saved is said in the error note of the design above the card: the pale red of a note
    /// with its words in the colour of text, where the old line was red text on the page. A text is typed into a cell
    /// of the plan while the data takes no writes, and the field is left, which saves it.
    @Test func theFailureOfASaveIsSaidInAnErrorNote() async throws {
        try await whileTypingAlone {
            try await EditorFixture.with { f in
                try await withAppWindow(of: f.app, size: AppWindowSize.large) { window in
                    window.appearance = NSAppearance(named: .aqua)
                    try await showAdvances(of: f.app, in: window)
                    try await withAccessibilityElements {
                        let label = "Sociální pojištění – Březen"
                        try await waitUntil { textField(labelled: label, in: window) != nil }
                        try await setDatabaseReadOnly(true, f.database)
                        try type("13 000", into: try #require(textField(labelled: label, in: window)), in: window)
                        #expect(window.makeFirstResponder(nil))
                        let failure = AdvancesModel.saveFailureText
                        try await waitUntil { frameOfText(startingWith: failure, in: window) != nil }
                        try await layOut(window)
                        let note = try pictureFrame(
                            of: try #require(frameOfText(startingWith: failure, in: window)), in: window)
                        let picture = try OffscreenPicture(of: window)
                        let tint = try OffscreenPicture.bytes(of: Palette.redTint, in: .light)
                        let text = try OffscreenPicture.bytes(of: Palette.text, in: .light)

                        let corner = picture.bytes(at: CGPoint(x: note.minX + 4, y: note.minY + 4))
                        #expect(zip(corner, tint).allSatisfy { abs($0 - $1) <= 2 }, "The note is \(corner)")
                        #expect(picture.count(near: text, in: note, by: 8) > 20, "The words are not in text colour")
                        try await setDatabaseReadOnly(false, f.database)
                    }
                }
            }
        }
    }

    // MARK: The card of the interest

    /// The interest on a mortgage has its pill "odhad do potvrzení banky" at the end of the line of its title, on the
    /// line of the title, where the card is wide enough for both, and under the title, at its start, where it is not.
    /// The card is shown alone in a window of 720 points, and of 380. VoiceOver reads the words of the pill, which
    /// stand 8 points inside the pill (its padding).
    @Test(arguments: [CGFloat(720), 380])
    func theEstimatePillStandsAtTheEndOfTheLineOfTheTitleOfTheInterestOrUnderIt(width: CGFloat) async throws {
        let pillPadding: CGFloat = 8
        try await EditorFixture.with { f in
            let model = await loadedAdvancesModel(of: f.app)
            let form = DeductionsForm(model: model, openChild: { _ in }).padding(24)
            try await withHostedView(form, size: CGSize(width: width, height: 900)) { window in
                try await withAccessibilityElements {
                    let pillText = "odhad do potvrzení banky"
                    try await waitUntil { frameOfText(startingWith: pillText, in: window) != nil }
                    try await layOut(window)
                    let heading = "Odpočty · úroky z úvěru na bydlení"
                    let card = try #require(frameOfCard(labelled: "Úroky z hypotéky", in: window))
                    // A heading is read under its words as a label, not as a value.
                    let title = try #require(accessibilityElement(labelled: heading, in: window)?.accessibilityFrame?())
                    let words = try #require(frameOfText(startingWith: pillText, in: window))
                    let pill = words.insetBy(dx: -pillPadding, dy: 0)

                    // The origin of the screen is at the bottom left, so what is lower has the smaller y.
                    if width > 600 {
                        #expect(abs(pill.midY - title.midY) <= 3, "The pill \(pill) is not on the line of \(title)")
                        #expect(pill.minX > title.maxX, "The pill \(pill) is not after the title \(title)")
                        let end = card.maxX - DesignMetrics.cardPadding
                        #expect(abs(pill.maxX - end) <= 1, "The pill \(pill) is not at the end of \(card)")
                    } else {
                        #expect(abs(pill.minX - title.minX) <= 1, "The pill \(pill) is not under the title \(title)")
                        #expect(pill.maxY <= title.minY, "The pill \(pill) is not under the title \(title)")
                    }
                }
            }
        }
    }

    // MARK: The impact panel

    /// The least the cards need beside the impact panel (`SidePanelLayout`'s main column in `AdvancesScreen`).
    private static let cardsLeastWidth: CGFloat = 520

    /// The width of the impact panel: that of the detail panels (`DetailPanelMetrics.width`). The prototype draws both
    /// as 300 points of content and 20 points of padding on either side, which are 340 in all.
    private static let impactPanelWidth = DetailPanelMetrics.width

    /// The impact panel stands beside the cards, 340 points wide, as the detail panels of Faktury and Odběratelé are,
    /// as soon as the cards keep their 520 points beside it, and under them, as wide as they are, where they would
    /// not. At the least window it comes under the cards; in the least window that has it beside them, where the
    /// cards are at their narrowest (`AdvancesWindowSize.impactPanelBeside`), and at a large size it stands beside
    /// them.
    @Test(arguments: [
        (AppWindowSize.minimum, false), (AdvancesWindowSize.impactPanelBeside, true), (AppWindowSize.large, true),
    ])
    func theImpactPanelStandsBesideTheCardsAt340AndUnderThemWhereTheyWouldBeNarrower(
        size: CGSize, isBeside: Bool
    ) async throws {
        #expect(Self.impactPanelWidth == 340)
        try await EditorFixture.with { f in
            try await withAppWindow(of: f.app, size: size) { window in
                try await showAdvances(of: f.app, in: window)
                try await withAccessibilityElements {
                    try await waitUntil { frameOfCard(labelled: "Manžel nebo manželka", in: window) != nil }
                    try await waitUntil { frameOfCard(labelled: "Dopad na daň", in: window) != nil }
                    try await expectSettled(window) { problems(ofTheImpactPanelIn: window, isBeside: isBeside) }
                }
            }
        }
    }

    /// What is wrong with the arrangement of the impact panel in `window`, in words: beside the cards it is not
    /// 340 points wide, not at the end of the page, not on the line of the top of the cards or too near them, and the
    /// cards are not what is left of the page; under them it is not as wide as the page or not under the last card.
    /// Needs the accessibility elements.
    private func problems(ofTheImpactPanelIn window: NSWindow, isBeside: Bool) -> [String] {
        guard let plan = frameOfCard(labelled: "Zálohy", in: window),
            let mortgage = frameOfCard(labelled: "Úroky z hypotéky", in: window),
            let spouse = frameOfCard(labelled: "Manžel nebo manželka", in: window),
            let impact = frameOfCard(labelled: "Dopad na daň", in: window)
        else {
            return ["A card of the page is missing"]
        }
        var found: [String] = []
        // The origin of the screen is at the bottom left, so what is higher has the greater y.
        if isBeside {
            if abs(impact.width - Self.impactPanelWidth) > 1 {
                found.append("The impact panel is \(impact.width) points wide, not \(Self.impactPanelWidth)")
            }
            if abs(impact.maxX - plan.maxX) > 1 {
                found.append("The impact panel ends at \(impact.maxX), the page at \(plan.maxX)")
            }
            if abs(impact.maxY - mortgage.maxY) > 1 {
                found.append("The impact panel starts at \(impact.maxY), the cards at \(mortgage.maxY)")
            }
            let rest = plan.width - 16 - Self.impactPanelWidth
            if abs(mortgage.width - rest) > 1 || mortgage.width < Self.cardsLeastWidth {
                found.append("The cards are \(mortgage.width) points wide, not \(rest) of the page \(plan.width)")
            }
        } else {
            if abs(impact.width - plan.width) > 1 || abs(mortgage.width - plan.width) > 1 {
                found.append("The panel is \(impact.width) points wide, the cards \(mortgage.width), not \(plan.width)")
            }
            if impact.maxY > spouse.minY - 15 {
                found.append("The impact panel is not 16 points under the last card: \(impact), the card \(spouse)")
            }
        }
        return found
    }

    // MARK: Helpers

    /// The frame `screen` of a view, given in the coordinates of the screen with the origin at its bottom left, as a
    /// picture of `window` counts it: in points from the top left of the content of the window.
    private func pictureFrame(of screen: CGRect, in window: NSWindow) throws -> CGRect {
        let frame = window.convertFromScreen(screen)
        let height = try #require(window.contentView).bounds.height
        return CGRect(x: frame.minX, y: height - frame.maxY, width: frame.width, height: frame.height)
    }

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
