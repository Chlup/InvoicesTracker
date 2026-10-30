import Foundation
import Testing
@testable import InvoicesTracker

/// The import from files to the database: the payments the rows get, the rates fetched for them, the one transaction
/// the plan is applied in, and what a second and a third import of changed files do to the data.
@MainActor
struct FakturoidImporterTests {
    // MARK: Helpers

    private static let importTime = date("2026-10-18T08:30:00Z")

    private func makeImporter(_ database: Database, http: StubHTTPClient? = nil) -> FakturoidImporter {
        FakturoidImporter(
            database: database, fetcher: http.map { CNBFetcher(http: $0) }, clock: ManualClock(Self.importTime)
        )
    }

    /// A stand-in for the server of the ČNB with the yearly files of `years`.
    private func cnb(_ years: [Int] = [2026]) throws -> StubHTTPClient {
        var bodies: [URL: Data] = [:]
        for year in years {
            bodies[CNBEndpoints.yearly(year)] = try Data(contentsOf: fixtureURL("cnb_rok_\(year)", "txt"))
        }
        return StubHTTPClient(bodies)
    }

    private func sampleURL(_ name: String = "fakturoid_sample") throws -> URL {
        try fixtureURL(name, "csv")
    }

    private func importFiles(_ importer: FakturoidImporter, _ urls: [URL]) async throws -> ImportSummary {
        try await importer.importFiles(urls) { _ in }
    }

    private func invoice(
        _ digits: String, _ currency: CurrencyCode = .czk, in database: Database
    ) async throws -> Invoice {
        try #require(try await database.invoice(numberDigits: digits, currency: currency))
    }

    private func allInvoices(_ database: Database) async throws -> [Invoice] {
        try await database.allInvoices()
    }

    /// An export of `rows` written to a file in `directory`.
    private func file(_ rows: [FakturoidCSV.Row], named name: String = "export.csv", in directory: URL) throws -> URL {
        try writeCSV(FakturoidCSV.text(rows), named: name, in: directory)
    }

    /// Caches the rates of 2025 for dollars and euros, so that these currencies are known and no rate of 2026 is.
    private func cacheRatesOf2025(in database: Database) async throws {
        let rows = try cnbYearlyRows([2025]).filter { $0.currency == .usd || $0.currency == .eur }
        try await database.insertCNBRates(rows)
    }

    /// A paid invoice in dollars for Beta, received on `paid`.
    private func dollarRow(_ number: String, paid: String, subtotal: String = "1000,0") -> FakturoidCSV.Row {
        FakturoidCSV.row([
            "Id": number, "Number": number, "Client name": "Beta Labs, Inc.", "Client registration no": "",
            "Client vat no": "", "Client country": "US", "Currency": "USD", "Exchange rate": "20.7", "Vat": "0.0",
            "Status": "paid", "Issued on": "2025-12-15", "Taxable fulfillment due": "2025-12-15", "Paid on": paid,
            "Subtotal": subtotal, "Total": subtotal, "Language": "en",
        ])
    }

    // MARK: The first import

