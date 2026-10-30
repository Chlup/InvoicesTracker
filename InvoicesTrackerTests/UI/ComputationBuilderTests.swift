import Foundation
import Testing
@testable import InvoicesTracker

/// The breakdown of a year's computation that the builder makes from the result of the tax engine: its five cards,
/// their rows, notes and signs. The sample year is the engine's regression year as of 17. 10. 2026; its figures were
/// worked out for the same data by a separate implementation of the rules (exact fractions, run in Python), and so
/// were those of the other years below and of the card of the net income, which is that of the sample year of
/// `PredictionSample`. In every expected string `\u{00A0}` is the no-break space.
struct ComputationBuilderTests {
    // MARK: Helpers

    /// A row as the screen shows it: the texts and the sign in front of it.
    private struct Shown: Equatable {
        var label: String
        var value: String
        var note: String?
        var sign: String

        init(_ label: String, _ value: String, _ note: String? = nil, _ sign: String = "") {
            self.label = label
            self.value = value
            self.note = note
            self.sign = sign
        }
    }

    private func section(_ title: String, in sections: [ComputationSection]) throws -> ComputationSection {
        try #require(sections.first { $0.title == title }, "No section \(title)")
    }

    private func shown(_ title: String, in sections: [ComputationSection]) throws -> [Shown] {
        try section(title, in: sections).rows.map { Shown($0.label, $0.value, $0.note, $0.sign.rawValue) }
    }

    private func row(_ label: String, in title: String, of sections: [ComputationSection]) throws -> ComputationRow {
        try #require(section(title, in: sections).rows.first { $0.label == label }, "No row \(label) in \(title)")
    }

    private func labels(_ title: String, in sections: [ComputationSection]) throws -> [String] {
        try section(title, in: sections).rows.map(\.label)
    }

    /// The sections of `input` as of `asOf`, built from what the engine works out for it.
    private func build(
        _ input: YearInput, asOf: String = "2026-10-17", today: String = "2026-10-17",
        conversion: IncomeFXMethod = .cnbDaily
    ) -> [ComputationSection] {
        let result = TaxEngine.compute(input, asOf: civilDate(asOf))
        return ComputationBuilder.build(result, input: input, today: civilDate(today), incomeFXMethod: conversion)
    }

    /// A year of these tests: see `computationYearInput`.
    private func yearInput(
        year: Int = 2026, netHalere: Int64 = 0, vatHalere: Int64 = 0, adjustmentHalere: Int64 = 0,
        months: [MonthActivity] = [MonthActivity](repeating: .main, count: 12), percent: Int = 60,
        deductions: Deductions = Deductions(), credit: Bool = true, advances: AdvancePlan = .empty
    ) -> YearInput {
        computationYearInput(
            year: year, netHalere: netHalere, vatHalere: vatHalere, adjustmentHalere: adjustmentHalere,
            months: months, percent: percent, deductions: deductions, credit: credit, advances: advances)
    }

    private let sample = TaxEngineRegressionTests.sampleYear2026

    private let incomeCard = "Příjmy a zisk"
    private let taxCard = "Daň z příjmů"
    private let socialCard = "Sociální pojištění"
    private let healthCard = "Zdravotní pojištění"
    private let netIncomeCard = "Čistý příjem"
    private var titles: [String] {
        [incomeCard, taxCard, socialCard, healthCard, netIncomeCard]
    }

    private let secondaryYear = computationSecondaryYear
    private let mixedYear = computationMixedYear

    /// What stands under the advances of the three authorities.
    private let month = "v měsíci, ke kterému patří"

    // MARK: The sample year, card by card

    @Test func theSectionsAreTheFiveCardsOfTheBreakdownWithTheColoursOfTheAuthorities() {
        let sections = build(sample)

        #expect(sections.map(\.title) == titles)
        #expect(sections.map(\.id) == titles)
        #expect(sections.map(\.authority) == [nil, .tax, .social, .health, nil])
        #expect(sections.map(\.isNetIncome) == [false, false, false, false, true])
    }

    @Test func theInsurancesAndTheNetIncomeStandOnTheRightAndTheIncomeAndTheTaxOnTheLeft() {
        let sections = build(sample)

        #expect(sections.map(\.standsRight) == [false, false, true, true, true])
        // The place follows from the authority and the net income alone: a card of none or of the tax stands on the
        // left, unless it is the net income.
        #expect(ComputationSection(title: "A", rows: []).standsRight == false)
        #expect(ComputationSection(title: "A", rows: [], authority: .tax).standsRight == false)
        #expect(ComputationSection(title: "A", rows: [], authority: .social).standsRight)
        #expect(ComputationSection(title: "A", rows: [], authority: .health).standsRight)
        #expect(ComputationSection(title: "A", rows: [], isNetIncome: true).standsRight)
    }

