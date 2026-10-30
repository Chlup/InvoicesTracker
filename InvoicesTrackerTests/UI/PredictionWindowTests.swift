import AppKit
import SwiftUI
import Testing
@testable import InvoicesTracker

/// Odhad odvodů in the window of the app, made as the app makes it, on the prediction sample stored in a temporary
/// database, with the app as of Saturday 17. 10. 2026 unless a test says another day, and the least room the window
/// allows:
/// - The months of the clients start folded: the heading of the section and its subtitle show, no cell does. The
///   heading unfolds the clients that are expected to invoice, and "Ostatní odběratelé" the others. The folds are the
///   app's, so they stay while other screens are shown.
/// - A cell of a month that is open is a toggle button that reads its state; a click on it stores the person's choice,
///   and the client offers to take its months back to the app's choice. Cells of months that have invoices or are over
///   are not buttons.
/// - The months of a client stand in full rows: January to June over July to December at the least room, all twelve
///   in a row in a large window.
/// - The page follows today: a day that changes at midnight builds it again, with no write of the data and with "K
///   datu" on another internal day, which leaves the reporting cutoff alone while the reload key follows today.
/// - The toolbar offers the working year menu and new-invoice action without date controls. Switching screens leaves
///   an internally picked reporting cutoff alone, and choosing the current year resumes its automatic month end.
/// - The warnings stand above the summary: 2027, on 15. 1. 2027, has no rules of its own, so the page says that it is
///   an estimate with the rules of 2026, and a payment at a provisional rate has its line under that.
/// - VoiceOver reads the breakdown of the levies as one group under the name of the screen.
///
/// Parts of the page are also shown alone in a window of their own, with the pages the builder makes for the sample:
/// - A change that could not be saved is said under the heading of the months, and the months of a client that cannot
///   be chosen for are not buttons. Just above the width that has room for the legend beside the heading, the legend
///   keeps its one row there, and a cell has no line for a text it does not have.
/// - The summary of a year in progress has the three parts of the income and the note of what is paid next year, and
///   that of a year that is over has none of them but the part that was received. Both have the block of what is left
///   to settle beyond the advances, which VoiceOver reads as one. The sentence that no invoice is expected shows where
///   no client is.
///
/// The elements are found by what VoiceOver reads for them. In every expected string `\u{00A0}` is the no-break space.
@Suite(.serialized, .settlesBackups)
@MainActor
struct PredictionWindowTests {
    /// What a page needs is measured in the font it is set in, so the fonts are registered before any test, as the app
    /// does at its launch.
    init() {
        InvoiceFonts.register()
    }

    // MARK: Folding the months

    @Test func theScreenStartsFoldedAndUnfoldsItsMonths() async throws {
        try await PredictionSample.withStoredSample { app in
            try await withAppWindow(of: app, size: AppWindowSize.minimum) { window in
                try await withAccessibilityElements {
                    try await showPrediction(of: app, in: window)

                    // Folded: the heading and its subtitle show, and no cell does.
                    let header = try #require(accessibilityButton(labelled: "Kdy čekám faktury", in: window))
                    #expect(value(of: header) == "sbaleno")
                    #expect(accessibilityHelp(of: header) == Self.monthsSubtitle)
                    #expect(cellLabels(in: window).isEmpty)
                    #expect(accessibilityElement(labelled: "Měsíce – Foxtrot, Inc.", in: window) == nil)
                    #expect(accessibilityButton(labelled: Self.others, in: window) == nil)

                    // The heading unfolds the clients that are expected to invoice: Foxtrot's and Tango's cells show,
                    // Sierra's do not, but the group of the others is there, folded.
                    _ = header.accessibilityPerformPress?()
                    try await waitUntil { accessibilityElement(labelled: "Měsíce – Foxtrot, Inc.", in: window) != nil }
                    #expect(app.predictionMonthsOpen)
                    let unfolded = try #require(accessibilityButton(labelled: "Kdy čekám faktury", in: window))
                    #expect(value(of: unfolded) == "rozbaleno")
                    #expect(accessibilityElement(labelled: "Měsíce – Tango s.r.o.", in: window) != nil)
                    #expect(cellLabels(in: window).contains(Self.foxtrotJune))
                    #expect(cellLabels(in: window).count == 24, "\(cellLabels(in: window))")
                    #expect(accessibilityElement(labelled: "Měsíce – Sierra, SE", in: window) == nil)
                    let others = try #require(accessibilityButton(labelled: Self.others, in: window))
                    #expect(value(of: others) == "sbaleno")

                    // The group of the others unfolds Sierra's cells.
                    _ = others.accessibilityPerformPress?()
                    try await waitUntil { accessibilityElement(labelled: "Měsíce – Sierra, SE", in: window) != nil }
                    #expect(app.predictionOthersOpen)
                    let unfoldedOthers = try #require(accessibilityButton(labelled: Self.others, in: window))
                    #expect(value(of: unfoldedOthers) == "rozbaleno")
                    #expect(cellLabels(in: window).count == 36, "\(cellLabels(in: window))")
                    #expect(cellLabels(in: window).contains(Self.sierraJanuary))

                    // Both folds are the app's: they stay when the person comes back from another screen.
                    app.screen = .overview
                    try await waitUntil { window.title == "Přehled" }
                    app.screen = .prediction
                    try await waitUntil { accessibilityElement(labelled: "Měsíce – Sierra, SE", in: window) != nil }
                    #expect(cellLabels(in: window).count == 36)

                    // Folding the heading takes the cells away again.
                    let again = try #require(accessibilityButton(labelled: "Kdy čekám faktury", in: window))
                    _ = again.accessibilityPerformPress?()
                    try await waitUntil { cellLabels(in: window).isEmpty }
                    #expect(!app.predictionMonthsOpen)
                }
            }
        }
    }

