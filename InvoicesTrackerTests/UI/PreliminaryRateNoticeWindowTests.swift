import AppKit
import SwiftUI
import Testing
@testable import InvoicesTracker

/// The notice of the preliminary uniform rate in the window of the app, on the data of `EditorFixture` with a payment
/// in dollars in 2026, ČNB month-end rates for January to September and the year set to its uniform rate, which the app
/// then computes: the notice is under the banner of the screens the rate affects and on no other, and Podrobnosti shows
/// Nastavení › Rok. One window at a time, so that what a test sees settle is its own window.
@Suite(.serialized, .settlesBackups)
@MainActor
struct PreliminaryRateNoticeWindowTests {
    /// The name of the notice: its title.
    private let name = "Předběžný jednotný kurz 2026"

    /// What a page needs is measured in the font it is set in, so the fonts are registered before any test, as the app
    /// does at its launch.
    init() {
        InvoiceFonts.register()
    }

    /// Stores what the year needs to convert at a computed rate: a payment in dollars made on the last day of
    /// September, the ČNB rates of the month ends of January to September, and the choice of the uniform rate.
    private func storeComputedRateOf2026(in app: AppModel) async throws {
        let database = try #require(app.database)
        let monthEnds = [
            "2026-01-30", "2026-02-27", "2026-03-31", "2026-04-30", "2026-05-29", "2026-06-30", "2026-07-31",
            "2026-08-31", "2026-09-30",
        ]
        try await database.insertCNBRates(
            monthEnds.flatMap { day in
                [
                    CNBRateRow(declaredOn: civilDate(day), currency: .usd, amount: 1, rate: decimal("21.35")),
                    CNBRateRow(declaredOn: civilDate(day), currency: .eur, amount: 1, rate: decimal("24.35")),
                ]
            })
        var invoice = Invoice.fixture(
            number: "20269001", currency: .usd, duzp: "2026-09-30", dueDate: "2026-09-30",
            items: [.fixture("1", at: 1_000_000)], vatMode: .outsideCountry)
        invoice.payment = try await app.convert(
            invoice, paidOn: civilDate("2026-09-30"), method: .cnbDaily, in: database)
        invoice.id = try await database.saveInvoice(invoice)
        try await database.updateYearSettings(2026) { $0.incomeFXMethod = .uniform }
        await app.didWrite()
        await app.updateComputedUniformRates()
    }

    /// Whether the window shows the notice, as a container VoiceOver reads under its title.
    private func showsNotice(in window: NSWindow) -> Bool {
        containerLabels(in: window).contains(name)
    }

    /// The notice is under the banner of Přehled, Faktury, Zálohy a odpočty, Výpočet, Odhad odvodů and Rozpočet, and
    /// not on Odběratelé, Simulátor, Import and Nastavení.
    @Test func theNoticeIsOnTheScreensTheRateAffectsAndOnNoOther() async throws {
        try await EditorFixture.with { f in
            try await storeComputedRateOf2026(in: f.app)
            try await withAppWindow(of: f.app, size: AppWindowSize.large) { window in
                try await withAccessibilityElements {
                    for screen in Screen.allCases {
                        f.app.screen = screen
                        try await waitUntil { window.title == screen.header(
                            year: 2026, asOf: f.app.asOf.asOf, today: f.app.today, incomeFX: .uniform).title
                        }
                        if screen.showsPreliminaryRateNotice {
                            try await waitUntil { showsNotice(in: window) }
                        } else {
                            // Settled: the state of the year has been read, and the notice is not there.
                            try await waitUntil { f.app.shownYearFX?.usesComputedRate == true }
                            #expect(!showsNotice(in: window), "\(screen) shows the notice")
                        }
                    }
                }
            }
        }
    }

    /// Podrobnosti of the notice opens Nastavení on the Rok tab.
    @Test func podrobnostiShowsNastaveniRok() async throws {
        try await EditorFixture.with { f in
            try await storeComputedRateOf2026(in: f.app)
            try await withAppWindow(of: f.app, size: AppWindowSize.large) { window in
                f.app.screen = .overview
                try await withAccessibilityElements {
                    try await waitUntil { showsNotice(in: window) }
                    let details = try #require(accessibilityButton(labelled: "Podrobnosti", in: window))
                    _ = details.accessibilityPerformPress?()
                    try await waitUntil { f.app.screen == .settings && f.app.settingsTab == .year }
                }
            }
        }
    }

    /// While the invoice editor is open in the place of the list of Faktury, the notice is not shown, and it comes back
    /// with the list.
    @Test func theInvoiceEditorHasNoNotice() async throws {
        try await EditorFixture.with { f in
            try await storeComputedRateOf2026(in: f.app)
            try await withAppWindow(of: f.app, size: AppWindowSize.large) { window in
                f.app.screen = .invoices
                try await withAccessibilityElements {
                    try await waitUntil { showsNotice(in: window) }
                    f.app.editorRequest = .new(templateID: nil, clientID: nil)
                    try await waitUntil { !showsNotice(in: window) }
                    f.app.editorRequest = nil
                    try await waitUntil { showsNotice(in: window) }
                }
            }
        }
    }

    /// The year converted at the daily rates has no notice, whichever screen is shown.
    @Test func aYearOnTheDailyRatesHasNoNotice() async throws {
        try await EditorFixture.with { f in
            try await storeComputedRateOf2026(in: f.app)
            try await f.database.updateYearSettings(2026) { $0.incomeFXMethod = .cnbDaily }
            await f.app.didWrite()
            try await withAppWindow(of: f.app, size: AppWindowSize.large) { window in
                f.app.screen = .overview
                try await withAccessibilityElements {
                    try await waitUntil { f.app.shownYearFX?.effective == .cnbDaily }
                    #expect(!showsNotice(in: window))
                }
            }
        }
    }
}
