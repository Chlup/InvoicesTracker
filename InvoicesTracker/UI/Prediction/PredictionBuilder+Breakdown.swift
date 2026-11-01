import Foundation

/// The breakdown of the year's levies in two columns of cards: the income, the profit and the tax on the left, the
/// social and the health insurance with the net income under them on the right. The cards are those of Výpočet, except
/// where an estimate of the whole year says it differently: the income is the payments received and those that are
/// expected, the advances are those of the whole year, what is left to pay is the settlement of the year, and the net
/// income is that of the whole year. Every figure comes from the engine's result. Where Výpočet says the same, its own
/// notes and rows are used (`ComputationBuilder`) and not written again.
nonisolated extension PredictionBuilder {
    /// The cards of the two columns for `outcome`. The right column ends with the card of the net income.
    static func breakdown(_ outcome: PredictionOutcome) -> (left: [ComputationSection], right: [ComputationSection]) {
        guard outcome.prediction.isComplete else { return ([], []) }
        let facts = facts(of: outcome)
        return (
            [incomeSection(outcome), taxSection(outcome, facts)],
            [socialSection(outcome, facts), healthSection(outcome), netIncomeSection(outcome)]
        )
    }

    /// What Výpočet's rows are made from for the prediction: the year as of its last day, whether it is over or not.
    private static func facts(of outcome: PredictionOutcome) -> ComputationBuilder.Facts {
        ComputationBuilder.Facts(
            result: outcome.result, input: outcome.input, isOver: outcome.prediction.isClosed,
            incomeFXMethod: outcome.prediction.usesUniformRate ? .uniform : .cnbDaily, uniformSource: nil)
    }

    // MARK: Income and profit

    private static func incomeSection(_ outcome: PredictionOutcome) -> ComputationSection {
        let prediction = outcome.prediction
        let result = outcome.result
        let payments = CzechCount.counted(
            prediction.receivedCount, one: "platba", few: "platby", many: "plateb", separator: CzechFormat.noBreakSpace)
        var rows = [
            ComputationRow(
                label: "Přijaté platby", value: CzechFormat.amount(prediction.receivedHalere),
                note: "1.\u{00A0}1. – " + CzechFormat.dayMonth(prediction.now) + " · " + payments
                    + (prediction.includesAdjustments ? " · včetně úprav příjmů" : ""))
        ]
        if prediction.waitingHalere != 0 {
            rows.append(
                ComputationRow(
                    label: "Vystavené faktury", value: CzechFormat.amount(prediction.waitingHalere),
                    note: "zaplatí se do 31.\u{00A0}12. podle obvyklé doby placení odběratele", sign: .plus))
        }
        if prediction.expectedHalere != 0 {
            rows.append(
                ComputationRow(
                    label: "Koncepty a očekávané faktury", value: CzechFormat.amount(prediction.expectedHalere),
                    note: expectedNote(prediction), sign: .plus))
        }
        rows.append(
            ComputationRow(
                label: prediction.isClosed ? "Příjmy za rok \(prediction.year)" : "Příjmy za rok (odhad)",
                value: CzechFormat.amount(prediction.incomeHalere),
                note: prediction.nextYearHalere > 0
                    ? "bez \(kc(ofHalere: prediction.nextYearHalere)), které přijdou až v roce \(prediction.year + 1)"
                    : nil,
                sign: .equals, style: .strong))
        // The income the engine counts, in whole crowns, from which the expenses and the profit follow.
        rows.append(
            ComputationRow(
                label: "Příjmy z podnikání (§ 7)", value: ComputationBuilder.crowns(result.P),
                note: ComputationBuilder.incomeRoundingNote, sign: .equals, style: .strong))
        rows += expenseRows(result)
        return ComputationSection(title: "Příjmy a zisk", rows: rows, tag: prediction.isClosed ? "celý rok" : "odhad")
    }

    /// Which clients the expected invoices are from, each with what it adds: "podle Kdy čekám faktury · Foxtrot 542 386
    /// · Tango 9 000". Nil when none of the clients adds an expected invoice.
    private static func expectedNote(_ prediction: IncomePrediction) -> String? {
        let clients = prediction.clients.filter { $0.expectedHalere > 0 }.map {
            shortClientName($0.name) + " " + CzechFormat.grouped(wholeCrowns(ofHalere: $0.expectedHalere))
        }
        return clients.isEmpty ? nil : "podle Kdy čekám faktury · " + clients.joined(separator: " · ")
    }

    /// The name of a client without what follows its first comma and without its legal form ("s.r.o.", "a.s.", "SE",
    /// "Inc."): "Foxtrot, Inc." is "Foxtrot", and "Tango s.r.o." is "Tango".
    static func shortClientName(_ name: String) -> String {
        var short = name
        if let comma = short.firstIndex(of: ",") {
            short = String(short[..<comma])
        }
        short = short.trimmingCharacters(in: .whitespaces)
        let legalForm = #"\s+(s\.\s?r\.\s?o\.|a\.\s?s\.|SE|Inc\.)$"#
        if let range = short.range(of: legalForm, options: [.regularExpression, .caseInsensitive]) {
            short.removeSubrange(range)
        }
        return short.isEmpty ? name : short
    }

    /// The flat-rate expenses and the profit they leave. The note of the expenses says whether the cap cut them.
    private static func expenseRows(_ result: TaxResult) -> [ComputationRow] {
        let rate = ComputationBuilder.percent(Decimal(result.expensePercent) / 100, fractionDigits: 0)
        let cap = CzechFormat.grouped(result.expenseCap)
        let note =
            result.uncappedExpenses > result.expenseCap
            ? "\(rate) je \(ComputationBuilder.crowns(result.uncappedExpenses)) → použije se strop \(cap)"
            : "\(rate) z příjmů · strop \(cap)"
        return [
            ComputationRow(
                label: "Výdajový paušál \(rate)", value: ComputationBuilder.crowns(-result.V), note: note,
                sign: .minus),
            ComputationRow(
                label: "Zisk (dílčí základ daně)", value: ComputationBuilder.crowns(result.DZ), sign: .equals,
                style: .strong),
        ]
    }

    // MARK: Tax

    /// The income tax: from the profit through the deductions, the base and the tax before the credits to the credits
    /// of the taxpayer and of the family, and the advances of the year with what is left to pay.
    private static func taxSection(
        _ outcome: PredictionOutcome, _ facts: ComputationBuilder.Facts
    ) -> ComputationSection {
        let result = outcome.result
        var rows = [
            ComputationRow(label: "Zisk", value: ComputationBuilder.crowns(result.DZ)),
            ComputationRow(
                label: "Nezdanitelné části základu", value: ComputationBuilder.crowns(-result.deductionsTotal),
                note: ComputationBuilder.deductionsNote(result), sign: .minus),
            ComputationRow(
                label: "Základ daně", value: CzechFormat.grouped(result.B), note: "zaokrouhleno na celé stovky dolů",
                sign: .equals, style: .strong),
            ComputationRow(
                label: "Sazba " + ComputationBuilder.percent(TaxRules.taxRateLow, fractionDigits: 0),
                value: CzechFormat.grouped(result.taxBeforeCredit),
                note: ComputationBuilder.percent(TaxRules.taxRateHigh, fractionDigits: 0)
                    + " až ze základu nad " + CzechFormat.grouped(result.rules.taxBandThreshold),
                sign: .times),
            ComputationRow(
                label: "Sleva na poplatníka", value: CzechFormat.grouped(-result.creditApplied),
                note: ComputationBuilder.creditNote(facts), sign: .minus),
        ]
        rows += ComputationBuilder.familyRows(result)
        // The net tax: a tax bonus makes it negative.
        rows.append(
            ComputationRow(
                label: outcome.prediction.isClosed ? "Daň za rok \(outcome.prediction.year)" : "Daň za rok (odhad)",
                value: CzechFormat.grouped(result.netTax),
                note: result.netTax < 0 ? ComputationBuilder.bonusNote : nil, sign: .equals, style: .strong))
        rows += advanceRows(of: .tax, outcome)
        return ComputationSection(title: "Daň z příjmů", rows: rows, authority: .tax, tag: "Finanční úřad")
    }

    // MARK: Insurance

    /// The social insurance: the base with its minimum and maximum, the insurance and the advances of the year. A year
    /// with months of secondary activity has Výpočet's own rows of the base, which say how that is insured.
    private static func socialSection(
        _ outcome: PredictionOutcome, _ facts: ComputationBuilder.Facts
    ) -> ComputationSection {
        let social = outcome.result.social
        var rows: [ComputationRow]
        if social.secondaryMonths > 0 {
            // Výpočet's rows without its advances and what is left, which the prediction words on its own.
            rows = ComputationBuilder.socialRows(facts)
        } else {
            let share = ComputationBuilder.percent(outcome.result.rules.socialAssessmentPercent, fractionDigits: 0)
            rows = [
                ComputationRow(
                    label: "Vyměřovací základ", value: CzechFormat.grouped(social.base),
                    note: "\(share) zisku, nahoru · min. \(CzechFormat.grouped(social.minimumBase))"
                        + " (\(ComputationBuilder.months(social.mainMonths)) hlavní činnosti)"
                        + " · max. \(CzechFormat.grouped(social.maximumBase))"),
                ComputationRow(
                    label: "Sazba " + ComputationBuilder.percent(TaxRules.socialRate, fractionDigits: 1),
                    value: CzechFormat.grouped(social.insurance), note: ComputationBuilder.roundedUp, sign: .times),
            ]
        }
        rows += advanceRows(of: .social, outcome)
        return ComputationSection(title: "Sociální pojištění", rows: rows, authority: .social, tag: "ČSSZ")
    }

    /// The health insurance: the base in haléře with its minimum, the insurance and the advances of the year.
    private static func healthSection(_ outcome: PredictionOutcome) -> ComputationSection {
        let health = outcome.result.health
        let share = ComputationBuilder.percent(TaxRules.healthAssessmentPercent, fractionDigits: 0)
        var rows = [
            ComputationRow(
                label: "Vyměřovací základ", value: CzechFormat.amount(health.baseHalere),
                note: "\(share) zisku · min. \(CzechFormat.amount(health.minimumBaseHalere))"
                    + " (\(ComputationBuilder.months(health.minimumMonths)))"),
            ComputationRow(
                label: "Sazba " + ComputationBuilder.percent(TaxRules.healthRate, fractionDigits: 1),
                value: CzechFormat.grouped(health.insurance), note: ComputationBuilder.roundedUp, sign: .times),
        ]
        rows += advanceRows(of: .health, outcome)
        return ComputationSection(title: "Zdravotní pojištění", rows: rows, authority: .health, tag: "VZP")
    }

    // MARK: Net income

    /// The card of the net income of the whole year, as Výpočet builds it (`ComputationBuilder.netIncomeSection`),
    /// worded for the estimate: the result and the tag at the right of the title name the year when it is over and say
    /// "(odhad)" while it is in progress, and the average is over the whole year, which the note of the months says.
    /// The income is the one the levies are worked out from, in the same words as in Příjmy a zisk.
    private static func netIncomeSection(_ outcome: PredictionOutcome) -> ComputationSection {
        let year = outcome.prediction.year
        let isClosed = outcome.prediction.isClosed
        let wording = ComputationBuilder.NetIncomeWording(
            incomeLabel: "Příjmy z podnikání (§ 7)",
            resultLabel: isClosed ? "Čistý příjem za rok \(year)" : "Čistý příjem za rok (odhad)",
            tag: isClosed ? "za rok \(year)" : "za rok (odhad)",
            divisorNote: BuilderText.months(of: NetIncome(outcome.result)), incomeWord: "příjmů")
        return ComputationBuilder.netIncomeSection(outcome.result, wording: wording)
    }

    // MARK: Advances

    /// The advances of the whole year paid to `authority`, taken off its levy, and what is left to pay with the return
    /// or the overview, written as Výpočet writes it (`ComputationBuilder.leftValue(_:)`).
    private static func advanceRows(of authority: Authority, _ outcome: PredictionOutcome) -> [ComputationRow] {
        let balance = outcome.result.balance(authority)
        let payments = CzechCount.counted(
            outcome.plannedCount(authority), one: "platba", few: "platby", many: "plateb",
            separator: CzechFormat.noBreakSpace)
        return [
            ComputationRow(
                label: "Zálohy za rok", value: CzechFormat.grouped(-balance.advancesPaid),
                note: "podle plánu záloh · \(payments) za celý rok", sign: .minus),
            ComputationRow(
                label: "Doplatek", value: ComputationBuilder.leftValue(balance), sign: .equals, style: .total),
        ]
    }
}
