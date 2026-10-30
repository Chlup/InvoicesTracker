import Foundation
import Testing
@testable import InvoicesTracker

/// The rules by which the prediction of a year's income puts its clients' invoices into months, money received, money
/// still to come this year and money of the next year: unpaid invoices of earlier years, overdue ones, payments dated
/// after today, drafts, the current month, the person's changes, unknown rates, the order of the clients and when a
/// client is active. The cases are made up for each rule, or the prediction sample changed in one thing.
struct IncomePredictionTests {
    // MARK: Helpers

    /// A client of the tests, in crowns and due in 14 days.
    private func client(_ id: Int64, _ name: String) -> Client {
        Client(id: id, name: name, currency: .czk, dueDays: 14)
    }

    /// An invoice of `client` for `amount` whole units of `currency` without VAT, issued on `issued` and paid in crowns
    /// on `paid` (`YYYY-MM-DD`), if given. Its number is "T" and its id.
    private func invoice(
        _ id: Int64, of client: Client, amount: Int64, issued: String, paid: String? = nil,
        currency: CurrencyCode = .czk, status: InvoiceStatus = .issued
    ) -> Invoice {
        var invoice = Invoice.fixture(
            number: "T\(id)", currency: currency, issued: issued, duzp: issued, dueDate: issued,
            items: [.fixture("1", at: amount * 100)], vatMode: .none, status: status,
            payment: paid.map { Payment.fixture(on: $0, net: amount * 100, vat: 0) })
        invoice.id = id
        invoice.clientID = client.id
        invoice.client = ClientSnapshot(client: client)
        return invoice
    }

    /// The input of 2026 as of `today`, 17. 10. 2026 unless given, with `clients`, `invoices` and their receipts, and
    /// the dollar at 21,320 Kč.
    private func input(
        clients: [Client], invoices: [Invoice], today: String = "2026-10-17", changes: [Int64: [Int: Bool]] = [:]
    ) -> PredictionInput {
        PredictionInput(
            year: 2026, today: civilDate(today), clients: clients, invoices: invoices, templates: [], changes: changes,
            receipts: PredictionSample.receipts(of: invoices, year: 2026), rates: PredictionSample.rates,
            usesUniformRate: false, rateDay: PredictionSample.rateDay)
    }

    /// A receipt the prediction makes up: `halere` paid on `day`.
    private func expected(_ halere: Int64, on day: String) -> Receipt {
        Receipt(day: civilDate(day), czkNetHalere: halere, czkVatHalere: 0, source: .synthetic)
    }

    private func row(_ id: Int64, in prediction: IncomePrediction) throws -> ClientPrediction {
        try #require(prediction.clients.first { $0.id == id }, "No client \(id)")
    }

    /// All five qualifying invoices train one CZK mean, even across currencies and a later issue date.
    @Test func annualMeansUseAllInvoicesAndKeepContactsSeparate() throws {
        let alfa = client(4, "Alfa")
        let bravo = client(5, "Bravo")
        var invoices = [
            invoice(1, of: alfa, amount: 100, issued: "2026-01-01", paid: "2026-01-02"),
            invoice(2, of: alfa, amount: 200, issued: "2026-02-01", paid: "2026-02-02"),
            invoice(3, of: alfa, amount: 300, issued: "2026-03-01", paid: "2026-03-02"),
            invoice(4, of: alfa, amount: 10, issued: "2026-08-31", paid: "2026-09-01", currency: .usd),
            invoice(5, of: alfa, amount: 20, issued: "2026-09-30", paid: "2026-10-01", currency: .eur),
            invoice(6, of: bravo, amount: 900, issued: "2027-01-01", paid: "2026-10-02"),
        ]
        // Bank and uniform stored conversions deliberately differ from the daily conversions of 200 and 600 Kč.
        invoices[3].payment?.conversion = .bankCZK
        invoices[3].payment?.czkNetHalere = 12_345
        invoices[4].payment?.conversion = .uniform
        invoices[4].payment?.czkNetHalere = 54_321
        var input = input(clients: [alfa, bravo], invoices: invoices, changes: [4: [11: true], 5: [11: true]])
        input.averageRates = [
            PredictionRateKey(currency: .usd, day: civilDate("2026-09-01")):
                storedRate("USD", "20", declaredOn: "2026-09-01"),
            PredictionRateKey(currency: .eur, day: civilDate("2026-10-01")):
                storedRate("EUR", "30", declaredOn: "2026-10-01"),
        ]
        let prediction = IncomePrediction.make(input)
        let a = try row(4, in: prediction)
        let b = try row(5, in: prediction)
        // (100 + 200 + 300 + 10 × 20 + 20 × 30) / 5 = 280 Kč.
        #expect(a.averageSampleCount == 5)
        #expect(a.nextAmountHalere == 28_000)
        #expect(a.months[10].amountHalere == 28_000)
        #expect(b.averageSampleCount == 1)
        #expect(b.nextAmountHalere == 90_000)
        #expect(b.months[10].amountHalere == 90_000)
        #expect(prediction.receivedHalere == 216_666)
        #expect(IncomePrediction.averageRateKeys(in: input) == Set(input.averageRates.keys))
    }

