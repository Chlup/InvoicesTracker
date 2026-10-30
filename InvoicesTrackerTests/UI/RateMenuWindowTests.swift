import AppKit
import SwiftUI
import Testing
@testable import InvoicesTracker

/// The rate capsule of the toolbar and its menu in the window of the app, made as the app makes it, on the data of
/// `EditorFixture` with the income of 2025 of `storeForeignIncomeOf2025`, and the window on Výpočet:
/// - the menu switches the year shown between the daily and the uniform rates, and Výpočet then shows the levies the
///   menu named for the method chosen;
/// - in the current year, which waits for its uniform rate, the menu offers the daily rates alone.
///
/// The capsule, the menu and its choices are found by what VoiceOver reads them as, and pressed as VoiceOver presses
/// them. One window at a time, so that what a test sees settle is its own window.
@Suite(.serialized, .settlesBackups)
@MainActor
struct RateMenuWindowTests {
    /// What a page needs is measured in the font it is set in, so the fonts are registered before any test, as the app
    /// does at its launch.
    init() {
        InvoiceFonts.register()
    }

    /// 2025, paid in dollars and euros, goes to its uniform rate and back through the menu. The menu shows the levies
    /// of each conversion and closes once the choice is made. Výpočet follows each choice: its key figure, which with
    /// nothing paid in advances is the levies of the year, is the figure the menu named for the method chosen.
    @Test func theRateCapsuleSwitchesTheYearShownBetweenTheDailyAndTheUniformRates() async throws {
        try await EditorFixture.with { f in
            try await storeForeignIncomeOf2025(in: f.app)
            try await withAppWindow(of: f.app, size: AppWindowSize.minimum) { window in
                f.app.selectYear(2025)
                let comparison = try #require(try await f.app.levyComparison(year: 2025))
                let dailyLevies = CzechFormat.wholeKc(comparison.daily)
                let uniformLevies = CzechFormat.wholeKc(comparison.uniform)
                try await withAccessibilityElements {
                    let daily = "Přepočet cizích měn v roce 2025: denní kurz ČNB"
                    let uniform = "Přepočet cizích měn v roce 2025: jednotný kurz"
                    try await waitUntil { accessibilityButton(labelled: daily, in: window) != nil }
                    try await waitUntil { keyFigure(in: window, says: dailyLevies) }

                    let menu = try await openRateMenu(labelled: daily, in: window)
                    // The levies of each conversion are read when the menu opens.
                    try await waitUntil {
                        accessibilityValue(ofButtonLabelled: "Jednotný kurz 2025", in: menu)?
                            .contains("odvody \(uniformLevies)") == true
                    }
                    #expect(
                        accessibilityValue(ofButtonLabelled: "Denní kurz ČNB", in: menu)?
                            .contains("odvody \(dailyLevies)") == true)
                    _ = try #require(accessibilityButton(labelled: "Jednotný kurz 2025", in: menu))
                        .accessibilityPerformPress?()
                    try await waitUntil { accessibilityButton(labelled: uniform, in: window) != nil }
                    try await waitUntil { !menu.isVisible }
                    #expect(try await f.database.yearSettings(2025).incomeFXMethod == .uniform)
                    try await waitUntil { keyFigure(in: window, says: uniformLevies) }

                    let again = try await openRateMenu(labelled: uniform, in: window)
                    _ = try #require(accessibilityButton(labelled: "Denní kurz ČNB", in: again))
                        .accessibilityPerformPress?()
                    try await waitUntil { accessibilityButton(labelled: daily, in: window) != nil }
                    try await waitUntil { !again.isVisible }
                    #expect(try await f.database.yearSettings(2025).incomeFXMethod == .cnbDaily)
                    try await waitUntil { keyFigure(in: window, says: dailyLevies) }
                }
            }
        }
    }

    /// In the current year, which waits for its uniform rate, the menu offers it disabled with the reason, and the
    /// daily rates the year has close it with nothing changed.
    @Test func theRateMenuOfTheCurrentYearOffersTheDailyRatesAlone() async throws {
        try await EditorFixture.with { f in
            try await withAppWindow(of: f.app, size: AppWindowSize.minimum) { window in
                try await withAccessibilityElements {
                    let daily = "Přepočet cizích měn v roce 2026: denní kurz ČNB"
                    try await waitUntil { accessibilityButton(labelled: daily, in: window) != nil }
                    let version = f.app.dataVersion

                    let menu = try await openRateMenu(labelled: daily, in: window)

                    let uniform = try #require(accessibilityButton(labelled: "Jednotný kurz 2026", in: menu))
                    #expect(uniform.isAccessibilityEnabled?() == false)
                    #expect(
                        accessibilityValue(ofButtonLabelled: "Jednotný kurz 2026", in: menu)
                            == "zatím nevyšel – GFŘ ho zveřejní v lednu 2027")
                    _ = try #require(accessibilityButton(labelled: "Denní kurz ČNB", in: menu))
                        .accessibilityPerformPress?()
                    try await waitUntil { !menu.isVisible }
                    #expect(f.app.dataVersion == version)
                }
            }
        }
    }

    // MARK: Helpers

    /// Opens the menu of the rate capsule that VoiceOver reads as `capsule` in `window`, pressed as VoiceOver presses
    /// it, and gives the popover it is shown in.
    private func openRateMenu(labelled capsule: String, in window: NSWindow) async throws -> NSWindow {
        _ = try #require(accessibilityButton(labelled: capsule, in: window)).accessibilityPerformPress?()
        try await waitUntil { rateMenu(of: window) != nil }
        return try #require(rateMenu(of: window))
    }

    /// The popover of the menu of the rate capsule over `window`, which has the choice "Denní kurz ČNB". Nil while it
    /// is closed.
    private func rateMenu(of window: NSWindow) -> NSWindow? {
        (window.childWindows ?? []).first { child in
            child.isVisible && accessibilityButton(labelled: "Denní kurz ČNB", in: child) != nil
        }
    }

    /// What VoiceOver reads after the label of the button labelled `label` in `window`: the lines of a choice of the
    /// rate menu under its title. Nil when there is no such button.
    private func accessibilityValue(ofButtonLabelled label: String, in window: NSWindow) -> String? {
        guard let button = accessibilityButton(labelled: label, in: window) else { return nil }
        return words(of: button)
    }

    /// What VoiceOver reads of the key figure of Výpočet of 2025 in `window`, a text that reads its eyebrow, its figure
    /// and its sentence as one phrase, such as "Doplatek za rok 2025, 252 900 Kč, Zálohami se za rok zaplatilo 0 Kč.
    /// Sčítají se jen kladné zůstatky …". Nil while the window shows no such text.
    private func keyFigureOfVýpočet(in window: NSWindow) -> String? {
        guard let content = window.contentView else { return nil }
        return firstReading(among: content.accessibilityChildren() ?? []) { $0.hasPrefix("Doplatek za rok 2025, ") }
    }

    /// Whether the key figure of Výpočet of 2025 in `window` has the figure `figure`: its phrase starts with the
    /// eyebrow, the figure and the comma that parts it from the sentence.
    private func keyFigure(in window: NSWindow, says figure: String) -> Bool {
        keyFigureOfVýpočet(in: window)?.hasPrefix("Doplatek za rok 2025, \(figure),") == true
    }

    /// The first thing VoiceOver reads among `elements` and their children, in the order of the tree, as their label
    /// and their value, that `matches`.
    private func firstReading(among elements: [Any], where matches: (String) -> Bool) -> String? {
        for item in elements {
            let element = item as AnyObject
            let reading = [element.accessibilityLabel?() ?? nil, words(of: element)].compactMap { $0 }
                .filter { !$0.isEmpty }.joined(separator: ", ")
            if matches(reading) {
                return reading
            }
            if let found = firstReading(among: element.accessibilityChildren?() ?? [], where: matches) {
                return found
            }
        }
        return nil
    }

    /// The value of `element` as words, or nil when it has none.
    private func words(of element: AnyObject) -> String? {
        // Asked for as a function of its type, because the protocols of accessibility declare `accessibilityValue()`
        // with more than one type.
        let value: (() -> Any?)? = element.accessibilityValue
        return (value?() ?? nil) as? String
    }
}
