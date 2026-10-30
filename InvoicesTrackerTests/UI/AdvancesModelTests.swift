import Foundation
import Testing
@testable import InvoicesTracker

/// The model of Zálohy a odpočty: the plan of advances as texts, the totals of the year and to the day shown, how a
/// cell that is not an amount is refused, what is saved and when, the change of the year, the secondary activity, the
/// prefill, the copy from the year before, and the family: a child is written at once, the spouse is saved at once
/// with the settings, and the spouse's own income is a typed field like those of the deductions. The data is the
/// sample year of the engine's regression test, stored in a temporary database; the app is as of 17. 10. 2026. A model
/// has no delay before it saves unless a test gives it one (`saveDelay`), and the tests that need a save to wait give
/// it an hour and save by hand. In every expected string `\u{00A0}` is the no-break space.
@Suite(.settlesBackups)
@MainActor
struct AdvancesModelTests {
    // MARK: The plan and its totals

    @Test func theRegressionPlanIsShownAsTextsWithItsTotalsOfTheYearAndToTheDayShown() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let app = try await makeAdvancesApp(in: directory)
        let model = AdvancesModel(app: app, saveDelay: .zero)
        #expect(model.settings == nil)

        await model.load()

        #expect(model.settings == SampleYear2026.yearSettings)
        #expect(model.cells.count == 12)
        // Zero is an empty cell; thousands are separated by a no-break space.
        #expect(model.cells[0] == ["13\u{00A0}340", "6\u{00A0}920", ""])
        #expect(model.cells[3] == ["13\u{00A0}340", "6\u{00A0}920", ""])
        #expect(model.cells[4] == ["12\u{00A0}150", "5\u{00A0}480", ""])
        #expect(model.cells[5] == ["12\u{00A0}150", "5\u{00A0}480", "23\u{00A0}000"])
        #expect(model.cells[11] == ["12\u{00A0}150", "5\u{00A0}480", "23\u{00A0}000"])
        // The year: 4 × 13 340 + 8 × 12 150, 4 × 6 920 + 8 × 5 480, and two quarters of 23 000.
        #expect(model.totals.yearSocial == 150_560)
        #expect(model.totals.yearHealth == 71_520)
        #expect(model.totals.yearTax == 46_000)
        // To 17. 10. 2026: January to October.
        #expect(model.totals.toDateSocial == 126_260)
        #expect(model.totals.toDateHealth == 60_560)
        #expect(model.totals.toDateTax == 23_000)
        #expect(model.toDateLabel == "Započteno k 17.\u{00A0}10.")
        #expect(model.isCounted(month: 10))
        #expect(!model.isCounted(month: 11))
    }

    @Test func aPastYearIsCountedWhole() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let app = try await makeAdvancesApp(in: directory)
        try await storeYear(advancesYear2025(), in: app)
        app.selectYear(2025)

        let model = await loadedAdvancesModel(of: app)

        #expect(model.totals.yearSocial == 113_400)
        #expect(model.totals.toDateSocial == 113_400)
        #expect(model.totals.toDateTax == 38_000)
        #expect(model.toDateLabel == "Zaplaceno za rok")
        #expect(model.isCounted(month: 12))
    }

    @Test func aPastYearShownAsOfADayInItIsNotCountedWhole() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let app = try await makeAdvancesApp(in: directory)
        try await storeYear(advancesYear2025(), in: app)
        app.selectYear(2025)
        app.pickAsOf(civilDate("2025-06-30"))

        let model = await loadedAdvancesModel(of: app)

        // The year is over, but the day shown is not its last: the advances of the months after June are still to come.
        #expect(model.toDateLabel == "Započteno k 30.\u{00A0}6.")
        #expect(model.isCounted(month: 6))
        #expect(!model.isCounted(month: 7))
        #expect(model.totals.toDateSocial == 6 * 9_450)
        #expect(model.totals.yearSocial == 113_400)

        // Its last day is the year as it ended.
        app.pickAsOf(civilDate("2025-12-31"))
        await model.load()

        #expect(model.toDateLabel == "Zaplaceno za rok")
        #expect(model.totals.toDateSocial == 113_400)
    }

    @Test func theTotalsToTheDayFollowTheDayShown() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let app = try await makeAdvancesApp(in: directory)
        let model = await loadedAdvancesModel(of: app)

        // The sixth month counts the plan up to June, whose tax advance is the first of the year.
        app.pickAsOf(civilDate("2026-06-30"))
        await model.load()

        #expect(model.totals.toDateSocial == 4 * 13_340 + 2 * 12_150)
        #expect(model.totals.toDateHealth == 4 * 6_920 + 2 * 5_480)
        #expect(model.totals.toDateTax == 23_000)
        #expect(model.toDateLabel == "Započteno k 30.\u{00A0}6.")
        #expect(model.totals.yearSocial == 150_560)

        app.pickAsOf(civilDate("2026-05-31"))
        await model.load()

        #expect(model.totals.toDateTax == 0)
    }

    @Test func aYearWithNothingStoredHasAnEmptyPlan() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let app = try await makeAdvancesApp(in: directory)
        app.selectYear(2024)

        let model = await loadedAdvancesModel(of: app)

        #expect(model.settings == YearSettings(year: 2024))
        #expect(model.cells == [[String]](repeating: ["", "", ""], count: 12))
        #expect(model.totals.yearSocial == 0)
        #expect(model.totals.toDateTax == 0)
        #expect(!model.hasPreviousYear)
    }

    @Test func theTextOfAnotherYearIsShownWhenTheYearChanges() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let app = try await makeAdvancesApp(in: directory)
        try await storeYear(advancesYear2025(), in: app)
        let model = await loadedAdvancesModel(of: app)
        #expect(model.cells[0][0] == "13\u{00A0}340")

        app.selectYear(2025)
        await model.load()

        #expect(model.settings?.year == 2025)
        #expect(model.cells[0] == ["9\u{00A0}450", "4\u{00A0}700", ""])
        #expect(model.cells[5][2] == "19\u{00A0}000")
    }

    // MARK: Cells

    @Test func aCellThatIsNotInWholeCrownsIsRefusedWithTheMessageAndNotSaved() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let app = try await makeAdvancesApp(in: directory)
        let model = await loadedAdvancesModel(of: app)
        let versionBefore = app.dataVersion

        model.setCell(month: 3, column: 0, text: "13 340,50")
        await model.saveNow()

        #expect(model.cellError(month: 3, column: 0) == advancesWholeKcMessage)
        // The text stays where the person typed it, and the plan is as it was.
        #expect(model.cells[2][0] == "13 340,50")
        #expect(model.settings?.advances.social[2] == 13_340)
        #expect(model.totals.yearSocial == 150_560)
        #expect(try await storedYear(2026, in: app).advances.social[2] == 13_340)
        #expect(app.dataVersion == versionBefore)
        // The other cells are not in question.
        #expect(model.cellError(month: 3, column: 1) == nil)
        #expect(model.cellError(month: 4, column: 0) == nil)
    }

    @Test(arguments: ["1.234,50", "abc", "13 34", "-100", "−5", "12,5", "1e3", "13 340 Kč"])
    func textThatIsNotAWholeAmountOfCrownsIsRefused(text: String) async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let app = try await makeAdvancesApp(in: directory)
        let model = await loadedAdvancesModel(of: app)

        model.setCell(month: 1, column: 1, text: text)
        await model.saveNow()

        #expect(model.cellError(month: 1, column: 1) == advancesWholeKcMessage)
        #expect(model.cells[0][1] == text)
        #expect(try await storedYear(2026, in: app).advances.health[0] == 6_920)
    }

    @Test(arguments: ["13 000", "13000", "13\u{00A0}000", "13 000,00", " 13 000 ", "013 000"])
    func wholeAmountsAreAccepted(text: String) async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let app = try await makeAdvancesApp(in: directory)
        let model = await loadedAdvancesModel(of: app)

        model.setCell(month: 2, column: 0, text: text)
        await model.saveNow()

        #expect(model.cellError(month: 2, column: 0) == nil)
        #expect(model.cells[1][0] == text)
        #expect(try await storedYear(2026, in: app).advances.social[1] == 13_000)
    }

    @Test func aRefusedCellIsAcceptedOnceItIsCorrected() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let app = try await makeAdvancesApp(in: directory)
        let model = await loadedAdvancesModel(of: app)
        model.setCell(month: 3, column: 0, text: "13 340,50")
        await model.saveNow()
        #expect(model.cellError(month: 3, column: 0) != nil)

        model.setCell(month: 3, column: 0, text: "13 341")
        await model.saveNow()

        #expect(model.cellError(month: 3, column: 0) == nil)
        #expect(try await storedYear(2026, in: app).advances.social[2] == 13_341)
        #expect(model.totals.yearSocial == 150_561)
    }

    @Test func anEmptyCellIsNoAdvance() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let app = try await makeAdvancesApp(in: directory)
        let model = await loadedAdvancesModel(of: app)

        model.setCell(month: 6, column: 2, text: "")
        await model.saveNow()

        #expect(model.cellError(month: 6, column: 2) == nil)
        #expect(try await storedYear(2026, in: app).advances.tax[5] == 0)
        #expect(model.totals.yearTax == 23_000)
    }

    @Test func aCellOutsideThePlanIsLeftAlone() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let app = try await makeAdvancesApp(in: directory)
        let model = await loadedAdvancesModel(of: app)
        let cells = model.cells

        model.setCell(month: 0, column: 0, text: "1")
        model.setCell(month: 13, column: 0, text: "1")
        model.setCell(month: 1, column: 3, text: "1")
        model.setCell(month: 1, column: -1, text: "1")
        model.setSecondary(month: 0, true)
        model.setSecondary(month: 13, true)
        await model.saveNow()

        #expect(model.cells == cells)
        #expect(model.settings == SampleYear2026.yearSettings)
    }

    @Test func aCellSavesAfterTheDelayWithoutAnythingElseAskingForIt() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let app = try await makeAdvancesApp(in: directory)
        let database = try #require(app.database)
        let model = await loadedAdvancesModel(of: app, saveDelay: .zero)
        let versionBefore = app.dataVersion

        model.setCell(month: 3, column: 0, text: "13 000")

        try await waitUntil { try await database.yearSettings(2026).advances.social[2] == 13_000 }
        // The screens are told of the write, so that they load again.
        try await waitUntil { app.dataVersion > versionBefore }
        #expect(model.settings?.advances.social[2] == 13_000)
        #expect(model.totals.yearSocial == 150_560 - 13_340 + 13_000)
        // The write is over only when the app has been told of it and has made its backup.
        await model.saveNow()
    }

    @Test func nothingIsSavedBeforeTheDelayIsOverOrTheScreenIsLeft() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let app = try await makeAdvancesApp(in: directory)
        let model = await loadedAdvancesModel(of: app, saveDelay: .seconds(3_600))
        let versionBefore = app.dataVersion

        model.setCell(month: 3, column: 0, text: "13 000")
        try await Task.sleep(for: .milliseconds(100))

        // The text is read when the typing stops: until then the plan, its totals and the data are as they were.
        #expect(model.totals.yearSocial == 150_560)
        #expect(try await storedYear(2026, in: app).advances.social[2] == 13_340)
        #expect(app.dataVersion == versionBefore)

        // Losing the focus, or leaving the screen, reads the text and saves it.
        await model.saveNow()

        #expect(model.totals.yearSocial == 150_560 - 13_340 + 13_000)
        #expect(try await storedYear(2026, in: app).advances.social[2] == 13_000)
        #expect(app.dataVersion == versionBefore + 1)
    }

    @Test func severalChangesBeforeTheDelayIsOverAreOneWrite() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let app = try await makeAdvancesApp(in: directory)
        let model = await loadedAdvancesModel(of: app, saveDelay: .seconds(3_600))
        let versionBefore = app.dataVersion

        model.setCell(month: 3, column: 0, text: "1")
        model.setCell(month: 3, column: 0, text: "13")
        model.setCell(month: 3, column: 0, text: "13 000")
        model.setCell(month: 3, column: 1, text: "7 000")
        model.setSecondary(month: 9, true)
        await model.saveNow()

        let saved = try await storedYear(2026, in: app)
        #expect(saved.advances.social[2] == 13_000)
        #expect(saved.advances.health[2] == 7_000)
        #expect(saved.secondaryMonths == [9])
        #expect(app.dataVersion == versionBefore + 1)

        // Nothing waits any more.
        await model.saveNow()
        #expect(app.dataVersion == versionBefore + 1)
    }

    @Test func aValueTypedAgainAsItIsStoredWritesNothing() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let app = try await makeAdvancesApp(in: directory)
        let model = await loadedAdvancesModel(of: app)
        let versionBefore = app.dataVersion

        model.setCell(month: 1, column: 0, text: "13340")
        model.setSecondary(month: 5, false)
        model.setExpensePercent(60)
        model.setTaxpayerCredit(true)
        await model.saveNow()

        #expect(app.dataVersion == versionBefore)
    }

    @Test func onlyWhatChangedIsWrittenSoAnotherWritersChangeIsKept() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let app = try await makeAdvancesApp(in: directory)
        let model = await loadedAdvancesModel(of: app, saveDelay: .seconds(3_600))
        // Another screen changes what this one does not show, while a cell waits to be saved.
        var other = try await storedYear(2026, in: app)
        other.activityFrom = 3
        other.healthExemptMonths = [4]
        other.incomeFXMethod = .uniform
        try await storeYear(other, in: app)

        model.setCell(month: 3, column: 0, text: "13 000")
        await model.saveNow()

        let saved = try await storedYear(2026, in: app)
        #expect(saved.advances.social[2] == 13_000)
        #expect(saved.activityFrom == 3)
        #expect(saved.healthExemptMonths == [4])
        #expect(saved.incomeFXMethod == .uniform)
        var expected = other
        expected.advances.social[2] = 13_000
        #expect(saved == expected)
    }

    @Test func aSaveThatFailsSaysSoAndKeepsTheTextAndTheValue() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let app = try await makeAdvancesApp(in: directory)
        let database = try #require(app.database)
        let model = await loadedAdvancesModel(of: app)
        #expect(model.saveFailure == nil)
        await database.close()

        model.setCell(month: 3, column: 0, text: "13 000")
        await model.saveNow()

        #expect(model.saveFailure == "Změnu se nepodařilo uložit.")
        #expect(model.cells[2][0] == "13 000")
        #expect(model.cellError(month: 3, column: 0) == nil)
        #expect(model.settings?.advances.social[2] == 13_000)
    }

    @Test func aSaveThatWorksAfterAFailedOneTakesTheLineAwayAndTheFailedChangeWithIt() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let app = try await makeAdvancesApp(in: directory)
        let database = try #require(app.database)
        let model = await loadedAdvancesModel(of: app, saveDelay: .seconds(3_600))
        await database.close()
        model.setCell(month: 3, column: 0, text: "13 000")
        await model.saveNow()
        #expect(model.saveFailure != nil)

        // The data works again (here: another database, with the same year), and the next change takes the one that
        // failed with it.
        let (working, workingDirectory) = try makeDatabase()
        defer { removeTemporaryDirectory(workingDirectory) }
        try await working.saveYearSettings(SampleYear2026.yearSettings)
        app.database = working
        model.setCell(month: 4, column: 0, text: "14 000")
        await model.saveNow()

        #expect(model.saveFailure == nil)
        let saved = try await working.yearSettings(2026)
        #expect(saved.advances.social[2] == 13_000)
        #expect(saved.advances.social[3] == 14_000)
    }

    @Test func aChangeMadeWhileTheDataIsLockedIsSavedOnceItIsOpenAgain() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let app = try await makeAdvancesApp(in: directory)
        let database = try #require(app.database)
        let model = await loadedAdvancesModel(of: app, saveDelay: .seconds(3_600))
        app.database = nil

        model.setCell(month: 3, column: 0, text: "13 000")
        await model.saveNow()

        // Nothing could be written, and what was typed stays on the screen.
        #expect(model.saveFailure == "Změnu se nepodařilo uložit.")
        #expect(model.cells[2][0] == "13 000")
        #expect(model.settings?.advances.social[2] == 13_000)

        app.database = database
        await model.saveNow()

        #expect(model.saveFailure == nil)
        #expect(try await storedYear(2026, in: app).advances.social[2] == 13_000)
    }

    // MARK: Typing

    @Test func aTextIsReadWhenTheTypingStopsNotKeyByKey() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let app = try await makeAdvancesApp(in: directory)
        let model = await loadedAdvancesModel(of: app, saveDelay: .seconds(3_600))
        let versionBefore = app.dataVersion

        // April's social insurance is 13 340 Kč; 12 150 Kč is typed key by key.
        for text in ["1", "11", "11 ", "11 8", "11 88", "12 150"] {
            model.setCell(month: 4, column: 0, text: text)

            // Neither a message nor a value comes of a text that is still being typed.
            #expect(model.cellError(month: 4, column: 0) == nil, "\(text)")
            #expect(model.settings?.advances.social[3] == 13_340, "\(text)")
            #expect(app.dataVersion == versionBefore, "\(text)")
            #expect(model.cells[3][0] == text)
        }
        #expect(try await storedYear(2026, in: app).advances.social[3] == 13_340)

        // When the typing stops the text is read: one save, of what was typed to the end.
        await model.saveNow()

        #expect(model.cellError(month: 4, column: 0) == nil)
        #expect(model.settings?.advances.social[3] == 12_150)
        #expect(try await storedYear(2026, in: app).advances.social[3] == 12_150)
        #expect(app.dataVersion == versionBefore + 1)
        #expect(model.totals.yearSocial == 150_560 - 13_340 + 12_150)
    }

    @Test func everyKeyStartsTheWaitAgainAndOnlyTheEndOfTheLastOneReadsTheText() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let app = try await makeAdvancesApp(in: directory)
        let delay = ManualDelay()
        let model = AdvancesModel(app: app, saveDelay: .milliseconds(500), wait: delay.wait)
        await model.load()
        let versionBefore = app.dataVersion

        // Each key ends the wait of the key before it and starts its own, whether the text is one that is read or not
        // and whether it differs from the text before it or not.
        var keys = 0
        for text in ["1", "11", "11 ", "11 8", "11 88", "12 150", "12 150"] {
            model.setCell(month: 4, column: 0, text: text)
            keys += 1
            try await waitUntil { delay.started == keys && delay.cancelled == keys - 1 && delay.armed == 1 }
        }
        #expect(app.dataVersion == versionBefore)
        #expect(model.cellError(month: 4, column: 0) == nil)

        // When the last wait is over the text is read and saved, once.
        #expect(delay.fire())

        try await waitUntil { try await storedYear(2026, in: app).advances.social[3] == 12_150 }
        try await waitUntil { app.dataVersion > versionBefore }
        #expect(app.dataVersion == versionBefore + 1)
        #expect(model.cellError(month: 4, column: 0) == nil)
        await model.saveNow()
    }

    @Test(.hangGuard)
    func aTimerThatWakesAfterTheNextKeyReplacedItReadsNothing() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let app = try await makeAdvancesApp(in: directory)
        let delay = StubbornDelay()
        let model = AdvancesModel(app: app, saveDelay: .milliseconds(500), wait: delay.wait)
        await model.load()

        // The first key starts a wait; the second one replaces it, but the first wait ends all the same.
        model.setCell(month: 4, column: 0, text: "11 8")
        try await waitUntil { delay.armed == 1 }
        model.setCell(month: 4, column: 0, text: "12 150")
        try await waitUntil { delay.armed == 2 }
        #expect(delay.fireOldest())
        await letWaitingJobsRun()

        // The timer that was replaced reads nothing: the text is still there to be read when the typing stops.
        #expect(model.settings?.advances.social[3] == 13_340)
        #expect(model.hasUnsavedInput)

        // The timer of the last key is the one that reads it and saves it.
        #expect(delay.fireOldest())
        try await waitUntil { try await storedYear(2026, in: app).advances.social[3] == 12_150 }
        await model.saveNow()
    }

    @Test func aTextThatIsStillBeingTypedInADeductionFieldStartsTheWaitAgainToo() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let app = try await makeAdvancesApp(in: directory)
        let delay = ManualDelay()
        let model = AdvancesModel(app: app, saveDelay: .milliseconds(500), wait: delay.wait)
        await model.load()

        var keys = 0
        for text in ["2", "20", "20 ", "20 0"] {
            model.setDeductionText(.gifts, text)
            keys += 1
            try await waitUntil { delay.started == keys && delay.cancelled == keys - 1 && delay.armed == 1 }
        }

        #expect(delay.fire())
        // "20 0" is no amount: it is not saved, and says so.
        try await waitUntil { model.deductionError(.gifts) != nil }
        #expect(model.deductionError(.gifts) == advancesWholeKcMessage)
        #expect(try await storedYear(2026, in: app).deductions.gifts == 0)
        await model.saveNow()
    }

    @Test func aChoiceOfAMenuOrABoxIsNotWaitedFor() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let app = try await makeAdvancesApp(in: directory)
        let delay = ManualDelay()
        let model = AdvancesModel(app: app, saveDelay: .milliseconds(500), wait: delay.wait)
        await model.load()

        model.setExpensePercent(40)
        model.setSecondary(month: 6, true)

        // Nothing waits, and the choices are saved without the end of any delay.
        try await waitUntil { try await storedYear(2026, in: app).expensePercent == 40 }
        try await waitUntil { try await storedYear(2026, in: app).secondaryMonths == [6] }
        #expect(delay.started == 0)
        await model.saveNow()
    }

    @Test func aTextThatEndsRefusedSavesNothingNotEvenItsValidBeginning() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let app = try await makeAdvancesApp(in: directory)
        let model = await loadedAdvancesModel(of: app, saveDelay: .seconds(3_600))
        let versionBefore = app.dataVersion

        // April's health insurance is 6 920 Kč; "6 921" is a whole amount, "6 921,50" is not.
        for text in ["6", "6 ", "6 9", "6 92", "6 921", "6 921,", "6 921,5", "6 921,50"] {
            model.setCell(month: 4, column: 1, text: text)
        }
        await model.saveNow()

        #expect(model.cellError(month: 4, column: 1) == advancesWholeKcMessage)
        #expect(model.cells[3][1] == "6 921,50")
        #expect(model.settings?.advances.health[3] == 6_920)
        #expect(try await storedYear(2026, in: app).advances.health[3] == 6_920)
        #expect(app.dataVersion == versionBefore)
        #expect(model.totals.yearHealth == 71_520)
    }

    @Test func aRefusedTextWithdrawsTheChangeThatWaitsForItsCell() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let app = try await makeAdvancesApp(in: directory)
        let database = try #require(app.database)
        let model = await loadedAdvancesModel(of: app, saveDelay: .seconds(3_600))
        try await setDatabaseReadOnly(true, database)

        // A value that could not be saved waits for the next save, and is still the person's value.
        model.setCell(month: 4, column: 1, text: "7 000")
        await model.saveNow()
        #expect(model.saveFailure == "Změnu se nepodařilo uložit.")
        #expect(model.settings?.advances.health[3] == 7_000)

        // The text of the cell is changed to one that is not an amount: that cell is not saved, and what waited for it
        // goes, so the plan is as the data holds it.
        model.setCell(month: 4, column: 1, text: "7 000,5")
        await model.saveNow()

        #expect(model.cellError(month: 4, column: 1) == advancesWholeKcMessage)
        #expect(model.cells[3][1] == "7 000,5")
        #expect(model.settings?.advances.health[3] == 6_920)
        #expect(model.totals.yearHealth == 71_520)

        try await setDatabaseReadOnly(false, database)
        await model.saveNow()

        #expect(try await storedYear(2026, in: app).advances.health[3] == 6_920)
    }

    // MARK: A save that fails and the year changes

    @Test func aYearChangedAfterASaveThatFailedSaysTheChangesWereNotSaved() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let app = try await makeAdvancesApp(in: directory)
        let database = try #require(app.database)
        let model = await loadedAdvancesModel(of: app, saveDelay: .seconds(3_600))
        try await setDatabaseReadOnly(true, database)
        model.setCell(month: 3, column: 0, text: "13 000")

        app.selectYear(2025)
        await model.load()

        // The year shown is the new one, and the line says that what was typed in the old one is not saved.
        #expect(model.settings?.year == 2025)
        #expect(model.saveFailure == "Změny roku 2026 se nepodařilo uložit.")
        #expect(model.cells[2][0] == "")
        #expect(try await storedYear(2026, in: app).advances.social[2] == 13_340)

        // The next save that works takes the line away, and goes to the year shown.
        try await setDatabaseReadOnly(false, database)
        model.setCell(month: 1, column: 0, text: "5 000")
        await model.saveNow()

        #expect(model.saveFailure == nil)
        #expect(try await storedYear(2025, in: app).advances.social[0] == 5_000)
        #expect(try await storedYear(2026, in: app).advances.social[2] == 13_340)
    }

    // MARK: A year's change and a reload

    @Test func whatWaitsToBeSavedGoesToTheYearItWasTypedInWhenTheYearChanges() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let app = try await makeAdvancesApp(in: directory)
        let model = await loadedAdvancesModel(of: app, saveDelay: .seconds(3_600))
        model.setCell(month: 3, column: 0, text: "13 000")

        app.selectYear(2025)
        await model.load()

        #expect(try await storedYear(2026, in: app).advances.social[2] == 13_000)
        #expect(model.settings?.year == 2025)
        #expect(model.cells[2][0] == "")
        #expect(try await storedYear(2025, in: app).advances.social == [Int64](repeating: 0, count: 12))
        // Typing in the new year goes to the new year.
        model.setCell(month: 1, column: 0, text: "5 000")
        await model.saveNow()
        #expect(try await storedYear(2025, in: app).advances.social[0] == 5_000)
        #expect(try await storedYear(2026, in: app).advances.social[0] == 13_340)
    }

    @Test func aLoadKeepsWhatIsTypedAndWhatIsRefused() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let app = try await makeAdvancesApp(in: directory)
        let model = await loadedAdvancesModel(of: app, saveDelay: .seconds(3_600))

        model.setCell(month: 1, column: 0, text: "6480")
        model.setCell(month: 2, column: 0, text: "abc")
        model.setCell(month: 3, column: 1, text: "9 999")
        // The screen loads again whenever the data changes, also while the typing has not stopped yet.
        app.reloadScreens()
        await model.load()

        #expect(model.cells[0][0] == "6480")
        #expect(model.cells[1][0] == "abc")
        #expect(model.cells[2][1] == "9 999")
        // Nothing typed has been read yet, and the cells nobody touched show the stored values.
        #expect(model.settings == SampleYear2026.yearSettings)
        #expect(model.cells[3][0] == "13\u{00A0}340")

        // Once the typing has stopped the texts are read. What was typed is not written over with its own
        // formatting, because the person may still type, and a text that is refused stays with its message.
        await model.saveNow()
        await model.load()

        #expect(model.cells[0][0] == "6480")
        #expect(model.cells[1][0] == "abc")
        #expect(model.cells[2][1] == "9 999")
        #expect(model.cellError(month: 2, column: 0) == advancesWholeKcMessage)
        #expect(model.cellError(month: 1, column: 0) == nil)
        #expect(model.settings?.advances.social[0] == 6_480)
        #expect(model.settings?.advances.health[2] == 9_999)
        let saved = try await storedYear(2026, in: app)
        #expect(saved.advances.social[0] == 6_480)
        #expect(saved.advances.health[2] == 9_999)
        #expect(saved.advances.social[1] == 13_340)
    }

    @Test func aCellNobodyTouchedFollowsTheStoredValue() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let app = try await makeAdvancesApp(in: directory)
        let model = await loadedAdvancesModel(of: app)
        var other = try await storedYear(2026, in: app)
        other.advances.social[7] = 9_000
        try await storeYear(other, in: app)

        await model.load()

        #expect(model.cells[7][0] == "9\u{00A0}000")
        #expect(model.totals.yearSocial == 150_560 - 12_150 + 9_000)
    }

    // MARK: Secondary activity

    @Test func theSecondaryActivityOfAMonthIsSavedAndTakenBack() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let app = try await makeAdvancesApp(in: directory)
        let model = await loadedAdvancesModel(of: app)

        model.setSecondary(month: 7, true)
        model.setSecondary(month: 8, true)
        await model.saveNow()
        #expect(model.settings?.secondaryMonths == [7, 8])
        #expect(try await storedYear(2026, in: app).secondaryMonths == [7, 8])

        model.setSecondary(month: 7, false)
        await model.saveNow()
        #expect(try await storedYear(2026, in: app).secondaryMonths == [8])
    }

    // MARK: Prefill

    @Test func prefillSetsTheMonthsFromTheChosenOneAndLeavesTheEarlierOnes() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let app = try await makeAdvancesApp(in: directory)
        // The plan before the advances changed: 13 340 Kč and 6 920 Kč all year.
        var before = SampleYear2026.yearSettings
        before.advances.social = [Int64](repeating: 13_340, count: 12)
        before.advances.health = [Int64](repeating: 6_920, count: 12)
        try await storeYear(before, in: app)
        let model = await loadedAdvancesModel(of: app)

        let errors = model.prefill(social: "12 150", health: "5 480", fromMonth: 5)
        await model.saveNow()

        #expect(errors.isEmpty)
        // May to December changed, January to April did not, and the income tax is not touched.
        #expect(model.settings?.advances == SampleYear2026.yearSettings.advances)
        #expect(model.cells[3] == ["13\u{00A0}340", "6\u{00A0}920", ""])
        #expect(model.cells[4] == ["12\u{00A0}150", "5\u{00A0}480", ""])
        #expect(model.cells[11] == ["12\u{00A0}150", "5\u{00A0}480", "23\u{00A0}000"])
        #expect(try await storedYear(2026, in: app).advances == SampleYear2026.yearSettings.advances)
        #expect(model.totals.yearSocial == 150_560)
    }

    @Test func prefillFromJanuaryFillsTheWholeYear() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let app = try await makeAdvancesApp(in: directory)
        let model = await loadedAdvancesModel(of: app)

        model.prefill(social: "10 000", health: "5 000", fromMonth: 1)
        await model.saveNow()

        let saved = try await storedYear(2026, in: app)
        #expect(saved.advances.social == [Int64](repeating: 10_000, count: 12))
        #expect(saved.advances.health == [Int64](repeating: 5_000, count: 12))
        #expect(saved.advances.tax == SampleYear2026.yearSettings.advances.tax)
    }

    @Test func prefillLeavesAColumnAloneWhenItsBoxIsEmpty() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let app = try await makeAdvancesApp(in: directory)
        let model = await loadedAdvancesModel(of: app)

        let errors = model.prefill(social: "  ", health: "5 000", fromMonth: 11)
        await model.saveNow()

        #expect(errors.isEmpty)
        // November and December have the new amount, the months before them have what they had.
        let saved = try await storedYear(2026, in: app)
        #expect(saved.advances.social == SampleYear2026.yearSettings.advances.social)
        #expect(Array(saved.advances.health[10...]) == [5_000, 5_000])
        #expect(Array(saved.advances.health[..<10]) == Array(SampleYear2026.yearSettings.advances.health[..<10]))
    }

    @Test func prefillWithAnAmountThatIsNotWholeCrownsWritesNothingAndSaysWhere() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let app = try await makeAdvancesApp(in: directory)
        let model = await loadedAdvancesModel(of: app)
        let versionBefore = app.dataVersion

        let errors = model.prefill(social: "12 150,50", health: "5 480", fromMonth: 5)
        await model.saveNow()

        #expect(errors.social == advancesWholeKcMessage)
        #expect(errors.health == nil)
        #expect(!errors.isEmpty)
        #expect(model.settings == SampleYear2026.yearSettings)
        #expect(app.dataVersion == versionBefore)

        let both = model.prefill(social: "x", health: "-1", fromMonth: 5)
        #expect(both.social == advancesWholeKcMessage)
        #expect(both.health == advancesWholeKcMessage)
        #expect(model.settings == SampleYear2026.yearSettings)
    }

    @Test(arguments: [(0, 1), (-3, 1), (13, 12), (99, 12)])
    func prefillTakesAMonthOutsideTheYearAsTheNearestOne(month: Int, from: Int) async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let app = try await makeAdvancesApp(in: directory)
        let model = await loadedAdvancesModel(of: app)

        model.prefill(social: "1 000", health: "", fromMonth: month)
        await model.saveNow()

        let social = try await storedYear(2026, in: app).advances.social
        #expect(Array(social[(from - 1)...]) == [Int64](repeating: 1_000, count: 13 - from))
        #expect(Array(social[..<(from - 1)]) == Array(SampleYear2026.yearSettings.advances.social[..<(from - 1)]))
    }

    @Test func prefillClearsTheMessagesOfTheCellsItWrites() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let app = try await makeAdvancesApp(in: directory)
        let model = await loadedAdvancesModel(of: app)
        model.setCell(month: 6, column: 0, text: "1,5")
        model.setCell(month: 2, column: 0, text: "2,5")
        await model.saveNow()
        #expect(model.cellError(month: 6, column: 0) != nil)

        model.prefill(social: "1 000", health: "", fromMonth: 5)

        #expect(model.cellError(month: 6, column: 0) == nil)
        #expect(model.cells[5][0] == "1\u{00A0}000")
        // A cell before the month is not touched, so its message stays.
        #expect(model.cellError(month: 2, column: 0) != nil)
        #expect(model.cells[1][0] == "2,5")
        await model.saveNow()
    }

    // MARK: Copy from the year before

    @Test func theCopyOfThePreviousYearIsOfferedOnlyWhenThatYearIsStored() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let app = try await makeAdvancesApp(in: directory)

        let without = await loadedAdvancesModel(of: app)
        #expect(!without.hasPreviousYear)

        try await storeYear(advancesYear2025(), in: app)
        let with = await loadedAdvancesModel(of: app)
        #expect(with.hasPreviousYear)

        app.selectYear(2025)
        await with.load()
        #expect(!with.hasPreviousYear)
    }

    @Test func copyingThePreviousYearTakesItsPlanAndItsSecondaryMonthsAndNothingElse() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let app = try await makeAdvancesApp(in: directory)
        try await storeYear(advancesYear2025(), in: app)
        let model = await loadedAdvancesModel(of: app)
        let own = SampleYear2026.yearSettings

        await model.copyFromPreviousYear()

        let previous = advancesYear2025()
        #expect(model.settings?.advances == previous.advances)
        #expect(model.settings?.secondaryMonths == [2, 3, 4])
        #expect(model.cells[0] == ["9\u{00A0}450", "4\u{00A0}700", ""])
        #expect(model.cells[5] == ["9\u{00A0}450", "4\u{00A0}700", "19\u{00A0}000"])
        #expect(model.totals.yearSocial == 113_400)
        // It is saved before the call returns.
        let saved = try await storedYear(2026, in: app)
        #expect(saved.advances == previous.advances)
        #expect(saved.secondaryMonths == [2, 3, 4])
        // What the year before chose for itself is not copied.
        #expect(saved.expensePercent == own.expensePercent)
        #expect(saved.deductions == own.deductions)
        #expect(saved.taxpayerCredit == own.taxpayerCredit)
        #expect(try await storedYear(2025, in: app) == previous)
    }

    @Test func copyingReplacesMessagesAndTextsOfCellsThatWereRefused() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let app = try await makeAdvancesApp(in: directory)
        try await storeYear(advancesYear2025(), in: app)
        let model = await loadedAdvancesModel(of: app)
        model.setCell(month: 1, column: 0, text: "oops")
        await model.saveNow()
        #expect(model.cellError(month: 1, column: 0) != nil)

        await model.copyFromPreviousYear()

        #expect(model.cellError(month: 1, column: 0) == nil)
        #expect(model.cells[0][0] == "9\u{00A0}450")
    }

    @Test func aCopyThatCannotReadTheYearBeforeSaysSoAndChangesNothing() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let app = try await makeAdvancesApp(in: directory)
        try await storeYear(advancesYear2025(), in: app)
        let database = try #require(app.database)
        let model = await loadedAdvancesModel(of: app)
        #expect(model.hasPreviousYear)
        await database.close()

        await model.copyFromPreviousYear()

        #expect(model.saveFailure == "Zálohy z minulého roku se nepodařilo zkopírovat.")
        #expect(model.settings == SampleYear2026.yearSettings)
        #expect(model.cells[0] == ["13\u{00A0}340", "6\u{00A0}920", ""])
    }

    @Test func copyingWithoutAPreviousYearDoesNothing() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let app = try await makeAdvancesApp(in: directory)
        let model = await loadedAdvancesModel(of: app)
        let versionBefore = app.dataVersion

        await model.copyFromPreviousYear()

        #expect(model.settings == SampleYear2026.yearSettings)
        #expect(app.dataVersion == versionBefore)
    }

    // MARK: Loading

    @Test func theDataThatIsLockedIsNotLoaded() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let app = makeAppModel(in: directory)
        let model = AdvancesModel(app: app, saveDelay: .zero)

        await model.load()

        #expect(model.settings == nil)
        #expect(model.errorText == "Zálohy a odpočty se nepodařilo načíst.")
        model.setCell(month: 1, column: 0, text: "1")
        await model.saveNow()
        #expect(model.saveFailure == nil)
    }

    @Test func aLoadThatFailsLeavesThePlanThatWasShownWhereItWas() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let app = try await makeAdvancesApp(in: directory)
        let database = try #require(app.database)
        let model = await loadedAdvancesModel(of: app)
        app.database = nil

        await model.load()

        #expect(model.errorText == "Zálohy a odpočty se nepodařilo načíst.")
        #expect(model.settings == SampleYear2026.yearSettings)
        #expect(model.cells[0] == ["13\u{00A0}340", "6\u{00A0}920", ""])
        #expect(model.totals.yearSocial == 150_560)
        app.database = database
    }

    @Test func aLoadThatWorksAgainTakesTheLineAway() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let app = try await makeAdvancesApp(in: directory)
        let database = try #require(app.database)
        let model = AdvancesModel(app: app, saveDelay: .zero)
        app.database = nil
        await model.load()
        #expect(model.errorText != nil)

        app.database = database
        await model.load()

        #expect(model.errorText == nil)
        #expect(model.settings != nil)
    }

    // MARK: The family

    /// A child of the whole year, claimed by me.
    private static func childYear(order: Int) -> ChildYear {
        ChildYear(household: MonthRange.wholeYear, claimant: .me, order: order, ztpp: nil, studies: nil)
    }

    /// The spouse of the sample family: claimed for the whole year, without own income.
    private static let spouse = SpouseYear(claim: true, months: MonthRange.wholeYear, ownIncomeKc: 0, ztpp: nil)

    @Test func addingAChildChangesTheTaxAndIsStored() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let app = try await makeAdvancesApp(in: directory)
        let database = try #require(app.database)
        let model = await loadedAdvancesModel(of: app)
        #expect(model.impactTotals?.taxWithKc == 94_440)
        #expect(model.family?.children == [])
        #expect(model.familyCards?.children.rows == [])

        let versionBefore = app.dataVersion
        try await model.saveChild(
            Child(id: nil, name: "Anna", birthDate: civilDate("2019-09-03")), childYear: Self.childYear(order: 1),
            otherOrders: [:])
        // The screens load again after the write.
        #expect(app.dataVersion > versionBefore)
        await model.load()

        // Anna's 15 204 Kč come off the 94 440 Kč of tax.
        #expect(model.impactTotals?.taxWithKc == 79_236)
        let stored = try await database.family(year: 2026).children
        #expect(stored.map(\.child.name) == ["Anna"])
        #expect(stored.map(\.year) == [Self.childYear(order: 1)])
        #expect(stored.map(\.isStored) == [true])
        #expect(model.family?.children == stored)
        #expect(model.familyCards?.children.rows.map(\.amount) == ["15\u{00A0}204\u{00A0}Kč"])
        #expect(model.familyCards?.children.total == "15\u{00A0}204\u{00A0}Kč za rok")
    }

    /// What the children's benefit leaves is not paid as a bonus while the income is below six minimum wages. In the
    /// year in progress, here as of 31. 1. 2026 before any money came, it is not paid yet, as the income may still
    /// grow; in 2025, which is over and shown as of its last day, it is not paid. Anna, entered for 2025, is the
    /// family of 2026 too.
    @Test func theBonusTheIncomeDoesNotBringIsNotPaidYetOnlyInTheYearInProgress() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let app = try await makeAdvancesApp(in: directory)
        let database = try #require(app.database)
        try await database.saveChild(
            Child(id: nil, name: "Anna", birthDate: civilDate("2019-09-03")), year: 2025,
            childYear: Self.childYear(order: 1))
        await app.didWriteAndBackUp()
        app.pickAsOf(civilDate("2026-01-31"))
        let model = await loadedAdvancesModel(of: app)

        #expect(
            model.familyCards?.children.bonusHint
                == "Zvýhodnění převyšuje daň o 15\u{00A0}204\u{00A0}Kč, bonus se ale zatím nevyplatí: příjmy roku"
                + " nedosáhly 6× minimální mzdy (134\u{00A0}400\u{00A0}Kč).")

        app.selectYear(2025)
        await model.load()

        #expect(model.toDateLabel == "Zaplaceno za rok")
        #expect(
            model.familyCards?.children.bonusHint
                == "Zvýhodnění převyšuje daň o 15\u{00A0}204\u{00A0}Kč, bonus se ale nevyplatí: příjmy roku"
                + " nedosáhly 6× minimální mzdy (124\u{00A0}800\u{00A0}Kč).")
    }

    /// The spouse is saved at once, and counts from 2024 with a child under three in the household: Tomáš, the first
    /// and only child, takes 15 204 Kč and the spouse 24 840 Kč off the 94 440 Kč of tax.
    @Test func theSpouseIsSavedAtOnceAndCountsWithAChildUnderThree() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let app = try await makeAdvancesApp(in: directory)
        let model = await loadedAdvancesModel(of: app, saveDelay: .seconds(3_600))
        try await model.saveChild(
            Child(id: nil, name: "Tomáš", birthDate: civilDate("2024-04-12")), childYear: Self.childYear(order: 1),
            otherOrders: [:])
        await model.load()
        #expect(model.family?.spouse == nil)

        try await model.setSpouse(Self.spouse)

        #expect(try await storedYear(2026, in: app).spouse == Self.spouse)
        #expect(model.family?.spouse == Self.spouse)
        #expect(model.spouseIncomeText == "0")
        await model.load()
        #expect(model.impactTotals?.taxWithKc == 54_396)
        #expect(model.familyCards?.spouse.result == "Sleva za 12\u{00A0}měsíců: 24\u{00A0}840\u{00A0}Kč")

        // Not claimed, the spouse keeps what was entered.
        var unclaimed = Self.spouse
        unclaimed.claim = false
        try await model.setSpouse(unclaimed)
        #expect(try await storedYear(2026, in: app).spouse == unclaimed)
        await model.load()
        #expect(model.impactTotals?.taxWithKc == 79_236)
    }

    /// The spouse's own income is a typed field like those of the deductions: read when the typing stops, saved in
    /// whole Kč, and refused with the message under it otherwise. Nothing in it is no income.
    @Test func theSpousesOwnIncomeIsSavedWhenTheTypingStopsAndARefusedOneIsNot() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let app = try await makeAdvancesApp(in: directory)
        let model = await loadedAdvancesModel(of: app, saveDelay: .seconds(3_600))
        try await model.setSpouse(Self.spouse)

        model.setSpouseIncomeText("70 000")
        // Typing alone saves nothing before the wait is over.
        #expect(try await storedYear(2026, in: app).spouse?.ownIncomeKc == 0)
        await model.saveNow()
        #expect(try await storedYear(2026, in: app).spouse?.ownIncomeKc == 70_000)
        #expect(model.spouseIncomeError == nil)

        model.setSpouseIncomeText("70 000,50")
        await model.saveNow()
        #expect(model.spouseIncomeError == "Zadejte částku v celých korunách, například 13 340.")
        #expect(model.spouseIncomeText == "70 000,50")
        #expect(try await storedYear(2026, in: app).spouse?.ownIncomeKc == 70_000)

        model.setSpouseIncomeText(" ")
        await model.saveNow()
        #expect(model.spouseIncomeError == nil)
        #expect(try await storedYear(2026, in: app).spouse?.ownIncomeKc == 0)
    }

    /// What is typed in the income and not read yet is saved with a change of the spouse made meanwhile, and neither
    /// takes the other's place.
    @Test func aChangeOfTheSpouseKeepsTheIncomeThatIsBeingTyped() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let app = try await makeAdvancesApp(in: directory)
        let model = await loadedAdvancesModel(of: app, saveDelay: .seconds(3_600))
        try await model.setSpouse(Self.spouse)

        model.setSpouseIncomeText("50 000")
        var withZTPP = try #require(model.family?.spouse)
        withZTPP.ztpp = MonthRange(from: 3, to: 5)
        try await model.setSpouse(withZTPP)

        #expect(
            try await storedYear(2026, in: app).spouse
                == SpouseYear(
                    claim: true, months: MonthRange.wholeYear, ownIncomeKc: 50_000, ztpp: MonthRange(from: 3, to: 5)))
        #expect(model.spouseIncomeText == "50 000")
    }

    /// A year with a stored spouse shows the income in its field, its thousands separated.
    @Test func aStoredSpouseShowsItsIncome() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let app = try await makeAdvancesApp(in: directory)
        let database = try #require(app.database)
        var spouse = Self.spouse
        spouse.ownIncomeKc = 65_000
        try await database.saveSpouse(spouse, year: 2026)
        await app.didWriteAndBackUp()

        let model = await loadedAdvancesModel(of: app)

        #expect(model.spouseIncomeText == "65\u{00A0}000")
        #expect(model.family?.spouse == spouse)
        #expect(model.familyCards?.spouse.incomeStatus == "do limitu 68\u{00A0}000\u{00A0}Kč")
    }

    /// A change of the family that cannot be written throws and changes nothing: a child with the orders of the others,
    /// a removal, and the spouse, which then waits as a change that is not saved, as the other choices of the screen
    /// do, and the screen says so. Once the data takes writes again, the changes are made.
    @Test func aChangeOfTheFamilyThatCannotBeWrittenThrowsAndChangesNothing() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let app = try await makeAdvancesApp(in: directory)
        let database = try #require(app.database)
        let model = await loadedAdvancesModel(of: app)
        try await model.saveChild(
            Child(id: nil, name: "Anna", birthDate: civilDate("2019-09-03")), childYear: Self.childYear(order: 1),
            otherOrders: [:])
        await model.load()
        let anna = try #require(model.family?.children.first?.child.id)
        let tomas = Child(id: nil, name: "Tomáš", birthDate: civilDate("2024-04-12"))
        let before = try await database.family(year: 2026)
        try await setDatabaseReadOnly(true, database)

        await #expect(throws: (any Error).self) {
            try await model.saveChild(tomas, childYear: Self.childYear(order: 1), otherOrders: [anna: 2])
        }
        await #expect(throws: (any Error).self) { try await model.removeChild(id: anna, otherOrders: [:]) }
        await #expect(throws: (any Error).self) { try await model.setSpouse(Self.spouse) }

        #expect(model.saveFailure == AdvancesModel.saveFailureText)
        try await setDatabaseReadOnly(false, database)
        #expect(try await database.family(year: 2026) == before)
        try await model.saveChild(tomas, childYear: Self.childYear(order: 1), otherOrders: [anna: 2])
        try await model.setSpouse(Self.spouse)
        #expect(try await database.family(year: 2026).children.map(\.year.order) == [2, 1])
        #expect(try await storedYear(2026, in: app).spouse == Self.spouse)
    }

    /// A year the computation refuses has no cards of the family, as it has no figures for them.
    @Test func aYearTheComputationRefusesHasNoFamilyCards() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let app = try await makeAdvancesApp(in: directory)
        try await Self.storeExpensePercent55(in: try #require(app.database))

        let model = await loadedAdvancesModel(of: app)

        #expect(model.impactError != nil)
        #expect(model.familyCards == nil)
        #expect(model.family?.children == [])
    }

    /// Something other than the app, which the tables have a check against, makes the expenses of 2026 55 %.
    private nonisolated static func storeExpensePercent55(in database: Database) async throws {
        try await database.write { connection in
            try connection.run("PRAGMA ignore_check_constraints = ON")
            try connection.run("UPDATE year_settings SET expense_percent = 55 WHERE year = 2026")
            try connection.run("PRAGMA ignore_check_constraints = OFF")
        }
    }
}
