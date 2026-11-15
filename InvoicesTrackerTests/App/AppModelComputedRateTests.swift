import Foundation
import Testing
@testable import InvoicesTracker

/// The preliminary uniform rate that the app computes from the ČNB month-end rates and keeps current
/// (`AppModel.updateComputedUniformRates()`): when the data opens, on a new day, after new ČNB rates and once the rates
/// entered by hand are removed. A year whose computed rate changes and that is set to the uniform rate has its payments
/// converted again, and a green banner says at what (`ComputedRateBanner`). The ČNB rates are invented and stored only
/// on the last business day of each month, and the clock is at noon of 17. 10. 2026 unless a test says otherwise, when
/// January to September of 2026 have ended. In every expected string `\u{00A0}` is the no-break space.
@Suite(.settlesBackups)
@MainActor
struct AppModelComputedRateTests {
    // MARK: Helpers

    /// The invented ČNB rates of dollars and euros declared on the last business day of each month of 2026, January
    /// first. Dollars average 21,35 Kč over January to September, 21,38 Kč with October and 21,42 Kč over the whole
    /// year; euros 24,35 Kč, 24,36 Kč and 24,40 Kč.
    private static let monthEnds2026: [(day: String, usd: String, eur: String)] = [
        ("2026-01-30", "21.150", "24.150"),
        ("2026-02-27", "21.250", "24.250"),
        ("2026-03-31", "21.350", "24.350"),
        ("2026-04-30", "21.450", "24.450"),
        ("2026-05-29", "21.550", "24.550"),
        ("2026-06-30", "21.450", "24.450"),
        ("2026-07-31", "21.350", "24.350"),
        ("2026-08-31", "21.250", "24.250"),
        ("2026-09-30", "21.350", "24.350"),
        ("2026-10-30", "21.650", "24.450"),
        ("2026-11-30", "21.500", "24.500"),
        ("2026-12-31", "21.700", "24.700"),
    ]

    /// An app model that has gone through the first launch with its clock at `clock`, and the ČNB rates of the ends of
    /// `months` of 2026 stored.
    private func makeApp(
        in directory: URL, clock: ManualClock = ManualClock(localNoon(2026, 10, 17)),
        monthEnds months: ClosedRange<Int>? = 1...9
    ) async throws -> AppModel {
        let app = makeAppModel(in: directory, clock: clock)
        try await startFresh(app)
        if let months {
            try await storeMonthEnds(months, in: try #require(app.database))
        }
        return app
    }

    /// Stores the ČNB rates of dollars and euros of the last business days of `months` of 2026.
    private func storeMonthEnds(_ months: ClosedRange<Int>, in database: Database) async throws {
        let rows = Self.monthEnds2026[(months.lowerBound - 1)...(months.upperBound - 1)].flatMap { day, usd, eur in
            [
                CNBRateRow(declaredOn: civilDate(day), currency: .usd, amount: 1, rate: decimal(usd)),
                CNBRateRow(declaredOn: civilDate(day), currency: .eur, amount: 1, rate: decimal(eur)),
            ]
        }
        try await database.insertCNBRates(rows)
    }

    /// Stores an invoice of `amountMinor` hundredths of `currency` without VAT, paid on `day` at the ČNB rate of that
    /// day, as a year that converts at the daily rates has it, and returns it as stored.
    private func storePaid(
        _ currency: CurrencyCode, _ amountMinor: Int64, on day: String, in app: AppModel
    ) async throws -> Invoice {
        let database = try #require(app.database)
        var paid = Invoice.fixture(
            number: day.replacing("-", with: ""), currency: currency, duzp: day, dueDate: day,
            items: [.fixture("1", at: amountMinor)], vatMode: currency.isCZK ? .domestic21 : .outsideCountry)
        paid.payment = try await app.convert(paid, paidOn: civilDate(day), method: .cnbDaily, in: database)
        paid.id = try await database.saveInvoice(paid)
        return paid
    }

    /// Stores 10 000,00 USD paid on 30. 6. 2026 at the ČNB rate of that day, 21,45 Kč.
    private func storeDollarsPaid(in app: AppModel) async throws -> Invoice {
        let dollars = try await storePaid(.usd, 1_000_000, on: "2026-06-30", in: app)
        #expect(dollars.payment?.conversion == .cnbDaily && dollars.payment?.czkNetHalere == 21_450_000)
        return dollars
    }

    /// The payment of `invoice` as it is stored now.
    private func payment(of invoice: Invoice, in app: AppModel) async throws -> Payment {
        let database = try #require(app.database)
        return try #require(try await database.invoice(id: invoice.id)?.payment)
    }

    /// The uniform rates of `year` in `app`, each for one unit, euros before dollars as the database orders them. An
    /// issue is recorded unless they are the rates of euros and dollars, each computed over `months` months.
    private func computedRates(
        of year: Int, overMonths months: Int, in app: AppModel, sourceLocation: SourceLocation = #_sourceLocation
    ) async throws -> [Decimal] {
        let rates = try await #require(app.database).uniformRates(year: year)
        #expect(
            rates.allSatisfy { $0.origin == .computed && $0.computedMonths == months && $0.amount == 1 },
            sourceLocation: sourceLocation)
        #expect(rates.map(\.currency) == [.eur, .usd], sourceLocation: sourceLocation)
        return rates.map(\.rate)
    }

