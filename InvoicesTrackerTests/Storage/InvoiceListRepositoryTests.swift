import Foundation
import Testing
@testable import InvoicesTracker

/// What the list of Faktury is read from, in one call, and the deletion and the removal of a payment that need the
/// number typed. The data is the sample year 2026 with invented clients, a crown invoice of Alfa from September 2025
/// and the ČNB rates of the fixtures, which end on 16. 10. 2026.
struct InvoiceListRepositoryTests {
    // MARK: Helpers

    private let asOf = civilDate("2026-10-17")

    /// A database with the sample year and one invoice of 2025.
    private func makeSampleDatabase() async throws -> (Database, URL) {
        let (database, directory) = try makeDatabase()
        do {
            try await SampleYear2026.store(in: database)
            try await database.saveInvoice(SearchFixtures.earlierCrownInvoice())
        } catch {
            removeTemporaryDirectory(directory)
            throw error
        }
        return (database, directory)
    }

    /// An invoice in dollars that is issued and not paid: 205 hours at 70,00 USD.
    private func unpaidDollarInvoice(number: String, issued: String, dueDate: String) -> Invoice {
        var invoice = Invoice.fixture(
            number: number, currency: .usd, issued: issued, duzp: issued, dueDate: dueDate,
            items: [InvoiceItem(description: "Software development", quantity: decimal("205"), unit: "h", unitPriceMinor: 7_000)],
            vatMode: .outsideCountry)
        invoice.client = SampleYear2026.bravo
        return invoice
    }

    // MARK: The list of a year

    @Test func theListOfAYearComesWithTheRatesItNeeds() async throws {
        let (database, directory) = try await makeSampleDatabase()
        defer { removeTemporaryDirectory(directory) }
        // Issued on a day the ČNB has declared a rate for, and not paid: it is estimated at the rate of that day.
        let unpaid = unpaidDollarInvoice(number: "20261002", issued: "2026-10-14", dueDate: "2026-11-13")
        let unpaidID = try await database.saveInvoice(unpaid)

        let source = try await database.invoiceListSource(scope: .issued, year: 2026, asOf: asOf, searchText: "")

        // Twelve invoices of the sample year and the one just saved; the one of 2025 is another year.
        #expect(source.invoices.count == 13)
        #expect(source.matchingIDs == nil)
        #expect(source.otherYearCounts.isEmpty)
        // The paid invoices in dollars: the rate of the day the money arrived.
        #expect(Set(source.paymentDayRates.keys) == [6, 7, 9, 10])
        #expect(source.paymentDayRates[10]?.rate == decimal("21.795"))
        #expect(source.paymentDayRates[10]?.currency == .usd)
        // Not paid: the rate of the day of issue. The draft of 31. 10. is after the newest declaration and has none.
        #expect(Set(source.issueDayRates.keys) == [unpaidID])
        #expect(source.issueDayRates[unpaidID]?.rate == decimal("21.754"))
        // The uniform rate of 2026 is not published.
        #expect(source.uniformRates.isEmpty)
    }

    @Test func theUniformRatesAreThoseOfTheYearByCurrency() async throws {
        let (database, directory) = try await makeSampleDatabase()
        defer { removeTemporaryDirectory(directory) }

        let source = try await database.invoiceListSource(
            scope: .issued, year: 2025, asOf: civilDate("2025-12-31"), searchText: "")

        #expect(source.invoices.map(\.number) == ["20250901"])
        #expect(source.uniformRates[.usd]?.rate == decimal("21.84"))
        #expect(source.uniformRates[.usd]?.year == 2025)
    }

    @Test func thePaidListHoldsThePaymentsOfTheYearUpToTheDayShown() async throws {
        let (database, directory) = try await makeSampleDatabase()
        defer { removeTemporaryDirectory(directory) }

        let upToToday = try await database.invoiceListSource(scope: .paid, year: 2026, asOf: asOf, searchText: "")
        // The eleven payments of the sample year; the draft has none.
        #expect(upToToday.invoices.count == 11)

        let upToJune = try await database.invoiceListSource(
            scope: .paid, year: 2026, asOf: civilDate("2026-06-30"), searchText: "")
        #expect(upToJune.invoices.map(\.number).sorted() == ["2026-01-01", "2026-02-01", "2026-03-01", "2026-04-01", "2026-05-01"])
        // Nothing of this list is paid after the day shown, so no rate is looked up for a payment that is not there.
        #expect(upToJune.paymentDayRates.isEmpty)
    }

    // MARK: The search

    @Test func aSearchGivesTheMatchesOfTheScopeAndTheCountsOfEveryYear() async throws {
        let (database, directory) = try await makeSampleDatabase()
        defer { removeTemporaryDirectory(directory) }

        let source = try await database.invoiceListSource(scope: .issued, year: 2026, asOf: asOf, searchText: "alfa")

        // The list is still the year's; the search says which of its invoices are the answer.
        #expect(source.invoices.count == 12)
        #expect(source.matchingIDs == [1, 2, 3, 4, 5])
        #expect(source.otherYearCounts == [2025: 1, 2026: 5])
    }