    // MARK: Changing a month

    @Test func clickingAnOpenMonthChangesIt() async throws {
        try await PredictionSample.withStoredSample { app in
            let database = try #require(app.database)
            app.predictionMonthsOpen = true
            try await withAppWindow(of: app, size: AppWindowSize.minimum) { window in
                try await withAccessibilityElements {
                    try await showPrediction(of: app, in: window)
                    let expected = Self.foxtrotNovember
                    let switchedOff = "Listopad: fakturu nečekám"
                    try await waitUntil { accessibilityElement(labelled: expected, in: window) != nil }
                    #expect(accessibilityButton(labelled: "Vrátit odhad aplikace", in: window) == nil)

                    // Foxtrot's November is a month the app expects an invoice in; the click switches it off, and the
                    // choice differs from the app's, so it is stored.
                    let november = try #require(accessibilityElement(labelled: expected, in: window))
                    #expect(value(of: november) == "zapnuto")
                    _ = november.accessibilityPerformPress?()
                    try await waitUntil { accessibilityElement(labelled: switchedOff, in: window) != nil }

                    let changes = try await database.expectedInvoiceMonths(year: 2026)
                    #expect(changes == [PredictionSample.foxtrot.id: [11: false]])
                    let off = try #require(accessibilityElement(labelled: switchedOff, in: window))
                    #expect(value(of: off) == "vypnuto")
                    #expect(accessibilityElement(labelled: expected, in: window) == nil)

                    // The row of the client offers to take its months back, and doing so deletes the choice.
                    let reset = try #require(accessibilityButton(labelled: "Vrátit odhad aplikace", in: window))
                    _ = reset.accessibilityPerformPress?()
                    try await waitUntil { accessibilityElement(labelled: expected, in: window) != nil }

                    #expect(try await database.expectedInvoiceMonths(year: 2026).isEmpty)
                    #expect(accessibilityButton(labelled: "Vrátit odhad aplikace", in: window) == nil)
                    let on = try #require(accessibilityElement(labelled: expected, in: window))
                    #expect(value(of: on) == "zapnuto")
                }
            }
        }
    }

    @Test func aMonthOfAClientThatIsNotExpectedToInvoiceMovesTheClientUp() async throws {
        try await PredictionSample.withStoredSample { app in
            let database = try #require(app.database)
            app.predictionMonthsOpen = true
            app.predictionOthersOpen = true
            try await withAppWindow(of: app, size: AppWindowSize.minimum) { window in
                try await withAccessibilityElements {
                    try await showPrediction(of: app, in: window)
                    try await waitUntil { accessibilityElement(labelled: "Měsíce – Sierra, SE", in: window) != nil }

                    // Sierra's October is a month the app does not expect an invoice in.
                    let october = try #require(accessibilityElement(labelled: "Říjen: fakturu nečekám", in: window))
                    #expect(value(of: october) == "vypnuto")
                    _ = october.accessibilityPerformPress?()
                    try await waitUntil { accessibilityButton(labelled: Self.others, in: window) == nil }

                    // Sierra is expected to invoice now, so no client is left in the group of the others.
                    let changes = try await database.expectedInvoiceMonths(year: 2026)
                    #expect(changes == [PredictionSample.sierra.id: [10: true]])
                    #expect(accessibilityElement(labelled: "Měsíce – Sierra, SE", in: window) != nil)
                    #expect(accessibilityButton(labelled: "Vrátit odhad aplikace", in: window) != nil)
                }
            }
        }
    }

    // MARK: What a cell says

