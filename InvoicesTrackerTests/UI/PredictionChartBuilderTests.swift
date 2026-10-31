import Foundation
import Testing
@testable import InvoicesTracker

/// The twelve months of the chart on the card of the estimate in Přehled: the actual months up to today, which come
/// from the invoices and the payments in the data, and the rest of the year, which comes from the prediction. The
/// figures of the prediction sample's 2026 as of Saturday 17. 10. 2026 were worked out for the same data by a separate
/// implementation, in crowns and haléře; the texts of the months tell them in whole Kč, rounded half up. In every
/// expected string `\u{00A0}` is the no-break space.
struct PredictionChartBuilderTests {
    // MARK: Helpers

    /// "0 Kč": what a part that applies shows when nothing is in it.
    private let zero = "0\u{00A0}Kč"

    /// What each payment of an invoice in the prediction sample's 2026 adds to the levies of the year on its own day:
    /// the engine's effect of each receipt of the year whose source is an invoice.
    private var sampleEffects: [ReceiptEffect] {
        let year = PredictionSample.yearInput(year: 2026)
        return year.receipts.compactMap { receipt in
            guard case .invoice = receipt.source else { return nil }
            return TaxEngine.effect(of: receipt, in: year)
        }
    }

    /// The months of the chart of 2026 as of `today` for `outcome`, the prediction with the payments it expects: made
    /// from `rows` and `effects`, which are the sample's own unless given.
    private func months(
        of outcome: PredictionOutcome, today: CivilDate = PredictionSample.sampleToday,
        rows: [InvoiceChartRow] = SampleYear2026.chartRows, effects: [ReceiptEffect]? = nil
    ) -> [PredictionChartMonth] {
        PredictionChartBuilder.months(
            year: 2026, today: today, rows: rows, paymentEffects: effects ?? sampleEffects,
            prediction: outcome.prediction, expectedPayments: outcome.expectedPayments())
    }

    /// The months of the prediction sample's 2026 as of 17. 10. 2026, January first.
    private func sampleMonths() throws -> [PredictionChartMonth] {
        months(of: try PredictionSample.outcome(year: 2026))
    }

    /// The months of the chart of 2026 as of `today` made from `rows` and `effects` alone: the sample's prediction as
    /// of `today` with no invoice and no payment left in it, so that the chart holds what the rows and the effects give
    /// it and nothing that the prediction adds.
    private func monthsOfRows(
        _ rows: [InvoiceChartRow], effects: [ReceiptEffect] = [], today: CivilDate
    ) throws -> [PredictionChartMonth] {
        var prediction = try PredictionSample.outcome(year: 2026, today: today).prediction
        prediction.expectedInvoices = []
        return PredictionChartBuilder.months(
            year: 2026, today: today, rows: rows, paymentEffects: effects, prediction: prediction,
            expectedPayments: [])
    }

    /// The six amounts of `month` in haléře: issued, received and net, each the actual part and then the estimate.
    private func amounts(of month: PredictionChartMonth) -> [Int64] {
        [
            month.issuedActualHalere, month.issuedEstimateHalere, month.receivedActualHalere,
            month.receivedEstimateHalere, month.netActualHalere, month.netEstimateHalere,
        ]
    }

    /// The six texts of `month`, in the order of `amounts(of:)`.
    private func texts(of month: PredictionChartMonth) -> [String] {
        [
            month.issuedActualText, month.issuedEstimateText, month.receivedActualText, month.receivedEstimateText,
            month.netActualText, month.netEstimateText,
        ]
    }

    /// A row of the chart: an invoice of `net` minor units without VAT, issued on `issued` and, when `paymentNet` is
    /// given, paid on `paidOn` with that many haléře without VAT.
    private func row(
        _ id: Int64, issued: String, net: Int64, currency: CurrencyCode = .czk, draft: Bool = false,
        inReview: Bool = false, paidOn: String? = nil, paymentNet: Int64? = nil, issueDayRate: ExchangeRate? = nil
    ) -> InvoiceChartRow {
        InvoiceChartRow(
            id: id, issueDate: civilDate(issued), isDraft: draft, inReview: inReview, currency: currency,
            netMinor: net, vatMinor: 0, paymentDate: paidOn.map(civilDate), paymentNetHalere: paymentNet,
            paymentVatHalere: paymentNet == nil ? nil : 0, issueDayRate: issueDayRate)
    }

