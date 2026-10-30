import Foundation
import Testing
@testable import InvoicesTracker

/// The search of the invoices through the database: what is found in which year, how the documents follow the data,
/// and what the queries cost with ten years of invoices. The data is invented. The tests run for the full-text table
/// and for the plain one, which must give the same answers.
struct SearchRepositoryTests {
    private static let asOf = civilDate("2026-10-17")

    /// A database with the three invoices of `SearchFixtures`, each with the id the database gave it, and the two
    /// clients they were written for.
    private struct Fixture {
        let database: Database
        let directory: URL
        let alfa: Client
        let bravo: Client
        let crown: Invoice
        let dollar: Invoice
        let earlier: Invoice

        var all: [Invoice] {
            [crown, dollar, earlier]
        }

        func ids(
            _ query: String,
            scope: InvoiceScope = .issued,
            year: Int = 2026,
            asOf: CivilDate = SearchRepositoryTests.asOf
        ) async throws -> Set<Int64> {
            try await database.searchInvoiceIDs(query, scope: scope, year: year, asOf: asOf)
        }

        func counts(
            _ query: String, scope: InvoiceScope = .issued, asOf: CivilDate = SearchRepositoryTests.asOf
        ) async throws -> [Int: Int] {
            try await database.searchCountsByYear(query, scope: scope, asOf: asOf)
        }

        /// The stored document of every search row, by invoice id.
        func documents() async throws -> [Int64: String] {
            try await database.read { connection in
                var documents: [Int64: String] = [:]
                for row in try connection.query("SELECT rowid, doc FROM invoice_search") {
                    documents[row.int64(0)] = row.text(1)
                }
                return documents
            }
        }
    }

    private static func setUp(_ kind: SearchIndexKind) async throws -> Fixture {
        let (database, directory) = try makeDatabase(searchIndex: kind)
        do {
            var alfa = SearchFixtures.alfa
            alfa.id = try await database.saveClient(alfa)
            var bravo = SearchFixtures.bravo
            bravo.id = try await database.saveClient(bravo)
            var crown = SearchFixtures.crownInvoice(clientID: alfa.id)
            crown.id = try await database.saveInvoice(crown)
            var dollar = SearchFixtures.dollarInvoice(clientID: bravo.id)
            dollar.id = try await database.saveInvoice(dollar)
            var earlier = SearchFixtures.earlierCrownInvoice(clientID: alfa.id)
            earlier.id = try await database.saveInvoice(earlier)
            #expect(await database.searchIndexKind == kind)
            return Fixture(
                database: database, directory: directory, alfa: alfa, bravo: bravo, crown: crown, dollar: dollar,
                earlier: earlier
            )
        } catch {
            removeTemporaryDirectory(directory)
            throw error
        }
    }

    /// The ids of the invoices (issued in `year`) whose document has every word of `query`, found the plain way, with
    /// no database.
    private static func expectedIDs(_ query: String, year: Int, in invoices: [Invoice]) -> Set<Int64> {
        let words = SearchFolding.words(query)
        let found = invoices.filter { invoice in
            let document = SearchDocumentBuilder.document(for: invoice)
            return invoice.issueDate.year == year && words.allSatisfy { document.contains($0) }
        }
        return Set(found.map(\.id))
    }

    // MARK: What is found

    @Test(arguments: availableSearchIndexKinds)
    func aWordWithoutDiacriticsFindsTheCityWrittenWithThemInAnyCase(kind: SearchIndexKind) async throws {
        let f = try await Self.setUp(kind)
        defer { removeTemporaryDirectory(f.directory) }

        #expect(try await f.ids("pribram") == [f.crown.id])
        #expect(try await f.ids("PŘÍBRAM") == [f.crown.id])
        #expect(try await f.ids("příbram") == [f.crown.id])
        #expect(try await f.ids("pribram", year: 2025) == [f.earlier.id])
        #expect(try await f.ids("pribram", year: 2024).isEmpty)
    }

    @Test(arguments: availableSearchIndexKinds)
    func everyWordMustBeSomewhereInTheInvoiceInAnyOrder(kind: SearchIndexKind) async throws {
        let f = try await Self.setUp(kind)
        defer { removeTemporaryDirectory(f.directory) }

        #expect(try await f.ids("alfa 2026") == [f.crown.id])
        #expect(try await f.ids("2026 alfa") == [f.crown.id])
        #expect(try await f.ids("alfa 2025", year: 2025) == [f.earlier.id])
        #expect(try await f.ids("alfa 2025").isEmpty)
        #expect(try await f.ids("bravo alfa").isEmpty)
        #expect(try await f.ids("bravo routing") == [f.dollar.id])
        #expect(try await f.ids("  bravo \t routing  ") == [f.dollar.id])
        #expect(try await f.ids("alfa alfa") == [f.crown.id])
    }

    @Test(arguments: availableSearchIndexKinds)
    func aWordIsFoundInsideOtherText(kind: SearchIndexKind) async throws {
        let f = try await Self.setUp(kind)
        defer { removeTemporaryDirectory(f.directory) }

        #expect(try await f.ids("ystem") == [f.crown.id])
        #expect(try await f.ids("ucetni@exam") == [f.crown.id])
        #expect(try await f.ids("9876543210").isEmpty)
        #expect(try await f.ids("a") == [f.crown.id, f.dollar.id])
    }

    @Test(arguments: availableSearchIndexKinds)
    func amountsAreFoundInEverySpelling(kind: SearchIndexKind) async throws {
        let f = try await Self.setUp(kind)
        defer { removeTemporaryDirectory(f.directory) }

        for query in ["14350", "14 350,00", "14350,00", "14350.00", "14\u{00A0}350,00", "305726", "305 726,75"] {
            #expect(try await f.ids(query) == [f.dollar.id], "\(query)")
        }
        for query in ["4500", "4 500,00", "4500.00", "945,00", "945.00", "5 445,00", "5445,00", "600,00"] {
            #expect(try await f.ids(query) == [f.crown.id], "\(query)")
        }
    }

