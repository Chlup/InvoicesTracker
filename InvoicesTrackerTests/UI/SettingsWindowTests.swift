import AppKit
import SwiftUI
import Testing

@testable import InvoicesTracker

/// Nastavení and its sheets in a window, made as the app makes them, on the data of `EditorFixture` (the supplier with
/// the three accounts, the sample year 2026 and a local backup, as of 17. 10. 2026) or on a fresh vault: the buttons
/// inside the cards, the boxes of the accounts, the notes and the footers of the sheets, as VoiceOver reads their
/// frames and as the pixels of the window show their colours, in a light and in a dark appearance. The window is light
/// or dark whatever the Mac is.
///
/// The controls are found by the labels VoiceOver reads them under. A sheet is shown alone in a window
/// (`withHostedView`), so the window has no background of its own and the pixels that are looked at are those of the
/// notes and the capsules, which lie on the colour of a card.
@Suite(.serialized, .settlesBackups)
@MainActor
struct SettingsWindowTests {
    /// The height of the button of `window` that VoiceOver reads under `label`.
    private func height(ofButton label: String, in window: NSWindow) throws -> CGFloat {
        try #require(accessibilityButton(labelled: label, in: window)?.accessibilityFrame?(), "No button \(label)")
            .height
    }

    /// The first button among `elements` and their children, in the order of the tree.
    private func firstButton(among elements: [Any]) -> AnyObject? {
        for item in elements {
            let element = item as AnyObject
            if element.accessibilityRole?() == .button {
                return element
            }
            if let found = firstButton(among: element.accessibilityChildren?() ?? []) {
                return found
            }
        }
        return nil
    }

    // MARK: The buttons inside the cards

    /// The buttons inside the cards of the tabs are the capsules of the design, 28 points tall: Zkontrolovat teď,
    /// Vytvořit nový kód…, the three buttons of the backups, and Zadat ručně, which opens the form of the uniform
    /// rate with Zrušit and Uložit kurz, 28 points tall too. Přidat, the button of the form of an adjustment, is a
    /// button of the page, 32 points tall.
    @Test func theButtonsInsideTheCardsOfNastaveniAre28PointCapsulesAndPridatIs32() async throws {
        try await EditorFixture.with { f in
            try await withAppWindow(of: f.app, size: AppWindowSize.large) { window in
                try await withAccessibilityElements {
                    let tabs: [(tab: SettingsTab, buttons: [String])] = [
                        (.application, ["Zkontrolovat teď"]),
                        (
                            .security,
                            ["Vytvořit nový kód…", "Zálohovat teď", "Exportovat zálohu…", "Obnovit ze zálohy…"]
                        ),
                        (.year, ["Zadat ručně"]),
                    ]
                    for (tab, buttons) in tabs {
                        f.app.showSettings(tab)
                        try await waitUntil { window.title == "Nastavení" }
                        for title in buttons {
                            try await waitUntil { accessibilityButton(labelled: title, in: window) != nil }
                            let height = try height(ofButton: title, in: window)
                            #expect(abs(height - 28) < 0.5, "\(title) is \(height) points tall")
                        }
                    }

                    // The form of the uniform rate, and the form of an adjustment under the rules.
                    let enter = try #require(accessibilityButton(labelled: "Zadat ručně", in: window))
                    #expect(enter.accessibilityPerformPress?() == true)
                    for title in ["Zrušit", "Uložit kurz"] {
                        try await waitUntil { accessibilityButton(labelled: title, in: window) != nil }
                        let height = try height(ofButton: title, in: window)
                        #expect(abs(height - 28) < 0.5, "\(title) is \(height) points tall")
                    }
                    try await waitUntil { accessibilityButton(labelled: "Přidat", in: window) != nil }
                    let add = try height(ofButton: "Přidat", in: window)
                    #expect(abs(add - 32) < 0.5, "Přidat is \(add) points tall")
                }
            }
        }
    }

    // MARK: The names of the cards

