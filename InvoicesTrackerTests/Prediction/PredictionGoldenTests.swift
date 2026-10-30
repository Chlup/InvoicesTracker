import Foundation
import Testing
@testable import InvoicesTracker

/// The prediction of the sample's years and the levies the engine works out with it, as of 31 December: 2026 as of
/// 17. 10. 2026, the closed years 2025 and 2024, and 2026 changed in one thing at a time. The incomes, the levies and
/// what is owed or overpaid were worked out for the same data by a separate implementation. Below the income the
/// figures round the income to whole crowns first: the profit of 2026 is 1 543 157 Kč, and the health assessment
/// base is 771 578,50 Kč.
struct PredictionGoldenTests {
    // MARK: Helpers

    /// The outcome of `input`, with the settings, the deductions, the advances and the family of its year in the
    /// sample, and the receipts of the input.
    private func outcome(of input: PredictionInput) throws -> PredictionOutcome {
        var yearInput = PredictionSample.yearInput(year: input.year)
        yearInput.receipts = input.receipts
        return try PredictionOutcome.make(prediction: IncomePrediction.make(input), yearInput: yearInput)
    }

    /// Checks the income of `outcome` in haléře, which the prediction and the engine count alike, and its levies in
    /// whole Kč: the net tax, the social and the health insurance.
    private func expectFigures(
        _ outcome: PredictionOutcome, income: Int64, tax: Int64, social: Int64, health: Int64,
        sourceLocation: SourceLocation = #_sourceLocation
    ) {
        #expect(outcome.prediction.incomeHalere == income, "income", sourceLocation: sourceLocation)
        #expect(outcome.result.incomeHalere == income, "the engine's income", sourceLocation: sourceLocation)
        #expect(outcome.result.netTax == tax, "tax", sourceLocation: sourceLocation)
        #expect(outcome.result.social.insurance == social, "social insurance", sourceLocation: sourceLocation)
        #expect(outcome.result.health.insurance == health, "health insurance", sourceLocation: sourceLocation)
    }

    /// A receipt the prediction makes up: `halere` paid on `day`.
    private func expected(_ halere: Int64, on day: String) -> Receipt {
        Receipt(day: civilDate(day), czkNetHalere: halere, czkVatHalere: 0, source: .synthetic)
    }

    private func row(_ id: Int64, in prediction: IncomePrediction) throws -> ClientPrediction {
        try #require(prediction.clients.first { $0.id == id }, "No client \(id)")
    }

    private func index(of number: String, in input: PredictionInput) throws -> Int {
        try #require(input.invoices.firstIndex { $0.number == number }, "No invoice \(number)")
    }

    // MARK: 2026

    /// 2 191 771,35 Kč received from 11 payments by 17. 10. 2026 and 551 385,64 Kč expected: the October draft at
    /// 21,320 Kč/USD, November at the four-invoice annual daily-CZK mean of 285 692,84 Kč, and two Tango invoices
    /// of 4 500 Kč. December contributes 290 192,84 Kč only in January. Sierra is no longer active.
    @Test func theSampleYearPredictsItsWholeIncome() throws {
        let prediction = IncomePrediction.make(PredictionSample.input(year: 2026))

        #expect(prediction.year == 2026)
        #expect(prediction.now == civilDate("2026-10-17"))
        #expect(!prediction.isClosed)
        #expect(prediction.receivedHalere == 219_177_135)
        #expect(prediction.receivedCount == 11)
        #expect(!prediction.includesAdjustments)
        #expect(prediction.waitingHalere == 0)
        #expect(prediction.waitingCount == 0)
        #expect(prediction.expectedHalere == 55_138_564)
        #expect(prediction.expectedCount == 4)
        #expect(prediction.nextYearHalere == 29_019_284)
        #expect(prediction.incomeHalere == 274_315_699)
        #expect(!prediction.usesUniformRate)
        #expect(prediction.rateDay == civilDate("2026-10-16"))
        #expect(prediction.clients.map(\.name) == ["Foxtrot, Inc.", "Tango s.r.o.", "Sierra, SE"])
        #expect(prediction.clients.map(\.isActive) == [true, true, false])
        #expect(
            prediction.syntheticReceipts == [
                expected(25_669_280, on: "2026-11-07"), expected(450_000, on: "2026-11-07"),
                expected(28_569_284, on: "2026-12-07"), expected(450_000, on: "2026-12-08"),
            ])