    /// Both charts count a future-issued invoice once at today's available rate, without inventing received cash.
    @Test(arguments: [false, true])
    func futureIssuedIncomeUsesTodaysRateInBothCharts(includingExactDeclaration: Bool) async throws {
        let (database, directory) = try makeDatabase()
        defer { removeTemporaryDirectory(directory) }
        let today = civilDate("2026-10-28")
        var rates = [
            CNBRateRow(declaredOn: civilDate("2026-10-27"), currency: .usd, amount: 1, rate: decimal("20")),
            CNBRateRow(declaredOn: civilDate("2026-10-29"), currency: .usd, amount: 1, rate: decimal("30")),
        ]
        if includingExactDeclaration {
            rates.append(
                CNBRateRow(declaredOn: civilDate("2026-10-30"), currency: .usd, amount: 1, rate: decimal("40")))
        }
        try await database.insertCNBRates(rates)
        try await database.saveInvoice(
            Invoice.fixture(
                currency: .usd, issued: "2026-10-31", duzp: "2026-10-31",
                items: [InvoiceItem.fixture("1", at: 10_000)], vatMode: .outsideCountry))
        let rows = try await database.chartRows(fromYear: 2026, throughYear: 2026, today: today)
        #expect(rows.count == 1)

        let outcome = try PredictionSample.outcome(year: 2026, today: today)
        var prediction = outcome.prediction
        prediction.expectedInvoices = []
        let predictionMonths = PredictionChartBuilder.months(
            year: 2026, today: today, issuedThrough: civilDate("2026-10-31"), rows: rows,
            paymentEffects: [], prediction: prediction, expectedPayments: [])
        #expect(predictionMonths[9].issuedActualHalere == 200_000)
        #expect(predictionMonths[9].issuedActualIsApproximate)
        #expect(predictionMonths.reduce(0) { $0 + $1.issuedActualHalere + $1.issuedEstimateHalere } == 200_000)
        #expect(predictionMonths.allSatisfy { $0.receivedActualHalere == 0 && $0.receivedEstimateHalere == 0 })

        let overview = OverviewBuilder.build(
            OverviewInput(
                year: 2026, asOf: civilDate("2026-10-31"), today: today, result: outcome.result,
                advances: AdvancePlan.empty, latestReceipts: [], chartMode: .months, chartWithVAT: false,
                chartRows: rows, chartYears: [2026], vatByMonth: [Int64](repeating: 0, count: 12),
                vatToCheckMonths: [], foreignCurrencies: [.usd], uniformRates: [], yearsAtUniformRate: []))
        #expect(overview.columns[9].issuedNetHalere == 200_000)
        #expect(overview.columns[9].issuedIsApproximate)
        #expect(overview.columns.reduce(0) { $0 + $1.issuedNetHalere } == 200_000)
        #expect(overview.columns.allSatisfy { $0.receivedNetHalere == 0 })
    }

    // MARK: The parts of the year

