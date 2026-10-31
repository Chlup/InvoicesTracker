import Foundation
import Testing
@testable import InvoicesTracker

/// The page of Odhad odvodů that the builder makes from a prediction and its levies: every text of the result card
/// and of the card Příjmy, the banner, the months of each client and the two columns of the breakdown. The data is the
/// prediction sample as of Saturday 17. 10. 2026, and its closed years 2025 and 2024; the incomes and the levies are
/// those of `PredictionGoldenTests`. Below the income line the figures are the engine's own, which rounds the income
/// to whole crowns first: the profit of 2026 is 1 543 157 Kč and the base of the health insurance 771 578,50 Kč. The
/// years the engine has no rules for, 2021 and 2027, take the settings of the sample's 2024 and 2026. In every
/// expected string `\u{A0}` is the no-break space.
struct PredictionBuilderTests {
    // MARK: Helpers

    private let foxtrot = PredictionSample.foxtrot.id
    private let tango = PredictionSample.tango.id
    private let sierra = PredictionSample.sierra.id

    /// The outcome of `input`, with the settings, the deductions, the advances and the family of its year in the
    /// sample, and the receipts of the input.
    private func outcome(of input: PredictionInput) throws -> PredictionOutcome {
        var yearInput = PredictionSample.yearInput(year: input.year)
        yearInput.receipts = input.receipts
        return try PredictionOutcome.make(prediction: IncomePrediction.make(input), yearInput: yearInput)
    }

    private func makePage(of input: PredictionInput) throws -> PredictionPage {
        PredictionBuilder.page(try outcome(of: input))
    }

    /// The page of the sample's `year` as of `today`, with the person's `changes`.
    private func makePage(
        year: Int = 2026, today: CivilDate = PredictionSample.sampleToday, changes: [Int64: [Int: Bool]] = [:]
    ) throws -> PredictionPage {
        try makePage(of: PredictionSample.input(year: year, today: today, changes: changes))
    }

    /// The sample's 2026 without its clients, invoices, templates and receipts, and with only `clients`.
    private func inputWithout(
        clients: [Client] = [], invoices: [Invoice] = [], templates: [InvoiceTemplate] = []
    ) -> PredictionInput {
        var input = PredictionSample.input(year: 2026)
        input.clients = clients
        input.invoices = invoices
        input.templates = templates
        input.receipts = PredictionSample.receipts(of: invoices, year: 2026)
        return input
    }

    /// The outcome of 2021, a year over that the engine has no rules for, as of the sample's today: three payments of
    /// 100 000 Kč and no client, invoice or template, and the settings, the deductions and the family of the sample's
    /// 2024, with its advances or, when given, `advances`.
    private func outcomeOf2021(advances: AdvancePlan? = nil) throws -> PredictionOutcome {
        let payments = ["2021-03-15", "2021-06-15", "2021-09-15"].map { day in
            Receipt(day: civilDate(day), czkNetHalere: 10_000_000, czkVatHalere: 0, source: .synthetic)
        }
        var yearInput = PredictionSample.yearInput(year: 2024)
        yearInput.year = 2021
        yearInput.receipts = payments
        if let advances {
            yearInput.advances = advances
        }
        var input = PredictionSample.input(year: 2021)
        input.clients = []
        input.invoices = []
        input.templates = []
        input.receipts = payments
        return try PredictionOutcome.make(prediction: IncomePrediction.make(input), yearInput: yearInput)
    }

    /// The outcome of 2027 on 15. 1. 2027, a year in progress that the engine has no rules for: the settings, the
    /// deductions, the advances and the family of the sample's 2026, and the prediction of the sample's 2027.
    private func outcomeOf2027() throws -> PredictionOutcome {
        let input = PredictionSample.input(year: 2027, today: civilDate("2027-01-15"))
        var yearInput = PredictionSample.yearInput(year: 2026)
        yearInput.year = 2027
        return try PredictionOutcome.make(prediction: IncomePrediction.make(input), yearInput: yearInput)
    }

    /// The outcome of `input` as `outcome(of:)` makes it, but with the advances that `change` makes of the plan of the
    /// year.
    private func outcomeWithChangedAdvances(
        of input: PredictionInput, _ change: (inout AdvancePlan) -> Void
    ) throws -> PredictionOutcome {
        var yearInput = PredictionSample.yearInput(year: input.year)
        yearInput.receipts = input.receipts
        change(&yearInput.advances)
        return try PredictionOutcome.make(prediction: IncomePrediction.make(input), yearInput: yearInput)
    }

    /// The sample's 2026 without its clients, invoices and templates but one client with one invoice, paid on
    /// 10. 3. 2026 with 200 000 Kč: the tax of the year is below zero, a bonus.
    private func inputWithOnePaymentThatLeavesTheTaxAsABonus() -> PredictionInput {
        let client = Client(id: 1, name: "Jediný s.r.o.", dueDays: 14)
        var invoice = Invoice.fixture(
            number: "20260301", issued: "2026-03-01", duzp: "2026-03-01", dueDate: "2026-03-15",
            items: [.fixture("1", at: 20_000_000)],
            payment: Payment.fixture(on: "2026-03-10", net: 20_000_000, vat: 0))
        invoice.id = 1
        invoice.clientID = client.id
        return inputWithout(clients: [client], invoices: [invoice])
    }

    /// The sample's 2026 without its clients, invoices and templates but one client with one invoice, paid on
    /// 10. 3. 2026 with 10 000 Kč: the income is far less than the minimum insurance of the year, and too small for the
    /// children's benefit to be paid as a tax bonus.
    private func inputWithOneSmallPayment() -> PredictionInput {
        let client = Client(id: 1, name: "Jediný s.r.o.", dueDays: 14)
        var invoice = Invoice.fixture(
            number: "20260301", issued: "2026-03-01", duzp: "2026-03-01", dueDate: "2026-03-15",
            items: [.fixture("1", at: 1_000_000)],
            payment: Payment.fixture(on: "2026-03-10", net: 1_000_000, vat: 0))
        invoice.id = 1
        invoice.clientID = client.id
        return inputWithout(clients: [client], invoices: [invoice])
    }

    private func row(_ id: Int64, in page: PredictionPage) throws -> PredictionClientRow {
        try #require((page.activeRows + page.otherRows).first { $0.id == id }, "No row of client \(id)")
    }

    private func section(_ title: String, in page: PredictionPage) throws -> ComputationSection {
        try #require((page.left + page.right).first { $0.title == title }, "No section \(title)")
    }

    private func row(_ label: String, in section: ComputationSection) throws -> ComputationRow {
        try #require(section.rows.first { $0.label == label }, "No row \(label) in \(section.title)")
    }

    /// The number a shown value is, in hundredths: "−1 200 000,00" is −120 000 000, "247 832" is 24 783 200 and
    /// "68 786 Kč" is 6 878 600.
    private func hundredths(_ shown: String) -> Int64 {
        let number = shown.replacingOccurrences(of: "\u{2212}", with: "-").filter { "0123456789,-".contains($0) }
        let isNegative = number.hasPrefix("-")
        let parts = number.dropFirst(isNegative ? 1 : 0).split(separator: ",", omittingEmptySubsequences: false)
        let fraction = parts.count > 1 ? Int64(parts[1]) ?? 0 : 0
        return ((Int64(parts[0]) ?? 0) * 100 + fraction) * (isNegative ? -1 : 1)
    }

    /// A cell as `label|value|sub`.
    private func described(_ cells: [PredictionCell]) -> [String] {
        cells.map { "\($0.label)|\($0.value)|\($0.sub)" }
    }

    /// Every text of the result card: the key figure, the bar of the levies with its popovers and the figure of what
    /// is left to settle.
    private func resultTexts(of page: PredictionPage) -> [String] {
        var texts = [page.keyFigure.eyebrow, page.keyFigure.figure]
        texts += [page.keyFigure.share, page.keyFigure.sentence].compactMap { $0 }
        texts += [page.levyBar.header, page.levyBar.accessibilityLabel]
        texts += [page.levyBar.total, page.levyBar.totalShare].compactMap { $0 }
        for part in page.levyBar.parts {
            texts += [part.legendValue, part.accessibilityLabel]
            texts += part.rows.flatMap { [$0.label, $0.value] }
            texts += [part.shareLine, part.note].compactMap { $0 }
        }
        texts += [page.due.eyebrow, page.due.figure]
        texts += [page.due.share, page.due.sentence].compactMap { $0 }
        return texts
    }

    /// Every text of the card Příjmy: its subtitle, the income and the net income with their notes, the parts of the
    /// income and the note of the money of next year.
    private func incomeTexts(of page: PredictionPage) -> [String] {
        var texts = [page.incomeSub, page.incomeNote, page.incomeHead, page.incomeTotal]
        texts += [page.netIncome.label, page.netIncome.amount, page.netIncome.sub]
        texts += page.parts.flatMap { [$0.text, $0.value] }
        return texts + [page.nextYearNote].compactMap { $0 }
    }

    /// Every text the page shows, for the checks that go through all of them.
    private func texts(of page: PredictionPage) -> [String] {
        var texts = resultTexts(of: page) + incomeTexts(of: page)
        texts += [page.banner, page.monthsHead, page.monthsSub, page.othersTitle, page.othersSub]
        texts += [page.noActiveText].compactMap { $0 }
        texts += page.legend.map(\.text)
        for row in page.activeRows + page.otherRows {
            texts += [row.name, row.how, row.adds] + [row.note].compactMap { $0 }
            texts += row.cells.flatMap { [$0.label, $0.value, $0.sub, $0.accessibilityLabel] }
        }
        for section in page.left + page.right {
            texts += [section.title] + [section.tag].compactMap { $0 }
            texts += section.rows.flatMap { [$0.label, $0.value] + [$0.note].compactMap { $0 } }
        }
        return texts
    }

    /// The texts of `texts` with an approximation sign that no no-break space follows.
    private func approximationsWithoutNoBreakSpace(in texts: [String]) -> [String] {
        texts.filter { text in
            text.indices.contains { index in
                text[index] == "≈" && !text[text.index(after: index)...].hasPrefix("\u{A0}")
            }
        }
    }

    // MARK: The result card

