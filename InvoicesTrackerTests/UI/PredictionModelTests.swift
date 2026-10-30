import Foundation
import Testing
@testable import InvoicesTracker

/// The model of Odhad odvodů: what it loads from the data of an app model — the prediction of the selected year, as of
/// today whatever "K datu" shows — and turns into the page of the screen with the two warnings above it (that the year
/// is an estimate with the rules of another year, and that a payment is converted at a provisional rate), and the
/// choices of months it writes. The data is the prediction sample stored in a temporary database, with the app as of
/// Saturday 17. 10. 2026 unless a test says another day. In the sample Foxtrot's November and December are months the
/// app expects an invoice in by its own choice, and Sierra's October to December are months it does not.
@Suite(.settlesBackups)
@MainActor
struct PredictionModelTests {
    // MARK: Helpers

    private let foxtrot = PredictionSample.foxtrot.id
    private let sierra = PredictionSample.sierra.id

    /// Runs `body` with an app model on a new folder, its clock at noon of 17. 10. 2026 unless given, and the sample
    /// stored in its data.
    private func withSample(
        clock: ManualClock = ManualClock(localNoon(2026, 10, 17)), _ body: (AppModel) async throws -> Void
    ) async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let app = makeAppModel(in: directory, clock: clock)
        try await startFresh(app)
        try await PredictionSample.store(in: app)
        try await body(app)
    }

    /// A model of `app` that has loaded, as the screen loads it.
    private func loadedModel(of app: AppModel) async -> PredictionModel {
        let model = PredictionModel(app: app)
        await model.load()
        return model
    }

    /// The changes stored for 2026: client → month → whether an invoice is expected.
    private func storedChanges(of app: AppModel) async throws -> [Int64: [Int: Bool]] {
        let database = try #require(app.database)
        return try await database.expectedInvoiceMonths(year: 2026)
    }

    /// The page the pure builder makes for the sample's 2026 with `changes`, which is what the model shows once they
    /// are stored.
    private func expectedPage(changes: [Int64: [Int: Bool]] = [:]) throws -> PredictionPage {
        PredictionBuilder.page(
            try PredictionOutcome.make(
                prediction: IncomePrediction.make(PredictionSample.input(year: 2026, changes: changes)),
                yearInput: PredictionSample.yearInput(year: 2026)))
    }

    /// Writes `months` as the text the table keeps the months of 2026 without the health insurance minimum in, which
    /// is how the data is changed outside the app.
    private nonisolated func storeHealthExemptMonths(_ months: String, in database: Database) async throws {
        try await database.write { connection in
            try connection.run("UPDATE year_settings SET health_exempt_months = ? WHERE year = 2026", [.text(months)])
        }
    }

    private func row(_ id: Int64, in model: PredictionModel) throws -> PredictionClientRow {
        let page = try #require(model.page)
        return try #require((page.activeRows + page.otherRows).first { $0.id == id }, "No row of client \(id)")
    }

    private func cell(_ month: Int, of id: Int64, in model: PredictionModel) throws -> PredictionCell {
        try #require(row(id, in: model).cells.first { $0.month == month }, "No cell \(month) of client \(id)")
    }

    // MARK: Loading

    @Test func theModelLoadsThePageOfTheSelectedYear() async throws {
        try await withSample { app in
            let model = PredictionModel(app: app)
            #expect(model.page == nil)
            #expect(model.errorText == nil)

            await model.load()

            let page = try #require(model.page)
            let expected = try expectedPage()
            #expect(page.label == "Odhad odvodů za celý rok 2026")
            #expect(page.hero == "466\u{A0}782\u{A0}Kč")
            #expect(page == expected)
            #expect(model.errorText == nil)
            #expect(model.saveFailure == nil)
        }
    }

    @Test func thePageFollowsTheYearShown() async throws {
        try await withSample { app in
            let model = await loadedModel(of: app)

            app.selectYear(2025)
            await model.load()

            #expect(model.page?.label == "Odvody za rok 2025 – skutečnost")
            #expect(model.page?.hero == "537\u{A0}865\u{A0}Kč")

            app.selectYear(2026)
            await model.load()

            #expect(model.page?.label == "Odhad odvodů za celý rok 2026")
        }
    }

    /// The prediction is made from today's data: moving "K datu" within the year changes nothing of the page, which
    /// still counts the invoices up to today.
    @Test func theModelIgnoresKDatu() async throws {
        try await withSample { app in
            let model = await loadedModel(of: app)
            let atToday = try #require(model.page)

            app.pickAsOf(civilDate("2026-07-15"))
            await model.load()

            #expect(app.asOf.asOf == civilDate("2026-07-15"))
            #expect(app.today == civilDate("2026-10-17"))
            #expect(model.page == atToday)
            #expect(model.page?.banner.hasPrefix("Odhad vychází z faktur do 17.\u{A0}10.\u{A0}2026:") == true)
        }
    }

    @Test func aScreenWhoseDataIsLockedShowsTheLine() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let app = makeAppModel(in: directory)
        let model = PredictionModel(app: app)

        await model.load()

        #expect(model.page == nil)
        #expect(model.errorText == "Odhad odvodů se nepodařilo načíst.")
    }

    /// A load that fails takes the page away with the warnings that stood above it, and a later one that works brings
    /// the page back. On 15. 1. 2027 the page of 2027 has both warnings, as 2027 has no rules of its own and a payment
    /// of January is at a provisional rate, so that the test sees them go. The load that fails is the one of 2026, the
    /// year chosen next.
    @Test func aLoadThatFailsTakesThePageAndItsWarningsAwayAndALaterOneRecovers() async throws {
        try await withSample(clock: ManualClock(localNoon(2027, 1, 15))) { app in
            let database = try #require(app.database)
            try await database.saveInvoiceWithProvisionalPayment(on: "2027-01-10")
            let model = await loadedModel(of: app)
            #expect(model.page != nil)
            #expect(model.rulesWarning != nil)
            #expect(model.provisionalNotice != nil)

            // A month that no form saves.
            app.selectYear(2026)
            try await storeHealthExemptMonths("13", in: database)
            await model.load()

            #expect(model.page == nil)
            #expect(model.rulesWarning == nil)
            #expect(model.provisionalNotice == nil)
            #expect(model.errorText == "Odhad odvodů se nepodařilo načíst.")

            try await storeHealthExemptMonths("", in: database)
            await model.load()

            #expect(model.page != nil)
            #expect(model.errorText == nil)
        }
    }

    /// A reload keeps the page of the last load until its own is there, and loads that overlap end with the result of
    /// the newer one: the first is for 2026, and waits for the data when the year changes and a second load starts.
    @Test func loadsThatOverlapEndWithTheResultOfTheNewerOne() async throws {
        try await withSample { app in
            let model = await loadedModel(of: app)
            let before = model.page

            let reload = Task.immediate { await model.load() }
            #expect(model.page == before)
            await reload.value

            let older = Task.immediate { await model.load() }
            app.selectYear(2025)
            let newer = Task { await model.load() }
            await older.value
            await newer.value

            #expect(model.page?.label == "Odvody za rok 2025 – skutečnost")
        }
    }

    /// The warnings are loaded and dropped with the page, so the newer load decides them too. On 15. 1. 2027 the older
    /// load is for 2027, which has no rules of its own and a payment at a provisional rate, so it has both warnings.
    /// The newer one is for 2026, which has neither. Three drafts of 2027 in other currencies give the older load more
    /// to read, the rates of those currencies, so that it ends last. The page still ends as the newer load made it:
    /// 2026's, without a warning.
    @Test func theWarningsOfLoadsThatOverlapAreThoseOfTheNewerOne() async throws {
        try await withSample(clock: ManualClock(localNoon(2027, 1, 15))) { app in
            let database = try #require(app.database)
            try await database.saveInvoiceWithProvisionalPayment(on: "2027-01-10")
            for (number, code) in [("20270111", "GBP"), ("20270112", "CHF"), ("20270113", "PLN")] {
                try await database.saveInvoice(
                    Invoice.fixture(
                        number: number, currency: CurrencyCode(code)!, issued: "2027-01-12", duzp: "2027-01-12",
                        dueDate: "2027-01-26", status: .draft))
            }
            let model = await loadedModel(of: app)
            #expect(model.rulesWarning != nil)
            #expect(model.provisionalNotice != nil)

            let older = Task.immediate { await model.load() }
            app.selectYear(2026)
            let newer = Task { await model.load() }
            await older.value
            await newer.value

            #expect(model.page?.label == "Odvody za rok 2026 – skutečnost")
            #expect(model.rulesWarning == nil)
            #expect(model.provisionalNotice == nil)
        }
    }

    // MARK: The warnings above the page

    /// 2027 has no tax rules of its own yet, so on 15. 1. 2027 its page is an estimate with the rules of 2026, and says
    /// so. On 17. 10. 2026 the page of 2026, which has rules of its own, has no warning.
    @Test func aYearWithoutItsOwnRulesIsSaidAboveThePage() async throws {
        try await withSample { app in
            let model = await loadedModel(of: app)

            #expect(model.page?.label == "Odhad odvodů za celý rok 2026")
            #expect(model.rulesWarning == nil)
            #expect(model.provisionalNotice == nil)
        }
        try await withSample(clock: ManualClock(localNoon(2027, 1, 15))) { app in
            let model = await loadedModel(of: app)

            #expect(model.page?.label == "Odhad odvodů za celý rok 2027")
            #expect(
                model.rulesWarning
                    == "Pravidla pro rok 2027 zatím nejsou v aplikaci – výpočet je odhad podle roku 2026.")
            #expect(model.provisionalNotice == nil)
        }
    }

    /// The warning is about the page it stands above: 2026, chosen after 2027, has rules of its own and takes it away.
    /// So does the notice of a payment at a provisional rate, which is a payment of 2027 and none of 2026: a load that
    /// succeeds sets it to nil as well.
    @Test func theWarningGoesWithAYearThatHasItsOwnRules() async throws {
        try await withSample(clock: ManualClock(localNoon(2027, 1, 15))) { app in
            let database = try #require(app.database)
            try await database.saveInvoiceWithProvisionalPayment(on: "2027-01-10")
            let model = await loadedModel(of: app)
            #expect(model.rulesWarning == RulesWarning.message(year: 2027, rulesYear: 2026))
            #expect(model.provisionalNotice == RulesWarning.provisionalIncome)

            app.selectYear(2026)
            await model.load()

            #expect(model.page?.label == "Odvody za rok 2026 – skutečnost")
            #expect(model.rulesWarning == nil)
            #expect(model.provisionalNotice == nil)
        }
    }

    /// A payment at a provisional rate is said when it is dated on or before the day of the prediction, which is today
    /// in the year in progress: a payment of tomorrow is not counted by the page, so it is not said. "K datu" does not
    /// matter, as it does not for the page.
    @Test func aPaymentAtAProvisionalRateIsSaidUpToTheDayOfThePrediction() async throws {
        try await withSample { app in
            let database = try #require(app.database)
            #expect(await loadedModel(of: app).provisionalNotice == nil)

            // Today is Saturday 17. 10. 2026.
            try await database.saveInvoiceWithProvisionalPayment(on: "2026-10-18")
            #expect(await loadedModel(of: app).provisionalNotice == nil)

            try await database.saveInvoiceWithProvisionalPayment(on: "2026-10-17")
            let model = await loadedModel(of: app)
            #expect(model.provisionalNotice == RulesWarning.provisionalIncome)
            #expect(model.rulesWarning == nil)

            // "K datu" is on a day before the payment, which the page counts all the same.
            app.pickAsOf(civilDate("2026-07-15"))
            await model.load()
            #expect(model.provisionalNotice == RulesWarning.provisionalIncome)
        }
    }

    /// The page of a year that is over is made as of its 31. 12., so a payment of December is counted and said,
    /// whatever day "K datu" is on. While it is said, the banner of the page, which has rules of its own, no longer
    /// says that nothing is estimated.
    @Test func aProvisionalPaymentOfAPastYearIsSaid() async throws {
        try await withSample { app in
            let database = try #require(app.database)
            app.selectYear(2025)
            let plain = await loadedModel(of: app)
            #expect(plain.provisionalNotice == nil)
            #expect(
                plain.page?.banner
                    == "Rok 2025 skončil: všechny platby jsou známé, nic se neodhaduje."
                    + " Měsíce ukazují, co se kdy vyfakturovalo.")

            try await database.saveInvoiceWithProvisionalPayment(on: "2025-12-15")
            let model = await loadedModel(of: app)
            #expect(model.page?.label == "Odvody za rok 2025 – skutečnost")
            #expect(model.provisionalNotice == RulesWarning.provisionalIncome)
            #expect(model.rulesWarning == nil)
            #expect(
                model.page?.banner
                    == "Rok 2025 skončil: všechny platby jsou známé. Měsíce ukazují, co se kdy vyfakturovalo.")

            app.pickAsOf(civilDate("2025-06-30"))
            await model.load()
            #expect(model.provisionalNotice == RulesWarning.provisionalIncome)
            #expect(
                model.page?.banner
                    == "Rok 2025 skončil: všechny platby jsou známé. Měsíce ukazují, co se kdy vyfakturovalo.")
        }
    }

    /// The two warnings are about different things: a year without rules of its own can have a payment at a
    /// provisional rate, and then the page has both.
    @Test func bothWarningsCanShowTogether() async throws {
        try await withSample(clock: ManualClock(localNoon(2027, 1, 15))) { app in
            let database = try #require(app.database)
            try await database.saveInvoiceWithProvisionalPayment(on: "2027-01-10")

            let model = await loadedModel(of: app)

            #expect(model.page != nil)
            #expect(model.rulesWarning == RulesWarning.message(year: 2027, rulesYear: 2026))
            #expect(model.provisionalNotice == RulesWarning.provisionalIncome)
        }
    }

    // MARK: Changing a month

    /// Foxtrot's November is on by the app's own choice, so switching it off is a change that is stored; the app is
    /// told, and the page is the one for the stored change. Sierra's October is off by the app's own choice, so
    /// switching it on is a change too, and Sierra is active from then on.
    @Test func togglingAMonthStoresItsChange() async throws {
        try await withSample { app in
            let model = await loadedModel(of: app)
            let before = try #require(model.page)
            let key = app.reloadKey
            #expect(try cell(11, of: foxtrot, in: model).isOn)

            await model.toggle(clientID: foxtrot, month: 11)

            #expect(try await storedChanges(of: app) == [foxtrot: [11: false]])
            #expect(app.reloadKey != key)
            let off = try #require(model.page)
            let expectedOff = try expectedPage(changes: [foxtrot: [11: false]])
            #expect(off == expectedOff)
            #expect(off != before)
            #expect(try row(foxtrot, in: model).isEdited)
            #expect(try cell(11, of: foxtrot, in: model).kind == .notExpected)
            #expect(try !cell(11, of: foxtrot, in: model).isOn)
            #expect(model.saveFailure == nil)

            #expect(!(try cell(10, of: sierra, in: model).isOn))
            await model.toggle(clientID: sierra, month: 10)

            #expect(try await storedChanges(of: app) == [foxtrot: [11: false], sierra: [10: true]])
            #expect(try cell(10, of: sierra, in: model).isOn)
            #expect(try cell(10, of: sierra, in: model).kind == .expected)
            #expect(try #require(model.page).activeRows.map(\.id).contains(sierra))
        }
    }

    /// Only a difference from the app's own choice is stored: a month taken back to what the app chooses has its row
    /// deleted, in a month the app expects an invoice in and in one it does not.
    @Test func aMonthClickedBackToTheAppsChoiceStoresNothing() async throws {
        try await withSample { app in
            let model = await loadedModel(of: app)
            let before = try #require(model.page)

            await model.toggle(clientID: foxtrot, month: 11)
            #expect(try await storedChanges(of: app) == [foxtrot: [11: false]])
            await model.toggle(clientID: foxtrot, month: 11)

            #expect(try await storedChanges(of: app).isEmpty)
            #expect(model.page == before)
            #expect(try !row(foxtrot, in: model).isEdited)

            await model.toggle(clientID: sierra, month: 10)
            #expect(try await storedChanges(of: app) == [sierra: [10: true]])
            await model.toggle(clientID: sierra, month: 10)

            #expect(try await storedChanges(of: app).isEmpty)
            #expect(model.page == before)
        }
    }

    /// Two clicks on Foxtrot's November that come together, the second before the first is written. The second would
    /// work from the page loaded before the first, which still has the month on, and write the first one's choice
    /// again. It is ignored instead: one change is stored, the first one's, and the app is told of one write.
    @Test func aSecondToggleWhileTheFirstIsWrittenIsIgnored() async throws {
        try await withSample { app in
            let model = await loadedModel(of: app)
            let version = app.dataVersion

            let first = Task.immediate { await model.toggle(clientID: foxtrot, month: 11) }
            let second = Task.immediate { await model.toggle(clientID: foxtrot, month: 11) }
            await first.value
            await second.value

            let stored = try await storedChanges(of: app)
            #expect(stored == [foxtrot: [11: false]])
            #expect(app.dataVersion == version + 1)
            #expect(try !cell(11, of: foxtrot, in: model).isOn)
            #expect(model.saveFailure == nil)
        }
    }

    /// "Vrátit odhad aplikace" clears the changes of one client and leaves the others' alone.
    @Test func resetClearsAClientsChanges() async throws {
        try await withSample { app in
            let model = await loadedModel(of: app)
            await model.toggle(clientID: foxtrot, month: 11)
            await model.toggle(clientID: foxtrot, month: 12)
            await model.toggle(clientID: sierra, month: 11)
            #expect(try await storedChanges(of: app) == [foxtrot: [11: false, 12: false], sierra: [11: true]])
            let key = app.reloadKey

            await model.reset(clientID: foxtrot)

            #expect(try await storedChanges(of: app) == [sierra: [11: true]])
            #expect(app.reloadKey != key)
            let expectedAfterReset = try expectedPage(changes: [sierra: [11: true]])
            #expect(model.page == expectedAfterReset)
            #expect(try !row(foxtrot, in: model).isEdited)
            #expect(try row(sierra, in: model).isEdited)
        }
    }

    /// A month that has an invoice, a client the page does not have and a model that has not loaded cannot be changed:
    /// nothing is written, and the app is not told.
    @Test func aMonthThatCannotBeChangedChangesNothing() async throws {
        try await withSample { app in
            let unloaded = PredictionModel(app: app)
            let key = app.reloadKey

            await unloaded.toggle(clientID: foxtrot, month: 11)
            await unloaded.reset(clientID: foxtrot)

            let model = await loadedModel(of: app)
            let before = try #require(model.page)
            // June has an invoice, 99 is no client, and 13 is no month.
            await model.toggle(clientID: foxtrot, month: 6)
            await model.toggle(clientID: 99, month: 11)
            await model.toggle(clientID: foxtrot, month: 13)
            await model.reset(clientID: 99)

            #expect(try await storedChanges(of: app).isEmpty)
            #expect(app.reloadKey == key)
            #expect(model.page == before)
            #expect(unloaded.page == nil)
        }
    }

    /// The invoices of no client the app knows are a group on the page like a client, but a choice cannot be stored for
    /// it: tapping a month of it changes nothing, and is not a failure to save.
    @Test func aMonthOfTheInvoicesOfNoKnownClientChangesNothing() async throws {
        try await withSample { app in
            let database = try #require(app.database)
            let invoice = Invoice.fixture(
                number: "20260599", issued: "2026-05-20", dueDate: "2026-06-04",
                payment: Payment.fixture(on: "2026-05-30"))
            try await database.saveInvoice(invoice)
            let model = await loadedModel(of: app)
            let unknown = try row(ClientPrediction.unknownID, in: model)
            #expect(unknown.name == "Neznámý odběratel")
            #expect(unknown.cells[10].kind == .notExpected)
            #expect(!unknown.cells[10].isToggle)
            let before = try #require(model.page)
            let key = app.reloadKey

            await model.toggle(clientID: ClientPrediction.unknownID, month: 11)
            await model.reset(clientID: ClientPrediction.unknownID)

            #expect(try await storedChanges(of: app).isEmpty)
            #expect(model.saveFailure == nil)
            #expect(app.reloadKey == key)
            #expect(model.page == before)
        }
    }

    /// A change that cannot be stored is said, and the page stays as it was. The next one that can be stored takes the
    /// line away.
    @Test func aChangeThatCannotBeStoredIsSaid() async throws {
        try await withSample { app in
            let database = try #require(app.database)
            let model = await loadedModel(of: app)
            let before = try #require(model.page)
            let key = app.reloadKey
            try await setDatabaseReadOnly(true, database)

            await model.toggle(clientID: foxtrot, month: 11)

            #expect(model.saveFailure == "Změnu se nepodařilo uložit.")
            #expect(model.page == before)
            #expect(app.reloadKey == key)

            await model.reset(clientID: foxtrot)

            #expect(model.saveFailure == "Změnu se nepodařilo uložit.")

            try await setDatabaseReadOnly(false, database)
            await model.toggle(clientID: foxtrot, month: 11)

            #expect(model.saveFailure == nil)
            #expect(try await storedChanges(of: app) == [foxtrot: [11: false]])
        }
    }

    // MARK: The folds of the screen

    /// The months section and the group of the other clients start folded, and stay as the person left them while the
    /// app runs: they are the app's, not the screen's.
    @Test func theFoldsOfTheScreenStartFolded() async throws {
        try await withSample { app in
            #expect(!app.predictionMonthsOpen)
            #expect(!app.predictionOthersOpen)

            app.predictionMonthsOpen = true
            app.predictionOthersOpen = true
            let model = await loadedModel(of: app)
            await model.toggle(clientID: foxtrot, month: 11)

            #expect(app.predictionMonthsOpen)
            #expect(app.predictionOthersOpen)
        }
    }
}
