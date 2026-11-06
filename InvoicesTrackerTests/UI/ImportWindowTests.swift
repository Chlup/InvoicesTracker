import AppKit
import SwiftUI
import Testing
@testable import InvoicesTracker

/// Import in a window, made as the app makes it, in a light and in a dark appearance, and looked at as the pixels of
/// the window and the frames VoiceOver reads show it: the card "Výběr souborů" with the zone where the files are
/// dropped, the two notes and the hint; the card "Před importem" with a row for each collected file, a row for each
/// outcome and the buttons; and the card "Průběh" while the import runs and once it is done, with the green panel, the
/// line of the clients, the offer to fill in the supplier and the lists. The page is shown alone in a tall window so
/// that it needs no scrolling, and in the window of the app at the least room and at a large size. The files are the
/// invented fixtures `fakturoid_sample.csv`, `fakturoid_reimport.csv` and `czk-21.isdoc`.
@Suite(.serialized, .settlesBackups)
@MainActor
struct ImportWindowTests {
    /// What a page needs is measured in the font it is set in, so the fonts are registered before any test, as the app
    /// does at its launch.
    init() {
        InvoiceFonts.register()
    }

    /// The room the page has: tall enough for every card with what it lists.
    private static let size = CGSize(width: 1_000, height: 1_700)

    /// The words of the drop zone.
    private static let zoneTitle = "Přetáhněte sem soubory CSV nebo ISDOC, nebo klikněte a vyberte je"
    private static let zoneDetail = "Exporty faktur z Fakturoidu · lze vybrat víc souborů najednou"

    /// The two notes of the card of the choice of files.
    private static let infoTitle = "Pro úplné faktury naimportujte oba exporty – CSV i ISDOC"
    private static let infoText =
        "Každý soubor se naimportuje samostatně a převezme se z něj jen to, co obsahuje. Faktura z jediného formátu"
        + " bude neúplná, dokud nenaimportujete i ten druhý."
    private static let attentionTitle = "Import přepíše faktury, které už v aplikaci máte"
    private static let attentionText =
        "Data ze souborů nahradí to, co jste u nich v aplikaci změnili. Tyto změny se ztratí a vrátit je nepůjde."

    /// The hint under the notes.
    private static let hint =
        "Faktury se spárují podle čísla: nové se přidají, zálohové a stornované se přeskočí. Soubory se čtou jen v"
        + " tomto počítači."

    /// An app on a new folder whose server answers once `gate` opens.
    private func makeApp(in directory: URL, gate: Gate) async throws -> AppModel {
        let yearly = try Data(contentsOf: fixtureURL("cnb_rok_2026", "txt"))
        let server = StubHTTPClient([CNBEndpoints.yearly(2026): yearly])
        let app = makeAppModel(in: directory, http: GatedHTTPClient(base: server, gate: gate))
        try await startFresh(app)
        return app
    }

    /// An app that has imported the sample, whose server answers at once, with the reimport of the sample, the ISDOC
    /// invoice and a file that is neither CSV nor ISDOC collected for the next import: the preview has invoices that
    /// are added, overwritten, unchanged and skipped.
    private func makeAppWithCollectedFiles(in directory: URL) async throws -> AppModel {
        let gate = Gate()
        await gate.open()
        let app = try await makeApp(in: directory, gate: gate)
        await app.importModel.importAll([try fixtureURL("fakturoid_sample", "csv")])
        let notes = directory.appending(path: "poznamky.txt")
        try Data("Poznámky k fakturám".utf8).write(to: notes)
        await app.importModel.addFiles([
            try fixtureURL("fakturoid_reimport", "csv"), try fixtureURL("czk-21", "isdoc"), notes,
        ])
        return app
    }

    /// How many pixels of `frame` there are, at the two pixels to a point of a picture.
    private func pixels(of frame: CGRect) -> Int {
        Int(frame.width * frame.height * 4)
    }

    // MARK: Výběr souborů

