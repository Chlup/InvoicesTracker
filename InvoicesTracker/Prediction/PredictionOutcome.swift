import Foundation

/// A year's prediction together with the levies the engine works out from it, as of 31 December of the year: from the
/// money received by "now" and the payments the prediction expects in the year, with the year's settings, deductions,
/// advances and family.
nonisolated struct PredictionOutcome: Sendable, Hashable {
    var prediction: IncomePrediction

    /// What the engine was given: the year's input with its receipts dated by "now" and the prediction's receipts.
    var input: YearInput

    /// The levies as of 31 December of the year. Its `receiptCount` counts the prediction's receipts too, so the
    /// payments received are counted by `prediction.receivedCount`. This known-input result is a publishable
    /// full-year estimate only when `prediction.isComplete` is true.
    var result: TaxResult

    /// The advances planned to `authority` for the whole year, its twelve months together, in whole Kč.
    func plannedTotal(_ authority: Authority) -> Int64 {
        plan(of: authority).reduce(0, +)
    }

    /// The months with an advance planned to `authority`.
    func plannedCount(_ authority: Authority) -> Int {
        plan(of: authority).filter { $0 != 0 }.count
    }

    /// What is left to pay with the returns: what the year's advances leave unpaid at each authority, together, in
    /// whole Kč. An overpayment at one authority does not lower what another is owed.
    var owedTotal: Int64 {
        Authority.allCases.reduce(0) { $0 + result.balance($1).remaining }
    }

    /// What the year's advances pay beyond the levies, at each authority, together, in whole Kč.
    var overpaidTotal: Int64 {
        Authority.allCases.reduce(0) { $0 + result.balance($1).overpayment }
    }

    /// The levies of `prediction`'s year with `yearInput`, the input of the year as the data holds it: its receipts are
    /// cut to those dated by "now", the prediction's receipts are added, and the engine computes the year as of its
    /// 31 December, so the minimum insurance counts the whole year. Throws `ComputationError.invalidYear` when the
    /// engine does not take the input, or `yearInput` is of another year.
    static func make(prediction: IncomePrediction, yearInput: YearInput) throws -> PredictionOutcome {
        var input = yearInput
        input.receipts = yearInput.receipts.filter { $0.day <= prediction.now } + prediction.syntheticReceipts
        let result = try AppModel.compute(input, asOf: PredictionInput.lastDay(of: prediction.year))
        return PredictionOutcome(prediction: prediction, input: input, result: result)
    }

    /// The twelve planned advances to `authority`.
    private func plan(of authority: Authority) -> [Int64] {
        switch authority {
        case .tax: input.advances.tax
        case .social: input.advances.social
        case .health: input.advances.health
        }
    }
}
