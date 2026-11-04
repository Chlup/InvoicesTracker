import Foundation
import Testing
@testable import InvoicesTracker

/// The texts and figures of Rozpočet that the builder makes from the net income it divides and the split of the
/// budget: the key figure of each source, the invoice menu, the bill of an invoice, the split bar, the rows of the four
/// categories with their hints, and the note. Today is Saturday 17. 10. 2026 unless a test says otherwise. In every
/// expected string `\u{00A0}` is the no-break space and `−` the minus sign of `CzechFormat`.
struct BudgetBuilderTests {
    // MARK: Helpers

    /// The split of the budget's own tests: Náklady held at 25 000 Kč a month, Úspory at 15 %, Investice at 25 %, and
    /// the rest to Útrata.
    private let sample = BudgetSplit(
        holdings: [
            .costs: .fixed(25_000), .savings: .share(Decimal(string: "0.15")!),
            .investments: .share(Decimal(string: "0.25")!), .spending: .share(0),
        ],
        remainder: .spending)

    /// What the builder is given: the budget of `year` as of `today` (`YYYY-MM-DD`) with `split` and `source`.
    private func input(
        year: Int = 2026, today: String = "2026-10-17", split: BudgetSplit = .empty, source: BudgetSource = .actual,
        invoiceID: Int64? = nil, actual: AverageNetIncome? = nil, prediction: PredictionOutcome? = nil,
        invoices: [BudgetInvoice] = [], typedTexts: [BudgetField: String] = [:],
        refusedFields: Set<BudgetField> = []
    ) -> BudgetInput {
        BudgetInput(
            year: year, today: civilDate(today),
            settings: BudgetSettings(split: split, source: source, invoiceID: invoiceID), actual: actual,
            prediction: prediction, invoices: invoices, typedTexts: typedTexts, refusedFields: refusedFields)
    }

    /// An average net income of `monthlyKc` a month over the months from January through `months`, with nothing due
    /// counted in it: a year whose levies of 500 000 Kč leave `monthlyKc` times `months`.
    private func average(_ monthlyKc: Int64, months: Int = 10) -> AverageNetIncome {
        let yearKc = monthlyKc * Int64(months)
        return AverageNetIncome(
            net: NetIncome(incomeKc: yearKc + 500_000, leviesKc: 500_000, months: months, isWholeYear: months == 12),
            due: nil)
    }

    /// The net of an invoice whose income is `income` haléře with `vat` haléře of DPH received, or expected, on `day`
    /// (`YYYY-MM-DD`), and which adds 750 Kč of tax, 810 Kč of social and 340 Kč of health insurance to the levies.
    private func net(
        of invoice: Invoice, on day: String, income: Int64, vat: Int64, isEstimate: Bool
    ) -> InvoiceNetIncome {
        InvoiceNetIncome(
            effect: ReceiptEffect(
                receipt: Receipt(
                    day: civilDate(day), czkNetHalere: income, czkVatHalere: vat, source: .invoice(invoice.id)),
                tax: 750, social: 810, health: 340, total: 1_900),
            isEstimate: isEstimate, isProvisional: false)
    }

    /// Invoice 20260905 of Alfa Systems s.r.o.: 8,4 hours at 600,00 Kč, 5 040,00 Kč and 1 058,40 Kč of DPH at 21 %,
    /// supplied on 30. 9. 2026 and paid on `paidOn`.
    private func paidInvoice(
        id: Int64 = 5, number: String = "20260905", paidOn: String = "2026-10-05"
    ) -> BudgetInvoice {
        var invoice = Invoice.fixture(
            number: number, duzp: "2026-09-30", dueDate: "2026-10-14", items: [.fixture("8.4", at: 60_000)],
            payment: Payment.fixture(on: paidOn, net: 504_000, vat: 105_840))
        invoice.id = id
        return BudgetInvoice(
            invoice: invoice, net: net(of: invoice, on: paidOn, income: 504_000, vat: 105_840, isEstimate: false))
    }