    @Test(arguments: availableSearchIndexKinds)
    func datesAreFoundInEverySpelling(kind: SearchIndexKind) async throws {
        let f = try await Self.setUp(kind)
        defer { removeTemporaryDirectory(f.directory) }

        for query in ["30.9.2026", "30.09.2026", "2026-09-30", "30. 9. 2026", "30.\u{00A0}9.\u{00A0}2026"] {
            #expect(try await f.ids(query) == [f.crown.id, f.dollar.id], "\(query)")
        }
        #expect(try await f.ids("15.10.2026") == [f.crown.id])
        #expect(try await f.ids("14. 10. 2026") == [f.crown.id])
        for query in ["2.10.2026", "02.10.2026", "2026-10-02"] {
            #expect(try await f.ids(query) == [f.dollar.id], "\(query)")
        }
        // The words of "30. 10. 2026" are looked for one by one, so the crown invoice, which has "30." and "10." in other
        // dates, is found too.
        #expect(try await f.ids("30. 10. 2026") == [f.crown.id, f.dollar.id])
        #expect(try await f.ids("30.10.2026") == [f.dollar.id])
        #expect(try await f.ids("30.9.2025", year: 2025) == [f.earlier.id])
    }

    @Test(arguments: availableSearchIndexKinds)
    func theMonthOfTheSupplyIsFoundByItsName(kind: SearchIndexKind) async throws {
        let f = try await Self.setUp(kind)
        defer { removeTemporaryDirectory(f.directory) }

        #expect(try await f.ids("září 2026") == [f.crown.id, f.dollar.id])
        #expect(try await f.ids("zari 2026") == [f.crown.id, f.dollar.id])
        #expect(try await f.ids("ZÁŘÍ") == [f.crown.id, f.dollar.id])
        #expect(try await f.ids("září 2025", year: 2025) == [f.earlier.id])
        #expect(try await f.ids("říjen 2026").isEmpty)
    }

    @Test(arguments: availableSearchIndexKinds)
    func everyOtherFieldOfTheSearchFindsItsInvoice(kind: SearchIndexKind) async throws {
        let f = try await Self.setUp(kind)
        defer { removeTemporaryDirectory(f.directory) }

        let crown = [f.crown.id] as Set<Int64>
        let dollar = [f.dollar.id] as Set<Int64>
        let expected: [(String, Set<Int64>)] = [
            ("20260901", crown), ("20260902", dollar), ("12345678", crown), ("CZ12345678", crown),
            ("ucetni@example.com", crown), ("billing@example.org", dollar), ("Hlavní 1", crown),
            ("Congress Avenue", dollar), ("Spojené státy", dollar), ("Spojené státy americké", dollar),
            ("americke", dollar), ("Česko", crown), ("78701", dollar),
            ("vývoj", crown), ("Software development", dollar), ("205 hod", dollar), ("7,5 hod", crown),
            ("USD", dollar), ("Tuzemsko 21 %", crown), ("Mimo tuzemsko", dollar), ("odst. 1", dollar),
            ("Převodem", crown), ("ACH", dollar), ("21,305", dollar), ("21,359", dollar),
            ("uhrazená", [f.crown.id, f.dollar.id]), ("vystavená", [f.crown.id, f.dollar.id]),
        ]
        for (query, ids) in expected {
            #expect(try await f.ids(query) == ids, "\(query)")
        }
    }

    @Test(arguments: availableSearchIndexKinds)
    func aWordOfTheNoteIsFoundAndTheExcerptExplainsIt(kind: SearchIndexKind) async throws {
        let f = try await Self.setUp(kind)
        defer { removeTemporaryDirectory(f.directory) }

        let found = try await f.ids("routing")

        #expect(found == [f.dollar.id])
        let invoice = try #require(try await f.database.invoice(id: f.dollar.id))
        let excerpt = try #require(SearchExcerpt.excerpt(for: invoice, words: SearchFolding.words("routing")))
        #expect(excerpt.label == "Poznámka")
        #expect(String(excerpt.text[excerpt.highlight]) == "Routing")
    }

    @Test(arguments: availableSearchIndexKinds)
    func aDraftIsSearchedLikeAnyOtherInvoiceOfTheIssueYear(kind: SearchIndexKind) async throws {
        let f = try await Self.setUp(kind)
        defer { removeTemporaryDirectory(f.directory) }
        let draft = Invoice.fixture(
            number: "20261001", issued: "2026-10-05", duzp: "2026-10-05", dueDate: "2026-10-19", status: .draft)
        let draftID = try await f.database.saveInvoice(draft)

        #expect(try await f.ids("koncept") == [draftID])
        #expect(try await f.ids("vystavená") == [f.crown.id, f.dollar.id])
        #expect(try await f.ids("koncept", scope: .paid).isEmpty)
    }

    // MARK: Short words, odd words

    @Test(arguments: availableSearchIndexKinds)
    func aWordOfTwoLettersIsFoundThroughLike(kind: SearchIndexKind) async throws {
        let f = try await Self.setUp(kind)
        defer { removeTemporaryDirectory(f.directory) }

        // "Kč" is in the amounts of the crown invoice and in the value in crowns of the dollar invoice.
        #expect(try await f.ids("kč") == [f.crown.id, f.dollar.id])
        #expect(try await f.ids("KČ") == [f.crown.id, f.dollar.id])
        #expect(try await f.ids("kč", year: 2025) == [f.earlier.id])
        #expect(try await f.ids("kč bravo") == [f.dollar.id])
        #expect(try await f.ids("kč 2026 pribram") == [f.crown.id])
        #expect(try await f.ids("zz").isEmpty)
    }

