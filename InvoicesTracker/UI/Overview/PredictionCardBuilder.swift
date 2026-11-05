import Foundation

/// The card "Odhad za celý rok" of Přehled: the estimate of the current year in a head, a line under it, the
/// calculation of the year beside how its levies are paid, and under them the chart of the year's twelve months. The
/// whole card is an estimate, as its head says, so no figure on it carries a sign of one.
nonisolated struct PredictionCardData: Sendable, Hashable {
    /// "Odhad za celý rok 2026".
    var head: String

    /// What the estimate counts and up to which day: "z faktur do 17. 10. 2026 · co ještě do 31. 12. přijde".
    var sub: String

    /// The income of the year less its levies, what that leaves and that per month, and beside it how the levies are
    /// paid (`PredictionBuilder.calculation(_:incomeLabel:incomeNote:marksEstimate:)`).
    var calculation: PredictionCalculation

    /// The twelve months of the year, January first, for the chart under the calculation: the actual months up to
    /// today from the invoices and payments in the data, then the rest of the year from the prediction
    /// (`PredictionChartBuilder.months(year:today:rows:paymentEffects:prediction:expectedPayments:)`). The card that
    /// `PredictionBuilder.card(_:)` makes has none, as it has only the prediction. The builder of the page fills it in.
    var chart: [PredictionChartMonth] = []
}

/// The card of Přehled that gives the estimate of the year as a calculation, with how its levies are paid, and leaves
/// the rest to Odhad odvodů.
nonisolated extension PredictionBuilder {
    /// The card for `outcome`, the estimate of a year in progress, as of the day it was made, `prediction.now`. Every
    /// figure is an estimate, which the head of the card says, so none of them has the sign "≈" in front of it. A year
    /// that is over has no card, and the caller leaves it out. The income is "Příjmy za rok", with the money that has
    /// come so far under it in grouped whole Kč: "z toho přišlo 2 191 771". An estimate that is not complete has a dash
    /// for each figure under the same labels, and the line under the head says why, once
    /// (`incompleteCalculation(_:incomeLabel:incomeNote:)`).
    static func card(_ outcome: PredictionOutcome) -> PredictionCardData {
        let prediction = outcome.prediction
        let head = "Odhad za celý rok \(prediction.year)"
        let incomeNote = "z toho přišlo " + CzechFormat.grouped(wholeCrowns(ofHalere: prediction.receivedHalere))
        guard prediction.isComplete else {
            return PredictionCardData(
                head: head, sub: incompleteText,
                calculation: incompleteCalculation(outcome, incomeLabel: incomeLabel, incomeNote: incomeNote))
        }
        return PredictionCardData(
            head: head,
            sub: "z faktur do " + CzechFormat.date(prediction.now) + " · co ještě do 31.\u{00A0}12. přijde",
            calculation: calculation(outcome, incomeLabel: incomeLabel, incomeNote: incomeNote, marksEstimate: false))
    }

    /// The label of the income of the year on the card, which the head names.
    private static let incomeLabel = "Příjmy za rok"
}
