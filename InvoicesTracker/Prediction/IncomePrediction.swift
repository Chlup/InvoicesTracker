import Foundation

/// What one month of a client's year holds for the prediction.
nonisolated enum PredictionMonthKind: Sendable, Hashable {
    /// The month has issued invoices, all of them paid by "now".
    case paid

    /// The month has issued invoices not all paid by "now", and of those not paid at least one is expected to be paid
    /// by 31 December.
    case waiting

    /// The month has issued invoices not all paid by "now", and every one not paid is expected to be paid only after
    /// 31 December.
    case waitingNextYear

    /// The month has no issued invoice and is over, or the whole year is.
    case past

    /// An invoice is expected in the month and paid by 31 December: its money counts in the year.
    case expected

    /// An invoice is expected in the month but paid only after 31 December: its money is the next year's.
    case expectedNextYear

    /// No invoice is expected in the month.
    case notExpected
}

/// One month of a client's year.
nonisolated struct PredictionMonth: Sendable, Hashable {
    /// 1 to 12.
    var month: Int

    var kind: PredictionMonthKind

    /// In haléře. For a month of issued invoices, what they bring: the payments of those paid by "now" and the
    /// converted amounts of the others, those whose amount is known. For an expected month the converted estimate, 0
    /// when it is unknown. Otherwise 0.
    var amountHalere: Int64

    /// Whether an unpaid invoice, enabled forecast or draft component has an unavailable amount. A mixed draft
    /// month retains its known subtotal in `amountHalere`.
    var hasUnknownAmount: Bool

    /// The numbers of the month's issued invoices, or for an open month those of its drafts, in the order of issue.
    var invoiceNumbers: [String]

    /// Whether an open month has drafts. An invoice expected in it takes their day and their amount.
    var isFromDraft: Bool

    /// For an open month (expected, expected next year or not expected), whether an invoice is expected in it: the
    /// person's choice where there is one, otherwise the app's own. False for any other month.
    var isOn: Bool

    /// For an open month, the app's own choice: the month has a draft, or it is a month of a regular client's rhythm.
    /// False for any other month, and for every month of the invoices of no client the app knows.
    var isAutomatic: Bool
}

/// One client's year: how it invoices and pays, its twelve months and the money it brings.
nonisolated struct ClientPrediction: Identifiable, Sendable, Hashable {
    /// The id of the group of the invoices of no client the app knows.
    static let unknownID: Int64 = -1

    /// The name of that group.
    static let unknownName = "Neznámý odběratel"

    /// The client's id, or `unknownID`.
    var id: Int64
    var name: String

    /// The currency of the next invoice: the last issued invoice's, otherwise the client's.
    var currency: CurrencyCode

    /// The issued invoices known at "now", of every year.
    var issuedCount: Int

    /// The issue date of the last of them.
    var lastIssued: CivilDate?

    /// Whether the client's next invoices are expected from its rhythm.
    var isRegular: Bool

    /// The rhythm in months, at least 1.
    var step: Int

    /// The usual days from the issue of an invoice to its payment.
    var delayDays: Int

    /// The annual arithmetic mean in haléře, or the empty-history template fallback; nil when unavailable.
    var nextAmountHalere: Int64?

    /// The number of qualifying real invoices, including those whose daily conversion is missing.
    var averageSampleCount: Int

    /// Whether `nextAmountHalere` comes from the client's first positive template.
    var nextAmountFromTemplate: Bool

    /// The twelve months, January first.
    var months: [PredictionMonth]

    /// The payments of the client's invoices received in the year by "now", in haléře.
    var receivedHalere: Int64

    /// The unpaid invoices of the year before that are expected to be paid in the year, in haléře.
    var previousYearWaitingHalere: Int64

    /// The invoices expected in the months of the year and paid by 31 December, in haléře.
    var expectedHalere: Int64

    /// What the client still brings in the year, in haléře: its unpaid invoices of the year and of the year before that
    /// are expected to be paid by 31 December, and its expected invoices.
    var addsHalere: Int64

    /// What the client's unpaid and expected invoices bring only after 31 December, in haléře.
    var nextYearHalere: Int64

    /// Whether any enabled contribution paid in the selected year has an unavailable amount, including an invoice
    /// issued in the preceding year that has no month cell in this year.
    var hasUnknownCurrentYearAmount: Bool

    /// Whether any enabled contribution paid only next year has an unavailable amount.
    var hasUnknownNextYearAmount: Bool

    /// Whether the client has an issued invoice in the year.
    var hasInvoiceInYear: Bool

    /// Whether the person changed any month of the client's year.
    var isEdited: Bool

    /// Whether the client is among those the page lists first. In a closed year, when it brought money or has an
    /// invoice in the year. Otherwise when a month is on, it still brings money, or its last invoice is at most 92 days
    /// old.
    var isActive: Bool
}

