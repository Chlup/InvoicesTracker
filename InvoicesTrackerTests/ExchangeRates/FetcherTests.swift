import Foundation
import Testing
@testable import InvoicesTracker

struct FetcherTests {
    // MARK: Helpers

    private static let cnbBase =
        "https://www.cnb.cz/cs/financni-trhy/devizovy-trh/kurzy-devizoveho-trhu/kurzy-devizoveho-trhu/"

    /// A file of the ČNB fixtures as the bytes the server would send.
    private func cnbBytes(_ name: String) throws -> Data {
        try Data(contentsOf: fixtureURL(name, "txt"))
    }

    // MARK: ČNB addresses

    @Test func theYearlyFileHasTheYearInItsAddress() {
        #expect(CNBEndpoints.yearly(2026) == webURL(Self.cnbBase + "rok.txt?rok=2026"))
        #expect(CNBEndpoints.yearly(2022) == webURL(Self.cnbBase + "rok.txt?rok=2022"))
    }

    @Test func theDailyFileHasTheDayInItsAddressAsDayMonthYear() {
        let address = CNBEndpoints.daily(civilDate("2026-10-16"))
        #expect(address == webURL(Self.cnbBase + "denni_kurz.txt?date=16.10.2026"))
        #expect(address.absoluteString.hasSuffix("denni_kurz.txt?date=16.10.2026"))
        // Two digits for the day and the month, four for the year.
        #expect(CNBEndpoints.daily(civilDate("2026-01-05")).absoluteString.hasSuffix("date=05.01.2026"))
        #expect(CNBEndpoints.daily(civilDate("2027-12-31")).absoluteString.hasSuffix("date=31.12.2027"))
        #expect(CNBEndpoints.daily(civilDate("0999-02-03")).absoluteString.hasSuffix("date=03.02.0999"))
    }

    @Test func everyAddressTheAppBuildsIsOneTheClientMayAsk() throws {
        let issues = GFRParser.issueLinks(indexHTML: try gfrFixture("gfr_index_2026", "html"), publicationYear: 2026)
        let pdf = try #require(GFRParser.pdfLink(issueHTML: try gfrFixture("gfr_issue_2_2026", "html")))
        let addresses =
            [
                CNBEndpoints.yearly(2026), CNBEndpoints.daily(civilDate("2026-10-16")),
                GFRParser.indexURL(forYear: 2025), pdf,
            ] + issues
        #expect(addresses.allSatisfy { URLSessionHTTPClient.isAllowed($0) })
    }

    // MARK: ČNB files

    @Test func theYearlyFileIsFetchedAndRead() async throws {
        let stub = StubHTTPClient([CNBEndpoints.yearly(2026): try cnbBytes("cnb_rok_2026")])
        let rows = try await CNBFetcher(http: stub).fetchYear(2026)
        #expect(rows.count == 200 * 30)
        #expect(rows == (try cnbYearlyRows([2026])))
        #expect(stub.requests == [CNBEndpoints.yearly(2026)])
    }

