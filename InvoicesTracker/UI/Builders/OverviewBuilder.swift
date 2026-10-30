import Foundation

// MARK: - Input

/// Everything Přehled needs, already loaded: the computed year, the advance plan, the newest receipts with what they
/// add to the levies, what every payment of an invoice of the year adds to them, the invoices of the chart, the facts
/// about VAT and the uniform rate, and the estimate of the whole year with the payments it expects and what each of
/// them adds to the levies.
nonisolated struct OverviewInput: Sendable {
    var year: Int

    /// The reporting cutoff the screen is shown as of: the invoices issued up to this day are in the chart. For the
    /// current year it is the last day of the current month, so it can be after today.
    var asOf: CivilDate

    /// Today. It decides whether the year is over, and where the years chart of a year that is over is cut, and the
    /// money counts as received up to it (`receivedThrough`).
    var today: CivilDate

    /// The levies of `year` as of `asOf`.
    var result: TaxResult

    /// The advance plan of `year`, which the upcoming payments are listed from.
    var advances: AdvancePlan

    /// The invoices with a payment that adds to the levies, with what each adds. The builder keeps the newest five of
    /// the year up to `asOf`.
    var latestReceipts: [(invoice: Invoice, effect: ReceiptEffect)]
    var chartMode: ChartMode

    /// Whether the chart is drawn with VAT. Both series are in the columns either way.
    var chartWithVAT: Bool

    /// The invoices of the chart: those issued in the years shown, and those issued outside them that have a payment
    /// in them. The chart of the estimate card counts the months of `year` up to today from them as well.
    var chartRows: [InvoiceChartRow]

    /// The years of the years chart, oldest first.
    var chartYears: [Int]

    /// The VAT of the invoices of each month of `year` in haléře, January first. The invoices to check are not in it.
    var vatByMonth: [Int64]

    /// The months (1 to 12) of `year` whose VAT leaves out an invoice to check: one that is not a draft, has VAT and
    /// its DUZP in the month.
    var vatToCheckMonths: Set<Int>

    /// The currencies other than crowns of the invoices that are not drafts and were issued in `year` or paid in it.
    var foreignCurrencies: [CurrencyCode]

    /// The uniform rates known for `year`.
    var uniformRates: [UniformRate]

    /// The years of `year` and `chartYears` that convert their income in other currencies at their uniform rate
    /// (`YearFXState.effective`); the others convert it at the ČNB rates of the days.
    var yearsAtUniformRate: Set<Int>

    /// The estimate of the whole of `year`, made from today's data whatever day "K datu" shows, or nil when there is
    /// none: the screen makes it only for the current year.
    var prediction: PredictionOutcome? = nil

    /// The levies of each year of the years chart as of the day its net income is counted to
    /// (`OverviewBuilder.netIncomeDay(ofYear:cut:)`), for the years chart only. A year that is not in it, because it
    /// has no such day yet or its levies could not be worked out, has no net income in the chart.
    var netIncomeResults: [Int: TaxResult] = [:]

    /// What each payment of an invoice received in `year` adds to the levies of the year on its own day
    /// (`TaxEngine.effect(of:in:)`), which the chart by months sums per month for its net income. It holds every such
    /// payment of the year, whatever the day shown: the chart cuts it at the day itself
    /// (`OverviewBuilder.chartCut(asOf:today:mode:)`), as it cuts its amounts, and the chart of the estimate card cuts
    /// it at today.
    var invoicePaymentEffects: [ReceiptEffect] = []

    /// The payments the estimate expects in `year`, in the order of their days, each with what it adds to the levies of
    /// the year on its own day (`PredictionOutcome.expectedPayments()`), which the chart of the estimate card sums per
    /// month for the received and net parts of its estimate. Empty where there is no estimate.
    var expectedPayments: [ExpectedPayment] = []

    /// How `year` converts its income in other currencies.
    var incomeFXMethod: IncomeFXMethod {
        yearsAtUniformRate.contains(year) ? .uniform : .cnbDaily
    }

    /// The day the money counts as received by: `asOf`, but never a day after today in the current year, as a payment
    /// dated later has not come yet even though the invoices issued until the end of the month are reported.
    var receivedThrough: CivilDate {
        asOf.year == today.year ? min(asOf, today) : asOf
    }
}

// MARK: - Output

/// The strip above the chart of the card "Příjmy": what the income of the year so far leaves after the tax and the
/// insurance, and the average of that per month, each with the words that say what the figure is. The figures are in
/// whole Kč.
nonisolated struct OverviewNetIncome: Sendable, Hashable {
    /// What the first figure is: "Čistý příjem za rok 2025" for a year shown as of its last day, otherwise "Čistý
    /// příjem od 1. 1. do 17. 10.".
    var yearLabel: String

    /// The net income of the year so far: "1 933 471 Kč", or "−12 345 Kč" where the levies are more than the income.
    var yearValue: String

    /// What the net income is a part of: "88,2 % příjmů bez DPH po dani a pojistném", or while the income is not above
    /// zero, as there is nothing to take a part of, "příjmy bez DPH po dani a pojistném".
    var yearSub: String

    /// What the second figure is: "Čistý příjem průměrně za měsíc".
    var monthLabel: String

    /// The net income over the months so far, per month: "193 347 Kč".
    var monthValue: String

    /// The months the average is over: "průměr za celý rok", "průměr za leden" or "průměr za leden–říjen".
    var monthSub: String
}

