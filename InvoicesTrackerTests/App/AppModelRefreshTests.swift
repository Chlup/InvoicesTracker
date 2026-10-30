import Foundation
import Testing
@testable import InvoicesTracker

/// What the app model does with what the refresh tells it: a rate that is found waits for the person (and is offered in
/// a sheet, while its year has no rate stored), the reminder of 31 March is kept for the banner and found again at the
/// next launch, a confirmed rate is stored with where it is from and the payments of its year are converted at it, and
/// entering it by hand opens the form of Nastavení › Rok. The data is invented, the server is a stub, and the clock is
/// at noon of 17. 10. 2026, when 2025 is the finished year.
@Suite(.settlesBackups)
@MainActor
struct AppModelRefreshTests {
    // MARK: Helpers

    /// An app model that has gone through the first launch. The server answers what `http` says; the refresh is made
    /// but not started unless `startsRefresh`.
    private func makeApp(
        in directory: URL, http: any HTTPClient = StubHTTPClient(), scheduler: ManualScheduler = ManualScheduler(),
        startsRefresh: Bool = false
    ) async throws -> AppModel {
        let app = makeAppModel(in: directory, http: http, scheduler: scheduler, startsRefresh: startsRefresh)
        try await startFresh(app)
        return app
    }

    /// Takes the rates that ship with the app out of 2025, as they are not there for a year that has just been
    /// published.
    private func deleteBuiltInRates(of year: Int, in database: Database) async throws {
        try await database.execute("DELETE FROM uniform_rate WHERE year = \(year)")
    }

    // MARK: What the refresh tells

    @Test func aFoundUniformRateWaitsForTheConfirmationAndIsOfferedInASheet() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let app = try await makeApp(in: directory)
        try await deleteBuiltInRates(of: 2025, in: try #require(app.database))
        let finding = try gfrFinding2025()
        #expect(app.pendingUniformRate == nil && app.uniformRateOffer == nil)

        await app.offerUniformRate(finding)

        #expect(app.pendingUniformRate == finding)
        #expect(app.uniformRateOffer == finding)
        // Nothing is stored until the person confirms it.
        #expect(try await #require(app.database).uniformRates(year: 2025).isEmpty)
    }

    @Test func whatTheRefreshFindsIsOfferedToTheApp() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let app = try await makeApp(in: directory)
        try await deleteBuiltInRates(of: 2025, in: try #require(app.database))
        let finding = try gfrFinding2025()

        try #require(app.refresh).onUniformRateFound?(finding)

        try await waitUntil { app.uniformRateOffer == finding }
        #expect(app.pendingUniformRate == finding)
    }

    @Test func aFindingForAYearThatHasItsRatesStoredIsNotOffered() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let app = try await makeApp(in: directory)
        // 2025 has the table that ships with the app, as a year that was confirmed has its own.
        #expect(try await #require(app.database).uniformRates(year: 2025).isEmpty == false)

        await app.offerUniformRate(try gfrFinding2025())