/// An invoice the prediction expects to be paid: an issued invoice not paid by "now", or one expected in a month that
/// is on, from a draft or from the client's rhythm.
nonisolated struct PredictedInvoice: Sendable, Hashable {
    /// Where the invoice comes from.
    nonisolated enum Kind: Sendable, Hashable {
        /// An issued invoice of the year or of the year before that is not paid by "now".
        case waiting

        /// The invoice of a month that is on and has drafts: it takes the day of the earliest draft and what the
        /// drafts bring.
        case draft

        /// The invoice of a month that is on and has no draft: it takes the client's usual day of the month and its
        /// next amount.
        case expected
    }

    var kind: Kind

    /// The day the invoice is issued: for a waiting invoice its own issue date, also when that is after "now"; for any
    /// other the day of the month's earliest draft or else the client's usual day of the month, "now" at the earliest.
    /// The delay to the payment is counted from it.
    var issueDate: CivilDate

    /// The day the invoice is expected to be paid.
    var payDay: CivilDate

    /// What the invoice is known to bring without VAT, in haléře. An incomplete mixed-draft month keeps its known
    /// subtotal; a wholly unavailable amount is 0 and is distinguished by `hasUnknownAmount`.
    var amountHalere: Int64

    /// Whether the invoice is paid by 31 December, so that its money counts in the year.
    var isCounted: Bool

    /// Whether the invoice’s amount is unavailable rather than a known zero.
    var hasUnknownAmount: Bool = false
}

/// A year's whole income predicted client by client as of "now": the money received, the issued invoices still to be
/// paid, the invoices expected from drafts and from the clients' rhythms, and what of them is paid only in the next
/// year. Amounts are in haléře.
nonisolated struct IncomePrediction: Sendable, Hashable {
    var year: Int

    /// The day the prediction is made as of: today in the current year, otherwise 31 December of the year.
    var now: CivilDate

    /// Whether "now" is the year's last day, so that nothing is expected any more.
    var isClosed: Bool

    /// The clients, the active ones first, and each part by what the client brings in the year, still to come and
    /// received, the most first. Clients that bring as much keep the order of the input. The invoices of no client the
    /// app knows sort as a client does, after the clients that bring as much.
    var clients: [ClientPrediction]

    /// The year's receipts dated by "now": payments and income adjustments.
    var receivedHalere: Int64

    /// The payments among them; income adjustments are not counted.
    var receivedCount: Int

    /// Whether an income adjustment is among them.
    var includesAdjustments: Bool

    /// The unpaid issued invoices of the year and of the year before that are expected to be paid by 31 December, those
    /// whose amount is known.
    var waitingHalere: Int64
    var waitingCount: Int

    /// The invoices expected in the months of the year and paid by 31 December.
    var expectedHalere: Int64
    var expectedCount: Int

    /// What the unpaid and the expected invoices bring only after 31 December: the next year's income.
    var nextYearHalere: Int64

    /// Copied from the input, for the page to name the rates.
    var usesUniformRate: Bool
    var rateDay: CivilDate?

    /// The invoices the prediction expects to be paid, those counted in the year and those paid only after 31 December:
    /// each unpaid invoice and an invoice for each month that is on, carrying any unknown-amount metadata. They are
    /// in order of the day they are paid, and the invoices paid on one day in the order of the clients.
    var expectedInvoices: [PredictedInvoice]

    /// For the engine: each counted invoice’s known amount, including a mixed draft month’s known subtotal. Wholly
    /// unknown amounts are excluded, while known zeros remain. These receipts never establish completeness.
    var syntheticReceipts: [Receipt] {
        expectedInvoices.filter { $0.isCounted && (!$0.hasUnknownAmount || $0.amountHalere != 0) }.map { invoice in
            Receipt(day: invoice.payDay, czkNetHalere: invoice.amountHalere, czkVatHalere: 0, source: .synthetic)
        }
    }

    /// Whether every enabled contribution counted in this year has a known amount.
    var isComplete: Bool {
        !expectedInvoices.contains { $0.isCounted && $0.payDay.year == year && $0.hasUnknownAmount }
    }

    /// Whether any client's next-year contribution has an unavailable amount.
    var hasUnknownNextYearAmount: Bool {
        clients.contains(where: \.hasUnknownNextYearAmount)
    }

    /// The year's whole income: received, waiting and expected.
    var incomeHalere: Int64 {
        receivedHalere + waitingHalere + expectedHalere
    }
}

