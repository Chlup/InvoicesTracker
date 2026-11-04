import Foundation

// MARK: - Input

/// A field of a row of Rozpočet that the person types into.
nonisolated enum BudgetField: Hashable, Sendable {
    /// The share of a category in percent.
    case percent(BudgetCategory)

    /// The amount of a category in whole Kč a month.
    case amount(BudgetCategory)
}

/// What Rozpočet is made from: the year and the day, the choices of the person, the net incomes each source divides,
/// and the texts the person is typing.
nonisolated struct BudgetInput: Sendable {
    /// The year of the screen, which is the toolbar year.
    var year: Int

    /// Today, which the statuses of the invoices and the words of the estimate are as of.
    var today: CivilDate

    /// The split, the source and the invoice the person chose.
    var settings: BudgetSettings

    /// Přehled's average net income per month of the year, or nil when it did not load.
    var actual: AverageNetIncome?

    /// The prediction of the whole year with its levies, or nil when it did not load or the year is over.
    var prediction: PredictionOutcome?

    /// The invoices of the year a budget can be made from, newest number first.
    var invoices: [BudgetInvoice]

    /// The text of each field the person is typing into, which the field keeps until editing ends.
    var typedTexts: [BudgetField: String] = [:]

    /// The fields whose typed text could not be read, which say what they take.
    var refusedFields: Set<BudgetField> = []
}

// MARK: - Output

/// One choice of the row that picks the source.
nonisolated struct BudgetSourceChoice: Identifiable, Hashable, Sendable {
    /// The source the choice picks.
    var value: BudgetSource

    /// The text of the segment: "Skutečnost", "Odhad za rok" or "Faktura".
    var title: String

    /// Whether the choice can be picked.
    var isEnabled: Bool

    /// Why the choice cannot be picked, shown on hover, or nil for none.
    var help: String?

    /// A source is one choice of the row, so it identifies the choice.
    var id: BudgetSource {
        value
    }
}

/// What the status line of an invoice in the menu says, and so its colour.
nonisolated enum BudgetInvoiceStatusTone: Hashable, Sendable {
    /// The money came: secondary text.
    case received

    /// Not paid and not past its due date: the accent's text.
    case awaiting

    /// Not paid and past its due date: the red of text.
    case overdue
}

/// An invoice in the menu of Faktura mode.
nonisolated struct BudgetInvoiceItem: Identifiable, Hashable, Sendable {
    /// The id of the invoice.
    var id: Int64

    /// The number of the invoice, such as "20260905".
    var number: String

    /// The name of the client.
    var client: String

    /// The line under the number: "peníze přišly 5. 10.", "čeká na platbu · splatná 30. 10." or "po splatnosti od
    /// 10. 10.".
    var status: String

    /// What the status says, which decides its colour.
    var statusTone: BudgetInvoiceStatusTone

    /// The amount that reaches the account with DPH, in whole Kč, with "≈ " in front of it while the invoice is not
    /// paid, or "—" when it cannot be worked out.
    var amount: String

    /// Whether this is the invoice the budget divides.
    var isChosen: Bool

    /// The first line of the item: "20260905 · Alfa Systems s.r.o.".
    var title: String {
        number + " · " + client
    }
}

/// The button that picks the invoice in Faktura mode, and the menu it opens.
nonisolated struct BudgetInvoicePicker: Hashable, Sendable {
    /// The number of the chosen invoice, in semibold on the button.
    var number: String

    /// The client of the chosen invoice, after the number on the button.
    var client: String

    /// The title of the menu: "Faktury roku 2026".
    var menuTitle: String

    /// The invoices of the year, newest number first.
    var items: [BudgetInvoiceItem]
}

/// A row of the bill of an invoice in Faktura mode: an operator, a label with a note under it, and an amount.
nonisolated struct BudgetBillRow: Hashable, Sendable {
    /// The operator in front of the label: "" for the first row, "−" for what comes off, "=" for the result.
    var sign: String

    /// What the amount is, such as "DPH" or "Čistý příjem k rozdělení".
    var label: String

    /// The line under the label, or nil for none.
    var note: String?

    /// The amount in whole Kč, with the minus sign for what comes off.
    var value: String

    /// The share of the income next to the amount, such as "37,7 % z příjmu bez DPH", or nil for none.
    var share: String?

    /// Whether the app works the amount out and the person cannot change it, which a lock shows.
    var isLocked: Bool

    /// Whether the row is the result under the strong line.
    var isResult: Bool
}

