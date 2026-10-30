import Foundation
import Testing
@testable import InvoicesTracker

/// The words of the sheet that asks the person to confirm a uniform rate the app found, and what it does: it says what
/// was found, compares the currencies of the table with those of the year before, and either stores the table
/// ("Použít"), opens the form of Nastavení › Rok ("Zadat ručně") or leaves the finding waiting ("Později"). The finding
/// is the public table of the instruction D-75 for 2025; the data is invented. In every expected string `\u{00A0}` is
/// the no-break space.
@Suite(.settlesBackups)
@MainActor
struct UniformRateConfirmModelTests {
    // MARK: Helpers

    private func makeApp(in directory: URL) async throws -> AppModel {
        let app = makeAppModel(in: directory)
        try await startFresh(app)
        return app
    }

    /// The finding for 2025 without the rates of the currencies in `codes`.
    private func finding2025(without codes: [String] = [], adding extra: [UniformRateEntry] = []) throws -> GFRFinding {
        let finding = try gfrFinding2025()
        let left = finding.rates.filter { !codes.contains($0.currency.code) }
        return GFRFinding(
            year: finding.year, instruction: finding.instruction, issueURL: finding.issueURL, pdfURL: finding.pdfURL,
            rates: left + extra)
    }

    /// A model of the sheet for `finding`, which the app offers, with the rates that ship with the app for its year
    /// taken out, as they are not there for a year that has just been published.
    private func makeModel(
        for finding: GFRFinding, in app: AppModel, deletingRatesOfItsYear: Bool = true
    ) async throws -> UniformRateConfirmModel {
        if deletingRatesOfItsYear {
            try await #require(app.database).execute("DELETE FROM uniform_rate WHERE year = \(finding.year)")
        }
        await app.offerUniformRate(finding)
        let model = UniformRateConfirmModel(app: app, finding: finding)
        await model.load()
        return model
    }

    // MARK: What it says