/// The average net income per month of a year as the footer of the tooltip of a column of the chart tells it: the words
/// that say which year and which months it is over, and the figure. When the engine worked the year out with the rules
/// of another year (`TaxResult.rulesAreEstimate`) the figure is an estimate: the sign "≈" stands before it, and the
/// sentence that says why goes with it, under the footer.
nonisolated struct ChartNetAverage: Sendable, Hashable {
    /// "Průměrný čistý příjem za měsíc v roce 2025" for a year counted as a whole, and for a year in progress the
    /// months the average is over after it, "Průměrný čistý příjem za měsíc v roce 2026 (leden–říjen)".
    var label: String

    /// The average in whole Kč: "199 441 Kč", and with the sign of an estimate in front of it, "≈ 199 441 Kč", for a
    /// year computed with the rules of another year.
    var value: String

    /// The sentence that the year is computed with the rules of another year (`RulesWarning.message(year:rulesYear:)`),
    /// which the tooltip shows under the footer and VoiceOver reads after the average, or nil for a year with rules of
    /// its own.
    var note: String? = nil
}

/// A column of the income chart: a month or a year, with what was issued (the bars) and what was received (the line),
/// each without and with VAT, in haléře. Where the levies of its year are known it also tells what is left of the
/// income after them (the green line). A month has the net income of the invoices paid in it, and the average per
/// month of the selected year; a year of the years chart that has been worked out has the net income of the year and
/// its average. Where the engine worked the year out with the rules of another year, the net income and the average
/// are marked as estimates, and a sentence says why.
nonisolated struct ChartColumn: Sendable, Hashable {
    /// "zář" or "2026".
    var label: String

    /// "Září 2026" or "Rok 2026".
    var title: String
    var issuedNetHalere: Int64
    var issuedGrossHalere: Int64
    var receivedNetHalere: Int64
    var receivedGrossHalere: Int64

    /// Whether an issued amount of the column is approximate: an invoice in a foreign currency, not paid, whose ČNB
    /// rate of the day of issue is not declared yet is worth what the latest declared rate makes of it. The tooltip
    /// and VoiceOver put "≈" before the issued amounts and say why (`approximateIssuedNote`).
    var issuedIsApproximate = false

    /// A month after the chosen day: its bar is drawn faded and the lines stop before it.
    var isFuture: Bool

    /// The month of the chosen day, or the selected year, which is written in bold.
    var isCurrent: Bool

    /// Whether the lines of what was received and of the net income have a point in this column.
    var hasLinePoint: Bool

    /// The net income of the column in haléře, always without VAT: the point of the green line. It is negative where
    /// the levies are more than the income.
    ///
    /// A month has what the invoices paid in it leave after the levies their payments added, each as of its own day
    /// (`ReceiptEffect.netHalere`), up to the day the chart is cut at: 0 for a month with no such payment, also for a
    /// month after the day shown, which has no point on the line. A column of the years chart has what the year leaves
    /// after the tax and the insurance (`NetIncome`) as of the day its levies were worked out, and only when the year
    /// has been worked out.
    var netIncomeHalere: Int64? = nil

    /// The average net income per month that the tooltip tells under its rows, or nil where the year is not known:
    /// every month has the average of the selected year, and a year of the years chart that has been worked out its
    /// own.
    var netAverage: ChartNetAverage? = nil

    /// The net income as the row of the tooltip and VoiceOver tell it: `netIncomeHalere` in crowns and haléře,
    /// "1 933 471,00 Kč" or, below zero, "−12 345,00 Kč". When the engine worked the year out with the rules of another
    /// year, the sign of an estimate stands in front of it, "≈ 880 922,00 Kč", also for a month with nothing in it,
    /// "≈ 0,00 Kč". It is set exactly when `netIncomeHalere` is.
    var netIncomeText: String? = nil

    /// The words under the net income row of the tooltip that say what the figure covers: for a month "součet za
    /// faktury zaplacené v měsíci", for a year of the years chart "za celý rok, po dani a pojistném" or, while the year
    /// is in progress, "od 1. 1. do 17. 10., po dani a pojistném". They are for the tooltip alone, as VoiceOver reads
    /// the figure without them. Nil where the column has no net income.
    var netIncomeNote: String? = nil

    /// What VoiceOver reads for the column, and what the tooltip says but for the words under its net income row
    /// (`netIncomeNote`): the amounts issued and received, then the net income and its average per month where the
    /// column has them, and after the average the sentence that the year is computed with the rules of another year
    /// where it is.
    var accessibilityLabel: String {
        func both(_ net: Int64, _ gross: Int64, sign: String = "") -> String {
            sign + CzechFormat.halere(net) + " bez DPH, " + sign + CzechFormat.halere(gross) + " s DPH"
        }
        let issued = both(
            issuedNetHalere, issuedGrossHalere, sign: issuedIsApproximate ? PredictionBuilder.estimateSign : "")
        let received = both(receivedNetHalere, receivedGrossHalere)
        var label = "\(title): vystaveno \(issued); přijato \(received)"
        if issuedIsApproximate {
            label += "; " + Self.approximateIssuedNote
        }
        if let netIncomeText {
            label += "; čistý příjem " + netIncomeText
        }
        if let netAverage {
            label += "; " + netAverage.label + " " + netAverage.value
            if let note = netAverage.note {
                label += "; " + note
            }
        }
        return label
    }
}

nonisolated extension ChartColumn {
    /// Why the issued amounts of a column are approximate: the sentence of the tooltip and of VoiceOver.
    static let approximateIssuedNote = "kurz ČNB ke dni vystavení zatím není, přepočteno posledním vyhlášeným"
}

/// The line under the chart with the uniform rates of the year.
nonisolated struct UniformLine: Sendable, Hashable {
    /// "Jednotný kurz za rok 2025".
    var title: String

    /// One pill each: "1 USD = 21,84 Kč".
    var rates: [String]

    /// Where the rates are from and what the income of the year is converted with.
    var source: String
}

