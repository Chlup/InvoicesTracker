import AppKit
import SwiftUI
import Testing

@testable import InvoicesTracker

/// The invoice editor, its chooser and the question before an invoice is thrown away in windows, made as the app makes
/// them, on the data of `EditorFixture` (three clients, two templates and the sample year 2026, as of 17. 10. 2026):
/// the chips of the clients, the buttons, the bars, the notes and the aside with the preview, as VoiceOver reads their
/// frames and as the pixels of the window show their colours, in a light and in a dark appearance. The window is
/// light or dark whatever the Mac is.
///
/// The controls are found by the labels VoiceOver reads them under. The chooser is shown alone in a window
/// (`withHostedView`), so the window has no background of its own and the pixels that are looked at are those of the
/// panels, which lie on their own colour.
@Suite(.serialized, .settlesBackups)
@MainActor
struct InvoiceEditorWindowTests {
    /// What a page needs is measured in the font it is set in, so the fonts are registered before any test, as the app
    /// does at its launch.
    init() {
        InvoiceFonts.register()
    }

    // MARK: What the tests look at

    /// `screen`, a frame in the coordinates of the screen with the origin at its bottom left, as points from the top
    /// left of the content of `window`, where a picture of the window counts them.
    private func pictureFrame(of screen: CGRect, in window: NSWindow) throws -> CGRect {
        let frame = window.convertFromScreen(screen)
        let height = try #require(window.contentView).bounds.height
        return CGRect(x: frame.minX, y: height - frame.maxY, width: frame.width, height: frame.height)
    }