    @Test func aTextOfNothingButSpacesIsNoSearch() async throws {
        let (database, directory) = try await makeSampleDatabase()
        defer { removeTemporaryDirectory(directory) }

        let source = try await database.invoiceListSource(scope: .issued, year: 2026, asOf: asOf, searchText: "   ")

        #expect(source.matchingIDs == nil)
        #expect(source.otherYearCounts.isEmpty)
    }

    // MARK: Deleting with the number typed

    @Test func theNumberTypedAsItsDigitsDeletesTheInvoiceAndItsSearchRow() async throws {
        let (database, directory) = try await makeSampleDatabase()
        defer { removeTemporaryDirectory(directory) }
        let before = try await database.integer("SELECT count(*) FROM invoice_search")

        let deleted = try await database.deleteInvoice(id: 5, confirmedBy: " 20260501 ")

        #expect(deleted == "2026-05-01")
        #expect(try await database.invoice(id: 5) == nil)
        #expect(try await database.integer("SELECT count(*) FROM invoice_search") == before - 1)
        #expect(try await database.invoice(id: 4) != nil)
    }

    @Test func aWrongNumberDeletesNothing() async throws {
        let (database, directory) = try await makeSampleDatabase()
        defer { removeTemporaryDirectory(directory) }

        #expect(try await database.deleteInvoice(id: 5, confirmedBy: "20260502") == nil)
        #expect(try await database.deleteInvoice(id: 5, confirmedBy: "") == nil)
        #expect(try await database.deleteInvoice(id: 5, confirmedBy: "2026") == nil)
        #expect(try await database.invoice(id: 5) != nil)
    }

    @Test func anInvoiceThatIsNotThereIsNotDeletedAndNotAnError() async throws {
        let (database, directory) = try await makeSampleDatabase()
        defer { removeTemporaryDirectory(directory) }

        #expect(try await database.deleteInvoice(id: 999, confirmedBy: "20260501") == nil)
    }

    // MARK: Removing a payment with the number typed

    /// The payment goes only for the number of the invoice or its digits, and the invoice is issued and unpaid again.
    /// A text that is not the number, an invoice without a payment and an invoice that is not there remove nothing and
    /// write nothing.
    @Test func removingAPaymentNeedsTheInvoiceNumber() async throws {
        let (database, directory) = try await makeSampleDatabase()
        defer { removeTemporaryDirectory(directory) }
        let paid = try #require(try await database.invoice(id: 5))
        #expect(paid.payment != nil)
        let writesBefore = await database.writeCount

        #expect(try await database.removePayment(ofInvoice: 5, confirmedBy: "20260502") == nil)
        #expect(try await database.removePayment(ofInvoice: 5, confirmedBy: "") == nil)
        #expect(try await database.removePayment(ofInvoice: 5, confirmedBy: "2026") == nil)
        #expect(try await database.removePayment(ofInvoice: 999, confirmedBy: "20260501") == nil)
        #expect(await database.writeCount == writesBefore)
        #expect(try await database.invoice(id: 5) == paid)

        // 2026-05-01 typed as its digits: the invoice comes back as it was, with the payment that was removed.
        let removed = try await database.removePayment(ofInvoice: 5, confirmedBy: " 20260501 ")

        #expect(removed == paid)
        #expect(await database.writeCount == writesBefore + 1)
        var unpaid = paid
        unpaid.payment = nil
        #expect(try await database.invoice(id: 5) == unpaid)
        #expect(try await database.invoice(id: 5)?.status == .issued)
        // There is no payment left to remove.
        #expect(try await database.removePayment(ofInvoice: 5, confirmedBy: "2026-05-01") == nil)
        #expect(await database.writeCount == writesBefore + 1)
        // The number as it is written removes a payment too.
        #expect(try await database.removePayment(ofInvoice: 4, confirmedBy: "2026-04-01")?.number == "2026-04-01")
        #expect(try await database.invoice(id: 4)?.payment == nil)
        #expect(try await database.invoice(id: 3)?.payment != nil)
    }

    /// The payment of an invoice imported from Fakturoid is removed as any change made in the app is made: the invoice
    /// is marked as changed in the app, so that the next import of the same export keeps it unpaid.
    @Test func removingThePaymentOfAnImportedInvoiceMarksItChangedInTheApp() async throws {
        let (database, directory) = try await makeSampleDatabase()
        defer { removeTemporaryDirectory(directory) }
        var imported = SearchFixtures.crownInvoice()
        imported.number = "20261003"
        imported.source = .imported(fakturoidID: "F-3", fingerprint: "row-3", changedInApp: false)
        imported.id = try await database.saveInvoice(imported)

        let removed = try await database.removePayment(ofInvoice: imported.id, confirmedBy: "20261003")

        #expect(removed == imported)
        let stored = try #require(try await database.invoice(id: imported.id))
        #expect(stored.payment == nil)
        #expect(stored.source == .imported(fakturoidID: "F-3", fingerprint: "row-3", changedInApp: true))
        #expect(stored.items == imported.items && stored.number == imported.number && stored.status == .issued)
    }

