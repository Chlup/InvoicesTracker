import AppKit
import SwiftUI
import Testing
@testable import InvoicesTracker

/// The Simulátor in the window of the app, made as the app makes it, on the data of `EditorFixture`: the sample year
/// 2026 is stored, and the app is as of 17. 10. 2026.
/// - The toolbar is the one of the other screens, and its year leaves the Simulátor the year of its page. Here, as on
///   Odhad odvodů, date controls and a simulation marker are absent.
/// - A typed text that the pause reads and refuses keeps its field focused, so the keys that follow still go into the
///   field: its message must not move the fields around it.
/// - The dialog of a child is the sheet of Zálohy a odpočty in the mode of the simulation, with the lock after
///   inactivity over it: what it saves and removes is the simulation's, and nothing is stored.
/// - The box of the health minimum is under the menu Činnost with a secondary activity only, and ticking it asks the
///   model for the exemption.
///
/// The fields are found by the labels VoiceOver reads them under. A test types in its turn among the tests that type
/// into a window (`whileTypingAlone`): the text fields of all windows share one field editor. In every expected string
/// `\u{00A0}` is the no-break space.
@Suite(.serialized, .settlesBackups)
@MainActor
struct SimulatorWindowTests {
    /// What a page needs is measured in the font it is set in, so the fonts are registered before any test, as the app
    /// does at its launch.
    init() {
        InvoiceFonts.register()
    }

    // MARK: The toolbar

    /// The Simulátor shows the toolbar of the other screens, the year menu with the rate capsule and Nová faktura
    /// last, as many items as Výpočet shows. It holds back and forth
    /// between the screens.
    @Test func theSimulátorShowsTheSameToolbarAsOtherScreens() async throws {
        try await EditorFixture.with { f in
            try await withAppWindow(of: f.app, size: AppWindowSize.minimum) { window in
                try await withAccessibilityElements {
                    try await waitUntil { indexOfTheRateCapsule(in: window) != nil }
                    try await layOut(window)
                    let onVýpočet = toolbarItems(of: window).count
                    #expect(toolbarItems(of: window).last?.label == "Nová faktura", "the toolbar of Výpočet")
                    #expect(indexOfTheRateCapsule(in: window) == onVýpočet - 2, "the toolbar of Výpočet")
                    let screens: [(screen: Screen, title: String)] = [
                        (.simulator, "Simulátor"), (.advances, "Zálohy a odpočty"), (.simulator, "Simulátor"),
                        (.importer, "Import faktur"),
                    ]
                    for (screen, title) in screens {
                        f.app.screen = screen
                        try await waitUntil { window.title == title }
                        try await layOut(window)
                        let items = toolbarItems(of: window)
                        #expect(items.count == onVýpočet, "the toolbar of \(screen.title)")
                        #expect(items.last?.label == "Nová faktura", "the toolbar of \(screen.title)")
                        #expect(indexOfTheRateCapsule(in: window) == items.count - 2, "the toolbar of \(screen.title)")
                    }
                }
            }
        }
    }

    /// The year chosen in the toolbar while the Simulátor is shown is the year of the other screens: the Simulátor
    /// keeps the year chosen on its page, and its page stays the one of that year.
    @Test func theYearOfTheToolbarLeavesTheSimulátorItsOwnYear() async throws {
        try await EditorFixture.with { f in
            try await withAppWindow(of: f.app, size: AppWindowSize.minimum) { window in
                let model = try await showSimulator(of: f.app, in: window)
                #expect(model.year == 2026)

                f.app.selectYear(2025)
                // The screen reads the settings of its year again when the year of the other screens changes.
                try await layOut(window)

                #expect(f.app.asOf.year == 2025)
                #expect(model.year == 2026)
                #expect(model.canCopyDeductionsAndFamily)
                #expect(model.page?.summary.keyFigure.eyebrow == "Odvody za rok 2026")
            }
        }
    }

    /// The simulator leaves an internally picked reporting cutoff alone when another screen is shown.
    @Test func theSimulatorLeavesTheInternalReportingCutoffAlone() async throws {
        try await EditorFixture.with { f in
            f.app.pickAsOf(civilDate("2026-07-15"))
            try await withAppWindow(of: f.app, size: AppWindowSize.minimum) { window in
                _ = try await showSimulator(of: f.app, in: window)
                try await withAccessibilityElements {
                    try await expectSettled(window) { mainToolbarProblems(in: window) }
                    f.app.screen = .computation
                    try await waitUntil { window.title == "Výpočet" }
                    try await expectSettled(window) { mainToolbarProblems(in: window) }
                    #expect(f.app.asOf.asOf == civilDate("2026-07-15"))
                    #expect(!f.app.asOf.followsToday)
                }
            }
        }
    }