    /// What looks like syntax of the full-text query or of a pattern is only text: it finds the invoices that have that
    /// text, as a search of the documents in Swift does, and never fails.
    @Test(arguments: availableSearchIndexKinds)
    func queriesThatLookLikeSyntaxAreOnlyTextAndDoNotThrow(kind: SearchIndexKind) async throws {
        let f = try await Self.setUp(kind)
        defer { removeTemporaryDirectory(f.directory) }

        #expect(try await f.ids("ab\"c").isEmpty)
        for query in [
            "%", "_", "\\", "'", "\"", "\"\"", "\"\"\"", "\"alfa", "alfa\"", "*", "alfa*", "^alfa", "+", "(", ")",
            "a(b", "NEAR(alfa 2026)", "alfa OR bravo", "AND", "OR", "NOT", "alfa AND", "doc:alfa", "{doc}: alfa", "--",
            ";", "'; DROP TABLE invoice; --", "%%%", "a%b", "\u{0000}", "alfa\u{0000}2026",
        ] {
            let expected = Self.expectedIDs(query, year: 2026, in: f.all)
            #expect(try await f.ids(query) == expected, "\(query.debugDescription)")
        }
        #expect(try await f.database.invoiceCount() == 3)
    }

    @Test(arguments: availableSearchIndexKinds)
    func aPercentSignIsNotAWildcardAndFindsNothingWhereTheDataHasNone(kind: SearchIndexKind) async throws {
        let f = try await Self.setUp(kind)
        defer { removeTemporaryDirectory(f.directory) }

        // Only the VAT mode of the crown invoices says "Tuzemsko 21 %". A wildcard would find the dollar invoice too.
        #expect(try await f.ids("%") == [f.crown.id])
        #expect(try await f.ids("%", year: 2025) == [f.earlier.id])
        #expect(try await f.ids("21 %") == [f.crown.id])
        #expect(try await f.ids("tuzemsko %") == [f.crown.id])

        // Where no document has one, nothing is found.
        try await f.database.deleteInvoice(id: f.crown.id)
        #expect(try await f.ids("%").isEmpty)
        #expect(try await f.counts("%") == [2025: 1])
        try await f.database.deleteInvoice(id: f.earlier.id)
        #expect(try await f.counts("%").isEmpty)
    }

    @Test(arguments: availableSearchIndexKinds)
    func percentUnderscoreAndBackslashAreOnlyThemselves(kind: SearchIndexKind) async throws {
        let f = try await Self.setUp(kind)
        defer { removeTemporaryDirectory(f.directory) }
        var odd = Invoice.fixture(number: "20260903", vatMode: .none)
        odd.note = "Sleva 10 % kód A_1 v C:\\temp"
        let oddID = try await f.database.saveInvoice(odd)

        for query in ["_", "\\", "a_", "\\t", "a_1", "c:\\temp", "kód % a_1"] {
            #expect(try await f.ids(query) == [oddID], "\(query)")
        }
        // The crown invoice has a percent sign too, in "Tuzemsko 21 %", and nothing else has.
        #expect(try await f.ids("%") == [f.crown.id, oddID])
        #expect(try await f.ids("a1").isEmpty)
        #expect(try await f.ids("a__").isEmpty)
        #expect(try await f.ids("%a").isEmpty)
        #expect(try await f.ids("c:/temp").isEmpty)
    }

    @Test(arguments: availableSearchIndexKinds)
    func theDatabaseAnswersLikeASearchOfTheDocumentsInSwift(kind: SearchIndexKind) async throws {
        let f = try await Self.setUp(kind)
        defer { removeTemporaryDirectory(f.directory) }
        let queries = [
            "alfa", "bravo", "labs inc", "kč", "usd", "uhrazená", "2026", "2025", "2026-10", "10.2026", "9.2026",
            "30.", "1 2", "4500 5445", "14350 305726", "hlavní příbram", "congress austin tx", "u", "z", "ab", "0",
            "00", ",00", "00,", "1.", ". ", "| ", " | ", "[", "]", "@", "@example", "s.r.o.", "s.r.o. příbram",
        ]

        for year in [2025, 2026] {
            for query in queries {
                let expected = Self.expectedIDs(query, year: year, in: f.all)
                #expect(try await f.ids(query, year: year) == expected, "\(query) in \(year)")
            }
        }
    }

    // MARK: Years and scopes

    @Test(arguments: availableSearchIndexKinds)
    func theCountsListTheYearsOfTheMatchesByTheYearOfIssue(kind: SearchIndexKind) async throws {
        let f = try await Self.setUp(kind)
        defer { removeTemporaryDirectory(f.directory) }

        #expect(try await f.counts("alfa") == [2025: 1, 2026: 1])
        #expect(try await f.counts("pribram") == [2025: 1, 2026: 1])
        #expect(try await f.counts("bravo") == [2026: 1])
        #expect(try await f.counts("2026") == [2026: 2])
        #expect(try await f.counts("kč") == [2025: 1, 2026: 2])
        #expect(try await f.counts("alfa bravo").isEmpty)
        #expect(try await f.counts("nothing like it").isEmpty)
    }

    @Test(arguments: availableSearchIndexKinds)
    func aSearchHasTheIdsOfTheYearAndTheCountsOfEveryYear(kind: SearchIndexKind) async throws {
        let f = try await Self.setUp(kind)
        defer { removeTemporaryDirectory(f.directory) }

        for query in ["alfa", "kč", "2026", "příbram 30.9", "usd", "xyz"] {
            let counts = try await f.counts(query)
            for year in 2024...2027 {
                #expect(try await f.ids(query, year: year).count == counts[year, default: 0], "\(query) \(year)")
            }
        }
    }

