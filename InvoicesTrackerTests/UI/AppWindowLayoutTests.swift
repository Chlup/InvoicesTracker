import AppKit
import SwiftUI
import Testing
@testable import InvoicesTracker

/// The screens in the window of the app, made as the app makes it, with the content under the unified toolbar: at the
/// least room the app allows and in a large window, laid out a few times and resized. AppKit settles their layout (a
/// layout that does not settle stops the app with an exception), and every part of them is inside the window. Faktury
/// is shown with the detail closed and open, with and without a search, on the data of `EditorFixture` and an invoice
/// of 2025 for Alfa, so that the search for "alfa" links another year too. Two screens also keep what their layout
/// promises: Výpočet runs from its result card through its two cards and its note to the breakdown and the footnote,
/// and the card of the table of Faktury starts with its summary row, above the names of the columns (32 points) and
/// rows of 40 points. The detail of an invoice is a card beside the table, level with it, and the window does not grow
/// for it; the table follows the width of the window both ways down to its least width, below which it scrolls sideways
/// under the summary row, which does not; a click on a row opens it and the arrow keys open the rows around it, and
/// "Vystavit" in the detail of a draft issues it where it is, without the editor, or its detail says why it cannot. The
/// search of Faktury is a field of its page, at the end of the filter row, not in the toolbar: Hledat (⌘F) focuses it,
/// Esc and its × clear it, and it stays the same field with its focus when the row wraps. The toolbar offers the
/// reporting year and no date or simulation controls. Reporting follows month end automatically while income headings
/// and new income adjustments keep the real cash cutoff. Every item of the toolbar fits it at the least room on every
/// screen. The page of Nastavení stands still while a tab loads: the switcher of the tabs does not move, and the tabs
/// that have no cards until they have read their data say "Načítám…". Odběratelé is laid out as Faktury is: under Nový
/// odběratel the card of its table, with the summary row on top and rows of one line, 40 points high, reaches down to
/// the bottom margin of the page; a click on a row, anywhere on it, opens the detail of its client beside the card and
/// not the form, and a second click closes it; the selection stays when the year changes, and a client saved in the
/// form of Nový odběratel becomes the selected one, its row scrolled into view. With the detail open in the least
/// window the table scrolls sideways in its card, and a wheel over the rows scrolls them up and down and the table
/// sideways. The detail of a client is as high as its content and no higher than the card of the table, in which it
/// scrolls what does not fit, and its figure is muted where the client has paid nothing; its Nová šablona opens the
/// form of a template for its client, whose new template then shows in the detail, and the panel of a template opens
/// its form and starts an invoice from it. Zálohy a odpočty fits with the note about rent (§ 9) under the menu of its
/// rate of 30 %, whole and clear of the box of the reduced base, and with the cards of a family whose texts are the
/// longest, every text whole, and so does the dialog of a child, a sheet with the lock after inactivity over it.
/// Výpočet and Přehled fit with a family whose benefit is a tax bonus, every row of the family as tall as its texts
/// need and the bar of the tax whole. The Simulátor fits with the cards of the family after its deductions, empty and
/// with the sample family copied into them, and with a secondary activity chosen and the rate of 30 % taken from the
/// settings of the year, whose box of the health minimum and its line are whole, and so is the note of the expenses
/// under the choices, with the sentence about rent (§ 9) after the one about the settings; in a large window the three
/// choices of its assumptions stand in one row. Its result is one card of 360 points beside the inputs, in the least
/// window too, with the key figure, the bar of the levies, the net income and the marginal levy one under the other,
/// whether the levies are more than the income or not, and the popover of the bar is drawn over the net income and the
/// marginal levy. The breakdown of Výpočet and of the Simulátor stands in two columns in a large window and in
/// one at the least room, and the key figure and the levy bar of the result card of Výpočet stand side by side where
/// the card has the room of two columns and one above the other where it has not, with its two cards of one height in a
/// row under it. Odhad odvodů fits with the months of its clients folded and unfolded, its result card and its card
/// Příjmy laid out as their widths say, its breakdown in the same two columns and the texts of its cells whole, and it
/// runs result card, Příjmy, note, months, breakdown; the page of a year without rules of its own fits as well, which
/// has a warning above its result card and no sign "≈" in it. One window at a time, so that what a test sees settle is
/// its own window.
@Suite(.serialized, .settlesBackups)
@MainActor
struct AppWindowLayoutTests {
    /// What a page needs is measured in the font it is set in, so the fonts are registered before any test, as the app
    /// does at its launch.
    init() {
        InvoiceFonts.register()
    }

    // MARK: The toolbar

    /// The toolbar offers the year, currency conversion and a new invoice without editable reporting-date controls.
    @Test func theToolbarHasNoReportingDateOrSimulationControls() async throws {
        try await EditorFixture.with(clock: ManualClock(localNoon(2026, 10, 28))) { f in
            try await withAppWindow(of: f.app, size: AppWindowSize.minimum) { window in
                try await layOut(window)
                let toolbarViews = (window.toolbar?.items ?? []).compactMap(\.view)
                #expect(!toolbarViews.isEmpty)
                #expect(toolbarViews.flatMap { datePickers(in: $0) }.isEmpty)
                try await withAccessibilityElements {
                    try await waitUntil { accessibilityButton(labelled: "Nová faktura", in: window) != nil }
                    #expect(yearMenu(in: window) != nil)
                    #expect(accessibilityButton(labelled: "Dnes", in: window) == nil)
                    #expect(accessibilityButton(labelled: "K datu 31.\u{00A0}10.\u{00A0}2026", in: window) == nil)
                    #expect(accessibilityElement(labelled: "simulace budoucnosti", in: window) == nil)
                    #expect(f.app.today == civilDate("2026-10-28"))
                    #expect(f.app.asOf.asOf == civilDate("2026-10-31"))
                }
            }
        }
    }

    /// The automatic reporting month changes without turning future payments into received income in the heading.
    @Test func theComputationHeadingUsesRealTodayWhileReportingFollowsMonthEnd() async throws {
        try await EditorFixture.with(clock: ManualClock(localNoon(2026, 10, 28))) { f in
            f.app.screen = .computation
            try await withAppWindow(of: f.app, size: AppWindowSize.minimum) { window in
                try await withAccessibilityElements {
                    // The key figure is read as one phrase that starts with its eyebrow.
                    let octoberHeading = "Zbývá zaplatit k 28.\u{00A0}10.\u{00A0}2026"
                    try await waitUntil { frameOfText(startingWith: octoberHeading, in: window) != nil }
                    #expect(f.app.asOf.asOf == civilDate("2026-10-31"))

                    f.app.handleDayChanged(civilDate("2026-11-01"))
                    let novemberHeading = "Zbývá zaplatit k 1.\u{00A0}11.\u{00A0}2026"
                    try await waitUntil { frameOfText(startingWith: novemberHeading, in: window) != nil }
                    #expect(f.app.today == civilDate("2026-11-01"))
                    #expect(f.app.asOf.asOf == civilDate("2026-11-30"))
                }
            }
        }
    }

    /// Changing years reloads the settings tab and keeps a new income adjustment on the real received-through day.
    @Test func returningToTheCurrentYearKeepsTheIncomeAdjustmentOnRealToday() async throws {
        try await EditorFixture.with(clock: ManualClock(localNoon(2026, 10, 28))) { f in
            try await withAppWindow(of: f.app, size: AppWindowSize.minimum) { window in
                f.app.showSettings(.year)
                try await waitUntil { window.title == "Nastavení" }
                try await withAccessibilityElements {
                    try await waitUntil { frameOfText(startingWith: "Platí jen pro rok 2026", in: window) != nil }
                    f.app.selectYear(2025)
                    try await waitUntil { frameOfText(startingWith: "Platí jen pro rok 2025", in: window) != nil }
                    #expect(f.app.asOf.asOf == civilDate("2025-12-31"))

                    f.app.selectYear(2026)
                    try await waitUntil { frameOfText(startingWith: "Platí jen pro rok 2026", in: window) != nil }
                    try await layOut(window)
                    #expect(f.app.today == civilDate("2026-10-28"))
                    #expect(f.app.asOf.asOf == civilDate("2026-10-31"))
                    #expect(f.app.asOf.followsToday)
                    let frame = try #require(window.contentView?.superview)
                    let timeZone = f.app.dependencies.timeZone()
                    let shown = datePickers(in: frame).map { CivilDate.today(now: $0.dateValue, timeZone: timeZone) }
                    #expect(!shown.isEmpty, "the Datum of a new income adjustment")
                    #expect(shown.allSatisfy { $0 == civilDate("2026-10-28") }, "the days shown: \(shown)")
                }
            }
        }
    }

    /// The date pickers under `view`.
    private func datePickers(in view: NSView) -> [NSDatePicker] {
        if let picker = view as? NSDatePicker {
            return [picker]
        }
        return view.subviews.flatMap { datePickers(in: $0) }
    }

    // MARK: The toolbar at the least room

    /// Every toolbar item remains visible on every screen, including the longer uniform-rate capsule.
    @Test func theToolbarFitsEveryItemAtTheMinimumWindow() async throws {
        try await EditorFixture.with { f in
            // Rates of 2026 entered by hand, and the year switched to them.
            let typed = [("USD", "21.50"), ("EUR", "24.50")].map { code, rate in
                UniformRate(
                    year: 2026, currency: CurrencyCode(code)!, amount: 1, rate: decimal(rate), instruction: "",
                    sourceURL: nil, confirmedAt: nil, origin: .manual)
            }
            try await f.database.saveUniformRates(typed, year: 2026)
            #expect(await f.app.setFXMethod(.uniform, year: 2026) == .saved)
            try await withAppWindow(of: f.app, size: AppWindowSize.minimum) { window in
                f.app.pickAsOf(civilDate("2026-12-15"))
                try await withAccessibilityElements {
                    let capsule = "Přepočet cizích měn v roce 2026: jednotný kurz"
                    try await waitUntil { accessibilityButton(labelled: capsule, in: window) != nil }
                    for screen in Screen.allCases {
                        f.app.screen = screen
                        let title = screen.header(
                            year: 2026, asOf: f.app.asOf.asOf, today: f.app.today, incomeFX: .uniform
                        ).title
                        try await waitUntil { window.title == title }
                        try await expectSettled(window) {
                            toolbarProblems(of: window).map { "\(screen): \($0)" }
                        }
                    }
                }
            }
        }
    }

    /// The year menu, rate capsule and new-invoice button all fit without an overflow menu.
    private func toolbarProblems(of window: NSWindow) -> [String] {
        guard let toolbar = window.toolbar else { return ["The window has no toolbar"] }
        let shown = Set((toolbar.visibleItems ?? []).map { ObjectIdentifier($0) })
        let problems = toolbar.items.enumerated().compactMap { index, item in
            shown.contains(ObjectIdentifier(item)) ? nil : "Item \(index + 1) '\(item.label)' does not fit"
        }
        guard toolbar.items.count == 3 else {
            return problems + ["The toolbar has \(toolbar.items.count) items, not 3"]
        }
        return problems
    }

    // MARK: Faktury

    /// The invoice of `EditorFixture` that the tests of Faktury open, as Přehled opens an invoice: 2026-03-01 for Alfa,
    /// which the search for "alfa" finds too.
    private static let alfaInvoiceID: Int64 = 3

    /// The invoice of `EditorFixture` in dollars, 20260901 for Bravo, paid on 2. 10. 2026, whose detail is one of the
    /// highest: its payment crosses a threshold of the levies, so that the note of its section says so.
    private static let dollarInvoiceID: Int64 = 10

    @Test(arguments: [false, true], [nil, "alfa"] as [String?])
    func fakturyFitsTheWindowAtTheLeastRoomAndAtALargeSize(detailOpen: Bool, search: String?) async throws {
        try await EditorFixture.with { f in
            try await f.database.saveInvoice(SearchFixtures.earlierCrownInvoice(clientID: f.alfaID))
            await f.app.didWrite()
            f.app.searchText = search ?? ""
            try await withAppWindow(of: f.app, size: AppWindowSize.minimum) { window in
                try await withAccessibilityElements {
                    if detailOpen {
                        // As Přehled opens an invoice: Faktury shows it with its detail beside the table.
                        f.app.openInvoice(Self.alfaInvoiceID)
                    } else {
                        f.app.screen = .invoices
                    }
                    // The eleven invoices of 2026, or the five of them that "alfa" finds.
                    let rows = search == nil ? 11 : 5
                    try await waitUntil { invoiceRows(in: window).count == rows }

                    try await expectSettled(window) { problems(of: window, detailOpen: detailOpen) }
                    window.setContentSize(AppWindowSize.large)
                    try await expectSettled(window) { problems(of: window, detailOpen: detailOpen) }
                    window.setContentSize(AppWindowSize.minimum)
                    try await expectSettled(window) { problems(of: window, detailOpen: detailOpen) }
                }
            }
        }
    }

    /// The detail of an invoice is a card of the page beside the table: it starts where the card of the table starts,
    /// under the filters, and is as high as its content, or as that card where its content is higher; it is 340 points
    /// wide and stands at the right margin of the page, the card of the table ending 16 points before it. The window
    /// has no inspector beside the page: its split views hold the sidebar and the page alone.
    @Test func theDetailCardStandsBesideTheTableAndStartsWithIt() async throws {
        try await EditorFixture.with { f in
            try await withAppWindow(of: f.app, size: AppWindowSize.large) { window in
                try await withAccessibilityElements {
                    f.app.openInvoice(Self.alfaInvoiceID)
                    try await waitUntil { detailCardFrame(in: window) != nil }

                    try await expectSettled(window) { problems(of: window, detailOpen: true) }
                    #expect(openRowNumber(in: window) == "2026-03-01")
                    #expect(splitViewItemBehaviors(in: window) == [.sidebar, .default])
                }
            }
        }
    }

    /// A detail that fits beside the table is as high as its content, as the prototype's panel is, and no higher: in a
    /// large window the detail of a paid invoice starts with the card of the table and ends 20 points under its last
    /// button, Smazat fakturu…, which is well above the bottom of that card, and it has nothing to scroll.
    @Test func aDetailThatFitsIsAsHighAsItsContentAndShorterThanTheTable() async throws {
        try await EditorFixture.with { f in
            try await withAppWindow(of: f.app, size: AppWindowSize.large) { window in
                try await withAccessibilityElements {
                    f.app.openInvoice(Self.alfaInvoiceID)
                    try await waitUntil { detailCardFrame(in: window) != nil }
                    try await expectSettled(window) { problems(of: window, detailOpen: true) }

                    let detail = try #require(detailCardFrame(in: window))
                    let table = try #require(tableCardFrame(in: window))
                    let delete = try #require(buttonFrame("Smazat fakturu…", in: window))
                    #expect(detail.height < table.height - 50, "The detail \(detail) is not shorter than \(table)")
                    #expect((detail.maxY - table.maxY).magnitude <= 1, "\(detail) does not start with \(table)")
                    #expect((delete.minY - detail.minY - 20).magnitude <= 1.5, "\(delete) in \(detail)")
                    #expect(detailOverflow(in: window) <= 0.5, "The detail scrolls \(detailOverflow(in: window))")
                }
            }
        }
    }

    /// A detail whose content is higher than the card of the table is as high as that card and no higher, and the part
    /// of the content that does not fit scrolls inside it: in the least window the detail of a paid invoice in dollars
    /// starts with the card of the table and ends where it ends, and its content is higher than the card shows.
    @Test func aDetailHigherThanTheTableIsCappedAtItAndScrollsInsideIt() async throws {
        try await EditorFixture.with { f in
            try await withAppWindow(of: f.app, size: AppWindowSize.minimum) { window in
                try await withAccessibilityElements {
                    f.app.openInvoice(Self.dollarInvoiceID)
                    try await waitUntil { detailCardFrame(in: window) != nil }
                    try await expectSettled(window) { problems(of: window, detailOpen: true) }

                    let detail = try #require(detailCardFrame(in: window))
                    let table = try #require(tableCardFrame(in: window))
                    #expect((detail.maxY - table.maxY).magnitude <= 1, "\(detail) does not start with \(table)")
                    #expect((detail.minY - table.minY).magnitude <= 1, "\(detail) does not end with \(table)")
                    #expect(detailOverflow(in: window) > 50, "The detail scrolls \(detailOverflow(in: window))")
                }
            }
        }
    }

    /// How much higher than the part of it that the card of the detail of Faktury in `window` shows its content is,
    /// which is what scrolls in it (`overflow(ofTheCardFramed:in:)`). Needs the accessibility elements
    /// (`withAccessibilityElements(_:)`).
    private func detailOverflow(in window: NSWindow) -> CGFloat {
        overflow(ofTheCardFramed: detailCardFrame(in: window), in: window)
    }

    /// How much higher than the part of it that the card framed `card` in `window` shows its content is, which is what
    /// scrolls in it: the scroll view within the card. Nothing where the card is as high as its content, which then has
    /// no scroll view of its own, and where there is no card.
    private func overflow(ofTheCardFramed card: CGRect?, in window: NSWindow) -> CGFloat {
        guard let card, let content = window.contentView else { return 0 }
        let scrolled = scrollViews(in: content).first { card.insetBy(dx: -1, dy: -1).contains(frameInWindow($0)) }
        guard let scrolled, let document = scrolled.documentView else { return 0 }
        return max(0, document.frame.height - scrolled.contentView.bounds.height)
    }

    /// The frame of the button that VoiceOver reads under `label` in `window`, in the coordinates of the window.
    private func buttonFrame(_ label: String, in window: NSWindow) -> CGRect? {
        let frame = accessibilityButton(labelled: label, in: window)?.accessibilityFrame?()
        return frame.map { window.convertFromScreen($0) }
    }

    /// The buttons of the detail of an invoice that the design has under its header, by the name VoiceOver reads for
    /// them in `window`, in the order of reading: the row above first, and on a row the left one first. A button that
    /// the detail does not have is left out.
    private func detailActions(in window: NSWindow) -> [(name: String, frame: CGRect)] {
        let names = ["Označit jako uhrazenou", "Vystavit", "Upravit", "Upravit platbu", "Zobrazit PDF"]
        var found: [(name: String, frame: CGRect)] = []
        for name in names {
            if let frame = accessibilityButton(labelled: name, in: window)?.accessibilityFrame?() {
                found.append((name, frame))
            }
        }
        // The origin of the screen is at the bottom left, so the higher a button the larger its y.
        return found.sorted { first, second in
            if abs(first.frame.midY - second.frame.midY) > 1 {
                return first.frame.midY > second.frame.midY
            }
            return first.frame.minX < second.frame.minX
        }
    }

    /// The names of `detailActions(in:)`.
    private func detailActionNames(in window: NSWindow) -> [String] {
        detailActions(in: window).map(\.name)
    }

    /// What is wrong with the buttons under the header of the detail in `window`, in words: one is a button that is off
    /// or not a capsule 28 points high, the height of a button inside a card.
    private func problems(ofTheDetailActionsIn window: NSWindow) -> [String] {
        detailActions(in: window).flatMap { action -> [String] in
            var problems: [String] = []
            if abs(action.frame.height - 28) >= 0.5 {
                problems.append("\(action.name) is \(action.frame.height) points high")
            }
            if accessibilityButton(labelled: action.name, in: window)?.isAccessibilityEnabled?() == false {
                problems.append("\(action.name) is off")
            }
            return problems
        }
    }

    /// A paid invoice is not edited, only its payment: its detail offers to change the payment and to show the PDF, and
    /// "Upravit" is not there at all, not even as a button that is off. (The invoice of 2026-03-01 is paid on 7. 4.)
    @Test func aPaidInvoiceOffersOnlyItsPaymentAndThePDF() async throws {
        try await EditorFixture.with { f in
            try await withAppWindow(of: f.app, size: AppWindowSize.large) { window in
                try await withAccessibilityElements {
                    f.app.openInvoice(Self.alfaInvoiceID)
                    try await waitUntil { detailCardFrame(in: window) != nil }
                    try await waitUntil { accessibilityButton(labelled: "Zobrazit PDF", in: window) != nil }

                    #expect(accessibilityButton(labelled: "Upravit", in: window) == nil)
                    #expect(accessibilityButton(labelled: "Upravit platbu", in: window) != nil)
                    #expect(accessibilityButton(labelled: "Zobrazit PDF", in: window) != nil)
                    #expect(detailActionNames(in: window) == ["Upravit platbu", "Zobrazit PDF"])
                    #expect(problems(ofTheDetailActionsIn: window) == [])
                    #expect(accessibilityButton(labelled: "Smazat fakturu…", in: window) != nil)
                }
            }
        }
    }

    /// An invoice that waits for its payment is marked paid, edited and shown as a PDF, in that order, and its payment
    /// is not there to change: the payment of an invoice is only changed once it has one.
    @Test func anUnpaidInvoiceOffersPaymentEditingAndPDF() async throws {
        try await EditorFixture.with { f in
            let unpaid = try await f.storeIssuedDollarInvoice()
            await f.app.didWrite()
            try await withAppWindow(of: f.app, size: AppWindowSize.large) { window in
                try await withAccessibilityElements {
                    f.app.openInvoice(unpaid.id)
                    try await waitUntil { detailCardFrame(in: window) != nil }
                    try await waitUntil { accessibilityButton(labelled: "Zobrazit PDF", in: window) != nil }

                    #expect(detailActionNames(in: window) == ["Označit jako uhrazenou", "Upravit", "Zobrazit PDF"])
                    #expect(problems(ofTheDetailActionsIn: window) == [])
                }
            }
        }
    }

    /// A draft is issued, edited and shown as a PDF, in that order. It is not marked paid before it is issued.
    @Test func aDraftOffersIssueEditAndPDF() async throws {
        try await EditorFixture.with { f in
            let draft = try await f.storeIssuedDollarInvoice(number: "20260904", status: .draft)
            await f.app.didWrite()
            try await withAppWindow(of: f.app, size: AppWindowSize.large) { window in
                try await withAccessibilityElements {
                    f.app.openInvoice(draft.id)
                    try await waitUntil { detailCardFrame(in: window) != nil }
                    try await waitUntil { accessibilityButton(labelled: "Zobrazit PDF", in: window) != nil }

                    #expect(detailActionNames(in: window) == ["Vystavit", "Upravit", "Zobrazit PDF"])
                    #expect(problems(ofTheDetailActionsIn: window) == [])
                }
            }
        }
    }

    /// "Vystavit" issues a draft where it is, in one click: the editor does not open, and Faktury keeps the detail of
    /// the invoice, which shows it issued, with the buttons of an invoice that waits for its payment; no banner says
    /// so. The rate of its DUZP is fixed on it as the editor fixes it: 21,522, declared on 30. 9. 2026.
    @Test func vystavitIssuesADraftWhereItIsWithoutTheEditor() async throws {
        try await EditorFixture.with { f in
            let draft = try await f.storeIssuedDollarInvoice(number: "20260904", status: .draft)
            await f.app.didWrite()
            try await withAppWindow(of: f.app, size: AppWindowSize.large) { window in
                try await withAccessibilityElements {
                    f.app.openInvoice(draft.id)
                    try await waitUntil { detailActionNames(in: window) == ["Vystavit", "Upravit", "Zobrazit PDF"] }

                    let issue = try #require(accessibilityButton(labelled: "Vystavit", in: window))
                    #expect(issue.accessibilityPerformPress?() == true)
                    try await waitUntil {
                        detailActionNames(in: window) == ["Označit jako uhrazenou", "Upravit", "Zobrazit PDF"]
                    }

                    let issued = try await f.stored(draft.id)
                    #expect(issued.status == .issued)
                    #expect(issued.invoiceRate == storedRate("USD", "21.522", declaredOn: "2026-09-30"))
                    #expect(f.app.editorRequest == nil)
                    #expect(window.title == "Faktury")
                    #expect(f.app.banner == nil)
                    #expect(detailCardFrame(in: window) != nil)
                    #expect(showsText("Čeká na platbu", in: window))
                    #expect(problems(ofTheDetailActionsIn: window) == [])
                }
            }
        }
    }

    /// A draft that cannot be issued stays a draft, and its detail says why under its buttons, with the reason the
    /// editor gives: here its DUZP, 31. 5. 2024, has no rate in the cache of the ČNB, and the file of 2024 that it asks
    /// for does not come. The buttons stay as they were and on, "Upravit" among them, and the editor does not open.
    @Test func aDraftThatCannotBeIssuedSaysWhyInItsDetailAndCanStillBeEdited() async throws {
        try await EditorFixture.with { f in
            var draft = try await f.storeIssuedDollarInvoice(number: "20240501", status: .draft)
            draft.issueDate = civilDate("2024-05-31")
            draft.duzp = civilDate("2024-05-31")
            draft.dueDate = civilDate("2024-06-30")
            draft.invoiceRate = nil
            try await f.database.saveInvoice(draft)
            await f.app.didWrite()
            try await withAppWindow(of: f.app, size: AppWindowSize.large) { window in
                try await withAccessibilityElements {
                    f.app.openInvoice(draft.id)
                    try await waitUntil { detailActionNames(in: window) == ["Vystavit", "Upravit", "Zobrazit PDF"] }

                    let issue = try #require(accessibilityButton(labelled: "Vystavit", in: window))
                    #expect(issue.accessibilityPerformPress?() == true)
                    let reason = "Kurz ČNB k DUZP zatím není stažený. Fakturu vystavíte, až se kurzy stáhnou."
                    try await waitUntil { showsText(reason, in: window) }

                    #expect(f.http.requests == [CNBEndpoints.yearly(2024)])
                    #expect(try await f.stored(draft.id).status == .draft)
                    #expect(detailActionNames(in: window) == ["Vystavit", "Upravit", "Zobrazit PDF"])
                    #expect(problems(ofTheDetailActionsIn: window) == [])
                    #expect(f.app.editorRequest == nil)
                    #expect(window.title == "Faktury")
                }
            }
        }
    }

    /// The table follows the window both ways: it is narrower in the least window than in a large one, and as wide as
    /// before once the window is large again. Each time it is as wide as its card, with nothing to scroll sideways: in
    /// the least window, while the detail is closed, the card (828 points) holds the table, whose least width is 772.
    @Test func theTableShrinksWhenTheWindowNarrowsAndGrowsBack() async throws {
        try await EditorFixture.with { f in
            try await withAppWindow(of: f.app, size: AppWindowSize.large) { window in
                try await withAccessibilityElements {
                    f.app.screen = .invoices
                    try await waitUntil { invoiceList(in: window) != nil }
                    try await expectSettled(window) {
                        problems(of: window, detailOpen: false) + problems(ofTheTableFillingItsCardIn: window)
                    }
                    let large = try tableWidth(in: window)

                    window.setContentSize(AppWindowSize.minimum)
                    try await expectSettled(window) {
                        problems(of: window, detailOpen: false) + problems(ofTheTableFillingItsCardIn: window)
                    }
                    #expect(try tableWidth(in: window) < large)

                    window.setContentSize(AppWindowSize.large)
                    try await expectSettled(window) {
                        problems(of: window, detailOpen: false) + problems(ofTheTableFillingItsCardIn: window)
                    }
                    #expect((try tableWidth(in: window) - large).magnitude <= 1)
                }
            }
        }
    }

    /// Below its least width the table keeps that width and scrolls sideways in its card, with the detail beside the
    /// card. In the least window with the detail open it is that wide, the least widths of its columns (684 points)
    /// with 8 points between each two and 16 at either end, 772 points, which is more than its card shows, and the card
    /// has a horizontal scroller.
    @Test func aTableBelowItsMinimumScrollsSideways() async throws {
        try await EditorFixture.with { f in
            try await withAppWindow(of: f.app, size: AppWindowSize.minimum) { window in
                try await withAccessibilityElements {
                    f.app.openInvoice(Self.alfaInvoiceID)
                    try await waitUntil { detailCardFrame(in: window) != nil }
                    try await expectSettled(window) { problems(of: window, detailOpen: true) }

                    let scrollView = try #require(tableScrollView(in: window))
                    let table = try tableWidth(in: window)
                    #expect(InvoiceTableColumns().minimumWidth == 772)
                    #expect((table - 772).magnitude < 0.5)
                    #expect(table > scrollView.contentView.bounds.width + 0.5)
                    #expect(scrollView.hasHorizontalScroller)
                    #expect(scrollView.horizontalScroller?.isHidden == false)
                }
            }
        }
    }