    /// The search document follows the removal at once: the invoice is no longer found as paid, nor by the day of its
    /// payment, and is still found by what it is.
    @Test(arguments: availableSearchIndexKinds)
    func removingAPaymentRebuildsTheSearchDocument(kind: SearchIndexKind) async throws {
        let (database, directory) = try makeDatabase(searchIndex: kind)
        defer { removeTemporaryDirectory(directory) }
        try await SampleYear2026.store(in: database)
        func found(_ query: String) async throws -> Set<Int64> {
            try await database.searchInvoiceIDs(query, scope: .issued, year: 2026, asOf: asOf)
        }
        #expect(try await found("uhrazená").contains(11))
        #expect(try await found("15.10.2026") == [11])

        #expect(try await database.removePayment(ofInvoice: 11, confirmedBy: "20260902") != nil)

        #expect(try await found("uhrazená").contains(11) == false)
        #expect(try await found("uhrazená").count == 10)
        #expect(try await found("15.10.2026").isEmpty)
        #expect(try await found("cetus 20260902") == [11])
        #expect(try await database.integer("SELECT count(*) FROM invoice_search WHERE rowid = 11") == 1)
    }
}

// MARK: - Ten years of invoices

/// With 5 000 invoices over ten years, what the list of Faktury is read from for one year takes under half a second,
/// with and without a search, and so does turning it into rows, chips and tiles; and the list is about that year only.
struct InvoiceListPerformanceTests {
    private let limit = Duration.milliseconds(500)

    @Test(arguments: availableSearchIndexKinds)
    func theListOfOneYearOfTenTakesUnderHalfASecond(kind: SearchIndexKind) async throws {
        let (database, directory) = try makeDatabase(searchIndex: kind)
        defer { removeTemporaryDirectory(directory) }
        let rates = try cnbYearlyRows([2025, 2026]).filter { $0.currency == .usd || $0.currency == .eur }
        try await database.insertCNBRates(rates)
        try await database.insertGeneratedInvoices(years: 2017...2026, perYear: 500)
        try await database.rebuildAllSearchDocuments()
        let asOf = civilDate("2026-10-17")
        let clock = ContinuousClock()

        var start = clock.now
        let source = try await database.invoiceListSource(scope: .issued, year: 2026, asOf: asOf, searchText: "")
        let listTime = clock.now - start

        start = clock.now
        let list = InvoiceListBuilder.build(
            InvoiceListInput(
                year: 2026, asOf: asOf, statusDay: asOf, scope: .issued, filter: .all, invoices: source.invoices,
                searchText: "", matchingIDs: source.matchingIDs, otherYearCounts: source.otherYearCounts,
                paymentDayRates: source.paymentDayRates, issueDayRates: source.issueDayRates,
                uniformRates: source.uniformRates))
        let buildTime = clock.now - start

        start = clock.now
        let searched = try await database.invoiceListSource(scope: .issued, year: 2026, asOf: asOf, searchText: "acme")
        let searchTime = clock.now - start

        start = clock.now
        let searchedList = InvoiceListBuilder.build(
            InvoiceListInput(
                year: 2026, asOf: asOf, statusDay: asOf, scope: .issued, filter: .all, invoices: searched.invoices,
                searchText: "acme", matchingIDs: searched.matchingIDs, otherYearCounts: searched.otherYearCounts,
                paymentDayRates: searched.paymentDayRates, issueDayRates: searched.issueDayRates,
                uniformRates: searched.uniformRates))
        let searchedBuildTime = clock.now - start

        start = clock.now
        let paid = try await database.invoiceListSource(scope: .paid, year: 2026, asOf: asOf, searchText: "acme")
        let paidTime = clock.now - start

        #expect(listTime < limit, "list took \(listTime)")
        #expect(buildTime < limit, "rows took \(buildTime)")
        #expect(searchTime < limit, "search took \(searchTime)")
        #expect(searchedBuildTime < limit, "rows of a search took \(searchedBuildTime)")
        #expect(paidTime < limit, "paid list took \(paidTime)")

        // The list is the 500 invoices of 2026, with the rates of the foreign ones that the ČNB has declared.
        #expect(source.invoices.count == 500)
        #expect(source.invoices.allSatisfy { $0.issueDate.year == 2026 })
        #expect(list.rows.count == 500)
        #expect(source.paymentDayRates.count > 50)
        #expect(!source.issueDayRates.isEmpty)
        // The search is Acme's invoices of 2026, and the other years are counted for the links.
        let acme = Set(source.invoices.filter { $0.client.name.hasPrefix("Acme") }.map(\.id))
        #expect(searched.matchingIDs == acme)
        #expect(searchedList.rows.count == acme.count)
        #expect(searched.otherYearCounts.keys.sorted() == Array(2017...2026))
        #expect(paid.invoices.allSatisfy { ($0.payment?.date).map { $0.year == 2026 && $0 <= asOf } == true })
    }
}