    /// History already paid in the preceding year supplies cadence but no selected-year amount or automatic month.
    @Test func emptyAnnualHistoryStopsAutomaticMonthsButKeepsDraftsAndManualChoices() throws {
        let alfa = client(4, "Alfa")
        let old = [
            invoice(1, of: alfa, amount: 10_000, issued: "2025-11-01", paid: "2025-11-02"),
            invoice(2, of: alfa, amount: 20_000, issued: "2025-12-01", paid: "2025-12-02"),
        ]
        let draft = invoice(3, of: alfa, amount: 700, issued: "2026-02-01", status: .draft)
        var input = input(clients: [alfa], invoices: old + [draft], today: "2026-01-01", changes: [4: [3: true]])
        let prediction = IncomePrediction.make(input)
        let a = try row(4, in: prediction)
        #expect(a.isRegular)
        #expect(a.averageSampleCount == 0)
        #expect(a.nextAmountHalere == nil)
        #expect(a.months.filter(\.isAutomatic).map(\.month) == [2])
        #expect(a.months[1].amountHalere == 70_000)
        #expect(a.months[2].hasUnknownAmount)
        #expect(!prediction.isComplete)
        input.changes = [:]
        #expect(IncomePrediction.make(input).isComplete)
    }

    /// A manual fallback converts the first positive template in the current client's currency, never old USD.
    @Test func manualTemplateFallbackUsesTheCurrentClientCurrency() throws {
        let alfa = client(4, "Alfa")
        var input = input(clients: [alfa], invoices: [
            invoice(1, of: alfa, amount: 10_000, issued: "2025-12-01", paid: "2025-12-02", currency: .usd)
        ], today: "2026-01-01")
        input.templates = [InvoiceTemplate(name: "Práce", clientID: 4, items: [
            TemplateItem(description: "Práce", quantity: 1, unit: "", unitPriceMinor: 500_000)
        ], vatMode: .none, dueDays: 14)]
        #expect(try row(4, in: IncomePrediction.make(input)).months.allSatisfy { !$0.isOn })
        input.changes = [4: [2: true]]
        let a = try row(4, in: IncomePrediction.make(input))
        #expect(a.nextAmountFromTemplate)
        #expect(a.nextAmountHalere == 500_000)
        #expect(a.months[1].amountHalere == 500_000)
    }

    /// Missing historical FX keeps a positive denominator and cadence, without falling back to a positive template.
    @Test func missingHistoricalFXDoesNotUseTheEmptyHistoryTemplateFallback() throws {
        let alfa = client(4, "Alfa")
        var input = input(clients: [alfa], invoices: [
            invoice(1, of: alfa, amount: 100, issued: "2026-08-31", paid: "2026-09-01", currency: .usd),
            invoice(2, of: alfa, amount: 200, issued: "2026-09-30", paid: "2026-10-01", currency: .usd),
        ])
        input.templates = [InvoiceTemplate(name: "Práce", clientID: 4, items: [
            TemplateItem(description: "Práce", quantity: 1, unit: "", unitPriceMinor: 500_000)
        ], vatMode: .none, dueDays: 14)]
        let prediction = IncomePrediction.make(input)
        let a = try row(4, in: prediction)
        #expect(a.averageSampleCount == 2)
        #expect(a.nextAmountHalere == nil)
        #expect(!a.nextAmountFromTemplate)
        #expect(a.months[9...].allSatisfy { $0.isAutomatic && $0.isOn && $0.hasUnknownAmount })
        #expect(!prediction.isComplete)
        #expect(prediction.syntheticReceipts.isEmpty)
        input.changes = [4: [10: false, 11: false, 12: false]]
        #expect(IncomePrediction.make(input).isComplete)
        input.changes = [4: [10: false, 11: false]]
        // The one-day delay leaves December in the same year here, so use a late December draft for next year.
        input.invoices.append(invoice(3, of: alfa, amount: 10, issued: "2026-12-31", currency: .eur, status: .draft))
        input.rates = [:]
        input.averageRates = [:]
        let nextYearOnly = IncomePrediction.make(input)
        #expect(nextYearOnly.isComplete)
        #expect(nextYearOnly.hasUnknownNextYearAmount)
        #expect(try row(4, in: nextYearOnly).hasUnknownNextYearAmount)
        #expect(try !row(4, in: nextYearOnly).hasUnknownCurrentYearAmount)
    }