    @Test func theDailyFileIsFetchedAndRead() async throws {
        let day = civilDate("2026-10-16")
        let stub = StubHTTPClient([CNBEndpoints.daily(day): try cnbBytes("cnb_denni_2026-10-16")])
        let daily = try await CNBFetcher(http: stub).fetchDay(day)
        #expect(daily.declaredOn == day)
        #expect(daily.rows.count == 5)
        #expect(
            daily.rows.first { $0.currency == .usd }
                == CNBRateRow(declaredOn: day, currency: .usd, amount: 1, rate: decimal("21.622")))
        #expect(stub.requests == [CNBEndpoints.daily(day)])
    }

    /// The file of the ČNB as it was downloaded on 18 October 2026: it proves that the parser accepts the real format,
    /// not only the trimmed fixture of its own tests.
    @Test func theDailyFileTheServerSentIsRead() async throws {
        let day = civilDate("2026-10-16")
        let stub = StubHTTPClient([CNBEndpoints.daily(day): try cnbBytes("cnb_denni_live_2026-10-16")])
        let daily = try await CNBFetcher(http: stub).fetchDay(day)
        #expect(daily.declaredOn == day)
        #expect(daily.rows.count == 30)
        #expect(daily.rows.allSatisfy { $0.declaredOn == day })
        // It holds the very rates the yearly file of the ČNB has for the day.
        let yearlyRowsOfTheDay = try cnbYearlyRows([2026]).filter { $0.declaredOn == day }
        #expect(Set(daily.rows) == Set(yearlyRowsOfTheDay))
        // And the trimmed fixture is a part of it.
        let trimmed = try CNBDailyParser.parse(cnbFixture("cnb_denni_2026-10-16"))
        #expect(Set(trimmed.rows).isSubset(of: Set(daily.rows)))
    }

    @Test func aFileInWindows1250IsReadLikeTheSameFileInUTF8() async throws {
        let day = civilDate("2026-10-16")
        let text = try cnbFixture("cnb_denni_live_2026-10-16")
        let windows1250 = try #require(text.data(using: .windowsCP1250))
        // The test is only about the fallback if the bytes are not UTF-8.
        #expect(String(data: windows1250, encoding: .utf8) == nil)
        let stub = StubHTTPClient([CNBEndpoints.daily(day): windows1250])
        let daily = try await CNBFetcher(http: stub).fetchDay(day)
        let expected = try CNBDailyParser.parse(text)
        #expect(daily.declaredOn == expected.declaredOn)
        #expect(daily.rows == expected.rows)
    }

    @Test func theDayTheFileSaysIsReturnedWhenItIsNotTheDayThatWasAskedFor() async throws {
        // A request for a day the ČNB declared nothing on can be answered with the file of an earlier day. The day the
        // rates were declared on is the one the file says, not the one that was asked for.
        let sunday = civilDate("2026-10-18")
        let stub = StubHTTPClient([CNBEndpoints.daily(sunday): try cnbBytes("cnb_denni_live_2026-10-16")])
        let daily = try await CNBFetcher(http: stub).fetchDay(sunday)
        #expect(daily.declaredOn == civilDate("2026-10-16"))
        #expect(daily.rows.allSatisfy { $0.declaredOn == civilDate("2026-10-16") })
    }

    @Test func aFailedRequestFailsTheFetch() async {
        let day = civilDate("2026-10-16")
        let offline = StubHTTPClient(failures: [
            CNBEndpoints.daily(day): HTTPError.offline, CNBEndpoints.yearly(2026): HTTPError.offline,
        ])
        await #expect(throws: HTTPError.offline) { try await CNBFetcher(http: offline).fetchDay(day) }
        await #expect(throws: HTTPError.offline) { try await CNBFetcher(http: offline).fetchYear(2026) }
        // An address the server does not know answers 404.
        let missing = StubHTTPClient()
        await #expect(throws: HTTPError.status(404)) { try await CNBFetcher(http: missing).fetchDay(day) }
        await #expect(throws: HTTPError.status(404)) { try await CNBFetcher(http: missing).fetchYear(2026) }
    }

    @Test(arguments: [
        "<html><body><h1>Server error</h1></body></html>",  // a page of an error that answers 200
        "",
        "16.10.2026\nUSA|dolar|1|USD|21,622\n",
    ])
    func aFileThatIsNotInTheFormatFailsTheFetch(_ body: String) async {
        let day = civilDate("2026-10-16")
        let stub = StubHTTPClient([
            CNBEndpoints.daily(day): Data(body.utf8), CNBEndpoints.yearly(2026): Data(body.utf8),
        ])
        await #expect(throws: CNBParseError.malformedHeader) { try await CNBFetcher(http: stub).fetchDay(day) }
        await #expect(throws: CNBParseError.malformedHeader) { try await CNBFetcher(http: stub).fetchYear(2026) }
    }

    @Test func bytesThatAreNotTextInAnyOfTheTwoEncodingsFailTheFetch() async {
        // 0x81 is not a character of Windows-1250, and a lone 0x81 is not UTF-8 either.
        let day = civilDate("2026-10-16")
        let stub = StubHTTPClient([CNBEndpoints.daily(day): Data([0x31, 0x36, 0x81, 0x0A])])
        await #expect(throws: CNBParseError.malformedHeader) { try await CNBFetcher(http: stub).fetchDay(day) }
    }

    // MARK: GFŘ: finding the announcement

    private let index2026 = webURL("https://mf.gov.cz/cs/dane-a-ucetnictvi/financni-zpravodaj/2026")
    private let pdfOfIssue2 = webURL(
        "https://mf.gov.cz/assets/attachments/2026-01-14_Financni-zpravodaj-cislo-2-2026.pdf")

    /// The numbers of the CMS in the addresses of the issues of 2026.
    private static let issueIDs = [
        1: 62457, 2: 62472, 3: 62787, 4: 62809, 5: 63397, 6: 63429, 7: 63592, 8: 63672, 9: 63824, 10: 64098,
        11: 64454, 12: 65270,
    ]

    private func issue(_ number: Int) -> URL {
        guard let id = Self.issueIDs[number] else { preconditionFailure("No issue \(number) in 2026.") }
        return webURL(
            "https://mf.gov.cz/cs/dane-a-ucetnictvi/financni-zpravodaj/2026/"
                + "financni-zpravodaj-cislo-\(number)-2026-\(id)")
    }

    /// An issue that announces something else.
    private let pageWithoutTheAnnouncement = Data(
        """
        <html><head><title>Finanční zpravodaj číslo 1/2026</title></head>
        <body><ol><li>Sdělení o vydání tiskopisů pro daň z příjmů</li></ol></body></html>
        """.utf8)

    /// An index page that links the issues `numbers`, in that order.
    private func indexPage(listing numbers: [Int]) -> Data {
        let links = numbers.map { "<a href=\"\(issue($0).path)\">Finanční zpravodaj</a>" }.joined()
        return Data(("<html>" + links + "</html>").utf8)
    }

    /// The page of an issue that announces the uniform rates of 2025 and links the PDFs `hrefs`, in that order.
    private func announcingPage(linking hrefs: [String]) -> Data {
        let links = hrefs.map { "<li><a href=\"\($0)\">PDF</a></li>" }.joined()
        return Data(
            """
            <html><head><title>Finanční zpravodaj číslo 2/2026</title></head><body>
            <ol><li>Pokyn č. GFŘ-D-75 Stanovení jednotných kurzů za zdaňovací období 2025</li></ol><ul>\(links)</ul>
            </body></html>
            """.utf8)
    }

    /// What the server has in January 2026: the index of the issues, an issue without the announcement, the issue with
    /// it and its PDF. The other issues are not there, so a request for one would fail with 404.
    private func januaryServer(pdf: Data) throws -> StubHTTPClient {
        StubHTTPClient([
            index2026: try gfrFixtureData("gfr_index_2026", "html"),
            issue(1): pageWithoutTheAnnouncement,
            issue(2): try gfrFixtureData("gfr_issue_2_2026", "html"),
            pdfOfIssue2: pdf,
        ])
    }

    private func found(_ outcome: GFROutcome) throws -> GFRFinding {
        guard case .found(let finding) = outcome else {
            throw FetcherTestsError.unexpected("\(outcome)")
        }
        return finding
    }

    private func unreadable(_ outcome: GFROutcome) throws -> (issue: URL, reason: String) {
        guard case .unreadable(let issue, let reason) = outcome else {
            throw FetcherTestsError.unexpected("\(outcome)")
        }
        return (issue, reason)
    }

    @Test func theAnnouncementIsFoundInTheSecondIssueAndItsPDFIsRead() async throws {
        let stub = try januaryServer(pdf: try gfrFixtureData("gfr_issue_2_2026", "pdf"))
        let outcome = try await GFRFetcher(http: stub).find(year: 2025, alreadyChecked: [])
        let finding = try found(outcome)
        #expect(finding.year == 2025)
        #expect(finding.instruction == "GFŘ-D-75")
        #expect(finding.issueURL == issue(2))
        #expect(finding.pdfURL == pdfOfIssue2)
        #expect(finding.rates.count == 31)
        #expect(
            finding.rates.first { $0.currency == .usd }
                == UniformRateEntry(currency: .usd, amount: 1, rate: decimal("21.84")))
        #expect(Set(finding.rates) == Set(BuiltInUniformRates.rates(year: 2025)))
        // The index, the issues oldest first up to the announcement, and then its PDF. Nothing else is asked.
        #expect(stub.requests == [index2026, issue(1), issue(2), pdfOfIssue2])
    }

    @Test func anIssueThatWasCheckedBeforeIsNotAskedForAgain() async throws {
        let stub = try januaryServer(pdf: try gfrFixtureData("gfr_issue_2_2026", "pdf"))
        let outcome = try await GFRFetcher(http: stub).find(year: 2025, alreadyChecked: [issue(1)])
        #expect(try found(outcome).issueURL == issue(2))
        #expect(stub.requests == [index2026, issue(2), pdfOfIssue2])
    }

    /// The index of the fixture lists the issues newest first. The checks go oldest first whichever way it is listed.
    @Test(arguments: [[1, 2], [2, 1]])
    func theIssuesAreCheckedOldestFirstWhateverTheOrderOfTheIndex(_ listed: [Int]) async throws {
        let index = listed.map { "<a href=\"\(issue($0).path)\">Finanční zpravodaj</a>" }.joined()
        let stub = StubHTTPClient([
            index2026: Data(("<html>" + index + "</html>").utf8),
            issue(1): pageWithoutTheAnnouncement,
            issue(2): try gfrFixtureData("gfr_issue_2_2026", "html"),
            pdfOfIssue2: try gfrFixtureData("gfr_issue_2_2026", "pdf"),
        ])
        _ = try await GFRFetcher(http: stub).find(year: 2025, alreadyChecked: [])
        #expect(stub.requests == [index2026, issue(1), issue(2), pdfOfIssue2])
    }

    @Test func nothingAnnouncedYetGivesTheIssuesThatWereChecked() async throws {
        let index = [1, 2].map { "<a href=\"\(issue($0).path)\">Finanční zpravodaj</a>" }.joined()
        let stub = StubHTTPClient([
            index2026: Data(("<html>" + index + "</html>").utf8),
            issue(1): pageWithoutTheAnnouncement,
            issue(2): pageWithoutTheAnnouncement,
        ])
        let outcome = try await GFRFetcher(http: stub).find(year: 2025, alreadyChecked: [])
        #expect(outcome == .notYet(checkedIssues: [issue(1), issue(2)]))
        #expect(stub.requests == [index2026, issue(1), issue(2)])
    }

    @Test func issuesThatWereCheckedBeforeStayChecked() async throws {
        let index = [1, 2].map { "<a href=\"\(issue($0).path)\">Finanční zpravodaj</a>" }.joined()
        let stub = StubHTTPClient([
            index2026: Data(("<html>" + index + "</html>").utf8),
            issue(2): pageWithoutTheAnnouncement,
        ])
        let outcome = try await GFRFetcher(http: stub).find(year: 2025, alreadyChecked: [issue(1)])
        #expect(outcome == .notYet(checkedIssues: [issue(1), issue(2)]))
        #expect(stub.requests == [index2026, issue(2)])
    }

    @Test func aCallChecksAtMostSixIssuesOldestFirst() async throws {
        let pages = Dictionary(uniqueKeysWithValues: (1...12).map { (issue($0), pageWithoutTheAnnouncement) })
        let stub = StubHTTPClient(
            pages.merging([index2026: try gfrFixtureData("gfr_index_2026", "html")]) { first, _ in first })
        let fetcher = GFRFetcher(http: stub)

        let first = try await fetcher.find(year: 2025, alreadyChecked: [])
        #expect(first == .notYet(checkedIssues: Set((1...6).map(issue))))
        #expect(stub.requests == [index2026] + (1...6).map(issue))

        let second = try await fetcher.find(year: 2025, alreadyChecked: Set((1...6).map(issue)))
        #expect(second == .notYet(checkedIssues: Set((1...12).map(issue))))
        #expect(stub.requests.dropFirst(7) == ([index2026] + (7...12).map(issue))[...])

        // Everything is checked: only the index is asked for.
        let third = try await fetcher.find(year: 2025, alreadyChecked: Set((1...12).map(issue)))
        #expect(third == .notYet(checkedIssues: Set((1...12).map(issue))))
        #expect(stub.requests.count == 7 + 7 + 1)
    }

    @Test func theAnnouncementPastTheSixthIssueIsFoundByALaterCall() async throws {
        var pages = Dictionary(uniqueKeysWithValues: (1...12).map { (issue($0), pageWithoutTheAnnouncement) })
        pages[issue(8)] = try gfrFixtureData("gfr_issue_2_2026", "html")
        pages[index2026] = try gfrFixtureData("gfr_index_2026", "html")
        pages[pdfOfIssue2] = try gfrFixtureData("gfr_issue_2_2026", "pdf")
        let stub = StubHTTPClient(pages)
        let fetcher = GFRFetcher(http: stub)
        let firstSix = Set((1...6).map(issue))
        #expect(try await fetcher.find(year: 2025, alreadyChecked: []) == .notYet(checkedIssues: firstSix))
        let outcome = try await fetcher.find(year: 2025, alreadyChecked: firstSix)
        #expect(try found(outcome).issueURL == issue(8))
    }

    @Test func aYearWithoutIssuesYetHasNothingAnnounced() async throws {
        let index2027 = webURL("https://mf.gov.cz/cs/dane-a-ucetnictvi/financni-zpravodaj/2027")
        // The index of a new year lists no issue yet, but it is a page of the section and links to it.
        let page =
            "<html><body><a href=\"/cs/dane-a-ucetnictvi/financni-zpravodaj\">Finanční zpravodaj</a></body></html>"
        let stub = StubHTTPClient([index2027: Data(page.utf8)])
        let outcome = try await GFRFetcher(http: stub).find(year: 2026, alreadyChecked: [issue(1)])
        #expect(outcome == .notYet(checkedIssues: [issue(1)]))
        #expect(stub.requests == [index2027])
    }

    @Test func aPDFThatIsNotAPDFIsUnreadable() async throws {
        for body in [Data("<html>Not found</html>".utf8), Data(), Data("%PDF-1.4\n".utf8)] {
            let stub = try januaryServer(pdf: body)
            let outcome = try await GFRFetcher(http: stub).find(year: 2025, alreadyChecked: [])
            let result = try unreadable(outcome)
            #expect(result.issue == issue(2))
            #expect(!result.reason.isEmpty)
            #expect(stub.requests == [index2026, issue(1), issue(2), pdfOfIssue2])
        }
    }

    @Test func aPDFWithoutTextOrWithoutTheRatesIsUnreadable() async throws {
        let pdfs = [
            makePDF(lines: []),
            makePDF(lines: ["Finanční zpravodaj 02/2026", "Sdělení o vydání tiskopisů"]),
            // The instruction, without a table.
            makePDF(lines: [
                "Pokyn č. GFŘ-D-75", "Stanovení jednotných kurzů za zdaňovací období 2025 podle § 38 zákona",
            ]),
            // A table, without the instruction.
            makePDF(lines: ["Země Měna Množství Kód Průměr", "EMU euro 1 EUR 24,66"]),
            // The instruction and the table of another year.
            makePDF(lines: [
                "Pokyn č. GFŘ-D-65", "Stanovení jednotných kurzů za zdaňovací období 2024 podle § 38 zákona",
                "EMU euro 1 EUR 25,16",
            ]),
        ]
        for pdf in pdfs {
            let outcome = try await GFRFetcher(http: try januaryServer(pdf: pdf)).find(year: 2025, alreadyChecked: [])
            let result = try unreadable(outcome)
            #expect(result.issue == issue(2))
            #expect(!result.reason.isEmpty)
        }
    }

    @Test func aPDFWithTheTableAndTheInstructionIsReadLikeTheRealOne() async throws {
        let pdf = makePDF(lines: [
            "Pokyn č. GFŘ-D-99", "Stanovení jednotných kurzů za zdaňovací období 2025 podle § 38 zákona",
            "EMU euro 1 EUR 24,66", "Japonsko jen 100 JPY 14,59",
        ])
        let fetcher = GFRFetcher(http: try januaryServer(pdf: pdf))
        let finding = try found(try await fetcher.find(year: 2025, alreadyChecked: []))
        #expect(finding.instruction == "GFŘ-D-99")
        #expect(
            finding.rates == [
                UniformRateEntry(currency: .eur, amount: 1, rate: decimal("24.66")),
                UniformRateEntry(currency: CurrencyCode("JPY")!, amount: 100, rate: decimal("14.59")),
            ])
    }

    @Test func anIssueThatAnnouncesTheRatesButLinksNoPDFIsUnreadable() async throws {
        let page = announcingPage(linking: [])
        let stub = StubHTTPClient([
            index2026: try gfrFixtureData("gfr_index_2026", "html"), issue(1): page,
        ])
        let outcome = try await GFRFetcher(http: stub).find(year: 2025, alreadyChecked: [])
        let result = try unreadable(outcome)
        #expect(result.issue == issue(1))
        #expect(!result.reason.isEmpty)
        #expect(stub.requests == [index2026, issue(1)])
    }

    @Test func aPageThatIsNotTextIsUnreadable() async throws {
        let notText = Data([0x3C, 0x81, 0x3E])
        let brokenIndex = StubHTTPClient([index2026: notText])
        let indexOutcome = try await GFRFetcher(http: brokenIndex).find(year: 2025, alreadyChecked: [])
        #expect(try unreadable(indexOutcome).issue == index2026)

        let brokenIssue = StubHTTPClient([
            index2026: try gfrFixtureData("gfr_index_2026", "html"), issue(1): notText,
        ])
        let issueOutcome = try await GFRFetcher(http: brokenIssue).find(year: 2025, alreadyChecked: [])
        #expect(try unreadable(issueOutcome).issue == issue(1))
    }

    @Test func aPageInWindows1250IsRead() async throws {
        // The announcement, written in the other encoding the pages could come in.
        let page = String(
            decoding: announcingPage(linking: ["/assets/attachments/2026-01-14_Financni-zpravodaj-cislo-2-2026.pdf"]),
            as: UTF8.self)
        let bytes = try #require(page.data(using: .windowsCP1250))
        #expect(String(data: bytes, encoding: .utf8) == nil)
        let stub = StubHTTPClient([
            index2026: try gfrFixtureData("gfr_index_2026", "html"), issue(1): bytes,
            pdfOfIssue2: try gfrFixtureData("gfr_issue_2_2026", "pdf"),
        ])
        let outcome = try await GFRFetcher(http: stub).find(year: 2025, alreadyChecked: [])
        #expect(try found(outcome).issueURL == issue(1))
    }

    @Test(arguments: [
        "<html><body><h1>Údržba</h1><p>Stránky jsou dočasně nedostupné.</p></body></html>",
        "<html><body>503 Service Unavailable</body></html>",
        "",
    ])
    func anIndexThatIsNoPageOfTheSectionIsUnreadableNotNothingYet(_ page: String) async throws {
        // The server answers 200, but the page is not the index. That is not "no issue yet".
        let stub = StubHTTPClient([index2026: Data(page.utf8)])
        let outcome = try await GFRFetcher(http: stub).find(year: 2025, alreadyChecked: [issue(1)])
        let result = try unreadable(outcome)
        #expect(result.issue == index2026)
        #expect(!result.reason.isEmpty)
        #expect(stub.requests == [index2026])
    }

    @Test(arguments: [
        "<html><body><h1>Údržba</h1></body></html>",
        "<html><body>404 Not Found</body></html>",
        // The announcement alone does not make a page an issue of the Finanční zpravodaj.
        "<li>Pokyn č. GFŘ-D-75 Stanovení jednotných kurzů za zdaňovací období 2025</li>",
    ])
    func anIssuePageThatIsNoIssueIsUnreadableAndTheSearchStopsThere(_ page: String) async throws {
        let stub = StubHTTPClient([
            index2026: indexPage(listing: [1, 2, 3]),
            issue(1): pageWithoutTheAnnouncement,
            issue(2): Data(page.utf8),
            issue(3): pageWithoutTheAnnouncement,
        ])
        let outcome = try await GFRFetcher(http: stub).find(year: 2025, alreadyChecked: [])
        // The page is neither an issue that was checked (there is no `.notYet` to hold it) nor skipped.
        let result = try unreadable(outcome)
        #expect(result.issue == issue(2))
        #expect(!result.reason.isEmpty)
        #expect(stub.requests == [index2026, issue(1), issue(2)])
    }

    @Test func theNextPDFIsTriedWhenOneCannotBeRead() async throws {
        let first = webURL("https://mf.gov.cz/assets/attachments/first.pdf")
        let second = webURL("https://mf.gov.cz/assets/attachments/second.pdf?download=1")
        let stub = StubHTTPClient([
            index2026: indexPage(listing: [1, 2]),
            issue(1): pageWithoutTheAnnouncement,
            issue(2): announcingPage(linking: [
                "/assets/attachments/first.pdf", "https://mf.gov.cz/assets/attachments/second.pdf?download=1",
            ]),
            first: makePDF(lines: ["Finanční zpravodaj 02/2026", "Sdělení o vydání tiskopisů"]),
            second: try gfrFixtureData("gfr_issue_2_2026", "pdf"),
        ])
        let finding = try found(try await GFRFetcher(http: stub).find(year: 2025, alreadyChecked: []))
        #expect(finding.issueURL == issue(2))
        #expect(finding.pdfURL == second)
        #expect(finding.instruction == "GFŘ-D-75")
        #expect(Set(finding.rates) == Set(BuiltInUniformRates.rates(year: 2025)))
        #expect(stub.requests == [index2026, issue(1), issue(2), first, second])
    }

    @Test func thePDFsAfterTheOneThatIsReadAreNotAskedFor() async throws {
        let first = webURL("https://mf.gov.cz/assets/attachments/first.pdf")
        let stub = StubHTTPClient([
            index2026: indexPage(listing: [2]),
            issue(2): announcingPage(linking: ["/assets/attachments/first.pdf", "/assets/attachments/second.pdf"]),
            first: try gfrFixtureData("gfr_issue_2_2026", "pdf"),
        ])
        let finding = try found(try await GFRFetcher(http: stub).find(year: 2025, alreadyChecked: []))
        #expect(finding.pdfURL == first)
        #expect(stub.requests == [index2026, issue(2), first])
    }

    @Test func anIssueWhoseEveryPDFCannotBeReadIsUnreadable() async throws {
        let first = webURL("https://mf.gov.cz/assets/attachments/first.pdf")
        let second = webURL("https://mf.gov.cz/assets/attachments/second.pdf")
        let stub = StubHTTPClient([
            index2026: indexPage(listing: [2]),
            issue(2): announcingPage(linking: ["/assets/attachments/first.pdf", "/assets/attachments/second.pdf"]),
            first: Data("<html>Not found</html>".utf8),
            second: makePDF(lines: ["Pokyn č. GFŘ-D-65", "Stanovení jednotných kurzů za zdaňovací období 2024"]),
        ])
        let result = try unreadable(try await GFRFetcher(http: stub).find(year: 2025, alreadyChecked: []))
        #expect(result.issue == issue(2))
        #expect(!result.reason.isEmpty)
        #expect(stub.requests == [index2026, issue(2), first, second])
    }

    @Test func aFailureThatIsNoHTTPErrorPassesThroughTheFetchersAsItIs() async {
        // A TLS failure, a cancellation or a response that is no HTTP escapes the client as its own error.
        let failure = URLError(.secureConnectionFailed)
        let day = civilDate("2026-10-16")
        let stub = StubHTTPClient(failures: [index2026: failure, CNBEndpoints.daily(day): failure])
        await #expect(
            performing: { try await GFRFetcher(http: stub).find(year: 2025, alreadyChecked: []) },
            throws: { ($0 as? URLError)?.code == .secureConnectionFailed })
        await #expect(
            performing: { try await CNBFetcher(http: stub).fetchDay(day) },
            throws: { ($0 as? URLError)?.code == .secureConnectionFailed })
    }

    @Test func aFailedRequestFailsTheSearch() async throws {
        // No connection at all.
        let offline = GFRFetcher(http: StubHTTPClient(failures: [index2026: HTTPError.offline]))
        await #expect(throws: HTTPError.offline) { try await offline.find(year: 2025, alreadyChecked: []) }
        // An index that does not exist.
        await #expect(throws: HTTPError.status(404)) {
            try await GFRFetcher(http: StubHTTPClient()).find(year: 2025, alreadyChecked: [])
        }
        // An issue that cannot be loaded.
        let issueDown = StubHTTPClient(
            [index2026: try gfrFixtureData("gfr_index_2026", "html")], failures: [issue(1): HTTPError.status(503)])
        await #expect(throws: HTTPError.status(503)) {
            try await GFRFetcher(http: issueDown).find(year: 2025, alreadyChecked: [])
        }
        // A PDF that cannot be loaded.
        let pdfDown = StubHTTPClient(
            [
                index2026: try gfrFixtureData("gfr_index_2026", "html"), issue(1): pageWithoutTheAnnouncement,
                issue(2): try gfrFixtureData("gfr_issue_2_2026", "html"),
            ], failures: [pdfOfIssue2: HTTPError.offline])
        await #expect(throws: HTTPError.offline) {
            try await GFRFetcher(http: pdfDown).find(year: 2025, alreadyChecked: [])
        }
    }

    @Test func aFindingAndItsOutcomesCanBeComparedAndKept() throws {
        let finding = GFRFinding(
            year: 2025, instruction: "GFŘ-D-75", issueURL: issue(2), pdfURL: pdfOfIssue2,
            rates: [UniformRateEntry(currency: .usd, amount: 1, rate: decimal("21.84"))])
        let outcomes: Set<GFROutcome> = [
            .found(finding), .notYet(checkedIssues: [issue(1)]), .unreadable(issue(2), "reason"),
        ]
        #expect(outcomes.count == 3)
        #expect(outcomes.contains(.found(finding)))
        #expect(!outcomes.contains(.notYet(checkedIssues: [])))
    }
}

private enum FetcherTestsError: Error {
    case unexpected(String)
}
