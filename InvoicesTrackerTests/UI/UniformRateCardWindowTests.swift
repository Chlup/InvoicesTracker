import AppKit
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
