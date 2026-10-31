import AppKit
import SwiftUI
import Testing
@testable import InvoicesTracker

/// The card Jednotný kurz of Nastavení › Rok in the window of the app, as VoiceOver reaches it: a rate entered by hand
/// offers Upravit and Odstranit… under its year as it is written, Odstranit… asks in the card in place of the note,
/// Zrušit takes the question back, and Odstranit kurz brings back the table that ships with the app. The data is
/// invented, and the clock is at noon of 17. 10. 2026. In every expected string `\u{00A0}` is the no-break space.
@Suite(.serialized, .settlesBackups)
@MainActor
struct UniformRateCardWindowTests {
    /// Presses the control of `window` that VoiceOver reads under `label`, as VoiceOver presses it.
    private func press(_ label: String, in window: NSWindow) throws {
        let control = try #require(accessibilityElement(labelled: label, in: window))
        #expect(control.accessibilityPerformPress?() == true)
    }

    /// The frame `screen` of a view, given in the coordinates of the screen with the origin at its bottom left, as a
    /// picture of `window` counts it: in points from the top left of the content of the window.
    private func pictureFrame(of screen: CGRect, in window: NSWindow) throws -> CGRect {
        let frame = window.convertFromScreen(screen)
        let height = try #require(window.contentView).bounds.height
        return CGRect(x: frame.minX, y: height - frame.maxY, width: frame.width, height: frame.height)
    }

    /// The links of a rate entered by hand are the links of the design, Upravit in the blue of a link and Odstranit… in
    /// the red of text, and the note of what the rate stands in for is a panel on the inset background, as wide as the
    /// card's content, with its words in secondary text.
    @Test(arguments: [ColorScheme.light, .dark])
    func theLinksAndTheNoteOfARateEnteredByHandAreInTheColoursOfTheDesign(scheme: ColorScheme) async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let app = try await makeSettingsApp(in: directory)
        let database = try #require(app.database)
        let others = try await database.uniformRates(year: 2025).filter { $0.currency != .usd && $0.currency != .eur }
        let typed = UniformRate(
            year: 2025, currency: .usd, amount: 1, rate: decimal("21.90"), instruction: "", origin: .manual)
        try await database.saveUniformRates(others + [typed], year: 2025)
        app.selectYear(2025)
        let edit = "Upravit jednotný kurz 2025"
        let remove = "Odstranit ručně zadaný jednotný kurz 2025"
        let note = "Nahrazuje kurz z pokynu GFŘ-D-75"

        try await withAppWindow(of: app, size: AppWindowSize.large) { window in
            window.appearance = NSAppearance(named: scheme == .light ? .aqua : .darkAqua)
            app.showSettings(.year)
            try await withAccessibilityElements {
                try await waitUntil { accessibilityElement(labelled: remove, in: window) != nil }
                try await waitUntil { frameOfText(startingWith: note, in: window) != nil }
                try await layOut(window)
                let editScreen = try #require(accessibilityElement(labelled: edit, in: window)?.accessibilityFrame?())
                let removeScreen = try #require(
                    accessibilityElement(labelled: remove, in: window)?.accessibilityFrame?())
                let noteScreen = try #require(frameOfText(startingWith: note, in: window))
                let editFrame = try pictureFrame(of: editScreen, in: window)
                let removeFrame = try pictureFrame(of: removeScreen, in: window)
                let noteFrame = try pictureFrame(of: noteScreen, in: window)
                let picture = try OffscreenPicture(of: window)
                let blue = try OffscreenPicture.bytes(of: Palette.accentText, in: scheme)
                let red = try OffscreenPicture.bytes(of: Palette.redText, in: scheme)
                let inset = try OffscreenPicture.bytes(of: Palette.bgInset, in: scheme)
                let secondary = try OffscreenPicture.bytes(of: Palette.text2, in: scheme)

                #expect(picture.count(near: blue, in: editFrame, by: 8) > 30, "\(scheme): Upravit is not a link")
                #expect(picture.count(near: red, in: removeFrame, by: 8) > 30, "\(scheme): Odstranit… is not red")
                #expect(picture.count(near: red, in: editFrame, by: 8) == 0, "\(scheme): Upravit is red")
                #expect(
                    zip(picture.bytes(at: CGPoint(x: noteFrame.minX - 6, y: noteFrame.midY)), inset)
                        .allSatisfy { abs($0 - $1) <= 2 },
                    "\(scheme): the note is not on the inset background")
                #expect(
                    picture.count(near: secondary, in: noteFrame, by: 8) > 100, "\(scheme): the note is not secondary")
            }
        }
    }

    @Test func odstranitAsksInTheCardAndBringsBackTheShippedTable() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let app = try await makeSettingsApp(in: directory)
        let database = try #require(app.database)
        // A rate of dollars entered by hand over the table of 2025, as the form saves it.
        let others = try await database.uniformRates(year: 2025).filter { $0.currency != .usd && $0.currency != .eur }
        let typed = UniformRate(
            year: 2025, currency: .usd, amount: 1, rate: decimal("21.90"), instruction: "", origin: .manual)
        try await database.saveUniformRates(others + [typed], year: 2025)
        app.selectYear(2025)
        let remove = "Odstranit ručně zadaný jednotný kurz 2025"

        try await withAppWindow(of: app, size: AppWindowSize.large) { window in
            app.showSettings(.year)
            try await withAccessibilityElements {
                try await waitUntil { accessibilityElement(labelled: remove, in: window) != nil }
                #expect(accessibilityElement(labelled: "Upravit jednotný kurz 2025", in: window) != nil)
                #expect(
                    showsText(
                        "Nahrazuje kurz z pokynu GFŘ-D-75 (1\u{00A0}USD = 21,84\u{00A0}Kč · 1\u{00A0}EUR ="
                            + " 24,66\u{00A0}Kč), který má aplikace od vydání.", in: window))

                // Odstranit… asks in place of the note, and Zrušit takes the question back.
                try press(remove, in: window)
                try await waitUntil { accessibilityElement(labelled: "Odstranit kurz", in: window) != nil }
                #expect(accessibilityElement(labelled: "Odstranit ručně zadaný kurz?", in: window) != nil)
                #expect(
                    showsText(
                        "Rok 2025 pak použije kurz z pokynu GFŘ-D-75 (1\u{00A0}USD = 21,84\u{00A0}Kč · 1\u{00A0}EUR ="
                            + " 24,66\u{00A0}Kč).", in: window))
                try press("Zrušit", in: window)
                try await waitUntil { accessibilityElement(labelled: "Odstranit kurz", in: window) == nil }
                #expect(try await database.uniformRate(.usd, year: 2025)?.origin == .manual)

                // Odstranit kurz removes the rate entered by hand, and the card shows the table again.
                try press(remove, in: window)
                try await waitUntil { accessibilityElement(labelled: "Odstranit kurz", in: window) != nil }
                try press("Odstranit kurz", in: window)
                // The card reloads with the write, before the removal has said what it did: both are waited for.
                try await waitUntil { accessibilityElement(labelled: remove, in: window) == nil }
                try await waitUntil {
                    app.banner?.text
                        == "Ručně zadaný jednotný kurz 2025 je odstraněný. Rok 2025 teď používá kurz z pokynu"
                        + " GFŘ-D-75."
                }
                #expect(try await database.uniformRate(.usd, year: 2025)?.origin == .builtIn)
                #expect(showsText("pokyn GFŘ-D-75 · v aplikaci od vydání", in: window))
            }
        }
    }
}