    @Test func theCellsSayWhatTheyHold() async throws {
        try await PredictionSample.withStoredSample { app in
            app.predictionMonthsOpen = true
            app.predictionOthersOpen = true
            try await withAppWindow(of: app, size: AppWindowSize.minimum) { window in
                try await withAccessibilityElements {
                    try await showPrediction(of: app, in: window)
                    try await waitUntil { accessibilityElement(labelled: "Měsíce – Sierra, SE", in: window) != nil }

                    // Months that have invoices, or are over, are read as what they hold and cannot be changed.
                    for label in [Self.foxtrotJune, Self.sierraJanuary, "Leden: žádná faktura"] {
                        let cell = try #require(accessibilityElement(labelled: label, in: window), "No cell: \(label)")
                        #expect(value(of: cell) == nil, "\(label) reads a state")
                        #expect(cell.accessibilityRole?() != .button, "\(label) is a button")
                    }

                    // Months that are open are toggles that read their state: an invoice expected, with the draft it
                    // is expected from, or paid only next year, and an invoice not expected.
                    let toggles: [(label: String, state: String)] = [
                        ("Říjen: čekám fakturu asi 256\u{00A0}693\u{00A0}Kč (koncept 20261001)", "zapnuto"),
                        (Self.foxtrotNovember, "zapnuto"),
                        ("Prosinec: čekám fakturu asi 285\u{00A0}693\u{00A0}Kč, zaplatí se až v roce 2027", "zapnuto"),
                        ("Říjen: fakturu nečekám", "vypnuto"),
                    ]
                    for (label, state) in toggles {
                        let cell = try #require(accessibilityElement(labelled: label, in: window), "No cell: \(label)")
                        #expect(value(of: cell) == state, "\(label) reads \(String(describing: value(of: cell)))")
                        // The toggle trait makes the button what AppKit calls a toggle button: a check box.
                        #expect(cell.accessibilityRole?() == .checkBox, "\(label) is not a toggle")
                        #expect(cell.accessibilityPerformPress != nil, "\(label) cannot be pressed")
                    }
                }
            }
        }
    }

    // MARK: The months in rows