// MARK: - Making the prediction

nonisolated extension IncomePrediction {
    /// The daily keys required by the same annual samples used to make each client's arithmetic mean.
    static func averageRateKeys(in input: PredictionInput) -> Set<PredictionRateKey> {
        let year = PredictionYear(input)
        return Set(ClientGroup.groups(of: input, in: year).flatMap { group in
            let rhythm = group.rhythm(year: year)
            return group.samples(year: year, delayDays: rhythm.delayDays).compactMap(\.rateKey)
        })
    }

    /// The prediction of `input.year` as of "now". Each client's rhythm (`ClientRhythm`) comes from its issued
    /// invoices known at "now", never from drafts. Then:
    /// - The money received is the year's receipts dated by "now".
    /// - An issued invoice of the year or of the year before (never older) that is not paid by "now" is expected to be
    ///   paid after the client's usual delay, tomorrow at the earliest. It counts in the year when that day is in it.
    ///   It brings its amount converted at the rate of its currency, or without one at the rate the invoice keeps;
    ///   with neither, its amount is unknown and it brings nothing.
    /// - A month with issued invoices shows them. Any other month is past when it is over or the year is closed: the
    ///   current month stays open through its last day.
    /// - In an open month an invoice is expected when the person chose so, or else by the app's own choice, which the
    ///   invoices of no client the app knows never have. It is issued on the day of the month's earliest draft, or
    ///   else on the client's usual day of the month, today at the earliest, and paid after the client's usual delay.
    ///   It brings the month's drafts, each currency converted once, or else the client's annual CZK mean. With no
    ///   qualifying history only drafts enable automatic months, and a manual month may use the first template.
    /// - The invoices expected (`expectedInvoices`) are the unpaid ones and the one of each month
    ///   that is on, counted in the year or not, by the day they are paid.
    static func make(_ input: PredictionInput) -> IncomePrediction {
        let year = PredictionYear(input)
        let clients = ClientGroup.groups(of: input, in: year).map { PredictedClient(of: $0, input: input, year: year) }
        let ordered = Self.ordered(clients)
        let received = input.receipts.filter { $0.day.year == input.year && $0.day <= year.now }
        let invoices = ordered.flatMap(\.invoices).enumerated()
            .sorted { ($0.element.payDay, $0.offset) < ($1.element.payDay, $1.offset) }
            .map(\.element)
        return IncomePrediction(
            year: input.year, now: year.now, isClosed: year.isClosed, clients: ordered.map(\.prediction),
            receivedHalere: received.reduce(0) { $0 + $1.czkNetHalere },
            receivedCount: received.filter { !Self.isAdjustment($0) }.count,
            includesAdjustments: received.contains(where: Self.isAdjustment),
            waitingHalere: clients.reduce(0) { $0 + $1.waitingHalere },
            waitingCount: clients.reduce(0) { $0 + $1.waitingCount },
            expectedHalere: clients.reduce(0) { $0 + $1.prediction.expectedHalere },
            expectedCount: clients.reduce(0) { $0 + $1.expectedCount },
            nextYearHalere: clients.reduce(0) { $0 + $1.prediction.nextYearHalere },
            usesUniformRate: input.usesUniformRate, rateDay: input.rateDay, expectedInvoices: invoices)
    }

    /// `clients`, the active ones first, and each part by what the client brings in the year, the most first. Clients
    /// that bring as much keep their order.
    private static func ordered(_ clients: [PredictedClient]) -> [PredictedClient] {
        clients.enumerated()
            .sorted { lhs, rhs in
                let left = lhs.element.prediction
                let right = rhs.element.prediction
                if left.isActive != right.isActive {
                    return left.isActive
                }
                let leftBrings = left.addsHalere + left.receivedHalere
                let rightBrings = right.addsHalere + right.receivedHalere
                if leftBrings != rightBrings {
                    return leftBrings > rightBrings
                }
                return lhs.offset < rhs.offset
            }
            .map(\.element)
    }

    private static func isAdjustment(_ receipt: Receipt) -> Bool {
        if case .adjustment = receipt.source {
            return true
        }
        return false
    }
}