        let foxtrot = try row(PredictionSample.foxtrot.id, in: prediction)
        let past = [PredictionMonthKind](repeating: .past, count: 5)
        #expect(
            foxtrot.months.map(\.kind)
                == past + [.paid, .paid, .paid, .paid, .expected, .expected, .expectedNextYear])
        #expect(
            foxtrot.months.map(\.amountHalere) == [
                0, 0, 0, 0, 0, 28_880_600, 26_880_560, 27_943_300, 30_572_675, 25_669_280, 28_569_284, 28_569_284,
            ])
        #expect(foxtrot.months.map(\.month) == Array(1...12))
        #expect(foxtrot.months[5].invoiceNumbers == ["20260601"])
        #expect(foxtrot.months[9].isFromDraft)
        #expect(foxtrot.months[9].invoiceNumbers == ["20261001"])
        #expect(foxtrot.months[9...].map(\.isOn) == [true, true, true])
        #expect(foxtrot.months[9...].map(\.isAutomatic) == [true, true, true])
        #expect(foxtrot.delayDays == 7)
        #expect(foxtrot.isRegular)
        #expect(foxtrot.step == 1)
        #expect(foxtrot.currency == .usd)
        #expect(foxtrot.nextAmountHalere == 28_569_284)
        #expect(foxtrot.issuedCount == 7)
        #expect(foxtrot.lastIssued == civilDate("2026-09-30"))
        #expect(foxtrot.receivedHalere == 114_277_135)
        #expect(foxtrot.previousYearWaitingHalere == 0)
        #expect(foxtrot.expectedHalere == 54_238_564)
        #expect(foxtrot.addsHalere == 54_238_564)
        #expect(foxtrot.nextYearHalere == 28_569_284)
        #expect(foxtrot.hasInvoiceInYear)
        #expect(!foxtrot.isEdited)

        let tango = try row(PredictionSample.tango.id, in: prediction)
        #expect(
            tango.months.map(\.kind)
                == [PredictionMonthKind](repeating: .past, count: 7)
                + [.paid, .paid, .expected, .expected, .expectedNextYear])
        #expect(tango.months.map(\.amountHalere) == [0, 0, 0, 0, 0, 0, 0, 450_000, 450_000, 450_000, 450_000, 450_000])
        #expect(!tango.months[9].isFromDraft)
        #expect(tango.delayDays == 8)
        #expect(tango.isRegular)
        #expect(tango.nextAmountHalere == 450_000)
        #expect(tango.receivedHalere == 900_000)
        #expect(tango.addsHalere == 900_000)
        #expect(tango.nextYearHalere == 450_000)

        let sierra = try row(PredictionSample.sierra.id, in: prediction)
        #expect(
            sierra.months.map(\.kind)
                == [PredictionMonthKind](repeating: .paid, count: 5)
                + [.past, .past, .past, .past, .notExpected, .notExpected, .notExpected])
        #expect(
            sierra.months.map(\.amountHalere)
                == [22_000_000, 19_000_000, 21_000_000, 21_000_000, 21_000_000, 0, 0, 0, 0, 0, 0, 0])
        #expect(sierra.months[9...].map(\.isOn) == [false, false, false])
        #expect(sierra.delayDays == 5)
        #expect(!sierra.isRegular)
        #expect(sierra.issuedCount == 29)
        #expect(sierra.lastIssued == civilDate("2026-05-29"))
        #expect(sierra.receivedHalere == 104_000_000)
        #expect(sierra.addsHalere == 0)
    }

    /// The independent annual levies are tax 114 786 Kč, social 247 832 Kč and health 104 164 Kč. Advances leave
    /// 68 786 + 97 272 + 32 644 = 198 702 Kč owed. The marginal levy remains 37,8 %.
    @Test func theSampleYearsLeviesComeFromTheEngine() throws {
        let outcome = try outcome(of: PredictionSample.input(year: 2026))
        let result = outcome.result

        #expect(result.asOf == civilDate("2026-12-31"))
        expectFigures(outcome, income: 274_315_699, tax: 114_786, social: 247_832, health: 104_164)
        #expect(outcome.plannedTotal(.tax) == 46_000)
        #expect(outcome.plannedTotal(.social) == 150_560)
        #expect(outcome.plannedTotal(.health) == 71_520)
        #expect(outcome.plannedCount(.tax) == 2)
        #expect(outcome.plannedCount(.social) == 12)
        #expect(outcome.plannedCount(.health) == 12)
        #expect(Authority.allCases.map { result.balance($0).remaining } == [68_786, 97_272, 32_644])
        #expect(outcome.owedTotal == 198_702)
        #expect(outcome.overpaidTotal == 0)
        #expect(CzechFormat.percent(result.marginalTotal) == "37,8\u{00A0}%")
        // The engine was given the 11 payments received by today and the 4 expected ones.
        #expect(outcome.input.receipts.count == 15)
        #expect(outcome.input.receipts.filter { $0.source == .synthetic } == outcome.prediction.syntheticReceipts)
        // Below the income, the engine's own figures.
        #expect(result.P == 2_743_157)
        #expect(result.uncappedExpenses == 1_645_894)
        #expect(result.V == 1_200_000)
        #expect(result.DZ == 1_543_157)
        #expect(result.B == 1_386_600)
        #expect(result.social.base == 848_737)
        #expect(result.health.baseHalere == 77_157_850)
    }

    // MARK: Closed years

    /// A past year is predicted as of its last day, so nothing is expected and its figures are final. 2025:
    /// 2 931 159,89 Kč from 16 payments, nothing left for 2026. 2024: 2 372 500,00 Kč from 11 payments; Sierra's
    /// December invoice is paid on 5. 1. 2025, so 207 500,00 Kč go to 2025.
    @Test func aClosedYearPredictsNothing() throws {
        let year2025 = try outcome(of: PredictionSample.input(year: 2025))
        let year2024 = try outcome(of: PredictionSample.input(year: 2024))

        #expect(year2025.prediction.isClosed)
        #expect(year2025.prediction.now == civilDate("2025-12-31"))
        expectFigures(year2025, income: 293_115_989, tax: 142_986, social: 278_025, health: 116_854)
        #expect(year2025.owedTotal == 330_065)
        #expect(year2025.overpaidTotal == 0)
        #expect(year2025.prediction.receivedCount == 16)
        #expect(year2025.prediction.waitingHalere == 0)
        #expect(year2025.prediction.expectedHalere == 0)
        #expect(year2025.prediction.nextYearHalere == 0)
        #expect(year2025.prediction.syntheticReceipts.isEmpty)
        #expect(year2025.prediction.clients.map(\.name) == ["Sierra, SE", "Foxtrot, Inc.", "Tango s.r.o."])
        #expect(year2025.prediction.clients.map(\.isActive) == [true, true, false])
        #expect(year2025.prediction.clients.map(\.delayDays) == [5, 8, 30])
        let finalKinds: Set<PredictionMonthKind> = [.paid, .past]
        #expect(year2025.prediction.clients.allSatisfy { $0.months.allSatisfy { finalKinds.contains($0.kind) } })
        // Below the income, the engine's own figures.
        #expect(year2025.result.DZ == 1_731_160)
        #expect(year2025.result.health.baseHalere == 86_558_000)

        #expect(year2024.prediction.isClosed)
        expectFigures(year2024, income: 237_250_000, tax: 73_056, social: 188_304, health: 79_144)
        #expect(year2024.owedTotal == 152_704)
        #expect(year2024.prediction.receivedCount == 11)
        #expect(year2024.prediction.nextYearHalere == 20_750_000)
        #expect(year2024.prediction.syntheticReceipts.isEmpty)
        #expect(year2024.prediction.clients.map(\.name) == ["Sierra, SE", "Foxtrot, Inc.", "Tango s.r.o."])
        #expect(year2024.prediction.clients.map(\.isActive) == [true, false, false])
        let sierra = try row(PredictionSample.sierra.id, in: year2024.prediction)
        #expect(sierra.months[11].kind == .waitingNextYear)
        #expect(sierra.months[11].amountHalere == 20_750_000)
        #expect(sierra.nextYearHalere == 20_750_000)
        #expect(sierra.addsHalere == 0)
    }

    // MARK: 2026 changed in one thing

    /// Foxtrot's November switched off, and Sierra's November and December on: Sierra's 208 000 Kč of November count,
    /// its December's are paid in January.
    @Test func changedMonthsMoveTheIncome() throws {
        let changes: [Int64: [Int: Bool]] = [1: [11: false], 3: [11: true, 12: true]]
        let outcome = try outcome(of: PredictionSample.input(year: 2026, changes: changes))

        expectFigures(outcome, income: 266_546_415, tax: 103_131, social: 235_354, health: 98_919)
        #expect(outcome.owedTotal == 169_324)
        #expect(outcome.prediction.nextYearHalere == 49_819_284)
        let foxtrot = try row(PredictionSample.foxtrot.id, in: outcome.prediction)
        #expect(foxtrot.months[10].kind == .notExpected)
        #expect(foxtrot.months[10].isAutomatic)
        #expect(foxtrot.isEdited)
        let sierra = try row(PredictionSample.sierra.id, in: outcome.prediction)
        #expect(sierra.months[10...].map(\.kind) == [.expected, .expectedNextYear])
        #expect(sierra.isActive)
    }

    /// Foxtrot's October invoice is issued instead of being a draft, and is not paid yet: 256 692,80 Kč wait for a
    /// payment. Its issue-day conversion joins the four paid samples: 139 946 415 / 5 = 27 989 283 haléře.
    @Test func anIssuedUnpaidInvoiceCountsAsWaiting() throws {
        var input = PredictionSample.input(year: 2026)
        input.invoices[try index(of: "20261001", in: input)].status = .issued

        let outcome = try outcome(of: input)
        let foxtrot = try row(PredictionSample.foxtrot.id, in: outcome.prediction)

        expectFigures(outcome, income: 273_735_698, tax: 113_916, social: 246_900, health: 103_772)
        #expect(outcome.owedTotal == 196_508)
        #expect(outcome.prediction.waitingHalere == 25_669_280)
        #expect(outcome.prediction.waitingCount == 1)
        #expect(foxtrot.months[9].kind == .waiting)
        #expect(foxtrot.months[9].amountHalere == 25_669_280)
        #expect(foxtrot.nextAmountHalere == 27_989_283)
        #expect(foxtrot.issuedCount == 8)
    }

    /// No clients, no invoices and no templates: no income, and the levies are the minimum insurance of the whole
    /// year. The advances pay 168 360 Kč more than that.
    @Test func withoutClientsOnlyTheMinimumsRemain() throws {
        var input = PredictionSample.input(year: 2026)
        input.clients = []
        input.invoices = []
        input.templates = []
        input.receipts = []

        let outcome = try outcome(of: input)

        expectFigures(outcome, income: 0, tax: 0, social: 60_056, health: 39_664)
        #expect(outcome.owedTotal == 0)
        #expect(outcome.overpaidTotal == 168_360)
        #expect(outcome.prediction.clients.isEmpty)
    }

    /// Two new clients in crowns, without invoices and due in the default 14 days, instead of the sample's data, both
    /// with November switched on. The first has a template of 10 hours at 1 000,50 Kč, so its November brings
    /// 10 005,00 Kč; the second has none, and its November has an unknown amount.
    @Test func templatesGiveAnAmountAndTheirAbsenceAnUnknownOne() throws {
        var input = PredictionSample.input(year: 2026, changes: [1: [11: true], 2: [11: true]])
        input.clients = [Client(id: 1, name: "Nováček s.r.o."), Client(id: 2, name: "Bez šablony s.r.o.")]
        input.invoices = []
        input.receipts = []
        let item = TemplateItem(
            description: "Konzultace", quantity: decimal("10"), unit: "hod", unitPriceMinor: 100_050)
        input.templates = [
            InvoiceTemplate(id: 1, name: "Konzultace", clientID: 1, items: [item], vatMode: .domestic21, dueDays: 14)
        ]

        let outcome = try outcome(of: input)
        let withTemplate = try row(1, in: outcome.prediction)
        let withoutTemplate = try row(2, in: outcome.prediction)

        expectFigures(outcome, income: 1_000_500, tax: 0, social: 60_056, health: 39_664)
        #expect(outcome.overpaidTotal == 168_360)
        #expect(withTemplate.nextAmountFromTemplate)
        #expect(withTemplate.months[10].kind == .expected)
        #expect(withTemplate.months[10].amountHalere == 1_000_500)
        #expect(withoutTemplate.months[10].kind == .expected)
        #expect(withoutTemplate.months[10].amountHalere == 0)
        #expect([withTemplate.isActive, withoutTemplate.isActive] == [true, true])
    }

    /// A single client with a single invoice of 10 000 Kč, issued on 30. 9. 2026 and due on 14. 10., instead of the
    /// sample's data. On 17. 10. it is overdue, so it is expected tomorrow.
    @Test func aSingleOverdueInvoiceIsPaidTomorrow() throws {
        let client = Client(id: 1, name: "Jediný s.r.o.", dueDays: 14)
        var invoice = Invoice.fixture(
            number: "20260901", issued: "2026-09-30", dueDate: "2026-10-14", items: [.fixture("1", at: 1_000_000)])
        invoice.id = 1
        invoice.clientID = client.id
        var input = PredictionSample.input(year: 2026)
        input.clients = [client]
        input.invoices = [invoice]
        input.templates = []
        input.receipts = []

        let outcome = try outcome(of: input)
        let single = try row(1, in: outcome.prediction)

        expectFigures(outcome, income: 1_000_000, tax: 0, social: 60_056, health: 39_664)
        #expect(outcome.prediction.waitingHalere == 1_000_000)
        #expect(outcome.prediction.syntheticReceipts == [expected(1_000_000, on: "2026-10-18")])
        #expect(single.months[8].kind == .waiting)
        #expect(single.nextAmountHalere == 1_000_000)
        #expect(!single.isRegular)
    }

    /// On 31. 12. 2026 the year is closed: only the money received counts, 2 191 771,35 Kč. The tax advances pay
    /// 13 924 Kč more than the tax and the health advances 4 575 Kč more than the health insurance, 18 499 Kč in all.
    @Test func onTheLastDayOfTheYearTheYearIsClosed() throws {
        let outcome = try outcome(of: PredictionSample.input(year: 2026, today: civilDate("2026-12-31")))

        #expect(outcome.prediction.isClosed)
        expectFigures(outcome, income: 219_177_135, tax: 32_076, social: 159_279, health: 66_945)
        #expect(outcome.owedTotal == 8_719)
        #expect(outcome.overpaidTotal == 18_499)
        #expect(outcome.prediction.expectedHalere == 0)
        #expect(outcome.prediction.syntheticReceipts.isEmpty)
    }

    /// Income adjustments of −50 000 Kč on 10. 3. 2026 and of +100 000 Kč on 10. 11. 2026: only the first is dated by
    /// today, so only it counts. It is among the money received, though not one of the 11 payments.
    @Test func onlyAdjustmentsUpToTodayCount() throws {
        var input = PredictionSample.input(year: 2026)
        input.receipts += [
            Receipt(day: civilDate("2026-03-10"), czkNetHalere: -5_000_000, czkVatHalere: 0, source: .adjustment(1)),
            Receipt(day: civilDate("2026-11-10"), czkNetHalere: 10_000_000, czkVatHalere: 0, source: .adjustment(2)),
        ]

        let outcome = try outcome(of: input)

        expectFigures(outcome, income: 269_315_699, tax: 107_286, social: 239_802, health: 100_789)
        #expect(outcome.owedTotal == 179_797)
        #expect(outcome.prediction.receivedHalere == 214_177_135)
        #expect(outcome.prediction.receivedCount == 11)
        #expect(outcome.prediction.includesAdjustments)
    }

    /// Sierra's invoice of December 2025, 215 000 Kč, is not paid: it is the year before's, so it is expected this
    /// year, tomorrow, and makes Sierra active.
    @Test func lastYearsUnpaidInvoiceCountsThisYear() throws {
        var input = PredictionSample.input(year: 2026)
        input.invoices[try index(of: "2025-12-01", in: input)].payment = nil

        let outcome = try outcome(of: input)
        let sierra = try row(PredictionSample.sierra.id, in: outcome.prediction)

        expectFigures(outcome, income: 295_815_699, tax: 147_036, social: 282_361, health: 118_676)
        #expect(outcome.owedTotal == 279_993)
        #expect(sierra.previousYearWaitingHalere == 21_500_000)
        #expect(sierra.addsHalere == 21_500_000)
        #expect(sierra.isActive)
        #expect(outcome.prediction.waitingHalere == 21_500_000)
    }

    /// A further client in crowns, due in 14 days, with invoices of 100 000 Kč issued on 31. 1., 30. 4. and
    /// 31. 7. 2026, each paid 9 days later: quarterly, so October is expected, and nothing else.
    @Test func aQuarterlyClientIsExpectedEveryThirdMonth() throws {
        let quarterly = Client(id: 4, name: "Čtvrtletní s.r.o.", dueDays: 14)
        var input = PredictionSample.input(year: 2026)
        input.clients.append(quarterly)
        for (offset, issued) in ["2026-01-31", "2026-04-30", "2026-07-31"].enumerated() {
            var invoice = Invoice.fixture(
                number: "Q\(offset + 1)", issued: issued, duzp: issued, dueDate: issued,
                items: [.fixture("1", at: 10_000_000)],
                payment: Payment.fixture(
                    on: civilDate(issued).adding(days: 9).iso, net: 10_000_000, vat: 2_100_000))
            invoice.id = Int64(40 + offset)
            invoice.clientID = quarterly.id
            input.invoices.append(invoice)
        }
        input.receipts = PredictionSample.receipts(of: input.invoices, year: 2026)

        let outcome = try outcome(of: input)
        let row = try row(quarterly.id, in: outcome.prediction)

        expectFigures(outcome, income: 314_315_699, tax: 176_690, social: 312_072, health: 131_164)
        #expect(outcome.owedTotal == 351_846)
        #expect(outcome.prediction.receivedCount == 14)
        #expect(row.delayDays == 9)
        #expect(row.step == 3)
        #expect(row.months[9].kind == .expected)
        #expect(row.months[9].amountHalere == 10_000_000)
        #expect(row.months.filter(\.isOn).map(\.month) == [10])
    }

    /// 2026 on the uniform rate of 21,500 Kč for a dollar: Foxtrot's payments are converted at it (June's 13 720,00 USD
    /// are 294 980,00 Kč), as is its draft. The annual mean still uses daily conversions, 285 692,84 Kč.
    @Test func theUniformRateConvertsTheExpectedInvoices() throws {
        let uniform = ExchangeRate(currency: .usd, amount: 1, rate: decimal("21.5"))
        var input = PredictionSample.input(year: 2026)
        input.invoices = input.invoices.map { invoice in
            guard invoice.currency == .usd, var payment = invoice.payment, payment.date.year == 2026 else {
                return invoice
            }
            payment.conversion = .uniform
            payment.czkNetHalere = uniform.czkHalere(fromMinor: invoice.netMinor)
            payment.rate = StoredRate(rate: uniform, declaredOn: civilDate("2026-12-31"))
            var rebased = invoice
            rebased.payment = payment
            return rebased
        }
        input.receipts = PredictionSample.receipts(of: input.invoices, year: 2026)
        input.rates = [.usd: uniform]
        input.usesUniformRate = true
        input.rateDay = nil

        let outcome = try outcome(of: input)
        let foxtrot = try row(PredictionSample.foxtrot.id, in: outcome.prediction)

        expectFigures(outcome, income: 276_892_784, tax: 118_656, social: 251_971, health: 105_903)
        #expect(outcome.owedTotal == 208_450)
        #expect(foxtrot.months[5].amountHalere == 29_498_000)
        #expect(foxtrot.months[9...].map(\.amountHalere) == [25_886_000, 28_569_284, 28_569_284])
        #expect(outcome.prediction.usesUniformRate)
        #expect(outcome.prediction.rateDay == nil)
    }

    // MARK: Advances

    /// A year without planned advances: the advances of the year are 0 in 0 payments, and what is owed with the
    /// returns is each levy whole, 466 782 Kč together.
    @Test func aYearWithoutPlannedAdvancesOwesTheWholeLevies() throws {
        var yearInput = PredictionSample.yearInput(year: 2026)
        yearInput.advances = AdvancePlan.empty

        let outcome = try PredictionOutcome.make(
            prediction: IncomePrediction.make(PredictionSample.input(year: 2026)), yearInput: yearInput)

        for authority in Authority.allCases {
            #expect(outcome.plannedTotal(authority) == 0, "\(authority)")
            #expect(outcome.plannedCount(authority) == 0, "\(authority)")
            #expect(outcome.result.balance(authority).remaining == outcome.result.balance(authority).liability)
        }
        #expect(outcome.owedTotal == 466_782)
        #expect(outcome.overpaidTotal == 0)
    }
}
