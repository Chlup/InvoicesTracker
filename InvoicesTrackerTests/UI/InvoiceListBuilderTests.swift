import Foundation
import Testing
@testable import InvoicesTracker

/// What Faktury shows for a year, a scope, a status filter and a search. In every expected string `\u{00A0}` is the
/// no-break space.
struct InvoiceListBuilderTests {
    // MARK: Helpers

    private func usd(_ rate: String) -> ExchangeRate {
        ExchangeRate(currency: .usd, amount: 1, rate: decimal(rate))
    }

    /// A crown invoice of 7,5 hours at 600,00 Kč and 21 % VAT: 4 500,00 Kč and 5 445,00 Kč with VAT, for Cetus Data.
    private func crownInvoice(
        id: Int64, number: String = "20260902", issued: String = "2026-09-30", dueDate: String = "2026-10-14",
        status: InvoiceStatus = .issued, review: ReviewFlag? = nil, payment: Payment? = nil
    ) -> Invoice {
        var invoice = Invoice.fixture(
            number: number, issued: issued, duzp: issued, dueDate: dueDate, status: status, review: review,
            payment: payment)
        invoice.id = id
        invoice.client = SampleYear2026.cetus
        return invoice
    }

    /// A dollar invoice outside the VAT scope: `hours` at 70,00 USD (205 hours are 14 350,00 USD).
    private func dollarInvoice(
        id: Int64, number: String = "20260901", issued: String = "2026-09-30", duzp: String? = nil,
        dueDate: String = "2026-10-30", hours: String = "205", invoiceRate: StoredRate? = nil,
        status: InvoiceStatus = .issued, review: ReviewFlag? = nil, payment: Payment? = nil
    ) -> Invoice {
        var invoice = Invoice.fixture(
            number: number, currency: .usd, issued: issued, duzp: duzp ?? issued, dueDate: dueDate,
            items: [
                InvoiceItem(
                    description: "Software development", quantity: decimal(hours), unit: "h", unitPriceMinor: 7_000)
            ],
            vatMode: .outsideCountry, invoiceRate: invoiceRate, status: status, review: review, payment: payment)
        invoice.id = id
        invoice.client = SampleYear2026.bravo
        return invoice
    }

    /// 14 350,00 USD received on 2. 10. at 21,305: 305 726,75 Kč.
    private func paidAtTheRateOfTheDay(on day: String = "2026-10-02", net: Int64 = 30_572_675) -> Payment {
        .fixture(
            on: day, conversion: .cnbDaily, net: net, vat: 0, rate: storedRate("USD", "21.305", declaredOn: day))
    }

    private func uniformRate(
        _ code: String = "USD", _ rate: String = "21.84", year: Int = 2025, amount: Int = 1,
        instruction: String = "GFŘ-D-75", origin: UniformRateOrigin = .builtIn
    ) -> UniformRate {
        UniformRate(
            year: year, currency: CurrencyCode(code)!, amount: amount, rate: decimal(rate), instruction: instruction,
            sourceURL: nil, confirmedAt: nil, origin: origin
        )
    }

    /// The list as of `asOf` ("K datu", which the money follows) with the status as of `statusDay` (today, which the
    /// status follows). Unless a test says otherwise today is 17. 10. 2026 whatever day is shown.
    private func input(
        year: Int = 2026, asOf: String = "2026-10-17", statusDay: String = "2026-10-17",
        scope: InvoiceScope = .issued, filter: InvoiceStatusFilter = .all, invoices: [Invoice],
        searchText: String = "", matchingIDs: Set<Int64>? = nil, otherYearCounts: [Int: Int] = [:],
        paymentDayRates: [Int64: ExchangeRate] = [:], issueDayRates: [Int64: ExchangeRate] = [:],
        uniformRates: [UniformRate] = [], netIncomes: [Int64: InvoiceNetIncome] = [:]
    ) -> InvoiceListInput {
        InvoiceListInput(
            year: year, asOf: civilDate(asOf), statusDay: civilDate(statusDay), scope: scope, filter: filter,
            invoices: invoices, searchText: searchText, matchingIDs: matchingIDs, otherYearCounts: otherYearCounts,
            paymentDayRates: paymentDayRates, issueDayRates: issueDayRates,
            uniformRates: Dictionary(uniqueKeysWithValues: uniformRates.map { ($0.currency, $0) }),
            netIncomes: netIncomes
        )
    }

    private func build(_ input: InvoiceListInput) -> InvoiceListData {
        InvoiceListBuilder.build(input)
    }

    /// The figure at the uniform rate of 2025 on 1. 4. 2026, when the app no longer looks for the rates of 2025, for
    /// one unpaid invoice in each of `currencies`, issued on 30. 9. 2025, in a year that has no uniform rate at all.
    private func uniformOf2025AfterTheSearch(for currencies: [CurrencyCode]) -> UniformSummary {
        let invoices = currencies.enumerated().map { index, currency in
            var invoice = dollarInvoice(
                id: Int64(index + 1), number: "2025090\(index + 1)", issued: "2025-09-30", dueDate: "2025-10-30",
                hours: "10")
            invoice.currency = currency
            return invoice
        }
        return build(input(year: 2025, asOf: "2025-12-31", statusDay: "2026-04-01", invoices: invoices)).uniform
    }

    /// A crown invoice, a paid dollar invoice and an unpaid one: the sample of the summary row.
    private var threeInvoices: [Invoice] {
        [
            crownInvoice(id: 1, number: "20260902"),
            dollarInvoice(id: 2, number: "20260901", payment: paidAtTheRateOfTheDay()),
            dollarInvoice(id: 3, number: "20261001", hours: "172"),
        ]
    }

    private let notPublished2026 =
        "Jednotný kurz USD za rok 2026 ještě není vyhlášený – GFŘ ho zveřejní v lednu 2027."

    /// The figure at the uniform rate of the prototype while the rate of the year is not out: a muted word, with the
    /// text that says why in its tooltip.
    private func notAnnounced(_ help: String) -> UniformSummary {
        .missing(text: "zatím nevyhlášen", help: help)
    }

    /// The figure at the uniform rate once the app no longer looks for a rate it lacks: a muted word, with the text
    /// that says where to enter the rate in its tooltip.
    private func notInTheApp(_ help: String) -> UniformSummary {
        .missing(text: "v aplikaci není", help: help)
    }

    // MARK: The total in crowns

    @Test func theTotalCountsCrownsAtTheirNetPaidInvoicesAtTheRateOfTheDayAndUnpaidOnesAtTheRateOfTheIssueDay() {
        let data = build(
            input(
                invoices: threeInvoices, paymentDayRates: [2: usd("21.305")], issueDayRates: [3: usd("21.622")]))

        // 4 500,00 + 305 726,75 + 260 328,88
        #expect(data.czkTotalHalere == 57_055_563)
        // In whole Kč, as every summary is: 570 555,63 Kč.
        #expect(data.totalText == "570\u{00A0}556\u{00A0}Kč")
    }

    @Test func theTotalIsRoundedOnceFromTheSumInHalere() {
        // Two invoices of 0,50 Kč: 1 Kč together, where each rounded on its own would make 2 Kč.
        let half = [InvoiceItem(description: "Drobnost", quantity: decimal("1"), unit: "ks", unitPriceMinor: 50)]
        var first = crownInvoice(id: 1, number: "20260901")
        first.items = half
        var second = crownInvoice(id: 2, number: "20260902")
        second.items = half

        let data = build(input(invoices: [first, second]))

        #expect(data.czkTotalHalere == 100)
        #expect(data.totalText == "1\u{00A0}Kč")
    }

