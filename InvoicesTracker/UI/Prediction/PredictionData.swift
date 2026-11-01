import Foundation

// MARK: - The card of Přehled

/// One of the four figures of the card of Přehled, with its caption and the line under it: "Doplatek", "198 702 Kč",
/// "po zálohách 268 080 Kč za celý rok".
nonisolated struct PredictionMini: Identifiable, Sendable, Hashable {
    var label: String
    var value: String

    /// The share of the income that the figure takes, written beside it in smaller type: "17,0 %". Only the tax and
    /// the insurance have one (`PredictionBuilder.leviesShare(_:)`).
    var share: String?
    var sub: String

    var id: String {
        label
    }
}

// MARK: - The income

/// What a part of the year's income is, for the bar and its legend.
nonisolated enum PredictionPartKind: Sendable, Hashable {
    /// The money received up to the day of the estimate.
    case received

    /// Issued invoices that are not paid yet and will be paid by 31 December.
    case waiting

    /// Drafts and invoices the clients are expected to issue, paid by 31 December.
    case expected
}

/// A part of the year's income: what it is called, how much it is, and how much of the income, for drawing the bar.
nonisolated struct PredictionPart: Identifiable, Sendable, Hashable {
    var kind: PredictionPartKind
    var text: String
    var value: String

    /// The part of the year's income, 0 to 1. It is for drawing only; the money is in `value`.
    var fraction: Double

    var id: PredictionPartKind {
        kind
    }
}

/// The net income of the year ("čistý příjem"), what its income leaves after the levies, as the card Příjmy shows it
/// beside the income: a caption, the average per month as the amount, and under it the sum of the whole year with the
/// part of the income that is. The three texts are read as one.
nonisolated struct PredictionNetIncome: Sendable, Hashable {
    /// What the amount is: "Čistý příjem průměrně za měsíc", and "Čistý příjem průměrně za měsíc (odhad)" for a year in
    /// progress.
    var label: String

    /// The average per month in whole Kč: "189 698 Kč", or "−8 310 Kč" where the levies are more than the income. It
    /// has the sign of an estimate only in a year that is over and that the engine worked out with the rules of
    /// another year, as the levies it comes from have.
    var amount: String

    /// The sum of the whole year that the amount is the average of, and its part of the income: "za celý rok 2 276 375
    /// Kč · 83,0 % příjmů po odvodech". The sum has the sign of an estimate as the amount does. The part is left out
    /// while the income is not above zero, as there is nothing for the levies to take a part of, and is shown as it
    /// is otherwise, even where it is below zero.
    var sub: String
}

// MARK: - The months of the clients

/// What a month of a client holds, which says how its cell is drawn: the colours are the view's.
nonisolated enum PredictionCellKind: Sendable, Hashable {
    /// The month has issued invoices and all of them are paid.
    case paid

    /// The month has issued invoices, and some are not paid yet.
    case waiting

    /// The month has no issued invoice and is over, or the whole year is.
    case past

    /// An invoice is expected in the month, and its money counts in the year.
    case expected

    /// An invoice is expected in the month, but its money is the next year's.
    case expectedNextYear

    /// No invoice is expected in the month.
    case notExpected
}

/// One month of a client's year, as its cell shows it.
nonisolated struct PredictionCell: Identifiable, Sendable, Hashable {
    /// 1 to 12.
    var month: Int

    /// "led" to "pro".
    var label: String

    /// The amount in thousands ("289 tis.") or crowns ("4 500") with the sign of an estimate for an invoice that is
    /// expected, "—" for a month that is over, "?" for an invoice of an unknown amount, and nothing for a month that is
    /// not expected.
    var value: String

    /// "zaplaceno", "čeká", "koncept", "čekám", "→ 2027", "nečekám", or nothing for a month that is over.
    var sub: String
    var kind: PredictionCellKind

    /// Whether a tap changes the month: when it is not over and so can hold an invoice that is expected or not, and the
    /// client is one the app knows (`ClientPrediction.allowsChoices`).
    var isToggle: Bool

    /// Whether an invoice is expected in the month. Only a month that is not over has one.
    var isOn: Bool

    /// What VoiceOver reads: the month with its invoices, or what is expected in it.
    var accessibilityLabel: String

    var id: Int {
        month
    }
}

/// A line of the legend of the cells: what a kind of cell means.
nonisolated struct PredictionLegendItem: Identifiable, Sendable, Hashable {
    var kind: PredictionCellKind
    var text: String

    var id: PredictionCellKind {
        kind
    }
}