    /// An actual zero invoice trains a known zero mean, distinct from missing history or a missing conversion.
    @Test func anAnnualZeroMeanRemainsKnown() throws {
        let alfa = client(4, "Alfa")
        let input = input(clients: [alfa], invoices: [
            invoice(1, of: alfa, amount: 0, issued: "2026-09-01", paid: "2026-09-02")
        ], changes: [4: [11: true]])
        let prediction = IncomePrediction.make(input)
        let a = try row(4, in: prediction)
        #expect(a.nextAmountHalere == 0)
        #expect(a.averageSampleCount == 1)
        #expect(!a.months[10].hasUnknownAmount)
        #expect(!a.hasUnknownCurrentYearAmount)
        #expect(prediction.isComplete)
        #expect(prediction.syntheticReceipts == [expected(0, on: "2026-11-02")])
    }

    /// The selected payment year admits an invoice whose issue date is beyond a closed year's cutoff.
    @Test func anActualPaymentTrainsItsClosedYearDespiteALaterIssueDate() throws {
        let alfa = client(4, "Alfa")
        var input = input(clients: [alfa], invoices: [
            invoice(1, of: alfa, amount: 100, issued: "2027-01-01", paid: "2025-12-01", currency: .usd)
        ])
        input.year = 2025
        let key = PredictionRateKey(currency: .usd, day: civilDate("2025-12-01"))
        input.averageRates = [key: storedRate("USD", "20", declaredOn: "2025-12-01")]
        let prediction = IncomePrediction.make(input)
        #expect(IncomePrediction.averageRateKeys(in: input) == [key])
        #expect(try row(4, in: prediction).nextAmountHalere == 200_000)
        #expect(try row(4, in: prediction).averageSampleCount == 1)
    }

    /// A mixed-currency draft month retains its known subtotal in tax input while the whole estimate is incomplete.
    @Test func anIncompleteDraftMonthRetainsItsKnownSubtotal() throws {
        let alfa = client(4, "Alfa")
        var input = input(clients: [alfa], invoices: [
            invoice(1, of: alfa, amount: 1_000, issued: "2026-11-01", status: .draft),
            invoice(2, of: alfa, amount: 100, issued: "2026-11-01", currency: .eur, status: .draft),
        ])
        input.rates = [:]
        let prediction = IncomePrediction.make(input)
        let client = try row(4, in: prediction)
        var yearInput = PredictionSample.yearInput(year: 2026)
        yearInput.receipts = []
        let outcome = try PredictionOutcome.make(prediction: prediction, yearInput: yearInput)
        #expect(client.months[10].amountHalere == 100_000)
        #expect(client.months[10].hasUnknownAmount)
        #expect(!prediction.isComplete)
        #expect(prediction.expectedInvoices.first?.hasUnknownAmount == true)
        #expect(prediction.syntheticReceipts == [expected(100_000, on: "2026-11-15")])
        #expect(outcome.result.incomeHalere == 100_000)
        #expect(prediction.incomeHalere == outcome.result.incomeHalere)
    }

    /// A legacy negative due delay may put a January draft's unknown payment outside the selected year.
    @Test func anUnknownContributionOutsideTheSelectedYearDoesNotInvalidateIt() {
        var alfa = client(4, "Alfa")
        alfa.dueDays = -5
        let input = input(clients: [alfa], invoices: [
            invoice(1, of: alfa, amount: 100, issued: "2026-01-01", currency: .eur, status: .draft)
        ], today: "2026-01-01")
        let prediction = IncomePrediction.make(input)
        #expect(prediction.expectedInvoices.first?.payDay == civilDate("2025-12-27"))
        #expect(prediction.isComplete)
        #expect(!prediction.hasUnknownNextYearAmount)
        #expect(prediction.clients.allSatisfy { !$0.hasUnknownNextYearAmount })
        #expect(prediction.clients.allSatisfy { !$0.hasUnknownCurrentYearAmount })
    }

    // MARK: Invoices not paid yet

