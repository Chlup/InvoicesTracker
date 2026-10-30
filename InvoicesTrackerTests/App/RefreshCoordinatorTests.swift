import Foundation
import Testing
import os
@testable import InvoicesTracker

/// The refresh coordinator, driven by `refresh(_:)` with a manual clock, a manual scheduler, a stub server and a
/// temporary database: what it asks the servers for, what it stores, what it tells the app and when it wakes next.
/// Prague is UTC+2 until 25 October 2026 and UTC+1 after it; it is UTC+2 again from 28 March 2027.
@MainActor
struct RefreshCoordinatorTests {
    // MARK: Helpers

    /// What the coordinator told the app, in order.
    @MainActor
    private final class Calls {
        var daysChanged: [CivilDate] = []
        var ratesUpdated = 0
        var found: [GFRFinding] = []
        var reminders: [Int] = []
    }

    /// What the app around the coordinator says, which a test can change: whether "K datu" follows today, and the
    /// time zone of the Mac.
    @MainActor
    private final class Shell {
        var followsToday: Bool
        var timeZone: TimeZone

        init(followsToday: Bool, timeZone: TimeZone) {
            self.followsToday = followsToday
            self.timeZone = timeZone
        }
    }

    /// A coordinator, the clock and the timer it runs on, the app around it, and what it told the app.
    private struct Rig {
        let coordinator: RefreshCoordinator
        let clock: ManualClock
        let scheduler: ManualScheduler
        let shell: Shell
        let calls: Calls
    }

    /// A coordinator that asks `server` and keeps its data in `database`. The current year is the year of today in
    /// the time zone of the shell, as the app has it.
    private func makeRig(
        at now: String, server: any HTTPClient, database: Database, followsToday: Bool = false,
        timeZone: TimeZone = CzechCalendar.prague
    ) -> Rig {
        let clock = ManualClock(date(now))
        let scheduler = ManualScheduler()
        let shell = Shell(followsToday: followsToday, timeZone: timeZone)
        let calls = Calls()
        let coordinator = RefreshCoordinator(
            clock: clock, scheduler: scheduler, cnb: CNBFetcher(http: server), gfr: GFRFetcher(http: server),
            database: database, currentYear: { CivilDate.today(now: clock.now(), timeZone: shell.timeZone).year },
            followsToday: { shell.followsToday }, timeZone: { shell.timeZone })
        coordinator.onDayChanged = { calls.daysChanged.append($0) }
        coordinator.onRatesUpdated = { calls.ratesUpdated += 1 }
        coordinator.onUniformRateFound = { calls.found.append($0) }
        coordinator.onUniformRateReminder = { calls.reminders.append($0) }
        return Rig(coordinator: coordinator, clock: clock, scheduler: scheduler, shell: shell, calls: calls)
    }

    /// A new database whose ČNB cache holds the rates of the yearly fixture of 2026 declared up to `last`, and whose
    /// uniform rates of `withoutUniformRateOf` are deleted. Pair it with `removeTemporaryDirectory(_:)`.
    private func databaseWithRates(
        through last: String, withoutUniformRateOf year: Int? = nil
    ) async throws -> (Database, URL) {
        let (database, directory) = try makeDatabase()
        do {
            try await database.insertCNBRates(try cnbYearlyRows([2026]).filter { $0.declaredOn <= civilDate(last) })
            if let year {
                try await database.saveUniformRates([], year: year)
            }
            return (database, directory)
        } catch {
            removeTemporaryDirectory(directory)
            throw error
        }
    }

    /// A new database for the spring of 2027: the rates of 2026 up to 16 October and an invented rate declared on
    /// `last`, so that the cache is current, and no uniform rate of 2026, which is not built in.
    private func databaseIn2027(ratesThrough last: String) async throws -> (Database, URL) {
        let (database, directory) = try await databaseWithRates(through: "2026-10-16")
        do {
            try await database.insertCNBRates([
                CNBRateRow(declaredOn: civilDate(last), currency: .usd, amount: 1, rate: decimal("21.5"))
            ])
            return (database, directory)
        } catch {
            removeTemporaryDirectory(directory)
            throw error
        }
    }

    private func daily(_ day: String) -> URL {
        CNBEndpoints.daily(civilDate(day))
    }

    /// The daily file of `day` with the rates that the yearly fixture of 2026 has for `source` (`day` unless given), as
    /// if the ČNB had declared them on `day`.
    private func dailyFile(_ day: String, ratesOf source: String? = nil) throws -> Data {
        let declared = civilDate(day)
        let rows = try cnbYearlyRows([2026]).filter { $0.declaredOn == civilDate(source ?? day) }
        let redated = rows.map {
            CNBRateRow(declaredOn: declared, currency: $0.currency, amount: $0.amount, rate: $0.rate)
        }
        return cnbDailyFile(declaredOn: declared, rows: redated)
    }

    private func yearlyFile(_ year: Int) throws -> Data {
        try Data(contentsOf: fixtureURL("cnb_rok_\(year)", "txt"))
    }

    /// The yearly file of 2026 as it was on `last`: its header and the lines of the days up to `last`.
    private func yearlyFile2026(through last: String) throws -> Data {
        let lines = try cnbFixture("cnb_rok_2026").split(whereSeparator: \.isNewline)
        let kept = lines.filter { line in
            let parts = line.prefix(10).split(separator: ".")
            guard parts.count == 3 else { return true }
            return civilDate("\(parts[2])-\(parts[1])-\(parts[0])") <= civilDate(last)
        }
        return Data((kept.joined(separator: "\n") + "\n").utf8)
    }

    /// The lines of the uniform rates of 2025 and 2026 while they are not out.
    private let notOut2025 = "Jednotný kurz 2025: zatím nevyšel (kontrola od 2.\u{A0}1.\u{A0}2026)"
    private let notOut2026 = "Jednotný kurz 2026: zatím nevyšel (kontrola od 2.\u{A0}1.\u{A0}2027)"

    /// The index of the issues of 2026, where the uniform rates of 2025 are announced.
    private let index2026 = GFRParser.indexURL(forYear: 2025)

    /// The issues the index fixture links, oldest first.
    private func issues() throws -> [URL] {
        GFRParser.issueLinks(indexHTML: try gfrFixture("gfr_index_2026", "html"), publicationYear: 2026)
    }

    /// The PDF of the second issue of 2026, which has the table of 2025.
    private func pdfURL() throws -> URL {
        try #require(GFRParser.pdfLink(issueHTML: try gfrFixture("gfr_issue_2_2026", "html")))
    }

    /// An issue of the Finanční zpravodaj that announces something else.
    private let issueWithoutTheRates = Data(
        """
        <html><head><title>Finanční zpravodaj číslo 1/2026</title></head>
        <body><ol><li>Sdělení o vydání tiskopisů pro daň z příjmů</li></ol></body></html>
        """.utf8)

    /// An index that lists only the first issue of 2026.
    private func indexOfTheFirstIssue() throws -> Data {
        Data("<html><a href=\"\(try issues()[0].path)\">Finanční zpravodaj</a></html>".utf8)
    }

    /// The server in January 2026: the index of the issues of 2026, the first issue (which announces something else),
    /// the second one (which announces the rates of 2025) and `pdf` as its PDF.
    private func januaryServer(pdf: Data) throws -> StubHTTPClient {
        let issues = try issues()
        let pdfURL = try pdfURL()
        return StubHTTPClient([
            index2026: try gfrFixtureData("gfr_index_2026", "html"),
            issues[0]: issueWithoutTheRates,
            issues[1]: try gfrFixtureData("gfr_issue_2_2026", "html"),
            pdfURL: pdf,
        ])
    }

    /// The index of the issues of 2027, where the uniform rates of 2026 are announced.
    private let index2027 = GFRParser.indexURL(forYear: 2026)

    /// An invented server of 2027 on which the uniform rates of 2026 are out: an index with one issue that announces
    /// them, and its PDF with an invented instruction and two rates.
    private func serverWithTheRatesOf2026() -> StubHTTPClient {
        let issue = webURL(
            "https://mf.gov.cz/cs/dane-a-ucetnictvi/financni-zpravodaj/2027/financni-zpravodaj-cislo-2-2027-70001")
        let pdf = webURL("https://mf.gov.cz/assets/attachments/2027-01-13_Financni-zpravodaj-cislo-2-2027.pdf")
        let issuePage = """
            <html><head><title>Finanční zpravodaj číslo 2/2027</title></head><body>
            <ol><li>Pokyn č. GFŘ-D-99 Stanovení jednotných kurzů za zdaňovací období 2026</li></ol>
            <a href="\(pdf.path)">PDF</a></body></html>
            """
        return StubHTTPClient([
            index2027: Data("<html><a href=\"\(issue.path)\">Finanční zpravodaj</a></html>".utf8),
            issue: Data(issuePage.utf8),
            pdf: makePDF(lines: [
                "Pokyn č. GFŘ-D-99", "Stanovení jednotných kurzů za zdaňovací období 2026 podle § 38 zákona",
                "EMU euro 1 EUR 24,30", "USA dolar 1 USD 20,90",
            ]),
        ])
    }

    // MARK: ČNB rates

    @Test func theLaunchFetchesTheMissingDaysOneByOneAndStoresThem() async throws {
        let (database, directory) = try await databaseWithRates(through: "2026-10-14")
        defer { removeTemporaryDirectory(directory) }
        let server = StubHTTPClient([
            daily("2026-10-15"): try dailyFile("2026-10-15"),
            daily("2026-10-16"): try Data(contentsOf: fixtureURL("cnb_denni_live_2026-10-16", "txt")),
        ])
        let rig = makeRig(at: "2026-10-16T13:00:00Z", server: server, database: database)

        await rig.coordinator.refresh(.launch)

        #expect(server.requests == [daily("2026-10-15"), daily("2026-10-16")])
        #expect(try await database.newestCNBDeclaration() == civilDate("2026-10-16"))
        #expect(try await database.integer("SELECT count(*) FROM cnb_rate WHERE declared_on >= '2026-10-15'") == 60)
        #expect(rig.calls.ratesUpdated == 1)
        #expect(rig.coordinator.status.cnbUpToDate == civilDate("2026-10-16"))
        #expect(rig.coordinator.status.cnbFetchedAt == date("2026-10-16T13:00:00Z"))
        #expect(rig.coordinator.status.cnbText == "Kurzy ČNB: aktuální k 16.\u{A0}10.\u{A0}2026 (staženo 15:00)")
        #expect(rig.coordinator.status.lastError == nil)
        let log = try await database.recentFetchLog(limit: 10)
        #expect(log.map(\.target) == [daily("2026-10-16").absoluteString, daily("2026-10-15").absoluteString])
        #expect(log.allSatisfy { $0.kind == .cnbDaily && $0.ok && $0.message.isEmpty })
        #expect(try await database.refreshState()?.newestCNBDeclaration == civilDate("2026-10-16"))
    }