    @Test(arguments: availableSearchIndexKinds)
    func thePaidScopeIsTheYearOfThePaymentUpToTheAsOfDay(kind: SearchIndexKind) async throws {
        let f = try await Self.setUp(kind)
        defer { removeTemporaryDirectory(f.directory) }

        // paid on 15. 10. 2026 (crown), 2. 10. 2026 (dollar) and 10. 10. 2025 (the earlier crown invoice)
        #expect(try await f.ids("alfa", scope: .paid) == [f.crown.id])
        #expect(try await f.ids("2026", scope: .paid) == [f.crown.id, f.dollar.id])
        #expect(try await f.ids("alfa", scope: .paid, year: 2025) == [f.earlier.id])
        #expect(try await f.counts("alfa", scope: .paid) == [2025: 1, 2026: 1])
        #expect(try await f.counts("kč", scope: .paid) == [2025: 1, 2026: 2])

        let beforeTheCrownPayment = civilDate("2026-10-14")
        #expect(try await f.ids("alfa", scope: .paid, asOf: beforeTheCrownPayment).isEmpty)
        #expect(try await f.ids("bravo", scope: .paid, asOf: beforeTheCrownPayment) == [f.dollar.id])
        #expect(try await f.counts("alfa", scope: .paid, asOf: beforeTheCrownPayment) == [2025: 1])
        #expect(try await f.counts("kč", scope: .paid, asOf: civilDate("2026-10-02")) == [2025: 1, 2026: 1])
        #expect(try await f.counts("alfa", scope: .paid, asOf: civilDate("2025-10-09")).isEmpty)
        // the payment day itself counts
        #expect(try await f.counts("alfa", scope: .paid, asOf: civilDate("2026-10-15")) == [2025: 1, 2026: 1])
    }

    @Test(arguments: availableSearchIndexKinds)
    func anInvoiceBelongsToTheYearOfItsIssueNotOfItsSupply(kind: SearchIndexKind) async throws {
        let f = try await Self.setUp(kind)
        defer { removeTemporaryDirectory(f.directory) }
        // supplied on 31. 12. 2025, issued on 3. 1. 2026
        let late = Invoice.fixture(number: "20251202", issued: "2026-01-03", duzp: "2025-12-31", dueDate: "2026-01-17")
        let id = try await f.database.saveInvoice(late)

        #expect(try await f.ids("20251202", year: 2026) == [id])
        #expect(try await f.ids("20251202", year: 2025).isEmpty)
        #expect(try await f.counts("20251202") == [2026: 1])
    }

    @Test(arguments: availableSearchIndexKinds)
    func theIssuedScopeDoesNotLookAtTheAsOfDay(kind: SearchIndexKind) async throws {
        let f = try await Self.setUp(kind)
        defer { removeTemporaryDirectory(f.directory) }
        let longBefore = civilDate("2020-01-01")

        #expect(try await f.ids("alfa", asOf: longBefore) == [f.crown.id])
        #expect(try await f.counts("alfa", asOf: longBefore) == [2025: 1, 2026: 1])
    }

    @Test(arguments: availableSearchIndexKinds)
    func anInvoiceIssuedInOneYearAndPaidInTheNextIsInBothAccordingToTheScope(kind: SearchIndexKind) async throws {
        let f = try await Self.setUp(kind)
        defer { removeTemporaryDirectory(f.directory) }
        let yearEnd = Invoice.fixture(
            number: "20251201", duzp: "2025-12-31", dueDate: "2026-01-14", payment: .fixture(on: "2026-01-02"))
        let id = try await f.database.saveInvoice(yearEnd)

        #expect(try await f.ids("20251201", year: 2025) == [id])
        #expect(try await f.ids("20251201", year: 2026).isEmpty)
        #expect(try await f.ids("20251201", scope: .paid, year: 2026) == [id])
        #expect(try await f.ids("20251201", scope: .paid, year: 2025).isEmpty)
        #expect(try await f.counts("20251201") == [2025: 1])
        #expect(try await f.counts("20251201", scope: .paid) == [2026: 1])
        // Its due date is in 2026, so a word of 2026 finds it in the year of its issue too.
        #expect(try await f.counts("14.1.2026") == [2025: 1])
    }

    @Test(arguments: availableSearchIndexKinds)
    func anEmptyQueryIsNoSearchAndGivesEveryInvoiceOfTheScope(kind: SearchIndexKind) async throws {
        let f = try await Self.setUp(kind)
        defer { removeTemporaryDirectory(f.directory) }

        #expect(try await f.ids("") == [f.crown.id, f.dollar.id])
        #expect(try await f.ids("  \u{00A0}\t") == [f.crown.id, f.dollar.id])
        #expect(try await f.ids("", year: 2025) == [f.earlier.id])
        #expect(try await f.ids("", scope: .paid) == [f.crown.id, f.dollar.id])
        #expect(try await f.ids("", scope: .paid, asOf: civilDate("2026-10-10")) == [f.dollar.id])
        #expect(try await f.ids("", year: 2030).isEmpty)
        #expect(try await f.counts("") == [2025: 1, 2026: 2])
        #expect(try await f.counts("   ", scope: .paid) == [2025: 1, 2026: 2])
    }

    @Test(arguments: availableSearchIndexKinds)
    func aYearOutsideTheCalendarFindsNothing(kind: SearchIndexKind) async throws {
        let f = try await Self.setUp(kind)
        defer { removeTemporaryDirectory(f.directory) }

        for year in [0, -2026, 10_000, Int.max, Int.min] {
            #expect(try await f.ids("alfa", year: year).isEmpty, "\(year)")
            #expect(try await f.ids("", year: year).isEmpty, "\(year)")
            #expect(try await f.ids("alfa", scope: .paid, year: year).isEmpty, "\(year)")
        }
    }

    // MARK: Documents follow the data

    @Test(arguments: availableSearchIndexKinds)
    func everySaveGivesTheInvoiceExactlyOneDocumentOfTheBuilder(kind: SearchIndexKind) async throws {
        let f = try await Self.setUp(kind)
        defer { removeTemporaryDirectory(f.directory) }

        let documents = try await f.documents()

        #expect(documents.count == 3)
        for invoice in f.all {
            let stored = try #require(try await f.database.invoice(id: invoice.id))
            #expect(documents[invoice.id] == SearchDocumentBuilder.document(for: stored), "\(invoice.number)")
        }
        #expect(try await f.database.integer("SELECT count(*) FROM invoice_search") == 3)
    }

    @Test(arguments: availableSearchIndexKinds)
    func savingAnInvoiceReplacesItsDocumentInTheSameWrite(kind: SearchIndexKind) async throws {
        let f = try await Self.setUp(kind)
        defer { removeTemporaryDirectory(f.directory) }
        var dollar = f.dollar
        dollar.note = "Změněná poznámka"
        let writesBefore = await f.database.writeCount

        try await f.database.saveInvoice(dollar)

        #expect(await f.database.writeCount == writesBefore + 1)
        #expect(try await f.ids("routing").isEmpty)
        #expect(try await f.ids("zmenena") == [f.dollar.id])
        #expect(try await f.ids("bravo") == [f.dollar.id])
        #expect(try await f.database.integer("SELECT count(*) FROM invoice_search") == 3)
    }