    @Test func aPaidInvoiceIsCountedAtTheRateOfTheDayEvenWhenTheYearConvertsByTheUniformRate() {
        // Paid on 8. 10. 2025 and converted at the uniform rate 21,84 by the year's method: 3 640,00 USD.
        let paidAtTheUniformRate = Payment.fixture(
            on: "2025-10-08", conversion: .uniform, net: 7_949_760, vat: 0,
            rate: storedRate("USD", "21.84", declaredOn: "2025-12-31"))
        let invoice = dollarInvoice(
            id: 1, number: "20250901", issued: "2025-09-30", dueDate: "2025-10-30", hours: "52",
            payment: paidAtTheUniformRate)

        let data = build(
            input(
                year: 2025, asOf: "2025-12-31", invoices: [invoice], paymentDayRates: [1: usd("21.305")],
                uniformRates: [uniformRate()]))

        // 3 640,00 USD at 21,305 is 77 550,20 Kč; at 21,84 it is 79 497,60 Kč.
        #expect(data.czkTotalHalere == 7_755_020)
        #expect(data.totalText == "77\u{00A0}550\u{00A0}Kč")
        #expect(data.uniformTotalHalere == 7_949_760)
        #expect(data.uniformLabel == "Jednotným kurzem 2025")
        #expect(
            data.uniform
                == .value(
                    text: "79\u{00A0}498\u{00A0}Kč",
                    help: "Jednotný kurz 2025: 1\u{00A0}USD = 21,84\u{00A0}Kč · pokyn GFŘ-D-75"))
    }

    @Test func anAmountFromTheBankCountsAsEnteredInBothTotals() {
        let fromTheBank = Payment.fixture(
            on: "2026-10-02", conversion: .bankCZK, net: 30_600_000, vat: 0, bankCZKTotalHalere: 30_600_000)
        let invoice = dollarInvoice(id: 1, payment: fromTheBank)

        let data = build(
            input(
                invoices: [invoice], paymentDayRates: [1: usd("21.305")],
                uniformRates: [uniformRate(year: 2026, instruction: "", origin: .manual)]))

        // Not 14 350,00 USD at 21,305 (305 726,75 Kč) and not at the uniform rate.
        #expect(data.czkTotalHalere == 30_600_000)
        #expect(data.uniformTotalHalere == 30_600_000)
        #expect(data.totalText == "306\u{00A0}000\u{00A0}Kč")
        #expect(
            data.uniform
                == .value(
                    text: "306\u{00A0}000\u{00A0}Kč",
                    help: "Jednotný kurz 2026: 1\u{00A0}USD = 21,84\u{00A0}Kč · zadáno ručně"))
    }

    @Test func anAmountFromTheBankNeedsNoUniformRate() {
        let fromTheBank = Payment.fixture(
            on: "2026-10-02", conversion: .bankCZK, net: 30_600_000, vat: 0, bankCZKTotalHalere: 30_600_000)

        let data = build(input(invoices: [dollarInvoice(id: 1, payment: fromTheBank)]))

        #expect(data.uniformTotalHalere == 30_600_000)
        // The app's own text: a rate of 0,00 Kč would say nothing true.
        #expect(
            data.uniform
                == .value(
                    text: "306\u{00A0}000\u{00A0}Kč", help: "Částky v Kč podle banky – jednotný kurz se nepoužije"))
    }

    @Test func anUnpaidInvoiceUsesTheRateOfItsIssueDayNotOfItsTaxableSupply() {
        // Issued on 16. 10. with the supply on 31. 10.: the rate fixed on the invoice is not the one of the issue day.
        let invoice = dollarInvoice(
            id: 1, number: "20261001", issued: "2026-10-16", duzp: "2026-10-31", dueDate: "2026-11-15",
            hours: "172", invoiceRate: storedRate("USD", "21.800", declaredOn: "2026-10-16"))

        let data = build(input(invoices: [invoice], issueDayRates: [1: usd("21.622")]))

        // 12 040,00 USD at 21,622
        #expect(data.czkTotalHalere == 26_032_888)
        #expect(data.rows[0].czk == "≈ 260\u{00A0}328,88\u{00A0}Kč")
        #expect(data.rows[0].czkHelp == "Odhad kurzem ČNB ke dni vystavení: 21,622\u{00A0}Kč/USD")
    }

    @Test func aPaymentAfterTheChosenDayIsNotReceivedYetSoTheInvoiceIsAnEstimateEvenWhenItIsPaidByToday() {
        // The money arrives on 20. 10., three days after the day shown, and today is the 20th.
        let invoice = dollarInvoice(id: 1, payment: paidAtTheRateOfTheDay(on: "2026-10-20"))

        let data = build(
            input(
                statusDay: "2026-10-20", invoices: [invoice], paymentDayRates: [1: usd("21.305")],
                issueDayRates: [1: usd("21.359")]))

        // 14 350,00 USD at the rate of the issue day, 21,359
        #expect(data.czkTotalHalere == 30_650_165)
        #expect(data.rows[0].czk == "≈ 306\u{00A0}501,65\u{00A0}Kč")
        #expect(data.rows[0].czkKind == .estimate)
        #expect(data.rows[0].czkHelp == "Odhad kurzem ČNB ke dni vystavení: 21,359\u{00A0}Kč/USD")
        // The status is as of today, so the invoice is paid. The money is as of the day shown, so it has not been
        // received and the column in crowns does not look paid.
        #expect(data.rows[0].status == .paid(civilDate("2026-10-20")))
        #expect(data.rows[0].hasReceivedPayment == false)
    }

    @Test func aPaymentUpToTheChosenDayIsReceivedSoTheColumnInCrownsLooksPaid() {
        let invoice = dollarInvoice(id: 1, payment: paidAtTheRateOfTheDay(on: "2026-10-02"))

        let data = build(input(invoices: [invoice], paymentDayRates: [1: usd("21.305")]))

        #expect(data.rows[0].czk == "305\u{00A0}726,75\u{00A0}Kč")
        #expect(data.rows[0].czkKind == .actual)
        #expect(data.rows[0].status == .paid(civilDate("2026-10-02")))
        #expect(data.rows[0].hasReceivedPayment)
    }

    @Test func anInvoiceThatIsNotPaidHasNoReceivedPayment() {
        let data = build(input(invoices: [dollarInvoice(id: 1, hours: "172")], issueDayRates: [1: usd("21.622")]))

        #expect(data.rows[0].czk == "≈ 260\u{00A0}328,88\u{00A0}Kč")
        #expect(data.rows[0].hasReceivedPayment == false)
    }

    @Test func aPaidInvoiceWhoseRateOfTheDayIsMissingIsCountedAsStored() {
        let data = build(input(invoices: [dollarInvoice(id: 1, payment: paidAtTheRateOfTheDay())]))

        #expect(data.czkTotalHalere == 30_572_675)
    }

    @Test func anUnpaidForeignInvoiceWithoutAnyRateIsWorthNothingYet() throws {
        let data = build(input(invoices: [crownInvoice(id: 1), dollarInvoice(id: 2, hours: "172")]))

        #expect(data.czkTotalHalere == 450_000)
        let row = try #require(data.rows.first { $0.id == 2 })
        // A dash in the faintest grey, with nothing to say about a rate that is not known.
        #expect(row.czk == "—")
        #expect(row.czkKind == .unknown)
        #expect(row.czkHelp == nil)
    }

    @Test func anInvoiceInReviewIsLeftOutOfTheTotalInCrownsButStaysInTheCategory() {
        // An invoice in review is not counted until it is resolved: neither a crown invoice nor a paid dollar invoice
        // adds to the total.
        let invoices = [
            crownInvoice(id: 1, number: "20260901"),
            crownInvoice(id: 2, number: "20260902", review: ReviewFlag(reason: "záporná částka")),
            dollarInvoice(
                id: 3, number: "20260903", review: ReviewFlag(reason: "bez data platby"),
                payment: paidAtTheRateOfTheDay()),
        ]

        let data = build(input(invoices: invoices, paymentDayRates: [3: usd("21.305")]))

        #expect(data.czkTotalHalere == 450_000)
        #expect(data.totalText == "4\u{00A0}500\u{00A0}Kč")
        // The only invoice that is counted is in crowns, so there is no total at the uniform rate, and the row says
        // why the invoices in another currency are not in it.
        #expect(data.uniform == .hidden)
        #expect(data.reviewHint == " · mimo součet: 2\u{00A0}faktury ke kontrole")
        // They stay in the category: in the rows, in the count and in the chips.
        #expect(data.rows.map(\.id) == [3, 2, 1])
        #expect(data.countText == "3\u{00A0}faktury")
        #expect(data.chipCounts[.all] == 3)
        #expect(data.chipCounts[.review] == 2)
    }

    @Test func theCategoryOfInvoicesToCheckHasNothingToTotal() {
        let invoices = [
            crownInvoice(id: 1, number: "20260901"),
            crownInvoice(id: 2, number: "20260902", review: ReviewFlag(reason: "záporná částka")),
        ]

        let data = build(input(filter: .review, invoices: invoices))

        #expect(data.rows.map(\.id) == [2])
        #expect(data.countText == "1\u{00A0}faktura")
        #expect(data.czkTotalHalere == 0)
        #expect(data.totalText == "0\u{00A0}Kč")
        #expect(data.uniformTotalHalere == 0)
        #expect(data.uniform == .hidden)
        // No invoice in a foreign currency is left out, so there is nothing to explain.
        #expect(data.reviewHint == nil)
    }

    // MARK: The total at the uniform rate

    @Test func whileTheUniformRateOfTheYearIsNotPublishedTheSummarySaysSo() {
        let data = build(
            input(invoices: threeInvoices, paymentDayRates: [2: usd("21.305")], issueDayRates: [3: usd("21.622")]))

        #expect(data.uniformLabel == "Jednotným kurzem 2026")
        #expect(data.uniform == notAnnounced(notPublished2026))
        #expect(data.uniformTotalHalere == nil)
    }

    @Test func everyCurrencyWithoutARateIsNamedInTheOrderOfTheCodes() {
        var euro = dollarInvoice(id: 2, number: "20260903", hours: "10")
        euro.currency = .eur

        let data = build(input(invoices: [dollarInvoice(id: 1), euro]))

        #expect(
            data.uniform
                == notAnnounced(
                    "Jednotný kurz EUR, USD za rok 2026 ještě není vyhlášený – GFŘ ho zveřejní v lednu 2027."))
    }

    @Test func anInvoiceInReviewIsLeftOutOfTheUniformTotalAndNeverMakesItUnpublished() {
        // The euro invoice in review has no rate, which would make the tile "not published" if it counted.
        var euro = dollarInvoice(id: 4, number: "20260904", hours: "10", review: ReviewFlag(reason: "měna bez kurzu"))
        euro.currency = .eur
        let invoices = [
            crownInvoice(id: 1, number: "20260901"),
            dollarInvoice(id: 2, number: "20260902", payment: paidAtTheRateOfTheDay()),
            dollarInvoice(
                id: 3, number: "20260903", review: ReviewFlag(reason: "bez data platby"),
                payment: paidAtTheRateOfTheDay()),
            euro,
        ]

        let data = build(
            input(
                invoices: invoices, paymentDayRates: [2: usd("21.305"), 3: usd("21.305")],
                uniformRates: [uniformRate(year: 2026)]))

        // 4 500,00 Kč and 14 350,00 USD at 21,84 (313 404,00 Kč): the dollar invoice in review does not add to them.
        let expected: Int64 = 450_000 + 31_340_400
        #expect(data.uniformTotalHalere == expected)
        #expect(
            data.uniform
                == .value(
                    text: "317\u{00A0}904\u{00A0}Kč",
                    help: "Jednotný kurz 2026: 1\u{00A0}USD = 21,84\u{00A0}Kč · pokyn GFŘ-D-75"))
        // The count still has all four invoices.
        #expect(data.countText == "4\u{00A0}faktury")
        // A foreign invoice is counted, so the total at the uniform rate is there and needs no hint.
        #expect(data.reviewHint == nil)
    }

    @Test func aRateOfAnotherYearIsNoRateForThisOne() {
        let data = build(input(invoices: [dollarInvoice(id: 1)], uniformRates: [uniformRate(year: 2025)]))

        #expect(data.uniform == notAnnounced(notPublished2026))
        #expect(data.uniformTotalHalere == nil)
    }

    /// What the summary says of a rate that is missing follows the search of the app for it on the day: not out yet,
    /// with the January in which the GFŘ publishes it, until the search starts on 2 January; not out yet, with the app
    /// looking for it, until 31 March; and from 1 April that the app does not have it, which the words of the
    /// prototype, "zatím nevyhlášen", would no longer say truly.
    @Test func aMissingRateFollowsTheSearchOfTheAppForIt() {
        func uniform(on day: String) -> UniformSummary {
            build(
                input(
                    year: 2025, asOf: "2025-12-31", statusDay: day,
                    invoices: [dollarInvoice(id: 1, issued: "2025-09-30", dueDate: "2025-10-30")])
            ).uniform
        }
        let waiting = "Jednotný kurz USD za rok 2025 ještě není vyhlášený – GFŘ ho zveřejní v lednu 2026."
        let looking = "Jednotný kurz USD za rok 2025 ještě není vyhlášený – aplikace ho jednou denně hledá."

        #expect(uniform(on: "2025-12-31") == notAnnounced(waiting))
        #expect(uniform(on: "2026-01-01") == notAnnounced(waiting))
        #expect(uniform(on: "2026-01-02") == notAnnounced(looking))
        #expect(uniform(on: "2026-03-31") == notAnnounced(looking))
        #expect(
            uniform(on: "2026-04-01")
                == notInTheApp("Jednotný kurz USD za rok 2025 v aplikaci není – zadáte ho v Nastavení › Rok 2025."))
    }

    /// Nastavení › Rok takes the rates of dollars and euros only, so once the app no longer looks for a rate of any
    /// other currency, the summary does not send the person there to type it.
    @Test func afterTheSearchAMissingRateOfAnotherCurrencyCannotBeTyped() throws {
        let pounds = try #require(CurrencyCode("GBP"))

        #expect(
            uniformOf2025AfterTheSearch(for: [pounds])
                == notInTheApp("Jednotný kurz GBP za rok 2025 v aplikaci není – ručně ho zadat nelze."))
    }

    /// The summary names every currency without a rate in the order of their codes, and then says which of them are
    /// typed in Nastavení › Rok and which cannot be, each group in the order of its codes.
    @Test func afterTheSearchTheSummarySaysWhichMissingRatesCanBeTypedAndWhichCannot() throws {
        let pounds = try #require(CurrencyCode("GBP"))
        let canadianDollars = try #require(CurrencyCode("CAD"))

        #expect(
            uniformOf2025AfterTheSearch(for: [pounds, .eur])
                == notInTheApp(
                    "Jednotný kurz EUR, GBP za rok 2025 v aplikaci není –"
                        + " kurz EUR zadáte v Nastavení › Rok 2025, kurz GBP ručně zadat nelze."))
        #expect(
            uniformOf2025AfterTheSearch(for: [pounds, .eur, .usd])
                == notInTheApp(
                    "Jednotný kurz EUR, GBP, USD za rok 2025 v aplikaci není –"
                        + " kurz EUR, USD zadáte v Nastavení › Rok 2025, kurz GBP ručně zadat nelze."))
        #expect(
            uniformOf2025AfterTheSearch(for: [pounds, canadianDollars, .eur])
                == notInTheApp(
                    "Jednotný kurz CAD, EUR, GBP za rok 2025 v aplikaci není –"
                        + " kurz EUR zadáte v Nastavení › Rok 2025, kurz CAD, GBP ručně zadat nelze."))
        #expect(
            uniformOf2025AfterTheSearch(for: [.eur])
                == notInTheApp("Jednotný kurz EUR za rok 2025 v aplikaci není – zadáte ho v Nastavení › Rok 2025."))
    }

    @Test func aCurrencyWithARateIsNotNamedAsMissing() {
        var euro = dollarInvoice(id: 2, number: "20260903", hours: "10")
        euro.currency = .eur

        let data = build(input(invoices: [dollarInvoice(id: 1), euro], uniformRates: [uniformRate(year: 2026)]))

        #expect(
            data.uniform
                == notAnnounced("Jednotný kurz EUR za rok 2026 ještě není vyhlášený – GFŘ ho zveřejní v lednu 2027."))
    }

    @Test func theUniformTotalConvertsEveryInvoiceOfTheCategoryAtTheRateOfTheYear() {
        let eurRate = uniformRate("EUR", "24.66", year: 2026)
        var euro = dollarInvoice(id: 4, number: "20260904", hours: "10")
        euro.currency = .eur
        let invoices = threeInvoices + [euro]

        let data = build(
            input(
                invoices: invoices, paymentDayRates: [2: usd("21.305")], issueDayRates: [3: usd("21.622")],
                uniformRates: [uniformRate(year: 2026), eurRate]))

        // 4 500,00 Kč + (14 350 + 12 040) USD at 21,84 + 700,00 EUR at 24,66
        let expectedTotal: Int64 = 450_000 + 57_635_760 + 1_726_200
        #expect(data.uniformTotalHalere == expectedTotal)
        #expect(
            data.uniform
                == .value(
                    text: "598\u{00A0}120\u{00A0}Kč",
                    help: "Jednotný kurz 2026: 1\u{00A0}EUR = 24,66\u{00A0}Kč, 1\u{00A0}USD = 21,84\u{00A0}Kč"
                        + " · pokyn GFŘ-D-75"))
    }

    @Test func aRateForAHundredUnitsIsQuotedForAHundred() {
        var yen = dollarInvoice(id: 1, hours: "10")
        yen.currency = CurrencyCode("JPY")!

        let data = build(input(invoices: [yen], uniformRates: [uniformRate("JPY", "14.59", year: 2026, amount: 100)]))

        // 700,00 JPY at 14,59 Kč per 100
        #expect(data.uniformTotalHalere == 10_213)
        #expect(
            data.uniform
                == .value(
                    text: "102\u{00A0}Kč",
                    help: "Jednotný kurz 2026: 100\u{00A0}JPY = 14,59\u{00A0}Kč · pokyn GFŘ-D-75"))
    }

    @Test func aCategoryWithoutForeignInvoicesHasNoTotalAtTheUniformRate() {
        let data = build(input(invoices: [crownInvoice(id: 1)]))

        #expect(data.czkTotalHalere == 450_000)
        #expect(data.totalText == "4\u{00A0}500\u{00A0}Kč")
        #expect(data.uniformTotalHalere == 450_000)
        #expect(data.uniform == .hidden)
        #expect(data.reviewHint == nil)
    }

    @Test func aFilterThatLeavesOnlyCrownInvoicesHasNoTotalAtTheUniformRate() {
        // Only the crown invoice is overdue (due 14. 10.); the dollar invoices are due on 30. 10.
        let data = build(input(filter: .overdue, invoices: threeInvoices))

        #expect(data.rows.map(\.id) == [1])
        #expect(data.uniform == .hidden)
    }

    @Test func anEmptyCategoryShowsZeroCrownsAndNoForeignCurrency() {
        let data = build(input(filter: .drafts, invoices: threeInvoices))

        #expect(data.rows.isEmpty)
        #expect(data.czkTotalHalere == 0)
        #expect(data.countText == "0\u{00A0}faktur")
        #expect(data.totalText == "0\u{00A0}Kč")
        #expect(data.uniform == .hidden)
    }

    // MARK: The count

    @Test func theCountCountsTheRowsOfTheCategoryAndNamesIt() {
        let all = build(input(invoices: threeInvoices))
        let overdue = build(input(filter: .overdue, invoices: threeInvoices))
        let paid = build(
            input(scope: .paid, filter: .paid, invoices: threeInvoices, paymentDayRates: [2: usd("21.305")]))

        // The scope is the segment's to say: the line names the category alone.
        #expect(all.countText == "3\u{00A0}faktury")
        #expect(all.categoryText == " · všechny stavy")
        #expect(overdue.countText == "1\u{00A0}faktura")
        #expect(overdue.categoryText == " · po splatnosti")
        #expect(paid.countText == "1\u{00A0}faktura")
        #expect(paid.categoryText == " · uhrazené")
    }

    /// The count is the number of rows with the noun in the form Czech asks for that number, a no-break space between
    /// them, as the prototype writes it.
    @Test(arguments: [
        (0, "0\u{00A0}faktur"), (1, "1\u{00A0}faktura"), (2, "2\u{00A0}faktury"), (4, "4\u{00A0}faktury"),
        (5, "5\u{00A0}faktur"), (12, "12\u{00A0}faktur"),
    ])
    func theCountSaysTheInvoicesInTheFormOfCzechTheirNumberAsks(count: Int, text: String) {
        let data = build(input(invoices: Array(twelveInvoices.prefix(count))))

        #expect(data.rows.count == count)
        #expect(data.countText == text)
    }

    @Test func everyFilterNamesItsCategoryInLowerCase() {
        let names: [InvoiceStatusFilter: String] = [
            .all: "všechny stavy", .drafts: "koncepty", .awaiting: "čekají na platbu", .overdue: "po splatnosti",
            .paid: "uhrazené", .review: "ke kontrole",
        ]

        for filter in InvoiceStatusFilter.allCases {
            let category = build(input(filter: filter, invoices: [])).categoryText
            #expect(category == " · " + (names[filter] ?? "?"))
        }
    }

    // MARK: The summary of one invoice and the hint about invoices to check

    @Test func theSummaryOfOneInvoiceInCrownsIsTheCountAndTheTotal() {
        let data = build(input(invoices: [crownInvoice(id: 1, number: "20260902")]))

        #expect(data.countText == "1\u{00A0}faktura")
        #expect(data.categoryText == " · všechny stavy")
        #expect(data.totalText == "4\u{00A0}500\u{00A0}Kč")
        #expect(data.uniform == .hidden)
        #expect(data.reviewHint == nil)
    }

    @Test func aCurrencyWithoutAUniformRateSaysItIsNotOutYetAndWhenItComes() {
        let invoice = dollarInvoice(id: 2, number: "20261001", hours: "205")

        let data = build(input(invoices: [invoice], issueDayRates: [2: usd("21.622")]))

        // 14 350,00 USD at 21,622: 310 275,70 Kč.
        #expect(data.totalText == "310\u{00A0}276\u{00A0}Kč")
        #expect(data.uniform == notAnnounced(notPublished2026))
    }

    @Test func aKnownUniformRateIsNamedWithItsSource() {
        let data = build(
            input(
                invoices: [dollarInvoice(id: 2, number: "20261001", hours: "205")], issueDayRates: [2: usd("21.622")],
                uniformRates: [uniformRate(year: 2026)]))

        #expect(
            data.uniform
                == .value(
                    text: "313\u{00A0}404\u{00A0}Kč",
                    help: "Jednotný kurz 2026: 1\u{00A0}USD = 21,84\u{00A0}Kč · pokyn GFŘ-D-75"))
    }

    private let toCheck = ReviewFlag(reason: "chybí kurz faktury")

    @Test func whenOnlyInvoicesToCheckAreInForeignCurrencyTheSummarySaysTheyAreLeftOut() {
        // The dollar invoice is held for review, so neither total counts it, and the row would show no total at the
        // uniform rate while the table lists an invoice in dollars.
        let data = build(
            input(invoices: [crownInvoice(id: 1, number: "20260902"), dollarInvoice(id: 2, review: toCheck)]))

        #expect(data.chipCounts[.review] == 1)
        #expect(data.uniform == .hidden)
        #expect(data.reviewHint == " · mimo součet: 1\u{00A0}faktura ke kontrole")
        // The count counts what the table lists.
        #expect(data.countText == "2\u{00A0}faktury")
        #expect(data.categoryText == " · všechny stavy")
    }

    @Test func theHintCountsEveryInvoiceToCheckOfTheCategoryWithTheRightWord() {
        let invoices = [
            dollarInvoice(id: 1, number: "20261001", review: toCheck),
            dollarInvoice(id: 2, number: "20261002", review: toCheck),
            dollarInvoice(id: 3, number: "20261003", review: toCheck),
            crownInvoice(id: 4, number: "20261004", review: toCheck),
            crownInvoice(id: 5, number: "20261005", review: toCheck),
        ]

        #expect(build(input(invoices: invoices)).reviewHint == " · mimo součet: 5\u{00A0}faktur ke kontrole")
        #expect(
            build(input(invoices: Array(invoices.prefix(2)))).reviewHint
                == " · mimo součet: 2\u{00A0}faktury ke kontrole")
    }

    @Test func noHintWhenTheTableListsNoForeignInvoiceToCheck() {
        // A crown invoice to check changes nothing the row says: no invoice in a foreign currency is hidden.
        let invoices = [
            crownInvoice(id: 1, number: "20260902"), crownInvoice(id: 2, number: "20260903", review: toCheck),
        ]

        let data = build(input(invoices: invoices))

        #expect(data.uniform == .hidden)
        #expect(data.reviewHint == nil)
    }

    @Test func noHintWhenAnotherForeignInvoiceIsCounted() {
        let invoices = [
            dollarInvoice(id: 1, number: "20261001"), dollarInvoice(id: 2, number: "20261002", review: toCheck),
        ]

        let data = build(input(invoices: invoices, issueDayRates: [1: usd("21.622")]))

        #expect(data.uniform == notAnnounced(notPublished2026))
        #expect(data.reviewHint == nil)
    }

    @Test func theChipOfTheInvoicesToCheckListsOnlyThemAndStillHintsAtTheTotal() {
        let invoices = [
            crownInvoice(id: 1, number: "20260902"), dollarInvoice(id: 2, number: "20261001", review: toCheck),
        ]

        let data = build(input(filter: .review, invoices: invoices))

        #expect(data.countText == "1\u{00A0}faktura")
        #expect(data.categoryText == " · ke kontrole")
        #expect(data.totalText == "0\u{00A0}Kč")
        #expect(data.reviewHint == " · mimo součet: 1\u{00A0}faktura ke kontrole")
    }

    // MARK: The chips

    /// Six invoices of 2026 as of 17. 10.: a draft, one that awaits payment, an overdue one, a paid one and two in
    /// review.
    private var oneOfEachStatus: [Invoice] {
        [
            crownInvoice(id: 1, number: "20260901", status: .draft),
            crownInvoice(id: 2, number: "20260902", dueDate: "2026-10-30"),
            crownInvoice(id: 3, number: "20260903", dueDate: "2026-10-14"),
            crownInvoice(id: 4, number: "20260904", payment: .fixture(on: "2026-10-05")),
            crownInvoice(id: 5, number: "20260905", review: ReviewFlag(reason: "záporná částka")),
            crownInvoice(id: 6, number: "20260906", review: ReviewFlag(reason: "bez data platby")),
        ]
    }

    @Test func everyInvoiceIsCountedInItsChipAndInAll() {
        let counts = build(input(invoices: oneOfEachStatus)).chipCounts

        #expect(counts[.all] == 6)
        #expect(counts[.drafts] == 1)
        #expect(counts[.awaiting] == 1)
        #expect(counts[.overdue] == 1)
        #expect(counts[.paid] == 1)
        #expect(counts[.review] == 2)
    }

    @Test func theChipsCountTheWholeScopeWhateverFilterIsChosen() {
        let counts = build(input(filter: .paid, invoices: oneOfEachStatus)).chipCounts

        #expect(counts[.all] == 6)
        #expect(counts[.drafts] == 1)
        #expect(counts[.review] == 2)
    }

    @Test func theChipForInvoicesToCheckIsThereOnlyWhenItHasAnInvoice() {
        let withReview = build(input(invoices: oneOfEachStatus))
        let without = build(input(invoices: Array(oneOfEachStatus.prefix(4))))

        #expect(withReview.visibleChips == [.all, .drafts, .awaiting, .overdue, .paid, .review])
        #expect(without.chipCounts[.review] == 0)
        #expect(without.visibleChips == [.all, .drafts, .awaiting, .overdue, .paid])
    }

    @Test func theChipForInvoicesToCheckStaysWhileItIsTheChosenFilterEvenWithNothingInIt() {
        let data = build(input(filter: .review, invoices: Array(oneOfEachStatus.prefix(4))))

        #expect(data.rows.isEmpty)
        #expect(data.visibleChips.contains(.review))
    }

    @Test func aDayLaterAnInvoiceThatAwaitedPaymentIsOverdue() {
        let invoices = [crownInvoice(id: 1, dueDate: "2026-10-17")]

        let onTheDueDate = build(input(statusDay: "2026-10-17", invoices: invoices)).chipCounts
        let theDayAfter = build(input(statusDay: "2026-10-18", invoices: invoices)).chipCounts

        #expect(onTheDueDate[.awaiting] == 1)
        #expect(onTheDueDate[.overdue] == 0)
        #expect(theDayAfter[.awaiting] == 0)
        #expect(theDayAfter[.overdue] == 1)
    }

    @Test func theChipsCountByTheStatusDayWhateverDayIsShown() {
        // Due 17. 10. and not paid, with today the 18th: it is overdue whether the day shown is long before its due
        // date or long after it.
        let invoices = [crownInvoice(id: 1, dueDate: "2026-10-17")]

        for shown in ["2026-03-01", "2026-10-17", "2026-12-31"] {
            let counts = build(input(asOf: shown, statusDay: "2026-10-18", invoices: invoices)).chipCounts

            #expect(counts[.awaiting] == 0, "shown as of \(shown)")
            #expect(counts[.overdue] == 1, "shown as of \(shown)")
        }
    }

    @Test func theChosenChipFiltersByTheStatusDayWhateverDayIsShown() {
        // Seen in 2025, as of 31. 12., one invoice is paid on 2. 1. 2026 and the other is due on 30. 1. 2026. As of the
        // day shown both would await payment, but today is 20. 10. 2026: the first is paid and the second overdue.
        let invoices = [
            crownInvoice(
                id: 1, number: "20251201", issued: "2025-12-30", dueDate: "2026-01-13",
                payment: .fixture(on: "2026-01-02")),
            crownInvoice(id: 2, number: "20251202", issued: "2025-12-31", dueDate: "2026-01-30"),
        ]

        func rows(of filter: InvoiceStatusFilter) -> [Int64] {
            build(input(year: 2025, asOf: "2025-12-31", statusDay: "2026-10-20", filter: filter, invoices: invoices))
                .rows.map(\.id)
        }

        #expect(rows(of: .paid) == [1])
        #expect(rows(of: .overdue) == [2])
        #expect(rows(of: .awaiting).isEmpty)
        #expect(rows(of: .all) == [2, 1])
    }

    // MARK: The rows

    @Test func theRowsAreInTheOrderOfTheDigitsOfTheirNumbersNewestFirst() {
        let invoices = [
            crownInvoice(id: 1, number: "2026-08-01"),
            crownInvoice(id: 2, number: "Z20261001"),
            crownInvoice(id: 3, number: "20260902"),
            crownInvoice(id: 4, number: "20260901"),
        ]

        let rows = build(input(invoices: invoices)).rows

        #expect(rows.map(\.number) == ["Z20261001", "20260902", "20260901", "2026-08-01"])
    }

    @Test func aRowCarriesTheTextsOfTheTable() throws {
        let invoice = crownInvoice(id: 7, number: "20260902", payment: .fixture(on: "2026-10-15"))

        let row = try #require(build(input(invoices: [invoice])).rows.first)

        #expect(row.id == 7)
        #expect(row.number == "20260902")
        #expect(row.client == "Cetus Data s.r.o.")
        #expect(row.issued == "30.\u{00A0}9.")
        #expect(row.paidDate == "15.\u{00A0}10.")
        #expect(row.paidTone == .received)
        #expect(row.net == "4\u{00A0}500,00\u{00A0}Kč")
        // V Kč bez DPH shows an invoice in crowns too: its amount without VAT, which is its net.
        #expect(row.czk == "4\u{00A0}500,00\u{00A0}Kč")
        #expect(row.czk == row.net)
        #expect(row.czkKind == .actual)
        #expect(row.czkHelp == nil)
        #expect(row.status == .paid(civilDate("2026-10-15")))
        // The pill of the list has no date: the date has a column of its own.
        #expect(row.listStatus == "Uhrazená")
        #expect(row.pillTone == .paid)
        #expect(row.excerpt == nil)
    }

    @Test func anInvoiceWithoutAPaymentHasADashForItsPaymentDate() throws {
        let row = try #require(build(input(invoices: [crownInvoice(id: 1, status: .draft)])).rows.first)

        #expect(row.paidDate == "—")
        #expect(row.paidTone == PaidTone.none)
        #expect(row.status == .draft)
        #expect(row.listStatus == "Koncept")
        #expect(row.pillTone == .draft)
    }

    /// The pill of a row names the status without a date, in the tone of the status: a draft in grey, an invoice that
    /// waits for its payment in blue, one past its due date in red, a paid one in green and one to check in the
    /// orange of attention.
    @Test func everyStatusHasItsShortTextAndToneInTheList() throws {
        let data = build(input(invoices: oneOfEachStatus))
        func row(_ id: Int64) throws -> InvoiceRow {
            try #require(data.rows.first { $0.id == id })
        }

        #expect(try row(1).listStatus == "Koncept")
        #expect(try row(1).pillTone == .draft)
        #expect(try row(2).listStatus == "Čeká na platbu")
        #expect(try row(2).pillTone == .waiting)
        #expect(try row(3).listStatus == "Po splatnosti")
        #expect(try row(3).pillTone == .overdue)
        #expect(try row(4).listStatus == "Uhrazená")
        #expect(try row(4).pillTone == .paid)
        #expect(try row(5).listStatus == "Ke kontrole")
        #expect(try row(5).pillTone == .review)
    }

    @Test func aPaymentDatedAfterTodayIsALaterOne() throws {
        // A payment on 20. 10. while today is the 17th, as an import or a clock that was set back can leave one.
        let later = crownInvoice(id: 1, number: "20260901", payment: .fixture(on: "2026-10-20"))
        let today = crownInvoice(id: 2, number: "20260902", payment: .fixture(on: "2026-10-17"))

        let data = build(input(asOf: "2026-10-17", statusDay: "2026-10-17", invoices: [later, today]))

        let first = try #require(data.rows.first { $0.id == 1 })
        #expect(first.paidDate == "20.\u{00A0}10.")
        #expect(first.paidTone == .later)
        let second = try #require(data.rows.first { $0.id == 2 })
        #expect(second.paidDate == "17.\u{00A0}10.")
        #expect(second.paidTone == .received)
    }

    @Test func aPaymentOfJanuaryInTheListOfTheYearBeforeIsNoLaterOneOnceTodayHasPassedIt() throws {
        // The list of 2025 is shown as of 31. 12. 2025, and today is 20. 10. 2026: the payment of 2. 1. 2026 is after
        // the day shown but not after today, so it is not grey.
        let invoice = crownInvoice(
            id: 1, number: "20251201", issued: "2025-12-30", dueDate: "2026-01-13", payment: .fixture(on: "2026-01-02"))

        let data = build(input(year: 2025, asOf: "2025-12-31", statusDay: "2026-10-20", invoices: [invoice]))

        let row = try #require(data.rows.first)
        #expect(row.paidDate == "2.\u{00A0}1.\u{00A0}2026")
        #expect(row.paidTone == .received)
    }

    @Test func aPaidForeignInvoiceShowsWhatWasPaid() throws {
        let invoice = dollarInvoice(id: 1, payment: paidAtTheRateOfTheDay())

        let row = try #require(build(input(invoices: [invoice], paymentDayRates: [1: usd("21.305")])).rows.first)

        #expect(row.czk == "305\u{00A0}726,75\u{00A0}Kč")
        #expect(row.czkKind == .actual)
        #expect(row.czkHelp == nil)
    }

    @Test func aPaymentAtTheUniformRateOrFromTheBankShowsTheCrownsItBrought() throws {
        let uniform = Payment.fixture(
            on: "2026-10-02", conversion: .uniform, net: 31_340_400, vat: 0,
            rate: storedRate("USD", "21.84", declaredOn: "2026-12-31"))
        let bank = Payment.fixture(
            on: "2026-10-02", conversion: .bankCZK, net: 30_600_000, vat: 0, bankCZKTotalHalere: 30_600_000)

        let invoices = [
            dollarInvoice(id: 1, number: "20260901", payment: uniform),
            dollarInvoice(id: 2, number: "20260902", payment: bank),
        ]

        let rows = build(input(invoices: invoices)).rows

        #expect(rows.first { $0.id == 1 }?.czk == "313\u{00A0}404,00\u{00A0}Kč")
        #expect(rows.first { $0.id == 2 }?.czk == "306\u{00A0}000,00\u{00A0}Kč")
        #expect(rows.allSatisfy { $0.czkKind == .actual && $0.czkHelp == nil })
    }

    @Test func aProvisionalPaymentIsMarkedAsAnEstimate() throws {
        let provisional = Payment.fixture(
            on: "2026-10-02", conversion: .cnbDaily, net: 31_027_570, vat: 0,
            rate: storedRate("USD", "21.622", declaredOn: "2026-09-30"), provisional: true)

        let row = try #require(build(input(invoices: [dollarInvoice(id: 1, payment: provisional)])).rows.first)

        // The money came, so the value is what was received, in the colour of text, but its rate is not final yet.
        #expect(row.czk == "≈ 310\u{00A0}275,70\u{00A0}Kč")
        #expect(row.czkKind == .actual)
    }

    @Test func anUnpaidForeignInvoiceIsAnEstimateAtTheRateOfItsIssueDay() throws {
        let invoice = dollarInvoice(id: 3, number: "20261001", hours: "172")

        let row = try #require(build(input(invoices: [invoice], issueDayRates: [3: usd("21.622")])).rows.first)

        // The sign for an estimate is on the amount, which is grey; the tooltip names the conversion, with the rate in
        // three decimals.
        #expect(row.czk == "≈ 260\u{00A0}328,88\u{00A0}Kč")
        #expect(row.czkKind == .estimate)
        #expect(row.czkHelp == "Odhad kurzem ČNB ke dni vystavení: 21,622\u{00A0}Kč/USD")
    }

    @Test func theRateOfAnEstimateHasThreeDecimalsAsTheCNBQuotesIt() throws {
        let invoice = dollarInvoice(id: 3, number: "20261001", hours: "172")

        let row = try #require(build(input(invoices: [invoice], issueDayRates: [3: usd("21.6")])).rows.first)

        #expect(row.czkHelp == "Odhad kurzem ČNB ke dni vystavení: 21,600\u{00A0}Kč/USD")
    }

    @Test func aDateOfAnotherYearThanTheChosenDayShowsItsYear() throws {
        // Issued 30. 12. 2025 and paid on 2. 1. 2026: in the list of what was paid in 2026.
        let invoice = crownInvoice(
            id: 1, number: "20251201", issued: "2025-12-30", dueDate: "2026-01-13", payment: .fixture(on: "2026-01-02"))

        let data = build(input(scope: .paid, invoices: [invoice]))

        let row = try #require(data.rows.first)
        #expect(row.issued == "30.\u{00A0}12.\u{00A0}2025")
        #expect(row.paidDate == "2.\u{00A0}1.")
        #expect(row.listStatus == "Uhrazená")
        // The column of the day of issue has a date with its year, so it is widened to hold it; that of the payment
        // has none.
        #expect(data.issueDatesShowYear)
        #expect(!data.paymentDatesShowYear)
    }

    @Test func theDateColumnsHoldAYearOnlyWhileARowTheTableShowsPrintsOne() {
        // In the list of 2025 the payment of January 2026 prints its year; the chip of the overdue invoices shows
        // nothing paid, and no date of another year.
        let paidInJanuary = crownInvoice(
            id: 1, number: "20251201", issued: "2025-12-30", dueDate: "2026-01-13", payment: .fixture(on: "2026-01-02"))
        let overdue = crownInvoice(id: 2, number: "20251001", issued: "2025-10-01", dueDate: "2025-10-15")

        func list(of filter: InvoiceStatusFilter) -> InvoiceListData {
            build(
                input(
                    year: 2025, asOf: "2025-12-31", statusDay: "2026-10-20", filter: filter,
                    invoices: [paidInJanuary, overdue]))
        }
        let all = list(of: .all)
        let onlyOverdue = list(of: .overdue)

        #expect(all.paymentDatesShowYear)
        #expect(!all.issueDatesShowYear)
        #expect(onlyOverdue.rows.map(\.id) == [2])
        #expect(!onlyOverdue.paymentDatesShowYear)
        #expect(!onlyOverdue.issueDatesShowYear)
    }

    // MARK: The net income

    /// The invoice of the prediction sample with the id `id`: 1 to 11 are the payments of 2026, 12 is the draft.
    private func sample(_ id: Int64) -> Invoice {
        PredictionSample.invoices[Int(id) - 1]
    }

    /// The nets of `invoices` as of `asOf` in the year 2026 of the prediction sample, as the app works them out
    /// (`InvoiceNetIncome.make`). The draft is not paid, so its dollars are worth the rate of the sample.
    private func netIncomes(of invoices: [Invoice], asOf: String = "2026-10-17") -> [Int64: InvoiceNetIncome] {
        InvoiceNetIncome.make(
            for: invoices, asOf: civilDate(asOf), rates: [12: PredictionSample.usdRate],
            years: [2026: PredictionSample.yearInput(year: 2026)])
    }

    private func rowOfInvoice(_ id: Int64, in data: InvoiceListData) throws -> InvoiceRow {
        try #require(data.rows.first { $0.id == id })
    }

    /// The eleven payments of the sample and its draft as of 17. 10. 2026. What each payment left is the net of the
    /// golden table, which a separate implementation worked out, in whole Kč rounded half up. The cell has one line:
    /// what the levies took of the payment is told in the detail.
    @Test func theNetIncomeOfTheSampleYearIsWhatEachPaymentLeavesAfterTheLevies() throws {
        let invoices = (1...12).map { sample(Int64($0)) }

        let data = build(input(invoices: invoices, netIncomes: netIncomes(of: invoices)))

        // The first payment brought a tax bonus, so the levies fell.
        let first = try rowOfInvoice(1, in: data)
        #expect(first.netIncome == "253\u{00A0}401\u{00A0}Kč")
        #expect(first.netIncomeKind == .paid)
        let tenth = try rowOfInvoice(10, in: data)
        #expect(tenth.netIncome == "217\u{00A0}013\u{00A0}Kč")
        let eleventh = try rowOfInvoice(11, in: data)
        #expect(eleventh.netIncome == "2\u{00A0}798\u{00A0}Kč")
        // The draft is not paid: what its payment is expected to leave, on its due date, with the sign of an estimate.
        let draft = try rowOfInvoice(12, in: data)
        #expect(draft.netIncome == "≈\u{00A0}159\u{00A0}636\u{00A0}Kč")
        #expect(draft.netIncomeKind == .estimate)

        let byID = data.rows.sorted { $0.id < $1.id }
        let net = [
            "253\u{00A0}401\u{00A0}Kč", "177\u{00A0}521\u{00A0}Kč", "192\u{00A0}992\u{00A0}Kč",
            "190\u{00A0}839\u{00A0}Kč", "190\u{00A0}840\u{00A0}Kč", "261\u{00A0}885\u{00A0}Kč",
            "228\u{00A0}155\u{00A0}Kč", "3\u{00A0}819\u{00A0}Kč", "237\u{00A0}168\u{00A0}Kč",
            "217\u{00A0}013\u{00A0}Kč", "2\u{00A0}798\u{00A0}Kč", "≈\u{00A0}159\u{00A0}636\u{00A0}Kč",
        ]
        #expect(byID.map(\.netIncome) == net)
        #expect(byID.map(\.netIncomeKind) == [NetIncomeKind](repeating: .paid, count: 11) + [.estimate])
    }

    @Test func anInvoiceWithoutANetShowsADash() throws {
        let row = try #require(build(input(invoices: [crownInvoice(id: 1)])).rows.first)

        #expect(row.netIncome == "—")
        #expect(row.netIncomeKind == .none)
    }

    @Test func aPaymentWaitingForItsRateShowsTheSignOfAnEstimateInGreen() throws {
        // The money came, so it is a payment and not an estimate, but its rate is not final yet.
        var waiting = sample(10)
        waiting.payment?.provisional = true

        let data = build(input(invoices: [waiting], netIncomes: netIncomes(of: [waiting])))

        let row = try rowOfInvoice(10, in: data)
        #expect(row.netIncome == "≈\u{00A0}217\u{00A0}013\u{00A0}Kč")
        #expect(row.netIncomeKind == .paid)
    }

    @Test func aRowPaidAfterTheDayShownShowsItsNet() throws {
        // The first invoice of the sample is paid on 3. 2., two days after the day shown. The money has not arrived by
        // then, but it is a payment and not an estimate, and it counts in its year.
        let invoice = sample(1)
        #expect(invoice.payment?.date == civilDate("2026-02-03"))

        let data = build(
            input(asOf: "2026-02-01", invoices: [invoice], netIncomes: netIncomes(of: [invoice], asOf: "2026-02-01")))

        let row = try rowOfInvoice(1, in: data)
        #expect(row.hasReceivedPayment == false)
        #expect(row.netIncome == "253\u{00A0}401\u{00A0}Kč")
        #expect(row.netIncomeKind == .paid)
    }

    @Test func aPaymentOfNothingLeavesNothing() throws {
        let receipt = Receipt(day: civilDate("2026-10-15"), czkNetHalere: 0, czkVatHalere: 0, source: .invoice(1))
        let effect = ReceiptEffect(receipt: receipt, tax: 0, social: 0, health: 0, total: 0)
        let net = InvoiceNetIncome(effect: effect, isEstimate: false, isProvisional: false)
        let invoice = crownInvoice(id: 1, payment: .fixture(on: "2026-10-15"))

        let data = build(input(invoices: [invoice], netIncomes: [1: net]))

        let row = try rowOfInvoice(1, in: data)
        #expect(row.netIncome == "0\u{00A0}Kč")
        #expect(row.netIncomeKind == .paid)
    }

    // MARK: The scope

    @Test func theIssuedListHasTheInvoicesIssuedInTheYearEvenWhenTheyArePaidLater() {
        let invoices = [
            crownInvoice(id: 1, number: "20260901", payment: .fixture(on: "2026-10-05")),
            crownInvoice(id: 2, number: "20260902", payment: .fixture(on: "2026-10-20")),
            crownInvoice(id: 3, number: "20251201", issued: "2025-12-30", payment: .fixture(on: "2026-01-02")),
        ]

        let data = build(input(statusDay: "2026-10-20", scope: .issued, invoices: invoices))

        #expect(data.rows.map(\.id) == [2, 1])
        // The payment of the first row is after the day shown but not after today, 20. 10., so both are paid.
        #expect(data.rows.map(\.status) == [.paid(civilDate("2026-10-20")), .paid(civilDate("2026-10-05"))])
    }

    @Test func thePaidListHasTheInvoicesPaidInTheYearUpToTheChosenDay() {
        let invoices = [
            crownInvoice(id: 1, number: "20260901", payment: .fixture(on: "2026-10-05")),
            crownInvoice(id: 2, number: "20260902", payment: .fixture(on: "2026-10-20")),
            crownInvoice(id: 3, number: "20251201", issued: "2025-12-30", payment: .fixture(on: "2026-01-02")),
            crownInvoice(id: 4, number: "20250901", issued: "2025-09-30", payment: .fixture(on: "2025-10-10")),
            crownInvoice(id: 5, number: "20260903"),
        ]

        let data = build(input(scope: .paid, invoices: invoices))

        // Not the one paid after the day, nor the one paid in 2025, nor the unpaid one.
        #expect(data.rows.map(\.id) == [1, 3])
        #expect(data.chipCounts[.all] == 2)
        #expect(data.countText == "2\u{00A0}faktury")
        #expect(data.categoryText == " · všechny stavy")
    }

    // MARK: The sample year

    /// The twelve invoices of the sample year as of 17. 10. 2026. The numbers and the texts of the rows were worked
    /// out for the same data by a separate implementation.
    @Test func theSampleYearGivesTheRowsAndTheSummaryThatWereWorkedOutSeparately() {
        let day = civilDate("2026-10-17")

        let data = build(
            input(
                invoices: SampleYear2026.invoices, paymentDayRates: SampleYear2026.paymentDayRates,
                issueDayRates: SampleYear2026.issueDayRates))

        let numbers = [
            "20261001", "20260902", "20260901", "20260802", "20260801", "20260701", "20260601", "2026-05-01",
            "2026-04-01", "2026-03-01", "2026-02-01", "2026-01-01",
        ]
        #expect(data.rows.map(\.number) == numbers)
        let issued = [
            "31.\u{00A0}10.", "30.\u{00A0}9.", "30.\u{00A0}9.", "31.\u{00A0}8.", "18.\u{00A0}8.", "31.\u{00A0}7.",
            "30.\u{00A0}6.", "29.\u{00A0}5.", "30.\u{00A0}4.", "31.\u{00A0}3.", "28.\u{00A0}2.", "31.\u{00A0}1.",
        ]
        #expect(data.rows.map(\.issued) == issued)
        let paid = [
            "—", "15.\u{00A0}10.", "2.\u{00A0}10.", "9.\u{00A0}9.", "26.\u{00A0}8.", "7.\u{00A0}8.",
            "7.\u{00A0}7.", "5.\u{00A0}5.", "10.\u{00A0}4.", "7.\u{00A0}4.", "3.\u{00A0}3.", "3.\u{00A0}2.",
        ]
        #expect(data.rows.map(\.paidDate) == paid)
        #expect(data.rows.map(\.paidTone) == [PaidTone.none] + [PaidTone](repeating: .received, count: 11))
        let net = [
            "12\u{00A0}040,00\u{00A0}USD", "4\u{00A0}500,00\u{00A0}Kč", "14\u{00A0}350,00\u{00A0}USD",
            "13\u{00A0}300,00\u{00A0}USD", "4\u{00A0}500,00\u{00A0}Kč", "12\u{00A0}880,00\u{00A0}USD",
            "13\u{00A0}720,00\u{00A0}USD", "210\u{00A0}000,00\u{00A0}Kč", "210\u{00A0}000,00\u{00A0}Kč",
            "210\u{00A0}000,00\u{00A0}Kč", "190\u{00A0}000,00\u{00A0}Kč", "220\u{00A0}000,00\u{00A0}Kč",
        ]
        #expect(data.rows.map(\.net) == net)
        // V Kč bez DPH: the estimate of the draft at the rate of its issue day, what each payment in dollars brought,
        // and the amount of each invoice in crowns.
        let czk = [
            "≈ 260\u{00A0}328,88\u{00A0}Kč", "4\u{00A0}500,00\u{00A0}Kč", "305\u{00A0}726,75\u{00A0}Kč",
            "279\u{00A0}433,00\u{00A0}Kč", "4\u{00A0}500,00\u{00A0}Kč", "268\u{00A0}805,60\u{00A0}Kč",
            "288\u{00A0}806,00\u{00A0}Kč", "210\u{00A0}000,00\u{00A0}Kč", "210\u{00A0}000,00\u{00A0}Kč",
            "210\u{00A0}000,00\u{00A0}Kč", "190\u{00A0}000,00\u{00A0}Kč", "220\u{00A0}000,00\u{00A0}Kč",
        ]
        #expect(data.rows.map(\.czk) == czk)
        #expect(data.rows.map(\.czkKind) == [CrownsKind.estimate] + [CrownsKind](repeating: .actual, count: 11))
        // The tooltip of the estimate names the rate of the day of issue; nothing else has one.
        #expect(
            data.rows.map(\.czkHelp)
                == ["Odhad kurzem ČNB ke dni vystavení: 21,622\u{00A0}Kč/USD"] + [String?](repeating: nil, count: 11))
        // The pill of the list: the status without the date of the payment, which has its own column.
        #expect(data.rows.map(\.listStatus) == ["Koncept"] + [String](repeating: "Uhrazená", count: 11))
        #expect(data.rows.map(\.pillTone) == [PillTone.draft] + [PillTone](repeating: .paid, count: 11))
        // The status itself keeps the day of the payment, which the detail shows in its pill.
        let statuses = [
            "Koncept", "Uhrazená 15.\u{00A0}10.", "Uhrazená 2.\u{00A0}10.", "Uhrazená 9.\u{00A0}9.",
            "Uhrazená 26.\u{00A0}8.", "Uhrazená 7.\u{00A0}8.", "Uhrazená 7.\u{00A0}7.", "Uhrazená 5.\u{00A0}5.",
            "Uhrazená 10.\u{00A0}4.", "Uhrazená 7.\u{00A0}4.", "Uhrazená 3.\u{00A0}3.", "Uhrazená 3.\u{00A0}2.",
        ]
        #expect(data.rows.map { $0.status.label(asOf: day) } == statuses)
        #expect(!data.issueDatesShowYear)
        #expect(!data.paymentDatesShowYear)

        #expect(data.countText == "12\u{00A0}faktur")
        #expect(data.categoryText == " · všechny stavy")
        // 2 452 100,23 Kč in whole Kč.
        #expect(data.czkTotalHalere == 245_210_023)
        #expect(data.totalText == "2\u{00A0}452\u{00A0}100\u{00A0}Kč")
        #expect(data.uniform == notAnnounced(notPublished2026))
        #expect(data.reviewHint == nil)
        #expect(data.chipCounts[.all] == 12)
        #expect(data.chipCounts[.drafts] == 1)
        #expect(data.chipCounts[.awaiting] == 0)
        #expect(data.chipCounts[.overdue] == 0)
        #expect(data.chipCounts[.paid] == 11)
    }

    @Test func moneyReceivedOnThe1stOfJanuaryBelongsToTheNewYear() {
        let invoice = crownInvoice(
            id: 1, number: "20251201", issued: "2025-12-30", dueDate: "2026-01-13", payment: .fixture(on: "2026-01-01"))

        let newYear = build(input(year: 2026, scope: .paid, invoices: [invoice]))
        let oldYear = build(input(year: 2025, asOf: "2025-12-31", scope: .paid, invoices: [invoice]))
        let issuedInTheOldYear = build(input(year: 2025, asOf: "2025-12-31", scope: .issued, invoices: [invoice]))

        #expect(newYear.rows.map(\.id) == [1])
        #expect(oldYear.rows.isEmpty)
        // It was issued in 2025, where the money has not arrived yet on 31. 12., but the invoice is paid as of today.
        #expect(issuedInTheOldYear.rows.map(\.id) == [1])
        #expect(issuedInTheOldYear.rows.map(\.status) == [InvoiceDisplayStatus.paid(civilDate("2026-01-01"))])
    }

    // MARK: One status for an invoice

    /// An invoice in dollars issued on 30. 12. 2025, due on 13. 1. 2026 and paid on 2. 1. 2026: 14 350,00 USD, which
    /// were 306 501,65 Kč at the rate of the day of issue, 21,359, and 305 726,75 Kč at the rate of the day of the
    /// payment, 21,305.
    private var paidInJanuary: Invoice {
        dollarInvoice(
            id: 1, number: "20251201", issued: "2025-12-30", dueDate: "2026-01-13",
            payment: paidAtTheRateOfTheDay(on: "2026-01-02"))
    }

    @Test func anInvoicePaidInJanuaryShowsPaidWhenTheYearBeforeIsShown() throws {
        // The year 2025, as of 31. 12., and today is 20. 10. 2026.
        let data = build(
            input(
                year: 2025, asOf: "2025-12-31", statusDay: "2026-10-20", scope: .issued, invoices: [paidInJanuary],
                paymentDayRates: [1: usd("21.305")], issueDayRates: [1: usd("21.359")]))

        let row = try #require(data.rows.first)
        #expect(row.status == .paid(civilDate("2026-01-02")))
        // The payment is of another year than the day shown, so the detail's pill says its year, and so does the date
        // in the column of the payment; the pill of the list has no date.
        #expect(row.status.label(asOf: civilDate("2025-12-31")) == "Uhrazená 2.\u{00A0}1.\u{00A0}2026")
        #expect(row.listStatus == "Uhrazená")
        #expect(row.paidDate == "2.\u{00A0}1.\u{00A0}2026")
        #expect(data.paymentDatesShowYear)
        // The money is as of the day shown: it has not arrived, so V Kč is the estimate at the rate of the issue day.
        #expect(row.hasReceivedPayment == false)
        #expect(row.czk == "≈ 306\u{00A0}501,65\u{00A0}Kč")
        #expect(row.czkKind == .estimate)
        #expect(row.czkHelp == "Odhad kurzem ČNB ke dni vystavení: 21,359\u{00A0}Kč/USD")
        #expect(data.czkTotalHalere == 30_650_165)
        #expect(data.chipCounts[.paid] == 1)
        #expect(data.chipCounts[.awaiting] == 0)
        #expect(data.chipCounts[.overdue] == 0)
    }

    @Test func thePaidInYearScopeStillFollowsThePaymentDate() {
        let issueDayRates: [Int64: ExchangeRate] = [1: usd("21.359")]
        let paymentDayRates: [Int64: ExchangeRate] = [1: usd("21.305")]

        let paidIn2025 = build(
            input(
                year: 2025, asOf: "2025-12-31", statusDay: "2026-10-20", scope: .paid, invoices: [paidInJanuary],
                paymentDayRates: paymentDayRates, issueDayRates: issueDayRates))
        let paidIn2026 = build(
            input(
                year: 2026, asOf: "2026-10-20", statusDay: "2026-10-20", scope: .paid, invoices: [paidInJanuary],
                paymentDayRates: paymentDayRates, issueDayRates: issueDayRates))

        #expect(paidIn2025.rows.isEmpty)
        #expect(paidIn2026.rows.map(\.id) == [1])
        // Once the money is there the column in crowns is what was received.
        #expect(paidIn2026.rows.first?.czk == "305\u{00A0}726,75\u{00A0}Kč")
        #expect(paidIn2026.rows.first?.hasReceivedPayment == true)
        #expect(paidIn2026.rows.first?.status == .paid(civilDate("2026-01-02")))
    }

    @Test func anUnpaidInvoiceIsOverdueByTodayWhateverTheDayShown() throws {
        // Issued 1. 9. and due 15. 9. 2026, with "K datu" on 10. 9. and today the 20th of October.
        let invoice = crownInvoice(id: 1, number: "20260901", issued: "2026-09-01", dueDate: "2026-09-15")

        let data = build(input(asOf: "2026-09-10", statusDay: "2026-10-20", invoices: [invoice]))

        let row = try #require(data.rows.first)
        #expect(row.status == .overdue)
        #expect(data.chipCounts[.overdue] == 1)
        #expect(data.chipCounts[.awaiting] == 0)
    }

    @Test func anInvoiceIsNotOverdueYetWhenADayAfterTodayIsShown() throws {
        // Due 15. 11. 2026. A day in the future is shown, 31. 12., when the invoice would be overdue, but today is
        // 20. 10., so it still awaits payment.
        let invoice = crownInvoice(id: 1, number: "20261001", issued: "2026-10-01", dueDate: "2026-11-15")

        let data = build(input(asOf: "2026-12-31", statusDay: "2026-10-20", invoices: [invoice]))

        #expect(try #require(data.rows.first).status == .awaitingPayment)
        #expect(data.chipCounts[.awaiting] == 1)
        #expect(data.chipCounts[.overdue] == 0)
    }

    // MARK: Search

    /// Twelve invoices of 2026 numbered `202601` to `202612` followed by `01`.
    private var twelveInvoices: [Invoice] {
        (1...12).map { month in
            crownInvoice(
                id: Int64(month), number: "2026" + (month < 10 ? "0\(month)" : "\(month)") + "01",
                issued: "2026-\(month < 10 ? "0\(month)" : "\(month)")-15", dueDate: "2027-01-31")
        }
    }

    @Test func aSearchLeavesTheMatchingInvoicesInTheChipsTheRowsAndTheSummary() {
        let data = build(
            input(
                invoices: twelveInvoices, searchText: "cetus", matchingIDs: [3, 9],
                otherYearCounts: [2026: 2, 2025: 2]))

        #expect(data.rows.map(\.id) == [9, 3])
        #expect(data.chipCounts[.all] == 2)
        #expect(data.chipCounts[.awaiting] == 2)
        #expect(data.countText == "2\u{00A0}faktury")
        #expect(data.categoryText == " · všechny stavy · podle hledání")
        #expect(data.czkTotalHalere == 900_000)
        #expect(data.totalText == "9\u{00A0}000\u{00A0}Kč")
        #expect(data.uniformTotalHalere == 900_000)
    }

    @Test func theSearchLineSaysHowManyInvoicesOfTheYearWereFoundAndWhereElse() throws {
        let data = build(
            input(
                invoices: twelveInvoices, searchText: "cetus", matchingIDs: [3, 9],
                otherYearCounts: [2026: 2, 2025: 2]))

        let line = try #require(data.searchLine)
        #expect(line.text == "Hledání „cetus“: 2 z 12 faktur v roce 2026")
        #expect(line.otherYears == [OtherYearMatches(year: 2025, count: 2)])
        #expect(line.otherYears.map(\.label) == ["2025 (2)"])
    }

    @Test(arguments: [
        (1, "1\u{00A0}shoda"), (2, "2\u{00A0}shody"), (3, "3\u{00A0}shody"), (4, "4\u{00A0}shody"), (5, "5\u{00A0}shod"),
        (11, "11\u{00A0}shod"), (21, "21\u{00A0}shod"),
    ])
    func aLinkToAnotherYearIsReadAloudWithTheMatchesInTheFormOfCzechTheirNumberAsks(count: Int, spoken: String) {
        let matches = OtherYearMatches(year: 2025, count: count)

        #expect(matches.accessibilityLabel == "Zobrazit rok 2025, \(spoken)")
        // The label of the link to look at stays "2025 (n)".
        #expect(matches.label == "2025 (\(count))")
    }

    @Test func theOtherYearsWithMatchesAreNewestFirstAndNeverTheYearShown() throws {
        let data = build(
            input(
                invoices: twelveInvoices, searchText: "cetus", matchingIDs: [3],
                otherYearCounts: [2024: 1, 2026: 5, 2025: 2, 2023: 0]))

        let line = try #require(data.searchLine)
        #expect(line.otherYears == [OtherYearMatches(year: 2025, count: 2), OtherYearMatches(year: 2024, count: 1)])
    }

    @Test func aSearchWithNoMatchSaysSoAndPointsToOtherYearsOnlyWhenThereAreSome() throws {
        let none = build(input(invoices: twelveInvoices, searchText: "xyz", matchingIDs: []))
        let elsewhere = build(
            input(invoices: twelveInvoices, searchText: "xyz", matchingIDs: [], otherYearCounts: [2025: 3]))

        #expect(none.rows.isEmpty)
        #expect(try #require(none.searchLine).emptyText == "Hledání „xyz“ tu nic nenašlo.")
        #expect(none.emptyText == "Hledání „xyz“ tu nic nenašlo.")
        #expect(
            try #require(elsewhere.searchLine).emptyText == "Hledání „xyz“ tu nic nenašlo – zkuste jiný rok výše.")
        #expect(elsewhere.emptyText == "Hledání „xyz“ tu nic nenašlo – zkuste jiný rok výše.")
    }

    @Test func theSearchLineSpeaksOfOneInvoiceInTheGenitive() throws {
        let one = build(input(invoices: [crownInvoice(id: 1)], searchText: "cetus", matchingIDs: [1]))
        let two = [crownInvoice(id: 1), crownInvoice(id: 2, number: "20260903")]
        let few = build(input(invoices: two, searchText: "cetus", matchingIDs: [1, 2]))
        let nothing = build(input(invoices: [], searchText: "cetus", matchingIDs: []))

        #expect(try #require(one.searchLine).text == "Hledání „cetus“: 1 z 1 faktury v roce 2026")
        #expect(try #require(few.searchLine).text == "Hledání „cetus“: 2 z 2 faktur v roce 2026")
        #expect(try #require(nothing.searchLine).text == "Hledání „cetus“: 0 z 0 faktur v roce 2026")
    }

    @Test func theSearchLineCountsOnlyTheInvoicesOfTheScope() throws {
        // The invoice of 2025 is not in the issued list of 2026, so it is not one of the invoices searched.
        let invoices = [
            crownInvoice(id: 1), crownInvoice(id: 2, number: "20250901", issued: "2025-09-30"),
        ]

        let data = build(input(invoices: invoices, searchText: "cetus", matchingIDs: [1, 2]))

        #expect(try #require(data.searchLine).text == "Hledání „cetus“: 1 z 1 faktury v roce 2026")
        #expect(data.rows.map(\.id) == [1])
    }

    @Test func theSearchLineQuotesTheTextWithoutItsOuterWhitespace() throws {
        let data = build(input(invoices: [crownInvoice(id: 1)], searchText: "  cetus \n", matchingIDs: [1]))

        #expect(try #require(data.searchLine).text == "Hledání „cetus“: 1 z 1 faktury v roce 2026")
    }

    @Test func withoutASearchThereIsNoSearchLineAndAnEmptyListSaysThereIsNothingForTheFilter() {
        let data = build(input(filter: .drafts, invoices: [crownInvoice(id: 1)]))

        #expect(data.searchLine == nil)
        #expect(data.rows.isEmpty)
        #expect(data.emptyText == "Pro tento filtr tu nic není.")
    }

    @Test func aListWithRowsNeedsNoEmptyText() {
        #expect(build(input(invoices: [crownInvoice(id: 1)])).emptyText == nil)
    }

    @Test func aQueryOfNothingButSpacesIsNoSearch() {
        let data = build(input(invoices: [crownInvoice(id: 1)], searchText: "   ", matchingIDs: nil))

        #expect(data.searchLine == nil)
        #expect(data.rows.count == 1)
        #expect(data.categoryText == " · všechny stavy")
    }

    @Test func aRowFoundInAFieldTheTableDoesNotShowExplainsWhy() throws {
        var invoice = dollarInvoice(id: 1)
        invoice.note = "Routing number: [ROUTING NUMBER]"

        let data = build(input(invoices: [invoice], searchText: "routing", matchingIDs: [1]))

        let excerpt = try #require(data.rows.first?.excerpt)
        #expect(excerpt.label == "Poznámka")
        #expect(excerpt.text == "Routing number: [ROUTING NUMBER]")
    }

    @Test func aRowFoundInAFieldTheTableShowsNeedsNoExplanation() throws {
        let data = build(input(invoices: [crownInvoice(id: 1)], searchText: "cetus", matchingIDs: [1]))

        #expect(try #require(data.rows.first).excerpt == nil)
    }

    @Test func withoutASearchNoRowHasAnExcerpt() {
        var invoice = dollarInvoice(id: 1)
        invoice.note = "Routing number: [ROUTING NUMBER]"

        #expect(build(input(invoices: [invoice])).rows.allSatisfy { $0.excerpt == nil })
    }

    // MARK: The detail

    @Test func clickingAnInvoiceOpensItAndClickingItAgainClosesIt() {
        #expect(InvoiceListBuilder.toggleDetail(open: nil, clicked: 5) == 5)
        #expect(InvoiceListBuilder.toggleDetail(open: 5, clicked: 5) == nil)
        #expect(InvoiceListBuilder.toggleDetail(open: 5, clicked: 7) == 7)
    }
}