        #expect(app.pendingUniformRate == nil)
        #expect(app.uniformRateOffer == nil)
    }

    @Test func aFindingWithNoRateInItIsNotOffered() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let app = try await makeApp(in: directory)
        let finding = try gfrFinding2025()
        let empty = GFRFinding(
            year: 2026, instruction: finding.instruction, issueURL: finding.issueURL, pdfURL: finding.pdfURL, rates: [])

        await app.offerUniformRate(empty)

        #expect(app.pendingUniformRate == nil)
        #expect(app.uniformRateOffer == nil)
    }

    @Test func theReminderOf31MarchIsKeptForTheBannerOfPrehled() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let app = try await makeApp(in: directory)

        try #require(app.refresh).onUniformRateReminder?(2026)

        #expect(app.uniformRateReminderYear == 2026)
        #expect(app.uniformRateOffer == nil)
    }

    /// An app model on the data of `directory` as a new launch opens it, after the data were left with the search for
    /// the uniform rate of 2025 given up on (`gaveUp`) and the rates of 2025 stored or not (`stored`).
    private func relaunched(
        in directory: URL, gaveUp: Set<Int>, ratesStoredFor stored: Bool
    ) async throws -> AppModel {
        let before = try await makeApp(in: directory)
        let database = try #require(before.database)
        if !stored {
            try await deleteBuiltInRates(of: 2025, in: database)
        }
        var state = RefreshState()
        state.gaveUpUniform = gaveUp
        try await database.saveRefreshState(state)
        await database.close()
        let app = makeAppModel(in: directory)
        await app.launch()
        #expect(app.phase == .ready)
        return app
    }

    @Test func theReminderOf31MarchComesBackAtTheNextLaunchWhileTheYearHasNoRates() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }

        let app = try await relaunched(in: directory, gaveUp: [2025], ratesStoredFor: false)

        #expect(app.uniformRateReminderYear == 2025)
    }

    @Test func theReminderDoesNotComeBackOnceTheRatesOfTheYearAreStored() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }

        let app = try await relaunched(in: directory, gaveUp: [2025], ratesStoredFor: true)

        #expect(app.uniformRateReminderYear == nil)
    }

    @Test func noReminderComesBackForASearchThatWasNotGivenUp() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }

        let app = try await relaunched(in: directory, gaveUp: [], ratesStoredFor: false)

        #expect(app.uniformRateReminderYear == nil)
    }

    @Test func theNewestYearThatWasGivenUpOnIsTheOneTheReminderIsAbout() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }

        let app = try await relaunched(in: directory, gaveUp: [2024, 2025], ratesStoredFor: false)

        // 2024 has the table that ships with the app; 2025 has none.
        #expect(app.uniformRateReminderYear == 2025)
    }

    @Test func theReminderIsSaidToVoiceOverWhenItComesAndNotWhenItGoes() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let app = try await makeApp(in: directory)
        var announced: [String] = []
        app.announce = { announced.append($0) }

        app.uniformRateReminderYear = 2026
        app.uniformRateReminderYear = 2026
        app.uniformRateReminderYear = nil

        #expect(
            announced == ["Jednotný kurz za rok 2026 se nepodařilo najít – zadejte ho ručně v Nastavení › Rok 2026."])
    }

    @Test func aSheetThatWasPutOffKeepsTheFindingPendingAndComesAgainWhenTheRateIsFoundAgain() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let app = try await makeApp(in: directory)
        try await deleteBuiltInRates(of: 2025, in: try #require(app.database))
        let finding = try gfrFinding2025()
        await app.offerUniformRate(finding)

        // Dismissed without a choice.
        app.uniformRateOffer = nil

        #expect(app.pendingUniformRate == finding)
        // The next search finds it again, because it is not stored: the person is asked again.
        await app.offerUniformRate(finding)
        #expect(app.uniformRateOffer == finding)
    }

    @Test func newRatesLoadTheScreensAgainAlsoWhenNoPaymentWaitedForThem() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let app = try await makeApp(in: directory)
        let version = app.dataVersion

        // No payment waits for a rate: nothing is converted, and the screens load again all the same, as they show the
        // invoices that are not paid at the new rates too.
        try #require(app.refresh).onRatesUpdated?()
        try await waitUntil { app.dataVersion > version }

        #expect(app.dataVersion == version + 1)
    }

    /// An import while the yearly ČNB file of 2025 could not be downloaded leaves a dollar payment of 2025 provisional,
    /// at the rate of its invoice. The next refresh, online, fetches that year, and the payment is converted at the
    /// rate of its day.
    @Test(.hangGuard)
    func aPaymentLeftProvisionalByAnImportIsConvertedOnceTheRefreshFetchedTheRatesOfItsYear() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        var files: [URL: Data] = [:]
        for year in [2025, 2026] {
            files[CNBEndpoints.yearly(year)] = try Data(contentsOf: fixtureURL("cnb_rok_\(year)", "txt"))
        }
        let server = StubHTTPClient(files)
        let app = try await makeApp(in: directory, http: server)
        let database = try #require(app.database)

        // 1. The import, while the yearly file of 2025 cannot be fetched.
        let row = FakturoidCSV.row([
            "Id": "20250301", "Number": "20250301", "Client name": "Bravo Labs, Inc.", "Client registration no": "",
            "Client vat no": "", "Client country": "US", "Currency": "USD", "Exchange rate": "23.5", "Vat": "0.0",
            "Status": "paid", "Issued on": "2025-03-03", "Taxable fulfillment due": "2025-03-03",
            "Paid on": "2025-03-20", "Subtotal": "10000,0", "Total": "10000,0", "Language": "en",
        ])
        let url = try writeCSV(FakturoidCSV.text([row]), named: "export.csv", in: directory)
        let offline = StubHTTPClient(failures: [CNBEndpoints.yearly(2025): HTTPError.offline])
        let importer = FakturoidImporter(
            database: database, fetcher: CNBFetcher(http: offline), clock: ManualClock(localNoon(2026, 10, 16)))
        let summary = try await importer.importFiles([url]) { _ in }
        #expect(summary.added == 1 && summary.needsReview == 0)
        let imported = try #require(try await database.invoice(numberDigits: "20250301", currency: .usd))
        // 10 000,00 USD at the rate 23,5 of the export: 235 000,00 Kč of income in 2025, for now.
        #expect(imported.payment?.provisional == true)
        #expect(imported.payment?.czkNetHalere == 23_500_000)

        // 2. The refresh of the next launch, online.
        let refresh = try #require(app.refresh)
        let backupsBefore = app.backupsAfterWrite
        await refresh.refresh(.launch)

        #expect(server.requests.contains(CNBEndpoints.yearly(2025)))
        try await waitUntil {
            try await database.invoice(id: imported.id)?.payment?.provisional == false
        }
        // The conversion is a write, told from a task of the callback: the test goes on once that write has started
        // its backups, which the trait of the suite waits for, so that none of them runs after the folder is removed.
        try await waitUntil { app.backupsAfterWrite != backupsBefore }
        let rateOfTheDay = try #require(
            try cnbYearlyRows([2025]).first { $0.currency == .usd && $0.declaredOn == civilDate("2025-03-20") })
        let expected = DecimalMath.halfUp(Decimal(1_000_000) * rateOfTheDay.rate / Decimal(rateOfTheDay.amount))
        let payment = try #require(try await database.invoice(id: imported.id)?.payment)
        #expect(payment.rate == StoredRate(rate: rateOfTheDay.exchangeRate, declaredOn: civilDate("2025-03-20")))
        #expect(payment.czkNetHalere == expected)
        #expect(try await database.receipts(year: 2025).map(\.czkNetHalere) == [expected])
    }

    // MARK: Použít

    @Test func confirmingTheFindingOf2025StoresItsThirtyOneRatesAsFetchedWithTheirInstructionSourceAndDay()
        async throws
    {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let app = try await makeApp(in: directory)
        let database = try #require(app.database)
        try await deleteBuiltInRates(of: 2025, in: database)
        #expect(try await database.uniformRates(year: 2025).isEmpty)
        let finding = try gfrFinding2025()
        await app.offerUniformRate(finding)
        let version = app.dataVersion

        try await app.confirmUniformRate(finding)

        let stored = try await database.uniformRates(year: 2025)
        #expect(stored.count == 31)
        #expect(stored.allSatisfy { $0.origin == .fetched && $0.instruction == "GFŘ-D-75" })
        #expect(stored.allSatisfy { $0.sourceURL == gfrPDF2025URL.absoluteString })
        #expect(stored.allSatisfy { $0.confirmedAt == localNoon(2026, 10, 17) })
        let dollar = try #require(try await database.uniformRate(.usd, year: 2025))
        #expect(dollar.amount == 1 && dollar.rate == decimal("21.84"))
        let yen = try #require(try await database.uniformRate(CurrencyCode("JPY")!, year: 2025))
        #expect(yen.amount == 100 && yen.rate == decimal("14.59"))
        #expect(app.pendingUniformRate == nil)
        #expect(app.dataVersion > version)
    }

    @Test func confirmingStoresOnlyTheYearOfTheFindingAndLeavesTheOtherYearsAlone() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let app = try await makeApp(in: directory)
        let database = try #require(app.database)
        try await deleteBuiltInRates(of: 2025, in: database)
        let before2024 = try await database.uniformRates(year: 2024)
        #expect(before2024.isEmpty == false)

        try await app.confirmUniformRate(try gfrFinding2025())

        #expect(try await database.uniformRates(year: 2025).count == 31)
        #expect(try await database.uniformRates(year: 2024) == before2024)
    }

    @Test func confirmingAYearThatHasItsRatesStoredRefusesAndChangesNothing() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let app = try await makeApp(in: directory)
        let database = try #require(app.database)
        // The year has a rate typed by hand for dollars.
        let typed = UniformRate(
            year: 2025, currency: .usd, amount: 1, rate: decimal("21.00"), instruction: "", sourceURL: nil,
            confirmedAt: nil, origin: .manual)
        try await database.saveUniformRates([typed], year: 2025)
        let finding = try gfrFinding2025()
        app.pendingUniformRate = finding
        let version = app.dataVersion

        await #expect(throws: UniformRateConfirmationError.alreadyStored(year: 2025)) {
            try await app.confirmUniformRate(finding)
        }

        // What the person typed stays, nothing waits for a table of that year any more, and nothing was written.
        #expect(try await database.uniformRates(year: 2025) == [typed])
        #expect(app.pendingUniformRate == nil)
        #expect(app.dataVersion == version)
        #expect(!app.securityStepRunning)
    }

    @Test func confirmingATableWithNoRateRefusesAndStoresNothing() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let app = try await makeApp(in: directory)
        let database = try #require(app.database)
        try await deleteBuiltInRates(of: 2025, in: database)
        let finding = try gfrFinding2025()
        let empty = GFRFinding(
            year: 2025, instruction: finding.instruction, issueURL: finding.issueURL, pdfURL: finding.pdfURL, rates: [])

        await #expect(throws: UniformRateConfirmationError.emptyTable) {
            try await app.confirmUniformRate(empty)
        }

        #expect(try await database.uniformRates(year: 2025).isEmpty)
        #expect(!app.securityStepRunning)
    }

    @Test func confirmingConvertsThePaymentsOfTheYearAtTheNewRate() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let app = try await makeApp(in: directory)
        let database = try #require(app.database)
        // A dollar invoice paid on 7. 10. 2025 and converted at the ČNB rate of that day, 24,000 Kč, in a year that
        // converts its income with the uniform rate; the rate is not there yet.
        let id = try await database.saveInvoice(paidDollarInvoiceOf2025())
        try await database.updateYearSettings(2025) { $0.incomeFXMethod = .uniform }
        try await deleteBuiltInRates(of: 2025, in: database)

        try await app.confirmUniformRate(try gfrFinding2025())

        // 1 000 USD at 21,84 Kč.
        let payment = try #require(try await database.invoice(id: id)?.payment)
        #expect(payment.conversion == .uniform)
        #expect(payment.rate == storedRate("USD", "21.84", declaredOn: "2025-12-31"))
        #expect(payment.czkNetHalere == 2_184_000)
    }

    @Test func confirmingClearsTheFindingAndTheReminderOfItsYear() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let app = try await makeApp(in: directory)
        try await deleteBuiltInRates(of: 2025, in: try #require(app.database))
        let finding = try gfrFinding2025()
        await app.offerUniformRate(finding)
        try #require(app.refresh).onUniformRateReminder?(2025)

        try await app.confirmUniformRate(finding)

        #expect(app.pendingUniformRate == nil)
        #expect(app.uniformRateReminderYear == nil)
    }

    @Test func confirmingLeavesTheReminderOfAnotherYearAlone() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let app = try await makeApp(in: directory)
        try await deleteBuiltInRates(of: 2025, in: try #require(app.database))
        try #require(app.refresh).onUniformRateReminder?(2026)

        try await app.confirmUniformRate(try gfrFinding2025())

        // A reminder about another year is still true.
        #expect(app.uniformRateReminderYear == 2026)
    }

    @Test(.hangGuard)
    func confirmingTellsTheRefreshWhichThenLooksAtTheCurrentYearInsteadOfTheFinishedOne() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let scheduler = ManualScheduler()
        let app = try await makeApp(in: directory, scheduler: scheduler, startsRefresh: true)
        let refresh = try #require(app.refresh)
        let database = try #require(app.database)
        // The launch run is over when its timer is set.
        await scheduler.untilAWakeIsAsked()
        try await deleteBuiltInRates(of: 2025, in: database)
        await refresh.refresh(.manual)
        #expect(refresh.status.uniformYear == 2025)

        try await app.confirmUniformRate(try gfrFinding2025())

        try await waitUntil { refresh.status.uniformYear == 2026 }
        #expect(
            refresh.status.uniformText == "Jednotný kurz 2026: zatím nevyšel (kontrola od 2.\u{00A0}1.\u{00A0}2027)")
        refresh.stop()
    }

    @Test func confirmingWhileAStepOfTheVaultRunsIsRefusedAndStoresNothing() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let app = try await makeApp(in: directory)
        let database = try #require(app.database)
        try await deleteBuiltInRates(of: 2025, in: database)
        let finding = try gfrFinding2025()
        await app.offerUniformRate(finding)
        let gate = Gate()
        let step = Task { try await app.runSecurityStep { await gate.pass() } }
        await gate.untilARequestWaits()

        await #expect(throws: VaultError.busy) { try await app.confirmUniformRate(finding) }

        #expect(try await database.uniformRates(year: 2025).isEmpty)
        #expect(app.pendingUniformRate == finding)
        await gate.open()
        try await step.value
    }

    @Test func confirmingWhileTheDataIsLockedIsRefused() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let app = try await makeApp(in: directory)
        let finding = try gfrFinding2025()
        app.database = nil

        await #expect(throws: VaultError.locked) { try await app.confirmUniformRate(finding) }

        #expect(app.securityStepRunning == false)
    }

    @Test func ratesThatAreStoredAreNotTakenBackWhenThePaymentsCannotBeConvertedAndTheErrorSaysSo() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let app = try await makeApp(in: directory)
        let database = try #require(app.database)
        let id = try await database.saveInvoice(paidDollarInvoiceOf2025())
        try await database.makeUnreadable(paymentOf: id)
        try await deleteBuiltInRates(of: 2025, in: database)
        let finding = try gfrFinding2025()
        await app.offerUniformRate(finding)

        await #expect(throws: UniformRateConfirmationError.paymentsNotConverted(year: 2025)) {
            try await app.confirmUniformRate(finding)
        }

        #expect(try await database.uniformRates(year: 2025).count == 31)
        #expect(app.pendingUniformRate == nil)
        #expect(app.securityStepRunning == false)
    }

    // MARK: Zadat ručně

    @Test func enteringTheRateByHandOpensTheFormOfNastaveniRokForTheYearOfTheFinding() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let app = try await makeApp(in: directory)
        try await deleteBuiltInRates(of: 2025, in: try #require(app.database))
        let finding = try gfrFinding2025()
        await app.offerUniformRate(finding)
        app.screen = .invoices
        #expect(app.asOf.year == 2026)

        app.enterUniformRateManually(year: finding.year)

        #expect(app.screen == .settings)
        #expect(app.settingsTab == .year)
        #expect(app.asOf.year == 2025)
        #expect(app.settingsAction == .enterUniformRate)
        // The sheet is closed, and the finding still waits: nothing was stored.
        #expect(app.uniformRateOffer == nil)
        #expect(app.pendingUniformRate == finding)
    }

    @Test func theReminderOpensTheYearItIsAbout() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let app = try await makeApp(in: directory)
        app.refresh?.onUniformRateReminder?(2025)

        app.enterUniformRateManually(year: 2025)

        #expect(app.screen == .settings && app.settingsTab == .year)
        #expect(app.asOf.year == 2025)
        #expect(app.settingsAction == .enterUniformRate)
        #expect(app.uniformRateReminderYear == 2025)
    }

    @Test func enteringTheRateByHandOpensTheFormOfTheYearThatIsGivenWhateverWaits() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let app = try await makeApp(in: directory)
        // Neither a finding nor a reminder waits: the year is the person's choice (Zobrazit, a banner of another year).
        #expect(app.pendingUniformRate == nil && app.uniformRateReminderYear == nil)

        app.enterUniformRateManually(year: 2024)

        #expect(app.screen == .settings && app.settingsTab == .year)
        #expect(app.asOf.year == 2024)
        #expect(app.settingsAction == .enterUniformRate)
    }

    @Test func enteringTheRateByHandForTheYearAlreadyShownKeepsTheDayThatWasPicked() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let app = try await makeApp(in: directory)
        app.selectYear(2025)
        app.pickAsOf(civilDate("2025-06-30"))
        app.refresh?.onUniformRateReminder?(2025)

        app.enterUniformRateManually(year: 2025)

        #expect(app.asOf.asOf == civilDate("2025-06-30"))
        #expect(app.screen == .settings)
    }

    // MARK: Rates stored elsewhere

    @Test func ratesStoredByHandClearThePendingFindingAndTheReminderOfTheirYear() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let app = try await makeApp(in: directory)
        try await deleteBuiltInRates(of: 2025, in: try #require(app.database))
        await app.offerUniformRate(try gfrFinding2025())
        try #require(app.refresh).onUniformRateReminder?(2025)

        app.noteUniformRatesStored(forYear: 2025)

        #expect(app.pendingUniformRate == nil)
        #expect(app.uniformRateReminderYear == nil)
    }
}
