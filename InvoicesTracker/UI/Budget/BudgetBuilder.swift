import Foundation

/// Builds Rozpočet: what a net income is, how the split divides it among the four categories, and every text the screen
/// shows of it (`BudgetData`).
///
/// Three sources give the net income. Skutečnost divides Přehled's average per month (`AverageNetIncome`), with the
/// year twelve times it. Odhad za rok divides the predicted net income of the whole year (`PredictionOutcome`), a
/// twelfth of it a month and all of it a year; a past year has no estimate, so it shows Skutečnost. Faktura divides
/// what one invoice of the year leaves after its levies, once its DPH and its levies have come off the top. All
/// amounts are whole Kč. Where there is nothing to divide (an incomplete prediction, no invoice, a source that did not
/// load) the amounts are "—" while the shares stay as they are; an average below zero divides 0.
nonisolated enum BudgetBuilder {
    /// Everything Rozpočet shows for `input`.
    static func build(_ input: BudgetInput) -> BudgetData {
        let source = source(of: input)
        let invoice = source == .invoice ? chosenInvoice(in: input) : nil
        let figures = invoice.flatMap { InvoiceFigures($0) }
        let division = Division(input, source: source)
        let headline = headline(input, source: source, invoice: invoice, figures: figures)
        var bill: [BudgetBillRow] = []
        if let invoice, let figures {
            bill = billRows(invoice, figures: figures, in: input)
        }
        return BudgetData(
            source: source, sources: sources(input),
            invoicePicker: source == .invoice ? invoicePicker(input, chosen: invoice) : nil,
            keyFigure: headline.keyFigure, showsEstimatePill: headline.isEstimate,
            bar: bar(division: division, invoice: invoice, figures: figures), billRows: bill,
            cardSubtitle: source == .invoice
                ? "Podíly z toho, co po odvodech zbude, nebo pevné částky"
                : "Podíly z čistého příjmu, nebo pevné částky · za měsíc a za rok",
            remainderChoices: BudgetCategory.allCases, remainder: division.split.remainder,
            rows: BudgetCategory.allCases.map { row(of: $0, in: input, division: division) },
            note: note(remainder: division.split.remainder, source: source, figures: figures))
    }

    /// The source the screen shows: the saved one, except that Odhad za rok shows Skutečnost in a past year, as the
    /// estimate of a year that is over is what it was.
    static func source(of input: BudgetInput) -> BudgetSource {
        let saved = input.settings.source
        return saved == .prediction && input.year < input.today.year ? .actual : saved
    }

    /// The invoice Faktura mode divides: the saved one while it is listed, otherwise the one whose money came last,
    /// and the first listed when none is paid. Nil when the year has no invoice. The fallback is only shown; the saved
    /// id stays until the person picks an invoice.
    static func chosenInvoice(in input: BudgetInput) -> BudgetInvoice? {
        if let id = input.settings.invoiceID, let saved = input.invoices.first(where: { $0.invoice.id == id }) {
            return saved
        }
        var latest: (entry: BudgetInvoice, day: CivilDate)?
        for entry in input.invoices {
            guard let day = paidDay(of: entry.invoice, in: input) else { continue }
            if latest.map({ day > $0.day }) ?? true {
                latest = (entry, day)
            }
        }
        return latest?.entry ?? input.invoices.first
    }

    /// The amount the split divides, in whole Kč: a month's net income for Skutečnost and Odhad za rok, and what the
    /// chosen invoice leaves after its levies for Faktura. Nil when there is nothing to divide; an average or an
    /// invoice that leaves less than nothing divides 0.
    static func net(of input: BudgetInput) -> Int64? {
        switch source(of: input) {
        case .actual:
            input.actual.map { max(0, $0.monthlyKc) }
        case .prediction:
            completeOutcome(of: input).map { max(0, NetIncome($0.result).monthlyKc) }
        case .invoice:
            chosenInvoice(in: input).flatMap { InvoiceFigures($0) }.map(\.netKc)
        }
    }

    // MARK: What is divided

    /// The prediction of `input` while it is complete, which is when its whole year can be divided.
    static func completeOutcome(of input: BudgetInput) -> PredictionOutcome? {
        guard let outcome = input.prediction, outcome.prediction.isComplete else { return nil }
        return outcome
    }

    /// The day the money for `invoice` came, as of today, or nil when it is not paid (`Invoice.displayStatus(asOf:)`).
    static func paidDay(of invoice: Invoice, in input: BudgetInput) -> CivilDate? {
        if case .paid(let day) = invoice.displayStatus(asOf: input.today) {
            return day
        }
        return nil
    }

    /// The figures of an invoice in whole Kč, as Faktura mode shows them: its income without DPH, its DPH, its levies,
    /// and what it leaves to divide.
    struct InvoiceFigures {
        /// What the income adds to the levies, with the receipt it was worked out for.
        var effect: ReceiptEffect

        /// The income without DPH.
        var incomeKc: Int64

        /// The DPH, 0 for an invoice outside Czech VAT.
        var vatKc: Int64

        /// The day the money came, or is expected.
        var day: CivilDate

        /// The figures of `invoice`, or nil when its net could not be worked out.
        init?(_ invoice: BudgetInvoice) {
            guard let net = invoice.net, let incomeKc = invoice.incomeKc else { return nil }
            effect = net.effect
            self.incomeKc = incomeKc
            vatKc = invoice.vatKc
            day = net.day
        }

        /// The three levies together.
        var leviesKc: Int64 {
            effect.total
        }

        /// What reaches the account: the income with its DPH.
        var totalKc: Int64 {
            incomeKc + vatKc
        }

        /// What the split divides: the income less its levies, never below 0.
        var netKc: Int64 {
            max(0, incomeKc - leviesKc)
        }

        /// Whether the invoice has DPH, which then comes off the top as well.
        var hasVAT: Bool {
            vatKc != 0
        }

        /// The levy of `authority`.
        func levy(of authority: Authority) -> Int64 {
            switch authority {
            case .tax: effect.tax
            case .social: effect.social
            case .health: effect.health
            }
        }
    }

    /// How the split divides the net income of the source: the amount a month, or of the invoice, and for Skutečnost
    /// and Odhad za rok the amount of the year.
    struct Division {
        /// The split of the person.
        var split: BudgetSplit

        /// The amount divided (`BudgetBuilder.net(of:)`), nil when there is nothing to divide.
        var net: Int64?

        /// The allocation of `net`, with the fixed amounts once, or nil when there is nothing to divide.
        var month: BudgetAllocation?

        /// The allocation of the year, with the fixed amounts twelve times, or nil in Faktura mode or when there is
        /// nothing to divide. Skutečnost divides twelve times the month, Odhad za rok the predicted net of the year.
        var year: BudgetAllocation?

        /// Whether the source is Faktura, which divides an invoice and has no year.
        var isInvoice: Bool

        /// How `input`'s split divides the net income of `source`, the source the screen shows
        /// (`BudgetBuilder.source(of:)`).
        init(_ input: BudgetInput, source: BudgetSource) {
            split = input.settings.split
            isInvoice = source == .invoice
            net = BudgetBuilder.net(of: input)
            let yearNet: Int64? =
                switch source {
                case .actual: net.map { $0 * 12 }
                case .prediction: BudgetBuilder.completeOutcome(of: input).map { max(0, NetIncome($0.result).yearKc) }
                case .invoice: nil
                }
            month = net.map { split.allocation(net: $0, fixedMultiplier: 1) }
            year = yearNet.map { split.allocation(net: $0, fixedMultiplier: 12) }
        }

        /// How `category` is held.
        func mode(of category: BudgetCategory) -> BudgetRowMode {
            if category == split.remainder {
                return .remainder
            }
            if case .fixed = split.holding(of: category) {
                return .fixed
            }
            return .share
        }

        /// The share `category` is held by, or nil when it is the remainder or held by a fixed amount.
        func heldShare(of category: BudgetCategory) -> Decimal? {
            guard category != split.remainder, case .share(let share) = split.holding(of: category) else {
                return nil
            }
            return share
        }

        /// The amount a month `category` is held by, or 0 when it is not held by a fixed amount.
        func fixedKc(of category: BudgetCategory) -> Int64 {
            if case .fixed(let kc) = split.holding(of: category) {
                return kc
            }
            return 0
        }

        /// The most `category` can have a month, in whole Kč: what it has and what the remainder has to spare. Nil
        /// when there is nothing above 0 to divide.
        func limitKc(of category: BudgetCategory) -> Int64? {
            guard let net, net > 0, let month else { return nil }
            return (month.amounts[category] ?? 0) + max(0, month.amounts[split.remainder] ?? 0)
        }
    }

    // MARK: The rows

    /// What stands for an amount or a share that is not known.
    static let unknown = "—"

    /// The row of `category`.
    private static func row(of category: BudgetCategory, in input: BudgetInput, division: Division) -> BudgetRow {
        let mode = division.mode(of: category)
        let amount = division.month?.amounts[category]
        let held = division.heldShare(of: category) ?? 0
        let limit = division.split.shareLimit(of: category, net: division.net)
        let percentText: String
        let amountText: String
        switch mode {
        case .share:
            percentText = input.typedTexts[.percent(category)] ?? percentField(held)
            amountText = input.typedTexts[.amount(category)] ?? amount.map(CzechFormat.grouped) ?? unknown
        case .fixed:
            percentText = shareText(of: category, in: division)
            amountText = input.typedTexts[.amount(category)] ?? CzechFormat.grouped(division.fixedKc(of: category))
        case .remainder:
            percentText = shareText(of: category, in: division)
            amountText = amount.map(CzechFormat.wholeKc) ?? unknown
        }
        let fill = mode == .share ? held : division.month?.shares[category] ?? 0
        let year = division.year?.amounts[category].map(CzechFormat.wholeKc) ?? unknown
        return BudgetRow(
            category: category, name: category.title, purpose: category.purpose, mode: mode,
            fillFraction: fraction(fill), limitFraction: mode == .share ? fraction(limit) : 1,
            showsStop: mode == .share && limit < 1, percentText: percentText, amountText: amountText,
            amountIsNegative: (amount ?? 0) < 0,
            yearText: division.isInvoice ? nil : "za rok " + year,
            amountFieldIsEnabled: mode == .fixed || (mode == .share && (division.net ?? 0) > 0),
            hint: hint(of: category, mode: mode, in: input, division: division))
    }

    /// The share of `category` as text, for a row that is held by a fixed amount or is the remainder: "13,2 %",
    /// "nad 100 %" above the whole, and "—" below zero or when there is nothing above 0 to divide.
    static func shareText(of category: BudgetCategory, in division: Division) -> String {
        if let held = division.heldShare(of: category) {
            return CzechFormat.percent(held, fractionDigits: 1)
        }
        guard let share = division.month?.shares[category], share >= 0 else { return unknown }
        return share > 1 ? "nad 100\u{00A0}%" : CzechFormat.percent(share, fractionDigits: 1)
    }

    /// `share` as the % field shows it: in percent with one decimal and a comma, without the sign, "15,0".
    private static func percentField(_ share: Decimal) -> String {
        CzechFormat.rate(share * 100, fractionDigits: 1)
    }

    /// `value` as a fraction of a rail, kept between 0 and 1.
    private static func fraction(_ value: Decimal) -> Double {
        min(1, max(0, NSDecimalNumber(decimal: value).doubleValue))
    }

    /// The hint under the row of `category`, the first that applies: the shortfall on the remainder when the others
    /// take more than there is (red); what a field that could not be read takes (orange); and the most a share-held
    /// category can have when the text typed asks for more (orange).
    private static func hint(
        of category: BudgetCategory, mode: BudgetRowMode, in input: BudgetInput, division: Division
    ) -> BudgetHint? {
        if mode == .remainder {
            guard let shortfall = division.month?.shortfall, shortfall > 0 else { return nil }
            let text =
                "Nestačí to: pevné částky a podíly jsou o \(CzechFormat.wholeKc(shortfall)) víc, než je k rozdělení"
                + (division.isInvoice ? " z této faktury." : ".")
            return BudgetHint(text: text, tone: .error)
        }
        if input.refusedFields.contains(.percent(category)) {
            return BudgetHint(text: "Zadejte procenta, nejvýš s jedním desetinným místem.", tone: .attention)
        }
        if input.refusedFields.contains(.amount(category)) {
            return BudgetHint(text: "Zadejte částku v celých korunách.", tone: .attention)
        }
        guard mode == .share, asksAboveLimit(category, in: input, division: division) else { return nil }
        let limit = division.split.shareLimit(of: category, net: division.net)
        let limitKc = division.limitKc(of: category).map { " (" + CzechFormat.wholeKc($0) + ")" } ?? ""
        let text =
            "Víc se nevejde: na zbytek (\(division.split.remainder.title)) už nic nezbývá. Nejvýš "
            + CzechFormat.percent(limit, fractionDigits: 1) + limitKc + "."
        return BudgetHint(text: text, tone: .attention)
    }

    /// Whether the text typed into a field of `category` asks for more than the category can have: a percentage above
    /// the limit as the field shows it with one decimal, or an amount above the most it can have a month.
    private static func asksAboveLimit(_ category: BudgetCategory, in input: BudgetInput, division: Division) -> Bool {
        let limit = division.split.shareLimit(of: category, net: division.net)
        if let text = input.typedTexts[.percent(category)],
            let percent = AmountParser.decimal(text, maxFractionDigits: 1),
            percent * 10 > Decimal(DecimalMath.halfUp(limit * 1_000))
        {
            return true
        }
        if let text = input.typedTexts[.amount(category)], let kc = AmountParser.wholeKc(text),
            let limitKc = division.limitKc(of: category), kc > limitKc
        {
            return true
        }
        return false
    }
}