    @Test func wakingOnMondayAfterSleepingSinceFridayFetchesOnlyMondaysRates() async throws {
        let (database, directory) = try await databaseWithRates(through: "2026-10-14")
        defer { removeTemporaryDirectory(directory) }
        let server = StubHTTPClient([
            daily("2026-10-15"): try dailyFile("2026-10-15"),
            daily("2026-10-16"): try dailyFile("2026-10-16"),
            // Invented: Friday's rates, declared again on Monday.
            daily("2026-10-19"): try dailyFile("2026-10-19", ratesOf: "2026-10-16"),
        ])
        let rig = makeRig(at: "2026-10-16T13:00:00Z", server: server, database: database)
        await rig.coordinator.refresh(.launch)

        rig.clock.set(date("2026-10-19T13:00:00Z"))
        await rig.coordinator.refresh(.wake)

        #expect(Array(server.requests.dropFirst(2)) == [daily("2026-10-19")])
        #expect(try await database.newestCNBDeclaration() == civilDate("2026-10-19"))
        #expect(rig.calls.daysChanged == [civilDate("2026-10-19")])
        #expect(rig.calls.ratesUpdated == 2)
        #expect(rig.coordinator.status.cnbText == "Kurzy ČNB: aktuální k 19.\u{A0}10.\u{A0}2026 (staženo 15:00)")
    }

    @Test func aLongGapIsFilledFromTheYearlyFile() async throws {
        let (database, directory) = try await databaseWithRates(through: "2026-09-01")
        defer { removeTemporaryDirectory(directory) }
        let server = StubHTTPClient([CNBEndpoints.yearly(2026): try yearlyFile(2026)])
        let rig = makeRig(at: "2026-10-16T13:00:00Z", server: server, database: database)

        await rig.coordinator.refresh(.launch)

        #expect(server.requests == [CNBEndpoints.yearly(2026)])
        #expect(try await database.newestCNBDeclaration() == civilDate("2026-10-16"))
        #expect(try await database.integer("SELECT count(*) FROM cnb_rate") == 200 * 30)
        #expect(rig.calls.ratesUpdated == 1)
        let log = try await database.recentFetchLog(limit: 10)
        #expect(log.count == 1)
        #expect(log.first?.kind == .cnbYearly)
        #expect(log.first?.target == CNBEndpoints.yearly(2026).absoluteString)
        #expect(log.first?.ok == true)
    }

    @Test func yearlyFilesThatAScreenAsksForAreStoredLoggedAndAnnounced() async throws {
        let (database, directory) = try await databaseWithRates(through: "2026-10-16")
        defer { removeTemporaryDirectory(directory) }
        let server = StubHTTPClient([CNBEndpoints.yearly(2022): try yearlyFile(2022)])
        let rig = makeRig(at: "2026-10-17T10:00:00Z", server: server, database: database)
        let before = try await database.cnbRate(.usd, on: civilDate("2022-06-30"))
        #expect(before == .notYetAvailable)

        let stored = await rig.coordinator.fetchYears([2022])

        #expect(stored)
        #expect(server.requests == [CNBEndpoints.yearly(2022)])
        // The hole is filled, and the newest declaration is what it was.
        guard case .declared(_, let declaredOn) = try await database.cnbRate(.usd, on: civilDate("2022-06-30")) else {
            Issue.record("The rate of 30. 6. 2022 is still not declared")
            return
        }
        #expect(declaredOn == civilDate("2022-06-30"))
        #expect(try await database.newestCNBDeclaration() == civilDate("2026-10-16"))
        #expect(rig.calls.ratesUpdated == 1)
        let log = try await database.recentFetchLog(limit: 10)
        #expect(log.count == 1)
        #expect(log.first?.kind == .cnbYearly)
        #expect(log.first?.target == CNBEndpoints.yearly(2022).absoluteString)
        #expect(log.first?.ok == true)
    }

    @Test func aYearThatCannotBeFetchedIsLoggedAndStoresNothing() async throws {
        let (database, directory) = try await databaseWithRates(through: "2026-10-16")
        defer { removeTemporaryDirectory(directory) }
        let server = StubHTTPClient(failures: [CNBEndpoints.yearly(2022): HTTPError.offline])
        let rig = makeRig(at: "2026-10-17T10:00:00Z", server: server, database: database)

        let stored = await rig.coordinator.fetchYears([2022])

        #expect(stored == false)
        #expect(server.requests == [CNBEndpoints.yearly(2022)])
        #expect(rig.calls.ratesUpdated == 0)
        let log = try await database.recentFetchLog(limit: 10)
        #expect(log.count == 1)
        #expect(log.first?.ok == false)
        #expect(log.first?.message == "offline")
    }

    @Test func aYearThatFailsDoesNotKeepTheOthersFromBeingFetched() async throws {
        let (database, directory) = try await databaseWithRates(through: "2026-10-16")
        defer { removeTemporaryDirectory(directory) }
        let server = StubHTTPClient(
            [CNBEndpoints.yearly(2025): try yearlyFile(2025)], failures: [CNBEndpoints.yearly(2022): HTTPError.offline])
        let rig = makeRig(at: "2026-10-17T10:00:00Z", server: server, database: database)

        let stored = await rig.coordinator.fetchYears([2022, 2025])

        #expect(stored)
        #expect(server.requests == [CNBEndpoints.yearly(2022), CNBEndpoints.yearly(2025)])
        #expect(rig.calls.ratesUpdated == 1)
        let log = try await database.recentFetchLog(limit: 10)
        #expect(Set(log.map(\.ok)) == [true, false])
        #expect(log.count == 2)
    }

    @Test(.hangGuard)
    func aCoordinatorThatIsStoppedWhileAFileIsOnItsWayStoresNothingAndSaysNothing() async throws {
        let (database, directory) = try await databaseWithRates(through: "2026-10-16")
        defer { removeTemporaryDirectory(directory) }
        let gate = Gate()
        let stub = StubHTTPClient([CNBEndpoints.yearly(2022): try yearlyFile(2022)])
        let server = GatedHTTPClient(base: stub, gate: gate)
        let rig = makeRig(at: "2026-10-17T10:00:00Z", server: server, database: database)
        let fetching = Task { await rig.coordinator.fetchYears([2022]) }
        await gate.untilARequestWaits()

        rig.coordinator.stop()
        await gate.open()
        let stored = await fetching.value

        #expect(stored == false)
        #expect(rig.calls.ratesUpdated == 0)
        #expect(try await database.cnbRate(.usd, on: civilDate("2022-06-30")) == .notYetAvailable)
        // The request was made and its answer read, so it is in the log all the same.
        let log = try await database.recentFetchLog(limit: 5)
        #expect(log.count == 1)
        #expect(log.first?.ok == true)
    }

    @Test(.hangGuard)
    func ratesThatCannotBeStoredAreNotCountedAndNothingIsToldToTheApp() async throws {
        let (database, directory) = try await databaseWithRates(through: "2026-10-16")
        defer { removeTemporaryDirectory(directory) }
        let gate = Gate()
        let stub = StubHTTPClient([CNBEndpoints.yearly(2022): try yearlyFile(2022)])
        let server = GatedHTTPClient(base: stub, gate: gate)
        let rig = makeRig(at: "2026-10-17T10:00:00Z", server: server, database: database)
        let fetching = Task { await rig.coordinator.fetchYears([2022]) }
        await gate.untilARequestWaits()

        // The data cannot be written to when the file arrives.
        await database.close()
        await gate.open()
        let stored = await fetching.value

        #expect(stored == false)
        #expect(rig.calls.ratesUpdated == 0)
    }

    @Test func aCoordinatorThatIsStoppedFetchesNoYears() async throws {
        let (database, directory) = try await databaseWithRates(through: "2026-10-16")
        defer { removeTemporaryDirectory(directory) }
        let server = StubHTTPClient([CNBEndpoints.yearly(2022): try yearlyFile(2022)])
        let rig = makeRig(at: "2026-10-17T10:00:00Z", server: server, database: database)
        rig.coordinator.stop()

        let stored = await rig.coordinator.fetchYears([2022])

        #expect(stored == false)
        #expect(server.requests.isEmpty)
    }

    @Test func anEmptyCacheThatCannotBeFilledSaysSo() async throws {
        let (database, directory) = try makeDatabase()
        defer { removeTemporaryDirectory(directory) }
        let server = StubHTTPClient(failures: [CNBEndpoints.yearly(2026): HTTPError.offline])
        let rig = makeRig(at: "2026-10-16T13:00:00Z", server: server, database: database)

        await rig.coordinator.refresh(.launch)

        #expect(server.requests == [CNBEndpoints.yearly(2026)])
        #expect(rig.coordinator.status.cnbUpToDate == nil)
        #expect(rig.coordinator.status.cnbText == "Kurzy ČNB: zatím nestaženy")
        #expect(rig.coordinator.status.lastError == "Kurzy ČNB se nepodařilo stáhnout: není připojení k internetu.")
    }

    @Test func aNetworkErrorIsShownAndTheNextAttemptIsHalfAnHourLater() async throws {
        let (database, directory) = try await databaseWithRates(through: "2026-10-15")
        defer { removeTemporaryDirectory(directory) }
        let server = StubHTTPClient(failures: [daily("2026-10-16"): HTTPError.offline])
        let rig = makeRig(at: "2026-10-16T12:35:00Z", server: server, database: database)

        await rig.coordinator.refresh(.timer)

        #expect(server.requests == [daily("2026-10-16")])
        #expect(rig.coordinator.status.lastError == "Kurzy ČNB se nepodařilo stáhnout: není připojení k internetu.")
        #expect(rig.scheduler.armed == [date("2026-10-16T13:05:00Z")])
        #expect(rig.calls.ratesUpdated == 0)
        #expect(rig.coordinator.status.cnbText == "Kurzy ČNB: aktuální k 15.\u{A0}10.\u{A0}2026")
        let state = try #require(try await database.refreshState())
        #expect(state.cnbFailureCount == 1)
        #expect(state.lastCNBFailure == date("2026-10-16T12:35:00Z"))
        let log = try await database.recentFetchLog(limit: 10)
        #expect(log.count == 1)
        #expect(log.first?.ok == false)
        #expect(log.first?.message == "offline")
    }

