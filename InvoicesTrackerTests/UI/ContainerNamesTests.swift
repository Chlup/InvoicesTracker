import AppKit
import SwiftUI
import Testing
@testable import InvoicesTracker

/// The containers of each screen are named as the prototype names them (the `aria-label` of its sections, asides and
/// groups), as VoiceOver reads them: a card, a section of a detail, a group of chips, the column of a result. A name is
/// a text, and the prototype's texts are the design's. One table for each screen lists the names its containers have,
/// in the state the prototype draws them in; a container the prototype names and the screen does not have is a missing
/// name in the failure. The names that depend on the data (the bars, the key figures, the months of a client) are
/// checked with the screens that show them, and the sheets by `SheetChromeTests`.
@Suite(.serialized, .settlesBackups)
@MainActor
struct ContainerNamesTests {
    /// What a page needs is measured in the font it is set in, so the fonts are registered before any test, as the app
    /// does at its launch.
    init() {
        InvoiceFonts.register()
    }

    // MARK: Přehled and the reports

    /// Přehled names the card of what is left to pay, the levies by authority, the income, the grouping of the chart
    /// and the estimate of the whole year as the prototype names them.
    @Test func theCardsOfPrehledAreNamedAsThePrototypeNamesThem() async throws {
        try await EditorFixture.with { f in
            try await withAppWindow(of: f.app, size: AppWindowSize.large) { window in
                f.app.screen = .overview
                try await waitUntil { window.title == "Přehled" }
                try await withAccessibilityElements {
                    try await expectContainers(
                        ["Kolik zbývá zaplatit", "Odvody podle úřadů", "Příjmy", "Seskupit", "Odhad za celý rok"],
                        in: window, "Přehled")
                }
            }
        }
    }

    /// Výpočet names its result, the levies by authority, the cards of the marginal levy and of the limits of the
    /// year, the breakdown and the assumptions of the computation as the prototype names them.
    @Test func theCardsAndTheBreakdownOfVypocetAreNamedAsThePrototypeNamesThem() async throws {
        try await EditorFixture.with { f in
            try await withAppWindow(of: f.app, size: AppWindowSize.large) { window in
                f.app.screen = .computation
                try await waitUntil { window.title == "Výpočet" }
                try await withAccessibilityElements {
                    try await expectContainers(
                        [
                            "Výsledek", "Odvody podle úřadů", "Mezní odvod", "Hranice roku", "Rozpis výpočtu",
                            "Předpoklady výpočtu",
                        ], in: window, "Výpočet")
                }
            }
        }
    }

    /// Odhad odvodů names its result, the levies by authority, the income, the months in which the invoices are
    /// expected and the breakdown of the estimate as the prototype names them.
    @Test func theCardsAndTheBreakdownOfOdhadOdvoduAreNamedAsThePrototypeNamesThem() async throws {
        try await PredictionSample.withStoredSample { app in
            try await withAppWindow(of: app, size: AppWindowSize.large) { window in
                app.screen = .prediction
                try await waitUntil { window.title == "Odhad odvodů" }
                try await withAccessibilityElements {
                    try await expectContainers(
                        ["Výsledek", "Odvody podle úřadů", "Příjmy", "Kdy čekám faktury", "Rozpis odhadu"],
                        in: window, "Odhad odvodů")
                }
            }
        }
    }

    /// The Simulátor names the cards of its inputs, the column with its result and the breakdown under the
    /// simulation as the prototype names them.
    @Test func theCardsTheResultAndTheBreakdownOfTheSimulatorAreNamedAsThePrototypeNamesThem() async throws {
        try await EditorFixture.with { f in
            try await withAppWindow(of: f.app, size: AppWindowSize.large) { window in
                f.app.screen = .simulator
                try await waitUntil { window.title == "Simulátor" }
                let model = f.app.simulatorModel
                model.setIncomeText("2 500 000")
                model.readTypedTexts()
                try await withAccessibilityElements {
                    try await expectContainers(
                        [
                            "Rok a příjem", "Úroky z úvěru na bydlení", "Spoření a pojištění na stáří",
                            "Dary a slevy na dani", "Děti v simulaci", "Manžel nebo manželka v simulaci",
                            "Výsledek simulace", "Kolik zaplatíte", "Odvody podle úřadů", "Mezní odvod",
                            "Rozpis výpočtu simulace",
                        ], in: window, "Simulátor")
                }
            }
        }
    }

    // MARK: The lists and the editor

