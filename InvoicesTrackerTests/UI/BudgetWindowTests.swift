import AppKit
import SwiftUI
import Testing
@testable import InvoicesTracker

/// Rozpočet in the window of the app, made as the app makes it, on the data of `EditorFixture` as of 17. 10. 2026,
/// whose average net income is 187 111 Kč a month and whose latest paid invoice is 20260902. A new app starts with an
/// empty budget: Náklady a fixed 0 Kč, Úspory and Investice 0 %, and Útrata the remainder.
/// - The row of the sidebar opens the screen, with Přehled's average as its key figure.
/// - Koruny typed into the field of a category change the remainder key by key, and leaving the field shows the amount
///   as the screen writes it and saves the split.
/// - A field that takes the focus and is left without a key typed changes nothing.
/// - The slider of a category is one element that VoiceOver adjusts by 1 %, and the adjustment is saved at once.
/// - Faktura shows the bill of the invoice it divides, and the menu of the invoices of the year picks another.
/// - A failed listing of the invoices keeps the row of the sources above its line, so that another one can be chosen.
///
/// The fields and the controls are found by the labels VoiceOver reads them under, and pressed as VoiceOver presses
/// them. A test that types does so in its turn among the tests that type into a window (`whileTypingAlone`): the text
/// fields of all windows share one field editor. In every expected string `\u{00A0}` is the no-break space.
@Suite(.serialized, .settlesBackups)
@MainActor
struct BudgetWindowTests {
    /// What a page needs is measured in the font it is set in, so the fonts are registered before any test, as the app
    /// does at its launch.
    init() {
        InvoiceFonts.register()
    }

    /// The row of Rozpočet in the list of the sidebar: under the heading of the year with its five screens, the heading
    /// "Evidence" with Odběratelé, and the heading "Nástroje" with Simulátor.
    private static let sidebarRow = 10