    @Test(arguments: availableSearchIndexKinds)
    func aPaymentThatIsAddedChangedAndRemovedMovesTheDocument(kind: SearchIndexKind) async throws {
        let f = try await Self.setUp(kind)
        defer { removeTemporaryDirectory(f.directory) }
        var crown = f.crown

        crown.payment = nil
        try await f.database.saveInvoice(crown)
        #expect(try await f.ids("15.10.2026").isEmpty)
        #expect(try await f.ids("uhrazená") == [f.dollar.id])

        crown.payment = .fixture(on: "2026-11-02")
        try await f.database.saveInvoice(crown)
        #expect(try await f.ids("2.11.2026") == [f.crown.id])
        #expect(try await f.ids("uhrazená") == [f.crown.id, f.dollar.id])
        #expect(try await f.ids("2.11.2026", scope: .paid, asOf: civilDate("2026-11-30")) == [f.crown.id])
    }

    @Test(arguments: availableSearchIndexKinds)
    func aSaveThatFailsLeavesTheDocumentsAsTheyWere(kind: SearchIndexKind) async throws {
        let f = try await Self.setUp(kind)
        defer { removeTemporaryDirectory(f.directory) }
        let before = try await f.documents()
        // another invoice with the number of the first one
        var duplicate = SearchFixtures.dollarInvoice()
        duplicate.number = "2026-09-01"
        duplicate.note = "Duplicate number"

        await #expect(throws: InvoiceError.duplicateNumber("2026-09-01")) {
            try await f.database.saveInvoice(duplicate)
        }