/// The year being predicted, as of "now".
private nonisolated struct PredictionYear {
    var year: Int
    var now: CivilDate

    /// 31 December of the year.
    var end: CivilDate

    /// Whether the year is the year of today: the only one whose drafts count.
    var isCurrent: Bool

    /// Whether nothing is expected in the year any more (`PredictionInput.isClosed(year:today:)`).
    var isClosed: Bool

    init(_ input: PredictionInput) {
        year = input.year
        now = PredictionInput.now(year: input.year, today: input.today)
        end = PredictionInput.lastDay(of: input.year)
        isCurrent = input.year == input.today.year
        isClosed = PredictionInput.isClosed(year: input.year, today: input.today)
    }

    /// Whether `invoice` is an issued invoice known at "now": in the current year every one, also those dated after
    /// today, and in another year those issued by its end.
    func isKnown(_ invoice: Invoice) -> Bool {
        invoice.status == .issued && (isCurrent || invoice.issueDate <= end)
    }

    /// Whether `invoice` is a draft of the year that counts: only in the current year.
    func isCountedDraft(_ invoice: Invoice) -> Bool {
        invoice.status == .draft && isCurrent && invoice.issueDate.year == year
    }

    /// Whether `invoice` is paid by "now".
    func isPaid(_ invoice: Invoice) -> Bool {
        invoice.payment.map { $0.date <= now } ?? false
    }

    /// What the payment of `invoice` brings in the year by "now", in haléře: 0 unless it is an issued invoice paid in
    /// the year by "now".
    func received(_ invoice: Invoice) -> Int64 {
        guard invoice.status == .issued, let payment = invoice.payment, payment.date.year == year, payment.date <= now
        else {
            return 0
        }
        return payment.czkNetHalere
    }
}