    @Test func theScreenOpensFromTheSidebarAndShowsTheAverage() async throws {
        try await EditorFixture.with { f in
            try await withAppWindow(of: f.app, size: AppWindowSize.minimum) { window in
                try await waitUntil { sidebarList(in: window)?.numberOfRows == 12 }
                let list = try #require(sidebarList(in: window))

                // As a click on the row selects it.
                list.selectRowIndexes(IndexSet(integer: Self.sidebarRow), byExtendingSelection: false)

                try await waitUntil { window.title == "Rozpočet" }
                #expect(f.app.screen == .budget)
                #expect(
                    window.subtitle == "Rok 2026 · jak rozdělit čistý příjem na náklady, útratu, úspory a investice")
                try await withAccessibilityElements {
                    // The key figure reads its eyebrow, the average of Přehled and its sentence as one phrase.
                    try await waitUntil {
                        frameOfText(
                            startingWith: "Čistý příjem průměrně za měsíc, 187\u{00A0}111\u{00A0}Kč, ", in: window)
                            != nil
                    }
                }
            }
        }
    }

    @Test func typingKorunyIntoAFieldUpdatesTheRemainder() async throws {
        try await whileTypingAlone {
            try await EditorFixture.with { f in
                try await withAppWindow(of: f.app, size: AppWindowSize.minimum) { window in
                    let model = try await showBudget(of: f.app, in: window)
                    try await withAccessibilityElements {
                        try await waitUntil { textField(labelled: "Úspory v korunách", in: window) != nil }
                        let field = try #require(textField(labelled: "Úspory v korunách", in: window))

                        try type("20 000", into: field, in: window)

                        // The remainder, Útrata, gets what the savings leave at once, while the field keeps the text.
                        try await waitUntil { row(.spending, of: model)?.amountText == "167\u{00A0}111\u{00A0}Kč" }
                        try await waitUntil { showsText("167\u{00A0}111\u{00A0}Kč", in: window) }
                        #expect(row(.savings, of: model)?.percentText == "10,7")
                        #expect(field.stringValue == "20 000")

                        // Leaving the field shows the amount as the screen writes it, and saves the split.
                        #expect(window.makeFirstResponder(nil))
                        try await waitUntil { field.stringValue == "20\u{00A0}000" }
                        try await waitUntil { !model.hasUnsavedInput }
                        let saved = f.app.appSettings.budget.split.allocation(net: 187_111, fixedMultiplier: 1)
                        #expect(saved.amounts[.savings] == 20_000)
                        #expect(saved.amounts[.spending] == 167_111)
                    }
                }
            }
        }
    }

    /// A field that takes the focus and is left without a key typed changes nothing, though SwiftUI hands its text, the
    /// value as the screen writes it, to the screen as its editing ends: a share set from koruny keeps its exact share
    /// when its % field and its Kč field are left, a share set in percent keeps it when its Kč field is left, and a
    /// fixed amount stays as it is. The split is set through the model, so that each field shows its value as the
    /// screen writes it before the test takes the focus to it.
    @Test func aFieldLeftWithoutTypingChangesNothing() async throws {
        try await whileTypingAlone {
            try await EditorFixture.with { f in
                try await withAppWindow(of: f.app, size: AppWindowSize.minimum) { window in
                    let model = try await showBudget(of: f.app, in: window)
                    model.typeAmount("30 000", for: .savings)
                    model.endEditing(.savings)
                    model.typePercent("15", for: .investments)
                    model.endEditing(.investments)
                    model.typeAmount("20 000", for: .costs)
                    model.endEditing(.costs)
                    await model.saveNow()
                    let saved = f.app.appSettings.budget
                    #expect(saved.split.holding(of: .savings) == .share(Decimal(30_000) / Decimal(187_111)))
                    #expect(saved.split.holding(of: .investments) == .share(decimal("0.15")))
                    #expect(saved.split.holding(of: .costs) == .fixed(20_000))
                    try await withAccessibilityElements {
                        // 30 000 Kč of 187 111 Kč is 16,03 %, and 15 % of 187 111 Kč is 28 066,65 Kč.
                        for (label, shown) in [
                            ("Úspory v procentech", "16,0"), ("Úspory v korunách", "30\u{00A0}000"),
                            ("Investice v korunách", "28\u{00A0}067"), ("Náklady v korunách", "20\u{00A0}000"),
                        ] {
                            try await waitUntil { textField(labelled: label, in: window)?.stringValue == shown }
                            let field = try #require(textField(labelled: label, in: window))

                            #expect(window.makeFirstResponder(field), "\(label)")
                            try await layOut(window)
                            #expect(window.makeFirstResponder(nil), "\(label)")
                            try await layOut(window)
                            await model.saveNow()

                            #expect(f.app.appSettings.budget == saved, "\(label)")
                            #expect(field.stringValue == shown, "\(label)")
                        }
                    }
                }
            }
        }
    }

    /// A failed listing of the invoices in Faktura mode shows the line that the page could not be loaded, and above it
    /// the row of the sources, so that another one can be chosen: Skutečnost then shows Přehled's average.
    @Test func aFailedListingOfInvoicesKeepsTheSourcesToChooseFrom() async throws {
        try await EditorFixture.with { f in
            try await storeAnInvoiceThatCannotBeListed(in: f.database)
            await f.app.updateAppSettings { $0.budget.source = .invoice }
            try await withAppWindow(of: f.app, size: AppWindowSize.minimum) { window in
                window.makeKeyAndOrderFront(nil)
                f.app.screen = .budget
                try await waitUntil { window.title == "Rozpočet" }
                try await waitUntil { f.app.budgetModel.errorText != nil }
                try await layOut(window)
                try await withAccessibilityElements {
                    try await waitUntil { showsText("Rozpočet se nepodařilo načíst.", in: window) }
                    try await waitUntil { accessibilityButton(labelled: "Skutečnost", in: window) != nil }

                    _ = try #require(accessibilityButton(labelled: "Skutečnost", in: window))
                        .accessibilityPerformPress?()

                    try await waitUntil { f.app.budgetModel.data?.source == .actual }
                    #expect(f.app.budgetModel.errorText == nil)
                    #expect(f.app.budgetModel.data?.keyFigure.figure == "187\u{00A0}111\u{00A0}Kč")
                    try await waitUntil { !showsText("Rozpočet se nepodařilo načíst.", in: window) }
                    #expect(f.app.appSettings.budget.source == .actual)
                }
            }
        }
    }

    @Test func theSliderIsAdjustableWithVoiceOver() async throws {
        try await EditorFixture.with { f in
            try await withAppWindow(of: f.app, size: AppWindowSize.minimum) { window in
                let model = try await showBudget(of: f.app, in: window)
                try await withAccessibilityElements {
                    let label = "Investice, podíl z čistého příjmu"
                    try await waitUntil { accessibilityElement(labelled: label, in: window) != nil }
                    let slider = try #require(accessibilityElement(labelled: label, in: window))
                    #expect(slider.accessibilityRole?() == .slider)
                    #expect(slider.accessibilityValueDescription?() == "0,0\u{00A0}%")

                    _ = slider.accessibilityPerformIncrement?()

                    // 1 % of 187 111 Kč is 1 871 Kč, which the remainder gives up.
                    try await waitUntil { row(.investments, of: model)?.percentText == "1,0" }
                    #expect(row(.investments, of: model)?.amountText == "1\u{00A0}871")
                    #expect(row(.spending, of: model)?.amountText == "185\u{00A0}240\u{00A0}Kč")
                    try await waitUntil {
                        accessibilityElement(labelled: label, in: window)?.accessibilityValueDescription?()
                            == "1,0\u{00A0}%"
                    }
                    // The adjustment ends the choice, which is saved at once.
                    try await waitUntil {
                        f.app.appSettings.budget.split.holding(of: .investments) == .share(decimal("0.01"))
                    }
                }
            }
        }
    }

    @Test func choosingAnInvoiceShowsItsBill() async throws {
        try await EditorFixture.with { f in
            try await withAppWindow(of: f.app, size: AppWindowSize.minimum) { window in
                _ = try await showBudget(of: f.app, in: window)
                let listed = try await f.app.budgetInvoices()
                let latest = try #require(listed.first { $0.invoice.number == "20260902" })
                let august = try #require(listed.first { $0.invoice.number == "20260801" })
                try await withAccessibilityElements {
                    try await waitUntil { accessibilityButton(labelled: "Faktura", in: window) != nil }

                    _ = try #require(accessibilityButton(labelled: "Faktura", in: window)).accessibilityPerformPress?()

                    // Faktura divides the invoice whose money came last, and shows its bill down to what it leaves.
                    let latestButton = "Faktura 20260902, " + latest.invoice.client.name
                    try await waitUntil { accessibilityButton(labelled: latestButton, in: window) != nil }
                    try await waitUntil {
                        billRow(startingWith: "Přišlo z faktury: ", in: window)?.contains("20260902 · ") == true
                    }
                    #expect(billRow(startingWith: "Daně a odvody: ", in: window) != nil)
                    #expect(billRow(startingWith: "Čistý příjem k rozdělení: ", in: window) != nil)
                    #expect(f.app.appSettings.budget.source == .invoice)

                    // The menu of the invoices of the year picks another one.
                    let picker = try #require(accessibilityButton(labelled: latestButton, in: window))
                    _ = picker.accessibilityPerformPress?()
                    let item = "20260801 · " + august.invoice.client.name
                    try await waitUntil { invoiceMenu(of: window, holding: item) != nil }
                    let menu = try #require(invoiceMenu(of: window, holding: item))
                    let choice = try #require(accessibilityButton(labelled: item, in: menu))
                    // The choices of the menu are drawn, not squeezed out of a list that scrolls.
                    #expect((choice.accessibilityFrame?().height ?? 0) > 20)
                    _ = choice.accessibilityPerformPress?()

                    try await waitUntil { !menu.isVisible }
                    let augustButton = "Faktura 20260801, " + august.invoice.client.name
                    try await waitUntil { accessibilityButton(labelled: augustButton, in: window) != nil }
                    try await waitUntil {
                        billRow(startingWith: "Přišlo z faktury: ", in: window)?.contains("20260801 · ") == true
                    }
                    #expect(f.app.appSettings.budget.invoiceID == august.invoice.id)
                }
            }
        }
    }

    // MARK: Helpers

    /// Shows Rozpočet in `window`, which is made the key window as a person's click makes it, once its model has
    /// loaded, and gives the model.
    private func showBudget(of app: AppModel, in window: NSWindow) async throws -> BudgetModel {
        window.makeKeyAndOrderFront(nil)
        app.screen = .budget
        try await waitUntil { window.title == "Rozpočet" }
        try await waitUntil { app.budgetModel.data != nil }
        try await layOut(window)
        return app.budgetModel
    }

    /// The row of `category` as `model` shows it, or nil while it shows nothing.
    private func row(_ category: BudgetCategory, of model: BudgetModel) -> BudgetRow? {
        model.data?.rows.first { $0.category == category }
    }

    /// What VoiceOver reads for the row of the bill whose reading starts with `prefix`, its label and value, such as
    /// "Přišlo z faktury: 5 445 Kč. 20260902 · …", or nil while `window` shows no such row.
    private func billRow(startingWith prefix: String, in window: NSWindow) -> String? {
        accessibilityElement(labelStartingWith: prefix, in: window)?.accessibilityLabel?() ?? nil
    }

    /// The popover of the menu of the invoices over `window`, which has the choice `item`. Nil while it is closed.
    private func invoiceMenu(of window: NSWindow, holding item: String) -> NSWindow? {
        (window.childWindows ?? []).first { child in
            child.isVisible && accessibilityButton(labelled: item, in: child) != nil
        }
    }

    /// The list of the sidebar in `window`, or nil while it has none.
    private func sidebarList(in window: NSWindow) -> NSOutlineView? {
        guard let content = window.contentView else { return nil }
        return outlines(in: content).first
    }

    private func outlines(in view: NSView) -> [NSOutlineView] {
        if let outline = view as? NSOutlineView {
            return [outline]
        }
        return view.subviews.flatMap { outlines(in: $0) }
    }

    /// Stores an invoice of 2026 that cannot be read: issued on 5. 10. 2026 and due on 25. 11., with a payment whose
    /// day, 30. 2. 2027, does not exist, as a change of the data outside the app could write it. The average of 2026
    /// never comes upon it; the list of the invoices of 2026, which Faktura mode reads, does, and fails.
    private nonisolated func storeAnInvoiceThatCannotBeListed(in database: Database) async throws {
        let id = try await database.saveInvoice(
            Invoice.fixture(
                number: "20261005", issued: "2026-10-05", duzp: "2026-10-05", dueDate: "2026-11-25",
                payment: Payment.fixture(on: "2027-03-01")))
        try await database.write { connection in
            try connection.run("UPDATE payment SET date = ? WHERE invoice_id = ?", [.text("2027-02-30"), .integer(id)])
        }
    }

    /// Types `text` into `field` as a person does: the field takes the focus and its text is replaced, and the change
    /// reaches the binding as the keys do.
    private func type(_ text: String, into field: NSTextField, in window: NSWindow) throws {
        #expect(window.makeFirstResponder(field))
        let editor = try #require(field.currentEditor() as? NSTextView)
        editor.selectAll(nil)
        editor.insertText(text, replacementRange: editor.selectedRange())
    }
}
