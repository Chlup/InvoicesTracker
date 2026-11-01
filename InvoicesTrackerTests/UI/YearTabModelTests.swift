import Foundation
import Testing
@testable import InvoicesTracker

/// The tab Rok of Nastavení: the profile of the year (the conversion of foreign income, the minimum), the months of the
/// activity and those without the health minimum, the uniform rate entered by hand, the rules and the income
/// adjustments. Every choice is saved at once with the year's one-transaction update, and a change of the conversion
/// or of the uniform rate converts the year's payments again. The clock is at noon of 17. 10. 2026, and the data is
/// invented. In every expected string `\u{00A0}` is the no-break space and `\u{2212}` the minus sign.
@Suite(.settlesBackups)
@MainActor
struct YearTabModelTests {
    /// The tab of `app` for its selected year, loaded as the screen loads it.
    private func loadedModel(of app: AppModel) async -> YearTabModel {
        let model = YearTabModel(app: app)
        await model.load()
        return model
    }

    /// Stores the ČNB rates of dollars of 2026 and an invoice of 10 000,00 USD paid on 2. 10. 2026 at the rate of that
    /// day, 21,795 Kč, as a year that converts at the daily rates has it, and returns the invoice as stored.
    private func storeDollarsPaidIn2026(in app: AppModel) async throws -> Invoice {
        let database = try #require(app.database)
        try await database.insertCNBRates(try cnbYearlyRows([2026]).filter { $0.currency == .usd })
        var paid = Invoice.fixture(
            number: "20261001", currency: .usd, duzp: "2026-09-30", dueDate: "2026-10-14",
            items: [.fixture("1", at: 1_000_000)], vatMode: .outsideCountry)
        paid.payment = try await app.convert(paid, paidOn: civilDate("2026-10-02"), method: .cnbDaily, in: database)
        #expect(paid.payment?.czkNetHalere == 21_795_000)
        paid.id = try await database.saveInvoice(paid)
        return paid
    }

    /// The uniform rate of 1 unit of `currency` in `year` entered by hand, `rate` crowns, without an instruction.
    private func manualRate(_ currency: CurrencyCode, _ rate: String, year: Int) -> UniformRate {
        UniformRate(year: year, currency: currency, amount: 1, rate: decimal(rate), instruction: "", origin: .manual)
    }

    // MARK: Profil

    @Test func turning2025ToTheUniformRateConvertsAPaidDollarInvoiceAt2184() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let app = try await makeSettingsApp(in: directory)
        let database = try #require(app.database)
        let id = try await database.saveInvoice(paidDollarInvoiceOf2025())
        app.selectYear(2025)
        let model = await loadedModel(of: app)
        #expect(model.settings?.incomeFXMethod == .cnbDaily)

        await model.setFXMethod(.uniform)

