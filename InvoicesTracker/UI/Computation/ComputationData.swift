import Foundation

// MARK: - The sections

/// A part of the breakdown, a card of the screen.
nonisolated struct ComputationSection: Identifiable, Sendable, Hashable {
    var title: String
    var rows: [BillRow]

    /// The authority the section is about, whose colour marks it. Nil for a section that is about none.
    var authority: Authority?

    /// What stands at the right of the title: the count of the payments, the office the section is paid to, or the
    /// period the card of the net income is about.
    var tag: String?

    /// Whether the section is the card of the net income, which is about no authority and has a colour of its own.
    var isNetIncome = false

    var id: String {
        title
    }

    /// Whether the card stands in the right column of the breakdown, under the insurances: the social and the health
    /// insurance and the net income do. The income and the tax stand in the left one.
    var standsRight: Bool {
        isNetIncome || authority == .social || authority == .health
    }
}

// MARK: - The cards under the result

/// What one authority takes of the next crown, as a part of the bar of the marginal levy.
nonisolated struct MarginalShare: Identifiable, Sendable, Hashable {
    var authority: Authority

    /// The rate of the authority, as the part of the full width of the bar, 0 to 1: a tax of 15 % of the next crown is
    /// 0,15 of the width, so the three parts together fill as much of the bar as the levy total is of a hundred
    /// crowns. It is for drawing only; the money is in the texts.
    var fraction: Double

    var id: Authority {
        authority
    }
}

/// "Mezní odvod": what the three levies together take of the next crown, and what each authority's part of that is.
nonisolated struct ComputationMarginal: Sendable, Hashable {
    /// "37,8 %".
    var total: String

    /// The parts of the bar: tax, social, health. Each one is as wide as the rate of its authority, so the parts
    /// together fill as much of the bar as `total` is of a hundred crowns.
    var shares: [MarginalShare]
    var text: String
}

/// A line of "Hranice roku": a limit, how far the year is from it, and a bar of the way there.
nonisolated struct ThresholdBar: Identifiable, Sendable, Hashable {
    var title: String

    /// "zbývá 118 455", "dosažen 2. 10." or "překročeno".
    var value: String

    /// How full the bar is, 0 to 1. It is for drawing only; the money is in `value`.
    var fraction: Double

    /// The authority whose colour the bar has. Nil for a neutral bar.
    var authority: Authority?

    /// Whether the limit is reached.
    var isReached: Bool

    /// Whether the value is set in green. Only the cap of the expenses is, when it is reached; a band that is exceeded
    /// or a maximum that is reached stays grey.
    var isHighlighted: Bool

    var id: String {
        title
    }
}

/// "Hranice roku": how far the year is from the cap of the flat-rate expenses, the band of 23 % and the maximum of the
/// social insurance base.
nonisolated struct ComputationThresholds: Sendable, Hashable {
    var heading: String
    var bars: [ThresholdBar]
}

/// "Předpoklady výpočtu": what the computation takes for granted.
nonisolated struct ComputationAssumptions: Sendable, Hashable {
    var items: [String]
}

// MARK: - The page

/// Everything the screen shows for a year as of a day: the result, which is the key figure of what is left to pay and
/// the bar of the levies, the cards under it, the note and the sections of the breakdown.
nonisolated struct ComputationPage: Sendable, Hashable {
    /// The year it was built for.
    var year: Int

    /// What the computation counts up to the day shown, in the note under the cards.
    var banner: String
    var sections: [ComputationSection]

    /// "Zbývá zaplatit": what each authority still has to get, added up, and where the sum goes. It stands at the left
    /// of the result card.
    var keyFigure: KeyFigureData

    /// The levies of the three authorities with their total, as Přehled shows them. It stands at the right of the
    /// result card, which has the total here because the key figure beside it is what is left to pay, not the levies.
    var levies: LevyBarData
    var marginal: ComputationMarginal
    var thresholds: ComputationThresholds
    var assumptions: ComputationAssumptions
}
