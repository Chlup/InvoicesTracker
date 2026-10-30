import Foundation

// MARK: - Builder

/// Turns the prediction of a year and the levies the engine works out from it into the page of Odhad odvodů: the
/// summary card, the banner, the months of the clients and the two columns of the breakdown. Every text is made here,
/// and the screen only lays them out. The summary, the banner and the months are in this file, the rows of the clients
/// and their cells in `+Clients`, and the breakdown in `+Breakdown`.
///
/// Nothing is worked out again: the income, the parts of it and the months come from the prediction, and every figure
/// of the levies from the engine's result; so do the net income and its part of the income (`NetIncome`,
/// `IncomeShares`). The breakdown reuses Výpočet's own rows and notes where it says the same (`ComputationBuilder`).
///
/// The sign "≈", followed by a no-break space so that a line never ends with the sign alone (`estimateSign`), stands in
/// front of a figure that is an estimate. In a year in progress these are the sum that is paid only in the next year
/// and the amounts expected of the clients, in their rows and in the cells of their months. The income of the year has
/// no sign: its head says that it is an estimate, and so does the caption of the net income. The advances never have
/// it, and the sum of the levies, each of them, the amount of the settlement and the two figures of the net income, its
/// average per month and the sum of the year, have it only in the case below. A year that is over has no estimate: it
/// is what it was, and none of its texts has the sign, even when a payment is converted at a provisional rate; only the
/// banner takes account of that (`page(_:hasProvisionalIncome:)`). The one exception is the levies of a year that the
/// engine worked out with the rules of another year (`TaxResult.rulesAreEstimate`): they are an estimate whether the
/// year is over or not, so the sum of them, each of them, the amount of the settlement and the net income, which is the
/// income less them, have the sign. The sums are in whole Kč, rounded half up from haléře, and the dates are written as
/// everywhere in the app (`CzechFormat`).
nonisolated enum PredictionBuilder {
    // MARK: Texts

    /// The sentence that no invoice is expected from any client.
    static let noActiveText =
        "Od žádného odběratele teď fakturu nečekám."
        + " Rozbalte ostatní odběratele a označte měsíce, kdy faktura přijde."

    /// Why the whole-year figures are unavailable while their known components remain visible.
    static let incompleteText =
        "Odhad je neúplný: některé částky nejsou známé – chybí kurz nebo podklady pro odhad."

    // MARK: The page

    /// The page for `outcome`, the prediction of a year with its levies. Every date it writes is the day the prediction
    /// is made as of, `outcome.prediction.now`. `hasProvisionalIncome` says that the screen shows, above the page, that
    /// part of the income up to that day is converted at a provisional rate (`RulesWarning.provisionalIncome`). The
    /// banner of a year that is over then no longer says that nothing is estimated, as it does not for levies worked
    /// out with the rules of another year. Nothing else of the page changes: the rate puts no sign "≈" on the income,
    /// on the levies or on the net income.
    static func page(_ outcome: PredictionOutcome, hasProvisionalIncome: Bool = false) -> PredictionPage {
        let prediction = outcome.prediction
        let year = prediction.year
        let isClosed = prediction.isClosed
        let rulesAreEstimate = outcome.result.rulesAreEstimate
        let active = prediction.clients.filter(\.isActive)
        let others = prediction.clients.filter { !$0.isActive }
        let columns = breakdown(outcome)
        let monthsSub =
            "Měsíce s očekávanou fakturou předvyplňuje aplikace podle dosavadních faktur."
            + " Klepnutím je změníte, když víte víc – třeba u nové zakázky nebo když spolupráce končí."
        return PredictionPage(
            label: isClosed ? "Odvody za rok \(year) – skutečnost" : "Odhad odvodů za celý rok \(year)",
            hero: prediction.isComplete
                ? estimate(CzechFormat.wholeKc(outcome.result.liabilityTotal), when: rulesAreEstimate) : "—",
            heroShare: prediction.isComplete ? leviesShare(outcome.result).map { $0 + " příjmů" } : nil,
            levies: levies(outcome.result).map { levy in
                var shown = levy
                if !prediction.isComplete { shown.value = "—" }
                return shown
            }, heroText: prediction.isComplete ? heroText(prediction) : incompleteText,
            settlement: settlement(outcome),
            incomeHead: isClosed ? "Příjmy za rok \(year)" : "Příjmy za rok \(year) (odhad)",
            incomeTotal: prediction.isComplete ? kc(ofHalere: prediction.incomeHalere) : "—",
            parts: parts(prediction), netIncome: prediction.isComplete
                ? netIncome(outcome.result, isClosed: isClosed)
                : PredictionNetIncome(
                    label: "Čistý příjem průměrně za měsíc (odhad)", amount: "—", sub: incompleteText),
            nextYearNote: nextYearNote(prediction),
            banner: banner(
                prediction, rulesAreEstimate: rulesAreEstimate, hasProvisionalIncome: hasProvisionalIncome),
            monthsHead: isClosed ? "Faktury po měsících" : "Kdy čekám faktury",
            monthsSub: isClosed ? "Podle data vystavení." : monthsSub, legend: legend(isClosed: isClosed),
            activeRows: active.map { clientRow($0, in: prediction) },
            otherRows: others.map { clientRow($0, in: prediction) },
            othersTitle: "Ostatní odběratelé (\(others.count))", othersSub: othersSub(others, in: prediction),
            noActiveText: active.isEmpty && !others.isEmpty && !isClosed ? noActiveText : nil,
            left: columns.left, right: columns.right)
    }

    // MARK: The summary card

    /// The share of the year's income that the tax and the insurance take together, in percent with one decimal:
    /// "17,0 %". It is the part of the income that the net income does not leave (`IncomeShares`), and nil when the
    /// income is not above zero. Odhad odvodů writes it beside the sum of the levies, and the card of the estimate on
    /// Přehled beside its figure of them. It never has the sign "≈".
    static func leviesShare(_ result: TaxResult) -> String? {
        IncomeShares(result).map { BuilderText.share(tenths: $0.leviesTenths) }
    }

    /// The tax, the social and the health insurance of the year. Each has the sign of an estimate in front of it when
    /// the engine worked the year out with the rules of another year.
    private static func levies(_ result: TaxResult) -> [PredictionLevy] {
        Authority.allCases.map { authority in
            let liability = result.balance(authority).liability
            let value = authority == .tax ? BuilderText.taxOrBonus(liability) : CzechFormat.wholeKc(liability)
            return PredictionLevy(
                authority: authority, title: ComputationBuilder.shortName(of: authority),
                value: estimate(value, when: result.rulesAreEstimate))
        }
    }

    /// What the sum of the levies is made from: for a year in progress the estimated income, for a year that is over
    /// the payments.
    private static func heroText(_ prediction: IncomePrediction) -> String {
        if prediction.isClosed {
            return "Daň a pojistné za celý rok \(prediction.year) ze všech přijatých plateb."
        }
        return "Daň a pojistné z odhadovaného příjmu \(kc(ofHalere: prediction.incomeHalere))"
            + " za celý rok \(prediction.year)"
            + " – s odpočty a slevami ze Záloh a odpočtů a s minimálním pojistným za celý rok."
    }

    /// What is left to pay with the returns beyond the year's advances, which its sentence names; or, when nothing is
    /// owed and the advances pay more than the levies, what is overpaid. What is left to pay is the sum of what each
    /// authority is owed: an overpayment at one authority does not lower what another is owed, but the sentence names
    /// it beside. The amount has the sign of an estimate only when the engine worked the year out with the rules of
    /// another year, as the sum of the levies has; the advances never have it.
    private static func settlement(_ outcome: PredictionOutcome) -> PredictionSettlement {
        let prediction = outcome.prediction
        let isClosed = prediction.isClosed
        guard prediction.isComplete else {
            return PredictionSettlement(
                kind: .owed, label: "Odhad doplatku odvodů bez záloh", amount: "—",
                lead: incompleteText + " Plánované zálohy ",
                advances: CzechFormat.wholeKc(outcome.result.advancesPaidTotal), tail: " za celý rok.")
        }
        let owed = outcome.owedTotal
        let overpaid = outcome.overpaidTotal
        let advances = CzechFormat.wholeKc(outcome.result.advancesPaidTotal)
        func amount(_ crowns: Int64) -> String {
            estimate(CzechFormat.wholeKc(crowns), when: outcome.result.rulesAreEstimate)
        }
        guard owed > 0 || overpaid == 0 else {
            return PredictionSettlement(
                kind: .overpaid, label: isClosed ? "Přeplatek záloh" : "Odhad přeplatku záloh",
                amount: amount(overpaid), lead: "Zálohy ", advances: advances,
                tail: " převýší odvody – rozdíl se vrátí po podání přiznání a přehledů.")
        }
        let beside =
            overpaid > 0
            ? " U některého úřadu " + (isClosed ? "vznikl" : "vznikne") + " přeplatek " + CzechFormat.wholeKc(overpaid)
                + "."
            : ""
        if isClosed {
            return PredictionSettlement(
                kind: .owed, label: "Doplatek odvodů bez záloh", amount: amount(owed),
                lead: "Za rok \(prediction.year) navíc k zálohám ", advances: advances,
                tail: " – daň, ČSSZ a VZP po podání přiznání a přehledů." + beside)
        }
        return PredictionSettlement(
            kind: .owed, label: "Odhad doplatku odvodů bez záloh", amount: amount(owed),
            lead: "Tolik si odložte stranou – navíc k zálohám ", advances: advances,
            tail: ", které platíte průběžně. Platí se po skončení roku s přiznáním a přehledy pro ČSSZ a VZP." + beside)
    }

    /// What was received, and in a year in progress what waits for its payment and what is expected, each with its part
    /// of the income for the bar.
    private static func parts(_ prediction: IncomePrediction) -> [PredictionPart] {
        let income = prediction.incomeHalere
        let unknown = prediction.expectedInvoices.filter {
            $0.isCounted && $0.payDay.year == prediction.year && $0.hasUnknownAmount
        }
        func part(
            _ kind: PredictionPartKind, _ text: String, _ halere: Int64, hasUnknown: Bool = false
        ) -> PredictionPart {
            PredictionPart(
                kind: kind,
                text: text + (hasUnknown ? (halere == 0 ? " (částka neznámá)" : " (známá část)") : ""),
                value: hasUnknown && halere == 0 ? "—" : kc(ofHalere: halere),
                fraction: prediction.isComplete ? fraction(halere, of: income) : 0)
        }
        var parts = [part(.received, "Přišlo do " + CzechFormat.date(prediction.now), prediction.receivedHalere)]
        if !prediction.isClosed {
            parts.append(
                part(.waiting, "Vystaveno, čeká na platbu", prediction.waitingHalere,
                    hasUnknown: unknown.contains { $0.kind == .waiting }))
            parts.append(
                part(.expected, "Koncepty a očekávané faktury", prediction.expectedHalere,
                    hasUnknown: unknown.contains { $0.kind != .waiting }))
        }
        return parts
    }

    /// `part` of `whole` for drawing a bar, 0 to 1.
    private static func fraction(_ part: Int64, of whole: Int64) -> Double {
        guard whole > 0 else { return 0 }
        return min(1, max(0, Double(part) / Double(whole)))
    }

    /// What the income of the year leaves after the levies (`NetIncome`): its average per month as the amount, and
    /// under it the sum of the whole year, with the part of the income that the sum is (`IncomeShares`) while the
    /// income is above zero. A part below zero or above the whole is shown as it is. The result is of 31 December, so
    /// the average is over all twelve months. The caption says that the figure is an estimate in a year in progress, as
    /// the head of the income does, and the two figures have the sign of an estimate only when the engine worked the
    /// year out with the rules of another year, as the levies they are made from have.
    private static func netIncome(_ result: TaxResult, isClosed: Bool) -> PredictionNetIncome {
        let net = NetIncome(result)
        let share =
            IncomeShares(result).map { " · " + BuilderText.share(tenths: $0.netTenths) + " příjmů po dani a pojistném" }
            ?? ""
        return PredictionNetIncome(
            label: isClosed ? "Čistý příjem průměrně za měsíc" : "Čistý příjem průměrně za měsíc (odhad)",
            amount: estimate(CzechFormat.wholeKc(net.monthlyKc), when: result.rulesAreEstimate),
            sub: "za celý rok " + estimate(CzechFormat.wholeKc(net.yearKc), when: result.rulesAreEstimate) + share)
    }

    /// The sum that is paid only in the next year, which is that year's income, or nil when there is none. The note
    /// names the year and not a month: a payment after 31 December need not come in January.
    private static func nextYearNote(_ prediction: IncomePrediction) -> String? {
        if prediction.hasUnknownNextYearAmount {
            let known = prediction.nextYearHalere > 0
                ? " Známá část: " + kc(ofHalere: prediction.nextYearHalere) + "." : ""
            return "Část příjmů přijde až v roce \(prediction.year + 1), ale jejich celková částka není známá"
                + " – chybí kurz nebo podklady pro odhad." + known
        }
        guard prediction.nextYearHalere > 0 else { return nil }
        let next = prediction.year + 1
        return estimate(kc(ofHalere: prediction.nextYearHalere), isClosed: prediction.isClosed)
            + " přijde až v roce \(next) (faktury zaplacené po 31.\u{00A0}12.) – to už jsou příjmy roku \(next)."
    }

    // MARK: The banner and the months

    /// What the estimate counts and what rates it converts the amounts in other currencies with: the ČNB rate of the
    /// day it was declared, or the uniform rate of the year. For a year that is over, that all payments are known and,
    /// unless the engine worked the year out with the rules of another year (`rulesAreEstimate`) or part of the income
    /// is converted at a provisional rate (`hasProvisionalIncome`), that nothing is estimated.
    private static func banner(
        _ prediction: IncomePrediction, rulesAreEstimate: Bool, hasProvisionalIncome: Bool
    ) -> String {
        if prediction.isClosed {
            let known = "Rok \(prediction.year) skončil: všechny platby jsou známé"
            return (rulesAreEstimate || hasProvisionalIncome ? known + "." : known + ", nic se neodhaduje.")
                + " Měsíce ukazují, co se kdy vyfakturovalo."
        }
        let rates =
            prediction.usesUniformRate
            ? "cizí měny jednotným kurzem \(prediction.year)"
            : "cizí měny kurzem ČNB z " + CzechFormat.date(prediction.rateDay ?? prediction.now)
        return "Odhad vychází z faktur do \(CzechFormat.date(prediction.now)): přijaté platby, vystavené faktury"
            + " a faktury, které podle dosavadního rytmu odběratele ještě přijdou."
            + " Počítají se jen peníze, které přijdou do 31.\u{00A0}12."
            + " – faktura zaplacená až v lednu patří do příjmů dalšího roku."
            + " Částka další faktury je průměr všech skutečných a očekávaných plateb v roce \(prediction.year)"
            + " z reálných faktur odběratele. Cizoměnové částky převádím každou zvlášť denním kurzem ČNB"
            + " ke dni platby, u nezaplacených ke dni vystavení (nejpozději k dnešku)."
            + " Průměr se proto může lišit od uložených částek plateb."
            + " Koncepty a čekající platby převádím: \(rates)."
            + (prediction.isComplete ? "" : " " + incompleteText)
    }

    /// What the cells mean. A year that is over has only the cells of invoices.
    private static func legend(isClosed: Bool) -> [PredictionLegendItem] {
        var legend = [
            PredictionLegendItem(kind: .paid, text: "zaplaceno"),
            PredictionLegendItem(kind: .waiting, text: "čeká na platbu"),
        ]
        if !isClosed {
            legend.append(PredictionLegendItem(kind: .expected, text: "čekám fakturu"))
            legend.append(PredictionLegendItem(kind: .expectedNextYear, text: "zaplatí se až příští rok"))
        }
        return legend
    }

    /// Why the group of the other clients is folded, and who is in it.
    private static func othersSub(_ others: [ClientPrediction], in prediction: IncomePrediction) -> String {
        let why = prediction.isClosed ? "v roce \(prediction.year) bez faktur" : "letos od nich nic nečekám"
        guard !others.isEmpty else { return why }
        return why + " · " + others.map(\.name).joined(separator: ", ")
    }

    // MARK: Texts of numbers

    /// `halere` in whole crowns, rounded half up.
    static func wholeCrowns(ofHalere halere: Int64) -> Int64 {
        DecimalMath.halfUp(Decimal(halere) / 100)
    }

    /// `halere` as whole Kč: "2 191 771 Kč".
    static func kc(ofHalere halere: Int64) -> String {
        CzechFormat.wholeKc(wholeCrowns(ofHalere: halere))
    }

    /// The sign of an estimate, and a no-break space to keep it with the figure.
    static let estimateSign = "≈\u{00A0}"

    /// `text` as an estimate: with the sign in front of it in a year in progress, and as it is in a year that is
    /// over.
    static func estimate(_ text: String, isClosed: Bool) -> String {
        isClosed ? text : estimateSign + text
    }

    /// `text` with the sign of an estimate in front of it when `isEstimate`, and as it is otherwise.
    private static func estimate(_ text: String, when isEstimate: Bool) -> String {
        isEstimate ? estimateSign + text : text
    }
}
