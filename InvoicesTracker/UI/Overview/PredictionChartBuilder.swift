import Foundation

/// One month of the chart on the card of the estimate in Přehled: what was issued in it, what was received in it, and
/// what the payments received in it leave after the levies they add. Each is in two parts, the actual figure up to
/// today and the estimate of what is still to come. Amounts are in haléře. The texts say them in whole Kč, or "—" for a
/// part that does not apply to the month: the estimate of a past month and the actual figure of a future one. None of
/// them has the sign "≈", as the card they stand in is an area of estimates as a whole.
nonisolated struct PredictionChartMonth: Sendable, Hashable, Identifiable {
    /// Where a month stands against today.
    nonisolated enum Part: Sendable, Hashable {
        /// A month before the one of today: it has only its actual figures.
        case past

        /// The month of today: its actual figures are those up to today, and its estimate is what is still to come.
        case current

        /// A month after the one of today: it has only its estimate.
        case future
    }

    /// The number of the month, 1 for January to 12 for December.
    var month: Int

    /// The short name of the month, under its bars: "říj".
    var label: String

    /// What the tooltip calls the month: "Září 2026"; for the current month "Říjen 2026 · do 17. 10. skutečnost, dál
    /// odhad", with today's day; for a future one "Listopad 2026 · odhad".
    var title: String
    var part: Part

    /// The amount without VAT of the invoices issued in the month by the reporting cutoff (the end of the current
    /// month), in haléře, so in the current month also the invoices dated after today. 0 for a future month.
    var issuedActualHalere: Int64

    /// The amount without VAT of the invoices still to be issued in the month, in haléře: the invoices expected from a
    /// draft or from a client's rhythm, and the invoices already in the data but dated after the reporting cutoff,
    /// each at the prediction's amount while it waits for its payment and at what was paid once the money has come. 0
    /// for a past month.
    var issuedEstimateHalere: Int64

    /// The money received in the month by today, without VAT, in haléře. 0 for a future month.
    var receivedActualHalere: Int64

    /// The money still expected in the month, without VAT, in haléře. 0 for a past month.
    var receivedEstimateHalere: Int64

    /// What the payments received in the month by today leave after the levies they added on their own days, in
    /// haléře. 0 for a future month.
    var netActualHalere: Int64

    /// What the payments still expected in the month leave after the levies they add on their own days, in haléře. 0
    /// for a past month.
    var netEstimateHalere: Int64

    /// `issuedActualHalere` in whole Kč, rounded half up, "310 227 Kč", or "—" for a future month.
    var issuedActualText: String

    /// `issuedEstimateHalere` in whole Kč, or "—" for a past month.
    var issuedEstimateText: String

    /// `receivedActualHalere` in whole Kč, or "—" for a future month.
    var receivedActualText: String

    /// `receivedEstimateHalere` in whole Kč, or "—" for a past month.
    var receivedEstimateText: String

    /// `netActualHalere` in whole Kč, or "—" for a future month.
    var netActualText: String

    /// `netEstimateHalere` in whole Kč, or "—" for a past month.
    var netEstimateText: String

    /// Whether `issuedActualHalere` is approximate: an invoice in another currency whose ČNB rate of the day of issue
    /// is not declared yet is worth the latest declared rate. The amount has no sign for it, the card being an area of
    /// estimates as a whole; the note under the figures of the month says why it is approximate (`notes`).
    var issuedActualIsApproximate = false

    /// The sentences under the figures of the tooltip, which VoiceOver reads after them: that the invoices issued cover
    /// the whole current month while the money received stops at today, and why an amount is approximate.
    var notes: [String] = []

    var id: Int {
        month
    }

    /// What VoiceOver reads for the month: its title, then what was issued, what was received and what the payments
    /// left after the levies. A past month tells its actual figures and a future one its estimates; the current month
    /// tells both for each, the actual one first.
    var accessibilityLabel: String {
        let phrases: [String]
        switch part {
        case .past:
            phrases = [
                "vystaveno " + issuedActualText, "přijato " + receivedActualText, "čistý příjem " + netActualText,
            ]
        case .future:
            phrases = [
                "vystaveno " + issuedEstimateText, "přijato " + receivedEstimateText,
                "čistý příjem " + netEstimateText,
            ]
        case .current:
            phrases = [
                "vystaveno \(issuedActualText) skutečnost, \(issuedEstimateText) odhad",
                "přijato \(receivedActualText) skutečnost, \(receivedEstimateText) odhad",
                "čistý příjem \(netActualText) skutečnost, \(netEstimateText) odhad",
            ]
        }
        return title + ": " + (phrases + notes).joined(separator: "; ")
    }
}