    @Test func theMonthsStandInTwoFullRowsOfSixAtTheLeastRoomAndInOneRowInALargeWindow() async throws {
        try await PredictionSample.withStoredSample { app in
            app.predictionMonthsOpen = true
            try await withAppWindow(of: app, size: AppWindowSize.minimum) { window in
                try await withAccessibilityElements {
                    try await showPrediction(of: app, in: window)
                    try await waitUntil { accessibilityElement(labelled: "Měsíce – Foxtrot, Inc.", in: window) != nil }

                    // At the least room: January to June, and under them July to December, in the same columns.
                    try await expectSettled(window) { problems(ofTheMonthsOfFoxtrotIn: window, inRowsOf: 6) }
                    let group = try #require(accessibilityElement(labelled: "Měsíce – Foxtrot, Inc.", in: window))
                    let cells = (group.accessibilityChildren?() ?? []).map { $0 as AnyObject }
                    let january = try #require(cells.first)
                    let july = try #require(accessibilityElement(labelled: Self.foxtrotJuly, in: window))
                    #expect(cells.count == 12 && cells[6] === july, "July is not the seventh cell")
                    let januaryFrame = try #require(january.accessibilityFrame?())
                    let julyFrame = try #require(july.accessibilityFrame?())
                    // The origin of the screen is at the bottom left, so what is under has the smaller y.
                    #expect(
                        (julyFrame.minX - januaryFrame.minX).magnitude <= 1,
                        "July \(julyFrame) is not under January \(januaryFrame)")
                    #expect(
                        julyFrame.maxY <= januaryFrame.minY + 0.5,
                        "July \(julyFrame) is not on the row under January \(januaryFrame)")

                    // A large window has room for all twelve in a row.
                    window.setContentSize(AppWindowSize.large)
                    try await expectSettled(window) { problems(ofTheMonthsOfFoxtrotIn: window, inRowsOf: 12) }
                }
            }
        }
    }

    // MARK: Today

    @Test func aPageLoadedForOneDayIsBuiltAgainForTheNextWithoutAnyWrite() async throws {
        try await PredictionSample.withStoredSample { app in
            // "K datu" is on another day, so midnight moves nothing the screens load for but today.
            app.pickAsOf(civilDate("2026-07-15"))
            try await withAppWindow(of: app, size: AppWindowSize.minimum) { window in
                try await withAccessibilityElements {
                    try await showPrediction(of: app, in: window)
                    let sentence = "Odhad vychází z faktur do "
                    let on17th = sentence + "17.\u{00A0}10.\u{00A0}2026:"
                    let on18th = sentence + "18.\u{00A0}10.\u{00A0}2026:"
                    try await waitUntil { frameOfText(startingWith: on17th, in: window) != nil }
                    let key = app.reloadKey
                    let version = app.dataVersion

                    app.handleDayChanged(civilDate("2026-10-18"))

                    #expect(app.reloadKey != key)
                    #expect(app.reloadKey.asOf == key.asOf)
                    #expect(app.reloadKey.year == key.year)
                    #expect(app.reloadKey.today == civilDate("2026-10-18"))
                    #expect(app.dataVersion == version)
                    try await waitUntil { frameOfText(startingWith: on18th, in: window) != nil }
                    #expect(frameOfText(startingWith: on17th, in: window) == nil)
                    try await expectSettled(window) { mainToolbarProblems(in: window) }
                    #expect(app.dataVersion == version)
                }
            }
        }
    }

    // MARK: The warnings

    /// 2027 has no tax rules of its own yet, so on 15. 1. 2027 the page says that it is an estimate with the rules of
    /// 2026, in the box above the summary card. No payment is at a provisional rate, so the line about one is not
    /// there.
    @Test func aYearWithoutItsOwnRulesShowsTheWarningAboveTheSummary() async throws {
        try await PredictionSample.withStoredSample(clock: ManualClock(localNoon(2027, 1, 15))) { app in
            try await withAppWindow(of: app, size: AppWindowSize.minimum) { window in
                try await withAccessibilityElements {
                    try await showPrediction(of: app, in: window, summary: Self.summaryOf2027)

                    let message = RulesWarning.message(year: 2027, rulesYear: 2026)
                    #expect(showsText(message, in: window))
                    let warning = try #require(frameOfText(startingWith: message, in: window))
                    let summary = try #require(frameOfCard(labelled: Self.summaryOf2027, in: window))
                    // The origin of the screen is at the bottom left, so what is above has the larger y.
                    #expect(warning.minY >= summary.maxY - 0.5, "\(warning) is not above \(summary)")
                    #expect(frameOfText(startingWith: RulesWarning.provisionalIncome, in: window) == nil)
                }
            }
        }
    }

    /// A payment at a provisional rate has its line under the warning of the rules and above the summary, as on
    /// Výpočet.
    @Test func theLineOfAProvisionalRateStandsUnderTheWarningOfTheRules() async throws {
        try await PredictionSample.withStoredSample(clock: ManualClock(localNoon(2027, 1, 15))) { app in
            try await #require(app.database).saveInvoiceWithProvisionalPayment(on: "2027-01-10")
            try await withAppWindow(of: app, size: AppWindowSize.minimum) { window in
                try await withAccessibilityElements {
                    try await showPrediction(of: app, in: window, summary: Self.summaryOf2027)

                    let message = RulesWarning.message(year: 2027, rulesYear: 2026)
                    let rules = try #require(frameOfText(startingWith: message, in: window))
                    let notice = try #require(frameOfText(startingWith: RulesWarning.provisionalIncome, in: window))
                    let summary = try #require(frameOfCard(labelled: Self.summaryOf2027, in: window))
                    // The origin of the screen is at the bottom left, so what is above has the larger y.
                    #expect(rules.minY >= notice.maxY - 0.5, "\(rules) is not above \(notice)")
                    #expect(notice.minY >= summary.maxY - 0.5, "\(notice) is not above \(summary)")
                }
            }
        }
    }

    // MARK: The breakdown

    /// VoiceOver reads the breakdown of the levies, the cards under "Rozpis výpočtu", as one group under the name of
    /// the screen.
    @Test func theBreakdownIsReadAsOneGroupUnderTheNameOfTheScreen() async throws {
        try await PredictionSample.withStoredSample { app in
            try await withAppWindow(of: app, size: AppWindowSize.minimum) { window in
                try await withAccessibilityElements {
                    try await showPrediction(of: app, in: window)

                    #expect(frameOfCard(labelled: "Rozpis odhadu odvodů", in: window) != nil)
                }
            }
        }
    }

    // MARK: The toolbar

    /// Prediction uses today's data while the toolbar offers the year and keeps the internal reporting day alone.
    @Test func predictionOffersTheYearWithoutReportingDateControls() async throws {
        try await PredictionSample.withStoredSample { app in
            app.pickAsOf(civilDate("2026-07-15"))
            try await withAppWindow(of: app, size: AppWindowSize.minimum) { window in
                try await withAccessibilityElements {
                    try await showPrediction(of: app, in: window)
                    try await expectSettled(window) { mainToolbarProblems(in: window) }
                    #expect(app.asOf.asOf == civilDate("2026-07-15"))
                }
            }
        }
    }

    /// A past year's prediction leaves its internal reporting day alone and keeps the year menu available.
    @Test func aPastYearsPredictionHasNoReportingDateControls() async throws {
        try await PredictionSample.withStoredSample { app in
            app.selectYear(2025)
            app.pickAsOf(civilDate("2025-06-30"))
            try await withAppWindow(of: app, size: AppWindowSize.minimum) { window in
                try await withAccessibilityElements {
                    app.screen = .prediction
                    try await waitUntil { window.title == "Odhad odvodů" }
                    try await expectSettled(window) { mainToolbarProblems(in: window) }
                    #expect(app.asOf.asOf == civilDate("2025-06-30"))
                    #expect(app.asOf.year == 2025)
                }
            }
        }
    }

    /// Moving between prediction and overview preserves an internally picked cutoff and the working year menu.
    @Test func switchingFromPredictionKeepsTheInternalReportingCutoff() async throws {
        try await PredictionSample.withStoredSample { app in
            app.pickAsOf(civilDate("2026-07-15"))
            try await withAppWindow(of: app, size: AppWindowSize.minimum) { window in
                try await withAccessibilityElements {
                    try await showPrediction(of: app, in: window)
                    try await expectSettled(window) { mainToolbarProblems(in: window) }
                    #expect(app.asOf.asOf == civilDate("2026-07-15"))

                    app.screen = .overview
                    try await waitUntil { window.title == "Přehled" }
                    try await expectSettled(window) { mainToolbarProblems(in: window) }
                    #expect(app.asOf.asOf == civilDate("2026-07-15"))
                    #expect(app.asOf.year == 2026)
                    #expect(!app.asOf.followsToday)
                }
            }
        }
    }

    /// The year menu works on prediction: a past year selects its end, and the current year resumes month end.
    @Test func theYearMenuOnPredictionResumesTheAutomaticCurrentMonthCutoff() async throws {
        try await PredictionSample.withStoredSample { app in
            app.pickAsOf(civilDate("2026-07-15"))
            try await withAppWindow(of: app, size: AppWindowSize.minimum) { window in
                try await withAccessibilityElements {
                    try await showPrediction(of: app, in: window)
                    try await expectSettled(window) { mainToolbarProblems(in: window) }

                    app.selectYear(2025)
                    #expect(app.asOf.asOf == civilDate("2025-12-31"))
                    try await expectSettled(window) { mainToolbarProblems(in: window) }

                    app.selectYear(2026)
                    #expect(app.asOf.asOf == civilDate("2026-10-31"))
                    #expect(app.asOf.followsToday)
                    try await expectSettled(window) { mainToolbarProblems(in: window) }
                }
            }
        }
    }

    // MARK: Parts of the page in a window of their own

    @Test func aChangeThatCouldNotBeSavedIsSaidUnderTheHeadingOfTheMonths() async throws {
        let section = months(of: try PredictionSample.page(year: 2026), saveFailure: PredictionModel.saveFailureText)
        try await withHostedView(section.padding(24)) { window in
            try await withAccessibilityElements {
                try await waitUntil { showsText(PredictionModel.saveFailureText, in: window) }

                let failure = try #require(frameOfText(startingWith: PredictionModel.saveFailureText, in: window))
                let header = try #require(accessibilityButton(labelled: "Kdy čekám faktury", in: window))
                let heading = try #require(header.accessibilityFrame?())
                let firstClient = try #require(frameOfCard(labelled: "Měsíce – Foxtrot, Inc.", in: window))
                // The origin of the screen is at the bottom left, so what is under has the smaller y.
                #expect(failure.maxY <= heading.minY + 0.5, "\(failure) is not under \(heading)")
                #expect(failure.minY >= firstClient.maxY - 0.5, "\(failure) is not above \(firstClient)")
            }
        }
    }

    @Test func aMonthOfAClientThatCannotBeChosenForIsNotAButton() async throws {
        var page = try PredictionSample.page(year: 2026)
        // October and November of the first client are open months, but the client is one the app does not know.
        for index in [9, 10] {
            page.activeRows[0].cells[index].isToggle = false
        }
        try await withHostedView(months(of: page).padding(24)) { window in
            try await withAccessibilityElements {
                let october = "Říjen: čekám fakturu asi 256\u{00A0}693\u{00A0}Kč (koncept 20261001)"
                try await waitUntil { accessibilityElement(labelled: october, in: window) != nil }

                let cell = try #require(accessibilityElement(labelled: october, in: window))
                #expect(value(of: cell) == nil)
                #expect(cell.accessibilityRole?() != .button)
                // The same month of the other client is still a toggle.
                let other = "Říjen: čekám fakturu asi 4\u{00A0}500\u{00A0}Kč"
                #expect(value(of: try #require(accessibilityElement(labelled: other, in: window))) == "zapnuto")
            }
        }
    }

    /// Just above the width at which the legend of the cells has room beside the heading of the months, at 836 points,
    /// the legend keeps its one row there: it takes as much room beside the heading as in a card of 1 200 points, which
    /// has room for the row whatever it is given. Squeezed into two rows it would be narrower, and the heading wider.
    @Test func theLegendBesideTheHeadingOfTheMonthsKeepsItsOneRow() async throws {
        let page = try PredictionSample.page(year: 2026)

        let atTheEdge = try await roomRightOfTheHeading(of: page, inACardOf: 836)
        let wide = try await roomRightOfTheHeading(of: page, inACardOf: 1_200)

        // The legend stands beside the heading, after its gap of 16 points and before the margin of 22.
        #expect(atTheEdge > 22 + 16 + 100, "the heading leaves only \(atTheEdge) points")
        #expect((atTheEdge - wide).magnitude <= 1, "\(atTheEdge) points beside the heading at 836, \(wide) at 1 200")
    }

    /// A cell has a line only for a text it has. A month that is not expected has no amount, so "nečekám" stands right
    /// under the name of the month, and a month that is over has nothing under its dash: their two lines fit in the
    /// least height of a cell, 52 points. An empty line for the text they do not have would make them about as tall as
    /// a cell with all three lines, which needs more.
    @Test func aCellHasNoLineForATextItDoesNotHave() {
        let full = height(ofACellWithValue: "≈\u{00A0}4\u{00A0}500", sub: "čekám", kind: .expected)
        let notExpected = height(ofACellWithValue: "", sub: "nečekám", kind: .notExpected)
        let over = height(ofACellWithValue: "—", sub: "", kind: .past)

        #expect(full > 52, "a cell with three lines is \(full) points high")
        #expect(notExpected == 52, "a cell that is not expected is \(notExpected) points high")
        #expect(over == 52, "a cell that is over is \(over) points high")
    }

    @Test func theSentenceThatNoInvoiceIsExpectedShowsWhereNoClientIs() async throws {
        var page = try PredictionSample.page(year: 2026)
        // Every client is one of the others, folded.
        page.otherRows = page.activeRows + page.otherRows
        page.activeRows = []
        page.othersTitle = "Ostatní odběratelé (3)"
        page.noActiveText = PredictionBuilder.noActiveText
        try await withHostedView(months(of: page).padding(24)) { window in
            try await withAccessibilityElements {
                try await waitUntil { showsText(PredictionBuilder.noActiveText, in: window) }

                #expect(accessibilityButton(labelled: "Ostatní odběratelé (3)", in: window) != nil)
                #expect(cellLabels(in: window).isEmpty)
            }
        }
    }

    @Test func theSummaryOfAYearInProgressHasItsThreePartsTheNoteOfNextYearAndTheSettlement() async throws {
        let page = try PredictionSample.page(year: 2026)
        try await withHostedView(PredictionSummaryCard(page: page).padding(24)) { window in
            try await withAccessibilityElements {
                try await waitUntil { showsText("466\u{00A0}782\u{00A0}Kč", in: window) }

                #expect(showsText("ODHAD ODVODŮ ZA CELÝ ROK 2026", in: window))
                #expect(!showsText("odhad", in: window))
                let readings = accessibilityReadings(in: window)
                for part in page.parts {
                    #expect(readings.contains("\(part.text), \(part.value)"), "no part \(part.text) in \(readings)")
                }
                #expect(page.parts.count == 3)
                let income = "Příjmy za rok 2026 (odhad): 2\u{00A0}743\u{00A0}157\u{00A0}Kč"
                #expect(accessibilityElement(labelled: income, in: window) != nil)
                let note = try #require(page.nextYearNote)
                #expect(showsText(note, in: window))
                #expect(readings.contains("Daň, 114\u{00A0}786\u{00A0}Kč"))
                // The caption, the amount and the whole sentence are one reading, in this order, and nothing of them is
                // read apart. The caption reads as it is written, not in capitals.
                let settlement =
                    "Odhad doplatku odvodů bez záloh, 198\u{00A0}702\u{00A0}Kč,"
                    + " Tolik si odložte stranou – navíc k zálohám 268\u{00A0}080\u{00A0}Kč, které platíte průběžně."
                    + " Platí se po skončení roku s přiznáním a přehledy pro ČSSZ a VZP."
                #expect(
                    readings.filter { $0.contains("198\u{00A0}702") || $0.contains("navíc k zálohám") } == [settlement])
                for gone in ["Doplatek s přiznáním", "Zálohy za rok", "Z další koruny příjmu"] {
                    #expect(!readings.contains { $0.contains(gone) }, "\(gone) is still there")
                }
            }
        }
    }

    @Test func theSummaryOfAYearThatIsOverHasOnlyWhatWasReceivedAndTheSettlement() async throws {
        let page = try PredictionSample.page(year: 2025)
        try await withHostedView(PredictionSummaryCard(page: page).padding(24)) { window in
            try await withAccessibilityElements {
                try await waitUntil { showsText("537\u{00A0}865\u{00A0}Kč", in: window) }

                #expect(showsText("ODVODY ZA ROK 2025 – SKUTEČNOST", in: window))
                #expect(!showsText("odhad", in: window))
                #expect(page.nextYearNote == nil)
                let readings = accessibilityReadings(in: window)
                #expect(readings.contains("Přišlo do 31.\u{00A0}12.\u{00A0}2025, 2\u{00A0}931\u{00A0}160\u{00A0}Kč"))
                #expect(!readings.contains { $0.hasPrefix("Vystaveno") || $0.hasPrefix("Koncepty") })
                let income = "Příjmy za rok 2025: 2\u{00A0}931\u{00A0}160\u{00A0}Kč"
                #expect(accessibilityElement(labelled: income, in: window) != nil)
                let settlement =
                    "Doplatek odvodů bez záloh, 330\u{00A0}065\u{00A0}Kč,"
                    + " Za rok 2025 navíc k zálohám 207\u{00A0}800\u{00A0}Kč"
                    + " – daň, ČSSZ a VZP po podání přiznání a přehledů."
                #expect(
                    readings.filter { $0.contains("330\u{00A0}065") || $0.contains("navíc k zálohám") } == [settlement])
                for gone in ["Doplatek s přiznáním", "Zálohy za rok", "Z další koruny příjmu"] {
                    #expect(!readings.contains { $0.contains(gone) }, "\(gone) is still there")
                }
            }
        }
    }

    // MARK: Helpers

    private static let monthsSubtitle =
        "Měsíce s očekávanou fakturou předvyplňuje aplikace podle dosavadních faktur."
        + " Klepnutím je změníte, když víte víc – třeba u nové zakázky nebo když spolupráce končí."


    /// The group of the other clients of the sample's 2026, folded.
    private static let others = "Ostatní odběratelé (1)"

    /// The label of the summary card of 2027 as of 15. 1. 2027.
    private static let summaryOf2027 = "Odhad odvodů za celý rok 2027"

    private static let foxtrotJune = "Červen: faktura 20260601, 288\u{00A0}806\u{00A0}Kč, zaplaceno"
    private static let foxtrotJuly = "Červenec: faktura 20260701, 268\u{00A0}806\u{00A0}Kč, zaplaceno"
    private static let foxtrotNovember = "Listopad: čekám fakturu asi 285\u{00A0}693\u{00A0}Kč"
    private static let sierraJanuary = "Leden: faktura 2026-01-01, 220\u{00A0}000\u{00A0}Kč, zaplaceno"

    /// The months a label of a cell starts with.
    private static let monthNames = [
        "Leden", "Únor", "Březen", "Duben", "Květen", "Červen", "Červenec", "Srpen", "Září", "Říjen", "Listopad",
        "Prosinec",
    ]

    /// The card of the months for `page`, unfolded and with the others folded, which changes nothing it is told of.
    private func months(of page: PredictionPage, saveFailure: String? = nil) -> PredictionMonthsSection {
        PredictionMonthsSection(
            page: page, saveFailure: saveFailure, isOpen: .constant(true), othersAreOpen: .constant(false),
            toggle: { _, _ in }, reset: { _ in })
    }

    /// How far the heading of the card of the months of `page` ends from the right edge of the card, `width` points
    /// wide, shown alone in a window: the room of the legend beside the heading, with the gap before it and the margin
    /// of the card after it.
    private func roomRightOfTheHeading(of page: PredictionPage, inACardOf width: CGFloat) async throws -> CGFloat {
        var room: CGFloat = 0
        let size = CGSize(width: width + 100, height: 700)
        try await withHostedView(months(of: page).frame(width: width), size: size) { window in
            try await withAccessibilityElements {
                try await waitUntil { frameOfCard(labelled: "Kdy čekám faktury", in: window) != nil }
                try await layOut(window)
                let card = try #require(frameOfCard(labelled: "Kdy čekám faktury", in: window))
                let header = try #require(accessibilityButton(labelled: "Kdy čekám faktury", in: window))
                let heading = try #require(header.accessibilityFrame?())
                room = card.maxX - heading.maxX
            }
        }
        return room
    }

    /// The height of a cell of October of `kind` with `value` and `sub`, not a toggle, in a column of 64 points, the
    /// least a cell has.
    private func height(ofACellWithValue value: String, sub: String, kind: PredictionCellKind) -> CGFloat {
        let cell = PredictionCell(
            month: 10, label: "říj", value: value, sub: sub, kind: kind, isToggle: false, isOn: false,
            accessibilityLabel: "Říjen")
        return NSHostingView(rootView: PredictionMonthCell(cell: cell, toggle: {}).frame(width: 64)).fittingSize.height
    }

    /// What is wrong with how the months of Foxtrot, Inc. stand in `window`, in words: they are not twelve cells, or a
    /// cell is not as wide as the first, not level with the first of its row, not under the cell of its column in the
    /// first row, or not under the row above it. In a row they are one after the other. Empty when they stand in full
    /// rows of `columns`. Needs the accessibility elements.
    private func problems(ofTheMonthsOfFoxtrotIn window: NSWindow, inRowsOf columns: Int) -> [String] {
        guard let group = accessibilityElement(labelled: "Měsíce – Foxtrot, Inc.", in: window) else {
            return ["No months of Foxtrot, Inc."]
        }
        let frames = (group.accessibilityChildren?() ?? []).compactMap { ($0 as AnyObject).accessibilityFrame?() }
        guard frames.count == 12 else {
            return ["Foxtrot, Inc. has \(frames.count) cells, not 12"]
        }
        var found: [String] = []
        for (index, frame) in frames.enumerated() {
            let row = index / columns
            let column = index % columns
            let ofItsColumn = frames[column]
            let firstOfItsRow = frames[row * columns]
            if (frame.width - frames[0].width).magnitude > 1 {
                found.append("Month \(index + 1) is not as wide as the first: \(frame), \(frames[0])")
            }
            if (frame.minX - ofItsColumn.minX).magnitude > 1 {
                found.append("Month \(index + 1) is not under month \(column + 1): \(frame), \(ofItsColumn)")
            }
            if (frame.maxY - firstOfItsRow.maxY).magnitude > 1 {
                found.append("Month \(index + 1) is not level with month \(row * columns + 1): \(frame)")
            }
            if column > 0, frame.minX < frames[index - 1].maxX - 0.5 {
                found.append("Month \(index + 1) is not to the right of month \(index): \(frame)")
            }
            // The origin of the screen is at the bottom left, so what is under has the smaller y.
            if row > 0, frame.maxY > frames[(row - 1) * columns].minY + 0.5 {
                found.append("Month \(index + 1) is not under the row above it: \(frame)")
            }
        }
        return found
    }

    /// Shows Odhad odvodů in `window` and waits until its page is there, which has the summary card labelled `summary`
    /// (the one of the year in progress unless told otherwise). Needs the accessibility elements.
    private func showPrediction(
        of app: AppModel, in window: NSWindow, summary: String = "Odhad odvodů za celý rok 2026"
    ) async throws {
        app.screen = .prediction
        try await waitUntil { window.title == "Odhad odvodů" }
        try await waitUntil { frameOfCard(labelled: summary, in: window) != nil }
        try await layOut(window)
    }

    /// What VoiceOver reads for each cell of the months on the page: the readings that start with a month and a colon.
    private func cellLabels(in window: NSWindow) -> [String] {
        accessibilityReadings(in: window).filter { reading in
            Self.monthNames.contains { reading.hasPrefix($0 + ": ") }
        }
    }

    /// The value VoiceOver reads for `element`, or nil for none.
    private func value(of element: AnyObject) -> String? {
        let value: (() -> Any?)? = element.accessibilityValue
        let text = (value?() ?? nil) as? String
        return text?.isEmpty == false ? text : nil
    }
    /// The real summary exposes the incomplete explanation and known receipt labels without calculated totals.
    @Test func anIncompleteSummaryExplainsUnavailableFiguresInTheWindow() async throws {
        var input = PredictionSample.input(year: 2026)
        input.averageRates = [:]
        let outcome = try PredictionOutcome.make(
            prediction: IncomePrediction.make(input), yearInput: PredictionSample.yearInput(year: 2026))
        let page = PredictionBuilder.page(outcome)
        try await withHostedView(PredictionSummaryCard(page: page).padding(24)) { window in
            try await withAccessibilityElements {
                try await waitUntil { showsText(PredictionBuilder.incompleteText, in: window) }
                let readings = accessibilityReadings(in: window)
                #expect(readings.contains("Příjmy za rok 2026 (odhad): —"))
                #expect(readings.contains("Přišlo do 17.\u{00A0}10.\u{00A0}2026, 2\u{00A0}191\u{00A0}771\u{00A0}Kč"))
                #expect(!readings.contains { $0.contains("466\u{00A0}782") || $0.contains("17,0") })
            }
        }
    }

}