    /// Faktury names its filters, the list, the summary row and, with a detail open, the detail with its payment and
    /// its effect on the levies as the prototype names them.
    @Test func theListAndTheDetailOfFakturyAreNamedAsThePrototypeNamesThem() async throws {
        try await EditorFixture.with { f in
            try await withAppWindow(of: f.app, size: AppWindowSize.large) { window in
                f.app.pendingDetailInvoiceID = 10
                f.app.screen = .invoices
                try await waitUntil { window.title == "Faktury" }
                try await withAccessibilityElements {
                    try await expectContainers(
                        ["Které faktury", "Seznam faktur", "Souhrn", "Detail faktury", "Platba", "Dopad na odvody"],
                        in: window, "Faktury")
                }
            }
        }
    }

    /// The editor of an invoice names its sections, the group of the chips of the client and the preview as the
    /// prototype names them.
    @Test func theSectionsOfTheEditorAreNamedAsThePrototypeNamesThem() async throws {
        try await EditorFixture.with { f in
            try await withAppWindow(of: f.app, size: AppWindowSize.large) { window in
                f.app.startNewInvoice(templateID: f.crownTemplate.id)
                try await waitUntil { f.app.editor != nil && window.title == "Nová faktura" }
                let editor = try #require(f.app.editor)
                try await waitUntil { editor.document != nil }
                try await withAccessibilityElements {
                    try await expectContainers(
                        [
                            "Odběratel a doklad", "Odběratel", "Platba, měna a DPH", "Položky", "Poznámka",
                            "Dopad na odvody", "Náhled PDF",
                        ], in: window, "Nová faktura")
                }
            }
        }
    }

    /// Zálohy a odpočty names the card of the advances, the cards of the deductions and of the family and the impact
    /// on the tax as the prototype names them.
    @Test func theCardsOfZalohyAOdpoctyAreNamedAsThePrototypeNamesThem() async throws {
        try await EditorFixture.with { f in
            try await withAppWindow(of: f.app, size: AppWindowSize.large) { window in
                f.app.screen = .advances
                try await waitUntil { window.title == "Zálohy a odpočty" }
                try await withAccessibilityElements {
                    try await expectContainers(
                        [
                            "Zálohy", "Úroky z hypotéky", "Spoření a pojištění na stáří", "Dary a slevy", "Děti",
                            "Manžel nebo manželka", "Dopad na daň",
                        ], in: window, "Zálohy a odpočty")
                }
            }
        }
    }

    /// Odběratelé names its list, the summary row and, with a client open, the detail and the templates in it as the
    /// prototype names them.
    @Test func theListAndTheDetailOfOdberateleAreNamedAsThePrototypeNamesThem() async throws {
        try await ClientsFixture.with { f in
            try await withAppWindow(of: f.app, size: AppWindowSize.large) { window in
                f.app.screen = .clients
                try await waitUntil { window.title == "Odběratelé" }
                try await withAccessibilityElements {
                    try await waitUntil { accessibilityElement(labelStartingWith: "Bravo", in: window) != nil }
                    let row = try #require(accessibilityElement(labelStartingWith: "Bravo", in: window))
                    #expect(row.accessibilityPerformPress?() == true)
                    try await expectContainers(
                        ["Seznam odběratelů", "Souhrn", "Detail odběratele", "Šablony faktur"],
                        in: window, "Odběratelé")
                }
            }
        }
    }

    // MARK: Nastavení and Import

    /// Each tab of Nastavení names its cards as the prototype names them.
    @Test(arguments: [
        (SettingsTab.application, ["Části nastavení", "Vzhled", "Kurzy", "Licence"]),
        (SettingsTab.supplier, ["Vaše údaje", "Bankovní účty"]),
        (SettingsTab.security, ["Odemykání", "Kód pro obnovení", "Zálohy"]),
        (
            SettingsTab.year,
            [
                "Profil", "Činnost", "Měsíce bez minima zdravotního pojištění", "Jednotný kurz", "Pravidla",
                "Úpravy příjmů",
            ]
        ),
    ])
    func theCardsOfEachTabOfNastaveniAreNamedAsThePrototypeNamesThem(tab: SettingsTab, names: [String]) async throws {
        try await EditorFixture.with { f in
            try await withAppWindow(of: f.app, size: AppWindowSize.large) { window in
                f.app.showSettings(tab)
                try await waitUntil { window.title == "Nastavení" }
                try await withAccessibilityElements {
                    try await expectContainers(names, in: window, "Nastavení › \(tab)")
                }
            }
        }
    }

    /// The choice of the files in Import is named as the prototype names it.
    @Test func theChoiceOfFilesOfImportIsNamedAsThePrototypeNamesIt() async throws {
        try await EditorFixture.with { f in
            try await withAppWindow(of: f.app, size: AppWindowSize.large) { window in
                f.app.screen = .importer
                try await waitUntil { window.title == "Import faktur" }
                try await withAccessibilityElements {
                    try await expectContainers(["Výběr souborů"], in: window, "Import")
                }
            }
        }
    }
}
