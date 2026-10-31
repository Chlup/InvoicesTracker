import AppKit
import SwiftUI
import Testing
@testable import InvoicesTracker

/// Import in a window of its own, made as the app makes it, in a light and in a dark appearance, and looked at as the
/// pixels of the window and the frames VoiceOver reads show it: the zone where the files are dropped, the card of the
/// progress with a block for each file, the green box of the summary, the offer to fill in the supplier, and the lists
/// of what is to check, kept and not added. The page is shown alone in a tall window so that it needs no scrolling.
@Suite(.serialized, .settlesBackups)
@MainActor
struct ImportWindowTests {
    /// What a page needs is measured in the font it is set in, so the fonts are registered before any test, as the app
    /// does at its launch.
    init() {
        InvoiceFonts.register()
    }

    /// The room the page has: tall enough for the zone, the file, the summary and the three lists.
    private static let size = CGSize(width: 1_000, height: 1_700)

    /// An app on a new folder whose server answers once `gate` opens.
    private func makeApp(in directory: URL, gate: Gate) async throws -> AppModel {
        let yearly = try Data(contentsOf: fixtureURL("cnb_rok_2026", "txt"))
        let server = StubHTTPClient([CNBEndpoints.yearly(2026): yearly])
        let app = makeAppModel(in: directory, http: GatedHTTPClient(base: server, gate: gate))
        try await startFresh(app)
        return app
    }

    /// The frame of the first text of `window` that starts with `phrase`, in points from the top left.
    private func textFrame(startingWith phrase: String, in window: NSWindow) throws -> CGRect {
        let frame = try #require(frameOfText(startingWith: phrase, in: window), "No text \(phrase)")
        return try pictureFrame(ofScreenFrame: frame, in: window)
    }