    @Test func aDayThatFailsEndsTheFetchingSoThatNoLaterDayIsStoredAfterAHole() async throws {
        let (database, directory) = try await databaseWithRates(through: "2026-10-14")
        defer { removeTemporaryDirectory(directory) }
        let server = StubHTTPClient(
            [daily("2026-10-16"): try dailyFile("2026-10-16")], failures: [daily("2026-10-15"): HTTPError.status(503)])
        let rig = makeRig(at: "2026-10-16T13:00:00Z", server: server, database: database)

        await rig.coordinator.refresh(.launch)

        #expect(server.requests == [daily("2026-10-15")])
        #expect(try await database.newestCNBDeclaration() == civilDate("2026-10-14"))
        #expect(rig.calls.ratesUpdated == 0)
        #expect(rig.scheduler.armed == [date("2026-10-16T13:30:00Z")])
        let log = try await database.recentFetchLog(limit: 10)
        #expect(log.map(\.message) == ["status 503"])
    }

    @Test func theFailureCountOutlivesARelaunchAndASuccessfulFetchClearsItAndTheError() async throws {
        let (database, directory) = try await databaseWithRates(through: "2026-10-15")
        defer { removeTemporaryDirectory(directory) }
        let offline = StubHTTPClient(failures: [daily("2026-10-16"): HTTPError.offline])
        let first = makeRig(at: "2026-10-16T12:35:00Z", server: offline, database: database)
        await first.coordinator.refresh(.timer)
        // An activation within the half hour asks nothing.
        first.clock.set(date("2026-10-16T12:50:00Z"))
        await first.coordinator.refresh(.becameActive)
        #expect(offline.requests.count == 1)
        #expect(first.scheduler.armed == [date("2026-10-16T13:05:00Z")])
        first.coordinator.stop()

        let online = StubHTTPClient([daily("2026-10-16"): try dailyFile("2026-10-16")])
        let second = makeRig(at: "2026-10-16T12:55:00Z", server: online, database: database)
        await second.coordinator.refresh(.launch)
        #expect(online.requests.isEmpty)
        #expect(second.scheduler.armed == [date("2026-10-16T13:05:00Z")])

        second.clock.set(date("2026-10-16T13:05:00Z"))
        await second.coordinator.refresh(.timer)

        #expect(online.requests == [daily("2026-10-16")])
        #expect(second.calls.ratesUpdated == 1)
        #expect(second.coordinator.status.lastError == nil)
        let state = try #require(try await database.refreshState())
        #expect(state.cnbFailureCount == 0)
        #expect(state.lastCNBFailure == nil)
    }

    @Test func ratesThatAreNotOutYetAreTriedAgainAt1500() async throws {
        let (database, directory) = try await databaseWithRates(through: "2026-10-15")
        defer { removeTemporaryDirectory(directory) }
        // At 14:35 the ČNB still answers with Thursday's file.
        let server = StubHTTPClient([daily("2026-10-16"): try dailyFile("2026-10-15")])
        let rig = makeRig(at: "2026-10-16T12:35:00Z", server: server, database: database)

        await rig.coordinator.refresh(.timer)

        #expect(server.requests == [daily("2026-10-16")])
        #expect(rig.calls.ratesUpdated == 0)
        #expect(rig.coordinator.status.lastError == nil)
        #expect(rig.scheduler.armed == [date("2026-10-16T13:00:00Z")])
        #expect(try await database.refreshState()?.cnbRetrySlotsUsed == [civilDate("2026-10-16"): 1])
        let log = try await database.recentFetchLog(limit: 10)
        #expect(log.count == 1)
        #expect(log.first?.ok == true)
        #expect(log.first?.message == "declared 2026-10-15")
    }

    @Test func aManualRefreshTriesAgainAtOnceEvenWhileBackingOff() async throws {
        let (database, directory) = try await databaseWithRates(through: "2026-10-15")
        defer { removeTemporaryDirectory(directory) }
        let server = StubHTTPClient(failures: [daily("2026-10-16"): HTTPError.status(503)])
        let rig = makeRig(at: "2026-10-16T12:35:00Z", server: server, database: database)
        await rig.coordinator.refresh(.timer)
        rig.clock.set(date("2026-10-16T12:40:00Z"))
        await rig.coordinator.refresh(.becameActive)
        #expect(server.requests.count == 1)

        await rig.coordinator.refresh(.manual)

        #expect(server.requests.count == 2)
        #expect(rig.coordinator.status.lastError == "Kurzy ČNB se nepodařilo stáhnout: server odpověděl chybou 503.")
        #expect(try await database.refreshState()?.cnbFailureCount == 2)
        // An hour after the second failure.
        #expect(rig.scheduler.armed == [date("2026-10-16T13:40:00Z")])
    }

    @Test func aCurrentCacheAsksNothingOnTheWeekendAndWakesForTheFixingOnMonday() async throws {
        let (database, directory) = try await databaseWithRates(through: "2026-10-16")
        defer { removeTemporaryDirectory(directory) }
        let server = StubHTTPClient()
        let rig = makeRig(at: "2026-10-17T10:00:00Z", server: server, database: database)

        await rig.coordinator.refresh(.launch)

        #expect(server.requests.isEmpty)
        #expect(rig.scheduler.armed == [date("2026-10-19T12:35:00Z")])
        #expect(rig.calls.ratesUpdated == 0)
        #expect(rig.coordinator.status.cnbText == "Kurzy ČNB: aktuální k 16.\u{A0}10.\u{A0}2026")
        #expect(rig.coordinator.status.uniformYear == 2026)
        #expect(rig.coordinator.status.uniformText == notOut2026)
        #expect(try await database.recentFetchLog(limit: 10).isEmpty)
    }

    @Test func theTimeOfTheDownloadIsShownInTheTimeZoneOfTheMacWithoutALeadingZero() throws {
        let fetched = date("2026-10-19T07:05:00Z")
        let prague = RefreshStatus.cnbText(
            upToDate: civilDate("2026-10-16"), fetchedAt: fetched, timeZone: CzechCalendar.prague)
        #expect(prague == "Kurzy ČNB: aktuální k 16.\u{A0}10.\u{A0}2026 (staženo 9:05)")
        let newYork = try #require(TimeZone(identifier: "America/New_York"))
        let inNewYork = RefreshStatus.cnbText(upToDate: civilDate("2026-10-16"), fetchedAt: fetched, timeZone: newYork)
        #expect(inNewYork == "Kurzy ČNB: aktuální k 16.\u{A0}10.\u{A0}2026 (staženo 3:05)")
    }

    @Test func aRunWithAFailureBacksOffFurtherEvenWhenAnEarlierFileOfTheRunWasFetched() async throws {
        let (database, directory) = try await databaseWithRates(through: "2026-10-14")
        defer { removeTemporaryDirectory(directory) }
        // The ČNB declared nothing on Thursday, so its file is Wednesday's, and Friday's file cannot be had.
        let server = StubHTTPClient(
            [daily("2026-10-15"): try dailyFile("2026-10-14")], failures: [daily("2026-10-16"): HTTPError.status(503)])
        let rig = makeRig(at: "2026-10-16T13:00:00Z", server: server, database: database)

        await rig.coordinator.refresh(.launch)
        #expect(rig.scheduler.armed == [date("2026-10-16T13:30:00Z")])
        rig.clock.set(date("2026-10-16T13:30:00Z"))
        await rig.coordinator.refresh(.timer)
        #expect(rig.scheduler.armed == [date("2026-10-16T14:30:00Z")])
        rig.clock.set(date("2026-10-16T14:30:00Z"))
        await rig.coordinator.refresh(.timer)
        #expect(rig.scheduler.armed == [date("2026-10-19T12:35:00Z")])

        #expect(server.requests.count == 6)
        #expect(rig.calls.ratesUpdated == 0)
        #expect(try await database.refreshState()?.cnbFailureCount == 3)
    }

    @Test func theNetworkComingBackTriesAgainAtOnceAfterAFailureWithoutConnection() async throws {
        let (database, directory) = try await databaseWithRates(through: "2026-10-15")
        defer { removeTemporaryDirectory(directory) }
        let server = SwitchingHTTPClient(StubHTTPClient(failures: [daily("2026-10-16"): HTTPError.offline]))
        let rig = makeRig(at: "2026-10-16T12:35:00Z", server: server, database: database)
        // Woken before the Wi-Fi is up.
        await rig.coordinator.refresh(.wake)
        #expect(try await database.refreshState()?.cnbFailureCount == 1)
        let online = StubHTTPClient([daily("2026-10-16"): try dailyFile("2026-10-16")])
        server.switchTo(online)
        rig.clock.set(date("2026-10-16T12:36:00Z"))
        await rig.coordinator.refresh(.becameActive)
        #expect(online.requests.isEmpty)

        await rig.coordinator.refresh(.networkAvailable)

        #expect(online.requests == [daily("2026-10-16")])
        #expect(try await database.newestCNBDeclaration() == civilDate("2026-10-16"))
        #expect(rig.calls.ratesUpdated == 1)
        #expect(try await database.refreshState()?.cnbFailureCount == 0)
        #expect(rig.coordinator.status.lastError == nil)
    }

    @Test func aYearlyFileWithNothingNewerChangesNothingForTheApp() async throws {
        let (database, directory) = try await databaseWithRates(through: "2026-09-01")
        defer { removeTemporaryDirectory(directory) }
        // The yearly file of the ČNB has not got past 1 September.
        let server = StubHTTPClient([CNBEndpoints.yearly(2026): try yearlyFile2026(through: "2026-09-01")])
        let rig = makeRig(at: "2026-10-16T13:00:00Z", server: server, database: database)

        await rig.coordinator.refresh(.launch)

        #expect(server.requests == [CNBEndpoints.yearly(2026)])
        #expect(try await database.newestCNBDeclaration() == civilDate("2026-09-01"))
        #expect(rig.calls.ratesUpdated == 0)
        #expect(rig.coordinator.status.cnbFetchedAt == nil)
        #expect(rig.coordinator.status.lastError == nil)
        let log = try await database.recentFetchLog(limit: 10)
        #expect(log.map(\.message) == ["no newer rates"])
        #expect(log.first?.ok == true)
    }