    /// Invoice `number` of Alfa Systems s.r.o., as `paidInvoice` but issued and supplied on 2. 10. 2026, due on `due`
    /// and not paid: its net is expected on the due day, or today when that has passed.
    private func unpaidInvoice(
        id: Int64 = 6, number: String = "20261002", due: String = "2026-10-30"
    ) -> BudgetInvoice {
        var invoice = Invoice.fixture(
            number: number, duzp: "2026-10-02", dueDate: due, items: [.fixture("8.4", at: 60_000)])
        invoice.id = id
        let expected = max(due, "2026-10-17")
        return BudgetInvoice(
            invoice: invoice, net: net(of: invoice, on: expected, income: 504_000, vat: 105_840, isEstimate: true))
    }

    /// The row of `category`.
    private func row(_ category: BudgetCategory, in data: BudgetData) throws -> BudgetRow {
        try #require(data.rows.first { $0.category == category })
    }

    /// The group of the split bar whose id is `id`.
    private func group(_ id: String, in data: BudgetData) throws -> SplitBarGroup {
        try #require(data.bar.groups.first { $0.id == id })
    }

    // MARK: Skutečnost

    /// Skutečnost divides Přehled's average per month, and the year twelve times it.
    @Test func theActualSourceShowsPřehledsAverageAndTwelveMonthsAYear() throws {
        let data = BudgetBuilder.build(input(actual: average(187_111)))

        #expect(data.source == .actual)
        #expect(data.keyFigure.eyebrow == "Čistý příjem průměrně za měsíc")
        #expect(data.keyFigure.figure == "187\u{00A0}111\u{00A0}Kč")
        #expect(data.keyFigure.sentence == "Průměr za leden–říjen. Za rok počítá dvanáctinásobek.")
        #expect(!data.showsEstimatePill)
        #expect(data.invoicePicker == nil)
        #expect(data.billRows.isEmpty)
        #expect(data.bar.header == "Rozdělení za měsíc")
        #expect(data.cardSubtitle == "Podíly z čistého příjmu, nebo pevné částky · za měsíc a za rok")
        #expect(data.remainderChoices == [.costs, .spending, .savings, .investments])
        #expect(data.remainder == .spending)
        #expect(data.sources.map(\.title) == ["Skutečnost", "Odhad za rok", "Faktura"])
        #expect(data.sources.allSatisfy { $0.isEnabled && $0.help == nil })

        let spending = try row(.spending, in: data)
        #expect(spending.name == "Útrata")
        #expect(spending.purpose == "co můžu utratit")
        #expect(spending.mode == .remainder)
        #expect(spending.amountText == "187\u{00A0}111\u{00A0}Kč")
        #expect(spending.yearText == "za rok 2\u{00A0}245\u{00A0}332\u{00A0}Kč")
        #expect(spending.percentText == "100,0\u{00A0}%")
        #expect(spending.fillFraction == 1)
        #expect(!spending.amountFieldIsEnabled)

        let costs = try row(.costs, in: data)
        #expect(costs.mode == .fixed)
        #expect(costs.amountText == "0")
        #expect(costs.percentText == "0,0\u{00A0}%")
        #expect(costs.yearText == "za rok 0\u{00A0}Kč")
        #expect(costs.amountFieldIsEnabled)
        #expect(costs.fixedToggleAccessibilityLabel == "Náklady: pevná částka v Kč")

        let savings = try row(.savings, in: data)
        #expect(savings.mode == .share)
        #expect(savings.percentText == "0,0")
        #expect(savings.amountText == "0")
        #expect(savings.amountFieldIsEnabled)
        #expect(savings.hint == nil)
        #expect(savings.sliderAccessibilityLabel == "Úspory, podíl z čistého příjmu")
        #expect(savings.percentFieldAccessibilityLabel == "Úspory v procentech")
        #expect(savings.amountFieldAccessibilityLabel == "Úspory v korunách")

        #expect(data.bar.segments.map(\.tone) == BudgetCategory.allCases.map { SplitBarTone.category($0) })
        #expect(data.bar.segments.map(\.weight) == [0, 187_111, 0, 0])
        let spendingGroup = try group("spending", in: data)
        #expect(spendingGroup.value == "187\u{00A0}111\u{00A0}Kč")
        #expect(spendingGroup.popover.subtitle == "zbytek")
        #expect(spendingGroup.popover.note == "Dostane, co zůstane po ostatních kategoriích.")
        #expect(
            spendingGroup.popover.rows == [
                LevyPopoverRow(label: "Podíl z čistého příjmu", value: "100,0\u{00A0}%", style: .strong),
                LevyPopoverRow(label: "Za měsíc", value: "187\u{00A0}111\u{00A0}Kč", style: .muted),
                LevyPopoverRow(label: "Za rok", value: "2\u{00A0}245\u{00A0}332\u{00A0}Kč", style: .muted),
            ])
        #expect(try group("costs", in: data).popover.note == "Částka je pevná, podíl se dopočítá z čistého příjmu.")
        #expect(try group("savings", in: data).popover.subtitle == "podílem")
    }

    /// With the unpaid invoices due this month counted, the average is Přehled's estimate, with its sign and its words;
    /// the day that ends the words ends the sentence with its own dot.
    @Test func theDueVariantCarriesTheSignAndItsWords() throws {
        let year = TaxEngineRegressionTests.sampleYear2026
        let today = civilDate("2026-10-17")
        var counted = year
        counted.receipts.append(
            Receipt(day: today, czkNetHalere: 5_000_000, czkVatHalere: 1_050_000, source: .synthetic))
        let due = DueNetIncome(result: TaxEngine.compute(counted, asOf: today), dueThrough: civilDate("2026-10-31"))
        let actual = AverageNetIncome(net: NetIncome(TaxEngine.compute(year, asOf: today)), due: due)

        let data = BudgetBuilder.build(input(actual: actual))

        #expect(data.keyFigure.figure == "≈\u{00A0}190\u{00A0}220\u{00A0}Kč")
        #expect(
            data.keyFigure.sentence
                == "Průměr za leden–říjen, včetně nezaplacených faktur splatných do 31.\u{00A0}10. Za rok počítá"
                + " dvanáctinásobek.")
        #expect(BudgetBuilder.net(of: input(actual: actual)) == 190_220)
        #expect(try row(.spending, in: data).amountText == "190\u{00A0}220\u{00A0}Kč")
    }

    /// A past year's average is the whole year's, the estimate of a year that is over is the actual year, and a saved
    /// Odhad shows Skutečnost.
    @Test func aPastYearAverageIsTheWholeYear() throws {
        let past = input(year: 2025, source: .prediction, actual: average(150_000, months: 12))

        let data = BudgetBuilder.build(past)

        #expect(BudgetBuilder.source(of: past) == .actual)
        #expect(data.source == .actual)
        #expect(data.keyFigure.sentence == "Průměr za celý rok 2025.")
        #expect(data.keyFigure.figure == "150\u{00A0}000\u{00A0}Kč")
        #expect(!data.showsEstimatePill)
        let prediction = try #require(data.sources.first { $0.value == .prediction })
        #expect(prediction.title == "Odhad za rok")
        #expect(!prediction.isEnabled)
        #expect(prediction.help == "Za minulý rok je odhad stejný jako skutečnost.")
        #expect(data.sources.filter { $0.value != .prediction }.allSatisfy { $0.isEnabled })
    }

    // MARK: Odhad za rok

    /// Odhad za rok divides the predicted net income of the whole year: a twelfth of it a month, all of it a year.
    @Test func thePredictionShowsItsYearAndTheEstimatePill() throws {
        let outcome = try PredictionSample.outcome(year: 2026)
        try #require(outcome.prediction.isComplete)
        let net = NetIncome(outcome.result)
        let budget = input(source: .prediction, prediction: outcome)

        let data = BudgetBuilder.build(budget)

        #expect(data.source == .prediction)
        #expect(data.keyFigure.eyebrow == "Čistý příjem průměrně za měsíc")
        #expect(data.keyFigure.figure == CzechFormat.wholeKc(net.monthlyKc))
        #expect(!data.keyFigure.figure.contains("≈"))
        #expect(data.showsEstimatePill)
        #expect(
            data.keyFigure.sentence
                == "Odhad za celý rok 2026 z faktur do 17.\u{00A0}10. a toho, co ještě do 31.\u{00A0}12. přijde,"
                + " stejně jako v Odhadu odvodů. Po odvodech \(CzechFormat.wholeKc(net.yearKc)) za rok.")
        #expect(BudgetBuilder.net(of: budget) == net.monthlyKc)
        let spending = try row(.spending, in: data)
        #expect(spending.amountText == CzechFormat.wholeKc(net.monthlyKc))
        #expect(spending.yearText == "za rok " + CzechFormat.wholeKc(net.yearKc))
    }

    /// An incomplete prediction has nothing to divide: no figure, no amounts, but the shares stay as they are.
    @Test func anIncompletePredictionDividesNothing() throws {
        var prediction = PredictionSample.input(year: 2026)
        prediction.averageRates = [:]
        let waitingClient = Client(id: 4, name: "Čekající", dueDays: 14)
        var waiting = Invoice.fixture(
            number: "WAITING-1", issued: "2026-10-01", duzp: "2026-10-01", dueDate: "2026-10-15",
            items: [.fixture("1", at: 1_000_000)])
        waiting.clientID = waitingClient.id
        prediction.clients.append(waitingClient)
        prediction.invoices.append(waiting)
        let outcome = try PredictionSample.outcome(of: prediction)
        try #require(!outcome.prediction.isComplete)
        let budget = input(split: sample, source: .prediction, prediction: outcome)

        let data = BudgetBuilder.build(budget)

        #expect(BudgetBuilder.net(of: budget) == nil)
        #expect(data.keyFigure.figure == "—")
        #expect(data.keyFigure.sentence == PredictionBuilder.incompleteText)
        #expect(data.showsEstimatePill)
        #expect(data.bar.segments.allSatisfy { $0.weight == 0 })
        #expect(data.bar.groups.allSatisfy { $0.value == "—" })
        for category in [BudgetCategory.spending, .savings, .investments] {
            let row = try row(category, in: data)
            #expect(row.amountText == "—")
            #expect(row.yearText == "za rok —")
        }
        let savings = try row(.savings, in: data)
        #expect(savings.percentText == "15,0")
        #expect(abs(savings.fillFraction - 0.15) < 0.000_001)
        #expect(abs(savings.limitFraction - 0.75) < 0.000_001)
        #expect(savings.showsStop)
        #expect(!savings.amountFieldIsEnabled)
        #expect(try row(.investments, in: data).percentText == "25,0")
        let costs = try row(.costs, in: data)
        #expect(costs.amountText == "25\u{00A0}000")
        #expect(costs.amountFieldIsEnabled)
        #expect(costs.percentText == "—")
        #expect(try row(.spending, in: data).percentText == "—")
    }

    // MARK: Faktura

    /// A paid invoice with DPH: the DPH and the levies come off the top, and the rest is divided.
    @Test func aPaidInvoiceWithVATTakesDPHAndLeviesOffTheTop() throws {
        let invoice = paidInvoice()
        let budget = input(source: .invoice, invoices: [invoice])

        let data = BudgetBuilder.build(budget)

        #expect(data.source == .invoice)
        #expect(BudgetBuilder.net(of: budget) == 3_140)
        #expect(data.keyFigure.eyebrow == "Přišlo z faktury 20260905")
        #expect(data.keyFigure.figure == "6\u{00A0}098\u{00A0}Kč")
        #expect(
            data.keyFigure.sentence
                == "Alfa Systems s.r.o. · peníze přišly 5.\u{00A0}10., včetně DPH. DPH a odvody z této platby spočítá"
                + " aplikace, zbytek se rozdělí podle kategorií.")
        #expect(!data.showsEstimatePill)
        #expect(data.bar.header == "Kam peníze z faktury poslat")
        #expect(data.cardSubtitle == "Podíly z toho, co po odvodech zbude, nebo pevné částky")

        #expect(
            data.billRows == [
                BudgetBillRow(
                    sign: "", label: "Přišlo z faktury", note: "20260905 · Alfa Systems s.r.o. · včetně DPH",
                    value: "6\u{00A0}098\u{00A0}Kč", share: nil, isLocked: false, isResult: false),
                BudgetBillRow(
                    sign: "−", label: "DPH",
                    note: "21\u{00A0}% z 5\u{00A0}040\u{00A0}Kč · za září, odvádí se do 26.\u{00A0}10.\u{00A0}2026",
                    value: "−1\u{00A0}058\u{00A0}Kč", share: nil, isLocked: true, isResult: false),
                BudgetBillRow(
                    sign: "−", label: "Daně a odvody", note: "daň 750 · sociální 810 · zdravotní 340",
                    value: "−1\u{00A0}900\u{00A0}Kč", share: "37,7\u{00A0}% z příjmu bez DPH", isLocked: true,
                    isResult: false),
                BudgetBillRow(
                    sign: "=", label: "Čistý příjem k rozdělení", note: nil, value: "3\u{00A0}140\u{00A0}Kč",
                    share: nil, isLocked: false, isResult: true),
            ])

        #expect(
            data.bar.segments.map(\.tone) == [
                .vat, .authority(.tax), .authority(.social), .authority(.health), .category(.costs),
                .category(.spending), .category(.savings), .category(.investments),
            ])
        #expect(data.bar.segments.map(\.weight).reduce(0, +) == 6_098)
        #expect(data.bar.groups.map(\.shortTitle) == ["DPH", "Odvody", "Náklady", "Útrata", "Úspory", "Investice"])
        let vat = try group("vat", in: data)
        #expect(vat.value == "1\u{00A0}058\u{00A0}Kč")
        #expect(vat.popover.title == "DPH")
        #expect(vat.popover.subtitle == "finanční úřad")
        #expect(
            vat.popover.rows == [
                LevyPopoverRow(label: "Sazba", value: "21\u{00A0}%", style: .muted),
                LevyPopoverRow(label: "Základ", value: "5\u{00A0}040\u{00A0}Kč", style: .muted),
                LevyPopoverRow(label: "DPH", value: "1\u{00A0}058\u{00A0}Kč", style: .strong),
            ])
        #expect(vat.popover.note == "Za září, odvádí se s přiznáním k DPH do 26.\u{00A0}10.\u{00A0}2026.")
        let levies = try group("levies", in: data)
        #expect(levies.dots == [.authority(.tax), .authority(.social), .authority(.health)])
        #expect(levies.popover.title == "Daně a odvody")
        #expect(levies.popover.subtitle == "spočítá aplikace")
        #expect(
            levies.popover.rows == [
                LevyPopoverRow(label: "Daň z příjmů", value: "750\u{00A0}Kč", style: .muted),
                LevyPopoverRow(label: "Sociální pojištění", value: "810\u{00A0}Kč", style: .muted),
                LevyPopoverRow(label: "Zdravotní pojištění", value: "340\u{00A0}Kč", style: .muted),
                LevyPopoverRow(label: "Celkem", value: "1\u{00A0}900\u{00A0}Kč", style: .strong),
            ])
        #expect(
            levies.popover.note
                == "O tolik platba zvýší odvody za rok 2026, stejně jako Dopad na odvody v detailu faktury.")
        #expect(
            try group("spending", in: data).popover.rows.map(\.label) == ["Podíl z čistého příjmu", "Z faktury"])

        let spending = try row(.spending, in: data)
        #expect(spending.amountText == "3\u{00A0}140\u{00A0}Kč")
        #expect(spending.yearText == nil)

        let picker = try #require(data.invoicePicker)
        #expect(picker.number == "20260905")
        #expect(picker.client == "Alfa Systems s.r.o.")
        #expect(picker.menuTitle == "Faktury roku 2026")
        #expect(
            picker.items == [
                BudgetInvoiceItem(
                    id: 5, number: "20260905", client: "Alfa Systems s.r.o.", status: "peníze přišly 5.\u{00A0}10.",
                    statusTone: .received, amount: "6\u{00A0}098\u{00A0}Kč", isChosen: true)
            ])
    }

    /// An unpaid invoice is worked out as if its money came on the day it is due, and says it is an estimate.
    @Test func anUnpaidInvoiceIsAnEstimateAsIfPaidWhenDue() throws {
        let data = BudgetBuilder.build(input(source: .invoice, invoices: [unpaidInvoice()]))

        #expect(data.keyFigure.eyebrow == "Přijde z faktury 20261002")
        #expect(data.keyFigure.figure == "6\u{00A0}098\u{00A0}Kč")
        #expect(data.showsEstimatePill)
        #expect(
            data.keyFigure.sentence
                == "Alfa Systems s.r.o. · zatím nezaplacená, splatná 30.\u{00A0}10. Částka i odvody jsou odhad, jako by"
                + " peníze přišly 30.\u{00A0}10.; po zaplacení se spočítají přesně.")
        #expect(data.billRows.first?.label == "Přijde z faktury")
        let item = try #require(data.invoicePicker?.items.first)
        #expect(item.status == "čeká na platbu · splatná 30.\u{00A0}10.")
        #expect(item.statusTone == .awaiting)
        #expect(item.amount == "≈\u{00A0}6\u{00A0}098\u{00A0}Kč")
    }

    /// The menu lists every invoice with its status; the saved one is chosen while it is listed, otherwise the one
    /// paid last, and the first when none is paid.
    @Test func theSavedInvoiceIsChosenElseTheLatestPaidElseTheFirst() throws {
        let invoices = [
            unpaidInvoice(id: 8, number: "20261003"), unpaidInvoice(id: 7, number: "20261001", due: "2026-10-10"),
            paidInvoice(id: 6, number: "20260906", paidOn: "2026-10-08"), paidInvoice(),
        ]

        let fallback = input(source: .invoice, invoiceID: 99, invoices: invoices)
        #expect(BudgetBuilder.chosenInvoice(in: fallback)?.invoice.id == 6)
        #expect(BudgetBuilder.chosenInvoice(in: input(source: .invoice, invoices: invoices))?.invoice.id == 6)
        let saved = input(source: .invoice, invoiceID: 7, invoices: invoices)
        #expect(BudgetBuilder.chosenInvoice(in: saved)?.invoice.id == 7)
        let unpaid = input(source: .invoice, invoices: Array(invoices.prefix(2)))
        #expect(BudgetBuilder.chosenInvoice(in: unpaid)?.invoice.id == 8)

        let items = try #require(BudgetBuilder.build(saved).invoicePicker).items
        #expect(items.map(\.id) == [8, 7, 6, 5])
        #expect(items.map(\.isChosen) == [false, true, false, false])
        #expect(items[1].status == "po splatnosti od 10.\u{00A0}10.")
        #expect(items[1].statusTone == .overdue)
        #expect(items[2].status == "peníze přišly 8.\u{00A0}10.")
        #expect(items[1].title == "20261001 · Alfa Systems s.r.o.")
    }

    /// No invoice in the year: nothing to choose and nothing to divide.
    @Test func noInvoiceInTheYear() throws {
        let budget = input(source: .invoice)

        let data = BudgetBuilder.build(budget)

        #expect(data.invoicePicker == nil)
        #expect(BudgetBuilder.net(of: budget) == nil)
        #expect(data.keyFigure.figure == "—")
        #expect(data.keyFigure.sentence == "V roce 2026 zatím není vystavená žádná faktura.")
        #expect(data.billRows.isEmpty)
        #expect(try row(.spending, in: data).amountText == "—")
    }

    // MARK: Rows and hints

    /// Fixed amounts beyond what the invoice leaves make the remainder negative, in red, with the hint how much is
    /// missing.
    @Test func aShortfallIsRedWithItsHint() throws {
        let split = sample.settingAmount(32_500, of: .costs, net: 3_140)

        let data = BudgetBuilder.build(input(split: split, source: .invoice, invoices: [paidInvoice()]))

        let spending = try row(.spending, in: data)
        #expect(spending.amountText == "−30\u{00A0}616\u{00A0}Kč")
        #expect(spending.amountIsNegative)
        #expect(spending.percentText == "—")
        #expect(spending.fillFraction == 0)
        #expect(
            spending.hint
                == BudgetHint(
                    text: "Nestačí to: pevné částky a podíly jsou o 30\u{00A0}616\u{00A0}Kč víc, než je k rozdělení"
                        + " z této faktury.",
                    tone: .error))
        #expect(try row(.costs, in: data).percentText == "nad 100\u{00A0}%")
        #expect(try row(.costs, in: data).fillFraction == 1)
        let spendingGroup = try group("spending", in: data)
        #expect(spendingGroup.valueIsNegative)
        #expect(spendingGroup.value == "−30\u{00A0}616\u{00A0}Kč")
        #expect(data.bar.segments.first { $0.tone == .category(.spending) }?.weight == 0)
    }

    /// A share typed above what the remainder leaves keeps the text typed, and the hint says the most it can be.
    @Test func aTypedShareAboveTheLimitKeepsTheTextAndSaysTheLimit() throws {
        let split = sample.settingAmount(30_000, of: .savings, net: 190_037)
            .settingShare(Decimal(string: "0.8")!, of: .investments, net: 190_037)

        let data = BudgetBuilder.build(
            input(split: split, actual: average(190_037), typedTexts: [.percent(.investments): "80"]))

        let investments = try row(.investments, in: data)
        #expect(investments.percentText == "80")
        #expect(investments.amountText == "135\u{00A0}037")
        #expect(
            investments.hint
                == BudgetHint(
                    text: "Víc se nevejde: na zbytek (Útrata) už nic nezbývá. Nejvýš 71,1\u{00A0}%"
                        + " (135\u{00A0}037\u{00A0}Kč).",
                    tone: .attention))
        #expect(investments.showsStop)
        #expect(abs(investments.limitFraction - 135_037.0 / 190_037.0) < 0.000_001)
        #expect(try row(.spending, in: data).amountText == "0\u{00A0}Kč")
        #expect(try row(.savings, in: data).hint == nil)
    }

    /// A typed text that the model refused stays in its field, and the hint says what the field takes.
    @Test func aRefusedFieldKeepsItsTextAndSaysWhy() throws {
        let data = BudgetBuilder.build(
            input(
                actual: average(187_111), typedTexts: [.amount(.savings): "abc"],
                refusedFields: [.amount(.savings)]))

        let savings = try row(.savings, in: data)
        #expect(savings.amountText == "abc")
        #expect(savings.hint == BudgetHint(text: "Zadejte částku v celých korunách.", tone: .attention))

        let percent = BudgetBuilder.build(
            input(
                actual: average(187_111), typedTexts: [.percent(.savings): "1,25"],
                refusedFields: [.percent(.savings)]))
        #expect(try row(.savings, in: percent).percentText == "1,25")
        #expect(
            try row(.savings, in: percent).hint
                == BudgetHint(text: "Zadejte procenta, nejvýš s jedním desetinným místem.", tone: .attention))
    }

    // MARK: The note

    /// The note names the other three in the accusative, the remainder, and in Faktura mode who works out DPH and the
    /// levies.
    @Test func theNoteNamesTheOtherThreeAndTheRemainder() throws {
        let actual = BudgetBuilder.build(input(actual: average(187_111)))
        #expect(
            actual.note
                == "Když změníte Náklady, Úspory nebo Investice, změní se jen zbytek – teď je to Útrata. Co jste"
                + " nastavili, se samo nepohne. Kategorie s pevnou částkou má stejnou částku v Kč pro skutečnost,"
                + " odhad i každou fakturu a dopočítá se jí jen podíl; ostatní drží svůj podíl. Rozdělení se ukládá.")

        let costs = BudgetSplit.empty.withRemainder(.costs, net: 187_111)
        let toCosts = BudgetBuilder.build(input(split: costs, actual: average(187_111)))
        #expect(toCosts.note.hasPrefix("Když změníte Útratu, Úspory nebo Investice, změní se jen zbytek – teď je to"
            + " Náklady."))
        #expect(toCosts.remainder == .costs)

        let invoice = BudgetBuilder.build(input(source: .invoice, invoices: [paidInvoice()]))
        #expect(
            invoice.note.hasSuffix(
                "Rozdělení se ukládá. DPH a odvody z faktury spočítá aplikace (odvody stejně jako Dopad na odvody v"
                    + " detailu faktury) a měnit nejdou."))

        var withoutVAT = paidInvoice()
        withoutVAT.invoice.vatMode = .outsideCountry
        withoutVAT.net = net(of: withoutVAT.invoice, on: "2026-10-05", income: 504_000, vat: 0, isEstimate: false)
        let plain = BudgetBuilder.build(input(source: .invoice, invoices: [withoutVAT]))
        #expect(
            plain.note.hasSuffix(
                "Rozdělení se ukládá. Odvody z faktury spočítá aplikace stejně jako Dopad na odvody v detailu faktury"
                    + " a měnit nejdou."))
        #expect(plain.billRows.map(\.label) == ["Přišlo z faktury", "Daně a odvody", "Čistý příjem k rozdělení"])
        #expect(plain.billRows[1].share == "37,7\u{00A0}% z faktury")
        #expect(plain.billRows[0].note == "20260905 · Alfa Systems s.r.o.")
        #expect(
            plain.keyFigure.sentence
                == "Alfa Systems s.r.o. · peníze přišly 5.\u{00A0}10. Odvody z této platby spočítá aplikace, zbytek se"
                + " rozdělí podle kategorií.")
    }

    // MARK: A negative average

    /// An average below zero is shown as it is but leaves nothing to divide: the shares come to 0 Kč, and a fixed
    /// amount makes the remainder negative.
    @Test func aNegativeAverageDividesNothingAndFixedAmountsShowAShortfall() throws {
        let split = BudgetSplit.empty.settingAmount(1_000, of: .costs, net: nil)
        let budget = input(split: split, actual: average(-12_345))

        let data = BudgetBuilder.build(budget)

        #expect(data.keyFigure.figure == "−12\u{00A0}345\u{00A0}Kč")
        #expect(BudgetBuilder.net(of: budget) == 0)
        let savings = try row(.savings, in: data)
        #expect(savings.amountText == "0")
        #expect(!savings.amountFieldIsEnabled)
        #expect(try group("savings", in: data).value == "0\u{00A0}Kč")
        let spending = try row(.spending, in: data)
        #expect(spending.amountText == "−1\u{00A0}000\u{00A0}Kč")
        #expect(spending.amountIsNegative)
        #expect(
            spending.hint
                == BudgetHint(
                    text: "Nestačí to: pevné částky a podíly jsou o 1\u{00A0}000\u{00A0}Kč víc, než je k rozdělení.",
                    tone: .error))
        #expect(try row(.costs, in: data).amountFieldIsEnabled)
    }
}