    /// The months before the one of today are past, the one of today is current and those after it are future. Every
    /// month has its number for an id and the short name of the month for its label.
    @Test func theMonthsBeforeTodayArePastTheMonthOfTodayIsCurrentAndTheRestAreFuture() throws {
        let months = try sampleMonths()

        #expect(months.map(\.month) == Array(1...12))
        #expect(months.map(\.id) == Array(1...12))
        #expect(months.map(\.label) == CzechFormat.monthShort)
        #expect(months[9].label == "říj")
        #expect(
            months.map(\.part)
                == [PredictionChartMonth.Part](repeating: .past, count: 9) + [.current, .future, .future])
    }

    // MARK: The sample year

    /// September is over. Its actual parts are the two invoices issued in it, the dollar one worth the 30 572 675
    /// haléře it was paid on 2. 10., which is by today, and the crown one worth 450 000; the payment received in it;
    /// and what that payment left after the levies. It has no estimate.
    @Test func aPastMonthHasItsActualPartsAndNoEstimate() throws {
        let september = try sampleMonths()[8]

        #expect(september.title == "Září 2026")
        #expect(september.issuedActualHalere == 31_022_675)
        #expect(september.receivedActualHalere == 27_943_300)
        #expect(september.netActualHalere == 23_716_800)
        #expect(september.issuedEstimateHalere == 0)
        #expect(september.receivedEstimateHalere == 0)
        #expect(september.netEstimateHalere == 0)
        #expect(
            texts(of: september) == [
                "310\u{00A0}227\u{00A0}Kč", "—", "279\u{00A0}433\u{00A0}Kč", "—",
                "237\u{00A0}168\u{00A0}Kč", "—",
            ])
    }

    /// October is the current month, as of 17. 10.: the actual parts are what has happened by today, the two payments
    /// of 2. and 15. 10. and no invoice issued, and the estimate is what is still to come, the draft of 31. 10. and
    /// Tango's invoice of the month, which are issued after today and paid only in November.
    @Test func theCurrentMonthHasItsActualPartsUpToTodayAndTheEstimateOfTheRest() throws {
        let october = try sampleMonths()[9]

        #expect(october.title == "Říjen 2026 · do 17.\u{00A0}10. skutečnost, dál odhad")
        #expect(amounts(of: october) == [0, 26_119_280, 31_022_675, 0, 21_981_075, 0])
        #expect(
            texts(of: october) == [
                "0\u{00A0}Kč", "261\u{00A0}193\u{00A0}Kč", "310\u{00A0}227\u{00A0}Kč", "0\u{00A0}Kč",
                "219\u{00A0}811\u{00A0}Kč", "0\u{00A0}Kč",
            ])
    }

    /// November and December are in the future and have only their estimate. December's two invoices are paid in
    /// January, which is next year, but they are issued in the year, so they are in December's issued part; its
    /// payments are those of 7. and 8. 12.
    @Test func aFutureMonthHasOnlyItsEstimate() throws {
        let months = try sampleMonths()
        let november = months[10]
        let december = months[11]

        #expect(november.title == "Listopad 2026 · odhad")
        #expect(amounts(of: november) == [0, 29_019_284, 0, 26_119_280, 0, 16_243_380])
        #expect(november.issuedActualText == "—")
        #expect(november.receivedActualText == "—")
        #expect(november.netActualText == "—")
        #expect(november.issuedEstimateText == "290\u{00A0}193\u{00A0}Kč")
        #expect(november.receivedEstimateText == "261\u{00A0}193\u{00A0}Kč")
        #expect(november.netEstimateText == "162\u{00A0}434\u{00A0}Kč")
        #expect(december.title == "Prosinec 2026 · odhad")
        #expect(amounts(of: december) == [0, 29_019_284, 0, 29_019_284, 0, 18_046_984])
    }

    // MARK: What VoiceOver reads

    /// A past month is read with its actual parts, a future month with its estimates, both in the three phrases
    /// "vystaveno", "přijato" and "čistý příjem".
    @Test func aPastAndAFutureMonthAreReadWithTheirOnePart() throws {
        let months = try sampleMonths()

        #expect(
            months[8].accessibilityLabel == "Září 2026: vystaveno 310\u{00A0}227\u{00A0}Kč; přijato "
                + "279\u{00A0}433\u{00A0}Kč; čistý příjem 237\u{00A0}168\u{00A0}Kč")
        #expect(
            months[10].accessibilityLabel == "Listopad 2026 · odhad: vystaveno 290\u{00A0}193\u{00A0}Kč; přijato "
                + "261\u{00A0}193\u{00A0}Kč; čistý příjem 162\u{00A0}434\u{00A0}Kč")
    }

    /// The current month is read with both of its parts in each phrase, the actual one first.
    @Test func theCurrentMonthIsReadWithBothParts() throws {
        let october = try sampleMonths()[9]

        #expect(
            october.accessibilityLabel
                == "Říjen 2026 · do 17.\u{00A0}10. skutečnost, dál odhad: vystaveno 0\u{00A0}Kč skutečnost, "
                + "261\u{00A0}193\u{00A0}Kč odhad; přijato 310\u{00A0}227\u{00A0}Kč skutečnost, "
                + "0\u{00A0}Kč odhad; čistý příjem 219\u{00A0}811\u{00A0}Kč skutečnost, 0\u{00A0}Kč odhad")
    }

    /// Half a crown is rounded up, as everywhere else in whole Kč: a payment of 1 000,50 Kč is read as 1 001 Kč, and
    /// one of 0,49 Kč as nothing.
    @Test func halfACrownIsRoundedUpAndLessThanHalfIsDropped() throws {
        let rows = [
            row(201, issued: "2026-04-01", net: 100_050, paidOn: "2026-04-02", paymentNet: 100_050),
            row(202, issued: "2026-05-01", net: 49, paidOn: "2026-05-02", paymentNet: 49),
        ]

        let chart = try monthsOfRows(rows, today: civilDate("2026-06-15"))

        #expect(chart[3].issuedActualText == "1\u{00A0}001\u{00A0}Kč")
        #expect(chart[3].receivedActualText == "1\u{00A0}001\u{00A0}Kč")
        #expect(chart[4].issuedActualText == zero)
        #expect(chart[4].receivedActualText == zero)
        // The amounts themselves stay in haléře, as the chart is drawn from them.
        #expect(chart[3].issuedActualHalere == 100_050 && chart[4].receivedActualHalere == 49)
    }

    /// An unpaid invoice in dollars is worth the latest declared rate while the ČNB has not declared the rate of its
    /// day of issue, and its amount is approximate. The card of the estimate is an area of estimates as a whole, so the
    /// amount has no sign "≈" there, in the hover box or for VoiceOver; the note that explains the rate stays under the
    /// figures and is read after them.
    @Test func anApproximateIssuedAmountHasNoSignButKeepsItsNote() throws {
        var provisional = row(
            203, issued: "2026-10-10", net: 1_000_000, currency: .usd,
            issueDayRate: ExchangeRate(currency: .usd, amount: 1, rate: decimal("21.5")))
        provisional.issueDayRateIsProvisional = true

        let october = try monthsOfRows([provisional], today: civilDate("2026-10-17"))[9]

        #expect(october.issuedActualIsApproximate)
        #expect(october.issuedActualHalere == 21_500_000)
        #expect(october.issuedActualText == "215\u{00A0}000\u{00A0}Kč")
        #expect(october.notes == [ChartColumn.approximateIssuedNote])
        #expect(
            october.accessibilityLabel == "Říjen 2026 · do 17.\u{00A0}10. skutečnost, dál odhad: vystaveno "
                + "215\u{00A0}000\u{00A0}Kč skutečnost, \(zero) odhad; přijato \(zero) skutečnost, \(zero) odhad; "
                + "čistý příjem \(zero) skutečnost, \(zero) odhad; " + ChartColumn.approximateIssuedNote)
        let everyText = texts(of: october) + [october.accessibilityLabel, october.title] + october.notes
        #expect(everyText.allSatisfy { !$0.contains("≈") }, "\(everyText)")
    }

    // MARK: Where an invoice is counted

    /// Foxtrot's October invoice is issued, and still dated 31. 10., after today. It is no invoice issued by today, so
    /// its row is not in the actual part of October. The prediction expects it as an unpaid invoice of its own issue
    /// day, so it is in the estimate, at the prediction's amount for it (12 040,00 USD at today's 21,320 Kč) and not at
    /// the rate of its day of issue, which the ČNB has not declared yet (the row has 21,622).
    @Test func anIssuedInvoiceDatedAfterTodayIsInTheHatchedPartOfItsMonth() throws {
        var input = PredictionSample.input(year: 2026)
        input.invoices[try #require(input.invoices.firstIndex { $0.number == "20261001" })].status = .issued
        let outcome = try PredictionSample.outcome(of: input)
        var rows = SampleYear2026.chartRows
        rows[try #require(rows.firstIndex { $0.issueDate == civilDate("2026-10-31") })].isDraft = false
        let waiting = outcome.prediction.expectedInvoices.filter { $0.kind == .waiting }
        #expect(waiting.map(\.issueDate) == [civilDate("2026-10-31")])

        let october = months(of: outcome, rows: rows)[9]

        #expect(october.issuedActualHalere == 0)
        #expect(october.issuedEstimateHalere == 26_119_280)
        #expect(october.receivedActualHalere == 31_022_675)
        #expect(october.receivedEstimateHalere == 0)
    }

    /// Sierra's invoice of 30. 4. was paid on 10. 4., before it was issued, and today is 15. 4.: its 210 000,00 Kč
    /// have come and the invoice is yet to be issued. The prediction does not list it, as it waits for no payment, and
    /// the actual part of April stops at today, so its row is what puts it in April's hatched part, at the amount paid.
    /// Its payment is in April's actual received and in its net income, and no payment is expected for it. The next
    /// invoice, of 29. 5., is paid on 5. 5., after today, so it is a waiting invoice of the prediction, and May's
    /// hatched part holds it once. The sample expects nothing else in April or May: its first expected payment is in
    /// June.
    @Test func anIssuedInvoiceDatedAfterTodayAndPaidAlreadyIsInTheHatchedPartOfItsMonth() throws {
        let today = civilDate("2026-04-15")
        let outcome = try PredictionSample.outcome(year: 2026, today: today)
        let listed = outcome.prediction.expectedInvoices
        #expect(listed.filter { $0.issueDate.month == 4 }.isEmpty)
        #expect(listed.filter { $0.issueDate.month == 5 }.map(\.kind) == [.waiting])
        #expect(outcome.expectedPayments().allSatisfy { $0.day.month > 5 })
        let aprilEffects = sampleEffects.filter { $0.receipt.day.month == 4 }
        #expect(aprilEffects.map(\.receipt.day) == [civilDate("2026-04-07"), civilDate("2026-04-10")])

        let chart = months(of: outcome, today: today)
        let april = chart[3]
        let may = chart[4]

        #expect(april.issuedActualHalere == 0)
        #expect(april.issuedEstimateHalere == 21_000_000)
        #expect(april.receivedActualHalere == 42_000_000)
        #expect(april.receivedEstimateHalere == 0)
        #expect(april.netActualHalere == aprilEffects.reduce(0) { $0 + $1.netHalere })
        #expect(april.netEstimateHalere == 0)
        #expect(may.issuedEstimateHalere == 21_000_000)
    }

    /// An invoice of 2 500,00 Kč dated 30. 6. was paid on 10. 4., and today is 15. 4.: its money has come, and its date
    /// is in June, a later month than the one of today. The prediction does not list it, so June's hatched part holds
    /// it through its row, while June's actual parts are "—" as for any future month. Its payment is in April's actual
    /// received and net income, and in no estimate.
    @Test func anIssuedInvoiceDatedInALaterMonthAndPaidAlreadyIsInTheHatchedPartOfThatMonth() throws {
        let paidInAdvance = row(101, issued: "2026-06-30", net: 250_000, paidOn: "2026-04-10", paymentNet: 250_000)
        let payment = Receipt(
            day: civilDate("2026-04-10"), czkNetHalere: 250_000, czkVatHalere: 0, source: .invoice(101))
        let effect = ReceiptEffect(receipt: payment, tax: 0, social: 0, health: 10, total: 10)

        let chart = try monthsOfRows([paidInAdvance], effects: [effect], today: civilDate("2026-04-15"))
        let april = chart[3]
        let june = chart[5]

        #expect(june.part == .future)
        #expect(june.issuedEstimateHalere == 250_000)
        #expect(june.issuedEstimateText == "2\u{00A0}500\u{00A0}Kč")
        #expect(june.issuedActualHalere == 0)
        #expect(june.issuedActualText == "—")
        #expect(june.receivedActualText == "—")
        #expect(june.netActualText == "—")
        #expect(june.receivedEstimateHalere == 0)
        #expect(june.netEstimateHalere == 0)
        #expect(april.receivedActualHalere == 250_000)
        #expect(april.netActualHalere == 249_000)
        #expect(april.issuedActualHalere == 0)
        #expect(april.issuedEstimateHalere == 0)
        #expect(april.receivedEstimateHalere == 0)
        #expect(april.netEstimateHalere == 0)
    }

    /// The row of an invoice puts it in the hatched part only when it is dated after today and its money has come by
    /// today, both counted to the end of today. An invoice dated today itself is issued already, so it is in the actual
    /// part and not in the hatched one as well. One dated after today and paid on today itself is in the hatched part.
    /// One paid tomorrow and one not paid wait for their payments: the prediction lists them (here it lists nothing),
    /// so the rows leave them to it, and no invoice is counted twice.
    @Test func theRowOfAnInvoiceCountsItInTheHatchedPartOnlyWhenDatedAfterTodayAndPaidByToday() throws {
        let datedToday = row(101, issued: "2026-04-15", net: 70_000, paidOn: "2026-04-10", paymentNet: 70_000)
        let paidToday = row(102, issued: "2026-04-30", net: 250_000, paidOn: "2026-04-15", paymentNet: 250_000)
        let paidTomorrow = row(103, issued: "2026-05-31", net: 400_000, paidOn: "2026-04-16", paymentNet: 400_000)
        let unpaid = row(104, issued: "2026-06-15", net: 100_000)

        let chart = try monthsOfRows([datedToday, paidToday, paidTomorrow, unpaid], today: civilDate("2026-04-15"))

        #expect(chart[3].issuedActualHalere == 70_000)
        #expect(chart[3].issuedEstimateHalere == 250_000)
        #expect(chart[4].issuedEstimateHalere == 0)
        #expect(chart[5].issuedEstimateHalere == 0)
    }

    /// The rows hold the invoices issued in other years that were paid in the year too. One dated in June of the next
    /// year and paid on 10. 4. is not issued in a month of this year, so no month's hatched part holds it, but the
    /// money is received this April.
    @Test func anInvoiceDatedInTheNextYearIsNotInTheHatchedPartOfAMonthOfThisYear() throws {
        let nextYears = row(101, issued: "2027-06-10", net: 250_000, paidOn: "2026-04-10", paymentNet: 250_000)

        let chart = try monthsOfRows([nextYears], today: civilDate("2026-04-15"))

        #expect(chart.allSatisfy { $0.issuedEstimateHalere == 0 })
        #expect(chart.allSatisfy { $0.issuedActualHalere == 0 })
        #expect(chart[3].receivedActualHalere == 250_000)
    }

    /// An invoice in review is no income yet, so although it is dated after today and its money has come, it is neither
    /// in the hatched part of its month nor in the money received.
    @Test func anInvoiceInReviewDatedAfterTodayIsNotInTheHatchedPartAlthoughPaid() throws {
        let inReview = row(
            101, issued: "2026-06-30", net: 250_000, inReview: true, paidOn: "2026-04-10", paymentNet: 250_000)

        let chart = try monthsOfRows([inReview], today: civilDate("2026-04-15"))

        #expect(chart[5].issuedEstimateHalere == 0)
        #expect(chart[3].receivedActualHalere == 0)
    }

    /// An invoice issued on 5. 10. and not paid is an issued invoice by today, so its amount is in the actual part of
    /// October. The prediction expects its payment, but the invoice is not an invoice still to be issued, so it is not
    /// in the estimate as well; Tango's October already has an invoice, so the draft is all the estimate holds.
    @Test func anUnpaidInvoiceIssuedByTodayIsInTheActualPartAndNotInTheEstimate() throws {
        var input = PredictionSample.input(year: 2026)
        var unpaid = Invoice.fixture(
            number: "20261002", issued: "2026-10-05", duzp: "2026-10-05", dueDate: "2026-11-04", vatMode: .none)
        unpaid.id = 100
        unpaid.clientID = PredictionSample.tango.id
        unpaid.client = ClientSnapshot(client: PredictionSample.tango)
        input.invoices.append(unpaid)
        let outcome = try PredictionSample.outcome(of: input)
        let waiting = outcome.prediction.expectedInvoices.filter { $0.kind == .waiting }
        #expect(waiting.map(\.issueDate) == [civilDate("2026-10-05")])
        #expect(waiting.map(\.amountHalere) == [450_000])

        let rows = SampleYear2026.chartRows + [row(100, issued: "2026-10-05", net: 450_000)]

        let october = months(of: outcome, rows: rows)[9]

        #expect(october.issuedActualHalere == 450_000)
        #expect(october.issuedEstimateHalere == 25_669_280)
    }

    /// A draft and an invoice in review are not issued: neither is in the actual part of the month it is dated in, and
    /// the payment of the invoice in review is no money received.
    @Test func aDraftAndAnInvoiceInReviewAreNotCounted() throws {
        let draft = row(101, issued: "2026-10-10", net: 100_000, draft: true)
        let inReview = row(
            102, issued: "2026-10-12", net: 200_000, inReview: true, paidOn: "2026-10-14", paymentNet: 200_000)
        let outcome = try PredictionSample.outcome(year: 2026)

        let october = months(of: outcome, rows: SampleYear2026.chartRows + [draft, inReview])[9]

        #expect(october.issuedActualHalere == 0)
        #expect(october.receivedActualHalere == 31_022_675)
    }

    /// The money received in a month is counted whatever the year the invoice was issued in: an invoice of December
    /// 2025 paid on 5. 10. 2026 is received in October. It is not issued in 2026, so it adds nothing to the issued
    /// part. An invoice of January 2026 that was paid on 5. 10. 2025 is issued in the year, but its payment is not
    /// received in an October of this year.
    @Test func aPaymentOfAnInvoiceOfTheYearBeforeIsReceivedInItsMonth() throws {
        let lastYears = row(103, issued: "2025-12-20", net: 300_000, paidOn: "2026-10-05", paymentNet: 300_000)
        let paidInAdvance = row(104, issued: "2026-01-10", net: 100_000, paidOn: "2025-10-05", paymentNet: 100_000)
        let outcome = try PredictionSample.outcome(year: 2026)

        let chart = months(of: outcome, rows: SampleYear2026.chartRows + [lastYears, paidInAdvance])

        #expect(chart[9].receivedActualHalere == 31_322_675)
        #expect(chart[9].issuedActualHalere == 0)
        #expect(chart[0].issuedActualHalere == 22_000_000 + 100_000)
    }

    // MARK: Today cuts the chart

    /// The actual parts stop at today, whatever day "K datu" shows: the builder knows today alone. An invoice of
    /// 100,00 USD issued on 5. 10. and paid on 20. 10. is issued, but not paid yet, so it is worth what it was when it
    /// was issued (21,500 Kč a dollar), and not what was paid. An invoice issued and paid after today and the effect of
    /// its payment on the levies are not in October's actual parts at all.
    @Test func theChartIsCutAtTodayWhateverDayIsShown() throws {
        let paidLater = row(
            101, issued: "2026-10-05", net: 10_000, currency: .usd, paidOn: "2026-10-20", paymentNet: 210_000,
            issueDayRate: ExchangeRate(currency: .usd, amount: 1, rate: decimal("21.5")))
        let issuedLater = row(102, issued: "2026-10-19", net: 100_000, paidOn: "2026-10-20", paymentNet: 100_000)
        let paymentLater = Receipt(
            day: civilDate("2026-10-20"), czkNetHalere: 100_000, czkVatHalere: 0, source: .invoice(102))
        let effectLater = ReceiptEffect(receipt: paymentLater, tax: 0, social: 0, health: 10, total: 10)
        let outcome = try PredictionSample.outcome(year: 2026)

        let october = months(
            of: outcome, rows: SampleYear2026.chartRows + [paidLater, issuedLater],
            effects: sampleEffects + [effectLater])[9]

        #expect(october.issuedActualHalere == 215_000)
        #expect(october.receivedActualHalere == 31_022_675)
        #expect(october.netActualHalere == 21_981_075)
    }

    /// The cut falls at the end of today, so an invoice issued on 17. 10. itself is already issued. One of 4 500,00 Kč
    /// that is not paid is in October's issued part, and the prediction's own invoice for it, which is dated "now" too,
    /// is no invoice still to be issued, so it is not in the hatched part as well: that holds the draft alone.
    @Test func anInvoiceIssuedOnTodayItselfIsInTheActualPartAndNotInTheHatchedOne() throws {
        var input = PredictionSample.input(year: 2026)
        var unpaid = Invoice.fixture(
            number: "20261002", issued: "2026-10-17", duzp: "2026-10-17", dueDate: "2026-11-16", vatMode: .none)
        unpaid.id = 100
        unpaid.clientID = PredictionSample.tango.id
        unpaid.client = ClientSnapshot(client: PredictionSample.tango)
        input.invoices.append(unpaid)
        let outcome = try PredictionSample.outcome(of: input)
        let waiting = outcome.prediction.expectedInvoices.filter { $0.kind == .waiting }
        #expect(outcome.prediction.now == civilDate("2026-10-17"))
        #expect(waiting.map(\.issueDate) == [outcome.prediction.now])
        #expect(waiting.map(\.amountHalere) == [450_000])
        let rows = SampleYear2026.chartRows + [row(100, issued: "2026-10-17", net: 450_000)]

        let october = months(of: outcome, rows: rows)[9]

        #expect(october.issuedActualHalere == 450_000)
        #expect(october.issuedEstimateHalere == 25_669_280)
    }

    /// The cut falls at the end of today, so a payment dated 17. 10. itself is already received. One of 2 000,00 Kč is
    /// in October's received part, and what it leaves after its levies, 1 990,00 Kč, is in October's net income. It is
    /// no payment still to come, so neither estimate holds it: the sample expects no payment in October.
    @Test func aPaymentDatedOnTodayItselfIsInTheActualPartAndNotInTheEstimate() throws {
        let outcome = try PredictionSample.outcome(year: 2026)
        #expect(outcome.expectedPayments().allSatisfy { $0.day.month != 10 })
        let paidToday = row(101, issued: "2026-09-17", net: 200_000, paidOn: "2026-10-17", paymentNet: 200_000)
        let payment = Receipt(
            day: civilDate("2026-10-17"), czkNetHalere: 200_000, czkVatHalere: 0, source: .invoice(101))
        let effect = ReceiptEffect(receipt: payment, tax: 0, social: 0, health: 10, total: 10)

        let october = months(of: outcome, rows: [paidToday], effects: [effect])[9]

        #expect(october.receivedActualHalere == 200_000)
        #expect(october.receivedEstimateHalere == 0)
        #expect(october.netActualHalere == 199_000)
        #expect(october.netEstimateHalere == 0)
    }

    // MARK: Nothing in a month

    /// Where a part applies it shows zeros when there is nothing in it, and "—" only where it does not apply. With no
    /// invoice, no payment and nothing expected, January is past with zeros for its actual parts and "—" for its
    /// estimates, October is current with zeros everywhere, and December is future with "—" for its actual parts and
    /// zeros for its estimates.
    @Test func aMonthWithNothingInItShowsZerosWhereItsPartsApply() throws {
        var prediction = try PredictionSample.outcome(year: 2026).prediction
        prediction.expectedInvoices = []

        let months = PredictionChartBuilder.months(
            year: 2026, today: PredictionSample.sampleToday, rows: [], paymentEffects: [], prediction: prediction,
            expectedPayments: [])

        #expect(texts(of: months[0]) == [zero, "—", zero, "—", zero, "—"])
        #expect(texts(of: months[9]) == [zero, zero, zero, zero, zero, zero])
        #expect(texts(of: months[11]) == ["—", zero, "—", zero, "—", zero])
        #expect(months.flatMap { amounts(of: $0) }.allSatisfy { $0 == 0 })
        #expect(months[0].accessibilityLabel == "Leden 2026: vystaveno \(zero); přijato \(zero); čistý příjem \(zero)")
    }

    // MARK: The scale

    /// The scale of the chart holds the largest sum of a month: the 310 226,75 Kč that September issued, which October
    /// received too.
    @Test func theScaleHoldsTheLargestMonth() throws {
        let months = try sampleMonths()

        #expect(PredictionChartBuilder.largestAmount(in: months) == 42_000_000)
        #expect(PredictionChartBuilder.largestAmount(in: []) == 0)
    }

    /// The current month stands on the actual and the estimate together: 1 000,00 Kč issued by today and 2 000,00 Kč
    /// still to be issued make a bar of 3 000,00 Kč. A net income below zero is drawn at zero, so February's net of
    /// −4 900,00 Kč does not make the chart taller although its size is more than that of any amount in it.
    @Test func theScaleAddsTheActualAndTheEstimateAndLeavesOutANegativeNet() throws {
        var prediction = try PredictionSample.outcome(year: 2026).prediction
        prediction.expectedInvoices = [
            PredictedInvoice(
                kind: .expected, issueDate: civilDate("2026-10-30"), payDay: civilDate("2026-11-10"),
                amountHalere: 200_000, isCounted: true)
        ]
        let loss = ReceiptEffect(
            receipt: Receipt(day: civilDate("2026-02-10"), czkNetHalere: 10_000, czkVatHalere: 0, source: .invoice(1)),
            tax: 0, social: 5_000, health: 0, total: 5_000)

        let months = PredictionChartBuilder.months(
            year: 2026, today: PredictionSample.sampleToday, rows: [row(1, issued: "2026-10-05", net: 100_000)],
            paymentEffects: [loss], prediction: prediction, expectedPayments: [])

        #expect(months[1].netActualHalere == -490_000)
        #expect(PredictionChartBuilder.largestAmount(in: months) == 300_000)
    }
}