        #expect(try await f.documents() == before)
        #expect(try await f.ids("duplicate").isEmpty)
    }

    @Test(arguments: availableSearchIndexKinds)
    func theSearchWorksAfterTheDatabaseIsOpenedAgain(kind: SearchIndexKind) async throws {
        let key = randomKey()
        let (database, directory) = try makeDatabase(searchIndex: kind, key: key)
        defer { removeTemporaryDirectory(directory) }
        let id = try await database.saveInvoice(SearchFixtures.dollarInvoice())
        await database.close()

        let reopened = try Database(fileURL: database.fileURL, key: key)

        #expect(await reopened.searchIndexKind == kind)
        #expect(try await reopened.searchInvoiceIDs("routing", scope: .issued, year: 2026, asOf: Self.asOf) == [id])
        #expect(try await reopened.searchCountsByYear("bravo", scope: .issued, asOf: Self.asOf) == [2026: 1])
    }

    /// The documents hold the names, addresses and amounts of the invoices. The full-text table keeps them in pages of
    /// the one encrypted file, like every other table, and so does the write-ahead log.
    @Test(arguments: availableSearchIndexKinds)
    func theSearchDocumentsAreNotOnDiskAsPlainText(kind: SearchIndexKind) async throws {
        let f = try await Self.setUp(kind)
        defer { removeTemporaryDirectory(f.directory) }
        try await f.database.rebuildAllSearchDocuments()
        let secrets = [
            "routing number", "ROUTING NUMBER", "pribram", "Příbram", "alfa systems", "Alfa Systems", "14350,00",
        ]
        let path = f.database.fileURL.path(percentEncoded: false)

        // Until the connection closes the pages sit in the write-ahead log.
        let logWhileOpen = try #require(FileManager.default.contents(atPath: path + "-wal"))
        #expect(!logWhileOpen.isEmpty)
        for secret in secrets {
            #expect(logWhileOpen.range(of: Data(secret.utf8)) == nil, "\(secret) in the log")
        }

        await f.database.close()

        let file = try #require(FileManager.default.contents(atPath: path))
        #expect(!file.isEmpty)
        for secret in secrets {
            #expect(file.range(of: Data(secret.utf8)) == nil, "\(secret) in the file")
        }
    }

    @Test(arguments: availableSearchIndexKinds)
    func deletingAnInvoiceRemovesItFromTheSearch(kind: SearchIndexKind) async throws {
        let f = try await Self.setUp(kind)
        defer { removeTemporaryDirectory(f.directory) }

        try await f.database.deleteInvoice(id: f.crown.id)

        #expect(try await f.ids("pribram").isEmpty)
        #expect(try await f.counts("alfa") == [2025: 1])
        #expect(try await f.documents().keys.sorted() == [f.dollar.id, f.earlier.id])
    }

    @Test(arguments: availableSearchIndexKinds)
    func rebuildingEveryDocumentGivesTheDocumentsOfTheBuilderInOneWrite(kind: SearchIndexKind) async throws {
        let f = try await Self.setUp(kind)
        defer { removeTemporaryDirectory(f.directory) }
        let before = try await f.documents()
        try await f.database.write { connection in
            try connection.run("DELETE FROM invoice_search")
        }
        #expect(try await f.ids("pribram").isEmpty)
        let writesBefore = await f.database.writeCount

        try await f.database.rebuildAllSearchDocuments()

        #expect(await f.database.writeCount == writesBefore + 1)
        #expect(try await f.documents() == before)
        #expect(try await f.ids("pribram") == [f.crown.id])
        #expect(try await f.counts("alfa") == [2025: 1, 2026: 1])
    }

    @Test(.enabled(if: availableSearchIndexKinds.contains(.fts5)))
    func rebuildingEveryDocumentAlsoClearsRowsOfInvoicesThatAreGone() async throws {
        let f = try await Self.setUp(.fts5)
        defer { removeTemporaryDirectory(f.directory) }
        // A full-text table cannot have a foreign key, so a row can outlive its invoice.
        try await f.database.write { connection in
            try connection.run("INSERT INTO invoice_search(rowid, doc) VALUES (99, 'alfa of an invoice that is gone')")
        }
        #expect(try await f.documents().count == 4)

        try await f.database.rebuildAllSearchDocuments()

        #expect(try await f.documents().keys.sorted() == f.all.map(\.id).sorted())
    }

    @Test(arguments: availableSearchIndexKinds)
    func rebuildingEveryDocumentOfADatabaseWithoutInvoicesIsFine(kind: SearchIndexKind) async throws {
        let (database, directory) = try makeDatabase(searchIndex: kind)
        defer { removeTemporaryDirectory(directory) }

        try await database.rebuildAllSearchDocuments()

        #expect(try await database.integer("SELECT count(*) FROM invoice_search") == 0)
        #expect(try await database.searchInvoiceIDs("alfa", scope: .issued, year: 2026, asOf: Self.asOf).isEmpty)
    }

    // MARK: The client of an invoice

    @Test(arguments: availableSearchIndexKinds)
    func renamingAClientMakesItsInvoicesFindableByTheNewNameAndKeepsTheOldOne(kind: SearchIndexKind) async throws {
        let f = try await Self.setUp(kind)
        defer { removeTemporaryDirectory(f.directory) }
        let dollarDocument = try await f.documents()[f.dollar.id]
        var renamed = f.alfa
        renamed.name = "Alfa Prime"

        try await f.database.saveClient(renamed)

        #expect(try await f.ids("prime") == [f.crown.id])
        #expect(try await f.ids("prime", year: 2025) == [f.earlier.id])
        #expect(try await f.counts("prime") == [2025: 1, 2026: 1])
        #expect(try await f.ids("alfa prime 2026") == [f.crown.id])
        // The invoices say what they said when they were written, and are found by it as before.
        #expect(try await f.counts("systems") == [2025: 1, 2026: 1])
        #expect(try await f.database.invoice(id: f.crown.id)?.client.name == "Alfa Systems s.r.o.")
        // The other client's invoice is as it was.
        #expect(try await f.documents()[f.dollar.id] == dollarDocument)
    }

    @Test(arguments: availableSearchIndexKinds)
    func everyPrintedFieldOfAChangedClientIsSearched(kind: SearchIndexKind) async throws {
        let f = try await Self.setUp(kind)
        defer { removeTemporaryDirectory(f.directory) }
        var changed = f.alfa
        changed.street = "Nádražní 99"
        changed.postcode = "110 00"
        changed.city = "Praha"
        changed.country = "SK"
        changed.ico = "87654321"
        changed.dic = "SK87654321"
        changed.email = "faktury@example.net"

        try await f.database.saveClient(changed)

        for query in ["nádražní 99", "110 00", "praha", "slovensko", "87654321", "SK87654321", "faktury@example.net"] {
            #expect(try await f.counts(query) == [2025: 1, 2026: 1], "\(query)")
        }
    }

    @Test(arguments: availableSearchIndexKinds)
    func savingAClientIsOneWriteWhateverNumberOfInvoicesItHas(kind: SearchIndexKind) async throws {
        let f = try await Self.setUp(kind)
        defer { removeTemporaryDirectory(f.directory) }
        var renamed = f.alfa
        renamed.name = "Alfa Prime"
        let writesBefore = await f.database.writeCount

        try await f.database.saveClient(renamed)

        #expect(await f.database.writeCount == writesBefore + 1)
    }

    @Test(arguments: availableSearchIndexKinds)
    func aChangeThatIsNotPrintedLeavesTheDocumentsAsTheyAre(kind: SearchIndexKind) async throws {
        let f = try await Self.setUp(kind)
        defer { removeTemporaryDirectory(f.directory) }
        let before = try await f.documents()
        var changed = f.alfa
        changed.phone = "+420 123 456 789"
        changed.dueDays = 30
        changed.paymentMethod = "Hotově"

        try await f.database.saveClient(changed)

        #expect(try await f.documents() == before)
    }

    @Test(arguments: availableSearchIndexKinds)
    func anInvoiceThatIsNotLinkedToTheClientIsNotAffectedByItsRename(kind: SearchIndexKind) async throws {
        let f = try await Self.setUp(kind)
        defer { removeTemporaryDirectory(f.directory) }
        // The same printed data as the first client, but no link.
        let unlinked = Invoice.fixture(number: "20260904")
        let unlinkedID = try await f.database.saveInvoice(unlinked)
        var renamed = f.alfa
        renamed.name = "Alfa Prime"

        try await f.database.saveClient(renamed)

        #expect(try await f.ids("prime") == [f.crown.id])
        #expect(try await f.ids("alfa") == [f.crown.id, unlinkedID])
    }

    @Test(arguments: availableSearchIndexKinds)
    func savingAnInvoiceAfterTheRenameKeepsTheNewNameInItsDocument(kind: SearchIndexKind) async throws {
        let f = try await Self.setUp(kind)
        defer { removeTemporaryDirectory(f.directory) }
        var renamed = f.alfa
        renamed.name = "Alfa Prime"
        try await f.database.saveClient(renamed)
        var crown = f.crown
        crown.note = "Po přejmenování"

        try await f.database.saveInvoice(crown)

        #expect(try await f.ids("prime") == [f.crown.id])
        #expect(try await f.ids("prejmenovani") == [f.crown.id])
        #expect(try await f.ids("systems") == [f.crown.id])
    }

    @Test(arguments: availableSearchIndexKinds)
    func rebuildingEveryDocumentKeepsTheNameOfTheClientAsItIsNow(kind: SearchIndexKind) async throws {
        let f = try await Self.setUp(kind)
        defer { removeTemporaryDirectory(f.directory) }
        var renamed = f.alfa
        renamed.name = "Alfa Prime"
        try await f.database.saveClient(renamed)
        let before = try await f.documents()

        try await f.database.rebuildAllSearchDocuments()

        #expect(try await f.documents() == before)
        #expect(try await f.counts("prime") == [2025: 1, 2026: 1])
    }

    // MARK: Both kinds of table

    /// Documents are folded, so a full-text table and a plain one never differ in what they find. A document that
    /// something else wrote in capitals shows which statement a database asks: the full-text index finds the letters
    /// whatever their case, while a pattern takes the capitals of letters beyond ASCII as they are.
    @Test(arguments: availableSearchIndexKinds)
    func aDatabaseAsksItsOwnKindOfTableForTheWordsItLooksFor(kind: SearchIndexKind) async throws {
        let f = try await Self.setUp(kind)
        defer { removeTemporaryDirectory(f.directory) }
        try await f.database.write { connection in
            try connection.run(
                "UPDATE invoice_search SET doc = ? WHERE rowid = ?", [.text("ŁODZ"), .integer(f.crown.id)])
        }

        #expect(try await f.ids("łodz") == (kind == .fts5 ? [f.crown.id] : []))
        #expect(try await f.counts("łodz") == (kind == .fts5 ? [2026: 1] : [:]))
    }

    @Test(.enabled(if: availableSearchIndexKinds.contains(.fts5)))
    func theFullTextTableAndThePlainTableFindTheSameInvoices() async throws {
        let full = try await Self.setUp(.fts5)
        defer { removeTemporaryDirectory(full.directory) }
        let plain = try await Self.setUp(.plain)
        defer { removeTemporaryDirectory(plain.directory) }
        let queries = [
            "pribram", "alfa 2026", "14350", "14 350,00", "14350.00", "30.9.2026", "září 2026", "routing", "kč",
            "ab\"c", "%", "_", "\\", "NEAR(alfa)", "alfa OR bravo", "", "  ", "a", "ž", "ř", "ťuk", "ěščřžýáíé",
            "2026-09", "00", "usd kč", "bravo labs, inc.", "labs,", "[routing", "number:", "ucetni@", "@example.com",
            "cz1",
        ]

        for scope in [InvoiceScope.issued, .paid] {
            for query in queries {
                for year in [2025, 2026] {
                    let expected = try await plain.ids(query, scope: scope, year: year)
                    let found = try await full.ids(query, scope: scope, year: year)
                    #expect(found == expected, "\(query) \(scope) \(year)")
                }
                let expectedCounts = try await plain.counts(query, scope: scope)
                #expect(try await full.counts(query, scope: scope) == expectedCounts, "\(query) \(scope)")
            }
        }
    }
}