    @Test func aDailyFileOfALaterDayThanAskedForIsNotStored() async throws {
        let (database, directory) = try await databaseWithRates(through: "2026-10-15")
        defer { removeTemporaryDirectory(directory) }
        let server = StubHTTPClient([daily("2026-10-16"): try dailyFile("2026-10-19", ratesOf: "2026-10-16")])
        let rig = makeRig(at: "2026-10-16T13:00:00Z", server: server, database: database)

        await rig.coordinator.refresh(.launch)

        #expect(try await database.newestCNBDeclaration() == civilDate("2026-10-15"))
        #expect(try await database.integer("SELECT count(*) FROM cnb_rate WHERE declared_on > '2026-10-15'") == 0)
        #expect(rig.calls.ratesUpdated == 0)
        #expect(rig.coordinator.status.lastError == "Kurzy ČNB se nepodařilo stáhnout: soubor je z jiného dne.")
        #expect(try await database.refreshState()?.cnbFailureCount == 1)
        let log = try await database.recentFetchLog(limit: 10)
        #expect(log.count == 1)
        #expect(log.first?.ok == false)
        #expect(log.first?.message == "declared 2026-10-19")
    }

    @Test func theTimeOfTheLastDownloadOutlivesARelaunchAndIgnoresTheDownloadsOfAnImport() async throws {
        let (database, directory) = try await databaseWithRates(through: "2026-10-14")
        defer { removeTemporaryDirectory(directory) }
        let server = StubHTTPClient([
            daily("2026-10-15"): try dailyFile("2026-10-15"), daily("2026-10-16"): try dailyFile("2026-10-16"),
        ])
        let first = makeRig(at: "2026-10-16T13:00:00Z", server: server, database: database)
        await first.coordinator.refresh(.launch)
        first.coordinator.stop()
        // Later an import fetches the yearly file of an older year, and logs it like any other request.
        try await database.appendFetchLog(
            FetchLogEntry(at: date("2026-10-16T13:30:00Z"), kind: .cnbYearly, target: "2022", ok: true, message: ""))

        let second = makeRig(at: "2026-10-17T10:00:00Z", server: StubHTTPClient(), database: database)
        await second.coordinator.refresh(.launch)

        #expect(second.coordinator.status.cnbFetchedAt == date("2026-10-16T13:00:00Z"))
        #expect(second.coordinator.status.cnbText == "Kurzy ČNB: aktuální k 16.\u{A0}10.\u{A0}2026 (staženo 15:00)")
    }

    @Test func aDatabaseThatCannotBeReadIsShownAndTheTimerBacksOff() async throws {
        let (database, directory) = try await databaseWithRates(through: "2026-10-15")
        defer { removeTemporaryDirectory(directory) }
        await database.close()
        let server = StubHTTPClient()
        let rig = makeRig(at: "2026-10-16T13:00:00Z", server: server, database: database)

        await rig.coordinator.refresh(.launch)

        #expect(rig.coordinator.status.lastError == "Uložené kurzy se nepodařilo načíst.")
        #expect(server.requests.isEmpty)
        #expect(rig.scheduler.armed == [date("2026-10-16T13:30:00Z")])
    }

    // MARK: The years that provisional payments wait for

    /// Stores an issued invoice of 10 000,00 USD for Bravo Labs, paid on `paidOn` and converted at the invented rate
    /// 23,5 of the invoice, provisionally unless `provisional` is false.
    private func storeDollarPayment(
        number: String, paidOn: String, provisional: Bool = true, in database: Database
    ) async throws {
        let rate = storedRate("USD", "23.5", declaredOn: "2025-03-03")
        let hours = InvoiceItem(
            description: "Software development", quantity: decimal("125"), unit: "h", unitPriceMinor: 7_000)
        var invoice = Invoice.fixture(
            number: number, currency: .usd, duzp: "2025-03-03", dueDate: "2025-03-17", items: [hours],
            vatMode: .outsideCountry, invoiceRate: rate,
            payment: Payment.fixture(
                on: paidOn, conversion: .cnbDaily, net: 23_500_000, vat: 0, rate: rate, provisional: provisional))
        invoice.client = SampleYear2026.bravo
        try await database.saveInvoice(invoice)
    }

    @Test func aYearThatAProvisionalPaymentWaitsForIsFetchedStoredLoggedAndAnnounced() async throws {
        let (database, directory) = try await databaseWithRates(through: "2026-10-16")
        defer { removeTemporaryDirectory(directory) }
        try await storeDollarPayment(number: "20250301", paidOn: "2025-03-20", in: database)
        let server = StubHTTPClient([CNBEndpoints.yearly(2025): try yearlyFile(2025)])
        let rig = makeRig(at: "2026-10-16T13:00:00Z", server: server, database: database)

        await rig.coordinator.refresh(.launch)

        #expect(server.requests == [CNBEndpoints.yearly(2025)])
        #expect(try await database.cnbRate(.usd, on: civilDate("2025-03-20")) != .notYetAvailable)
        // The rates are older than the newest declaration, which stays, and so does the time of its download.
        #expect(try await database.newestCNBDeclaration() == civilDate("2026-10-16"))
        #expect(rig.coordinator.status.cnbFetchedAt == nil)
        #expect(rig.calls.ratesUpdated == 1)
        #expect(rig.coordinator.status.lastError == nil)
        let log = try await database.recentFetchLog(limit: 10)
        #expect(log.map(\.target) == [CNBEndpoints.yearly(2025).absoluteString])
        #expect(log.allSatisfy { $0.kind == .cnbYearly && $0.ok && $0.message.isEmpty })
        #expect(try await database.refreshState()?.cnbFailureCount == 0)

        // Once its rate is there, nothing waits for the year any more.
        rig.clock.set(date("2026-10-16T14:00:00Z"))
        await rig.coordinator.refresh(.becameActive)
        #expect(server.requests.count == 1)
    }

    @Test func aYearThatCannotBeFetchedCountsAsAFailureAndIsNotAskedForAgainWithinTheBackOff() async throws {
        let (database, directory) = try await databaseWithRates(through: "2026-10-16")
        defer { removeTemporaryDirectory(directory) }
        try await storeDollarPayment(number: "20250301", paidOn: "2025-03-20", in: database)
        let server = StubHTTPClient(failures: [CNBEndpoints.yearly(2025): HTTPError.offline])
        let rig = makeRig(at: "2026-10-16T13:00:00Z", server: server, database: database)

        await rig.coordinator.refresh(.launch)

        #expect(server.requests == [CNBEndpoints.yearly(2025)])
        #expect(rig.calls.ratesUpdated == 0)
        #expect(rig.coordinator.status.lastError == "Kurzy ČNB se nepodařilo stáhnout: není připojení k internetu.")
        let state = try #require(try await database.refreshState())
        #expect(state.cnbFailureCount == 1)
        #expect(state.lastCNBFailure == date("2026-10-16T13:00:00Z"))
        let log = try await database.recentFetchLog(limit: 10)
        #expect(log.count == 1 && log.first?.ok == false && log.first?.message == "offline")

        // Within the half hour of the back-off, a trigger asks nothing.
        rig.clock.set(date("2026-10-16T13:20:00Z"))
        await rig.coordinator.refresh(.becameActive)
        #expect(server.requests.count == 1)

        // After it, the year is asked for again.
        rig.clock.set(date("2026-10-16T13:30:00Z"))
        await rig.coordinator.refresh(.becameActive)
        #expect(server.requests == [CNBEndpoints.yearly(2025), CNBEndpoints.yearly(2025)])
        #expect(try await database.refreshState()?.cnbFailureCount == 2)
    }

    @Test func aProvisionalPaymentOfTodayBeforeItsRatesAreDeclaredAsksForNothing() async throws {
        let (database, directory) = try await databaseWithRates(through: "2026-10-15")
        defer { removeTemporaryDirectory(directory) }
        // Friday 16 October, 12:00 in Prague: the rates of the day come after 14:30. A payment of a later day waits
        // for its rates too.
        try await storeDollarPayment(number: "20250301", paidOn: "2026-10-16", in: database)
        try await storeDollarPayment(number: "20250302", paidOn: "2026-10-30", in: database)
        let server = StubHTTPClient([CNBEndpoints.yearly(2026): try yearlyFile(2026)])
        let rig = makeRig(at: "2026-10-16T10:00:00Z", server: server, database: database)

        await rig.coordinator.refresh(.launch)

        #expect(server.requests.isEmpty)
        #expect(rig.calls.ratesUpdated == 0)
    }

    @Test func withoutProvisionalPaymentsNoYearIsAskedFor() async throws {
        let (database, directory) = try await databaseWithRates(through: "2026-10-16")
        defer { removeTemporaryDirectory(directory) }
        // A payment of 2025 that has its rate already, though the cache holds no rate of 2025.
        try await storeDollarPayment(number: "20250301", paidOn: "2025-03-20", provisional: false, in: database)
        let server = StubHTTPClient([CNBEndpoints.yearly(2025): try yearlyFile(2025)])
        let rig = makeRig(at: "2026-10-16T13:00:00Z", server: server, database: database)

        await rig.coordinator.refresh(.launch)

        #expect(server.requests.isEmpty)
        #expect(rig.calls.ratesUpdated == 0)
        #expect(try await database.refreshState()?.provisionalPaymentDays == [])
    }

    // MARK: The timer

    @Test func everyRunArmsOneTimerWithAToleranceOfAtLeastAMinute() async throws {
        let (database, directory) = try await databaseWithRates(through: "2026-10-15")
        defer { removeTemporaryDirectory(directory) }
        let rig = makeRig(at: "2026-10-16T08:00:00Z", server: StubHTTPClient(), database: database)

        await rig.coordinator.refresh(.launch)
        rig.clock.set(date("2026-10-16T09:00:00Z"))
        await rig.coordinator.refresh(.becameActive)

        #expect(rig.scheduler.wakes.map(\.date) == [date("2026-10-16T12:35:00Z"), date("2026-10-16T12:35:00Z")])
        #expect(rig.scheduler.armed == [date("2026-10-16T12:35:00Z")])
        #expect(rig.scheduler.wakes.allSatisfy { $0.tolerance >= 60 })
    }