/// A payment that was received lately, with what it adds to the levies.
nonisolated struct LatestReceipt: Sendable, Hashable {
    var invoiceID: Int64

    /// The day it was received: "15. 10.". The receipts are those of the year of the screen, so it has no year.
    var date: String
    var number: String
    var client: String

    /// The invoice as it was written: "5 445,00 Kč vč. DPH 945,00" or "14 350,00 USD · kurz 21,305".
    var original: String

    /// The income in crowns, "≈" before it while the payment waits for its rate.
    var czk: String

    /// What the payment adds to the levies, "+8 000 Kč".
    var effect: String
}

/// A payment to an authority that is still to come.
nonisolated struct UpcomingItem: Sendable, Hashable {
    /// The day it is due, or the first day of the month of an advance. The list is in the order of it.
    var date: CivilDate

    /// The big text of the date badge: the day of the month for a VAT return, the month for an advance.
    var day: String

    /// The small text of the date badge: the month for a VAT return, the year for an advance.
    var month: String
    var title: String
    var subtitle: String
    var amount: String

    /// Whether it is a VAT return, which is not a levy on income.
    var isVAT: Bool
}

/// What Přehled shows.
nonisolated struct OverviewData: Sendable, Hashable {
    /// The key figure of the result card: what is left to pay, with the sentence under it that says which levies it
    /// counts and which advances it takes off. The levies themselves are in `levies`, not beside it.
    var keyFigure: KeyFigureData

    /// The bar of the levies at the other side of the result card: what the three authorities want from the income so
    /// far, each with the advances paid and what is left in its popover. It is the bar that Výpočet shows for the same
    /// year and day, and has the total of the levies and its share of the income in its header, because the key figure
    /// is what is left to pay and not the levies.
    var levies: LevyBarData

    /// The tiles under the hairline of the result card, in the order they stand in.
    var tiles: [FigureTileData]
    var columns: [ChartColumn]
    var chartSubtitle: String

    /// The strip above the chart: the net income of the year so far and its average per month.
    var netIncome: OverviewNetIncome
    var uniformLine: UniformLine?
    var latestReceipts: [LatestReceipt]
    var upcoming: [UpcomingItem]

    /// The card with the estimate of the whole year, or nil when the page has none: it is there only for the current
    /// year, while the estimate is open.
    var prediction: PredictionCardData?
}

// MARK: - Builder

