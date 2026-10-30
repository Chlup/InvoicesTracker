import Foundation

/// A payment the prediction expects in its year, with what it adds to the year's levies on the day it comes.
nonisolated struct ExpectedPayment: Sendable, Hashable {
    /// The day the payment is expected.
    var day: CivilDate

    /// The payment without VAT, in haléře.
    var amountHalere: Int64

    /// What the payment adds to the three levies together on its day, in whole Kč: the levies of the year with the
    /// money received by "now" and the payments expected before it, with and without this payment.
    var leviesKc: Int64

    /// What the payment leaves after the levies, in haléře: its amount less the levies, which are whole Kč. It is more
    /// than the amount when the levies are negative, because the payment brings a tax bonus, and it is negative when
    /// the levies are more than the payment, as the insurance has a minimum.
    var netHalere: Int64 {
        amountHalere - leviesKc * 100
    }
}

nonisolated extension PredictionOutcome {
    /// The payments the prediction expects in its year, one for each receipt of `prediction.syntheticReceipts` and in
    /// its order: by day, and on one day in the order of the clients.
    ///
    /// Each payment adds to the levies, on its own day, what the engine finds for the money received by "now" (the
    /// receipts of `input` that are not made up) and the payments expected before it, with this payment and without it.
    /// A payment that is equal to an earlier one is worked out like any other, on top of it. That is why the engine is
    /// asked for the levies of both inputs (`TaxEngine.compute(_:asOf:)`): `TaxEngine.effect(of:in:)` takes a made-up
    /// receipt that is equal out of the input first, so it would work the second payment out as if the first were not
    /// there.
    ///
    /// A payment dated outside the year of `input` adds no levies, as `TaxEngine.effect(of:in:)` finds for a receipt of
    /// another year: it stays in the result, in its place, with `leviesKc` 0, and the engine is never asked about its
    /// day, which it takes only in the year. The prediction dates a payment "now" or later by the delay it expects, but
    /// when that delay is a client's stored days to pay and they are below zero, a payment of early January is dated in
    /// the year before. The input is the one `make(prediction:yearInput:)` gave the engine already, which counts the
    /// receipts of its year only, so such a payment is in it and changes nothing.
    func expectedPayments() -> [ExpectedPayment] {
        let received = input.receipts.filter { $0.source != .synthetic }
        var earlier: [Receipt] = []
        var payments: [ExpectedPayment] = []
        for payment in prediction.syntheticReceipts {
            guard payment.day.year == input.year else {
                payments.append(ExpectedPayment(day: payment.day, amountHalere: payment.czkNetHalere, leviesKc: 0))
                continue
            }
            let without = leviesKc(of: received + earlier, asOf: payment.day)
            earlier.append(payment)
            let with = leviesKc(of: received + earlier, asOf: payment.day)
            payments.append(
                ExpectedPayment(day: payment.day, amountHalere: payment.czkNetHalere, leviesKc: with - without))
        }
        return payments
    }

    /// The three levies of the year together, in whole Kč, as of `day`, when the year's receipts are `receipts`. `day`
    /// must be in the year of the input, as the engine takes no other.
    private func leviesKc(of receipts: [Receipt], asOf day: CivilDate) -> Int64 {
        var changed = input
        changed.receipts = receipts
        return TaxEngine.compute(changed, asOf: day).liabilityTotal
    }
}