    /// The frame of the button of `window` that VoiceOver reads under `label`, in points from the top left.
    private func buttonFrame(_ label: String, in window: NSWindow) throws -> CGRect {
        let button = try #require(accessibilityButton(labelled: label, in: window), "No \(label)")
        return try pictureFrame(ofScreenFrame: try #require(button.accessibilityFrame?()), in: window)
    }

    // MARK: The choice of files

    /// The zone where files are dropped is the accent tint with a ring of the soft accent, rounded by 10 points as a
    /// panel is (a corner of 14 would still be outside at 3.5 points in, where the ring is), and it keeps the pill
    /// "Vybrat soubory…" and the words of the zone. There is no button for a sample file.
    @Test(arguments: [ColorScheme.light, .dark])
    func theDropZoneIsTheAccentTintWithARingOfTheSoftAccentAndKeepsItsPill(scheme: ColorScheme) async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let app = try await makeApp(in: directory, gate: Gate())

        try await withHostedView(ImportScreen(app: app), size: Self.size) { window in
            window.appearance = appearance(of: scheme)
            try await withAccessibilityElements {
                try await waitUntil {
                    accessibilityElement(labelStartingWith: "Přetáhněte CSV sem", in: window) != nil
                }
                try await layOut(window)
                let zoneElement = try #require(
                    accessibilityElement(labelStartingWith: "Přetáhněte CSV sem", in: window))
                let zone = try pictureFrame(ofScreenFrame: try #require(zoneElement.accessibilityFrame?()), in: window)
                let picture = try OffscreenPicture(of: window)
                let tint = try OffscreenPicture.bytes(of: Palette.accentTint, in: scheme)
                let soft = try OffscreenPicture.bytes(of: Palette.accentSoft, in: scheme)

                #expect(
                    pixelIs(tint, at: CGPoint(x: zone.minX + 12, y: zone.midY), in: picture),
                    "\(scheme): the zone is not the accent tint")
                #expect(
                    pixelIs(soft, at: CGPoint(x: zone.minX + 3.5, y: zone.minY + 3.5), in: picture),
                    "\(scheme): the zone has no ring of the soft accent rounded by 10 points")
                let label = (zoneElement.accessibilityLabel?() ?? "") as String
                #expect(label.contains("Vybrat soubory…"), "The zone reads \(label)")
                #expect(label.contains("Export faktur z Fakturoidu · lze vybrat víc souborů najednou"))
                #expect(accessibilityElement(labelStartingWith: "Vyzkoušet na ukázkovém souboru", in: window) == nil)
            }
        }
    }

    // MARK: The progress and the summary

    /// An import that is done: the block of the file and the lists are on the inset background, the summary is the
    /// green tint with Zobrazit faktury as the accent capsule 28 points tall, the offer to fill in the supplier is an
    /// information note whose button is a capsule of the card colour with its words in the accent text, and the counts
    /// of the file are in the colours of the design.
    @Test(arguments: [ColorScheme.light, .dark])
    func aFinishedImportIsMadeOfTheComponentsOfTheDesign(scheme: ColorScheme) async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let gate = Gate()
        await gate.open()
        let app = try await makeApp(in: directory, gate: gate)
        // An invoice of the app has the number of one of the rows: a line of what could not be added.
        try await #require(app.database).saveInvoice(Invoice.fixture(number: "20261008"))
        await app.importModel.importFiles([try fixtureURL("fakturoid_sample", "csv")])
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
                let orangeText = try OffscreenPicture.bytes(of: Palette.orangeText, in: scheme)
                let card = try OffscreenPicture.bytes(of: Palette.bgCard, in: scheme)

                let file = try textFrame(startingWith: "fakturoid_sample.csv", in: window)
                #expect(
                    pixelIs(inset, at: CGPoint(x: file.minX - 8, y: file.midY), in: picture),
                    "\(scheme): the block of the file is not on the inset background")
                let summary = try textFrame(startingWith: "Hotovo –", in: window)
                #expect(
                    pixelIs(green, at: CGPoint(x: summary.minX - 8, y: summary.midY), in: picture),
                    "\(scheme): the summary is not the green tint")
                #expect(
                    picture.count(near: greenText, in: summary, by: 4) > 15,
                    "\(scheme): the headline of the summary is not in the green text")
                let show = try buttonFrame("Zobrazit faktury", in: window)
                #expect(abs(show.height - 28) < 0.5, "Zobrazit faktury is \(show.height) points tall")
                #expect(pixelIs(accent, at: CGPoint(x: show.minX + 6, y: show.midY), in: picture))

                let notAdded = try #require(accessibilityElement(labelStartingWith: "Nepřidáno (", in: window))
                let list = try pictureFrame(ofScreenFrame: try #require(notAdded.accessibilityFrame?()), in: window)
                #expect(
                    pixelIs(inset, at: CGPoint(x: list.minX - 8, y: list.midY), in: picture),
                    "\(scheme): a list is not on the inset background")

                let offer = try textFrame(startingWith: "Export obsahuje údaje dodavatele", in: window)
                #expect(
                    pixelIs(blue, at: CGPoint(x: offer.minX - 5, y: offer.midY), in: picture),
                    "\(scheme): the offer is not an information note")
                let fill = try buttonFrame("Doplnit údaje dodavatele z exportu", in: window)
                #expect(abs(fill.height - 28) < 0.5, "The button of the offer is \(fill.height) points tall")
                #expect(pixelIs(card, at: CGPoint(x: fill.minX + 8, y: fill.midY), in: picture))
                #expect(
                    picture.count(near: accentText, in: fill, by: 6) > 15,
                    "\(scheme): the words of the button are not in the accent text")

                let updated = try textFrame(startingWith: "aktualizované", in: window)
                #expect(
                    picture.count(near: accentText, in: updated, by: 6) > 10,
                    "\(scheme): the count of what was updated is not in the accent text")
                let skipped = try textFrame(startingWith: "přeskočené", in: window)
                #expect(
                    picture.count(near: orangeText, in: skipped, by: 6) > 10,
                    "\(scheme): the count of what was skipped is not in the orange text")
            }
        }
    }
}
