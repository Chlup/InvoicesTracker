import Foundation

// MARK: - Input

/// What a payment that has not been made yet would add to the levies, worked out for the day the money is expected: the
/// due date, or the day shown when that is later.
nonisolated struct LevyEstimate: Sendable, Hashable {
    /// The day the money is expected. The year of it is the year the income belongs to.
    var day: CivilDate

    /// The income in haléře the payment would be worth: the net of an invoice in crowns, the net of any other invoice
    /// at the latest rate known.
    var incomeHalere: Int64

    /// What that income adds to each levy on `day`.
    var effect: ReceiptEffect
}

/// Everything the detail of an invoice needs, already loaded: the invoice and, where the invoice cannot tell, the rate
/// of its DUZP and the effect of its payment on the levies.
nonisolated struct InvoiceDetailInput: Sendable {
    var invoice: Invoice

    /// The day the screen is shown as of ("K datu"). It decides whether a payment counts yet, and a payment from
    /// another year than this day is written with its year.
    var asOf: CivilDate

    /// The day the status is worked out for: today, whatever year or day the screen is shown as of. It decides the
    /// status of the invoice and the pill that says it.
    var statusDay: CivilDate

    /// The ČNB rate that stands for the DUZP: for a draft, the one that would be fixed on it now (a draft shows that
    /// one, whatever it stored), and for an invoice that has none of its own, the one valid on its DUZP. Nil when the
    /// rate is not known.
    var duzpRate: StoredRate?

    /// What the payment adds to the levies of its year, for an invoice with a payment that counts as income.
    var paymentEffect: ReceiptEffect?

    /// What a payment would add, and so what it would leave, for an invoice that is not paid and would count as income.
    var estimate: LevyEstimate?
}

// MARK: - Output

/// What one authority takes of a payment: its name, the colour of it is the view's, and the amount with its sign.
nonisolated struct EffectRow: Sendable, Hashable, Identifiable {
    var authority: Authority
    var title: String

    /// "+780": whole Kč with the sign.
    var value: String

    var id: Authority {
        authority
    }
}

/// "Dopad na odvody 2026": what the payment adds to the levies of its year.
nonisolated struct LevyEffectDetail: Sendable, Hashable {
    var heading: String

    /// "+1 702 Kč".
    var total: String
    var rows: [EffectRow]

    /// "37,8 % z příjmu 4 500,00 Kč – peníze přišly 15. 10. 2026, proto patří do roku 2026.", and the thresholds of the
    /// year the income reaches: "Celá platba je nad stropem paušálu (příjmy 2 mil. Kč), kde je celý další příjem
    /// ziskem."
    var note: String
}

/// The payment of an invoice: when the money came, what it is worth as income, what it adds to the levies of its year
/// and what it leaves after them.
nonisolated struct PaymentDetail: Sendable, Hashable {
    /// "2. 10. 2026 · 14 350,00 USD".
    var line: String

    /// The income in crowns, with "≈" before it while the payment waits for its rate.
    var crowns: String

    /// How it was converted: "kurz ČNB ke dni přijetí 21,305".
    var note: String

    /// Why the payment does not count yet, when it is after the day shown.
    var laterNote: String?

    var effect: LevyEffectDetail?

    /// What the payment leaves of its income after the levies it adds ("Čistý příjem"), in whole Kč, with "≈" before it
    /// while the payment waits for its rate: "253 401 Kč". It is worked out from the effect, so it is there exactly
    /// when `effect` is, and it is more than the income when the effect is negative.
    var netIncome: String?
}