    /// The frame of the button that VoiceOver reads under `label` in `window`, in points from the top left of its
    /// content.
    private func buttonFrame(_ label: String, in window: NSWindow) throws -> CGRect {
        let screen = try #require(
            accessibilityButton(labelled: label, in: window)?.accessibilityFrame?(), "No button \(label)")
        return try pictureFrame(of: screen, in: window)
    }

    /// The frame of the card that VoiceOver reads under `label` in `window`, in points from the top left of its
    /// content.
    private func cardFrame(_ label: String, in window: NSWindow) throws -> CGRect {
        try pictureFrame(of: try #require(frameOfCard(labelled: label, in: window), "No card \(label)"), in: window)
    }

    /// The frame of the first group of `window` that holds a text which VoiceOver reads as `text`, such as a bar, in
    /// points from the top left of its content.
    private func groupFrame(holdingText text: String, in window: NSWindow) throws -> CGRect {
        try pictureFrame(
            of: try #require(frameOfGroup(holdingText: text, in: window), "No group holding \(text)"), in: window)
    }

    /// The frame of the first text of `window` that VoiceOver reads as a phrase starting with `phrase`, in points from
    /// the top left of its content.
    private func textFrame(startingWith phrase: String, in window: NSWindow) throws -> CGRect {
        try pictureFrame(
            of: try #require(frameOfText(startingWith: phrase, in: window), "No text \(phrase)"), in: window)
    }

    /// Whether the pixel at `point` of `picture` is `colour`, within 2 levels in every channel. A point outside the
    /// picture, such as one of a button under the fold of the page, is no colour at all.
    private func isColour(_ colour: [Int], at point: CGPoint, in picture: OffscreenPicture) -> Bool {
        guard let found = pixel(at: point, in: picture) else { return false }
        return zip(found, colour).allSatisfy { abs($0 - $1) <= 2 }
    }

    /// The bytes of the pixel at `point` of `picture`, or nil where the point is outside it.
    private func pixel(at point: CGPoint, in picture: OffscreenPicture) -> [Int]? {
        guard CGRect(origin: .zero, size: picture.size).contains(point) else { return nil }
        return picture.bytes(at: point)
    }

    /// The pixel at `point` of `picture` as a failed expectation says it.
    private func described(_ point: CGPoint, in picture: OffscreenPicture) -> String {
        pixel(at: point, in: picture).map { "\($0)" } ?? "outside the picture"
    }

    /// Expects the pixel at `point` of `picture` to be `colour`, and says what `what` is instead when it is not.
    private func expectColour(
        _ colour: [Int], at point: CGPoint, in picture: OffscreenPicture, _ what: String,
        sourceLocation: SourceLocation = #_sourceLocation
    ) {
        #expect(
            isColour(colour, at: point, in: picture), "\(what) is \(described(point, in: picture))",
            sourceLocation: sourceLocation)
    }

    /// Expects `bar`, a frame in points from the top left of `picture`, to be a panel on the window: the colour of a
    /// card, with the corners of a panel (10 points). The window shows 1,5 points in from the corner both ways, where
    /// the corner is cut, and the card shows 3,5 points in, where the corners of a card, 16 points deep, would still
    /// show the window.
    private func expectPanelOnTheWindow(_ bar: CGRect, in picture: OffscreenPicture, scheme: ColorScheme) throws {
        let card = try bytes(Palette.bgCard, scheme)
        let window = try bytes(Palette.bgWindow, scheme)

        let cut = CGPoint(x: bar.minX + 1.5, y: bar.minY + 1.5)
        expectColour(window, at: cut, in: picture, "\(scheme): the corner of the bar, 1,5 points in,")
        let rounded = CGPoint(x: bar.minX + 3.5, y: bar.minY + 3.5)
        expectColour(card, at: rounded, in: picture, "\(scheme): the corner of the bar, 3,5 points in,")
        let padding = CGPoint(x: bar.minX + 10, y: bar.midY)
        expectColour(card, at: padding, in: picture, "\(scheme): the padding of the bar")
    }

    /// Scrolls the form of the editor to its end, where the buttons are, and lays the window out again: the form is
    /// taller than the window, and a picture of the window shows only what is in it.
    private func scrollTheFormToItsEnd(in window: NSWindow) async throws {
        let scrollViews = allScrollViews(in: try #require(window.contentView)).filter {
            !($0.documentView is NSTableView)
        }
        let form = try #require(
            scrollViews.max { ($0.documentView?.frame.height ?? 0) < ($1.documentView?.frame.height ?? 0) })
        let room = form.contentView.bounds.height
        let end = max(0, (form.documentView?.frame.height ?? 0) - room)
        form.contentView.scroll(to: NSPoint(x: 0, y: end))
        form.reflectScrolledClipView(form.contentView)
        try await layOut(window)
    }

    /// The scroll views under `view`, and `view` itself where it is one.
    private func allScrollViews(in view: NSView) -> [NSScrollView] {
        if let scrollView = view as? NSScrollView {
            return [scrollView]
        }
        return view.subviews.flatMap { allScrollViews(in: $0) }
    }

    /// The bytes of `color` in a window of `scheme`.
    private func bytes(_ color: Color, _ scheme: ColorScheme) throws -> [Int] {
        try OffscreenPicture.bytes(of: color, in: scheme)
    }

    /// Shows the window of the app on `fixture` in the `scheme` appearance, opens the editor on a new invoice from
    /// `template` (a blank one without), waits until it has worked the invoice out, and gives the window to `body`
    /// with the accessibility elements on.
    private func withEditor(
        _ fixture: EditorFixture, template: InvoiceTemplate?, size: CGSize = AppWindowSize.large,
        scheme: ColorScheme = .light, _ body: (NSWindow, InvoiceEditorModel) async throws -> Void
    ) async throws {
        try await withAppWindow(of: fixture.app, size: size) { window in
            window.appearance = NSAppearance(named: scheme == .light ? .aqua : .darkAqua)
            fixture.app.startNewInvoice(templateID: template?.id)
            try await waitUntil { fixture.app.editor != nil && window.title == "Nová faktura" }
            let editor = try #require(fixture.app.editor)
            try await waitUntil { editor.document != nil }
            try await withAccessibilityElements {
                try await waitUntil { accessibilityButton(labelled: "Zrušit", in: window) != nil }
                try await layOut(window)
                try await body(window, editor)
            }
        }
    }

    /// Shows the window of the app on `fixture` in the `scheme` appearance, opens the editor on the invoice `id`, and
    /// gives the window to `body`, with the accessibility elements on.
    private func withEditorOfInvoice(
        _ id: Int64, on fixture: EditorFixture, scheme: ColorScheme = .light,
        _ body: (NSWindow, InvoiceEditorModel) async throws -> Void
    ) async throws {
        try await withAppWindow(of: fixture.app, size: AppWindowSize.large) { window in
            window.appearance = NSAppearance(named: scheme == .light ? .aqua : .darkAqua)
            fixture.app.screen = .invoices
            fixture.app.editorRequest = .edit(id)
            try await waitUntil { fixture.app.editor != nil && window.title.hasPrefix("Upravit fakturu ") }
            let editor = try #require(fixture.app.editor)
            try await withAccessibilityElements {
                try await waitUntil { accessibilityButton(labelled: "Zrušit", in: window) != nil }
                try await layOut(window)
                try await body(window, editor)
            }
        }
    }

    // MARK: The chips of the clients

    /// The client of the invoice is chosen among chips of 28 points, the one of the invoice filled with the accent and
    /// the others in the colour of a card.
    @Test(arguments: [ColorScheme.light, .dark])
    func theClientIsChosenWithChipsOf28PointsTheOneOfTheInvoiceInTheAccent(scheme: ColorScheme) async throws {
        try await EditorFixture.with { f in
            try await withEditor(f, template: f.dollarTemplate, scheme: scheme) { window, _ in
                let picture = try OffscreenPicture(of: window)
                let accent = try bytes(Palette.accent, scheme)
                let card = try bytes(Palette.bgCard, scheme)

                for name in ["Alfa Systems s.r.o.", "Bravo Labs, Inc.", "Cetus Data s.r.o."] {
                    let chip = try buttonFrame(name, in: window)
                    #expect(abs(chip.height - DesignMetrics.smallControlHeight) < 0.5, "\(name): \(chip)")
                    let selected = name == "Bravo Labs, Inc."
                    let expected = selected ? accent : card
                    let point = CGPoint(x: chip.minX + 8, y: chip.midY)
                    expectColour(expected, at: point, in: picture, "\(scheme): the chip of \(name)")
                    let element = try #require(accessibilityButton(labelled: name, in: window))
                    #expect((element.isAccessibilitySelected?() == true) == selected, "\(name)")
                }
            }
        }
    }

    // MARK: The buttons

    /// The buttons of the editor are the capsules of the design, 32 points tall, at the trailing end under the form:
    /// Zrušit on the grey fill, Uložit koncept in the colour of a card with the shadow of a control, because it stands
    /// on the window itself, and the main one, Vystavit fakturu, in the accent. "Vybrat jinou" in the bar of the
    /// template and "Přidat položku" under the items are the capsules of a card, 28 points tall, on the grey fill.
    @Test(arguments: [ColorScheme.light, .dark])
    func theButtonsOfTheEditorAreTheCapsulesOfTheDesign(scheme: ColorScheme) async throws {
        try await EditorFixture.with { f in
            try await withEditor(f, template: f.crownTemplate, scheme: scheme) { window, editor in
                try await waitUntil { editor.canIssue }
                let fill = try bytes(Palette.fill, scheme)
                let card = try bytes(Palette.bgCard, scheme)
                let accent = try bytes(Palette.accent, scheme)

                // Under the toolbar and in the cards.
                var picture = try OffscreenPicture(of: window)
                for name in ["Vybrat jinou", "Přidat položku"] {
                    let frame = try buttonFrame(name, in: window)
                    let point = CGPoint(x: frame.minX + 8, y: frame.midY)
                    #expect(abs(frame.height - DesignMetrics.smallControlHeight) < 0.5, "\(name): \(frame)")
                    expectColour(fill, at: point, in: picture, "\(scheme): \(name)")
                }

                // At the end of the form.
                try await scrollTheFormToItsEnd(in: window)
                picture = try OffscreenPicture(of: window)
                let cancel = try buttonFrame("Zrušit", in: window)
                let draft = try buttonFrame("Uložit koncept", in: window)
                let issue = try buttonFrame("Vystavit fakturu", in: window)
                for (name, frame) in [("Zrušit", cancel), ("Uložit koncept", draft), ("Vystavit fakturu", issue)] {
                    #expect(abs(frame.height - DesignMetrics.regularControlHeight) < 0.5, "\(name): \(frame)")
                }
                #expect(cancel.maxX < draft.minX && draft.maxX < issue.minX, "The order: \(cancel) \(draft) \(issue)")
                let colours = [(cancel, fill, "Zrušit"), (draft, card, "Uložit koncept"), (issue, accent, "Vystavit")]
                for (frame, colour, name) in colours {
                    let point = CGPoint(x: frame.minX + 8, y: frame.midY)
                    expectColour(colour, at: point, in: picture, "\(scheme): \(name)")
                }
                // They end where the form ends, at the trailing margin of the page.
                let form = try cardFrame("Odběratel a doklad", in: window)
                #expect(abs(issue.maxX - form.maxX) < 1, "\(issue) under \(form)")
            }
        }
    }

    // MARK: The bars

    /// The bar of the template over a new invoice is a panel on the window, not a card: the colour of a card, with the
    /// corners of a panel.
    @Test(arguments: [ColorScheme.light, .dark])
    func theBarOfTheTemplateIsAPanelOnTheWindow(scheme: ColorScheme) async throws {
        try await EditorFixture.with { f in
            try await withEditor(f, template: f.dollarTemplate, scheme: scheme) { window, _ in
                let bar = try groupFrame(holdingText: "Šablona", in: window)
                let picture = try OffscreenPicture(of: window)

                try expectPanelOnTheWindow(bar, in: picture, scheme: scheme)
            }
        }
    }

    /// The bar of an invoice that is edited is a panel on the window too, with the state of the invoice in the grey of
    /// captions and, for an invoice that is issued, the warning under it as a note of attention: the pale orange of an
    /// estimate behind it.
    @Test(arguments: [ColorScheme.light, .dark])
    func theBarOfAnInvoiceThatIsEditedIsAPanelWithTheWarningOfAnAttentionNote(scheme: ColorScheme) async throws {
        try await EditorFixture.with { f in
            try await withEditorOfInvoice(10, on: f, scheme: scheme) { window, _ in
                let bar = try groupFrame(holdingText: "Upravujete fakturu", in: window)
                let picture = try OffscreenPicture(of: window)
                let tint = try bytes(Palette.orangeTint, scheme)
                let caption = try bytes(Palette.text3, scheme)

                try expectPanelOnTheWindow(bar, in: picture, scheme: scheme)
                let warning = try textFrame(startingWith: "Faktura už je vystavená.", in: window)
                let corner = CGPoint(x: warning.minX + 4, y: warning.minY + 4)
                expectColour(tint, at: corner, in: picture, "\(scheme): the warning")
                // The state of the invoice, "vystavená … · uhrazená …", is a caption.
                let state = try textFrame(startingWith: "vystavená", in: window)
                #expect(picture.count(near: caption, in: state, by: 12) > 20, "\(scheme): the state is not a caption")
            }
        }
    }

    // MARK: The sections

    /// The words of a row are in the grey of secondary text, and the lines that explain a row (what the client starts
    /// an invoice with, what the number is, what the QR code is) in the grey of captions, one shade lighter.
    @Test(arguments: [ColorScheme.light, .dark])
    func theLabelsAreSecondaryTextAndTheLinesThatExplainThemAreCaptions(scheme: ColorScheme) async throws {
        try await EditorFixture.with { f in
            try await withEditor(f, template: f.crownTemplate, scheme: scheme) { window, _ in
                let picture = try OffscreenPicture(of: window)
                let label = try bytes(Palette.text2, scheme)
                let caption = try bytes(Palette.text3, scheme)

                for phrase in ["Odběratel", "Číslo faktury", "Splatnost", "Platba", "Režim DPH", "QR platba"] {
                    let frame = try textFrame(startingWith: phrase, in: window)
                    #expect(picture.count(near: label, in: frame, by: 12) > 5, "\(scheme): \(phrase) is not secondary")
                }
                for phrase in ["výchozí:", "řada RRRRMMPP", "QR Platba s číslem účtu"] {
                    let frame = try textFrame(startingWith: phrase, in: window)
                    #expect(
                        picture.count(near: caption, in: frame, by: 12) > 5, "\(scheme): \(phrase) is not a caption")
                }
            }
        }
    }

    /// The cards of the form are read under the names the design gives them, and the card of the items and the card of
    /// the note, which have a title, under "Položky" and "Poznámka".
    @Test func theCardsOfTheFormAreReadUnderTheNamesOfTheDesign() async throws {
        try await EditorFixture.with { f in
            try await withEditor(f, template: f.crownTemplate) { window, _ in
                for name in ["Odběratel a doklad", "Platba, měna a DPH", "Položky", "Poznámka", "Náhled PDF"] {
                    #expect(frameOfCard(labelled: name, in: window) != nil, "No card \(name)")
                }
            }
        }
    }

    // MARK: The items, the note and what stops the invoice

    /// The total of the invoice stands under a rule of the stronger colour of a line, as the total of a bill does.
    @Test(arguments: [ColorScheme.light, .dark])
    func theTotalStandsUnderAStrongerRuleThanTheTotalsDo(scheme: ColorScheme) async throws {
        try await EditorFixture.with { f in
            try await withEditor(f, template: f.crownTemplate, scheme: scheme) { window, editor in
                let picture = try OffscreenPicture(of: window)
                let strong = try bytes(Palette.sepStrong, scheme)
                let amount = try #require(editor.totals?.total)
                let total = try textFrame(startingWith: amount, in: window)

                // The rule is 1 point thick, 8 points over the words, and runs under the amounts at the trailing side.
                let above = CGRect(x: total.minX, y: total.minY - 14, width: 200, height: 12)
                #expect(picture.count(near: strong, in: above, by: 2) > 100, "\(scheme): no rule over the total")
            }
        }
    }

    /// What stops the invoice from being issued is said over its buttons in the orange of attention, one line under the
    /// other at the trailing side. A blank invoice has no items yet.
    @Test(arguments: [ColorScheme.light, .dark])
    func whatStopsTheInvoiceIsSaidInTheOrangeOfAttention(scheme: ColorScheme) async throws {
        try await EditorFixture.with { f in
            try await withEditor(f, template: nil, scheme: scheme) { window, editor in
                try await waitUntil { !editor.validation.isEmpty }
                try await scrollTheFormToItsEnd(in: window)
                let picture = try OffscreenPicture(of: window)
                let orange = try bytes(Palette.orangeText, scheme)
                let line = try #require(editor.validation.first)

                let frame = try textFrame(startingWith: line, in: window)
                #expect(picture.count(near: orange, in: frame, by: 12) > 10, "\(scheme): \(line) is not orange")
            }
        }
    }

    /// A note of more lines than the page prints says so in the red of an error, where it says what it is for in the
    /// grey of captions.
    @Test(arguments: [ColorScheme.light, .dark])
    func aNoteThatIsTooLongSaysSoInRed(scheme: ColorScheme) async throws {
        try await EditorFixture.with { f in
            try await withEditor(f, template: f.crownTemplate, scheme: scheme) { window, editor in
                let hint = "Vytiskne se dole na faktuře."
                editor.note = InvoicePageFixtures.note(lines: 21)
                try await scrollTheFormToItsEnd(in: window)
                let red = try bytes(Palette.redText, scheme)
                var picture = try OffscreenPicture(of: window)
                var frame = try textFrame(startingWith: hint, in: window)
                #expect(picture.count(near: red, in: frame, by: 12) > 20, "\(scheme): the hint is not red")

                editor.note = InvoicePageFixtures.note(lines: 20)
                try await layOut(window)
                picture = try OffscreenPicture(of: window)
                frame = try textFrame(startingWith: hint, in: window)
                let caption = try bytes(Palette.text3, scheme)
                #expect(picture.count(near: red, in: frame, by: 12) == 0, "\(scheme): the hint is red")
                #expect(picture.count(near: caption, in: frame, by: 12) > 20, "\(scheme): the hint is not a caption")
            }
        }
    }

    /// While the note is empty it shows its example in the grey of captions, and a note that has text shows none.
    @Test(arguments: [ColorScheme.light, .dark])
    func anEmptyNoteShowsItsExampleAndANoteWithTextDoesNot(scheme: ColorScheme) async throws {
        try await EditorFixture.with { f in
            try await withEditor(f, template: f.crownTemplate, scheme: scheme) { window, editor in
                try await scrollTheFormToItsEnd(in: window)
                let caption = try bytes(Palette.text3, scheme)
                let card = try cardFrame("Poznámka", in: window)
                // Where the text of the note stands: under the title of the card, over the line that says what it
                // is for.
                let field = CGRect(x: card.minX + 20, y: card.minY + 60, width: card.width - 40, height: 40)

                var picture = try OffscreenPicture(of: window)
                #expect(editor.note.isEmpty)
                let withExample = picture.count(near: caption, in: field, by: 12)
                #expect(withExample > 20, "\(scheme): no example in the note")

                // The words of a note are in the colour of text, whose soft edges come to the grey of captions in a few
                // pixels only.
                editor.note = "Platba do 14 dnů."
                try await layOut(window)
                picture = try OffscreenPicture(of: window)
                let withText = picture.count(near: caption, in: field, by: 12)
                #expect(withText * 3 < withExample, "\(scheme): \(withText) pixels with text, \(withExample) without")
            }
        }
    }

    // MARK: The note of the impact

    /// What the invoice does to the levies is the note of an estimate: the pale orange of attention with the circle of
    /// information, its heading in semibold and its sentence under it, read as "Dopad na odvody".
    @Test(arguments: [ColorScheme.light, .dark])
    func theImpactOnTheLeviesIsTheNoteOfAnEstimate(scheme: ColorScheme) async throws {
        try await EditorFixture.with { f in
            try await withEditor(f, template: f.crownTemplate, scheme: scheme) { window, editor in
                try await waitUntil { editor.impactText != nil }
                try await waitUntil { frameOfCard(labelled: "Dopad na odvody", in: window) != nil }
                try await scrollTheFormToItsEnd(in: window)
                let box = try cardFrame("Dopad na odvody", in: window)
                let picture = try OffscreenPicture(of: window)
                let tint = try bytes(Palette.orangeTint, scheme)
                let text = try bytes(Palette.text, scheme)
                let heading = try #require(editor.impactText)

                expectColour(tint, at: CGPoint(x: box.minX + 4, y: box.minY + 4), in: picture, "\(scheme): the note")
                #expect(heading.hasPrefix("Až přijde platba, přibude k odvodům za rok 2026 zhruba "))
                let words = try textFrame(startingWith: heading, in: window)
                #expect(picture.count(near: text, in: words, by: 12) > 40, "\(scheme): the words are not text")
            }
        }
    }

    // MARK: The aside with the preview

    /// In a large window the preview is an aside of 461 points beside the form, on the fill of the design, at the
    /// trailing margin of the page, 16 points from the form, level with the top of the form.
    @Test(arguments: [ColorScheme.light, .dark])
    func theAsideStandsBesideTheFormAt461PointsInALargeWindow(scheme: ColorScheme) async throws {
        try await EditorFixture.with { f in
            try await withEditor(f, template: f.crownTemplate, scheme: scheme) { window, _ in
                let aside = try cardFrame("Náhled PDF", in: window)
                let form = try cardFrame("Odběratel a doklad", in: window)
                let picture = try OffscreenPicture(of: window)
                let fill = try bytes(Palette.fill, scheme)
                let content = try #require(window.contentView).bounds

                #expect(abs(aside.width - PreviewPane.width) < 0.5, "The aside is \(aside)")
                #expect(abs(aside.maxX - (content.maxX - DesignMetrics.pageTrailing)) < 1, "The aside is \(aside)")
                #expect(
                    abs(aside.minX - form.maxX - DesignMetrics.cardSpacing) < 1,
                    "The form is \(form), the aside \(aside)")
                let beside = CGPoint(x: aside.minX + 8, y: aside.minY + 120)
                expectColour(fill, at: beside, in: picture, "\(scheme): the aside")
            }
        }
    }

    /// In the least window the preview comes under the form, as wide as the form is, and the editor still fits.
    @Test func theAsideComesUnderTheFormInTheLeastWindow() async throws {
        try await EditorFixture.with { f in
            try await withEditor(f, template: f.crownTemplate, size: AppWindowSize.minimum) { window, _ in
                let aside = try cardFrame("Náhled PDF", in: window)
                let form = try cardFrame("Odběratel a doklad", in: window)
                let buttons = try buttonFrame("Vystavit fakturu", in: window)

                #expect(aside.minY >= buttons.maxY, "The aside \(aside) is not under the buttons \(buttons)")
                #expect(abs(aside.minX - form.minX) < 1 && abs(aside.width - form.width) < 1, "\(aside) and \(form)")
            }
        }
    }

    /// The preview stands beside the form from 1 107 points of room for the editor, the 590 points that the rows of the
    /// items need, the gap of 16, the aside of 461 and the margins of the page, 24 and 16. The window of the tests has
    /// the sidebar of 232 points, so 1 339 points of window give the editor 1 107: 1 330 is under, and 1 340 over.
    @Test(arguments: [(1_330, false), (1_340, true)])
    func thePreviewStandsBesideTheFormOnlyWhereTheFormKeepsItsLeastWidth(width: Int, beside: Bool) async throws {
        try await EditorFixture.with { f in
            let size = CGSize(width: CGFloat(width), height: 1_000)
            try await withEditor(f, template: f.crownTemplate, size: size) { window, _ in
                let aside = try cardFrame("Náhled PDF", in: window)
                let form = try cardFrame("Odběratel a doklad", in: window)

                #expect((aside.minX >= form.maxX) == beside, "At \(width): the form is \(form), the aside \(aside)")
            }
        }
    }

    // MARK: The chooser

    /// The choices of the chooser are panels on the inset background, with the corners of a panel and a line of the
    /// colour of the separators around them, and under them the link to Odběratelé in the blue of a link that
    /// VoiceOver reads as a link, and Zrušit, a capsule of 32 points on the grey fill, at the trailing end.
    @Test(arguments: [ColorScheme.light, .dark])
    func theChoicesAreInsetPanelsAndTheFooterHasALinkAndZrusit(scheme: ColorScheme) async throws {
        try await EditorFixture.with { f in
            try await withHostedView(NewInvoiceChooser(app: f.app), size: CGSize(width: 620, height: 640)) { window in
                window.appearance = NSAppearance(named: scheme == .light ? .aqua : .darkAqua)
                try await withAccessibilityElements {
                    let link = "Šablony upravíte u odběratelů"
                    try await waitUntil {
                        accessibilityElement(labelStartingWith: "Služby pro Alfa", in: window) != nil
                    }
                    try await layOut(window)
                    let row = try #require(accessibilityElement(labelStartingWith: "Služby pro Alfa", in: window))
                    let rowFrame = try pictureFrame(of: try #require(row.accessibilityFrame?()), in: window)
                    let picture = try OffscreenPicture(of: window)
                    let inset = try bytes(Palette.bgInset, scheme)
                    let line = try bytes(Palette.sep, scheme)
                    let fill = try bytes(Palette.fill, scheme)
                    let accentText = try bytes(Palette.accentText, scheme)

                    let inside = CGPoint(x: rowFrame.minX + 6, y: rowFrame.midY)
                    expectColour(inset, at: inside, in: picture, "\(scheme): the choice")
                    // The corners of a panel are cut 10 points deep, so 4,5 points in from the corner both ways is
                    // inside it (the corners of a card, 16 points deep, would be cut there), and the line around it
                    // is the colour of the separators.
                    let corner = CGPoint(x: rowFrame.minX + 4.5, y: rowFrame.minY + 4.5)
                    expectColour(inset, at: corner, in: picture, "\(scheme): the corner of the choice")
                    let top = CGPoint(x: rowFrame.midX, y: rowFrame.minY + 0.5)
                    expectColour(line, at: top, in: picture, "\(scheme): the line around the choice")
                    let zrusit = try buttonFrame("Zrušit", in: window)
                    #expect(abs(zrusit.height - DesignMetrics.regularControlHeight) < 0.5, "Zrušit: \(zrusit)")
                    let cap = CGPoint(x: zrusit.minX + 8, y: zrusit.midY)
                    expectColour(fill, at: cap, in: picture, "\(scheme): Zrušit")
                    let linkElement = try #require(accessibilityElement(labelled: link, in: window))
                    let linkFrame = try pictureFrame(of: try #require(linkElement.accessibilityFrame?()), in: window)
                    #expect(linkElement.accessibilityRole?() == .link)
                    #expect(
                        picture.count(near: accentText, in: linkFrame, by: 12) > 20, "\(scheme): the link is not blue")
                    #expect(linkFrame.maxX < zrusit.minX)
                    #expect(abs(linkFrame.minX - rowFrame.minX) < 1, "\(linkFrame) under \(rowFrame)")
                }
            }
        }
    }

    // MARK: The question before an invoice is thrown away

    /// The question that the window asks over the editor has the capsules of a dialog, 32 points tall: Pokračovat v
    /// úpravách on the grey fill, which Esc is too, and Zahodit in the solid red of what cannot be undone.
    @Test(arguments: [ColorScheme.light, .dark])
    func theQuestionHasTheCapsulesOfADialogAndZahoditIsRed(scheme: ColorScheme) async throws {
        try await EditorFixture.with { f in
            try await withEditor(f, template: f.crownTemplate, scheme: scheme) { window, editor in
                editor.note = "Typed note"
                try await waitUntil { f.app.editorHasChanges }

                f.app.leaveEditor()

                try await waitUntil { accessibilityButton(labelled: "Zahodit", in: window) != nil }
                try await layOut(window)
                let keep = try buttonFrame("Pokračovat v úpravách", in: window)
                let discard = try buttonFrame("Zahodit", in: window)
                let picture = try OffscreenPicture(of: window)
                let fill = try bytes(Palette.fill, scheme)
                let red = try bytes(Palette.red, scheme)

                for (name, frame) in [("Pokračovat v úpravách", keep), ("Zahodit", discard)] {
                    #expect(abs(frame.height - DesignMetrics.regularControlHeight) < 0.5, "\(name): \(frame)")
                }
                #expect(keep.maxX < discard.minX, "Zahodit is the last: \(keep) \(discard)")
                expectColour(fill, at: CGPoint(x: keep.minX + 8, y: keep.midY), in: picture, "\(scheme): keep")
                expectColour(red, at: CGPoint(x: discard.minX + 8, y: discard.midY), in: picture, "\(scheme): discard")
                let keepOn = try #require(accessibilityButton(labelled: "Pokračovat v úpravách", in: window))
                #expect(keepOn.accessibilityPerformPress?() == true)
            }
        }
    }
}