    @Test(.hangGuard)
    func theTimerRunsARefreshWhenItFires() async throws {
        let (database, directory) = try await databaseWithRates(through: "2026-10-15")
        defer { removeTemporaryDirectory(directory) }
        let server = StubHTTPClient([daily("2026-10-16"): try dailyFile("2026-10-16")])
        let rig = makeRig(at: "2026-10-16T08:00:00Z", server: server, database: database)
        await rig.coordinator.refresh(.launch)
        #expect(server.requests.isEmpty)

        rig.clock.set(date("2026-10-16T12:35:00Z"))
        await withCheckedContinuation { continuation in
            rig.coordinator.onRatesUpdated = { continuation.resume() }
            rig.scheduler.fire()
        }
        // Waits for the rest of that run.
        await rig.coordinator.refresh(.becameActive)

        #expect(server.requests == [daily("2026-10-16")])
        #expect(rig.scheduler.armed == [date("2026-10-19T12:35:00Z")])
    }

    @Test func triggersThatComeTogetherRunOneAfterTheOther() async throws {
        let (database, directory) = try await databaseWithRates(through: "2026-10-14")
        defer { removeTemporaryDirectory(directory) }
        let server = StubHTTPClient([
            daily("2026-10-15"): try dailyFile("2026-10-15"), daily("2026-10-16"): try dailyFile("2026-10-16"),
        ])
        let rig = makeRig(at: "2026-10-16T13:00:00Z", server: server, database: database)

        async let launch: Void = rig.coordinator.refresh(.launch)
        async let activation: Void = rig.coordinator.refresh(.becameActive)
        _ = await (launch, activation)

        #expect(server.requests == [daily("2026-10-15"), daily("2026-10-16")])
        #expect(rig.calls.ratesUpdated == 1)
        #expect(rig.scheduler.armed.count == 1)
    }

    @Test func stoppingCancelsTheTimerAndEndsTheRefreshes() async throws {
        let (database, directory) = try await databaseWithRates(through: "2026-10-16")
        defer { removeTemporaryDirectory(directory) }
        let server = StubHTTPClient()
        let rig = makeRig(at: "2026-10-17T10:00:00Z", server: server, database: database)
        await rig.coordinator.refresh(.launch)
        #expect(rig.scheduler.armed.count == 1)

        rig.coordinator.stop()
        rig.clock.set(date("2026-10-19T13:00:00Z"))
        await rig.coordinator.refresh(.manual)

        #expect(rig.scheduler.armed.isEmpty)
        #expect(rig.scheduler.wakes.count == 1)
        #expect(server.requests.isEmpty)
        #expect(rig.calls.daysChanged.isEmpty)
    }

    @Test func aCoordinatorIsStartedFromStartToStopAndNotByResumeAlone() async throws {
        let (database, directory) = try await databaseWithRates(through: "2026-10-16")
        defer { removeTemporaryDirectory(directory) }
        let rig = makeRig(at: "2026-10-17T10:00:00Z", server: StubHTTPClient(), database: database)
        #expect(!rig.coordinator.isStarted)

        rig.coordinator.start()
        #expect(rig.coordinator.isStarted)
        rig.coordinator.start()
        #expect(rig.coordinator.isStarted)
        rig.coordinator.stop()
        #expect(!rig.coordinator.isStarted)

        // The task of the launch that start() made is ahead of this one in the queue of the main actor, and it found
        // the coordinator stopped. A launch of its own does not start the listening.
        await Task(priority: .utility) {}.value
        await rig.coordinator.resume()
        #expect(!rig.coordinator.isStarted)
    }

    @Test(.hangGuard)
    func triggersThatComeDuringARunMakeOneRunAfterIt() async throws {
        let (database, directory) = try await databaseWithRates(through: "2026-10-15")
        defer { removeTemporaryDirectory(directory) }
        let gate = Gate()
        let stub = StubHTTPClient(failures: [daily("2026-10-16"): HTTPError.offline])
        let server = GatedHTTPClient(base: stub, gate: gate)
        let rig = makeRig(at: "2026-10-16T12:35:00Z", server: server, database: database)
        let launch = Task { await rig.coordinator.refresh(.launch) }
        await gate.untilARequestWaits()

        // Three triggers while the run waits for the server; the network coming back is the one that counts. Each of
        // them is waiting behind the run, with the ones before it, when its task is made.
        let queued = [RefreshTrigger.becameActive, .networkAvailable, .wake].map { trigger in
            Task.immediate { await rig.coordinator.refresh(trigger) }
        }
        await gate.open()
        await launch.value
        for run in queued {
            await run.value
        }

        // The launch and one run after it, which did not wait out the back-off of the launch.
        #expect(rig.scheduler.wakes.count == 2)
        #expect(stub.requests == [daily("2026-10-16"), daily("2026-10-16")])
        #expect(try await database.refreshState()?.cnbFailureCount == 2)
    }

    @Test(.hangGuard)
    func stoppingDuringARunAlsoCancelsTheRunWaitingBehindIt() async throws {
        let (database, directory) = try await databaseWithRates(through: "2026-10-15")
        defer { removeTemporaryDirectory(directory) }
        let gate = Gate()
        // A manual check that ran after the launch would ask for the day again.
        let stub = StubHTTPClient(failures: [daily("2026-10-16"): HTTPError.offline])
        let server = GatedHTTPClient(base: stub, gate: gate)
        let rig = makeRig(at: "2026-10-16T12:35:00Z", server: server, database: database)
        let launch = Task { await rig.coordinator.refresh(.launch) }
        await gate.untilARequestWaits()
        // The manual check is waiting behind the run when its task is made.
        let queued = Task.immediate { await rig.coordinator.refresh(.manual) }

        rig.coordinator.stop()
        await gate.open()
        await launch.value
        await queued.value

        #expect(stub.requests == [daily("2026-10-16")])
        #expect(rig.calls.ratesUpdated == 0)
        #expect(rig.scheduler.wakes.isEmpty)
    }

    @Test(.hangGuard)
    func aRestartBeforeTheStoppedRunIsOverRunsALaunchOfItsOwn() async throws {
        let (database, directory) = try await databaseWithRates(through: "2026-10-15")
        defer { removeTemporaryDirectory(directory) }
        let gate = Gate()
        let stub = StubHTTPClient([daily("2026-10-16"): try dailyFile("2026-10-16")])
        let server = GatedHTTPClient(base: stub, gate: gate)
        let rig = makeRig(at: "2026-10-16T12:35:00Z", server: server, database: database)
        // A run waits for the server, and a trigger waits behind it.
        let stoppedRun = Task { await rig.coordinator.refresh(.launch) }
        await gate.untilARequestWaits()
        let queued = Task.immediate { await rig.coordinator.refresh(.becameActive) }

        // The vault locks, and it is unlocked again before that run is over: the launch of the restart asks the server
        // too, while the request of the stopped run is still held back.
        rig.coordinator.stop()
        let restart = Task { await rig.coordinator.resume() }
        await gate.untilRequestsWait(2)
        await gate.open()
        await restart.value
        await stoppedRun.value
        await queued.value

        // The launch of the restart ran to its end: it stored the rates, saved its state and armed the timer.
        #expect(try await database.newestCNBDeclaration() == civilDate("2026-10-16"))
        #expect(try await database.refreshState()?.newestCNBDeclaration == civilDate("2026-10-16"))
        #expect(rig.calls.ratesUpdated == 1)
        #expect(rig.scheduler.armed == [date("2026-10-19T12:35:00Z")])
        // Only that launch set a timer: the stopped run ended after the restart began, and set none.
        #expect(rig.scheduler.wakes.count == 1)
    }

    @Test func stoppingRightAfterStartingKeepsTheLaunchFromRunning() async throws {
        let (database, directory) = try await databaseWithRates(through: "2026-10-15")
        defer { removeTemporaryDirectory(directory) }
        // A launch would ask for the day that is missing.
        let server = StubHTTPClient([daily("2026-10-16"): try dailyFile("2026-10-16")])
        let rig = makeRig(at: "2026-10-16T12:35:00Z", server: server, database: database)

        // The task of the launch has not run yet when the coordinator is stopped, in the same turn.
        rig.coordinator.start()
        rig.coordinator.stop()
        // A task of the same priority that is made now is behind the task of the launch in the queue of the main actor,
        // so when it has run, the task of the launch has run too.
        await Task(priority: .utility) {}.value
        // A launch that the stop did not hold back is in progress by now, and this waits for the rest of it. The
        // coordinator is stopped, so it returns at once.
        await rig.coordinator.refresh(.becameActive)

        #expect(server.requests.isEmpty)
        #expect(try await database.refreshState() == nil)
        #expect(rig.scheduler.wakes.isEmpty)
    }

    @Test func aRunThatIsStoppedBeforeItStartsDoesNothing() async throws {
        let (database, directory) = try await databaseWithRates(through: "2026-10-15")
        defer { removeTemporaryDirectory(directory) }
        // A launch would ask for the day that is missing.
        let server = StubHTTPClient([daily("2026-10-16"): try dailyFile("2026-10-16")])
        let rig = makeRig(at: "2026-10-16T12:35:00Z", server: server, database: database)

        // The launch has made its run, which has not started, when the coordinator is stopped.
        let launch = Task.immediate { await rig.coordinator.refresh(.launch) }
        rig.coordinator.stop()
        await launch.value

        #expect(server.requests.isEmpty)
        #expect(try await database.refreshState() == nil)
        #expect(rig.scheduler.wakes.isEmpty)
    }

    @Test func triggersThatWaitTogetherRunAsTheManualCheckElseAsTheNetworkElseAsTheLatest() {
        #expect(RefreshTrigger.coalescing(nil, .wake) == .wake)
        #expect(RefreshTrigger.coalescing(.becameActive, .wake) == .wake)
        #expect(RefreshTrigger.coalescing(.networkAvailable, .wake) == .networkAvailable)
        #expect(RefreshTrigger.coalescing(.wake, .networkAvailable) == .networkAvailable)
        #expect(RefreshTrigger.coalescing(.manual, .networkAvailable) == .manual)
        #expect(RefreshTrigger.coalescing(.networkAvailable, .manual) == .manual)
        #expect(RefreshTrigger.coalescing(.manual, .timer) == .manual)
    }