// MARK: - The statements

/// The statements that look for the words of a query, and how SQLite runs them.
struct SearchQueryTests {
    private let asOf = civilDate("2026-10-17")

    /// The arguments after the first and the last day: the words.
    private func wordArguments(_ statement: SearchStatement) -> [SQLValue] {
        Array(statement.arguments.dropFirst(2))
    }

    private func makeStatement(
        _ query: String, _ kind: SearchIndexKind, scope: InvoiceScope = .issued
    ) throws -> SearchStatement {
        let words = SearchFolding.words(query)
        return try #require(
            SearchQueries.invoiceIDs(words: words, kind: kind, scope: scope, year: 2026, asOf: asOf))
    }

    @Test func wordsOfThreeCharactersGoIntoOneMatchAndShorterOnesIntoLike() throws {
        let statement = try makeStatement("alfa kč 2026 a", .fts5)

        #expect(statement.sql.components(separatedBy: "MATCH").count == 2)
        #expect(statement.sql.components(separatedBy: " LIKE ").count == 3)
        #expect(wordArguments(statement) == [.text("\"alfa\" AND \"2026\""), .text("%kc%"), .text("%a%")])
    }

    @Test func eachTermOfTheMatchIsQuotedAndItsQuotesAreDoubled() throws {
        let statement = try makeStatement("ab\"c x\"\"y 30.9.2026 and", .fts5)

        #expect(
            wordArguments(statement) == [.text("\"ab\"\"c\" AND \"x\"\"\"\"y\" AND \"30.9.2026\" AND \"and\"")])
    }

    @Test func aWordIsLookedUpOnceWhateverTheNumberOfTimesItIsTyped() throws {
        let fullText = try makeStatement("alfa 2026 alfa kč kč", .fts5)
        let plain = try makeStatement("alfa 2026 alfa kč kč", .plain)

        #expect(wordArguments(fullText) == [.text("\"alfa\" AND \"2026\""), .text("%kc%")])
        #expect(wordArguments(plain) == [.text("%alfa%"), .text("%2026%"), .text("%kc%")])
    }

    @Test func aPlainTableUsesLikeForEveryWordAndNeverMatch() throws {
        let statement = try makeStatement("alfa kč 2026", .plain)

        #expect(!statement.sql.contains("MATCH"))
        #expect(statement.sql.components(separatedBy: " LIKE ").count == 4)
        #expect(wordArguments(statement) == [.text("%alfa%"), .text("%kc%"), .text("%2026%")])
    }

    @Test func thePatternOfALikeEscapesPercentUnderscoreAndBackslash() throws {
        let plain = try makeStatement("50% a_b c\\d %_\\", .plain)
        let fullText = try makeStatement("a% _b \\ 50%", .fts5)

        #expect(
            wordArguments(plain) == [.text("%50\\%%"), .text("%a\\_b%"), .text("%c\\\\d%"), .text("%\\%\\_\\\\%")])
        // Two characters or fewer, so these are patterns; the longer word is a term of the match.
        #expect(wordArguments(fullText) == [.text("\"50%\""), .text("%a\\%%"), .text("%\\_b%"), .text("%\\\\%")])
        #expect(plain.sql.contains("ESCAPE '\\'") && fullText.sql.contains("ESCAPE '\\'"))
    }

    @Test func aQueryWithoutWordsHasNoConditionOnTheDocuments() throws {
        for kind in [SearchIndexKind.fts5, .plain] {
            let statement = try makeStatement("  ", kind)

            #expect(!statement.sql.contains("invoice_search"))
            #expect(wordArguments(statement).isEmpty)
        }
    }

    @Test func aYearOutsideTheCalendarHasNoStatement() {
        for year in [0, 10_000, -1] {
            let statement = SearchQueries.invoiceIDs(
                words: ["alfa"], kind: .plain, scope: .issued, year: year, asOf: asOf)
            #expect(statement == nil, "\(year)")
        }
    }

    @Test func theDaysOfTheScopeAreTheYearAndForPaymentsTheYearUpToTheAsOfDay() throws {
        let issued = try makeStatement("alfa", .plain)
        let paid = try makeStatement("alfa", .plain, scope: .paid)
        let paidEarly = try #require(
            SearchQueries.invoiceIDs(
                words: ["alfa"], kind: .plain, scope: .paid, year: 2026, asOf: civilDate("2026-03-01")))
        let paidAfterTheYear = try #require(
            SearchQueries.invoiceIDs(
                words: ["alfa"], kind: .plain, scope: .paid, year: 2026, asOf: civilDate("2027-03-01")))

        #expect(Array(issued.arguments.prefix(2)) == [.text("2026-01-01"), .text("2026-12-31")])
        #expect(Array(paid.arguments.prefix(2)) == [.text("2026-01-01"), .text("2026-10-17")])
        #expect(Array(paidEarly.arguments.prefix(2)) == [.text("2026-01-01"), .text("2026-03-01")])
        #expect(Array(paidAfterTheYear.arguments.prefix(2)) == [.text("2026-01-01"), .text("2026-12-31")])
    }

    // MARK: How SQLite runs them

    private func queryPlan(of statement: SearchStatement, in database: Database) async throws -> [String] {
        try await database.read { connection in
            try connection.query("EXPLAIN QUERY PLAN " + statement.sql, statement.arguments).map { $0.text(3) }
        }
    }

    @Test func aFullTextTableIsLookedUpWithTheMatchAndNeverScannedBlindly() async throws {
        guard availableSearchIndexKinds.contains(.fts5) else { return }
        let (database, directory) = try makeDatabase(searchIndex: .fts5)
        defer { removeTemporaryDirectory(directory) }

        let plan = try await queryPlan(of: makeStatement("acme 2025", .fts5), in: database)

        #expect(plan.contains { $0.contains("invoice_search VIRTUAL TABLE INDEX 0:M") }, "\(plan)")
        #expect(!plan.contains { $0.hasPrefix("SCAN invoice ") || $0 == "SCAN invoice" }, "\(plan)")
    }

    @Test func aPlainTableIsSearchedOnlyForTheInvoicesOfTheYear() async throws {
        let (database, directory) = try makeDatabase(searchIndex: .plain)
        defer { removeTemporaryDirectory(directory) }

        for scope in [InvoiceScope.issued, .paid] {
            let plan = try await queryPlan(of: makeStatement("acme 2025", .plain, scope: scope), in: database)

            #expect(plan.contains { $0.hasPrefix("SEARCH") && $0.contains("USING") && $0.contains("_date") }, "\(plan)")
            #expect(!plan.contains { $0.hasPrefix("SCAN invoice") }, "\(plan)")
        }
    }
}