    @Test func theFirstImportAddsTheInvoicesWithTheirPaymentsAndClients() async throws {
        let (database, directory) = try makeDatabase()
        defer { removeTemporaryDirectory(directory) }
        let http = try cnb()
        var progress: [ImportProgress] = []

        let summary = try await makeImporter(database, http: http)
            .importFiles([try sampleURL()]) { progress.append($0) }

        // The one file has 13 rows.
        #expect(progress == [ImportProgress(rowCounts: [13], fileCount: 1)])
        #expect(summary.files == ["fakturoid_sample.csv"])
        #expect(summary.added == 11 && summary.updated == 0 && summary.unchanged == 0 && summary.skipped == 2)
        #expect(summary.needsReview == 4 && summary.reviewItems.count == 4)
        #expect(summary.keptChangedInApp == 0 && summary.conflicts == 0 && summary.flaggedCancelled == 0)
        #expect(summary.newClients == 4 && summary.filledClients == 0)
        #expect(try await database.invoiceCount() == 11)
        #expect(
            try await database.clients().map(\.name)
                == ["Alfa Systems s.r.o.", "Beta Labs, Inc.", "delta S.R.O.", "Gamma GmbH"])
        // The only request was for the yearly file of 2026, once.
        #expect(http.requests == [CNBEndpoints.yearly(2026)])
    }

    @Test func thePaymentsOfTheTwoPaidInvoicesAreConvertedByTheMethodOfTheYear() async throws {
        let (database, directory) = try makeDatabase()
        defer { removeTemporaryDirectory(directory) }
        _ = try await importFiles(makeImporter(database, http: try cnb()), [try sampleURL()])

        let crowns = try await invoice("20260902", in: database)
        let dollars = try await invoice("20260901", .usd, in: database)

        #expect(
            crowns.payment
                == Payment(
                    date: civilDate("2026-10-15"), conversion: .czk, czkNetHalere: 450_000, czkVatHalere: 94_500))
        // 14 350,00 USD at the rate of 2 October 2026, 21,795: 312 758,25 Kč.
        #expect(
            dollars.payment
                == Payment(
                    date: civilDate("2026-10-02"), conversion: .cnbDaily, czkNetHalere: 31_275_825, czkVatHalere: 0,
                    rate: storedRate("USD", "21.795", declaredOn: "2026-10-02")))
        #expect(dollars.invoiceRate == storedRate("USD", "21.359", declaredOn: "2026-09-30"))
        let others = try await allInvoices(database).filter { $0.id != crowns.id && $0.id != dollars.id }
        #expect(others.count == 9 && others.allSatisfy { $0.payment == nil })
    }

    @Test func theImportedPaymentsAreTheIncomeOfTheYearAndTheInvoicesInReviewAreNot() async throws {
        let (database, directory) = try makeDatabase()
        defer { removeTemporaryDirectory(directory) }
        _ = try await importFiles(makeImporter(database, http: try cnb()), [try sampleURL()])
        let crowns = try await invoice("20260902", in: database)
        let dollars = try await invoice("20260901", .usd, in: database)

        let receipts = try await database.receipts(year: 2026)

        #expect(
            receipts == [
                Receipt(
                    day: civilDate("2026-10-02"), czkNetHalere: 31_275_825, czkVatHalere: 0,
                    source: .invoice(dollars.id)),
                Receipt(
                    day: civilDate("2026-10-15"), czkNetHalere: 450_000, czkVatHalere: 94_500,
                    source: .invoice(crowns.id)),
            ])
    }

    @Test func theInvoicesInReviewAreStoredWithTheirReasonsAndNoPayment() async throws {
        let (database, directory) = try makeDatabase()
        defer { removeTemporaryDirectory(directory) }
        _ = try await importFiles(makeImporter(database, http: try cnb()), [try sampleURL()])

        let negative = try await invoice("20261003", in: database)
        let uncollectible = try await invoice("20261004", in: database)
        let noDate = try await invoice("20261005", in: database)
        let unknownCurrency = try await invoice("20261006", CurrencyCode("XYZ")!, in: database)

        #expect(negative.review == ReviewFlag(reason: "záporná částka") && negative.netMinor == -450_000)
        #expect(uncollectible.review == ReviewFlag(reason: "neznámý stav faktury: uncollectible"))
        #expect(noDate.review == ReviewFlag(reason: "zaplaceno bez data platby"))
        #expect(unknownCurrency.review == ReviewFlag(reason: "měna XYZ bez kurzů ČNB"))
        #expect([negative, uncollectible, noDate, unknownCurrency].allSatisfy { $0.payment == nil })
        // The others are not in review.
        #expect(try await allInvoices(database).filter { $0.review != nil }.count == 4)
    }

    @Test func eachInvoiceIsLinkedToItsClientAndKeepsTheDataOfItsOwnRow() async throws {
        let (database, directory) = try makeDatabase()
        defer { removeTemporaryDirectory(directory) }
        _ = try await importFiles(makeImporter(database, http: try cnb()), [try sampleURL()])
        let clients = try await database.clients()
        let delta = try #require(clients.first { $0.dic == "CZ87654321" })
        let alfa = try #require(clients.first { $0.ico == "12345678" })

        let older = try await invoice("20261009", in: database)
        let newer = try await invoice("20261010", in: database)
        let third = try await invoice("20261001", in: database)

        #expect(older.clientID == delta.id && newer.clientID == delta.id)
        #expect(older.client.name == "Delta s.r.o." && older.client.dic == "CZ87654321")
        #expect(newer.client.name == "delta S.R.O." && newer.client.dic.isEmpty)
        #expect(third.clientID == alfa.id && third.number == "2026-10-01")
        #expect(third.client.name == "Alfa Systems, s.r.o.")
        #expect(alfa.phone == "+420 111 222 333" && alfa.origin == .imported && !alfa.editedAfterImport)
    }

    @Test func theImportedInvoicesCanBeFoundBySearch() async throws {
        let (database, directory) = try makeDatabase()
        defer { removeTemporaryDirectory(directory) }
        _ = try await importFiles(makeImporter(database, http: try cnb()), [try sampleURL()])

        let found = try await database.searchInvoiceIDs(
            "delta", scope: .issued, year: 2026, asOf: civilDate("2026-12-31"))

        let older = try await invoice("20261009", in: database)
        let newer = try await invoice("20261010", in: database)
        #expect(found == [older.id, newer.id])
    }

    @Test func theSummaryIsKeptInTheImportLog() async throws {
        let (database, directory) = try makeDatabase()
        defer { removeTemporaryDirectory(directory) }
        let summary = try await importFiles(makeImporter(database, http: try cnb()), [try sampleURL()])

        let log = try #require(try await database.lastImportLog())

        #expect(log.at == Self.importTime)
        #expect(try JSONDecoder().decode(ImportSummary.self, from: log.json) == summary)
    }

    @Test func theSupplierOfTheFirstRowIsReturnedForTheImportScreenToOffer() async throws {
        let (database, directory) = try makeDatabase()
        defer { removeTemporaryDirectory(directory) }

        let summary = try await importFiles(makeImporter(database, http: try cnb()), [try sampleURL()])

        #expect(
            summary.exportSupplier
                == Supplier(
                    name: "Jana Vzorová", street: "Polní 5", postcode: "60200", city: "Brno", country: "CZ",
                    ico: "11223344", dic: "CZ11223344"))
        // It is only offered: nothing is written to the supplier.
        #expect(try await database.supplier() == Supplier())
    }

    @Test func noSupplierIsReturnedWhenTheRowsHaveNoneOfTheirOwn() async throws {
        let (database, directory) = try makeDatabase()
        defer { removeTemporaryDirectory(directory) }
        let blank = ["Your name": "", "Your street": "", "Your city": "", "Your zip": "", "Your country": "",
            "Your registration no": "", "Your vat no": ""]
        let url = try file([FakturoidCSV.row(blank)], in: directory)

        let summary = try await importFiles(makeImporter(database), [url])

        #expect(summary.exportSupplier == nil)
    }

    @Test func theSecondLineOfTheSupplierStreetJoinsTheFirst() async throws {
        let (database, directory) = try makeDatabase()
        defer { removeTemporaryDirectory(directory) }
        let url = try file([FakturoidCSV.row(["Your street": "Polní 5", "Your street2": "budova B"])], in: directory)

        let summary = try await importFiles(makeImporter(database), [url])

        #expect(summary.exportSupplier?.street == "Polní 5, budova B")
    }

    // MARK: A second import of the same file

    @Test func importingTheSameFileAgainChangesNothing() async throws {
        let (database, directory) = try makeDatabase()
        defer { removeTemporaryDirectory(directory) }
        let http = try cnb()
        let importer = makeImporter(database, http: http)
        _ = try await importFiles(importer, [try sampleURL()])
        let invoicesBefore = try await allInvoices(database)
        let clientsBefore = try await database.clients()

        let summary = try await importFiles(importer, [try sampleURL()])

        #expect(summary.added == 0 && summary.updated == 0 && summary.unchanged == 11 && summary.skipped == 2)
        #expect(summary.needsReview == 0 && summary.reviewItems.isEmpty)
        #expect(summary.keptChangedInApp == 0 && summary.conflicts == 0 && summary.flaggedCancelled == 0)
        #expect(summary.newClients == 0 && summary.filledClients == 0)
        #expect(try await allInvoices(database) == invoicesBefore)
        #expect(try await database.clients() == clientsBefore)
        // The rates are cached: nothing is fetched again.
        #expect(http.requests == [CNBEndpoints.yearly(2026)])
    }

    // MARK: A changed export

    @Test func aChangedExportUpdatesWhatWasNotChangedKeepsWhatWasAndFlagsWhatWasCancelled() async throws {
        let (database, directory) = try makeDatabase()
        defer { removeTemporaryDirectory(directory) }
        let importer = makeImporter(database, http: try cnb())
        _ = try await importFiles(importer, [try sampleURL()])
        _ = try await importFiles(importer, [try sampleURL()])

        // In the app, invoice 20260902 is changed, and an invoice of the app takes the number of row 14.
        var edited = try await invoice("20260902", in: database)
        edited.note = "Domluveno telefonicky"
        if case .imported(let id, let fingerprint, _) = edited.source {
            edited.source = .imported(fakturoidID: id, fingerprint: fingerprint, changedInApp: true)
        }
        try await database.saveInvoice(edited)
        var appInvoice = Invoice.fixture(
            number: "20261102", currency: .czk, issued: "2026-11-02", duzp: "2026-11-02", dueDate: "2026-11-17")
        appInvoice.id = try await database.saveInvoice(appInvoice)
        let reimport = try fakturoidFixtureRows("fakturoid_reimport")
        let dollarsBefore = try await invoice("20260901", .usd, in: database)

        let summary = try await importFiles(importer, [try sampleURL("fakturoid_reimport")])

        // Row 3 is updated, row 1 is kept, row 14 is a conflict, row 2 is flagged and rows 4 and 5 are skipped.
        #expect(summary.added == 0 && summary.updated == 1 && summary.unchanged == 8 && summary.skipped == 2)
        #expect(summary.keptChangedInApp == 1)
        #expect(summary.keptItems == ["20260902 — změněno v aplikaci — ponecháno"])
        #expect(summary.conflicts == 1 && summary.conflictItems.count == 1)
        #expect(summary.conflictItems.first?.hasPrefix("20261102 — ") == true)
        #expect(summary.flaggedCancelled == 1 && summary.needsReview == 0)
        #expect(summary.reviewItems == ["20260901 — zrušeno ve Fakturoidu"])
        #expect(summary.newClients == 0 && summary.filledClients == 0)
        // The invoice changed in the app and the invoice made in the app are exactly as they were.
        #expect(try await invoice("20260902", in: database) == edited)
        #expect(try await invoice("20261102", in: database) == appInvoice)
        // The updated invoice has its payment.
        let updated = try await invoice("20261001", in: database)
        #expect(updated.number == "2026-10-01")
        #expect(
            updated.payment
                == Payment(
                    date: civilDate("2026-11-03"), conversion: .czk, czkNetHalere: 450_000, czkVatHalere: 94_500))
        #expect(
            updated.source == .imported(fakturoidID: "5003", fingerprint: reimport[2].fingerprint, changedInApp: false))
        // The cancelled invoice is held for review, keeps its payment, and is not income.
        let flagged = try await invoice("20260901", .usd, in: database)
        #expect(flagged.review == ReviewFlag(reason: "zrušeno ve Fakturoidu"))
        #expect(flagged.payment == dollarsBefore.payment)
        #expect(
            flagged.source == .imported(fakturoidID: "5002", fingerprint: reimport[1].fingerprint, changedInApp: false))
        let receipts = try await database.receipts(year: 2026)
        #expect(!receipts.contains { $0.source == .invoice(flagged.id) })
        #expect(
            receipts.map(\.source) == [.invoice(edited.id), .invoice(updated.id)])
        #expect(receipts.map(\.day) == [civilDate("2026-10-15"), civilDate("2026-11-03")])
    }

    @Test func aChangedRowForAnInvoiceNotChangedInTheAppUpdatesItsAmountsAndPayment() async throws {
        let (database, directory) = try makeDatabase()
        defer { removeTemporaryDirectory(directory) }
        let importer = makeImporter(database, http: try cnb())
        _ = try await importFiles(importer, [try sampleURL()])

        // Row 1 is not changed in the app, so its change in the export (4 600 Kč) is taken.
        let url = try file(
            [
                FakturoidCSV.row([
                    "Id": "5001", "Number": "20260902", "Status": "paid", "Paid on": "2026-10-15",
                    "Issued on": "2026-09-30", "Taxable fulfillment due": "2026-09-30", "Subtotal": "4600,0",
                    "Total": "5566,0", "Vat": "966.0", "Subject": "Vývoj software, září 2026", "Due": "30",
                    "Due on": "2026-10-30", "Client email": "fakturace@alfa.example",
                ])
            ], in: directory)
        let summary = try await importFiles(importer, [url])

        let updated = try await invoice("20260902", in: database)
        #expect(summary.updated == 1 && summary.added == 0 && summary.keptChangedInApp == 0)
        #expect(updated.netMinor == 460_000 && updated.vatMinor == 96_600)
        #expect(
            updated.payment
                == Payment(
                    date: civilDate("2026-10-15"), conversion: .czk, czkNetHalere: 460_000, czkVatHalere: 96_600))
        #expect(updated.id == 1)
    }

    // MARK: Clients

    @Test func anExistingClientIsFilledWhereItIsEmptyAndTheOthersAreCreated() async throws {
        let (database, directory) = try makeDatabase()
        defer { removeTemporaryDirectory(directory) }
        var alfa = SearchFixtures.alfa
        alfa.street = ""
        alfa.phone = "+420 999 000 111"
        alfa.email = "ucetni@example.com"
        alfa.id = try await database.saveClient(alfa)

        let summary = try await importFiles(makeImporter(database, http: try cnb()), [try sampleURL()])

        let clients = try await database.clients()
        let stored = try #require(clients.first { $0.id == alfa.id })
        var expected = alfa
        expected.street = "Náměstí 1"
        #expect(stored == expected)
        #expect(stored.origin == .app && !stored.editedAfterImport)
        #expect(clients.count == 4)
        #expect(summary.newClients == 3 && summary.filledClients == 1)
        #expect(try await invoice("20260902", in: database).clientID == alfa.id)
    }

    @Test func aSecondImportFillsWhatWasEmptiedInAClientAndNothingElse() async throws {
        let (database, directory) = try makeDatabase()
        defer { removeTemporaryDirectory(directory) }
        let importer = makeImporter(database, http: try cnb())
        _ = try await importFiles(importer, [try sampleURL()])
        var alfa = try #require(try await database.clients().first { $0.ico == "12345678" })
        alfa.phone = ""
        alfa.city = ""
        try await database.saveClient(alfa)

        let summary = try await importFiles(importer, [try sampleURL()])

        #expect(summary.filledClients == 1 && summary.newClients == 0 && summary.unchanged == 11)
        let filled = try #require(try await database.clients().first { $0.ico == "12345678" })
        #expect(filled.city == "Příbram" && filled.phone == "+420 111 222 333")
    }

    // MARK: Rates

    @Test func withoutAFetcherAPaymentIsProvisionalAtTheRateOfTheInvoice() async throws {
        let (database, directory) = try makeDatabase()
        defer { removeTemporaryDirectory(directory) }
        // The rates of 2025 are cached, so the currency is known, but not those of the day of the payment.
        try await cacheRatesOf2025(in: database)

        let summary = try await importFiles(makeImporter(database), [try sampleURL()])

        let dollars = try await invoice("20260901", .usd, in: database)
        #expect(summary.needsReview == 4)
        #expect(dollars.review == nil)
        #expect(
            dollars.payment
                == Payment(
                    date: civilDate("2026-10-02"), conversion: .cnbDaily, czkNetHalere: 30_650_165, czkVatHalere: 0,
                    rate: storedRate("USD", "21.359", declaredOn: "2026-09-30"), provisional: true))
        #expect(try await database.provisionalPayments().map(\.number) == ["20260901"])
    }

    @Test func withoutAnyRatesAPaidInvoiceInDollarsIsProvisionalAndNotHeldForReview() async throws {
        let (database, directory) = try makeDatabase()
        defer { removeTemporaryDirectory(directory) }

        // No rates in the database and no way to fetch them: the first import, offline.
        let summary = try await importFiles(makeImporter(database), [try sampleURL()])

        let dollars = try await invoice("20260901", .usd, in: database)
        #expect(dollars.review == nil)
        #expect(
            dollars.payment
                == Payment(
                    date: civilDate("2026-10-02"), conversion: .cnbDaily, czkNetHalere: 30_650_165, czkVatHalere: 0,
                    rate: storedRate("USD", "21.359", declaredOn: "2026-09-30"), provisional: true))
        #expect(try await invoice("20261007", .eur, in: database).review == nil)
        // Only the four rows that are held for review with rates in the database are held without them.
        #expect(summary.needsReview == 4)
        #expect(try await invoice("20260902", in: database).payment != nil)
    }

    @Test func anUnpaidInvoiceInDollarsNeedsNoRatesToBeImportedAsAnyOther() async throws {
        let (database, directory) = try makeDatabase()
        defer { removeTemporaryDirectory(directory) }
        let foreign: FakturoidCSV.Row = [
            "Client name": "Beta Labs, Inc.", "Client registration no": "", "Client vat no": "",
            "Client country": "US", "Vat": "0.0", "Language": "en", "Subtotal": "1000,0", "Total": "1000,0",
        ]
        let url = try file(
            [
                FakturoidCSV.row(
                    foreign.merging(["Id": "1", "Number": "20261001", "Currency": "USD", "Exchange rate": "21.359"]) {
                        $1
                    }),
                FakturoidCSV.row(
                    foreign.merging(["Id": "2", "Number": "20261002", "Currency": "EUR", "Exchange rate": "24.34"]) {
                        $1
                    }),
                FakturoidCSV.row(
                    foreign.merging(["Id": "3", "Number": "20261003", "Currency": "XYZ", "Exchange rate": "1.5"]) {
                        $1
                    }),
            ], in: directory)
        let http = StubHTTPClient()

        // The database has no rates, and there is no fetcher.
        let withoutFetcher = try await importFiles(makeImporter(database), [url])

        #expect(withoutFetcher.added == 3 && withoutFetcher.needsReview == 1)
        #expect(withoutFetcher.reviewItems == ["20261003 — měna XYZ bez kurzů ČNB"])
        let dollars = try await invoice("20261001", .usd, in: database)
        #expect(dollars.review == nil && dollars.payment == nil)
        #expect(dollars.invoiceRate == storedRate("USD", "21.359", declaredOn: "2026-10-01"))
        #expect(try await invoice("20261002", .eur, in: database).review == nil)
        let unknown = try await invoice("20261003", CurrencyCode("XYZ")!, in: database)
        #expect(unknown.review == ReviewFlag(reason: "měna XYZ bez kurzů ČNB"))

        // Nothing is asked for either way: an invoice that is not paid has no day to convert on.
        let again = try await importFiles(makeImporter(database, http: http), [url])
        #expect(again.unchanged == 3 && again.updated == 0 && http.requests.isEmpty)
    }

    @Test(arguments: [
        (HTTPError.offline as any Error, "offline"), (HTTPError.status(503) as any Error, "status 503"),
        (CNBParseError.malformedHeader as any Error, "file not readable"),
        (URLError(.secureConnectionFailed) as any Error, "request failed"),
    ])
    func aFailedDownloadIsLoggedAndNotRepeatedAndTheirPaymentsAreProvisional(
        failure: any Error, message: String
    ) async throws {
        let (database, directory) = try makeDatabase()
        defer { removeTemporaryDirectory(directory) }
        try await cacheRatesOf2025(in: database)
        let http = StubHTTPClient(failures: [CNBEndpoints.yearly(2026): failure])
        let url = try file(
            [
                dollarRow("20260201", paid: "2026-02-03"), dollarRow("20260301", paid: "2026-03-03"),
                dollarRow("20261001", paid: "2026-10-02"),
            ], in: directory)

        let summary = try await importFiles(makeImporter(database, http: http), [url])

        #expect(summary.added == 3 && summary.needsReview == 0)
        #expect(http.requests == [CNBEndpoints.yearly(2026)])
        let payments = try await allInvoices(database).compactMap(\.payment)
        #expect(payments.count == 3 && payments.allSatisfy { $0.provisional })
        let log = try await database.recentFetchLog(limit: 10)
        #expect(log.count == 1)
        #expect(log.first?.kind == .cnbYearly && log.first?.target == "2026" && log.first?.ok == false)
        #expect(log.first?.message == message)
        #expect(log.first?.at == Self.importTime)
    }

    @Test func cancellingTheImportWhileRatesAreFetchedStopsItBeforeAnythingIsChanged() async throws {
        let (database, directory) = try makeDatabase()
        defer { removeTemporaryDirectory(directory) }
        let importer = FakturoidImporter(
            database: database, fetcher: CNBFetcher(http: CancellingHTTPClient()), clock: ManualClock(Self.importTime))
        let url = try sampleURL()

        let task = Task { try await importer.importFiles([url]) { _ in } }

        await #expect(throws: CancellationError.self) { _ = try await task.value }
        #expect(try await database.invoiceCount() == 0)
        #expect(try await database.clients().isEmpty)
        #expect(try await database.lastImportLog() == nil)
        #expect(try await database.recentFetchLog(limit: 10).isEmpty)
    }

    @Test func aSuccessfulDownloadIsLogged() async throws {
        let (database, directory) = try makeDatabase()
        defer { removeTemporaryDirectory(directory) }

        _ = try await importFiles(makeImporter(database, http: try cnb()), [try sampleURL()])

        let log = try await database.recentFetchLog(limit: 10)
        #expect(log.count == 1)
        #expect(log.first?.kind == .cnbYearly && log.first?.target == "2026" && log.first?.ok == true)
    }

    @Test func eachYearOfPaymentsIsFetchedOnceWhateverTheNumberOfPayments() async throws {
        let (database, directory) = try makeDatabase()
        defer { removeTemporaryDirectory(directory) }
        let http = try cnb()
        let url = try file(
            [
                dollarRow("20260201", paid: "2026-02-03"), dollarRow("20260301", paid: "2026-03-03"),
                dollarRow("20260401", paid: "2026-04-03"), dollarRow("20261001", paid: "2026-10-02"),
            ], in: directory)

        let summary = try await importFiles(makeImporter(database, http: http), [url])

        #expect(summary.added == 4 && summary.needsReview == 0)
        #expect(http.requests == [CNBEndpoints.yearly(2026)])
        #expect(try await allInvoices(database).compactMap(\.payment).allSatisfy { !$0.provisional })
    }

    @Test func aPaymentInJanuaryAlsoFetchesThePreviousYearForTheLastRateOfThatYear() async throws {
        let (database, directory) = try makeDatabase()
        defer { removeTemporaryDirectory(directory) }
        let http = try cnb([2025, 2026])
        // 1 January 2026 is a holiday: the rate valid on it is the one declared on 31 December 2025, 20,632.
        let url = try file([dollarRow("20251201", paid: "2026-01-01")], in: directory)

        _ = try await importFiles(makeImporter(database, http: http), [url])

        #expect(Set(http.requests) == [CNBEndpoints.yearly(2026), CNBEndpoints.yearly(2025)])
        #expect(http.requests.count == 2)
        let payment = try #require(try await invoice("20251201", .usd, in: database).payment)
        #expect(payment.rate == storedRate("USD", "20.632", declaredOn: "2025-12-31"))
        #expect(payment.czkNetHalere == 2_063_200 && !payment.provisional)
    }

    @Test func aYearOfPaymentsWhoseRatesAreCachedIsNotFetched() async throws {
        let (database, directory) = try makeDatabase()
        defer { removeTemporaryDirectory(directory) }
        try await database.insertCNBRates(try cnbYearlyRows([2026]))
        let http = StubHTTPClient()
        let url = try file([dollarRow("20251201", paid: "2026-10-02")], in: directory)

        _ = try await importFiles(makeImporter(database, http: http), [url])

        #expect(http.requests.isEmpty)
        let payment = try await invoice("20251201", .usd, in: database).payment
        #expect(payment?.rate == storedRate("USD", "21.795", declaredOn: "2026-10-02"))
    }

    @Test func invoicesInCrownsNeedNoRates() async throws {
        let (database, directory) = try makeDatabase()
        defer { removeTemporaryDirectory(directory) }
        let http = StubHTTPClient()
        let url = try file([FakturoidCSV.row(["Status": "paid", "Paid on": "2026-10-15"])], in: directory)

        _ = try await importFiles(makeImporter(database, http: http), [url])

        #expect(http.requests.isEmpty)
        #expect(try await invoice("20261001", in: database).payment?.conversion == .czk)
    }

    @Test func aYearConvertedWithTheUniformRateUsesIt() async throws {
        let (database, directory) = try makeDatabase()
        defer { removeTemporaryDirectory(directory) }
        var settings = YearSettings(year: 2026)
        settings.incomeFXMethod = .uniform
        try await database.saveYearSettings(settings)
        try await database.saveUniformRates(
            [
                UniformRate(
                    year: 2026, currency: .usd, amount: 1, rate: decimal("21.84"), instruction: "GFŘ-D-99",
                    sourceURL: nil, confirmedAt: nil, origin: .manual)
            ], year: 2026)

        _ = try await importFiles(makeImporter(database, http: try cnb()), [try sampleURL()])

        let payment = try #require(try await invoice("20260901", .usd, in: database).payment)
        // 14 350,00 USD at 21,84: 313 404,00 Kč.
        #expect(payment.conversion == .uniform && payment.czkNetHalere == 31_340_400 && !payment.provisional)
        #expect(payment.rate == storedRate("USD", "21.84", declaredOn: "2026-12-31"))
    }

    /// A year chosen to convert at the uniform rate is converted at the ČNB rates of the days until it has the rate:
    /// the payment is one at the rate of its day, and waits for nothing.
    @Test func aYearWithoutItsUniformRateYetIsConvertedAtTheRateOfTheDay() async throws {
        let (database, directory) = try makeDatabase()
        defer { removeTemporaryDirectory(directory) }
        var settings = YearSettings(year: 2026)
        settings.incomeFXMethod = .uniform
        try await database.saveYearSettings(settings)

        _ = try await importFiles(makeImporter(database, http: try cnb()), [try sampleURL()])

        let payment = try #require(try await invoice("20260901", .usd, in: database).payment)
        #expect(payment.conversion == .cnbDaily && !payment.provisional)
        #expect(payment.czkNetHalere == 31_275_825)
        #expect(payment.rate == storedRate("USD", "21.795", declaredOn: "2026-10-02"))
    }

    @Test func aCurrencyWithoutTheUniformRateOfItsYearIsConvertedAtTheRateOfTheDay() async throws {
        let (database, directory) = try makeDatabase()
        defer { removeTemporaryDirectory(directory) }
        var settings = YearSettings(year: 2026)
        settings.incomeFXMethod = .uniform
        try await database.saveYearSettings(settings)
        // The year has the uniform rate of euros only.
        try await database.saveUniformRates(
            [
                UniformRate(
                    year: 2026, currency: .eur, amount: 1, rate: decimal("24.5"), instruction: "GFŘ-D-99",
                    sourceURL: nil, confirmedAt: nil, origin: .manual)
            ], year: 2026)

        _ = try await importFiles(makeImporter(database, http: try cnb()), [try sampleURL()])

        let payment = try #require(try await invoice("20260901", .usd, in: database).payment)
        #expect(payment.conversion == .cnbDaily && !payment.provisional)
        #expect(payment.czkNetHalere == 31_275_825)
    }

    /// The importer says which years it added, changed or took away payments of, so that the app can convert each of
    /// them again by the method it uses after the import: the years of the days a payment has and had.
    @Test func anImportNamesTheYearsWhosePaymentsItChanged() async throws {
        let (database, directory) = try makeDatabase()
        defer { removeTemporaryDirectory(directory) }
        let rates = try cnbYearlyRows([2025, 2026]).filter { $0.currency == .usd }
        try await database.insertCNBRates(rates)
        let importer = makeImporter(database)
        #expect(importer.yearsOfChangedPayments.isEmpty)

        _ = try await importFiles(importer, [try file([dollarRow("20251201", paid: "2026-01-05")], in: directory)])
        #expect(importer.yearsOfChangedPayments == [2026])

        // The same row again changes nothing.
        _ = try await importFiles(importer, [try file([dollarRow("20251201", paid: "2026-01-05")], in: directory)])
        #expect(importer.yearsOfChangedPayments.isEmpty)

        // The payment moved to the year before: both years changed.
        _ = try await importFiles(importer, [try file([dollarRow("20251201", paid: "2025-12-30")], in: directory)])
        #expect(importer.yearsOfChangedPayments == [2025, 2026])
        #expect(try await invoice("20251201", .usd, in: database).payment?.date == civilDate("2025-12-30"))
    }

    @Test func anInvoiceHeldForReviewGetsNoPaymentEvenWhenItsRowSaysPaid() async throws {
        let (database, directory) = try makeDatabase()
        defer { removeTemporaryDirectory(directory) }
        let url = try file(
            [
                FakturoidCSV.row([
                    "Status": "paid", "Paid on": "2026-10-15", "Subtotal": "-4500,0", "Total": "-5445,0",
                    "Vat": "-945.0",
                ])
            ], in: directory)

        _ = try await importFiles(makeImporter(database), [url])

        let held = try await invoice("20261001", in: database)
        #expect(held.review == ReviewFlag(reason: "záporná částka") && held.payment == nil)
    }

    /// More rows than the invoices of one lookup, so that the invoices that are there come in several lookups.
    private static let longExport = ImportQueries.chunkSize * 2 + 100

    @Test func anExportLongerThanOneLookupIsFoundAgainInFullByTheDigitsOfTheNumbers() async throws {
        let (database, directory) = try makeDatabase()
        defer { removeTemporaryDirectory(directory) }
        // Without an Id in the export an invoice can only be found by the digits of its number.
        let rows = (0..<Self.longExport).map { index in
            FakturoidCSV.row(["Id": "", "Number": String(format: "2026%05d", index)])
        }
        let url = try file(rows, in: directory)
        let importer = makeImporter(database)

        let first = try await importFiles(importer, [url])
        let second = try await importFiles(importer, [url])

        #expect(first.added == Self.longExport && first.conflicts == 0 && first.newClients == 1)
        #expect(second.unchanged == Self.longExport && second.added == 0 && second.updated == 0)
        #expect(second.conflicts == 0)
        #expect(try await database.invoiceCount() == Self.longExport)
        #expect(try await database.clients().count == 1)
    }

    @Test func anExportLongerThanOneLookupIsFoundAgainInFullByTheFakturoidIds() async throws {
        let (database, directory) = try makeDatabase()
        defer { removeTemporaryDirectory(directory) }
        let before = (0..<Self.longExport).map { index in
            FakturoidCSV.row(["Id": String(7000 + index), "Number": String(format: "2026%05d", index)])
        }
        // The same invoices under other numbers: only their Ids say that they are there already.
        let renumbered = (0..<Self.longExport).map { index in
            FakturoidCSV.row(["Id": String(7000 + index), "Number": String(format: "2027%05d", index)])
        }
        let importer = makeImporter(database)

        _ = try await importFiles(importer, [try file(before, named: "before.csv", in: directory)])
        let summary = try await importFiles(importer, [try file(renumbered, named: "after.csv", in: directory)])

        #expect(summary.conflicts == Self.longExport && summary.added == 0 && summary.updated == 0)
        #expect(summary.conflictItems.allSatisfy { $0.contains("už importováno pod číslem 2026") })
        #expect(try await database.invoiceCount() == Self.longExport)
    }

    @Test func aNumberWithoutADigitIsImportedInReviewOnceAndFoundAgain() async throws {
        let (database, directory) = try makeDatabase()
        defer { removeTemporaryDirectory(directory) }
        let url = try file(
            [
                FakturoidCSV.row(["Id": "9", "Number": "ABC"]), FakturoidCSV.row(["Id": "10", "Number": "XYZ"]),
                FakturoidCSV.row(["Id": "11", "Number": "20261001"]),
            ], in: directory)
        let importer = makeImporter(database)

        let first = try await importFiles(importer, [url])
        let second = try await importFiles(importer, [url])

        #expect(first.added == 2 && first.needsReview == 1 && first.conflicts == 1)
        #expect(first.reviewItems == ["ABC — číslo bez číslic"])
        #expect(first.conflictItems == ["XYZ — jiná faktura už má číslo bez číslic — nepřidáno"])
        #expect(second.added == 0 && second.updated == 0 && second.unchanged == 2 && second.conflicts == 1)
        let held = try await invoice("", in: database)
        #expect(held.number == "ABC" && held.review == ReviewFlag(reason: "číslo bez číslic"))
        #expect(try await database.invoiceCount() == 2)
    }

    @Test func aNumberWithoutADigitDoesNotStopTheImportWhenTheAppHasSuchAnInvoice() async throws {
        let (database, directory) = try makeDatabase()
        defer { removeTemporaryDirectory(directory) }
        try await database.saveInvoice(Invoice.fixture(number: "ABC"))
        let url = try file(
            [
                FakturoidCSV.row(["Id": "10", "Number": "XYZ"]), FakturoidCSV.row(["Id": "11", "Number": "20261001"]),
            ], in: directory)

        let summary = try await importFiles(makeImporter(database), [url])

        #expect(summary.added == 1 && summary.conflicts == 1)
        #expect(try await database.invoiceCount() == 2)
    }

    // MARK: One transaction

    @Test func aFailureWhileApplyingLeavesNoClientInvoiceOrLogBehind() async throws {
        let (database, directory) = try makeDatabase()
        defer { removeTemporaryDirectory(directory) }
        try await database.execute(
            """
            CREATE TRIGGER refuse_the_last_row BEFORE INSERT ON invoice WHEN NEW.number = '20261010'
            BEGIN SELECT RAISE(ABORT, 'refused'); END
            """
        )

        await #expect(throws: SQLiteError.self) {
            _ = try await importFiles(makeImporter(database, http: try cnb()), [try sampleURL()])
        }

        #expect(try await database.invoiceCount() == 0)
        #expect(try await database.clients().isEmpty)
        #expect(try await database.lastImportLog() == nil)
        #expect(try await database.integer("SELECT count(*) FROM invoice_search") == 0)
    }

    // MARK: Files

    @Test func severalFilesAreOneImportAndEachIsReported() async throws {
        let (database, directory) = try makeDatabase()
        defer { removeTemporaryDirectory(directory) }
        var progress: [ImportProgress] = []

        // The same invoices twice in one import. Rows that are alike are taken once. Where the second file differs, the
        // invoice is held for review (rows 1 and 3), or it is cancelled in the second file and is not added (row 2).
        let summary = try await makeImporter(database, http: try cnb())
            .importFiles([try sampleURL(), try sampleURL("fakturoid_reimport")]) { progress.append($0) }

        // After each file: the rows of every file read so far (13 and 14), and how many files there are.
        #expect(
            progress == [
                ImportProgress(rowCounts: [13], fileCount: 2), ImportProgress(rowCounts: [13, 14], fileCount: 2),
            ])
        #expect(progress.map(\.filesRead) == [1, 2])
        #expect(progress.map(\.rowsRead) == [13, 27])
        #expect(summary.files == ["fakturoid_sample.csv", "fakturoid_reimport.csv"])
        #expect(summary.added == 11 && summary.updated == 0 && summary.unchanged == 0 && summary.conflicts == 0)
        #expect(summary.skipped == 4)
        #expect(summary.needsReview == 6 && summary.flaggedCancelled == 0)
        let held = "v importu vícekrát s různým obsahem — ke kontrole"
        #expect(summary.reviewItems.contains("20260902 — " + held))
        #expect(summary.reviewItems.contains("2026-10-01 — " + held))
        #expect(summary.reviewItems.count == 6)
        #expect(try await database.invoiceCount() == 11)
        #expect(try await database.invoice(numberDigits: "20260901", currency: .usd) == nil)
        #expect(try await database.clients().count == 4)
        // Nothing of it is income: the invoices that differ are held, the one that is cancelled is not there.
        #expect(try await database.receipts(year: 2026).isEmpty)
    }

    /// The older export of an invoice says it is paid, the newer one that it is cancelled.
    private func paidAndCancelledFiles(in directory: URL) throws -> (older: URL, newer: URL) {
        let paid = dollarRow("20260901", paid: "2026-10-02")
        var cancelled = paid
        cancelled["Status"] = "cancelled"
        cancelled["Cancelled at"] = "2026-10-16 09:00:00"
        let older = try file([paid], named: "older.csv", in: directory)
        let newer = try file([cancelled], named: "newer.csv", in: directory)
        return (older, newer)
    }

    @Test(arguments: [false, true])
    func anInvoiceCancelledInOneFileIsNotIncomeWhicheverFileComesFirst(newerFirst: Bool) async throws {
        let (database, directory) = try makeDatabase()
        defer { removeTemporaryDirectory(directory) }
        let files = try paidAndCancelledFiles(in: directory)

        let urls = newerFirst ? [files.newer, files.older] : [files.older, files.newer]

        let summary = try await importFiles(makeImporter(database, http: try cnb()), urls)

        #expect(summary.added == 0 && summary.skipped == 1 && summary.conflicts == 0 && summary.needsReview == 0)
        #expect(summary.reviewItems.isEmpty && summary.conflictItems.isEmpty)
        #expect(try await database.invoiceCount() == 0)
        #expect(try await database.receipts(year: 2026).isEmpty)
    }

    @Test(arguments: [false, true])
    func anImportedInvoiceCancelledInOneFileIsFlaggedWhicheverFileComesFirst(newerFirst: Bool) async throws {
        let (database, directory) = try makeDatabase()
        defer { removeTemporaryDirectory(directory) }
        let files = try paidAndCancelledFiles(in: directory)
        let importer = makeImporter(database, http: try cnb())
        _ = try await importFiles(importer, [files.older])
        #expect(try await database.receipts(year: 2026).count == 1)

        let urls = newerFirst ? [files.newer, files.older] : [files.older, files.newer]

        let summary = try await importFiles(importer, urls)

        #expect(summary.flaggedCancelled == 1 && summary.added == 0 && summary.updated == 0 && summary.conflicts == 0)
        #expect(summary.reviewItems == ["20260901 — zrušeno ve Fakturoidu"])
        let flagged = try await invoice("20260901", .usd, in: database)
        #expect(flagged.review == ReviewFlag(reason: "zrušeno ve Fakturoidu"))
        #expect(try await database.receipts(year: 2026).isEmpty)
    }

    @Test(arguments: [false, true])
    func twoFilesThatDifferOnOneInvoiceHoldItForReviewWithoutAPayment(secondFirst: Bool) async throws {
        let (database, directory) = try makeDatabase()
        defer { removeTemporaryDirectory(directory) }
        let first = try file([dollarRow("20260901", paid: "2026-10-02")], named: "first.csv", in: directory)
        let second = try file(
            [dollarRow("20260901", paid: "2026-10-02", subtotal: "1100,0")], named: "second.csv", in: directory)
        let files = secondFirst ? [second, first] : [first, second]
        let importer = makeImporter(database, http: try cnb())

        let summary = try await importFiles(importer, files)

        #expect(summary.added == 1 && summary.needsReview == 1 && summary.conflicts == 0)
        #expect(summary.reviewItems == ["20260901 — v importu vícekrát s různým obsahem — ke kontrole"])
        let held = try await invoice("20260901", .usd, in: database)
        #expect(held.review == ReviewFlag(reason: "v importu vícekrát s různým obsahem") && held.payment == nil)
        #expect(held.netMinor == (secondFirst ? 110_000 : 100_000))
        #expect(try await database.receipts(year: 2026).isEmpty)
        // The same two files again change nothing and say nothing.
        let again = try await importFiles(importer, files)
        #expect(again.unchanged == 1 && again.added == 0 && again.updated == 0 && again.reviewItems.isEmpty)
        #expect(try await invoice("20260901", .usd, in: database) == held)
    }

    @Test func anInvoiceChangedInTheAppThatIsCancelledInFakturoidKeepsItsFieldsAndPaymentButIsNotIncome() async throws {
        let (database, directory) = try makeDatabase()
        defer { removeTemporaryDirectory(directory) }
        let importer = makeImporter(database, http: try cnb())
        _ = try await importFiles(importer, [try sampleURL()])
        var edited = try await invoice("20260902", in: database)
        edited.note = "Domluveno telefonicky"
        if case .imported(let id, let fingerprint, _) = edited.source {
            edited.source = .imported(fakturoidID: id, fingerprint: fingerprint, changedInApp: true)
        }
        try await database.saveInvoice(edited)
        let cancelled = FakturoidCSV.row([
            "Id": "5001", "Number": "20260902", "Status": "cancelled", "Cancelled at": "2026-10-20 09:00:00",
            "Paid on": "2026-10-15", "Issued on": "2026-09-30", "Taxable fulfillment due": "2026-09-30",
            "Subtotal": "4500,0", "Total": "5445,0", "Vat": "945.0",
        ])
        let url = try file([cancelled], in: directory)
        let cancelledRow = try #require(try FakturoidCSV.rows([cancelled]).first)

        let summary = try await importFiles(importer, [url])

        #expect(summary.flaggedCancelled == 1 && summary.keptChangedInApp == 0 && summary.updated == 0)
        #expect(
            summary.reviewItems == ["20260902 — zrušeno ve Fakturoidu a změněno v aplikaci — ponecháno ke kontrole"])
        let stored = try await invoice("20260902", in: database)
        var expected = edited
        expected.review = ReviewFlag(reason: "zrušeno ve Fakturoidu")
        if case .imported(let id, _, _) = edited.source {
            expected.source = .imported(fakturoidID: id, fingerprint: cancelledRow.fingerprint, changedInApp: true)
        }
        #expect(stored == expected)
        #expect(stored.payment != nil && stored.note == "Domluveno telefonicky")
        #expect(try await database.receipts(year: 2026).allSatisfy { $0.source != .invoice(stored.id) })
        // The same file again says nothing.
        let again = try await importFiles(importer, [url])
        #expect(again.unchanged == 1 && again.flaggedCancelled == 0 && again.reviewItems.isEmpty)
    }

    @Test func aRowWithoutACurrencyIsHeldForReviewAndNotCountedAsCrowns() async throws {
        let (database, directory) = try makeDatabase()
        defer { removeTemporaryDirectory(directory) }
        let url = try file(
            [FakturoidCSV.row(["Currency": "", "Exchange rate": "", "Status": "paid", "Paid on": "2026-10-15"])],
            in: directory)

        let summary = try await importFiles(makeImporter(database), [url])

        #expect(summary.added == 1 && summary.needsReview == 1 && summary.reviewItems == ["20261001 — chybí měna"])
        let held = try await invoice("20261001", CurrencyCode("XXX")!, in: database)
        #expect(held.review == ReviewFlag(reason: "chybí měna") && held.payment == nil)
        #expect(try await database.receipts(year: 2026).isEmpty)
    }

    @Test func aVATThatCannotBeReadHoldsTheInvoiceButAnEmptyOneIsNoVAT() async throws {
        let (database, directory) = try makeDatabase()
        defer { removeTemporaryDirectory(directory) }
        let url = try file(
            [
                FakturoidCSV.row(["Number": "20261001", "Vat": "abc", "Status": "paid", "Paid on": "2026-10-15"]),
                FakturoidCSV.row(["Number": "20261002", "Vat": "", "Status": "paid", "Paid on": "2026-10-16"]),
            ], in: directory)

        let summary = try await importFiles(makeImporter(database), [url])

        #expect(summary.added == 2 && summary.reviewItems == ["20261001 — neplatná nebo příliš velká DPH"])
        let unreadable = try await invoice("20261001", in: database)
        #expect(unreadable.review != nil && unreadable.payment == nil)
        let empty = try await invoice("20261002", in: database)
        #expect(empty.review == nil && empty.vatMode == .none && empty.payment != nil)
    }

    @Test func aPaidInvoiceInDollarsWithoutARateOfItsOwnTakesTheCachedRateOfItsDuzp() async throws {
        let (database, directory) = try makeDatabase()
        defer { removeTemporaryDirectory(directory) }
        var row = dollarRow("20260901", paid: "2026-10-02")
        row["Exchange rate"] = ""
        row["Issued on"] = "2026-09-30"
        row["Taxable fulfillment due"] = "2026-09-30"
        let url = try file([row], in: directory)

        _ = try await importFiles(makeImporter(database, http: try cnb()), [url])

        let invoice = try await invoice("20260901", .usd, in: database)
        #expect(invoice.review == nil)
        #expect(invoice.invoiceRate == storedRate("USD", "21.522", declaredOn: "2026-09-30"))
        // The payment is worked out with the rate of the day of the payment, not with the rate of the invoice.
        #expect(invoice.payment?.rate == storedRate("USD", "21.795", declaredOn: "2026-10-02"))
        #expect(invoice.payment?.provisional == false && invoice.payment?.czkNetHalere == 2_179_500)
    }

    @Test func theRateOfAnInvoiceWithoutOneIsTheLatestRateDeclaredOnOrBeforeTheDuzpNotTheDayOfIssue() async throws {
        let (database, directory) = try makeDatabase()
        defer { removeTemporaryDirectory(directory) }
        var row = dollarRow("20260901", paid: "2026-10-05")
        row["Exchange rate"] = ""
        // The DUZP is a Saturday: the rate is the one declared on the Friday before it, not the one of the issue day.
        row["Issued on"] = "2026-10-05"
        row["Taxable fulfillment due"] = "2026-10-03"
        let url = try file([row], in: directory)

        _ = try await importFiles(makeImporter(database, http: try cnb()), [url])

        let invoice = try await invoice("20260901", .usd, in: database)
        #expect(invoice.review == nil)
        #expect(invoice.invoiceRate == storedRate("USD", "21.795", declaredOn: "2026-10-02"))
    }

    @Test func whenThePaymentRateIsNotThereTheCachedRateOfTheDuzpMakesTheProvisionalPayment() async throws {
        let (database, directory) = try makeDatabase()
        defer { removeTemporaryDirectory(directory) }
        try await cacheRatesOf2025(in: database)
        var row = dollarRow("20260901", paid: "2026-10-02")
        row["Exchange rate"] = ""
        row["Issued on"] = "2026-09-30"
        row["Taxable fulfillment due"] = "2026-09-30"
        let url = try file([row], in: directory)

        // The only rates are those of 2025 and there is no fetcher: the latest rate before the DUZP is the last one of
        // 2025.
        _ = try await importFiles(makeImporter(database), [url])

        let invoice = try await invoice("20260901", .usd, in: database)
        #expect(invoice.review == nil)
        #expect(invoice.invoiceRate == storedRate("USD", "20.632", declaredOn: "2025-12-31"))
        #expect(invoice.payment?.provisional == true && invoice.payment?.czkNetHalere == 2_063_200)
        #expect(invoice.payment?.rate == storedRate("USD", "20.632", declaredOn: "2025-12-31"))
    }

    @Test func aPaidInvoiceInDollarsWithoutAnyRateIsHeldForReviewNotPaidWithNothing() async throws {
        let (database, directory) = try makeDatabase()
        defer { removeTemporaryDirectory(directory) }
        var row = dollarRow("20260901", paid: "2026-10-02")
        row["Exchange rate"] = ""
        let url = try file([row], in: directory)

        // No rates in the database and no fetcher.
        let summary = try await importFiles(makeImporter(database), [url])

        #expect(summary.added == 1 && summary.needsReview == 1)
        #expect(summary.reviewItems == ["20260901 — chybí kurz faktury"])
        let held = try await invoice("20260901", .usd, in: database)
        #expect(held.review == ReviewFlag(reason: "chybí kurz faktury") && held.payment == nil)
        #expect(held.invoiceRate == nil)
        #expect(try await database.receipts(year: 2026).isEmpty)
        #expect(try await database.provisionalPayments().isEmpty)
    }

    @Test func aFileWithAByteOrderMarkAndWindowsLineEndingsIsReadLikeTheSameFile() async throws {
        let (database, directory) = try makeDatabase()
        defer { removeTemporaryDirectory(directory) }
        let text = try String(contentsOf: try sampleURL(), encoding: .utf8)
        let windows = "\u{FEFF}" + text.replacingOccurrences(of: "\n", with: "\r\n")
        let url = try writeCSV(windows, named: "windows.csv", in: directory)

        let summary = try await importFiles(makeImporter(database, http: try cnb()), [url])

        #expect(summary.added == 11 && summary.skipped == 2 && summary.needsReview == 4)
        #expect(try await invoice("20261008", in: database).items[0].description == "Konzultace \"říjen\", 2. část")
    }

    @Test func noFilesIsNoImport() async throws {
        let (database, directory) = try makeDatabase()
        defer { removeTemporaryDirectory(directory) }
        var progress: [ImportProgress] = []

        let summary = try await makeImporter(database, http: try cnb()).importFiles([]) { progress.append($0) }

        #expect(summary == ImportSummary())
        #expect(progress.isEmpty)
        #expect(try await database.lastImportLog() == nil)
    }

    @Test func aFileThatIsNoFakturoidExportStopsTheImportBeforeAnythingIsChanged() async throws {
        let (database, directory) = try makeDatabase()
        defer { removeTemporaryDirectory(directory) }
        let other = try writeCSV("Date,Amount\n2026-10-01,5\n", named: "bank.csv", in: directory)
        var progress: [ImportProgress] = []

        let error = await #expect(throws: FileImportError.self) {
            _ = try await makeImporter(database, http: try cnb())
                .importFiles([try sampleURL(), other]) { progress.append($0) }
        }

        #expect(error == FileImportError(file: "bank.csv", reason: .notAFakturoidExport))
        #expect(error?.errorDescription == "bank.csv: Nevypadá to jako export faktur z Fakturoidu.")
        // Only the first file was read when the second one stopped the import.
        #expect(progress == [ImportProgress(rowCounts: [13], fileCount: 2)])
        #expect(try await database.invoiceCount() == 0)
        #expect(try await database.clients().isEmpty)
        #expect(try await database.lastImportLog() == nil)
    }

    @Test func anEmptyFileADamagedFileAndAFileThatIsNotTextAreRefusedWithTheirReasons() async throws {
        let (database, directory) = try makeDatabase()
        defer { removeTemporaryDirectory(directory) }
        let importer = makeImporter(database)
        let empty = try writeCSV("", named: "empty.csv", in: directory)
        let damaged = try writeCSV(FakturoidCSV.headerLine + "\n\"5001,false\n", named: "damaged.csv", in: directory)
        let notText = directory.appending(path: "binary.csv")
        try Data([0xFF, 0xFE, 0x00, 0xC3, 0x28, 0x81]).write(to: notText)
        let missing = directory.appending(path: "missing.csv")

        let emptyError = await #expect(throws: FileImportError.self) { _ = try await importFiles(importer, [empty]) }
        let damagedError = await #expect(throws: FileImportError.self) {
            _ = try await importFiles(importer, [damaged])
        }
        let binaryError = await #expect(throws: FileImportError.self) { _ = try await importFiles(importer, [notText]) }
        let missingError = await #expect(throws: FileImportError.self) {
            _ = try await importFiles(importer, [missing])
        }

        #expect(emptyError == FileImportError(file: "empty.csv", reason: .emptyFile))
        #expect(damagedError == FileImportError(file: "damaged.csv", reason: .damagedFile(line: 2)))
        #expect(binaryError == FileImportError(file: "binary.csv", reason: .unreadableFile))
        #expect(missingError == FileImportError(file: "missing.csv", reason: .unreadableFile))
        #expect(try await database.invoiceCount() == 0)
    }
}

/// A stand-in for the server of the ČNB that cancels the task that asks it, as the system does when a person cancels
/// a request.
private struct CancellingHTTPClient: HTTPClient {
    func get(_ url: URL) async throws -> Data {
        withUnsafeCurrentTask { $0?.cancel() }
        throw URLError(.cancelled)
    }
}