/// What the detail of an invoice shows.
nonisolated struct InvoiceDetail: Sendable, Hashable {
    var invoiceID: Int64
    var number: String

    /// The status as of `InvoiceDetailInput.statusDay`, which is today: the one an invoice has whatever year or day the
    /// screen is shown as of.
    var status: InvoiceDisplayStatus

    /// `status.label(asOf:)` with the day the screen is shown as of: what the pill says. The day of a payment from
    /// another year than that day comes with its year.
    var statusLabel: String

    /// "Alfa Systems s.r.o. · Česko".
    var client: String

    /// The amount with VAT in the currency of the invoice.
    var total: String

    /// One line per item: "205 h × 70,00 USD · Software development".
    var itemLines: [String]

    /// Vystaveno, DUZP, Splatnost, Platba, DPH and, for an invoice in a foreign currency, Kurz ČNB k DUZP.
    var facts: [DetailFact]
    var payment: PaymentDetail?

    /// What a payment would add to the levies and what it would leave after them, for an invoice that is not paid.
    var estimate: String?

    /// Why the invoice is held for review and that it is not counted, for an invoice to check.
    var reviewNote: String?

    /// Whether the invoice can be issued: it is a draft.
    var canIssue: Bool

    /// Whether the invoice can be marked paid: it is issued and has no payment, of whatever day. A payment that the day
    /// shown has not reached yet is a payment, so it cannot be marked paid again.
    var canPay: Bool

    /// Whether the payment of the invoice can be changed, its day or how it was converted: it has a payment and is not
    /// to check. The sheet that marks an invoice paid opens on that payment. An invoice to check is resolved by
    /// deleting it, as its note says, so its payment is not offered for a change.
    var canEditPayment: Bool

    /// Whether the invoice can be edited: it has no payment. A paid invoice stays as it was paid, and only its payment
    /// can be changed (`canEditPayment`).
    var canEdit: Bool
}

/// What the dialog that deletes an invoice says.
nonisolated struct InvoiceDeletionSummary: Sendable, Hashable {
    /// "Smazat fakturu 2026-05-01?"
    var title: String

    /// "Alfa Systems s.r.o. · 5 445,00 Kč".
    var subtitle: String

    /// The number to type to confirm.
    var number: String

    /// What deleting the invoice does, one sentence each.
    var lines: [String]
}

// MARK: - Builder

