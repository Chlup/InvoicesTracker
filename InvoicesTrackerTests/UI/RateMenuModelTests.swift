import Foundation
import Testing
@testable import InvoicesTracker

/// The menu of the rate capsule as the window shows it (`RateMenuModel`): it opens with what the window knows of the
/// year shown, reads how the year converts its income in other currencies and the levies of the year with each
/// conversion, and a choice converts the year and lets the menu close, or keeps it open and says what went wrong. The
/// data is invented, the clock is at noon of 17. 10. 2026, and 2025 has the uniform rates that ship with the app
/// (1 USD = 21,84 Kč, 1 EUR = 24,66 Kč).
@Suite(.settlesBackups)
@MainActor
struct RateMenuModelTests {
    /// An app model that has gone through the first launch, with the income of 2025 of `storeForeignIncomeOf2025`,
    /// showing 2025.
    private func makeAppShowing2025(in directory: URL) async throws -> (app: AppModel, income: [Invoice]) {
        let app = makeAppModel(in: directory)
        try await startFresh(app)
        let income = try await storeForeignIncomeOf2025(in: app)
        app.selectYear(2025)
        return (app, income)
    }

    /// Writes an expense rate into the settings of 2025 that the tables refuse, as the data changed outside the app
    /// would have it.
    private nonisolated func storeExpensePercentOf2025(_ percent: Int, in database: Database) async throws {
        try await database.write { connection in
            try connection.run("PRAGMA ignore_check_constraints = ON")
            try connection.run(
                "UPDATE year_settings SET expense_percent = ? WHERE year = 2025", [.integer(Int64(percent))])
            try connection.run("PRAGMA ignore_check_constraints = OFF")
        }
    }

    // MARK: Opening

    /// The menu opens with what the window has read of the year, and its own reading adds the levies of each
    /// conversion: those Výpočet shows for the daily rates the year converts with, and more with the uniform rate.
    @Test func theMenuOfAYearThatCanUseBothConversionsShowsTheLeviesOfEach() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let (app, _) = try await makeAppShowing2025(in: directory)
        await app.loadShownYearFX()

        let menu = RateMenuModel(app: app)
        #expect(menu.content?.heading == "Cizí měny v roce 2025")
        #expect(menu.content?.items.map(\.comparison) == [nil, nil])

        await menu.load()