/// A client with its invoices. The invoices of no client the app knows make a group of their own.
private nonisolated struct ClientGroup {
    var id: Int64
    var name: String

    /// Nil for the invoices of no client the app knows.
    var client: Client?
    var invoices: [Invoice]

    /// Cadence uses the invoices known at the prediction cutoff, independently of annual amount eligibility.
    func rhythm(year: PredictionYear) -> ClientRhythm {
        ClientRhythm(
            issued: invoices.filter(year.isKnown), now: year.now, dueDays: client?.dueDays)
    }

    /// Annual samples include a payment in the selected year even when its invoice was issued in a later year.
    func samples(year: PredictionYear, delayDays: Int) -> [PredictionAverageSample] {
        PredictionAverage.samples(issued: invoices, year: year.year, now: year.now, delayDays: delayDays)
    }

    /// The groups of `input`: one for each client, in their order, and after them one for the invoices of no client
    /// the app knows, when any of them counts in `year`. Invoices in review are left out: they are not income until
    /// they are resolved.
    static func groups(of input: PredictionInput, in year: PredictionYear) -> [ClientGroup] {
        let clientIDs = Set(input.clients.map(\.id))
        var invoicesByClient: [Int64: [Invoice]] = [:]
        for invoice in input.invoices where invoice.review == nil {
            let id = invoice.clientID.flatMap { clientIDs.contains($0) ? $0 : nil } ?? ClientPrediction.unknownID
            invoicesByClient[id, default: []].append(invoice)
        }
        var groups = input.clients.map { client in
            ClientGroup(id: client.id, name: client.name, client: client, invoices: invoicesByClient[client.id] ?? [])
        }
        let unknown = invoicesByClient[ClientPrediction.unknownID] ?? []
        let counts = unknown.contains { invoice in
            year.isKnown(invoice) || year.isCountedDraft(invoice) || year.received(invoice) != 0
        }
        if counts {
            groups.append(
                ClientGroup(
                    id: ClientPrediction.unknownID, name: ClientPrediction.unknownName, client: nil, invoices: unknown))
        }
        return groups
    }
}

/// An issued invoice not paid by "now": the day it is expected to be paid and what it brings.
private nonisolated struct WaitingInvoice {
    var invoice: Invoice

    /// The issue date and the client's usual delay, tomorrow at the earliest.
    var payDay: CivilDate

    /// The invoice's amount without VAT, converted at the rate of its currency, or without one at the rate the invoice
    /// keeps; nil when it is unknown, with neither.
    var amountHalere: Int64?

    /// Whether it is paid by 31 December, so that it counts in the year.
    var isCounted: Bool

    init(_ invoice: Invoice, delayDays: Int, input: PredictionInput, year: PredictionYear) {
        let usualDay = invoice.issueDate.adding(days: delayDays)
        self.invoice = invoice
        payDay = usualDay > year.now ? usualDay : year.now.adding(days: 1)
        if invoice.currency.isCZK || input.rates[invoice.currency] != nil {
            amountHalere = input.czkHalere(fromMinor: invoice.netMinor, in: invoice.currency)
        } else if let kept = invoice.invoiceRate?.rate, kept.currency == invoice.currency {
            amountHalere = kept.czkHalere(fromMinor: invoice.netMinor)
        } else {
            amountHalere = nil
        }
        isCounted = payDay <= year.end
    }
}

