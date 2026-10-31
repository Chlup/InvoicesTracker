import AppKit
import SwiftUI
import Testing
@testable import InvoicesTracker

/// The sheets of the app, opened where the app opens them in the window of `EditorFixture` and looked at as the pixels
/// of the sheet show them: each is on the colour of a card (`Palette.bgCard`), as the design draws a dialog, in a light
/// and in a dark appearance. A sheet that has no such background shows nothing of its own at the edges of its content,
/// so a pixel at each corner of the sheet that is not the colour of a card is a sheet that was left out of the chrome
/// every sheet shares (`sheetChrome()`). Every place that shows a sheet is here: the forms of a client and of a
/// template, the payment and the PDF of an invoice, the dialog of a child in Zálohy a odpočty and in the Simulátor, the
/// chooser of a new invoice, the confirmation of a uniform rate, and the sheets of Nastavení.
@Suite(.serialized, .settlesBackups)
@MainActor
struct SheetChromeTests {
    /// What a page needs is measured in the font it is set in, so the fonts are registered before any test, as the app
    /// does at its launch.
    init() {
        InvoiceFonts.register()
    }

    /// The sheets of the app, by where they are opened.
    enum Sheet: String, CaseIterable, Sendable, CustomTestStringConvertible {
        case clientForm
        case templateForm
        case payment
        case pdf
        case childOfAdvances
        case childOfSimulator
        case chooser
        case uniformRate
        case licence
        case newCode
        case restore

        var testDescription: String {
            rawValue
        }
    }

    /// The invoice 20260901 of `EditorFixture`, paid in dollars by Bravo.
    private static let invoiceID: Int64 = 10

    @Test(arguments: Sheet.allCases, [ColorScheme.light, .dark])
    func everySheetOfTheAppIsOnTheColourOfACard(sheet: Sheet, scheme: ColorScheme) async throws {
        try await whileTypingAlone {
            try await EditorFixture.with { f in
                try await withAppWindow(of: f.app, size: AppWindowSize.large) { window in
                    window.appearance = appearance(of: scheme)
                    try await withAccessibilityElements {
                        let shown = try await open(sheet, of: f, in: window)
                        try await layOut(shown)
                        let picture = try WindowPicture(of: shown)
                        let size = try #require(shown.contentView).bounds.size
                        let card = try OffscreenPicture.bytes(of: Palette.bgCard, in: scheme) + [255]
                        let corners = [
                            CGPoint(x: 3, y: 3), CGPoint(x: size.width - 3, y: 3), CGPoint(x: 3, y: size.height - 3),
                            CGPoint(x: size.width - 3, y: size.height - 3),
                        ]
                        for corner in corners {
                            let found = picture.bytes(at: corner)
                            #expect(
                                found.count == 4 && zip(found, card).allSatisfy { abs($0 - $1) <= 2 },
                                "\(sheet) in a \(scheme) window: \(corner) is \(found), not a card's colour \(card)")
                        }
                    }
                }
            }
        }
    }

    /// The sheets that the prototype draws are dialogs named by their titles (the `aria-label` of the dialog is the
    /// title it shows): VoiceOver reads each as a group under the title of the form, of the chooser, of the payment, of
    /// the invoice and so on. A sheet is a window of the system with no title of its own, so the group is the root of
    /// its content. The sheets that only the app has, the licence and the uniform rate, are not in the table.
    @Test(arguments: [
        (Sheet.clientForm, "Nový odběratel"), (.templateForm, "Nová šablona"), (.payment, "Upravit platbu"),
        (.pdf, "Faktura 20260901"), (.childOfAdvances, "Nové dítě"), (.childOfSimulator, "Nové dítě v simulaci"),
        (.chooser, "Nová faktura"), (.newCode, "Nový kód pro obnovení"), (.restore, "Obnovit ze zálohy"),
    ])
    func everySheetOfThePrototypeIsNamedByItsTitle(sheet: Sheet, name: String) async throws {
        try await whileTypingAlone {
            try await EditorFixture.with { f in
                try await withAppWindow(of: f.app, size: AppWindowSize.large) { window in
                    try await withAccessibilityElements {
                        let shown = try await open(sheet, of: f, in: window)
                        try await layOut(shown)
                        try await expectContainers([name], in: shown, "The sheet \(sheet)")
                    }
                }
            }
        }
    }

    // MARK: Opening the sheets

    /// Opens `sheet` in `window` as a person does, and returns the sheet once it is there.
    private func open(_ sheet: Sheet, of f: EditorFixture, in window: NSWindow) async throws -> NSWindow {
        switch sheet {
        case .clientForm:
            f.app.screen = .clients
            try await press(button: "Nový odběratel", in: window)
        case .templateForm:
            f.app.screen = .clients
            let prefix = EditorFixture.cetus.name + ","
            try await waitUntil { accessibilityElement(labelStartingWith: prefix, in: window) != nil }
            let row = try #require(accessibilityElement(labelStartingWith: prefix, in: window))
            #expect(row.accessibilityPerformPress?() == true)
            try await press(button: "Nová šablona", in: window)
        case .payment:
            f.app.openInvoice(Self.invoiceID)
            try await press(button: "Upravit platbu", in: window)
        case .pdf:
            f.app.openInvoice(Self.invoiceID)
            try await press(button: "Zobrazit PDF", in: window)
        case .childOfAdvances:
            f.app.screen = .advances
            try await press(button: "Přidat dítě", in: window)
        case .childOfSimulator:
            f.app.screen = .simulator
            try await press(button: "Přidat dítě", in: window)
        case .chooser:
            f.app.editorRequest = .chooser
        case .uniformRate:
            try await #require(f.app.database).execute("DELETE FROM uniform_rate WHERE year = 2025")
            await f.app.offerUniformRate(try gfrFinding2025())
        case .licence:
            f.app.showSettings(.application)
            try await waitUntil { accessibilityElement(labelStartingWith: "Zobrazit licenci", in: window) != nil }
            let link = try #require(accessibilityElement(labelStartingWith: "Zobrazit licenci", in: window))
            #expect(link.accessibilityPerformPress?() == true)
        case .newCode:
            f.app.showSettings(.security)
            try await press(button: "Vytvořit nový kód…", in: window)
        case .restore:
            f.app.showSettings(.security)
            try await press(button: "Obnovit ze zálohy…", in: window)
        }
        try await waitUntil { window.sheets.count == 1 }
        return try #require(window.sheets.first)
    }

    /// Presses the button of `window` that VoiceOver reads under `label`, as a click does, once it is there.
    private func press(button label: String, in window: NSWindow) async throws {
        try await waitUntil { accessibilityButton(labelled: label, in: window)?.isAccessibilityEnabled?() == true }
        let button = try #require(accessibilityButton(labelled: label, in: window))
        #expect(button.accessibilityPerformPress?() == true)
    }
}