    /// Two unpaid invoices of 10 000 Kč, five days apart (too close for a rhythm): one of 31. 12. 2024, two years
    /// before 2026, and one of 5. 1. 2025, the year before. Only last year's counts: its usual day is long over, so it
    /// is expected tomorrow, 18. 10. 2026. The older one is left out, and neither has a month in 2026.
    @Test func onlyLastYearsUnpaidInvoicesCount() throws {
        let delta = client(4, "Delta s.r.o.")
        let input = input(
            clients: [delta],
            invoices: [
                invoice(1, of: delta, amount: 10_000, issued: "2024-12-31"),
                invoice(2, of: delta, amount: 10_000, issued: "2025-01-05"),
            ])

        let prediction = IncomePrediction.make(input)
        let delta2026 = try row(4, in: prediction)

        #expect(delta2026.previousYearWaitingHalere == 1_000_000)
        #expect(delta2026.addsHalere == 1_000_000)
        #expect(delta2026.nextYearHalere == 0)
        #expect(delta2026.isActive)
        #expect(delta2026.months.allSatisfy { $0.kind == .past || $0.kind == .notExpected })
        #expect(prediction.waitingHalere == 1_000_000)
        #expect(prediction.waitingCount == 1)
        #expect(prediction.syntheticReceipts == [expected(1_000_000, on: "2026-10-18")])
    }