/// Turns a computed year into the texts and numbers of Přehled. Nothing here is looked up or computed again: every
/// number comes from the input.
nonisolated enum OverviewBuilder {
    /// How many receipts the list shows. The screen reads the invoices of this many receipts and no more.
    static let latestReceiptCount = 5

    /// How many payments are listed as the next ones.
    private static let upcomingCount = 4

    static func build(_ input: OverviewInput) -> OverviewData {
        // A year is over when it is before the current one and shown as of its last day. Any other day of it is the
        // year as it was on that day, worded like a year in progress, with the advances after it still to come.
        let isOver = AsOfState.isFinishedYear(asOf: input.asOf, today: input.today)
        // The part of the income that the levies take, which the strip of the net income tells. There is none while the
        // income is not above zero.
        let shares = IncomeShares(input.result)
        return OverviewData(
            keyFigure: keyFigure(input, isOver: isOver),
            levies: levies(input, isOver: isOver),
            tiles: tiles(input, isOver: isOver),
            columns: columns(input, isOver: isOver),
            chartSubtitle: chartSubtitle(input),
            netIncome: netIncome(input, shares: shares),
            uniformLine: uniformLine(input),
            latestReceipts: latestReceipts(input),
            upcoming: isOver ? [] : upcoming(input),
            prediction: predictionCard(input)
        )
    }

    // MARK: The result card

    /// The key figure: what is left to pay, with the sentence that says what it counts. The eyebrow is "Zbývá
    /// zaplatit", "Doplatek za rok 2025" for a year that is over and shown as of its last day, or "Vše pokryto
    /// zálohami" when nothing is left; any other day of a past year is worded as a year in progress. The levies and
    /// their share of the income are not here but in the header of the bar (`levies(_:isOver:)`).
    private static func keyFigure(_ input: OverviewInput, isOver: Bool) -> KeyFigureData {
        let result = input.result
        let year = input.year
        let eyebrow: String
        if result.remainingTotal > 0 {
            eyebrow = isOver ? "Doplatek za rok \(year)" : "Zbývá zaplatit"
        } else {
            eyebrow = "Vše pokryto zálohami"
        }
        let sentence: String
        if isOver {
            var text = "Odvody za celý rok \(year) po odečtení všech záloh."
            if result.childBonus > 0 {
                // A tax bonus comes back with the advances the levies did not need, and is no overpayment of them.
                let overpaidAdvances = result.overpaymentTotal - result.childBonus
                text += " Vrátí se " + CzechFormat.wholeKc(result.overpaymentTotal) + " – daňový bonus "
                    + CzechFormat.wholeKc(result.childBonus)
                    + (overpaidAdvances > 0 ? " a přeplatky záloh " + CzechFormat.wholeKc(overpaidAdvances) : "")
                    + "."
            } else if result.overpaymentTotal > 0 {
                text += " U některého úřadu zálohy převýšily povinnost o "
                    + CzechFormat.wholeKc(result.overpaymentTotal) + " – ten přeplatek se vrací."
            }
            sentence = text
        } else {
            // In January there is one month of advances to name, not a span from January to January.
            let months = input.asOf.month == 1 ? "leden" : "leden až " + CzechFormat.monthNames[input.asOf.month - 1]
            sentence = "Odvody z příjmů od 1.\u{00A0}1. do " + CzechFormat.date(input.receivedThrough)
                + " po odečtení záloh za " + months + "."
        }
        return KeyFigureData(
            eyebrow: eyebrow, figure: CzechFormat.wholeKc(result.remainingTotal), sentence: sentence)
    }

    /// The bar of the levies, the one Výpočet shows for the same year and day (`LevyBarBuilder.balances`): the levies
    /// of the income received through the day shown, "Odvody z příjmů do 17. 10.", or of the whole year, "Odvody za
    /// rok 2025", with the total of the levies and its share of the income in the header, because the key figure
    /// beside the bar is what is left to pay and not the levies.
    private static func levies(_ input: OverviewInput, isOver: Bool) -> LevyBarData {
        let header =
            isOver
            ? "Odvody za rok \(input.year)"
            : "Odvody z příjmů do " + BuilderText.date(input.receivedThrough, omittingYear: input.year)
        return LevyBarBuilder.balances(
            of: input.result, kind: .toDate(isOver: isOver), header: header, showsTotal: true)
    }

    /// The tiles under the key figure. In a year in progress: what the planned advances will still pay, what is paid
    /// with the return and the overviews, and what the levies take of the next crown. In a year that is over: what the
    /// advances paid, the Doplatek and what comes back. The Doplatek of a year that is over is the key figure again,
    /// and so is the second tile of a year with no advance left to plan, as the design draws them.
    private static func tiles(_ input: OverviewInput, isOver: Bool) -> [FigureTileData] {
        let result = input.result
        if isOver {
            return [
                FigureTileData(
                    label: "Zaplaceno zálohami", figure: CzechFormat.wholeKc(result.advancesPaidTotal),
                    note: "za celý rok \(input.year)"),
                FigureTileData(
                    label: "Doplatek", figure: CzechFormat.wholeKc(result.remainingTotal),
                    note: "s přiznáním a přehledy"),
                // A tax bonus comes back after the return, not after the overviews, and is no overpayment.
                result.childBonus > 0
                    ? FigureTileData(
                        label: "Vrátí se", figure: CzechFormat.wholeKc(result.overpaymentTotal),
                        note: "daňový bonus a přeplatky")
                    : FigureTileData(
                        label: "Přeplatky", figure: CzechFormat.wholeKc(result.overpaymentTotal),
                        note: "vrací se po přehledech"),
            ]
        }
        return [
            FigureTileData(
                label: "Odejde zálohami", figure: CzechFormat.wholeKc(result.leavesViaPlannedAdvances),
                note: "do konce roku podle plánu"),
            FigureTileData(
                label: "Doplatek", figure: CzechFormat.wholeKc(result.settlementTotal),
                note: "s přiznáním a přehledy za rok \(input.year)"),
            FigureTileData(
                label: "Mezní odvod", figure: CzechFormat.percent(result.marginalTotal),
                note: "z další koruny příjmu"),
        ]
    }

    // MARK: The estimate of the year

    /// The card with the estimate of the whole year. It is for the current year while the estimate is open: a year that
    /// is over has nothing to estimate, and on the last day of the current year nothing more is expected
    /// (`IncomePrediction.isClosed`). It does not depend on the day shown: the estimate is made as of today, and so is
    /// its chart, which counts the invoices issued up to the automatic reporting cutoff, the end of the current month
    /// (`AsOfState.automaticCutoff(today:)`), and the money received up to today from the invoices of the chart and the
    /// effects of their payments, and the rest of the year from the estimate and the payments it expects
    /// (`PredictionChartBuilder`). Unknown selected-year issuance omits the chart even when its payment belongs
    /// to the next year and the annual income and levies remain complete.
    private static func predictionCard(_ input: OverviewInput) -> PredictionCardData? {
        guard input.year == input.today.year, let outcome = input.prediction, !outcome.prediction.isClosed else {
            return nil
        }
        var card = PredictionBuilder.card(outcome)
        let hasUnknownIssuance = outcome.prediction.expectedInvoices.contains {
            $0.issueDate.year == input.year && $0.hasUnknownAmount
        }
        guard outcome.prediction.isComplete, !hasUnknownIssuance else { return card }
        card.chart = PredictionChartBuilder.months(
            year: input.year, today: input.today, issuedThrough: AsOfState.automaticCutoff(today: input.today),
            rows: input.chartRows, paymentEffects: input.invoicePaymentEffects, prediction: outcome.prediction,
            expectedPayments: input.expectedPayments)
        return card
    }

    // MARK: The net income

    /// The strip above the chart: what the income of the year so far leaves after the tax and the insurance
    /// (`NetIncome`), and the average of that per month. A year shown as of its last day is named as a whole; any other
    /// day is the span from the first of January through it, and the average is over the months so far. The part of the
    /// income that the net income is comes from `shares`; with none, the strip only says what the figure is. It is a
    /// figure of the levies, not of the chart, so the chart's grouping and VAT do not change it.
    private static func netIncome(_ input: OverviewInput, shares: IncomeShares?) -> OverviewNetIncome {
        let net = NetIncome(input.result)
        let yearLabel =
            net.isWholeYear
            ? "Čistý příjem za rok \(input.year)"
            : "Čistý příjem od 1.\u{00A0}1. do " + BuilderText.date(input.receivedThrough, omittingYear: input.year)
        let yearSub =
            shares.map { BuilderText.share(tenths: $0.netTenths) + " příjmů bez DPH po dani a pojistném" }
            ?? "příjmy bez DPH po dani a pojistném"
        return OverviewNetIncome(
            yearLabel: yearLabel, yearValue: CzechFormat.wholeKc(net.yearKc), yearSub: yearSub,
            monthLabel: "Čistý příjem průměrně za měsíc", monthValue: CzechFormat.wholeKc(net.monthlyKc),
            monthSub: "průměr za " + BuilderText.months(of: net)
        )
    }

    // MARK: The chart

    /// What the chart shows and how: the money received in other currencies is in it as its year converted it, at
    /// the uniform rate of the year of the months when it uses it, or of any year of the years chart, which each have
    /// their own.
    private static func chartSubtitle(_ input: OverviewInput) -> String {
        let scope: String
        let received: String
        switch input.chartMode {
        case .months:
            scope = "Rok \(input.year) po měsících"
            received =
                input.incomeFXMethod == .uniform
                ? "přijaté v cizí měně jednotným kurzem \(input.year)" : "cizí měny kurzem ČNB ke dni platby"
        case .years:
            scope = "Po letech"
            received =
                input.yearsAtUniformRate.isDisjoint(with: input.chartYears)
                ? "cizí měny kurzem ČNB ke dni platby" : "přijaté v cizí měně přepočtem zvoleným pro svůj rok"
        }
        return scope + " · v Kč " + (input.chartWithVAT ? "s DPH" : "bez DPH") + " · " + received
            + ", nezaplacené kurzem ČNB ke dni vystavení · podrobnosti po najetí myší"
    }

    /// The four sums of a column of the chart.
    private nonisolated struct ColumnSums {
        var issuedNet: Int64 = 0
        var issuedGross: Int64 = 0
        var issuedIsApproximate = false
        var receivedNet: Int64 = 0
        var receivedGross: Int64 = 0
    }

    /// The day after which no invoice counts as issued in the chart: the reporting cutoff, but today for the years
    /// chart of a year that is over (`AsOfState.isFinishedYear`), so that the money received since the end of that
    /// year is in it. The months chart is about the cutoff alone. Money counts as received only up to today as well
    /// (`columns(_:isOver:)`).
    static func chartCut(asOf: CivilDate, today: CivilDate, mode: ChartMode) -> CivilDate {
        mode == .years && AsOfState.isFinishedYear(asOf: asOf, today: today) ? today : asOf
    }

    /// The day the net income of `year` is counted to in the years chart, so the day its levies are worked out as of:
    /// the cut (`chartCut(asOf:today:mode:)`) for the year the cut is in, as the amounts of the chart are counted, and
    /// the last day for any year before it. Nil for a year after the cut, which has no net income yet.
    static func netIncomeDay(ofYear year: Int, cut: CivilDate) -> CivilDate? {
        if year > cut.year {
            return nil
        }
        return year == cut.year ? cut : CivilDate(year: year, month: 12, day: 31)
    }

    /// `text` with the sign of an estimate in front of it (`PredictionBuilder.estimateSign`) when the engine worked the
    /// year of `result` out with the rules of another year (`TaxResult.rulesAreEstimate`), and as it is otherwise.
    private static func estimate(_ text: String, of result: TaxResult) -> String {
        result.rulesAreEstimate ? PredictionBuilder.estimateSign + text : text
    }

    /// The net income of the year of `result` in crowns and haléře as the row of the tooltip and VoiceOver tell it
    /// (`ChartColumn.netIncomeText`), marked as an estimate when the year's rules are another year's.
    private static func netIncomeText(of result: TaxResult) -> String {
        estimate(CzechFormat.halere(NetIncome(result).yearKc * 100), of: result)
    }

    /// The words under the net income row of the tooltip of the year of `result` (`ChartColumn.netIncomeNote`): "za
    /// celý rok, po dani a pojistném" for a year worked out for its last day, otherwise the span it was worked out
    /// for, "od 1. 1. do 17. 10., po dani a pojistném".
    private static func netIncomeNote(of result: TaxResult) -> String {
        NetIncome(result).isWholeYear
            ? "za celý rok, po dani a pojistném"
            : "od 1.\u{00A0}1. do " + BuilderText.date(result.asOf, omittingYear: result.year) + ", po dani a pojistném"
    }

    /// The average net income per month of the year of `result` as the tooltip tells it, worded for the months its net
    /// income is over (`ChartNetAverage.label`). When the engine worked the year out with the rules of another year
    /// (`TaxResult.rulesAreEstimate`) the figure is marked as an estimate and the note is the sentence of the warning
    /// of the screens (`RulesWarning.message(year:rulesYear:)`); a year with rules of its own has neither.
    private static func netAverage(of result: TaxResult) -> ChartNetAverage {
        let net = NetIncome(result)
        let months = net.isWholeYear ? "" : " (" + BuilderText.months(of: net) + ")"
        return ChartNetAverage(
            label: "Průměrný čistý příjem za měsíc v roce \(result.year)" + months,
            value: estimate(CzechFormat.wholeKc(net.monthlyKc), of: result),
            note: result.rulesAreEstimate ? RulesWarning.message(year: result.year, rulesYear: result.rules.year) : nil
        )
    }

    /// The columns of the chart: the twelve months of the year, or the years of the list.
    ///
    /// No invoice issued after the cut (`chartCut(asOf:today:mode:)`) counts as issued, and no payment dated after the
    /// cut or after today counts as received: the cut reaches the end of the current month, but the money stops at
    /// today. A bar is in the column of the day of issue and the line in the column of the day of payment, so an
    /// invoice issued in one year and paid in the next is a bar of the first and money received in the second. Drafts
    /// and invoices in review count nowhere. An invoice in another currency that is not paid is worth the rate of its
    /// day of issue, or, while that is not declared, the latest declared one, and the column says it is approximate.
    ///
    /// The net income is a figure of the levies, not of the chart's amounts. Every month has the average of the
    /// selected year, the one the strip above the chart tells, and the net income of the invoices paid in it: the sum
    /// of what each such payment leaves after the levies it added on its own day
    /// (`OverviewInput.invoicePaymentEffects`, up to the cut), 0 for a month with none and for every month after the
    /// day shown. A year of the years chart has its net income and its average when the input has its levies
    /// (`OverviewInput.netIncomeResults`), and neither otherwise. A year that the engine worked out with the rules of
    /// another year (`TaxResult.rulesAreEstimate`: every year before the oldest rules the app has and every year after
    /// the newest) has them marked as estimates, with the sentence that says why: so has every month of such a
    /// selected year, in its net income and its average. A year with rules of its own is not marked. Each net income
    /// is followed by the words that say what it covers (`ChartColumn.netIncomeNote`).
    private static func columns(_ input: OverviewInput, isOver: Bool) -> [ChartColumn] {
        let cut = chartCut(asOf: input.asOf, today: input.today, mode: input.chartMode)
        // Money received stops at today, whatever the cut is.
        let receivedCut = min(cut, input.today)
        let years = input.chartYears
        let columnCount = input.chartMode == .months ? 12 : years.count
        let yearIndex = Dictionary(
            years.enumerated().map { ($0.element, $0.offset) }, uniquingKeysWith: { first, _ in first })

        // The column a day belongs to, if it is one of those shown.
        func column(of day: CivilDate) -> Int? {
            switch input.chartMode {
            case .months: day.year == input.year ? day.month - 1 : nil
            case .years: yearIndex[day.year]
            }
        }

        var sums = [ColumnSums](repeating: ColumnSums(), count: columnCount)
        for row in input.chartRows where !row.isDraft && !row.inReview {
            if row.issueDate <= cut, let index = column(of: row.issueDate) {
                let issued = issuedValue(of: row, receivedThrough: receivedCut)
                sums[index].issuedNet += issued.net
                sums[index].issuedGross += issued.gross
                sums[index].issuedIsApproximate = sums[index].issuedIsApproximate || issued.isApproximate
            }
            if let day = row.paymentDate, day <= receivedCut, let net = row.paymentNetHalere,
                let index = column(of: day)
            {
                sums[index].receivedNet += net
                sums[index].receivedGross += net + (row.paymentVatHalere ?? 0)
            }
        }

        // The month of the chosen day is the current one, and later months are in the future, unless the year is over.
        let currentMonth = input.asOf.month - 1
        let selectedYearAverage = netAverage(of: input.result)
        let monthNets = netIncomeByMonth(input, cut: receivedCut)
        return sums.enumerated().map { index, sum in
            switch input.chartMode {
            case .months:
                return ChartColumn(
                    label: CzechFormat.monthShort[index],
                    title: BuilderText.capitalized(CzechFormat.monthNames[index]) + " \(input.year)",
                    issuedNetHalere: sum.issuedNet, issuedGrossHalere: sum.issuedGross,
                    receivedNetHalere: sum.receivedNet, receivedGrossHalere: sum.receivedGross,
                    issuedIsApproximate: sum.issuedIsApproximate,
                    isFuture: !isOver && index > currentMonth, isCurrent: !isOver && index == currentMonth,
                    hasLinePoint: isOver || index <= currentMonth, netIncomeHalere: monthNets[index],
                    netAverage: selectedYearAverage,
                    netIncomeText: estimate(CzechFormat.halere(monthNets[index]), of: input.result),
                    netIncomeNote: "součet za faktury zaplacené v měsíci"
                )
            case .years:
                let year = years[index]
                let result = input.netIncomeResults[year]
                return ChartColumn(
                    label: String(year), title: "Rok \(year)",
                    issuedNetHalere: sum.issuedNet, issuedGrossHalere: sum.issuedGross,
                    receivedNetHalere: sum.receivedNet, receivedGrossHalere: sum.receivedGross,
                    issuedIsApproximate: sum.issuedIsApproximate,
                    isFuture: false, isCurrent: year == input.year, hasLinePoint: true,
                    netIncomeHalere: result.map { NetIncome($0).yearKc * 100 },
                    netAverage: result.map { netAverage(of: $0) }, netIncomeText: result.map { netIncomeText(of: $0) },
                    netIncomeNote: result.map { netIncomeNote(of: $0) }
                )
            }
        }
    }

    /// What the invoices paid in each month of `input.year` leave after the levies their payments added, in haléře,
    /// January first: the sum of `ReceiptEffect.netHalere` of the payments on or before `cut`. A month with no such
    /// payment has 0, and so has every month after the cut.
    private static func netIncomeByMonth(_ input: OverviewInput, cut: CivilDate) -> [Int64] {
        var nets = [Int64](repeating: 0, count: 12)
        for effect in input.invoicePaymentEffects {
            let day = effect.receipt.day
            if day.year == input.year, day <= cut {
                nets[day.month - 1] += effect.netHalere
            }
        }
        return nets
    }

    /// What an issued invoice is worth in the charts, in haléře without and with VAT, and whether that is approximate.
    nonisolated struct IssuedValue: Sendable, Hashable {
        var net: Int64
        var gross: Int64

        /// Whether the value is an estimate at a rate that stands in for the one of the day of issue, which the ČNB has
        /// not declared yet (`InvoiceChartRow.issueDayRateIsProvisional`).
        var isApproximate = false
    }

    /// What an issued invoice is worth, the one way both charts count it: in crowns as it is; in another currency what
    /// was paid when the payment is on or before `receivedThrough` (the money has come), otherwise an estimate at the
    /// ČNB rate of the day of issue, or at the latest declared rate while the rate of that day is not declared yet,
    /// and then the value is approximate. An estimate without any rate is worth nothing yet.
    static func issuedValue(of row: InvoiceChartRow, receivedThrough: CivilDate) -> IssuedValue {
        if row.currency.isCZK {
            return IssuedValue(net: row.netMinor, gross: row.netMinor + row.vatMinor)
        }
        if let day = row.paymentDate, day <= receivedThrough, let net = row.paymentNetHalere {
            return IssuedValue(net: net, gross: net + (row.paymentVatHalere ?? 0))
        }
        guard let rate = row.issueDayRate else { return IssuedValue(net: 0, gross: 0) }
        let net = rate.czkHalere(fromMinor: row.netMinor)
        return IssuedValue(
            net: net, gross: net + rate.czkHalere(fromMinor: row.vatMinor),
            isApproximate: row.issueDayRateIsProvisional)
    }

    /// What an issued invoice is worth in haléře, without and with VAT (`issuedValue(of:receivedThrough:)`), when a
    /// payment counts as received up to `cut`.
    static func issuedHalere(of row: InvoiceChartRow, cut: CivilDate) -> (net: Int64, gross: Int64) {
        let value = issuedValue(of: row, receivedThrough: cut)
        return (value.net, value.gross)
    }

    // MARK: The uniform rate

    /// The line with the uniform rates of the year, only when it has any: the rate of every foreign currency of the
    /// year's invoices whose rate is known, where the rates are from, and how the year converts its income.
    private static func uniformLine(_ input: OverviewInput) -> UniformLine? {
        let currencies = Set(input.foreignCurrencies).subtracting([CurrencyCode.czk])
        var seen: Set<CurrencyCode> = []
        let rates = input.uniformRates
            .filter { $0.year == input.year && currencies.contains($0.currency) && $0.rate > 0 && $0.amount > 0 }
            .sorted { $0.currency < $1.currency }
            .filter { seen.insert($0.currency).inserted }
        guard !rates.isEmpty else { return nil }
        let conversion = input.incomeFXMethod == .uniform ? "jednotným kurzem" : "denním kurzem ČNB"
        let source = (BuilderText.uniformSource(of: rates).map { $0 + " · " } ?? "")
            + "příjmy se přepočítávají " + conversion
        return UniformLine(
            title: "Jednotný kurz za rok \(input.year)", rates: rates.map(BuilderText.uniformRate), source: source)
    }

    // MARK: The latest receipts

    /// The newest receipts of the year up to the day the money is received by, newest first; receipts of one day keep
    /// the order they came in. A draft and an invoice in review are not income, so they are not receipts.
    private static func latestReceipts(_ input: OverviewInput) -> [LatestReceipt] {
        var received: [(index: Int, invoice: Invoice, payment: Payment, effect: ReceiptEffect)] = []
        for (index, entry) in input.latestReceipts.enumerated() {
            guard entry.invoice.status == .issued, entry.invoice.review == nil else { continue }
            guard let payment = entry.invoice.payment else { continue }
            guard payment.date.year == input.year, payment.date <= input.receivedThrough else { continue }
            received.append((index, entry.invoice, payment, entry.effect))
        }
        received.sort { first, second in
            if first.payment.date != second.payment.date {
                return first.payment.date > second.payment.date
            }
            return first.index < second.index
        }
        return received.prefix(latestReceiptCount).map { entry in
            LatestReceipt(
                invoiceID: entry.invoice.id,
                date: BuilderText.date(entry.payment.date, omittingYear: input.year),
                number: entry.invoice.number, client: entry.invoice.client.name,
                original: original(of: entry.invoice, paid: entry.payment),
                czk: (entry.payment.provisional ? "≈ " : "") + CzechFormat.halere(entry.payment.czkNetHalere),
                effect: (entry.effect.total >= 0 ? "+" : "") + CzechFormat.wholeKc(entry.effect.total)
            )
        }
    }

    /// The invoice as it was written, and for a foreign currency how it was converted.
    private static func original(of invoice: Invoice, paid payment: Payment) -> String {
        if invoice.currency.isCZK {
            let vat = invoice.vatMinor
            let total = CzechFormat.halere(invoice.totalMinor)
            return vat == 0 ? total : total + " vč. DPH " + CzechFormat.amount(vat)
        }
        let amount = CzechFormat.money(Money(minor: invoice.netMinor, currency: invoice.currency))
        if payment.conversion == .bankCZK {
            return amount + " · zadáno ručně"
        }
        guard let rate = payment.rate else { return amount }
        return amount + " · kurz " + CzechFormat.rate(rate.rate.rate)
    }

    // MARK: Upcoming payments

    /// The next payments after the chosen day, nearest first: the advances of the months after its month, one item a
    /// month and only for a month that has any, and the VAT return of every month of the year that is not due yet, as
    /// "DPH na výstupu za září": the output VAT, that of the invoices of the month. The VAT of a month with an invoice
    /// to check says that such invoices are not counted in it, and a month without any VAT only says to file the
    /// return.
    private static func upcoming(_ input: OverviewInput) -> [UpcomingItem] {
        var items: [UpcomingItem] = []
        for month in (input.asOf.month + 1)..<13 {
            let social = amount(input.advances.social, month: month)
            let health = amount(input.advances.health, month: month)
            let tax = amount(input.advances.tax, month: month)
            guard social + health + tax != 0 else { continue }
            var parts: [String] = []
            if social != 0 { parts.append("sociální " + CzechFormat.grouped(social)) }
            if health != 0 { parts.append("zdravotní " + CzechFormat.grouped(health)) }
            if tax != 0 { parts.append("daň " + CzechFormat.grouped(tax)) }
            items.append(
                UpcomingItem(
                    date: firstDay(ofMonth: month, year: input.year), day: CzechFormat.monthShort[month - 1],
                    month: String(input.year), title: "Zálohy za " + CzechFormat.monthNames[month - 1],
                    subtitle: parts.joined(separator: " · "), amount: CzechFormat.wholeKc(social + health + tax),
                    isVAT: false
                ))
        }
        for month in 1...12 {
            let due = CzechCalendar.vatFilingDue(year: input.year, month: month)
            guard due > input.receivedThrough else { continue }
            let vat = amount(input.vatByMonth, month: month)
            // A return due in the next year says which, as "led 27".
            let yearMark = due.year == input.year ? "" : " " + String(String(due.year).suffix(2))
            let subtitle =
                if input.vatToCheckMonths.contains(month) {
                    "faktury ke kontrole nejsou započtené"
                } else if vat == 0 {
                    "podat přiznání"
                } else {
                    "přiznání a kontrolní hlášení · mimo odvody z příjmů"
                }
            items.append(
                UpcomingItem(
                    date: due, day: String(due.day), month: CzechFormat.monthShort[due.month - 1] + yearMark,
                    title: "DPH na výstupu za " + CzechFormat.monthNames[month - 1], subtitle: subtitle,
                    amount: vat == 0 ? "0\u{00A0}Kč" : CzechFormat.halere(vat), isVAT: true
                ))
        }
        return Array(items.sorted { $0.date < $1.date }.prefix(upcomingCount))
    }

    /// The amount of a month (1 to 12) of a list of twelve, or 0 for a list that is shorter.
    private static func amount(_ list: [Int64], month: Int) -> Int64 {
        list.indices.contains(month - 1) ? list[month - 1] : 0
    }

    private static func firstDay(ofMonth month: Int, year: Int) -> CivilDate {
        guard let day = CivilDate(year: year, month: month, day: 1) else {
            preconditionFailure("1/\(month)/\(year) is not a date in the years 1 to 9999.")
        }
        return day
    }
}