    /// Takes `day` as the new day, as the refresh tells it (`AppModel.handleDayChanged(_:)`), and waits until the
    /// keeper that the new day started has ended its turn.
    private func changeDay(to day: String, in app: AppModel) async throws {
        let before = app.latestConversion
        app.handleDayChanged(civilDate(day))
        try await waitUntil { app.latestConversion != before }
        await app.latestConversion?.value
    }

    // MARK: When the keeper runs

    @Test func openingTheDataComputesTheRateOfTheCurrentYear() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let before = try await makeApp(in: directory)
        let database = try #require(before.database)
        #expect(try await database.uniformRates(year: 2026).isEmpty)
        let shipped = try await database.uniformRates(year: 2025)
        await database.close()

        let app = makeAppModel(in: directory)
        await app.launch()

        #expect(app.phase == .ready)
        #expect(try await computedRates(of: 2026, overMonths: 9, in: app) == [decimal("24.35"), decimal("21.35")])
        // 2025 keeps the table that ships with the app: a computed rate never replaces it.
        #expect(try await #require(app.database).uniformRates(year: 2025) == shipped)
        // 2026 converts at the daily rates: nothing is converted at the rate, and no banner tells of it.
        #expect(app.banner == nil)
    }

    @Test func aNewMonthRecomputesTheRateAndConvertsTheYearSetToIt() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let app = try await makeApp(in: directory)
        let dollars = try await storeDollarsPaid(in: app)
        await app.updateComputedUniformRates()
        #expect(await app.setFXMethod(.uniform, year: 2026) == .saved)
        // 10 000,00 USD at 21,35 Kč, the mean of January to September.
        #expect(try await payment(of: dollars, in: app).czkNetHalere == 21_350_000)
        // The ČNB declares the rate of the end of October on 30. 10.
        try await storeMonthEnds(10...10, in: try #require(app.database))
        app.banner = nil

        try await changeDay(to: "2026-11-01", in: app)

        #expect(try await computedRates(of: 2026, overMonths: 10, in: app) == [decimal("24.36"), decimal("21.38")])
        let converted = try await payment(of: dollars, in: app)
        #expect(converted.conversion == .uniform && converted.czkNetHalere == 21_380_000)
        #expect(
            app.banner?.text
                == "Předběžný jednotný kurz 2026 je přepočítaný i s kurzem za říjen: 1\u{00A0}USD ≈ 21,38\u{00A0}Kč"
                + " (dříve 21,35). Platby roku 2026 jsou jím přepočtené.")
    }

    /// The ČNB rate of the end of October is not stored yet on 1 November: the rate stays computed over September, and
    /// the new rates of the ČNB, once the refresh has stored them, compute it over October too.
    @Test func newRatesOfAMonthEndRecomputeTheRate() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let app = try await makeApp(in: directory)
        let dollars = try await storeDollarsPaid(in: app)
        await app.updateComputedUniformRates()
        #expect(await app.setFXMethod(.uniform, year: 2026) == .saved)
        let version = app.dataVersion

        try await changeDay(to: "2026-11-01", in: app)

        #expect(try await computedRates(of: 2026, overMonths: 9, in: app) == [decimal("24.35"), decimal("21.35")])
        #expect(app.dataVersion == version)
        try await storeMonthEnds(10...10, in: try #require(app.database))

        await app.ratesUpdated()

        #expect(try await computedRates(of: 2026, overMonths: 10, in: app) == [decimal("24.36"), decimal("21.38")])
        #expect(try await payment(of: dollars, in: app).czkNetHalere == 21_380_000)
        #expect(
            app.banner?.text
                == "Předběžný jednotný kurz 2026 je přepočítaný i s kurzem za říjen: 1\u{00A0}USD ≈ 21,38\u{00A0}Kč"
                + " (dříve 21,35). Platby roku 2026 jsou jím přepočtené.")
    }

    @Test func aYearNotSetToTheUniformRateGetsNoBanner() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let app = try await makeApp(in: directory)
        let dollars = try await storeDollarsPaid(in: app)
        await app.updateComputedUniformRates()
        try await storeMonthEnds(10...10, in: try #require(app.database))
        let version = app.dataVersion

        try await changeDay(to: "2026-11-01", in: app)

        #expect(try await computedRates(of: 2026, overMonths: 10, in: app) == [decimal("24.36"), decimal("21.38")])
        // The year stays at the daily rates, and its payments as they were.
        #expect(try await payment(of: dollars, in: app) == dollars.payment)
        #expect(app.banner == nil)
        // The rate is a write all the same: the screens load again, as the menu of the toolbar names the new rate.
        #expect(app.dataVersion > version)
    }

    @Test func recomputingTheSameRateChangesNothing() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let app = try await makeApp(in: directory)
        let database = try #require(app.database)
        try await database.updateYearSettings(2026) { $0.incomeFXMethod = .uniform }
        let dollars = try await storeDollarsPaid(in: app)
        await app.updateComputedUniformRates()
        #expect(app.banner != nil)
        let rates = try await database.uniformRates(year: 2026)
        let converted = try await payment(of: dollars, in: app)
        #expect(converted.czkNetHalere == 21_350_000)
        app.banner = nil
        let key = app.reloadKey

        await app.updateComputedUniformRates()

        #expect(app.banner == nil)
        #expect(app.reloadKey == key)
        #expect(try await database.uniformRates(year: 2026) == rates)
        #expect(try await payment(of: dollars, in: app) == converted)

        // A new day in the same month computes the same rate: the day alone loads the screens again.
        let version = app.dataVersion
        try await changeDay(to: "2026-10-18", in: app)

        #expect(app.banner == nil)
        #expect(app.dataVersion == version)
    }

    @Test func januaryLeavesTheCurrentYearWithoutARate() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let app = try await makeApp(in: directory, clock: ManualClock(localNoon(2027, 1, 20)), monthEnds: 1...12)

        await app.updateComputedUniformRates()

        let database = try #require(app.database)
        #expect(try await database.uniformRates(year: 2027).isEmpty)
        #expect(try await computedRates(of: 2026, overMonths: 12, in: app) == [decimal("24.40"), decimal("21.42")])
    }

    /// A year set to the uniform rate in January, before any month of it has ended, has no rate yet and is computed at
    /// the daily rates. On 1 February it gets its first rate, the mean of January alone: its payments are converted at
    /// it, and the banner says so.
    @Test func aYearSetToTheUniformRateBeforeFebruaryGetsItsFirstRateOnFebruary1() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let app = try await makeApp(in: directory, clock: ManualClock(localNoon(2027, 1, 31)), monthEnds: nil)
        let database = try #require(app.database)
        try await database.insertCNBRates([
            CNBRateRow(declaredOn: civilDate("2027-01-15"), currency: .usd, amount: 1, rate: decimal("21.200")),
            CNBRateRow(declaredOn: civilDate("2027-01-15"), currency: .eur, amount: 1, rate: decimal("24.200")),
            CNBRateRow(declaredOn: civilDate("2027-01-29"), currency: .usd, amount: 1, rate: decimal("21.400")),
            CNBRateRow(declaredOn: civilDate("2027-01-29"), currency: .eur, amount: 1, rate: decimal("24.300")),
        ])
        try await database.updateYearSettings(2027) { $0.incomeFXMethod = .uniform }
        // 10 000,00 USD at 21,20 Kč, the ČNB rate of 15. 1. 2027.
        let dollars = try await storePaid(.usd, 1_000_000, on: "2027-01-15", in: app)
        #expect(dollars.payment?.czkNetHalere == 21_200_000)

        await app.updateComputedUniformRates()

        let january = try await app.fxState(year: 2027)
        #expect(january.chosen == .uniform && january.effective == .cnbDaily)
        #expect(january.uniform == .notPublishedYet(year: 2027))
        #expect(try await database.uniformRates(year: 2027).isEmpty)
        #expect(try await payment(of: dollars, in: app) == dollars.payment)
        #expect(app.banner == nil)

        try await changeDay(to: "2027-02-01", in: app)

        let february = try await app.fxState(year: 2027)
        #expect(february.effective == .uniform && february.uniform.computedMonths == 1)
        let converted = try await payment(of: dollars, in: app)
        #expect(converted.conversion == .uniform && converted.czkNetHalere == 21_400_000)
        #expect(
            app.banner?.text
                == "Předběžný jednotný kurz 2027 je spočítaný z kurzu za leden: 1\u{00A0}USD ≈ 21,40\u{00A0}Kč. Platby"
                + " roku 2027 jsou jím přepočtené.")
    }

    /// The clock of the Mac set back from 1 November to 31 October: October has not ended, so the rate is computed over
    /// September again, and the banner does not say a month was added.
    @Test func theClockGoingBackRecomputesWithFewerMonths() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let app = try await makeApp(in: directory, clock: ManualClock(localNoon(2026, 11, 1)), monthEnds: 1...10)
        let dollars = try await storeDollarsPaid(in: app)
        await app.updateComputedUniformRates()
        #expect(await app.setFXMethod(.uniform, year: 2026) == .saved)
        #expect(try await payment(of: dollars, in: app).czkNetHalere == 21_380_000)
        app.banner = nil

        try await changeDay(to: "2026-10-31", in: app)

        #expect(try await computedRates(of: 2026, overMonths: 9, in: app) == [decimal("24.35"), decimal("21.35")])
        #expect(try await payment(of: dollars, in: app).czkNetHalere == 21_350_000)
        #expect(
            app.banner?.text
                == "Předběžný jednotný kurz 2026 je přepočítaný: 1\u{00A0}USD ≈ 21,35\u{00A0}Kč (dříve 21,38). Platby"
                + " roku 2026 jsou jím přepočtené.")
    }

    /// The keeper asked for while another conversion runs waits for its turn. The data is let go meanwhile (a lock
    /// after a change of the keys that failed), so when its turn comes it does nothing: it stores no rate, converts no
    /// payment and shows no banner. Asked for while the data is locked, it does nothing either.
    @Test(.hangGuard)
    func theKeeperDoesNothingWithTheDataClosed() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let app = try await makeApp(in: directory)
        let database = try #require(app.database)
        try await database.updateYearSettings(2026) { $0.incomeFXMethod = .uniform }
        let dollars = try await storeDollarsPaid(in: app)
        let gate = Gate()
        let running = Task { await app.convertPaymentsInTurn { _ in await gate.pass() } }
        await gate.untilARequestWaits()
        let runningTurn = app.latestConversion
        let keeper = Task { await app.updateComputedUniformRates() }
        try await waitUntil { app.latestConversion != runningTurn }
        let version = app.dataVersion

        app.lockAfterFailedChange(
            .newCode(number: 2, created: civilDate("2026-10-17"), replacedLabel: nil, replacedNumber: nil))
        await gate.open()
        await keeper.value
        _ = await running.value
        await app.updateComputedUniformRates()

        #expect(app.phase == .locked)
        #expect(try await database.uniformRates(year: 2026).isEmpty)
        #expect(try await database.invoice(id: dollars.id)?.payment == dollars.payment)
        #expect(app.banner == nil)
        #expect(app.dataVersion == version)
    }

    /// A year paid only in crowns, set to the uniform rate, gets its computed rate, which converts nothing: no banner
    /// tells of it.
    @Test func aYearPaidOnlyInCrownsGetsNoBanner() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let app = try await makeApp(in: directory)
        try await #require(app.database).updateYearSettings(2026) { $0.incomeFXMethod = .uniform }
        let crowns = try await storePaid(.czk, 4_500_000, on: "2026-06-30", in: app)

        await app.updateComputedUniformRates()

        #expect(try await computedRates(of: 2026, overMonths: 9, in: app) == [decimal("24.35"), decimal("21.35")])
        #expect(try await app.fxState(year: 2026).effective == .uniform)
        #expect(try await payment(of: crowns, in: app) == crowns.payment)
        #expect(app.banner == nil)
    }

    /// A year set to the uniform rate and paid only in pounds, whose rate the app does not compute, stays at the daily
    /// rates: no banner tells of the rates of dollars and euros it got.
    @Test func aYearPaidOnlyInACurrencyWithoutAComputedRateGetsNoBanner() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let app = try await makeApp(in: directory)
        let database = try #require(app.database)
        let pound = try #require(CurrencyCode("GBP"))
        try await database.insertCNBRates([
            CNBRateRow(declaredOn: civilDate("2026-06-30"), currency: pound, amount: 1, rate: decimal("28.500"))
        ])
        try await database.updateYearSettings(2026) { $0.incomeFXMethod = .uniform }
        let pounds = try await storePaid(pound, 100_000, on: "2026-06-30", in: app)

        await app.updateComputedUniformRates()

        #expect(try await computedRates(of: 2026, overMonths: 9, in: app) == [decimal("24.35"), decimal("21.35")])
        let state = try await app.fxState(year: 2026)
        #expect(state.uniform == .missingCurrency(pound) && state.effective == .cnbDaily)
        #expect(try await payment(of: pounds, in: app) == pounds.payment)
        #expect(app.banner == nil)
    }

    /// Rates of 2026 entered by hand and removed again in Nastavení › Rok: the year, set to the uniform rate, takes the
    /// rate the app computes at once, and its payments are converted at it.
    @Test func removingTypedRatesFallsBackToTheComputedRate() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let app = try await makeApp(in: directory)
        let dollars = try await storeDollarsPaid(in: app)
        app.showSettings(.year)
        let model = YearTabModel(app: app)
        await model.load()
        #expect(await model.saveManualUniformRates(usd: "21,90", eur: "", instruction: ""))
        await model.setFXMethod(.uniform)
        // 10 000,00 USD at 21,90 Kč.
        #expect(try await payment(of: dollars, in: app).czkNetHalere == 21_900_000)
        model.askToRemoveRates()

        await model.removeManualUniformRates()

        #expect(try await computedRates(of: 2026, overMonths: 9, in: app) == [decimal("24.35"), decimal("21.35")])
        #expect(try await app.fxState(year: 2026).effective == .uniform)
        let converted = try await payment(of: dollars, in: app)
        #expect(converted.conversion == .uniform && converted.czkNetHalere == 21_350_000)
        #expect(model.saveFailure == nil)
    }

    // MARK: The banner

    /// The computed rates of `year` over `months` months, by currency: dollars at `usd` and euros at `eur`, either left
    /// out when nil.
    private func computed(_ months: Int, usd: String?, eur: String? = nil, year: Int = 2026) -> [UniformRate] {
        [(CurrencyCode.eur, eur), (.usd, usd)].compactMap { currency, rate in
            rate.map {
                UniformRate(
                    year: year, currency: currency, amount: 1, rate: decimal($0), instruction: "", origin: .computed,
                    computedMonths: months)
            }
        }
    }

    @Test func theFirstRateOfAYearSaysTheMonthsItIsComputedFrom() {
        #expect(
            ComputedRateBanner.text(year: 2027, before: [], after: computed(1, usd: "21.40", year: 2027), paid: [.usd])
                == "Předběžný jednotný kurz 2027 je spočítaný z kurzu za leden: 1\u{00A0}USD ≈ 21,40\u{00A0}Kč. Platby"
                + " roku 2027 jsou jím přepočtené.")
        #expect(
            ComputedRateBanner.text(year: 2027, before: [], after: computed(3, usd: "21.40", year: 2027), paid: [.usd])
                == "Předběžný jednotný kurz 2027 je spočítaný z kurzů za leden–březen: 1\u{00A0}USD ≈ 21,40\u{00A0}Kč."
                + " Platby roku 2027 jsou jím přepočtené.")
    }

    @Test(arguments: [
        (9, "i s kurzem za říjen"),
        (8, "i s kurzy za září a říjen"),
        (7, "i s kurzy za srpen–říjen"),
        (1, "i s kurzy za únor–říjen"),
    ])
    func aRateWithMoreMonthsNamesTheMonthsAdded(monthsBefore: Int, added: String) {
        let text = ComputedRateBanner.text(
            year: 2026, before: computed(monthsBefore, usd: "21.35"), after: computed(10, usd: "21.38"), paid: [.usd])

        #expect(
            text
                == "Předběžný jednotný kurz 2026 je přepočítaný \(added): 1\u{00A0}USD ≈ 21,38\u{00A0}Kč (dříve"
                + " 21,35). Platby roku 2026 jsou jím přepočtené.")
    }

    /// The same months with other rates (rates of the ČNB stored anew), or fewer months (the clock set back): no month
    /// is named.
    @Test(arguments: [10, 11])
    func aRateWithAsManyMonthsOrFewerNamesNoMonth(monthsBefore: Int) {
        let text = ComputedRateBanner.text(
            year: 2026, before: computed(monthsBefore, usd: "21.38"), after: computed(10, usd: "21.35"), paid: [.usd])

        #expect(
            text
                == "Předběžný jednotný kurz 2026 je přepočítaný: 1\u{00A0}USD ≈ 21,35\u{00A0}Kč (dříve 21,38). Platby"
                + " roku 2026 jsou jím přepočtené.")
    }

    @Test func bothCurrenciesAreNamedDollarsFirst() {
        let text = ComputedRateBanner.text(
            year: 2026, before: computed(9, usd: "21.35", eur: "24.35"),
            after: computed(10, usd: "21.38", eur: "24.36"), paid: [.eur, .usd])

        #expect(
            text
                == "Předběžný jednotný kurz 2026 je přepočítaný i s kurzem za říjen: 1\u{00A0}USD ≈ 21,38\u{00A0}Kč"
                + " (dříve 21,35), 1\u{00A0}EUR ≈ 24,36\u{00A0}Kč (dříve 24,35). Platby roku 2026 jsou jím"
                + " přepočtené.")
    }

    /// Only the currencies the year was paid in are named, and a rate the year did not have before has no earlier
    /// rate to name.
    @Test func onlyTheCurrenciesPaidInAreNamedWithTheRateTheyHadBefore() {
        #expect(
            ComputedRateBanner.text(
                year: 2026, before: computed(9, usd: "21.35", eur: "24.35"),
                after: computed(10, usd: "21.38", eur: "24.36"), paid: [.eur])
                == "Předběžný jednotný kurz 2026 je přepočítaný i s kurzem za říjen: 1\u{00A0}EUR ≈ 24,36\u{00A0}Kč"
                + " (dříve 24,35). Platby roku 2026 jsou jím přepočtené.")
        #expect(
            ComputedRateBanner.text(
                year: 2026, before: computed(9, usd: "21.35"), after: computed(10, usd: "21.38", eur: "24.36"),
                paid: [.usd, .eur])
                == "Předběžný jednotný kurz 2026 je přepočítaný i s kurzem za říjen: 1\u{00A0}USD ≈ 21,38\u{00A0}Kč"
                + " (dříve 21,35), 1\u{00A0}EUR ≈ 24,36\u{00A0}Kč. Platby roku 2026 jsou jím přepočtené.")
    }

    @Test func aYearPaidInNeitherDollarsNorEurosOfTheRateHasNoBanner() throws {
        let after = computed(10, usd: "21.38")
        let before = computed(9, usd: "21.35")
        let pound = try #require(CurrencyCode("GBP"))

        #expect(ComputedRateBanner.text(year: 2026, before: before, after: after, paid: []) == nil)
        #expect(ComputedRateBanner.text(year: 2026, before: before, after: after, paid: [pound]) == nil)
        // Paid in euros, which the rate has none of.
        #expect(ComputedRateBanner.text(year: 2026, before: before, after: after, paid: [.eur]) == nil)
        // The rates were deleted.
        #expect(ComputedRateBanner.text(year: 2026, before: before, after: [], paid: [.usd]) == nil)
    }
}