    /// 466 782 Kč of tax and insurance (114 786 + 247 832 + 104 164) from an income of 2 743 157 Kč, which is 17,0 % of
    /// it. The advances of the year are 268 080 Kč, so 198 702 Kč are owed with the returns beyond them; the three
    /// authorities are owed 68 786, 97 272 and 32 644 Kč of that, and nothing is overpaid at any of them. The key
    /// figure has no sign of an estimate: its eyebrow says "Odhad". The levy bar has no total, as the figure beside it
    /// is the total.
    @Test func theResultCardSaysTheSampleYear() throws {
        let page = try makePage()

        #expect(
            page.keyFigure
                == KeyFigureData(
                    eyebrow: "Odhad odvodů za celý rok 2026", figure: "466\u{A0}782\u{A0}Kč",
                    share: "17,0\u{A0}% z příjmů",
                    sentence: "Odvody z odhadovaného příjmu 2\u{A0}743\u{A0}157\u{A0}Kč za celý rok 2026"
                        + " – s odpočty a slevami ze Záloh a odpočtů a s minimálním pojistným za celý rok."))
        #expect(page.levyBar.header == "Odvody za celý rok 2026 podle úřadů")
        #expect(page.levyBar.total == nil)
        #expect(page.levyBar.totalShare == nil)
        #expect(page.levyBar.parts.map(\.authority) == [.tax, .social, .health])
        #expect(page.levyBar.parts.map(\.weight) == [114_786, 247_832, 104_164])
        #expect(
            page.levyBar.parts.map(\.legendValue) == [
                "114\u{A0}786\u{A0}Kč", "247\u{A0}832\u{A0}Kč", "104\u{A0}164\u{A0}Kč",
            ])
        #expect(
            page.levyBar.accessibilityLabel
                == "Odvody za celý rok 2026 podle úřadů: Daň z příjmů 114\u{A0}786\u{A0}Kč,"
                + " Sociální pojištění 247\u{A0}832\u{A0}Kč, Zdravotní pojištění 104\u{A0}164\u{A0}Kč")
        #expect(
            page.due
                == KeyFigureData(
                    eyebrow: "Odhad doplatku odvodů bez záloh", figure: "198\u{A0}702\u{A0}Kč",
                    sentence: "Tolik si odložte stranou – navíc k zálohám 268\u{A0}080\u{A0}Kč, které platíte průběžně."
                        + " Platí se po skončení roku s přiznáním a přehledy pro ČSSZ a VZP.",
                    sentenceEmphasis: "268\u{A0}080\u{A0}Kč"))
        // The advances are never broken across lines.
        #expect(try #require(page.due.sentenceEmphasis).allSatisfy { $0 != " " })
    }

    /// The popover of each authority has three rows in the words of a whole year: what the year's levy is, the advances
    /// of all twelve months, and what is left to pay, with the share of the income in a line under them. The tax is
    /// owed 68 786 Kč beyond its 46 000 Kč of advances, the social insurance 97 272 Kč beyond 150 560 Kč, and the
    /// health insurance 32 644 Kč beyond 71 520 Kč. The shares of the income, 4,2, 9,0 and 3,8 %, add up to the 17,0 %
    /// beside the key figure.
    @Test func theLevyBarGivesEachAuthorityItsYearItsAdvancesAndWhatIsLeft() throws {
        let page = try makePage()
        let rows = page.levyBar.parts.map { part in part.rows.map { [$0.label, $0.value] } }

        #expect(
            rows == [
                [["Odvody za rok", "114\u{A0}786\u{A0}Kč"], ["Zálohy za rok", "46\u{A0}000\u{A0}Kč"],
                    ["Doplatek", "68\u{A0}786\u{A0}Kč"]],
                [["Odvody za rok", "247\u{A0}832\u{A0}Kč"], ["Zálohy za rok", "150\u{A0}560\u{A0}Kč"],
                    ["Doplatek", "97\u{A0}272\u{A0}Kč"]],
                [["Odvody za rok", "104\u{A0}164\u{A0}Kč"], ["Zálohy za rok", "71\u{A0}520\u{A0}Kč"],
                    ["Doplatek", "32\u{A0}644\u{A0}Kč"]],
            ])
        #expect(page.levyBar.parts.allSatisfy { $0.rows.map(\.style) == [.strong, .muted, .strong] })
        #expect(
            page.levyBar.parts.map(\.shareLine) == [
                "4,2\u{A0}% z příjmů bez DPH", "9,0\u{A0}% z příjmů bez DPH", "3,8\u{A0}% z příjmů bez DPH",
            ])
        #expect(
            page.levyBar.parts[0].accessibilityLabel
                == "Daň z příjmů: odvody za rok 114\u{A0}786\u{A0}Kč, zálohy za rok 46\u{A0}000\u{A0}Kč,"
                + " doplatek 68\u{A0}786\u{A0}Kč, 4,2\u{A0}% z příjmů bez DPH")
        // The doplatky of the three add up to what is left to settle.
        let owed = page.levyBar.parts.map { hundredths($0.rows[2].value) }.reduce(0, +)
        #expect(owed == hundredths(page.due.figure))
    }

    /// The card Příjmy has its subtitle, the head, total and note of the income, and the parts of the income for the
    /// bar: 2 191 771 Kč received, nothing issued and unpaid, and 551 386 Kč expected, with the 290 193 Kč that are
    /// paid only in the next year. The income less the levies leaves 2 276 375 Kč, which is 83,0 % of the income and
    /// over the twelve months 189 698 Kč a month (189 697,92 rounded half up); the caption says that it is an
    /// estimate, and the figures have no sign. Nothing in the card has the sign of an estimate, as the whole card is
    /// one.
    @Test func theCardPrijmySaysTheIncomeAndTheNetIncomeOfTheSampleYear() throws {
        let page = try makePage()

        #expect(page.incomeSub == "Odhad za celý rok 2026 z faktur do 17.\u{A0}10.\u{A0}2026")
        #expect(page.incomeNote == "bez DPH · peníze přijaté do 31.\u{A0}12.")
        #expect(page.incomeHead == "Příjmy za rok 2026 (odhad)")
        #expect(page.incomeTotal == "2\u{A0}743\u{A0}157\u{A0}Kč")
        #expect(page.parts.map(\.kind) == [.received, .waiting, .expected])
        #expect(
            page.parts.map(\.text) == [
                "Přišlo do 17.\u{A0}10.\u{A0}2026", "Vystaveno, čeká na platbu", "Koncepty a očekávané faktury",
            ])
        #expect(page.parts.map(\.value) == ["2\u{A0}191\u{A0}771\u{A0}Kč", "0\u{A0}Kč", "551\u{A0}386\u{A0}Kč"])
        // The widths of the bar: 79,90 % received, nothing waiting, 20,10 % expected.
        #expect(abs(page.parts[0].fraction - 0.7990) < 0.0001)
        #expect(page.parts[1].fraction == 0)
        #expect(abs(page.parts[2].fraction - 0.2010) < 0.0001)
        #expect(abs(page.parts.map(\.fraction).reduce(0, +) - 1) < 0.000_001)
        #expect(
            page.netIncome
                == PredictionNetIncome(
                    label: "Čistý příjem průměrně za měsíc (odhad)", amount: "189\u{A0}698\u{A0}Kč",
                    sub: "za celý rok 2\u{A0}276\u{A0}375\u{A0}Kč · 83,0\u{A0}% příjmů po odvodech"))
        #expect(
            page.nextYearNote
                == "290\u{A0}193\u{A0}Kč přijde až v roce 2027 (faktury zaplacené po 31.\u{A0}12.)"
                + " – to už jsou příjmy roku 2027.")
        #expect(
            [page.incomeSub, page.incomeNote, page.incomeHead, page.incomeTotal, page.netIncome.amount]
                .allSatisfy { !$0.contains("≈") })
    }

    /// The income total of a year in progress is what was received and what is expected, and it never carries the sign
    /// of an estimate, not even in a year whose levies the engine works out with the rules of another year. Neither do
    /// the levies of such a year in progress: the result card is an estimate as a whole, and the warning above the page
    /// says that the rules are another year's.
    @Test func theIncomeTotalHasNoEstimateSign() throws {
        let sample = try makePage()
        let page2027 = PredictionBuilder.page(try outcomeOf2027())

        #expect(!sample.incomeTotal.contains("≈"))
        #expect(!page2027.keyFigure.figure.contains("≈"))
        #expect(!page2027.incomeTotal.contains("≈"))
    }

    /// The annual daily conversion explanation remains the same under a uniform payment preference.
    @Test func theBannerSeparatesDailyAverageRatesFromOrdinaryQuotes() throws {
        var uniform = PredictionSample.input(year: 2026)
        uniform.usesUniformRate = true
        uniform.rateDay = nil
        let banner = try makePage(of: uniform).banner
        #expect(banner.contains("každou zvlášť denním kurzem ČNB"))
        #expect(banner.contains("jednotným kurzem 2026"))
        #expect(!banner.contains("posledních tří"))
    }

    /// The months section is open to change in a year in progress, and says when it was invoiced in a year that is
    /// over.
    @Test func theMonthsSectionHasItsHeadingItsLineAndItsLegend() throws {
        let page = try makePage()

        #expect(page.monthsHead == "Kdy čekám faktury")
        #expect(
            page.monthsSub
                == "Měsíce s očekávanou fakturou předvyplňuje aplikace podle dosavadních faktur. Klepnutím je změníte,"
                + " když víte víc – třeba u nové zakázky nebo když spolupráce končí.")
        #expect(page.legend.map(\.kind) == [.paid, .waiting, .expected, .expectedNextYear])
        #expect(page.legend.map(\.text) == ["zaplaceno", "čeká na platbu", "čekám fakturu", "zaplatí se až příští rok"])
    }

    // MARK: The clients

    /// Foxtrot and Tango are active, Sierra is not. Each row says how the client invoices and pays, what it still
    /// brings and what has been received, and has its twelve months.
    @Test func theClientRowsSayTheirRhythmAndMonths() throws {
        let page = try makePage()

        #expect(page.activeRows.map(\.name) == ["Foxtrot, Inc.", "Tango s.r.o."])
        #expect(page.activeRows.map(\.id) == [foxtrot, tango])
        #expect(page.otherRows.map(\.name) == ["Sierra, SE"])
        #expect(page.otherRows.map(\.id) == [sierra])
        #expect(page.othersTitle == "Ostatní odběratelé (1)")
        #expect(page.othersSub == "letos od nich nic nečekám · Sierra, SE")
        #expect(page.noActiveText == nil)

        let foxtrotRow = page.activeRows[0]
        #expect(foxtrotRow.how == "měsíčně ≈\u{A0}285\u{A0}693\u{A0}Kč · platí za ~7\u{A0}dní")
        #expect(foxtrotRow.adds == "+\u{A0}542\u{A0}386\u{A0}Kč")
        #expect(!foxtrotRow.addsIsMuted)
        #expect(
            foxtrotRow.note
                == "letos přišlo 1\u{A0}142\u{A0}771\u{A0}Kč · ≈\u{A0}285\u{A0}693\u{A0}Kč přijde až v roce 2027")
        #expect(!foxtrotRow.isEdited)
        #expect(
            described(foxtrotRow.cells) == [
                "led|—|", "úno|—|", "bře|—|", "dub|—|", "kvě|—|",
                "čvn|289\u{A0}tis.|zaplaceno", "čvc|269\u{A0}tis.|zaplaceno", "srp|279\u{A0}tis.|zaplaceno",
                "zář|306\u{A0}tis.|zaplaceno",
                "říj|≈\u{A0}257\u{A0}tis.|koncept", "lis|≈\u{A0}286\u{A0}tis.|čekám",
                "pro|≈\u{A0}286\u{A0}tis.|→\u{A0}2027",
            ])

        let tangoRow = page.activeRows[1]
        #expect(tangoRow.how == "měsíčně ≈\u{A0}4\u{A0}500\u{A0}Kč · platí za ~8\u{A0}dní")
        #expect(tangoRow.adds == "+\u{A0}9\u{A0}000\u{A0}Kč")
        #expect(!tangoRow.addsIsMuted)
        #expect(
            tangoRow.note
                == "letos přišlo 9\u{A0}000\u{A0}Kč · ≈\u{A0}4\u{A0}500\u{A0}Kč přijde až v roce 2027")
        #expect(
            described(tangoRow.cells) == [
                "led|—|", "úno|—|", "bře|—|", "dub|—|", "kvě|—|", "čvn|—|", "čvc|—|",
                "srp|4\u{A0}500|zaplaceno", "zář|4\u{A0}500|zaplaceno",
                "říj|≈\u{A0}4\u{A0}500|čekám", "lis|≈\u{A0}4\u{A0}500|čekám", "pro|≈\u{A0}4\u{A0}500|→\u{A0}2027",
            ])

        let sierraRow = page.otherRows[0]
        #expect(sierraRow.how == "poslední faktura 29.\u{A0}5.\u{A0}2026")
        #expect(sierraRow.adds == "letos už nic")
        #expect(sierraRow.addsIsMuted)
        #expect(sierraRow.note == "letos přišlo 1\u{A0}040\u{A0}000\u{A0}Kč")
        #expect(
            described(sierraRow.cells) == [
                "led|220\u{A0}tis.|zaplaceno", "úno|190\u{A0}tis.|zaplaceno", "bře|210\u{A0}tis.|zaplaceno",
                "dub|210\u{A0}tis.|zaplaceno", "kvě|210\u{A0}tis.|zaplaceno",
                "čvn|—|", "čvc|—|", "srp|—|", "zář|—|", "říj||nečekám", "lis||nečekám", "pro||nečekám",
            ])
    }

    /// The six states of a month: issued and paid, issued and waiting, over, expected, expected but paid next year,
    /// and not expected. Only the last three are changed by a tap, and the first of them is on.
    @Test func theCellsOfAClientAreInSixStates() throws {
        let page = try makePage()
        let cells = try row(foxtrot, in: page).cells
        let sierraCells = try row(sierra, in: page).cells
        let over: [PredictionCellKind] = Array(repeating: .past, count: 5)
        let paid: [PredictionCellKind] = Array(repeating: .paid, count: 4)
        let expected: [PredictionCellKind] = [.expected, .expected, .expectedNextYear]
        let sierraPaid: [PredictionCellKind] = Array(repeating: .paid, count: 5)
        let sierraOver: [PredictionCellKind] = Array(repeating: .past, count: 4)
        let sierraNotExpected: [PredictionCellKind] = Array(repeating: .notExpected, count: 3)
        let fixed: [Bool] = Array(repeating: false, count: 9)
        let open: [Bool] = [true, true, true]

        #expect(cells.map(\.month) == Array(1...12))
        #expect(cells.map(\.kind) == over + paid + expected)
        #expect(cells.map(\.isToggle) == fixed + open)
        #expect(cells.map(\.isOn) == fixed + open)
        #expect(sierraCells.map(\.kind) == sierraPaid + sierraOver + sierraNotExpected)
        #expect(sierraCells.map(\.isToggle) == fixed + open)
        #expect(sierraCells.map(\.isOn) == Array(repeating: false, count: 12))
    }

    /// What VoiceOver reads for a cell: the month with its invoice, or what is expected in it, with the draft it
    /// takes its day and amount from.
    @Test func theCellsSayWhatTheyHoldToVoiceOver() throws {
        let page = try makePage()
        let foxtrotCells = try row(foxtrot, in: page).cells
        let sierraCells = try row(sierra, in: page).cells

        #expect(foxtrotCells[0].accessibilityLabel == "Leden: žádná faktura")
        #expect(foxtrotCells[5].accessibilityLabel == "Červen: faktura 20260601, 288\u{A0}806\u{A0}Kč, zaplaceno")
        #expect(
            foxtrotCells[9].accessibilityLabel == "Říjen: čekám fakturu asi 256\u{A0}693\u{A0}Kč (koncept 20261001)")
        #expect(foxtrotCells[10].accessibilityLabel == "Listopad: čekám fakturu asi 285\u{A0}693\u{A0}Kč")
        #expect(
            foxtrotCells[11].accessibilityLabel
                == "Prosinec: čekám fakturu asi 285\u{A0}693\u{A0}Kč, zaplatí se až v roce 2027")
        #expect(sierraCells[0].accessibilityLabel == "Leden: faktura 2026-01-01, 220\u{A0}000\u{A0}Kč, zaplaceno")
        #expect(sierraCells[9].accessibilityLabel == "Říjen: fakturu nečekám")
    }

    /// A draft of a month that the person switched off still says so to VoiceOver.
    @Test func aDraftMonthSwitchedOffStillNamesItsDraft() throws {
        let page = try makePage(changes: [foxtrot: [10: false]])
        let october = try row(foxtrot, in: page).cells[9]

        #expect(october.kind == .notExpected)
        #expect(!october.isOn)
        #expect(october.value == "")
        #expect(october.sub == "nečekám")
        #expect(october.accessibilityLabel == "Říjen: fakturu nečekám (koncept 20261001)")
    }

    /// Foxtrot's November switched off, and Sierra's November and December on: Sierra is active now, its November
    /// is paid this year and its December next, and no client is left for the group of the others. The client that was
    /// changed says so, and offers to go back to the app's choice.
    @Test func changedMonthsMarkTheirClientsAndMoveThem() throws {
        let page = try makePage(changes: [foxtrot: [11: false], sierra: [11: true, 12: true]])

        #expect(page.activeRows.map(\.id) == [foxtrot, sierra, tango])
        #expect(page.otherRows.isEmpty)
        let foxtrotRow = try row(foxtrot, in: page)
        #expect(foxtrotRow.isEdited)
        #expect(foxtrotRow.cells[10].sub == "nečekám")
        #expect(foxtrotRow.cells[10].value == "")
        #expect(foxtrotRow.note?.hasSuffix(" · měsíce upravené ručně") == true)
        let sierraRow = try row(sierra, in: page)
        #expect(sierraRow.isEdited)
        #expect(sierraRow.adds == "+\u{A0}208\u{A0}000\u{A0}Kč")
        #expect(!sierraRow.addsIsMuted)
        #expect(
            Array(described(sierraRow.cells)[10...])
                == ["lis|≈\u{A0}208\u{A0}tis.|čekám", "pro|≈\u{A0}208\u{A0}tis.|→\u{A0}2027"])
        #expect(
            sierraRow.note
                == "letos přišlo 1\u{A0}040\u{A0}000\u{A0}Kč · ≈\u{A0}208\u{A0}000\u{A0}Kč přijde až v roce 2027"
                + " · měsíce upravené ručně")
    }

    /// The invoices of no client the app knows make a group of their own, "Neznámý odběratel". Its months are shown
    /// as the others are, but none can be changed: the choices are stored for a client of the app, and it has none.
    @Test func theMonthsOfTheInvoicesOfNoKnownClientCannotBeChanged() throws {
        var input = PredictionSample.input(year: 2026)
        for index in input.invoices.indices where input.invoices[index].clientID == sierra {
            input.invoices[index].clientID = nil
        }

        let page = try makePage(of: input)
        let unknown = try row(ClientPrediction.unknownID, in: page)

        #expect(unknown.name == "Neznámý odběratel")
        #expect(unknown.cells[9...].map(\.kind) == [PredictionCellKind](repeating: .notExpected, count: 3))
        #expect(unknown.cells[9...].map(\.sub) == ["nečekám", "nečekám", "nečekám"])
        #expect(!unknown.cells.contains { $0.isToggle })
        // Sierra is still a client, without invoices now, and its open months can be changed.
        #expect(try row(sierra, in: page).cells[9...].allSatisfy(\.isToggle))
    }

    // MARK: How a client invoices

    /// How often a regular client invoices, in Czech: monthly, every two months, quarterly, every 4 months, and every
    /// N months from five on. Foxtrot of the sample, with the step of its rhythm changed.
    @Test func theRhythmOfARegularClientIsSaidInCzech() throws {
        let prediction = IncomePrediction.make(PredictionSample.input(year: 2026))
        var client = try #require(prediction.clients.first { $0.id == foxtrot })
        let rhythms: [(step: Int, text: String)] = [
            (1, "měsíčně"), (2, "každé dva měsíce"), (3, "čtvrtletně"), (4, "každé 4\u{A0}měsíce"),
            (5, "každých 5\u{A0}měsíců"), (12, "každých 12\u{A0}měsíců"),
        ]

        for (step, text) in rhythms {
            client.step = step
            #expect(
                PredictionBuilder.clientRow(client, in: prediction).how
                    == "\(text) ≈\u{A0}285\u{A0}693\u{A0}Kč · platí za ~7\u{A0}dní", "step \(step)")
        }
    }

    /// One invoice of 10 000 Kč, issued on 30. 9. 2026, instead of the sample's clients: the client has no rhythm
    /// yet, and the invoice is expected to be paid tomorrow.
    @Test func aClientWithOneInvoiceNamesItAndWhatItBrings() throws {
        let client = Client(id: 1, name: "Jediný s.r.o.", dueDays: 14)
        var invoice = Invoice.fixture(
            number: "20260901", issued: "2026-09-30", dueDate: "2026-10-14", items: [.fixture("1", at: 1_000_000)])
        invoice.id = 1
        invoice.clientID = client.id

        let page = try makePage(of: inputWithout(clients: [client], invoices: [invoice]))
        let single = try row(1, in: page)

        #expect(
            single.how == "zatím jedna faktura (30.\u{A0}9.\u{A0}2026) ≈\u{A0}10\u{A0}000\u{A0}Kč"
                + " · další zatím nečekám")
        #expect(single.adds == "+\u{A0}10\u{A0}000\u{A0}Kč")
        #expect(single.cells[8].kind == .waiting)
        #expect(single.cells[8].value == "10\u{A0}tis.")
        #expect(single.cells[8].sub == "čeká")
        #expect(single.cells[8].accessibilityLabel == "Září: faktura 20260901, 10\u{A0}000\u{A0}Kč, čeká na platbu")
        #expect(page.activeRows.map(\.id) == [1])
        #expect(page.noActiveText == nil)
    }

    /// The same client with a month switched on says that it counts on more invoices.
    @Test func aClientWithOneInvoiceAndAMonthOnCountsOnMore() throws {
        let client = Client(id: 1, name: "Jediný s.r.o.", dueDays: 14)
        var invoice = Invoice.fixture(
            number: "20260901", issued: "2026-09-30", dueDate: "2026-10-14", items: [.fixture("1", at: 1_000_000)])
        invoice.id = 1
        invoice.clientID = client.id
        var input = inputWithout(clients: [client], invoices: [invoice])
        input.changes = [1: [11: true]]

        let single = try row(1, in: try makePage(of: input))

        #expect(
            single.how == "zatím jedna faktura (30.\u{A0}9.\u{A0}2026) ≈\u{A0}10\u{A0}000\u{A0}Kč"
                + " · počítám s dalšími")
    }

    /// Two new clients in crowns, without invoices, both with November switched on. The first has a template of
    /// 10 hours at 1 000,50 Kč, so its November brings 10 005,00 Kč; the second has none, so its November has no
    /// amount and the row says what to do about it.
    @Test func aClientWithoutInvoicesGetsItsAmountFromATemplateOrSaysItHasNone() throws {
        let item = TemplateItem(
            description: "Konzultace", quantity: decimal("10"), unit: "hod", unitPriceMinor: 100_050)
        let template = InvoiceTemplate(
            id: 1, name: "Konzultace", clientID: 1, items: [item], vatMode: .domestic21, dueDays: 14)
        var input = inputWithout(
            clients: [Client(id: 1, name: "Nováček s.r.o."), Client(id: 2, name: "Bez šablony s.r.o.")],
            templates: [template])
        input.changes = [1: [11: true], 2: [11: true]]

        let page = try makePage(of: input)
        let withTemplate = try row(1, in: page)
        let withoutTemplate = try row(2, in: page)

        #expect(withTemplate.how == "zatím bez faktur · částka ze šablony ≈\u{A0}10\u{A0}005\u{A0}Kč")
        #expect(withTemplate.adds == "+\u{A0}10\u{A0}005\u{A0}Kč")
        #expect(withTemplate.cells[10].value == "≈\u{A0}10\u{A0}tis.")
        #expect(withTemplate.cells[10].sub == "čekám")
        #expect(withTemplate.note == "měsíce upravené ručně")
        #expect(withoutTemplate.how == "zatím bez faktur")
        #expect(withoutTemplate.adds == "—")
        #expect(!withoutTemplate.addsIsMuted)
        #expect(withoutTemplate.cells[10].value == "—")
        #expect(withoutTemplate.cells[10].sub == "bez částky")
        #expect(withoutTemplate.cells[10].accessibilityLabel == "Listopad: čekám fakturu, částka není známá")
        #expect(
            withoutTemplate.note
                == "částka příjmů letos není úplná – chybí kurz nebo podklady pro odhad"
                + " · bez faktur a šablony neumím odhadnout částku – přidejte šablonu faktury"
                + " · měsíce upravené ručně")
    }

    /// A positive foreign template without a usable quote keeps its amount unavailable and asks for the missing
    /// conversion rate rather than another template when a month is manually enabled.
    @Test func aForeignTemplateWithoutAQuoteExplainsItsMissingConversion() throws {
        var client = Client(id: 1, name: "Euro s.r.o.")
        client.currency = .eur
        let item = TemplateItem(description: "Konzultace", quantity: decimal("1"), unit: "hod", unitPriceMinor: 100_000)
        let template = InvoiceTemplate(
            id: 1, name: "Konzultace", clientID: client.id, items: [item], vatMode: .domestic21, dueDays: 14)
        var input = inputWithout(clients: [client], templates: [template])
        input.rates = [:]
        input.changes = [client.id: [11: true]]

        let foreign = try row(client.id, in: makePage(of: input))
        let note = try #require(foreign.note)

        #expect(foreign.how == "zatím bez faktur · částka ze šablony —")
        #expect(foreign.adds == "—")
        #expect(foreign.cells[10].sub == "bez částky")
        #expect(note.contains("částka ze šablony není dostupná – chybí kurz pro přepočet měny šablony"))
        #expect(!note.contains("přidejte šablonu faktury"))
        #expect(!note.contains("bez faktur a šablony"))
    }

    /// A client without invoices whose template comes to nothing, 10 hours at 0,00 Kč, with November switched on: the
    /// template gives no amount, so the row names none from it beside the note that it cannot estimate one.
    @Test func aTemplateOfNothingGivesTheRowNoAmount() throws {
        let item = TemplateItem(description: "Konzultace", quantity: decimal("10"), unit: "hod", unitPriceMinor: 0)
        let template = InvoiceTemplate(
            id: 1, name: "Konzultace", clientID: 1, items: [item], vatMode: .domestic21, dueDays: 14)
        var input = inputWithout(clients: [Client(id: 1, name: "Nováček s.r.o.")], templates: [template])
        input.changes = [1: [11: true]]

        let zero = try row(1, in: makePage(of: input))

        #expect(zero.how == "zatím bez faktur")
        #expect(
            zero.note
                == "částka příjmů letos není úplná – chybí kurz nebo podklady pro odhad"
                + " · bez faktur a šablony neumím odhadnout částku – přidejte šablonu faktury"
                + " · měsíce upravené ručně")
    }

    /// An unpaid invoice of 1 000,00 EUR, a currency the prediction has no rate for, that keeps no rate of its own: its
    /// amount is unknown. Its month still waits for the payment, with "?" in place of the amount, and VoiceOver reads
    /// it without an amount.
    @Test func anUnpaidInvoiceOfAnUnknownAmountIsAQuestionMark() throws {
        let client = Client(id: 1, name: "Euro s.r.o.", dueDays: 14)
        var invoice = Invoice.fixture(
            number: "20260901", currency: .eur, issued: "2026-09-30", dueDate: "2026-10-14",
            items: [.fixture("1", at: 100_000)])
        invoice.id = 1
        invoice.clientID = client.id

        let september = try row(1, in: makePage(of: inputWithout(clients: [client], invoices: [invoice]))).cells[8]

        #expect(september.kind == .waiting)
        #expect(september.value == "?")
        #expect(september.sub == "čeká")
        #expect(september.accessibilityLabel == "Září: faktura 20260901, čeká na platbu")
    }

    /// Sierra's invoice of December 2025, 215 000 Kč, is not paid: it is expected this year, and says so in the
    /// note of the client, in what the client adds and among the invoices that are issued and unpaid.
    @Test func lastYearsUnpaidInvoiceIsInTheNoteAndInTheBreakdown() throws {
        var input = PredictionSample.input(year: 2026)
        let december = try #require(input.invoices.firstIndex { $0.number == "2025-12-01" })
        input.invoices[december].payment = nil

        let page = try makePage(of: input)
        let sierraRow = try row(sierra, in: page)

        #expect(sierraRow.adds == "+\u{A0}215\u{A0}000\u{A0}Kč")
        #expect(
            sierraRow.note
                == "letos přišlo 1\u{A0}040\u{A0}000\u{A0}Kč · čeká 215\u{A0}000\u{A0}Kč za faktury z roku 2025")
        #expect(page.activeRows.map(\.id).contains(sierra))
        let issued = try row("Vystavené faktury", in: section("Příjmy a zisk", in: page))
        #expect(issued.sign == .plus)
        #expect(issued.value == "215\u{A0}000,00")
        #expect(issued.note == "zaplatí se do 31.\u{A0}12. podle obvyklé doby placení odběratele")
        #expect(page.parts[1].value == "215\u{A0}000\u{A0}Kč")
    }

    // MARK: The breakdown

    /// The two columns of the breakdown, row by row, with the figures of the engine: 2 191 771,35 Kč received and
    /// 551 385,64 Kč expected make 2 743 156,99 Kč, which the engine takes as 2 743 157 Kč of income; the expenses are
    /// capped at 1 200 000 Kč and the profit is 1 543 157 Kč. The tax is 114 786 Kč, the social insurance 247 832 Kč
    /// and the health insurance 104 164 Kč, and the advances leave 68 786, 97 272 and 32 644 Kč to pay. The card of
    /// the net income closes the right column; its rows are those of `theNetIncomeCardClosesTheRightColumn`.
    @Test func theBreakdownAddsUpWithTheEnginesFigures() throws {
        let page = try makePage()

        #expect(page.left.map(\.title) == ["Příjmy a zisk", "Daň z příjmů"])
        #expect(page.right.map(\.title) == ["Sociální pojištění", "Zdravotní pojištění", "Čistý příjem"])
        #expect((page.left + page.right).map(\.authority) == [nil, .tax, .social, .health, nil])
        #expect(
            (page.left + page.right).map(\.tag) == ["odhad", "Finanční úřad", "ČSSZ", "VZP", "za rok (odhad)"])

        #expect(
            try section("Příjmy a zisk", in: page).rows == [
                ComputationRow(
                    label: "Přijaté platby", value: "2\u{A0}191\u{A0}771,35",
                    note: "1.\u{A0}1. – 17.\u{A0}10. · 11\u{A0}plateb"),
                ComputationRow(
                    label: "Koncepty a očekávané faktury", value: "551\u{A0}385,64",
                    note: "podle Kdy čekám faktury · Foxtrot 542\u{A0}386 · Tango 9\u{A0}000", sign: .plus),
                ComputationRow(
                    label: "Příjmy za rok (odhad)", value: "2\u{A0}743\u{A0}156,99",
                    note: "bez 290\u{A0}193\u{A0}Kč, které přijdou až v roce 2027", sign: .equals, style: .strong),
                ComputationRow(
                    label: "Příjmy z podnikání (§ 7)", value: "2\u{A0}743\u{A0}157,00",
                    note: ComputationBuilder.incomeRoundingNote, sign: .equals, style: .strong),
                ComputationRow(
                    label: "Výdajový paušál 60\u{A0}%", value: "\u{2212}1\u{A0}200\u{A0}000,00",
                    note: "60\u{A0}% je 1\u{A0}645\u{A0}894,00 → použije se strop 1\u{A0}200\u{A0}000", sign: .minus),
                ComputationRow(
                    label: "Zisk (dílčí základ daně)", value: "1\u{A0}543\u{A0}157,00", sign: .equals, style: .strong),
            ])
        #expect(
            try section("Daň z příjmů", in: page).rows == [
                ComputationRow(label: "Zisk", value: "1\u{A0}543\u{A0}157,00"),
                ComputationRow(
                    label: "Nezdanitelné části základu", value: "\u{2212}156\u{A0}480,00",
                    note: "úroky z hypotéky 150\u{A0}000 z 219\u{A0}000 (limit) · spoření a pojištění 6\u{A0}480",
                    sign: .minus),
                ComputationRow(
                    label: "Základ daně", value: "1\u{A0}386\u{A0}600", note: "zaokrouhleno na celé stovky dolů",
                    sign: .equals, style: .strong),
                ComputationRow(
                    label: "Sazba 15\u{A0}%", value: "207\u{A0}990",
                    note: "23\u{A0}% až ze základu nad 1\u{A0}762\u{A0}812", sign: .times),
                ComputationRow(
                    label: "Sleva na poplatníka", value: "\u{2212}30\u{A0}840", note: "celá roční částka",
                    sign: .minus),
                ComputationRow(
                    label: "Sleva na manžela / manželku", value: "\u{2212}24\u{A0}840",
                    note: "12\u{A0}měsíců s dítětem do 3 let", sign: .minus),
                ComputationRow(
                    label: "Daň po slevách", value: "152\u{A0}310", note: "slevy snižují daň nejvýš na nulu",
                    sign: .equals, style: .strong),
                ComputationRow(
                    label: "Daňové zvýhodnění na děti", value: "\u{2212}37\u{A0}524",
                    note: "Anna 15\u{A0}204 · Tomáš 22\u{A0}320", sign: .minus),
                ComputationRow(label: "Daň za rok (odhad)", value: "114\u{A0}786", sign: .equals, style: .strong),
                ComputationRow(
                    label: "Zálohy za rok", value: "\u{2212}46\u{A0}000",
                    note: "podle plánu záloh · 2\u{A0}platby za celý rok", sign: .minus),
                ComputationRow(label: "Doplatek", value: "68\u{A0}786\u{A0}Kč", sign: .equals, style: .total),
            ])
        #expect(
            try section("Sociální pojištění", in: page).rows == [
                ComputationRow(
                    label: "Vyměřovací základ", value: "848\u{A0}737",
                    note: "55\u{A0}% zisku, nahoru · min. 205\u{A0}668 (12\u{A0}měsíců hlavní činnosti)"
                        + " · max. 2\u{A0}350\u{A0}416"),
                ComputationRow(
                    label: "Sazba 29,2\u{A0}%", value: "247\u{A0}832", note: "zaokrouhleno na celé koruny nahoru",
                    sign: .times),
                ComputationRow(
                    label: "Zálohy za rok", value: "\u{2212}150\u{A0}560",
                    note: "podle plánu záloh · 12\u{A0}plateb za celý rok", sign: .minus),
                ComputationRow(label: "Doplatek", value: "97\u{A0}272\u{A0}Kč", sign: .equals, style: .total),
            ])
        #expect(
            try section("Zdravotní pojištění", in: page).rows == [
                ComputationRow(
                    label: "Vyměřovací základ", value: "771\u{A0}578,50",
                    note: "50\u{A0}% zisku · min. 293\u{A0}802,00 (12\u{A0}měsíců)"),
                ComputationRow(
                    label: "Sazba 13,5\u{A0}%", value: "104\u{A0}164", note: "zaokrouhleno na celé koruny nahoru",
                    sign: .times),
                ComputationRow(
                    label: "Zálohy za rok", value: "\u{2212}71\u{A0}520",
                    note: "podle plánu záloh · 12\u{A0}plateb za celý rok", sign: .minus),
                ComputationRow(label: "Doplatek", value: "32\u{A0}644\u{A0}Kč", sign: .equals, style: .total),
            ])

        // No two rows of a card have the same label, which is their identity.
        for section in page.left + page.right {
            #expect(Set(section.rows.map(\.id)).count == section.rows.count, "\(section.title)")
        }
    }

    /// Each card is one calculation from the top down, so the values as they are shown add up: the payments received
    /// and expected make the income, the income in whole crowns less the expenses is the profit, the base is the profit
    /// less the deductions rounded down to hundreds, the tax less the credits and the child benefit is the tax of the
    /// year, and what the advances leave is what is left to pay.
    @Test func theValuesOfTheRowsAddUpAsTheyAreShown() throws {
        let page = try makePage()
        let income = try section("Příjmy a zisk", in: page)
        let tax = try section("Daň z příjmů", in: page)
        let social = try section("Sociální pojištění", in: page)
        let health = try section("Zdravotní pojištění", in: page)
        func value(_ label: String, in section: ComputationSection) throws -> Int64 {
            hundredths(try row(label, in: section).value)
        }

        let total = try value("Příjmy za rok (odhad)", in: income)
        #expect(try value("Přijaté platby", in: income) + value("Koncepty a očekávané faktury", in: income) == total)
        let business = try value("Příjmy z podnikání (§ 7)", in: income)
        #expect(business == (total + 50) / 100 * 100)
        let profit = try value("Zisk (dílčí základ daně)", in: income)
        #expect(try business + value("Výdajový paušál 60\u{A0}%", in: income) == profit)
        #expect(try value("Zisk", in: tax) == profit)

        let afterDeductions = try profit + value("Nezdanitelné části základu", in: tax)
        #expect(try value("Základ daně", in: tax) == afterDeductions / 10_000 * 10_000)
        let afterCredits = try value("Sazba 15\u{A0}%", in: tax) + value("Sleva na poplatníka", in: tax)
            + value("Sleva na manžela / manželku", in: tax)
        #expect(try value("Daň po slevách", in: tax) == afterCredits)
        let taxOfTheYear = try afterCredits + value("Daňové zvýhodnění na děti", in: tax)
        #expect(try value("Daň za rok (odhad)", in: tax) == taxOfTheYear)

        #expect(try value("Doplatek", in: tax) == taxOfTheYear + value("Zálohy za rok", in: tax))
        let socialInsurance = try value("Sazba 29,2\u{A0}%", in: social)
        #expect(try value("Doplatek", in: social) == socialInsurance + value("Zálohy za rok", in: social))
        let healthInsurance = try value("Sazba 13,5\u{A0}%", in: health)
        #expect(try value("Doplatek", in: health) == healthInsurance + value("Zálohy za rok", in: health))
    }

    /// Income adjustments of −50 000 Kč on 10. 3. 2026 and of +100 000 Kč on 10. 11. 2026: only the first is dated by
    /// today. It is among the money received, though it is not one of the 11 payments, and the note says so.
    @Test func adjustmentsAreFoldedIntoTheReceivedPayments() throws {
        var input = PredictionSample.input(year: 2026)
        input.receipts += [
            Receipt(day: civilDate("2026-03-10"), czkNetHalere: -5_000_000, czkVatHalere: 0, source: .adjustment(1)),
            Receipt(day: civilDate("2026-11-10"), czkNetHalere: 10_000_000, czkVatHalere: 0, source: .adjustment(2)),
        ]

        let received = try row("Přijaté platby", in: section("Příjmy a zisk", in: makePage(of: input)))

        #expect(received.value == "2\u{A0}141\u{A0}771,35")
        #expect(received.note == "1.\u{A0}1. – 17.\u{A0}10. · 11\u{A0}plateb · včetně úprav příjmů")
    }

    /// A tax below zero is a bonus that the tax office pays, and reads so. A single payment of 200 000 Kč leaves the
    /// tax at nothing, and the children's 37 524 Kč are paid as a bonus. The taxpayer's credit is used only as far as
    /// the tax goes.
    @Test func aNegativeTaxReadsAsABonus() throws {
        let page = try makePage(of: inputWithOnePaymentThatLeavesTheTaxAsABonus())
        let tax = try section("Daň z příjmů", in: page)

        let part = page.levyBar.parts[0]
        #expect(part.authority == .tax)
        #expect(part.legendValue == "bonus 37\u{A0}524\u{A0}Kč")
        // A bonus is no levy to draw: the part of the bar has no width.
        #expect(part.weight == -37_524)
        #expect(try row("Daň za rok (odhad)", in: tax).value == "\u{2212}37\u{A0}524")
        #expect(
            try row("Daň za rok (odhad)", in: tax).note == "záporná daň je daňový bonus – vyplatí ho finanční úřad")
        #expect(
            try row("Sleva na poplatníka", in: tax).note == "roční sleva 30\u{A0}840 se uplatní nejvýše do výše daně")
        // The bonus is paid back with the advances, so there is no tax to settle.
        #expect(try row("Doplatek", in: tax).value.hasPrefix("vrátí se "))
    }

    /// A year with months of secondary activity has the social base of Výpočet's own rows, which the single row of a
    /// year of main activity cannot say, and Výpočet's row of the rate under them; the advances and what is left to pay
    /// are those of Odhad odvodů itself.
    @Test func aYearWithSecondaryActivityHasTheRowsOfVypocetForTheSocialBase() throws {
        var settings = PredictionSample.settings(of: 2026)
        settings.secondaryMonths = [3, 4]
        let input = PredictionSample.input(year: 2026)
        let yearInput = AppModel.yearInput(
            settings, receipts: input.receipts, family: TaxEngineFamilyTests.sampleFamily)
        let outcome = try PredictionOutcome.make(prediction: IncomePrediction.make(input), yearInput: yearInput)

        let social = try section("Sociální pojištění", in: PredictionBuilder.page(outcome))

        #expect(social.rows.contains { $0.label == "Zisk na měsíc činnosti (ř.\u{A0}23)" })
        #expect(!social.rows.contains { $0.label == "Vyměřovací základ" })
        #expect(Array(social.rows.suffix(3).map(\.label)) == ["Sazba 29,2\u{A0}%", "Zálohy za rok", "Doplatek"])
        #expect(Set(social.rows.map(\.id)).count == social.rows.count)
    }

    // MARK: The net income

    /// The average per month and the sum of the year it is the average of are the figures that Přehled's card of the
    /// estimate gives for the year. The card is an area of estimates as a whole, so it has no sign of an estimate in
    /// front of the average and no caption of an estimate.
    @Test func theNetIncomeIsTheSameAsOnPrehledsEstimateCard() throws {
        let outcome = try PredictionSample.outcome(year: 2026)
        let page = PredictionBuilder.page(outcome)
        let card = try #require(PredictionBuilder.card(outcome).stats.last)

        #expect(card.label + " (odhad)" == page.netIncome.label)
        #expect(card.value == page.netIncome.amount)
        #expect(page.netIncome.sub.hasPrefix(card.sub))
    }

    /// The card of the net income closes the right column, under the two insurances. It is the card of Výpočet worded
    /// for the whole year: the income of 2 743 157 Kč less the tax of 114 786 Kč and the insurance of 247 832 Kč and
    /// 104 164 Kč leaves 2 276 375 Kč, which is 83,0 % of the income, and over the twelve months 189 698 Kč. The year
    /// is in progress, so the label of its result and its tag say that it is an estimate.
    @Test func theNetIncomeCardClosesTheRightColumn() throws {
        let page = try makePage()
        let card = try section("Čistý příjem", in: page)

        #expect(page.right.last == card)
        #expect(card.tag == "za rok (odhad)")
        #expect(card.isNetIncome)
        #expect(card.authority == nil)
        #expect(
            card.rows == [
                ComputationRow(label: "Příjmy z podnikání (§ 7)", value: "2\u{A0}743\u{A0}157,00", note: "bez DPH"),
                ComputationRow(label: "Daň z příjmů", value: "\u{2212}114\u{A0}786", sign: .minus),
                ComputationRow(label: "Sociální pojištění", value: "\u{2212}247\u{A0}832", sign: .minus),
                ComputationRow(label: "Zdravotní pojištění", value: "\u{2212}104\u{A0}164", sign: .minus),
                ComputationRow(
                    label: "Čistý příjem za rok (odhad)", value: "2\u{A0}276\u{A0}375",
                    note: "83,0\u{A0}% příjmů · skutečné výdaje podnikání tu odečtené nejsou", sign: .equals,
                    style: .strong),
                ComputationRow(label: "12\u{A0}měsíců", value: "12", note: "celý rok", sign: .divided),
                ComputationRow(
                    label: "Průměrně za měsíc", value: "189\u{A0}698\u{A0}Kč", note: "čistý příjem na jeden měsíc",
                    sign: .equals, style: .total),
            ])
        // The card Příjmy says the figures of the card.
        #expect(try row("Průměrně za měsíc", in: card).value == page.netIncome.amount)
    }

    /// 2025 is over: its income of 2 931 160 Kč less the levies of 537 865 Kč leaves 2 393 295 Kč, which is 81,7 % of
    /// the income, and over the twelve months 199 441 Kč (199 441,25 rounded). Nothing is an estimate, so the caption
    /// has no "(odhad)", no figure has the sign of one, and the card of the net income names the year.
    @Test func aYearThatIsOverHasItsNetIncomeWithoutAnEstimate() throws {
        let page = try PredictionSample.page(year: 2025)

        #expect(
            page.netIncome
                == PredictionNetIncome(
                    label: "Čistý příjem průměrně za měsíc", amount: "199\u{A0}441\u{A0}Kč",
                    sub: "za celý rok 2\u{A0}393\u{A0}295\u{A0}Kč · 81,7\u{A0}% příjmů po odvodech"))
        let card = try section("Čistý příjem", in: page)
        #expect(card.tag == "za rok 2025")
        #expect(try row("Čistý příjem za rok 2025", in: card).value == "2\u{A0}393\u{A0}295")
        #expect(try row("Průměrně za měsíc", in: card).value == page.netIncome.amount)
        #expect(texts(of: page).filter { $0.contains("≈") }.isEmpty)
    }

    /// No clients, invoices or templates: no income, and the minimum insurance of the whole year, 99 720 Kč, is all the
    /// levies, so the year leaves −99 720 Kč, which over the twelve months is −8 310 Kč. There is no income for the
    /// levies to take a part of, so neither the line under the average nor the card has a share.
    @Test func withoutIncomeTheNetIncomeIsNegativeAndHasNoShare() throws {
        let page = try makePage(of: inputWithout())

        #expect(
            page.netIncome
                == PredictionNetIncome(
                    label: "Čistý příjem průměrně za měsíc (odhad)", amount: "\u{2212}8\u{A0}310\u{A0}Kč",
                    sub: "za celý rok \u{2212}99\u{A0}720\u{A0}Kč"))
        let card = try section("Čistý příjem", in: page)
        let result = try row("Čistý příjem za rok (odhad)", in: card)
        #expect(result.value == "\u{2212}99\u{A0}720")
        #expect(result.note == "skutečné výdaje podnikání tu odečtené nejsou")
        #expect(try row("Průměrně za měsíc", in: card).value == page.netIncome.amount)
    }

    /// One payment of 10 000 Kč: the minimum insurance of the whole year, 99 720 Kč, is far more than the income, so
    /// the year leaves −89 720 Kč, which over the twelve months is −7 477 Kč (−7 476,67 rounded), and the levies take
    /// 997,2 % of the income. The income is above zero, so the line under the average has its share, and a share below
    /// zero is shown as it is.
    @Test func aShareBelowZeroIsShownAsItIs() throws {
        let page = try makePage(of: inputWithOneSmallPayment())

        #expect(
            page.netIncome
                == PredictionNetIncome(
                    label: "Čistý příjem průměrně za měsíc (odhad)", amount: "\u{2212}7\u{A0}477\u{A0}Kč",
                    sub: "za celý rok \u{2212}89\u{A0}720\u{A0}Kč · \u{2212}897,2\u{A0}% příjmů po odvodech"))
        #expect(
            try row("Čistý příjem za rok (odhad)", in: section("Čistý příjem", in: page)).note
                == "\u{2212}897,2\u{A0}% příjmů · skutečné výdaje podnikání tu odečtené nejsou")
    }

    // MARK: A year that is over

    /// 2025 is over: its income is what was received, 2 931 159,89 Kč from 16 payments, and nothing is an estimate.
    /// There is no estimate sign, the bar has only what was received, the months say when it was invoiced, and none can
    /// be changed. The levies are 142 986 + 278 025 + 116 854 Kč, the advances 207 800 Kč, so 330 065 Kč are owed
    /// beyond them.
    @Test func aClosedYearSaysSkutecnost() throws {
        let page = try makePage(year: 2025)

        #expect(
            page.keyFigure
                == KeyFigureData(
                    eyebrow: "Odvody za rok 2025 – skutečnost", figure: "537\u{A0}865\u{A0}Kč",
                    share: "18,3\u{A0}% z příjmů", sentence: "Odvody za celý rok 2025 ze všech přijatých plateb."))
        #expect(page.levyBar.header == "Odvody za rok 2025 podle úřadů")
        #expect(page.levyBar.parts.map(\.weight) == [142_986, 278_025, 116_854])
        #expect(
            page.due
                == KeyFigureData(
                    eyebrow: "Doplatek odvodů bez záloh", figure: "330\u{A0}065\u{A0}Kč",
                    sentence: "Za rok 2025 navíc k zálohám 207\u{A0}800\u{A0}Kč"
                        + " – daň, ČSSZ a VZP po podání přiznání a přehledů.",
                    sentenceEmphasis: "207\u{A0}800\u{A0}Kč"))
        #expect(page.incomeSub == "Rok 2025 · skutečnost")
        #expect(page.incomeHead == "Příjmy za rok 2025")
        #expect(page.incomeTotal == "2\u{A0}931\u{A0}160\u{A0}Kč")
        #expect(page.parts.map(\.text) == ["Přišlo do 31.\u{A0}12.\u{A0}2025"])
        #expect(page.parts.map(\.value) == ["2\u{A0}931\u{A0}160\u{A0}Kč"])
        #expect(page.parts.map(\.fraction) == [1])
        #expect(page.nextYearNote == nil)
        #expect(
            page.banner
                == "Rok 2025 skončil: všechny platby jsou známé, nic se neodhaduje."
                + " Měsíce ukazují, co se kdy vyfakturovalo.")
        #expect(page.monthsHead == "Faktury po měsících")
        #expect(page.monthsSub == "Podle data vystavení.")
        #expect(page.legend.map(\.text) == ["zaplaceno", "čeká na platbu"])
        #expect(page.activeRows.map(\.name) == ["Sierra, SE", "Foxtrot, Inc."])
        #expect(page.activeRows[0].how == "měsíčně · platí za ~5\u{A0}dní")
        #expect(page.activeRows[0].adds == "2\u{A0}692\u{A0}500\u{A0}Kč")
        #expect(!page.activeRows[0].addsIsMuted)
        #expect(page.activeRows[1].how == "měsíčně · platí za ~8\u{A0}dní")
        #expect(page.activeRows[1].adds == "238\u{A0}660\u{A0}Kč")
        #expect(page.otherRows.map(\.name) == ["Tango s.r.o."])
        #expect(page.otherRows[0].how == "v roce 2025 bez faktur")
        #expect(page.otherRows[0].adds == "0\u{A0}Kč")
        #expect(page.otherRows[0].addsIsMuted)
        #expect(page.othersTitle == "Ostatní odběratelé (1)")
        #expect(page.othersSub == "v roce 2025 bez faktur · Tango s.r.o.")
        // Nothing is chosen in a year that is over.
        let cells = (page.activeRows + page.otherRows).flatMap(\.cells)
        #expect(!cells.contains { $0.isToggle || $0.isOn })
        #expect(!cells.contains { [.expected, .expectedNextYear, .notExpected].contains($0.kind) })
        #expect(texts(of: page).filter { $0.contains("≈") }.isEmpty)

        let income = try section("Příjmy a zisk", in: page)
        #expect(income.tag == "celý rok")
        #expect(try row("Příjmy za rok 2025", in: income).value == "2\u{A0}931\u{A0}159,89")
        #expect(try row("Příjmy z podnikání (§ 7)", in: income).value == "2\u{A0}931\u{A0}160,00")
        #expect(try row("Zisk (dílčí základ daně)", in: income).value == "1\u{A0}731\u{A0}160,00")
        #expect(income.rows.map(\.label).contains("Koncepty a očekávané faktury") == false)
        let tax = try section("Daň z příjmů", in: page)
        #expect(try row("Daň za rok 2025", in: tax).value == "142\u{A0}986")
        #expect(try row("Doplatek", in: tax).value == "104\u{A0}986\u{A0}Kč")
        #expect(try row("Vyměřovací základ", in: section("Zdravotní pojištění", in: page)).value == "865\u{A0}580,00")
    }

    /// Sierra's invoice of December 2024 is paid on 5. 1. 2025: 207 500 Kč belong to the next year. A year that is
    /// over has no estimate, so the sums of money that come later are written without the sign of an estimate.
    @Test func aClosedYearNamesTheMoneyOfTheNextYearWithoutAnApproximation() throws {
        let page = try makePage(year: 2024)

        #expect(
            page.nextYearNote
                == "207\u{A0}500\u{A0}Kč přijde až v roce 2025 (faktury zaplacené po 31.\u{A0}12.)"
                + " – to už jsou příjmy roku 2025.")
        let sierraRow = try row(sierra, in: page)
        #expect(sierraRow.note == "207\u{A0}500\u{A0}Kč přijde až v roce 2025")
        #expect(sierraRow.cells[11].value == "208\u{A0}tis.")
        #expect(sierraRow.cells[11].sub == "→\u{A0}2025")
        #expect(sierraRow.cells[11].kind == .waiting)
        #expect(
            sierraRow.cells[11].accessibilityLabel
                == "Prosinec: faktura 2024-12-01, 207\u{A0}500\u{A0}Kč, čeká na platbu")
        #expect(
            try row("Příjmy za rok 2024", in: section("Příjmy a zisk", in: page)).note
                == "bez 207\u{A0}500\u{A0}Kč, které přijdou až v roce 2025")
        #expect(page.othersTitle == "Ostatní odběratelé (2)")
        #expect(page.othersSub == "v roce 2024 bez faktur · Foxtrot, Inc., Tango s.r.o.")
        #expect(texts(of: page).filter { $0.contains("≈") }.isEmpty)
    }

    /// On 31. 12. 2026 the year of today is over too, so it is a year of facts: 2 191 771 Kč received. The advances
    /// leave 8 719 Kč to pay with the returns, and the tax advances pay 18 499 Kč more than the tax, which does not
    /// lower what the others are owed but is named as it arose.
    @Test func theLastDayOfTheYearClosesTheYearOfToday() throws {
        let page = try makePage(today: civilDate("2026-12-31"))

        #expect(page.keyFigure.eyebrow == "Odvody za rok 2026 – skutečnost")
        #expect(page.levyBar.header == "Odvody za rok 2026 podle úřadů")
        #expect(page.incomeSub == "Rok 2026 · skutečnost")
        #expect(page.incomeTotal == "2\u{A0}191\u{A0}771\u{A0}Kč")
        #expect(
            page.due
                == KeyFigureData(
                    eyebrow: "Doplatek odvodů bez záloh", figure: "8\u{A0}719\u{A0}Kč",
                    sentence: "Za rok 2026 navíc k zálohám 268\u{A0}080\u{A0}Kč"
                        + " – daň, ČSSZ a VZP po podání přiznání a přehledů."
                        + " U některého úřadu vznikl přeplatek 18\u{A0}499\u{A0}Kč.",
                    sentenceEmphasis: "268\u{A0}080\u{A0}Kč"))
        #expect(page.monthsHead == "Faktury po měsících")
        #expect(texts(of: page).filter { $0.contains("≈") }.isEmpty)
        #expect(!(page.activeRows + page.otherRows).flatMap(\.cells).contains { $0.isToggle })
    }

    // MARK: A year with the rules of another year

    /// 2021 is over, and the engine has no rules for it: it works the levies out with those of 2022. The year has three
    /// payments of 100 000 Kč, and the sample's 2024 for the rest (`outcomeOf2021(advances:)`). The levies are an
    /// estimate, and the year is shown among facts ("– skutečnost"), so the sum of them, each of the three (in the
    /// legend and in the rows of the popover that follow from the levy) and the amount of what is left to settle have
    /// the sign of one, and so have the average per month of the net income and the sum of the year, which is the
    /// income less the levies. Nothing else of the page does: not the advances, not the key figure's share and not the
    /// income, which was received. The advances pay more than the levies, so what is left is the overpayment
    /// ("Přeplatek záloh"). The tax is a bonus, which reads so after the sign. The label is that of a year that is
    /// over, and the banner no longer says that nothing is estimated.
    @Test func aYearOverWithoutItsOwnRulesMarksItsLeviesAsEstimates() throws {
        let outcome = try outcomeOf2021()
        let page = PredictionBuilder.page(outcome)
        let sign = "≈\u{A0}"

        #expect(outcome.result.rulesAreEstimate)
        #expect(outcome.result.rules.year == 2022)
        #expect(page.keyFigure.figure.hasPrefix(sign))
        #expect(page.levyBar.parts.map(\.legendValue).allSatisfy { $0.hasPrefix(sign) })
        #expect(page.levyBar.parts[0].legendValue.hasPrefix(sign + "bonus "))
        for part in page.levyBar.parts {
            // The levy and what is left to pay of it follow from the rules of another year; the advances are the plan.
            #expect(part.rows.filter { $0.style != .muted }.allSatisfy { $0.value.hasPrefix(sign) })
            #expect(part.rows.filter { $0.style == .muted }.allSatisfy { !$0.value.contains("≈") })
            #expect(part.accessibilityLabel.contains(sign))
        }
        #expect(page.levyBar.accessibilityLabel.contains(sign))
        #expect(outcome.owedTotal == 0)
        #expect(outcome.overpaidTotal > 0)
        #expect(page.due.eyebrow == "Přeplatek záloh")
        #expect(page.due.figure == sign + CzechFormat.wholeKc(outcome.overpaidTotal))
        let advances = CzechFormat.wholeKc(outcome.result.advancesPaidTotal)
        #expect(
            page.due.sentence
                == "Zálohy " + advances + " převýší odvody – rozdíl se vrátí po podání přiznání a přehledů.")
        #expect(page.due.sentenceEmphasis == advances)
        #expect(!advances.contains("≈"))
        #expect(!page.incomeTotal.contains("≈"))
        // The year is over, so the caption of the net income does not say that it is an estimate, but the figures have
        // the sign, the average and the sum of the year.
        #expect(page.netIncome.label == "Čistý příjem průměrně za měsíc")
        #expect(page.netIncome.amount.hasPrefix(sign))
        #expect(page.netIncome.sub.hasPrefix("za celý rok " + sign))
        // The sign is on the figures of the levies, in the legend, the rows and the readings of the bar, on the figure
        // of what is left to settle and on the two figures of the net income, and on no other text of the page.
        let marked = texts(of: page).filter { $0.contains("≈") }
        #expect(marked.contains(page.keyFigure.figure))
        #expect(marked.contains(page.due.figure))
        #expect(marked.contains(page.netIncome.amount))
        #expect(marked.contains(page.netIncome.sub))
        let unmarked = [
            page.keyFigure.eyebrow, page.keyFigure.sentence, page.keyFigure.share, page.due.eyebrow,
            page.due.sentence, page.levyBar.header, page.incomeSub, page.incomeNote, page.incomeHead,
            page.incomeTotal, page.netIncome.label,
        ].compactMap { $0 }
        #expect(unmarked.allSatisfy { !$0.contains("≈") }, "\(unmarked.filter { $0.contains("≈") })")
        #expect(page.keyFigure.eyebrow == "Odvody za rok 2021 – skutečnost")
        #expect(
            page.banner
                == "Rok 2021 skončil: všechny platby jsou známé. Měsíce ukazují, co se kdy vyfakturovalo.")
    }

    /// The same year with no advance planned: the insurance is left to settle, so what is left is the doplatek in the
    /// texts of a year that is over, and its amount has the sign of an estimate as the přeplatek has in the year above.
    /// The advances, which are nothing, have none. The tax is a bonus, which is an overpayment at that authority, so
    /// the text names it beside what is owed.
    @Test func aYearOverWithoutItsOwnRulesMarksWhatIsLeftToPayAsAnEstimateToo() throws {
        let outcome = try outcomeOf2021(advances: AdvancePlan.empty)
        let page = PredictionBuilder.page(outcome)

        #expect(outcome.owedTotal > 0)
        #expect(outcome.overpaidTotal > 0)
        #expect(
            page.due
                == KeyFigureData(
                    eyebrow: "Doplatek odvodů bez záloh", figure: "≈\u{A0}" + CzechFormat.wholeKc(outcome.owedTotal),
                    sentence: "Za rok 2021 navíc k zálohám 0\u{A0}Kč"
                        + " – daň, ČSSZ a VZP po podání přiznání a přehledů. U některého úřadu vznikl přeplatek "
                        + CzechFormat.wholeKc(outcome.overpaidTotal) + ".",
                    sentenceEmphasis: "0\u{A0}Kč"))
    }

    /// The first weeks of 2027 are in progress, and the engine has no rules for the year yet: it works the levies out
    /// with those of 2026. The result card is an estimate as a whole ("Odhad odvodů za celý rok 2027"), so none of its
    /// figures has the sign "≈", and the warning above the page says that the rules are another year's: not the sum of
    /// the levies, not the legend, rows and readings of the bar, not what is left to settle ("Odhad přeplatku záloh")
    /// and not the figures of the net income, which sit in a card that is an estimate too. The label and the banner are
    /// those of a year in progress, and so is the caption of the net income.
    @Test func aYearInProgressWithoutItsOwnRulesHasNoApproximationInItsResultCard() throws {
        let outcome = try outcomeOf2027()
        let page = PredictionBuilder.page(outcome)

        #expect(outcome.result.rulesAreEstimate)
        #expect(outcome.result.rules.year == 2026)
        #expect(outcome.owedTotal == 0)
        #expect(outcome.overpaidTotal > 0)
        #expect(page.keyFigure.eyebrow == "Odhad odvodů za celý rok 2027")
        #expect(page.levyBar.header == "Odvody za celý rok 2027 podle úřadů")
        #expect(page.due.eyebrow == "Odhad přeplatku záloh")
        #expect(page.due.figure == CzechFormat.wholeKc(outcome.overpaidTotal))
        #expect(
            page.due.sentence
                == "Zálohy " + CzechFormat.wholeKc(outcome.result.advancesPaidTotal)
                + " převýší odvody – rozdíl se vrátí po podání přiznání a přehledů.")
        let marked = resultTexts(of: page) + [page.netIncome.amount, page.netIncome.sub, page.incomeTotal]
        #expect(marked.filter { $0.contains("≈") }.isEmpty, "\(marked.filter { $0.contains("≈") })")
        #expect(page.netIncome.label == "Čistý příjem průměrně za měsíc (odhad)")
        #expect(page.banner.hasPrefix("Odhad vychází z faktur do 15.\u{A0}1.\u{A0}2027"))
    }

    // MARK: A year with a payment at a provisional rate

    /// 2025 is over and has rules of its own, so its banner says that nothing is estimated. While the screen shows
    /// above the page that part of its income is converted at a provisional rate (`hasProvisionalIncome`), the banner
    /// no longer says so: it reads as that of a year worked out with the rules of another year. Nothing else of the
    /// page changes, as the rate is no estimate of the levies and puts no sign "≈" on the income or on them.
    @Test func aYearOverWithAProvisionalRateDoesNotSayThatNothingIsEstimated() throws {
        let outcome = try PredictionSample.outcome(year: 2025)
        let plain = PredictionBuilder.page(outcome)
        let provisional = PredictionBuilder.page(outcome, hasProvisionalIncome: true)

        #expect(!outcome.result.rulesAreEstimate)
        #expect(PredictionBuilder.page(outcome, hasProvisionalIncome: false) == plain)
        #expect(
            plain.banner
                == "Rok 2025 skončil: všechny platby jsou známé, nic se neodhaduje."
                + " Měsíce ukazují, co se kdy vyfakturovalo.")
        #expect(
            provisional.banner
                == "Rok 2025 skončil: všechny platby jsou známé. Měsíce ukazují, co se kdy vyfakturovalo.")
        var expected = plain
        expected.banner = provisional.banner
        #expect(provisional == expected)
        #expect(texts(of: provisional).filter { $0.contains("≈") }.isEmpty)
    }

    /// A year over that the engine has no rules for already reads without "nic se neodhaduje", so a provisional rate
    /// changes nothing of its page, and the two reasons together do not bring the sentence back.
    @Test func aYearOverWithoutItsOwnRulesReadsTheSameWithAProvisionalRate() throws {
        let outcome = try outcomeOf2021()

        #expect(outcome.result.rulesAreEstimate)
        #expect(PredictionBuilder.page(outcome, hasProvisionalIncome: true) == PredictionBuilder.page(outcome))
        #expect(
            PredictionBuilder.page(outcome, hasProvisionalIncome: true).banner
                == "Rok 2021 skončil: všechny platby jsou známé. Měsíce ukazují, co se kdy vyfakturovalo.")
    }

    /// A year in progress never says that nothing is estimated, so a provisional rate changes nothing of its page: not
    /// its banner, any other text or any sign.
    @Test func aYearInProgressWithAProvisionalRateKeepsItsPage() throws {
        let outcome = try PredictionSample.outcome(year: 2026)
        let page = PredictionBuilder.page(outcome, hasProvisionalIncome: true)

        #expect(page == PredictionBuilder.page(outcome))
        #expect(page.banner.hasPrefix("Odhad vychází z faktur do 17.\u{00A0}10.\u{00A0}2026:"))
    }

    // MARK: A year with levies that are overpaid

    /// No clients, no invoices and no templates: no income, and the levies are the minimum insurance of the whole year,
    /// 99 720 Kč. The advances pay 268 080 Kč, 168 360 Kč more than that, so what is left is an overpayment, not a sum
    /// to settle. With rules of its own, the year has no sign of an estimate on any figure.
    @Test func anOverpaidYearSaysPreplatek() throws {
        let page = try makePage(of: inputWithout())

        #expect(page.keyFigure.figure == "99\u{A0}720\u{A0}Kč")
        // There is no income for the levies to take a part of, so there is no share beside the figure or in a popover.
        #expect(page.keyFigure.share == nil)
        #expect(page.levyBar.parts.allSatisfy { $0.shareLine == nil })
        #expect(
            page.levyBar.parts.map(\.legendValue) == ["0\u{A0}Kč", "60\u{A0}056\u{A0}Kč", "39\u{A0}664\u{A0}Kč"])
        // The advances pay more than every levy: the last row of each popover is what comes back, in green.
        #expect(
            page.levyBar.parts.map { $0.rows[2] } == [
                LevyPopoverRow(label: "Přeplatek", value: "46\u{A0}000\u{A0}Kč", style: .positive),
                LevyPopoverRow(label: "Přeplatek", value: "90\u{A0}504\u{A0}Kč", style: .positive),
                LevyPopoverRow(label: "Přeplatek", value: "31\u{A0}856\u{A0}Kč", style: .positive),
            ])
        #expect(
            page.due
                == KeyFigureData(
                    eyebrow: "Odhad přeplatku záloh", figure: "168\u{A0}360\u{A0}Kč",
                    sentence: "Zálohy 268\u{A0}080\u{A0}Kč převýší odvody"
                        + " – rozdíl se vrátí po podání přiznání a přehledů.",
                    sentenceEmphasis: "268\u{A0}080\u{A0}Kč"))
        #expect(page.incomeTotal == "0\u{A0}Kč")
        #expect(page.parts.map(\.fraction) == [0, 0, 0])
        #expect(page.nextYearNote == nil)
        #expect(try row("Doplatek", in: section("Daň z příjmů", in: page)).value == "přeplatek 46\u{A0}000\u{A0}Kč")
        #expect(
            try row("Doplatek", in: section("Sociální pojištění", in: page)).value == "přeplatek 90\u{A0}504\u{A0}Kč")
        #expect(
            try row("Doplatek", in: section("Zdravotní pojištění", in: page)).value == "přeplatek 31\u{A0}856\u{A0}Kč")
    }

    /// A year that is over and overpaid has the overpayment without the sign of an estimate, and names it "Přeplatek
    /// záloh", not the estimate of one.
    @Test func anOverpaidYearThatIsOverHasNoEstimateSign() throws {
        var input = inputWithout()
        input.today = civilDate("2026-12-31")

        let page = try makePage(of: input)

        #expect(
            page.due
                == KeyFigureData(
                    eyebrow: "Přeplatek záloh", figure: "168\u{A0}360\u{A0}Kč",
                    sentence: "Zálohy 268\u{A0}080\u{A0}Kč převýší odvody"
                        + " – rozdíl se vrátí po podání přiznání a přehledů.",
                    sentenceEmphasis: "268\u{A0}080\u{A0}Kč"))
    }

    /// Advances that pay exactly what the levies come to leave nothing to settle and nothing to get back: that is a
    /// settlement of nothing, not an overpayment.
    @Test func advancesThatPayExactlyTheLeviesLeaveNothingToSettle() throws {
        let input = inputWithout()
        var yearInput = PredictionSample.yearInput(year: 2026)
        yearInput.receipts = input.receipts
        let none = [Int64](repeating: 0, count: 12)
        yearInput.advances = AdvancePlan(
            social: [60_056] + none.dropFirst(), health: [39_664] + none.dropFirst(), tax: none)

        let page = PredictionBuilder.page(
            try PredictionOutcome.make(prediction: IncomePrediction.make(input), yearInput: yearInput))

        #expect(
            page.due
                == KeyFigureData(
                    eyebrow: "Odhad doplatku odvodů bez záloh", figure: "0\u{A0}Kč",
                    sentence: "Tolik si odložte stranou – navíc k zálohám 99\u{A0}720\u{A0}Kč, které platíte průběžně."
                        + " Platí se po skončení roku s přiznáním a přehledy pro ČSSZ a VZP.",
                    sentenceEmphasis: "99\u{A0}720\u{A0}Kč"))
        #expect(try row("Doplatek", in: section("Daň z příjmů", in: page)).value == "0\u{A0}Kč")
        #expect(
            try row("Zálohy za rok", in: section("Daň z příjmů", in: page)).note
                == "podle plánu záloh · 0\u{A0}plateb za celý rok")
    }

    /// The sample year with health advances of 12 000 Kč a month, 144 000 Kč, which pay 39 836 Kč more than the health
    /// insurance of 104 164 Kč while the tax and the social insurance still owe: what is owed is the sum of what those
    /// two leave, 166 058 Kč, and the overpayment at the health insurance does not lower it but is named beside it. It
    /// is still to arise in a year in progress. The advances of the year are 340 560 Kč: the sample's 268 080 Kč with
    /// the 144 000 Kč of health advances instead of its 71 520 Kč.
    @Test func aYearInProgressOverpaidAtOneAuthorityNamesThatOverpayment() throws {
        let outcome = try outcomeWithChangedAdvances(of: PredictionSample.input(year: 2026)) {
            $0.health = [Int64](repeating: 12_000, count: 12)
        }
        let page = PredictionBuilder.page(outcome)

        #expect(outcome.owedTotal == 166_058)
        #expect(outcome.overpaidTotal == 39_836)
        #expect(page.due.eyebrow == "Odhad doplatku odvodů bez záloh")
        #expect(page.due.figure == "166\u{A0}058\u{A0}Kč")
        #expect(
            page.due.sentence
                == "Tolik si odložte stranou – navíc k zálohám 340\u{A0}560\u{A0}Kč, které platíte průběžně."
                + " Platí se po skončení roku s přiznáním a přehledy pro ČSSZ a VZP."
                + " U některého úřadu vznikne přeplatek 39\u{A0}836\u{A0}Kč.")
        #expect(page.due.sentenceEmphasis == "340\u{A0}560\u{A0}Kč")
        // The health insurance is the one that is overpaid: the last row of its popover is the overpayment, in green.
        #expect(
            page.levyBar.parts[2].rows[2]
                == LevyPopoverRow(label: "Přeplatek", value: "39\u{A0}836\u{A0}Kč", style: .positive))
        #expect(page.levyBar.parts[0].rows[2].label == "Doplatek")
    }

    /// The same in 2025, which is over: health advances of 12 000 Kč a month pay 27 146 Kč more than the health
    /// insurance of 116 854 Kč while the tax and the social insurance owe 269 611 Kč beyond their advances. The
    /// overpayment has arisen, so the verb is in the past. The advances of the year are 295 400 Kč: the sample's
    /// 207 800 Kč with the 144 000 Kč of health advances instead of its 56 400 Kč.
    @Test func aYearOverOverpaidAtOneAuthoritySaysVznikl() throws {
        let outcome = try outcomeWithChangedAdvances(of: PredictionSample.input(year: 2025)) {
            $0.health = [Int64](repeating: 12_000, count: 12)
        }
        let page = PredictionBuilder.page(outcome)

        #expect(outcome.owedTotal == 269_611)
        #expect(outcome.overpaidTotal == 27_146)
        #expect(page.due.eyebrow == "Doplatek odvodů bez záloh")
        #expect(page.due.figure == "269\u{A0}611\u{A0}Kč")
        #expect(
            page.due.sentence
                == "Za rok 2025 navíc k zálohám 295\u{A0}400\u{A0}Kč"
                + " – daň, ČSSZ a VZP po podání přiznání a přehledů."
                + " U některého úřadu vznikl přeplatek 27\u{A0}146\u{A0}Kč.")
    }

    /// A single payment of 200 000 Kč leaves the tax a bonus of 37 524 Kč (`aNegativeTaxReadsAsABonus`). With no
    /// advance planned the minimum insurance of 99 720 Kč is left to pay, and the bonus, which the tax office pays, is
    /// an overpayment at that authority beside it, which the text names. (With the advances of the sample, which more
    /// than cover the insurance and the tax, nothing is owed and the settlement is the overpayment alone.)
    @Test func aTaxBonusBesideWhatIsOwedIsTheOverpayment() throws {
        let input = inputWithOnePaymentThatLeavesTheTaxAsABonus()
        let outcome = try outcomeWithChangedAdvances(of: input) { $0 = AdvancePlan.empty }
        let page = PredictionBuilder.page(outcome)

        #expect(outcome.overpaidTotal == 37_524)
        #expect(outcome.owedTotal == 99_720)
        #expect(page.due.eyebrow == "Odhad doplatku odvodů bez záloh")
        #expect(page.due.figure == "99\u{A0}720\u{A0}Kč")
        #expect(page.due.sentence?.hasSuffix(" U některého úřadu vznikne přeplatek 37\u{A0}524\u{A0}Kč.") == true)
        // The tax is a bonus that comes back: its popover says "Vrátí se", the others what is left to pay.
        let tax = page.levyBar.parts[0]
        #expect(tax.rows[2] == LevyPopoverRow(label: "Vrátí se", value: "37\u{A0}524\u{A0}Kč", style: .positive))
        #expect(page.levyBar.parts[1...].allSatisfy { $0.rows[2].label == "Doplatek" })
    }

    /// No advance is planned yet, as in every January before the advances are entered: the text keeps its words and
    /// names 0 Kč, and the whole of the levies is to be put aside.
    @Test func aYearInProgressWithNoPlannedAdvancesNamesZeroKc() throws {
        let outcome = try outcomeWithChangedAdvances(of: PredictionSample.input(year: 2026)) {
            $0 = AdvancePlan.empty
        }
        let page = PredictionBuilder.page(outcome)

        #expect(outcome.result.advancesPaidTotal == 0)
        // The figure repeats the sum of the levies and the sentence names 0 Kč, as the design draws it (D7).
        #expect(page.due.figure == page.keyFigure.figure)
        #expect(
            page.due
                == KeyFigureData(
                    eyebrow: "Odhad doplatku odvodů bez záloh", figure: "466\u{A0}782\u{A0}Kč",
                    sentence: "Tolik si odložte stranou – navíc k zálohám 0\u{A0}Kč, které platíte průběžně."
                        + " Platí se po skončení roku s přiznáním a přehledy pro ČSSZ a VZP.",
                    sentenceEmphasis: "0\u{A0}Kč"))
    }

    // MARK: The tax in the higher band

    /// An income of 3 000 000 Kč more (an adjustment of the year) brings the base to 4 386 600 Kč, which is over the
    /// band of 23 % from 1 762 812 Kč: the tax before the credits is 15 % of the band and 23 % of the rest,
    /// 264 421,80 + 603 471,24 = 867 893,04 Kč, rounded up. It is one row, as the card of the tax has no other.
    @Test func aBaseInTheHigherBandHasTheWholeTaxBeforeTheCreditsInOneRow() throws {
        var input = PredictionSample.input(year: 2026)
        input.receipts.append(
            Receipt(day: civilDate("2026-02-02"), czkNetHalere: 300_000_000, czkVatHalere: 0, source: .adjustment(1)))

        let tax = try section("Daň z příjmů", in: makePage(of: input))

        #expect(try row("Základ daně", in: tax).value == "4\u{A0}386\u{A0}600")
        let rate = try row("Sazba 15\u{A0}%", in: tax)
        #expect(rate.value == "867\u{A0}894")
        #expect(rate.note == "23\u{A0}% až ze základu nad 1\u{A0}762\u{A0}812")
        #expect(rate.sign == .times)
    }

    // MARK: The names of the clients

    /// The note of the expected invoices names the clients shortly: without what follows a comma, and without a legal
    /// form at the end.
    @Test func aClientNameInTheNoteLosesWhatFollowsItsCommaAndItsLegalForm() {
        let names: [(String, String)] = [
            ("Foxtrot, Inc.", "Foxtrot"), ("Sierra, SE", "Sierra"), ("Tango s.r.o.", "Tango"), ("Alfa a.s.", "Alfa"),
            ("Beta a. s.", "Beta"), ("Gama s. r. o.", "Gama"), ("Delta SE", "Delta"), ("Epsilon Inc.", "Epsilon"),
            ("Zeta se", "Zeta"), ("Nová Firma", "Nová Firma"), ("SE", "SE"),
            ("Soustava s.r.o. Brno", "Soustava s.r.o. Brno"), (", s.r.o.", ", s.r.o."),
        ]

        for (name, short) in names {
            #expect(PredictionBuilder.shortClientName(name) == short, "\(name)")
        }
    }

    // MARK: The sentence of no active client

    /// The sentence that no invoice is expected from any client leads to the group of the others, so it shows only
    /// when there are others to unfold and the year is open to change. Sierra alone is not active in 2026.
    @Test func theNoActiveSentenceShowsOnlyWithClientsToUnfold() throws {
        let sentence =
            "Od žádného odběratele teď fakturu nečekám."
            + " Rozbalte ostatní odběratele a označte měsíce, kdy faktura přijde."
        let onlySierra = inputWithout(
            clients: [PredictionSample.sierra],
            invoices: PredictionSample.invoices.filter { $0.clientID == sierra && $0.issueDate.year >= 2025 },
            templates: [PredictionSample.templates[2]])
        var closed = onlySierra
        closed.year = 2025
        closed.clients = [PredictionSample.tango]
        closed.invoices = []
        closed.receipts = []

        let open = try makePage(of: onlySierra)
        #expect(open.activeRows.isEmpty)
        #expect(open.otherRows.map(\.id) == [sierra])
        #expect(open.noActiveText == sentence)
        // No client at all, so nothing to unfold.
        #expect(try makePage(of: inputWithout()).noActiveText == nil)
        // A client who is active.
        #expect(try makePage().noActiveText == nil)
        #expect(try makePage(year: 2025).noActiveText == nil)
        // A year that is over, with the only client one that has no invoice in it: nothing can be marked.
        let over = try makePage(of: closed)
        #expect(over.activeRows.isEmpty)
        #expect(over.otherRows.map(\.id) == [tango])
        #expect(over.noActiveText == nil)
    }

    // MARK: Plurals

    /// A month with invoices says how many it has in Czech: "faktura 20260601" for one, "2 faktury" up to 4, and
    /// "5 faktur" from five on. Sierra's five months of the sample get 1, 2, 3, 4 and 5 invoices.
    @Test func aMonthWithSeveralInvoicesCountsThemInCzech() throws {
        var input = PredictionSample.input(year: 2026)
        var nextID: Int64 = 100
        // January keeps its one invoice, and each of the next four months gets one more than the month before it.
        for (month, extra) in [(1, 1), (2, 2), (3, 3), (4, 4)] {
            let model = try #require(input.invoices.first { $0.number == "2026-0\(month)-01" })
            for index in 1...extra {
                var copy = model
                copy.id = nextID
                copy.number = "2026-0\(month)-0\(index + 1)"
                nextID += 1
                input.invoices.append(copy)
            }
        }
        input.receipts = PredictionSample.receipts(of: input.invoices, year: 2026)

        let cells = try row(sierra, in: makePage(of: input)).cells

        #expect(cells[0].accessibilityLabel == "Leden: 2 faktury, 440\u{A0}000\u{A0}Kč, zaplaceno")
        #expect(cells[1].accessibilityLabel == "Únor: 3 faktury, 570\u{A0}000\u{A0}Kč, zaplaceno")
        #expect(cells[2].accessibilityLabel == "Březen: 4 faktury, 840\u{A0}000\u{A0}Kč, zaplaceno")
        #expect(cells[3].accessibilityLabel == "Duben: 5 faktur, 1\u{A0}050\u{A0}000\u{A0}Kč, zaplaceno")
        #expect(cells[4].accessibilityLabel == "Květen: faktura 2026-05-01, 210\u{A0}000\u{A0}Kč, zaplaceno")
    }

    // MARK: The approximation sign

    /// Every sign of an estimate in a year in progress has a no-break space after it, in the months, the notes and the
    /// breakdown, so that a line never ends with the sign alone. The pages are the sample's, the sample with other
    /// months chosen, a single invoice with a month on, and a year with the rules of another year, whose levies and
    /// settlement have no sign, as the result card of a year in progress is an estimate as a whole. The pages of the
    /// first three have an amount that is expected of a client, which has the sign; the page of the fourth, in the
    /// first weeks of a year, expects nothing.
    @Test func everyApproximationOfAYearInProgressIsFollowedByANoBreakSpace() throws {
        let client = Client(id: 1, name: "Jediný s.r.o.", dueDays: 14)
        var invoice = Invoice.fixture(
            number: "20260901", issued: "2026-09-30", dueDate: "2026-10-14", items: [.fixture("1", at: 1_000_000)])
        invoice.id = 1
        invoice.clientID = client.id
        var single = inputWithout(clients: [client], invoices: [invoice])
        single.changes = [1: [11: true]]
        let pages = [
            try makePage(), try makePage(changes: [foxtrot: [11: false], sierra: [11: true, 12: true]]),
            try makePage(of: single),
        ]
        let page2027 = PredictionBuilder.page(try outcomeOf2027())

        for page in pages {
            let all = texts(of: page)
            #expect(all.contains { $0.contains("≈") })
            #expect(approximationsWithoutNoBreakSpace(in: all).isEmpty, "\(approximationsWithoutNoBreakSpace(in: all))")
            // None of them is in the result card or in the card Příjmy.
            #expect((resultTexts(of: page) + incomeTexts(of: page)).filter { $0.contains("≈") }.isEmpty)
        }
        #expect(approximationsWithoutNoBreakSpace(in: texts(of: page2027)).isEmpty)
        #expect((resultTexts(of: page2027) + incomeTexts(of: page2027)).filter { $0.contains("≈") }.isEmpty)
    }

    /// An annual CZK caption explains the qualifying payments and their separate daily conversions.
    @Test func theCaptionExplainsAnnualDailyCZKAverages() throws {
        let page = try makePage()
        let client = try row(foxtrot, in: page)
        #expect(client.how.contains("285\u{00A0}693\u{00A0}Kč"))
        #expect(page.banner.contains("všech skutečných a očekávaných plateb v roce 2026"))
        #expect(page.banner.contains("každou zvlášť denním kurzem ČNB"))
        #expect(page.banner.contains("může lišit od uložených částek plateb"))
        #expect(!page.banner.contains("posledních tří"))
    }

    /// An unknown denominator leaves every bar fraction empty while preserving its known labels.
    @Test func incompleteOutcomesDoNotClaimKnownSubtotalShares() throws {
        var input = PredictionSample.input(year: 2026)
        input.averageRates = [:]
        let waitingClient = Client(id: 4, name: "Čekající", dueDays: 14)
        var waiting = Invoice.fixture(
            number: "WAITING-1", issued: "2026-10-01", duzp: "2026-10-01", dueDate: "2026-10-15",
            items: [.fixture("1", at: 1_000_000)])
        waiting.clientID = waitingClient.id
        input.clients.append(waitingClient)
        input.invoices.append(waiting)
        let outcome = try outcome(of: input)
        try #require(!outcome.prediction.isComplete)
        let page = PredictionBuilder.page(outcome)
        #expect(page.keyFigure.figure == "—")
        #expect(page.keyFigure.share == nil)
        #expect(page.due.figure == "—")
        #expect(page.incomeTotal == "—")
        #expect(page.netIncome.amount == "—")
        #expect(page.left.isEmpty && page.right.isEmpty)
        #expect(page.parts.allSatisfy { $0.fraction == 0 })
        #expect(page.parts[0].value == PredictionBuilder.kc(ofHalere: outcome.prediction.receivedHalere))
        #expect(page.parts[1].value == "10\u{00A0}000\u{00A0}Kč")
        #expect(try row(tango, in: page).how.contains("4\u{00A0}500\u{00A0}Kč"))
        #expect(page.banner.contains("chybí kurz"))
        #expect(page.nextYearNote?.contains("2027") == true)
        #expect(page.nextYearNote?.contains("chybí kurz") == true)
        let card = PredictionBuilder.card(outcome)
        #expect(card.stats.allSatisfy { $0.value == "—" && $0.share == nil })
        #expect(card.stats[0].sub.contains(page.parts[0].value))
        #expect(card.sub.contains("chybí kurz"))
    }

    /// An estimate that is not complete has an empty bar of the levies: no part has a width, the legend says "—" for
    /// each authority, and a popover has no figure that follows from the unknown amounts, only the advances, which the
    /// plan knows, and no share. The sentence that the estimate is incomplete stands once in the result card, under the
    /// key figure; what is left to settle names the planned advances only. The banner keeps its sentence, as it did.
    @Test func anIncompleteEstimateHasAnEmptyLevyBarAndSaysSoOnceInTheResultCard() throws {
        var input = PredictionSample.input(year: 2026)
        input.averageRates = [:]
        let waitingClient = Client(id: 4, name: "Čekající", dueDays: 14)
        var waiting = Invoice.fixture(
            number: "WAITING-1", issued: "2026-10-01", duzp: "2026-10-01", dueDate: "2026-10-15",
            items: [.fixture("1", at: 1_000_000)])
        waiting.clientID = waitingClient.id
        input.clients.append(waitingClient)
        input.invoices.append(waiting)
        let outcome = try outcome(of: input)
        try #require(!outcome.prediction.isComplete)
        let page = PredictionBuilder.page(outcome)
        let advances = CzechFormat.wholeKc(outcome.result.advancesPaidTotal)

        #expect(page.keyFigure.eyebrow == "Odhad odvodů za celý rok 2026")
        #expect(page.keyFigure.sentence == PredictionBuilder.incompleteText)
        #expect(page.levyBar.header == "Odvody za celý rok 2026 podle úřadů")
        #expect(page.levyBar.parts.map(\.weight) == [0, 0, 0])
        #expect(page.levyBar.parts.map(\.legendValue) == ["—", "—", "—"])
        #expect(page.levyBar.parts.allSatisfy { $0.shareLine == nil && $0.note == nil })
        for part in page.levyBar.parts {
            #expect(part.rows.map(\.label) == ["Odvody za rok", "Zálohy za rok", "Doplatek"])
            #expect(part.rows[0].value == "—" && part.rows[2].value == "—")
            #expect(part.rows[1].value == CzechFormat.wholeKc(outcome.result.balance(part.authority).advancesPaid))
            #expect(
                part.accessibilityLabel
                    == part.authority.title + ": odvody za rok —, zálohy za rok "
                    + CzechFormat.wholeKc(outcome.result.balance(part.authority).advancesPaid) + ", doplatek —")
        }
        #expect(
            page.levyBar.accessibilityLabel
                == "Odvody za celý rok 2026 podle úřadů: Daň z příjmů —, Sociální pojištění —, Zdravotní pojištění —")
        #expect(
            page.due
                == KeyFigureData(
                    eyebrow: "Odhad doplatku odvodů bez záloh", figure: "—",
                    sentence: "Plánované zálohy " + advances + " za celý rok.", sentenceEmphasis: advances))
        let sentence = PredictionBuilder.incompleteText
        #expect(resultTexts(of: page).filter { $0.contains(sentence) }.count == 1)
        #expect(page.banner.hasSuffix(sentence))
    }

    /// A known zero and an unknown month remain distinct even when both retain a zero subtotal.
    @Test func expectedCellsDistinguishKnownZeroFromUnknown() throws {
        let prediction = try PredictionSample.outcome(year: 2026).prediction
        var client = try #require(prediction.clients.first { $0.id == foxtrot })
        client.months[10].amountHalere = 0
        client.months[10].hasUnknownAmount = false
        var cell = PredictionBuilder.clientRow(client, in: prediction).cells[10]
        #expect(cell.value == "≈\u{00A0}0")
        #expect(cell.accessibilityLabel.contains("0\u{00A0}Kč"))
        client.months[10].hasUnknownAmount = true
        cell = PredictionBuilder.clientRow(client, in: prediction).cells[10]
        #expect(cell.value == "—")
        #expect(cell.sub == "bez částky")
        #expect(cell.accessibilityLabel.contains("částka není známá"))
    }

    /// An unavailable expected amount never turns into a displayed zero subtotal.
    @Test func aWhollyUnknownExpectedPartDoesNotReadAsZero() throws {
        var input = inputWithout(clients: [Client(id: 1, name: "Nový")])
        input.changes = [1: [11: true]]
        let page = try makePage(of: input)
        #expect(page.parts[2].value == "—")
        #expect(page.parts[2].text.contains("částka neznámá"))
        #expect(page.banner.contains("podklady pro odhad"))
    }

    /// An unknown prior-year waiting invoice has no month cell but must not claim that the client brings nothing.
    @Test(arguments: [false, true])
    func anUnknownPriorYearPaymentKeepsItsClientIncomplete(_ hasKnownWaiting: Bool) throws {
        let client = Client(id: 1, name: "Starší", dueDays: 14)
        var unknown = Invoice.fixture(
            number: "OLD-1", currency: .usd, issued: "2025-12-15", duzp: "2025-12-15",
            dueDate: "2025-12-29", items: [.fixture("1", at: 10_000)])
        unknown.clientID = client.id
        var invoices = [unknown]
        if hasKnownWaiting {
            var known = Invoice.fixture(
                number: "OLD-2", issued: "2025-12-16", duzp: "2025-12-16",
                dueDate: "2025-12-30", items: [.fixture("1", at: 100_000)])
            known.clientID = client.id
            invoices.append(known)
        }
        var input = inputWithout(clients: [client], invoices: invoices)
        input.rates = [:]
        input.averageRates = [
            PredictionRateKey(currency: .usd, day: civilDate("2025-12-15")):
                storedRate("USD", "20", declaredOn: "2025-12-15")
        ]
        let page = try makePage(of: input)
        let shown = try row(1, in: page)
        #expect(shown.cells.allSatisfy { $0.kind == .past || $0.kind == .notExpected })
        #expect(shown.adds == "—")
        #expect(!shown.addsIsMuted)
        #expect(shown.note?.contains("příjmů letos není úplná") == true)
        if hasKnownWaiting {
            #expect(shown.note?.contains("známá část 1\u{00A0}000\u{00A0}Kč") == true)
            #expect(page.parts[1].value == "1\u{00A0}000\u{00A0}Kč")
        }
    }

}