    @Test func theHeadlineNamesTheYearTheInstructionAndTheRatesOfDollarsAndEuros() throws {
        let finding = try gfrFinding2025()

        #expect(
            UniformRateConfirmText.headline(for: finding)
                == "Vyšel jednotný kurz za rok 2025 (pokyn GFŘ-D-75): 1\u{00A0}USD = 21,84\u{00A0}Kč,"
                + " 1\u{00A0}EUR = 24,66\u{00A0}Kč")
    }

    @Test func theHeadlineLeavesOutTheRateOfACurrencyTheTableDoesNotHave() throws {
        let noEuro = try finding2025(without: ["EUR"])
        let neither = try finding2025(without: ["EUR", "USD"])

        #expect(
            UniformRateConfirmText.headline(for: noEuro)
                == "Vyšel jednotný kurz za rok 2025 (pokyn GFŘ-D-75): 1\u{00A0}USD = 21,84\u{00A0}Kč")
        #expect(UniformRateConfirmText.headline(for: neither) == "Vyšel jednotný kurz za rok 2025 (pokyn GFŘ-D-75)")
    }

    @Test(arguments: [
        (1, "Tabulka má 1\u{00A0}měnu."), (2, "Tabulka má 2\u{00A0}měny."), (31, "Tabulka má 31\u{00A0}měn."),
    ])
    func theTableSaysHowManyCurrenciesItHas(count: Int, text: String) {
        #expect(UniformRateConfirmText.currencyCount(count) == text)
    }

    @Test func aCurrencyOfLastYearThatIsMissingIsWarnedAboutAndANewOneIsNoted() {
        let usd = CurrencyCode.usd
        let eur = CurrencyCode.eur
        let chf = CurrencyCode("CHF")!
        let hrk = CurrencyCode("HRK")!
        let xyz = CurrencyCode("XYZ")!

        let missing = UniformRateConfirmText.differences(
            found: [usd, eur], previous: [usd, eur, chf, hrk], previousYear: 2024)
        let added = UniformRateConfirmText.differences(found: [usd, eur, xyz], previous: [usd, eur], previousYear: 2024)
        let both = UniformRateConfirmText.differences(found: [usd, xyz], previous: [usd, chf], previousYear: 2024)
        let none = UniformRateConfirmText.differences(found: [usd, eur], previous: [eur, usd], previousYear: 2024)

        #expect(
            missing.lines == [
                "Oproti roku 2024 v tabulce chybí: CHF, HRK. Zkontrolujte ji ve Finančním zpravodaji, než ji použijete."
            ])
        #expect(missing.warns)
        #expect(added.lines == ["Nově je v tabulce: XYZ."])
        #expect(!added.warns)
        #expect(
            both.lines == [
                "Oproti roku 2024 v tabulce chybí: CHF. Zkontrolujte ji ve Finančním zpravodaji, než ji použijete.",
                "Nově je v tabulce: XYZ.",
            ])
        #expect(both.warns)
        #expect(none.lines.isEmpty && !none.warns)
    }

    // MARK: The comparison with last year

    @Test func theSheetComparesTheTableWithTheOneOfTheYearBefore() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let app = try await makeApp(in: directory)

        // The table of 2024 that ships with the app has the same 31 currencies as the one of 2025.
        let same = try await makeModel(for: try gfrFinding2025(), in: app)
        // One of them is gone from the table that was read, as a row the reader could not see would leave it.
        let lacking = try await makeModel(for: try finding2025(without: ["CHF"]), in: app)
        let extra = UniformRateEntry(currency: CurrencyCode("XYZ")!, amount: 1, rate: decimal("1.50"))
        let more = try await makeModel(for: try finding2025(adding: [extra]), in: app)

        #expect(same.differenceLines.isEmpty && !same.warnsOfMissingCurrencies)
        #expect(
            lacking.differenceLines == [
                "Oproti roku 2024 v tabulce chybí: CHF. Zkontrolujte ji ve Finančním zpravodaji, než ji použijete."
            ])
        #expect(lacking.warnsOfMissingCurrencies)
        #expect(more.differenceLines == ["Nově je v tabulce: XYZ."] && !more.warnsOfMissingCurrencies)
    }

    @Test func aYearWhoseLastYearHasNoTableHasNothingToCompareWith() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let app = try await makeApp(in: directory)
        let finding = try gfrFinding2025()
        // A year after the ones that ship with the app: the year before it has no rates stored.
        let later = GFRFinding(
            year: 2031, instruction: "GFŘ-D-99", issueURL: finding.issueURL, pdfURL: finding.pdfURL,
            rates: finding.rates)

        let model = try await makeModel(for: later, in: app, deletingRatesOfItsYear: false)

        #expect(model.differenceLines.isEmpty && !model.warnsOfMissingCurrencies)
    }

    // MARK: Použít

    @Test func usingTheTableStoresItClosesTheSheetAndSaysNothingMore() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let app = try await makeApp(in: directory)
        let model = try await makeModel(for: try gfrFinding2025(), in: app)
        #expect(app.uniformRateOffer != nil)

        await model.use()

        #expect(model.failure == nil && !model.isWorking && !model.isSettled)
        #expect(app.uniformRateOffer == nil && app.pendingUniformRate == nil)
        let stored = try await #require(app.database).uniformRates(year: 2025)
        #expect(stored.count == 31 && stored.allSatisfy { $0.origin == .fetched })
    }

    @Test(.hangGuard)
    func usingTheTableWhileAStepOfTheVaultRunsSaysSoAndKeepsTheSheet() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let app = try await makeApp(in: directory)
        let model = try await makeModel(for: try gfrFinding2025(), in: app)
        let gate = Gate()
        let step = Task { try await app.runSecurityStep { await gate.pass() } }
        await gate.untilARequestWaits()

        await model.use()

        #expect(model.failure == "Aplikace ještě dokončuje jiný krok s daty. Zkuste to za chvíli znovu.")
        #expect(app.uniformRateOffer != nil && app.pendingUniformRate != nil)
        #expect(try await #require(app.database).uniformRates(year: 2025).isEmpty)
        await gate.open()
        try await step.value
        // The person tries again once the step is over, and the failure of the first try is gone.
        await model.use()
        #expect(model.failure == nil && app.uniformRateOffer == nil)
    }

    @Test func aTableThatCannotBeStoredIsSaidAndNothingChanges() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let app = try await makeApp(in: directory)
        let model = try await makeModel(for: try gfrFinding2025(), in: app)
        try await #require(app.database).execute(
            "CREATE TRIGGER refuse BEFORE INSERT ON uniform_rate BEGIN SELECT RAISE(ABORT, 'refused'); END")

        await model.use()

        #expect(model.failure == "Kurz se nepodařilo uložit.")
        #expect(app.uniformRateOffer != nil && app.pendingUniformRate != nil && !model.isWorking)
        #expect(try await #require(app.database).uniformRates(year: 2025).isEmpty)
    }

    @Test func aTableWhoseYearGotItsRatesMeanwhileIsNotStoredAndTheSheetOnlySaysSo() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let app = try await makeApp(in: directory)
        let database = try #require(app.database)
        let model = try await makeModel(for: try gfrFinding2025(), in: app)
        // The rates were typed by hand while the sheet was open.
        let typed = UniformRate(
            year: 2025, currency: .usd, amount: 1, rate: decimal("21.00"), instruction: "", sourceURL: nil,
            confirmedAt: nil, origin: .manual)
        try await database.saveUniformRates([typed], year: 2025)

        await model.use()

        #expect(model.failure == "Jednotný kurz za rok 2025 už je uložený.")
        #expect(model.isSettled)
        // What was typed stays, and nothing waits for the table any more.
        #expect(try await database.uniformRates(year: 2025) == [typed])
        #expect(app.pendingUniformRate == nil)
        // The sheet stays, to say so, until Zavřít.
        #expect(app.uniformRateOffer != nil)
        model.later()
        #expect(app.uniformRateOffer == nil)
    }

    @Test func aFailureOfTheStepIsSaidToVoiceOverWhenItComesAndNotBefore() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let app = try await makeApp(in: directory)
        var announced: [String] = []
        app.announce = { announced.append($0) }
        let model = try await makeModel(for: try gfrFinding2025(), in: app)
        try await #require(app.database).execute(
            "CREATE TRIGGER refuse BEFORE INSERT ON uniform_rate BEGIN SELECT RAISE(ABORT, 'refused'); END")
        #expect(announced.isEmpty)

        await model.use()

        #expect(announced == ["Kurz se nepodařilo uložit."])
        // A new try that fails again is told again: it is an answer to what the person just did.
        await model.use()
        #expect(announced == ["Kurz se nepodařilo uložit.", "Kurz se nepodařilo uložit."])
    }

    @Test func ratesThatAreStoredWhosePaymentsCouldNotBeConvertedSayEverythingElseWasDone() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let app = try await makeApp(in: directory)
        let database = try #require(app.database)
        let id = try await database.saveInvoice(paidDollarInvoiceOf2025())
        try await database.makeUnreadable(paymentOf: id)
        let model = try await makeModel(for: try gfrFinding2025(), in: app)

        await model.use()

        #expect(model.failure == "Změna je uložená, platby roku 2025 se ale nepodařilo přepočítat.")
        #expect(model.isSettled)
        // The sheet stays, to say so, until Zavřít; the rates are stored, so nothing waits for them any more.
        #expect(app.uniformRateOffer != nil && app.pendingUniformRate == nil)
        #expect(try await database.uniformRates(year: 2025).count == 31)
        model.later()
        #expect(app.uniformRateOffer == nil)
    }

    // MARK: Zadat ručně and Později

    @Test func enteringTheRateByHandClosesTheSheetAndOpensTheFormOfTheYear() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let app = try await makeApp(in: directory)
        let model = try await makeModel(for: try gfrFinding2025(), in: app)

        model.enterManually()

        #expect(app.uniformRateOffer == nil)
        #expect(app.screen == .settings && app.settingsTab == .year && app.asOf.year == 2025)
        #expect(app.settingsAction == .enterUniformRate)
        #expect(app.pendingUniformRate != nil)
    }

    @Test func puttingTheSheetOffClosesItAndTheFindingStaysPendingForNastaveni() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let app = try await makeApp(in: directory)
        let model = try await makeModel(for: try gfrFinding2025(), in: app)

        model.later()

        #expect(app.uniformRateOffer == nil)
        #expect(app.pendingUniformRate != nil)
        #expect(app.screen == .overview)
        #expect(try await #require(app.database).uniformRates(year: 2025).isEmpty)
    }
}