/// Works out the twelve months of the chart on the card of the estimate in Přehled. The months up to today are what the
/// data holds, the invoices issued and the payments received; the rest of the year is what the prediction expects,
/// together with the invoices dated in it whose money has come already.
nonisolated enum PredictionChartBuilder {
    /// What the text of a part that does not apply to a month says.
    private static let notApplicable = "—"

    /// The three sums of one part of one month, in haléře.
    private nonisolated struct Sums {
        var issued: Int64 = 0
        var issuedIsApproximate = false
        var received: Int64 = 0
        var net: Int64 = 0
    }

    // MARK: The months

    /// The twelve months of `year`, January first. `year` is the year of `today`: the card is for the current year.
    ///
    /// A month before the one of `today` is past and has only its actual figures, the month of `today` is current and
    /// has both, and a month after it is future and has only its estimate. A part that does not apply is 0 in the
    /// amounts and "—" in the texts; one that applies and has nothing in it is 0 and "0 Kč".
    ///
    /// The actual figures leave out drafts and invoices in review. What was issued is reported through `issuedThrough`,
    /// the reporting cutoff, which is the end of the current month and so after `today` (it is never before it; `nil`
    /// is `today`), while the money received and the net income stop at `today`, whatever the cutoff is:
    /// - issued: the invoices of `year` in `rows` issued in the month by `issuedThrough`, each worth what the chart of
    ///   Příjmy counts for it (`OverviewBuilder.issuedValue(of:receivedThrough:)`, with payments counted up to
    ///   `today`), also when it is dated after `today`. An unpaid invoice in another currency whose rate of the day of
    ///   issue is not declared yet is worth the latest declared rate, and the month says its figure is approximate;
    /// - received: the payments of those invoices dated in the month of `year` by `today`, whatever the year the
    ///   invoice was issued in;
    /// - net: what the payments in `paymentEffects` dated in the month by `today` leave after the levies they added
    ///   (`ReceiptEffect.netHalere`).
    ///
    /// The estimate is what `prediction` and `expectedPayments` hold for the month, and the invoices of `rows` that are
    /// dated after `issuedThrough` and paid by `today`:
    /// - issued: the invoices still to be issued in `year`. They are the invoices expected from a draft or from a
    ///   client's rhythm; the invoices dated after `issuedThrough` that are not paid by "now", at the prediction's own
    ///   amount for each; and the invoices dated after `issuedThrough` whose payment is dated by `today`, each worth
    ///   what the chart of Příjmy counts for a paid invoice, its payment's amount. The prediction does not list a paid
    ///   invoice, as it waits for nothing, and the actual figures stop at `issuedThrough`, so such an invoice would be
    ///   in neither part. An invoice issued by `issuedThrough` is among the actual figures already, also when it is
    ///   not paid, and so it is not counted again here;
    /// - received and net: the payments expected in the month (`PredictionOutcome.expectedPayments()`), each with its
    ///   amount and what it leaves after the levies it adds, from today on. The payment of an invoice that is dated
    ///   after `issuedThrough` and paid by `today` is among the actual figures of the month it was received in, so it
    ///   adds nothing here; an invoice issued by `issuedThrough` and not paid keeps its payment in the expected ones.
    static func months(
        year: Int, today: CivilDate, issuedThrough: CivilDate? = nil, rows: [InvoiceChartRow],
        paymentEffects: [ReceiptEffect], prediction: IncomePrediction, expectedPayments: [ExpectedPayment]
    ) -> [PredictionChartMonth] {
        let cut = max(issuedThrough ?? today, today)
        let actualByMonth = actualSums(
            year: year, today: today, cut: cut, rows: rows, paymentEffects: paymentEffects)
        let estimateByMonth = estimateSums(
            year: year, today: today, cut: cut, rows: rows, prediction: prediction, expectedPayments: expectedPayments)
        return (1...12).map { month in
            let part = partOfMonth(month, today: today)
            let actual = part == .future ? nil : actualByMonth[month - 1]
            let estimate = part == .past ? nil : estimateByMonth[month - 1]
            let approximate = actual?.issuedIsApproximate ?? false
            return PredictionChartMonth(
                month: month, label: CzechFormat.monthShort[month - 1],
                title: title(ofMonth: month, part: part, year: year, today: today), part: part,
                issuedActualHalere: actual?.issued ?? 0, issuedEstimateHalere: estimate?.issued ?? 0,
                receivedActualHalere: actual?.received ?? 0, receivedEstimateHalere: estimate?.received ?? 0,
                netActualHalere: actual?.net ?? 0, netEstimateHalere: estimate?.net ?? 0,
                issuedActualText: text(actual?.issued),
                issuedEstimateText: text(estimate?.issued),
                receivedActualText: text(actual?.received), receivedEstimateText: text(estimate?.received),
                netActualText: text(actual?.net), netEstimateText: text(estimate?.net),
                issuedActualIsApproximate: approximate,
                notes: notes(part: part, today: today, cut: cut, approximate: approximate))
        }
    }

    /// The largest amount the chart has to hold, in haléře: the largest of the sums of the months, each the actual part
    /// and the estimate together, for what was issued, what was received and the net income. The net income is drawn
    /// from zero like the axis, so one below zero counts as 0 and does not make the chart taller. The scale of the
    /// chart is `IncomeChartLayout.top(forLargest:)` of it. A chart without months holds nothing, 0.
    static func largestAmount(in months: [PredictionChartMonth]) -> Int64 {
        months.map { month in
            max(
                month.issuedActualHalere + month.issuedEstimateHalere,
                month.receivedActualHalere + month.receivedEstimateHalere,
                max(0, month.netActualHalere + month.netEstimateHalere))
        }.max() ?? 0
    }

    // MARK: The parts

    /// Where `month` stands against `today`: before its month, in it, or after it.
    private static func partOfMonth(_ month: Int, today: CivilDate) -> PredictionChartMonth.Part {
        if month < today.month {
            .past
        } else if month == today.month {
            .current
        } else {
            .future
        }
    }

    /// The actual sums of each month of `year`, January first, as `months` defines them: what was issued by `cut`, and
    /// what was received by `today`. Nothing after them counts, so a month after the one of `today` has none.
    private static func actualSums(
        year: Int, today: CivilDate, cut: CivilDate, rows: [InvoiceChartRow], paymentEffects: [ReceiptEffect]
    ) -> [Sums] {
        var sums = [Sums](repeating: Sums(), count: 12)
        for row in rows where !row.isDraft && !row.inReview {
            let issueDay = row.issueDate
            if issueDay.year == year, issueDay <= cut {
                let value = OverviewBuilder.issuedValue(of: row, receivedThrough: today)
                sums[issueDay.month - 1].issued += value.net
                sums[issueDay.month - 1].issuedIsApproximate =
                    sums[issueDay.month - 1].issuedIsApproximate || value.isApproximate
            }
            if let day = row.paymentDate, day.year == year, day <= today, let net = row.paymentNetHalere {
                sums[day.month - 1].received += net
            }
        }
        for effect in paymentEffects {
            let day = effect.receipt.day
            if day.year == year, day <= today {
                sums[day.month - 1].net += effect.netHalere
            }
        }
        return sums
    }

    /// The estimated sums of each month of `year`, January first, as `months` defines them: the invoices still to be
    /// issued by the month they are issued in, the payments expected by the month they come in. The invoices still to
    /// be issued are those the prediction expects from a draft or from a client's rhythm, those dated after `cut` that
    /// are not paid by "now", at the prediction's amount, and those in `rows` that are dated after `cut` and paid by
    /// `today` (`isDatedAfterCutAndPaid`), at their payment's amount. The payment of the last is among the actual
    /// figures already, so it adds no payment expected here. An invoice dated by `cut` is among the actual issued
    /// figures, so it is not counted here whatever the prediction lists.
    private static func estimateSums(
        year: Int, today: CivilDate, cut: CivilDate, rows: [InvoiceChartRow], prediction: IncomePrediction,
        expectedPayments: [ExpectedPayment]
    ) -> [Sums] {
        var sums = [Sums](repeating: Sums(), count: 12)
        for invoice in prediction.expectedInvoices where isStillToBeIssued(invoice, cut: cut) {
            if invoice.issueDate.year == year {
                sums[invoice.issueDate.month - 1].issued += invoice.amountHalere
            }
        }
        for row in rows where isDatedAfterCutAndPaid(row, year: year, today: today, cut: cut) {
            sums[row.issueDate.month - 1].issued += OverviewBuilder.issuedValue(of: row, receivedThrough: today).net
        }
        for payment in expectedPayments where payment.day.year == year {
            sums[payment.day.month - 1].received += payment.amountHalere
            sums[payment.day.month - 1].net += payment.netHalere
        }
        return sums
    }

    /// Whether the prediction expects `invoice` to be issued after `cut`, the end of the reporting cutoff. An invoice
    /// expected from a draft or from a client's rhythm is issued on its day, "now" at the earliest. An unpaid invoice
    /// is issued already, unless its own issue date is after `cut`; one issued by `cut` is among the actual figures.
    private static func isStillToBeIssued(_ invoice: PredictedInvoice, cut: CivilDate) -> Bool {
        switch invoice.kind {
        case .draft, .expected: true
        case .waiting: invoice.issueDate > cut
        }
    }

    /// Whether `row` is an invoice of `year` that is dated after `cut` and whose payment is dated on or before
    /// `today`. Its money has come, so the prediction does not list it among the invoices it expects to be paid, and it
    /// is dated after `cut`, so the actual figures leave it out: it is still to be issued, and its row is what puts it
    /// in the estimate. A draft and an invoice in review are not issued invoices, as for the actual figures. An unpaid
    /// invoice, or one whose payment is dated after `today`, is not one of these: the prediction expects its payment,
    /// lists it, and counts it.
    private static func isDatedAfterCutAndPaid(
        _ row: InvoiceChartRow, year: Int, today: CivilDate, cut: CivilDate
    ) -> Bool {
        guard !row.isDraft, !row.inReview, row.issueDate.year == year, row.issueDate > cut,
            let paymentDate = row.paymentDate
        else {
            return false
        }
        return paymentDate <= today
    }

    // MARK: The texts

    /// What the tooltip calls `month`: its name and `year`; for the current month also the day the actual figures are
    /// up to, and for a future month that it is an estimate.
    private static func title(
        ofMonth month: Int, part: PredictionChartMonth.Part, year: Int, today: CivilDate
    ) -> String {
        let name = BuilderText.capitalized(CzechFormat.monthNames[month - 1]) + " \(year)"
        switch part {
        case .past: return name
        case .current: return name + " · do " + CzechFormat.dayMonth(today) + " skutečnost, dál odhad"
        case .future: return name + " · odhad"
        }
    }

    /// `halere` in whole Kč, rounded half up, or "—" for a part that does not apply, which has no amount.
    private static func text(_ halere: Int64?) -> String {
        halere.map { PredictionBuilder.kc(ofHalere: $0) } ?? notApplicable
    }

    /// The sentences under the figures of a month. The current month says that the invoices issued are of the whole
    /// month, to its end, while the money received and the net income stop at today, when the cutoff is after today;
    /// a month whose issued amount is approximate says why (`ChartColumn.approximateIssuedNote`).
    private static func notes(
        part: PredictionChartMonth.Part, today: CivilDate, cut: CivilDate, approximate: Bool
    ) -> [String] {
        var notes: [String] = []
        if part == .current, cut > today {
            // `dayMonth` ends with the full stop of the day: "17. 10."
            notes.append(
                "Vystaveno: faktury za celý měsíc. Přijato a čistý příjem: jen do " + CzechFormat.dayMonth(today))
        }
        if approximate {
            notes.append(ChartColumn.approximateIssuedNote)
        }
        return notes
    }
}