/// A client's year as the prediction makes it, with what it adds to the totals.
private nonisolated struct PredictedClient {
    var prediction: ClientPrediction

    /// The client's unpaid invoices, in the order of issue, and then one invoice for each of its
    /// months that is on, in the order of the months: those counted in the year and those paid only after 31 December.
    var invoices: [PredictedInvoice]

    /// The client's unpaid invoices of the year and of the year before counted in the year, those whose amount is
    /// known.
    var waitingHalere: Int64
    var waitingCount: Int

    /// The client's months expected and counted in the year.
    var expectedCount: Int

    init(of group: ClientGroup, input: PredictionInput, year: PredictionYear) {
        let known = group.invoices.filter(year.isKnown).sorted(by: ClientRhythm.issuedEarlier)
        let drafts = group.invoices.filter(year.isCountedDraft).sorted(by: ClientRhythm.issuedEarlier)
        let template = group.client.flatMap { client in input.templates.first { $0.clientID == client.id } }
        let rhythm = group.rhythm(year: year)
        let average = PredictionAverage.make(
            samples: group.samples(year: year, delayDays: rhythm.delayDays), rates: input.averageRates)
        let templateTotal = template?.items.reduce(Int64(0)) { total, item in
            total + InvoiceMath.itemAmount(quantity: item.quantity, unitPriceMinor: item.unitPriceMinor)
        } ?? 0
        let fromTemplate = average.sampleCount == 0 && templateTotal > 0
        let templateCurrency = group.client?.currency ?? .czk
        let templateAmount: Int64? = templateCurrency.isCZK || input.rates[templateCurrency] != nil
            ? input.czkHalere(fromMinor: templateTotal, in: templateCurrency) : nil
        let nextAmount = fromTemplate ? templateAmount : average.amountHalere
        let waiting = known
            .filter { (year.year - 1...year.year).contains($0.issueDate.year) && !year.isPaid($0) }
            .map { WaitingInvoice($0, delayDays: rhythm.delayDays, input: input, year: year) }

        var invoices: [PredictedInvoice] = []
        var waitingHalere: Int64 = 0
        var waitingCount = 0
        var previousYearHalere: Int64 = 0
        var nextYearHalere: Int64 = 0
        for item in waiting {
            let amount = item.amountHalere ?? 0
            invoices.append(
                PredictedInvoice(
                    kind: .waiting, issueDate: item.invoice.issueDate, payDay: item.payDay, amountHalere: amount,
                    isCounted: item.isCounted, hasUnknownAmount: item.amountHalere == nil))
            if item.isCounted {
                waitingHalere += amount
                if item.amountHalere != nil { waitingCount += 1 }
                if item.invoice.issueDate.year < year.year {
                    previousYearHalere += amount
                }
            } else {
                nextYearHalere += amount
            }
        }

        let changes = input.changes[group.id] ?? [:]
        // The invoices of no client the app knows expect no month of the app's own accord: a choice is stored for a
        // client of the app, so nothing could take such a month back.
        let automatic =
            group.id == ClientPrediction.unknownID
            ? []
            : (average.sampleCount > 0
                ? rhythm.automaticMonths(in: year.year, draftMonths: Set(drafts.map(\.issueDate.month)))
                : Set(drafts.map(\.issueDate.month)))
        var months: [PredictionMonth] = []
        var expectedHalere: Int64 = 0
        var expectedCount = 0
        for month in 1...12 {
            let issued = known.filter { $0.issueDate.year == year.year && $0.issueDate.month == month }
            if !issued.isEmpty {
                months.append(Self.issuedMonth(month, issued, delayDays: rhythm.delayDays, input: input, year: year))
                continue
            }
            if month < year.now.month || year.isClosed {
                months.append(
                    PredictionMonth(
                        month: month, kind: .past, amountHalere: 0, hasUnknownAmount: false, invoiceNumbers: [],
                        isFromDraft: false, isOn: false, isAutomatic: false))
                continue
            }
            let monthDrafts = drafts.filter { $0.issueDate.month == month }
            let isAutomatic = automatic.contains(month)
            let isOn = changes[month] ?? isAutomatic
            var kind = PredictionMonthKind.notExpected
            var amount: Int64 = 0
            var hasUnknownAmount = false
            if isOn {
                let usualDay = monthDrafts.first?.issueDate ?? rhythm.usualIssueDate(month: month, year: year.year)
                let issueDate = max(usualDay, year.now)
                let payDay = issueDate.adding(days: rhythm.delayDays)
                if monthDrafts.isEmpty {
                    amount = nextAmount ?? 0
                    hasUnknownAmount = nextAmount == nil
                } else {
                    amount = Self.amount(of: monthDrafts, input: input)
                    hasUnknownAmount = monthDrafts.contains {
                        !$0.currency.isCZK && input.rates[$0.currency] == nil
                    }
                }
                let isCounted = payDay <= year.end
                invoices.append(
                    PredictedInvoice(
                        kind: monthDrafts.isEmpty ? .expected : .draft, issueDate: issueDate, payDay: payDay,
                        amountHalere: amount, isCounted: isCounted, hasUnknownAmount: hasUnknownAmount))
                if isCounted {
                    kind = .expected
                    expectedHalere += amount
                    expectedCount += 1
                } else {
                    kind = .expectedNextYear
                    nextYearHalere += amount
                }
            }
            months.append(
                PredictionMonth(
                    month: month, kind: kind, amountHalere: amount, hasUnknownAmount: hasUnknownAmount,
                    invoiceNumbers: monthDrafts.map(\.number), isFromDraft: !monthDrafts.isEmpty, isOn: isOn,
                    isAutomatic: isAutomatic))
        }

        let received = group.invoices.reduce(0) { $0 + year.received($1) }
        let adds = waitingHalere + expectedHalere
        let hasInvoiceInYear = known.contains { $0.issueDate.year == year.year }
        let isActive: Bool
        if year.isClosed {
            isActive = received > 0 || hasInvoiceInYear
        } else {
            let isRecent = rhythm.lastIssued.map { year.now.days(since: $0) <= 92 } ?? false
            isActive = months.contains(where: \.isOn) || adds > 0 || isRecent
        }
        prediction = ClientPrediction(
            id: group.id, name: group.name, currency: known.last?.currency ?? templateCurrency,
            issuedCount: known.count,
            lastIssued: rhythm.lastIssued, isRegular: rhythm.isRegular, step: rhythm.step, delayDays: rhythm.delayDays,
            nextAmountHalere: nextAmount, averageSampleCount: average.sampleCount,
            nextAmountFromTemplate: fromTemplate,
            months: months, receivedHalere: received, previousYearWaitingHalere: previousYearHalere,
            expectedHalere: expectedHalere, addsHalere: adds, nextYearHalere: nextYearHalere,
            hasUnknownCurrentYearAmount: invoices.contains {
                $0.isCounted && $0.payDay.year == year.year && $0.hasUnknownAmount
            },
            hasUnknownNextYearAmount: invoices.contains { !$0.isCounted && $0.hasUnknownAmount },
            hasInvoiceInYear: hasInvoiceInYear, isEdited: !changes.isEmpty, isActive: isActive)
        self.invoices = invoices
        self.waitingHalere = waitingHalere
        self.waitingCount = waitingCount
        self.expectedCount = expectedCount
    }

    /// The month of `issued`, the issued invoices of `month`: paid when every one is paid by "now", otherwise waiting,
    /// or waiting for the next year when each one not paid is expected to be paid only after 31 December. It brings
    /// the payments and the amounts of the others that are known.
    private static func issuedMonth(
        _ month: Int, _ issued: [Invoice], delayDays: Int, input: PredictionInput, year: PredictionYear
    ) -> PredictionMonth {
        let unpaid = issued.filter { !year.isPaid($0) }
            .map { WaitingInvoice($0, delayDays: delayDays, input: input, year: year) }
        let paidHalere = issued.filter(year.isPaid).reduce(0) { $0 + ($1.payment?.czkNetHalere ?? 0) }
        let kind: PredictionMonthKind =
            if unpaid.isEmpty {
                .paid
            } else if unpaid.contains(where: \.isCounted) {
                .waiting
            } else {
                .waitingNextYear
            }
        return PredictionMonth(
            month: month, kind: kind, amountHalere: paidHalere + unpaid.reduce(0) { $0 + ($1.amountHalere ?? 0) },
            hasUnknownAmount: unpaid.contains { $0.amountHalere == nil }, invoiceNumbers: issued.map(\.number),
            isFromDraft: false, isOn: false, isAutomatic: false)
    }

    /// What `drafts` bring, in haléře: the drafts of each currency together, converted once.
    private static func amount(of drafts: [Invoice], input: PredictionInput) -> Int64 {
        Dictionary(grouping: drafts, by: \.currency).reduce(0) { total, entry in
            total + input.czkHalere(fromMinor: entry.value.reduce(0) { $0 + $1.netMinor }, in: entry.key)
        }
    }
}