// MARK: - Texts shared by the builders

/// Pieces of text that Přehled and Faktury write the same way.
nonisolated enum BuilderText {
    /// `text` with its first letter in capitals: "září" is "Září".
    static func capitalized(_ text: String) -> String {
        text.prefix(1).uppercased() + String(text.dropFirst())
    }

    /// A day as the screens write it: "17. 10." in `year`, the year of the screen, and "17. 10. 2025" in any other.
    static func date(_ day: CivilDate, omittingYear year: Int) -> String {
        day.year == year ? CzechFormat.dayMonth(day) : CzechFormat.date(day)
    }

    /// A uniform rate as a pill: "1 USD = 21,84 Kč", "100 JPY = 14,59 Kč". The rate has two decimals, as the GFŘ
    /// publishes it.
    static func uniformRate(_ rate: UniformRate) -> String {
        uniformRate(rate.rate, of: rate.currency, amount: rate.amount)
    }

    /// `rate` crowns for `amount` units of `currency` as a pill: "1 USD = 21,84 Kč" (`uniformRate(_:)`).
    static func uniformRate(_ rate: Decimal, of currency: CurrencyCode, amount: Int) -> String {
        "\(amount)\u{00A0}\(currency.code) = \(CzechFormat.rate(rate, fractionDigits: 2))\u{00A0}Kč"
    }

    /// Where uniform rates are from (`uniformSource(instruction:origin:)`), each source once, one after the other:
    /// "pokyn GFŘ-D-75", "pokyn GFŘ-D-80, zadáno ručně", "zadáno ručně". Nil when none says.
    static func uniformSource(of rates: [UniformRate]) -> String? {
        var sources: [String] = []
        for rate in rates {
            if let source = uniformSource(instruction: rate.instruction, origin: rate.origin),
                !sources.contains(source)
            {
                sources.append(source)
            }
        }
        return sources.isEmpty ? nil : sources.joined(separator: ", ")
    }

    /// Where a uniform rate published by `instruction` (nil or empty when it has none) and from `origin` is from, as
    /// every screen says it: "pokyn GFŘ-D-75" for an official rate; a rate entered by hand says so also when it has an
    /// instruction, "pokyn GFŘ-D-80, zadáno ručně", or only "zadáno ručně" without one. Nil for an official rate
    /// without an instruction.
    static func uniformSource(instruction: String?, origin: UniformRateOrigin) -> String? {
        let named = (instruction ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        switch (named.isEmpty, origin) {
        case (false, .manual):
            return "pokyn \(named), zadáno ručně"
        case (true, .manual):
            return "zadáno ručně"
        case (false, .builtIn), (false, .fetched):
            return "pokyn \(named)"
        case (true, .builtIn), (true, .fetched):
            return nil
        }
    }

    /// The tax after the credits as every screen writes it: "94 440 Kč", or "bonus 37 524 Kč" while it is below zero,
    /// a tax bonus that the tax office pays (`TaxResult.netTax`).
    static func taxOrBonus(_ kc: Int64) -> String {
        kc < 0 ? "bonus " + CzechFormat.wholeKc(-kc) : CzechFormat.wholeKc(kc)
    }

    /// Why `year` cannot use its uniform rate (`availability`), as every screen says it on the same day — the menu of
    /// the rate capsule under the rate, Nastavení › Rok in the choice of the conversion, the payment sheet in its
    /// notice: "zatím nevyšel – GFŘ ho zveřejní v lednu 2027" before the app looks for the rate, "zatím nevyšel –
    /// aplikace ho jednou denně hledá" while it does, "v aplikaci není – zadáte ho v Nastavení › Rok 2024" once it no
    /// longer does, and for a year that has rates but not that of a currency it was paid in "chybí jednotný kurz EUR –
    /// zadáte ho v Nastavení › Rok 2025", or "chybí jednotný kurz GBP – ručně ho zadat nelze" when Nastavení › Rok does
    /// not take the rate of that currency (`UniformRate.currenciesEnteredByHand`). Nil while the year can use its rate.
    static func uniformRateMissing(_ availability: UniformAvailability, year: Int) -> String? {
        switch availability {
        case .ready: nil
        case .missingCurrency(let currency):
            UniformRate.currenciesEnteredByHand.contains(currency)
                ? "chybí jednotný kurz \(currency.code) – zadáte ho v Nastavení › Rok \(year)"
                : "chybí jednotný kurz \(currency.code) – ručně ho zadat nelze"
        case .notPublishedYet: "zatím nevyšel – GFŘ ho zveřejní v lednu \(year + 1)"
        case .searchedFor: "zatím nevyšel – aplikace ho jednou denně hledá"
        case .notInApp: "v aplikaci není – zadáte ho v Nastavení › Rok \(year)"
        }
    }
}