    /// The card of the choice of files, top to bottom: the zone where files are dropped, the accent tint with a ring of
    /// the soft accent, rounded by 10 points as a panel is (a corner of 14 would still be outside at 3.5 points in,
    /// where the ring is), with its words and the pill "Vybrat soubory…"; the information note that asks for both
    /// exports; the attention note that the import overwrites the invoices the app has; and the hint. There is no
    /// button for sample files, and on data that were never imported into there is no line of the last import.
    @Test(arguments: [ColorScheme.light, .dark])
    func theChoiceCardShowsTheDropZoneTheTwoNotesAndTheHint(scheme: ColorScheme) async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let app = try await makeApp(in: directory, gate: Gate())

        try await withHostedView(ImportScreen(app: app), size: Self.size) { window in
            window.appearance = appearance(of: scheme)
            try await withAccessibilityElements {
                try await waitUntil { accessibilityElement(labelStartingWith: Self.zoneTitle, in: window) != nil }
                try await layOut(window)
                let zoneElement = try #require(accessibilityElement(labelStartingWith: Self.zoneTitle, in: window))
                let zone = try pictureFrame(ofScreenFrame: try #require(zoneElement.accessibilityFrame?()), in: window)
                let picture = try OffscreenPicture(of: window)
                let tint = try OffscreenPicture.bytes(of: Palette.accentTint, in: scheme)
                let soft = try OffscreenPicture.bytes(of: Palette.accentSoft, in: scheme)
                let orangeTint = try OffscreenPicture.bytes(of: Palette.orangeTint, in: scheme)

                #expect(
                    pixelIs(tint, at: CGPoint(x: zone.minX + 12, y: zone.midY), in: picture),
                    "\(scheme): the zone is not the accent tint")
                #expect(
                    pixelIs(soft, at: CGPoint(x: zone.minX + 3.5, y: zone.minY + 3.5), in: picture),
                    "\(scheme): the zone has no ring of the soft accent rounded by 10 points")
                let label = (zoneElement.accessibilityLabel?() ?? "") as String
                #expect(label.contains(Self.zoneDetail), "The zone reads \(label)")
                #expect(label.contains("Vybrat soubory…"), "The zone reads \(label)")

                let card = try cardFrame("Výběr souborů", in: window)
                let info = try textFrame(startingWith: Self.infoTitle, in: window)
                let attention = try textFrame(startingWith: Self.attentionTitle, in: window)
                let hint = try textFrame(startingWith: Self.hint, in: window)
                #expect(zone.maxY < info.minY && info.maxY < attention.minY && attention.maxY < hint.minY)
                #expect(card.contains(hint), "The hint is not in the card")
                #expect(
                    picture.count(near: tint, in: info, by: 3) > pixels(of: info) / 3,
                    "\(scheme): the note that asks for both exports is not an information note")
                #expect(
                    picture.count(near: orangeTint, in: attention, by: 3) > pixels(of: attention) / 3,
                    "\(scheme): the note that the import overwrites is not an attention note")
                try picture.expectText(
                    in: hint, setIn: Palette.text2, atLeast: 60, scheme: scheme, "\(scheme): the hint")

                let readings = accessibilityReadings(in: window)
                for text in [Self.infoTitle, Self.infoText, Self.attentionTitle, Self.attentionText, Self.hint] {
                    #expect(readings.contains { $0.contains(text) }, "The card does not read \(text)")
                }
                #expect(!readings.contains { $0.contains("Vyzkoušet") })
                #expect(!readings.contains { $0.hasPrefix("Poslední import") })
            }
        }
    }

    /// The line of the last import shows under the hint only while no file is collected and no result is shown: not
    /// with the summary of the import that was just done, and not with files collected for the next one.
    @Test func theLastImportLineShowsOnlyWhileNoFileIsCollectedAndNoResultIsShown() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let gate = Gate()
        await gate.open()
        let app = try await makeApp(in: directory, gate: gate)
        await app.importModel.importAll([try fixtureURL("fakturoid_sample", "csv")])
        let last = try #require(app.importModel.lastImportLine)

        try await withHostedView(ImportScreen(app: app), size: Self.size) { window in
            try await withAccessibilityElements {
                try await waitUntil { frameOfText(startingWith: "Hotovo –", in: window) != nil }
                #expect(!showsText(last, in: window), "The line of the last import shows with the summary")
            }
        }

        // The data are opened again, as after a relaunch: the model of the import is a new one, with no summary.
        await app.open(try #require(app.database))
        await app.importModel.load()
        try await withHostedView(ImportScreen(app: app), size: Self.size) { window in
            try await withAccessibilityElements {
                try await waitUntil { showsText(last, in: window) }
                let card = try cardFrame("Výběr souborů", in: window)
                #expect(card.contains(try textFrame(startingWith: last, in: window)))

                await app.importModel.addFiles([try fixtureURL("fakturoid_reimport", "csv")])
                try await waitUntil { frameOfCard(labelled: "Kontrola před importem", in: window) != nil }
                #expect(!showsText(last, in: window), "The line of the last import shows with the files collected")
            }
        }
    }

    // MARK: Před importem

    /// The collected files and what importing them would do: the card "Před importem", read as "Kontrola před
    /// importem", with the count of the files on the right of its title. Each file is a row on the inset background
    /// with a grey pill of its kind (CSV, ISDOC, or ? for another file), its name, what it holds or why it cannot be
    /// used (in the red text), and an ✕ of 28 points read as "Odebrat <name>". Under the files, a row for each outcome
    /// under a hairline, with a dot of 8 points in its colour (green for what is added, orange for what is
    /// overwritten, the faintest grey otherwise), its count, and a note in the faint grey, or the orange text for what
    /// is overwritten. The buttons are "Zrušit" on the grey fill and the accent capsule that imports, 28 points tall,
    /// at the right.
    @Test(arguments: [ColorScheme.light, .dark])
    func collectedFilesShowTheReviewCardWithTheirOutcomeAndButtons(scheme: ColorScheme) async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let app = try await makeAppWithCollectedFiles(in: directory)
        let model = app.importModel
        #expect(model.files.map(\.name) == ["fakturoid_reimport.csv", "czk-21.isdoc", "poznamky.txt"])
        let labels = model.outcomeRows.map(\.label)
        try #require(labels.contains("Nové") && labels.contains("Přepíší se") && labels.contains("Beze změny"))
        #expect(model.canImport)

        try await withHostedView(ImportScreen(app: app), size: Self.size) { window in
            window.appearance = appearance(of: scheme)
            try await withAccessibilityElements {
                try await waitUntil { frameOfCard(labelled: "Kontrola před importem", in: window) != nil }
                try await layOut(window)
                let picture = try OffscreenPicture(of: window)
                let card = try cardFrame("Kontrola před importem", in: window)
                let choice = try cardFrame("Výběr souborů", in: window)
                #expect(abs(card.minY - choice.maxY - 16) < 1, "The cards are \(card.minY - choice.maxY) apart")
                let readings = accessibilityReadings(in: window)
                #expect(readings.contains("Před importem"))
                #expect(readings.contains("3\u{00A0}soubory"))

                // The files.
                let inset = try OffscreenPicture.bytes(of: Palette.bgInset, in: scheme)
                let fill = try OffscreenPicture.bytes(of: Palette.fill, in: scheme)
                let redText = try OffscreenPicture.bytes(of: Palette.redText, in: scheme)
                for (file, pill) in zip(model.files, ["CSV", "ISDOC", "?"]) {
                    let name = try textFrame(startingWith: file.name, in: window)
                    #expect(card.contains(name), "\(file.name) is not in the card")
                    #expect(
                        pixelIs(inset, at: CGPoint(x: name.minX - 5, y: name.midY), in: picture),
                        "\(scheme): the row of \(file.name) is not on the inset background")
                    #expect(readings.contains(pill), "No pill \(pill)")
                    let detail = ImportPreviewText.fileDetail(of: file)
                    #expect(readings.contains(detail), "\(file.name) does not read \(detail)")
                    let remove = try buttonFrame("Odebrat \(file.name)", in: window)
                    #expect(abs(remove.width - 28) < 0.5 && abs(remove.height - 28) < 0.5, "✕ is \(remove.size)")
                    #expect(remove.minX > name.maxX && abs(remove.midY - name.midY) < 8)
                }
                let pillFrame = try textFrame(startingWith: "ISDOC", in: window)
                #expect(
                    picture.count(near: fill, in: pillFrame.insetBy(dx: -4, dy: 0), by: 3) > pixels(of: pillFrame) / 3,
                    "\(scheme): the pill of the kind is not on the grey fill")
                let failed = try textFrame(startingWith: ImportPreviewText.fileDetail(of: model.files[2]), in: window)
                #expect(
                    picture.count(near: redText, in: failed, by: 6) > 15,
                    "\(scheme): the error of the file that cannot be used is not in the red text")

                // The outcome.
                let dots: [String: Color] = ["Nové": Palette.green, "Přepíší se": Palette.orange]
                for row in model.outcomeRows {
                    let label = try textFrame(startingWith: row.label, in: window)
                    #expect(card.contains(label), "\(row.label) is not in the card")
                    let colour = try OffscreenPicture.bytes(of: dots[row.label] ?? Palette.text4, in: scheme)
                    #expect(
                        pixelIs(colour, at: CGPoint(x: label.minX - 12, y: label.midY), in: picture, within: 6),
                        "\(scheme): the dot of \(row.label) is not in its colour")
                    #expect(readings.contains(row.note), "\(row.label) does not read \(row.note)")
                    #expect(readings.contains(String(row.count)), "\(row.label) does not read \(row.count)")
                    // The note is 16 points in from the start of the row, where the dot is: under the label.
                    let note = try textFrame(startingWith: row.note, in: window)
                    #expect(abs(note.minX - label.minX) < 1, "The note of \(row.label) is not indented by 16 points")
                    let separator = try OffscreenPicture.bytes(of: Palette.sep, in: scheme)
                    let lines = picture.rows(near: separator, from: label.minX, to: label.minX + 60, by: 2)
                    #expect(
                        lines.contains { $0 < label.minY && $0 > label.minY - 14 },
                        "\(scheme): no hairline above \(row.label)")
                }
                let overwritten = try #require(model.outcomeRows.first { $0.tone == .overwrite })
                try picture.expectText(
                    in: try textFrame(startingWith: overwritten.note, in: window), setIn: Palette.orangeText,
                    atLeast: 40, scheme: scheme, "\(scheme): the note of what is overwritten")
                let added = try #require(model.outcomeRows.first { $0.tone == .new })
                try picture.expectText(
                    in: try textFrame(startingWith: added.note, in: window), setIn: Palette.text3, atLeast: 40,
                    scheme: scheme, "\(scheme): the note of what is added")

                // The buttons.
                let cancel = try buttonFrame("Zrušit", in: window)
                let start = try buttonFrame(model.importButtonTitle, in: window)
                #expect(abs(cancel.height - 28) < 0.5 && abs(start.height - 28) < 0.5)
                #expect(pixelIs(fill, at: CGPoint(x: cancel.minX + 6, y: cancel.midY), in: picture))
                let accent = try OffscreenPicture.bytes(of: Palette.accent, in: scheme)
                #expect(pixelIs(accent, at: CGPoint(x: start.minX + 6, y: start.midY), in: picture))
                #expect(cancel.maxX < start.minX && abs(start.maxX - (card.maxX - 20)) < 1)
                let button = try #require(accessibilityButton(labelled: model.importButtonTitle, in: window))
                #expect(button.isAccessibilityEnabled?() == true)
                #expect(!readings.contains { $0.hasPrefix("Průběh") })
            }
        }
    }

    /// The ✕ of a file takes it out, and Zrušit takes them all: the card goes with the last file.
    @Test func theCrossRemovesAFileAndZrusitEmptiesTheList() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let app = try await makeAppWithCollectedFiles(in: directory)

        try await withHostedView(ImportScreen(app: app), size: Self.size) { window in
            try await withAccessibilityElements {
                try await waitUntil { accessibilityButton(labelled: "Odebrat poznamky.txt", in: window) != nil }
                let remove = try #require(accessibilityButton(labelled: "Odebrat poznamky.txt", in: window))
                #expect(remove.accessibilityPerformPress?() == true)
                try await waitUntil { app.importModel.files.count == 2 }
                try await waitUntil { showsText("2\u{00A0}soubory", in: window) }

                let cancel = try #require(accessibilityButton(labelled: "Zrušit", in: window))
                #expect(cancel.accessibilityPerformPress?() == true)
                try await waitUntil { frameOfCard(labelled: "Kontrola před importem", in: window) == nil }
                #expect(app.importModel.files.isEmpty)
            }
        }
    }

    // MARK: Průběh

    /// While the import runs the card "Průběh", read as "Průběh importu", says that it goes on when another screen is
    /// shown, has the bar of 6 points on the grey fill, read as "Průběh importu", and says how far it is. The card of
    /// the review is not shown meanwhile.
    @Test(.hangGuard)
    func aRunningImportShowsItsBarAndSaysItGoesOn() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let gate = Gate()
        let app = try await makeApp(in: directory, gate: gate)
        await app.importModel.addFiles([try fixtureURL("fakturoid_sample", "csv")])
        let total = try #require(app.importModel.preview?.invoiceCount)
        let run = Task { await app.importModel.importCollected() }
        await gate.untilARequestWaits()

        do {
            try await withHostedView(ImportScreen(app: app), size: Self.size) { window in
                try await withAccessibilityElements {
                    try await waitUntil { frameOfCard(labelled: "Průběh importu", in: window) != nil }
                    try await layOut(window)
                    let picture = try OffscreenPicture(of: window)
                    let card = try cardFrame("Průběh importu", in: window)
                    let readings = accessibilityReadings(in: window)
                    #expect(readings.contains("Průběh"))
                    #expect(readings.contains("Můžete přejít jinam, import poběží dál."))
                    #expect(readings.contains("Importuji 0 z \(total)…"))
                    let bar = try #require(
                        accessibilityElement(role: .progressIndicator, labelled: "Průběh importu", in: window))
                    let frame = try pictureFrame(ofScreenFrame: try #require(bar.accessibilityFrame?()), in: window)
                    #expect(abs(frame.height - 6) < 0.5, "The bar is \(frame.height) points tall")
                    #expect(card.contains(frame))
                    let fill = try OffscreenPicture.bytes(of: Palette.fill, in: scheme(of: window))
                    #expect(pixelIs(fill, at: CGPoint(x: frame.midX, y: frame.midY), in: picture))
                    #expect(frameOfCard(labelled: "Kontrola před importem", in: window) == nil)
                }
            }
        } catch {
            await gate.open()
            throw error
        }
        await gate.open()
        await run.value
    }

    /// An import that is done: the bar is full in the green text, the green panel holds the headline in the green text
    /// and Zobrazit faktury as the accent capsule 28 points tall, which shows Faktury. Under the panel are the line of
    /// the clients and the offer to fill in the supplier, an information note whose button is a capsule of the card
    /// colour with its words in the accent text; then each list on the inset background, the overwritten invoices
    /// first with their numbers on one line. There is no block for each file.
    @Test(arguments: [ColorScheme.light, .dark])
    func aFinishedImportShowsTheHeadlineAndTheOverwrittenList(scheme: ColorScheme) async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let gate = Gate()
        await gate.open()
        let app = try await makeApp(in: directory, gate: gate)
        // An invoice of the app in euros has the number of one of the rows: a line of what could not be added.
        try await #require(app.database).saveInvoice(
            Invoice.fixture(number: "20261008", currency: .eur, vatMode: VatMode.none))
        await app.importModel.importAll([try fixtureURL("fakturoid_sample", "csv")])
        await app.importModel.importAll([try fixtureURL("fakturoid_reimport", "csv")])
        let summary = try #require(app.importModel.summary)
        try #require(!summary.overwrittenItems.isEmpty)
        #expect(app.importModel.canFillSupplier)

        try await withHostedView(ImportScreen(app: app), size: Self.size) { window in
            window.appearance = appearance(of: scheme)
            try await withAccessibilityElements {
                try await waitUntil { frameOfText(startingWith: "Hotovo –", in: window) != nil }
                try await layOut(window)
                let picture = try OffscreenPicture(of: window)
                let inset = try OffscreenPicture.bytes(of: Palette.bgInset, in: scheme)
                let green = try OffscreenPicture.bytes(of: Palette.greenTint, in: scheme)
                let blue = try OffscreenPicture.bytes(of: Palette.accentTint, in: scheme)
                let accent = try OffscreenPicture.bytes(of: Palette.accent, in: scheme)
                let accentText = try OffscreenPicture.bytes(of: Palette.accentText, in: scheme)
                let greenText = try OffscreenPicture.bytes(of: Palette.greenText, in: scheme)
                let card = try OffscreenPicture.bytes(of: Palette.bgCard, in: scheme)
                let readings = accessibilityReadings(in: window)
                let progress = try cardFrame("Průběh importu", in: window)

                #expect(readings.contains("Průběh"))
                #expect(!readings.contains("Můžete přejít jinam, import poběží dál."))
                #expect(!readings.contains { $0.hasPrefix("Importuji") })
                let bar = try #require(
                    accessibilityElement(role: .progressIndicator, labelled: "Průběh importu", in: window))
                let barFrame = try pictureFrame(ofScreenFrame: try #require(bar.accessibilityFrame?()), in: window)
                #expect(abs(barFrame.height - 6) < 0.5, "The bar is \(barFrame.height) points tall")
                for x in [barFrame.minX + 4, barFrame.midX, barFrame.maxX - 4] {
                    #expect(
                        pixelIs(greenText, at: CGPoint(x: x, y: barFrame.midY), in: picture),
                        "\(scheme): the bar is not full in the green text at \(x)")
                }

                let headline = try textFrame(startingWith: "Hotovo –", in: window)
                #expect(readings.contains(ImportText.headline(of: summary)))
                #expect(
                    pixelIs(green, at: CGPoint(x: headline.minX - 8, y: headline.midY), in: picture),
                    "\(scheme): the headline is not on the green tint")
                #expect(
                    picture.count(near: greenText, in: headline, by: 4) > 15,
                    "\(scheme): the headline is not in the green text")
                let show = try buttonFrame("Zobrazit faktury", in: window)
                #expect(abs(show.height - 28) < 0.5, "Zobrazit faktury is \(show.height) points tall")
                #expect(pixelIs(accent, at: CGPoint(x: show.minX + 6, y: show.midY), in: picture))
                #expect(
                    pixelIs(green, at: CGPoint(x: show.maxX + 6, y: show.midY), in: picture),
                    "\(scheme): Zobrazit faktury is not in the green panel")

                let clients = try textFrame(startingWith: ImportText.clientsLine(of: summary), in: window)
                #expect(clients.minY > show.maxY, "The line of the clients is not under the green panel")
                #expect(
                    !pixelIs(green, at: CGPoint(x: clients.minX - 8, y: clients.midY), in: picture),
                    "\(scheme): the line of the clients is in the green panel")

                let offer = try textFrame(startingWith: "Export obsahuje údaje dodavatele", in: window)
                #expect(offer.minY > clients.maxY)
                #expect(
                    pixelIs(blue, at: CGPoint(x: offer.minX - 5, y: offer.midY), in: picture),
                    "\(scheme): the offer is not an information note")
                let fill = try buttonFrame("Doplnit údaje dodavatele z exportu", in: window)
                #expect(abs(fill.height - 28) < 0.5, "The button of the offer is \(fill.height) points tall")
                #expect(pixelIs(card, at: CGPoint(x: fill.minX + 8, y: fill.midY), in: picture))
                #expect(
                    picture.count(near: accentText, in: fill, by: 6) > 15,
                    "\(scheme): the words of the button are not in the accent text")

                let lists = app.importModel.summaryLists
                #expect(lists.first?.title == "Přepsané (\(summary.overwrittenItems.count))")
                var above = fill.maxY
                for list in lists {
                    let title = try textFrame(startingWith: list.title, in: window)
                    #expect(title.minY > above, "\(list.title) is not under what comes before it")
                    #expect(progress.contains(title))
                    #expect(
                        pixelIs(inset, at: CGPoint(x: title.minX - 8, y: title.midY), in: picture),
                        "\(scheme): \(list.title) is not on the inset background")
                    #expect(readings.contains(list.note), "\(list.title) does not read \(list.note)")
                    for item in list.items {
                        #expect(readings.contains(item), "\(list.title) does not read \(item)")
                    }
                    above = title.maxY
                }
                #expect(readings.contains(summary.overwrittenItems.joined(separator: ", ")))
                #expect(!readings.contains("fakturoid_reimport.csv"), "The card still has a block for the file")

                let button = try #require(accessibilityButton(labelled: "Zobrazit faktury", in: window))
                #expect(button.accessibilityPerformPress?() == true)
                try await waitUntil { app.screen == .invoices }
            }
        }
    }

    // MARK: The window of the app

    /// The cards in the window of the app at the least room and at a large size, in a light and in a dark appearance:
    /// with files collected the review is under the choice, and once they are imported the progress is; each card is
    /// on the card colour, 820 points wide at the most, within the page, 16 points under the one before, and holds what
    /// it shows.
    @Test(arguments: [AppWindowSize.minimum, AppWindowSize.large], [ColorScheme.light, .dark])
    func theCardsFitTheWindowOfTheApp(size: CGSize, scheme: ColorScheme) async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let app = try await makeAppWithCollectedFiles(in: directory)
        let model = app.importModel

        try await withAppWindow(of: app, size: size) { window in
            window.appearance = appearance(of: scheme)
            app.screen = .importer
            try await waitUntil { window.title == "Import faktur" }
            try await withAccessibilityElements {
                try await waitUntil { frameOfCard(labelled: "Kontrola před importem", in: window) != nil }
                try await layOut(window)
                let width = try #require(window.contentView).bounds.width
                let choice = try cardFrame("Výběr souborů", in: window)
                let review = try cardFrame("Kontrola před importem", in: window)
                for frame in [choice, review] {
                    #expect(frame.width <= 820.5 && frame.maxX <= width - 16 + 0.5, "A card is at \(frame)")
                }
                #expect(abs(review.minX - choice.minX) < 0.5 && abs(review.minY - choice.maxY - 16) < 1)
                let cardColour = try OffscreenPicture.bytes(of: Palette.bgCard, in: scheme)
                let picture = try OffscreenPicture(of: window)
                #expect(
                    pixelIs(cardColour, at: CGPoint(x: choice.maxX - 10, y: choice.minY + 10), in: picture),
                    "\(scheme): the choice of files is not on the card colour")
                for file in model.files {
                    #expect(review.contains(try buttonFrame("Odebrat \(file.name)", in: window)))
                }
                #expect(review.contains(try buttonFrame(model.importButtonTitle, in: window)))

                await model.importCollected()
                try await waitUntil { frameOfCard(labelled: "Průběh importu", in: window) != nil }
                try await layOut(window)
                #expect(frameOfCard(labelled: "Kontrola před importem", in: window) == nil)
                let progress = try cardFrame("Průběh importu", in: window)
                #expect(progress.width <= 820.5 && progress.maxX <= width - 16 + 0.5, "The progress is at \(progress)")
                #expect(abs(progress.minX - choice.minX) < 0.5 && abs(progress.minY - choice.maxY - 16) < 1)
                #expect(progress.contains(try buttonFrame("Zobrazit faktury", in: window)))
                for list in model.summaryLists {
                    #expect(progress.contains(try textFrame(startingWith: list.title, in: window)))
                }
            }
        }
    }

    /// The appearance `window` is drawn in.
    private func scheme(of window: NSWindow) -> ColorScheme {
        window.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? .dark : .light
    }
}