    @Test func onlyTheNetworkComingBackAfterItWasGoneRunsTheRefresh() async throws {
        let (database, directory) = try await databaseWithRates(through: "2026-10-16")
        defer { removeTemporaryDirectory(directory) }
        let rig = makeRig(at: "2026-10-17T10:00:00Z", server: StubHTTPClient(), database: database)

        // The first report and the reports that change nothing run nothing.
        await rig.coordinator.networkChanged(satisfied: true)
        await rig.coordinator.networkChanged(satisfied: true)
        await rig.coordinator.networkChanged(satisfied: false)
        #expect(rig.scheduler.wakes.isEmpty)

        await rig.coordinator.networkChanged(satisfied: true)
        #expect(rig.scheduler.wakes.count == 1)
        await rig.coordinator.networkChanged(satisfied: true)
        #expect(rig.scheduler.wakes.count == 1)
    }

    @Test func aChangeOfTheSettingsArmsTheMidnightWhenTodayIsFollowedAgain() async throws {
        let (database, directory) = try await databaseWithRates(through: "2026-10-16")
        defer { removeTemporaryDirectory(directory) }
        let server = StubHTTPClient()
        let rig = makeRig(at: "2026-10-17T10:00:00Z", server: server, database: database)
        await rig.coordinator.refresh(.launch)
        #expect(rig.scheduler.armed == [date("2026-10-19T12:35:00Z")])

        rig.shell.followsToday = true
        await rig.coordinator.refresh(.settingsChanged)

        #expect(rig.scheduler.armed == [date("2026-10-17T22:00:00Z")])
        #expect(server.requests.isEmpty)
    }

    // MARK: Today

    @Test func atMidnightWhileFollowingTodayTheNewDayIsAnnounced() async throws {
        let (database, directory) = try await databaseWithRates(through: "2026-10-16")
        defer { removeTemporaryDirectory(directory) }
        let server = StubHTTPClient()
        let rig = makeRig(at: "2026-10-16T20:00:00Z", server: server, database: database, followsToday: true)
        await rig.coordinator.refresh(.launch)
        #expect(rig.calls.daysChanged.isEmpty)
        #expect(rig.scheduler.armed == [date("2026-10-16T22:00:00Z")])

        rig.clock.set(date("2026-10-16T22:00:00Z"))
        await rig.coordinator.refresh(.timer)

        #expect(rig.calls.daysChanged == [civilDate("2026-10-17")])
        #expect(server.requests.isEmpty)
        #expect(rig.scheduler.armed == [date("2026-10-17T22:00:00Z")])
        // The notification of the new day that comes as well announces nothing more.
        await rig.coordinator.refresh(.dayChanged)
        #expect(rig.calls.daysChanged == [civilDate("2026-10-17")])
    }

    @Test func withoutFollowingTodayMidnightIsNoWakeButTheNextTriggerAnnouncesTheDay() async throws {
        let (database, directory) = try await databaseWithRates(through: "2026-10-16")
        defer { removeTemporaryDirectory(directory) }
        let rig = makeRig(at: "2026-10-16T20:00:00Z", server: StubHTTPClient(), database: database)
        await rig.coordinator.refresh(.launch)
        #expect(rig.scheduler.armed == [date("2026-10-19T12:35:00Z")])

        rig.clock.set(date("2026-10-16T22:00:30Z"))
        await rig.coordinator.refresh(.dayChanged)

        #expect(rig.calls.daysChanged == [civilDate("2026-10-17")])
        #expect(rig.scheduler.armed == [date("2026-10-19T12:35:00Z")])
    }

    @Test func atNewYearTheNewYearsDayIsAnnouncedAndTheFinishedYearWaitsFor2January() async throws {
        let (database, directory) = try await databaseWithRates(through: "2026-10-16")
        defer { removeTemporaryDirectory(directory) }
        // An invented rate of the last business day of 2026, so that the cache is current.
        try await database.insertCNBRates([
            CNBRateRow(declaredOn: civilDate("2026-12-31"), currency: .usd, amount: 1, rate: decimal("21.5"))
        ])
        let server = StubHTTPClient()
        let rig = makeRig(at: "2026-12-31T20:00:00Z", server: server, database: database, followsToday: true)
        await rig.coordinator.refresh(.launch)
        #expect(rig.scheduler.armed == [date("2026-12-31T23:00:00Z")])
        #expect(rig.coordinator.status.uniformYear == 2026)

        rig.clock.set(date("2026-12-31T23:00:00Z"))
        await rig.coordinator.refresh(.timer)

        #expect(rig.calls.daysChanged == [civilDate("2027-01-01")])
        #expect(server.requests.isEmpty)
        #expect(rig.calls.found.isEmpty)
        #expect(rig.calls.reminders.isEmpty)
        #expect(try await database.refreshState()?.finishedYearsWithoutUniformRate == [2026])
        #expect(rig.coordinator.status.uniformYear == 2026)
        #expect(rig.coordinator.status.uniformText == notOut2026)
        // The next wake is the midnight of 2 January, from which the uniform rate of 2026 is looked for.
        #expect(rig.scheduler.armed == [date("2027-01-01T23:00:00Z")])
    }

    @Test func theDayAndItsMidnightAreThoseOfTheTimeZoneOfTheMac() async throws {
        let newYork = try #require(TimeZone(identifier: "America/New_York"))
        let (database, directory) = try await databaseWithRates(through: "2026-10-16")
        defer { removeTemporaryDirectory(directory) }
        let rig = makeRig(
            at: "2026-10-17T10:00:00Z", server: StubHTTPClient(), database: database, followsToday: true,
            timeZone: newYork)
        await rig.coordinator.refresh(.launch)
        #expect(rig.scheduler.armed == [date("2026-10-18T04:00:00Z")])

        // Past midnight in Prague, still Saturday evening in New York.
        rig.clock.set(date("2026-10-17T22:30:00Z"))
        await rig.coordinator.refresh(.becameActive)
        #expect(rig.calls.daysChanged.isEmpty)

        rig.clock.set(date("2026-10-18T04:00:00Z"))
        await rig.coordinator.refresh(.timer)
        #expect(rig.calls.daysChanged == [civilDate("2026-10-18")])
    }

    @Test func aChangeOfTheTimeZoneAcrossMidnightAnnouncesTheNewDay() async throws {
        let newYork = try #require(TimeZone(identifier: "America/New_York"))
        let (database, directory) = try await databaseWithRates(through: "2026-10-16")
        defer { removeTemporaryDirectory(directory) }
        // Friday 18:30 in New York is Saturday 00:30 in Prague.
        let rig = makeRig(
            at: "2026-10-16T22:30:00Z", server: StubHTTPClient(), database: database, timeZone: newYork)
        await rig.coordinator.refresh(.launch)

        rig.shell.timeZone = CzechCalendar.prague
        await rig.coordinator.refresh(.timeZoneChanged)

        #expect(rig.calls.daysChanged == [civilDate("2026-10-17")])
    }

    @Test func aClockSetBackADayAnnouncesTheEarlierDay() async throws {
        let (database, directory) = try await databaseWithRates(through: "2026-10-16")
        defer { removeTemporaryDirectory(directory) }
        let rig = makeRig(at: "2026-10-17T10:00:00Z", server: StubHTTPClient(), database: database)
        await rig.coordinator.refresh(.launch)

        rig.clock.set(date("2026-10-16T10:00:00Z"))
        await rig.coordinator.refresh(.clockChanged)

        #expect(rig.calls.daysChanged == [civilDate("2026-10-16")])
    }

    // MARK: The uniform rate of the finished year

    @Test func inJanuaryTheUniformRateOfTheFinishedYearIsFoundAndOfferedButNotStored() async throws {
        let (database, directory) = try await databaseWithRates(through: "2026-01-14", withoutUniformRateOf: 2025)
        defer { removeTemporaryDirectory(directory) }
        let server = try januaryServer(pdf: try gfrFixtureData("gfr_issue_2_2026", "pdf"))
        let rig = makeRig(at: "2026-01-15T09:00:00Z", server: server, database: database)

        await rig.coordinator.refresh(.launch)

        let issues = try issues()
        let pdf = try pdfURL()
        #expect(server.requests == [index2026, issues[0], issues[1], pdf])
        let finding = try #require(rig.calls.found.first)
        #expect(rig.calls.found.count == 1)
        #expect(finding.year == 2025)
        #expect(finding.instruction == "GFŘ-D-75")
        #expect(finding.issueURL == issues[1])
        #expect(Set(finding.rates) == Set(BuiltInUniformRates.rates(year: 2025)))
        #expect(try await database.uniformRates(year: 2025).isEmpty)
        #expect(try await database.integer("SELECT count(*) FROM uniform_rate WHERE year = 2025") == 0)
        #expect(rig.calls.reminders.isEmpty)
        #expect(rig.coordinator.status.uniformYear == 2025)
        #expect(rig.coordinator.status.uniformText == "Jednotný kurz 2025: vyšel (pokyn GFŘ-D-75), čeká na potvrzení")
        #expect(rig.coordinator.status.lastError == nil)
        let log = try await database.recentFetchLog(limit: 10)
        #expect(log.map(\.kind) == [.gfrPDF, .gfrIssue, .gfrIssue, .gfrIndex])
        #expect(log.map(\.target) == [pdf, issues[1], issues[0], index2026].map(\.absoluteString))
        #expect(log.allSatisfy { $0.ok })
        #expect(try await database.refreshState()?.lastUniformCheck == civilDate("2026-01-15"))

        // At most once a day: a later trigger of the same day asks nothing.
        rig.clock.set(date("2026-01-15T11:00:00Z"))
        await rig.coordinator.refresh(.becameActive)
        #expect(server.requests.count == 4)
        #expect(rig.calls.found.count == 1)
        #expect(rig.coordinator.status.uniformText == "Jednotný kurz 2025: vyšel (pokyn GFŘ-D-75), čeká na potvrzení")
    }