    /// An internal future cutoff creates no simulation marker or date controls on any of these pages.
    @Test func anInternalFutureCutoffHasNoSimulationControlsOnThesePages() async throws {
        try await EditorFixture.with { f in
            f.app.pickAsOf(civilDate("2026-12-01"))
            try await withAppWindow(of: f.app, size: AppWindowSize.minimum) { window in
                try await withAccessibilityElements {
                    let screens: [(screen: Screen, title: String)] = [
                        (.prediction, "Odhad odvodů"), (.simulator, "Simulátor"), (.computation, "Výpočet"),
                    ]
                    for (screen, title) in screens {
                        f.app.screen = screen
                        try await waitUntil { window.title == title }
                        try await expectSettled(window) { mainToolbarProblems(in: window) }
                        #expect(!accessibilityReadings(in: window).contains("simulace budoucnosti"))
                        #expect(f.app.asOf.asOf == civilDate("2026-12-01"))
                    }
                }
            }
        }
    }

    /// Date controls stay absent when the internal cutoff changes or returns to the automatic current month.
    @Test func dateControlsStayAbsentAcrossScreensAndInternalDateChanges() async throws {
        try await EditorFixture.with { f in
            try await withAppWindow(of: f.app, size: AppWindowSize.minimum) { window in
                try await withAccessibilityElements {
                    for screen in [Screen.prediction, .simulator] {
                        f.app.screen = screen
                        try await waitUntil { window.title == screen.title }
                        try await expectSettled(window) { mainToolbarProblems(in: window) }

                        f.app.pickAsOf(civilDate("2026-07-15"))
                        try await expectSettled(window) { mainToolbarProblems(in: window) }
                        #expect(f.app.asOf.asOf == civilDate("2026-07-15"))

                        f.app.goToday()
                        #expect(f.app.asOf.asOf == civilDate("2026-10-31"))
                        #expect(f.app.asOf.followsToday)
                        try await expectSettled(window) { mainToolbarProblems(in: window) }
                    }
                }
            }
        }
    }

    /// The toolbar's year menu changes the reporting year while the simulator keeps its own page year.
    @Test func theYearMenuOnSimulatorResumesTheAutomaticCurrentMonthCutoff() async throws {
        try await EditorFixture.with { f in
            f.app.pickAsOf(civilDate("2026-07-15"))
            try await withAppWindow(of: f.app, size: AppWindowSize.minimum) { window in
                let model = try await showSimulator(of: f.app, in: window)
                try await withAccessibilityElements {
                    try await expectSettled(window) { mainToolbarProblems(in: window) }
                    #expect(model.year == 2026)

                    f.app.selectYear(2025)
                    #expect(f.app.asOf.asOf == civilDate("2025-12-31"))
                    try await expectSettled(window) { mainToolbarProblems(in: window) }
                    #expect(model.year == 2026)
                    #expect(model.page?.summary.keyFigure.eyebrow == "Odvody za rok 2026")

                    f.app.selectYear(2026)
                    #expect(f.app.asOf.asOf == civilDate("2026-10-31"))
                    #expect(f.app.asOf.followsToday)
                    try await expectSettled(window) { mainToolbarProblems(in: window) }
                    #expect(model.year == 2026)
                }
            }
        }
    }

    private func toolbarItems(of window: NSWindow) -> [NSToolbarItem] {
        window.toolbar?.items ?? []
    }

    /// The place of the rate capsule of 2026 among the items of the toolbar of `window`: the index of the item whose
    /// view holds the button VoiceOver reads as the capsule. Nil while the toolbar has no such button.
    private func indexOfTheRateCapsule(in window: NSWindow) -> Int? {
        let label = "Přepočet cizích měn v roce 2026: denní kurz ČNB"
        guard let capsule = accessibilityButton(labelled: label, in: window), let frame = capsule.accessibilityFrame?()
        else {
            return nil
        }
        // Both frames are in the coordinates of the screen.
        let center = CGPoint(x: frame.midX, y: frame.midY)
        return toolbarItems(of: window).firstIndex { item in
            item.view.map { window.convertToScreen(frameInWindow($0)).contains(center) } ?? false
        }
    }

    // MARK: The texts of the inputs