        let items = try #require(menu.content?.items)
        let daily = try await app.computeSelectedYear().liabilityTotal
        #expect(items[0].comparison?.hasPrefix("daň a pojistné \(CzechFormat.wholeKc(daily)) · o ") == true)
        #expect(items[0].comparison?.hasSuffix(" méně") == true)
        #expect(items[1].comparison?.hasSuffix(" více") == true)
        #expect(items.map(\.isChecked) == [true, false])
        #expect(items.map(\.isEnabled) == [true, true])
        #expect(menu.errorText == nil)
    }

    /// Levies that the computation cannot work out, for a stored value it does not take, are left out: the choices
    /// are there all the same.
    @Test func leviesThatCannotBeComputedAreLeftOutOfTheMenu() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let (app, _) = try await makeAppShowing2025(in: directory)
        let database = try #require(app.database)
        try await database.saveYearSettings(YearSettings(year: 2025))
        try await storeExpensePercentOf2025(55, in: database)
        let menu = RateMenuModel(app: app)

        await menu.load()

        let items = try #require(menu.content?.items)
        #expect(items.map(\.comparison) == [nil, nil])
        #expect(items.map(\.isEnabled) == [true, true])
        #expect(menu.errorText == nil)
    }

    @Test func aMenuThatCannotReadTheYearSaysSo() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let (app, _) = try await makeAppShowing2025(in: directory)
        await app.loadShownYearFX()
        let menu = RateMenuModel(app: app)
        // Every read of the data fails from now on.
        let database = try #require(app.database)
        await database.close()

        await menu.load()

        #expect(menu.content == nil)
        #expect(menu.heading == "Cizí měny v roce 2025")
        #expect(menu.errorText == "Přepočet cizích měn se nepodařilo načíst.")
    }

    // MARK: Choosing

    /// The uniform rate chosen in the menu converts the year at it, and the capsule names it as soon as the menu may
    /// close: the menu reads the year shown again itself rather than waiting for the window to.
    @Test func choosingTheUniformRateConvertsTheYearAndLetsTheMenuClose() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let (app, income) = try await makeAppShowing2025(in: directory)
        let database = try #require(app.database)
        let menu = RateMenuModel(app: app)
        await menu.load()

        #expect(await menu.choose(.uniform))

        #expect(try await database.yearSettings(2025).incomeFXMethod == .uniform)
        // 10 000,00 USD at 21,84 Kč.
        let dollars = try #require(try await database.invoice(id: income[1].id)?.payment)
        #expect(dollars.conversion == .uniform && dollars.czkNetHalere == 21_840_000)
        #expect(menu.choiceFailure == nil)
        #expect(app.shownYearFXMethod == .uniform)
    }

    /// While a choice is stored and the payments of the year are converted, the menu says it is choosing, so that its
    /// choices wait for it, and once it is made it says so no more. A conversion that holds the turns keeps the choice
    /// waiting for its own, so the test looks at the menu while it is choosing, rather than racing a choice that may
    /// be made before it looks.
    @Test(.hangGuard)
    func theChoicesWaitWhileAChoiceIsMade() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let (app, _) = try await makeAppShowing2025(in: directory)
        let menu = RateMenuModel(app: app)
        await menu.load()
        #expect(!menu.isChoosing)
        let gate = Gate()
        let holding = Task { await app.convertPaymentsInTurn { _ in await gate.pass() } }
        await gate.untilARequestWaits()

        let choice = Task { await menu.choose(.uniform) }
        try await waitUntil { menu.isChoosing }
        await gate.open()

        #expect(await choice.value)
        _ = await holding.value
        #expect(!menu.isChoosing)
    }

    /// A year set to the uniform rate that lacks the rate of euros is computed at the daily rates, which are checked.
    /// Choosing them drops the choice of the uniform rate, which Nastavení cannot take back while the rate is missing.
    @Test func theDailyRatesCanBeChosenForAYearSetToTheUniformRateItLacks() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let (app, _) = try await makeAppShowing2025(in: directory)
        let database = try #require(app.database)
        try await database.execute("DELETE FROM uniform_rate WHERE year = 2025 AND currency = 'EUR'")
        try await database.updateYearSettings(2025) { $0.incomeFXMethod = .uniform }
        let menu = RateMenuModel(app: app)
        await menu.load()
        let items = try #require(menu.content?.items)
        #expect(items.map(\.isChecked) == [true, false])
        #expect(items.map(\.isEnabled) == [true, false])
        #expect(items[1].detail == "chybí jednotný kurz EUR – zadáte ho v Nastavení › Rok 2025")

        #expect(await menu.choose(.cnbDaily))

        #expect(try await database.yearSettings(2025).incomeFXMethod == .cnbDaily)
        #expect(app.shownYearFX?.chosen == .cnbDaily)
        await menu.load()
        #expect(
            menu.content?.footer
                == "Rok 2025 se počítá denními kurzy ČNB. Jednotný kurz půjde zvolit, až bude pro rok 2025 známý.")
    }

    @Test func aChoiceThatCannotBeSavedKeepsTheMenuOpenAndSaysSo() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let (app, _) = try await makeAppShowing2025(in: directory)
        let database = try #require(app.database)
        let menu = RateMenuModel(app: app)
        await menu.load()
        try await setDatabaseReadOnly(true, database)

        #expect(await menu.choose(.uniform) == false)

        #expect(menu.choiceFailure == "Změnu se nepodařilo uložit.")
        try await setDatabaseReadOnly(false, database)
        #expect(try await database.yearSettings(2025).incomeFXMethod == .cnbDaily)
    }

    @Test func aChoiceWhosePaymentsCannotBeConvertedIsSavedAndSaysSo() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let (app, _) = try await makeAppShowing2025(in: directory)
        let database = try #require(app.database)
        var damaged = paidDollarInvoiceOf2025()
        damaged.number = "20251003"
        let id = try await database.saveInvoice(damaged)
        try await database.makeUnreadable(paymentOf: id)
        let menu = RateMenuModel(app: app)
        await menu.load()

        #expect(await menu.choose(.uniform) == false)

        #expect(menu.choiceFailure == "Změna je uložená, platby roku 2025 se ale nepodařilo přepočítat.")
        #expect(try await database.yearSettings(2025).incomeFXMethod == .uniform)
    }
}
