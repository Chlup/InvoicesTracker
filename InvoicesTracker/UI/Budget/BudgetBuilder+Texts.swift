import Foundation

// MARK: - The names of the categories

nonisolated extension BudgetCategory {
    /// The name of the category, as its row, the legend and "Zbytek dostane" name it: "Náklady", "Útrata", "Úspory",
    /// "Investice".
    var title: String {
        switch self {
        case .costs: "Náklady"
        case .spending: "Útrata"
        case .savings: "Úspory"
        case .investments: "Investice"
        }
    }

    /// The name in the accusative, as the note names the categories that change only the remainder: "Náklady",
    /// "Útratu", "Úspory", "Investice".
    var accusative: String {
        switch self {
        case .costs: "Náklady"
        case .spending: "Útratu"
        case .savings: "Úspory"
        case .investments: "Investice"
        }
    }

    /// What the category is for, under its name in its row.
    var purpose: String {
        switch self {
        case .costs: "hypotéka a další pravidelné platby"
        case .spending: "co můžu utratit"
        case .savings: "na spořicí účet"
        case .investments: "na investiční účet"
        }
    }
}

// MARK: - The texts of Rozpočet

nonisolated extension BudgetBuilder {
    /// The key figure of the result card, and whether it is an estimate, which the "odhad" pill beside its eyebrow
    /// says.
    struct Headline {
        /// The key figure with its eyebrow and its sentence.
        var keyFigure: KeyFigureData

        /// Whether the figure is an estimate as a whole.
        var isEstimate: Bool
    }

    /// The choices of the source row. Odhad za rok cannot be picked in a past year, whose estimate is what it was.
    static func sources(_ input: BudgetInput) -> [BudgetSourceChoice] {
        let isPast = input.year < input.today.year
        return [
            BudgetSourceChoice(value: .actual, title: "Skutečnost", isEnabled: true, help: nil),
            BudgetSourceChoice(
                value: .prediction, title: "Odhad za rok", isEnabled: !isPast,
                help: isPast ? "Za minulý rok je odhad stejný jako skutečnost." : nil),
            BudgetSourceChoice(value: .invoice, title: "Faktura", isEnabled: true, help: nil),
        ]
    }

    /// The key figure of `source`; `invoice` and `figures` are those of the chosen invoice in Faktura mode.
    static func headline(
        _ input: BudgetInput, source: BudgetSource, invoice: BudgetInvoice?, figures: InvoiceFigures?
    ) -> Headline {
        switch source {
        case .actual: actualHeadline(input)
        case .prediction: predictionHeadline(input)
        case .invoice: invoiceHeadline(input, invoice: invoice, figures: figures)
        }
    }

    /// The eyebrow of the averages, Přehled's label of the same figure.
    private static let averageEyebrow = "Čistý příjem průměrně za měsíc"

    /// Skutečnost: Přehled's average per month, with its sign of an estimate where it counts the unpaid invoices due
    /// this month, and the sentence that is Přehled's line under it with a capital letter, followed by how the year is
    /// worked out. A past year's average is of the whole year.
    private static func actualHeadline(_ input: BudgetInput) -> Headline {
        guard let actual = input.actual else {
            return Headline(keyFigure: KeyFigureData(eyebrow: averageEyebrow, figure: unknown), isEstimate: false)
        }
        let figure = actual.due.map(OverviewBuilder.dueAverage) ?? CzechFormat.wholeKc(actual.net.monthlyKc)
        let sentence: String
        if input.year < input.today.year {
            sentence = "Průměr za celý rok \(input.year)."
        } else {
            var months = "Průměr za " + BuilderText.months(of: actual.net)
            if let due = actual.due {
                months += ", " + OverviewBuilder.includingDueInvoices(due)
            }
            sentence = ended(months) + " Za rok počítá dvanáctinásobek."
        }
        return Headline(
            keyFigure: KeyFigureData(eyebrow: averageEyebrow, figure: figure, sentence: sentence), isEstimate: false)
    }

    /// Odhad za rok: a twelfth of the predicted net income of the whole year, with the "odhad" pill and no sign, and
    /// the sentence that says what the estimate is made from and what it leaves a year. An incomplete prediction has
    /// no figure and says why, as Odhad odvodů does.
    private static func predictionHeadline(_ input: BudgetInput) -> Headline {
        guard let outcome = input.prediction else {
            return Headline(keyFigure: KeyFigureData(eyebrow: averageEyebrow, figure: unknown), isEstimate: true)
        }
        guard outcome.prediction.isComplete else {
            return Headline(
                keyFigure: KeyFigureData(
                    eyebrow: averageEyebrow, figure: unknown, sentence: PredictionBuilder.incompleteText),
                isEstimate: true)
        }
        let net = NetIncome(outcome.result)
        let sentence =
            "Odhad za celý rok \(input.year) z faktur do " + BuilderText.date(input.today, omittingYear: input.year)
            + " a toho, co ještě do 31.\u{00A0}12. přijde, stejně jako v Odhadu odvodů. Po odvodech "
            + CzechFormat.wholeKc(net.yearKc) + " za rok."
        return Headline(
            keyFigure: KeyFigureData(
                eyebrow: averageEyebrow, figure: CzechFormat.wholeKc(net.monthlyKc), sentence: sentence),
            isEstimate: true)
    }

    /// Faktura: what reaches the account from the chosen invoice, with DPH, and the sentence that says when it came
    /// and what the app works out of it; or, for an invoice that is not paid, when it is due and that its figures are
    /// an estimate as if the money came on the day expected, with the "odhad" pill. A year without an invoice says so.
    private static func invoiceHeadline(
        _ input: BudgetInput, invoice: BudgetInvoice?, figures: InvoiceFigures?
    ) -> Headline {
        guard let invoice else {
            return Headline(
                keyFigure: KeyFigureData(
                    eyebrow: "Čistý příjem z faktury", figure: unknown,
                    sentence: "V roce \(input.year) zatím není vystavená žádná faktura."),
                isEstimate: false)
        }
        let paidDay = paidDay(of: invoice.invoice, in: input)
        let eyebrow = (paidDay == nil ? "Přijde z faktury " : "Přišlo z faktury ") + invoice.invoice.number
        let client = invoice.invoice.client.name
        let sentence: String
        if let paidDay {
            let words = client + " · peníze přišly " + date(paidDay, in: input)
            if let figures {
                sentence =
                    ended(words + (figures.hasVAT ? ", včetně DPH" : "")) + " "
                    + (figures.hasVAT ? "DPH a odvody" : "Odvody")
                    + " z této platby spočítá aplikace, zbytek se rozdělí podle kategorií."
            } else {
                sentence = ended(words)
            }
        } else {
            let words = client + " · zatím nezaplacená, splatná " + date(invoice.invoice.dueDate, in: input)
            if let figures {
                sentence =
                    ended(words) + " Částka i odvody jsou odhad, jako by peníze přišly " + date(figures.day, in: input)
                    + "; po zaplacení se spočítají přesně."
            } else {
                sentence = ended(words)
            }
        }
        return Headline(
            keyFigure: KeyFigureData(
                eyebrow: eyebrow, figure: figures.map { CzechFormat.wholeKc($0.totalKc) } ?? unknown,
                sentence: sentence),
            isEstimate: paidDay == nil)
    }

    // MARK: The bill of an invoice

    /// The bill of the chosen invoice: what reaches the account, the DPH where it has some, the levies with their
    /// share of the income, and what is left to divide under the strong line.
    static func billRows(_ invoice: BudgetInvoice, figures: InvoiceFigures, in input: BudgetInput) -> [BudgetBillRow] {
        let number = invoice.invoice.number
        let isPaid = paidDay(of: invoice.invoice, in: input) != nil
        var rows = [
            BudgetBillRow(
                sign: "", label: isPaid ? "Přišlo z faktury" : "Přijde z faktury",
                note: number + " · " + invoice.invoice.client.name + (figures.hasVAT ? " · včetně DPH" : ""),
                value: CzechFormat.wholeKc(figures.totalKc), share: nil, isLocked: false, isResult: false)
        ]
        if figures.hasVAT {
            let note =
                vatRate(of: invoice) + " z " + CzechFormat.wholeKc(figures.incomeKc) + " · za "
                + supplyMonth(of: invoice) + ", odvádí se do " + CzechFormat.date(vatDue(of: invoice))
            rows.append(
                BudgetBillRow(
                    sign: minus, label: "DPH", note: note, value: CzechFormat.wholeKc(-figures.vatKc), share: nil,
                    isLocked: true, isResult: false))
        }
        let levies = Authority.allCases.map { authority in
            authority.shortTitle.lowercased() + " " + CzechFormat.grouped(figures.levy(of: authority))
        }
        let share =
            figures.incomeKc > 0
            ? CzechFormat.percent(Decimal(figures.leviesKc) / Decimal(figures.incomeKc), fractionDigits: 1)
                + (figures.hasVAT ? " z příjmu bez DPH" : " z faktury")
            : nil
        rows.append(
            BudgetBillRow(
                sign: minus, label: "Daně a odvody", note: levies.joined(separator: " · "),
                value: CzechFormat.wholeKc(-figures.leviesKc), share: share, isLocked: true, isResult: false))
        rows.append(
            BudgetBillRow(
                sign: "=", label: "Čistý příjem k rozdělení", note: nil, value: CzechFormat.wholeKc(figures.netKc),
                share: nil, isLocked: false, isResult: true))
        return rows
    }

    /// The minus sign of an operator, the one `CzechFormat` writes before a negative number.
    private static let minus = "\u{2212}"

    /// The rate of DPH of `invoice` as text: "21 %".
    static func vatRate(of invoice: BudgetInvoice) -> String {
        "\(invoice.invoice.vatMode.ratePercent)\u{00A0}%"
    }

    /// The month of the taxable supply of `invoice`, which its DPH is filed for, in the nominative: "září".
    static func supplyMonth(of invoice: BudgetInvoice) -> String {
        CzechFormat.monthNames[invoice.invoice.duzp.month - 1]
    }

    /// The day the DPH of `invoice` is due with the return of the month of its taxable supply.
    static func vatDue(of invoice: BudgetInvoice) -> CivilDate {
        CzechCalendar.vatFilingDue(year: invoice.invoice.duzp.year, month: invoice.invoice.duzp.month)
    }

    // MARK: The invoice menu

    /// The button and the menu of Faktura mode, or nil when the year has no invoice: every invoice of the year with
    /// its status and the amount that reaches the account, with "≈ " while it is not paid.
    static func invoicePicker(_ input: BudgetInput, chosen: BudgetInvoice?) -> BudgetInvoicePicker? {
        guard let chosen else { return nil }
        let items = input.invoices.map { entry in
            let invoice = entry.invoice
            let status = status(of: invoice, in: input)
            let sign = paidDay(of: invoice, in: input) == nil ? PredictionBuilder.estimateSign : ""
            let amount = InvoiceFigures(entry).map { sign + CzechFormat.wholeKc($0.totalKc) } ?? unknown
            return BudgetInvoiceItem(
                id: invoice.id, number: invoice.number, client: invoice.client.name, status: status.text,
                statusTone: status.tone, amount: amount, isChosen: invoice.id == chosen.invoice.id)
        }
        return BudgetInvoicePicker(
            number: chosen.invoice.number, client: chosen.invoice.client.name, menuTitle: "Faktury roku \(input.year)",
            items: items)
    }

    /// The status line of `invoice` in the menu: "peníze přišly 5. 10." when it is paid, "po splatnosti od 10. 10."
    /// past its due date, and "čeká na platbu · splatná 30. 10." otherwise.
    private static func status(
        of invoice: Invoice, in input: BudgetInput
    ) -> (text: String, tone: BudgetInvoiceStatusTone) {
        switch invoice.displayStatus(asOf: input.today) {
        case .paid(let day):
            ("peníze přišly " + date(day, in: input), .received)
        case .overdue:
            ("po splatnosti od " + date(invoice.dueDate, in: input), .overdue)
        case .awaitingPayment, .draft, .needsReview:
            ("čeká na platbu · splatná " + date(invoice.dueDate, in: input), .awaiting)
        }
    }

    // MARK: The note

    /// The note under the card: which categories change only the remainder, named in the accusative, which category
    /// the remainder is, and how the categories are held; in Faktura mode also that the app works out the DPH, where
    /// the invoice has some, and the levies.
    static func note(remainder: BudgetCategory, source: BudgetSource, figures: InvoiceFigures?) -> String {
        let others = BudgetCategory.allCases.filter { $0 != remainder }.map(\.accusative)
        let named = others.dropLast().joined(separator: ", ") + " nebo " + (others.last ?? "")
        var note =
            "Když změníte \(named), změní se jen zbytek – teď je to \(remainder.title). Co jste nastavili, se samo"
            + " nepohne. Kategorie s pevnou částkou má stejnou částku v Kč pro skutečnost, odhad i každou fakturu a"
            + " dopočítá se jí jen podíl; ostatní drží svůj podíl. Rozdělení se ukládá."
        if source == .invoice {
            note +=
                figures?.hasVAT == true
                ? " DPH a odvody z faktury spočítá aplikace (odvody stejně jako Dopad na odvody v detailu faktury) a"
                    + " měnit nejdou."
                : " Odvody z faktury spočítá aplikace stejně jako Dopad na odvody v detailu faktury a měnit nejdou."
        }
        return note
    }

    // MARK: Pieces

    /// A day as the screen writes it: "5. 10." in the year of the screen, "5. 10. 2025" in any other.
    static func date(_ day: CivilDate, in input: BudgetInput) -> String {
        BuilderText.date(day, omittingYear: input.year)
    }

    /// `text` ended as a sentence: with a full stop, unless it ends with the dot of a day already.
    static func ended(_ text: String) -> String {
        text.hasSuffix(".") ? text : text + "."
    }
}