    @Test func incomeAndProfitShowThePaymentsTheVATTheRoundedIncomeTheExpensesAndTheProfit() throws {
        let sections = build(sample)

        #expect(
            try shown(incomeCard, in: sections) == [
                Shown(
                    "Přijaté platby", "2\u{00A0}412\u{00A0}061,35",
                    "1.\u{00A0}1. – 17.\u{00A0}10. · cizí měny v Kč ke dni přijetí"),
                Shown(
                    "DPH z přijatých plateb", "\u{2212}220\u{00A0}290,00", "vede se zvlášť, do příjmů nepatří",
                    "\u{2212}"),
                Shown("Příjmy bez DPH", "2\u{00A0}191\u{00A0}771,35", nil, "="),
                Shown(
                    "Příjmy z podnikání (§ 7)", "2\u{00A0}191\u{00A0}771,00",
                    "od poloviny nahoru · zaokrouhlení příjmů na celé Kč a výdajů dolů je konvence aplikace"
                        + " – zákon směr nepředepisuje",
                    "="),
                Shown(
                    "Výdajový paušál 60\u{00A0}%", "\u{2212}1\u{00A0}200\u{00A0}000,00",
                    "60\u{00A0}% je 1\u{00A0}315\u{00A0}062,00 → použije se strop 1\u{00A0}200\u{00A0}000",
                    "\u{2212}"),
                Shown(
                    "Zisk (dílčí základ daně)", "991\u{00A0}771,00",
                    "strop paušálu je vyčerpaný – další příjem je celý ziskem", "="),
            ])
    }

    @Test func theTaxCardShowsTheProfitTheDeductionsTheBaseTheBandsTheCreditAndTheAdvances() throws {
        let sections = build(sample)

        #expect(
            try shown(taxCard, in: sections) == [
                Shown("Zisk", "991\u{00A0}771,00"),
                Shown(
                    "Nezdanitelné části základu", "\u{2212}156\u{00A0}480,00",
                    "úroky z hypotéky 150\u{00A0}000 z 219\u{00A0}000 (limit) · spoření a pojištění 6\u{00A0}480",
                    "\u{2212}"),
                Shown("Základ daně", "835\u{00A0}200", "zaokrouhleno na celé stovky dolů", "="),
                Shown(
                    "Sazba 15\u{00A0}%", "125\u{00A0}280",
                    "z 835\u{00A0}200 základu (pásmo do 1\u{00A0}762\u{00A0}812)"
                        + " · pravidla 2026 · ověřeno 20.\u{00A0}10.\u{00A0}2026",
                    "×"),
                Shown("Sazba 23\u{00A0}%", "0", "pásmo nad 1\u{00A0}762\u{00A0}812 zatím nedosaženo", "×"),
                Shown("Daň před slevou", "125\u{00A0}280", "zaokrouhleno na celé koruny nahoru", "="),
                Shown("Sleva na poplatníka", "\u{2212}30\u{00A0}840", "celá roční částka", "\u{2212}"),
                Shown("Daň z dosavadních příjmů", "94\u{00A0}440", nil, "="),
                Shown("Zálohy", "\u{2212}23\u{00A0}000", "1 ze 2 · \(month)", "\u{2212}"),
                Shown(
                    "Zbývá", "71\u{00A0}440\u{00A0}Kč",
                    "odejde plánovanými zálohami 23\u{00A0}000 · doplatek po přiznání 48\u{00A0}440", "="),
            ])
    }

    @Test func socialInsuranceShowsTheComputedBaseTheBaseWithItsMinimumAndMaximumTheInsuranceAndTheAdvances() throws {
        let sections = build(sample)

        #expect(
            try shown(socialCard, in: sections) == [
                Shown("Vypočtený základ", "545\u{00A0}475", "55\u{00A0}% zisku, zaokrouhleno nahoru"),
                Shown(
                    "Vyměřovací základ", "545\u{00A0}475",
                    "55\u{00A0}% zisku, nahoru · min. 171\u{00A0}390 (17\u{00A0}139 × 10\u{00A0}měsíců hlavní činnosti)"
                        + " · max. 2\u{00A0}350\u{00A0}416 (roční strop, nekrátí se)"),
                Shown("Sazba 29,2\u{00A0}%", "159\u{00A0}279", "zaokrouhleno na celé koruny nahoru", "×"),
                Shown("Zálohy", "\u{2212}126\u{00A0}260", "10 ze 12 · \(month)", "\u{2212}"),
                Shown(
                    "Zbývá", "33\u{00A0}019\u{00A0}Kč",
                    "odejde plánovanými zálohami 24\u{00A0}300 · doplatek po přehledu 8\u{00A0}719", "="),
            ])
    }

    @Test func healthInsuranceShowsTheBasesInHalereTheMinimumWithItsMonthsTheInsuranceAndTheAdvances() throws {
        let sections = build(sample)

        #expect(
            try shown(healthCard, in: sections) == [
                Shown("Vypočtený základ", "495\u{00A0}885,50", "50\u{00A0}% zisku"),
                Shown(
                    "Vyměřovací základ", "495\u{00A0}885,50",
                    "50\u{00A0}% zisku · min. 244\u{00A0}835,00 (24\u{00A0}483,50 × 10\u{00A0}měsíců)"
                        + " · bez maxima, nezaokrouhluje se"),
                Shown("Sazba 13,5\u{00A0}%", "66\u{00A0}945", "zaokrouhleno na celé koruny nahoru", "×"),
                Shown("Zálohy", "\u{2212}60\u{00A0}560", "10 ze 12 · \(month)", "\u{2212}"),
                Shown(
                    "Zbývá", "6\u{00A0}385\u{00A0}Kč",
                    "odejde plánovanými zálohami 6\u{00A0}385 z plánovaných 10\u{00A0}960"
                        + " (započte se nejvýše to, co zbývá) · doplatek po přehledu 0", "="),
            ])
    }

    @Test func theResultsOfACardAreBoldAndTheAmountLeftToPayIsTheTotal() throws {
        let sections = build(sample)

        func style(_ label: String, in title: String) throws -> ComputationRowStyle {
            try row(label, in: title, of: sections).style
        }
        #expect(try style("Příjmy z podnikání (§ 7)", in: incomeCard) == .strong)
        #expect(try style("Zisk (dílčí základ daně)", in: incomeCard) == .strong)
        #expect(try style("Základ daně", in: taxCard) == .strong)
        #expect(try style("Daň z dosavadních příjmů", in: taxCard) == .strong)
        #expect(try style("Zbývá", in: taxCard) == .total)
        #expect(try style("Zbývá", in: socialCard) == .total)
        #expect(try style("Zbývá", in: healthCard) == .total)
        #expect(try style("Přijaté platby", in: incomeCard) == .plain)
        #expect(try style("Sazba 29,2\u{00A0}%", in: socialCard) == .plain)
        #expect(try style("Zálohy", in: taxCard) == .plain)
    }

    @Test func aSubtractedRowIsSpokenWithItsMinusAndItsNote() throws {
        let sections = build(sample)

        let advances = try row("Zálohy", in: socialCard, of: sections)
        #expect(advances.spokenText == "Zálohy: \u{2212}126\u{00A0}260. 10 ze 12 · \(month)")
        // A row without a note is the label and the value.
        #expect(
            try row("Daň z dosavadních příjmů", in: taxCard, of: sections).spokenText
                == "Daň z dosavadních příjmů: 94\u{00A0}440")
    }

    // MARK: The conventions

    @Test func theConventionsOfTheAppAreWordedOnceForTheScreenAndForTheSettings() {
        #expect(
            ComputationBuilder.roundingConvention
                == "zaokrouhlení příjmů na celé Kč a výdajů dolů je konvence aplikace – zákon směr nepředepisuje")
        #expect(
            ComputationBuilder.incomeRoundingNote == "od poloviny nahoru · " + ComputationBuilder.roundingConvention)
        #expect(
            ComputationBuilder.notReachedMonthsConvention
                == "měsíce po zvoleném dni se u snížené rozhodné částky počítají jako měsíce bez vedlejší činnosti"
                + " – konvence aplikace, zákon to neřeší")
        #expect(
            ComputationBuilder.rulesVersion(of: TaxRules.forYear(2026).rules)
                == "pravidla 2026 · ověřeno 20.\u{00A0}10.\u{00A0}2026")
    }

    @Test func incomeIsRoundedHalfUpAndTheExpensesDownAndTheRowsSayHow() throws {
        // 100 001,50 Kč is 100 002 Kč rounded half up; 60 % of that is 60 001,20 Kč, rounded down to 60 001 Kč.
        let sections = build(yearInput(netHalere: 10_000_150))

        #expect(
            try shown(incomeCard, in: sections).map(\.value) == [
                "100\u{00A0}001,50", "0,00", "100\u{00A0}001,50", "100\u{00A0}002,00", "\u{2212}60\u{00A0}001,00",
                "40\u{00A0}001,00",
            ])
        let expenses = try row("Výdajový paušál 60\u{00A0}%", in: incomeCard, of: sections)
        #expect(
            expenses.note
                == "60\u{00A0}% z příjmů, zaokrouhleno dolů · strop 1\u{00A0}200\u{00A0}000 zatím nedosažen")
        let profit = try row("Zisk (dílčí základ daně)", in: incomeCard, of: sections)
        #expect(profit.note == nil)
    }

    // MARK: Income

    @Test func aSinglePaymentIsNamedInTheSingularInTheTagOfTheSection() throws {
        let sections = build(yearInput(netHalere: 10_000_150))

        #expect(sections.first?.tag == "1\u{00A0}platba")
        let payments = try row("Přijaté platby", in: incomeCard, of: sections)
        #expect(payments.note == "1.\u{00A0}1. – 17.\u{00A0}10. · cizí měny v Kč ke dni přijetí")
    }

    @Test func paymentsAreCountedInTheTagInTheFormCzechWants() {
        func tag(payments: Int) -> String? {
            var input = yearInput()
            input.receipts = (0..<payments).map { index in
                Receipt(
                    day: civilDate("2026-03-02"), czkNetHalere: 100_000, czkVatHalere: 0,
                    source: .invoice(Int64(index + 1)))
            }
            return build(input).first?.tag
        }

        #expect(tag(payments: 0) == "0\u{00A0}plateb")
        #expect(tag(payments: 2) == "2\u{00A0}platby")
        #expect(tag(payments: 4) == "4\u{00A0}platby")
        #expect(tag(payments: 5) == "5\u{00A0}plateb")
    }

    @Test func anIncomeAdjustmentAddsItsRowAndIsNotCountedAsAPayment() throws {
        // A payment of 100 001,50 Kč and an adjustment of −1 000,00 Kč.
        let sections = build(yearInput(netHalere: 10_000_150, adjustmentHalere: -100_000))

        #expect(
            try shown(incomeCard, in: sections) == [
                Shown(
                    "Přijaté platby", "100\u{00A0}001,50",
                    "1.\u{00A0}1. – 17.\u{00A0}10. · cizí měny v Kč ke dni přijetí"),
                Shown("DPH z přijatých plateb", "0,00", "vede se zvlášť, do příjmů nepatří", "\u{2212}"),
                Shown(
                    "Úpravy příjmů", "\u{2212}1\u{00A0}000,00",
                    "Nastavení › Rok · dobropisy, vratky a platby mimo faktury", "+"),
                Shown("Příjmy bez DPH", "99\u{00A0}001,50", nil, "="),
                Shown(
                    "Příjmy z podnikání (§ 7)", "99\u{00A0}002,00",
                    "od poloviny nahoru · " + ComputationBuilder.roundingConvention, "="),
                Shown(
                    "Výdajový paušál 60\u{00A0}%", "\u{2212}59\u{00A0}401,00",
                    "60\u{00A0}% z příjmů, zaokrouhleno dolů · strop 1\u{00A0}200\u{00A0}000 zatím nedosažen",
                    "\u{2212}"),
                Shown("Zisk (dílčí základ daně)", "39\u{00A0}601,00", nil, "="),
            ])
    }

    @Test func aPositiveAdjustmentIsAddedWithoutAMinus() throws {
        let sections = build(yearInput(netHalere: 10_000_150, adjustmentHalere: 250_000))

        let adjustment = try row("Úpravy příjmů", in: incomeCard, of: sections)
        #expect(adjustment.value == "2\u{00A0}500,00")
        #expect(adjustment.sign == .plus)
        #expect(try row("Příjmy bez DPH", in: incomeCard, of: sections).value == "102\u{00A0}501,50")
    }

    @Test func withoutAnAdjustmentThereIsNoRowForIt() throws {
        #expect(try !labels(incomeCard, in: build(sample)).contains("Úpravy příjmů"))
        #expect(try !labels(incomeCard, in: build(yearInput())).contains("Úpravy příjmů"))
    }

    @Test func adjustmentsThatCancelEachOtherLeaveNoRowAndTheRowsStillAddUp() throws {
        var input = yearInput(netHalere: 10_000_150, adjustmentHalere: 100_000)
        input.receipts.append(
            Receipt(day: civilDate("2026-03-04"), czkNetHalere: -100_000, czkVatHalere: 0, source: .adjustment(2)))
        let sections = build(input)

        // No net adjustment, so no row; the payment less its VAT is the income.
        #expect(try !labels(incomeCard, in: sections).contains("Úpravy příjmů"))
        #expect(try row("Příjmy bez DPH", in: incomeCard, of: sections).value == "100\u{00A0}001,50")
    }

    @Test func theUniformRateIsNamedWhenTheYearConvertsWithIt() throws {
        let sections = build(sample, conversion: .uniform)

        let payments = try row("Přijaté platby", in: incomeCard, of: sections)
        #expect(payments.note == "1.\u{00A0}1. – 17.\u{00A0}10. · cizí měny v Kč jednotným kurzem 2026")
    }

    /// The texts that name the conversion of the income in other currencies say the method the year uses: the note of
    /// the payments received and the assumptions, which name where the uniform rate is from when that is known.
    @Test func theConversionTextsFollowTheMethodTheYearUses() throws {
        let daily = computationPage(sample, conversion: .cnbDaily, uniformSource: "pokyn GFŘ-D-75")
        let uniform = computationPage(
            computationYearInput(year: 2025, netHalere: 10_000_150), asOf: "2025-12-31", conversion: .uniform,
            uniformSource: "pokyn GFŘ-D-75")
        let typed = computationPage(sample, conversion: .uniform, uniformSource: "zadáno ručně")
        let unknown = computationPage(sample, conversion: .uniform)

        #expect(
            daily.sections.first?.rows.first?.note == "1.\u{00A0}1. – 17.\u{00A0}10. · cizí měny v Kč ke dni přijetí")
        #expect(daily.assumptions.items[3] == "Cizí měny v Kč kurzem ČNB ke dni přijetí platby")
        #expect(
            uniform.sections.first?.rows.first?.note
                == "1.\u{00A0}1. – 31.\u{00A0}12. · cizí měny v Kč jednotným kurzem 2025")
        #expect(uniform.assumptions.items[3] == "Cizí měny v Kč jednotným kurzem 2025 (pokyn GFŘ-D-75)")
        #expect(typed.assumptions.items[3] == "Cizí měny v Kč jednotným kurzem 2026 (zadáno ručně)")
        #expect(unknown.assumptions.items[3] == "Cizí měny v Kč jednotným kurzem 2026")
    }

    @Test func aLossIsShownWithTheMinusSignAndNoExpenses() throws {
        // A payment of 1 000 Kč and an adjustment of −3 000 Kč: income of −2 000 Kč, no expenses, a loss.
        let sections = build(yearInput(netHalere: 100_000, adjustmentHalere: -300_000))

        #expect(try row("Příjmy bez DPH", in: incomeCard, of: sections).value == "\u{2212}2\u{00A0}000,00")
        #expect(
            try row("Příjmy z podnikání (§ 7)", in: incomeCard, of: sections).value == "\u{2212}2\u{00A0}000,00")
        #expect(try row("Výdajový paušál 60\u{00A0}%", in: incomeCard, of: sections).value == "0,00")
        #expect(
            try row("Zisk (dílčí základ daně)", in: incomeCard, of: sections).value == "\u{2212}2\u{00A0}000,00")
        #expect(try row("Zisk", in: taxCard, of: sections).value == "\u{2212}2\u{00A0}000,00")
        #expect(try row("Základ daně", in: taxCard, of: sections).value == "0")
    }

    // MARK: Expenses

    @Test func theCapIsNamedWhenItAppliesAtOtherRatesToo() throws {
        // 80 % of 2 100 000 Kč is 1 680 000 Kč, over the cap of 1 600 000 Kč.
        let sections = build(yearInput(netHalere: 210_000_000, percent: 80))

        let expenses = try row("Výdajový paušál 80\u{00A0}%", in: incomeCard, of: sections)
        #expect(expenses.value == "\u{2212}1\u{00A0}600\u{00A0}000,00")
        #expect(
            expenses.note
                == "80\u{00A0}% je 1\u{00A0}680\u{00A0}000,00 → použije se strop 1\u{00A0}600\u{00A0}000")
    }

    @Test func exactlyAtTheCapTheNoteSaysThatTheRateIsTheCapAndTheProfitIsNotShieldedAnyMore() throws {
        // 60 % of 2 000 000 Kč is exactly the cap: the cap is reached, though it cut nothing off.
        let sections = build(yearInput(netHalere: 200_000_000))

        let expenses = try row("Výdajový paušál 60\u{00A0}%", in: incomeCard, of: sections)
        #expect(expenses.value == "\u{2212}1\u{00A0}200\u{00A0}000,00")
        #expect(expenses.note == "60\u{00A0}% je přesně strop 1\u{00A0}200\u{00A0}000")
        #expect(
            try row("Zisk (dílčí základ daně)", in: incomeCard, of: sections).note
                == "strop paušálu je vyčerpaný – další příjem je celý ziskem")
    }

    @Test func oneCrownBelowTheCapTheCapIsNotReached() throws {
        // 60 % of 1 999 999 Kč is 1 199 999,40 Kč, rounded down to 1 199 999 Kč.
        let sections = build(yearInput(netHalere: 199_999_900))

        let expenses = try row("Výdajový paušál 60\u{00A0}%", in: incomeCard, of: sections)
        #expect(expenses.value == "\u{2212}1\u{00A0}199\u{00A0}999,00")
        #expect(
            expenses.note
                == "60\u{00A0}% z příjmů, zaokrouhleno dolů · strop 1\u{00A0}200\u{00A0}000 zatím nedosažen")
        #expect(try row("Zisk (dílčí základ daně)", in: incomeCard, of: sections).note == nil)
    }

    @Test func aYearThatIsOverDoesNotSayThatTheCapIsNotReachedYet() throws {
        let sections = build(
            yearInput(year: 2025, netHalere: 10_000_150), asOf: "2025-12-31", today: "2026-10-17")

        #expect(
            try row("Výdajový paušál 60\u{00A0}%", in: incomeCard, of: sections).note
                == "60\u{00A0}% z příjmů, zaokrouhleno dolů · strop 1\u{00A0}200\u{00A0}000 nedosažen")
    }

    // MARK: Deductions and the base

    @Test func withoutDeductionsTheRowSaysNone() throws {
        let sections = build(yearInput(netHalere: 10_000_150))

        let deductions = try row("Nezdanitelné části základu", in: taxCard, of: sections)
        #expect(deductions.value == "0,00")
        #expect(deductions.note == "žádné")
    }

    @Test func eachDeductionIsListedWithWhatCountsAndWhatTheLimitCutOff() throws {
        // 1 000 000 Kč of income, 600 000 Kč of expenses, a profit of 400 000 Kč. The interest is within its limit, the
        // pension savings are over the shared limit of 48 000 Kč, and 500 Kč of gifts are below the minimum.
        let claims = Deductions(mortgageInterestPaid: 100_000, pensionSavings: 60_000, gifts: 500)
        let sections = build(yearInput(netHalere: 100_000_000, deductions: claims))

        let deductions = try row("Nezdanitelné části základu", in: taxCard, of: sections)
        #expect(deductions.value == "\u{2212}148\u{00A0}000,00")
        #expect(
            deductions.note
                == "úroky z hypotéky 100\u{00A0}000 · spoření a pojištění 48\u{00A0}000 z 60\u{00A0}000 (limit)"
                + " · dary 500 (pod minimem – neuplatní se)")
        #expect(try row("Základ daně", in: taxCard, of: sections).value == "252\u{00A0}000")
    }

    @Test func giftsOverTheirLimitAreListedWithTheLimit() throws {
        // A profit of 400 000 Kč allows gifts of 30 % of it, 120 000 Kč.
        let sections = build(yearInput(netHalere: 100_000_000, deductions: Deductions(gifts: 150_000)))

        let deductions = try row("Nezdanitelné části základu", in: taxCard, of: sections)
        #expect(deductions.value == "\u{2212}120\u{00A0}000,00")
        #expect(deductions.note == "dary 120\u{00A0}000 z 150\u{00A0}000 (limit)")
    }

    @Test func deductionsTogetherTakeOffAtMostTheProfitAndTheRowSaysSo() throws {
        // A profit of 100 000 Kč and interest of 150 000 Kč, which is within its limit.
        let sections = build(yearInput(netHalere: 25_000_000, deductions: Deductions(mortgageInterestPaid: 150_000)))

        let deductions = try row("Nezdanitelné části základu", in: taxCard, of: sections)
        #expect(deductions.value == "\u{2212}100\u{00A0}000,00")
        #expect(deductions.note == "úroky z hypotéky 150\u{00A0}000 · celkem nejvýše do výše zisku")
        #expect(try row("Základ daně", in: taxCard, of: sections).value == "0")
    }

    @Test func giftsAreCutToNothingWhereThereIsNoProfitToTakeThemFrom() throws {
        // A loss: the limit on gifts is 30 % of nothing, so 500 Kč of gifts are allowed none of it.
        let sections = build(
            yearInput(netHalere: 100_000, adjustmentHalere: -300_000, deductions: Deductions(gifts: 500)))

        let deductions = try row("Nezdanitelné části základu", in: taxCard, of: sections)
        #expect(deductions.value == "0,00")
        #expect(deductions.note == "dary 0 z 500 (limit)")
    }

    @Test func pensionSavingsAndLifeInsuranceHaveTheirOwnLimitsBefore2024() throws {
        let claims = Deductions(lifeInsurance: 10_000, pensionSavings: 30_000)
        let sections = build(
            yearInput(year: 2022, netHalere: 100_000_000, deductions: claims), asOf: "2022-12-31")

        let deductions = try row("Nezdanitelné části základu", in: taxCard, of: sections)
        #expect(deductions.value == "\u{2212}34\u{00A0}000,00")
        #expect(
            deductions.note
                == "penzijní spoření 24\u{00A0}000 z 30\u{00A0}000 (limit) · životní pojištění 10\u{00A0}000")
    }

    // MARK: Tax

    @Test func aHighIncomeSplitsTheTaxIntoTheTwoBands() throws {
        // 5 700 000 Kč of income: the profit and the base are 4 500 000 Kč, 1 762 812 Kč of them at 15 % and
        // 2 737 188 Kč at 23 %.
        let sections = build(yearInput(netHalere: 570_000_000))

        #expect(
            try shown(taxCard, in: sections).prefix(8) == [
                Shown("Zisk", "4\u{00A0}500\u{00A0}000,00"),
                Shown("Nezdanitelné části základu", "0,00", "žádné", "\u{2212}"),
                Shown("Základ daně", "4\u{00A0}500\u{00A0}000", "zaokrouhleno na celé stovky dolů", "="),
                Shown(
                    "Sazba 15\u{00A0}%", "264\u{00A0}421,80",
                    "z 1\u{00A0}762\u{00A0}812 základu (pásmo do 1\u{00A0}762\u{00A0}812)"
                        + " · pravidla 2026 · ověřeno 20.\u{00A0}10.\u{00A0}2026",
                    "×"),
                Shown(
                    "Sazba 23\u{00A0}%", "629\u{00A0}553,24",
                    "z 2\u{00A0}737\u{00A0}188 základu (pásmo nad 1\u{00A0}762\u{00A0}812)", "×"),
                Shown("Daň před slevou", "893\u{00A0}976", "zaokrouhleno na celé koruny nahoru", "="),
                Shown("Sleva na poplatníka", "\u{2212}30\u{00A0}840", "celá roční částka", "\u{2212}"),
                Shown("Daň z dosavadních příjmů", "863\u{00A0}136", nil, "="),
            ])
        let expenses = try row("Výdajový paušál 60\u{00A0}%", in: incomeCard, of: sections)
        #expect(
            expenses.note
                == "60\u{00A0}% je 3\u{00A0}420\u{00A0}000,00 → použije se strop 1\u{00A0}200\u{00A0}000")
    }

    @Test func theTwoPartsOfTheTaxRoundedUpGiveTheTaxBeforeTheCredit() throws {
        // The parts are shown in haléře where they have any and add up exactly; the tax is their sum rounded up to
        // whole crowns.
        for income: Int64 in [570_000_000, 400_000_000, 100_000_000, 10_000_150] {
            let input = yearInput(netHalere: income)
            let result = TaxEngine.compute(input, asOf: civilDate("2026-10-17"))
            let sections = ComputationBuilder.build(
                result, input: input, today: civilDate("2026-10-17"), incomeFXMethod: .cnbDaily)

            let low = try row("Sazba 15\u{00A0}%", in: taxCard, of: sections).value
            let high = try row("Sazba 23\u{00A0}%", in: taxCard, of: sections).value
            let before = try row("Daň před slevou", in: taxCard, of: sections).value
            let sum = minorUnits(of: low) + minorUnits(of: high)
            let rounded = (sum + 99) / 100
            #expect(before == CzechFormat.grouped(rounded))
            #expect(rounded == result.taxBeforeCredit)
        }
    }

    @Test func aSmallTaxTakesTheCreditOnlyUpToTheTax() throws {
        // The profit of 40 001 Kč gives a base of 40 000 Kč and a tax of 6 000 Kč, less than the credit of 30 840 Kč.
        let sections = build(yearInput(netHalere: 10_000_150))

        #expect(
            try shown(taxCard, in: sections) == [
                Shown("Zisk", "40\u{00A0}001,00"),
                Shown("Nezdanitelné části základu", "0,00", "žádné", "\u{2212}"),
                Shown("Základ daně", "40\u{00A0}000", "zaokrouhleno na celé stovky dolů", "="),
                Shown(
                    "Sazba 15\u{00A0}%", "6\u{00A0}000",
                    "z 40\u{00A0}000 základu (pásmo do 1\u{00A0}762\u{00A0}812)"
                        + " · pravidla 2026 · ověřeno 20.\u{00A0}10.\u{00A0}2026",
                    "×"),
                Shown("Sazba 23\u{00A0}%", "0", "pásmo nad 1\u{00A0}762\u{00A0}812 zatím nedosaženo", "×"),
                Shown("Daň před slevou", "6\u{00A0}000", "zaokrouhleno na celé koruny nahoru", "="),
                Shown(
                    "Sleva na poplatníka", "\u{2212}6\u{00A0}000",
                    "roční sleva 30\u{00A0}840 se uplatní nejvýše do výše daně", "\u{2212}"),
                Shown("Daň z dosavadních příjmů", "0", nil, "="),
                Shown("Zálohy", "0", "žádné zálohy v plánu", "\u{2212}"),
                Shown("Zbývá", "0\u{00A0}Kč", nil, "="),
            ])
    }

    @Test func aCreditThatIsNotClaimedIsNotApplied() throws {
        let sections = build(yearInput(netHalere: 10_000_150, credit: false))

        let credit = try row("Sleva na poplatníka", in: taxCard, of: sections)
        #expect(credit.value == "0")
        #expect(credit.note == "neuplatňuje se")
        #expect(try row("Daň z dosavadních příjmů", in: taxCard, of: sections).value == "6\u{00A0}000")
    }

    // MARK: The family

    /// `input` with `family`.
    private func withFamily(
        _ input: YearInput, _ family: FamilyFacts = TaxEngineFamilyTests.sampleFamily
    ) -> YearInput {
        var input = input
        input.family = family
        return input
    }

    /// The sample year with the sample family, Anna (3. 9. 2019) and Tomáš (12. 4. 2024) and a spouse without income of
    /// her own: after the taxpayer credit the spouse credit takes 24 840 Kč off, which leaves 69 600 Kč, and the
    /// children take 37 524 Kč more, Anna 15 204 Kč as the first child and Tomáš 22 320 Kč as the second, to 32 076 Kč.
    /// The tax advance of June leaves 9 076 Kč, which the advance of December covers.
    @Test func theTaxCardShowsTheFamilySteps() throws {
        let sections = build(withFamily(sample))

        #expect(
            try shown(taxCard, in: sections) == [
                Shown("Zisk", "991\u{00A0}771,00"),
                Shown(
                    "Nezdanitelné části základu", "\u{2212}156\u{00A0}480,00",
                    "úroky z hypotéky 150\u{00A0}000 z 219\u{00A0}000 (limit) · spoření a pojištění 6\u{00A0}480",
                    "\u{2212}"),
                Shown("Základ daně", "835\u{00A0}200", "zaokrouhleno na celé stovky dolů", "="),
                Shown(
                    "Sazba 15\u{00A0}%", "125\u{00A0}280",
                    "z 835\u{00A0}200 základu (pásmo do 1\u{00A0}762\u{00A0}812)"
                        + " · pravidla 2026 · ověřeno 20.\u{00A0}10.\u{00A0}2026",
                    "×"),
                Shown("Sazba 23\u{00A0}%", "0", "pásmo nad 1\u{00A0}762\u{00A0}812 zatím nedosaženo", "×"),
                Shown("Daň před slevou", "125\u{00A0}280", "zaokrouhleno na celé koruny nahoru", "="),
                Shown("Sleva na poplatníka", "\u{2212}30\u{00A0}840", "celá roční částka", "\u{2212}"),
                Shown(
                    "Sleva na manžela / manželku", "\u{2212}24\u{00A0}840", "12\u{00A0}měsíců s dítětem do 3 let",
                    "\u{2212}"),
                Shown("Daň po slevách", "69\u{00A0}600", "slevy snižují daň nejvýš na nulu", "="),
                Shown(
                    "Daňové zvýhodnění na děti", "\u{2212}37\u{00A0}524",
                    "Anna 15\u{00A0}204 · Tomáš 22\u{00A0}320", "\u{2212}"),
                Shown("Daň z dosavadních příjmů", "32\u{00A0}076", nil, "="),
                Shown("Zálohy", "\u{2212}23\u{00A0}000", "1 ze 2 · \(month)", "\u{2212}"),
                Shown(
                    "Zbývá", "9\u{00A0}076\u{00A0}Kč",
                    "odejde plánovanými zálohami 9\u{00A0}076 z plánovaných 23\u{00A0}000"
                        + " (započte se nejvýše to, co zbývá) · doplatek po přiznání 0",
                    "="),
            ])
        #expect(try row("Daň po slevách", in: taxCard, of: sections).style == .strong)
        #expect(try row("Daň z dosavadních příjmů", in: taxCard, of: sections).style == .strong)
    }

    /// The sample family with 120 000 Kč received on 20. 1. and 130 000 Kč on 20. 2. 2026, and a tax advance of
    /// 10 000 Kč paid in January. As of 28. 2. the taxpayer credit takes the tax of 15 000 Kč to nothing, so the spouse
    /// credit is not used, and the income has reached six minimum wages: the children's 37 524 Kč are all a bonus. The
    /// tax is negative, and the tax office returns the advance with the bonus.
    @Test func aBonusReadsAsNegativeTaxAndComesBack() throws {
        var input = TaxEngineFamilyTests.input(TaxEngineFamilyTests.earlyReceipts)
        input.advances.tax[0] = 10_000
        let sections = build(input, asOf: "2026-02-28")

        #expect(
            try shown(taxCard, in: sections).suffix(8) == [
                Shown("Daň před slevou", "15\u{00A0}000", "zaokrouhleno na celé koruny nahoru", "="),
                Shown(
                    "Sleva na poplatníka", "\u{2212}15\u{00A0}000",
                    "roční sleva 30\u{00A0}840 se uplatní nejvýše do výše daně", "\u{2212}"),
                Shown(
                    "Sleva na manžela / manželku", "0",
                    "12\u{00A0}měsíců s dítětem do 3 let · daň už je nulová, sleva se neprojeví", "\u{2212}"),
                Shown("Daň po slevách", "0", "slevy snižují daň nejvýš na nulu", "="),
                Shown(
                    "Daňové zvýhodnění na děti", "\u{2212}37\u{00A0}524",
                    "Anna 15\u{00A0}204 · Tomáš 22\u{00A0}320 · z toho daňový bonus 37\u{00A0}524", "\u{2212}"),
                Shown(
                    "Daň z dosavadních příjmů", "\u{2212}37\u{00A0}524",
                    "záporná daň je daňový bonus – vyplatí ho finanční úřad", "="),
                Shown("Zálohy", "\u{2212}10\u{00A0}000", "1 z 1 · \(month)", "\u{2212}"),
                Shown("Zbývá", "vrátí se 47\u{00A0}524\u{00A0}Kč", "vrací se po podání přiznání, na žádost", "="),
            ])
    }

    /// 2025 with the sample family and 600 000 Kč, seen as of its last day: the taxpayer credit leaves 5 160 Kč of the
    /// tax of 36 000 Kč, which is all the spouse credit can take, and the children's benefit is all a bonus. The year
    /// is over, so its tax is the tax of the year, and the bonus comes back with the return.
    @Test func aBonusOfAYearThatIsOverComesBackAsTheDoplatek() throws {
        let input = withFamily(yearInput(year: 2025, netHalere: 60_000_000))
        let sections = build(input, asOf: "2025-12-31")

        #expect(
            try shown(taxCard, in: sections).suffix(6) == [
                Shown(
                    "Sleva na manžela / manželku", "\u{2212}5\u{00A0}160",
                    "12\u{00A0}měsíců s dítětem do 3 let · uplatní se jen 5\u{00A0}160\u{00A0}Kč, víc daně nezbývá",
                    "\u{2212}"),
                Shown("Daň po slevách", "0", "slevy snižují daň nejvýš na nulu", "="),
                Shown(
                    "Daňové zvýhodnění na děti", "\u{2212}37\u{00A0}524",
                    "Anna 15\u{00A0}204 · Tomáš 22\u{00A0}320 · z toho daňový bonus 37\u{00A0}524", "\u{2212}"),
                Shown(
                    "Daň za rok 2025", "\u{2212}37\u{00A0}524",
                    "záporná daň je daňový bonus – vyplatí ho finanční úřad", "="),
                Shown("Zálohy", "0", "žádné zálohy v plánu", "\u{2212}"),
                Shown(
                    "Doplatek", "vrátí se 37\u{00A0}524\u{00A0}Kč", "vrací se po podání přiznání, na žádost", "="),
            ])
    }

    /// Without a family the card is the one of a year without it, row for row, and so is the whole page with a family
    /// whose credits come to nothing: a spouse whose own income is over the limit, and a child the other parent claims.
    @Test func withoutAFamilyTheTaxCardIsUnchanged() throws {
        let without = build(sample)

        #expect(
            try labels(taxCard, in: without) == [
                "Zisk", "Nezdanitelné části základu", "Základ daně", "Sazba 15\u{00A0}%", "Sazba 23\u{00A0}%",
                "Daň před slevou", "Sleva na poplatníka", "Daň z dosavadních příjmů", "Zálohy", "Zbývá",
            ])
        #expect(try shown(taxCard, in: without).last?.value == "71\u{00A0}440\u{00A0}Kč")

        var anna = TaxEngineFamilyTests.sampleFamily.children[0]
        anna.claimant = .otherParent
        let nothing = withFamily(
            sample,
            FamilyFacts(
                children: [anna],
                spouse: SpouseYear(claim: true, months: MonthRange.wholeYear, ownIncomeKc: 70_000, ztpp: nil)))
        #expect(computationPage(nothing) == computationPage(sample))
        #expect(build(nothing) == without)
    }

    /// The spouse row names the months the credit counts, from 2024 those with a child under three, and those with
    /// ZTP/P, which count twice. Before 2024 no child is needed. The credit takes what the taxpayer credit leaves of
    /// the tax and no more, and the row says so.
    @Test func theSpouseRowSaysItsMonthsAndHowMuchOfTheCreditIsUsed() throws {
        var family = TaxEngineFamilyTests.sampleFamily
        family.spouse?.ztpp = MonthRange(from: 9, to: 11)
        let ztpp = try row("Sleva na manžela / manželku", in: taxCard, of: build(withFamily(sample, family)))
        // Twelve months and three more with ZTP/P: 15 × 2 070 Kč.
        #expect(ztpp.value == "\u{2212}31\u{00A0}050")
        #expect(ztpp.note == "12\u{00A0}měsíců s dítětem do 3 let · 3 se ZTP/P")

        // 2023, a spouse alone, 600 000 Kč: 5 160 Kč of tax are left after the taxpayer credit.
        let spouseAlone = FamilyFacts(spouse: TaxEngineFamilyTests.sampleFamily.spouse)
        let sections = build(
            withFamily(yearInput(year: 2023, netHalere: 60_000_000), spouseAlone),
            asOf: "2023-12-31")
        let spouse = try row("Sleva na manžela / manželku", in: taxCard, of: sections)
        #expect(spouse.value == "\u{2212}5\u{00A0}160")
        #expect(spouse.note == "12\u{00A0}měsíců · uplatní se jen 5\u{00A0}160\u{00A0}Kč, víc daně nezbývá")
        #expect(try row("Daň po slevách", in: taxCard, of: sections).value == "0")
        // No child, so no row of the children.
        #expect(try !labels(taxCard, in: sections).contains("Daňové zvýhodnění na děti"))
        #expect(try row("Daň za rok 2023", in: taxCard, of: sections) == ComputationRow(
            label: "Daň za rok 2023", value: "0", note: nil, sign: .equals, style: .strong))
    }

    /// The row of the children names each child I claim with what it brings, in the order of the family: one without a
    /// name is "dítě", and one the other parent claims is left out, though it still takes its rank. What the benefit
    /// leaves after its credit is a bonus when it is paid, and the row says why it is not when it is not.
    @Test func theChildRowNamesMyChildrenAndWhyTheBonusIsNotPaid() throws {
        // As of 31. 1. the income is 120 000 Kč, below six minimum wages, 134 400 Kč.
        let january = build(TaxEngineFamilyTests.input(TaxEngineFamilyTests.earlyReceipts), asOf: "2026-01-31")
        let notYet = try row("Daňové zvýhodnění na děti", in: taxCard, of: january)
        #expect(notYet.value == "0")
        #expect(
            notYet.note
                == "Anna 15\u{00A0}204 · Tomáš 22\u{00A0}320 · bonus 37\u{00A0}524 se nevyplatí:"
                + " příjmy pod 6× minimální mzdu (134\u{00A0}400)")
        #expect(
            try row("Daň z dosavadních příjmů", in: taxCard, of: january)
                == ComputationRow(
                    label: "Daň z dosavadních příjmů", value: "0", note: nil, sign: .equals, style: .strong))

        // Anna alone and 766 000 Kč: her 15 204 Kč take the 13 300 Kč of tax and leave 84 Kč.
        let annaAlone = FamilyFacts(children: [TaxEngineFamilyTests.sampleFamily.children[0]])
        let underAHundred = build(withFamily(yearInput(netHalere: 76_600_000), annaAlone))
        let small = try row("Daňové zvýhodnění na děti", in: taxCard, of: underAHundred)
        #expect(small.value == "\u{2212}15\u{00A0}120")
        #expect(small.note == "Anna 15\u{00A0}204 · bonus 84 se nevyplatí: je pod 100\u{00A0}Kč")
        #expect(try row("Daň po slevách", in: taxCard, of: underAHundred).value == "15\u{00A0}120")
        #expect(try !labels(taxCard, in: underAHundred).contains("Sleva na manžela / manželku"))

        // Anna is claimed by the other parent and stays the first child; Tomáš, without a name, is the second.
        var anna = TaxEngineFamilyTests.sampleFamily.children[0]
        anna.claimant = .otherParent
        var tomas = TaxEngineFamilyTests.sampleFamily.children[1]
        tomas.label = ""
        let theirsSections = build(withFamily(sample, FamilyFacts(children: [anna, tomas])))
        let theirs = try row("Daňové zvýhodnění na děti", in: taxCard, of: theirsSections)
        #expect(theirs.value == "\u{2212}22\u{00A0}320")
        #expect(theirs.note == "dítě 22\u{00A0}320")
    }

    /// Whatever the family does, the rows of the card add up: the tax before the credits less the two credits is the
    /// tax after them, never below zero, and that less the children's credit and bonus is the tax, the net tax of the
    /// engine, which the advances are set against.
    @Test func theRowsOfTheFamilyAddUpToTheNetTax() throws {
        let annaAlone = FamilyFacts(children: [TaxEngineFamilyTests.sampleFamily.children[0]])
        let scenarios: [(YearInput, String)] = [
            (withFamily(sample), "2026-10-17"),
            (withFamily(sample), "2026-01-31"),
            (TaxEngineFamilyTests.input(TaxEngineFamilyTests.earlyReceipts), "2026-01-31"),
            (TaxEngineFamilyTests.input(TaxEngineFamilyTests.earlyReceipts), "2026-02-28"),
            (withFamily(yearInput(netHalere: 60_000_000)), "2026-12-31"),
            (withFamily(yearInput(netHalere: 76_600_000), annaAlone), "2026-12-31"),
            (withFamily(yearInput(year: 2025, netHalere: 60_000_000)), "2025-12-31"),
        ]
        for (input, asOf) in scenarios {
            let result = TaxEngine.compute(input, asOf: civilDate(asOf))
            let sections = ComputationBuilder.build(
                result, input: input, today: civilDate("2026-10-17"), incomeFXMethod: .cnbDaily)
            let context = "\(input.year) as of \(asOf)"
            func figure(_ label: String) throws -> Int64 {
                minorUnits(of: try row(label, in: taxCard, of: sections).value) / 100
            }
            let isOver = asOf == "2025-12-31"
            let spouse = try labels(taxCard, in: sections).contains("Sleva na manžela / manželku")
                ? try figure("Sleva na manžela / manželku") : 0
            let after = try figure("Daň po slevách")
            #expect(spouse == -result.spouseCreditApplied, "\(context)")
            #expect(after == result.taxAfterCredits, "\(context)")
            #expect(after >= 0, "\(context)")
            #expect(
                try figure("Daň před slevou") + figure("Sleva na poplatníka") + spouse == after, "\(context)")
            let children = try figure("Daňové zvýhodnění na děti")
            #expect(children == -(result.childCredit + result.childBonus), "\(context)")
            let tax = try figure(isOver ? "Daň za rok \(input.year)" : "Daň z dosavadních příjmů")
            #expect(after + children == tax, "\(context)")
            #expect(tax == result.netTax, "\(context)")
            #expect(tax == result.balance(.tax).liability, "\(context)")
        }
    }

    // MARK: Social and health insurance

    @Test func theMinimumDecidesWhenTheProfitIsSmall() throws {
        let sections = build(yearInput(netHalere: 10_000_150))

        #expect(
            try shown(socialCard, in: sections) == [
                Shown("Vypočtený základ", "22\u{00A0}001", "55\u{00A0}% zisku, zaokrouhleno nahoru"),
                Shown(
                    "Vyměřovací základ", "171\u{00A0}390",
                    "55\u{00A0}% zisku, nahoru · min. 171\u{00A0}390 (17\u{00A0}139 × 10\u{00A0}měsíců hlavní činnosti)"
                        + " · max. 2\u{00A0}350\u{00A0}416 (roční strop, nekrátí se)"),
                Shown("Sazba 29,2\u{00A0}%", "50\u{00A0}046", "zaokrouhleno na celé koruny nahoru", "×"),
                Shown("Zálohy", "0", "žádné zálohy v plánu", "\u{2212}"),
                Shown(
                    "Zbývá", "50\u{00A0}046\u{00A0}Kč",
                    "odejde plánovanými zálohami 0 · doplatek po přehledu 50\u{00A0}046", "="),
            ])
        #expect(
            try shown(healthCard, in: sections) == [
                Shown("Vypočtený základ", "20\u{00A0}000,50", "50\u{00A0}% zisku"),
                Shown(
                    "Vyměřovací základ", "244\u{00A0}835,00",
                    "50\u{00A0}% zisku · min. 244\u{00A0}835,00 (24\u{00A0}483,50 × 10\u{00A0}měsíců)"
                        + " · bez maxima, nezaokrouhluje se"),
                Shown("Sazba 13,5\u{00A0}%", "33\u{00A0}053", "zaokrouhleno na celé koruny nahoru", "×"),
                Shown("Zálohy", "0", "žádné zálohy v plánu", "\u{2212}"),
                Shown(
                    "Zbývá", "33\u{00A0}053\u{00A0}Kč",
                    "odejde plánovanými zálohami 0 · doplatek po přehledu 33\u{00A0}053", "="),
            ])
    }

    @Test func theMaximumDecidesWhenTheProfitIsLarge() throws {
        let sections = build(yearInput(netHalere: 570_000_000))

        #expect(
            try shown(socialCard, in: sections).map(\.value) == [
                "2\u{00A0}475\u{00A0}000", "2\u{00A0}350\u{00A0}416", "686\u{00A0}322", "0",
                "686\u{00A0}322\u{00A0}Kč",
            ])
        #expect(
            try shown(healthCard, in: sections).map(\.value) == [
                "2\u{00A0}250\u{00A0}000,00", "2\u{00A0}250\u{00A0}000,00", "303\u{00A0}750", "0",
                "303\u{00A0}750\u{00A0}Kč",
            ])
    }

    @Test func aSingleMonthOfActivityIsNamedInTheSingular() throws {
        var months = [MonthActivity](repeating: .inactive, count: 12)
        months[0] = .main
        let sections = build(yearInput(netHalere: 10_000_150, months: months), asOf: "2026-01-31")

        #expect(
            try row("Vyměřovací základ", in: socialCard, of: sections).note?.contains(
                "(17\u{00A0}139 × 1\u{00A0}měsíc hlavní činnosti)") == true)
        #expect(
            try row("Vyměřovací základ", in: healthCard, of: sections).note?.contains(
                "(24\u{00A0}483,50 × 1\u{00A0}měsíc)") == true)
    }

    @Test func monthsWithoutTheMinimumAreNotCountedInTheHealthRow() throws {
        var input = yearInput(netHalere: 10_000_150)
        input.healthExemptMonths = [1, 2, 3, 4, 5]
        let sections = build(input)

        // Ten counted months of activity, five of them exempt: the minimum of five months, 122 417,50 Kč.
        let base = try row("Vyměřovací základ", in: healthCard, of: sections)
        #expect(base.value == "122\u{00A0}417,50")
        #expect(
            base.note
                == "50\u{00A0}% zisku · min. 122\u{00A0}417,50 (24\u{00A0}483,50 × 5\u{00A0}měsíců s minimem)"
                + " · bez maxima, nezaokrouhluje se")
    }

    // MARK: Secondary activity

    @Test func anInsuredSecondaryActivityShowsTheReducedDecisiveAmountAndTheBase() throws {
        // A profit of 1 000 000 Kč over twelve months of secondary activity.
        let sections = build(yearInput(netHalere: 220_000_000, months: secondaryYear), asOf: "2026-12-31")

        #expect(
            try shown(socialCard, in: sections).prefix(5) == [
                Shown(
                    "Snížená rozhodná částka", "117\u{00A0}521",
                    "117\u{00A0}521 − 0 × 9\u{00A0}794 (0\u{00A0}měsíců bez vedlejší činnosti)"),
                Shown(
                    "Vedlejší činnost", "pojištěná",
                    "zisk 1\u{00A0}000\u{00A0}000 dosáhl snížené rozhodné částky"),
                Shown("Vypočtený základ", "550\u{00A0}000", "55\u{00A0}% zisku, zaokrouhleno nahoru"),
                Shown(
                    "Vyměřovací základ", "550\u{00A0}000",
                    "55\u{00A0}% zisku, nahoru · min. 64\u{00A0}644"
                        + " (5\u{00A0}387 × 12\u{00A0}měsíců vedlejší činnosti)"
                        + " · max. 2\u{00A0}350\u{00A0}416 (roční strop, nekrátí se)"),
                Shown("Sazba 29,2\u{00A0}%", "160\u{00A0}600", "zaokrouhleno na celé koruny nahoru", "×"),
            ])
    }

    @Test func aSecondaryActivityBelowTheReducedDecisiveAmountIsNotInsured() throws {
        // A profit of 100 000 Kč, below the decisive amount of 117 521 Kč.
        let sections = build(yearInput(netHalere: 25_000_000, months: secondaryYear), asOf: "2026-12-31")

        let rows = try shown(socialCard, in: sections)
        #expect(
            rows.first { $0.label == "Vedlejší činnost" }
                == Shown("Vedlejší činnost", "nepojištěná", "zisk 100\u{00A0}000 nedosáhl snížené rozhodné částky"))
        #expect(
            rows.first { $0.label == "Vypočtený základ" }
                == Shown("Vypočtený základ", "0", "vedlejší činnost není pojištěná"))
        #expect(
            rows.first { $0.label == "Vyměřovací základ" }
                == Shown("Vyměřovací základ", "0", "nic se nevyměřuje"))
        #expect(rows.first { $0.label == "Sazba 29,2\u{00A0}%" }?.value == "0")
    }

    @Test func monthsAfterTheChosenDayCountAsMonthsWithoutSecondaryActivityAndTheRowSaysSo() throws {
        // As of 30. 6., six secondary months are counted: k is 12 − 6 = 6, and the reduced amount 58 757 Kč.
        let sections = build(yearInput(netHalere: 220_000_000, months: secondaryYear), asOf: "2026-06-30")

        let reduced = try row("Snížená rozhodná částka", in: socialCard, of: sections)
        #expect(reduced.value == "58\u{00A0}757")
        #expect(
            reduced.note
                == "117\u{00A0}521 − 6 × 9\u{00A0}794 (6\u{00A0}měsíců bez vedlejší činnosti)"
                + " · měsíce po zvoleném dni se u snížené rozhodné částky počítají jako měsíce bez vedlejší činnosti"
                + " – konvence aplikace, zákon to neřeší")
        #expect(
            try row("Vyměřovací základ", in: socialCard, of: sections).note?.contains(
                "(5\u{00A0}387 × 6\u{00A0}měsíců vedlejší činnosti)") == true)
    }

    @Test func evenASingleMonthAfterTheChosenDayIsNamed() throws {
        // As of 30. 11., eleven secondary months are counted and December is not: k is 1, the reduced amount is
        // 107 727 Kč.
        let sections = build(yearInput(netHalere: 220_000_000, months: secondaryYear), asOf: "2026-11-30")

        let reduced = try row("Snížená rozhodná částka", in: socialCard, of: sections)
        #expect(reduced.value == "107\u{00A0}727")
        #expect(
            reduced.note
                == "117\u{00A0}521 − 1 × 9\u{00A0}794 (1\u{00A0}měsíc bez vedlejší činnosti)"
                + " · " + ComputationBuilder.notReachedMonthsConvention)
    }

    @Test func theWholeYearCountsAllItsMonthsSoThereIsNoConventionToName() throws {
        let sections = build(yearInput(netHalere: 220_000_000, months: secondaryYear), asOf: "2026-12-31")

        let reduced = try row("Snížená rozhodná částka", in: socialCard, of: sections)
        #expect(reduced.value == "117\u{00A0}521")
        #expect(reduced.note?.contains("konvence") == false)
    }

    @Test func aMixedYearShowsTheRowsOfTheOverviewOfTheSocialSecurityAdministration() throws {
        // A profit of 1 000 000 Kč over eight months of main and four of secondary activity.
        let sections = build(yearInput(netHalere: 220_000_000, months: mixedYear), asOf: "2026-12-31")

        #expect(
            try shown(socialCard, in: sections).prefix(9) == [
                Shown(
                    "Zisk na měsíc činnosti (ř.\u{00A0}23)", "83\u{00A0}333,33",
                    "zisk 1\u{00A0}000\u{00A0}000 ÷ 12\u{00A0}měsíců činnosti, na haléře od poloviny nahoru"),
                Shown(
                    "Podíl zisku, hlavní činnost (ř.\u{00A0}24)", "666\u{00A0}666,64",
                    "ř.\u{00A0}23 × 8\u{00A0}měsíců"),
                Shown(
                    "Podíl zisku, vedlejší činnost (ř.\u{00A0}24)", "333\u{00A0}333,32",
                    "ř.\u{00A0}23 × 4\u{00A0}měsíce"),
                Shown(
                    "Snížená rozhodná částka", "39\u{00A0}169",
                    "117\u{00A0}521 − 8 × 9\u{00A0}794 (8\u{00A0}měsíců bez vedlejší činnosti)"),
                Shown(
                    "Vedlejší činnost", "pojištěná",
                    "podíl zisku 333\u{00A0}333,32 dosáhl snížené rozhodné částky"),
                Shown(
                    "Základ z podílů zisku (ř.\u{00A0}25)", "550\u{00A0}001",
                    "55\u{00A0}% podílů, nahoru: hlavní 366\u{00A0}667 + vedlejší 183\u{00A0}334"),
                Shown(
                    "Minimální základ (ř.\u{00A0}26)", "158\u{00A0}660",
                    "hlavní 17\u{00A0}139 × 8 = 137\u{00A0}112 + vedlejší 5\u{00A0}387 × 4 = 21\u{00A0}548"),
                Shown(
                    "Vyměřovací základ (ř.\u{00A0}27)", "550\u{00A0}001",
                    "nejvyšší z: ř.\u{00A0}25 celkem 550\u{00A0}001 · ř.\u{00A0}26 celkem 158\u{00A0}660"
                        + " · ř.\u{00A0}26 hlavní + ř.\u{00A0}25 vedlejší 320\u{00A0}446;"
                        + " nejvýše max. 2\u{00A0}350\u{00A0}416 (roční strop, nekrátí se)"),
                Shown("Sazba 29,2\u{00A0}%", "160\u{00A0}601", "zaokrouhleno na celé koruny nahoru", "×"),
            ])
    }

    @Test func aMixedYearWhoseSecondaryShareIsTooSmallIsInsuredForTheMainActivityOnly() throws {
        // A profit of 100 000 Kč: the secondary share, 33 333,32 Kč, is below the reduced decisive amount of 39 169 Kč.
        let sections = build(yearInput(netHalere: 25_000_000, months: mixedYear), asOf: "2026-12-31")

        let rows = try shown(socialCard, in: sections)
        #expect(
            rows.first { $0.label == "Vedlejší činnost" }
                == Shown(
                    "Vedlejší činnost", "nepojištěná", "podíl zisku 33\u{00A0}333,32 nedosáhl snížené rozhodné částky"))
        #expect(
            rows.first { $0.label == "Základ z podílů zisku (ř.\u{00A0}25)" }
                == Shown(
                    "Základ z podílů zisku (ř.\u{00A0}25)", "36\u{00A0}667",
                    "55\u{00A0}% podílů, nahoru: hlavní 36\u{00A0}667 + vedlejší 0"))
        #expect(
            rows.first { $0.label == "Minimální základ (ř.\u{00A0}26)" }
                == Shown(
                    "Minimální základ (ř.\u{00A0}26)", "137\u{00A0}112",
                    "hlavní 17\u{00A0}139 × 8 = 137\u{00A0}112 + vedlejší 0"))
        #expect(rows.first { $0.label == "Vyměřovací základ (ř.\u{00A0}27)" }?.value == "137\u{00A0}112")
        #expect(rows.first { $0.label == "Sazba 29,2\u{00A0}%" }?.value == "40\u{00A0}037")
    }

    @Test func thePartsOfTheRowsOfAMixedYearAddUpToWhatTheEngineWorkedOut() throws {
        // The parts of rows 25 and 26 are worked out again for the screen. The sums the screen names have to be the
        // engine's, and the base has to be the highest of the candidates it names, at most the maximum.
        for net: Int64 in [220_000_000, 25_000_000, 60_000_000, 900_000_000] {
            let input = yearInput(netHalere: net, months: mixedYear)
            let result = TaxEngine.compute(input, asOf: civilDate("2026-12-31"))
            let sections = ComputationBuilder.build(
                result, input: input, today: civilDate("2026-10-17"), incomeFXMethod: .cnbDaily)
            let social = try section(socialCard, in: sections)

            let row25 = try #require(social.rows.first { $0.label.hasPrefix("Základ z podílů zisku") })
            let row26 = try #require(social.rows.first { $0.label.hasPrefix("Minimální základ") })
            let row27 = try #require(social.rows.first { $0.label.hasPrefix("Vyměřovací základ") })
            #expect(row25.value == CzechFormat.grouped(result.social.computedBase))
            #expect(row26.value == CzechFormat.grouped(result.social.minimumBase))
            #expect(row27.value == CzechFormat.grouped(result.social.base))

            let parts25 = amounts(in: try #require(row25.note), after: ["hlavní", "vedlejší"])
            #expect(parts25.count == 2)
            #expect(parts25.reduce(0, +) == result.social.computedBase)
            let candidates = amounts(
                in: try #require(row27.note), after: ["ř.\u{00A0}25 celkem", "ř.\u{00A0}26 celkem", "vedlejší"])
            #expect(candidates.count == 3)
            #expect(candidates.first == result.social.computedBase)
            #expect(candidates.dropFirst().first == result.social.minimumBase)
            #expect(min(candidates.max() ?? 0, result.social.maximumBase) == result.social.base)
        }
    }

    // MARK: Advances

    @Test func aYearThatIsOverSaysDoplatekAndLeavesOutWhatOnlyAYearInProgressHas() throws {
        // A payment of 4 500 Kč with 945 Kč of VAT in 2025, seen from 2026 as of its last day.
        let sections = build(yearInput(year: 2025, netHalere: 450_000, vatHalere: 94_500), asOf: "2025-12-31")

        #expect(
            try shown(incomeCard, in: sections).map(\.value) == [
                "5\u{00A0}445,00", "\u{2212}945,00", "4\u{00A0}500,00", "4\u{00A0}500,00",
                "\u{2212}2\u{00A0}700,00", "1\u{00A0}800,00",
            ])
        #expect(
            try row("Přijaté platby", in: incomeCard, of: sections).note
                == "1.\u{00A0}1. – 31.\u{00A0}12. · cizí měny v Kč ke dni přijetí")
        #expect(
            try row("Sazba 15\u{00A0}%", in: taxCard, of: sections).note
                == "z 1\u{00A0}800 základu (pásmo do 1\u{00A0}676\u{00A0}052)"
                + " · pravidla 2025 · ověřeno 20.\u{00A0}10.\u{00A0}2026")
        #expect(
            try row("Sazba 23\u{00A0}%", in: taxCard, of: sections).note
                == "pásmo nad 1\u{00A0}676\u{00A0}052 nedosaženo")
        #expect(
            try labels(taxCard, in: sections) == [
                "Zisk", "Nezdanitelné části základu", "Základ daně", "Sazba 15\u{00A0}%", "Sazba 23\u{00A0}%",
                "Daň před slevou", "Sleva na poplatníka", "Daň za rok 2025", "Zálohy", "Doplatek",
            ])
        #expect(try row("Daň za rok 2025", in: taxCard, of: sections).value == "0")
        // Everything left is the Doplatek, so there is nothing to say about planned advances.
        for (title, expected) in [(taxCard, "0"), (socialCard, "57\u{00A0}098"), (healthCard, "37\u{00A0}712")] {
            let rows = try shown(title, in: sections)
            #expect(Array(rows.suffix(2).map(\.label)) == ["Zálohy", "Doplatek"])
            #expect(rows.last?.value == expected + "\u{00A0}Kč")
            #expect(rows.last?.note == nil)
            #expect(rows.dropLast().last == Shown("Zálohy", "0", "žádné zálohy v plánu", "\u{2212}"))
        }
    }

    @Test func aPastYearShownAsOfAMidYearDayIsAYearInProgressAsOfThatDay() throws {
        // The same payment as above in 2025, but seen as of 30. 6. 2025 from 2026, with 1 000 Kč of social insurance
        // advances in each month: six paid, six planned.
        var advances = AdvancePlan.empty
        advances.social = [Int64](repeating: 1_000, count: 12)
        let sections = build(
            yearInput(year: 2025, netHalere: 450_000, vatHalere: 94_500, advances: advances), asOf: "2025-06-30")

        #expect(
            try row("Přijaté platby", in: incomeCard, of: sections).note
                == "1.\u{00A0}1. – 30.\u{00A0}6. · cizí měny v Kč ke dni přijetí")
        #expect(
            try row("Výdajový paušál 60\u{00A0}%", in: incomeCard, of: sections).note
                == "60\u{00A0}% z příjmů, zaokrouhleno dolů · strop 1\u{00A0}200\u{00A0}000 zatím nedosažen")
        #expect(
            try row("Sazba 23\u{00A0}%", in: taxCard, of: sections).note
                == "pásmo nad 1\u{00A0}676\u{00A0}052 zatím nedosaženo")
        #expect(
            try Array(labels(taxCard, in: sections).suffix(3)) == ["Daň z dosavadních příjmů", "Zálohy", "Zbývá"])
        #expect(
            try shown(socialCard, in: sections).suffix(2) == [
                Shown("Zálohy", "\u{2212}6\u{00A0}000", "6 ze 12 · \(month)", "\u{2212}"),
                Shown(
                    "Zbývá", "22\u{00A0}549\u{00A0}Kč",
                    "odejde plánovanými zálohami 6\u{00A0}000 · doplatek po přehledu 16\u{00A0}549", "="),
            ])
        // Six months of the minimum, as of that day: 6 × 16 295 Kč and 6 × 23 278,50 Kč.
        #expect(try row("Sazba 29,2\u{00A0}%", in: socialCard, of: sections).value == "28\u{00A0}549")
        #expect(try row("Sazba 13,5\u{00A0}%", in: healthCard, of: sections).value == "18\u{00A0}856")
        #expect(try row("Zbývá", in: healthCard, of: sections).value == "18\u{00A0}856\u{00A0}Kč")
    }

    @Test func anOverpaymentIsShownWhereTheAdvancesAreMoreThanTheLevyAndSaysHowItComesBack() throws {
        // The tax is 0 Kč and 10 000 Kč of income tax advances were paid in March. The social insurance is 50 046 Kč
        // and 60 000 Kč were paid in March, the health insurance 33 053 Kč and 40 000 Kč.
        var advances = AdvancePlan.empty
        advances.tax[2] = 10_000
        advances.social[2] = 60_000
        advances.health[2] = 40_000
        let sections = build(yearInput(netHalere: 10_000_150, advances: advances))

        let tax = try shown(taxCard, in: sections).suffix(2)
        #expect(
            tax == [
                Shown("Zálohy", "\u{2212}10\u{00A0}000", "1 z 1 · \(month)", "\u{2212}"),
                Shown(
                    "Zbývá", "přeplatek 10\u{00A0}000\u{00A0}Kč", "vrací se po podání přiznání, na žádost", "="),
            ])
        let social = try shown(socialCard, in: sections).suffix(2)
        #expect(
            social == [
                Shown("Zálohy", "\u{2212}60\u{00A0}000", "1 z 1 · \(month)", "\u{2212}"),
                Shown("Zbývá", "přeplatek 9\u{00A0}954\u{00A0}Kč", "vrací se po přehledu", "="),
            ])
        let health = try shown(healthCard, in: sections).suffix(2)
        #expect(
            health == [
                Shown("Zálohy", "\u{2212}40\u{00A0}000", "1 z 1 · \(month)", "\u{2212}"),
                Shown("Zbývá", "přeplatek 6\u{00A0}947\u{00A0}Kč", "vrací se po přehledu", "="),
            ])
    }

    @Test func anOverpaymentOfAYearThatIsOverSaysHowItComesBackToo() throws {
        var advances = AdvancePlan.empty
        advances.tax[2] = 10_000
        advances.health[2] = 40_000
        let sections = build(
            yearInput(year: 2025, netHalere: 450_000, vatHalere: 94_500, advances: advances), asOf: "2025-12-31")

        let tax = try row("Doplatek", in: taxCard, of: sections)
        #expect(tax.value == "přeplatek 10\u{00A0}000\u{00A0}Kč")
        #expect(tax.note == "vrací se po podání přiznání, na žádost")
        // The health insurance is 37 712 Kč, less than the 40 000 Kč paid.
        let health = try row("Doplatek", in: healthCard, of: sections)
        #expect(health.value == "přeplatek 2\u{00A0}288\u{00A0}Kč")
        #expect(health.note == "vrací se po přehledu")
    }

    @Test func plannedAdvancesThatAreMoreThanWhatRemainsAreNotAllUsed() throws {
        // 50 046 Kč of social insurance, nothing paid, 40 000 Kč planned for each of November and December.
        var advances = AdvancePlan.empty
        advances.social[10] = 40_000
        advances.social[11] = 40_000
        let sections = build(yearInput(netHalere: 10_000_150, advances: advances))

        #expect(
            try shown(socialCard, in: sections).suffix(2) == [
                Shown("Zálohy", "0", "0 ze 2 · \(month)", "\u{2212}"),
                Shown(
                    "Zbývá", "50\u{00A0}046\u{00A0}Kč",
                    "odejde plánovanými zálohami 50\u{00A0}046 z plánovaných 80\u{00A0}000"
                        + " (započte se nejvýše to, co zbývá) · doplatek po přehledu 0",
                    "="),
            ])
    }

    @Test func theWordZeStandsBeforeTheCountsThatCzechSaysItBefore() throws {
        // "ze dvou, tří, čtyř, šesti, sedmi, dvanácti" but "z jednoho, pěti, osmi, devíti, deseti, jedenácti".
        let withZe: Set<Int> = [2, 3, 4, 6, 7, 12]
        for planned in 1...12 {
            var advances = AdvancePlan.empty
            for index in 0..<planned {
                advances.health[index] = 1_000
            }
            let sections = build(yearInput(netHalere: 10_000_150, advances: advances))

            let paid = min(planned, 10)
            let word = withZe.contains(planned) ? "ze" : "z"
            #expect(
                try row("Zálohy", in: healthCard, of: sections).note == "\(paid) \(word) \(planned) · \(month)",
                "\(planned) advances")
        }
    }

    // MARK: Net income

    /// What the note of the net income says about the expenses, where it has no share of the income to say first.
    private let notSubtracted = "skutečné výdaje podnikání tu odečtené nejsou"

    /// The sample year of `PredictionSample`, with its family, as of 17. 10. 2026: 2 191 771 Kč of income less the tax
    /// of 32 076 Kč, the social insurance of 159 279 Kč and the health insurance of 66 945 Kč leave 1 933 471 Kč. That
    /// is 88,2 % of the income, and over the ten months so far 193 347 Kč a month.
    @Test func theNetIncomeCardOfTheSampleYearSoFar() throws {
        let sections = build(PredictionSample.yearInput(year: 2026))
        let card = try section(netIncomeCard, in: sections)

        #expect(card.tag == "do 17.\u{00A0}10.")
        #expect(card.authority == nil)
        #expect(card.isNetIncome)
        #expect(
            try shown(netIncomeCard, in: sections) == [
                Shown("Příjmy z podnikání (§ 7)", "2\u{00A0}191\u{00A0}771,00", "bez DPH"),
                Shown("Daň z příjmů", "\u{2212}32\u{00A0}076", nil, "\u{2212}"),
                Shown("Sociální pojištění", "\u{2212}159\u{00A0}279", nil, "\u{2212}"),
                Shown("Zdravotní pojištění", "\u{2212}66\u{00A0}945", nil, "\u{2212}"),
                Shown(
                    "Čistý příjem", "1\u{00A0}933\u{00A0}471",
                    "88,2\u{00A0}% příjmů · skutečné výdaje podnikání tu odečtené nejsou", "="),
                Shown("10\u{00A0}měsíců", "10", "leden–říjen", "÷"),
                Shown("Průměrně za měsíc", "193\u{00A0}347\u{00A0}Kč", "čistý příjem na jeden měsíc", "="),
            ])
        #expect(card.rows.map(\.style) == [.plain, .plain, .plain, .plain, .strong, .plain, .total])
    }

    /// 2025 of the sample as of its last day is a whole year: the income of 2 931 160 Kč less the levies leaves
    /// 2 393 295 Kč, 81,7 % of the income, which over the twelve months is 199 441 Kč a month.
    @Test func aYearShownAsOfItsLastDayHasTheNetIncomeOfTheWholeYear() throws {
        let sections = build(PredictionSample.yearInput(year: 2025), asOf: "2025-12-31")
        let rows = try shown(netIncomeCard, in: sections)

        #expect(try section(netIncomeCard, in: sections).tag == "za rok 2025")
        #expect(rows[0].value == "2\u{00A0}931\u{00A0}160,00")
        #expect(
            rows[4] == Shown("Čistý příjem", "2\u{00A0}393\u{00A0}295", "81,7\u{00A0}% příjmů · \(notSubtracted)", "="))
        #expect(rows[5] == Shown("12\u{00A0}měsíců", "12", "celý rok", "÷"))
        #expect(rows[6].value == "199\u{00A0}441\u{00A0}Kč")
    }

    /// The sample family with 120 000 Kč received on 20. 1. and 130 000 Kč on 20. 2. 2026, as of 28. 2.: the children's
    /// benefit is all a tax bonus of 37 524 Kč, which the tax office pays. The card adds it to the income, in place of
    /// the tax, and takes the two insurances off.
    @Test func aBonusIsAddedToTheNetIncome() throws {
        let input = TaxEngineFamilyTests.input(TaxEngineFamilyTests.earlyReceipts)
        let result = TaxEngine.compute(input, asOf: civilDate("2026-02-28"))
        #expect(result.netTax == -37_524)

        let rows = try shown(netIncomeCard, in: build(input, asOf: "2026-02-28"))

        #expect(
            rows.map(\.label).prefix(5) == [
                "Příjmy z podnikání (§ 7)", "Daňový bonus", "Sociální pojištění", "Zdravotní pojištění", "Čistý příjem",
            ])
        #expect(rows[1] == Shown("Daňový bonus", "37\u{00A0}524", "vyplatí ho finanční úřad", "+"))
        #expect(rows[4].value == CzechFormat.grouped(result.P - result.liabilityTotal))
        #expect(rows[5] == Shown("2\u{00A0}měsíce", "2", "leden–únor", "÷"))
    }

    /// Before any payment there is no income for the levies to take a part of, so the note has no share, and the
    /// minimum insurance leaves a net income below zero, which carries its minus sign.
    @Test func beforeTheFirstPaymentTheCardHasNoShareAndANegativeNetIncome() throws {
        let sections = build(yearInput(), asOf: "2026-01-31")
        let rows = try shown(netIncomeCard, in: sections)

        #expect(rows[4].label == "Čistý příjem")
        #expect(rows[4].note == notSubtracted)
        #expect(rows[4].value.hasPrefix("\u{2212}"))
        #expect(rows[5] == Shown("1\u{00A0}měsíc", "1", "leden", "÷"))
        #expect(rows[6].value.hasPrefix("\u{2212}"))
    }

    /// Any day of December but the last is a year in progress, even though it has twelve months so far.
    @Test func aDayOfDecemberBeforeTheLastIsNotTheWholeYear() throws {
        let sections = build(yearInput(netHalere: 100_000_000), asOf: "2026-12-17")
        let rows = try shown(netIncomeCard, in: sections)

        #expect(try section(netIncomeCard, in: sections).tag == "do 17.\u{00A0}12.")
        #expect(rows[5] == Shown("12\u{00A0}měsíců", "12", "leden–prosinec", "÷"))
    }

    /// A share is written in tenths of a percent, a negative one with the minus sign (U+2212).
    @Test func sharesAreWrittenInTenthsOfAPercentWithTheMinusSign() {
        #expect(BuilderText.share(tenths: 118) == "11,8\u{00A0}%")
        #expect(BuilderText.share(tenths: -12) == "\u{2212}1,2\u{00A0}%")
        #expect(BuilderText.share(tenths: 0) == "0,0\u{00A0}%")
        #expect(BuilderText.share(tenths: 1_000) == "100,0\u{00A0}%")
    }

    /// The months an average is over: the whole year, January alone, or January through the last month so far.
    @Test func theMonthsOfTheAverageAreNamedFromJanuaryThroughTheLastOne() {
        func months(_ count: Int, isWholeYear: Bool = false) -> String {
            BuilderText.months(of: NetIncome(incomeKc: 0, leviesKc: 0, months: count, isWholeYear: isWholeYear))
        }

        #expect(months(12, isWholeYear: true) == "celý rok")
        #expect(months(1) == "leden")
        #expect(months(2) == "leden–únor")
        #expect(months(10) == "leden–říjen")
        #expect(months(12) == "leden–prosinec")
    }

    // MARK: Years without rules

    @Test func anEstimateNamesTheRulesOfTheYearItIsComputedWith() throws {
        // 2027 has no rules of its own and is computed with those of 2026.
        let sections = build(yearInput(year: 2027, netHalere: 10_000_150), asOf: "2027-10-17", today: "2027-10-17")

        #expect(
            try row("Sazba 15\u{00A0}%", in: taxCard, of: sections).note
                == "z 40\u{00A0}000 základu (pásmo do 1\u{00A0}762\u{00A0}812)"
                + " · pravidla 2026 · ověřeno 20.\u{00A0}10.\u{00A0}2026")
        #expect(
            try Array(labels(taxCard, in: sections).suffix(3)) == ["Daň z dosavadních příjmů", "Zálohy", "Zbývá"])
    }

    // MARK: Whatever the year

    @Test func everyRowOfASectionHasItsOwnLabelAndAValue() throws {
        var overpaid = AdvancePlan.empty
        overpaid.tax[2] = 10_000
        let scenarios: [(YearInput, String, String)] = [
            (sample, "2026-10-17", "2026-10-17"),
            (yearInput(), "2026-10-17", "2026-10-17"),
            (
                yearInput(netHalere: 10_000_150, adjustmentHalere: -100_000, advances: overpaid), "2026-10-17",
                "2026-10-17"
            ),
            (yearInput(netHalere: 570_000_000), "2026-10-17", "2026-10-17"),
            (yearInput(year: 2025, netHalere: 450_000, vatHalere: 94_500), "2025-12-31", "2026-10-17"),
            (yearInput(year: 2025, netHalere: 450_000, vatHalere: 94_500), "2025-06-30", "2026-10-17"),
            (yearInput(netHalere: 220_000_000, months: mixedYear), "2026-12-31", "2026-10-17"),
            (yearInput(netHalere: 25_000_000, months: mixedYear), "2026-06-30", "2026-10-17"),
            (yearInput(netHalere: 220_000_000, months: secondaryYear), "2026-06-30", "2026-10-17"),
            (yearInput(netHalere: 25_000_000, months: secondaryYear), "2026-12-31", "2026-10-17"),
            (yearInput(year: 2027, netHalere: 10_000_150), "2027-03-31", "2027-03-31"),
        ]
        for (input, asOf, today) in scenarios {
            let sections = build(input, asOf: asOf, today: today)
            #expect(sections.map(\.title) == titles)
            for section in sections {
                let labels = section.rows.map(\.label)
                #expect(Set(labels).count == labels.count, "Labels of \(section.title) repeat: \(labels)")
                #expect(section.rows.allSatisfy { !$0.label.isEmpty && !$0.value.isEmpty })
            }
            let result = TaxEngine.compute(input, asOf: civilDate(asOf))
            try checkNetIncomeCard(in: sections, of: result, "\(input.year) \(asOf)")
        }
    }

    @Test func theFiguresOfTheBreakdownAreThoseOfTheEngineWhateverTheYear() throws {
        // Each year of the grid is built, and what the rows say about the income, the tax and the base is read back
        // and compared with the result of the engine. Today is 17. 10. 2026: a year before 2026 is over when it is
        // shown as of its last day, and in progress as of any other day.
        for scenario in computationGrid() {
            try checkFigures(of: scenario)
        }
    }

    /// Builds `scenario` and compares what the rows say with the result of the engine.
    private func checkFigures(of scenario: ComputationScenario) throws {
        let input = scenario.input
        let result = TaxEngine.compute(input, asOf: civilDate(scenario.asOf))
        let sections = ComputationBuilder.build(
            result, input: input, today: civilDate("2026-10-17"), incomeFXMethod: .cnbDaily)
        let context = "\(input.receipts.map(\.czkNetHalere)) \(scenario.asOf) \(input.expensePercent) %"
        let isOver = scenario.isOver

        /// The first row of a card whose label is `label`, or starts with it (the rows of a mixed year name their
        /// row of the overview), as the text of its value.
        func value(_ label: String, in title: String) throws -> String {
            let section = try section(title, in: sections)
            return try #require(
                section.rows.first { $0.label == label || $0.label.hasPrefix(label + " (") }?.value,
                "No row \(label) in \(title) for \(context)")
        }
        func halere(_ label: String, in title: String) throws -> Int64 {
            try minorUnits(of: value(label, in: title))
        }

        // Every card is there with its own labels and a value in each row.
        #expect(sections.map(\.title) == titles, "\(context)")
        for section in sections {
            let labels = section.rows.map(\.label)
            #expect(Set(labels).count == labels.count, "Labels of \(section.title) repeat for \(context)")
            #expect(section.rows.allSatisfy { !$0.value.isEmpty }, "\(context)")
        }

        // What was paid in, less the VAT, plus the adjustments, is the income, which is the engine's.
        let paidIn = try halere("Přijaté platby", in: incomeCard)
        let vat = -(try halere("DPH z přijatých plateb", in: incomeCard))
        let adjustments =
            try section(incomeCard, in: sections).rows.first { $0.label == "Úpravy příjmů" }.map {
                minorUnits(of: $0.value)
            } ?? 0
        let counted = try halere("Příjmy bez DPH", in: incomeCard)
        #expect(paidIn - vat + adjustments == counted, "\(context)")
        #expect(counted == result.incomeHalere, "\(context)")
        #expect(vat == result.vatHalere, "\(context)")

        // The crowns and haléře of the return are the engine's, with the sign of the operation.
        let rate = "Výdajový paušál \(input.expensePercent)\u{00A0}%"
        let figures: [(String, String, Int64)] = [
            ("Příjmy z podnikání (§ 7)", incomeCard, result.P * 100), (rate, incomeCard, -result.V * 100),
            ("Zisk (dílčí základ daně)", incomeCard, result.DZ * 100), ("Zisk", taxCard, result.DZ * 100),
            ("Nezdanitelné části základu", taxCard, -result.deductionsTotal * 100),
            ("Základ daně", taxCard, result.B * 100), ("Daň před slevou", taxCard, result.taxBeforeCredit * 100),
            ("Sleva na poplatníka", taxCard, -result.creditApplied * 100),
            (isOver ? "Daň za rok \(input.year)" : "Daň z dosavadních příjmů", taxCard, result.netTax * 100),
            ("Vyměřovací základ", socialCard, result.social.base * 100),
            ("Sazba 29,2\u{00A0}%", socialCard, result.social.insurance * 100),
            ("Vyměřovací základ", healthCard, result.health.baseHalere),
            ("Sazba 13,5\u{00A0}%", healthCard, result.health.insurance * 100),
        ]
        for (label, title, expected) in figures {
            #expect(try halere(label, in: title) == expected, "\(label) for \(context)")
        }

        // The two parts of the tax add up, rounded up to whole crowns, to the tax before the credit.
        let parts = try halere("Sazba 15\u{00A0}%", in: taxCard) + halere("Sazba 23\u{00A0}%", in: taxCard)
        #expect((parts + 99) / 100 == result.taxBeforeCredit, "\(context)")

        // The card of the net income adds up, whatever the year.
        try checkNetIncomeCard(in: sections, of: result, context)

        // What each authority has been paid in advances and what is left: a Doplatek for a year that is over, a
        // Zbývá for one in progress, or the overpayment.
        let tails = [(Authority.tax, taxCard), (.social, socialCard), (.health, healthCard)]
        for (authority, title) in tails {
            let balance = result.balance(authority)
            let rows = try section(title, in: sections).rows
            #expect(Array(rows.suffix(2).map(\.label)) == ["Zálohy", isOver ? "Doplatek" : "Zbývá"], "\(context)")
            #expect(rows.suffix(2).first?.value == CzechFormat.grouped(-balance.advancesPaid), "\(context)")
            let expected =
                balance.overpayment > 0
                ? "přeplatek " + CzechFormat.wholeKc(balance.overpayment) : CzechFormat.wholeKc(balance.remaining)
            #expect(rows.last?.value == expected, "\(authority) for \(context)")
            // A year in progress says where what remains goes; a year that is over only how an overpayment returns.
            let note = rows.last?.note
            if balance.overpayment > 0 {
                #expect(note?.hasPrefix("vrací se po") == true, "\(context)")
            } else if isOver || (balance.remaining == 0 && balance.plannedAfterAsOf == 0) {
                #expect(note == nil, "\(context)")
            } else {
                let leaves = CzechFormat.grouped(balance.leavesViaPlannedAdvances)
                let settlement = CzechFormat.grouped(balance.settlement)
                #expect(note?.hasPrefix("odejde plánovanými zálohami \(leaves)") == true, "\(context)")
                #expect(note?.hasSuffix(" \(settlement)") == true, "\(context)")
            }
        }
    }

    /// Checks that the card of the net income in `sections`, built for `result`, adds up: the levies are the net tax
    /// and the two insurances, the income and the three levies as the card shows them, with their signs, give the net
    /// income, which is the income less the levies in whole crowns, and the average is that over the months so far,
    /// with a half rounded away from zero: twelve on 31. 12. and otherwise those through the month of the day shown.
    private func checkNetIncomeCard(in sections: [ComputationSection], of result: TaxResult, _ context: String) throws {
        #expect(
            result.liabilityTotal == result.netTax + result.social.insurance + result.health.insurance, "\(context)")
        let net = result.P - result.liabilityTotal
        let rows = try section(netIncomeCard, in: sections).rows
        try #require(rows.count == 7, "\(context)")

        let resultRow = try row(netIncomeCard, in: netIncomeCard, of: sections)
        #expect(resultRow.value == CzechFormat.grouped(net), "\(context)")
        let values = rows.prefix(4).map { minorUnits(of: $0.value) }
        #expect(values.reduce(0, +) == net * 100, "\(context) \(values)")

        let isWholeYear = result.asOf.month == 12 && result.asOf.day == 31
        let months = isWholeYear ? 12 : result.asOf.month
        #expect(rows[5].value == String(months), "\(context)")
        let average = DecimalMath.halfUp(Decimal(net) / Decimal(months))
        #expect(rows[6].value == CzechFormat.wholeKc(average), "\(context)")
    }

    // MARK: Reading the rows back

    /// An amount such as "264 421,80", "−2 000" or "6 000 Kč" in haléře.
    private func minorUnits(of text: String) -> Int64 {
        let digits = text.replacingOccurrences(of: "\u{00A0}Kč", with: "")
        let isNegative = digits.hasPrefix("\u{2212}")
        let parts = digits.filter { $0.isNumber || $0 == "," }.split(separator: ",", omittingEmptySubsequences: false)
        guard let crowns = Int64(parts.first ?? ""), parts.count <= 2 else { return Int64.min }
        let fraction = parts.count == 2 ? Int64(parts[1]) ?? Int64.min : 0
        return (isNegative ? -1 : 1) * (crowns * 100 + fraction)
    }

    /// The whole-crown amounts in a note that stand right after one of `markers` ("hlavní 366 667"), in order.
    private func amounts(in note: String, after markers: [String]) -> [Int64] {
        let alternatives = markers.map { NSRegularExpression.escapedPattern(for: $0) }.joined(separator: "|")
        guard let amount = try? Regex("(?:\(alternatives)) (\\d{1,3}(?:\u{00A0}\\d{3})*)(?![\\d,])") else {
            return []
        }
        return note.matches(of: amount).compactMap { match in
            match.output[1].substring.flatMap { Int64(String($0).filter(\.isNumber)) }
        }
    }
}
