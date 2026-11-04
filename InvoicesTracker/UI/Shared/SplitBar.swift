import Foundation

// MARK: - What the bar shows

/// What a part of the split bar, a dot of its legend or its popover is coloured as. The builder names the part; the
/// view picks its colour: the grey of DPH, the colour of an authority, or the colour of a budget category.
nonisolated enum SplitBarTone: Hashable, Sendable {
    /// The DPH of an invoice.
    case vat

    /// The levy of one authority.
    case authority(Authority)

    /// One of the four parts of a budget.
    case category(BudgetCategory)
}

/// One part of the split bar, drawn as wide as its weight in proportion to the others.
nonisolated struct SplitBarSegment: Hashable, Sendable {
    /// The id of the group of the legend that the part belongs to (`SplitBarGroup.id`), which hovering it brings out.
    var group: String

    /// What the part is coloured as.
    var tone: SplitBarTone

    /// The amount of the part in whole Kč. A part of nothing or less draws no width.
    var weight: Int64
}

/// An item of the legend of the split bar: its dots, its short name and its amount, with the popover it opens and what
/// VoiceOver reads for it. A group can stand for several parts, as "Odvody" stands for the three authorities.
nonisolated struct SplitBarGroup: Identifiable, Hashable, Sendable {
    /// What identifies the group among those of the bar, such as "vat", "levies" or the raw value of a category.
    var id: String

    /// The dots in front of the short name, one for each part of the group.
    var dots: [SplitBarTone]

    /// The short name, such as "DPH", "Odvody" or "Útrata".
    var shortTitle: String

    /// The amount as the legend shows it, such as "1 058 Kč", or "—" while there is nothing to divide.
    var value: String

    /// Whether the amount is below zero, so the legend sets it in the red of text.
    var valueIsNegative: Bool

    /// What hovering or focusing the group shows.
    var popover: SplitBarPopover

    /// What VoiceOver reads for the item of the legend: its name and what it holds, then the rows of its popover.
    var accessibilityLabel: String
}

/// The popover of a group of the split bar: a dot and the name over a line that says what it is, the rows of its
/// figures, and a note under them.
nonisolated struct SplitBarPopover: Hashable, Sendable {
    /// The name of the group, such as "Daně a odvody".
    var title: String

    /// What the group is or how it is held, such as "spočítá aplikace" or "pevná částka".
    var subtitle: String

    /// The colour of the dot beside the name.
    var tone: SplitBarTone

    /// The rows of figures, in the order they are shown.
    var rows: [LevyPopoverRow]

    /// The note under the rows, or nil for none.
    var note: String?
}

/// What the split bar shows: the header over it, its parts in order, the items of its legend, and what VoiceOver reads
/// for the whole bar. The texts are the builder's; the view only shows them.
nonisolated struct SplitBarData: Hashable, Sendable {
    /// The header over the bar, such as "Rozdělení za měsíc".
    var header: String

    /// The parts of the bar, in the order they are drawn.
    var segments: [SplitBarSegment]

    /// The items of the legend, in the order of the parts they stand for.
    var groups: [SplitBarGroup]

    /// What VoiceOver reads for the bar: the header, then each group with its amount.
    var accessibilityLabel: String
}