    /// The note under the income says that the amount is without VAT and in crowns, and that no employment or other
    /// taxable income is counted, as the prototype words it ("Bez DPH, v Kč. …"), where the app said only "V Kč. …".
    @Test func theNoteUnderTheIncomeSaysItIsWithoutVatAndInCrowns() async throws {
        try await EditorFixture.with { f in
            try await withAppWindow(of: f.app, size: AppWindowSize.minimum) { window in
                _ = try await showSimulator(of: f.app, in: window)
                try await withAccessibilityElements {
                    let note = "Bez DPH, v Kč. Bez zaměstnání a jiných zdanitelných příjmů."
                    try await waitUntil { showsText(note, in: window) }
                    #expect(!showsText("V Kč. Bez zaměstnání a jiných zdanitelných příjmů.", in: window))
                }
            }
        }
    }

    /// "Začít znovu" in the note at the top and "Převzít ze Záloh a odpočtů 2026" over the cards of the deductions are
    /// capsules 28 points tall, the height of a button inside a card, and not the 22 points of a system button.
    @Test func theRestartAndTheCopyButtonsAreCapsulesOfTheHeightOfAButtonInACard() async throws {
        try await EditorFixture.with { f in
            try await withAppWindow(of: f.app, size: AppWindowSize.minimum) { window in
                _ = try await showSimulator(of: f.app, in: window)
                try await withAccessibilityElements {
                    for label in ["Začít znovu", "Převzít ze Záloh a odpočtů 2026"] {
                        try await waitUntil { accessibilityButton(labelled: label, in: window) != nil }
                        let frame = try #require(
                            accessibilityButton(labelled: label, in: window)?.accessibilityFrame?())
                        #expect((frame.height - 28).magnitude < 0.5, "\(label) is \(frame.height) points tall")
                    }
                }
            }
        }
    }

    // MARK: Refused texts

    /// At the least room the app allows, the life insurance pauses in the middle of "13 340". The text so far is
    /// refused and its message comes under the field. The fields of the savings stay where they are, so the field
    /// keeps the focus. The rest of the amount is typed into it and taken, and the message goes without the focus
    /// going.
    @Test func aRefusedSavingsAmountKeepsItsFieldFocusedInTheSmallestWindow() async throws {
        try await whileTypingAlone {
            try await EditorFixture.with { f in
                try await withAppWindow(of: f.app, size: AppWindowSize.minimum) { window in
                    let model = try await showSimulator(of: f.app, in: window)
                    try await withAccessibilityElements {
                        let label = "Soukromé životní pojištění (Kč za rok)"
                        try await waitUntil { textField(labelled: label, in: window) != nil }
                        let field = try #require(textField(labelled: label, in: window))

                        try type("13 3", into: field, in: window)
                        try await waitUntil { model.deductionErrors[.lifeInsurance] != nil }
                        #expect(model.deductionErrors[.lifeInsurance] == AdvancesModel.wholeKcMessage)
                        try await expectSettled(window) { focusProblems(of: field, in: window) }

                        try typeOn("40", into: field)
                        try await waitUntil { model.deductionErrors[.lifeInsurance] == nil }
                        #expect(model.page?.hints.retirementAllowed == "13\u{00A0}340\u{00A0}Kč")
                        try await expectSettled(window) { focusProblems(of: field, in: window) }
                    }
                }
            }
        }
    }

    /// In a window 1 200 points wide, 13 months of activity are refused. The message comes under the row of the
    /// assumptions and the field keeps the focus. Then 6 is typed in it and taken.
    @Test func aRefusedNumberOfMonthsKeepsItsFieldFocused() async throws {
        try await whileTypingAlone {
            try await EditorFixture.with { f in
                try await withAppWindow(of: f.app, size: CGSize(width: 1_200, height: 720)) { window in
                    let model = try await showSimulator(of: f.app, in: window)
                    try await withAccessibilityElements {
                        try await waitUntil { textField(labelled: "Měsíců činnosti", in: window) != nil }
                        let field = try #require(textField(labelled: "Měsíců činnosti", in: window))

                        try type("13", into: field, in: window)
                        try await waitUntil { model.monthsError != nil }
                        #expect(model.monthsError == SimulatorModel.activityMonthsMessage)
                        try await expectSettled(window) { focusProblems(of: field, in: window) }

                        try type("6", into: field, in: window)
                        try await waitUntil { model.monthsError == nil }
                        #expect(model.page?.summary.keyFigure.figure == "49\u{00A0}860\u{00A0}Kč")
                        try await expectSettled(window) { focusProblems(of: field, in: window) }
                    }
                }
            }
        }
    }

    // MARK: The health switch

    /// The box that asks for the exemption from the health minimum, by the label VoiceOver reads it under.
    private static let healthSwitch = "Bez minima zdravotního pojištění"

    /// The box under the menu Činnost shows only with a secondary activity: with the main one it is not there, once
    /// Vedlejší is chosen it is, unticked, and with Hlavní again it goes.
    @Test func theHealthSwitchShowsOnlyWithVedlejsiActivity() async throws {
        try await EditorFixture.with { f in
            try await withAppWindow(of: f.app, size: AppWindowSize.minimum) { window in
                let model = try await showSimulator(of: f.app, in: window)
                try await withAccessibilityElements {
                    // The assumptions are on the page, so the box is not missing because the page is not there yet.
                    try await waitUntil { accessibilityElement(labelled: "Činnost", in: window) != nil }
                    try await layOut(window)
                    #expect(model.activity == .main)
                    #expect(accessibilityElement(labelled: Self.healthSwitch, in: window) == nil)

                    model.setActivity(.secondary)
                    try await waitUntil { accessibilityElement(labelled: Self.healthSwitch, in: window) != nil }
                    let box = try #require(accessibilityElement(labelled: Self.healthSwitch, in: window))
                    #expect(box.accessibilityRole?() == .checkBox)
                    #expect(isTicked(box) == false)

                    model.setActivity(.main)
                    try await waitUntil { accessibilityElement(labelled: Self.healthSwitch, in: window) == nil }
                }
            }
        }
    }

    /// Ticking the box asks the model for the exemption, and the health insurance of the page follows: a month of
    /// secondary activity on 5 000 Kč pays the minimum of the month, 3 306 Kč, and once the box is ticked only the
    /// 135 Kč of its profit. The box keeps its tick while Hlavní is chosen and shows it again with Vedlejší.
    @Test func tickingTheHealthSwitchTakesTheMinimumOffVedlejsiActivity() async throws {
        try await EditorFixture.with { f in
            try await withAppWindow(of: f.app, size: AppWindowSize.minimum) { window in
                let model = try await showSimulator(of: f.app, in: window)
                model.setIncomeText("5 000")
                model.setMonthsText("1")
                model.readTypedTexts()
                model.setActivity(.secondary)
                try await withAccessibilityElements {
                    try await waitUntil { accessibilityElement(labelled: Self.healthSwitch, in: window) != nil }
                    #expect(model.page?.summary.levyBar.parts.last?.legendValue == "3\u{00A0}306\u{00A0}Kč")

                    let box = try #require(accessibilityElement(labelled: Self.healthSwitch, in: window))
                    _ = box.accessibilityPerformPress?()

                    try await waitUntil { model.healthMinimumExempt }
                    #expect(model.page?.summary.levyBar.parts.last?.legendValue == "135\u{00A0}Kč")
                    try await waitUntil {
                        accessibilityElement(labelled: Self.healthSwitch, in: window).flatMap(isTicked) == true
                    }

                    model.setActivity(.main)
                    try await waitUntil { accessibilityElement(labelled: Self.healthSwitch, in: window) == nil }
                    model.setActivity(.secondary)
                    try await waitUntil { accessibilityElement(labelled: Self.healthSwitch, in: window) != nil }
                    #expect(accessibilityElement(labelled: Self.healthSwitch, in: window).flatMap(isTicked) == true)
                }
            }
        }
    }

    /// Whether the box `element` is ticked, as VoiceOver reads it: the value of a check box, 1 or 0. Nil when it reads
    /// no such value.
    private func isTicked(_ element: AnyObject) -> Bool? {
        // Asked for as a function of its type, because the protocols of accessibility declare `accessibilityValue()`
        // with more than one type.
        let value: (() -> Any?)? = element.accessibilityValue
        return ((value?() ?? nil) as? NSNumber)?.boolValue
    }

    // MARK: The family

    /// Přidat dítě opens the dialog of a new child of the simulation as a sheet of the window, with the lock after
    /// inactivity over it. Ema, born 15. 6. 2026, is the first child from June: 7 × 1 267 Kč. Uložit dítě adds her to
    /// the simulation and her row to the card, and nothing is stored. Her row opens her dialog, whose Odebrat dítě
    /// takes her out at once, without a question.
    @Test func aChildOfTheSimulationIsAddedAndRemovedInItsDialogAndNotStored() async throws {
        try await whileTypingAlone {
            try await EditorFixture.with { f in
                try await withAppWindow(of: f.app, size: AppWindowSize.minimum) { window in
                    let model = try await showSimulator(of: f.app, in: window)
                    let versionBefore = f.app.dataVersion
                    try await withAccessibilityElements {
                        try await waitUntil { accessibilityButton(labelled: "Přidat dítě", in: window) != nil }
                        let add = try #require(accessibilityButton(labelled: "Přidat dítě", in: window))
                        _ = add.accessibilityPerformPress?()
                        try await waitUntil { window.attachedSheet != nil }
                        let sheet = try #require(window.attachedSheet)
                        #expect(IdleLockSheets.guarded.contains(sheet))
                        try await waitUntil { accessibilityReadings(in: sheet).contains("Nové dítě v simulaci") }
                        #expect(showsText("Jen pro simulaci roku 2026 – nic se neukládá", in: sheet))

                        try await waitUntil { textField(labelled: "Datum narození", in: sheet) != nil }
                        try type("Ema", into: try #require(textField(labelled: "Jméno", in: sheet)), in: sheet)
                        let birth = try #require(textField(labelled: "Datum narození", in: sheet))
                        try type("15. 6. 2026", into: birth, in: sheet)
                        try await waitUntil {
                            showsText("V roce 2026: 7\u{00A0}měsíců jako 1. dítě · 8\u{00A0}869\u{00A0}Kč", in: sheet)
                        }
                        let save = try #require(accessibilityButton(labelled: "Uložit dítě", in: sheet))
                        _ = save.accessibilityPerformPress?()

                        try await waitUntil { window.attachedSheet == nil }
                        #expect(model.family?.children.map(\.child.name) == ["Ema"])
                        let row =
                            "Ema · nar. 15.\u{00A0}6.\u{00A0}2026, 1. dítě · 7\u{00A0}měsíců, 8\u{00A0}869\u{00A0}Kč"
                        try await waitUntil { accessibilityButton(labelled: row, in: window) != nil }

                        _ = try #require(accessibilityButton(labelled: row, in: window)).accessibilityPerformPress?()
                        try await waitUntil { window.attachedSheet != nil }
                        let edit = try #require(window.attachedSheet)
                        #expect(IdleLockSheets.guarded.contains(edit))
                        try await waitUntil { accessibilityReadings(in: edit).contains("Upravit dítě v simulaci") }
                        let remove = try #require(accessibilityButton(labelled: "Odebrat dítě", in: edit))
                        _ = remove.accessibilityPerformPress?()

                        try await waitUntil { window.attachedSheet == nil }
                        #expect(model.family?.children.isEmpty == true)
                        try await waitUntil { showsText(ChildrenCardContent.noChildrenInSimulation, in: window) }
                    }
                    #expect(f.app.dataVersion == versionBefore)
                    #expect(try await f.database.family(year: 2026).children.isEmpty)
                }
            }
        }
    }

    // MARK: Helpers

    /// Shows the Simulátor in `window`, which is made the key window as a person's click makes it, once it has read
    /// the settings of its year, and gives its model.
    private func showSimulator(of app: AppModel, in window: NSWindow) async throws -> SimulatorModel {
        window.makeKeyAndOrderFront(nil)
        app.screen = .simulator
        try await waitUntil { window.title == "Simulátor" }
        try await waitUntil { app.simulatorModel.canCopyDeductionsAndFamily }
        try await layOut(window)
        return app.simulatorModel
    }

    /// Types `text` into `field` as a person does: the field takes the focus and its text is replaced, and the change
    /// reaches the binding as the keys do.
    private func type(_ text: String, into field: NSTextField, in window: NSWindow) throws {
        #expect(window.makeFirstResponder(field))
        let editor = try #require(field.currentEditor() as? NSTextView)
        editor.selectAll(nil)
        editor.insertText(text, replacementRange: editor.selectedRange())
    }

    /// Types `text` on at the end of what `field`, which has the focus, holds.
    private func typeOn(_ text: String, into field: NSTextField) throws {
        let editor = try #require(field.currentEditor() as? NSTextView)
        editor.insertText(text, replacementRange: editor.selectedRange())
    }

    /// What is wrong with the focus of `field` in `window`, in words: the field is gone from the window, or another
    /// view has the focus. Empty while the field is being typed in.
    private func focusProblems(of field: NSTextField, in window: NSWindow) -> [String] {
        guard field.window === window else {
            return ["The field is no longer in the window"]
        }
        guard let editor = field.currentEditor(), window.firstResponder === editor else {
            return ["The field lost the focus to \(String(describing: window.firstResponder))"]
        }
        return []
    }
}