/// A client of the months section: how it invoices, what it still adds to the year, a note, and its twelve months.
nonisolated struct PredictionClientRow: Identifiable, Sendable, Hashable {
    /// The client's id, which the model changes the months of.
    var id: Int64
    var name: String

    /// How the client invoices and pays: "měsíčně ≈ 285 693 Kč · platí za ~7 dní".
    var how: String

    /// What the client still adds to the year, "+ 542 386 Kč", or "letos už nic"; for a year that is over what it
    /// brought.
    var adds: String

    /// Whether `adds` is set in the grey of what is nothing.
    var addsIsMuted: Bool

    /// What else is worth saying of the client, or nil.
    var note: String?

    /// Whether the person changed a month of the client, so that the row offers to go back to the app's choice.
    var isEdited: Bool

    /// The twelve months, January first.
    var cells: [PredictionCell]
}

// MARK: - The page

/// Everything the screen shows for a year: the result card, the card Příjmy, the banner, the months of the clients and
/// the two columns of the breakdown. Every text is made, and the screen only lays them out.
nonisolated struct PredictionPage: Sendable, Hashable {
    // The result card.

    /// The levies of the year together as the key figure: the eyebrow "Odhad odvodů za celý rok 2026", or "Odvody za
    /// rok 2025 – skutečnost" for a year that is over, the sum "466 782 Kč", its share of the income "17,0 % z příjmů"
    /// (none while the income is not above zero), and the sentence that says what the sum is made from. In an
    /// estimate that is not complete the figure is "—" and the sentence says that it is not complete.
    var keyFigure: KeyFigureData

    /// The bar of the levies of the year by authority, beside the key figure: its header says "Odvody za celý rok 2026
    /// podle úřadů", it has no total, as the key figure is the total, and the popover of each part has the year's levy,
    /// the advances of the year and what is left to pay or comes back.
    var levyBar: LevyBarData

    /// What is left to settle beyond the year's advances, or what they overpay, as a second key figure under the two
    /// above: its eyebrow, the amount in the display size and a sentence that names the advances in bold.
    var due: KeyFigureData

    // The card Příjmy.

    /// The line under the title of the card: "Odhad za celý rok 2026 z faktur do 17. 10. 2026", or "Rok 2025 ·
    /// skutečnost" for a year that is over.
    var incomeSub: String

    /// The line under the income: "bez DPH · peníze přijaté do 31. 12.".
    var incomeNote: String
    var incomeHead: String

    /// The income of the year: "2 743 157 Kč". It has no sign of an estimate in any year; the head of a year in
    /// progress says "(odhad)".
    var incomeTotal: String

    /// The parts of the income: what was received, and in a year in progress what waits and what is expected.
    var parts: [PredictionPart]

    /// What the income leaves after the levies, beside the income: the average per month and the sum of the whole
    /// year.
    var netIncome: PredictionNetIncome

    /// The sum that is paid only in the next year, or nil when there is none.
    var nextYearNote: String?

    // The banner and the months.

    var banner: String
    var monthsHead: String
    var monthsSub: String
    var legend: [PredictionLegendItem]

    /// The clients that are listed at once, and the others, in a group of their own that is unfolded on request.
    var activeRows: [PredictionClientRow]
    var otherRows: [PredictionClientRow]
    var othersTitle: String
    var othersSub: String

    /// The sentence that no invoice is expected from any client, or nil when it does not apply: when a client is
    /// active, when there is no other client to unfold, and for a year that is over.
    var noActiveText: String?

    // The breakdown.

    /// The cards of the left column: the income and the profit, and the tax.
    var left: [ComputationSection]

    /// The cards of the right column: the social and the health insurance, and under them the net income.
    var right: [ComputationSection]
}

// MARK: - Months

nonisolated extension ClientPrediction {
    /// Whether the person can choose the months of the client. The invoices of no client the app knows
    /// (`unknownID`) are a group on the page, but a choice is stored for a client of the app, and they have none.
    var allowsChoices: Bool {
        id != Self.unknownID
    }
}

nonisolated extension PredictionMonthKind {
    /// Whether the person can change the month: an invoice is expected in it or not, and it is not over and has no
    /// issued invoice.
    var isOpen: Bool {
        switch self {
        case .expected, .expectedNextYear, .notExpected: true
        case .paid, .waiting, .waitingNextYear, .past: false
        }
    }
}
