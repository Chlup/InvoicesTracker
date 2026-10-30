import Foundation

/// The texts the editor shows, worked out from what the model holds: the title and the line under it, the bars of a
/// new invoice and of an invoice that is edited, what the client chosen starts an invoice with, the currency with its
/// rate, the due date, the note under the QR box and the amounts of the rows.
extension InvoiceEditorModel {
    /// "Nová faktura", or "Upravit fakturu <number>".
    var title: String {
        editing.map { "Upravit fakturu \($0.number)" } ?? "Nová faktura"
    }

    /// "Ze šablony <name>" or "Prázdná faktura" for a new invoice, and "Koncept", "Uhrazená faktura" or "Vystavená
    /// faktura".
    var subtitle: String {
        if let editing {
            if editing.status == .draft {
                return "Koncept"
            }
            return editing.payment == nil ? "Vystavená faktura" : "Uhrazená faktura"
        }
        return template.map { "Ze šablony \($0.name)" } ?? "Prázdná faktura"
    }

    /// The name on the bar of a new invoice, "Šablona <name>" with "Vybrat jinou"; nil for an invoice that exists.
    var templateBarName: String? {
        editing == nil ? (template?.name ?? "Prázdná faktura") : nil
    }

    /// What the bar "Upravujete fakturu <number>" says of the invoice: "koncept", or "vystavená 30. 9. 2026 · uhrazená
    /// 2. 10. 2026". Nil for a new invoice.
    var editBarState: String? {
        guard let editing else { return nil }
        if editing.status == .draft {
            return "koncept"
        }
        var text = "vystavená " + CzechFormat.date(editing.issueDate)
        if let payment = editing.payment {
            text += " · uhrazená " + CzechFormat.date(payment.date)
        }
        if editing.review != nil {
            // An edit does not resolve it: the invoice stays out of the income until it is marked paid or deleted.
            text += " · ke kontrole"
        }
        return text
    }

    /// The warning under the bar of an invoice that is issued, with the word about the payment of a paid one.
    var editWarning: String? {
        guard let editing, editing.status == .issued else { return nil }
        var text =
            "Faktura už je vystavená. Po uložení se změní i její PDF – pokud jste ji už poslali, pošlete odběrateli"
            + " opravenou verzi."
        if editing.payment != nil {
            text += " Platba zůstane a příjem se přepočte stejným kurzem."
        }
        return text
    }

    var numberHint: String {
        editing?.status == .issued ? "číslo faktury se při úpravě nemění" : "řada RRRRMMPP podle měsíce DUZP"
    }

    /// Whether the number can be typed: until the invoice is issued.
    var numberIsEditable: Bool {
        editing?.status != .issued
    }

    /// The main button: "Uložit změny" for an invoice that is issued, otherwise "Vystavit fakturu".
    var primaryTitle: String {
        editing?.status == .issued ? "Uložit změny" : "Vystavit fakturu"
    }

    /// Whether there is "Uložit koncept": for a new invoice and a draft.
    var showsSaveDraft: Bool {
        editing == nil || editing?.status == .draft
    }

    /// "výchozí: USD · ACH (USD) · splatnost 30 dní · Mimo tuzemsko – § 9 odst. 1 (bez DPH) · faktura anglicky": what
    /// the client chosen starts an invoice with.
    var clientInfo: String {
        guard let client = pickedClient else { return "" }
        let language = client.language == .en ? "anglicky" : "česky"
        return "výchozí: \(client.currency.code) · \(client.paymentMethod) · splatnost "
            + "\(CzechCount.days(client.dueDays)) · \(client.vatMode.label) · faktura \(language)"
    }

    /// The way of payment the invoice prints.
    var methodText: String {
        terms?.paymentMethod ?? ""
    }

    var currency: CurrencyCode {
        terms?.currency ?? .czk
    }

    /// "CZK – česká koruna", or the currency with the rate of the DUZP, the day it was declared (so that an old rate
    /// is seen to be one) and whether it is fixed already.
    var currencyText: String {
        let currency = self.currency
        guard !currency.isCZK else { return "CZK – česká koruna" }
        guard let rate, rate.rate.currency == currency else {
            return "\(currency.code) · kurz ČNB zatím není k dispozici"
        }
        let fixing = rateIsFixed ? "platí od vystavení" : "při vystavení se zafixuje"
        let value = CzechFormat.rateLabel(rate.rate)
        let declared = CzechFormat.date(rate.declaredOn)
        return "\(currency.code) · kurz \(value) (ČNB k DUZP, vyhlášený \(declared), \(fixing))"
    }

    /// The due date, or "—" while the date or the days are not usable.
    var dueDateText: String {
        guard let dueDate = draft.usableDueDate else { return "—" }
        return CzechFormat.date(dueDate)
    }

    /// What follows the field of the due days: the word for the days it says ("den", "dny" or "dní"; "dní" for a text
    /// that is not a number of days) and the due date, "dní · 30. 11. 2026".
    var dueDaysLine: String {
        CzechCount.dayWord(dueDays ?? 0) + " · " + dueDateText
    }

    /// Whether a QR code is possible for the currency, so that the box can be ticked: the QR Platba for crowns and the
    /// EPC code for euros.
    var qrAvailable: Bool {
        Self.qrIsOnByDefault(for: currency)
    }

    /// The line under the box: what the code is, or why the page has none.
    var qrNote: String {
        if let qrReason {
            return qrReason
        }
        switch currency {
        case .czk:
            return "QR Platba s číslem účtu, částkou a variabilním symbolem – odběratel ji naskenuje v mobilní bance."
        case .eur:
            return "QR kód pro platbu SEPA (EPC) s IBAN, částkou a referencí."
        default:
            return ""
        }
    }

    var canIssue: Bool {
        validation.isEmpty && document != nil
    }

    var canAddItem: Bool {
        items.count < EditorLimits.items
    }

    /// How many lines the note prints.
    var noteLineCount: Int {
        InvoiceEditorChecks.lineCount(of: note)
    }

    /// The amount of the item in row `index` with its currency, or "—" where it cannot be worked out.
    func amountText(ofItem index: Int) -> String {
        guard !amountsTooHigh, items.indices.contains(index), let quantity = items[index].quantity,
            let price = items[index].unitPriceMinor
        else { return "—" }
        let amount = InvoiceMath.itemAmount(quantity: quantity, unitPriceMinor: price)
        return CzechFormat.money(Money(minor: amount, currency: currency))
    }
}