        #expect(try await database.yearSettings(2025).incomeFXMethod == .uniform)
        let payment = try #require(try await database.invoice(id: id)?.payment)
        #expect(payment.conversion == .uniform)
        #expect(payment.rate == storedRate("USD", "21.84", declaredOn: "2025-12-31"))
        // 1 000 USD at 21,84 Kč.
        #expect(payment.czkNetHalere == 2_184_000)
        #expect(model.settings?.incomeFXMethod == .uniform)
        #expect(model.saveFailure == nil)
    }

    @Test func aConversionThatIsSavedButWhosePaymentsCannotBeConvertedAgainSaysSo() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let app = try await makeSettingsApp(in: directory)
        let database = try #require(app.database)
        let id = try await database.saveInvoice(paidDollarInvoiceOf2025())
        try await database.makeUnreadable(paymentOf: id)
        app.selectYear(2025)
        let model = await loadedModel(of: app)

        await model.setFXMethod(.uniform)

        #expect(try await database.yearSettings(2025).incomeFXMethod == .uniform)
        #expect(model.settings?.incomeFXMethod == .uniform)
        #expect(model.saveFailure == "Změna je uložená, platby roku 2025 se ale nepodařilo přepočítat.")
    }

    @Test func theProfilUniformOptionIsDisabledUntilTheRateIsKnown() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let app = try await makeSettingsApp(in: directory)
        let database = try #require(app.database)
        let model = await loadedModel(of: app)

        // 2026 does not have its uniform rate yet, and the menu says no more of it than the design does: that it is
        // not out. The longer reason of the menu of the rate capsule would make the closed menu as wide as that.
        #expect(model.canChooseUniform == false)
        #expect(model.uniformOptionLabel == "jednotný kurz za rok – zatím nevyšel")
        #expect(model.shownFXMethod == .cnbDaily)
        // It cannot be chosen.
        await model.setFXMethod(.uniform)
        #expect(try await database.yearSettings(2026).incomeFXMethod == .cnbDaily)
        #expect(model.settings?.incomeFXMethod == .cnbDaily)
        #expect(model.shownFXMethod == .cnbDaily)
        #expect(model.saveFailure == nil)

        // Once the rate is known, here entered by hand, it can.
        #expect(await model.saveManualUniformRates(usd: "21,50", eur: "24,50", instruction: ""))
        #expect(model.canChooseUniform)
        #expect(model.uniformOptionLabel == "jednotný kurz za rok")
        await model.setFXMethod(.uniform)
        #expect(try await database.yearSettings(2026).incomeFXMethod == .uniform)
        #expect(model.shownFXMethod == .uniform)
        #expect(model.saveFailure == nil)
    }

    /// A year set to the uniform rate that lacks the rate of a currency it was paid in is computed at the daily rates
    /// meanwhile, and the Profil shows the conversion it is computed with, with the uniform rate that cannot be chosen.
    @Test func theProfilShowsTheDailyRateOfAYearSetToTheUniformRateThatLacksIt() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let app = try await makeSettingsApp(in: directory)
        let database = try #require(app.database)
        try await database.saveInvoice(paidDollarInvoiceOf2025())
        app.selectYear(2025)
        let model = await loadedModel(of: app)
        await model.setFXMethod(.uniform)
        #expect(model.shownFXMethod == .uniform)

        // The table of 2025 loses its rate of dollars, the currency the year was paid in.
        try await database.execute("DELETE FROM uniform_rate WHERE year = 2025 AND currency = 'USD'")
        await model.load()

        #expect(model.settings?.incomeFXMethod == .uniform)
        #expect(model.shownFXMethod == .cnbDaily)
        #expect(model.canChooseUniform == false)
        #expect(
            model.uniformOptionLabel
                == "jednotný kurz za rok – chybí jednotný kurz USD – zadáte ho v Nastavení › Rok 2025")
    }

    /// Why the uniform rate cannot be chosen follows where the search of the app for it stands on the day of the app,
    /// in the words of the menu of the rate capsule: on 15. 2. 2026 the app looks for the rate of 2025 once a day, and
    /// on 17. 10. 2026 it no longer looks for the rate of 2024.
    @Test func theProfilSaysWhereTheSearchForTheUniformRateStands() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let looking = try await makeSettingsApp(
            in: directory.appending(path: "Looking", directoryHint: .isDirectory),
            clock: ManualClock(localNoon(2026, 2, 15)))
        try await #require(looking.database).execute("DELETE FROM uniform_rate WHERE year = 2025")
        looking.selectYear(2025)
        let searched = await loadedModel(of: looking)

        #expect(searched.canChooseUniform == false)
        #expect(searched.uniformOptionLabel == "jednotný kurz za rok – zatím nevyšel – aplikace ho jednou denně hledá")

        let over = try await makeSettingsApp(in: directory.appending(path: "Over", directoryHint: .isDirectory))
        try await #require(over.database).execute("DELETE FROM uniform_rate WHERE year = 2024")
        over.selectYear(2024)
        let notInApp = await loadedModel(of: over)

        #expect(notInApp.canChooseUniform == false)
        #expect(
            notInApp.uniformOptionLabel == "jednotný kurz za rok – v aplikaci není – zadáte ho v Nastavení › Rok 2024")
    }

    @Test func theProfilNamesTheFlatRateOfTheExpensesAndItsCap() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let app = try await makeSettingsApp(in: directory)
        let model = await loadedModel(of: app)

        #expect(model.expenseText == "paušál 60\u{00A0}% (strop 1\u{00A0}200\u{00A0}000\u{00A0}Kč)")
    }

    @Test func aChoiceThatCannotBeSavedIsTakenBackAndSaid() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let app = try await makeSettingsApp(in: directory)
        let database = try #require(app.database)
        let model = await loadedModel(of: app)
        try await setDatabaseReadOnly(true, database)

        await model.setActivity(from: 3, to: 7)

        #expect(model.settings?.activityFrom == 1)
        #expect(model.settings?.activityTo == 12)
        #expect(model.saveFailure == YearTabModel.saveFailureText)
        try await setDatabaseReadOnly(false, database)
        await model.setActivity(from: 3, to: 7)
        #expect(model.saveFailure == nil)
        #expect(try await database.yearSettings(2026).activityFrom == 3)
    }

    // MARK: Činnost

    @Test func theActivityIsSavedAndSaysHowManyMonthsItHas() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let app = try await makeSettingsApp(in: directory)
        let model = await loadedModel(of: app)
        #expect(model.activityText == "celý rok")

        await model.setActivity(from: 3, to: 7)

        let stored = try await #require(app.database).yearSettings(2026)
        #expect(stored.activityFrom == 3)
        #expect(stored.activityTo == 7)
        #expect(model.activityText == "5\u{00A0}měsíců činnosti · ostatní měsíce se do minim nepočítají")

        // A range the engine does not take is not saved.
        await model.setActivity(from: 8, to: 4)
        await model.setActivity(from: 0, to: 12)
        #expect(try await #require(app.database).yearSettings(2026).activityFrom == 3)
        #expect(YearTabModel.activityText(from: 6, to: 7) == "2\u{00A0}měsíce činnosti · ostatní měsíce se do minim nepočítají")
        #expect(YearTabModel.activityText(from: 12, to: 12) == "1\u{00A0}měsíc činnosti · ostatní měsíce se do minim nepočítají")
    }

    @Test func aStoredActivityThatRunsBackwardsHasNoActiveMonthAndStopsNothing() {
        var settings = YearSettings(year: 2026)
        settings.activityFrom = 3
        settings.activityTo = 7
        #expect((1...12).filter { YearTabModel.isActiveMonth($0, in: settings) } == [3, 4, 5, 6, 7])

        settings.activityFrom = 8
        settings.activityTo = 4

        #expect((1...12).filter { YearTabModel.isActiveMonth($0, in: settings) }.isEmpty)
        #expect(YearTabModel.activityText(from: 8, to: 4) == "0\u{00A0}měsíců činnosti · ostatní měsíce se do minim nepočítají")
    }

    @Test func aMonthWithoutTheHealthMinimumIsSavedAtOnce() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let app = try await makeSettingsApp(in: directory)
        let model = await loadedModel(of: app)

        await model.setHealthExempt(month: 9, true)
        await model.setHealthExempt(month: 10, true)
        await model.setHealthExempt(month: 9, false)

        #expect(try await #require(app.database).yearSettings(2026).healthExemptMonths == [10])
        #expect(model.settings?.healthExemptMonths == [10])
    }

    /// The months without the health minimum are chosen like every other choice of the design: the selected month is
    /// the accent with the text on an accent on it, not the dark fill of the prototype. The others are raised, as the
    /// prototype rings both of its tones that are not chosen: a capsule of the colour of a card with the text where the
    /// activity was carried on, and the inset background with the faintest text where it was not. A marked month is
    /// selected whether or not the activity was carried on in it.
    @Test func theMonthTogglesSelectWithTheAccent() {
        #expect(MonthToggleTone(isOn: true, isActive: true) == .selected)
        #expect(MonthToggleTone(isOn: true, isActive: false) == .selected)
        #expect(MonthToggleTone(isOn: false, isActive: true) == .available)
        #expect(MonthToggleTone(isOn: false, isActive: false) == .outsideActivity)

        #expect(MonthToggleTone.selected.background == Palette.accent)
        #expect(MonthToggleTone.selected.foreground == Palette.onAccent)
        #expect(MonthToggleTone.available.background == Palette.bgCard)
        #expect(MonthToggleTone.available.foreground == Palette.text)
        #expect(MonthToggleTone.outsideActivity.background == Palette.bgInset)
        #expect(MonthToggleTone.outsideActivity.foreground == Palette.text4)
        #expect(MonthToggleTone.available.isRaised)
        #expect(!MonthToggleTone.selected.isRaised)
        #expect(MonthToggleTone.outsideActivity.isRaised)
        // Only the selected month is the accent.
        #expect(MonthToggleTone.available.background != Palette.accent)
        #expect(MonthToggleTone.outsideActivity.background != Palette.accent)
    }

    @Test func markingTheSecondaryMonthsCopiesThemToTheMonthsWithoutTheHealthMinimum() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let app = try await makeSettingsApp(in: directory)
        let database = try #require(app.database)
        var settings = try await database.yearSettings(2026)
        settings.secondaryMonths = [2, 3, 4]
        settings.healthExemptMonths = [3, 11]
        try await database.saveYearSettings(settings)
        let model = await loadedModel(of: app)
        #expect(
            model.secondaryHint
                == "V Zálohách máte vedlejší činnost v měsících únor, duben. Byli jste v nich zároveň zaměstnaní nebo"
                + " studovali? Pak se za ně minimum zdravotního nepočítá.")

        await model.markSecondaryAsExempt()

        #expect(try await database.yearSettings(2026).healthExemptMonths == [2, 3, 4, 11])
        #expect(model.secondaryHint == nil)
    }

    // MARK: Jednotný kurz

    @Test func manualRatesOf2026AreStoredAsManualAndUsedAsTheUniformRate() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let app = try await makeSettingsApp(in: directory)
        app.showSettings(.year)
        let database = try #require(app.database)
        let model = await loadedModel(of: app)
        #expect(model.shownRates.isEmpty)
        #expect(
            model.missingRateText
                == "Zatím nevyšel. GFŘ ho zveřejní v lednu 2027; aplikace ho pak sama najde a požádá vás o potvrzení.")

        #expect(await model.saveManualUniformRates(usd: "21,50", eur: "", instruction: " GFŘ-D-80 "))

        let usd = try #require(try await database.uniformRate(.usd, year: 2026))
        #expect(usd.rate == decimal("21.50"))
        #expect(usd.amount == 1)
        #expect(usd.origin == .manual)
        #expect(usd.instruction == "GFŘ-D-80")
        #expect(try await database.uniformRate(.eur, year: 2026) == nil)
        #expect(model.shownRates.map(\.currency) == [.usd])
        #expect(model.rateSource == "pokyn GFŘ-D-80, zadáno ručně")
        // The year converts at the daily ČNB rates, so the banner says where to switch it.
        #expect(
            app.banner?.text
                == "Jednotný kurz 2026 je uložený. Rok 2026 na něj přepnete v liště nahoře nebo tady v Profilu.")
    }

    @Test func manualRatesOfAYearThatConvertsAtTheUniformRateConvertItsPaymentsAgain() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let app = try await makeSettingsApp(in: directory)
        let database = try #require(app.database)
        let id = try await database.saveInvoice(paidDollarInvoiceOf2025())
        app.selectYear(2025)
        let model = await loadedModel(of: app)
        await model.setFXMethod(.uniform)

        // A correction of the published rate, entered by hand.
        model.startEditingRates()
        #expect(model.usdText == "21,84")
        #expect(model.eurText == "24,66")
        #expect(await model.saveManualUniformRates(usd: "22,00", eur: "24,66", instruction: "GFŘ-D-75"))

        #expect(try await database.invoice(id: id)?.payment?.czkNetHalere == 2_200_000)
        #expect(try await database.uniformRate(.usd, year: 2025)?.origin == .manual)
        #expect(!model.editsRates)
    }

    @Test func ratesThatAreNotRatesAreRefusedWithAMessage() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let app = try await makeSettingsApp(in: directory)
        let model = await loadedModel(of: app)
        model.startEditingRates()

        #expect(!(await model.saveManualUniformRates(usd: "", eur: " ", instruction: "GFŘ-D-80")))
        #expect(model.rateError == "Zadejte aspoň jeden kurz, například 21,84.")
        #expect(!(await model.saveManualUniformRates(usd: "21,5x", eur: "", instruction: "")))
        #expect(model.rateError == "Zadejte kurz ve tvaru 21,84.")
        #expect(!(await model.saveManualUniformRates(usd: "−21,50", eur: "", instruction: "")))
        #expect(!(await model.saveManualUniformRates(usd: "21,555", eur: "", instruction: "")))
        #expect(try await #require(app.database).uniformRates(year: 2026).isEmpty)
        #expect(model.editsRates)
    }

    // MARK: A uniform rate that does not fit the year

    @Test func aRateTypedWithoutItsDecimalCommaIsRefusedAgainstTheCNBRatesOfTheYear() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let app = try await makeSettingsApp(in: directory)
        let database = try #require(app.database)
        let dollars = try cnbYearlyRows([2025]).filter { $0.currency == .usd }
        try await database.insertCNBRates(dollars)
        app.selectYear(2025)
        let model = await loadedModel(of: app)
        model.startEditingRates()
        let mean = dollars.map { $0.rate / Decimal($0.amount) }.reduce(Decimal(0), +) / Decimal(dollars.count)

        #expect(!(await model.saveManualUniformRates(usd: "2184", eur: "", instruction: "GFŘ-D-75")))

        #expect(
            model.rateError
                == "Kurz USD 2\u{00A0}184,00 neodpovídá kurzům ČNB za rok 2025 (průměr "
                + CzechFormat.rate(mean, fractionDigits: 2) + "). Zkontrolujte desetinnou čárku.")
        #expect(try await database.uniformRate(.usd, year: 2025)?.rate == decimal("21.84"))
        #expect(model.editsRates)

        #expect(await model.saveManualUniformRates(usd: "21,84", eur: "", instruction: "GFŘ-D-75"))
        #expect(try await database.uniformRate(.usd, year: 2025)?.origin == .manual)
    }

    @Test func aRateUpToTwentyPercentFromTheMeanOfTheCNBRatesIsTakenAndOneFurtherIsRefused() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let app = try await makeSettingsApp(in: directory)
        let database = try #require(app.database)
        // Invented rates of 2024: 20 and 22 Kč a dollar, and 2 100 Kč for 100 dollars, which is 21 Kč a dollar. The
        // mean is 21 Kč.
        try await database.insertCNBRates([
            CNBRateRow(declaredOn: civilDate("2024-03-01"), currency: .usd, amount: 1, rate: decimal("20")),
            CNBRateRow(declaredOn: civilDate("2024-06-03"), currency: .usd, amount: 1, rate: decimal("22")),
            CNBRateRow(declaredOn: civilDate("2024-09-02"), currency: .usd, amount: 100, rate: decimal("2100")),
        ])
        app.selectYear(2024)
        let model = await loadedModel(of: app)
        model.startEditingRates()

        // 19 % above and below the mean.
        #expect(await model.saveManualUniformRates(usd: "24,99", eur: "", instruction: ""))
        #expect(await model.saveManualUniformRates(usd: "17,01", eur: "", instruction: ""))

        // 21 % above and below it.
        #expect(!(await model.saveManualUniformRates(usd: "25,41", eur: "", instruction: "")))
        #expect(
            model.rateError
                == "Kurz USD 25,41 neodpovídá kurzům ČNB za rok 2024 (průměr 21,00). Zkontrolujte desetinnou čárku.")
        #expect(!(await model.saveManualUniformRates(usd: "16,59", eur: "", instruction: "")))
        #expect(try await database.uniformRate(.usd, year: 2024)?.rate == decimal("17.01"))
    }

    @Test func withoutCNBRatesOfTheYearARateIsComparedWithTheUniformRateOfTheYearBefore() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let app = try await makeSettingsApp(in: directory)
        // 2026 has no ČNB rates stored, and 2025 has its uniform rate, 21,84 Kč a dollar.
        let model = await loadedModel(of: app)
        model.startEditingRates()

        #expect(!(await model.saveManualUniformRates(usd: "2184", eur: "", instruction: "")))

        #expect(
            model.rateError
                == "Kurz USD 2\u{00A0}184,00 se příliš liší od jednotného kurzu za rok 2025 (21,84). Zkontrolujte"
                + " desetinnou čárku.")
        // Up to half as much again is taken.
        #expect(await model.saveManualUniformRates(usd: "32,76", eur: "", instruction: ""))
        #expect(!(await model.saveManualUniformRates(usd: "32,77", eur: "", instruction: "")))
    }

    @Test func withNeitherCNBRatesNorAUniformRateOfTheYearBeforeAnyRateIsTaken() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let app = try await makeSettingsApp(in: directory)
        // 2022 has no ČNB rates stored, and the app has no uniform rate of 2021.
        app.selectYear(2022)
        let model = await loadedModel(of: app)
        model.startEditingRates()

        #expect(await model.saveManualUniformRates(usd: "2184", eur: "", instruction: ""))

        #expect(try await #require(app.database).uniformRate(.usd, year: 2022)?.rate == decimal("2184"))
    }

    @Test func ratesEnteredByHandClearTheFoundRateAndTheReminderThatWaitedForThemOfTheirYear() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let app = try await makeSettingsApp(in: directory)
        app.selectYear(2025)
        let model = await loadedModel(of: app)
        try await #require(app.database).execute("DELETE FROM uniform_rate WHERE year = 2025")
        await app.offerUniformRate(try gfrFinding2025())
        #expect(app.pendingUniformRate != nil)
        app.refresh?.onUniformRateReminder?(2025)

        #expect(await model.saveManualUniformRates(usd: "21,90", eur: "", instruction: "GFŘ-D-75"))

        #expect(app.pendingUniformRate == nil)
        #expect(app.uniformRateReminderYear == nil)
    }

    @Test func aReminderAboutAnotherYearStaysWhenRatesAreEnteredByHand() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let app = try await makeSettingsApp(in: directory)
        let model = await loadedModel(of: app)
        app.refresh?.onUniformRateReminder?(2025)

        #expect(await model.saveManualUniformRates(usd: "21,50", eur: "", instruction: ""))

        #expect(app.uniformRateReminderYear == 2025)
    }

    @Test func theFormOpensOnceTheYearIsLoadedWhenEnteringTheRateByHandWasAsked() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let app = try await makeSettingsApp(in: directory)
        app.settingsAction = .enterUniformRate
        let model = YearTabModel(app: app)

        // The tab is not loaded yet: the request waits, and the load opens the form for it.
        model.openRequestedForm()
        #expect(!model.editsRates && app.settingsAction == .enterUniformRate)
        await model.load()

        #expect(model.editsRates)
        #expect(app.settingsAction == nil)
    }

    @Test func theFormOpensAtOnceWhenTheTabIsLoadedAlready() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let app = try await makeSettingsApp(in: directory)
        let model = await loadedModel(of: app)
        #expect(!model.editsRates)

        app.settingsAction = .enterUniformRate
        model.openRequestedForm()

        #expect(model.editsRates && app.settingsAction == nil)
    }

    @Test func theFormWaitsForTheYearThatWasAskedForWhenTheTabStillShowsAnother() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let app = try await makeSettingsApp(in: directory)
        let model = await loadedModel(of: app)
        // Zadat ručně for 2025, while the tab shows 2026.
        app.selectYear(2025)
        app.settingsAction = .enterUniformRate

        model.openRequestedForm()
        #expect(!model.editsRates && app.settingsAction == .enterUniformRate)
        await model.load()

        #expect(model.year == 2025 && model.editsRates)
        #expect(app.settingsAction == nil)
    }

    @Test func aRequestOfAnotherTabIsLeftForIt() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let app = try await makeSettingsApp(in: directory)
        let model = await loadedModel(of: app)
        app.settingsAction = .restoreBackup

        model.openRequestedForm()

        #expect(!model.editsRates && app.settingsAction == .restoreBackup)
    }

    @Test func theRateOfAPublishedYearShowsItsSource() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let app = try await makeSettingsApp(in: directory)
        app.selectYear(2025)

        let model = await loadedModel(of: app)

        #expect(model.shownRates.map(\.currency) == [.usd, .eur])
        #expect(model.shownRates.map { YearTabModel.rateText($0) } == ["21,84\u{00A0}Kč", "24,66\u{00A0}Kč"])
        #expect(model.rateSource == "pokyn GFŘ-D-75 · v aplikaci od vydání")
    }

    @Test func aGFRPageThatCouldNotBeReadIsShownWithItsLink() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let clock = ManualClock(localNoon(2027, 1, 20))
        let app = try await makeSettingsApp(in: directory, clock: clock)
        let page = try #require(URL(string: "https://mf.gov.cz/assets/attachments/2027-01-14_Financni-zpravodaj-c-2-2027.pdf"))
        var state = RefreshState()
        state.unreadableUniformPages = [2026: page]
        try await #require(app.database).saveRefreshState(state)
        app.selectYear(2026)

        let model = await loadedModel(of: app)

        #expect(model.unreadablePage == page)
        #expect(model.editsRates)
        // On 20. 1. 2027 the app looks for the rate of 2026.
        #expect(model.missingRateText == "Zatím nevyšel. Aplikace ho jednou denně hledá a dá vám ho potvrdit.")
    }

    /// The card never promises a January that has passed: until 2 January of the next year it says when the GFŘ
    /// publishes the rate, from 2 January to 31 March that the app looks for it, and from 1 April that the app does not
    /// have it.
    @Test(arguments: [
        (
            "2026-12-31",
            "Zatím nevyšel. GFŘ ho zveřejní v lednu 2027; aplikace ho pak sama najde a požádá vás o potvrzení."
        ),
        (
            "2027-01-01",
            "Zatím nevyšel. GFŘ ho zveřejní v lednu 2027; aplikace ho pak sama najde a požádá vás o potvrzení."
        ),
        ("2027-01-02", "Zatím nevyšel. Aplikace ho jednou denně hledá a dá vám ho potvrdit."),
        ("2027-03-31", "Zatím nevyšel. Aplikace ho jednou denně hledá a dá vám ho potvrdit."),
        ("2027-04-01", "Pro rok 2026 kurz v aplikaci není. Zadejte ho podle pokynu GFŘ."),
    ])
    func theCardSaysWhereTheRateOfAYearWithoutOneStandsOnTheDay(_ day: String, _ text: String) {
        #expect(YearTabModel.missingRateText(year: 2026, today: civilDate(day)) == text)
    }

    // MARK: Upravit and Odstranit

    @Test func savingTheOfficialValuesUnchangedKeepsTheOfficialRate() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let app = try await makeSettingsApp(in: directory)
        let database = try #require(app.database)
        let shipped = try await database.uniformRates(year: 2025)
        app.selectYear(2025)
        let model = await loadedModel(of: app)
        #expect(model.formHint == nil)
        let version = app.dataVersion

        // Upravit opens the form with the official rates and instruction, and says what saving other ones does.
        model.startEditingRates()
        #expect([model.usdText, model.eurText, model.instructionText] == ["21,84", "24,66", "GFŘ-D-75"])
        #expect(model.formHint == "Ručně zadaný kurz nahradí kurz z pokynu GFŘ-D-75. Vrátíte ho tlačítkem Odstranit.")

        #expect(
            await model.saveManualUniformRates(
                usd: model.usdText, eur: model.eurText, instruction: model.instructionText))

        #expect(app.banner?.text == "Jednotný kurz 2025 se nezměnil.")
        #expect(try await database.uniformRates(year: 2025) == shipped)
        #expect(model.shownRates.allSatisfy { $0.origin == .builtIn })
        #expect(model.rateSource == "pokyn GFŘ-D-75 · v aplikaci od vydání")
        #expect(!model.editsRates && model.formHint == nil)
        #expect(!model.isManual)
        #expect(app.dataVersion == version)
    }

    @Test func editingAManualRateInAUniformYearConvertsItsPaymentsAgain() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let app = try await makeSettingsApp(in: directory)
        let database = try #require(app.database)
        let dollars = try await storeDollarsPaidIn2026(in: app)
        let model = await loadedModel(of: app)
        #expect(await model.saveManualUniformRates(usd: "21,50", eur: "", instruction: ""))
        await model.setFXMethod(.uniform)
        // 10 000,00 USD at 21,50 Kč.
        #expect(try await database.invoice(id: dollars.id)?.payment?.czkNetHalere == 21_500_000)

        // Upravit opens the form with the rate entered by hand, which has nothing official to replace.
        model.startEditingRates()
        #expect([model.usdText, model.eurText, model.instructionText] == ["21,50", "", ""])
        #expect(model.formHint == nil)
        #expect(await model.saveManualUniformRates(usd: "21,90", eur: "", instruction: ""))

        #expect(app.banner?.text == "Jednotný kurz 2026 je uložený. Platby roku 2026 jsou jím přepočtené.")
        #expect(try await database.invoice(id: dollars.id)?.payment?.czkNetHalere == 21_900_000)
        #expect(try await database.uniformRate(.usd, year: 2026)?.origin == .manual)

        // A year that converts at the daily rates keeps its payments, and the banner says where to switch it.
        await model.setFXMethod(.cnbDaily)
        #expect(await model.saveManualUniformRates(usd: "22,00", eur: "", instruction: ""))

        #expect(
            app.banner?.text
                == "Jednotný kurz 2026 je uložený. Rok 2026 na něj přepnete v liště nahoře nebo tady v Profilu.")
        #expect(try await database.invoice(id: dollars.id)?.payment == dollars.payment)
        #expect(try await database.uniformRate(.usd, year: 2026)?.rate == decimal("22.00"))
    }

    /// 2026 is set to the uniform rate, was paid in dollars and has a rate of euros entered by hand: it lacks the rate
    /// of dollars and is computed at the daily rates. An edit that adds the rate of dollars turns it to the uniform
    /// rate, and the write makes the window read the year shown again, whose capsule then names the uniform rate.
    @Test func anEditThatAddsTheMissingCurrencyTurnsTheYearToTheUniformRateAndTheToolbarFollows() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let app = try await makeSettingsApp(in: directory)
        let database = try #require(app.database)
        let dollars = try await storeDollarsPaidIn2026(in: app)
        try await database.updateYearSettings(2026) { $0.incomeFXMethod = .uniform }
        let model = await loadedModel(of: app)
        #expect(await model.saveManualUniformRates(usd: "", eur: "24,50", instruction: ""))
        #expect(try await app.fxState(year: 2026).uniform == .missingCurrency(.usd))
        await app.loadShownYearFX()
        #expect(app.shownYearFXMethod == .cnbDaily)
        #expect(try await database.invoice(id: dollars.id)?.payment == dollars.payment)
        let version = app.dataVersion

        // Upravit adds the rate of dollars.
        model.startEditingRates()
        #expect([model.usdText, model.eurText] == ["", "24,50"])
        #expect(await model.saveManualUniformRates(usd: "21,90", eur: model.eurText, instruction: ""))

        #expect(app.banner?.text == "Jednotný kurz 2026 je uložený. Platby roku 2026 jsou jím přepočtené.")
        // 10 000,00 USD at 21,90 Kč.
        #expect(try await database.invoice(id: dollars.id)?.payment?.czkNetHalere == 21_900_000)
        #expect(app.dataVersion > version)
        await app.loadShownYearFX()
        #expect(app.shownYearFX?.effective == .uniform)
        #expect(app.shownYearFXMethod == .uniform)
    }

    /// The banner of a saved rate says what the year of the rate uses once its payments are converted, read anew. The
    /// tab may have loaded another year meanwhile, as when the year shown changes during the save: here 2025, which
    /// converts at the daily rates, while 2026, whose rate is saved, converts at it.
    @Test(.hangGuard)
    func theBannerOfASavedRateSaysWhatItsYearUsesAlsoWhenTheTabLoadsAnotherYearMeanwhile() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let app = try await makeSettingsApp(in: directory)
        let database = try #require(app.database)
        let dollars = try await storeDollarsPaidIn2026(in: app)
        let model = await loadedModel(of: app)
        #expect(await model.saveManualUniformRates(usd: "21,50", eur: "", instruction: ""))
        await model.setFXMethod(.uniform)
        // A conversion that takes long holds the turns: the save waits for its own while the tab loads 2025.
        let gate = Gate()
        let running = Task { await app.convertPaymentsInTurn { _ in await gate.pass() } }
        await gate.untilARequestWaits()
        let runningTurn = app.latestConversion
        let saving = Task { await model.saveManualUniformRates(usd: "21,90", eur: "", instruction: "") }
        try await waitUntil { app.latestConversion != runningTurn }
        app.selectYear(2025)
        await model.load()
        #expect(model.fxState?.year == 2025 && model.fxState?.effective == .cnbDaily)

        await gate.open()

        #expect(await saving.value)
        _ = await running.value
        #expect(app.banner?.text == "Jednotný kurz 2026 je uložený. Platby roku 2026 jsou jím přepočtené.")
        // 10 000,00 USD at 21,90 Kč.
        #expect(try await database.invoice(id: dollars.id)?.payment?.czkNetHalere == 21_900_000)
    }

    /// A saved rate that lacks a currency the year has payments in leaves the year on the daily rates, whatever it is
    /// set to, and the banner says which rate is missing.
    @Test func aSavedRateThatLacksACurrencyOfThePaymentsSaysTheYearStaysOnTheDailyRates() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let app = try await makeSettingsApp(in: directory)
        let database = try #require(app.database)
        _ = try await storeDollarsPaidIn2026(in: app)
        let model = await loadedModel(of: app)
        let lacksDollars =
            "Jednotný kurz 2026 je uložený, ale chybí v něm kurz USD, ve kterém máte v roce 2026 platby. Dokud ho"
            + " nedoplníte, počítá se rok 2026 denními kurzy ČNB."

        // Set to the daily rates.
        #expect(await model.saveManualUniformRates(usd: "", eur: "24,50", instruction: ""))
        #expect(app.banner?.text == lacksDollars)

        // Set to the uniform rate.
        try await database.updateYearSettings(2026) { $0.incomeFXMethod = .uniform }
        await model.load()
        #expect(await model.saveManualUniformRates(usd: "", eur: "24,60", instruction: ""))
        #expect(app.banner?.text == lacksDollars)
        #expect(try await app.fxState(year: 2026).effective == .cnbDaily)
    }

    /// The form takes the rates of dollars and euros only, so the banner of a save that lacks the rate of any other
    /// currency does not ask for it to be added, and says that it cannot be typed.
    @Test func theBannerOfASaveThatLacksTheRateOfACurrencyThatCannotBeTypedSaysSo() throws {
        let pounds = try #require(CurrencyCode("GBP"))

        #expect(
            YearTabModel.lacksPaidCurrencyText(year: 2026, currency: pounds)
                == "Jednotný kurz 2026 je uložený, ale chybí v něm kurz GBP, ve kterém máte v roce 2026 platby."
                + " Ten ručně zadat nelze, takže se rok 2026 počítá denními kurzy ČNB.")
        #expect(
            YearTabModel.lacksPaidCurrencyText(year: 2026, currency: .eur)
                == "Jednotný kurz 2026 je uložený, ale chybí v něm kurz EUR, ve kterém máte v roce 2026 platby."
                + " Dokud ho nedoplníte, počítá se rok 2026 denními kurzy ČNB.")
    }

    /// The currencies a save keeps beside dollars and euros are those the database holds for the year when it saves,
    /// not those the tab last loaded: another path may have stored the table of the year again meanwhile, here with the
    /// rate of pounds corrected by a later instruction.
    @Test func aRateSaveKeepsTheOtherCurrenciesStoredForItsYearNotThoseTheTabLastLoaded() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let app = try await makeSettingsApp(in: directory)
        let database = try #require(app.database)
        let pounds = try #require(CurrencyCode("GBP"))
        func others(_ rates: [UniformRate]) -> [UniformRate] {
            rates.filter { $0.currency != .usd && $0.currency != .eur }
        }
        app.selectYear(2025)
        let model = await loadedModel(of: app)
        #expect(model.uniformRates.first { $0.currency == pounds }?.rate == decimal("28.80"))
        // Another path stores the table of 2025 again with the rate of pounds corrected, and the tab is not loaded
        // again.
        var corrected = try await database.uniformRates(year: 2025)
        let index = try #require(corrected.firstIndex { $0.currency == pounds })
        corrected[index].rate = decimal("29.10")
        corrected[index].instruction = "GFŘ-D-76"
        try await database.saveUniformRates(corrected, year: 2025)
        let before = try await database.uniformRates(year: 2025)
        #expect(model.uniformRates.first { $0.currency == pounds }?.rate == decimal("28.80"))

        model.startEditingRates()
        model.usdText = "21,90"
        model.eurText = "24,70"
        model.instructionText = "GFŘ-D-80"
        #expect(
            await model.saveManualUniformRates(
                usd: model.usdText, eur: model.eurText, instruction: model.instructionText))

        let saved = try await database.uniformRates(year: 2025)
        // Every currency but dollars and euros is as it was stored before the save, the pound with its correction.
        #expect(others(saved) == others(before))
        #expect(others(saved).count == BuiltInUniformRates.rates(year: 2025).count - 2)
        let pound = try #require(saved.first { $0.currency == pounds })
        #expect(pound.rate == decimal("29.10") && pound.instruction == "GFŘ-D-76")
        // Dollars and euros are the typed ones.
        let dollarsAndEuros = YearTabModel.dollarAndEuroRates(saved)
        #expect(dollarsAndEuros.map(\.currency) == [.usd, .eur])
        #expect(dollarsAndEuros.map(\.rate) == [decimal("21.90"), decimal("24.70")])
        #expect(dollarsAndEuros.allSatisfy { $0.origin == .manual && $0.instruction == "GFŘ-D-80" })
    }

    /// Typed rates are skipped as unchanged only when the database holds them. The tab may still show them after
    /// another path stored other rates for the year, and what the form says is what the person asked to save.
    @Test func aRateSaveIsNotSkippedWhenOnlyTheTabStillShowsTheTypedRates() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let app = try await makeSettingsApp(in: directory)
        let database = try #require(app.database)
        try await database.saveUniformRates(
            [manualRate(.usd, "21.90", year: 2026), manualRate(.eur, "24.70", year: 2026)], year: 2026)
        let model = await loadedModel(of: app)
        model.startEditingRates()
        #expect([model.usdText, model.eurText] == ["21,90", "24,70"])
        // Another path stores other rates for the year, and the tab is not loaded again.
        try await database.saveUniformRates(
            [manualRate(.usd, "22.00", year: 2026), manualRate(.eur, "25.00", year: 2026)], year: 2026)

        #expect(
            await model.saveManualUniformRates(
                usd: model.usdText, eur: model.eurText, instruction: model.instructionText))

        #expect(try await database.uniformRate(.usd, year: 2026)?.rate == decimal("21.90"))
        #expect(try await database.uniformRate(.eur, year: 2026)?.rate == decimal("24.70"))
        // The year converts at the daily rates, so the banner says where to switch it.
        #expect(
            app.banner?.text
                == "Jednotný kurz 2026 je uložený. Rok 2026 na něj přepnete v liště nahoře nebo tady v Profilu.")
        #expect(!model.editsRates)
    }

    /// The question says that the payments are converted at the table that comes back when the year is set to the
    /// uniform rate, as the removal converts them then: also while a rate entered by hand that lacks a currency of the
    /// payments keeps the year on the daily rates.
    @Test func theQuestionSaysThePaymentsAreConvertedWhenTheYearIsSetToTheUniformRate() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let app = try await makeSettingsApp(in: directory)
        let database = try #require(app.database)
        // The ČNB rates of dollars of 2025, which the payment of 7. 10. 2025 is converted at on the daily rates.
        try await database.insertCNBRates(try cnbYearlyRows([2025]).filter { $0.currency == .usd })
        let id = try await database.saveInvoice(paidDollarInvoiceOf2025())
        app.selectYear(2025)
        let model = await loadedModel(of: app)
        await model.setFXMethod(.uniform)
        // A rate of euros alone: the year, paid in dollars, is computed at the daily rates meanwhile.
        #expect(await model.saveManualUniformRates(usd: "", eur: "24,80", instruction: ""))
        #expect(model.fxState?.chosen == .uniform)
        #expect(model.fxState?.effective == .cnbDaily)
        #expect(try await database.invoice(id: id)?.payment?.conversion == .cnbDaily)

        model.askToRemoveRates()

        #expect(
            model.removalQuestion
                == "Rok 2025 pak použije kurz z pokynu GFŘ-D-75 (1\u{00A0}USD = 21,84\u{00A0}Kč · 1\u{00A0}EUR ="
                + " 24,66\u{00A0}Kč). Platby roku 2025 se jím přepočtou.")
        await model.removeManualUniformRates()
        // 1 000 USD at 21,84 Kč.
        let payment = try #require(try await database.invoice(id: id)?.payment)
        #expect(payment.conversion == .uniform && payment.czkNetHalere == 2_184_000)
    }

    /// Odstranit… asks in the card what removing the rate entered by hand leads to: for a year whose table ships with
    /// the app, for the current year and for a year that is over, each with and without the uniform rate. Zrušit
    /// removes nothing.
    @Test func theRemovalAsksInlineWithWhatFollows() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let app = try await makeSettingsApp(in: directory)
        let database = try #require(app.database)
        try await database.saveInvoice(paidDollarInvoiceOf2025())
        // 2026 has settings of its own, so that it keeps the daily rates when 2025 switches.
        try await database.updateYearSettings(2026) { $0.incomeFXMethod = .cnbDaily }
        app.selectYear(2025)
        let model = await loadedModel(of: app)
        // The official rate has nothing to remove.
        model.askToRemoveRates()
        #expect(!model.asksToRemove)
        #expect(model.manualNote == nil)

        // 2025, whose table ships with the app.
        #expect(await model.saveManualUniformRates(usd: "21,90", eur: "24,80", instruction: "GFŘ-D-80"))
        #expect(model.isManual)
        #expect(model.rateSource == "pokyn GFŘ-D-80, zadáno ručně")
        #expect(
            model.manualNote
                == "Nahrazuje kurz z pokynu GFŘ-D-75 (1\u{00A0}USD = 21,84\u{00A0}Kč · 1\u{00A0}EUR = 24,66\u{00A0}Kč),"
                + " který má aplikace od vydání.")
        model.askToRemoveRates()
        #expect(model.asksToRemove)
        #expect(YearTabModel.removalTitle == "Odstranit ručně zadaný kurz?")
        #expect(YearTabModel.removalConfirmTitle == "Odstranit kurz")
        #expect(
            model.removalQuestion
                == "Rok 2025 pak použije kurz z pokynu GFŘ-D-75 (1\u{00A0}USD = 21,84\u{00A0}Kč · 1\u{00A0}EUR ="
                + " 24,66\u{00A0}Kč).")
        await model.setFXMethod(.uniform)
        #expect(model.asksToRemove)
        #expect(
            model.removalQuestion
                == "Rok 2025 pak použije kurz z pokynu GFŘ-D-75 (1\u{00A0}USD = 21,84\u{00A0}Kč · 1\u{00A0}EUR ="
                + " 24,66\u{00A0}Kč). Platby roku 2025 se jím přepočtou.")
        model.cancelRemovingRates()
        #expect(!model.asksToRemove)
        #expect(try await database.uniformRate(.usd, year: 2025)?.origin == .manual)

        // 2026, the current year, whose rate the GFŘ publishes in January.
        app.selectYear(2026)
        await model.load()
        #expect(await model.saveManualUniformRates(usd: "21,90", eur: "", instruction: ""))
        #expect(model.rateSource == "zadáno ručně")
        #expect(
            model.manualNote
                == "Dokud je kurz zadaný ručně, aplikace oficiální kurz nehledá. Po odstranění ho začne hledat znovu.")
        model.askToRemoveRates()
        #expect(
            model.removalQuestion
                == "Jednotný kurz 2026 pak nebude k dispozici, dokud ho GFŘ nezveřejní (v lednu 2027). Aplikace ho"
                + " začne znovu hledat a dá vám ho potvrdit.")
        await model.setFXMethod(.uniform)
        #expect(
            model.removalQuestion
                == "Jednotný kurz 2026 pak nebude k dispozici, dokud ho GFŘ nezveřejní (v lednu 2027). Aplikace ho"
                + " začne znovu hledat a dá vám ho potvrdit. Do té doby se rok 2026 počítá denními kurzy ČNB;"
                + " jednotným kurzem se přepočte, až kurz potvrdíte.")
        model.cancelRemovingRates()

        // 2021, a year that is over and whose table the app does not have.
        app.selectYear(2021)
        await model.load()
        #expect(!model.asksToRemove)
        #expect(await model.saveManualUniformRates(usd: "20,00", eur: "", instruction: ""))
        #expect(model.manualNote == "Oficiální kurz pro rok 2021 aplikace nemá.")
        model.askToRemoveRates()
        #expect(model.removalQuestion == "Jednotný kurz 2021 pak v aplikaci nebude.")
        await model.setFXMethod(.uniform)
        #expect(
            model.removalQuestion
                == "Jednotný kurz 2021 pak v aplikaci nebude. Rok 2021 se bude počítat denními kurzy ČNB.")
        // Upravit closes the question.
        model.startEditingRates()
        #expect(!model.asksToRemove)
        #expect(model.formHint == nil)
    }

    /// The texts of a rate entered by hand for a year without an official one follow the search of the app for it,
    /// like the card: the January of the GFŘ is named only before the app starts looking.
    @Test func theTextsOfARateEnteredByHandFollowTheSearchForTheOfficialOne() {
        func question(_ day: String, uniform: Bool) -> String {
            YearTabModel.removalQuestion(year: 2026, today: civilDate(day), choseUniform: uniform)
        }
        func banner(_ day: String, uniform: Bool) -> String {
            YearTabModel.removalBanner(year: 2026, today: civilDate(day), choseUniform: uniform)
        }
        let awaited =
            "Dokud je kurz zadaný ručně, aplikace oficiální kurz nehledá. Po odstranění ho začne hledat znovu."

        #expect(YearTabModel.manualNote(year: 2026, today: civilDate("2027-01-01")) == awaited)
        #expect(YearTabModel.manualNote(year: 2026, today: civilDate("2027-03-31")) == awaited)
        #expect(
            YearTabModel.manualNote(year: 2026, today: civilDate("2027-04-01"))
                == "Oficiální kurz pro rok 2026 aplikace nemá.")

        #expect(
            question("2027-01-01", uniform: false)
                == "Jednotný kurz 2026 pak nebude k dispozici, dokud ho GFŘ nezveřejní (v lednu 2027). Aplikace ho"
                + " začne znovu hledat a dá vám ho potvrdit.")
        #expect(
            question("2027-01-02", uniform: false)
                == "Jednotný kurz 2026 pak nebude k dispozici, dokud ho GFŘ nezveřejní. Aplikace ho začne znovu hledat"
                + " a dá vám ho potvrdit.")
        #expect(
            question("2027-03-31", uniform: true)
                == "Jednotný kurz 2026 pak nebude k dispozici, dokud ho GFŘ nezveřejní. Aplikace ho začne znovu hledat"
                + " a dá vám ho potvrdit. Do té doby se rok 2026 počítá denními kurzy ČNB; jednotným kurzem se"
                + " přepočte, až kurz potvrdíte.")
        #expect(question("2027-04-01", uniform: false) == "Jednotný kurz 2026 pak v aplikaci nebude.")

        #expect(
            banner("2027-03-31", uniform: false)
                == "Ručně zadaný jednotný kurz 2026 je odstraněný. Aplikace oficiální kurz znovu hledá.")
        #expect(
            banner("2027-04-01", uniform: true)
                == "Ručně zadaný jednotný kurz 2026 je odstraněný. Pro rok 2026 teď jednotný kurz není. Rok 2026 se"
                + " zatím počítá denními kurzy ČNB.")
        #expect(
            YearTabModel.removalBanner(year: 2024, today: civilDate("2027-04-01"), choseUniform: true)
                == "Ručně zadaný jednotný kurz 2024 je odstraněný. Rok 2024 teď používá kurz z pokynu GFŘ-D-65.")
    }

    @Test func removingAManualRateOfABuiltInYearBringsBackTheShippedRate() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let app = try await makeSettingsApp(in: directory)
        let database = try #require(app.database)
        let shipped = try await database.uniformRates(year: 2025)
        let id = try await database.saveInvoice(paidDollarInvoiceOf2025())
        app.selectYear(2025)
        let model = await loadedModel(of: app)
        await model.setFXMethod(.uniform)
        // A rate of dollars alone: the year has no rate of euros while it is stored.
        #expect(await model.saveManualUniformRates(usd: "21,90", eur: "", instruction: ""))
        #expect(try await database.uniformRate(.eur, year: 2025) == nil)
        // 1 000 USD at 21,90 Kč.
        #expect(try await database.invoice(id: id)?.payment?.czkNetHalere == 2_190_000)
        model.askToRemoveRates()

        await model.removeManualUniformRates()

        #expect(try await database.uniformRates(year: 2025) == shipped)
        #expect(model.shownRates.map { YearTabModel.rateText($0) } == ["21,84\u{00A0}Kč", "24,66\u{00A0}Kč"])
        #expect(model.shownRates.allSatisfy { $0.origin == .builtIn })
        #expect(model.rateSource == "pokyn GFŘ-D-75 · v aplikaci od vydání")
        #expect(!model.isManual && !model.asksToRemove)
        #expect(
            app.banner?.text
                == "Ručně zadaný jednotný kurz 2025 je odstraněný. Rok 2025 teď používá kurz z pokynu GFŘ-D-75.")
        // 1 000 USD at 21,84 Kč again.
        let payment = try #require(try await database.invoice(id: id)?.payment)
        #expect(payment.conversion == .uniform && payment.czkNetHalere == 2_184_000)
        #expect(model.saveFailure == nil)
    }

    @Test func removingAManualRateOfTheCurrentYearLeavesNoneAndSaysTheYearIsDaily() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let app = try await makeSettingsApp(in: directory)
        let database = try #require(app.database)
        let dollars = try await storeDollarsPaidIn2026(in: app)
        let model = await loadedModel(of: app)
        #expect(await model.saveManualUniformRates(usd: "21,90", eur: "", instruction: ""))
        await model.setFXMethod(.uniform)
        // 10 000,00 USD at 21,90 Kč.
        #expect(try await database.invoice(id: dollars.id)?.payment?.czkNetHalere == 21_900_000)
        await app.loadShownYearFX()
        #expect(app.shownYearFXMethod == .uniform)
        let version = app.dataVersion
        model.askToRemoveRates()

        await model.removeManualUniformRates()

        #expect(try await database.uniformRates(year: 2026).isEmpty)
        #expect(model.shownRates.isEmpty && !model.isManual && !model.asksToRemove)
        let fxState = try await app.fxState(year: 2026)
        #expect(fxState.chosen == .uniform)
        #expect(fxState.effective == .cnbDaily)
        #expect(fxState.uniform == .notPublishedYet(year: 2026))
        #expect(
            app.banner?.text
                == "Ručně zadaný jednotný kurz 2026 je odstraněný. Aplikace oficiální kurz znovu hledá. Rok 2026 se"
                + " zatím počítá denními kurzy ČNB.")
        // Back at the ČNB rate of 2. 10. 2026.
        #expect(try await database.invoice(id: dollars.id)?.payment == dollars.payment)
        #expect(
            model.missingRateText
                == "Zatím nevyšel. GFŘ ho zveřejní v lednu 2027; aplikace ho pak sama najde a požádá vás o potvrzení.")
        // The write makes the window read the year shown again, and the toolbar then names the daily rates.
        #expect(app.dataVersion > version)
        await app.loadShownYearFX()
        #expect(app.shownYearFX?.effective == .cnbDaily)
        #expect(app.shownYearFXMethod == .cnbDaily)
    }

    /// The banner of a removal is built from the choice the year has once its payments are converted, read anew: the
    /// tab may still show the choice it loaded, which another path changed since. Here 2026 is set to the uniform rate,
    /// as the menu of the toolbar does, after the tab loaded it on the daily rates: the removal leaves it without a
    /// rate, computed at the daily rates until the official one comes, and the banner says so.
    @Test func theRemovalBannerFollowsTheMethodTheYearUsesNotTheTabsLastLoad() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let app = try await makeSettingsApp(in: directory)
        let database = try #require(app.database)
        try await database.saveUniformRates(
            [manualRate(.usd, "21.90", year: 2026), manualRate(.eur, "24.70", year: 2026)], year: 2026)
        let model = await loadedModel(of: app)
        #expect(model.isManual && model.settings?.incomeFXMethod == .cnbDaily)
        #expect(await app.setFXMethod(.uniform, year: 2026) == .saved)
        // The tab is not loaded again.
        #expect(model.settings?.incomeFXMethod == .cnbDaily)
        model.askToRemoveRates()

        await model.removeManualUniformRates()

        #expect(try await database.uniformRates(year: 2026).isEmpty)
        #expect(
            app.banner?.text
                == "Ručně zadaný jednotný kurz 2026 je odstraněný. Aplikace oficiální kurz znovu hledá. Rok 2026 se"
                + " zatím počítá denními kurzy ČNB.")
    }

    /// A year whose conversion cannot be read once its rates are removed gets no banner: the rates are removed, and the
    /// tab says itself that it cannot load the year.
    @Test func aRemovalThatCannotReadWhatItsYearUsesNowShowsNoBanner() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let app = try await makeSettingsApp(in: directory)
        let database = try #require(app.database)
        try await database.saveUniformRates(
            [manualRate(.usd, "21.90", year: 2026), manualRate(.eur, "24.70", year: 2026)], year: 2026)
        try await database.updateYearSettings(2026) { $0.incomeFXMethod = .uniform }
        let model = await loadedModel(of: app)
        #expect(model.isManual && model.settings?.incomeFXMethod == .uniform)
        // The choice of the year is damaged in the data after the tab read it.
        try await database.execute("UPDATE year_settings SET income_fx_method = 'unknown' WHERE year = 2026")
        model.askToRemoveRates()

        await model.removeManualUniformRates()

        #expect(try await database.uniformRates(year: 2026).isEmpty)
        #expect(app.banner == nil)
        #expect(model.errorText == YearTabModel.loadFailureText)
    }

    /// On 15. 4. 2027 the search for the rate of 2026 has given up. A rate entered by hand and removed again lets the
    /// refresh look for it once more, as if the search had never given up: it ends again, with the reminder.
    @Test func removingAManualRateLetsTheSearchThatGaveUpRunAgain() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let server = StubHTTPClient()
        let app = makeAppModel(in: directory, clock: ManualClock(localNoon(2027, 4, 15)), http: server)
        try await startFresh(app)
        let database = try #require(app.database)
        var state = RefreshState()
        state.gaveUpUniform = [2026]
        try await database.saveRefreshState(state)
        app.selectYear(2026)
        let model = await loadedModel(of: app)
        #expect(await model.saveManualUniformRates(usd: "21,90", eur: "", instruction: ""))
        #expect(model.manualNote == "Oficiální kurz pro rok 2026 aplikace nemá.")
        model.askToRemoveRates()
        #expect(model.removalQuestion == "Jednotný kurz 2026 pak v aplikaci nebude.")

        await model.removeManualUniformRates()

        #expect(
            app.banner?.text == "Ručně zadaný jednotný kurz 2026 je odstraněný. Pro rok 2026 teď jednotný kurz není.")
        #expect(try await database.refreshState()?.gaveUpUniform == [])
        #expect(app.uniformRateReminderYear == nil)
        let refresh = try #require(app.refresh)
        await refresh.refresh(.settingsChanged)
        #expect(server.requests.contains(GFRParser.indexURL(forYear: 2026)))
        #expect(app.uniformRateReminderYear == 2026)
    }

    // MARK: Pravidla

    @Test func theRulesAreTheValuesOfTheYearWithTheConventionsOfTheApp() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let app = try await makeSettingsApp(in: directory)

        let model = await loadedModel(of: app)

        #expect(model.rulesVersion == "verze 2026.1 · ověřeno 20.\u{00A0}10.\u{00A0}2026")
        // The levies first; the amounts of the family follow them (`theRulesListTheFamilyAmounts`).
        #expect(
            Array(model.ruleRows.prefix(6)) == [
                YearTabModel.RuleRow(
                    label: "Daň 15\u{00A0}%, 23\u{00A0}% ze základu nad", value: "1\u{00A0}762\u{00A0}812\u{00A0}Kč"),
                YearTabModel.RuleRow(label: "Sleva na poplatníka", value: "30\u{00A0}840\u{00A0}Kč"),
                YearTabModel.RuleRow(
                    label: "Sociální 55\u{00A0}% zisku × 29,2\u{00A0}%, min. VZ / měsíc", value: "17\u{00A0}139\u{00A0}Kč"),
                YearTabModel.RuleRow(label: "Sociální – maximální VZ za rok", value: "2\u{00A0}350\u{00A0}416\u{00A0}Kč"),
                YearTabModel.RuleRow(
                    label: "Zdravotní 50\u{00A0}% zisku × 13,5\u{00A0}%, min. VZ / měsíc", value: "24\u{00A0}483,50\u{00A0}Kč"),
                YearTabModel.RuleRow(label: "Strop paušálu 60\u{00A0}%", value: "1\u{00A0}200\u{00A0}000\u{00A0}Kč"),
            ])
        #expect(
            model.conventions == [
                BuilderText.capitalized(ComputationBuilder.incomeRoundingNote),
                BuilderText.capitalized(ComputationBuilder.notReachedMonthsConvention),
            ])
        #expect(model.rulesWarning == nil)
    }

    /// After the levies the rules list the amounts of the family: the spouse credit for a year, from 2024 only with a
    /// child under three, the child benefit of the first, the second and the third and every further child for a year,
    /// and the income from which the tax bonus is paid, six minimum wages of the year.
    @Test func theRulesListTheFamilyAmounts() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let app = try await makeSettingsApp(in: directory)

        let model = await loadedModel(of: app)

        #expect(model.ruleRows.count == 9)
        #expect(
            Array(model.ruleRows.dropFirst(6)) == [
                YearTabModel.RuleRow(
                    label: "Sleva na manžela/ku – jen s vaším dítětem do 3 let", value: "24\u{00A0}840\u{00A0}Kč"),
                YearTabModel.RuleRow(
                    label: "Daňové zvýhodnění na 1. / 2. / 3. a další dítě",
                    value: "15\u{00A0}204 / 22\u{00A0}320 / 27\u{00A0}840\u{00A0}Kč"),
                YearTabModel.RuleRow(
                    label: "Daňový bonus od příjmů (6× minimální mzda 22\u{00A0}400\u{00A0}Kč)",
                    value: "134\u{00A0}400\u{00A0}Kč"),
            ])

        // 2023 needs no child for the spouse credit, and has a minimum wage of its own.
        app.selectYear(2023)
        let year2023 = await loadedModel(of: app)
        #expect(
            Array(year2023.ruleRows.dropFirst(6)) == [
                YearTabModel.RuleRow(label: "Sleva na manžela/ku", value: "24\u{00A0}840\u{00A0}Kč"),
                YearTabModel.RuleRow(
                    label: "Daňové zvýhodnění na 1. / 2. / 3. a další dítě",
                    value: "15\u{00A0}204 / 22\u{00A0}320 / 27\u{00A0}840\u{00A0}Kč"),
                YearTabModel.RuleRow(
                    label: "Daňový bonus od příjmů (6× minimální mzda 17\u{00A0}300\u{00A0}Kč)",
                    value: "103\u{00A0}800\u{00A0}Kč"),
            ])
    }

    @Test func aYearWithoutRulesOfItsOwnSaysItIsAnEstimate() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let app = try await makeSettingsApp(in: directory, clock: ManualClock(localNoon(2027, 1, 20)))

        let model = await loadedModel(of: app)

        #expect(model.year == 2027)
        #expect(model.rulesVersion == "verze 2026.1 · ověřeno 20.\u{00A0}10.\u{00A0}2026")
        #expect(model.rulesWarning == RulesWarning.message(year: 2027, rulesYear: 2026))
    }

    // MARK: Úpravy příjmů

    @Test func anAdjustmentOfMinusOneThousandCrownsIsStoredInHalere() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let app = try await makeSettingsApp(in: directory)
        app.showSettings(.year)
        let database = try #require(app.database)
        let model = await loadedModel(of: app)
        model.adjustmentAmount = "−1 000"
        model.adjustmentDescription = "dobropis k faktuře 20260801"

        #expect(await model.addAdjustment(date: civilDate("2026-08-20"), amount: "−1 000", description: " dobropis k faktuře 20260801 "))

        let stored = try await database.adjustments(year: 2026)
        #expect(stored.map(\.amountHalere) == [-100_000])
        #expect(stored.map(\.description) == ["dobropis k faktuře 20260801"])
        #expect(model.adjustments.map(\.amountHalere) == [-100_000])
        #expect(model.adjustmentAmount == "")
        #expect(model.adjustmentDescription == "")
        #expect(model.adjustmentsTotal == "celkem \u{2212}1\u{00A0}000,00\u{00A0}Kč")
        #expect(YearTabModel.adjustmentAmountText(-100_000) == "\u{2212}1\u{00A0}000,00\u{00A0}Kč")
        #expect(YearTabModel.adjustmentAmountText(450_000) == "+4\u{00A0}500,00\u{00A0}Kč")
        #expect(app.banner?.text == "Úprava příjmů je přidaná a počítá se do roku 2026.")
    }

    /// The field of the amount shows the example of the design, "−5 200", with the minus sign and the no-break space
    /// the app writes its numbers with.
    @Test func theFieldOfTheAmountOfAnAdjustmentShowsTheExampleOfTheDesign() {
        #expect(YearTabModel.adjustmentAmountPrompt == "\u{2212}5\u{00A0}200")
    }

    @Test func theAmountOfAnAdjustmentIsReadWithItsSign() {
        #expect(YearTabModel.signedAmount("−1 000") == -100_000)
        #expect(YearTabModel.signedAmount("-1000,50") == -100_050)
        #expect(YearTabModel.signedAmount("+4 500") == 450_000)
        #expect(YearTabModel.signedAmount(" 4 500 ") == 450_000)
        #expect(YearTabModel.signedAmount("+−5") == nil)
        #expect(YearTabModel.signedAmount("+ 5") == nil)
        #expect(YearTabModel.signedAmount("++5") == nil)
        #expect(YearTabModel.signedAmount("+") == nil)
    }

    @Test func anAdjustmentWithoutAnAmountOrOutsideTheYearIsRefused() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let app = try await makeSettingsApp(in: directory)
        let model = await loadedModel(of: app)

        #expect(!(await model.addAdjustment(date: civilDate("2025-12-31"), amount: "500", description: "")))
        #expect(model.adjustmentError == "Zadejte datum v roce 2026.")
        #expect(!(await model.addAdjustment(date: civilDate("2026-03-01"), amount: "0", description: "")))
        #expect(model.adjustmentError == "Zadejte částku v Kč – kladnou, když příjem přibyl, zápornou, když ubyl.")
        #expect(!(await model.addAdjustment(date: civilDate("2026-03-01"), amount: "12,345", description: "")))
        #expect(model.adjustmentError == "Zadejte částku ve tvaru 13 340 nebo 13 340,50.")
        #expect(try await #require(app.database).adjustments(year: 2026).isEmpty)
        #expect(model.adjustmentsTotal == nil)
    }

    @Test func anAdjustmentIsDeleted() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let app = try await makeSettingsApp(in: directory)
        let database = try #require(app.database)
        let model = await loadedModel(of: app)
        #expect(await model.addAdjustment(date: civilDate("2026-02-01"), amount: "4 500", description: "platba v Kč"))
        let id = try #require(model.adjustments.first?.id)

        await model.deleteAdjustment(id: id)

        #expect(try await database.adjustments(year: 2026).isEmpty)
        #expect(model.adjustments.isEmpty)
    }
}