    /// An invoice of 1. 9. 2026, due in 14 days and still unpaid on 17. 10., is overdue: it is expected tomorrow,
    /// 18. 10. Another client's invoice of 10. 10. is expected on its usual day, 24. 10.
    @Test func anOverdueInvoiceIsPaidTomorrow() throws {
        let late = client(4, "Pozdní s.r.o.")
        let onTime = client(5, "Včasný s.r.o.")
        let input = input(
            clients: [late, onTime],
            invoices: [
                invoice(1, of: late, amount: 5_000, issued: "2026-09-01"),
                invoice(2, of: onTime, amount: 3_000, issued: "2026-10-10"),
            ])

        let prediction = IncomePrediction.make(input)
        let september = try row(4, in: prediction).months[8]

        #expect(september.kind == .waiting)
        #expect(september.amountHalere == 500_000)
        #expect(september.invoiceNumbers == ["T1"])
        #expect(try row(5, in: prediction).months[9].kind == .waiting)
        #expect(
            prediction.syntheticReceipts == [expected(500_000, on: "2026-10-18"), expected(300_000, on: "2026-10-24")])
        #expect(prediction.waitingHalere == 800_000)
        #expect(prediction.waitingCount == 2)
    }

    /// Tango's September invoice is paid on 20. 10. 2026, after today. The data has that payment, but on 17. 10. it is
    /// still to come: the month waits, the payment is expected on the client's usual day (30. 9. and 8 days, which is
    /// over, so tomorrow), and it is not among the money received. The income stays what it was.
    @Test func aPaymentDatedAfterTodayIsStillToCome() throws {
        var input = PredictionSample.input(year: 2026)
        let index = try #require(input.invoices.firstIndex { $0.number == "20260902" })
        input.invoices[index].payment?.date = civilDate("2026-10-20")
        input.receipts = PredictionSample.receipts(of: input.invoices, year: 2026)

        let prediction = IncomePrediction.make(input)
        let tango = try row(PredictionSample.tango.id, in: prediction)

        #expect(input.receipts.contains { $0.day == civilDate("2026-10-20") })
        #expect(prediction.receivedHalere == 218_727_135)
        #expect(prediction.receivedCount == 10)
        #expect(tango.receivedHalere == 450_000)
        #expect(tango.delayDays == 8)
        #expect(tango.months[8].kind == .waiting)
        #expect(tango.months[8].amountHalere == 450_000)
        #expect(prediction.waitingHalere == 450_000)
        #expect(prediction.syntheticReceipts.contains(expected(450_000, on: "2026-10-18")))
        #expect(prediction.incomeHalere == 274_315_699)
    }

    // MARK: Drafts and the current month

    /// Foxtrot's draft of 31. 10. 2026 is expected in October of 2026, the current year, with its own amount: 12 040,00
    /// USD at 21,320 Kč. Seen from 2027, 2026 is over and the draft counts nowhere: its month is past and nothing is
    /// expected.
    @Test func aDraftCountsOnlyInTheCurrentYear() throws {
        let current = IncomePrediction.make(PredictionSample.input(year: 2026))
        let over = IncomePrediction.make(PredictionSample.input(year: 2026, today: civilDate("2027-01-15")))
        let october = try row(PredictionSample.foxtrot.id, in: current).months[9]
        let octoberSeenFrom2027 = try row(PredictionSample.foxtrot.id, in: over).months[9]

        #expect(october.kind == .expected)
        #expect(october.isFromDraft)
        #expect(october.invoiceNumbers == ["20261001"])
        #expect(october.amountHalere == 25_669_280)
        #expect(over.isClosed)
        #expect(octoberSeenFrom2027.kind == .past)
        #expect(!octoberSeenFrom2027.isFromDraft)
        #expect(octoberSeenFrom2027.invoiceNumbers.isEmpty)
        #expect(over.expectedHalere == 0)
        #expect(over.syntheticReceipts.isEmpty)
    }

    /// On 31. 10. 2026, the last day of October, the month is still open: Foxtrot's October draft is expected, and so
    /// is Tango's October invoice, issued that day at the earliest (its usual day, the 30th, is over) and paid 8 days
    /// later. The income is the same as on 17. 10.
    @Test func theCurrentMonthStaysOpenOnItsLastDay() throws {
        let prediction = IncomePrediction.make(PredictionSample.input(year: 2026, today: civilDate("2026-10-31")))
        let foxtrot = try row(PredictionSample.foxtrot.id, in: prediction)
        let tango = try row(PredictionSample.tango.id, in: prediction)

        #expect(!prediction.isClosed)
        #expect(foxtrot.months[9].kind == .expected)
        #expect(foxtrot.months[9].isFromDraft)
        #expect(foxtrot.months[9].amountHalere == 25_669_280)
        #expect(tango.months[9].kind == .expected)
        #expect(tango.months[9].amountHalere == 450_000)
        #expect(prediction.syntheticReceipts.contains(expected(450_000, on: "2026-11-08")))
        #expect(prediction.incomeHalere == 274_315_699)
    }

    /// A year is closed, so that nothing is expected in it any more, when it is over, and the year of today on its
    /// 31 December. On 30 December the year of today is still open.
    @Test func aYearIsClosedWhenItIsOverOrOnItsLastDay() {
        #expect(PredictionInput.isClosed(year: 2025, today: civilDate("2026-10-17")))
        #expect(PredictionInput.isClosed(year: 2026, today: civilDate("2026-12-31")))
        #expect(!PredictionInput.isClosed(year: 2026, today: civilDate("2026-12-30")))
    }

    // MARK: The person's changes

    /// Foxtrot's September is switched off, but September has an invoice, paid: the month shows it, the change does not
    /// count, and the client counts as edited.
    @Test func aChangedMonthWithARealInvoiceShowsTheInvoice() throws {
        let prediction = IncomePrediction.make(PredictionSample.input(year: 2026, changes: [1: [9: false]]))
        let foxtrot = try row(PredictionSample.foxtrot.id, in: prediction)

        #expect(foxtrot.months[8].kind == .paid)
        #expect(foxtrot.months[8].amountHalere == 30_572_675)
        #expect(foxtrot.months[8].invoiceNumbers == ["20260901"])
        #expect(foxtrot.isEdited)
        #expect(prediction.incomeHalere == 274_315_699)
    }

    /// A new client in crowns whose only invoice is a draft of 1 000,00 USD for 20. 11. 2026. The app expects November
    /// from the draft, converted in the draft's own currency at 21,320 Kč: 21 320,00 Kč, paid 14 days later, 4. 12. The
    /// client has no rhythm yet, so no other month is expected.
    @Test func aClientWithOnlyADraftExpectsTheDraftsMonth() throws {
        let echo = client(4, "Echo s.r.o.")
        let draft = invoice(1, of: echo, amount: 1_000, issued: "2026-11-20", currency: .usd, status: .draft)

        let prediction = IncomePrediction.make(input(clients: [echo], invoices: [draft]))
        let echo2026 = try row(4, in: prediction)
        let november = echo2026.months[10]

        #expect(november.kind == .expected)
        #expect(november.isFromDraft)
        #expect(november.isAutomatic)
        #expect(november.isOn)
        #expect(november.invoiceNumbers == ["T1"])
        #expect(november.amountHalere == 2_132_000)
        #expect(echo2026.months.filter(\.isOn).map(\.month) == [11])
        #expect(echo2026.issuedCount == 0)
        #expect(echo2026.currency == .czk)
        #expect(echo2026.nextAmountHalere == nil)
        #expect(echo2026.isActive)
        #expect(prediction.syntheticReceipts == [expected(2_132_000, on: "2026-12-04")])
    }

    // MARK: Rates

    /// Without a rate for the dollar (none declared by today, and no uniform rate), Foxtrot's expected invoices have an
    /// unknown amount: its months are still expected, but they add nothing. Tango, in crowns, is not affected, and the
    /// levies are worked out all the same.
    @Test func anExpectedInvoiceWithoutARateHasAnUnknownAmount() throws {
        var input = PredictionSample.input(year: 2026)
        input.rates = [:]
        input.averageRates = [:]

        let prediction = IncomePrediction.make(input)
        let foxtrot = try row(PredictionSample.foxtrot.id, in: prediction)
        let outcome = try PredictionOutcome.make(
            prediction: prediction, yearInput: PredictionSample.yearInput(year: 2026))

        #expect(foxtrot.months[9...].map(\.kind) == [.expected, .expected, .expectedNextYear])
        #expect(foxtrot.months[9...].map(\.amountHalere) == [0, 0, 0])
        #expect(foxtrot.nextAmountHalere == nil)
        #expect(foxtrot.expectedHalere == 0)
        #expect(foxtrot.addsHalere == 0)
        #expect(foxtrot.isActive)
        #expect(prediction.expectedHalere == 900_000)
        #expect(prediction.incomeHalere == 220_077_135)
        #expect(outcome.result.incomeHalere == 220_077_135)
    }

    /// Unpaid invoices in euros, which the prediction has no rate for. Alfa's of 1. 10. 2026 keeps the ČNB rate of its
    /// DUZP, 24,300 Kč, and is converted at it: its 1 000,00 EUR are 24 300,00 Kč, paid tomorrow. Bravo's of 30. 9.
    /// and of 20. 12. keep none, so their amounts are unknown: they add nothing to the money that waits, nor to the
    /// money of the next year (the second is paid on 3. 1. 2027), and no payment of them is expected.
    @Test func anUnpaidInvoiceWithoutARateTakesItsOwnRateOrHasAnUnknownAmount() throws {
        let alfa = client(4, "Alfa s.r.o.")
        let bravo = client(5, "Bravo s.r.o.")
        var withItsRate = invoice(1, of: alfa, amount: 1_000, issued: "2026-10-01", currency: .eur)
        withItsRate.invoiceRate = storedRate("EUR", "24.3", declaredOn: "2026-10-01")
        let input = input(
            clients: [alfa, bravo],
            invoices: [
                withItsRate,
                invoice(2, of: bravo, amount: 2_000, issued: "2026-09-30", currency: .eur),
                invoice(3, of: bravo, amount: 3_000, issued: "2026-12-20", currency: .eur),
            ])

        let prediction = IncomePrediction.make(input)
        let alfa2026 = try row(4, in: prediction)
        let bravo2026 = try row(5, in: prediction)

        #expect(alfa2026.months[9].kind == .waiting)
        #expect(alfa2026.months[9].amountHalere == 2_430_000)
        #expect(!alfa2026.months[9].hasUnknownAmount)
        #expect(alfa2026.addsHalere == 2_430_000)
        #expect(bravo2026.months[8].kind == .waiting)
        #expect(bravo2026.months[8].amountHalere == 0)
        #expect(bravo2026.months[8].hasUnknownAmount)
        #expect(bravo2026.months[11].kind == .waitingNextYear)
        #expect(bravo2026.months[11].amountHalere == 0)
        #expect(bravo2026.months[11].hasUnknownAmount)
        #expect(bravo2026.addsHalere == 0)
        #expect(bravo2026.nextYearHalere == 0)
        #expect(prediction.waitingHalere == 2_430_000)
        #expect(prediction.waitingCount == 1)
        #expect(prediction.nextYearHalere == 0)
        #expect(prediction.syntheticReceipts == [expected(2_430_000, on: "2026-10-18")])
    }

    // MARK: The invoices expected

    /// The sample year as of 17. 10. 2026 expects six invoices, in the order they are paid and on one day in the order
    /// of the clients: Foxtrot's October draft, issued on its own day, 31. 10., and Tango's October invoice, issued on
    /// the client's usual day, the 30th, both paid on 7. 11.; then the two clients' November invoices and their
    /// December ones. The first four are paid by 31. 12. and count in the year, the two of December are paid in
    /// January. The counted ones are the receipts the engine is given.
    @Test func theExpectedInvoicesOfTheSampleYearAreTheDraftAndTheClientsMonths() {
        let prediction = IncomePrediction.make(PredictionSample.input(year: 2026))
        let invoices = prediction.expectedInvoices

        #expect(invoices.map(\.kind) == [.draft, .expected, .expected, .expected, .expected, .expected])
        #expect(invoices.map(\.issueDate.month) == [10, 10, 11, 11, 12, 12])
        #expect(invoices.first?.issueDate == civilDate("2026-10-31"))
        #expect(
            invoices.map(\.payDay)
                == ["2026-11-07", "2026-11-07", "2026-12-07", "2026-12-08", "2027-01-06", "2027-01-07"]
                .map(civilDate))
        #expect(invoices.map(\.amountHalere) == [25_669_280, 450_000, 28_569_284, 450_000, 28_569_284, 450_000])
        #expect(invoices.map(\.isCounted) == [true, true, true, true, false, false])
        #expect(
            invoices.filter(\.isCounted).map { expected($0.amountHalere, on: $0.payDay.iso) }
                == prediction.syntheticReceipts)
    }

    /// Foxtrot's October invoice is issued instead of being a draft, and is still dated 31. 10., after today. It is
    /// expected as an unpaid invoice with its own issue date, not the day it is expected to be paid, and with its
    /// amount, 12 040,00 USD at 21,320 Kč. It is paid 7 days after the issue, 7. 11.
    @Test func anIssuedInvoiceDatedAfterTodayIsExpectedAsWaitingWithItsOwnDay() throws {
        var input = PredictionSample.input(year: 2026)
        input.invoices[try #require(input.invoices.firstIndex { $0.number == "20261001" })].status = .issued

        let waiting = IncomePrediction.make(input).expectedInvoices.filter { $0.kind == .waiting }

        #expect(waiting.map(\.issueDate) == [civilDate("2026-10-31")])
        #expect(waiting.map(\.amountHalere) == [25_669_280])
        #expect(waiting.map(\.payDay) == [civilDate("2026-11-07")])
        #expect(waiting.map(\.isCounted) == [true])
    }

    /// Alfa's unpaid invoice of 20. 12. 2026 for 3 000 Kč, due in 14 days, is paid on 3. 1. 2027: it is listed as
    /// waiting, with its own issue date, and it is not counted in the year. Bravo's, of 1. 10. 2026, is in euros, which
    /// the prediction has no rate for, so it retains an unknown amount with metadata in the waiting list.
    @Test func anUnpaidInvoiceKeepsItsUnknownAmountMetadata() {
        let alfa = client(4, "Alfa s.r.o.")
        let bravo = client(5, "Bravo s.r.o.")
        let input = input(
            clients: [alfa, bravo],
            invoices: [
                invoice(1, of: alfa, amount: 3_000, issued: "2026-12-20"),
                invoice(2, of: bravo, amount: 2_000, issued: "2026-10-01", currency: .eur),
            ])

        let prediction = IncomePrediction.make(input)

        #expect(
            prediction.expectedInvoices == [
                PredictedInvoice(
                    kind: .waiting, issueDate: civilDate("2026-10-01"), payDay: civilDate("2026-10-18"),
                    amountHalere: 0, isCounted: true, hasUnknownAmount: true),
                PredictedInvoice(
                    kind: .waiting, issueDate: civilDate("2026-12-20"), payDay: civilDate("2027-01-03"),
                    amountHalere: 300_000, isCounted: false)
            ])
        #expect(prediction.syntheticReceipts.isEmpty)
        #expect(!prediction.isComplete)
    }

    /// Without a rate for the dollar, Foxtrot's three expected invoices have an unknown amount, 0. They are listed all
    /// the same, the draft's and the November one counted, but only the known Tango amounts become receipts.
    @Test func anExpectedInvoiceWithoutARateIsListedWithoutAnAmount() {
        var input = PredictionSample.input(year: 2026)
        input.rates = [:]
        input.averageRates = [:]

        let prediction = IncomePrediction.make(input)
        let invoices = prediction.expectedInvoices

        #expect(invoices.map(\.kind) == [.draft, .expected, .expected, .expected, .expected, .expected])
        #expect(invoices.map(\.amountHalere) == [0, 450_000, 0, 450_000, 0, 450_000])
        #expect(invoices.map(\.isCounted) == [true, true, true, true, false, false])
        #expect(
            prediction.syntheticReceipts == [
                expected(450_000, on: "2026-11-07"), expected(450_000, on: "2026-12-08"),
            ])
    }

    // MARK: The clients

    /// The clients sort by what they bring in the year, received and still to come: Bravo 3 000 Kč, Cetus and Echo
    /// 2 000 Kč each, in the order given, and Alfa 1 000 Kč. Delta brought the most, 9 000 Kč in March, but nothing is
    /// expected of it any more: it is not active, so it comes after the active clients.
    @Test func theClientsSortByWhatTheyBringDescending() {
        let alfa = client(1, "Alfa")
        let bravo = client(2, "Bravo")
        let cetus = client(3, "Cetus")
        let delta = client(4, "Delta")
        let echo = client(5, "Echo")
        let input = input(
            clients: [alfa, bravo, cetus, delta, echo],
            invoices: [
                invoice(1, of: alfa, amount: 1_000, issued: "2026-10-01"),
                invoice(2, of: bravo, amount: 3_000, issued: "2026-10-01"),
                invoice(3, of: cetus, amount: 2_000, issued: "2026-09-01", paid: "2026-09-10"),
                invoice(4, of: delta, amount: 9_000, issued: "2026-03-02", paid: "2026-03-10"),
                invoice(5, of: echo, amount: 2_000, issued: "2026-10-05"),
            ])

        let prediction = IncomePrediction.make(input)

        #expect(prediction.clients.map(\.name) == ["Bravo", "Cetus", "Echo", "Alfa", "Delta"])
        #expect(prediction.clients.map(\.isActive) == [true, true, true, true, false])
        #expect(
            prediction.clients.map { $0.addsHalere + $0.receivedHalere }
                == [300_000, 200_000, 200_000, 100_000, 900_000])
    }

    /// Sierra is no longer invoiced, so it is not active. Switching its November on expects an invoice like its last
    /// ones, 208 000 Kč, on 29. 11. and paid 5 days later: Sierra becomes active and, bringing more than Tango, comes
    /// second.
    @Test func anInactiveClientBecomesActiveWhenAMonthIsSwitchedOn() throws {
        let before = IncomePrediction.make(PredictionSample.input(year: 2026))
        let after = IncomePrediction.make(PredictionSample.input(year: 2026, changes: [3: [11: true]]))
        let sierra = try row(PredictionSample.sierra.id, in: after)

        #expect(try !row(PredictionSample.sierra.id, in: before).isActive)
        #expect(sierra.isActive)
        #expect(sierra.isEdited)
        #expect(sierra.months[10].kind == .expected)
        #expect(sierra.months[10].isOn)
        #expect(!sierra.months[10].isAutomatic)
        #expect(sierra.months[10].amountHalere == 20_800_000)
        #expect(after.syntheticReceipts.contains(expected(20_800_000, on: "2026-12-04")))
        #expect(after.clients.map(\.name) == ["Foxtrot, Inc.", "Sierra, SE", "Tango s.r.o."])
    }

    /// Monthly invoices of 10 000 Kč of no client the app knows, of 31. 8. and 30. 9. 2026, and a draft of 20. 11.: the
    /// group "Neznámý odběratel" has a rhythm, but the app expects none of its months, neither from the rhythm nor
    /// from the draft. A choice cannot be stored for the group, so nothing could take such a month back. Its invoices
    /// still count: August is paid, and September waits for its payment, tomorrow.
    @Test func theInvoicesOfNoKnownClientExpectNoMonth() throws {
        let gone = client(9, "Zrušený s.r.o.")
        var invoices = [
            invoice(1, of: gone, amount: 10_000, issued: "2026-08-31", paid: "2026-09-10"),
            invoice(2, of: gone, amount: 10_000, issued: "2026-09-30"),
            invoice(3, of: gone, amount: 10_000, issued: "2026-11-20", status: .draft),
        ]
        for index in invoices.indices {
            invoices[index].clientID = nil
        }

        let prediction = IncomePrediction.make(input(clients: [], invoices: invoices))
        let unknown = try row(ClientPrediction.unknownID, in: prediction)

        #expect(unknown.name == "Neznámý odběratel")
        #expect(unknown.isRegular)
        #expect(unknown.months[7].kind == .paid)
        #expect(unknown.months[8].kind == .waiting)
        #expect(unknown.months[9...].map(\.kind) == [.notExpected, .notExpected, .notExpected])
        #expect(!unknown.months.contains { $0.isOn || $0.isAutomatic })
        #expect(unknown.months[10].invoiceNumbers == ["T3"])
        #expect(prediction.expectedHalere == 0)
        #expect(prediction.expectedCount == 0)
        #expect(prediction.waitingHalere == 1_000_000)
        #expect(prediction.syntheticReceipts == [expected(1_000_000, on: "2026-10-18")])
    }

    /// A prior-year unpaid invoice retains current-year unknown metadata even without an issued month in this year.
    @Test func anUnknownPriorYearWaitingAmountMarksTheClientIncomplete() throws {
        let alfa = client(4, "Alfa")
        var input = input(clients: [alfa], invoices: [
            invoice(1, of: alfa, amount: 100, issued: "2025-12-15", currency: .eur),
            invoice(2, of: alfa, amount: 1_000, issued: "2025-12-16"),
        ])
        input.rates = [:]
        input.averageRates = [
            PredictionRateKey(currency: .eur, day: civilDate("2025-12-15")):
                storedRate("EUR", "20", declaredOn: "2025-12-15")
        ]
        let prediction = IncomePrediction.make(input)
        let client = try row(4, in: prediction)
        #expect(client.nextAmountHalere == 150_000)
        #expect(client.hasUnknownCurrentYearAmount)
        #expect(!client.hasUnknownNextYearAmount)
        #expect(client.addsHalere == 100_000)
        #expect(client.months.allSatisfy { !$0.hasUnknownAmount })
        #expect(!prediction.isComplete)
    }
}
