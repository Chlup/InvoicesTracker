import Foundation

/// The limits of an invoice in the editor.
nonisolated enum EditorLimits {
    /// An invoice has at most this many items, and a note of at most this many lines, so that the page of the invoice
    /// stays one page (the page itself is checked as well: `InvoicePDFRenderer.fitsOnOnePage`).
    static let items = 12
    static let noteLines = 20

    /// The days from the date of issue to the due date.
    static let dueDays = 0...999

    /// The years of the DUZP. The ČNB rates of the days around it are looked up, and a date at the very edge of the
    /// calendar has no day before it or after it to look at.
    static let years = 2000...2099

    /// An amount of an item, of the whole invoice or with its VAT is below this, in minor units: 10¹⁰ units of the
    /// currency, which is far above any invoice and far below what an `Int64` of hundredths holds, even added up.
    static let amount = Decimal(1_000_000_000_000)
}

/// What the editor says is wrong, in Czech.
nonisolated enum EditorText {
    static let chooseClient = "Vyberte odběratele."

    /// Said where the clients are chosen and there is none, in the editor and in the form of a template.
    static let noClients = "Zatím nemáte žádného odběratele – přidejte ho v části Odběratelé."
    static let numberWithoutDigit = "Číslo faktury musí obsahovat alespoň jednu číslici."
    static let invalidDate = "Zadejte platné datum."
    static let invalidDueDays =
        "Splatnost musí být \(EditorLimits.dueDays.lowerBound) až \(EditorLimits.dueDays.upperBound) dní."
    static let noItems = "Přidejte alespoň jednu položku."
    static let tooManyItems = "Faktura může mít nejvýše \(EditorLimits.items) položek."
    static let amountTooHigh = "Částka na faktuře je příliš vysoká."
    static let totalNotPositive = "Celková částka musí být větší než nula."
    static let noteTooLong = "Poznámka může mít nejvýše \(EditorLimits.noteLines) řádků."
    static let notPrepared = "Fakturu se nepodařilo připravit."
    static let ratesNotDownloaded =
        "Kurz ČNB k DUZP zatím není stažený. Fakturu vystavíte, až se kurzy stáhnou – koncept můžete uložit už teď."

    /// For an invoice that is issued, which has no draft to save.
    static let changesWaitForRates = "Kurz ČNB k DUZP zatím není stažený. Změny uložíte, až se kurzy stáhnou."
    static let currencyNotQuoted = "ČNB pro tuto měnu kurz nevyhlašuje – fakturu v ní vystavit nejde."
    static let paymentNotConvertible =
        "Příjem z platby nejde přepočítat – kurz ČNB ke dni přijetí zatím není k dispozici."

    static func quantity(ofItem position: Int) -> String {
        "Položka \(position): zadejte počet větší než nula."
    }

    static func price(ofItem position: Int) -> String {
        "Položka \(position): zadejte cenu za MJ ve tvaru 13 340 nebo 13 340,50."
    }
}

/// Something that is wrong with the invoice in the editor.
nonisolated struct EditorProblem: Sendable, Hashable {
    var text: String

    /// Whether it stops even a draft from being saved. A draft is work in progress: it may be without items or without
    /// a price. An invoice is issued only once nothing at all is wrong with it.
    var blocksDraft: Bool
}

/// The items the rows of the editor say, and what is wrong with them.
nonisolated struct CheckedItems: Sendable {
    /// The items as the rows say them; a number that cannot be read counts as nothing. They are not to be added up
    /// while `tooHigh`.
    var items: [InvoiceItem]
    var problems: [EditorProblem]

    /// Whether an item, the whole invoice or the invoice with its VAT is above `EditorLimits.amount`.
    var tooHigh: Bool
}

/// The checks of the editor that need nothing but the texts the person typed.
nonisolated enum InvoiceEditorChecks {
    /// The items of `rows` for an invoice with `vatMode`, with what is wrong with them: no items, too many, a quantity
    /// that is not above zero or a price that is not an amount in some row, a total that is not above zero, amounts too
    /// high.
    ///
    /// The amounts are added up here in `Decimal`, and the total of the invoice and its VAT as well, before anything
    /// is added in `Int64`: typed values are bounded one by one (`AmountParser`), but twelve of them multiplied and
    /// added are not, and an overflow would stop the app.
    static func check(_ rows: [EditableItem], vatMode: VatMode) -> CheckedItems {
        var items: [InvoiceItem] = []
        var problems: [EditorProblem] = []
        var amounts: [Decimal] = []
        if rows.isEmpty {
            problems.append(EditorProblem(text: EditorText.noItems, blocksDraft: false))
        }
        if rows.count > EditorLimits.items {
            problems.append(EditorProblem(text: EditorText.tooManyItems, blocksDraft: true))
        }
        for (index, row) in rows.enumerated() {
            let position = index + 1
            let quantity = row.quantity
            if quantity.map({ $0 > 0 }) != true {
                // A quantity that cannot be read is more than an unfinished one: it cannot be stored.
                let unreadable = !row.quantityIsBlank && quantity == nil
                problems.append(EditorProblem(text: EditorText.quantity(ofItem: position), blocksDraft: unreadable))
            }
            if !row.priceIsBlank && row.unitPriceMinor == nil {
                problems.append(EditorProblem(text: EditorText.price(ofItem: position), blocksDraft: true))
            }
            items.append(
                InvoiceItem(
                    description: row.description.trimmingCharacters(in: .whitespacesAndNewlines),
                    quantity: quantity ?? 0, unit: row.unit.trimmingCharacters(in: .whitespacesAndNewlines),
                    unitPriceMinor: row.unitPriceMinor ?? 0))
            amounts.append(Self.amount(quantity: quantity ?? 0, unitPriceMinor: row.unitPriceMinor ?? 0))
        }
        let net = Self.total(of: amounts)
        let vat = DecimalMath.rounded(net * Decimal(vatMode.ratePercent) / 100, scale: 0, .plain)
        let tooHigh =
            amounts.contains { $0.magnitude >= EditorLimits.amount }
            || net.magnitude >= EditorLimits.amount || (net + vat).magnitude >= EditorLimits.amount
        if tooHigh {
            problems.append(EditorProblem(text: EditorText.amountTooHigh, blocksDraft: true))
        } else if !rows.isEmpty, problems.isEmpty, net + vat <= 0 {
            problems.append(EditorProblem(text: EditorText.totalNotPositive, blocksDraft: false))
        }
        return CheckedItems(items: items, problems: problems, tooHigh: tooHigh)
    }

    /// The amount of one item in whole minor units, rounded the way an invoice rounds it, as a `Decimal` that cannot
    /// overflow.
    static func amount(quantity: Decimal, unitPriceMinor: Int64) -> Decimal {
        DecimalMath.rounded(quantity * Decimal(unitPriceMinor), scale: 0, .plain)
    }

    /// The amounts added up, in `Decimal` too.
    static func total(of amounts: [Decimal]) -> Decimal {
        amounts.reduce(Decimal(0), +)
    }

    /// How many lines the note prints: the ones from the first to the last that has anything on it.
    static func lineCount(of note: String) -> Int {
        let trimmed = note.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? 0 : trimmed.components(separatedBy: .newlines).count
    }
}
