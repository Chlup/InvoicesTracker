import AppKit
import SwiftUI
import Testing

@testable import InvoicesTracker

/// What VoiceOver says for the text controls of the app that lead somewhere else: a link, as the system's link style
/// made it before the app drew its own (`TextLinkButtonStyle`, `calloutLink()`). Every control that was a link then is
/// read as one now, in the form it is written in (`calloutLink()` in the blue of a link, `calloutLink(.destructive)` in
/// the red of text, and `TextLinkButtonStyle` with the trait added by hand), and a text control that does something on
/// the page instead of leading anywhere, such as "Vrátit odhad aplikace", is read as a button. Each control is shown
/// as the app shows it and found by the label VoiceOver reads it under.
@Suite(.serialized, .settlesBackups)
@MainActor
struct LinkRoleTests {
    // MARK: Helpers

    /// Expects `window` to show something that VoiceOver reads under `label`, and that to be read as a link, not as a
    /// button.
    private func expectLink(
        _ label: String, in window: NSWindow, sourceLocation: SourceLocation = #_sourceLocation
    ) async throws {
        try await waitUntil(sourceLocation: sourceLocation) { accessibilityElement(labelled: label, in: window) != nil }
        let element = try #require(
            accessibilityElement(labelled: label, in: window), "No control \(label)", sourceLocation: sourceLocation)
        let role = element.accessibilityRole?()
        #expect(role == .link, "\(label) is read as \(String(describing: role))", sourceLocation: sourceLocation)
        #expect(
            accessibilityButton(labelled: label, in: window) == nil, "\(label) is read as a button",
            sourceLocation: sourceLocation)
    }

    /// Shows `view` alone in a window of `size` and expects the control under `label` in it to be read as a link.
    private func expectLink(
        _ label: String, in view: some View, size: CGSize = CGSize(width: 700, height: 600),
        sourceLocation: SourceLocation = #_sourceLocation
    ) async throws {
        try await withHostedView(view, size: size) { window in
            try await withAccessibilityElements {
                try await expectLink(label, in: window, sourceLocation: sourceLocation)
            }
        }
    }

    /// Shows the tab `tab` of Nastavení in `window` of the app.
    private func showSettings(_ tab: SettingsTab, of app: AppModel, in window: NSWindow) async throws {
        app.showSettings(tab)
        try await waitUntil { window.title == "Nastavení" }
    }

    // MARK: The links of the pages

    /// Plán záloh and Všechny faktury, the links at the end of the headings of the two lists of Přehled, are
    /// `calloutLink()` and lead to Zálohy a odpočty and to Faktury.
    @Test func theLinksOfTheListsOfPrehledAreReadAsLinks() async throws {
        let advance = UpcomingItem(
            date: civilDate("2026-11-01"), day: "lis", month: "2026", title: "Zálohy za listopad",
            subtitle: "sociální 12\u{00A0}150 · zdravotní 5\u{00A0}480", amount: "17\u{00A0}630\u{00A0}Kč",
            isVAT: false)
        let receipt = LatestReceipt(
            invoiceID: 1, date: "15.\u{00A0}10.", number: "20260902", client: "Cetus Data s.r.o.",
            original: "5\u{00A0}445,00\u{00A0}Kč vč. DPH 945,00", czk: "4\u{00A0}500,00\u{00A0}Kč",
            effect: "+8\u{00A0}000\u{00A0}Kč")

        try await expectLink(
            "Plán záloh", in: UpcomingList(items: [advance], showAdvances: {}, showInvoices: {}).padding(24))
        try await expectLink(
            "Všechny faktury",
            in: LatestReceiptsList(receipts: [receipt], open: { _ in }, showInvoices: {}).padding(24))
    }

    /// "Pravidla v Nastavení", the link of the footnote of Výpočet, is a `TextLinkButtonStyle` that is given the trait
    /// of a link by hand, and leads to the rules of the year.
    @Test func theLinkOfTheFootnoteOfVypocetIsReadAsALink() async throws {
        let assumptions = computationPage(TaxEngineRegressionTests.sampleYear2026).assumptions

        try await expectLink(
            "Pravidla v Nastavení", in: AssumptionsFootnote(assumptions: assumptions, showSettings: {}).padding(24))
    }

    /// Zrušit hledání in the line under the filters of Faktury is `calloutLink()`. (The × in the field of the search
    /// has the same name and is a button, so the line is shown alone.)
    @Test func theLinkThatCancelsASearchIsReadAsALink() async throws {
        let line = SearchLine(text: "Hledání „cetus“: 2 z 12 faktur v roce 2026", otherYears: [], emptyText: "")

        try await expectLink(
            "Zrušit hledání", in: SearchLineView(line: line, showYear: { _ in }, clear: {}).padding(24))
    }

    /// Zobrazit dopad v Přehledu at the foot of the impact panel of Zálohy a odpočty is `calloutLink()` and leads to
    /// Přehled.
    @Test func theLinkOfTheImpactPanelIsReadAsALink() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let app = try await makeAdvancesApp(in: directory)

        try await withAppWindow(of: app, size: AppWindowSize.large) { window in
            app.screen = .advances
            try await waitUntil { window.title == "Zálohy a odpočty" }
            try await withAccessibilityElements {
                try await expectLink("Zobrazit dopad v Přehledu", in: window)
            }
        }
    }

    // MARK: The links of Nastavení

    /// The links inside the cards of the tabs of Nastavení: Zobrazit licenci in Aplikace, Zobrazit ve Finderu and
    /// Vybrat složku… in the backups of Zabezpečení, Odebrat účet v eurech in the box of the account in euros in Moje
    /// údaje (in the red of text), and the expenses of the profile, which lead to Zálohy a odpočty, in Rok.
    @Test func theLinksInsideTheCardsOfNastaveniAreReadAsLinks() async throws {
        let licence = try #require(AppTabModel.licences.first)

        try await EditorFixture.with { f in
            try await withAppWindow(of: f.app, size: AppWindowSize.large) { window in
                try await withAccessibilityElements {
                    try await showSettings(.application, of: f.app, in: window)
                    try await expectLink("Zobrazit licenci – \(licence.name)", in: window)

                    try await showSettings(.security, of: f.app, in: window)
                    try await expectLink("Zobrazit ve Finderu", in: window)
                    try await expectLink("Vybrat složku…", in: window)

                    try await showSettings(.supplier, of: f.app, in: window)
                    try await expectLink("Odebrat účet v eurech", in: window)

                    try await showSettings(.year, of: f.app, in: window)
                    try await expectLink("paušál 60\u{00A0}% (strop 1\u{00A0}200\u{00A0}000\u{00A0}Kč)", in: window)
                }
            }
        }
    }

    /// The links of a rate entered by hand and of an adjustment of the income, in Rok: Upravit in the blue of a link,
    /// and Odstranit… and Smazat in the red of text.
    @Test func theLinksOfTheRatesAndTheAdjustmentsOfTheYearAreReadAsLinks() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let app = try await makeSettingsApp(in: directory)
        let database = try #require(app.database)
        let others = try await database.uniformRates(year: 2025).filter { $0.currency != .usd && $0.currency != .eur }
        let typed = UniformRate(
            year: 2025, currency: .usd, amount: 1, rate: decimal("21.90"), instruction: "", origin: .manual)
        try await database.saveUniformRates(others + [typed], year: 2025)
        _ = try await database.saveAdjustment(
            IncomeAdjustment(date: civilDate("2025-06-30"), amountHalere: -100_000, description: "Vratka"))
        app.selectYear(2025)

        try await withAppWindow(of: app, size: AppWindowSize.large) { window in
            try await withAccessibilityElements {
                try await showSettings(.year, of: app, in: window)
                try await expectLink("Upravit jednotný kurz 2025", in: window)
                try await expectLink("Odstranit ručně zadaný jednotný kurz 2025", in: window)
                try await expectLink("Smazat úpravu", in: window)
            }
        }
    }

    // MARK: What stays a button

    /// "Vrátit odhad aplikace" in the block of a client whose months were changed takes them back to the app's choice
    /// on the page and leads nowhere: it has the look of a link (`calloutLink(isLink: false)`) and is read as a button,
    /// as it always was.
    @Test func aTextControlThatDoesSomethingOnThePageIsReadAsAButton() async throws {
        let page = try PredictionSample.page(year: 2026, changes: [PredictionSample.foxtrot.id: [11: false]])
        let section = PredictionMonthsSection(
            page: page, saveFailure: nil, isOpen: .constant(true), othersAreOpen: .constant(false),
            toggle: { _, _ in }, reset: { _ in })
        let label = "Vrátit odhad aplikace"

        try await withHostedView(section.frame(width: 900).padding(24), size: CGSize(width: 1_000, height: 900)) {
            window in
            try await withAccessibilityElements {
                try await waitUntil { accessibilityElement(labelled: label, in: window) != nil }
                let element = try #require(accessibilityElement(labelled: label, in: window))
                let role = element.accessibilityRole?()
                #expect(role == .button, "\(label) is read as \(String(describing: role))")
            }
        }
    }
}
