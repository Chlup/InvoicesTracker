import Foundation
import Testing
@testable import InvoicesTracker

/// The model of Faktury: what it loads for the selected year, scope, status chip and search; when the detail opens and
/// when it closes, also on the arrow keys of the table; the other-year links; and deleting an invoice with its number
/// typed. The data is the sample year 2026 with invented clients and two invoices of 2025 for Alfa, in a temporary
/// database; the app is as of 17. 10. 2026. In every expected string `\u{00A0}` is the no-break space.
@Suite(.settlesBackups)
@MainActor
struct InvoicesModelTests {
    // MARK: Helpers

    /// The numbers of the sample year, newest first, as the list writes them.
    private let allNumbers = [
        "20261001", "20260902", "20260901", "20260802", "20260801", "20260701", "20260601", "2026-05-01",
        "2026-04-01", "2026-03-01", "2026-02-01", "2026-01-01",
    ]

    /// An app model on a new folder with the sample year stored and two invoices of 2025 for Alfa (20250901 and
    /// 20251001), so that the years to choose from are 2026 and 2025.
    private func makeApp(
        in directory: URL, clock: ManualClock = ManualClock(localNoon(2026, 10, 17))
    ) async throws -> AppModel {
        let app = makeAppModel(in: directory, clock: clock)
        try await startFresh(app)
        let database = try #require(app.database)
        try await SampleYear2026.store(in: database)
        try await database.saveInvoice(SearchFixtures.earlierCrownInvoice())
        var second = SearchFixtures.earlierCrownInvoice()
        second.number = "20251001"
        second.issueDate = civilDate("2025-10-31")
        second.duzp = civilDate("2025-10-31")
        second.dueDate = civilDate("2025-11-14")
        second.payment = .fixture(on: "2025-11-10")
        try await database.saveInvoice(second)
        await app.didWriteAndBackUp()
        return app
    }

    /// A model of `app` that has loaded, on the screen Faktury (a banner belongs to the screen that is shown).
    private func loadedModel(of app: AppModel) async -> InvoicesModel {
        app.screen = .invoices
        let model = InvoicesModel(app: app)
        await model.load()
        return model
    }

    private func numbers(of model: InvoicesModel) -> [String] {
        model.data?.rows.map(\.number) ?? []
    }

    // MARK: What the list loads

    @Test func theListOfTheYearHasTheTwelveInvoicesOfTheSample() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let app = try await makeApp(in: directory)
        let model = InvoicesModel(app: app)
        #expect(model.data == nil)
        #expect(model.scope == .issued)
        #expect(model.filter == .all)

        await model.load()