// MARK: - Ten years of invoices

/// With 5 000 invoices over ten years, a search takes under half a second, and finds what the documents say.
struct SearchPerformanceTests {
    private let limit = Duration.milliseconds(500)

    @Test(arguments: availableSearchIndexKinds)
    func aSearchOfFiveThousandInvoicesTakesUnderHalfASecond(kind: SearchIndexKind) async throws {
        let (database, directory) = try makeDatabase(searchIndex: kind)
        defer { removeTemporaryDirectory(directory) }
        try await database.insertGeneratedInvoices(years: 2017...2026, perYear: 500)
        try await database.rebuildAllSearchDocuments()
        #expect(try await database.integer("SELECT count(*) FROM invoice_search") == 5_000)
        let asOf = civilDate("2026-10-17")
        let clock = ContinuousClock()

        var start = clock.now
        let found = try await database.searchInvoiceIDs("acme 2025", scope: .issued, year: 2025, asOf: asOf)
        let searchTime = clock.now - start

        start = clock.now
        let counts = try await database.searchCountsByYear("acme 2025", scope: .issued, asOf: asOf)
        let countsTime = clock.now - start

        start = clock.now
        let paid = try await database.searchInvoiceIDs("acme 2025", scope: .paid, year: 2025, asOf: asOf)
        let paidTime = clock.now - start

        start = clock.now
        let short = try await database.searchInvoiceIDs("kč 2025", scope: .issued, year: 2025, asOf: asOf)
        let shortTime = clock.now - start

        #expect(searchTime < limit, "search took \(searchTime)")
        #expect(countsTime < limit, "counts took \(countsTime)")
        #expect(paidTime < limit, "search in the paid scope took \(paidTime)")
        #expect(shortTime < limit, "search with a short word took \(shortTime)")

        // The answers are what a search of the documents in Swift says, year by year.
        var invoices: [Invoice] = []
        for year in 2017...2026 {
            invoices += try await database.invoices(scope: .issued, year: year, asOf: asOf)
        }
        #expect(invoices.count == 5_000)
        let documents = Dictionary(
            uniqueKeysWithValues: invoices.map { ($0.id, SearchDocumentBuilder.document(for: $0)) })
        func expected(_ words: [String], where include: (Invoice) -> Bool) -> Set<Int64> {
            let found = invoices.filter { invoice in
                include(invoice) && words.allSatisfy { documents[invoice.id, default: ""].contains($0) }
            }
            return Set(found.map(\.id))
        }
        let acme2025 = ["acme", "2025"]
        #expect(found == expected(acme2025) { $0.issueDate.year == 2025 })
        #expect(found.count > 100)
        var expectedCounts: [Int: Int] = [:]
        for invoice in invoices where acme2025.allSatisfy({ documents[invoice.id, default: ""].contains($0) }) {
            expectedCounts[invoice.issueDate.year, default: 0] += 1
        }
        #expect(counts == expectedCounts)
        #expect(counts.count > 1)
        #expect(paid == expected(acme2025) { $0.payment.map { $0.date.year == 2025 && $0.date <= asOf } ?? false })
        #expect(!paid.isEmpty)
        #expect(short == expected(["kc", "2025"]) { $0.issueDate.year == 2025 })
        #expect(short.count > found.count)
    }
}