    @Test func anUnreadablePDFIsShownWithTheLinkAndItsIssueIsNotCountedAsChecked() async throws {
        let (database, directory) = try await databaseWithRates(through: "2026-01-14", withoutUniformRateOf: 2025)
        defer { removeTemporaryDirectory(directory) }
        let server = try januaryServer(pdf: Data("<html>Not found</html>".utf8))
        let rig = makeRig(at: "2026-01-15T09:00:00Z", server: server, database: database)

        await rig.coordinator.refresh(.launch)

        let issues = try issues()
        #expect(rig.calls.found.isEmpty)
        #expect(rig.calls.reminders.isEmpty)
        #expect(rig.coordinator.status.uniformYear == 2025)
        #expect(
            rig.coordinator.status.uniformText
                == "Jednotný kurz 2025: Finanční zpravodaj se nepodařilo přečíst (\(issues[1].absoluteString))")
        #expect(try await database.uniformRates(year: 2025).isEmpty)
        let state = try #require(try await database.refreshState())
        #expect(!(state.checkedIssues[2025] ?? []).contains(issues[1]))
        let log = try await database.recentFetchLog(limit: 10)
        #expect(log.map(\.kind) == [.gfrPDF, .gfrIssue, .gfrIssue, .gfrIndex])
        #expect(log.first?.ok == false)
        #expect(log.first?.message == "not readable")
        #expect(log.dropFirst().allSatisfy { $0.ok })
    }

    @Test func issuesWithoutTheRatesAreRememberedAndNotAskedForAgain() async throws {
        let (database, directory) = try await databaseWithRates(through: "2026-01-14", withoutUniformRateOf: 2025)
        defer { removeTemporaryDirectory(directory) }
        let issues = try issues()
        // On 8 January only the first issue is out, and it announces something else.
        let server = StubHTTPClient([index2026: try indexOfTheFirstIssue(), issues[0]: issueWithoutTheRates])
        let rig = makeRig(at: "2026-01-08T09:00:00Z", server: server, database: database)

        await rig.coordinator.refresh(.launch)

        #expect(server.requests == [index2026, issues[0]])
        #expect(try await database.refreshState()?.checkedIssues[2025] == [issues[0]])
        #expect(rig.coordinator.status.uniformYear == 2025)
        #expect(rig.coordinator.status.uniformText == notOut2025)
        #expect(rig.coordinator.status.lastError == nil)

        // The next day only the index is asked for.
        rig.clock.set(date("2026-01-09T09:00:00Z"))
        await rig.coordinator.refresh(.dayChanged)
        #expect(Array(server.requests.dropFirst(2)) == [index2026])
    }

    @Test func anIndexThatIsNotThereYetMeansTheRateIsNotOutYet() async throws {
        let (database, directory) = try await databaseWithRates(through: "2026-01-14", withoutUniformRateOf: 2025)
        defer { removeTemporaryDirectory(directory) }
        let server = StubHTTPClient()
        let rig = makeRig(at: "2026-01-02T08:00:00Z", server: server, database: database)

        await rig.coordinator.refresh(.launch)

        #expect(server.requests == [index2026])
        #expect(rig.coordinator.status.lastError == nil)
        #expect(rig.coordinator.status.uniformText == notOut2025)
        #expect(rig.calls.found.isEmpty)
        let state = try #require(try await database.refreshState())
        #expect(state.lastUniformCheck == civilDate("2026-01-02"))
        #expect(state.checkedIssues[2025] == nil)
        let log = try await database.recentFetchLog(limit: 10)
        #expect(log.map(\.kind) == [.gfrIndex])
        #expect(log.first?.message == "status 404")
    }

    @Test func aSearchWithoutAConnectionIsShownAndDoesNotUseUpTheSearchOfTheDay() async throws {
        let (database, directory) = try await databaseWithRates(through: "2026-01-14", withoutUniformRateOf: 2025)
        defer { removeTemporaryDirectory(directory) }
        let server = StubHTTPClient(failures: [index2026: HTTPError.offline])
        let rig = makeRig(at: "2026-01-15T09:00:00Z", server: server, database: database)

        await rig.coordinator.refresh(.launch)

        #expect(
            rig.coordinator.status.lastError
                == "Jednotný kurz 2025 se nepodařilo zkontrolovat: není připojení k internetu.")
        #expect(rig.calls.found.isEmpty)
        #expect(rig.calls.reminders.isEmpty)
        #expect(try await database.refreshState()?.lastUniformCheck == nil)

        // The next trigger of the day searches again.
        rig.clock.set(date("2026-01-15T09:10:00Z"))
        await rig.coordinator.refresh(.becameActive)
        #expect(server.requests == [index2026, index2026])
    }

    @Test(arguments: [
        (HTTPError.status(503), "server odpověděl chybou 503"),
        (HTTPError.hostNotAllowed("example.com"), "server přesměroval na neočekávanou adresu"),
    ])
    func aSearchThatTheServerFailsUsesUpTheSearchOfTheDay(_ failure: HTTPError, _ reason: String) async throws {
        let (database, directory) = try await databaseWithRates(through: "2026-01-14", withoutUniformRateOf: 2025)
        defer { removeTemporaryDirectory(directory) }
        let server = StubHTTPClient(failures: [index2026: failure])
        let rig = makeRig(at: "2026-01-15T09:00:00Z", server: server, database: database)

        await rig.coordinator.refresh(.launch)

        #expect(rig.coordinator.status.lastError == "Jednotný kurz 2025 se nepodařilo zkontrolovat: \(reason).")
        #expect(try await database.refreshState()?.lastUniformCheck == civilDate("2026-01-15"))
        // Neither a later trigger nor the network coming back searches again that day.
        rig.clock.set(date("2026-01-15T09:10:00Z"))
        await rig.coordinator.refresh(.becameActive)
        await rig.coordinator.refresh(.networkAvailable)
        #expect(server.requests == [index2026])
    }

    @Test func on31MarchARateStillNotOutBringsTheReminderAndTheChecksStop() async throws {
        let (database, directory) = try await databaseWithRates(through: "2026-03-31", withoutUniformRateOf: 2025)
        defer { removeTemporaryDirectory(directory) }
        let issues = try issues()
        let server = StubHTTPClient([index2026: try indexOfTheFirstIssue(), issues[0]: issueWithoutTheRates])
        let rig = makeRig(at: "2026-03-31T08:00:00Z", server: server, database: database)

        await rig.coordinator.refresh(.launch)

        #expect(server.requests == [index2026, issues[0]])
        #expect(rig.calls.reminders == [2025])
        #expect(rig.calls.found.isEmpty)
        #expect(try await database.refreshState()?.gaveUpUniform == [2025])
        #expect(try await database.uniformRates(year: 2025).isEmpty)
        // The line says the rate has to be entered by hand.
        #expect(rig.coordinator.status.uniformYear == 2025)
        #expect(
            rig.coordinator.status.uniformText == "Jednotný kurz 2025: nenalezen, zadejte ho ručně v Nastavení › Rok")

        rig.clock.set(date("2026-04-01T08:00:00Z"))
        await rig.coordinator.refresh(.dayChanged)
        #expect(server.requests.count == 2)
        #expect(rig.calls.reminders == [2025])
    }

    @Test func on31MarchAnIndexThatIsNotThereBringsTheReminderAndTheSearchEnds() async throws {
        let (database, directory) = try await databaseIn2027(ratesThrough: "2027-03-31")
        defer { removeTemporaryDirectory(directory) }
        let server = StubHTTPClient()
        let rig = makeRig(at: "2027-03-31T08:00:00Z", server: server, database: database)

        await rig.coordinator.refresh(.launch)

        #expect(server.requests == [index2027])
        #expect(rig.calls.reminders == [2026])
        #expect(try await database.refreshState()?.gaveUpUniform == [2026])
        #expect(rig.coordinator.status.uniformYear == 2026)
        #expect(
            rig.coordinator.status.uniformText == "Jednotný kurz 2026: nenalezen, zadejte ho ručně v Nastavení › Rok")
    }

    @Test(arguments: [HTTPError.status(503), HTTPError.hostNotAllowed("example.com"), HTTPError.offline])
    func on31MarchASearchThatFailsBringsTheReminderAndTheSearchEnds(_ failure: HTTPError) async throws {
        let (database, directory) = try await databaseIn2027(ratesThrough: "2027-03-31")
        defer { removeTemporaryDirectory(directory) }
        let server = StubHTTPClient(failures: [index2027: failure])
        let rig = makeRig(at: "2027-03-31T08:00:00Z", server: server, database: database)

        await rig.coordinator.refresh(.launch)

        #expect(rig.calls.reminders == [2026])
        #expect(try await database.refreshState()?.gaveUpUniform == [2026])
        #expect(
            rig.coordinator.status.uniformText == "Jednotný kurz 2026: nenalezen, zadejte ho ručně v Nastavení › Rok")
        // Nothing is looked for any more.
        rig.clock.set(date("2027-04-01T08:00:00Z"))
        await rig.coordinator.refresh(.dayChanged)
        #expect(server.requests == [index2027])
        #expect(rig.calls.reminders == [2026])
    }

    @Test func aRateFoundOn31MarchIsOfferedWithoutAReminderAndTheSearchGoesOn() async throws {
        let (database, directory) = try await databaseIn2027(ratesThrough: "2027-03-31")
        defer { removeTemporaryDirectory(directory) }
        let rig = makeRig(at: "2027-03-31T08:00:00Z", server: serverWithTheRatesOf2026(), database: database)

        await rig.coordinator.refresh(.launch)

        #expect(rig.calls.found.map(\.instruction) == ["GFŘ-D-99"])
        #expect(rig.calls.reminders.isEmpty)
        #expect(try await database.refreshState()?.gaveUpUniform == [])
        #expect(try await database.uniformRates(year: 2026).isEmpty)
        #expect(rig.coordinator.status.uniformText == "Jednotný kurz 2026: vyšel (pokyn GFŘ-D-99), čeká na potvrzení")

        // While it is not confirmed, it is offered again the next day, still without a reminder.
        rig.clock.set(date("2027-04-01T08:00:00Z"))
        await rig.coordinator.refresh(.dayChanged)
        #expect(rig.calls.found.count == 2)
        #expect(rig.calls.reminders.isEmpty)
    }

    @Test func aManualRefreshChecksTheUniformRateAgainOnTheSameDay() async throws {
        let (database, directory) = try await databaseWithRates(through: "2026-01-14", withoutUniformRateOf: 2025)
        defer { removeTemporaryDirectory(directory) }
        let server = StubHTTPClient()
        let rig = makeRig(at: "2026-01-02T08:00:00Z", server: server, database: database)
        await rig.coordinator.refresh(.launch)
        await rig.coordinator.refresh(.becameActive)
        #expect(server.requests == [index2026])

        await rig.coordinator.refresh(.manual)

        #expect(server.requests == [index2026, index2026])
    }

    @Test func anUnreadablePageStaysShownAfterARelaunchUntilASearchGetsAnAnswer() async throws {
        let (database, directory) = try await databaseWithRates(through: "2026-01-15", withoutUniformRateOf: 2025)
        defer { removeTemporaryDirectory(directory) }
        let issues = try issues()
        let unreadable = "Jednotný kurz 2025: Finanční zpravodaj se nepodařilo přečíst (\(issues[1].absoluteString))"
        let first = makeRig(
            at: "2026-01-15T09:00:00Z", server: try januaryServer(pdf: Data("<html>Not found</html>".utf8)),
            database: database)
        await first.coordinator.refresh(.launch)
        #expect(first.coordinator.status.uniformText == unreadable)
        first.coordinator.stop()

        // A relaunch on the same day searches nothing and still shows the page.
        let notOut = StubHTTPClient([index2026: try indexOfTheFirstIssue(), issues[0]: issueWithoutTheRates])
        let second = makeRig(at: "2026-01-15T11:00:00Z", server: notOut, database: database)
        await second.coordinator.refresh(.launch)
        #expect(notOut.requests.isEmpty)
        #expect(second.coordinator.status.uniformText == unreadable)

        // The search of the next day gets an answer, which takes its place.
        second.clock.set(date("2026-01-16T09:00:00Z"))
        await second.coordinator.refresh(.dayChanged)
        #expect(notOut.requests == [index2026, issues[0]])
        #expect(second.coordinator.status.uniformText == notOut2025)
    }

    @Test func aChangeOfTheSettingsAfterAConfirmedRateMovesTheLineOnToTheCurrentYear() async throws {
        let (database, directory) = try await databaseWithRates(through: "2026-01-14", withoutUniformRateOf: 2025)
        defer { removeTemporaryDirectory(directory) }
        let server = try januaryServer(pdf: try gfrFixtureData("gfr_issue_2_2026", "pdf"))
        let rig = makeRig(at: "2026-01-15T09:00:00Z", server: server, database: database)
        await rig.coordinator.refresh(.launch)
        let finding = try #require(rig.calls.found.first)
        #expect(rig.coordinator.status.uniformYear == 2025)

        // The app stores what the person confirmed, then tells the coordinator.
        let confirmed = finding.rates.map {
            UniformRate(
                year: 2025, currency: $0.currency, amount: $0.amount, rate: $0.rate, instruction: finding.instruction,
                sourceURL: finding.pdfURL.absoluteString, confirmedAt: date("2026-01-15T09:05:00Z"), origin: .fetched)
        }
        try await database.saveUniformRates(confirmed, year: 2025)
        await rig.coordinator.refresh(.settingsChanged)

        #expect(rig.coordinator.status.uniformYear == 2026)
        #expect(rig.coordinator.status.uniformText == notOut2026)
        #expect(server.requests.count == 4)
    }

    // MARK: Rates entered by hand

    /// A rate of dollars of 2026 entered by hand.
    private let manual2026 = UniformRate(
        year: 2026, currency: .usd, amount: 1, rate: decimal("21.90"), instruction: "", origin: .manual)

    /// The rates of 2026 entered by hand on 1 February 2027 stand in for the official ones: those are not looked for
    /// while they are stored, and are looked for the day they are removed.
    @Test func aFinishedYearWithRatesEnteredByHandIsNotLookedForUntilTheyAreRemoved() async throws {
        let (database, directory) = try await databaseIn2027(ratesThrough: "2027-02-01")
        defer { removeTemporaryDirectory(directory) }
        try await database.saveUniformRates([manual2026], year: 2026)
        let server = StubHTTPClient()
        let rig = makeRig(at: "2027-02-01T15:00:00Z", server: server, database: database)

        await rig.coordinator.refresh(.launch)

        #expect(server.requests.isEmpty)
        let state = try #require(try await database.refreshState())
        #expect(state.finishedYearsWithoutUniformRate == [2026])
        #expect(state.finishedYearsWithManualUniformRate == [2026])
        #expect(state.lastUniformCheck == nil)
        // The line is about the current year, as for a year that has its rate.
        #expect(rig.coordinator.status.uniformYear == 2027)

        try await database.deleteUniformRates(year: 2026)
        await rig.coordinator.searchAgain(for: 2026)
        await rig.coordinator.refresh(.settingsChanged)

        #expect(server.requests == [index2027])
        #expect(try await database.refreshState()?.finishedYearsWithManualUniformRate == [])
        #expect(rig.coordinator.status.uniformYear == 2026)
        #expect(rig.coordinator.status.uniformText == notOut2026)
    }

    /// The search for the rates of 2026 ended on 31 March 2027 without them. Rates entered by hand and removed again
    /// before any run saw them start it again: the stored state forgets at once that it ended, and so does the
    /// coordinator, which kept the state of its run.
    @Test func removingRatesEnteredByHandStartsASearchThatGaveUpAgain() async throws {
        let (database, directory) = try await databaseIn2027(ratesThrough: "2027-03-31")
        defer { removeTemporaryDirectory(directory) }
        let server = StubHTTPClient()
        let rig = makeRig(at: "2027-03-31T08:00:00Z", server: server, database: database)
        await rig.coordinator.refresh(.launch)
        #expect(rig.calls.reminders == [2026])
        #expect(try await database.refreshState()?.gaveUpUniform == [2026])

        try await database.saveUniformRates([manual2026], year: 2026)
        try await database.deleteUniformRates(year: 2026)
        await rig.coordinator.searchAgain(for: 2026)

        #expect(try await database.refreshState()?.gaveUpUniform == [])
        rig.clock.set(date("2027-04-01T08:00:00Z"))
        await rig.coordinator.refresh(.dayChanged)
        // Looked for again, and given up on again with the reminder.
        #expect(server.requests == [index2027, index2027])
        #expect(rig.calls.reminders == [2026, 2026])
        #expect(try await database.refreshState()?.gaveUpUniform == [2026])
    }

    /// A run that began while the search for the rates of 2026 had ended keeps its state after the rates entered by
    /// hand were removed: it does not bring the end of the search back, and the next run looks for them.
    @Test(.hangGuard)
    func aRunInProgressDoesNotBringBackTheEndOfASearchThatStartsAgain() async throws {
        let (database, directory) = try await databaseIn2027(ratesThrough: "2027-03-31")
        defer { removeTemporaryDirectory(directory) }
        var ended = RefreshState()
        ended.gaveUpUniform = [2026]
        ended.lastUniformCheck = civilDate("2027-03-31")
        try await database.saveRefreshState(ended)
        let gate = Gate()
        let stub = StubHTTPClient()
        // 1 April 2027 after 14:30: the rates of the day are fetched, and the run waits for them at the gate.
        let rig = makeRig(
            at: "2027-04-01T13:00:00Z", server: GatedHTTPClient(base: stub, gate: gate), database: database)
        let running = Task { await rig.coordinator.refresh(.launch) }
        await gate.untilARequestWaits()

        try await database.saveUniformRates([manual2026], year: 2026)
        try await database.deleteUniformRates(year: 2026)
        await rig.coordinator.searchAgain(for: 2026)
        await gate.open()
        await running.value

        #expect(stub.requests == [daily("2027-04-01")])
        #expect(try await database.refreshState()?.gaveUpUniform == [])
        rig.clock.set(date("2027-04-02T08:00:00Z"))
        await rig.coordinator.refresh(.dayChanged)
        #expect(stub.requests.contains(index2027))
        #expect(rig.calls.reminders == [2026])
    }

    // MARK: The stored state

    @Test func theStateIsKeptUnderItsOwnKeyBesideTheAppSettings() async throws {
        let (database, directory) = try makeDatabase()
        defer { removeTemporaryDirectory(directory) }
        #expect(try await database.refreshState() == nil)
        var state = RefreshState()
        state.newestCNBDeclaration = civilDate("2026-10-16")
        state.cnbFailureCount = 1
        state.lastCNBFailure = date("2026-10-16T12:35:00Z")
        state.cnbRetrySlotsUsed = [civilDate("2026-10-16"): 2]
        state.checkedIssues = [2025: [webURL("https://mf.gov.cz/cs/dane-a-ucetnictvi/financni-zpravodaj/2026/x")]]

        try await database.saveRefreshState(state)

        #expect(try await database.refreshState() == state)
        #expect(try await database.integer("SELECT count(*) FROM app_settings WHERE key = 'refresh_state'") == 1)
        #expect(try await database.appSettings() == AppSettings())
        state.cnbFailureCount = 0
        try await database.saveRefreshState(state)
        #expect(try await database.refreshState() == state)
        #expect(try await database.integer("SELECT count(*) FROM app_settings WHERE key = 'refresh_state'") == 1)
    }

    @Test func aStoredStateThatCannotBeReadIsStartedAfresh() async throws {
        let (database, directory) = try await databaseWithRates(through: "2026-10-16")
        defer { removeTemporaryDirectory(directory) }
        try await database.storeSetting("x", forKey: "refresh_state")
        let rig = makeRig(at: "2026-10-17T10:00:00Z", server: StubHTTPClient(), database: database)

        await rig.coordinator.refresh(.launch)

        #expect(try await database.refreshState()?.newestCNBDeclaration == civilDate("2026-10-16"))
        #expect(rig.scheduler.armed == [date("2026-10-19T12:35:00Z")])
    }
}

/// A server whose answers the test can change between runs. It passes every request to the stub it has now.
private final class SwitchingHTTPClient: HTTPClient {
    private let current: OSAllocatedUnfairLock<StubHTTPClient>

    init(_ first: StubHTTPClient) {
        current = OSAllocatedUnfairLock(initialState: first)
    }

    func switchTo(_ next: StubHTTPClient) {
        current.withLock { $0 = next }
    }

    func get(_ url: URL) async throws -> Data {
        let stub = current.withLock { $0 }
        return try await stub.get(url)
    }
}

private extension Database {
    /// Stores `value` as it is under `key` in `app_settings`, as something else than this version of the app could
    /// have written it.
    func storeSetting(_ value: String, forKey key: String) throws {
        try write { connection in
            try connection.run("INSERT INTO app_settings(key, value) VALUES (?, ?)", [.text(key), .text(value)])
        }
    }
}
