import Foundation

/// The card "Odhad za celý rok" of Přehled: the estimate of the current year in a head, a line under it, three figures
/// of the year and two per month, and under them the chart of the year's twelve months. The whole card is an estimate,
/// as its head says, so no figure on it carries a sign of one.
nonisolated struct PredictionCardData: Sendable, Hashable {
    /// "Odhad za celý rok 2026".
    var head: String

    /// What the estimate counts and up to which day: "z faktur do 17. 10. 2026 · co ještě do 31. 12. přijde".
    var sub: String

    /// The income of the year, its tax and insurance, and what is left to settle with the returns, in this order: the
    /// first row of figures.
    var stats: [PredictionMini]

    /// The figures per month, in this order: the net income, which has the green dot, and what to set aside. They are
    /// the second row of figures, under a hairline of their own.
    var monthStats: [PredictionMini]

    /// The twelve months of the year, January first, for the chart under the figures: the actual months up to today
    /// from the invoices and payments in the data, then the rest of the year from the prediction
    /// (`PredictionChartBuilder.months(year:today:rows:paymentEffects:prediction:expectedPayments:)`). The card that
    /// `PredictionBuilder.card(_:)` makes has none, as it has only the prediction. The builder of the page fills it in.
    var chart: [PredictionChartMonth] = []
}

/// The card of Přehled that gives the estimate of the year in five figures, in two rows, and leaves the rest to Odhad
/// odvodů.
nonisolated extension PredictionBuilder {
    /// The card for `outcome`, the estimate of a year in progress, as of the day it was made, `prediction.now`. Every
    /// figure is an estimate, which the head of the card says, so none of them has the sign "≈" in front of it. A year
    /// that is over has no card, and the caller leaves it out. The figures are in two rows by meaning: the year's
    /// (`stats`), then the ones per month (`monthStats`). An estimate that is not complete has a dash for each figure.
    static func card(_ outcome: PredictionOutcome) -> PredictionCardData {
        let prediction = outcome.prediction
        guard prediction.isComplete else {
            return PredictionCardData(
                head: "Odhad za celý rok \(prediction.year)", sub: incompleteText,
                stats: [
                    PredictionMini(
                        label: "Příjmy za rok", value: "—",
                        sub: "z toho přišlo " + kc(ofHalere: prediction.receivedHalere)),
                    PredictionMini(label: "Odvody", value: "—", sub: incompleteText),
                    PredictionMini(label: "Doplatek", value: "—", sub: incompleteText),
                ],
                monthStats: [
                    PredictionMini(
                        label: netIncomeLabel, value: "—", sub: incompleteText, marksNetIncome: true),
                    PredictionMini(label: setAsideLabel, value: "—", sub: incompleteText),
                ])
        }
        return PredictionCardData(
            head: "Odhad za celý rok \(prediction.year)",
            sub: "z faktur do " + CzechFormat.date(prediction.now) + " · co ještě do 31.\u{00A0}12. přijde",
            stats: [incomeStat(prediction), leviesStat(outcome.result), settlementStat(outcome)],
            monthStats: [netIncomeStat(outcome.result), setAsideStat(outcome)])
    }

    /// The label of the net income per month.
    private static let netIncomeLabel = "Čistý příjem průměrně za měsíc"

    /// The label of what to set aside per month.
    private static let setAsideLabel = "Odkládat průměrně za měsíc"

    /// The income of the whole year, and how much of it has come.
    private static func incomeStat(_ prediction: IncomePrediction) -> PredictionMini {
        PredictionMini(
            label: "Příjmy za rok", value: kc(ofHalere: prediction.incomeHalere),
            sub: "z toho přišlo " + kc(ofHalere: prediction.receivedHalere))
    }

    /// The tax and the insurance of the year together, "Odvody", beside it the share of the income they take
    /// (`PredictionBuilder.leviesShare(_:)`), and what each authority takes of it, without the currency. A tax below
    /// zero is a bonus that the tax office pays, and reads so in place of the tax.
    private static func leviesStat(_ result: TaxResult) -> PredictionMini {
        let tax = result.balance(.tax).liability
        let taxText = tax < 0 ? "daňový bonus " + CzechFormat.grouped(-tax) : "daň " + CzechFormat.grouped(tax)
        let social = CzechFormat.grouped(result.balance(.social).liability)
        let health = CzechFormat.grouped(result.balance(.health).liability)
        return PredictionMini(
            label: "Odvody", value: CzechFormat.wholeKc(result.liabilityTotal),
            share: leviesShare(result), sub: "\(taxText) · sociální \(social) · zdravotní \(health)")
    }

    /// What is left to pay with the returns, "Doplatek", after the advances of the whole year; or, when nothing is owed
    /// and the advances pay more than the levies, what is overpaid, "Přeplatek". An overpayment at one authority does
    /// not lower what another is owed, so a year with both is a sum to pay (as in the result card of Odhad odvodů).
    private static func settlementStat(_ outcome: PredictionOutcome) -> PredictionMini {
        let owed = outcome.owedTotal
        let overpaid = outcome.overpaidTotal
        guard owed > 0 || overpaid == 0 else {
            return PredictionMini(
                label: "Přeplatek", value: CzechFormat.wholeKc(overpaid), sub: "zálohy převýší odvody")
        }
        return PredictionMini(
            label: "Doplatek", value: CzechFormat.wholeKc(owed),
            sub: "po zálohách " + CzechFormat.wholeKc(outcome.result.advancesPaidTotal) + " za celý rok")
    }

    /// What the year's income leaves after the tax and the insurance (`NetIncome`), as its average per month and, under
    /// it, as the sum of the whole year. The estimate is worked out for 31 December, so the average is over all twelve
    /// months. The figures are negative, and read with the minus sign, where the levies are more than the income. It
    /// has the green dot.
    private static func netIncomeStat(_ result: TaxResult) -> PredictionMini {
        let net = NetIncome(result)
        return PredictionMini(
            label: netIncomeLabel, value: CzechFormat.wholeKc(net.monthlyKc),
            sub: "za celý rok " + CzechFormat.wholeKc(net.yearKc), marksNetIncome: true)
    }

    /// What to set aside each month for the irregular levy payments: the year's tax advances and the doplatek of all
    /// three authorities, paid with the returns, over twelve months (`PredictionOutcome.setAsideMonthly`), and under
    /// it the sum of the whole year (`PredictionBuilder.setAsideNote(_:total:)`). The card is an estimate as a whole,
    /// so neither carries the sign "≈".
    private static func setAsideStat(_ outcome: PredictionOutcome) -> PredictionMini {
        PredictionMini(
            label: setAsideLabel, value: CzechFormat.wholeKc(outcome.setAsideMonthly),
            sub: setAsideNote(outcome, total: CzechFormat.wholeKc(outcome.setAsideTotal)))
    }
}
