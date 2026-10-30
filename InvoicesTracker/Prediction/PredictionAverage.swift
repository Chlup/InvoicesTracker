import Foundation

/// The currency and requested day of one daily ČNB lookup.
nonisolated struct PredictionRateKey: Sendable, Hashable {
    var currency: CurrencyCode
    var day: CivilDate
}

/// An original net invoice amount and the day to use when converting it to crowns.
nonisolated struct PredictionAverageSample: Sendable, Hashable {
    var netMinor: Int64
    var currency: CurrencyCode
    var rateDay: CivilDate

    /// Crowns need no lookup; each foreign currency uses its requested daily rate.
    var rateKey: PredictionRateKey? {
        currency.isCZK ? nil : PredictionRateKey(currency: currency, day: rateDay)
    }
}

/// The arithmetic mean of all eligible invoice amounts converted individually to crowns.
nonisolated struct PredictionAverage: Sendable, Hashable {
    var sampleCount: Int
    var amountHalere: Int64?
    var missingRateKeys: Set<PredictionRateKey>

    /// Selects real issued invoices paid by `now` in `year`, regardless of their issue year, and unpaid invoices
    /// issued in `year` or the preceding year whose expected payment falls in `year`. Overdue payments are expected
    /// tomorrow. Drafts and review flags never train the mean. The original payment or issue date is retained for
    /// daily conversion; the rate loader handles future lookup dates independently of this receipt selection.
    static func samples(issued: [Invoice], year: Int, now: CivilDate, delayDays: Int) -> [PredictionAverageSample] {
        issued.compactMap { invoice in
            guard invoice.status == .issued, invoice.review == nil else { return nil }
            let rateDay: CivilDate
            if let payment = invoice.payment, payment.date <= now {
                guard payment.date.year == year else { return nil }
                rateDay = payment.date
            } else {
                guard (year - 1...year).contains(invoice.issueDate.year) else { return nil }
                let usualDay = invoice.issueDate.adding(days: delayDays)
                let payDay = usualDay > now ? usualDay : now.adding(days: 1)
                guard payDay.year == year else { return nil }
                rateDay = invoice.issueDate
            }
            return PredictionAverageSample(netMinor: invoice.netMinor, currency: invoice.currency, rateDay: rateDay)
        }
    }

    /// Converts each original net amount with its daily rate, rounding each conversion to haléře before averaging
    /// and rounding the mean half up. Every sample keeps its place in the denominator, including zero amounts.
    /// An empty sample or any missing conversion makes the mean unavailable, with every missing key reported.
    static func make(samples: [PredictionAverageSample], rates: [PredictionRateKey: StoredRate]) -> PredictionAverage {
        var total = Decimal(0)
        var missing: Set<PredictionRateKey> = []
        for sample in samples {
            if let key = sample.rateKey {
                guard let rate = rates[key] else {
                    missing.insert(key)
                    continue
                }
                total += Decimal(rate.rate.czkHalere(fromMinor: sample.netMinor))
            } else {
                total += Decimal(sample.netMinor)
            }
        }
        let amount = samples.isEmpty || !missing.isEmpty
            ? nil : DecimalMath.halfUp(total / Decimal(samples.count))
        return PredictionAverage(sampleCount: samples.count, amountHalere: amount, missingRateKeys: missing)
    }
}