/// Turns an invoice into the texts of its detail and of the dialog that deletes it.
nonisolated enum InvoiceDetailBuilder {
    static func build(_ input: InvoiceDetailInput) -> InvoiceDetail {
        let invoice = input.invoice
        let status = invoice.displayStatus(asOf: input.statusDay)
        return InvoiceDetail(
            invoiceID: invoice.id, number: invoice.number, status: status,
            statusLabel: status.label(asOf: input.asOf), client: clientLine(invoice.client),
            total: money(invoice.totalMinor, invoice.currency),
            itemLines: invoice.items.map { itemLine($0, currency: invoice.currency) },
            facts: facts(of: invoice, duzpRate: input.duzpRate, asOf: input.asOf),
            payment: invoice.payment.map { payment($0, of: invoice, asOf: input.asOf, effect: input.paymentEffect) },
            estimate: invoice.payment == nil
                ? input.estimate.map { estimateText($0, isDraft: invoice.status == .draft) } : nil,
            reviewNote: invoice.review.map { reviewNote($0, isPaid: invoice.payment != nil) },
            canIssue: invoice.status == .draft, canPay: invoice.status == .issued && invoice.payment == nil,
            canEditPayment: invoice.payment != nil && invoice.review == nil,
            canEdit: invoice.payment == nil
        )
    }

    /// What the dialog that deletes `invoice` says. `effect` is what the payment adds to the levies of its year, for a
    /// payment that counts as income; without it the sentence about the payment leaves the levies out.
    static func deletion(of invoice: Invoice, effect: ReceiptEffect?) -> InvoiceDeletionSummary {
        let total = money(invoice.totalMinor, invoice.currency)
        var lines = [
            "Faktura \(invoice.number) (\(invoice.client.name), \(total)) zmizí ze seznamu faktur, z přehledů"
                + " i z výpočtu odvodů."
        ]
        if let payment = invoice.payment, countsAsIncome(invoice) {
            var line =
                "Platba z \(CzechFormat.date(payment.date)) přestane být příjmem: příjem za rok \(payment.date.year)"
                + " klesne o \(CzechFormat.halere(payment.czkNetHalere))"
            if let effect {
                line += " a odvody o \(CzechFormat.wholeKc(effect.total))"
            }
            lines.append(line + ".")
        }
        if invoice.status != .draft {
            lines.append(
                "Pokud jste fakturu poslali odběrateli nebo ji uvedli v přiznání k DPH,"
                    + " zůstane tam – opravte to i tam.")
        }
        if case .imported = invoice.source {
            lines.append("Při dalším importu stejného exportu z Fakturoidu by se faktura přidala znovu.")
        }
        return InvoiceDeletionSummary(
            title: "Smazat fakturu \(invoice.number)?", subtitle: "\(invoice.client.name) · \(total)",
            number: invoice.number, lines: lines)
    }

    // MARK: What an effect says

    /// The rows of what a receipt adds to each authority, in the order tax, social, health.
    static func effectRows(_ effect: ReceiptEffect) -> [EffectRow] {
        Authority.allCases.map { authority in
            let amount: Int64
            switch authority {
            case .tax: amount = effect.tax
            case .social: amount = effect.social
            case .health: amount = effect.health
            }
            return EffectRow(authority: authority, title: authority.title, value: signed(amount))
        }
    }

    /// An amount of whole Kč with its sign: "+1 702", "+0" or "−300".
    static func signed(_ amount: Int64) -> String {
        (amount >= 0 ? "+" : "") + CzechFormat.grouped(amount)
    }

    /// What the levies take of the income, as a percentage with one decimal ("37,8 %"), or nil for an income of
    /// nothing.
    static func share(of effect: ReceiptEffect, income incomeHalere: Int64) -> String? {
        guard incomeHalere != 0 else { return nil }
        // The levies are whole crowns and the income haléře: levies ÷ (income ÷ 100).
        return CzechFormat.percent(Decimal(effect.total) * 100 / Decimal(incomeHalere))
    }

    /// Why the levies take the share they do of the income of `effect`: a sentence for each threshold of the year the
    /// income reaches, in the order the income reaches them, or nil when it reaches none. "Z platby je 187 271 Kč nad
    /// stropem paušálu (příjmy 2 mil. Kč), kde je celý další příjem ziskem."
    static func thresholdsText(of effect: ReceiptEffect) -> String? {
        guard !effect.crossings.isEmpty else { return nil }
        return effect.crossings.map(thresholdSentence).joined(separator: " ")
    }

    /// One threshold, with the part of the payment past it or all of it, named as Hranice roku in Výpočet names it. The
    /// income of the tax bonus is named with the bonus it brings.
    private static func thresholdSentence(_ crossing: ThresholdCrossing) -> String {
        let payment: String
        switch crossing.extent {
        case .whole: payment = "Celá platba je"
        case .part(let amount): payment = "Z platby je \(CzechFormat.wholeKc(amount))"
        }
        let limit = CzechFormat.wholeKc(crossing.limit)
        switch crossing.threshold {
        case .bonusIncome:
            // A step, not a rate: what the income reaching it brings is the bonus.
            return "Příjmy tím dosáhnou šestinásobku minimální mzdy (\(limit)), takže se vyplatí daňový bonus "
                + CzechFormat.wholeKc(crossing.bonus) + "."
        case .expenseCap:
            let income = IncomeChartLayout.label(forKc: crossing.limit) + "\u{00A0}Kč"
            return "\(payment) nad stropem paušálu (příjmy \(income)), kde je celý další příjem ziskem."
        case .taxBand:
            return "\(payment) v 23% pásmu daně (základ daně nad \(limit))."
        case .socialMaximum:
            return "\(payment) nad stropem sociálního pojištění (vyměřovací základ \(limit)),"
                + " kde už sociální pojištění nepřibývá."
        }
    }

    // MARK: Pieces

    /// Whether the invoice is income once it is paid: it is issued, and not held for review.
    static func countsAsIncome(_ invoice: Invoice) -> Bool {
        invoice.status == .issued && invoice.review == nil
    }

    private static func money(_ minor: Int64, _ currency: CurrencyCode) -> String {
        CzechFormat.money(Money(minor: minor, currency: currency))
    }

    /// The name of the client and, after a dot, the country in Czech (`Countries`), as far as the client has one.
    private static func clientLine(_ client: ClientSnapshot) -> String {
        let country = Countries.name(client.country, language: .cs)
        return country.isEmpty ? client.name : "\(client.name) · \(country)"
    }

    /// "205 h × 70,00 USD · Software development": the quantity with its unit, the price of one unit and the text.
    private static func itemLine(_ item: InvoiceItem, currency: CurrencyCode) -> String {
        ItemLine.text(
            quantity: item.quantity, unit: item.unit, unitPriceMinor: item.unitPriceMinor, currency: currency,
            description: item.description)
    }

    private static func facts(of invoice: Invoice, duzpRate: StoredRate?, asOf: CivilDate) -> [DetailFact] {
        let vat = invoice.vatMinor
        let method = invoice.paymentMethod.trimmingCharacters(in: .whitespacesAndNewlines)
        var facts = [
            DetailFact(label: "Vystaveno", value: CzechFormat.date(invoice.issueDate)),
            DetailFact(label: "DUZP", value: CzechFormat.date(invoice.duzp)),
            DetailFact(label: "Splatnost", value: CzechFormat.date(invoice.dueDate)),
            DetailFact(label: "Platba", value: method.isEmpty ? "—" : method),
            DetailFact(
                label: "DPH", value: invoice.vatMode.label + (vat == 0 ? "" : " · " + money(vat, invoice.currency))),
        ]
        if invoice.isForeignCurrency {
            facts.append(rateFact(of: invoice, duzpRate: duzpRate, asOf: asOf))
        }
        return facts
    }

    /// "Kurz ČNB k DUZP": the rate and what the net of the invoice is at it, and under it the day the ČNB declared the
    /// rate, with the reason when that is not the DUZP. A draft shows the rate that would be fixed on it and says that
    /// it is fixed when the invoice is issued.
    private static func rateFact(of invoice: Invoice, duzpRate: StoredRate?, asOf: CivilDate) -> DetailFact {
        let isDraft = invoice.status == .draft
        let label = "Kurz ČNB k DUZP"
        let laterNote = isDraft ? ["při vystavení se zafixuje"] : []
        let known = isDraft ? duzpRate : (invoice.invoiceRate ?? duzpRate)
        guard let known, known.rate.currency == invoice.currency, known.rate.amount > 0 else {
            let note = (["kurz ČNB zatím není k dispozici"] + laterNote).joined(separator: " · ")
            return DetailFact(label: label, value: "—", note: note)
        }
        let crowns = known.rate.czkHalere(fromMinor: invoice.netMinor)
        let value = "\(CzechFormat.rateLabel(known.rate)) → \(CzechFormat.halere(crowns))"
        let declared = CzechFormat.date(known.declaredOn)
        // The ČNB declares the rate of a business day on that day, and the rate of any other day on the business day
        // before it. A rate declared on another day than that is the latest one there is.
        let expectedDay = CzechCalendar.rateDeclarationDay(for: invoice.duzp)
        let note: String
        if known.declaredOn == invoice.duzp {
            note = "vyhlášený \(declared)"
        } else if known.declaredOn == expectedDay {
            let nonBusinessDay = invoice.duzp.weekday >= 6 ? "víkend" : "svátek"
            note = "vyhlášený \(declared), DUZP \(CzechFormat.date(invoice.duzp)) připadlo na \(nonBusinessDay)"
        } else if expectedDay > asOf {
            note = "kurz k DUZP zatím nebyl vyhlášen – platí poslední vyhlášený kurz z \(declared)"
        } else {
            note = "kurz k DUZP nebyl vyhlášen – platí kurz vyhlášený \(declared)"
        }
        return DetailFact(label: label, value: value, note: ([note] + laterNote).joined(separator: " · "))
    }

    private static func payment(
        _ payment: Payment, of invoice: Invoice, asOf: CivilDate, effect: ReceiptEffect?
    ) -> PaymentDetail {
        let rate = payment.rate.map { CzechFormat.rate($0.rate.rate) }
        let note: String
        if invoice.currency.isCZK {
            note = "z toho DPH \(CzechFormat.halere(payment.czkVatHalere))"
        } else if payment.provisional {
            note = (rate.map { "předběžný kurz \($0)" } ?? "předběžně") + " · přepočte se, až bude kurz vyhlášen"
        } else {
            switch payment.conversion {
            case .bankCZK:
                note = "částka v Kč podle banky"
            case .uniform:
                note = "jednotný kurz za rok \(payment.date.year) \(rate ?? "—")"
            case .cnbDaily, .czk:
                note = "kurz ČNB ke dni přijetí \(rate ?? "—")"
            }
        }
        return PaymentDetail(
            line: "\(CzechFormat.date(payment.date)) · \(money(invoice.totalMinor, invoice.currency))",
            crowns: (payment.provisional ? "≈ " : "") + CzechFormat.halere(payment.czkNetHalere), note: note,
            laterNote: payment.date > asOf ? "Platba je až po zvoleném datu, zatím se nepočítá." : nil,
            effect: effect.map { levyEffect($0, of: payment) },
            netIncome: effect.map { netIncome(of: payment, after: $0) })
    }

    /// What `payment` leaves of its income after the levies in `effect`, in whole Kč: its amount without VAT less the
    /// levies, which are whole Kč, as the list works out the net of the invoice. The sign of an estimate is in front of
    /// it while the payment waits for its rate.
    private static func netIncome(of payment: Payment, after effect: ReceiptEffect) -> String {
        let sign = payment.provisional ? PredictionBuilder.estimateSign : ""
        return sign + PredictionBuilder.kc(ofHalere: payment.czkNetHalere - effect.total * 100)
    }

    private static func levyEffect(_ effect: ReceiptEffect, of payment: Payment) -> LevyEffectDetail {
        let year = payment.date.year
        let share = share(of: effect, income: payment.czkNetHalere) ?? "0\u{00A0}%"
        var note =
            "\(share) z příjmu \(CzechFormat.halere(payment.czkNetHalere))"
            + " – peníze přišly \(CzechFormat.date(payment.date)), proto patří do roku \(year)."
        if let thresholds = thresholdsText(of: effect) {
            note += " " + thresholds
        }
        return LevyEffectDetail(
            heading: "Dopad na odvody \(year)", total: signed(effect.total) + "\u{00A0}Kč",
            rows: effectRows(effect),
            note: note
        )
    }

    /// "Až přijde platba, přibude k odvodům za rok 2026 zhruba 1 700 Kč (37,8 % z příjmu), pokud peníze dorazí do
    /// 30. 10. 2026.", the thresholds the income would reach, and, as the last sentence, what the payment would leave
    /// after the levies, in hundreds as the levies are: "Čistý příjem z ní by byl zhruba 2 800 Kč."
    private static func estimateText(_ estimate: LevyEstimate, isDraft: Bool) -> String {
        var text = isDraft ? "Po vystavení a zaplacení" : "Až přijde platba,"
        text += " přibude k odvodům za rok \(estimate.day.year) zhruba "
        text += CzechFormat.wholeKc(roundedToHundreds(estimate.effect.total))
        if estimate.incomeHalere != 0, let share = share(of: estimate.effect, income: estimate.incomeHalere) {
            text += " (\(share) z příjmu)"
        }
        text += ", pokud peníze dorazí do \(CzechFormat.date(estimate.day))."
        if let thresholds = thresholdsText(of: estimate.effect) {
            text += " " + thresholds
        }
        let net = PredictionBuilder.wholeCrowns(ofHalere: estimate.incomeHalere - estimate.effect.total * 100)
        text += " Čistý příjem z ní by byl zhruba \(CzechFormat.wholeKc(roundedToHundreds(net)))."
        return text
    }

    /// `amount` rounded to whole hundreds, half up.
    static func roundedToHundreds(_ amount: Int64) -> Int64 {
        let hundreds = (amount + 50).quotientAndRemainder(dividingBy: 100)
        // Swift divides towards zero, so a negative amount needs one hundred less when it is not a whole hundred.
        return (hundreds.remainder < 0 ? hundreds.quotient - 1 : hundreds.quotient) * 100
    }

    /// Why the invoice is held for review and what resolves it: marking it paid, or deleting it. An invoice that has a
    /// payment already cannot be marked paid, so it is told to be deleted alone.
    private static func reviewNote(_ flag: ReviewFlag, isPaid: Bool) -> String {
        let reason = flag.reason.trimmingCharacters(in: .whitespacesAndNewlines)
        let why = reason.isEmpty ? "Ke kontrole." : "Ke kontrole: \(reason)."
        let resolution = isPaid ? "smažte ji." : "označte ji jako uhrazenou nebo ji smažte."
        return why + " Faktura se nezapočítává do příjmů, dokud ji nevyřešíte – " + resolution
    }
}