    /// The detail opens in the window as it is: when a click on a row opens it, the window does not grow to make room
    /// for it, though the screen has room, as it did for the inspector the detail was before.
    @Test func theWindowDoesNotWidenWhenTheDetailOpens() async throws {
        try await EditorFixture.with { f in
            try await withAppWindow(of: f.app, size: AppWindowSize.minimum) { window in
                f.app.screen = .invoices
                try await withAccessibilityElements {
                    try await waitUntil { invoiceRows(in: window).count == 11 }
                    try await layOut(window)
                    let size = window.frame.size

                    press(try #require(invoiceRows(in: window).first))
                    try await waitUntil { detailCardFrame(in: window) != nil }
                    try await expectSettled(window) { problems(of: window, detailOpen: true) }

                    #expect(window.frame.size == size)
                }
            }
        }
    }

    /// A click on a row opens its invoice (VoiceOver presses the row as a click does) and gives the table the focus of
    /// the keyboard, which the list of the sidebar had: ↓ then opens the invoice of the row under the open one and ↑
    /// the one above it, and the table scrolls to show a row that the keys open under the part of it the window shows:
    /// the last row, which the least window with the detail open does not show whole. The rows of 40 points leave room
    /// for the eleven invoices of the fixture there, so two invoices of January are added, numbered to be the last
    /// rows. A click on the open row closes the detail, and so does the × of the detail.
    @Test func aClickOnARowOpensItsInvoiceAndTheArrowKeysOpenTheRowsAroundIt() async throws {
        // The table takes the focus of the keyboard, so the test takes its turn among the tests that type.
        try await whileTypingAlone {
            try await EditorFixture.with { f in
                for number in ["20260002", "20260001"] {
                    var invoice = Invoice.fixture(
                        number: number, duzp: "2026-01-15", dueDate: "2026-01-29", payment: .fixture(on: "2026-01-20"))
                    invoice.clientID = f.cetusID
                    invoice.client = ClientSnapshot(client: EditorFixture.cetus)
                    try await f.database.saveInvoice(invoice)
                }
                await f.app.didWrite()
                try await withAppWindow(of: f.app, size: AppWindowSize.minimum) { window in
                    window.makeKeyAndOrderFront(nil)
                    f.app.screen = .invoices
                    try await withAccessibilityElements {
                        try await waitUntil { invoiceRows(in: window).count == 13 }

                        // A person clicks in the key window, though a test of another suite may have made its own
                        // window the key one meanwhile.
                        window.makeKeyAndOrderFront(nil)
                        press(try #require(invoiceRows(in: window).first))
                        try await waitUntil { openRowNumber(in: window) == "20260902" }
                        #expect(detailCardFrame(in: window) != nil)
                        try await waitUntil { tableHasTheFocus(in: window) }

                        try pressArrow(.down, in: window)
                        try await waitUntil { openRowNumber(in: window) == "20260901" }
                        try pressArrow(.up, in: window)
                        try await waitUntil { openRowNumber(in: window) == "20260902" }

                        // Down to the last row, 20260001, one row a key: it is under the rows that the least window
                        // shows whole.
                        let last = try #require(invoiceRows(in: window).last?.accessibilityFrame?())
                        let shown = try #require(shownRows(in: window))
                        #expect(last.minY < shown.minY - 0.5, "the last row \(last) is shown whole in \(shown)")
                        let below = [
                            "20260901", "20260802", "20260801", "20260701", "20260601", "2026-05-01", "2026-04-01",
                            "2026-03-01", "2026-02-01", "2026-01-01", "20260002", "20260001",
                        ]
                        for number in below {
                            try pressArrow(.down, in: window)
                            try await waitUntil { openRowNumber(in: window) == number }
                        }
                        try await expectSettled(window) { problems(ofTheOpenRowShownIn: window) }

                        press(try #require(openRow(in: window)))
                        try await waitUntil { detailCardFrame(in: window) == nil }
                        #expect(openRow(in: window) == nil)

                        press(try #require(invoiceRows(in: window).last))
                        try await waitUntil { detailCardFrame(in: window) != nil }
                        press(try #require(accessibilityButton(labelled: "Zavřít detail", in: window)))
                        try await waitUntil { detailCardFrame(in: window) == nil }
                        #expect(openRow(in: window) == nil)
                    }
                }
            }
        }
    }

    /// What is wrong with the page of Faktury in `window`, in words: the views that stick out of the window, and where
    /// the card of the table is not where it belongs, which is under the toolbar and down to the bottom margin of the
    /// page (24 points), with the table that scrolls sideways in it. With the detail closed the card reaches the right
    /// margin of the page (16 points); with the detail open the card of the detail is there
    /// (`problems(ofTheDetail:besideTheTable:in:)`) and a row is open. Empty when the page is laid out so. Needs the
    /// accessibility elements (`withAccessibilityElements(_:)`).
    private func problems(of window: NSWindow, detailOpen: Bool) -> [String] {
        var problems = viewsOutside(window).map { "Outside the window: \($0)" }
        guard let table = tableCardFrame(in: window), let scrollView = tableScrollView(in: window) else {
            return problems + ["The page has no table"]
        }
        let room = window.contentLayoutRect
        if table.maxY > room.maxY + 0.5 {
            problems.append("The card of the table reaches under the toolbar: \(table)")
        }
        if (table.minY - 24).magnitude >= 0.5 {
            problems.append("The card of the table does not end at the bottom margin of the page: \(table)")
        }
        let scrolled = frameInWindow(scrollView)
        if !table.insetBy(dx: -0.5, dy: -0.5).contains(scrolled) {
            problems.append("The table that scrolls sideways is not in its card: \(scrolled), \(table)")
        }
        let detail = detailCardFrame(in: window)
        if detailOpen {
            guard let detail else {
                return problems + ["The detail is not open"]
            }
            problems += self.problems(ofTheDetail: detail, besideTheTable: table, in: room, of: window)
            if openRow(in: window) == nil {
                problems.append("No row of the table is open")
            }
        } else {
            if let detail {
                problems.append("The detail is open: \(detail)")
            }
            if (table.maxX - (room.maxX - 16)).magnitude >= 0.5 {
                problems.append("The card of the table does not reach the right margin of the page: \(table)")
            }
        }
        return problems
    }

    /// What is wrong with the card of the detail, `detail`, beside the card of the table, `table`, in the room of the
    /// page `room`, all in the coordinates of `window`: the detail is as wide as a detail panel (340 points,
    /// `DetailPanelMetrics.width`) at the right margin of the page (16 points), starts at the height of the card of the
    /// table (to a point), never reaches below it, and that card ends 16 points before it. The detail is as high as its
    /// content, so where it ends above the bottom of the card of the table it ends 20 points under its last button,
    /// Smazat fakturu…, and has nothing to scroll.
    private func problems(
        ofTheDetail detail: CGRect, besideTheTable table: CGRect, in room: CGRect, of window: NSWindow
    ) -> [String] {
        var problems: [String] = []
        if (detail.width - DetailPanelMetrics.width).magnitude >= 0.5 {
            problems.append("The detail is not \(DetailPanelMetrics.width) points wide: \(detail)")
        }
        if (detail.maxX - (room.maxX - 16)).magnitude >= 0.5 {
            problems.append("The detail does not stand at the right margin of the page: \(detail)")
        }
        // The origin of the window is at the bottom left: the top is the largest y.
        if (detail.maxY - table.maxY).magnitude > 1 {
            problems.append("The detail does not start where the table does: \(detail), \(table)")
        }
        if detail.minY < table.minY - 1 {
            problems.append("The detail reaches below the card of the table: \(detail), \(table)")
        }
        if detail.minY > table.minY + 1 {
            guard let delete = buttonFrame("Smazat fakturu…", in: window) else {
                return problems + ["The detail has no Smazat fakturu…"]
            }
            if (delete.minY - detail.minY - 20).magnitude > 1.5 {
                problems.append("The detail does not end 20 points under its last button: \(detail), \(delete)")
            }
            if detailOverflow(in: window) > 0.5 {
                problems.append("The detail scrolls although it is shorter than the table: \(detail), \(table)")
            }
        }
        if (detail.minX - 16 - table.maxX).magnitude >= 0.5 {
            problems.append("The table does not end 16 points before the detail: \(table), \(detail)")
        }
        return problems
    }

    /// What is wrong with the width of the table of Faktury in `window`: it is wider than its card shows, or a scroller
    /// says that there is more of it to the side, or it is narrower than its card. Empty when the table is as wide as
    /// its card.
    private func problems(ofTheTableFillingItsCardIn window: NSWindow) -> [String] {
        guard let scrollView = tableScrollView(in: window), let table = scrollView.documentView else {
            return ["The page has no table"]
        }
        var problems: [String] = []
        let shown = scrollView.contentView.bounds.width
        if (table.frame.width - shown).magnitude >= 0.5 {
            problems.append("The table is \(table.frame.width) points wide in a card that shows \(shown)")
        }
        if scrollView.horizontalScroller?.isHidden == false {
            problems.append("The card of the table shows a horizontal scroller")
        }
        return problems
    }

    /// What is wrong with where the open row is in `window`: it is not wholly within the part of the rows that the
    /// table shows. Empty when it is. Needs the accessibility elements.
    private func problems(ofTheOpenRowShownIn window: NSWindow) -> [String] {
        guard let row = openRow(in: window)?.accessibilityFrame?(), let shown = shownRows(in: window) else {
            return ["No row is open, or the table shows no rows"]
        }
        if row.minY < shown.minY - 0.5 || row.maxY > shown.maxY + 0.5 {
            return ["The open row \(row) is not within the rows that the table shows, \(shown)"]
        }
        return []
    }

    /// The table of Faktury in `window` as VoiceOver reads it, "Seznam faktur". Nil while the page has no table, and
    /// while the views make no accessibility elements.
    private func invoiceList(in window: NSWindow) -> AnyObject? {
        accessibilityElement(labelled: "Seznam faktur", in: window)
    }

    /// The rows of the table of Faktury in `window`, from the top: the buttons in it that VoiceOver reads with the
    /// number of an invoice and the rest of its row. (The arrows of a scroller are buttons too, with no label.) Empty
    /// while the views make no accessibility elements.
    private func invoiceRows(in window: NSWindow) -> [AnyObject] {
        guard let list = invoiceList(in: window) else { return [] }
        return descendants(of: list).filter { element in
            element.accessibilityRole?() == .button && !(element.accessibilityLabel?() ?? "").isEmpty
        }
    }

    /// The row of the open invoice in the table of Faktury in `window`: the one VoiceOver reads as selected.
    private func openRow(in window: NSWindow) -> AnyObject? {
        invoiceRows(in: window).first { $0.isAccessibilitySelected?() == true }
    }

    /// The number of the open invoice in the table of Faktury in `window`: what VoiceOver reads for its row up to the
    /// first comma. Nil when no row is open.
    private func openRowNumber(in window: NSWindow) -> String? {
        guard let label = openRow(in: window)?.accessibilityLabel?() else { return nil }
        return String(label.prefix { $0 != "," })
    }

    /// The part of the rows of the table of Faktury that the table shows in `window`, in the coordinates of the screen:
    /// the frame of the scroll area of the rows, under the names of the columns, which is the last of the two scroll
    /// areas in the card (the first scrolls the names and the rows sideways).
    private func shownRows(in window: NSWindow) -> CGRect? {
        guard let list = invoiceList(in: window) else { return nil }
        let rows = descendants(of: list).last { $0.accessibilityRole?() == .scrollArea }
        return rows?.accessibilityFrame?()
    }

    /// The frame of the card of the table of Faktury in `window`, which VoiceOver reads as "Seznam faktur", in the
    /// coordinates of the window: the summary row and the table under it. Nil while the page has no table, and while
    /// the views make no accessibility elements.
    private func tableCardFrame(in window: NSWindow) -> CGRect? {
        guard let frame = invoiceList(in: window)?.accessibilityFrame?() else { return nil }
        return window.convertFromScreen(frame)
    }

    /// The elements under `element`, in the order of the tree.
    private func descendants(of element: AnyObject) -> [AnyObject] {
        let children = (element.accessibilityChildren?() ?? []).map { $0 as AnyObject }
        return children.flatMap { [$0] + descendants(of: $0) }
    }

    /// The frame of the card of the detail of Faktury in `window`, which VoiceOver reads as "Detail faktury", in the
    /// coordinates of the window. Nil while the detail is closed, and while the views make no accessibility elements.
    private func detailCardFrame(in window: NSWindow) -> CGRect? {
        guard let frame = accessibilityElement(labelled: "Detail faktury", in: window)?.accessibilityFrame?() else {
            return nil
        }
        return window.convertFromScreen(frame)
    }

    /// The scroll view that the table of Faktury scrolls sideways in, in `window`: the one scroll view of the page with
    /// a horizontal scroller. Its frame is the card of the table, and what it scrolls is the table.
    private func tableScrollView(in window: NSWindow) -> NSScrollView? {
        guard let content = window.contentView else { return nil }
        return scrollViews(in: content).first { $0.hasHorizontalScroller }
    }

    /// How wide the table of Faktury is in `window`: what its card scrolls.
    private func tableWidth(in window: NSWindow) throws -> CGFloat {
        try #require(tableScrollView(in: window)?.documentView).frame.width
    }

    /// The behaviours of the items of the split views of `window`, from the leading side: the sidebar and the page, and
    /// an inspector where a page has one beside it.
    private func splitViewItemBehaviors(in window: NSWindow) -> [NSSplitViewItem.Behavior] {
        guard let frameView = window.contentView?.superview else { return [] }
        return splitViews(in: frameView)
            .compactMap { $0.delegate as? NSSplitViewController }
            .flatMap { $0.splitViewItems.map(\.behavior) }
    }

    private func splitViews(in view: NSView) -> [NSSplitView] {
        if let splitView = view as? NSSplitView {
            return [splitView] + view.subviews.flatMap { splitViews(in: $0) }
        }
        return view.subviews.flatMap { splitViews(in: $0) }
    }

    /// Presses `element` as VoiceOver presses a button, which is what a click on it does.
    private func press(_ element: AnyObject) {
        #expect(element.accessibilityPerformPress?() == true)
    }

    /// Whether the table of Faktury has the focus of the keyboard in `window`: SwiftUI gives a view of its own the
    /// focus by making the view that hosts the window's content the first responder, where the list of the sidebar or a
    /// text field is the first responder otherwise.
    private func tableHasTheFocus(in window: NSWindow) -> Bool {
        window.firstResponder === window.contentView
    }

    /// The arrow keys that move in the table.
    private enum Arrow {
        case up
        case down
    }

    /// Presses ↑ or ↓ as the keyboard does: a key-down event of the arrow key, handed to `window` as the application
    /// hands it the keys (`pressEscape(in:)`).
    private func pressArrow(_ arrow: Arrow, in window: NSWindow) throws {
        let key = arrow == .down ? NSDownArrowFunctionKey : NSUpArrowFunctionKey
        let characters = String(Character(try #require(UnicodeScalar(UInt32(key)))))
        try sendKeyDown(
            characters: characters, keyCode: arrow == .down ? 125 : 126, modifierFlags: [.numericPad, .function],
            to: window)
    }

    /// The card of the table starts with its summary row, the count and the totals, across the top of the card; under
    /// it are the names of the columns, 32 points high, and then the rows, 40 points high each. In the least window
    /// with the detail open the table scrolls sideways in the card, but the summary row does not: it stays as wide as
    /// the card and wraps in it.
    @Test func theSummaryRowStandsAboveTheNamesOfTheColumnsInTheCardOfTheTable() async throws {
        try await EditorFixture.with { f in
            try await withAppWindow(of: f.app, size: AppWindowSize.large) { window in
                f.app.screen = .invoices
                try await withAccessibilityElements {
                    try await waitUntil { invoiceRows(in: window).count == 11 }
                    try await expectSettled(window) {
                        problems(of: window, detailOpen: false) + problems(ofTheSummaryAndTheRowsIn: window)
                    }

                    // As Přehled opens an invoice: its detail stands beside the card of the table.
                    f.app.openInvoice(Self.alfaInvoiceID)
                    try await waitUntil { detailCardFrame(in: window) != nil }
                    window.setContentSize(AppWindowSize.minimum)
                    try await expectSettled(window) {
                        problems(of: window, detailOpen: true) + problems(ofTheSummaryAndTheRowsIn: window)
                    }
                    #expect(try tableWidth(in: window) > tableScrollView(in: window)?.contentView.bounds.width ?? 0)
                }
            }
        }
    }

    /// What is wrong with the summary row and the rows of the table of Faktury in `window`, in words
    /// (`problems(ofTheSummaryAndTheRowsOf:rows:)`). Needs the accessibility elements
    /// (`withAccessibilityElements(_:)`).
    private func problems(ofTheSummaryAndTheRowsIn window: NSWindow) -> [String] {
        problems(ofTheSummaryAndTheRowsOf: invoiceList(in: window), rows: invoiceRows(in: window))
    }

    /// What is wrong with the summary row and the rows of a table whose card VoiceOver reads as `list`, with the rows
    /// `rows` from the top, in words: the summary row in the card, which VoiceOver reads as "Souhrn", is not across the
    /// top of the card, as wide as the card and with no more than its own margin above it, the first row does not start
    /// 32 points under it (the names of the columns are between them), or one of the first five rows is not 40 points
    /// high and right under the row before it. Empty when they are laid out so. Faktury and Odběratelé have such a
    /// table.
    private func problems(ofTheSummaryAndTheRowsOf list: AnyObject?, rows: [AnyObject]) -> [String] {
        guard let list, let card = list.accessibilityFrame?(),
            let summary = descendants(of: list).first(where: { ($0.accessibilityLabel?() ?? "") == "Souhrn" })?
                .accessibilityFrame?()
        else {
            return ["The page has no card of the table with a summary row"]
        }
        var problems: [String] = []
        // The origin of the screen is at the bottom left: the top is the largest y. VoiceOver's frame of the row starts
        // under its margin at the top, 14 points; nothing else of the card stands above it.
        let above = card.maxY - summary.maxY
        if above < -0.5 || above > 14.5 || (summary.minX - card.minX).magnitude > 0.5
            || (summary.width - card.width).magnitude > 0.5
        {
            problems.append("The summary row is not across the top of the card: \(summary) in \(card)")
        }
        let rows = rows.prefix(5).compactMap { $0.accessibilityFrame?() }
        guard let first = rows.first else {
            return problems + ["The table has no rows"]
        }
        if (summary.minY - first.maxY - DataTableMetrics.headerHeight).magnitude > 0.5 {
            problems.append("The first row does not start 32 points under the summary row: \(first), \(summary)")
        }
        for row in rows where (row.height - DataTableMetrics.rowHeight).magnitude > 0.5 {
            problems.append("A row is not 40 points high: \(row)")
        }
        for (row, next) in zip(rows, rows.dropFirst()) where (row.minY - next.maxY).magnitude > 0.5 {
            problems.append("A row does not start where the row above it ends: \(next) under \(row)")
        }
        return problems
    }

    // MARK: The search of Faktury

    /// What VoiceOver reads for the search field of Faktury and for the × in it.
    private static let searchLabel = "Hledat ve fakturách"
    private static let crossLabel = "Zrušit hledání"

    /// The identifier of the group that holds the search field and its ×, which is the capsule of the search. The group
    /// has no label, as the field has its own.
    private static let searchGroup = InvoiceSearchField.accessibilityID

    /// The search of Faktury is a field on the page, not in the toolbar: it stands at the end of the filter row, after
    /// the segment of the scope and the chips, 170 to 280 points wide and ending at the right margin of the page. Where
    /// the row has no room for all three, it wraps, the field still at the right margin: at the least room the segment
    /// and the chips stand in one line and the field has the line under it, at its greatest width, with the detail open
    /// too, as the detail stands beside the table and leaves the filter row the width of the page.
    @Test func theFakturySearchSitsAtTheEndOfTheFilterRow() async throws {
        try await EditorFixture.with { f in
            try await withAppWindow(of: f.app, size: AppWindowSize.large) { window in
                f.app.screen = .invoices
                try await withAccessibilityElements {
                    try await waitUntil { invoiceRows(in: window).count == 11 }
                    // A large window: the scope, the chips and the field are one line, in this order.
                    try await expectSettled(window) {
                        problems(of: window, detailOpen: false)
                            + problems(ofTheFilterRowIn: window, arrangedAs: .oneLine)
                    }
                    // The toolbar is the one of every other screen: Faktury puts nothing in it.
                    #expect(searchFields(inTheToolbarOf: window) == [])
                    // The segment of the scope is the design's own control, found by its name: no system one.
                    #expect(segmentedControls(in: try #require(window.contentView)).isEmpty)
                    // The field is read as "Hledat ve fakturách", and it shows the same words while it is empty.
                    #expect(searchChild(role: .textField, labelled: Self.searchLabel, in: window) != nil)
                    #expect(searchTextField(in: window)?.placeholderString == Self.searchLabel)

                    // As Přehled opens an invoice, in the least window.
                    f.app.openInvoice(Self.alfaInvoiceID)
                    try await waitUntil { detailCardFrame(in: window) != nil }
                    window.setContentSize(AppWindowSize.minimum)
                    try await expectSettled(window) {
                        problems(of: window, detailOpen: true)
                            + problems(ofTheFilterRowIn: window, arrangedAs: .searchOnItsOwnLine)
                    }
                    #expect(searchFields(inTheToolbarOf: window) == [])
                }
            }
        }
    }

    /// Hledat (⌘F) puts the focus in the search field of the page: `AppModel.focusSearch()` is what the menu item
    /// calls, and the field is the first responder of the window after it, though the focus was elsewhere before.
    @Test func commandFFocusesTheSearchField() async throws {
        // The field takes the focus, so the test takes its turn among the tests that type.
        try await whileTypingAlone {
            try await EditorFixture.with { f in
                try await withAppWindow(of: f.app, size: AppWindowSize.minimum) { window in
                    window.makeKeyAndOrderFront(nil)
                    f.app.screen = .invoices
                    try await withAccessibilityElements {
                        try await waitUntil { invoiceRows(in: window).count == 11 }
                        try await waitUntil { searchTextField(in: window) != nil }
                        let field = try #require(searchTextField(in: window))
                        #expect(!hasFocus(field, in: window))

                        f.app.focusSearch()

                        try await waitUntil { hasFocus(field, in: window) }
                        #expect(hasFocus(field, in: window))
                    }
                }
            }
        }
    }

    /// Esc in the search field clears the search: Hledat puts the focus in the field, "acme" is typed as a person types
    /// it, and Esc, sent to the window as the keyboard sends it once the × shows that the field has taken the text in,
    /// leaves the app with no search text, and the focus in the empty field.
    @Test func escapeClearsTheSearch() async throws {
        // The field takes the focus, so the test takes its turn among the tests that type.
        try await whileTypingAlone {
            try await EditorFixture.with { f in
                try await withAppWindow(of: f.app, size: AppWindowSize.minimum) { window in
                    window.makeKeyAndOrderFront(nil)
                    f.app.screen = .invoices
                    try await withAccessibilityElements {
                        try await waitUntil { invoiceRows(in: window).count == 11 }
                        try await waitUntil { searchTextField(in: window) != nil }
                        let field = try #require(searchTextField(in: window))
                        f.app.focusSearch()
                        try await waitUntil { hasFocus(field, in: window) }

                        try type("acme", into: field, in: window)
                        #expect(f.app.searchText == "acme")
                        // A key that comes in the same turn of the run loop as the text, which a person's cannot, is
                        // not given to the field: SwiftUI has not taken the text in yet. It has when the × shows.
                        try await waitUntil { searchChild(role: .button, labelled: Self.crossLabel, in: window) != nil }
                        try pressEscape(in: window)

                        try await waitUntil { f.app.searchText == "" && field.stringValue == "" }
                        #expect(f.app.searchText == "")
                        #expect(field.stringValue == "")
                        #expect(hasFocus(field, in: window))
                    }
                }
            }
        }
    }

    /// The × is in the search field only while there is text in it. Pressed, as VoiceOver presses a button that it
    /// reads as "Zrušit hledání", it clears the search and leaves the focus in the field, to type another search in.
    @Test func theCrossInTheSearchClearsItAndIsThereOnlyWhileThereIsText() async throws {
        // The field takes the focus, so the test takes its turn among the tests that type.
        try await whileTypingAlone {
            try await EditorFixture.with { f in
                try await withAppWindow(of: f.app, size: AppWindowSize.minimum) { window in
                    window.makeKeyAndOrderFront(nil)
                    f.app.screen = .invoices
                    try await withAccessibilityElements {
                        try await waitUntil { invoiceRows(in: window).count == 11 }
                        try await waitUntil { searchTextField(in: window) != nil }
                        let field = try #require(searchTextField(in: window))
                        // The line under the filters that says what the search found has a button of the same name.
                        let cross = { searchChild(role: .button, labelled: Self.crossLabel, in: window) }
                        #expect(cross() == nil)

                        try type("acme", into: field, in: window)
                        try await waitUntil { cross() != nil }
                        #expect(try #require(cross()).accessibilityPerformPress?() == true)

                        try await waitUntil { f.app.searchText == "" && field.stringValue == "" && cross() == nil }
                        #expect(f.app.searchText == "")
                        #expect(field.stringValue == "")
                        #expect(cross() == nil)
                        #expect(hasFocus(field, in: window))
                    }
                }
            }
        }
    }

    /// The search field that has the focus is the same field, with the focus, when the filter row wraps: a window made
    /// narrower puts it on a line of its own, and wider again takes it back. (A field made anew by each way the row
    /// can wrap would lose the focus in the middle of a word when the window is resized, or when the chips narrow as
    /// the search narrows the list.)
    @Test func theSearchKeepsItsFocusWhenTheFilterRowWraps() async throws {
        // The field takes the focus, so the test takes its turn among the tests that type.
        try await whileTypingAlone {
            try await EditorFixture.with { f in
                try await withAppWindow(of: f.app, size: AppWindowSize.large) { window in
                    window.makeKeyAndOrderFront(nil)
                    f.app.screen = .invoices
                    try await withAccessibilityElements {
                        try await waitUntil { invoiceRows(in: window).count == 11 }
                        try await waitUntil { searchTextField(in: window) != nil }
                        let field = try #require(searchTextField(in: window))
                        f.app.focusSearch()
                        try await waitUntil { hasFocus(field, in: window) }
                        // The line of the field under the line of the segment: 0 in one line, below it in two.
                        let drop = { () -> CGFloat? in
                            guard let row = filterRowFrames(in: window) else { return nil }
                            return row.scope.midY - row.search.midY
                        }
                        #expect(try #require(drop()).magnitude < 1)

                        window.setContentSize(AppWindowSize.minimum)
                        try await expectSettled(window) { problems(of: window, detailOpen: false) }
                        try await waitUntil { (drop() ?? 0) > 10 }
                        #expect(searchTextField(in: window) === field)
                        #expect(hasFocus(field, in: window))

                        window.setContentSize(AppWindowSize.large)
                        try await expectSettled(window) { problems(of: window, detailOpen: false) }
                        try await waitUntil { (drop() ?? 10).magnitude < 1 }
                        #expect(searchTextField(in: window) === field)
                        #expect(hasFocus(field, in: window))
                    }
                }
            }
        }
    }

    /// Where the parts of the filter row of Faktury are, in the coordinates of the screen, whose origin is at the
    /// bottom left.
    private struct FilterRowFrames {
        /// The segment of the scope, "Které faktury".
        var scope: CGRect
        var firstChip: CGRect
        var lastChip: CGRect

        /// The capsule of the search, and the text field in it.
        var search: CGRect
        var field: CGRect

        /// Where the page ends on the right: its right margin, 16 points before the edge of the window.
        var pageEnd: CGFloat
    }

    /// How the filter row of Faktury wraps: in one line, or with the search on a line of its own under the segment and
    /// the chips.
    private enum FilterRowArrangement {
        case oneLine
        case searchOnItsOwnLine
    }

    /// The filter row of Faktury in `window` as the fixture shows it: the segment of the scope, which VoiceOver reads
    /// as "Které faktury", the chips "Vše 11" to "Uhrazené 11", and the search. Nil while a part of it is missing, and
    /// while the views make no accessibility elements (`withAccessibilityElements(_:)`).
    private func filterRowFrames(in window: NSWindow) -> FilterRowFrames? {
        guard let scope = accessibilityElement(labelled: "Které faktury", in: window)?.accessibilityFrame?(),
            let firstChip = accessibilityButton(labelled: "Vše 11", in: window)?.accessibilityFrame?(),
            let lastChip = accessibilityButton(labelled: "Uhrazené 11", in: window)?.accessibilityFrame?(),
            let search = accessibilityElement(identifiedBy: Self.searchGroup, in: window)?.accessibilityFrame?(),
            let field = searchTextField(in: window)
        else {
            return nil
        }
        return FilterRowFrames(
            scope: scope, firstChip: firstChip, lastChip: lastChip, search: search,
            field: window.convertToScreen(frameInWindow(field)),
            pageEnd: window.convertToScreen(window.contentLayoutRect).maxX - 16)
    }

    /// What is wrong with the filter row of Faktury in `window`, in words: the chips are not after the segment on its
    /// line, the search is not 170 to 280 points wide, it has not the field in it, it does not end at the right margin
    /// of the page, or it is not where `arrangement` puts it. That is after the chips and on their line, or on a line
    /// of its own under them at its greatest width. Empty when the row is laid out so.
    private func problems(
        ofTheFilterRowIn window: NSWindow, arrangedAs arrangement: FilterRowArrangement
    ) -> [String] {
        guard let row = filterRowFrames(in: window) else {
            return ["The filter row lacks the segment, the chip \"Vše 11\" or \"Uhrazené 11\", or the search"]
        }
        var problems: [String] = []
        if row.firstChip.minX < row.scope.maxX || (row.firstChip.midY - row.scope.midY).magnitude > 1 {
            problems.append("The chips are not after the segment on its line: \(row.firstChip), \(row.scope)")
        }
        if row.search.width < 169.5 || row.search.width > 280.5 {
            problems.append("The search is not 170 to 280 points wide: \(row.search)")
        }
        if !row.search.insetBy(dx: -0.5, dy: -0.5).contains(row.field) {
            problems.append("The field is not inside the search: \(row.field) in \(row.search)")
        }
        if (row.search.maxX - row.pageEnd).magnitude > 1 {
            problems.append("The search does not end at the right margin of the page (\(row.pageEnd)): \(row.search)")
        }
        switch arrangement {
        case .oneLine:
            if row.search.minX < row.lastChip.maxX {
                problems.append("The search is not after the chips: \(row.search), \(row.lastChip)")
            }
            if (row.search.midY - row.scope.midY).magnitude > 1 {
                problems.append("The search is not on the line of the segment: \(row.search), \(row.scope)")
            }
        case .searchOnItsOwnLine:
            // The origin of the screen is at the bottom left: under means a smaller y.
            if row.search.maxY > min(row.scope.minY, row.lastChip.minY) + 0.5 {
                problems.append("The search is not under the segment and the chips: \(row.search), \(row.lastChip)")
            }
            if (row.search.width - 280).magnitude > 0.5 {
                problems.append("The search on its own line is not at its greatest width: \(row.search)")
            }
        }
        return problems
    }

    /// Whether `field` has the keyboard focus in `window`: its field editor is the first responder.
    private func hasFocus(_ field: NSTextField, in window: NSWindow) -> Bool {
        field.currentEditor() != nil && window.firstResponder === field.currentEditor()
    }

    /// The text field of the search of Faktury in `window`: the one whose placeholder is "Hledat ve fakturách". (Its
    /// accessibility element is no guide to it: the element spans the capsule, and the field is a plain one, a little
    /// smaller than its element.)
    private func searchTextField(in window: NSWindow) -> NSTextField? {
        guard let content = window.contentView else { return nil }
        return editableTextFields(in: content).first { $0.placeholderString == Self.searchLabel }
    }

    /// The element with `role` and `label` that VoiceOver reads in the search of Faktury in `window`: inside its group,
    /// so that the × is not taken for the button of the same name in the line that says what the search found. Nil
    /// when the search has none, and while the views make no accessibility elements (`withAccessibilityElements(_:)`).
    private func searchChild(role: NSAccessibility.Role, labelled label: String, in window: NSWindow) -> AnyObject? {
        let group = accessibilityElement(identifiedBy: Self.searchGroup, in: window)
        let children: [Any] = group?.accessibilityChildren?() ?? []
        return children.map { $0 as AnyObject }.first { child in
            child.accessibilityRole?() == role && child.accessibilityLabel?() == label
        }
    }

    /// The search fields in the toolbar of `window`, each as the name of its type: the toolbar items that are search
    /// fields, and the search fields among the views around the content of the window, which are those of its title bar
    /// and toolbar. Empty when the toolbar has none.
    private func searchFields(inTheToolbarOf window: NSWindow) -> [String] {
        var found = (window.toolbar?.items ?? []).filter { $0 is NSSearchToolbarItem }.map { "\(Swift.type(of: $0))" }
        for view in window.contentView?.superview?.subviews ?? [] where view !== window.contentView {
            found += searchFields(in: view).map { "\(Swift.type(of: $0))" }
        }
        return found
    }

    private func searchFields(in view: NSView) -> [NSSearchField] {
        if let field = view as? NSSearchField {
            return [field]
        }
        return view.subviews.flatMap { searchFields(in: $0) }
    }

    /// Presses Esc as the keyboard does: a key-down event of the Escape key, handed to `window` as the application
    /// hands it the keys. (The application gives keys to its key window, and a window of a test run is not that: the
    /// run is not the active application.)
    private func pressEscape(in window: NSWindow) throws {
        try sendKeyDown(characters: "\u{1B}", keyCode: 53, modifierFlags: [], to: window)
    }

    /// Hands `window` a key-down event of the key with `keyCode`, which types `characters`.
    private func sendKeyDown(
        characters: String, keyCode: UInt16, modifierFlags: NSEvent.ModifierFlags, to window: NSWindow
    ) throws {
        let event = try #require(
            NSEvent.keyEvent(
                with: .keyDown, location: .zero, modifierFlags: modifierFlags,
                timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber, context: nil,
                characters: characters, charactersIgnoringModifiers: characters, isARepeat: false, keyCode: keyCode))
        window.sendEvent(event)
    }

    // MARK: Přehled and the editor

    @Test func prehledFitsTheWindowAtTheLeastRoomAndAtALargeSize() async throws {
        try await EditorFixture.with { f in
            try await withAppWindow(of: f.app, size: AppWindowSize.minimum) { window in
                f.app.screen = .overview
                try await waitUntil { window.title == "Přehled" }
                // The page scrolls; with the data it is far taller than while it loads.
                try await waitUntil { (scrolledPage(in: window)?.frame.height ?? 0) > 600 }

                try await expectSettled(window) { viewsOutside(window) }
                window.setContentSize(AppWindowSize.large)
                try await expectSettled(window) { viewsOutside(window) }
                window.setContentSize(AppWindowSize.minimum)
                try await expectSettled(window) { viewsOutside(window) }
            }
        }
    }

    /// The editor fits the window at the least room, at a large size and at the least room again. At the least room
    /// the preview stands under the form, as wide as the form is; in a large window it is the aside of 461 points
    /// beside the form (`PreviewPane.width`), with the gap of 16 between them.
    @Test func theEditorFitsTheWindowAtTheLeastRoomAndAtALargeSize() async throws {
        try await EditorFixture.with { f in
            try await withAppWindow(of: f.app, size: AppWindowSize.minimum) { window in
                f.app.startNewInvoice(templateID: f.dollarTemplate.id)
                try await waitUntil { window.subtitle == "Ze šablony Software development" }
                try await waitUntil { (scrolledPage(in: window)?.frame.height ?? 0) > 600 }

                try await withAccessibilityElements {
                    let sizes = [
                        (AppWindowSize.minimum, false), (AppWindowSize.large, true), (AppWindowSize.minimum, false),
                    ]
                    for (size, beside) in sizes {
                        window.setContentSize(size)
                        try await expectSettled(window) { viewsOutside(window) }
                        try await waitUntil { frameOfCard(labelled: "Náhled PDF", in: window) != nil }
                        let aside = try #require(frameOfCard(labelled: "Náhled PDF", in: window))
                        let form = try #require(frameOfCard(labelled: "Odběratel a doklad", in: window))

                        if beside {
                            #expect(abs(aside.width - PreviewPane.width) < 0.5, "The aside is \(aside) at \(size)")
                            let gap = aside.minX - form.maxX
                            #expect((gap - DesignMetrics.cardSpacing).magnitude < 1, "The gap is \(gap) at \(size)")
                        } else {
                            #expect((aside.minX - form.minX).magnitude < 1, "The aside is \(aside), the form \(form)")
                            #expect((aside.width - form.width).magnitude < 1, "The aside is \(aside), the form \(form)")
                        }
                    }
                }
                #expect(window.title == "Nová faktura")
            }
        }
    }

    // MARK: The result card of Přehled

    /// Přehled on the sample year as of 17. 10. 2026: the card "Kolik zbývá zaplatit" holds the picture of the bar of
    /// the levies, and the card "Příjmy" stands under it, 16 points lower and as wide, whether the pointer is away from
    /// the bar, over its part of the tax or over the item of the tax in its legend: the popover that shows then takes
    /// no room, and the card does not move. Nothing of the page is beyond the window at the least room, at a large size
    /// and at the least room again. The test proves each state before it checks the cards in it: while the pointer is
    /// over the bar the other parts fade (the colour of the part of the social insurance changes), and when it is
    /// taken away the bar is whole again. A pointer that moved nothing fails the test, which would otherwise pass with
    /// the popover closed.
    @Test func theResultCardOfPrehledHoldsTheLevyBarAndPrijmyStaysUnderItWithOrWithoutTheHover() async throws {
        try await EditorFixture.with { f in
            let result = try await f.app.computeSelectedYear()
            let levyBar = LevyBarBuilder.balances(
                of: result, kind: .toDate(isOver: false), header: "Odvody z příjmů do 17.\u{00A0}10.", showsTotal: true)
            let weights = levyBar.parts.map(\.weight)
            try await withAppWindow(of: f.app, size: AppWindowSize.minimum, ignoringTheRealPointer: true) { window in
                f.app.screen = .overview
                try await waitUntil { window.title == "Přehled" }
                try await waitUntil { (scrolledPage(in: window)?.frame.height ?? 0) > 600 }

                try await withAccessibilityElements {
                    for size in [AppWindowSize.minimum, AppWindowSize.large, AppWindowSize.minimum] {
                        window.setContentSize(size)
                        try await expectSettled(window) {
                            problems(ofTheResultCardOfPrehledIn: window, levyBar: levyBar) + problems(ofPageIn: window)
                        }
                        let frames = [
                            try #require(frameOfCard(labelled: "Kolik zbývá zaplatit", in: window)),
                            try #require(frameOfCard(labelled: "Příjmy", in: window)),
                        ]
                        let bar = window.convertFromScreen(
                            try #require(
                                accessibilityElement(labelStartingWith: "Odvody z příjmů do", in: window)?
                                    .accessibilityFrame?()))

                        /// The colour of the part of the social insurance, which fades while a popover is open.
                        @MainActor func socialPart() throws -> [Int] {
                            try colourOfTheSocialPartOfTheLevyBar(weights: weights, bar: bar, in: window)
                        }
                        let resting = try socialPart()

                        // The pointer over the part of the tax in the bar, and then over its item of the legend,
                        // as a mouse moves it; the corner of the window takes it away again. The popover is open
                        // before the cards are looked at, and closed again before the next state.
                        for (name, point) in try pointsOpeningThePopoverOfTheTax(in: window) {
                            try movePointer(to: point, in: window)
                            try await waitUntil { ((try? socialPart()) ?? resting) != resting }
                            try await expectSettled(window) {
                                problems(ofTheResultCardOfPrehledIn: window, levyBar: levyBar)
                                    + problems(ofPageIn: window)
                            }
                            let now = [
                                try #require(frameOfCard(labelled: "Kolik zbývá zaplatit", in: window)),
                                try #require(frameOfCard(labelled: "Příjmy", in: window)),
                            ]
                            let moved = zip(frames, now).contains { before, after in
                                (before.minX - after.minX).magnitude > 0.5 || (before.minY - after.minY).magnitude > 0.5
                                    || (before.width - after.width).magnitude > 0.5
                                    || (before.height - after.height).magnitude > 0.5
                            }
                            #expect(!moved, "The cards moved with the pointer over the \(name): \(frames), \(now)")
                            try movePointer(to: TestWindow.restingPointer, in: window)
                            try await waitUntil { ((try? socialPart()) ?? []) == resting }
                        }
                    }
                }
            }
        }
    }

    /// The popover of the levy bar of Přehled hangs out of the result card, over the hairline and the tiles under the
    /// bar, over the edge of the card and the card "Příjmy" under it, and is drawn above all of them: the card is drawn
    /// above what follows it, and nothing clips the popover. With the sidebar as wide as it goes the card stacks its
    /// parts and the legend stands over the tiles, so that the popover reaches past the card; the pointer is moved
    /// over the part of the tax, and then over its item of the legend, as a mouse moves it. A strip down the popover,
    /// 6 points inside its leading edge, from 4 points under its top to 2 points under the top edge of "Příjmy", shows
    /// nothing but the colour of the popover while it is open, where the tiles, the hairline and the edges of the two
    /// cards cross it while it is closed.
    @Test func thePopoverOfPrehledIsDrawnOverTheTilesAndTheEdgesOfTheCardsUnderTheBar() async throws {
        try await EditorFixture.with { f in
            let result = try await f.app.computeSelectedYear()
            let weights = Authority.allCases.map { result.balance($0).liability }
            let levyBar = LevyBarBuilder.balances(
                of: result, kind: .toDate(isOver: false), header: "Odvody z příjmů do 17.\u{00A0}10.", showsTotal: true)
            try await withAppWindow(of: f.app, size: AppWindowSize.minimum, ignoringTheRealPointer: true) { window in
                f.app.screen = .overview
                try await waitUntil { window.title == "Přehled" }
                try await waitUntil { (scrolledPage(in: window)?.frame.height ?? 0) > 600 }

                try await withAccessibilityElements {
                    widenSidebar(of: window)
                    try await expectSettled(window) {
                        problems(ofTheResultCardOfPrehledIn: window, levyBar: levyBar)
                    }
                    let card = try #require(frameOfCard(labelled: "Kolik zbývá zaplatit", in: window))
                    #expect(
                        !ResultCardLayout.standsSideBySide(innerWidth: card.width - 2 * DesignMetrics.cardPadding),
                        "The parts stand side by side in a card \(card.width) points wide")

                    let content = try #require(window.contentView)
                    let bar = window.convertFromScreen(
                        try #require(
                            accessibilityElement(labelStartingWith: "Odvody z příjmů do", in: window)?
                                .accessibilityFrame?()))
                    let legend = window.convertFromScreen(
                        try #require(
                            accessibilityElement(labelStartingWith: "Daň z příjmů: odvody z příjmů", in: window)?
                                .accessibilityFrame?()))
                    let income = window.convertFromScreen(try #require(frameOfCard(labelled: "Příjmy", in: window)))
                    // The popover of the tax: 8 points under the legend, centred on its part and held in the panel.
                    let widths = LevyBarLayout.partWidths(weights: weights, width: bar.width)
                    let centre = LevyBarLayout.partCentres(widths: widths)[0]
                    let left = bar.minX + LevyBarLayout.popoverX(centredOn: centre, panelWidth: bar.width)
                    let top = content.bounds.height - legend.minY + LevyBarLayout.popoverGap
                    let incomeTop = content.bounds.height - income.maxY

                    /// The points of the strip down the popover, from 4 points under its top to 2 points under the
                    /// top edge of "Příjmy", whose colour is not that of the top of the strip: what is drawn over the
                    /// popover.
                    @MainActor func strayPoints() throws -> [CGPoint] {
                        let picture = try WindowPicture(of: window)
                        let strip = stride(from: top + 4, through: incomeTop + 2, by: 0.5).map {
                            CGPoint(x: left + 6, y: $0)
                        }
                        let colour = picture.bytes(at: strip[0])
                        return strip.filter { point in
                            zip(picture.bytes(at: point), colour).contains { abs($0 - $1) > 6 }
                        }
                    }

                    // With no popover the tiles, the hairline and the edges of the cards cross the strip: the test
                    // can tell the two states apart.
                    let corner = CGPoint(x: 4, y: 4)
                    try await expectSettled(window) {
                        ((try? strayPoints()) ?? []).isEmpty ? ["Nothing crosses the strip"] : []
                    }

                    let overPart = CGPoint(x: bar.minX + 10, y: bar.midY)
                    let overLegend = CGPoint(x: legend.minX + 10, y: legend.midY)
                    for (name, pointer) in [("part", overPart), ("item of the legend", overLegend)] {
                        try movePointer(to: pointer, in: window)
                        try await waitUntil { ((try? strayPoints()) ?? [CGPoint.zero]).isEmpty }
                        #expect(try strayPoints() == [], "Drawn over the popover of the \(name)")

                        try movePointer(to: corner, in: window)
                        try await waitUntil { !((try? strayPoints()) ?? []).isEmpty }
                    }
                }
            }
        }
    }

    /// The parts of the result card of Přehled stand where the shared result card sets them: the key figure at the top
    /// left, the two buttons of 28 points under it, 12 points lower and 8 apart, the section of the levy bar beside it
    /// in a column of its own, level at the top and 28 points to the right, or under the buttons in the whole width,
    /// 20 points lower, where the card is too narrow for two columns, and under both, under the hairline, the three
    /// tiles in one row, 48 points apart and never stretched. At a large size, at the least room (where the page has
    /// the room the card says) and with the sidebar as wide as it goes.
    @Test func thePartsOfTheResultCardOfPrehledStandWhereTheSharedCardSetsThem() async throws {
        try await EditorFixture.with { f in
            let result = try await f.app.computeSelectedYear()
            let tiles = [
                "Odejde zálohami, " + CzechFormat.wholeKc(result.leavesViaPlannedAdvances),
                "Doplatek, " + CzechFormat.wholeKc(result.settlementTotal),
                "Mezní odvod, " + CzechFormat.percent(result.marginalTotal),
            ]
            try await withAppWindow(of: f.app, size: AppWindowSize.minimum) { window in
                f.app.screen = .overview
                try await waitUntil { window.title == "Přehled" }
                try await waitUntil { (scrolledPage(in: window)?.frame.height ?? 0) > 600 }

                try await withAccessibilityElements {
                    window.setContentSize(AppWindowSize.large)
                    try await expectSettled(window) {
                        problems(ofThePartsOfTheResultCardOfPrehledIn: window, tiles: tiles, beside: true)
                    }
                    // Whatever the room, the parts stand as the width of the card says: side by side from 788 points
                    // inside its padding.
                    window.setContentSize(AppWindowSize.minimum)
                    try await expectSettled(window) {
                        problems(ofThePartsOfTheResultCardOfPrehledIn: window, tiles: tiles, beside: nil)
                    }
                    widenSidebar(of: window)
                    try await expectSettled(window) {
                        problems(ofThePartsOfTheResultCardOfPrehledIn: window, tiles: tiles, beside: false)
                    }
                }
            }
        }
    }

    /// "Jak se to počítá" opens Výpočet and "Upravit plán záloh" opens Zálohy a odpočty, each as the button of a page
    /// is pressed for VoiceOver, which reads the arrow of the first one as no part of its name.
    @Test func theButtonsOfTheResultCardOfPrehledOpenTheComputationAndThePlanOfAdvances() async throws {
        try await EditorFixture.with { f in
            try await withAppWindow(of: f.app, size: AppWindowSize.minimum) { window in
                try await withAccessibilityElements {
                    for (label, title, screen) in [
                        ("Jak se to počítá", "Výpočet", Screen.computation),
                        ("Upravit plán záloh", "Zálohy a odpočty", Screen.advances),
                    ] {
                        f.app.screen = .overview
                        try await waitUntil { window.title == "Přehled" }
                        try await waitUntil { accessibilityButton(labelled: label, in: window) != nil }

                        _ = try #require(accessibilityButton(labelled: label, in: window)).accessibilityPerformPress?()

                        try await waitUntil { window.title == title }
                        #expect(f.app.screen == screen)
                    }
                }
            }
        }
    }

    /// What is wrong with how the parts of the result card of Přehled stand in `window`, in words: a part is missing or
    /// not inside the card; the key figure is not at the top left, 20 points inside the card; the buttons are not 28
    /// points tall, side by side 8 points apart and 12 points under the key figure; the section of the levy bar is not
    /// the second column of two columns of one width 28 points apart, level at the top, or, one above the other, 20
    /// points under the buttons in the whole width; or the three tiles (`tiles`, the beginnings of what VoiceOver reads
    /// for each) are not in one row at the left edge, 48 points apart, level at the top, 37 points (20, the hairline
    /// and 16) under the lowest of the buttons and the legend, and 20 points above the foot of the card. `beside` says
    /// whether the parts of the first row should stand side by side, and nil that they should do what the width of the
    /// card says: side by side from 788 points inside its padding of 20. The origin of the screen is at the bottom
    /// left, so what is under has the smaller y. Needs the accessibility elements.
    private func problems(
        ofThePartsOfTheResultCardOfPrehledIn window: NSWindow, tiles: [String], beside: Bool?
    ) -> [String] {
        guard let card = frameOfCard(labelled: "Kolik zbývá zaplatit", in: window) else {
            return ["No card Kolik zbývá zaplatit"]
        }
        guard let key = frameOfText(startingWith: "Zbývá zaplatit", in: window) else {
            return ["No key figure"]
        }
        guard let section = accessibilityElement(labelled: "Odvody podle úřadů", in: window)?.accessibilityFrame?()
        else {
            return ["No section Odvody podle úřadů"]
        }
        guard let computation = accessibilityButton(labelled: "Jak se to počítá", in: window)?.accessibilityFrame?(),
            let advances = accessibilityButton(labelled: "Upravit plán záloh", in: window)?.accessibilityFrame?()
        else {
            return ["No buttons Jak se to počítá and Upravit plán záloh"]
        }
        var legend: [CGRect] = []
        for authority in Authority.allCases {
            guard
                let item = accessibilityElement(labelStartingWith: authority.title + ": ", in: window)?
                    .accessibilityFrame?()
            else {
                return ["No item of \(authority.title) in the legend"]
            }
            legend.append(item)
        }
        var tileFrames: [CGRect] = []
        for tile in tiles {
            guard let frame = frameOfText(startingWith: tile, in: window) else {
                return ["No tile \(tile)"]
            }
            tileFrames.append(frame)
        }

        var found: [String] = []
        let parts = [("The key figure", key), ("The section of the levy bar", section)]
            + [("The button Jak se to počítá", computation), ("The button Upravit plán záloh", advances)]
            + tileFrames.enumerated().map { ("The tile \($0.offset + 1)", $0.element) }
        for (name, frame) in parts where !card.insetBy(dx: -0.5, dy: -0.5).contains(frame) {
            found.append("\(name) is not inside the card: \(frame) and \(card)")
        }
        // The origin of the screen is at the bottom left: what is at the top has the largest y. The padding is 20.
        let padding = DesignMetrics.cardPadding
        if (card.maxY - padding - key.maxY).magnitude > 1 || (key.minX - card.minX - padding).magnitude > 1 {
            found.append("The key figure is not at the top left of the card: \(key) and \(card)")
        }
        for (name, frame) in [("Jak se to počítá", computation), ("Upravit plán záloh", advances)]
        where (frame.height - 28).magnitude > 0.5 {
            found.append("The button \(name) is \(frame.height) points tall, not 28")
        }
        if (computation.minY - advances.minY).magnitude > 0.5 || (computation.minX - key.minX).magnitude > 1
            || (advances.minX - computation.maxX - 8).magnitude > 1
        {
            found.append("The buttons are not side by side under the key figure: \(computation), \(advances)")
        }
        if (key.minY - computation.maxY - DesignMetrics.innerSpacing).magnitude > 1 {
            found.append("The buttons are not 12 points under the key figure: \(computation), \(key)")
        }

        let inner = card.width - 2 * padding
        if beside ?? ResultCardLayout.standsSideBySide(innerWidth: inner) {
            let column = (inner - ResultCardLayout.columnGap) / 2
            let second = card.minX + padding + column + ResultCardLayout.columnGap
            if (section.minX - second).magnitude > 1 || (section.width - column).magnitude > 1 {
                found.append("The levy bar is not the second column of \(column) points, 28 from the first: \(section)")
            }
            if (card.maxY - padding - section.maxY).magnitude > 1 {
                found.append("The levy bar is not level at the top with the key figure: \(section), \(card)")
            }
        } else {
            if (computation.minY - section.maxY - ResultCardLayout.rowGap).magnitude > 1 {
                found.append("The levy bar is not 20 points under the buttons: \(section), \(computation)")
            }
            if (section.minX - key.minX).magnitude > 1 || (section.width - inner).magnitude > 1 {
                found.append("The levy bar does not have the whole width of the card, from its left edge: \(section)")
            }
        }

        // The tiles: one row from the left edge, level at the top, 48 points apart, not stretched.
        if (tileFrames[0].minX - card.minX - padding).magnitude > 1 {
            found.append("The first tile is not at the left edge of the card: \(tileFrames[0]), the card \(card)")
        }
        for index in tileFrames.indices.dropFirst() {
            let (before, after) = (tileFrames[index - 1], tileFrames[index])
            if (before.maxY - after.maxY).magnitude > 1 {
                found.append("The tile \(index + 1) is not level at the top with the one before: \(after), \(before)")
            }
            if (after.minX - before.maxX - 48).magnitude > 1 {
                found.append("The tile \(index + 1) is not 48 points from the one before it: \(after), \(before)")
            }
        }
        // Under the lowest of the parts above: the gap of the rows (20), the hairline (1) and the gap under it (16).
        let lowestPart = ([computation.minY, advances.minY] + legend.map(\.minY)).min() ?? 0
        let gap = ResultCardLayout.rowGap + 1 + ResultCardLayout.belowGap
        if (lowestPart - tileFrames[0].maxY - gap).magnitude > 1 {
            found.append("The tiles are not \(gap) points under the parts above them: \(tileFrames[0]), \(lowestPart)")
        }
        if ((tileFrames.map(\.minY).min() ?? 0) - card.minY - padding).magnitude > 1 {
            found.append("The tiles are not 20 points above the foot of the card: \(tileFrames), the card \(card)")
        }
        return found
    }

    /// The points in `window`, in its coordinates (the origin at the bottom left), where the pointer opens the popover
    /// of the tax in the levy bar of Přehled: ten points inside its part in the bar, and ten points inside its item in
    /// the legend. Needs the accessibility elements.
    private func pointsOpeningThePopoverOfTheTax(in window: NSWindow) throws -> [(name: String, point: CGPoint)] {
        let bar = window.convertFromScreen(
            try #require(
                accessibilityElement(labelStartingWith: "Odvody z příjmů do", in: window)?.accessibilityFrame?()))
        let legend = window.convertFromScreen(
            try #require(
                accessibilityElement(labelStartingWith: "Daň z příjmů: odvody z příjmů", in: window)?
                    .accessibilityFrame?()))
        return [
            (name: "part of the tax", point: CGPoint(x: bar.minX + 10, y: bar.midY)),
            (name: "item of the tax in the legend", point: CGPoint(x: legend.minX + 10, y: legend.midY)),
        ]
    }

    /// What is wrong with the result card of Přehled in `window`, in words: the card "Kolik zbývá zaplatit" is missing,
    /// does not hold the picture of the bar of the levies (`levyBar`, read as an image) or has it beyond its frame; or
    /// the card "Příjmy" is not under it, 16 points lower and as wide. Empty when the cards stand so. The origin of the
    /// screen is at the bottom left, so what is under has the smaller y. Needs the accessibility elements.
    private func problems(ofTheResultCardOfPrehledIn window: NSWindow, levyBar: LevyBarData) -> [String] {
        guard let card = accessibilityElement(labelled: "Kolik zbývá zaplatit", in: window),
            let cardFrame = card.accessibilityFrame?()
        else {
            return ["No card Kolik zbývá zaplatit"]
        }
        var found: [String] = []
        if !accessibilityReadings(under: card).contains(levyBar.accessibilityLabel) {
            found.append("The card does not hold the picture of the levy bar: \(levyBar.accessibilityLabel)")
        }
        if let bar = accessibilityElement(labelled: levyBar.accessibilityLabel, in: window) {
            if bar.accessibilityRole?() != .image {
                found.append("The levy bar is no image: \(String(describing: bar.accessibilityRole?()))")
            }
            if let frame = bar.accessibilityFrame?(), !cardFrame.insetBy(dx: -0.5, dy: -0.5).contains(frame) {
                found.append("The levy bar is not within the card: \(frame), the card \(cardFrame)")
            }
        }
        guard let income = frameOfCard(labelled: "Příjmy", in: window) else {
            return found + ["No card Příjmy"]
        }
        let gap = cardFrame.minY - income.maxY
        if (gap - 16).magnitude > 1 {
            found.append("Příjmy is \(gap) points under the card, not 16: \(income), \(cardFrame)")
        }
        if (income.minX - cardFrame.minX).magnitude > 1 || (income.width - cardFrame.width).magnitude > 1 {
            found.append("Příjmy is not as wide as the card: \(income), \(cardFrame)")
        }
        return found
    }

    // MARK: The estimate of the whole year on Přehled

    /// Přehled on the prediction sample, as of Saturday 17. 10. 2026 with "K datu" on another day: the card of the
    /// estimate stands under the chart, which stands under the card of what is left to pay, one card under the other at
    /// the width of the page, at the least room, at a large size and at the least room again.
    @Test func theCardStandsUnderTheChart() async throws {
        try await PredictionSample.withStoredSample { app in
            app.pickAsOf(civilDate("2026-07-15"))
            try await withAppWindow(of: app, size: AppWindowSize.minimum) { window in
                try await withAccessibilityElements {
                    try await showOverviewWithTheEstimate(of: app, in: window)

                    for size in [AppWindowSize.minimum, AppWindowSize.large, AppWindowSize.minimum] {
                        window.setContentSize(size)
                        try await expectSettled(window) { problems(ofTheOrderOfTheCardsIn: window) }
                    }
                }
            }
        }
    }

    /// The page fits the window with the card of the estimate, and the card holds its parts: the title (with no pill)
    /// and the line under it, the button to the right of them, under them the four figures (the income, the levies,
    /// the settlement and the net income) 40 points apart and none of them more than 240 wide or beyond the card or on
    /// another, and under the figures the chart of the year, whose months VoiceOver reads within the card. At the
    /// least room (828 points of page, 740 with the sidebar as wide as it goes) the figures stand in two rows, the
    /// first three side by side and the net income under the income; in a large window all four stand side by side in
    /// one row. No sign of an estimate is read anywhere in the card.
    @Test func theCardHoldsItsPartsAndThePageFitsTheWindowAtTheLeastRoomAndAtALargeSize() async throws {
        try await PredictionSample.withStoredSample { app in
            try await withAppWindow(of: app, size: AppWindowSize.minimum) { window in
                try await withAccessibilityElements {
                    try await showOverviewWithTheEstimate(of: app, in: window)

                    for (size, figureRows) in [
                        (AppWindowSize.minimum, [3, 1]), (AppWindowSize.large, [4]), (AppWindowSize.minimum, [3, 1]),
                    ] {
                        window.setContentSize(size)
                        try await expectSettled(window) {
                            problems(ofPageIn: window)
                                + problems(ofThePartsOfTheEstimateCardIn: window, figureRows: figureRows)
                        }
                    }

                    // The detail of the least window with the sidebar as wide as it goes: 780 points.
                    widenSidebar(of: window)
                    try await expectSettled(window) {
                        problems(ofPageIn: window)
                            + problems(ofThePartsOfTheEstimateCardIn: window, figureRows: [3, 1])
                    }
                }
            }
        }
    }

    @Test func thePredictionButtonOpensTheScreen() async throws {
        try await PredictionSample.withStoredSample { app in
            app.pickAsOf(civilDate("2026-07-15"))
            try await withAppWindow(of: app, size: AppWindowSize.minimum) { window in
                try await withAccessibilityElements {
                    try await showOverviewWithTheEstimate(of: app, in: window)
                    let button = try #require(accessibilityButton(labelled: "Odhad odvodů", in: window))

                    _ = button.accessibilityPerformPress?()

                    try await waitUntil { window.title == "Odhad odvodů" }
                    #expect(app.screen == .prediction)
                    // Nothing else is changed: the year and the day of "K datu" stay as they were.
                    #expect(app.asOf.year == 2026)
                    #expect(app.asOf.asOf == civilDate("2026-07-15"))
                }
            }
        }
    }

    /// A real day change rebuilds the estimate without a write, even when the internal reporting day stays fixed.
    @Test func theCardIsBuiltAgainForTheNextDayWithoutAnyWrite() async throws {
        try await PredictionSample.withStoredSample { app in
            app.pickAsOf(civilDate("2026-07-15"))
            try await withAppWindow(of: app, size: AppWindowSize.minimum) { window in
                try await withAccessibilityElements {
                    try await showOverviewWithTheEstimate(of: app, in: window)
                    let on17th = "z faktur do 17.\u{00A0}10.\u{00A0}2026 ·"
                    let on18th = "z faktur do 18.\u{00A0}10.\u{00A0}2026 ·"
                    try await waitUntil { frameOfText(startingWith: on17th, in: window) != nil }
                    let key = app.reloadKey
                    let version = app.dataVersion

                    app.handleDayChanged(civilDate("2026-10-18"))

                    #expect(app.reloadKey != key)
                    #expect(app.reloadKey.asOf == key.asOf)
                    #expect(app.reloadKey.today == civilDate("2026-10-18"))
                    #expect(app.dataVersion == version)
                    try await waitUntil { frameOfText(startingWith: on18th, in: window) != nil }
                    #expect(frameOfText(startingWith: on17th, in: window) == nil)
                    #expect(app.dataVersion == version)
                    #expect(app.asOf.asOf == civilDate("2026-07-15"))
                }
            }
        }
    }

    /// Shows Přehled in `window` and waits until the card of the estimate and the chart are there. Needs the
    /// accessibility elements.
    private func showOverviewWithTheEstimate(of app: AppModel, in window: NSWindow) async throws {
        app.screen = .overview
        try await waitUntil { window.title == "Přehled" }
        try await waitUntil { frameOfCard(labelled: "Odhad za celý rok", in: window) != nil }
        try await waitUntil { frameOfCard(labelled: "Příjmy", in: window) != nil }
        try await layOut(window)
    }

    /// What is wrong with the order of the cards of Přehled in `window`, in words: the card of what is left to pay, the
    /// chart and the card of the estimate are not one under the other, with the gap of 16 points of the page between
    /// them, and as wide as the page. The origin of the screen is at the bottom left, so what is under has the smaller
    /// y. Needs the accessibility elements.
    private func problems(ofTheOrderOfTheCardsIn window: NSWindow) -> [String] {
        let titles = ["Kolik zbývá zaplatit", "Příjmy", "Odhad za celý rok"]
        let frames = titles.compactMap { frameOfCard(labelled: $0, in: window) }
        guard frames.count == titles.count else {
            return titles.filter { frameOfCard(labelled: $0, in: window) == nil }.map { "No card \($0)" }
        }
        var found: [String] = []
        for index in 1..<frames.count {
            let above = frames[index - 1]
            let below = frames[index]
            let gap = above.minY - below.maxY
            if (gap - 16).magnitude > 1 {
                found.append("\(titles[index]) is \(gap) points under \(titles[index - 1]), not 16: \(below), \(above)")
            }
            if (below.minX - above.minX).magnitude > 1 || (below.width - above.width).magnitude > 1 {
                found.append("\(titles[index]) is not as wide as \(titles[index - 1]): \(below), \(above)")
            }
        }
        return found
    }

    /// What is wrong with the parts of the card of the estimate in `window`, in words: its title, the line under the
    /// title, the four figures, the button or the months of the chart are not there, are beyond the card, lie on one
    /// another, or are not arranged as the card arranges them; the card has a pill "odhad" or a sign "≈" among
    /// what VoiceOver reads. The button stands to the right of the title and the line, in a row level with the title's:
    /// its middle is within the height of the title and the line. The figures stand under the title and the button, in
    /// rows of `figureRows` figures from the top; the figures of a row are level, side by side in the order income,
    /// levies, settlement, net income, 40 points apart and at most 240 points wide, and each row is under the one
    /// before it. The chart stands under the figures: the elements VoiceOver reads for its months of September,
    /// October and November are under every figure. The origin of the screen is at the bottom left, so what is under
    /// has the smaller y. Needs the accessibility elements.
    private func problems(ofThePartsOfTheEstimateCardIn window: NSWindow, figureRows: [Int]) -> [String] {
        guard let card = accessibilityElement(labelled: "Odhad za celý rok", in: window),
            let cardFrame = card.accessibilityFrame?()
        else {
            return ["No card Odhad za celý rok"]
        }
        // What VoiceOver reads for each part of the card, which starts with the words that find it.
        let parts = [
            (name: "the title", reading: "Odhad za celý rok 2026"),
            (name: "the line under the title", reading: "z faktur do "), (name: "the income", reading: "Příjmy za rok"),
            (name: "the levies", reading: "Odvody, "), (name: "the settlement", reading: "Doplatek, "),
            (name: "the net income", reading: "Čistý příjem průměrně za měsíc"),
            (name: "the button", reading: "Odhad odvodů"),
        ]
        let children = (card.accessibilityChildren?() ?? []).map { $0 as AnyObject }
        var frames: [String: CGRect] = [:]
        var found: [String] = []
        for (name, reading) in parts {
            let part = children.first { child in
                let value: (() -> Any?)? = child.accessibilityValue
                let words = (value?() ?? nil) as? String ?? child.accessibilityLabel?() ?? ""
                return words.hasPrefix(reading)
            }
            guard let frame = part?.accessibilityFrame?() else {
                found.append("No \(name) in the card")
                continue
            }
            frames[name] = frame
            if !cardFrame.insetBy(dx: -0.5, dy: -0.5).contains(frame) {
                found.append("\(name) is not within the card: \(frame), the card \(cardFrame)")
            }
        }
        // The card is an area of estimates as a whole: it has no pill that says so and no sign "≈" before a figure.
        let readings = accessibilityReadings(under: card)
        if readings.contains("odhad") {
            found.append("The card has the pill odhad")
        }
        if let approximate = readings.first(where: { $0.contains("≈") }) {
            found.append("The card reads a sign of an estimate: \(approximate)")
        }
        guard found.isEmpty, let title = frames["the title"], let line = frames["the line under the title"],
            let button = frames["the button"]
        else {
            return found
        }
        // The figures in the order they stand in.
        let figures = ["the income", "the levies", "the settlement", "the net income"].compactMap { frames[$0] }
        let names = parts.map(\.name)
        for (index, name) in names.enumerated() {
            for other in names[(index + 1)...] {
                guard let one = frames[name], let two = frames[other] else { continue }
                if one.intersection(two).width > 0.5 && one.intersection(two).height > 0.5 {
                    found.append("\(name) lies on \(other): \(one), \(two)")
                }
            }
        }
        // The button is to the right of the title and the line, in a row level with the title's.
        let titleRight = max(title.maxX, line.maxX)
        let titleTop = max(title.maxY, line.maxY)
        let titleBottom = min(title.minY, line.minY)
        if button.minX < titleRight - 0.5 {
            found.append("The button is not to the right of the title: \(button), the title ends at \(titleRight)")
        }
        if button.midY > titleTop + 0.5 || button.midY < titleBottom - 0.5 {
            found.append(
                "The button is not level with the title: \(button), the title spans \(titleBottom)–\(titleTop)")
        }
        // Every figure is under the title and the button.
        let headBottom = min(titleBottom, button.minY)
        if figures.contains(where: { $0.maxY > headBottom + 0.5 }) {
            found.append("The figures are not under the title and the button: \(figures), they end at \(headBottom)")
        }
        // The figures of a row share their top, the largest y.
        var rows: [[CGRect]] = []
        for figure in figures {
            if let top = rows.last?.first?.maxY, (top - figure.maxY).magnitude < 0.5 {
                rows[rows.count - 1].append(figure)
            } else {
                rows.append([figure])
            }
        }
        if rows.map(\.count) != figureRows {
            found.append("The figures are in rows of \(rows.map(\.count)), not of \(figureRows): \(figures)")
        }
        for row in rows {
            for (left, right) in zip(row, row.dropFirst()) where left.maxX > right.minX + 0.5 {
                found.append("The figures of a row are not side by side in their order: \(row)")
            }
            for (left, right) in zip(row, row.dropFirst()) where (right.minX - left.maxX - 40).magnitude > 1 {
                found.append("The figures of a row are not 40 points apart: \(left), \(right)")
            }
        }
        for figure in figures where figure.width > 240.5 {
            found.append("A figure is \(figure.width) points wide, not at most 240: \(figure)")
        }
        for (above, below) in zip(rows, rows.dropFirst()) {
            if let bottom = above.map(\.minY).min(), let top = below.map(\.maxY).max(), top > bottom + 0.5 {
                found.append("A row of figures is not under the row before it: \(below), \(above)")
            }
        }
        // A month of the chart, found by the words VoiceOver starts it with: a past one, the one of today and one to
        // come. The chart of Příjmy reads its months as well, and September with the same words, so they are looked
        // for in the card.
        let figuresBottom = figures.map(\.minY).min() ?? cardFrame.maxY
        let elements = descendants(of: card)
        for start in ["Září 2026:", "Říjen 2026 · do", "Listopad 2026 · odhad:"] {
            let month = elements.first { ($0.accessibilityLabel?() ?? "").hasPrefix(start) }
            guard let frame = month?.accessibilityFrame?() else {
                found.append("No month '\(start)' of the chart in the card")
                continue
            }
            if !cardFrame.insetBy(dx: -0.5, dy: -0.5).contains(frame) {
                found.append("The month '\(start)' is not within the card: \(frame), the card \(cardFrame)")
            }
            if frame.maxY > figuresBottom + 0.5 {
                found.append("The month '\(start)' is not under the figures: \(frame), they end at \(figuresBottom)")
            }
        }
        return found
    }

    // MARK: The net income above the chart on Přehled

    /// Přehled on the prediction sample as of Saturday 17. 10. 2026, today: the strip of the net income stands in the
    /// card "Příjmy" above the legend of the chart, the net income of the year so far and its average per month side by
    /// side, level and 48 points apart, at the least room, at a large size and at the least room again, with the page
    /// fitting the window.
    @Test func theNetIncomeStripStandsInThePrijmyCardAboveTheChart() async throws {
        try await PredictionSample.withStoredSample { app in
            try await withAppWindow(of: app, size: AppWindowSize.minimum) { window in
                try await withAccessibilityElements {
                    try await showOverviewWithTheEstimate(of: app, in: window)

                    for size in [AppWindowSize.minimum, AppWindowSize.large, AppWindowSize.minimum] {
                        window.setContentSize(size)
                        try await expectSettled(window) {
                            problems(ofPageIn: window) + problems(ofTheNetIncomeStripIn: window)
                        }
                    }
                }
            }
        }
    }

    /// What is wrong with the strip of the net income in the card "Příjmy" of Přehled in `window`, in words: the net
    /// income of the year so far, its average per month or the legend of the chart is not there or is beyond the card,
    /// VoiceOver does not read a figure as one phrase with its words and the line under it, the two figures do not
    /// stand level side by side in that order, they are not above the legend, or the legend of the chart by months has
    /// the key of the net income line of the chart by years. The origin of the screen is at the bottom left, so what is
    /// above has the larger y. Needs the accessibility elements.
    private func problems(ofTheNetIncomeStripIn window: NSWindow) -> [String] {
        guard let card = frameOfCard(labelled: "Příjmy", in: window) else {
            return ["No card Příjmy"]
        }
        var found: [String] = []
        // Each figure is one element that VoiceOver reads as one phrase: its words, the figure and the line under it.
        let phrases = [
            (
                words: "Čistý příjem od 1.\u{00A0}1. do 17.\u{00A0}10.", figure: "1\u{00A0}933\u{00A0}471\u{00A0}Kč",
                line: "88,2\u{00A0}% příjmů bez DPH po odvodech"
            ),
            (
                words: "Čistý příjem průměrně za měsíc", figure: "193\u{00A0}347\u{00A0}Kč",
                line: "průměr za leden–říjen"
            ),
        ]
        // The card of the estimate below it has a figure with the words of the average per month, so a phrase is found
        // by its words and its figure, which VoiceOver reads one after the other with a comma between them.
        let readings = accessibilityReadings(in: window)
        for (words, figure, line) in phrases {
            let reading = readings.first { $0.hasPrefix(words + ", " + figure) } ?? ""
            if !reading.contains(figure) || !reading.hasSuffix(line) {
                found.append("'\(words)' is not read with its figure and its line as one phrase: '\(reading)'")
            }
        }
        // What VoiceOver reads for each part, which starts with the words that find it.
        let parts = [
            (name: "the net income of the year", reading: phrases[0].words),
            (name: "the average per month", reading: phrases[1].words + ", " + phrases[1].figure),
            (name: "the legend of the chart", reading: "Vystaveno (podle data vystavení)"),
        ]
        var frames: [CGRect] = []
        for (name, reading) in parts {
            guard let frame = frameOfText(startingWith: reading, in: window) else {
                found.append("Cannot find \(name) in the window")
                continue
            }
            frames.append(frame)
            if !card.insetBy(dx: -0.5, dy: -0.5).contains(frame) {
                found.append("\(name) is not within the card: \(frame), the card \(card)")
            }
        }
        guard frames.count == parts.count else { return found }
        let (year, average, legend) = (frames[0], frames[1], frames[2])
        if (year.maxY - average.maxY).magnitude > 1 {
            found.append("The net income and its average are not level: \(year), \(average)")
        }
        if year.maxX > average.minX + 0.5 {
            found.append("The net income is not to the left of its average: \(year), \(average)")
        }
        if (average.minX - year.maxX - 48).magnitude > 1 {
            found.append("The net income and its average are not 48 points apart: \(year), \(average)")
        }
        if (year.minX - card.minX - 20).magnitude > 1 {
            found.append("The net income is not 20 points from the edge of the card: \(year), the card \(card)")
        }
        if min(year.minY, average.minY) < legend.maxY - 0.5 {
            found.append("The net income and its average are not above the legend: \(year), \(average), \(legend)")
        }
        // The net income line of the chart by months is not that of the chart by years, so its key is another.
        if frameOfText(startingWith: Self.netIncomeKeyByYears, in: window) != nil {
            found.append("The legend of the chart by months has the key of the net income line of the chart by years")
        }
        return found
    }

    /// What the legend of the chart by years says of the line of the net income, the third key of the legend.
    private static let netIncomeKeyByYears = "Čistý příjem za rok (po odvodech, vždy bez DPH)"

    /// What the legend of the chart by months says of the line of the net income, the third key of the legend.
    private static let netIncomeKeyByMonths = "Čistý příjem (součet za faktury zaplacené v měsíci, bez DPH)"

    /// Přehled on the prediction sample as of Saturday 17. 10. 2026, today, with the chart by years: the legend has the
    /// key of the net income line, which stands in the card "Příjmy" below the strip of the net income, the columns of
    /// the chart tell the net income of their years, and the page fits the window, at the least room, at a large size
    /// and at the least room again.
    @Test func theChartByYearsShowsTheNetIncomeKeyAndFitsTheWindow() async throws {
        try await PredictionSample.withStoredSample { app in
            await app.updateAppSettings { $0.chartMode = .years }
            try await withAppWindow(of: app, size: AppWindowSize.minimum) { window in
                try await withAccessibilityElements {
                    try await showOverviewWithTheEstimate(of: app, in: window)
                    try await waitUntil { frameOfText(startingWith: Self.netIncomeKeyByYears, in: window) != nil }

                    for size in [AppWindowSize.minimum, AppWindowSize.large, AppWindowSize.minimum] {
                        window.setContentSize(size)
                        try await expectSettled(window) {
                            problems(ofPageIn: window) + problems(ofTheNetIncomeInTheChartByYearsIn: window)
                        }
                    }
                }
            }
        }
    }

    /// What is wrong with the net income in the chart by years of Přehled in `window`, in words: the key of its line in
    /// the legend is not there, is beyond the card "Příjmy" or does not stand below the average per month of the strip
    /// above the chart; or a column of the chart for 2025 or 2026 does not read out the net income of its year and its
    /// average per month, as the engine works them out for the prediction sample. The origin of the screen is at the
    /// bottom left, so what is below has the smaller y. Needs the accessibility elements.
    private func problems(ofTheNetIncomeInTheChartByYearsIn window: NSWindow) -> [String] {
        guard let card = frameOfCard(labelled: "Příjmy", in: window) else {
            return ["No card Příjmy"]
        }
        guard let key = frameOfText(startingWith: Self.netIncomeKeyByYears, in: window) else {
            return ["Cannot find the key of the net income line in the window"]
        }
        // The card of the estimate below it has a figure with the same words, so the average of the strip is found by
        // its figure as well.
        let averageStart = "Čistý příjem průměrně za měsíc, 193\u{00A0}347\u{00A0}Kč"
        guard let average = frameOfText(startingWith: averageStart, in: window) else {
            return ["Cannot find the average per month of the strip in the window"]
        }
        var found: [String] = []
        if !card.insetBy(dx: -0.5, dy: -0.5).contains(key) {
            found.append("The key of the net income line is not within the card: \(key), the card \(card)")
        }
        if key.maxY > average.minY + 0.5 {
            found.append("The key of the net income line is not below the strip: \(key), the average \(average)")
        }
        // Each column is one element that VoiceOver reads from the title of the year to the end of its average.
        let readings = accessibilityReadings(in: window)
        let years = [
            (
                title: "Rok 2025:", net: "2\u{00A0}393\u{00A0}295\u{00A0}Kč",
                average: "Průměrný čistý příjem za měsíc v roce 2025 199\u{00A0}441\u{00A0}Kč"
            ),
            (
                title: "Rok 2026:", net: "1\u{00A0}933\u{00A0}471\u{00A0}Kč",
                average: "Průměrný čistý příjem za měsíc v roce 2026 (leden–říjen) 193\u{00A0}347\u{00A0}Kč"
            ),
        ]
        for (title, net, average) in years {
            let reading = readings.first { $0.hasPrefix(title) } ?? ""
            if !reading.hasSuffix("; čistý příjem " + net + "; " + average) {
                found.append("'\(title)' does not read out its net income and its average: '\(reading)'")
            }
        }
        return found
    }

    /// Přehled on the prediction sample as of Saturday 17. 10. 2026, today, with the chart by months, which the app
    /// starts with: the legend has the key of the net income line, which stands in the card "Příjmy" below the strip of
    /// the net income, the columns of the chart tell the net income of their months, and the page fits the window, at
    /// the least room, at a large size and at the least room again.
    @Test func theChartByMonthsShowsTheNetIncomeKeyAndFitsTheWindow() async throws {
        try await PredictionSample.withStoredSample { app in
            try await withAppWindow(of: app, size: AppWindowSize.minimum) { window in
                try await withAccessibilityElements {
                    try await showOverviewWithTheEstimate(of: app, in: window)
                    try await waitUntil { frameOfText(startingWith: Self.netIncomeKeyByMonths, in: window) != nil }

                    for size in [AppWindowSize.minimum, AppWindowSize.large, AppWindowSize.minimum] {
                        window.setContentSize(size)
                        try await expectSettled(window) {
                            problems(ofPageIn: window) + problems(ofTheNetIncomeInTheChartByMonthsIn: window)
                        }
                    }
                }
            }
        }
    }

    /// What is wrong with the net income in the chart by months of Přehled in `window`, in words: the key of its line
    /// in the legend is not there, is beyond the card "Příjmy" or does not stand below the average per month of the
    /// strip above the chart; or a column of the chart for February, October or November does not read out the net
    /// income of the invoices paid in its month and the average per month of the year, as the engine works them out for
    /// the prediction sample (November is after the day shown, so it has nothing). The origin of the screen is at the
    /// bottom left, so what is below has the smaller y. Needs the accessibility elements.
    private func problems(ofTheNetIncomeInTheChartByMonthsIn window: NSWindow) -> [String] {
        guard let cardElement = accessibilityElement(labelled: "Příjmy", in: window),
            let card = cardElement.accessibilityFrame?()
        else {
            return ["No card Příjmy"]
        }
        guard let key = frameOfText(startingWith: Self.netIncomeKeyByMonths, in: window) else {
            return ["Cannot find the key of the net income line in the window"]
        }
        // The card of the estimate below it has a figure with the same words, so the average of the strip is found by
        // its figure as well.
        let averageStart = "Čistý příjem průměrně za měsíc, 193\u{00A0}347\u{00A0}Kč"
        guard let average = frameOfText(startingWith: averageStart, in: window) else {
            return ["Cannot find the average per month of the strip in the window"]
        }
        var found: [String] = []
        if !card.insetBy(dx: -0.5, dy: -0.5).contains(key) {
            found.append("The key of the net income line is not within the card: \(key), the card \(card)")
        }
        if key.maxY > average.minY + 0.5 {
            found.append("The key of the net income line is not below the strip: \(key), the average \(average)")
        }
        // Each column is one element that VoiceOver reads from the title of the month to the end of its average. The
        // chart of the card of the estimate has an element for each month too, and a past month there starts with the
        // same words ("Únor 2026:"), so the columns are looked for in the card "Příjmy" alone.
        let readings = accessibilityReadings(under: cardElement)
        let months = [
            (title: "Únor 2026:", net: "253\u{00A0}401\u{00A0}Kč"),
            (title: "Říjen 2026:", net: "219\u{00A0}811\u{00A0}Kč"),
            (title: "Listopad 2026:", net: "0\u{00A0}Kč"),
        ]
        let average2026 = "Průměrný čistý příjem za měsíc v roce 2026 (leden–říjen) 193\u{00A0}347\u{00A0}Kč"
        for (title, net) in months {
            let reading = readings.first { $0.hasPrefix(title) } ?? ""
            if !reading.hasSuffix("; čistý příjem " + net + "; " + average2026) {
                found.append("'\(title)' does not read out its net income and its average: '\(reading)'")
            }
        }
        return found
    }

    /// The card "Příjmy" groups its chart with the segmented control of the design: a group "Seskupit" on a track of 32
    /// points in the card, with the buttons Měsíce and Roky of 28 points, the chosen one selected. The press of Roky,
    /// as VoiceOver makes it, groups the chart by years, keeps the choice in the settings and moves the mark; the
    /// press of Měsíce undoes it.
    @Test func theSegmentedControlOfPrijmyChoosesMonthsOrYears() async throws {
        try await PredictionSample.withStoredSample { app in
            try await withAppWindow(of: app, size: AppWindowSize.minimum) { window in
                try await withAccessibilityElements {
                    try await showOverviewWithTheEstimate(of: app, in: window)
                    try await waitUntil { accessibilityElement(labelled: "Seskupit", in: window) != nil }
                    let group = try #require(accessibilityElement(labelled: "Seskupit", in: window))
                    let track = try #require(group.accessibilityFrame?())
                    let card = try #require(frameOfCard(labelled: "Příjmy", in: window))
                    #expect(group.accessibilityRole?() == .group)
                    #expect(abs(track.height - 32) < 0.5, "The track is \(track.height) points tall")
                    #expect(card.insetBy(dx: -0.5, dy: -0.5).contains(track), "The control is outside the card")
                    let months = try #require(accessibilityButton(labelled: "Měsíce", in: window))
                    #expect(abs(try #require(months.accessibilityFrame?()).height - 28) < 0.5)
                    #expect(months.isAccessibilitySelected?() == true)
                    #expect(accessibilityButton(labelled: "Roky", in: window)?.isAccessibilitySelected?() != true)
                    #expect(app.appSettings.chartMode == .months)

                    let years = try #require(accessibilityButton(labelled: "Roky", in: window))
                    #expect(years.accessibilityPerformPress?() == true)
                    try await waitUntil { app.appSettings.chartMode == .years }
                    try await waitUntil { frameOfText(startingWith: Self.netIncomeKeyByYears, in: window) != nil }
                    #expect(accessibilityButton(labelled: "Roky", in: window)?.isAccessibilitySelected?() == true)
                    #expect(accessibilityButton(labelled: "Měsíce", in: window)?.isAccessibilitySelected?() != true)

                    let back = try #require(accessibilityButton(labelled: "Měsíce", in: window))
                    #expect(back.accessibilityPerformPress?() == true)
                    try await waitUntil { app.appSettings.chartMode == .months }
                    try await waitUntil { frameOfText(startingWith: Self.netIncomeKeyByMonths, in: window) != nil }
                }
            }
        }
    }

    // MARK: Zálohy a odpočty

    @Test func zalohyAOdpoctyFitTheWindowAtTheLeastRoomAndAtALargeSize() async throws {
        try await EditorFixture.with { f in
            try await withAppWindow(of: f.app, size: AppWindowSize.minimum) { window in
                f.app.screen = .advances
                try await waitUntil { window.title == "Zálohy a odpočty" }
                // The page scrolls; with the data it is far taller than while it loads.
                try await waitUntil { (scrolledPage(in: window)?.frame.height ?? 0) > 600 }

                try await expectSettled(window) { problems(ofPageIn: window) }
                window.setContentSize(AppWindowSize.large)
                try await expectSettled(window) { problems(ofPageIn: window) }
                window.setContentSize(AppWindowSize.minimum)
                try await expectSettled(window) { problems(ofPageIn: window) }
            }
        }
    }

    /// Zálohy a odpočty with 30 % chosen, which puts a note about rent under the menu of the rate. At the least room,
    /// where the rate stands over the box of the reduced base, at a large size, where the two stand side by side, and
    /// at the least room again, the page fits the window and the note is whole: within the card, as tall as its text
    /// needs at its width, under the menu of the rate and over the box where that stands under the menu.
    @Test func zalohyAOdpoctyWithTheNoteOfTheRateOf30PercentFitTheWindowAtTheLeastRoomAndAtALargeSize() async throws {
        try await EditorFixture.with { f in
            try await f.database.updateYearSettings(2026) { $0.expensePercent = 30 }
            await f.app.didWriteAndBackUp()
            try await withAppWindow(of: f.app, size: AppWindowSize.minimum) { window in
                f.app.screen = .advances
                try await waitUntil { window.title == "Zálohy a odpočty" }
                // The page scrolls; with the data it is far taller than while it loads.
                try await waitUntil { (scrolledPage(in: window)?.frame.height ?? 0) > 600 }

                try await withAccessibilityElements {
                    try await waitUntil { frameOfText(startingWith: Self.rentNote, in: window) != nil }
                    for size in [AppWindowSize.minimum, AppWindowSize.large, AppWindowSize.minimum] {
                        window.setContentSize(size)
                        try await expectSettled(window) {
                            problems(ofPageIn: window) + problems(ofTheNoteUnderTheRateIn: window)
                        }
                    }
                }
            }
        }
    }

    /// The menu of the rate of the flat-rate expenses in Zálohy a odpočty, and the box of the reduced base of the
    /// social insurance, by the labels VoiceOver reads them under.
    private static let rateMenuLabel = "Sazba paušálních výdajů"
    private static let reducedBaseLabel = "Snížený vyměřovací základ pro sociální pojištění"

    /// What is wrong with the note of the rate of 30 % in Zálohy a odpočty of `window`, which has 30 % chosen, in
    /// words: the note is missing or not within the card "Zálohy", is lower than its whole text needs at its width, as
    /// a text cut short would be, is not under the menu of the rate, lies over the menu or the box of the reduced base,
    /// or, where that box stands under the menu, is not over the box. Empty when it fits. Needs the accessibility
    /// elements.
    private func problems(ofTheNoteUnderTheRateIn window: NSWindow) -> [String] {
        guard let card = frameOfCard(labelled: "Zálohy", in: window) else { return ["No card Zálohy"] }
        guard let note = frameOfText(startingWith: Self.rentNote, in: window) else {
            return ["No note \(Self.rentNote)"]
        }
        guard let menu = accessibilityElement(labelled: Self.rateMenuLabel, in: window)?.accessibilityFrame?() else {
            return ["No menu \(Self.rateMenuLabel)"]
        }
        guard let box = accessibilityElement(labelled: Self.reducedBaseLabel, in: window)?.accessibilityFrame?() else {
            return ["No box \(Self.reducedBaseLabel)"]
        }
        var found = problems(ofText: Self.rentNote, frame: note, font: .callout, within: card, in: window)
        // The origin of the screen is at the bottom left, so what is under has the smaller y.
        if note.maxY > menu.minY + 0.5 {
            found.append("The note is not under the menu of the rate: \(note), the menu \(menu)")
        }
        for (name, part) in [("the menu of the rate", menu), ("the box of the reduced base", box)]
        where note.insetBy(dx: 0.5, dy: 0.5).intersects(part) {
            found.append("The note lies over \(name): \(note) and \(part)")
        }
        if box.maxY <= menu.minY + 0.5 && box.maxY > note.minY + 0.5 {
            found.append("The box of the reduced base is under the menu but not under the note: \(box), \(note)")
        }
        return found
    }

    /// Zálohy a odpočty with a family whose cards say the most: a child of mine, one of the other parent, one for each
    /// reason of counting in no month, a spouse with ZTP/P and without a child under three, and as of 31. 1. 2026, when
    /// no income has come yet, a benefit that is not paid as a bonus. At the least room, where the impact panel is
    /// under the cards, at the room where it first stands beside them and they are at their narrowest, at a large size
    /// and at the least room again, every text of the cards is whole: within its card, and as tall as the text needs at
    /// its width. So are the rows of the children, as their rows draw them, and the box of ZTP/P with its label.
    @Test func zalohyAOdpoctyWithTheFamilyFitTheWindowAtTheLeastRoomAndAtALargeSize() async throws {
        try await EditorFixture.with { f in
            try await Self.storeFamilyWithTheLongestTexts(in: f.database)
            await f.app.didWriteAndBackUp()
            f.app.pickAsOf(civilDate("2026-01-31"))
            try await withAppWindow(of: f.app, size: AppWindowSize.minimum) { window in
                f.app.screen = .advances
                try await waitUntil { window.title == "Zálohy a odpočty" }
                try await withAccessibilityElements {
                    try await waitUntil { frameOfText(startingWith: Self.familyTexts[1].prefix, in: window) != nil }

                    let sizes = [
                        AppWindowSize.minimum, AdvancesWindowSize.impactPanelBeside, AppWindowSize.large,
                        AppWindowSize.minimum,
                    ]
                    for size in sizes {
                        window.setContentSize(size)
                        try await expectSettled(window) { problems(ofPageIn: window) + problems(ofFamilyIn: window) }
                    }
                }
            }
        }
    }

    /// The row of a child breaks its reason over more lines where it is narrow, rather than cut it: the row grows.
    @Test func theRowOfAChildGrowsForItsReasonRatherThanCutIt() {
        func height(at width: CGFloat) -> CGFloat {
            let row = ChildRowButton(row: Self.rowWithReason) {}
            return NSHostingView(rootView: row.frame(width: width).fixedSize(horizontal: false, vertical: true))
                .fittingSize.height
        }
        let wide = height(at: 600)
        let narrow = height(at: 160)

        #expect(narrow > wide + 20, "The row is \(narrow) points tall at 160 points and \(wide) at 600")
    }

    /// The dialog of a child is a sheet of the window with the lock after inactivity over it, at the least room as
    /// well: with every row it can have — ZTP/P and the studies with their months, and what the child comes to — and
    /// with the question before a removal in place of its buttons, it is 620 points wide, no taller than the window,
    /// and its texts are whole.
    @Test func theDialogOfAChildFitsTheWindowAtTheLeastRoom() async throws {
        // The sheet is the key window once it is shown, and its fields share the field editor of every window:
        // the test takes the turn of the tests that type into a window.
        try await whileTypingAlone {
            try await EditorFixture.with { f in
                try await Self.storeFamilyWithTheLongestTexts(in: f.database)
                await f.app.didWriteAndBackUp()
                try await withAppWindow(of: f.app, size: AppWindowSize.minimum) { window in
                    f.app.screen = .advances
                    try await waitUntil { window.title == "Zálohy a odpočty" }
                    try await withAccessibilityElements {
                        let jan = Self.familyRows[3]
                        try await waitUntil { accessibilityButton(labelled: jan, in: window) != nil }
                        _ = try #require(accessibilityButton(labelled: jan, in: window)).accessibilityPerformPress?()
                        try await waitUntil { window.attachedSheet != nil }
                        let sheet = try #require(window.attachedSheet)
                        #expect(IdleLockSheets.guarded.contains(sheet))

                        for box in ["Průkaz ZTP/P – zvýhodnění dvojnásobné", "Po 18. narozeninách studuje"] {
                            try await waitUntil { accessibilityElement(labelled: box, in: sheet) != nil }
                            let checkbox = try #require(accessibilityElement(labelled: box, in: sheet))
                            _ = checkbox.accessibilityPerformPress?()
                        }
                        try await waitUntil { frameOfText(startingWith: Self.janInTheDialog, in: sheet) != nil }
                        try await expectSettled(window) { problems(ofDialog: sheet, in: window) }

                        let remove = try #require(accessibilityButton(labelled: "Odebrat dítě", in: sheet))
                        _ = remove.accessibilityPerformPress?()
                        let question = ChildDialogModel.removalMessage(year: 2026)
                        try await waitUntil { frameOfText(startingWith: question, in: sheet) != nil }
                        try await expectSettled(window) { problems(ofDialog: sheet, in: window) }
                        #expect(accessibilityButton(labelled: "Uložit dítě", in: sheet) == nil)
                    }
                }
            }
        }
    }

    /// What Jan comes to in his dialog once he studies the whole year with ZTP/P: of the children who count in 2026,
    /// Anna and Petr come before him.
    private static let janInTheDialog = "V roce 2026: 12\u{00A0}měsíců jako 3. a další dítě (se ZTP/P dvojnásobek)"

    /// Stores for 2026 a family whose cards say the most: Anna, mine; Petr, the other parent's; Eva, 26; Jan, an adult
    /// who does not study; Kristýna, who does not live in the household; and a spouse with ZTP/P in three months.
    private static func storeFamilyWithTheLongestTexts(in database: Database) async throws {
        let children: [(name: String, born: String, household: MonthRange?, claimant: Claimant)] = [
            ("Anna", "2019-09-03", MonthRange.wholeYear, .me),
            ("Petr", "2012-05-01", MonthRange.wholeYear, .otherParent),
            ("Eva", "2000-01-01", MonthRange.wholeYear, .me),
            ("Jan", "2007-03-01", MonthRange.wholeYear, .me),
            ("Kristýna Alžběta Nováková-Dvořáková", "2015-06-01", nil, .me),
        ]
        for (order, child) in children.enumerated() {
            try await database.saveChild(
                Child(id: nil, name: child.name, birthDate: civilDate(child.born)), year: 2026,
                childYear: ChildYear(
                    household: child.household, claimant: child.claimant, order: order + 1, ztpp: nil, studies: nil))
        }
        try await database.saveSpouse(
            SpouseYear(claim: true, months: MonthRange.wholeYear, ownIncomeKc: 0, ztpp: MonthRange(from: 9, to: 11)),
            year: 2026)
    }

    /// The texts of the family cards that say the most, by how each begins, with the card they are in and the font
    /// they are set in. As of 31. 1. 2026 the benefit of Anna is not paid as a bonus yet.
    private static let familyTexts: [(prefix: String, card: String, font: Font)] = [
        ("Za každý měsíc, na jehož začátku", "Děti", .callout),
        ("Pořadí dětí se s druhým rodičem dohodněte", "Děti", .callout),
        ("24\u{00A0}840\u{00A0}Kč za rok – 2\u{00A0}070\u{00A0}Kč za každý měsíc", "Manžel nebo manželka", .callout),
        ("Hrubé příjmy za celý rok", "Manžel nebo manželka", .callout),
        ("Od roku 2024 se sleva uplatní jen za měsíce", "Manžel nebo manželka", .body),
        ("V roce 2026 se sleva neuplatní", "Manžel nebo manželka", .body.weight(.semibold)),
    ]

    /// What is wrong with the cards of the family in `window`, in words: a card that is missing, a text or a row of a
    /// child that is missing or not within its card, and a text that is lower than it needs to be at its width, as a
    /// text cut short would be. Empty when the cards fit. Needs the accessibility elements.
    private func problems(ofFamilyIn window: NSWindow) -> [String] {
        var found: [String] = []
        for (prefix, label, font) in Self.familyTexts {
            guard let card = frameOfCard(labelled: label, in: window) else {
                return ["No card \(label)"]
            }
            guard let frame = frameOfText(startingWith: prefix, in: window) else {
                found.append("No text \(prefix)")
                continue
            }
            found += problems(ofText: prefix, frame: frame, font: font, within: card, in: window)
        }
        guard let children = frameOfCard(labelled: "Děti", in: window) else { return found + ["No card Děti"] }
        for row in Self.familyRows {
            guard let frame = accessibilityButton(labelled: row, in: window)?.accessibilityFrame?() else {
                found.append("No row \(row)")
                continue
            }
            if frame.minX < children.minX - 0.5 || frame.maxX > children.maxX + 0.5
                || frame.minY < children.minY - 0.5
            {
                found.append("The row \(row) is not within its card: \(frame), the card \(children)")
            }
        }
        // The row with a reason is as tall as the row needs at its width, as is the box of ZTP/P with its label.
        if let frame = accessibilityButton(labelled: Self.rowWithReason.spokenText, in: window)?.accessibilityFrame?() {
            let row = ChildRowButton(row: Self.rowWithReason) {}
            found += problems(of: "the row of Jan", frame: frame, needing: row)
        }
        guard let spouse = frameOfCard(labelled: "Manžel nebo manželka", in: window) else {
            return found + ["No card Manžel nebo manželka"]
        }
        guard let box = accessibilityElement(labelled: Self.spouseZTPPLabel, in: window)?.accessibilityFrame?() else {
            return found + ["No box \(Self.spouseZTPPLabel)"]
        }
        if box.minX < spouse.minX - 0.5 || box.maxX > spouse.maxX + 0.5 {
            found.append("The box \(Self.spouseZTPPLabel) is not within its card: \(box), the card \(spouse)")
        }
        let toggle = Toggle(Self.spouseZTPPLabel, isOn: .constant(true)).toggleStyle(.checkbox)
        found += problems(of: Self.spouseZTPPLabel, frame: box, needing: toggle)
        return found
    }

    /// What is wrong with `view` shown at `frame`, in the coordinates of the screen, in words: it is lower than `view`
    /// needs at that width, as a view whose text is cut short would be.
    private func problems<Content: View>(of what: String, frame: CGRect, needing view: Content) -> [String] {
        let measured = view.frame(width: frame.width).fixedSize(horizontal: false, vertical: true)
        let needed = NSHostingView(rootView: measured).fittingSize.height
        return frame.height + 1 < needed ? ["\(what) is \(frame.height) points tall, it needs \(needed)"] : []
    }

    /// The label of the box of ZTP/P of the spouse, with the months beside it while it is ticked.
    private static let spouseZTPPLabel = "Průkaz ZTP/P – sleva dvojnásobná"

    /// A row of a child that counts in no month, with its longest reason, as the card shows it.
    private static let rowWithReason = ChildCardRow(
        member: FamilyChild(
            child: Child(id: nil, name: "Jan", birthDate: civilDate("2007-03-01")),
            year: ChildYear(household: MonthRange.wholeYear, claimant: .me, order: 4, ztpp: nil, studies: nil),
            isStored: true),
        name: "Jan", birth: "nar. 1.\u{00A0}3.\u{00A0}2007", status: "zletilé a nestuduje – zvýhodnění nelze uplatnit",
        countsInNoMonth: true, amount: "—", hasAmount: false)

    /// What VoiceOver reads for the rows of the children of `storeFamilyWithTheLongestTexts(in:)`.
    private static let familyRows = [
        "Anna · nar. 3.\u{00A0}9.\u{00A0}2019, 1. dítě · 12\u{00A0}měsíců, 15\u{00A0}204\u{00A0}Kč",
        "Petr · nar. 1.\u{00A0}5.\u{00A0}2012, uplatňuje druhý rodič · 12\u{00A0}měsíců, —",
        "Eva · nar. 1.\u{00A0}1.\u{00A0}2000, už 26 let – zvýhodnění nelze uplatnit, —",
        "Jan · nar. 1.\u{00A0}3.\u{00A0}2007, zletilé a nestuduje – zvýhodnění nelze uplatnit, —",
        "Kristýna Alžběta Nováková-Dvořáková · nar. 1.\u{00A0}6.\u{00A0}2015, v roce 2026 s vámi nežije, —",
    ]

    /// What is wrong with the dialog `sheet` of `window`, in words: it is not 620 points wide, it is taller than the
    /// window, or one of its longer texts is missing, out of it, or lower than it needs to be at its width.
    private func problems(ofDialog sheet: NSWindow, in window: NSWindow) -> [String] {
        var found: [String] = []
        if (sheet.frame.width - 620).magnitude > 1 {
            found.append("The sheet is \(sheet.frame.width) points wide")
        }
        if sheet.frame.height > window.frame.height {
            found.append("The sheet is \(sheet.frame.height) points tall, the window \(window.frame.height)")
        }
        let texts: [(prefix: String, font: Font)] = [
            (ChildDialogModel.orderNote, .callout), (ChildDialogModel.studiesNote, .callout),
            (Self.janInTheDialog, .body.weight(.semibold)),
        ]
        let room = sheet.frame
        for (prefix, font) in texts {
            guard let frame = frameOfText(startingWith: prefix, in: sheet) else {
                found.append("No text \(prefix)")
                continue
            }
            found += problems(ofText: prefix, frame: frame, font: font, within: room, in: sheet)
        }
        if let message = frameOfText(startingWith: ChildDialogModel.removalMessage(year: 2026), in: sheet) {
            found += problems(
                ofText: ChildDialogModel.removalMessage(year: 2026), frame: message, font: .callout, within: room,
                in: sheet)
        }
        return found
    }

    /// What is wrong with the text that begins with `prefix`, at `frame` in the coordinates of the screen: it is not
    /// within `room`, or it is lower than the whole text needs at its width in `font`.
    private func problems(
        ofText prefix: String, frame: CGRect, font: Font, within room: CGRect, in window: NSWindow
    ) -> [String] {
        var found: [String] = []
        if frame.minX < room.minX - 0.5 || frame.maxX > room.maxX + 0.5 || frame.minY < room.minY - 0.5
            || frame.maxY > room.maxY + 0.5
        {
            found.append("The text \(prefix) is not within its room: \(frame), the room \(room)")
        }
        let whole = wholeText(startingWith: prefix, in: window) ?? prefix
        let text = Text(verbatim: whole).font(font).frame(width: frame.width)
        let needed = NSHostingView(rootView: text.fixedSize(horizontal: false, vertical: true)).fittingSize.height
        if frame.height + 1 < needed {
            found.append("The text \(prefix) is \(frame.height) points tall, it needs \(needed)")
        }
        return found
    }

    /// The whole text that VoiceOver reads for the first text of `window` that begins with `prefix`.
    private func wholeText(startingWith prefix: String, in window: NSWindow) -> String? {
        accessibilityReadings(in: window).first { $0.hasPrefix(prefix) }
    }

    // MARK: Odběratelé

    /// Odběratelé fits the window at the least room, at a large size and at the least room again, with the detail of a
    /// client closed and open, on the data of `EditorFixture`: Nový odběratel stands at the right margin of the page
    /// above the card of the table, which reaches down to the bottom margin of the page, and the detail stands beside
    /// the card, as Faktury lays its page out (`problems(ofOdberateleIn:detailOpen:)`).
    @Test(arguments: [false, true])
    func odberateleFitTheWindowAtTheLeastRoomAndAtALargeSize(detailOpen: Bool) async throws {
        try await EditorFixture.with { f in
            try await withAppWindow(of: f.app, size: AppWindowSize.minimum) { window in
                f.app.screen = .clients
                try await withAccessibilityElements {
                    try await waitUntil { clientRows(in: window).count == 3 }
                    if detailOpen {
                        press(try #require(clientRow(named: "Bravo Labs, Inc.", in: window)))
                        try await waitUntil { clientDetailFrame(in: window) != nil }
                    }

                    try await expectSettled(window) { problems(ofOdberateleIn: window, detailOpen: detailOpen) }
                    window.setContentSize(AppWindowSize.large)
                    try await expectSettled(window) { problems(ofOdberateleIn: window, detailOpen: detailOpen) }
                    window.setContentSize(AppWindowSize.minimum)
                    try await expectSettled(window) { problems(ofOdberateleIn: window, detailOpen: detailOpen) }
                }
            }
        }
    }

    // MARK: The table of Odběratelé

    /// The table of Odběratelé is as wide as its card, with nothing to scroll sideways, in a large window and in the
    /// least window while the detail is closed: the card of the least window is 828 points wide, more than the least
    /// width of the table (`ClientTableColumns`). The card starts with its summary row, above the names of the columns
    /// (32 points), and its rows are one line each, 40 points high, whatever they say: among the clients of the fixture
    /// stand one that says as little as can be and one whose name is far too long for its column. With the detail open
    /// (340 points) the card of the least window is 472 points wide, narrower than the table: the detail stays beside
    /// the card, and the table keeps its least width and scrolls sideways in the card under the summary row, as the
    /// table of Faktury does. A large window holds the table and the detail side by side again.
    @Test func theClientTableFillsItsCardAndScrollsSidewaysBesideTheDetailInTheLeastWindow() async throws {
        try await EditorFixture.with { f in
            try await f.database.saveClient(Client(name: "Bez údajů", country: ""))
            let longName = String(repeating: "Obchodní společnost s velmi dlouhým názvem ", count: 4)
            try await f.database.saveClient(
                Client(name: longName, city: "Hradec Králové", country: "SK", ico: "35709332"))
            await f.app.didWrite()
            try await withAppWindow(of: f.app, size: AppWindowSize.large) { window in
                try await withAccessibilityElements {
                    f.app.screen = .clients
                    try await waitUntil { clientRows(in: window).count == 5 }

                    // A large window: its card is 1 328 points wide.
                    try await expectSettled(window) {
                        problems(ofTheClientRowsIn: window, count: 5)
                            + problems(ofTheClientTableFillingItsCardIn: window)
                            + problems(ofOdberateleIn: window, detailOpen: false)
                            + problems(ofTheSummaryAndTheRowsOf: clientList(in: window), rows: clientRows(in: window))
                    }
                    #expect((try clientTableWidth(in: window) - 1_328).magnitude <= 1)

                    // The least window: its card of 828 points holds the table, so nothing scrolls sideways.
                    window.setContentSize(AppWindowSize.minimum)
                    try await expectSettled(window) {
                        problems(ofTheClientRowsIn: window, count: 5)
                            + problems(ofTheClientTableFillingItsCardIn: window)
                            + problems(ofOdberateleIn: window, detailOpen: false)
                    }
                    let card = try #require(clientTableScrollView(in: window)).contentView.bounds.width
                    #expect((card - 828).magnitude <= 1)

                    // The detail open: the card of 472 points is narrower than the table, which keeps its least
                    // width and scrolls sideways, under the summary row, which stays as wide as the card.
                    press(try #require(clientRow(named: "Bravo Labs, Inc.", in: window)))
                    try await waitUntil { clientDetailFrame(in: window) != nil }
                    try await expectSettled(window) {
                        problems(ofTheClientRowsIn: window, count: 5)
                            + problems(ofTheClientTableScrollingSidewaysIn: window)
                            + problems(ofOdberateleIn: window, detailOpen: true)
                            + problems(ofTheSummaryAndTheRowsOf: clientList(in: window), rows: clientRows(in: window))
                    }
                    let narrow = try #require(clientTableScrollView(in: window)).contentView.bounds.width
                    #expect((narrow - 472).magnitude <= 1)

                    // A large window again: the card beside the detail, 972 points, holds the table.
                    window.setContentSize(AppWindowSize.large)
                    try await expectSettled(window) {
                        problems(ofTheClientRowsIn: window, count: 5)
                            + problems(ofTheClientTableFillingItsCardIn: window)
                            + problems(ofOdberateleIn: window, detailOpen: true)
                    }
                    #expect((try clientTableWidth(in: window) - 972).magnitude <= 1)
                }
            }
        }
    }

    /// A click on a row of the table of Odběratelé selects it and opens the detail of its client beside the table, not
    /// the form of the client; nothing is selected before. The detail is titled with the name of the client and has
    /// Nová faktura and Upravit, buttons of 28 points. Upravit opens the form of the client, "Upravit odběratele", as a
    /// sheet, and Zrušit closes it with the detail still open. A second click on the row closes the detail, and so does
    /// its ✕, "Zavřít detail"; a click on another row opens the detail of that client. Nová faktura of the detail opens
    /// the editor on a blank invoice for its client, on Faktury. VoiceOver presses the rows and the buttons as a click
    /// does (`aMouseClickAnywhereOnAClientRowOpensItsDetailAndNoForm` clicks a row with the mouse).
    @Test func aClickOnAClientRowOpensItsDetailAndNotItsForm() async throws {
        // The sheet takes the focus of the window, so the test takes its turn among the tests that type.
        try await whileTypingAlone {
            try await EditorFixture.with { f in
                try await withAppWindow(of: f.app, size: AppWindowSize.large) { window in
                    f.app.screen = .clients
                    try await withAccessibilityElements {
                        try await waitUntil { clientRows(in: window).count == 3 }
                        try await layOut(window)
                        #expect(selectedClientRow(in: window) == nil)
                        #expect(clientDetailFrame(in: window) == nil)
                        let size = window.frame.size

                        press(try #require(clientRow(named: "Bravo Labs, Inc.", in: window)))
                        try await waitUntil { clientDetailFrame(in: window) != nil }
                        #expect(window.attachedSheet == nil)
                        #expect(isClientSelected("Bravo Labs, Inc.", in: window))
                        #expect(clientDetailShows("Bravo Labs, Inc.", in: window))
                        #expect(window.frame.size == size)
                        for label in ["Nová faktura pro Bravo Labs, Inc.", "Upravit", "Zavřít detail"] {
                            let height = buttonFrame(label, in: window)?.height ?? 0
                            #expect((height - DesignMetrics.smallControlHeight).magnitude < 0.5, "\(label): \(height)")
                        }

                        // Upravit opens the form of the client; Zrušit closes it, and the detail stays.
                        press(try #require(accessibilityButton(labelled: "Upravit", in: window)))
                        try await waitUntil { window.attachedSheet != nil }
                        let sheet = try #require(window.attachedSheet)
                        // The title of the sheet is a heading, which VoiceOver reads by its label.
                        try await waitUntil { accessibilityElement(labelled: "Upravit odběratele", in: sheet) != nil }
                        #expect(showsText("Bravo Labs, Inc.", in: sheet))
                        press(try #require(accessibilityButton(labelled: "Zrušit", in: sheet)))
                        try await waitUntil { window.attachedSheet == nil }
                        #expect(clientDetailShows("Bravo Labs, Inc.", in: window))

                        // A second click on the row closes the detail.
                        press(try #require(clientRow(named: "Bravo Labs, Inc.", in: window)))
                        try await waitUntil { clientDetailFrame(in: window) == nil }
                        #expect(selectedClientRow(in: window) == nil)

                        // Another row opens the detail of its client, and the ✕ closes it.
                        press(try #require(clientRow(named: "Cetus Data s.r.o.", in: window)))
                        try await waitUntil { clientDetailShows("Cetus Data s.r.o.", in: window) }
                        #expect(isClientSelected("Cetus Data s.r.o.", in: window))
                        press(try #require(accessibilityButton(labelled: "Zavřít detail", in: window)))
                        try await waitUntil { clientDetailFrame(in: window) == nil }
                        #expect(selectedClientRow(in: window) == nil)

                        // Nová faktura of the detail starts a blank invoice for its client, and no form.
                        press(try #require(clientRow(named: "Cetus Data s.r.o.", in: window)))
                        try await waitUntil { clientDetailFrame(in: window) != nil }
                        let newInvoice = "Nová faktura pro Cetus Data s.r.o."
                        press(try #require(accessibilityButton(labelled: newInvoice, in: window)))
                        try await waitUntil { f.app.screen == .invoices }
                        #expect(f.app.editorRequest == .new(templateID: nil, clientID: f.cetusID))
                        #expect(window.attachedSheet == nil)
                    }
                }
            }
        }
    }

    /// A mouse click anywhere on a row of the table of Odběratelé opens the detail of its client and no form, and a
    /// second click on the row closes the detail: on the name, on the chip of the currency, on the templates, on the
    /// money received, and in the margin at either end of the row. The detail narrows the card of the table, so each
    /// place is found again in the row as it is once the detail is open.
    @Test func aMouseClickAnywhereOnAClientRowOpensItsDetailAndNoForm() async throws {
        // The click makes the window the key window, so the test takes its turn among the tests that type.
        try await whileTypingAlone {
            try await EditorFixture.with { f in
                try await withAppWindow(of: f.app, size: AppWindowSize.large) { window in
                    f.app.screen = .clients
                    try await withAccessibilityElements {
                        try await waitUntil { clientRows(in: window).count == 3 }
                        // Across the middle of the row, from its leading edge or back from its trailing edge: the
                        // name, the chip of the currency, the templates, the money received, and the margins.
                        let places: [(String, (CGRect) -> CGFloat)] = [
                            ("the margin before the name", { $0.minX + 6 }),
                            ("the name", { $0.minX + 40 }),
                            ("the chip of the currency", { $0.minX + $0.width * 0.4 }),
                            ("the templates", { $0.minX + $0.width * 0.7 }),
                            ("the money received", { $0.maxX - 40 }),
                            ("the margin after the money received", { $0.maxX - 6 }),
                        ]
                        @MainActor func bravoRowFrame(in window: NSWindow) -> CGRect? {
                            clientRow(named: "Bravo Labs, Inc.", in: window)?.accessibilityFrame?()
                        }
                        for (place, x) in places {
                            try await layOut(window)
                            let closed = try #require(bravoRowFrame(in: window))
                            try await click(atX: x(closed), y: closed.midY, in: window)
                            try await waitUntil { clientDetailFrame(in: window) != nil }
                            #expect(isClientSelected("Bravo Labs, Inc.", in: window), "a click on \(place)")
                            #expect(window.attachedSheet == nil, "a click on \(place)")

                            try await layOut(window)
                            let open = try #require(bravoRowFrame(in: window))
                            try await click(atX: x(open), y: open.midY, in: window)
                            try await waitUntil { clientDetailFrame(in: window) == nil }
                            #expect(selectedClientRow(in: window) == nil, "a second click on \(place)")
                        }
                        #expect(window.attachedSheet == nil)
                        #expect(f.app.screen == .clients)
                    }
                }
            }
        }
    }

    /// A client saved in the form of Nový odběratel becomes the selected one: once the sheet closes, its row is
    /// selected and shown whole, and the detail beside the table is that of the new client. The card of the least
    /// window shows a dozen rows, so with twenty clients added to the three of the fixture the row of the new client,
    /// whose name comes last, is far below them until the rows scroll to it.
    @Test func aClientSavedInTheFormOfNovyOdberatelBecomesTheSelectedOneAndItsRowIsShown() async throws {
        // The sheet takes the focus of the window, and the test types into it.
        try await whileTypingAlone {
            try await EditorFixture.with { f in
                for number in 1...20 {
                    try await f.database.saveClient(Client(name: "Klient \(number)", city: "Brno"))
                }
                await f.app.didWrite()
                try await withAppWindow(of: f.app, size: AppWindowSize.minimum) { window in
                    f.app.screen = .clients
                    try await withAccessibilityElements {
                        try await waitUntil { clientRows(in: window).count == 23 }

                        press(try #require(accessibilityButton(labelled: "Nový odběratel", in: window)))
                        try await waitUntil { window.attachedSheet != nil }
                        let sheet = try #require(window.attachedSheet)
                        try await waitUntil { textField(labelled: "Název", in: sheet) != nil }
                        let name = try #require(textField(labelled: "Název", in: sheet))
                        try type("Žluťoučký kůň s.r.o.", into: name, in: sheet)
                        press(try #require(accessibilityButton(labelled: "Uložit odběratele", in: sheet)))
                        try await waitUntil { window.attachedSheet == nil }

                        try await waitUntil { isClientSelected("Žluťoučký kůň s.r.o.", in: window) }
                        #expect(clientRows(in: window).count == 24)
                        #expect(clientDetailShows("Žluťoučký kůň s.r.o.", in: window))
                        try await expectSettled(window) { problems(ofTheSelectedClientRowShownIn: window) }
                    }
                }
            }
        }
    }

    /// The selected client stays selected when the year in the toolbar changes, and its row says what the client paid
    /// in the year shown: Bravo was paid 305 727 Kč in 2026 and nothing in 2025, which its row then leaves out.
    @Test func theSelectedClientStaysSelectedWhenTheYearChanges() async throws {
        try await EditorFixture.with { f in
            try await withAppWindow(of: f.app, size: AppWindowSize.large) { window in
                f.app.screen = .clients
                try await withAccessibilityElements {
                    try await waitUntil { clientRows(in: window).count == 3 }
                    press(try #require(clientRow(named: "Bravo Labs, Inc.", in: window)))
                    try await waitUntil { clientDetailShows("Bravo Labs, Inc.", in: window) }
                    let received = "Přijato 2026 305\u{00A0}727\u{00A0}Kč"
                    #expect(clientRowLabel(named: "Bravo Labs, Inc.", in: window)?.contains(received) == true)

                    f.app.selectYear(2025)
                    try await waitUntil {
                        clientRowLabel(named: "Bravo Labs, Inc.", in: window)?.contains("Přijato") == false
                    }
                    #expect(isClientSelected("Bravo Labs, Inc.", in: window))
                    #expect(clientDetailShows("Bravo Labs, Inc.", in: window))

                    f.app.selectYear(2026)
                    try await waitUntil {
                        clientRowLabel(named: "Bravo Labs, Inc.", in: window)?.contains(received) == true
                    }
                    #expect(isClientSelected("Bravo Labs, Inc.", in: window))
                    #expect(clientDetailShows("Bravo Labs, Inc.", in: window))
                }
            }
        }
    }

    /// The rows of the table of Odběratelé scroll up and down in its card, under the names of the columns, and the
    /// table scrolls sideways where it is wider than its card, as the table of Faktury does. A wheel over the rows
    /// moves what can move: an up-and-down one moves the rows and leaves the table where it is sideways, and a sideways
    /// one moves the table, the names of the columns with the rows, and leaves the rows where they are up and down.
    @Test func aWheelOverTheClientTableScrollsItsRowsUpAndDownAndTheTableSideways() async throws {
        try await EditorFixture.with { f in
            // Clients enough for more rows than the card of the least window shows.
            for number in 1...20 {
                try await f.database.saveClient(Client(name: "Klient \(number)", city: "Brno"))
            }
            await f.app.didWrite()
            try await withAppWindow(of: f.app, size: AppWindowSize.minimum) { window in
                f.app.screen = .clients
                try await withAccessibilityElements {
                    try await waitUntil { clientRows(in: window).count == 23 }
                    // The detail beside the card of the least window leaves the card narrower than the table.
                    press(try #require(clientRow(named: "Alfa Systems s.r.o.", in: window)))
                    try await waitUntil { clientDetailFrame(in: window) != nil }
                }
                try await expectSettled(window) { problems(ofTheClientTableScrollingSidewaysIn: window) }
                let table = try #require(clientTableScrollView(in: window))
                let rows = try #require(clientRowsScrollView(in: window))
                let rows0 = rows.contentView.bounds.origin
                #expect(table.contentView.bounds.origin == .zero)

                rows.scrollWheel(with: try wheelEvent(upAndDown: -80, sideways: 0))
                try await waitUntil { rows.contentView.bounds.origin != rows0 }
                let rows1 = rows.contentView.bounds.origin
                #expect(rows1.x == rows0.x && rows1.y != rows0.y)
                #expect(table.contentView.bounds.origin == .zero)

                rows.scrollWheel(with: try wheelEvent(upAndDown: 0, sideways: -80))
                try await waitUntil { table.contentView.bounds.origin.x != 0 }
                #expect(table.contentView.bounds.origin.y == 0)
                #expect(rows.contentView.bounds.origin == rows1)
            }
        }
    }

    /// A client that the import created and nobody has edited since is a row like any other: nothing on the screen says
    /// how it came into the app.
    @Test func aClientCreatedByTheImportHasNoMarkOnItsRow() async throws {
        try await EditorFixture.with { f in
            try await f.database.saveClient(ClientsFixture.imported)
            await f.app.didWrite()
            try await withAppWindow(of: f.app, size: AppWindowSize.large) { window in
                f.app.screen = .clients
                try await withAccessibilityElements {
                    try await waitUntil { clientRows(in: window).count == 4 }

                    // Neither a text of its own nor a part of what VoiceOver reads for the row.
                    let row = try #require(clientRow(named: "Delta Import GmbH", in: window))
                    let said = row.accessibilityLabel?() ?? ""
                    #expect(!said.localizedCaseInsensitiveContains("vytvořeno"), "\(said)")
                    #expect(frameOfText(startingWith: "vytvořeno", in: window) == nil)
                    #expect(!showsText("vytvořeno importem", in: window))
                }
            }
        }
    }

    // MARK: The detail of a client

    /// A detail of a client that fits beside the table is as high as its content, as the prototype's panel is, and no
    /// higher: in a large window the detail of Cetus, which has no template, starts with the card of the table and
    /// ends 20 points under the sentence that says what a template does, well above the bottom of that card, and it
    /// has nothing to scroll.
    @Test func aClientDetailThatFitsIsAsHighAsItsContentAndShorterThanTheTable() async throws {
        try await EditorFixture.with { f in
            try await withAppWindow(of: f.app, size: AppWindowSize.large) { window in
                f.app.screen = .clients
                try await withAccessibilityElements {
                    try await waitUntil { clientRows(in: window).count == 3 }
                    press(try #require(clientRow(named: "Cetus Data s.r.o.", in: window)))
                    try await waitUntil { frameOfText(startingWith: "Zatím žádná šablona.", in: window) != nil }
                    try await expectSettled(window) { problems(ofOdberateleIn: window, detailOpen: true) }

                    let detail = try #require(clientDetailFrame(in: window))
                    let table = try #require(clientTableCardFrame(in: window))
                    let empty = try #require(frameOfText(startingWith: "Zatím žádná šablona.", in: window))
                    let last = window.convertFromScreen(empty)
                    #expect(detail.height < table.height - 50, "The detail \(detail) is not shorter than \(table)")
                    #expect((detail.maxY - table.maxY).magnitude <= 1, "\(detail) does not start with \(table)")
                    #expect((last.minY - detail.minY - 20).magnitude <= 1.5, "\(last) in \(detail)")
                    #expect(clientDetailOverflow(in: window) <= 0.5, "It scrolls \(clientDetailOverflow(in: window))")
                }
            }
        }
    }

    /// A detail of a client whose content is higher than the card of the table is as high as that card and no higher,
    /// and the part of the content that does not fit scrolls inside it: in the least window the detail of Bravo with
    /// a dozen templates starts with the card of the table and ends where it ends, and its content is higher than the
    /// card shows.
    @Test func aClientDetailHigherThanTheTableIsCappedAtItAndScrollsInsideIt() async throws {
        try await EditorFixture.with { f in
            for number in 1...11 {
                var template = f.dollarTemplate
                template.id = 0
                template.name = "Software development \(number)"
                try await f.database.saveTemplate(template)
            }
            await f.app.didWrite()
            try await withAppWindow(of: f.app, size: AppWindowSize.minimum) { window in
                f.app.screen = .clients
                try await withAccessibilityElements {
                    try await waitUntil { clientRows(in: window).count == 3 }
                    press(try #require(clientRow(named: "Bravo Labs, Inc.", in: window)))
                    let last = "Upravit šablonu Software development 11"
                    try await waitUntil { accessibilityButton(labelled: last, in: window) != nil }
                    try await expectSettled(window) { problems(ofOdberateleIn: window, detailOpen: true) }

                    let detail = try #require(clientDetailFrame(in: window))
                    let table = try #require(clientTableCardFrame(in: window))
                    #expect((detail.maxY - table.maxY).magnitude <= 1, "\(detail) does not start with \(table)")
                    #expect((detail.minY - table.minY).magnitude <= 1, "\(detail) does not end with \(table)")
                    #expect(clientDetailOverflow(in: window) > 50, "It scrolls \(clientDetailOverflow(in: window))")
                }
            }
        }
    }

    /// The figure of a client that has paid nothing in the year, "0 Kč" for Alfa, is muted, in tertiary text, with no
    /// pixel of it in the colour of text, and that of a client that has paid, 305 727 Kč for Bravo, is in the colour
    /// of text. The window is light, whatever the Mac's appearance is.
    @Test func theFigureOfAClientThatPaidNothingIsInTertiaryText() async throws {
        try await EditorFixture.with { f in
            try await withAppWindow(of: f.app, size: AppWindowSize.large) { window in
                window.appearance = NSAppearance(named: .aqua)
                f.app.screen = .clients
                let text = try OffscreenPicture.bytes(of: Palette.text, in: .light)
                let tertiary = try OffscreenPicture.bytes(of: Palette.text3, in: .light)
                try await withAccessibilityElements {
                    try await waitUntil { clientRows(in: window).count == 3 }
                    let figures = [
                        ("Alfa Systems s.r.o.", "0\u{00A0}Kč", true),
                        ("Bravo Labs, Inc.", "305\u{00A0}727\u{00A0}Kč", false),
                    ]
                    for (name, figure, muted) in figures {
                        press(try #require(clientRow(named: name, in: window)))
                        try await waitUntil { frameOfText(startingWith: figure, in: window) != nil }
                        try await layOut(window)
                        let onScreen = try #require(frameOfText(startingWith: figure, in: window))
                        let frame = window.convertFromScreen(onScreen)
                        let height = try #require(window.contentView).bounds.height
                        // The picture counts its points from the top left, the window from the bottom left.
                        let region = CGRect(
                            x: frame.minX, y: height - frame.maxY, width: frame.width, height: frame.height)
                        let picture = try OffscreenPicture(of: window)

                        if muted {
                            #expect(picture.count(near: text, in: region, by: 8) == 0, "\(figure) is not muted")
                            #expect(picture.count(near: tertiary, in: region, by: 2) > 20, "\(figure) is not tertiary")
                        } else {
                            #expect(picture.count(near: text, in: region, by: 2) > 20, "\(figure) is muted")
                        }
                    }
                }
            }
        }
    }

    /// Nová šablona in the detail of a client opens the form of a new template for that client: the chip of Cetus is
    /// chosen in it, not the one of Alfa, which comes first. Once the template is saved, the sheet closes, Cetus stays
    /// selected and its detail has a panel for the new template in place of the sentence that said it had none.
    @Test func novaSablonaInTheDetailOfAClientOpensTheFormOfATemplateForThatClient() async throws {
        // The sheet takes the focus of the window, and the test types into it.
        try await whileTypingAlone {
            try await EditorFixture.with { f in
                try await withAppWindow(of: f.app, size: AppWindowSize.large) { window in
                    f.app.screen = .clients
                    try await withAccessibilityElements {
                        try await waitUntil { clientRows(in: window).count == 3 }
                        press(try #require(clientRow(named: "Cetus Data s.r.o.", in: window)))
                        try await waitUntil { frameOfText(startingWith: "Zatím žádná šablona.", in: window) != nil }

                        press(try #require(accessibilityButton(labelled: "Nová šablona", in: window)))
                        try await waitUntil { window.attachedSheet != nil }
                        let sheet = try #require(window.attachedSheet)
                        try await waitUntil { accessibilityButton(labelled: "Alfa Systems s.r.o.", in: sheet) != nil }
                        let cetus = try #require(accessibilityButton(labelled: "Cetus Data s.r.o.", in: sheet))
                        let alfa = try #require(accessibilityButton(labelled: "Alfa Systems s.r.o.", in: sheet))
                        #expect(cetus.isAccessibilitySelected?() == true)
                        #expect(alfa.isAccessibilitySelected?() != true)

                        let name = try #require(textField(labelled: "Název šablony", in: sheet))
                        try type("Konzultace", into: name, in: sheet)
                        press(try #require(accessibilityButton(labelled: "Uložit šablonu", in: sheet)))
                        try await waitUntil { window.attachedSheet == nil }

                        let newPanel = "Vystavit podle šablony Konzultace"
                        try await waitUntil { accessibilityButton(labelled: newPanel, in: window) != nil }
                        #expect(isClientSelected("Cetus Data s.r.o.", in: window))
                        #expect(clientDetailShows("Cetus Data s.r.o.", in: window))
                        #expect(frameOfText(startingWith: "Zatím žádná šablona.", in: window) == nil)
                    }
                }
            }
        }
    }

    /// Where the name of a template fills its line, it ends 8 points before the amount of the template, the room the
    /// prototype leaves between them, and not 16: a name of narrow letters with no space, which breaks after any letter
    /// and so fills its lines but the last (to less than the width of a letter), on the panel of a template of 999 USD.
    @Test func aLongNameOfATemplateEnds8PointsBeforeItsAmount() async throws {
        try await EditorFixture.with { f in
            var template = f.dollarTemplate
            template.id = 0
            template.name = String(repeating: "i", count: 120)
            template.items = [TemplateItem(description: "Konzultace", quantity: 1, unit: "h", unitPriceMinor: 99_900)]
            try await f.database.saveTemplate(template)
            await f.app.didWrite()
            try await withAppWindow(of: f.app, size: AppWindowSize.large) { window in
                f.app.screen = .clients
                try await withAccessibilityElements {
                    try await waitUntil { clientRows(in: window).count == 3 }
                    press(try #require(clientRow(named: "Bravo Labs, Inc.", in: window)))
                    try await waitUntil { frameOfText(startingWith: template.name, in: window) != nil }
                    try await layOut(window)

                    let name = try #require(frameOfText(startingWith: template.name, in: window))
                    let amount = try #require(frameOfText(startingWith: "999,00\u{00A0}USD", in: window))
                    let gap = amount.minX - name.maxX
                    #expect(gap >= 7.5 && gap < 12, "The name ends \(gap) points before the amount: \(name), \(amount)")
                }
            }
        }
    }

    /// The two buttons of the panel of a template, Vystavit podle šablony and Upravit, share one line in the detail of
    /// its client, which is as wide as a detail panel, 6 points apart: the panel of Bravo's template "Software
    /// development" in the least window.
    @Test func theTwoButtonsOfATemplatePanelShareOneLine() async throws {
        try await EditorFixture.with { f in
            try await withAppWindow(of: f.app, size: AppWindowSize.minimum) { window in
                f.app.screen = .clients
                try await withAccessibilityElements {
                    try await waitUntil { clientRows(in: window).count == 3 }
                    press(try #require(clientRow(named: "Bravo Labs, Inc.", in: window)))
                    let use = "Vystavit podle šablony Software development"
                    let edit = "Upravit šablonu Software development"
                    try await waitUntil { buttonFrame(edit, in: window) != nil }
                    try await layOut(window)

                    let first = try #require(buttonFrame(use, in: window))
                    let second = try #require(buttonFrame(edit, in: window))
                    #expect((first.midY - second.midY).magnitude < 0.5, "Not on one line: \(first), \(second)")
                    #expect((second.minX - first.maxX - 6).magnitude < 0.5, "Not 6 points apart: \(first), \(second)")
                }
            }
        }
    }

    /// The panel of a template in the detail of its client: Upravit opens the form of the template, "Upravit šablonu",
    /// as a sheet, and Zrušit closes it with the detail still open; Vystavit podle šablony opens the editor on a new
    /// invoice made from the template, on Faktury, and no sheet. The two buttons are 28 points high, as the buttons
    /// inside a card are.
    @Test func theButtonsOfATemplateInTheDetailEditItAndStartAnInvoiceFromIt() async throws {
        // The sheet takes the focus of the window, so the test takes its turn among the tests that type.
        try await whileTypingAlone {
            try await EditorFixture.with { f in
                try await withAppWindow(of: f.app, size: AppWindowSize.large) { window in
                    f.app.screen = .clients
                    try await withAccessibilityElements {
                        try await waitUntil { clientRows(in: window).count == 3 }
                        press(try #require(clientRow(named: "Bravo Labs, Inc.", in: window)))
                        let edit = "Upravit šablonu Software development"
                        let use = "Vystavit podle šablony Software development"
                        try await waitUntil { accessibilityButton(labelled: use, in: window) != nil }
                        for label in [use, edit] {
                            let height = buttonFrame(label, in: window)?.height ?? 0
                            #expect((height - DesignMetrics.smallControlHeight).magnitude < 0.5, "\(label): \(height)")
                        }

                        press(try #require(accessibilityButton(labelled: edit, in: window)))
                        try await waitUntil { window.attachedSheet != nil }
                        let sheet = try #require(window.attachedSheet)
                        // The title of the sheet is a heading, which VoiceOver reads by its label; the chips of the
                        // clients come once the form has loaded them.
                        try await waitUntil { accessibilityElement(labelled: "Upravit šablonu", in: sheet) != nil }
                        try await waitUntil { accessibilityButton(labelled: "Bravo Labs, Inc.", in: sheet) != nil }
                        let bravo = try #require(accessibilityButton(labelled: "Bravo Labs, Inc.", in: sheet))
                        #expect(bravo.isAccessibilitySelected?() == true)
                        press(try #require(accessibilityButton(labelled: "Zrušit", in: sheet)))
                        try await waitUntil { window.attachedSheet == nil }
                        #expect(clientDetailShows("Bravo Labs, Inc.", in: window))

                        press(try #require(accessibilityButton(labelled: use, in: window)))
                        try await waitUntil { f.app.screen == .invoices }
                        #expect(f.app.editorRequest == .new(templateID: f.dollarTemplate.id, clientID: nil))
                        #expect(window.attachedSheet == nil)
                    }
                }
            }
        }
    }

    /// A wheel event of the mouse that scrolls by `upAndDown` points up and down and by `sideways` points sideways.
    private func wheelEvent(upAndDown: Int32, sideways: Int32) throws -> NSEvent {
        let event = try #require(
            CGEvent(
                scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 2, wheel1: upAndDown, wheel2: sideways,
                wheel3: 0))
        return try #require(NSEvent(cgEvent: event))
    }

    /// Clicks the left mouse button at the point `x`, `y` of the screen, as the mouse does: a press and its release.
    /// The window is made the key window first, as a person clicks in the key window, though a test of another suite
    /// may have made its own window the key one meanwhile.
    private func click(atX x: CGFloat, y: CGFloat, in window: NSWindow) async throws {
        window.makeKeyAndOrderFront(nil)
        let point = window.convertFromScreen(CGRect(x: x, y: y, width: 0, height: 0)).origin
        for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
            let event = try #require(
                NSEvent.mouseEvent(
                    with: type, location: point, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                    windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1,
                    pressure: type == .leftMouseDown ? 1 : 0))
            window.sendEvent(event)
            try await Task.sleep(for: .milliseconds(60))
        }
    }

    /// The table of Odběratelé in `window` as VoiceOver reads it, "Seznam odběratelů": its card, with the summary row
    /// and the table under it. Nil while the page has no table, and while the views make no accessibility elements.
    private func clientList(in window: NSWindow) -> AnyObject? {
        accessibilityElement(labelled: "Seznam odběratelů", in: window)
    }

    /// The rows of the table of Odběratelé in `window`, from the top: the buttons in it that VoiceOver reads with the
    /// name of a client and the rest of its row. (The arrows of a scroller are buttons with no label.) Empty while the
    /// views make no accessibility elements.
    private func clientRows(in window: NSWindow) -> [AnyObject] {
        guard let list = clientList(in: window) else { return [] }
        return descendants(of: list).filter { element in
            element.accessibilityRole?() == .button && !(element.accessibilityLabel?() ?? "").isEmpty
        }
    }

    /// The row of the client called `name` in the table of Odběratelé in `window`.
    private func clientRow(named name: String, in window: NSWindow) -> AnyObject? {
        clientRows(in: window).first { ($0.accessibilityLabel?() ?? "").hasPrefix(name + ",") }
    }

    /// What VoiceOver reads for the row of the client called `name` in the table of Odběratelé in `window`, or nil
    /// where the table has no such row.
    private func clientRowLabel(named name: String, in window: NSWindow) -> String? {
        clientRow(named: name, in: window).flatMap { $0.accessibilityLabel?() ?? nil }
    }

    /// The selected row of the table of Odběratelé in `window`: the one VoiceOver reads as selected. Nil when no row is
    /// selected.
    private func selectedClientRow(in window: NSWindow) -> AnyObject? {
        clientRows(in: window).first { $0.isAccessibilitySelected?() == true }
    }

    /// What is wrong with where the selected row of the table of Odběratelé is in `window`: it is not wholly within the
    /// part of the rows that the table shows, the frame of the scroll area of the rows, under the names of the columns,
    /// which is the last of the two scroll areas in the card (the first scrolls the names and the rows sideways).
    /// Empty when it is. Needs the accessibility elements.
    private func problems(ofTheSelectedClientRowShownIn window: NSWindow) -> [String] {
        guard let row = selectedClientRow(in: window)?.accessibilityFrame?(), let list = clientList(in: window),
            let shown = descendants(of: list).last(where: { $0.accessibilityRole?() == .scrollArea })?
                .accessibilityFrame?()
        else {
            return ["No row is selected, or the table shows no rows"]
        }
        if row.minY < shown.minY - 0.5 || row.maxY > shown.maxY + 0.5 {
            return ["The selected row \(row) is not within the rows that the table shows, \(shown)"]
        }
        return []
    }

    /// Whether the selected row of the table of Odběratelé in `window` is that of the client called `name`.
    private func isClientSelected(_ name: String, in window: NSWindow) -> Bool {
        (selectedClientRow(in: window)?.accessibilityLabel?() ?? "").hasPrefix(name + ",")
    }

    /// The frame of the card of the table of Odběratelé in `window`, in the coordinates of the window: the summary row
    /// and the table under it. Nil while the page has no table, and while the views make no accessibility elements.
    private func clientTableCardFrame(in window: NSWindow) -> CGRect? {
        guard let frame = clientList(in: window)?.accessibilityFrame?() else { return nil }
        return window.convertFromScreen(frame)
    }

    /// The frame of the card of the detail of Odběratelé in `window`, which VoiceOver reads as "Detail odběratele", in
    /// the coordinates of the window. Nil while no client is selected, and while the views make no accessibility
    /// elements.
    private func clientDetailFrame(in window: NSWindow) -> CGRect? {
        guard let frame = accessibilityElement(labelled: "Detail odběratele", in: window)?.accessibilityFrame?() else {
            return nil
        }
        return window.convertFromScreen(frame)
    }

    /// How much higher than the part of it that the card of the detail of Odběratelé in `window` shows its content is,
    /// which is what scrolls in it (`overflow(ofTheCardFramed:in:)`). Needs the accessibility elements
    /// (`withAccessibilityElements(_:)`).
    private func clientDetailOverflow(in window: NSWindow) -> CGFloat {
        overflow(ofTheCardFramed: clientDetailFrame(in: window), in: window)
    }

    /// Whether the detail of Odběratelé in `window` is that of the client called `name`: VoiceOver reads the name in
    /// it, as its title.
    private func clientDetailShows(_ name: String, in window: NSWindow) -> Bool {
        guard let detail = accessibilityElement(labelled: "Detail odběratele", in: window) else { return false }
        return accessibilityReadings(under: detail).contains(name)
    }

    /// What is wrong with the `count` rows of the table of Odběratelé in `window`, in words: there are not so many, or
    /// one is not 40 points high, the height of a row of one line (to half a point). Empty when each of them is. Needs
    /// the accessibility elements.
    private func problems(ofTheClientRowsIn window: NSWindow, count: Int) -> [String] {
        let heights = clientRows(in: window).compactMap { $0.accessibilityFrame?().height }
        guard heights.count == count else {
            return ["The table has \(heights.count) rows, not \(count)"]
        }
        if heights.contains(where: { ($0 - DataTableMetrics.rowHeight).magnitude > 0.5 }) {
            return ["The rows are not 40 points high: \(heights)"]
        }
        return []
    }

    /// What is wrong with the page of Odběratelé in `window`, in words: the views that stick out of the window; Nový
    /// odběratel not a capsule 32 points high at the right margin of the page (16 points), under the toolbar and 14
    /// points above the card of the table; the card of the table not reaching the bottom margin of the page (24
    /// points), or the table that scrolls sideways not in it. With the detail closed the card reaches the right margin
    /// of the page and no row is selected; with the detail open the card of the detail stands beside it
    /// (`problems(ofTheClientDetail:besideTheTable:in:)`) and a row is selected. Empty when the page is laid out so.
    /// Needs the accessibility elements (`withAccessibilityElements(_:)`).
    private func problems(ofOdberateleIn window: NSWindow, detailOpen: Bool) -> [String] {
        var problems = viewsOutside(window).map { "Outside the window: \($0)" }
        guard let table = clientTableCardFrame(in: window), let scrollView = clientTableScrollView(in: window) else {
            return problems + ["The page has no table"]
        }
        let room = window.contentLayoutRect
        if let button = buttonFrame("Nový odběratel", in: window) {
            if (button.maxX - (room.maxX - 16)).magnitude >= 0.5 {
                problems.append("Nový odběratel does not stand at the right margin of the page: \(button)")
            }
            if (button.height - DesignMetrics.regularControlHeight).magnitude >= 0.5 {
                problems.append("Nový odběratel is \(button.height) points high")
            }
            // The origin of the window is at the bottom left: the top is the largest y.
            if button.maxY > room.maxY + 0.5 {
                problems.append("Nový odběratel reaches under the toolbar: \(button)")
            }
            if (button.minY - table.maxY - 14).magnitude >= 0.5 {
                problems.append("Nový odběratel does not stand 14 points above the table: \(button), \(table)")
            }
        } else {
            problems.append("The page has no Nový odběratel")
        }
        if (table.minY - 24).magnitude >= 0.5 {
            problems.append("The card of the table does not end at the bottom margin of the page: \(table)")
        }
        let scrolled = frameInWindow(scrollView)
        if !table.insetBy(dx: -0.5, dy: -0.5).contains(scrolled) {
            problems.append("The table that scrolls sideways is not in its card: \(scrolled), \(table)")
        }
        let detail = clientDetailFrame(in: window)
        if detailOpen {
            guard let detail else {
                return problems + ["The detail is not open"]
            }
            problems += self.problems(ofTheClientDetail: detail, besideTheTable: table, in: room)
            if selectedClientRow(in: window) == nil {
                problems.append("No row of the table is selected")
            }
        } else {
            if let detail {
                problems.append("The detail is open: \(detail)")
            }
            if (table.maxX - (room.maxX - 16)).magnitude >= 0.5 {
                problems.append("The card of the table does not reach the right margin of the page: \(table)")
            }
            if selectedClientRow(in: window) != nil {
                problems.append("A row of the table is selected")
            }
        }
        return problems
    }

    /// What is wrong with the card of the detail of a client, `detail`, beside the card of the table, `table`, in the
    /// room of the page `room`, all in the coordinates of the window: the detail is as wide as a detail panel (340
    /// points, `DetailPanelMetrics.width`) at the right margin of the page (16 points), starts at the height of the
    /// card of the table (to a point) and never reaches below it, and the card of the table ends 16 points before it.
    private func problems(ofTheClientDetail detail: CGRect, besideTheTable table: CGRect, in room: CGRect) -> [String] {
        var problems: [String] = []
        if (detail.width - DetailPanelMetrics.width).magnitude >= 0.5 {
            problems.append("The detail is not \(DetailPanelMetrics.width) points wide: \(detail)")
        }
        if (detail.maxX - (room.maxX - 16)).magnitude >= 0.5 {
            problems.append("The detail does not stand at the right margin of the page: \(detail)")
        }
        // The origin of the window is at the bottom left: the top is the largest y.
        if (detail.maxY - table.maxY).magnitude > 1 {
            problems.append("The detail does not start where the table does: \(detail), \(table)")
        }
        if detail.minY < table.minY - 1 {
            problems.append("The detail reaches below the card of the table: \(detail), \(table)")
        }
        if (detail.minX - 16 - table.maxX).magnitude >= 0.5 {
            problems.append("The table does not end 16 points before the detail: \(table), \(detail)")
        }
        return problems
    }

    /// The scroll view that the table of Odběratelé scrolls sideways in, in `window`: the one scroll view with a
    /// horizontal scroller. Its frame is the card of the table under the summary row, and what it scrolls is the table:
    /// the names of the columns and the rows.
    private func clientTableScrollView(in window: NSWindow) -> NSScrollView? {
        guard let content = window.contentView else { return nil }
        return allScrollViews(in: content).first { $0.hasHorizontalScroller }
    }

    /// The scroll view that the rows of the table of Odběratelé scroll up and down in, in `window`: the one inside the
    /// scroll view that scrolls the table sideways, under the names of the columns.
    private func clientRowsScrollView(in window: NSWindow) -> NSScrollView? {
        guard let table = clientTableScrollView(in: window)?.documentView else { return nil }
        return allScrollViews(in: table).first
    }

    /// How wide the table of Odběratelé is in `window`: what its card scrolls sideways.
    private func clientTableWidth(in window: NSWindow) throws -> CGFloat {
        try #require(clientTableScrollView(in: window)?.documentView).frame.width
    }

    private func allScrollViews(in view: NSView) -> [NSScrollView] {
        let own = (view as? NSScrollView).map { [$0] } ?? []
        return own + view.subviews.flatMap { allScrollViews(in: $0) }
    }

    /// What is wrong with the width of the table of Odběratelé in `window`: it is not as wide as its card, or a
    /// scroller says that there is more of it to the side. Empty when the table is as wide as its card.
    private func problems(ofTheClientTableFillingItsCardIn window: NSWindow) -> [String] {
        guard let scrollView = clientTableScrollView(in: window), let table = scrollView.documentView else {
            return ["The page has no table"]
        }
        var problems: [String] = []
        let shown = scrollView.contentView.bounds.width
        if (table.frame.width - shown).magnitude >= 0.5 {
            problems.append("The table is \(table.frame.width) points wide in a card that shows \(shown)")
        }
        if scrollView.horizontalScroller?.isHidden == false {
            problems.append("The card of the table shows a horizontal scroller")
        }
        return problems
    }

    /// What is wrong with the width of the table of Odběratelé in `window` while its card is narrower than its least
    /// width: it is not that wide (`ClientTableColumns.minimumWidth`), or not wider than its card, or the card shows no
    /// horizontal scroller. Empty when the table keeps its least width and scrolls sideways.
    private func problems(ofTheClientTableScrollingSidewaysIn window: NSWindow) -> [String] {
        guard let scrollView = clientTableScrollView(in: window), let table = scrollView.documentView else {
            return ["The page has no table"]
        }
        var problems: [String] = []
        let shown = scrollView.contentView.bounds.width
        let least = ClientTableColumns.minimumWidth
        if (table.frame.width - least).magnitude >= 0.5 {
            problems.append("The table is \(table.frame.width) points wide, not \(least)")
        }
        if table.frame.width <= shown + 0.5 {
            problems.append("The table is not wider than its card, which shows \(shown) points")
        }
        if scrollView.horizontalScroller?.isHidden != false {
            problems.append("The card of the table shows no horizontal scroller")
        }
        return problems
    }

    /// Widens the sidebar of `window` to the widest it goes, 320 points, as dragging its edge does.
    private func widenSidebar(of window: NSWindow) {
        guard let frameView = window.contentView?.superview,
            let splitView = splitViews(in: frameView).first(where: { $0.delegate is NSSplitViewController })
        else {
            return
        }
        splitView.setPosition(320, ofDividerAt: 0)
    }

    // MARK: Výpočet

    @Test func vypocetFitsTheWindowAtTheLeastRoomAndAtALargeSize() async throws {
        try await expectVypocetFits(inYear: nil)
    }

    /// A year that is over has no planned advances, and a year without rules has the orange warning above the cards.
    @Test(arguments: [2025, 2027])
    func vypocetOfAYearThatIsOverAndOfAnEstimateFitsTheWindowToo(year: Int) async throws {
        try await expectVypocetFits(inYear: year)
    }

    /// Shows Výpočet in the window at the least room, at a large size and at the least room again, for `year` or, with
    /// nil, the year of the app, and records an issue for every problem of the page.
    private func expectVypocetFits(inYear year: Int?) async throws {
        try await EditorFixture.with { f in
            try await withAppWindow(of: f.app, size: AppWindowSize.minimum) { window in
                f.app.screen = .computation
                if let year {
                    f.app.selectYear(year)
                }
                try await waitUntil { window.title == "Výpočet" }
                // The page scrolls; with the data it is far taller than while it loads.
                try await waitUntil { (scrolledPage(in: window)?.frame.height ?? 0) > 600 }

                try await expectSettled(window) { problems(ofPageIn: window) }
                window.setContentSize(AppWindowSize.large)
                try await expectSettled(window) { problems(ofPageIn: window) }
                window.setContentSize(AppWindowSize.minimum)
                try await expectSettled(window) { problems(ofPageIn: window) }
            }
        }
    }

    /// Výpočet opens with its result and goes on in this order, at the least room and in a large window: the result
    /// card, the cards Mezní odvod and Hranice roku, the note about the day the computation counts up to, "Rozpis
    /// výpočtu" with the breakdown, which starts with Příjmy a zisk, and the footnote "Předpoklady výpočtu". Nothing of
    /// the page is laid out beyond the window.
    @Test func theVypocetPageRunsResultMarginalThresholdsNoteBreakdownFootnote() async throws {
        try await EditorFixture.with { f in
            try await withAppWindow(of: f.app, size: AppWindowSize.minimum) { window in
                f.app.screen = .computation
                try await waitUntil { window.title == "Výpočet" }
                // The page scrolls; with the data it is far taller than while it loads.
                try await waitUntil { (scrolledPage(in: window)?.frame.height ?? 0) > 600 }

                try await withAccessibilityElements {
                    for size in [AppWindowSize.minimum, AppWindowSize.large, AppWindowSize.minimum] {
                        window.setContentSize(size)
                        try await expectSettled(window) {
                            problems(ofTheOrderOfVýpočetIn: window) + problems(ofPageIn: window)
                        }
                    }
                    #expect(viewsOutside(window) == [])
                }
            }
        }
    }

    /// The two cards under the result of Výpočet, Mezní odvod and Hranice roku, are cards of one height in one row at
    /// the least room (2 × 380 and the gap of 16 are 776 points, and the page has 828) and in a large window.
    @Test func theMarginalAndTheThresholdsCardsOfVypocetAreInOneRowOfOneHeight() async throws {
        try await EditorFixture.with { f in
            try await withAppWindow(of: f.app, size: AppWindowSize.minimum) { window in
                f.app.screen = .computation
                try await waitUntil { window.title == "Výpočet" }
                try await waitUntil { (scrolledPage(in: window)?.frame.height ?? 0) > 600 }

                try await withAccessibilityElements {
                    for size in [AppWindowSize.minimum, AppWindowSize.large, AppWindowSize.minimum] {
                        window.setContentSize(size)
                        try await expectSettled(window) { problems(ofTheSmallCardsIn: window, inRowsOf: [2]) }
                    }
                }
            }
        }
    }

    /// The key figure and the levy bar of the result card of Výpočet stand side by side, in two columns of one width
    /// and level at the top, where the card has the 788 points inside its padding that two columns of 380 and the gap
    /// of 28 take, such as in a large window, and the bar stands under the key figure, in the whole width, where it has
    /// less, such as at the least room with the sidebar as wide as it goes. At the least room itself the page has 828
    /// points, the card exactly the 788 inside its padding, and the parts stand wherever the room puts them.
    @Test func theKeyFigureAndTheLevyBarStandSideBySideInALargeWindowAndOneAboveTheOtherInANarrowOne() async throws {
        try await EditorFixture.with { f in
            let levies = CzechFormat.wholeKc(try await f.app.computeSelectedYear().liabilityTotal)
            try await withAppWindow(of: f.app, size: AppWindowSize.minimum) { window in
                f.app.screen = .computation
                try await waitUntil { window.title == "Výpočet" }
                try await waitUntil { (scrolledPage(in: window)?.frame.height ?? 0) > 600 }

                try await withAccessibilityElements {
                    window.setContentSize(AppWindowSize.large)
                    try await expectSettled(window) {
                        problems(ofTheResultOfVýpočetIn: window, levies: levies, beside: true)
                    }
                    // Whatever the room, the parts stand as the width of the card says: side by side from 788 points
                    // inside its padding.
                    window.setContentSize(AppWindowSize.minimum)
                    try await expectSettled(window) {
                        problems(ofTheResultOfVýpočetIn: window, levies: levies, beside: nil)
                    }
                    widenSidebar(of: window)
                    try await expectSettled(window) {
                        problems(ofTheResultOfVýpočetIn: window, levies: levies, beside: false)
                    }
                }
            }
        }
    }

    /// "Pravidla v Nastavení", the link of the footnote of Výpočet, opens Nastavení on its tab Rok, where the rules of
    /// the year are.
    @Test func theLinkOfTheFootnoteOpensTheRulesOfTheYearInNastaveni() async throws {
        try await EditorFixture.with { f in
            try await withAppWindow(of: f.app, size: AppWindowSize.minimum) { window in
                f.app.screen = .computation
                try await waitUntil { window.title == "Výpočet" }
                try await withAccessibilityElements {
                    try await waitUntil { accessibilityButton(labelled: "Pravidla v Nastavení", in: window) != nil }
                    #expect(f.app.settingsTab != .year)

                    _ = try #require(accessibilityButton(labelled: "Pravidla v Nastavení", in: window))
                        .accessibilityPerformPress?()

                    try await waitUntil { window.title == "Nastavení" }
                    #expect(f.app.screen == .settings)
                    #expect(f.app.settingsTab == .year)
                }
            }
        }
    }

    /// The popover of the levy bar hangs out of the result card of Výpočet, over the edge of the card and the card
    /// under it, and is drawn above both: the card is drawn above what follows it, and nothing clips the popover. The
    /// pointer is moved over the part of the tax, and then over its item of the legend, as a mouse moves it. A strip
    /// down the popover, 6 points inside its leading edge, shows nothing but the colour of the popover while it is
    /// open, where the edges of the two cards cross it while it is closed.
    @Test func thePopoverOfTheLevyBarIsDrawnOverTheCardsUnderTheResult() async throws {
        try await EditorFixture.with { f in
            let result = try await f.app.computeSelectedYear()
            let weights = Authority.allCases.map { result.balance($0).liability }
            try await withAppWindow(of: f.app, size: AppWindowSize.large, ignoringTheRealPointer: true) { window in
                f.app.screen = .computation
                try await waitUntil { window.title == "Výpočet" }
                try await waitUntil { (scrolledPage(in: window)?.frame.height ?? 0) > 600 }

                try await withAccessibilityElements {
                    try await expectSettled(window) { problems(ofTheOrderOfVýpočetIn: window) }
                    let content = try #require(window.contentView)
                    let bar = window.convertFromScreen(
                        try #require(
                            accessibilityElement(labelStartingWith: "Odvody z příjmů do", in: window)?
                                .accessibilityFrame?()))
                    let legend = window.convertFromScreen(
                        try #require(
                            accessibilityElement(labelStartingWith: "Daň z příjmů: odvody z příjmů", in: window)?
                                .accessibilityFrame?()))
                    // The popover of the tax: 8 points under the legend, centred on its part and held in the panel.
                    let widths = LevyBarLayout.partWidths(weights: weights, width: bar.width)
                    let centre = LevyBarLayout.partCentres(widths: widths)[0]
                    let left = bar.minX + LevyBarLayout.popoverX(centredOn: centre, panelWidth: bar.width)
                    let top = content.bounds.height - legend.minY + LevyBarLayout.popoverGap

                    /// The points of the strip down the popover, from 4 to 100 points under its top, whose colour is
                    /// not that of the top of the strip: what is drawn over the popover while it is open.
                    @MainActor func strayPoints() throws -> [CGPoint] {
                        let picture = try WindowPicture(of: window)
                        let strip = stride(from: top + 4, to: top + 100, by: 0.5).map { CGPoint(x: left + 6, y: $0) }
                        let colour = picture.bytes(at: strip[0])
                        return strip.filter { point in
                            zip(picture.bytes(at: point), colour).contains { abs($0 - $1) > 6 }
                        }
                    }

                    // With no popover the edges of the cards cross the strip: the test can tell the two states apart.
                    let corner = CGPoint(x: 4, y: 4)
                    try await expectSettled(window) {
                        ((try? strayPoints()) ?? []).isEmpty ? ["No edge of a card crosses the strip"] : []
                    }

                    let overPart = CGPoint(x: bar.minX + 10, y: bar.midY)
                    let overLegend = CGPoint(x: legend.minX + 10, y: legend.midY)
                    for (name, pointer) in [("part", overPart), ("item of the legend", overLegend)] {
                        try movePointer(to: pointer, in: window)
                        try await waitUntil { ((try? strayPoints()) ?? [CGPoint.zero]).isEmpty }
                        #expect(try strayPoints() == [], "Drawn over the popover of the \(name)")

                        try movePointer(to: corner, in: window)
                        try await waitUntil { !((try? strayPoints()) ?? []).isEmpty }
                    }
                }
            }
        }
    }

    /// The breakdown of Výpočet has the income and the tax on the left and the social and the health insurance with the
    /// net income under them on the right: all five in one column at the least room, where the detail has 828 points
    /// and two columns need 856, and in two columns in a large window, whichever way the window goes.
    @Test func theBreakdownIsOneColumnAtTheLeastRoomAndTwoInALargeWindow() async throws {
        try await EditorFixture.with { f in
            try await withAppWindow(of: f.app, size: AppWindowSize.minimum) { window in
                f.app.screen = .computation
                try await waitUntil { window.title == "Výpočet" }
                try await waitUntil { (scrolledPage(in: window)?.frame.height ?? 0) > 600 }

                try await withAccessibilityElements {
                    for (size, beside) in Self.breakdownSizes {
                        window.setContentSize(size)
                        try await expectSettled(window) {
                            problems(ofTheBreakdown: Self.vypocetBreakdown, beside: beside) { title in
                                frameOfCard(headed: title, in: window)
                            }
                        }
                    }
                }
            }
        }
    }

    /// Výpočet and Přehled with the family of the sample stored for 2026. As of 28. 2. the children's benefit is a
    /// bonus: the tax card has every row of the family, the tax is negative with its note, the longest of the card,
    /// "záporná daň je daňový bonus – vyplatí ho finanční úřad", and the tax comes back; the item of the tax in the
    /// legend of the levy bar reads the bonus with its share of the income, below zero. As of 31. 1. the bonus is not
    /// paid yet, and the row of the children says why in its longest note. At the least room, at a large size and at
    /// the least room again, the pages fit the window, each of these rows is within the page and as tall as its label
    /// and note need beside its value, and both lines of the item of the tax fit its column.
    @Test func vypocetAndPrehledWithTheFamilyAndABonusFitTheWindow() async throws {
        try await EditorFixture.with { f in
            try await Self.storeTheSampleFamily(in: f.database)
            await f.app.didWriteAndBackUp()
            f.app.pickAsOf(civilDate("2026-02-28"))
            try await withAppWindow(of: f.app, size: AppWindowSize.minimum) { window in
                try await withAccessibilityElements {
                    try await expectFamilyRowsFit(Self.familyRowsWithABonus, in: window)

                    f.app.screen = .overview
                    try await waitUntil { window.title == "Přehled" }
                    try await waitUntil {
                        accessibilityElement(labelled: Self.taxItemOfTheLegendWithABonus, in: window) != nil
                    }
                    for size in [AppWindowSize.minimum, AppWindowSize.large, AppWindowSize.minimum] {
                        window.setContentSize(size)
                        try await expectSettled(window) {
                            problems(ofPageIn: window) + problemsOfTheTaxItemOfTheLegend(in: window)
                        }
                    }

                    f.app.pickAsOf(civilDate("2026-01-31"))
                    f.app.screen = .computation
                    try await waitUntil { window.title == "Výpočet" }
                    try await expectFamilyRowsFit([Self.childRowBeforeTheBonus], in: window)
                }
            }
        }
    }

    /// Waits until Výpočet in `window` shows `rows`, then checks them and the page at the least room, at a large size
    /// and at the least room again.
    private func expectFamilyRowsFit(_ rows: [ComputationRow], in window: NSWindow) async throws {
        try await waitUntil { rows.allSatisfy { accessibilityElement(labelled: $0.spokenText, in: window) != nil } }
        for size in [AppWindowSize.minimum, AppWindowSize.large, AppWindowSize.minimum] {
            window.setContentSize(size)
            try await expectSettled(window) {
                problems(ofPageIn: window) + rows.flatMap { problems(ofRow: $0, in: window) }
            }
        }
    }

    /// Stores for 2026 the family of the engine's family tests: Anna (3. 9. 2019) and Tomáš (12. 4. 2024), the first
    /// and the second child, and a spouse without income of her own, claimed the whole year.
    private static func storeTheSampleFamily(in database: Database) async throws {
        for (order, child) in [("Anna", "2019-09-03"), ("Tomáš", "2024-04-12")].enumerated() {
            try await database.saveChild(
                Child(id: nil, name: child.0, birthDate: civilDate(child.1)), year: 2026,
                childYear: ChildYear(
                    household: MonthRange.wholeYear, claimant: .me, order: order + 1, ztpp: nil, studies: nil))
        }
        try await database.saveSpouse(
            SpouseYear(claim: true, months: MonthRange.wholeYear, ownIncomeKc: 0, ztpp: nil), year: 2026)
    }

    /// The rows of the tax card of the sample year with the sample family as of 28. 2. 2026: the income of 220 000 Kč
    /// is past six minimum wages, the deductions take the whole profit, and the children's 37 524 Kč are a bonus.
    private static let familyRowsWithABonus = [
        ComputationRow(
            label: "Sleva na manžela / manželku", value: "0",
            note: "12\u{00A0}měsíců s dítětem do 3 let · daň už je nulová, sleva se neprojeví", sign: .minus),
        ComputationRow(
            label: "Daň po slevách", value: "0", note: "slevy snižují daň nejvýš na nulu", sign: .equals,
            style: .strong),
        ComputationRow(
            label: "Daňové zvýhodnění na děti", value: "\u{2212}37\u{00A0}524",
            note: "Anna 15\u{00A0}204 · Tomáš 22\u{00A0}320 · z toho daňový bonus 37\u{00A0}524", sign: .minus),
        ComputationRow(
            label: "Daň z dosavadních příjmů", value: "\u{2212}37\u{00A0}524",
            note: "záporná daň je daňový bonus – vyplatí ho finanční úřad", sign: .equals, style: .strong),
        ComputationRow(
            label: "Zbývá", value: "vrátí se 37\u{00A0}524\u{00A0}Kč", note: "vrací se po podání přiznání, na žádost",
            sign: .equals, style: .total),
    ]

    /// The row of the children as of 31. 1. 2026, before any income has come: the benefit is not paid as a bonus yet.
    private static let childRowBeforeTheBonus = ComputationRow(
        label: "Daňové zvýhodnění na děti", value: "0",
        note: "Anna 15\u{00A0}204 · Tomáš 22\u{00A0}320 · bonus 37\u{00A0}524 se nevyplatí:"
            + " příjmy pod 6× minimální mzdu (134\u{00A0}400)",
        sign: .minus)

    /// The part of the income that the tax takes in Přehled as of 28. 2. 2026 with the sample family: the tax is the
    /// bonus of 37 524 Kč below zero, minus 17,0 % of the income of 220 000 Kč.
    private static let taxShareWithABonus = "\u{2212}17,0\u{00A0}%"

    /// What VoiceOver reads for the item of the tax in the legend of the levy bar of Přehled as of 28. 2. 2026 with the
    /// sample family: the bonus as the levy, no advances paid, the bonus that comes back, and the part of the income
    /// the tax takes, below zero.
    private static let taxItemOfTheLegendWithABonus =
        "Daň z příjmů: odvody z příjmů bonus 37\u{00A0}524\u{00A0}Kč, zaplaceno zálohami 0\u{00A0}Kč,"
        + " vrátí se 37\u{00A0}524\u{00A0}Kč, \(taxShareWithABonus) z příjmů bez DPH"

    /// What is wrong with `row` of a card of Výpočet in `window`, in words: VoiceOver does not find it, it is not
    /// within the margins of the page, or it is lower than its label and its note need at the width they have beside
    /// the sign and the value, as a text cut short would be. Empty when the row fits. Needs the accessibility elements.
    private func problems(ofRow row: ComputationRow, in window: NSWindow) -> [String] {
        guard let frame = accessibilityElement(labelled: row.spokenText, in: window)?.accessibilityFrame?() else {
            return ["No row \(row.label)"]
        }
        var found: [String] = []
        if let page = scrolledPage(in: window) {
            // The margins of the page: 24 points on its leading side and 16 on its trailing side.
            let room = window.convertToScreen(frameInWindow(page))
            let margins = CGRect(x: room.minX + 24, y: room.minY, width: room.width - 24 - 16, height: room.height)
            if frame.minX < margins.minX - 0.5 || frame.maxX > margins.maxX + 0.5 {
                found.append("The row \(row.label) is not within the page: \(frame), the margins \(margins)")
            }
        }
        // As the card sets a row: the sign 18 points wide, 10 points between it and the texts, the label with the note
        // 2 points under it, and 10 points more before the value, which keeps its width. The frame VoiceOver has for
        // the row is that of what it reads, without the 8 points above and below it. The value of the total is title 2.
        let weight: Font.Weight =
            switch row.style {
            case .plain: .regular
            case .strong: .semibold
            case .total: .bold
            }
        let valueFont = row.style == .total ? Typography.title2 : Font.body.weight(weight)
        let valueWidth = fittingSize(of: Text(verbatim: row.value).font(valueFont).monospacedDigit()).width
        let signWidth = fittingSize(of: Text(verbatim: row.sign.rawValue).fontWeight(.bold)).width
        // How far into the row the frame starts: where the sign is drawn, in the middle of its 18 points, or at the
        // texts for a row with no sign.
        let frameStartsAt: CGFloat = row.sign == .blank ? 18 + 10 : (18 - signWidth) / 2
        let width = frame.width + frameStartsAt - 18 - 10 - 10 - valueWidth
        var needed = height(of: Text(verbatim: row.label).fontWeight(weight), width: width)
        if let note = row.note {
            needed += 2 + height(of: Text(verbatim: note).font(.callout), width: width)
        }
        if frame.height + 1 < needed {
            found.append("The row \(row.label) is \(frame.height) points tall, its texts need \(needed)")
        }
        return found
    }

    /// What is wrong with the item of the tax with a bonus in the legend of the levy bar of Přehled, in `window`, in
    /// words: VoiceOver does not find it, or one of its two lines of text is wider than the item, so that a text of it
    /// would be cut short or run into the item beside it. Empty when it fits. Needs the accessibility elements.
    private func problemsOfTheTaxItemOfTheLegend(in window: NSWindow) -> [String] {
        guard
            let frame = accessibilityElement(labelled: Self.taxItemOfTheLegendWithABonus, in: window)?
                .accessibilityFrame?()
        else {
            return ["No item of the tax with a bonus in the legend"]
        }
        // The dot of the authority, 8 points and 6 after it, the short name, and under them the bonus.
        let name = Text(verbatim: "Daň").font(Typography.callout)
        let bonus = Text(verbatim: "bonus 37\u{00A0}524\u{00A0}Kč").font(Typography.bodySemibold).monospacedDigit()
        let top = 8 + 6 + fittingSize(of: name).width
        let bottom = fittingSize(of: bonus).width
        return [("top", top), ("bottom", bottom)].compactMap { line, needed in
            needed > frame.width + 0.5
                ? "The \(line) line of the item needs \(needed) points, it has \(frame.width)" : nil
        }
    }

    /// The size `text` takes at its ideal width.
    private func fittingSize(of text: some View) -> CGSize {
        NSHostingView(rootView: text.fixedSize()).fittingSize
    }

    /// The height `text` takes at `width`, wrapped as it needs.
    private func height(of text: some View, width: CGFloat) -> CGFloat {
        NSHostingView(rootView: text.frame(width: max(0, width)).fixedSize(horizontal: false, vertical: true))
            .fittingSize.height
    }

    /// The cards under the result of Výpočet by the labels VoiceOver reads them under, in the order they stand in. The
    /// card of the thresholds is read under "Hranice roku", and its heading is "Hranice roku 2026".
    private static let vypocetSmallCards = ["Mezní odvod", "Hranice roku"]

    /// The cards of the breakdown of Výpočet by the headings they read, the left stack and then the right one: the
    /// income and the tax, and the social and the health insurance with the net income under them.
    private static let vypocetBreakdown = [
        ["Příjmy a zisk", "Daň z příjmů"], ["Sociální pojištění", "Zdravotní pojištění", "Čistý příjem"],
    ]

    /// The cards of the breakdown of Odhad odvodů by the headings they read, the left stack and then the right one: the
    /// income and the tax, and the social and the health insurance with the net income under them.
    private static let predictionBreakdown = [
        ["Příjmy a zisk", "Daň z příjmů"], ["Sociální pojištění", "Zdravotní pojištění", "Čistý příjem"],
    ]

    /// The sizes the breakdown of a screen is looked at in, and whether its two stacks stand beside each other in them:
    /// the detail of the least window has 828 points, less than the 856 that two columns need, and a large window has
    /// more. Back at the least room, the stacks come together again.
    private static let breakdownSizes = [
        (size: AppWindowSize.minimum, beside: false), (size: AppWindowSize.large, beside: true),
        (size: AppWindowSize.minimum, beside: false),
    ]

    /// What is wrong with the order of the page of Výpočet in `window`, in words: a part is missing, or one of them is
    /// not above the next in this order: the result card, the two small cards (Mezní odvod and Hranice roku, in the
    /// order they are named in, a row at a time and each row from the left), the note about the day the computation
    /// counts up to, "Rozpis výpočtu" with the first card of its breakdown, Příjmy a zisk, inside it, and the footnote
    /// "Předpoklady výpočtu". Empty when the page runs in that order.
    private func problems(ofTheOrderOfVýpočetIn window: NSWindow) -> [String] {
        guard let result = frameOfCard(labelled: "Výsledek", in: window) else {
            return ["No card Výsledek"]
        }
        var small: [CGRect] = []
        for label in Self.vypocetSmallCards {
            guard let frame = frameOfCard(labelled: label, in: window) else {
                return ["No card \(label)"]
            }
            small.append(frame)
        }
        guard let thresholds = frameOfCard(headed: "Hranice roku 2026", in: window) else {
            return ["No card headed Hranice roku 2026"]
        }
        guard let note = frameOfText(startingWith: "Počítáno jen ze skutečně přijatých plateb", in: window) else {
            return ["No note about the day the computation counts up to"]
        }
        guard let breakdown = frameOfCard(labelled: "Rozpis výpočtu", in: window) else {
            return ["No group Rozpis výpočtu"]
        }
        guard let income = frameOfCard(headed: "Příjmy a zisk", in: window) else {
            return ["No card Příjmy a zisk"]
        }
        guard let footnote = frameOfCard(labelled: "Předpoklady výpočtu", in: window) else {
            return ["No footnote Předpoklady výpočtu"]
        }
        var found: [String] = []
        if (thresholds.minY - small[1].minY).magnitude > 0.5 || (thresholds.maxY - small[1].maxY).magnitude > 0.5 {
            found.append("The card headed Hranice roku 2026 is not the card Hranice roku: \(thresholds), \(small[1])")
        }
        // The parts by the band of the page they belong to, the first band the highest.
        let landmarks: [(band: Int, name: String, frame: CGRect)] =
            [(0, "Výsledek", result)] + zip(Self.vypocetSmallCards, small).map { (1, $0, $1) }
            + [(2, "the note", note), (3, "Rozpis výpočtu", breakdown), (4, "the footnote", footnote)]
        for upper in landmarks {
            // The origin of the screen is at the bottom left, so what stands above has the larger y.
            for lower in landmarks where upper.band < lower.band && upper.frame.minY < lower.frame.maxY - 0.5 {
                found.append("\(upper.name) is not above \(lower.name): \(upper.frame) and \(lower.frame)")
            }
        }
        for index in small.indices.dropFirst() {
            let (before, after) = (small[index - 1], small[index])
            let isAbove = before.minY >= after.maxY
            let isBeside = (before.maxY - after.maxY).magnitude <= 1 && before.maxX <= after.minX
            if !isAbove && !isBeside {
                found.append("\(Self.vypocetSmallCards[index]) does not follow \(Self.vypocetSmallCards[index - 1])")
            }
        }
        // The first card of the breakdown is inside its group, under the heading that the group starts with.
        if !breakdown.insetBy(dx: -0.5, dy: -0.5).contains(income) {
            found.append("Příjmy a zisk is not inside Rozpis výpočtu: \(income) and \(breakdown)")
        }
        if income.maxY > breakdown.maxY - 10 {
            found.append("Příjmy a zisk does not start under the heading of Rozpis výpočtu: \(income) and \(breakdown)")
        }
        return found
    }

    /// What is wrong with the result card of Výpočet in `window`, in words: the key figure or the levy bar is missing
    /// or not inside the card; the key figure and the levy bar do not stand side by side, in columns of one width 28
    /// points apart, level at the top; or they do not stand one above the other, 28 points apart, the bar in the whole
    /// width. `levies` is the total of the levies that the bar has in its header, beside the words of the header or
    /// under them. `beside` says which of the two they should do, and nil that they should do what the width of the
    /// card says: side by side from 788 points inside its padding of 20. Empty when they stand so.
    private func problems(ofTheResultOfVýpočetIn window: NSWindow, levies: String, beside: Bool?) -> [String] {
        guard let card = frameOfCard(labelled: "Výsledek", in: window) else {
            return ["No card Výsledek"]
        }
        guard let key = frameOfText(startingWith: "Zbývá zaplatit k", in: window) else {
            return ["No key figure"]
        }
        guard let bar = accessibilityElement(labelStartingWith: "Odvody z příjmů do", in: window)?.accessibilityFrame?()
        else {
            return ["No levy bar"]
        }
        guard let header = frameOfText(startingWith: "Odvody z příjmů do", in: window) else {
            return ["No header of the levy bar"]
        }
        guard let total = frameOfText(startingWith: levies, in: window) else {
            return ["No total of the levies \(levies)"]
        }
        // The top of the levy bar is that of its header, or of its total where it stands on the line of the header and
        // is the taller of the two.
        let barTop = max(header.maxY, total.maxY)
        var found: [String] = []
        for (name, frame) in [("The key figure", key), ("The levy bar", bar)]
        where !card.insetBy(dx: -0.5, dy: -0.5).contains(frame) {
            found.append("\(name) is not inside the card: \(frame) and \(card)")
        }
        // The origin of the screen is at the bottom left: what is at the top has the largest y. The padding is 20.
        let inner = card.width - 40
        if (card.maxY - 20 - key.maxY).magnitude > 1 || (key.minX - card.minX - 20).magnitude > 1 {
            found.append("The key figure is not at the top left of the card: \(key) and \(card)")
        }
        if beside ?? ResultCardLayout.standsSideBySide(innerWidth: inner) {
            let column = (inner - 28) / 2
            if (bar.minX - (card.minX + 20 + column + 28)).magnitude > 1 || (bar.width - column).magnitude > 1 {
                found.append("The levy bar is not the second column of \(column) points, 28 from the first: \(bar)")
            }
            if (card.maxY - 20 - barTop).magnitude > 1 {
                found.append("The levy bar is not level at the top with the key figure: \(header), \(total), \(card)")
            }
            // The sentence under the key figure stops at the width the design gives it on this screen, 36 em of the
            // 13-point type, 468 points, where the column has the room for it: not at the 416 of the other screens.
            if column > 470, (key.width - 468).magnitude > 1 {
                found.append("The key figure is not 468 points wide, the width of its sentence: \(key)")
            }
        } else {
            if (key.minY - barTop - 28).magnitude > 1 {
                found.append("The levy bar is not 28 points under the key figure: \(header), \(total), \(key)")
            }
            if (bar.minX - key.minX).magnitude > 1 || (bar.width - inner).magnitude > 1 {
                found.append("The levy bar does not have the whole width of the card, from its left edge: \(bar)")
            }
        }
        return found
    }

    /// What is wrong with the small cards of Výpočet in `window`, in words: a card is missing, the cards are not in
    /// rows of `expectedRows` cards from the top, or the cards of a row are not of one height (to half a point). Empty
    /// when the cards stand so.
    private func problems(ofTheSmallCardsIn window: NSWindow, inRowsOf expectedRows: [Int]) -> [String] {
        var cards: [CGRect] = []
        for label in Self.vypocetSmallCards {
            guard let frame = frameOfCard(labelled: label, in: window) else {
                return ["No card \(label)"]
            }
            cards.append(frame)
        }
        // The cards of a row share their top, the largest y: the origin of the screen is at the bottom left.
        var rows: [[CGRect]] = []
        for card in cards {
            if let top = rows.last?.first?.maxY, (top - card.maxY).magnitude < 0.5 {
                rows[rows.count - 1].append(card)
            } else {
                rows.append([card])
            }
        }
        var problems: [String] = []
        if rows.map(\.count) != expectedRows {
            problems.append("The cards are in rows of \(rows.map(\.count)), not of \(expectedRows): \(cards)")
        }
        for row in rows {
            let heights = row.map(\.height)
            if let tallest = heights.max(), let lowest = heights.min(), tallest - lowest > 0.5 {
                problems.append("The cards of a row are not of one height: \(heights)")
            }
        }
        return problems
    }

    /// What is wrong with how the cards of a breakdown stand in two stacks, in words. `stacks` are the names of the
    /// cards of the left stack and of the right one, from the top, and `frameOf` finds the frame of a card by its name.
    /// With `beside` each stack is a column of its own, the right one stands to the right of the left one, and their
    /// tops are level and their widths equal; without it all the cards stand in one column, in the order of the names,
    /// the left stack first. In a column every card is under the one before it, at its left edge and of its width.
    /// Empty when the cards stand so.
    private func problems(
        ofTheBreakdown stacks: [[String]], beside: Bool, frameOf: (String) -> CGRect?
    ) -> [String] {
        var columns: [[(name: String, frame: CGRect)]] = []
        for stack in stacks {
            var column: [(name: String, frame: CGRect)] = []
            for name in stack {
                guard let frame = frameOf(name) else {
                    return ["No card \(name)"]
                }
                column.append((name: name, frame: frame))
            }
            columns.append(column)
        }
        var found: [String] = []
        for column in beside ? columns : [columns.flatMap { $0 }] {
            for (index, card) in column.enumerated() {
                if (card.frame.minX - column[0].frame.minX).magnitude > 1
                    || (card.frame.width - column[0].frame.width).magnitude > 1
                {
                    found.append("\(card.name) is not in the column of \(column[0].name): \(card.frame)")
                }
                // The origin of the screen is at the bottom left, so a card under another has its top, the largest y,
                // at or under the bottom of the other.
                if index > 0, card.frame.maxY > column[index - 1].frame.minY + 0.5 {
                    found.append("\(card.name) is not under \(column[index - 1].name): \(card.frame)")
                }
            }
        }
        if beside, let left = columns.first, let right = columns.last,
            let leftTop = left.first, let rightTop = right.first
        {
            let leftEdge = left.map(\.frame.maxX).max() ?? 0
            for card in right where card.frame.minX < leftEdge - 0.5 {
                found.append("\(card.name) is not to the right of the left stack, which ends at \(leftEdge)")
            }
            if (leftTop.frame.maxY - rightTop.frame.maxY).magnitude > 1 {
                found.append("\(rightTop.name) is not level with \(leftTop.name): \(rightTop.frame), \(leftTop.frame)")
            }
            if (leftTop.frame.width - rightTop.frame.width).magnitude > 1 {
                found.append("\(rightTop.name) is not as wide as \(leftTop.name): \(rightTop.frame), \(leftTop.frame)")
            }
        }
        return found
    }

    /// Výpočet and Přehled with the line that part of the income is converted at a provisional rate, which comes above
    /// their cards when a payment of the year waits for its rate and goes once it is converted: the pages fit the
    /// window with it at the least room and at a large size.
    @Test func vypocetAndPrehledFitTheWindowWithTheLineOfProvisionalIncome() async throws {
        try await EditorFixture.with { f in
            try await withAppWindow(of: f.app, size: AppWindowSize.minimum) { window in
                try await waitUntil { (scrolledPage(in: window)?.frame.height ?? 0) > 600 }
                let without = try #require(scrolledPage(in: window)).frame.height
                // The dollars that arrived on 2. 10. 2026 wait for the rate of their day.
                try await f.database.markPaymentProvisional(ofInvoice: 10)
                await f.app.didWrite()
                try await waitUntil { (scrolledPage(in: window)?.frame.height ?? 0) > without + 30 }
                try await expectSettled(window) { problems(ofPageIn: window) }
                window.setContentSize(AppWindowSize.large)
                try await expectSettled(window) { problems(ofPageIn: window) }
                window.setContentSize(AppWindowSize.minimum)
                try await expectSettled(window) { problems(ofPageIn: window) }

                f.app.screen = .overview
                try await waitUntil { window.title == "Přehled" }
                try await waitUntil { (scrolledPage(in: window)?.frame.height ?? 0) > 600 }
                try await expectSettled(window) { problems(ofPageIn: window) }
                window.setContentSize(AppWindowSize.large)
                try await expectSettled(window) { problems(ofPageIn: window) }
                window.setContentSize(AppWindowSize.minimum)
                try await expectSettled(window) { problems(ofPageIn: window) }

                // Converted at the rate of its day, the payment is no longer provisional, and the line goes.
                let with = try #require(scrolledPage(in: window)).frame.height
                var converted = try await f.stored(10)
                converted.payment?.provisional = false
                try await f.database.saveInvoice(converted)
                await f.app.didWrite()
                try await waitUntil { (scrolledPage(in: window)?.frame.height ?? 0) < with - 30 }
            }
        }
    }

    // MARK: Odhad odvodů

    /// Odhad odvodů on the prediction sample, for the year in progress and for 2025, which is over, with the months of
    /// the clients folded and unfolded (and the group of the other clients with them), at the least room, at a large
    /// size and at the least room again, and at the least room with the sidebar as wide as it goes: the page fits the
    /// window, its breakdown stands in one column where the detail has less than the 856 points that two columns need
    /// (828 at the least room, 740 with the wide sidebar) and in two columns in a large window (the cards of Výpočet,
    /// with the same headings), the key figure and the bar of the result card stand as the width says and the figure of
    /// what is left to settle under them, the net income is read as one phrase in the card Příjmy, beside the income
    /// and above the bar, the legend and the note of the money of next year, and no text of a cell is cut or even
    /// shrunk: the months stand in rows of six at the least room, in cells of more than 100 points. In the narrowest
    /// window that holds all twelve in a row, in cells of 64 points, the texts shrink as far as the cell lets them and
    /// are not cut.
    @Test func thePredictionFitsTheLeastRoomAndALargeWindow() async throws {
        try await PredictionSample.withStoredSample { app in
            try await withAppWindow(of: app, size: AppWindowSize.minimum) { window in
                try await withAccessibilityElements {
                    app.screen = .prediction
                    try await waitUntil { window.title == "Odhad odvodů" }
                    // The page scrolls; with the data it is far taller than while it loads.
                    try await waitUntil { (scrolledPage(in: window)?.frame.height ?? 0) > 600 }

                    for year in [2026, 2025] {
                        let page = try PredictionSample.page(year: year)
                        app.selectYear(year)
                        try await waitUntil { frameOfCard(labelled: "Výsledek", in: window) != nil }
                        for isUnfolded in [false, true] {
                            app.predictionMonthsOpen = isUnfolded
                            app.predictionOthersOpen = isUnfolded
                            for (size, beside) in Self.breakdownSizes {
                                window.setContentSize(size)
                                try await expectSettled(window) {
                                    problems(ofThePredictionFor: page, beside: beside, unfolded: isUnfolded, in: window)
                                }
                            }
                            window.setContentSize(Self.narrowestRoomForTwelveMonthsInARow)
                            try await expectSettled(window) {
                                problems(
                                    ofThePredictionFor: page, beside: true, unfolded: isUnfolded,
                                    shrinkingTextsTo: PredictionMonthCell.minimumTextScale, in: window)
                            }
                        }
                    }

                    // The detail of the least window with the sidebar as wide as it goes: 780 points.
                    window.setContentSize(AppWindowSize.minimum)
                    widenSidebar(of: window)
                    let page = try PredictionSample.page(year: 2025)
                    try await expectSettled(window) {
                        problems(ofThePredictionFor: page, beside: false, unfolded: true, in: window)
                    }
                }
            }
        }
    }

    /// The narrowest window whose card of the months holds twelve cells of 64 points and the gaps between them, 834
    /// points: the detail is 232 points less than the window (the sidebar), the page 40 less than that (24 and 16) and
    /// the card 40 less again (20 and 20), 1 146, and two more for the width the cells are measured in to be more than
    /// the least.
    private static let narrowestRoomForTwelveMonthsInARow = CGSize(width: 1_148, height: 1_000)

    /// What is wrong with Odhad odvodů in `window` for `page`, in words: the problems of a page that scrolls, of the
    /// result card and of the card Příjmy, the cards of the breakdown not in the two stacks that stand `beside` each
    /// other or one under the other, and, with the months `unfolded`, the cells of the clients, whose texts may shrink
    /// to `scale` of their size (not at all unless told). Needs the accessibility elements.
    private func problems(
        ofThePredictionFor page: PredictionPage, beside: Bool, unfolded: Bool, shrinkingTextsTo scale: CGFloat = 1,
        in window: NSWindow
    ) -> [String] {
        problems(ofPageIn: window)
            + problems(ofTheResultCardOfOdhadFor: page, in: window)
            + problems(ofTheCardPrijmyOf: page, in: window)
            + problems(ofTheBreakdown: Self.predictionBreakdown, beside: beside) { title in
                frameOfCard(labelled: title, in: window)
            }
            + (unfolded ? problems(ofTheCellsOf: page, shrinkingTextsTo: scale, in: window) : [])
    }

    /// What is wrong with the result card of Odhad odvodů for `page` in `window`, in words: the key figure, the bar of
    /// the levies (its header and the items of its legend) or what is left to settle is missing or not inside the card;
    /// the key figure is not at the top left of the card; the key figure and the bar do not stand as the width of the
    /// card says (side by side, in columns of one width 28 points apart and level at the top, from 788 points inside
    /// its padding of 20, and otherwise one above the other, 20 points apart, the bar in the whole width); or what is
    /// left to settle is not at the left edge, under the taller of the two, 37 points lower (20, a hairline and 16).
    /// The origin of the screen is at the bottom left, so what is above has the larger y. Empty when it stands so.
    /// Needs the accessibility elements.
    private func problems(ofTheResultCardOfOdhadFor page: PredictionPage, in window: NSWindow) -> [String] {
        guard let card = frameOfCard(labelled: "Výsledek", in: window) else {
            return ["No card Výsledek"]
        }
        guard let key = frameOfText(startingWith: page.keyFigure.eyebrow, in: window) else {
            return ["No key figure"]
        }
        guard let bar = accessibilityElement(labelStartingWith: page.levyBar.header, in: window)?.accessibilityFrame?(),
            let header = frameOfText(startingWith: page.levyBar.header, in: window)
        else {
            return ["No levy bar with its header"]
        }
        let items = page.levyBar.parts.compactMap { part in
            accessibilityElement(labelled: part.accessibilityLabel, in: window)?.accessibilityFrame?()
        }
        guard items.count == page.levyBar.parts.count else {
            return ["The legend of the levy bar has \(items.count) items, not \(page.levyBar.parts.count)"]
        }
        guard let due = frameOfText(startingWith: page.due.eyebrow, in: window) else {
            return ["No figure of what is left to settle"]
        }
        var found: [String] = []
        let inside = card.insetBy(dx: -0.5, dy: -0.5)
        for (name, frame) in [("The key figure", key), ("The levy bar", bar), ("What is left to settle", due)]
        where !inside.contains(frame) {
            found.append("\(name) is not inside the card: \(frame) and \(card)")
        }
        let inner = card.width - 40
        if (card.maxY - 20 - key.maxY).magnitude > 1 || (key.minX - card.minX - 20).magnitude > 1 {
            found.append("The key figure is not at the top left of the card: \(key) and \(card)")
        }
        if ResultCardLayout.standsSideBySide(innerWidth: inner) {
            let column = (inner - 28) / 2
            if (bar.minX - (card.minX + 20 + column + 28)).magnitude > 1 || (bar.width - column).magnitude > 1 {
                found.append("The levy bar is not the second column of \(column) points, 28 from the first: \(bar)")
            }
            if (card.maxY - 20 - header.maxY).magnitude > 1 {
                found.append("The levy bar is not level at the top with the key figure: \(header), \(card)")
            }
        } else {
            if (key.minY - header.maxY - 20).magnitude > 1 {
                found.append("The levy bar is not 20 points under the key figure: \(header), \(key)")
            }
            if (bar.minX - key.minX).magnitude > 1 || (bar.width - inner).magnitude > 1 {
                found.append("The levy bar does not have the whole width of the card, from its left edge: \(bar)")
            }
        }
        // The sentences stop at the widths the design gives them, 34 em and 36 em of the 13-point type, and where the
        // room allows it a long one is set as wide as that, not held to the 416 points of the other screens.
        if key.width > 442.5 {
            found.append("The sentence of the key figure is wider than 442 points: \(key)")
        }
        if due.width > 468.5 {
            found.append("The sentence of what is left to settle is wider than 468 points: \(due)")
        }
        if (inner - 28) / 2 > 470 {
            for (name, sentence, frame) in [
                ("the key figure", page.keyFigure.sentence, key), ("what is left to settle", page.due.sentence, due),
            ] where (sentence?.count ?? 0) >= 120 && frame.width < 418 {
                found.append("The long sentence of \(name) is held to 416 points, not as wide as the design: \(frame)")
            }
        }
        let lowest = min(key.minY, items.map(\.minY).min() ?? bar.minY)
        if (lowest - 37 - due.maxY).magnitude > 1.5 {
            found.append("What is left to settle is not 37 points under the parts above it: \(due), \(key), \(items)")
        }
        if (due.minX - key.minX).magnitude > 1 {
            found.append("What is left to settle is not at the left edge of the card: \(due), \(card)")
        }
        return found
    }

    /// What is wrong with the card Příjmy of Odhad odvodů for `page` in `window`, in words: it is missing; VoiceOver
    /// does not read the income and the net income each as one phrase; the two do not stand side by side, 48 points
    /// apart and level at the top, in the card; the bar of the income (14 points high) is not 14 points under the
    /// lower of them; an item of the legend is not under the bar; or the note of the money of next year (which only a
    /// year with such money has) is not under the legend. The origin of the screen is at the bottom left, so what is
    /// above has the larger y. Empty when it stands so. Needs the accessibility elements.
    private func problems(ofTheCardPrijmyOf page: PredictionPage, in window: NSWindow) -> [String] {
        guard let card = frameOfCard(labelled: "Příjmy", in: window) else {
            return ["No card Příjmy"]
        }
        let net = page.netIncome
        let incomePhrase = [page.incomeHead, page.incomeTotal, page.incomeNote].joined(separator: ", ")
        let netPhrase = [net.label, net.amount, net.sub].joined(separator: ", ")
        guard let income = frameOfText(startingWith: incomePhrase, in: window) else {
            return ["The income is not read as one phrase: \(incomePhrase)"]
        }
        guard let netIncome = frameOfText(startingWith: netPhrase, in: window) else {
            return ["The net income is not read as one phrase: \(netPhrase)"]
        }
        guard let bar = accessibilityElement(labelled: "\(page.incomeHead): \(page.incomeTotal)", in: window)?
            .accessibilityFrame?()
        else {
            return ["No bar of the income"]
        }
        var found: [String] = []
        let inside = card.insetBy(dx: -0.5, dy: -0.5)
        for (name, frame) in [("The income", income), ("The net income", netIncome), ("The bar", bar)]
        where !inside.contains(frame) {
            found.append("\(name) is not within the card Příjmy: \(frame), the card \(card)")
        }
        if (income.maxY - netIncome.maxY).magnitude > 1 || (netIncome.minX - income.maxX - 48).magnitude > 1 {
            found.append("The net income is not beside the income, 48 points from it: \(netIncome), \(income)")
        }
        if (bar.height - 14).magnitude > 0.5 {
            found.append("The bar of the income is \(bar.height) points high, not 14")
        }
        if (min(income.minY, netIncome.minY) - 14 - bar.maxY).magnitude > 1.5 {
            found.append("The bar is not 14 points under the figures: \(bar), \(income), \(netIncome)")
        }
        var legendBottom = bar.minY
        for part in page.parts {
            guard let item = frameOfText(startingWith: part.text + ", " + part.value, in: window) else {
                found.append("No item of the legend for \(part.text)")
                continue
            }
            if item.maxY > bar.minY - 11 {
                found.append("The item \(part.text) is not under the bar: \(item), \(bar)")
            }
            legendBottom = min(legendBottom, item.minY)
        }
        if let text = page.nextYearNote {
            if let note = frameOfText(startingWith: text, in: window) {
                if note.maxY > legendBottom - 11 {
                    found.append("The note of the money of next year is not under the legend: \(note), \(legendBottom)")
                }
            } else {
                found.append("No note of the money of next year")
            }
        }
        return found
    }

    /// What is wrong with the cells of the months of the clients of `page` in `window`, in words: the months of a
    /// client are not there with all their cells, or a text of a cell needs more room than the cell gives it even when
    /// it shrinks to `scale` of its size. The cells are the children of the group of their client. Empty when the cells
    /// are whole. Needs the accessibility elements.
    private func problems(ofTheCellsOf page: PredictionPage, shrinkingTextsTo scale: CGFloat, in window: NSWindow)
        -> [String]
    {
        var found: [String] = []
        for row in page.activeRows + page.otherRows {
            guard let group = accessibilityElement(labelled: "Měsíce – \(row.name)", in: window) else {
                found.append("No months of \(row.name)")
                continue
            }
            let elements = group.accessibilityChildren?() ?? []
            guard elements.count == row.cells.count else {
                found.append("\(row.name) has \(elements.count) cells, not \(row.cells.count)")
                continue
            }
            for (cell, element) in zip(row.cells, elements) {
                guard let frame = (element as AnyObject).accessibilityFrame?() else {
                    found.append("The cell \(cell.accessibilityLabel) has no frame")
                    continue
                }
                // As the cell sets its texts: 8 points of room on either side, the label and the sub-text at 11 points,
                // the value at 12 points in digits of one width.
                let value = Text(verbatim: cell.value).font(.callout.weight(.semibold)).monospacedDigit()
                let widest = [
                    fittingSize(of: Text(verbatim: cell.label).font(.subheadline.weight(.semibold))).width,
                    fittingSize(of: value).width,
                    fittingSize(of: Text(verbatim: cell.sub).font(.subheadline)).width,
                ].max() ?? 0
                if widest * scale > frame.width - 16 + 0.5 {
                    found.append(
                        "The texts of \(cell.accessibilityLabel) need \(widest) points, even shrunk to \(scale)"
                            + " of their size it has \(frame.width - 16)")
                }
            }
        }
        return found
    }

    /// Odhad odvodů of a year without rules of its own, 2027 as of 15. 1. 2027 on the prediction sample: the warning
    /// that the page is an estimate with the rules of 2026 stands above the result card, and none of the figures of the
    /// result card or of the net income has the sign "≈", as the card is an estimate as a whole. At the least room the
    /// page fits the window, with the months of the clients folded and unfolded.
    @Test func thePredictionOfAYearWithoutItsOwnRulesFitsTheLeastRoom() async throws {
        try await PredictionSample.withStoredSample(clock: ManualClock(localNoon(2027, 1, 15))) { app in
            // The page the screen shows. The sample stores no settings of 2027, so the levies are those of the
            // defaults.
            let outcome = try await app.predictionOutcome(year: 2027)
            let page = PredictionBuilder.page(outcome)
            #expect(outcome.result.rulesAreEstimate)
            #expect(!page.keyFigure.figure.contains("≈"))
            #expect(page.levyBar.parts.allSatisfy { !$0.legendValue.contains("≈") })
            #expect(!page.due.figure.contains("≈"))
            try await withAppWindow(of: app, size: AppWindowSize.minimum) { window in
                try await withAccessibilityElements {
                    app.screen = .prediction
                    try await waitUntil { window.title == "Odhad odvodů" }
                    // The page scrolls; with the data it is far taller than while it loads.
                    try await waitUntil { (scrolledPage(in: window)?.frame.height ?? 0) > 600 }
                    try await waitUntil { frameOfCard(labelled: "Výsledek", in: window) != nil }
                    #expect(showsText(RulesWarning.message(year: 2027, rulesYear: 2026), in: window))

                    for isUnfolded in [false, true] {
                        app.predictionMonthsOpen = isUnfolded
                        app.predictionOthersOpen = isUnfolded
                        try await expectSettled(window) {
                            problems(ofThePredictionFor: page, beside: false, unfolded: isUnfolded, in: window)
                        }
                    }
                    let card = try #require(accessibilityElement(labelled: "Výsledek", in: window))
                    let readings = accessibilityReadings(under: card)
                    #expect(!readings.contains { $0.contains("≈") }, "\(readings)")
                }
            }
        }
    }

    /// Odhad odvodů runs in this order, at the least room and in a large window: the result card, the card Příjmy, the
    /// info note about what the estimate counts, the months of the clients ("Kdy čekám faktury") and "Rozpis odhadu"
    /// with its breakdown, each above the next. Nothing of the page is laid out beyond the window.
    @Test func thePredictionPageRunsResultPrijmyNoteMonthsBreakdown() async throws {
        try await PredictionSample.withStoredSample { app in
            let page = try PredictionSample.page(year: 2026)
            try await withAppWindow(of: app, size: AppWindowSize.minimum) { window in
                try await withAccessibilityElements {
                    app.screen = .prediction
                    try await waitUntil { window.title == "Odhad odvodů" }
                    try await waitUntil { (scrolledPage(in: window)?.frame.height ?? 0) > 600 }

                    for isUnfolded in [false, true] {
                        app.predictionMonthsOpen = isUnfolded
                        app.predictionOthersOpen = isUnfolded
                        for size in [AppWindowSize.minimum, AppWindowSize.large, AppWindowSize.minimum] {
                            window.setContentSize(size)
                            try await expectSettled(window) {
                                problems(ofTheOrderOfOdhadFor: page, in: window) + problems(ofPageIn: window)
                            }
                        }
                    }
                    #expect(viewsOutside(window) == [])
                }
            }
        }
    }

    /// What is wrong with the order of the page of Odhad odvodů in `window`, in words: a part is missing, or one of
    /// them is not above the next in this order: the result card, the card Příjmy, the note about what the estimate
    /// counts, the card of the months, and "Rozpis odhadu" with the first card of its breakdown, Příjmy a zisk,
    /// inside it. The cards are 16 points apart, and as wide as the page. Empty when the page runs in that order.
    /// Needs the accessibility elements.
    private func problems(ofTheOrderOfOdhadFor page: PredictionPage, in window: NSWindow) -> [String] {
        let landmarks: [(name: String, frame: CGRect?)] = [
            ("Výsledek", frameOfCard(labelled: "Výsledek", in: window)),
            ("Příjmy", frameOfCard(labelled: "Příjmy", in: window)),
            ("the note", frameOfText(startingWith: "Odhad vychází z faktur do", in: window)),
            (page.monthsHead, frameOfCard(labelled: page.monthsHead, in: window)),
            ("Rozpis odhadu", frameOfCard(labelled: "Rozpis odhadu", in: window)),
        ]
        var found: [String] = []
        for landmark in landmarks where landmark.frame == nil {
            found.append("No \(landmark.name)")
        }
        let frames = landmarks.compactMap { landmark in landmark.frame.map { (name: landmark.name, frame: $0) } }
        for (upper, lower) in zip(frames, frames.dropFirst()) {
            // The origin of the screen is at the bottom left, so what stands above has the larger y.
            let gap = upper.frame.minY - lower.frame.maxY
            if gap < 15.5 || gap > 16.5 {
                found.append("\(lower.name) is \(gap) points under \(upper.name), not 16")
            }
        }
        if let first = frames.first?.frame {
            for name in ["Příjmy", page.monthsHead] {
                guard let frame = frames.first(where: { $0.name == name })?.frame else { continue }
                if (frame.width - first.width).magnitude > 1 || (frame.minX - first.minX).magnitude > 1 {
                    found.append("\(name) is not as wide as the result card: \(frame), \(first)")
                }
            }
        }
        if let breakdown = frames.last?.frame, let income = frameOfCard(labelled: "Příjmy a zisk", in: window) {
            if !breakdown.insetBy(dx: -0.5, dy: -0.5).contains(income) {
                found.append("Příjmy a zisk is not inside Rozpis odhadu: \(income) and \(breakdown)")
            }
            if income.maxY > breakdown.maxY - 10 {
                found.append("Příjmy a zisk does not start under the heading of Rozpis odhadu")
            }
        }
        return found
    }

    /// The popover of the levy bar hangs out of the result card of Odhad odvodů, over the edge of the card and of the
    /// card Příjmy under it, and is drawn above both: the card is drawn above what follows it, and nothing clips the
    /// popover. The pointer is moved over the part of the tax, and then over its item of the legend. A strip down the
    /// popover, 6 points inside its leading edge, shows nothing but the colour of the popover while it is open, where
    /// the edges of the two cards cross it while it is closed.
    @Test func thePopoverOfTheLevyBarIsDrawnOverTheCardPrijmy() async throws {
        try await PredictionSample.withStoredSample { app in
            let page = try PredictionSample.page(year: 2026)
            let weights = page.levyBar.parts.map(\.weight)
            try await withAppWindow(of: app, size: AppWindowSize.large, ignoringTheRealPointer: true) { window in
                app.screen = .prediction
                try await waitUntil { window.title == "Odhad odvodů" }
                try await waitUntil { (scrolledPage(in: window)?.frame.height ?? 0) > 600 }

                try await withAccessibilityElements {
                    try await expectSettled(window) { problems(ofTheOrderOfOdhadFor: page, in: window) }
                    let content = try #require(window.contentView)
                    let bar = window.convertFromScreen(
                        try #require(
                            accessibilityElement(labelStartingWith: page.levyBar.header, in: window)?
                                .accessibilityFrame?()))
                    let legend = window.convertFromScreen(
                        try #require(
                            accessibilityElement(labelled: page.levyBar.parts[0].accessibilityLabel, in: window)?
                                .accessibilityFrame?()))
                    // The popover of the tax: 8 points under the legend, centred on its part and held in the panel.
                    let widths = LevyBarLayout.partWidths(weights: weights, width: bar.width)
                    let centre = LevyBarLayout.partCentres(widths: widths)[0]
                    let left = bar.minX + LevyBarLayout.popoverX(centredOn: centre, panelWidth: bar.width)
                    let top = content.bounds.height - legend.minY + LevyBarLayout.popoverGap

                    /// The points of the strip down the popover, from 4 to 100 points under its top, whose colour is
                    /// not that of the top of the strip: what is drawn over the popover while it is open.
                    @MainActor func strayPoints() throws -> [CGPoint] {
                        let picture = try WindowPicture(of: window)
                        let strip = stride(from: top + 4, to: top + 100, by: 0.5).map { CGPoint(x: left + 6, y: $0) }
                        let colour = picture.bytes(at: strip[0])
                        return strip.filter { point in
                            zip(picture.bytes(at: point), colour).contains { abs($0 - $1) > 6 }
                        }
                    }

                    // With no popover the edges of the cards cross the strip: the test can tell the two states apart.
                    let corner = CGPoint(x: 4, y: 4)
                    try await expectSettled(window) {
                        ((try? strayPoints()) ?? []).isEmpty ? ["No edge of a card crosses the strip"] : []
                    }

                    let overPart = CGPoint(x: bar.minX + 10, y: bar.midY)
                    let overLegend = CGPoint(x: legend.minX + 10, y: legend.midY)
                    for (name, pointer) in [("part", overPart), ("item of the legend", overLegend)] {
                        try movePointer(to: pointer, in: window)
                        try await waitUntil { ((try? strayPoints()) ?? [CGPoint.zero]).isEmpty }
                        #expect(try strayPoints() == [], "Drawn over the popover of the \(name)")

                        try movePointer(to: corner, in: window)
                        try await waitUntil { !((try? strayPoints()) ?? []).isEmpty }
                    }
                }
            }
        }
    }

    // MARK: Nastavení

    /// Each tab of Nastavení, on the data of `EditorFixture`: the supplier with the three accounts, the sample year and
    /// a local backup.
    @Test(arguments: SettingsTab.allCases)
    func nastaveniFitsTheWindowAtTheLeastRoomAndAtALargeSize(tab: SettingsTab) async throws {
        try await EditorFixture.with { f in
            try await withAppWindow(of: f.app, size: AppWindowSize.minimum) { window in
                f.app.showSettings(tab)
                try await waitUntil { window.title == "Nastavení" }
                // The page scrolls; with the cards of the tab it is far taller than the "Načítám…" that stands in
                // their place while the tab loads.
                try await waitUntil { (scrolledPage(in: window)?.frame.height ?? 0) > 300 }

                try await expectSettled(window) { problems(ofPageIn: window) }
                window.setContentSize(AppWindowSize.large)
                try await expectSettled(window) { problems(ofPageIn: window) }
                window.setContentSize(AppWindowSize.minimum)
                try await expectSettled(window) { problems(ofPageIn: window) }
            }
        }
    }

    /// Zabezpečení a zálohy with the notice of a change of the keys that a lock cut off, above its cards.
    @Test func zabezpeceniWithTheNoticeOfACutOffChangeFitsTheWindowAtTheLeastRoomAndAtALargeSize() async throws {
        try await EditorFixture.with { f in
            try await withAppWindow(of: f.app, size: AppWindowSize.minimum) { window in
                f.app.securityNotice =
                    "Nový kód č. 2 se nepodařilo použít – platí dál kód č. 1 z 17.\u{00A0}10.\u{00A0}2026. Nový kód"
                    + " zahoďte."
                f.app.showSettings(.security)
                try await waitUntil { window.title == "Nastavení" }
                try await waitUntil { (scrolledPage(in: window)?.frame.height ?? 0) > 300 }

                try await expectSettled(window) { problems(ofPageIn: window) }
                window.setContentSize(AppWindowSize.large)
                try await expectSettled(window) { problems(ofPageIn: window) }
                window.setContentSize(AppWindowSize.minimum)
                try await expectSettled(window) { problems(ofPageIn: window) }
            }
        }
    }

    // MARK: Nastavení stands still while a tab loads

    /// Aplikace, Moje údaje, Rok, Zabezpečení and Aplikace again, one after another. Moje údaje and Rok say "Načítám…"
    /// where their cards will be until they have read their data, on a page that has at least 160 points for them. The
    /// switcher of the tabs and the scroll view under it stay where they are on Aplikace: right after the switch,
    /// before the tab has read anything, and once it is loaded. (A page whose tab had no cards yet narrowed to the
    /// switcher and stood in the middle of the window until they came.)
    ///
    /// Right after the switch is not a matter of timing. The test is on the main actor and gives it up only at an
    /// `await`, and the read of a tab is a task of the main actor that starts once the tab is on the screen, so no read
    /// has run when the page is laid out and looked at in the same turn of the run loop.
    @Test func theSettingsTabSwitcherStaysPutWhileATabLoads() async throws {
        try await EditorFixture.with { f in
            try await withAppWindow(of: f.app, size: AppWindowSize.minimum) { window in
                f.app.showSettings(.application)
                try await waitUntil { window.title == "Nastavení" }
                try await withAccessibilityElements {
                    try await waitUntil { frameOfCard(labelled: "Vzhled", in: window) != nil }
                    try await layOut(window)
                    let home = try #require(settingsPageFrames(in: window))

                    // Each tab, with the card that comes with its data and whether "Načítám…" stands in its place.
                    let steps: [(tab: SettingsTab, card: String, loads: Bool)] = [
                        (.supplier, "Vaše údaje", true), (.year, "Profil", true), (.security, "Odemykání", false),
                        (.application, "Vzhled", false),
                    ]
                    for (tab, card, loads) in steps {
                        let name = tab.title(year: f.app.asOf.year)
                        let loading = { frameOfText(startingWith: "Načítám…", in: window) != nil }
                        let hasCards = { frameOfCard(labelled: card, in: window) != nil }

                        f.app.settingsTab = tab
                        layOutAtOnce(window)
                        #expect(problems(ofSettingsPageIn: window, comparedTo: home) == [], "right after \(name)")
                        #expect(loading() == loads, "\(name) says it loads: \(loading())")
                        #expect(hasCards() != loads, "\(name) shows its cards: \(hasCards())")
                        if loads {
                            let room = scrolledPage(in: window)?.frame.height ?? 0
                            #expect(room >= 160, "\(name) keeps \(room) points for its cards")
                        }

                        try await waitUntil { hasCards() }
                        try await layOut(window)
                        #expect(problems(ofSettingsPageIn: window, comparedTo: home) == [], "once \(name) is loaded")
                        #expect(!loading(), "\(name) says it loads once it is loaded")
                    }
                }
            }
        }
    }

    /// What is typed in Moje údaje stays where it was typed through a reload of the tab, which a bump of the version of
    /// the data brings: the field is the one that was typed in, with its text and the focus, not one made anew behind
    /// "Načítám…", and the typed street is what is saved by itself. A field that was not typed in shows what the reload
    /// has read.
    @Test func typingInMojeÚdajeSurvivesAReload() async throws {
        // The field takes the focus, so the test takes its turn among the tests that type.
        try await whileTypingAlone {
            try await EditorFixture.with { f in
                try await withAppWindow(of: f.app, size: AppWindowSize.minimum) { window in
                    window.makeKeyAndOrderFront(nil)
                    f.app.showSettings(.supplier)
                    try await waitUntil { window.title == "Nastavení" }
                    try await withAccessibilityElements {
                        try await waitUntil { textField(labelled: "Ulice a číslo", in: window) != nil }
                        let street = try #require(textField(labelled: "Ulice a číslo", in: window))
                        let city = { textField(labelled: "Město", in: window)?.stringValue }
                        #expect(city() == "Praha")

                        // The city is written behind the back of the tab, which does not know it until it reads again.
                        let database = try #require(f.app.database)
                        var elsewhere = try await database.supplier()
                        elsewhere.city = "Plzeň"
                        try await database.saveSupplier(elsewhere)

                        // No `await` from the typing to the look: the tab has been told to read, and has not read.
                        try type("Nová ulice 1", into: street, in: window)
                        f.app.reloadScreens()
                        layOutAtOnce(window)
                        #expect(frameOfText(startingWith: "Načítám…", in: window) == nil)
                        #expect(textField(labelled: "Ulice a číslo", in: window) === street)
                        #expect(street.stringValue == "Nová ulice 1")
                        #expect(city() == "Praha")

                        try await waitUntil { city() == "Plzeň" }
                        try await layOut(window)
                        #expect(textField(labelled: "Ulice a číslo", in: window) === street)
                        #expect(street.stringValue == "Nová ulice 1")
                        #expect(window.firstResponder === street.currentEditor())
                        try await waitUntil { try await database.supplier().street == "Nová ulice 1" }
                    }
                }
            }
        }
    }

    /// The cards of Rok stay while the tab reads another year, which is chosen in the toolbar: the tab shows the year
    /// it has until the one chosen is read, with no "Načítám…" between them.
    @Test func theCardsOfRokStayWhileAnotherYearLoads() async throws {
        try await EditorFixture.with { f in
            try await withAppWindow(of: f.app, size: AppWindowSize.minimum) { window in
                f.app.showSettings(.year)
                try await waitUntil { window.title == "Nastavení" }
                try await withAccessibilityElements {
                    try await waitUntil { frameOfCard(labelled: "Profil", in: window) != nil }
                    try await layOut(window)

                    f.app.selectYear(2025)
                    layOutAtOnce(window)
                    #expect(frameOfText(startingWith: "Načítám…", in: window) == nil)
                    #expect(frameOfCard(labelled: "Profil", in: window) != nil)
                    #expect(frameOfText(startingWith: "Platí jen pro rok 2026", in: window) != nil)

                    try await waitUntil { frameOfText(startingWith: "Platí jen pro rok 2025", in: window) != nil }
                    try await layOut(window)
                    #expect(frameOfText(startingWith: "Načítám…", in: window) == nil)
                    #expect(frameOfCard(labelled: "Profil", in: window) != nil)
                }
            }
        }
    }

    /// The switcher of the tabs stands above what scrolls: with the page of each tab scrolled to its end, at the least
    /// room the window gives, the switcher is where it was. (Some pages are barely longer than the window, and some
    /// are hundreds of points longer, so at least one of them has to have scrolled a long way.)
    @Test func theSettingsTabSwitcherDoesNotScrollWithThePage() async throws {
        try await EditorFixture.with { f in
            try await withAppWindow(of: f.app, size: AppWindowSize.minimum) { window in
                f.app.showSettings(.application)
                try await waitUntil { window.title == "Nastavení" }
                try await withAccessibilityElements {
                    var farthest: CGFloat = 0
                    for tab in SettingsTab.allCases {
                        let name = tab.title(year: f.app.asOf.year)
                        f.app.settingsTab = tab
                        // The page scrolls; with the cards of the tab it is far taller than the "Načítám…" that
                        // stands in their place while the tab loads.
                        try await waitUntil { (scrolledPage(in: window)?.frame.height ?? 0) > 300 }
                        try await layOut(window)
                        let home = try #require(settingsPageFrames(in: window))
                        let start = frameInWindow(try #require(scrolledPage(in: window)))

                        scrollPage(in: window, toEnd: true)
                        try await layOut(window)
                        let end = frameInWindow(try #require(scrolledPage(in: window)))
                        farthest = max(farthest, (end.minY - start.minY).magnitude)
                        #expect(problems(ofSettingsPageIn: window, comparedTo: home) == [], "at the end of \(name)")

                        scrollPage(in: window, toEnd: false)
                        try await layOut(window)
                    }
                    #expect(farthest > 100, "the page that scrolled the farthest scrolled \(farthest) points")
                }
            }
        }
    }

    /// The tabs of Nastavení are the segmented control of the design, not the one macOS draws: VoiceOver reads the
    /// group "Části nastavení" with a button for each tab, of which the shown one is selected, 28 points tall on a
    /// track that leaves 2 points around them. A press on another tab, as VoiceOver makes it, shows that tab. The
    /// control is as wide as its tabs, at the leading edge of the page, and does not fill the page.
    @Test func theTabsOfNastaveniAreTheSegmentedControlOfTheDesign() async throws {
        try await EditorFixture.with { f in
            try await withAppWindow(of: f.app, size: AppWindowSize.minimum) { window in
                f.app.showSettings(.application)
                try await waitUntil { window.title == "Nastavení" }
                try await withAccessibilityElements {
                    try await waitUntil { accessibilityElement(labelled: "Části nastavení", in: window) != nil }
                    let group = try #require(accessibilityElement(labelled: "Části nastavení", in: window))
                    #expect(group.accessibilityRole?() == .group)
                    // It is the design's own control, found by its name: no system one.
                    #expect(segmentedControls(in: try #require(window.contentView)).isEmpty)
                    let titles = SettingsTab.allCases.map { $0.title(year: f.app.asOf.year) }
                    #expect(titles == ["Aplikace", "Moje údaje", "Zabezpečení a zálohy", "Rok 2026"])

                    var tabFrames: [CGRect] = []
                    for title in titles {
                        let tab = try #require(accessibilityButton(labelled: title, in: window), "No tab \(title)")
                        let frame = try #require(tab.accessibilityFrame?())
                        #expect(abs(frame.height - 28) < 0.5, "\(title) is \(frame.height) points tall")
                        tabFrames.append(frame)
                    }
                    #expect(accessibilityButton(labelled: "Aplikace", in: window)?.isAccessibilitySelected?() == true)
                    #expect(
                        accessibilityButton(labelled: "Moje údaje", in: window)?.isAccessibilitySelected?() != true)

                    // The track holds the tabs in a row with 2 points around them, and is as wide as they are.
                    let track = try #require(group.accessibilityFrame?())
                    #expect(abs(track.height - 32) < 0.5, "The track is \(track.height) points tall")
                    let tabs = tabFrames.reduce(CGRect.null) { $0.union($1) }
                    #expect(abs(track.width - (tabs.width + 4)) < 0.5, "The track is \(track.width) points wide")
                    #expect(track.width < 600, "The tabs fill the page: \(track.width) points")
                    try await waitUntil { frameOfCard(labelled: "Vzhled", in: window) != nil }
                    let card = try #require(frameOfCard(labelled: "Vzhled", in: window))
                    #expect(
                        abs(track.minX - card.minX) < 1, "The tabs start at \(track.minX), the cards at \(card.minX)")

                    // A press on another tab shows it.
                    let supplier = try #require(accessibilityButton(labelled: "Moje údaje", in: window))
                    #expect(supplier.accessibilityPerformPress?() == true)
                    try await waitUntil { f.app.settingsTab == .supplier }
                    try await waitUntil {
                        accessibilityButton(labelled: "Moje údaje", in: window)?.isAccessibilitySelected?() == true
                    }
                    #expect(accessibilityButton(labelled: "Aplikace", in: window)?.isAccessibilitySelected?() != true)
                    try await waitUntil { frameOfCard(labelled: "Vaše údaje", in: window) != nil }
                }
            }
        }
    }

    /// A tab that cannot read its data says so, and does not say "Načítám…" beside it for ever.
    @Test func aTabThatCannotReadItsDataSaysSoAndDoesNotKeepLoading() async throws {
        try await EditorFixture.with { f in
            try await withAppWindow(of: f.app, size: AppWindowSize.minimum) { window in
                f.app.showSettings(.application)
                try await waitUntil { window.title == "Nastavení" }
                try await withAccessibilityElements {
                    try await waitUntil { frameOfCard(labelled: "Vzhled", in: window) != nil }
                    // Every read of the data fails from now on.
                    await f.database.close()

                    let failures: [(tab: SettingsTab, text: String)] = [
                        (.supplier, SupplierTabModel.loadFailureText), (.year, YearTabModel.loadFailureText),
                    ]
                    for (tab, text) in failures {
                        f.app.settingsTab = tab
                        try await waitUntil { frameOfText(startingWith: text, in: window) != nil }
                        try await layOut(window)
                        #expect(frameOfText(startingWith: "Načítám…", in: window) == nil, "\(tab) says: \(text)")
                    }
                }
            }
        }
    }

    /// Where the page of Nastavení stands: the switcher of the tabs in the coordinates of the screen and the scroll
    /// view under it in those of the window.
    private struct SettingsPageFrames {
        var switcher: CGRect
        var scrollView: CGRect
    }

    /// The frames of the page of Nastavení in `window`, or nil while it has no switcher or no scroll view. The switcher
    /// is the group that VoiceOver reads as "Části nastavení" (`SegmentedControl`), in the coordinates of the screen,
    /// so the views of the window have to make their accessibility elements (`withAccessibilityElements(_:)`).
    private func settingsPageFrames(in window: NSWindow) -> SettingsPageFrames? {
        guard let content = window.contentView,
            let switcher = accessibilityElement(labelled: "Části nastavení", in: window)?.accessibilityFrame?(),
            let scrollView = scrollViews(in: content).first(where: { !($0.documentView is NSTableView) })
        else {
            return nil
        }
        return SettingsPageFrames(switcher: switcher, scrollView: frameInWindow(scrollView))
    }

    /// What is wrong with the page of Nastavení in `window`, in words: the switcher of the tabs or the scroll view is
    /// not where `home` has it. Empty while the page stands still.
    private func problems(ofSettingsPageIn window: NSWindow, comparedTo home: SettingsPageFrames) -> [String] {
        guard let frames = settingsPageFrames(in: window) else {
            return ["The page has no switcher of the tabs or no scroll view"]
        }
        var problems: [String] = []
        if !isSame(frames.switcher, as: home.switcher) {
            problems.append("The switcher of the tabs is at \(frames.switcher), not at \(home.switcher)")
        }
        if !isSame(frames.scrollView, as: home.scrollView) {
            problems.append("The scroll view of the page is at \(frames.scrollView), not at \(home.scrollView)")
        }
        return problems
    }

    /// Whether `frame` is `other` within half a point in its position and its size.
    private func isSame(_ frame: CGRect, as other: CGRect) -> Bool {
        (frame.minX - other.minX).magnitude < 0.5 && (frame.minY - other.minY).magnitude < 0.5
            && (frame.width - other.width).magnitude < 0.5 && (frame.height - other.height).magnitude < 0.5
    }

    /// Lays `window` out once, at once: no turn of the run loop passes, so what the app does in tasks of its own, such
    /// as the read of the data that a tab starts once it is on the screen, has not run when this returns.
    /// `layOut(_:)` lets the run loop turn.
    private func layOutAtOnce(_ window: NSWindow) {
        window.contentView?.needsLayout = true
        window.layoutIfNeeded()
        window.displayIfNeeded()
    }

    /// Scrolls the page of Nastavení in `window` as far as it goes towards its end, or back to its start.
    private func scrollPage(in window: NSWindow, toEnd: Bool) {
        guard let page = scrolledPage(in: window) else { return }
        // The bottom of the page is its larger y when the view is flipped, and its smaller y when it is not.
        let bottom = page.isFlipped ? page.bounds.maxY - 1 : page.bounds.minY
        let top = page.isFlipped ? page.bounds.minY : page.bounds.maxY - 1
        page.scrollToVisible(NSRect(x: page.bounds.minX, y: toEnd ? bottom : top, width: 1, height: 1))
    }

    /// Types `text` into `field` as a person does: the field takes the focus and its text is replaced, and the change
    /// reaches the binding as the keys do.
    private func type(_ text: String, into field: NSTextField, in window: NSWindow) throws {
        #expect(window.makeFirstResponder(field))
        let editor = try #require(field.currentEditor() as? NSTextView)
        editor.selectAll(nil)
        editor.insertText(text, replacementRange: editor.selectedRange())
    }

    /// The segmented controls under `view`.
    private func segmentedControls(in view: NSView) -> [NSSegmentedControl] {
        if let control = view as? NSSegmentedControl {
            return [control]
        }
        return view.subviews.flatMap { segmentedControls(in: $0) }
    }

    // MARK: Import

    /// What Import shows.
    enum ImportScene: CaseIterable, Sendable {
        /// Only the choice of files.
        case choosing

        /// Two files that are read, and the import that goes on.
        case running

        /// The summary of an import, with the lists of what is to check and not added, and the offer to fill the
        /// supplier.
        case done

        /// A file that is no export, with the line that says nothing was imported.
        case failed
    }

    /// Import in each of its states, at the least room, at a large size and at the least room again. The page holds the
    /// card of the files and, below it, the card of the progress, which grow with what they list.
    @Test(arguments: ImportScene.allCases)
    func importFitsTheWindowAtTheLeastRoomAndAtALargeSize(scene: ImportScene) async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let gate = Gate()
        let yearly = try Data(contentsOf: fixtureURL("cnb_rok_2026", "txt"))
        let server = StubHTTPClient([CNBEndpoints.yearly(2026): yearly])
        let app = makeAppModel(in: directory, http: GatedHTTPClient(base: server, gate: gate))
        try await startFresh(app)
        let model = app.importModel
        let sample = try fixtureURL("fakturoid_sample", "csv")
        let reimport = try fixtureURL("fakturoid_reimport", "csv")
        var running: Task<Void, Never>?
        switch scene {
        case .choosing:
            break
        case .running:
            running = Task { await model.importFiles([sample, reimport]) }
            await gate.untilARequestWaits()
        case .done:
            await gate.open()
            // An invoice of the app has the number of one of the rows: a line of what could not be added.
            try await #require(app.database).saveInvoice(Invoice.fixture(number: "20261008"))
            await model.importFiles([sample])
        case .failed:
            await gate.open()
            let bank = try writeCSV("Date,Amount\n2026-10-01,5\n", named: "bank.csv", in: directory)
            await model.importFiles([sample, bank])
        }

        do {
            try await withAppWindow(of: app, size: AppWindowSize.minimum) { window in
                app.screen = .importer
                try await waitUntil { window.title == "Import faktur" }
                // The page scrolls; with its cards it is taller than the margins and the line over them.
                try await waitUntil { (scrolledPage(in: window)?.frame.height ?? 0) > 200 }

                try await expectSettled(window) { problems(ofPageIn: window) }
                window.setContentSize(AppWindowSize.large)
                try await expectSettled(window) { problems(ofPageIn: window) }
                window.setContentSize(AppWindowSize.minimum)
                try await expectSettled(window) { problems(ofPageIn: window) }
            }
        } catch {
            // An import that is held back must not outlive a test that failed.
            await gate.open()
            throw error
        }
        await gate.open()
        await running?.value
        switch scene {
        case .done:
            #expect(model.summary?.conflicts == 1 && model.canFillSupplier)
        case .failed:
            #expect(model.failure != nil)
        case .running, .choosing:
            break
        }
    }

    // MARK: Simulátor

    /// The cards of the Simulátor by the labels VoiceOver reads them under: the four of the inputs, the two of the
    /// family after them, which the Simulátor's design reads as "… v simulaci", the result of the year the app shows
    /// (which holds the net income and the marginal levy, so they are no cards of their own), and the four of the
    /// breakdown below them, the last of which is the net income.
    private static let simulatorCards = [
        "Rok a příjem", "Úroky z úvěru na bydlení", "Spoření a pojištění na stáří", "Dary a slevy na dani",
        Self.simulatorChildrenCard, Self.simulatorSpouseCard, "Kolik zaplatíte", "Daň z příjmů", "Sociální pojištění",
        "Zdravotní pojištění", "Čistý příjem",
    ]

    /// The labels the two cards of the family are read under in the Simulátor.
    private static let simulatorChildrenCard = "Děti v simulaci"
    private static let simulatorSpouseCard = "Manžel nebo manželka v simulaci"

    /// The Simulátor of the year the app shows, on the data of `EditorFixture`, whose stored settings of 2026 are what
    /// the copy brings: at the least room, at a large size and at the least room again, every card is on the
    /// page, none runs out of it sideways and none lies over another. So it is with the cards of the family empty, and
    /// with the sample family copied into them, where the longer texts of the cards are whole within them: without
    /// income the children's benefit is not paid as a bonus, and the box says why. Either way the card of the children
    /// says beside Přidat dítě that nothing of the simulation is stored.
    @Test(arguments: [false, true])
    func theSimulatorFitsTheSmallestAndTheLargestWindow(withTheFamily: Bool) async throws {
        try await EditorFixture.with { f in
            if withTheFamily {
                try await Self.storeTheSampleFamily(in: f.database)
                await f.app.didWriteAndBackUp()
            }
            try await withAppWindow(of: f.app, size: AppWindowSize.minimum) { window in
                f.app.screen = .simulator
                try await waitUntil { window.title == "Simulátor" }
                // The screen has the settings of its year read, which is when the copy is on offer.
                try await waitUntil { f.app.simulatorModel.canCopyDeductionsAndFamily }
                if withTheFamily {
                    await f.app.simulatorModel.copyDeductionsAndFamily()
                }
                // The page scrolls; with its cards it is far taller than the banner over them.
                try await waitUntil { (scrolledPage(in: window)?.frame.height ?? 0) > 600 }

                try await withAccessibilityElements {
                    if withTheFamily {
                        let hint = Self.simulatorFamilyTexts[0].prefix
                        try await waitUntil { frameOfText(startingWith: hint, in: window) != nil }
                    }
                    for size in [AppWindowSize.minimum, AppWindowSize.large, AppWindowSize.minimum] {
                        window.setContentSize(size)
                        try await expectSettled(window) {
                            problems(ofSimulatorIn: window)
                                + (withTheFamily ? problems(ofSimulatorFamilyIn: window) : [])
                                + problems(ofSimulationNoteIn: window)
                        }
                    }
                }
            }
        }
    }

    /// The longer texts of the cards of the family in the Simulátor with the sample family and no income, by how each
    /// begins, with the card they are in and the font they are set in.
    private static let simulatorFamilyTexts: [(prefix: String, card: String, font: Font)] = [
        ("Zvýhodnění převyšuje daň o 37\u{00A0}524\u{00A0}Kč, bonus se ale nevyplatí", simulatorChildrenCard, .callout),
        ("Za každý měsíc, na jehož začátku", simulatorChildrenCard, .callout),
        ("Dítě do 3 let ve společné domácnosti: Tomáš", simulatorSpouseCard, .body),
        ("Hrubé příjmy za celý rok", simulatorSpouseCard, .callout),
        ("Sleva za 12\u{00A0}měsíců: 24\u{00A0}840\u{00A0}Kč – daň už je nulová", simulatorSpouseCard,
            .body.weight(.semibold)),
    ]

    /// What the card of the children of the Simulátor says beside Přidat dítě.
    private static let simulationNote = "Jen pro simulaci – nic se neukládá."

    /// What is wrong with the note beside Přidat dítě in the card of the children of the Simulátor in `window`, in
    /// words: it is missing, not within its card, lower than it needs to be at its width, as a text cut short would be,
    /// or not on the line of the button, after it. Empty when it is right. Needs the accessibility elements.
    private func problems(ofSimulationNoteIn window: NSWindow) -> [String] {
        guard let card = frameOfCard(labelled: Self.simulatorChildrenCard, in: window) else {
            return ["No card \(Self.simulatorChildrenCard)"]
        }
        guard let note = frameOfText(startingWith: Self.simulationNote, in: window) else {
            return ["No note \(Self.simulationNote)"]
        }
        guard let button = accessibilityButton(labelled: "Přidat dítě", in: window)?.accessibilityFrame?() else {
            return ["No button Přidat dítě"]
        }
        var found = problems(ofText: Self.simulationNote, frame: note, font: .callout, within: card, in: window)
        if note.minX < button.maxX || abs(note.midY - button.midY) > 2 {
            found.append("The note \(note) is not beside the button \(button)")
        }
        return found
    }

    /// What VoiceOver reads for the rows of the sample family in the Simulátor.
    private static let simulatorFamilyRows = [
        "Anna · nar. 3.\u{00A0}9.\u{00A0}2019, 1. dítě · 12\u{00A0}měsíců, 15\u{00A0}204\u{00A0}Kč",
        "Tomáš · nar. 12.\u{00A0}4.\u{00A0}2024, 2. dítě · 12\u{00A0}měsíců, 22\u{00A0}320\u{00A0}Kč",
    ]

    /// What is wrong with the cards of the family of the Simulátor in `window`, in words: a text or a row of a child
    /// that is missing or not within its card, and a text that is lower than it needs to be at its width, as a text
    /// cut short would be. Empty when the cards fit. Needs the accessibility elements.
    private func problems(ofSimulatorFamilyIn window: NSWindow) -> [String] {
        var found: [String] = []
        for (prefix, label, font) in Self.simulatorFamilyTexts {
            guard let card = frameOfCard(labelled: label, in: window) else {
                return ["No card \(label)"]
            }
            guard let frame = frameOfText(startingWith: prefix, in: window) else {
                found.append("No text \(prefix)")
                continue
            }
            found += problems(ofText: prefix, frame: frame, font: font, within: card, in: window)
        }
        guard let children = frameOfCard(labelled: Self.simulatorChildrenCard, in: window) else {
            return found + ["No card \(Self.simulatorChildrenCard)"]
        }
        for row in Self.simulatorFamilyRows {
            guard let frame = accessibilityButton(labelled: row, in: window)?.accessibilityFrame?() else {
                found.append("No row \(row)")
                continue
            }
            if frame.minX < children.minX - 0.5 || frame.maxX > children.maxX + 0.5
                || frame.minY < children.minY - 0.5
            {
                found.append("The row \(row) is not within its card: \(frame), the card \(children)")
            }
        }
        return found
    }

    /// The assumptions of the Simulátor (the flat-rate expenses, the activity and its months) with the longest texts
    /// they can show: the box of the health minimum with its line, which Vedlejší shows under the menu Činnost, and
    /// the note of the expenses with both sentences that can follow its figures. The rate of 30 % is stored in the
    /// settings of 2026 before the Simulátor reads them, so that it comes from there and is not picked: the note says
    /// so ("Předvyplněno podle Nastavení roku 2026.") and then adds the sentence about rent that the rate of 30 %
    /// brings. At the least room, at a large size and at the least room again, the box, its line and the note are
    /// whole and within their card, the box in its place under the menu and the note under the choices, and none of
    /// the parts of the assumptions lies over another, whichever way the three choices are arranged. At a large size
    /// they stand in one row, the menu of the rate, the menu Činnost and the field of the months with their tops
    /// level, though the line under the box is long: it breaks within a width of its own and does not widen the
    /// column of the activity.
    @Test func theSimulatorFitsTheLeastRoomWithTheLongestTextsOfItsAssumptions() async throws {
        try await EditorFixture.with { f in
            try await f.database.updateYearSettings(2026) { $0.expensePercent = 30 }
            await f.app.didWriteAndBackUp()
            try await withAppWindow(of: f.app, size: AppWindowSize.minimum) { window in
                f.app.screen = .simulator
                try await waitUntil { window.title == "Simulátor" }
                try await waitUntil { f.app.simulatorModel.canCopyDeductionsAndFamily }
                f.app.simulatorModel.setActivity(.secondary)
                let expenseNote = try #require(f.app.simulatorModel.page?.expenseNote)
                #expect(expenseNote.hasSuffix(" Předvyplněno podle Nastavení roku 2026. " + Self.rentNote))
                // The page scrolls; with its cards it is far taller than the banner over them.
                try await waitUntil { (scrolledPage(in: window)?.frame.height ?? 0) > 600 }

                try await withAccessibilityElements {
                    try await waitUntil { frameOfText(startingWith: Self.healthSwitchNote, in: window) != nil }
                    try await waitUntil { frameOfText(startingWith: expenseNote, in: window) != nil }
                    for size in [AppWindowSize.minimum, AppWindowSize.large, AppWindowSize.minimum] {
                        window.setContentSize(size)
                        try await expectSettled(window) {
                            problems(ofSimulatorIn: window) + problems(ofTheHealthSwitchIn: window)
                                + problems(ofTheExpenseNote: expenseNote, in: window)
                                + (size == AppWindowSize.large ? problems(ofTheChoicesInOneRowIn: window) : [])
                        }
                    }
                }
            }
        }
    }

    /// The sentence that the rate of 30 % adds to the note of the expenses of the Simulátor, and puts under the menu of
    /// the rate in Zálohy a odpočty.
    private static let rentNote = "Běžný pronájem podle § 9 aplikace nepočítá – není to příjem z podnikání."

    /// What is wrong with the note of the expenses in the Simulátor of `window`, which has Vedlejší chosen, in words:
    /// `note`, the whole text, is missing or not within the card "Rok a příjem", is lower than its whole text needs at
    /// its width, as a text cut short would be, or is not under the choices: the menus of the rate and of the activity,
    /// the box of the health minimum with its line, and the field of the months. Empty when it fits. Needs the
    /// accessibility elements.
    private func problems(ofTheExpenseNote note: String, in window: NSWindow) -> [String] {
        guard let card = frameOfCard(labelled: "Rok a příjem", in: window) else { return ["No card Rok a příjem"] }
        guard let frame = frameOfText(startingWith: note, in: window) else { return ["No note \(note)"] }
        var found = problems(ofText: note, frame: frame, font: .callout, within: card, in: window)
        // The origin of the screen is at the bottom left, so what is under has the smaller y.
        for label in ["Výdaje paušálem", "Činnost", "Měsíců činnosti", Self.healthSwitchLabel] {
            guard let part = accessibilityElement(labelled: label, in: window)?.accessibilityFrame?() else {
                found.append("No \(label)")
                continue
            }
            if frame.maxY > part.minY + 0.5 {
                found.append("The note is not under \(label): \(frame), \(label) \(part)")
            }
        }
        if let line = frameOfText(startingWith: Self.healthSwitchNote, in: window), frame.maxY > line.minY + 0.5 {
            found.append("The note is not under the line of the box: \(frame), the line \(line)")
        }
        return found
    }

    /// The box of the health minimum that Vedlejší shows in the Simulátor, by the label VoiceOver reads it under, and
    /// the line under it.
    private static let healthSwitchLabel = "Bez minima zdravotního pojištění"
    private static let healthSwitchNote =
        "Po celé měsíce činnosti jste zároveň zaměstnaní s pojistným aspoň z minimální mzdy, studujete,"
        + " pobíráte důchod, jste na rodičovské, máte průkaz ZTP/P a podobně."

    /// What is wrong with the box of the health minimum in the Simulátor of `window`, which has Vedlejší chosen, in
    /// words: the box or its line is missing or not within the card "Rok a příjem", the box is lower than it needs to
    /// be at its width or the line lower than its whole text needs, as a text cut short would be, the box is not under
    /// the menu Činnost or the line not under the box, or two parts of the assumptions lie over each other. Empty
    /// when they fit. Needs the accessibility elements.
    private func problems(ofTheHealthSwitchIn window: NSWindow) -> [String] {
        guard let card = frameOfCard(labelled: "Rok a příjem", in: window) else { return ["No card Rok a příjem"] }
        guard let box = accessibilityElement(labelled: Self.healthSwitchLabel, in: window)?.accessibilityFrame?()
        else {
            return ["No box \(Self.healthSwitchLabel)"]
        }
        guard let line = frameOfText(startingWith: Self.healthSwitchNote, in: window) else {
            return ["No line \(Self.healthSwitchNote)"]
        }
        var found: [String] = []
        if box.minX < card.minX - 0.5 || box.maxX > card.maxX + 0.5 {
            found.append("The box \(Self.healthSwitchLabel) is not within its card: \(box), the card \(card)")
        }
        let toggle = Toggle(Self.healthSwitchLabel, isOn: .constant(false)).toggleStyle(.checkbox)
        found += problems(of: Self.healthSwitchLabel, frame: box, needing: toggle)
        found += problems(ofText: Self.healthSwitchNote, frame: line, font: .callout, within: card, in: window)

        // The parts of the assumptions that stand near the box: the menus of the rate and of the activity, and the
        // field of the months.
        var parts: [(name: String, frame: CGRect)] = [("the box", box), ("the line under it", line)]
        for label in ["Výdaje paušálem", "Činnost", "Měsíců činnosti"] {
            guard let frame = accessibilityElement(labelled: label, in: window)?.accessibilityFrame?() else {
                found.append("No \(label)")
                continue
            }
            parts.append((name: label, frame: frame))
            // The origin of the screen is at the bottom left, so what is under has the smaller y.
            if label == "Činnost" && box.maxY > frame.minY + 0.5 {
                found.append("The box is not under the menu Činnost: \(box), the menu \(frame)")
            }
        }
        if line.maxY > box.minY + 0.5 {
            found.append("The line is not under the box: \(line), the box \(box)")
        }
        for (index, first) in parts.enumerated() {
            for second in parts[(index + 1)...] where first.frame.insetBy(dx: 0.5, dy: 0.5).intersects(second.frame) {
                found.append("\(first.name) lies over \(second.name): \(first.frame) and \(second.frame)")
            }
        }
        return found
    }

    /// What is wrong with how the three choices of the assumptions of the Simulátor stand in `window` if they are to
    /// stand in one row, in words: the menu of the rate, the menu Činnost or the field of the months is missing, one
    /// does not have its top level with the one before it, or it is not to the right of it. Empty when they stand so.
    /// Needs the accessibility elements.
    private func problems(ofTheChoicesInOneRowIn window: NSWindow) -> [String] {
        var choices: [(name: String, frame: CGRect)] = []
        for label in ["Výdaje paušálem", "Činnost", "Měsíců činnosti"] {
            guard let frame = accessibilityElement(labelled: label, in: window)?.accessibilityFrame?() else {
                return ["No \(label)"]
            }
            choices.append((name: label, frame: frame))
        }
        var found: [String] = []
        for (index, choice) in choices.enumerated().dropFirst() {
            let before = choices[index - 1]
            // The origin of the screen is at the bottom left, so a top is the largest y.
            if (choice.frame.maxY - before.frame.maxY).magnitude > 1 {
                found.append("\(choice.name) is not level with \(before.name): \(choice.frame), \(before.frame)")
            }
            if choice.frame.minX < before.frame.maxX - 0.5 {
                found.append("\(choice.name) is not to the right of \(before.name): \(choice.frame), \(before.frame)")
            }
        }
        return found
    }

    /// At the least room the app allows, the result stands to the right of the year and the income, its top level with
    /// theirs, in a column of 360 points, 16 points from the inputs, and not under them.
    @Test func theResultsStandBesideTheInputsAtTheSmallestWindow() async throws {
        try await EditorFixture.with { f in
            try await withAppWindow(of: f.app, size: AppWindowSize.minimum) { window in
                f.app.screen = .simulator
                try await waitUntil { window.title == "Simulátor" }
                try await waitUntil { (scrolledPage(in: window)?.frame.height ?? 0) > 600 }

                try await withAccessibilityElements {
                    try await expectSettled(window) { problems(ofResultsBesideInputsIn: window) }
                }
            }
        }
    }

    /// The result card of the Simulátor holds, from the top, the key figure, the bar of the levies, the net income and
    /// the marginal levy, in a card padded 20: the parts are 14 points apart, and each of the last two stands under a
    /// hairline with 12 points under it. It is 360 points wide beside the inputs, at the least room and in a large
    /// window, and as wide as the page under them where the sidebar is as wide as it goes. Without income the key
    /// figure asks for it and the net income is negative; the parts stand the same.
    @Test(arguments: ["2 500 000", ""])
    func theResultCardOfTheSimulatorStacksTheKeyFigureTheBarTheNetIncomeAndTheMarginalLevy(
        income: String
    ) async throws {
        try await EditorFixture.with { f in
            try await withAppWindow(of: f.app, size: AppWindowSize.minimum) { window in
                f.app.screen = .simulator
                try await waitUntil { window.title == "Simulátor" }
                try await waitUntil { (scrolledPage(in: window)?.frame.height ?? 0) > 600 }
                let model = f.app.simulatorModel
                model.setIncomeText(income)
                model.readTypedTexts()
                let summary = try #require(model.page?.summary)

                try await withAccessibilityElements {
                    for size in [AppWindowSize.minimum, AppWindowSize.large, AppWindowSize.minimum] {
                        window.setContentSize(size)
                        try await expectSettled(window) {
                            problems(ofTheResultCardOfTheSimulatorFor: summary, under: false, in: window)
                        }
                    }
                    widenSidebar(of: window)
                    try await waitUntil { (frameOfCard(labelled: "Kolik zaplatíte", in: window)?.width ?? 0) > 600 }
                    try await expectSettled(window) {
                        problems(ofTheResultCardOfTheSimulatorFor: summary, under: true, in: window)
                    }
                }
            }
        }
    }

    /// The net income stands in the result card of the Simulátor under the bar of the levies and above the marginal
    /// levy, at the least room, at a large size and at the least room again, whether the levies are more than the
    /// income (the amount is then negative, as it is while the income is 0) or not: VoiceOver reads its words, the
    /// average per month and the line under them as one phrase. With the sidebar as wide as it goes, the results come
    /// under the inputs, in a card as wide as the page, and the amount stands beside its words: the net income is two
    /// lines of text tall, not three.
    @Test(arguments: ["0", "2 500 000"])
    func theNetIncomeStandsUnderTheBarOfTheLeviesAndAboveTheMarginalLevyWhetherOrNotTheLeviesAreMoreThanTheIncome(
        income: String
    ) async throws {
        try await EditorFixture.with { f in
            try await withAppWindow(of: f.app, size: AppWindowSize.minimum) { window in
                f.app.screen = .simulator
                try await waitUntil { window.title == "Simulátor" }
                try await waitUntil { (scrolledPage(in: window)?.frame.height ?? 0) > 600 }
                let model = f.app.simulatorModel
                model.setIncomeText(income)
                model.readTypedTexts()
                let summary = try #require(model.page?.summary)
                #expect(summary.netIncome.amount.hasPrefix("\u{2212}") == (income == "0"))

                try await withAccessibilityElements {
                    for size in [AppWindowSize.minimum, AppWindowSize.large, AppWindowSize.minimum] {
                        window.setContentSize(size)
                        try await expectSettled(window) { problems(ofTheNetIncomeOf: summary, in: window) }
                    }
                    widenSidebar(of: window)
                    try await waitUntil { (frameOfCard(labelled: "Kolik zaplatíte", in: window)?.width ?? 0) > 600 }
                    try await expectSettled(window) { problems(ofTheNetIncomeOf: summary, in: window) }
                    let line = frameOfText(startingWith: reading(of: summary.netIncome), in: window)
                    // The amount is in the title size, 27 points a line: the amount beside its words and the line under
                    // them are about 45 points tall, and with the amount under its words, 65.
                    #expect((line?.height ?? .infinity) < 55, "The amount is not beside its words: \(line as Any)")
                }
            }
        }
    }

    /// The popover of the levy bar hangs out of the bar over what follows it in the result card of the Simulátor, the
    /// hairline, the net income and the marginal levy, and is drawn above all of them and not clipped by the card. The
    /// pointer is moved over the part of the tax, and then over its item of the legend, as a mouse moves it. A strip
    /// down the popover, 6 points inside its leading edge, shows nothing but the colour of the popover while it is
    /// open, where the hairlines and the dot of the net income cross it while it is closed.
    @Test func thePopoverOfTheLevyBarIsDrawnOverTheNetIncomeAndTheMarginalLevyOfTheSimulator() async throws {
        try await EditorFixture.with { f in
            try await withAppWindow(of: f.app, size: AppWindowSize.large, ignoringTheRealPointer: true) { window in
                f.app.screen = .simulator
                try await waitUntil { window.title == "Simulátor" }
                try await waitUntil { (scrolledPage(in: window)?.frame.height ?? 0) > 600 }
                let model = f.app.simulatorModel
                model.setIncomeText("2 500 000")
                model.readTypedTexts()
                let weights = try #require(model.page?.summary.levyBar.parts.map(\.weight))

                try await withAccessibilityElements {
                    try await waitUntil { frameOfCard(labelled: "Mezní odvod", in: window) != nil }
                    try await expectSettled(window) {
                        frameOfCard(labelled: "Kolik zaplatíte", in: window) == nil ? ["No result card"] : []
                    }
                    let content = try #require(window.contentView)
                    let bar = window.convertFromScreen(
                        try #require(
                            accessibilityElement(labelStartingWith: "Odvody podle úřadů: Daň z příjmů", in: window)?
                                .accessibilityFrame?()))
                    let legend = window.convertFromScreen(
                        try #require(
                            accessibilityElement(labelStartingWith: "Daň z příjmů: za rok", in: window)?
                                .accessibilityFrame?()))
                    let card = window.convertFromScreen(
                        try #require(frameOfCard(labelled: "Kolik zaplatíte", in: window)))
                    // The popover of the tax: 8 points under the legend, centred on its part and held in the panel.
                    let widths = LevyBarLayout.partWidths(weights: weights, width: bar.width)
                    let centre = LevyBarLayout.partCentres(widths: widths)[0]
                    let left = bar.minX + LevyBarLayout.popoverX(centredOn: centre, panelWidth: bar.width)
                    let top = content.bounds.height - legend.minY + LevyBarLayout.popoverGap

                    /// The points of the strip down the popover, from 4 to 100 points under its top, whose colour is
                    /// not that of the top of the strip: what is drawn over the popover while it is open.
                    @MainActor func strayPoints() throws -> [CGPoint] {
                        let picture = try WindowPicture(of: window)
                        let strip = stride(from: top + 4, to: top + 100, by: 0.5).map { CGPoint(x: left + 6, y: $0) }
                        let colour = picture.bytes(at: strip[0])
                        return strip.filter { point in
                            zip(picture.bytes(at: point), colour).contains { abs($0 - $1) > 6 }
                        }
                    }

                    // The popover is shorter than what follows the bar in the card, so it ends inside the card.
                    #expect(top + 100 < content.bounds.height - card.minY, "The strip reaches out of the card")
                    // With no popover the hairlines and the net income cross the strip: the test can tell the two
                    // states apart.
                    let corner = CGPoint(x: 4, y: 4)
                    try await expectSettled(window) {
                        ((try? strayPoints()) ?? []).isEmpty ? ["Nothing of the card crosses the strip"] : []
                    }

                    let overPart = CGPoint(x: bar.minX + 10, y: bar.midY)
                    let overLegend = CGPoint(x: legend.minX + 10, y: legend.midY)
                    for (name, pointer) in [("part", overPart), ("item of the legend", overLegend)] {
                        try movePointer(to: pointer, in: window)
                        try await waitUntil { ((try? strayPoints()) ?? [CGPoint.zero]).isEmpty }
                        #expect(try strayPoints() == [], "Drawn over the popover of the \(name)")

                        try movePointer(to: corner, in: window)
                        try await waitUntil { !((try? strayPoints()) ?? []).isEmpty }
                    }
                }
            }
        }
    }

    /// The cards of the breakdown of the Simulátor by the labels VoiceOver reads them under, the left stack and then
    /// the right one: the tax, and the social and the health insurance with the net income under them.
    private static let simulatorBreakdown = [
        ["Daň z příjmů"], ["Sociální pojištění", "Zdravotní pojištění", "Čistý příjem"],
    ]

    /// The breakdown of the Simulátor has the tax on the left and the two insurances with the net income under them on
    /// the right: all four in one column at the least room, where the detail has 828 points and two columns need 856,
    /// and in two columns in a large window, whichever way the window goes.
    @Test func theSimulatorBreakdownIsOneColumnAtTheLeastRoomAndTwoInALargeWindow() async throws {
        try await EditorFixture.with { f in
            try await withAppWindow(of: f.app, size: AppWindowSize.minimum) { window in
                f.app.screen = .simulator
                try await waitUntil { window.title == "Simulátor" }
                try await waitUntil { (scrolledPage(in: window)?.frame.height ?? 0) > 600 }

                try await withAccessibilityElements {
                    for (size, beside) in Self.breakdownSizes {
                        window.setContentSize(size)
                        try await expectSettled(window) {
                            problems(ofTheBreakdown: Self.simulatorBreakdown, beside: beside) { label in
                                frameOfCard(labelled: label, in: window)
                            }
                        }
                    }
                }
            }
        }
    }

    /// What is wrong with the page of the Simulátor in `window`, in words: the problems of a page that scrolls, a card
    /// that is missing, one that runs out of the page sideways, and two that overlap. Empty when the page fits.
    private func problems(ofSimulatorIn window: NSWindow) -> [String] {
        var problems = problems(ofPageIn: window)
        guard let page = scrolledPage(in: window)?.enclosingScrollView else {
            return problems + ["The page is not shown"]
        }
        let room = window.convertToScreen(frameInWindow(page))
        var placed: [(label: String, frame: CGRect)] = []
        for label in Self.simulatorCards {
            guard let frame = frameOfCard(labelled: label, in: window) else {
                problems.append("No card \(label)")
                continue
            }
            if frame.minX < room.minX - 0.5 || frame.maxX > room.maxX + 0.5 {
                problems.append("The card \(label) runs out of the page \(room): \(frame)")
            }
            for other in placed where frame.insetBy(dx: 0.5, dy: 0.5).intersects(other.frame) {
                problems.append("The card \(label) lies over \(other.label): \(frame) and \(other.frame)")
            }
            placed.append((label: label, frame: frame))
        }
        return problems
    }

    /// What is wrong with where the result stands in `window`, in words: it is not to the right of the year and the
    /// income, 16 points from them, in a column of 360 points, or its top is more than 40 points from theirs. Empty
    /// when it stands beside them.
    private func problems(ofResultsBesideInputsIn window: NSWindow) -> [String] {
        guard let inputs = frameOfCard(labelled: "Rok a příjem", in: window) else {
            return ["No card Rok a příjem"]
        }
        guard let results = frameOfCard(labelled: "Kolik zaplatíte", in: window) else {
            return ["No card Kolik zaplatíte"]
        }
        var problems: [String] = []
        if results.minX < inputs.maxX - 0.5 {
            problems.append("The result is not to the right of the inputs: \(results) and \(inputs)")
        }
        if (results.minX - inputs.maxX - 16).magnitude > 1 {
            problems.append("The result is not 16 points from the inputs: \(results) and \(inputs)")
        }
        if (results.width - 360).magnitude > 1 {
            problems.append("The result is \(results.width) points wide, not 360")
        }
        // The origin of the screen is at the bottom left, so a top is the largest y.
        if (results.maxY - inputs.maxY).magnitude > 40 {
            problems.append("The top of the result is \(inputs.maxY - results.maxY) points under that of the inputs")
        }
        return problems
    }

    /// What VoiceOver reads for `net` in the result card of the Simulátor: its words, the average per month and the
    /// line under them, as one phrase.
    private func reading(of net: SimulatorNetIncome) -> String {
        [net.label, net.amount, net.sub].joined(separator: ", ")
    }

    /// What is wrong with the net income in the result card of the Simulátor in `window` for `summary`, in words:
    /// VoiceOver does not read its words, the average per month and the line under them as one phrase, the phrase is
    /// not within the card, it is not under the last item of the legend of the bar of the levies, or the marginal levy
    /// is not under it. The origin of the screen is at the bottom left, so what is above has the larger y. Empty when
    /// it stands so. Needs the accessibility elements.
    private func problems(ofTheNetIncomeOf summary: SimulatorSummary, in window: NSWindow) -> [String] {
        let phrase = reading(of: summary.netIncome)
        guard accessibilityReadings(in: window).contains(phrase) else {
            return ["The net income is not read as one phrase: \(phrase)"]
        }
        guard let last = summary.levyBar.parts.last, let card = frameOfCard(labelled: "Kolik zaplatíte", in: window),
            let frame = frameOfText(startingWith: phrase, in: window),
            let legend = accessibilityElement(labelled: last.accessibilityLabel, in: window)?.accessibilityFrame?(),
            let marginal = frameOfCard(labelled: "Mezní odvod", in: window)
        else {
            return ["No result card, or no net income, last item of the legend or marginal levy in it"]
        }
        var found: [String] = []
        if !card.insetBy(dx: -0.5, dy: -0.5).contains(frame) {
            found.append("The net income is not within the result card: \(frame), the card \(card)")
        }
        if frame.maxY > legend.minY + 0.5 {
            found.append("The net income is not under the legend of the bar: \(frame), \(legend)")
        }
        if marginal.maxY > frame.minY + 0.5 {
            found.append("The marginal levy is not under the net income: \(marginal), \(frame)")
        }
        return found
    }

    /// What is wrong with the result card of the Simulátor for `summary` in `window`, in words: a part of it is missing
    /// or not inside the card; the card is not 360 points wide beside the inputs, or, with `under`, as wide as the page
    /// under them; or its parts do not stand one under the other as the design has them: the key figure at the top
    /// left, the bar of the levies (its header, its picture and the items of its legend) in the whole width inside the
    /// padding and 14 points under it, the net income 27 points under the legend (14, a hairline and 12), the marginal
    /// levy 27 points under the net income, and the foot of the card 20 points under it. The origin of the screen is at
    /// the bottom left, so what is above has the larger y. Empty when it stands so. Needs the accessibility elements.
    private func problems(
        ofTheResultCardOfTheSimulatorFor summary: SimulatorSummary, under: Bool, in window: NSWindow
    ) -> [String] {
        guard let card = frameOfCard(labelled: "Kolik zaplatíte", in: window) else {
            return ["No card Kolik zaplatíte"]
        }
        guard let key = frameOfText(startingWith: summary.keyFigure.eyebrow, in: window) else {
            return ["No key figure"]
        }
        guard let header = frameOfText(startingWith: summary.levyBar.header, in: window),
            let picture = accessibilityElement(labelStartingWith: summary.levyBar.header + ": ", in: window)?
                .accessibilityFrame?()
        else {
            return ["No levy bar with its header"]
        }
        let items = summary.levyBar.parts.compactMap { part in
            accessibilityElement(labelled: part.accessibilityLabel, in: window)?.accessibilityFrame?()
        }
        guard items.count == summary.levyBar.parts.count else {
            return ["The legend of the levy bar has \(items.count) items, not \(summary.levyBar.parts.count)"]
        }
        guard let net = frameOfText(startingWith: reading(of: summary.netIncome), in: window) else {
            return ["No net income"]
        }
        guard let marginal = frameOfCard(labelled: "Mezní odvod", in: window) else {
            return ["No marginal levy"]
        }
        var found: [String] = []
        let inside = card.insetBy(dx: -0.5, dy: -0.5)
        for (name, frame) in [
            ("The key figure", key), ("The levy bar", picture), ("The net income", net),
            ("The marginal levy", marginal),
        ] where !inside.contains(frame) {
            found.append("\(name) is not inside the card: \(frame) and \(card)")
        }
        if under {
            if card.width < 600 {
                found.append("The card is \(card.width) points wide, not as wide as the page under the inputs")
            }
        } else if (card.width - 360).magnitude > 1 {
            found.append("The card is \(card.width) points wide, not 360")
        }
        if (card.maxY - 20 - key.maxY).magnitude > 1 || (key.minX - card.minX - 20).magnitude > 1 {
            found.append("The key figure is not at the top left of the card: \(key) and \(card)")
        }
        if (key.minY - header.maxY - 14).magnitude > 1.5 {
            found.append("The levy bar is not 14 points under the key figure: \(header), \(key)")
        }
        if (picture.minX - key.minX).magnitude > 1 || (picture.width - (card.width - 40)).magnitude > 1 {
            found.append("The levy bar does not have the whole width inside the padding of the card: \(picture)")
        }
        let legendBottom = items.map(\.minY).min() ?? picture.minY
        if (legendBottom - 27 - net.maxY).magnitude > 1.5 {
            found.append("The net income is not 27 points under the legend of the bar: \(net), \(items)")
        }
        if (net.minX - key.minX).magnitude > 1 {
            found.append("The net income is not at the left edge of the card: \(net), \(card)")
        }
        if (net.minY - 27 - marginal.maxY).magnitude > 1.5 {
            found.append("The marginal levy is not 27 points under the net income: \(marginal), \(net)")
        }
        if (marginal.minX - key.minX).magnitude > 1 {
            found.append("The marginal levy is not at the left edge of the card: \(marginal), \(card)")
        }
        if (marginal.minY - 20 - card.minY).magnitude > 1.5 {
            found.append("The card does not end 20 points under the marginal levy: \(marginal), \(card)")
        }
        // The marginal levy reads its heading, its total and its sentence, and no bar.
        if let group = accessibilityElement(labelled: "Mezní odvod", in: window) {
            let expected = ["Mezní odvod", "Mezní odvod", summary.marginal.total, summary.marginal.text]
            if accessibilityReadings(under: group) != expected {
                found.append("The marginal levy reads \(accessibilityReadings(under: group)), not \(expected)")
            }
        }
        return found
    }

    /// Přehled when the search for the uniform rate ends without finding it: the reminder comes above the cards, which
    /// the page grows by, the page fits the window at the least room and at a large size, and the page is as it was
    /// when the reminder goes.
    @Test func prehledShowsTheReminderOfTheUniformRateAboveItsCardsAndFitsTheWindowWithIt() async throws {
        try await EditorFixture.with { f in
            try await withAppWindow(of: f.app, size: AppWindowSize.minimum) { window in
                f.app.screen = .overview
                try await waitUntil { window.title == "Přehled" }
                try await waitUntil { (scrolledPage(in: window)?.frame.height ?? 0) > 600 }
                let without = try #require(scrolledPage(in: window)).frame.height

                f.app.uniformRateReminderYear = 2026
                try await waitUntil { (scrolledPage(in: window)?.frame.height ?? 0) > without + 40 }
                try await expectSettled(window) { problems(ofPageIn: window) }
                window.setContentSize(AppWindowSize.large)
                try await expectSettled(window) { problems(ofPageIn: window) }
                window.setContentSize(AppWindowSize.minimum)
                try await expectSettled(window) { problems(ofPageIn: window) }

                f.app.uniformRateReminderYear = nil
                try await waitUntil { ((scrolledPage(in: window)?.frame.height ?? 0) - without).magnitude < 1 }
            }
        }
    }

    /// The sheet that asks to confirm a uniform rate is a sheet of the window whichever screen it shows, 560 points
    /// wide and not taller than the window, and it goes when the finding is put off.
    @Test func theSheetThatConfirmsAUniformRateIsShownOverTheWindowAndGoesWhenItIsPutOff() async throws {
        try await EditorFixture.with { f in
            try await withAppWindow(of: f.app, size: AppWindowSize.minimum) { window in
                f.app.screen = .invoices
                try await waitUntil { window.title == "Faktury" }
                #expect(window.attachedSheet == nil)

                try await #require(f.app.database).execute("DELETE FROM uniform_rate WHERE year = 2025")
                await f.app.offerUniformRate(try gfrFinding2025())
                try await waitUntil { window.attachedSheet != nil }
                let sheet = try #require(window.attachedSheet)
                try await layOut(window)

                #expect((sheet.frame.width - 560).magnitude < 1, "The sheet is \(sheet.frame.width) points wide")
                let height = sheet.frame.height
                #expect(height > 200 && height <= 700, "The sheet is \(height) points tall")
                // Put off: the finding waits, and the window is as it was.
                f.app.uniformRateOffer = nil
                try await waitUntil { window.attachedSheet == nil }
                #expect(f.app.pendingUniformRate != nil)
            }
        }
    }

    /// What is wrong with the page of a screen that scrolls in `window`, in words: the views that stick out of the
    /// window, and a page that is wider than the window, which would make it scroll sideways. Empty when the page fits.
    private func problems(ofPageIn window: NSWindow) -> [String] {
        var problems = viewsOutside(window).map { "Outside the window: \($0)" }
        if let page = scrolledPage(in: window), page.frame.width > window.contentLayoutRect.width + 0.5 {
            problems.append("The page is wider than the window: \(page.frame.width) points")
        }
        return problems
    }

    /// What the page of the screen scrolls, in `window`: the content of the first scroll view that is not the list of
    /// the sidebar.
    private func scrolledPage(in window: NSWindow) -> NSView? {
        guard let content = window.contentView else { return nil }
        return scrollViews(in: content).lazy.compactMap(\.documentView).first { !($0 is NSTableView) }
    }

    private func scrollViews(in view: NSView) -> [NSScrollView] {
        if let scrollView = view as? NSScrollView {
            return [scrollView]
        }
        return view.subviews.flatMap { scrollViews(in: $0) }
    }
}