        let data = try #require(model.data)
        #expect(data.rows.count == 12)
        #expect(numbers(of: model) == allNumbers)
        #expect(data.chipCounts[.all] == 12)
        #expect(data.chipCounts[.paid] == 11)
        #expect(data.chipCounts[.drafts] == 1)
        #expect(data.visibleChips == [.all, .drafts, .awaiting, .overdue, .paid])
        #expect(data.countTile.value == "12")
        #expect(data.countTile.subtitle == "vystavené v roce 2026 · všechny stavy")
        #expect(data.searchLine == nil)
        #expect(model.errorText == nil)
        // The detail starts closed.
        #expect(model.openInvoiceID == nil)
        #expect(model.openInvoice == nil)
        #expect(model.detail == nil)
    }

    @Test func aPaymentInDollarsShowsTheCrownValueOfTheRateOfTheDay() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let app = try await makeApp(in: directory)

        let model = await loadedModel(of: app)

        let row = try #require(model.data?.rows.first { $0.number == "20260901" })
        #expect(row.client == "Bravo Labs, Inc.")
        #expect(row.net == "14\u{00A0}350,00\u{00A0}USD")
        #expect(row.czk == "305\u{00A0}726,75\u{00A0}Kč")
        #expect(row.czkNote == "ČNB 21,305 · 2.\u{00A0}10.")
        #expect(row.status.label(asOf: civilDate("2026-10-17")) == "Uhrazená 2.\u{00A0}10.")
    }

    @Test func theChipsAndTheScopeChooseTheRows() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let app = try await makeApp(in: directory)
        let model = await loadedModel(of: app)

        model.filter = .drafts
        await model.load()
        #expect(numbers(of: model) == ["20261001"])
        // The counts of the chips are those of the category, whichever chip is chosen.
        #expect(model.data?.chipCounts[.all] == 12)

        model.scope = .paid
        // Another scope starts with every status.
        #expect(model.filter == .all)
        await model.load()
        #expect(model.data?.rows.count == 11)
        #expect(model.data?.countTile.subtitle == "zaplacené v roce 2026 · všechny stavy")
    }

    @Test func aPaymentAfterTheDayShownIsPaidByTodayButIsNotInWhatWasPaidByThatDay() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let app = try await makeApp(in: directory)
        app.pickAsOf(civilDate("2026-06-30"))

        let model = await loadedModel(of: app)

        // The status is as of today, 17. 10., which all eleven payments of the sample have reached.
        #expect(model.data?.chipCounts[.paid] == 11)
        #expect(model.data?.chipCounts[.drafts] == 1)
        // The money is as of the day shown: the payment of 7. 7. has not arrived by 30. 6., the one of 5. 5. has.
        let later = try #require(model.data?.rows.first { $0.number == "20260601" })
        #expect(later.status == .paid(civilDate("2026-07-07")))
        #expect(later.hasReceivedPayment == false)
        let earlier = try #require(model.data?.rows.first { $0.number == "2026-05-01" })
        #expect(earlier.status == .paid(civilDate("2026-05-05")))
        #expect(earlier.hasReceivedPayment)
        // The list of what was paid in the year is money too: the five payments up to 30. 6.
        model.scope = .paid
        await model.load()
        #expect(model.data?.rows.count == 5)
    }

    @Test func anInvoiceThatIsNotPaidIsOverdueByTodayWhateverDayIsShown() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let app = try await makeApp(in: directory)
        let database = try #require(app.database)
        // Due on 14. 10. 2026, which is before today, 17. 10., and after the day shown, 30. 6.
        let id = try await database.saveInvoice(Invoice.fixture(number: "20260930"))
        await app.didWrite()
        app.pickAsOf(civilDate("2026-06-30"))

        let model = await loadedModel(of: app)

        #expect(model.data?.rows.first { $0.id == id }?.status == .overdue)
        #expect(model.data?.chipCounts[.overdue] == 1)
        #expect(model.data?.chipCounts[.awaiting] == 0)
        model.filter = .overdue
        await model.load()
        #expect(model.data?.rows.map(\.id) == [id])
    }

    @Test func theStatusFollowsTodayWhenTheDayChangesWhileAnotherDayIsShown() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let app = try await makeApp(in: directory)
        let database = try #require(app.database)
        // Due today, 17. 10., so it awaits payment.
        let id = try await database.saveInvoice(Invoice.fixture(number: "20260930", dueDate: "2026-10-17"))
        await app.didWrite()
        app.pickAsOf(civilDate("2026-06-30"))
        let model = await loadedModel(of: app)
        #expect(model.data?.rows.first { $0.id == id }?.status == .awaitingPayment)

        // Midnight passes while the app shows 30. 6.
        app.handleDayChanged(civilDate("2026-10-18"))
        await model.load()

        #expect(app.asOf.asOf == civilDate("2026-06-30"))
        #expect(model.data?.rows.first { $0.id == id }?.status == .overdue)
    }

    // MARK: The net income

    /// Writes an income adjustment dated 30. 2. 2025, a day that does not exist, as a change of the data outside the
    /// app could write it. The year 2025 finds it by its dates, so its levies cannot be worked out, and no other year
    /// finds it.
    private nonisolated func storeAnAdjustmentOfADayThatIsNone(in database: Database) async throws {
        try await database.write { connection in
            try connection.run(
                "INSERT INTO income_adjustment(date, amount_halere, description) VALUES (?, ?, ?)",
                [.text("2025-02-30"), .integer(5_000_000), .text("Mimo faktury")])
        }
    }

    /// The prediction sample stored as of 17. 10. 2026 (the figures of its golden table): the payment of 3. 2. is
    /// worth 253 401 Kč after the levies it adds, and the draft is expected, so its net is an estimate. A year the
    /// levies cannot be read for leaves its invoices without a net, and the list still shows them.
    @Test func theRowsOfTheStoredSampleShowTheirNetIncome() async throws {
        try await PredictionSample.withStoredSample { app in
            let model = await loadedModel(of: app)

            let first = try #require(model.data?.rows.first { $0.id == 1 })
            #expect(first.netIncome == "253\u{00A0}401\u{00A0}Kč")
            #expect(first.netIncomeNote == "odvody snížila")
            #expect(first.netIncomeKind == .paid)
            let draft = try #require(model.data?.rows.first { $0.id == 12 })
            #expect(draft.netIncome == "≈\u{00A0}159\u{00A0}636\u{00A0}Kč")
            #expect(draft.netIncomeNote == "odhad")
            #expect(draft.netIncomeKind == .estimate)

            try await storeAnAdjustmentOfADayThatIsNone(in: try #require(app.database))
            app.selectYear(2025)
            await model.load()

            #expect(model.errorText == nil)
            let unreadable = try #require(model.data?.rows.first { $0.id == 25 })
            #expect(unreadable.netIncome == "—")
            #expect(unreadable.netIncomeNote == "")
            #expect(unreadable.netIncomeKind == .none)
        }
    }

    // MARK: The search

    @Test func aSearchKeepsTheMatchesOfTheYearAndLinksTheOtherYears() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let app = try await makeApp(in: directory)
        let model = await loadedModel(of: app)

        app.searchText = "alfa"
        await model.load()

        let data = try #require(model.data)
        #expect(numbers(of: model) == ["2026-05-01", "2026-04-01", "2026-03-01", "2026-02-01", "2026-01-01"])
        // The counts are those of the matches.
        #expect(data.chipCounts[.all] == 5)
        #expect(data.chipCounts[.paid] == 5)
        #expect(data.chipCounts[.drafts] == 0)
        let line = try #require(data.searchLine)
        #expect(line.text == "Hledání „alfa“: 5 z 12 faktur v roce 2026")
        #expect(line.otherYears == [OtherYearMatches(year: 2025, count: 2)])
        #expect(data.countTile.subtitle == "vystavené v roce 2026 · všechny stavy · podle hledání")
    }

    @Test func aSearchWithoutMatchesSaysSoAndPointsToTheOtherYears() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let app = try await makeApp(in: directory)
        let model = await loadedModel(of: app)

        app.searchText = "unicorn"
        await model.load()

        let data = try #require(model.data)
        #expect(data.rows.isEmpty)
        #expect(data.emptyText == "Hledání „unicorn“ tu nic nenašlo.")
    }

    @Test func theLinkToAnotherYearChangesTheYearResetsTheChipAndKeepsTheSearch() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let app = try await makeApp(in: directory)
        let model = await loadedModel(of: app)
        app.searchText = "alfa"
        model.filter = .paid
        await model.load()
        model.click(5)

        model.switchToYear(2025)

        #expect(app.asOf.year == 2025)
        #expect(app.asOf.asOf == civilDate("2025-12-31"))
        #expect(model.filter == .all)
        #expect(app.searchText == "alfa")
        // The detail of an invoice of another year is closed.
        #expect(model.openInvoiceID == nil)
        await model.load()
        #expect(numbers(of: model) == ["20251001", "20250901"])
        #expect(model.data?.searchLine?.text == "Hledání „alfa“: 2 z 2 faktur v roce 2025")
        #expect(model.data?.searchLine?.otherYears == [OtherYearMatches(year: 2026, count: 5)])
    }

    @Test func theScopeIsKeptWhenTheYearChanges() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let app = try await makeApp(in: directory)
        let model = await loadedModel(of: app)
        model.scope = .paid

        model.switchToYear(2025)
        await model.load()

        #expect(model.scope == .paid)
        #expect(numbers(of: model) == ["20251001", "20250901"])
    }

    @Test func zrusitHledaniClearsTheSearchOfTheApp() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let app = try await makeApp(in: directory)
        let model = await loadedModel(of: app)
        app.searchText = "alfa"
        await model.load()
        #expect(model.data?.rows.count == 5)

        model.clearSearch()
        await model.load()

        #expect(app.searchText == "")
        #expect(model.data?.rows.count == 12)
        #expect(model.data?.searchLine == nil)
    }

    @Test func aMatchInAFieldTheTableDoesNotShowComesWithAnExcerptThatMarksIt() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let app = try await makeApp(in: directory)
        let database = try #require(app.database)
        var dollar = try #require(try await database.invoice(id: 10))
        dollar.note = "Platba na účet. Routing number: [ROUTING NUMBER] — nezapomeňte uvést variabilní symbol faktury."
        try await database.saveInvoice(dollar)
        let model = await loadedModel(of: app)

        app.searchText = "routing"
        await model.load()

        let row = try #require(model.data?.rows.first)
        #expect(model.data?.rows.count == 1)
        let excerpt = try #require(row.excerpt)
        // The line says which field the text is from; the match is the part that is marked.
        #expect(excerpt.label == "Poznámka")
        let line = excerpt.attributedLine
        #expect(String(line.characters).hasPrefix("Poznámka: Platba na účet. Routing number"))
        let marked = line.runs.filter { $0.inlinePresentationIntent == .stronglyEmphasized }
            .map { String(line[$0.range].characters) }
        // Both words of the note match "routing", in the case the note writes them; the first place is the excerpt's.
        #expect(marked == ["Routing"])
    }

    @Test func aMatchInAColumnTheTableShowsHasNoExcerpt() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let app = try await makeApp(in: directory)
        let model = await loadedModel(of: app)

        app.searchText = "bravo"
        await model.load()

        #expect(model.data?.rows.count == 5)
        #expect(model.data?.rows.allSatisfy { $0.excerpt == nil } == true)
    }

    // MARK: The detail

    @Test func aClickOnTheSameRowTwiceClosesTheDetail() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let app = try await makeApp(in: directory)
        let model = await loadedModel(of: app)

        model.click(6)
        #expect(model.openInvoiceID == 6)
        await model.load()
        #expect(model.openInvoice?.number == "20260601")
        #expect(model.detail?.number == "20260601")

        model.click(6)
        #expect(model.openInvoiceID == nil)
        #expect(model.openInvoice == nil)
        #expect(model.detail == nil)
    }

    @Test func aClickOnAnotherRowOpensThatInvoice() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let app = try await makeApp(in: directory)
        let model = await loadedModel(of: app)

        model.click(6)
        model.click(7)

        #expect(model.openInvoiceID == 7)
        await model.loadDetail()
        #expect(model.detail?.number == "20260701")
    }

    @Test func theCloseButtonClosesTheDetail() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let app = try await makeApp(in: directory)
        let model = await loadedModel(of: app)
        model.click(6)
        await model.loadDetail()

        model.closeDetail()

        #expect(model.openInvoiceID == nil)
        #expect(model.openInvoice == nil)
        #expect(model.detail == nil)
    }

    @Test func aSearchThatExcludesTheOpenInvoiceClosesTheDetail() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let app = try await makeApp(in: directory)
        let model = await loadedModel(of: app)
        model.click(6)
        await model.load()
        #expect(model.openInvoice?.number == "20260601")

        // Invoice 6 is for Bravo Labs, so it does not match "alfa".
        app.searchText = "alfa"
        await model.load()

        #expect(model.openInvoiceID == nil)
        #expect(model.openInvoice == nil)
        #expect(model.detail == nil)
    }

    @Test func aSearchThatKeepsTheOpenInvoiceKeepsTheDetail() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let app = try await makeApp(in: directory)
        let model = await loadedModel(of: app)
        model.click(6)
        await model.load()

        app.searchText = "bravo"
        await model.load()

        #expect(model.openInvoiceID == 6)
        #expect(model.detail?.number == "20260601")
    }

    @Test func aSearchThatStillMatchesAnInvoiceOutsideTheListKeepsItsDetail() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let app = try await makeApp(in: directory)
        // Invoice 13 was issued in 2025 for Alfa: it is not in the list of what was issued in 2026, but it was opened.
        app.openInvoice(13)
        let model = InvoicesModel(app: app)
        await model.load()
        #expect(model.openInvoiceID == 13)

        app.searchText = "alfa"
        await model.load()

        // The search matches it, although the list of the year does not hold it.
        #expect(model.openInvoiceID == 13)
        #expect(model.detail?.number == "20250901")
        #expect(numbers(of: model).contains("20250901") == false)

        // Clearing the search does not close it either.
        app.searchText = ""
        await model.load()
        #expect(model.openInvoiceID == 13)
    }

    @Test func aSearchThatNoLongerMatchesAnInvoiceOutsideTheListClosesItsDetail() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let app = try await makeApp(in: directory)
        app.openInvoice(13)
        let model = InvoicesModel(app: app)
        await model.load()
        #expect(model.openInvoiceID == 13)

        // Invoice 13 is for Alfa, so it does not match "bravo".
        app.searchText = "bravo"
        await model.load()

        #expect(model.openInvoiceID == nil)
        #expect(model.detail == nil)
    }

    @Test func aChipKeepsTheDetailOnlyWhileTheInvoiceIsStillInTheList() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let app = try await makeApp(in: directory)
        let model = await loadedModel(of: app)
        model.click(6)
        await model.load()

        // Invoice 6 is paid, so the chip of the paid invoices keeps it.
        model.filter = .paid
        await model.load()
        #expect(model.openInvoiceID == 6)

        // It is not a draft: the chip of the drafts takes it out of the list.
        model.filter = .drafts
        await model.load()
        #expect(model.openInvoiceID == nil)
        #expect(model.detail == nil)
    }

    @Test func aScopeKeepsTheDetailOnlyWhileTheInvoiceIsStillInTheList() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let app = try await makeApp(in: directory)
        let model = await loadedModel(of: app)
        // The draft has no payment, so it is not in the list of what was paid in the year.
        model.click(12)
        await model.load()
        #expect(model.openInvoiceID == 12)

        model.scope = .paid
        await model.load()

        #expect(model.openInvoiceID == nil)

        // A paid invoice is in both lists.
        model.click(6)
        await model.load()
        model.scope = .issued
        await model.load()
        #expect(model.openInvoiceID == 6)
    }

    @Test func theChipOfTheInvoicesToCheckGoesBackToAllWhenNoneIsLeft() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let app = try await makeApp(in: directory)
        let database = try #require(app.database)
        var first = Invoice.fixture(number: "Z20260930", review: ReviewFlag(reason: "záporná částka"))
        first.source = .imported(fakturoidID: "F-9", fingerprint: "row-9", changedInApp: false)
        var second = Invoice.fixture(number: "Z20260931", review: ReviewFlag(reason: "záporná částka"))
        second.source = .imported(fakturoidID: "F-10", fingerprint: "row-10", changedInApp: false)
        first.id = try await database.saveInvoice(first)
        second.id = try await database.saveInvoice(second)
        await app.didWrite()
        let model = await loadedModel(of: app)
        model.filter = .review
        await model.load()
        #expect(model.data?.rows.count == 2)

        // One of the two is resolved: the chip has one left.
        first.review = nil
        try await database.saveInvoice(first)
        app.reloadScreens()
        await model.load()
        #expect(model.filter == .review)
        #expect(model.data?.rows.count == 1)

        // The last one is resolved: the chip goes, and the list shows every status again.
        second.review = nil
        try await database.saveInvoice(second)
        app.reloadScreens()
        await model.load()

        #expect(model.filter == .all)
        #expect(model.data?.rows.count == 14)
        #expect(model.data?.visibleChips.contains(.review) == false)
    }

    @Test func aSearchThatFindsNoInvoiceToCheckKeepsTheChipOfTheInvoicesToCheck() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let app = try await makeApp(in: directory)
        let database = try #require(app.database)
        // An invoice for Alfa Systems to check.
        var held = Invoice.fixture(number: "Z20260930", review: ReviewFlag(reason: "záporná částka"))
        held.source = .imported(fakturoidID: "F-9", fingerprint: "row-9", changedInApp: false)
        held.id = try await database.saveInvoice(held)
        await app.didWrite()
        let model = await loadedModel(of: app)
        model.filter = .review
        await model.load()
        #expect(model.data?.rows.map(\.id) == [held.id])

        // A search that finds invoices of Cetus Data, none of them to check: the chip stays, with nothing in it.
        app.searchText = "cetus"
        await model.load()

        #expect(model.filter == .review)
        #expect(model.data?.rows.isEmpty == true)
        #expect(model.data?.visibleChips.contains(.review) == true)

        // Without the search, the invoice to check is there again.
        app.searchText = ""
        await model.load()
        #expect(model.data?.rows.map(\.id) == [held.id])
    }

    @Test func aChipThatHasNothingToShowButIsNotTheOneOfTheInvoicesToCheckStaysChosen() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let app = try await makeApp(in: directory)
        let model = await loadedModel(of: app)

        // The sample has no overdue invoice: the chip says so and stays.
        model.filter = .overdue
        await model.load()

        #expect(model.filter == .overdue)
        #expect(model.data?.rows.isEmpty == true)
    }

    @Test func theDetailOfAnInvoiceThatIsPaidSaysWhatItsPaymentAddedToTheLevies() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let app = try await makeApp(in: directory)
        let model = await loadedModel(of: app)

        // Invoice 11 is the payment of 15. 10. 2026 that adds 1 702 Kč to the levies.
        model.click(11)
        await model.loadDetail()

        let payment = try #require(model.detail?.payment)
        #expect(payment.crowns == "4\u{00A0}500,00\u{00A0}Kč")
        #expect(payment.effect?.heading == "Dopad na odvody 2026")
        #expect(payment.effect?.total == "+1\u{00A0}702\u{00A0}Kč")
        #expect(payment.effect?.rows.map(\.value) == ["+675", "+723", "+304"])
        #expect(model.detail?.estimate == nil)
        #expect(model.detail?.canPay == false)
    }

    @Test func theDetailOfAnInvoiceThatIsNotPaidSaysRoughlyWhatItWouldAdd() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let app = try await makeApp(in: directory)
        let database = try #require(app.database)
        // Invoice 11 is not paid: it is due on 30. 10. 2026, after the day shown.
        var unpaid = try #require(try await database.invoice(id: 11))
        unpaid.payment = nil
        try await database.saveInvoice(unpaid)
        let model = await loadedModel(of: app)

        model.click(11)
        await model.loadDetail()

        #expect(model.detail?.payment == nil)
        #expect(model.detail?.canPay == true)
        // The 4 500,00 Kč it would bring less the 1 702 Kč it would add to the levies leave 2 798 Kč, which is
        // 2 800 Kč in hundreds.
        #expect(
            model.detail?.estimate
                == "Až přijde platba, přibude k odvodům za rok 2026 zhruba 1\u{00A0}700\u{00A0}Kč (37,8\u{00A0}% z příjmu), pokud peníze dorazí do 30.\u{00A0}10.\u{00A0}2026."
                + " Celá platba je nad stropem paušálu (příjmy 2\u{00A0}mil.\u{00A0}Kč), kde je celý další příjem ziskem."
                + " Čistý příjem z ní by byl zhruba 2\u{00A0}800\u{00A0}Kč."
        )
    }

    @Test func theDetailOfADraftInDollarsEstimatesWithTheLatestRateKnown() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let app = try await makeApp(in: directory)
        let model = await loadedModel(of: app)

        // Invoice 12 is a draft of 12 040,00 USD due on 30. 11. 2026. No rate is declared after 16. 10., 21,622.
        model.click(12)
        await model.loadDetail()

        let detail = try #require(model.detail)
        #expect(detail.canPay == false)
        // What the engine says that 260 328,88 Kč received on 30. 11. add to the levies, rounded to hundreds.
        let income = ExchangeRate(currency: .usd, amount: 1, rate: decimal("21.622")).czkHalere(fromMinor: 1_204_000)
        #expect(income == 26_032_888)
        let input = try await app.yearInput(for: 2026).input
        let receipt = Receipt(day: civilDate("2026-11-30"), czkNetHalere: income, czkVatHalere: 0, source: .invoice(12))
        let levies = TaxEngine.effect(of: receipt, in: input).total
        let rounded = (levies + 50) / 100 * 100
        let estimate = try #require(detail.estimate)
        #expect(estimate.hasPrefix("Po vystavení a zaplacení přibude k odvodům za rok 2026 zhruba \(CzechFormat.wholeKc(rounded)) ("))
        // The income less those levies, in whole Kč and then in hundreds, is the last sentence, after the threshold.
        let net = ((income - levies * 100 + 50) / 100 + 50) / 100 * 100
        #expect(
            estimate.hasSuffix(
                "z příjmu), pokud peníze dorazí do 30.\u{00A0}11.\u{00A0}2026."
                    + " Celá platba je nad stropem paušálu (příjmy 2\u{00A0}mil.\u{00A0}Kč), kde je celý další příjem ziskem."
                    + " Čistý příjem z ní by byl zhruba \(CzechFormat.wholeKc(net))."
            ))
        // The rate that would be fixed on it is shown, with a note that the day is not declared yet.
        #expect(detail.facts.last?.label == "Kurz ČNB k DUZP")
        #expect(detail.facts.last?.value == "21,622\u{00A0}Kč/USD → 260\u{00A0}328,88\u{00A0}Kč")
    }

    /// The first invoice of the prediction sample, 220 000,00 Kč paid on 3. 2. 2026, brings the tax bonus: its payment
    /// lowers the levies by 33 401 Kč (the tax by 37 524 Kč, the social insurance rises by 4 123 Kč) and so leaves more
    /// than it is worth, 253 401 Kč. The detail says what it left, and the levies with the minus sign.
    @Test func theDetailOfTheFirstInvoiceSaysWhatItLeftAndThatItLoweredTheLevies() async throws {
        try await PredictionSample.withStoredSample { app in
            let model = await loadedModel(of: app)

            model.click(1)
            await model.loadDetail()

            let payment = try #require(model.detail?.payment)
            #expect(payment.netIncome == "253\u{00A0}401\u{00A0}Kč")
            #expect(payment.effect?.total == "\u{2212}33\u{00A0}401\u{00A0}Kč")
            #expect(payment.effect?.rows.map(\.value) == ["\u{2212}37\u{00A0}524", "+4\u{00A0}123", "+0"])
        }
    }

    /// The draft of the prediction sample, 12 040 USD due on 30. 11. 2026, is worth 256 692,80 Kč at the dollar of
    /// 16. 10., 21,320. It would add 97 057 Kč to the levies and leave 159 635,80 Kč. The note says what it adds to
    /// the levies and, last, what it would leave in hundreds, 159 600 Kč; the list says the same net in whole Kč.
    @Test func theDetailOfTheDraftSaysWhatItWouldLeave() async throws {
        try await PredictionSample.withStoredSample { app in
            let model = await loadedModel(of: app)

            model.click(12)
            await model.loadDetail()

            let estimate = try #require(model.detail?.estimate)
            #expect(
                estimate.hasPrefix(
                    "Po vystavení a zaplacení přibude k odvodům za rok 2026 zhruba 97\u{00A0}100\u{00A0}Kč"
                        + " (37,8\u{00A0}% z příjmu), pokud peníze dorazí do 30.\u{00A0}11.\u{00A0}2026."))
            #expect(estimate.hasSuffix(" Čistý příjem z ní by byl zhruba 159\u{00A0}600\u{00A0}Kč."))
            // The list and the detail work the net out together: the row of the draft says the same figure.
            let row = try #require(model.data?.rows.first { $0.id == 12 })
            #expect(row.netIncome == "≈\u{00A0}159\u{00A0}636\u{00A0}Kč")
        }
    }

    /// An invoice in pounds that is not paid has no rate to be converted at: the sample holds the rates of the ČNB for
    /// the dollar only, and the invoice has none of its own. Its detail says nothing of the levies a payment would add
    /// or of what it would leave, the list shows a dash for it, and the invoice can still be marked paid.
    @Test func theDetailOfAnUnpaidInvoiceInACurrencyWithoutAnyRateHasNoEstimate() async throws {
        try await PredictionSample.withStoredSample { app in
            let database = try #require(app.database)
            let inPounds = Invoice.fixture(
                number: "20261002", currency: CurrencyCode("GBP")!, duzp: "2026-10-15", dueDate: "2026-11-15",
                items: [InvoiceItem(description: "Vývoj", quantity: decimal("10"), unit: "h", unitPriceMinor: 7_000)],
                vatMode: .outsideCountry)
            let id = try await database.saveInvoice(inPounds)
            await app.didWrite()
            let model = await loadedModel(of: app)

            model.click(id)
            await model.loadDetail()

            let detail = try #require(model.detail)
            #expect(detail.invoiceID == id)
            #expect(detail.estimate == nil)
            #expect(detail.payment == nil)
            #expect(detail.canPay == true)
            // The list shows no net for it either, and loads as it does for the others.
            #expect(model.data?.rows.first { $0.id == id }?.netIncome == "—")
        }
    }

    @Test func theDetailOfADraftShowsNoRateWhileTheCacheIsBehind() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let clock = ManualClock(localNoon(2026, 10, 17))
        let app = try await makeApp(in: directory, clock: clock)
        let model = await loadedModel(of: app)
        // A week later nothing newer than 16. 10. has been fetched: the editor would not issue the draft at 21,622, as
        // a rate that old is not the last one declared, so the detail does not show it as the rate of the draft.
        clock.set(localNoon(2026, 10, 23))

        model.click(12)
        await model.loadDetail()

        let fact = try #require(model.detail?.facts.last)
        #expect(fact.label == "Kurz ČNB k DUZP")
        #expect(fact.value == "—")
        #expect(fact.note == "kurz ČNB zatím není k dispozici · při vystavení se zafixuje")
    }

    @Test func theDetailOfADraftDoesNotTakeTheRateFromBeforeAHole() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let app = try await makeApp(in: directory)
        let database = try #require(app.database)
        // The cache holds the dollar rates of 2022, 2025 and 2026 and none of 2023 and 2024.
        try await database.insertCNBRates(try cnbYearlyRows([2022]).filter { $0.currency == .usd })
        let draft = Invoice.fixture(
            number: "20240501", currency: .usd, duzp: "2024-05-31", dueDate: "2024-06-30",
            items: [InvoiceItem(description: "Vývoj", quantity: decimal("10"), unit: "h", unitPriceMinor: 7_000)],
            vatMode: .outsideCountry, status: .draft)
        let id = try await database.saveInvoice(draft)
        let model = await loadedModel(of: app)

        model.openInvoiceID = id
        await model.loadDetail()

        let fact = try #require(model.detail?.facts.last)
        #expect(fact.label == "Kurz ČNB k DUZP")
        #expect(fact.value == "—")
        #expect(fact.note == "kurz ČNB zatím není k dispozici · při vystavení se zafixuje")
    }

    @Test func theDetailOfAnIssuedInvoiceWithoutItsOwnRateDoesNotTakeOneFromBeforeAHoleEither() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let app = try await makeApp(in: directory)
        let database = try #require(app.database)
        try await database.insertCNBRates(try cnbYearlyRows([2022]).filter { $0.currency == .usd })
        var imported = Invoice.fixture(
            number: "Z20240501", currency: .usd, duzp: "2024-05-31", dueDate: "2024-06-30",
            items: [InvoiceItem(description: "Vývoj", quantity: decimal("10"), unit: "h", unitPriceMinor: 7_000)],
            vatMode: .outsideCountry)
        imported.source = .imported(fakturoidID: "F-5", fingerprint: "row-5", changedInApp: false)
        let id = try await database.saveInvoice(imported)
        let model = await loadedModel(of: app)

        model.openInvoiceID = id
        await model.loadDetail()

        let fact = try #require(model.detail?.facts.last)
        #expect(fact.value == "—")
        #expect(fact.note == "kurz ČNB zatím není k dispozici")
    }

    @Test func theDetailOfAnInvoiceToCheckSaysSoAndEstimatesNothing() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let app = try await makeApp(in: directory)
        let database = try #require(app.database)
        var toCheck = Invoice.fixture(number: "Z20260930", review: ReviewFlag(reason: "záporná částka"))
        toCheck.source = .imported(fakturoidID: "F-9", fingerprint: "row-9", changedInApp: false)
        let id = try await database.saveInvoice(toCheck)
        await app.didWrite()
        let model = await loadedModel(of: app)

        model.click(id)
        await model.loadDetail()

        #expect(model.detail?.statusLabel == "Ke kontrole")
        #expect(model.detail?.reviewNote?.hasPrefix("Ke kontrole: záporná částka.") == true)
        #expect(model.detail?.estimate == nil)
        #expect(model.detail?.canPay == true)
    }

    @Test func theDetailStaysOpenWhenTheDataIsLoadedAgain() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let app = try await makeApp(in: directory)
        let model = await loadedModel(of: app)
        // The draft is not in the list of the paid invoices, but it was opened on its own.
        model.scope = .paid
        await model.load()
        model.openInvoiceID = 12
        await model.load()
        #expect(model.openInvoiceID == 12)

        app.reloadScreens()
        await model.load()

        #expect(model.openInvoiceID == 12)
        #expect(model.detail?.number == "20261001")
    }

    @Test func anInvoiceThatAnotherScreenOpensIsShownOnArrivalAndThenForgotten() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let app = try await makeApp(in: directory)
        // Invoice 13 was issued in 2025: it is not in the list of what was issued in 2026, but the detail shows it.
        app.openInvoice(13)
        #expect(app.screen == .invoices)
        #expect(app.pendingDetailInvoiceID == 13)

        let model = InvoicesModel(app: app)
        await model.load()

        #expect(model.openInvoiceID == 13)
        #expect(model.openInvoice?.number == "20250901")
        #expect(model.detail?.number == "20250901")
        #expect(app.pendingDetailInvoiceID == nil)
        #expect(numbers(of: model).contains("20250901") == false)

        // The next load does not open it again once it is closed.
        model.closeDetail()
        await model.load()
        #expect(model.openInvoiceID == nil)
    }

    @Test func theDetailOfAnInvoiceThatWasDeletedMeanwhileIsClosedWhenItsPDFIsAskedFor() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let app = try await makeApp(in: directory)
        let model = await loadedModel(of: app)
        model.click(6)
        await model.load()
        let database = try #require(app.database)
        try await database.deleteInvoice(id: 6)
        #expect(model.openInvoiceID == 6)
        #expect(model.actionFailure == nil)

        let document = try await model.pdfDocument(for: 6)

        #expect(document == nil)
        #expect(model.openInvoiceID == nil)
        #expect(model.detail == nil)
        #expect(model.actionFailure == "Faktura mezitím byla smazána.")
    }

    @Test func theDetailOfAnInvoiceThatWasDeletedMeanwhileIsClosedWhenItsDeletionIsAskedFor() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let app = try await makeApp(in: directory)
        let model = await loadedModel(of: app)
        model.click(6)
        await model.load()
        let database = try #require(app.database)
        try await database.deleteInvoice(id: 6)

        let summary = try await model.deletionSummary(for: 6)

        #expect(summary == nil)
        #expect(model.openInvoiceID == nil)
        #expect(model.actionFailure == "Faktura mezitím byla smazána.")
    }

    @Test func anInvoiceThatIsGoneLeavesAnotherOpenDetailAlone() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let app = try await makeApp(in: directory)
        let model = await loadedModel(of: app)
        model.click(7)
        await model.load()

        // An invoice that never was is asked for: what is open stays, and the screen says what it was asked.
        #expect(try await model.pdfDocument(for: 999) == nil)

        #expect(model.openInvoiceID == 7)
        #expect(model.actionFailure == "Faktura mezitím byla smazána.")
    }

    @Test func theRefusalOfADeletionSaysTheInvoiceMayBeGone() {
        #expect(
            DeleteInvoiceDialog.refusedText
                == "Fakturu se nepodařilo smazat – číslo nesouhlasí nebo faktura už neexistuje.")
    }

    @Test func anInvoiceThatIsDeletedMeanwhileClosesItsDetail() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let app = try await makeApp(in: directory)
        let model = await loadedModel(of: app)
        model.click(6)
        await model.load()
        let database = try #require(app.database)
        try await database.deleteInvoice(id: 6)
        app.reloadScreens()

        await model.load()

        #expect(model.openInvoiceID == nil)
        #expect(model.openInvoice == nil)
        #expect(numbers(of: model).contains("20260601") == false)
    }

    // MARK: The arrow keys

    @Test func theDownArrowOpensTheRowUnderTheOpenOneAndTheUpArrowTheOneAbove() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let app = try await makeApp(in: directory)
        let model = await loadedModel(of: app)
        model.click(6)

        model.moveSelection(by: 1)
        #expect(model.openInvoice?.number == "2026-05-01")
        #expect(model.detail?.number == "2026-05-01")
        model.moveSelection(by: -1)
        model.moveSelection(by: -1)
        #expect(model.openInvoice?.number == "20260701")
    }

    @Test func withNoRowOpenTheDownArrowOpensTheFirstRowAndTheUpArrowTheLast() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let app = try await makeApp(in: directory)
        let model = await loadedModel(of: app)

        model.moveSelection(by: 1)
        #expect(model.openInvoice?.number == allNumbers.first)
        model.closeDetail()
        model.moveSelection(by: -1)
        #expect(model.openInvoice?.number == allNumbers.last)
    }

    @Test func theArrowKeysStopAtTheEndsOfTheList() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let app = try await makeApp(in: directory)
        let model = await loadedModel(of: app)

        model.moveSelection(by: 1)
        model.moveSelection(by: -1)
        #expect(model.openInvoice?.number == allNumbers.first)
        for _ in allNumbers {
            model.moveSelection(by: 1)
        }
        #expect(model.openInvoice?.number == allNumbers.last)
    }

    @Test func fromAnInvoiceOutsideTheListTheDownArrowOpensTheFirstRowAndTheUpArrowTheLast() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let app = try await makeApp(in: directory)
        // Invoice 13 was issued in 2025: it is not in the list of 2026, but another screen opens it.
        app.openInvoice(13)
        let model = await loadedModel(of: app)
        #expect(model.openInvoiceID == 13)

        model.moveSelection(by: 1)
        #expect(model.openInvoice?.number == allNumbers.first)

        app.openInvoice(13)
        await model.load()
        #expect(model.openInvoiceID == 13)
        model.moveSelection(by: -1)
        #expect(model.openInvoice?.number == allNumbers.last)
    }

    @Test func theArrowKeysOpenNothingInAnEmptyList() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let app = try await makeApp(in: directory)
        let model = await loadedModel(of: app)
        app.searchText = "nothing matches this"
        await model.load()
        #expect(model.data?.rows.isEmpty == true)

        model.moveSelection(by: 1)
        model.moveSelection(by: -1)
        #expect(model.openInvoiceID == nil)
    }

    // MARK: Deleting

    @Test func theTypedNumberDeletesTheInvoiceAndSaysSo() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let app = try await makeApp(in: directory)
        let model = await loadedModel(of: app)
        model.click(5)
        await model.load()
        let versionBefore = app.dataVersion

        let deleted = try await model.delete(5, typed: "20260501")

        #expect(deleted)
        #expect(app.banner == AppBanner(text: "Faktura 2026-05-01 byla smazána.", screen: .invoices))
        #expect(app.dataVersion > versionBefore)
        #expect(model.openInvoiceID == nil)
        let database = try #require(app.database)
        #expect(try await database.invoice(id: 5) == nil)
        await model.load()
        #expect(model.data?.rows.count == 11)
        #expect(numbers(of: model).contains("2026-05-01") == false)
    }

    @Test func aWrongNumberDeletesNothing() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let app = try await makeApp(in: directory)
        let model = await loadedModel(of: app)
        let versionBefore = app.dataVersion

        let deleted = try await model.delete(5, typed: "20260502")

        #expect(deleted == false)
        #expect(app.banner == nil)
        #expect(app.dataVersion == versionBefore)
        let database = try #require(app.database)
        #expect(try await database.invoice(id: 5) != nil)
    }

    @Test func deletingAnInvoiceThatIsNotOpenLeavesTheOpenOneAlone() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let app = try await makeApp(in: directory)
        let model = await loadedModel(of: app)
        model.click(6)
        await model.load()

        let deleted = try await model.delete(5, typed: "2026-05-01")

        #expect(deleted)
        #expect(model.openInvoiceID == 6)
    }

    @Test func theConsequencesOfDeletingAPaidInvoiceNameTheLevyDrop() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let app = try await makeApp(in: directory)
        let model = await loadedModel(of: app)

        // Invoice 11 is the payment of 15. 10. 2026 that adds 1 702 Kč to the levies.
        let summary = try #require(try await model.deletionSummary(for: 11))

        #expect(summary.title == "Smazat fakturu 20260902?")
        #expect(summary.number == "20260902")
        #expect(summary.subtitle == "Cetus Data s.r.o. · 5\u{00A0}445,00\u{00A0}Kč")
        #expect(
            summary.lines == [
                "Faktura 20260902 (Cetus Data s.r.o., 5\u{00A0}445,00\u{00A0}Kč) zmizí ze seznamu faktur, z přehledů i z výpočtu odvodů.",
                "Platba z 15.\u{00A0}10.\u{00A0}2026 přestane být příjmem: příjem za rok 2026 klesne o 4\u{00A0}500,00\u{00A0}Kč a odvody o 1\u{00A0}702\u{00A0}Kč.",
                "Pokud jste fakturu poslali odběrateli nebo ji uvedli v přiznání k DPH, zůstane tam – opravte to i tam.",
            ])
    }

    @Test func noConsequencesAreListedForAnInvoiceThatIsGone() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let app = try await makeApp(in: directory)
        let model = await loadedModel(of: app)

        #expect(try await model.deletionSummary(for: 999) == nil)
    }

    // MARK: A load that fails

    @Test func aLoadThatFailsShowsAShortLineInsteadOfTheTable() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let app = try await makeApp(in: directory)
        let model = await loadedModel(of: app)
        #expect(model.data != nil)
        let database = try #require(app.database)
        await database.close()

        await model.load()

        #expect(model.data == nil)
        #expect(model.errorText == "Faktury se nepodařilo načíst.")
    }

    // MARK: The PDF

    @Test func thePdfIsMadeOfTheInvoiceTheSupplierAndTheAccountOfItsCurrency() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let app = try await makeApp(in: directory)
        let database = try #require(app.database)
        let supplier = Supplier(name: "Jan Novák", street: "Ulice 1", postcode: "110 00", city: "Praha", ico: "11111111")
        try await database.saveSupplier(supplier)
        let account = BankAccount(currency: .czk, accountNumber: "123456789/0100", iban: "CZ6501000000000123456789")
        try await database.saveBankAccounts([account])
        let model = await loadedModel(of: app)

        let document = try #require(try await model.pdfDocument(for: 11))

        #expect(document.invoice.number == "20260902")
        #expect(document.supplier == supplier)
        #expect(document.account == account)
        #expect(try await model.pdfDocument(for: 999) == nil)
    }
}