/// How a row of a category is held, which decides its controls.
nonisolated enum BudgetRowMode: Hashable, Sendable {
    /// By its share of the net income: a slider, a % field and a Kč field.
    case share

    /// By a fixed amount a month: a read-only rail, the share as text and a Kč field.
    case fixed

    /// The remainder, which gets what the others leave: a read-only rail and its share and amount as text.
    case remainder
}

/// What the hint under a row says, and so its colour.
nonisolated enum BudgetHintTone: Hashable, Sendable {
    /// Orange text: the typed value was not taken as it is.
    case attention

    /// Red text: the categories take more than there is.
    case error
}

/// The line under a row that says why a value is not what was typed, or what is missing.
nonisolated struct BudgetHint: Hashable, Sendable {
    /// The words of the hint, a whole sentence.
    var text: String

    /// What the hint says, which decides its colour.
    var tone: BudgetHintTone
}

/// The row of one category in the card Rozdělení.
nonisolated struct BudgetRow: Identifiable, Hashable, Sendable {
    /// The category of the row.
    var category: BudgetCategory

    /// The name of the category: "Náklady", "Útrata", "Úspory" or "Investice".
    var name: String

    /// What the category is for, under its name.
    var purpose: String

    /// How the category is held.
    var mode: BudgetRowMode

    /// How much of the rail the share fills, 0 to 1.
    var fillFraction: Double

    /// How far the share can grow, 0 to 1: the rail is solid up to it and faint beyond. 1 for a row that is not held
    /// by a share.
    var limitFraction: Double

    /// Whether the rail has a stop mark at the limit.
    var showsStop: Bool

    /// The text of the % field ("15,0") of a share-held row, or the share as text of any other row ("13,2 %",
    /// "nad 100 %" or "—").
    var percentText: String

    /// The text of the Kč field ("25 000") of a row that has one, or the amount as text of the remainder
    /// ("89 022 Kč" or "—").
    var amountText: String

    /// Whether the amount is below zero, so it is set in the red of text.
    var amountIsNegative: Bool

    /// The amount of the year under the Kč column, "za rok 2 245 332 Kč", or nil in Faktura mode.
    var yearText: String?

    /// Whether the Kč field takes typing.
    var amountFieldIsEnabled: Bool

    /// The line under the row, or nil for none.
    var hint: BudgetHint?

    /// A category has one row, so it identifies the row.
    var id: BudgetCategory {
        category
    }

    /// What VoiceOver reads for the slider: "Úspory, podíl z čistého příjmu".
    var sliderAccessibilityLabel: String {
        name + ", podíl z čistého příjmu"
    }

    /// What VoiceOver reads for the % field: "Úspory v procentech".
    var percentFieldAccessibilityLabel: String {
        name + " v procentech"
    }

    /// What VoiceOver reads for the Kč field: "Úspory v korunách".
    var amountFieldAccessibilityLabel: String {
        name + " v korunách"
    }

    /// What VoiceOver reads for the checkbox "pevná částka": "Náklady: pevná částka v Kč".
    var fixedToggleAccessibilityLabel: String {
        name + ": pevná částka v Kč"
    }
}

/// Everything Rozpočet shows, as the builder words it.
nonisolated struct BudgetData: Hashable, Sendable {
    /// The source the screen shows, which the source row selects: the saved one, except that a saved Odhad shows
    /// Skutečnost in a past year.
    var source: BudgetSource

    /// The choices of the source row.
    var sources: [BudgetSourceChoice]

    /// The button that picks the invoice, in Faktura mode while the year has an invoice.
    var invoicePicker: BudgetInvoicePicker?

    /// The key figure of the result card.
    var keyFigure: KeyFigureData

    /// Whether the orange "odhad" pill stands next to the eyebrow.
    var showsEstimatePill: Bool

    /// The split bar of the result card.
    var bar: SplitBarData

    /// The bill of the invoice above the rows, in Faktura mode; empty otherwise.
    var billRows: [BudgetBillRow]

    /// The subtitle of the card Rozdělení.
    var cardSubtitle: String

    /// The categories that "Zbytek dostane" offers, in order.
    var remainderChoices: [BudgetCategory]

    /// The category that gets what the others leave.
    var remainder: BudgetCategory

    /// The rows of the four categories, in order.
    var rows: [BudgetRow]

    /// The note under the card.
    var note: String
}