    /// Every card of Nastavení is read by VoiceOver under the name the design gives its section: "Jednotný kurz" and
    /// "Pravidla" where the cards show "Jednotný kurz 2026" and "Pravidla výpočtu", the others under their titles.
    @Test func theCardsOfNastaveniAreReadUnderTheNamesOfTheDesign() async throws {
        try await EditorFixture.with { f in
            try await withAppWindow(of: f.app, size: AppWindowSize.large) { window in
                try await withAccessibilityElements {
                    let tabs: [(tab: SettingsTab, cards: [String])] = [
                        (.application, ["Vzhled", "Kurzy", "Licence"]),
                        (.supplier, ["Vaše údaje", "Bankovní účty"]),
                        (.security, ["Odemykání", "Kód pro obnovení", "Zálohy"]),
                        (.year, ["Profil", "Činnost", "Jednotný kurz", "Pravidla", "Úpravy příjmů"]),
                    ]
                    for (tab, cards) in tabs {
                        f.app.showSettings(tab)
                        try await waitUntil { window.title == "Nastavení" }
                        for card in cards {
                            try await waitUntil { frameOfCard(labelled: card, in: window) != nil }
                        }
                    }
                }
            }
        }
    }

    // MARK: Moje údaje

    /// The box of an account is a panel on the inset background, as wide as the card's content: a point in its left
    /// padding is the inset colour, and a point just outside it is the colour of the card.
    @Test(arguments: [ColorScheme.light, .dark])
    func theBoxOfAnAccountIsAnInsetPanel(scheme: ColorScheme) async throws {
        try await EditorFixture.with { f in
            try await withAppWindow(of: f.app, size: AppWindowSize.large) { window in
                window.appearance = NSAppearance(named: scheme == .light ? .aqua : .darkAqua)
                f.app.showSettings(.supplier)
                try await withAccessibilityElements {
                    try await waitUntil { frameOfCard(labelled: "Účet v USD", in: window) != nil }
                    try await layOut(window)
                    let box = try pictureFrame(
                        ofScreenFrame: try #require(frameOfCard(labelled: "Účet v USD", in: window)), in: window)
                    let card = try pictureFrame(
                        ofScreenFrame: try #require(frameOfCard(labelled: "Bankovní účty", in: window)), in: window)
                    let picture = try OffscreenPicture(of: window)
                    let inset = try OffscreenPicture.bytes(of: Palette.bgInset, in: scheme)
                    let cardColour = try OffscreenPicture.bytes(of: Palette.bgCard, in: scheme)

                    #expect(pixelIs(inset, at: CGPoint(x: box.minX + 6, y: box.midY), in: picture), "\(scheme): inset")
                    #expect(
                        pixelIs(cardColour, at: CGPoint(x: box.minX - 6, y: box.midY), in: picture),
                        "\(scheme): outside the box")
                    // The box is as wide as the card's content: the card pads it by 20 points on either side.
                    #expect(
                        abs(box.minX - (card.minX + DesignMetrics.cardPadding)) < 1, "\(scheme): \(box) in \(card)")
                    #expect(
                        abs(box.maxX - (card.maxX - DesignMetrics.cardPadding)) < 1, "\(scheme): \(box) in \(card)")
                }
            }
        }
    }

    // MARK: Notes

    /// The warning that the backups are only in this Mac is the attention note of the design: the orange tint of a note
    /// with its words in the colour of text, where the old box tinted its words orange as well.
    @Test(arguments: [ColorScheme.light, .dark])
    func theWarningAboutBackupsOnlyInThisMacIsAnAttentionNote(scheme: ColorScheme) async throws {
        try await EditorFixture.with { f in
            try await withAppWindow(of: f.app, size: AppWindowSize.large) { window in
                window.appearance = NSAppearance(named: scheme == .light ? .aqua : .darkAqua)
                f.app.showSettings(.security)
                try await withAccessibilityElements {
                    let warning = "Zálohy jsou zatím jen v tomto Macu."
                    try await waitUntil { frameOfText(startingWith: warning, in: window) != nil }
                    try await layOut(window)
                    let note = try pictureFrame(
                        ofScreenFrame: try #require(frameOfText(startingWith: warning, in: window)), in: window)
                    let picture = try OffscreenPicture(of: window)
                    let tint = try OffscreenPicture.bytes(of: Palette.orangeTint, in: scheme)
                    let text = try OffscreenPicture.bytes(of: Palette.text, in: scheme)

                    #expect(
                        pixelIs(tint, at: CGPoint(x: note.minX + 4, y: note.minY + 4), in: picture),
                        "\(scheme): the note is \(picture.bytes(at: CGPoint(x: note.minX + 4, y: note.minY + 4)))")
                    #expect(picture.count(near: text, in: note, by: 8) > 40, "\(scheme): the words are not text")
                }
            }
        }
    }

    /// The hint about the months of a secondary activity that are not marked is the information note of the design,
    /// the pale blue with its words in the colour of text, and holds Označit i tady, a capsule 28 points tall in the
    /// colour of a card with its words in the blue of a link.
    @Test(arguments: [ColorScheme.light, .dark])
    func theHintAboutTheSecondaryMonthsIsAnInformationNoteWithAButton(scheme: ColorScheme) async throws {
        try await EditorFixture.with { f in
            try await f.database.updateYearSettings(2026) {
                $0.secondaryMonths = [2, 3]
                $0.healthExemptMonths = []
            }
            await f.app.didWriteAndBackUp()
            try await withAppWindow(of: f.app, size: AppWindowSize.large) { window in
                window.appearance = NSAppearance(named: scheme == .light ? .aqua : .darkAqua)
                f.app.showSettings(.year)
                try await withAccessibilityElements {
                    let hint = "V Zálohách máte vedlejší činnost v měsících únor, březen."
                    try await waitUntil { frameOfText(startingWith: hint, in: window) != nil }
                    try await waitUntil { accessibilityButton(labelled: "Označit i tady", in: window) != nil }
                    try await layOut(window)
                    let note = try pictureFrame(
                        ofScreenFrame: try #require(frameOfText(startingWith: hint, in: window)), in: window)
                    let buttonFrame = try #require(
                        accessibilityButton(labelled: "Označit i tady", in: window)?.accessibilityFrame?())
                    let button = try pictureFrame(ofScreenFrame: buttonFrame, in: window)
                    let picture = try OffscreenPicture(of: window)
                    let tint = try OffscreenPicture.bytes(of: Palette.accentTint, in: scheme)
                    let text = try OffscreenPicture.bytes(of: Palette.text, in: scheme)
                    let card = try OffscreenPicture.bytes(of: Palette.bgCard, in: scheme)
                    let link = try OffscreenPicture.bytes(of: Palette.accentText, in: scheme)

                    // Inside the padding of the note, to the left of its words, where no glyph stands.
                    #expect(
                        pixelIs(tint, at: CGPoint(x: note.minX - 6, y: note.midY), in: picture),
                        "\(scheme): the note is not the information tint")
                    #expect(picture.count(near: text, in: note, by: 8) > 40, "\(scheme): the words are not text")
                    #expect(abs(button.height - 28) < 0.5, "\(scheme): the button is \(button.height) points tall")
                    let capsule = try #require(
                        picture.extent(near: card, in: button.insetBy(dx: -2, dy: -2), by: 2),
                        "\(scheme): the button is not the colour of a card")
                    #expect(abs(capsule.height - 28) <= 1.5, "\(scheme): the capsule is \(capsule.height) points tall")
                    #expect(picture.count(near: link, in: button, by: 8) > 30, "\(scheme): the words are not the link")
                }
            }
        }
    }

    // MARK: The sheets

    /// The sheet Nový kód pro obnovení asks in the attention note of the design and ends in Zrušit, a capsule on the
    /// grey fill, and Vytvořit nový kód, a capsule in the accent, both 32 points tall as the buttons of a dialog
    /// are.
    @Test(arguments: [ColorScheme.light, .dark])
    func theSheetOfANewCodeAsksInAnAttentionNoteAndEndsInTwoCapsules(scheme: ColorScheme) async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let app = try await makeSettingsApp(in: directory)
        app.showSettings(.security)
        let security = SecurityTabModel(app: app)
        security.load()

        let sheet = NewRecoveryCodeSheet(model: security) {}
        try await withHostedView(sheet, size: CGSize(width: 560, height: 360)) { window in
            window.appearance = NSAppearance(named: scheme == .light ? .aqua : .darkAqua)
            try await withAccessibilityElements {
                try await waitUntil { accessibilityButton(labelled: "Vytvořit nový kód", in: window) != nil }
                try await layOut(window)
                for title in ["Zrušit", "Vytvořit nový kód"] {
                    let height = try height(ofButton: title, in: window)
                    #expect(abs(height - 32) < 0.5, "\(scheme): \(title) is \(height) points tall")
                }
                let createFrame = try #require(
                    accessibilityButton(labelled: "Vytvořit nový kód", in: window)?.accessibilityFrame?())
                let cancelFrame = try #require(
                    accessibilityButton(labelled: "Zrušit", in: window)?.accessibilityFrame?())
                let create = try pictureFrame(ofScreenFrame: createFrame, in: window)
                let cancel = try pictureFrame(ofScreenFrame: cancelFrame, in: window)
                let warning = "Zálohy vytvořené do dneška"
                let note = try pictureFrame(
                    ofScreenFrame: try #require(frameOfText(startingWith: warning, in: window)), in: window)
                let picture = try OffscreenPicture(of: window)
                let accent = try OffscreenPicture.bytes(of: Palette.accent, in: scheme)
                let fill = try OffscreenPicture.bytes(of: Palette.fill, in: scheme)
                let tint = try OffscreenPicture.bytes(of: Palette.orangeTint, in: scheme)

                #expect(
                    picture.extent(near: accent, in: create.insetBy(dx: -2, dy: -2), by: 2) != nil,
                    "\(scheme): Vytvořit nový kód is not in the accent")
                #expect(
                    picture.extent(near: fill, in: cancel.insetBy(dx: -2, dy: -2), by: 2) != nil,
                    "\(scheme): Zrušit is not on the grey fill")
                #expect(
                    pixelIs(tint, at: CGPoint(x: note.minX + 4, y: note.minY + 4), in: picture),
                    "\(scheme): the warning is not an attention note")
            }
        }
    }

    /// Hotovo of the new code stays off until the person says the code is stored away from this Mac: the sheet makes
    /// the code with Vytvořit nový kód, and its second step has the checkbox "Nový kód mám uložený mimo tento Mac" and
    /// Hotovo, which the checkbox enables and clearing it disables again. (This pins what the sheet does, whatever the
    /// look of the checkbox.)
    @Test func hotovoOfTheNewCodeStaysOffUntilTheCodeIsSaidToBeStored() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let app = try await makeSettingsApp(in: directory)
        app.showSettings(.security)
        let security = SecurityTabModel(app: app)
        security.load()

        try await withHostedView(NewRecoveryCodeSheet(model: security) {}, size: CGSize(width: 560, height: 760)) {
            window in
            try await withAccessibilityElements {
                try await waitUntil { accessibilityButton(labelled: "Vytvořit nový kód", in: window) != nil }
                let create = try #require(accessibilityButton(labelled: "Vytvořit nový kód", in: window))
                #expect(create.accessibilityPerformPress?() == true)

                try await waitUntil { accessibilityButton(labelled: "Hotovo", in: window) != nil }
                let stored = "Nový kód mám uložený mimo tento Mac"
                try await waitUntil { accessibilityElement(labelled: stored, in: window) != nil }
                let done = try #require(accessibilityButton(labelled: "Hotovo", in: window))
                let checkbox = try #require(accessibilityElement(labelled: stored, in: window))
                #expect(checkbox.accessibilityRole?() == .checkBox)
                #expect(done.isAccessibilityEnabled?() == false)

                #expect(checkbox.accessibilityPerformPress?() == true)
                try await waitUntil { done.isAccessibilityEnabled?() == true }

                #expect(checkbox.accessibilityPerformPress?() == true)
                try await waitUntil { done.isAccessibilityEnabled?() == false }
            }
        }
    }

    /// The sheet Obnovit ze zálohy chooses among the backups in rows of the design: the chosen one on the pale blue
    /// with a ring of the accent, the others on the inset background, and ends in Zrušit and Obnovit, 32 points tall.
    @Test(arguments: [ColorScheme.light, .dark])
    func theBackupChosenInTheRestoreSheetIsAPaleBlueRowWithARingOfTheAccent(scheme: ColorScheme) async throws {
        try await EditorFixture.with { f in
            f.app.showSettings(.security)
            let security = SecurityTabModel(app: f.app)
            security.load()
            let sheet = RestoreSheet(app: f.app, security: security) {}

            try await withHostedView(sheet, size: CGSize(width: 560, height: 600)) { window in
                window.appearance = NSAppearance(named: scheme == .light ? .aqua : .darkAqua)
                try await withAccessibilityElements {
                    try await waitUntil { accessibilityElement(labelled: "Zálohy", in: window) != nil }
                    let list = try #require(accessibilityElement(labelled: "Zálohy", in: window))
                    let row = try #require(firstButton(among: list.accessibilityChildren?() ?? []))
                    let frame = try pictureFrame(ofScreenFrame: try #require(row.accessibilityFrame?()), in: window)
                    let inset = try OffscreenPicture.bytes(of: Palette.bgInset, in: scheme)
                    let paleBlue = try OffscreenPicture.bytes(of: Palette.accentTint, in: scheme)
                    let accent = try OffscreenPicture.bytes(of: Palette.accent, in: scheme)
                    let before = try OffscreenPicture(of: window)
                    #expect(
                        pixelIs(inset, at: CGPoint(x: frame.minX + 6, y: frame.midY), in: before),
                        "\(scheme): a row that is not chosen is not on the inset background")

                    #expect(row.accessibilityPerformPress?() == true)
                    try await waitUntil { row.isAccessibilitySelected?() == true }
                    try await layOut(window)
                    let after = try OffscreenPicture(of: window)
                    #expect(
                        pixelIs(paleBlue, at: CGPoint(x: frame.minX + 6, y: frame.midY), in: after),
                        "\(scheme): the chosen row is not pale blue")
                    #expect(
                        after.count(near: accent, in: frame.insetBy(dx: -2, dy: -2), by: 2) > 200,
                        "\(scheme): the chosen row has no ring of the accent")
                    for title in ["Zrušit", "Obnovit"] {
                        let height = try height(ofButton: title, in: window)
                        #expect(abs(height - 32) < 0.5, "\(scheme): \(title) is \(height) points tall")
                    }
                }
            }
        }
    }

    /// The sheet with the text of a licence ends in Zavřít, a capsule in the accent 32 points tall, over the text on
    /// the inset background; Esc closes it.
    @Test func theSheetOfALicenceEndsInACapsuleOfTheAccentOverTheTextOnTheInsetBackground() async throws {
        let calls = SheetCalls()
        let sheet = LicenseSheet(licence: AppTabModel.licences[0]) { calls.closed += 1 }

        try await withHostedView(sheet, size: CGSize(width: 640, height: 640)) { window in
            window.appearance = NSAppearance(named: .aqua)
            try await withAccessibilityElements {
                try await waitUntil { accessibilityButton(labelled: "Zavřít", in: window) != nil }
                try await layOut(window)
                let height = try height(ofButton: "Zavřít", in: window)
                #expect(abs(height - 32) < 0.5, "Zavřít is \(height) points tall")
                let closeFrame = try #require(
                    accessibilityButton(labelled: "Zavřít", in: window)?.accessibilityFrame?())
                let close = try pictureFrame(ofScreenFrame: closeFrame, in: window)
                let picture = try OffscreenPicture(of: window)
                let accent = try OffscreenPicture.bytes(of: Palette.accent, in: .light)
                let inset = try OffscreenPicture.bytes(of: Palette.bgInset, in: .light)

                #expect(
                    picture.extent(near: accent, in: close.insetBy(dx: -2, dy: -2), by: 2) != nil,
                    "Zavřít is not in the accent")
                #expect(picture.count(near: inset, in: CGRect(origin: .zero, size: picture.size), by: 2) > 20_000)
                #expect(try press(.escape, in: window))
                #expect(calls.closed == 1)
            }
        }
    }
}
