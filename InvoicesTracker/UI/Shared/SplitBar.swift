import SwiftUI

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

// MARK: - Layout

/// The widths of the parts of the split bar and the middles of its groups, which the view and the popover share.
nonisolated enum SplitBarLayout {
    /// The widths of the parts of `data` in a bar `width` points wide (`LevyBarLayout.partWidths`): a part of no
    /// weight has no width.
    static func widths(of data: SplitBarData, width: CGFloat) -> [CGFloat] {
        LevyBarLayout.partWidths(weights: data.segments.map(\.weight), width: width)
    }

    /// The middle of the group `id` in a bar `width` points wide, in points from the leading edge of the bar: halfway
    /// between the leading edge of its first part and the trailing edge of its last, so a group of three parts is
    /// centred on all three. Parts of no width are left out, unless all of them are so, when the group lies where a
    /// part after it would begin. Nil where no part belongs to the group.
    static func centre(ofGroup id: String, in data: SplitBarData, width: CGFloat) -> CGFloat? {
        let widths = widths(of: data, width: width)
        let centres = LevyBarLayout.partCentres(widths: widths)
        let members = data.segments.indices.filter { data.segments[$0].group == id }
        let drawn = members.filter { widths[$0] > 0 }
        let indices = drawn.isEmpty ? members : drawn
        guard !indices.isEmpty else { return nil }
        let leading = indices.map { centres[$0] - widths[$0] / 2 }.min() ?? 0
        let trailing = indices.map { centres[$0] + widths[$0] / 2 }.max() ?? 0
        return (leading + trailing) / 2
    }
}

// MARK: - Colours

extension SplitBarTone {
    /// The colour of the tone: the grey of DPH, the colour of an authority, or the colour of a budget category.
    var color: Color {
        switch self {
        case .vat: Palette.text4
        case .authority(let authority): authority.color
        case .category(let category):
            switch category {
            case .spending: Palette.green
            case .savings: Palette.greenText
            case .investments: Palette.accent
            case .costs: Palette.text2
            }
        }
    }
}

extension SplitBarGroup {
    /// The colour of the amount in the legend: the red of text below zero, else the colour of text.
    var valueColor: Color {
        valueIsNegative ? Palette.redText : Palette.text
    }
}

// MARK: - The view

/// The sizes and gaps of the split bar that only its view needs.
private nonisolated enum SplitBarMetrics {
    /// The space between two columns of the legend.
    static let legendGap: CGFloat = 16

    /// The space between the name of a group and its value in the legend.
    static let legendLineGap: CGFloat = 2

    /// The size of a dot of the legend.
    static let legendDotSize: CGFloat = 8

    /// The space between the dots, and between the dots and the name, in the legend.
    static let legendDotGap: CGFloat = 4

    /// The size of the dot of the popover.
    static let popoverDotSize: CGFloat = 10

    /// The space between the parts of the popover, and between the dot, the name and the subtitle at its top.
    static let popoverSpacing: CGFloat = 8

    /// The space between the edges of the popover and its content, at the top and the bottom.
    static let popoverVerticalPadding: CGFloat = 12

    /// The space between the edges of the popover and its content, at the sides.
    static let popoverHorizontalPadding: CGFloat = 14

    /// The space between the labels and the values of the rows of the popover.
    static let rowColumnGap: CGFloat = 12

    /// The space between two rows of the popover.
    static let rowGap: CGFloat = 4

    /// How long a part takes to fade, and to come back.
    static let fadeDuration: Double = 0.12
}

/// A bar split into any parts: the header, one bar whose parts are as wide as their weights in the colours of their
/// tones, and a legend of the groups, each with its dots, short name and amount. The pointer over a part or an item of
/// the legend, or the focus of the keyboard on an item, fades the parts of the other groups and shows the popover of
/// the group under the bar, centred on all the parts of the group. Like the levy bar, the popover takes no room and no
/// pointer and is not read; VoiceOver reads the bar as one picture and each item of the legend as its popover. The
/// containers of the view must be drawn over what follows them and must not clip the popover.
struct SplitBarView: View {
    let data: SplitBarData

    /// The id of the group whose part or item of the legend the pointer is over.
    @State private var hovered: String?

    /// The id of the group whose item of the legend has the focus of the keyboard.
    @FocusState private var focused: String?

    /// A bar that shows `data`.
    init(_ data: SplitBarData) {
        self.init(data, showing: nil)
    }

    /// A bar that shows `data` with the popover of the group `id` open, as while the pointer is over it, or with none
    /// for nil. It is for previews and tests, which cannot move the pointer.
    init(_ data: SplitBarData, showing id: String?) {
        self.data = data
        _hovered = State(initialValue: id)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DesignMetrics.innerSpacing) {
            Text(verbatim: data.header)
                .font(Typography.bodySemibold)
                .foregroundStyle(Palette.text)
                .fixedSize(horizontal: false, vertical: true)
            bar
            legend
        }
        .overlay(alignment: .topLeading) {
            popover
        }
        .zIndex(1)
    }

    /// The group whose popover shows: the one under the pointer, or else the one whose item has the focus.
    private var active: String? {
        hovered ?? focused
    }

    // MARK: Bar

    /// The bar: the parts with a width in the colours of their tones, or the empty track where none has one. The
    /// parts of the other groups fade while a popover shows.
    private var bar: some View {
        GeometryReader { proxy in
            let widths = SplitBarLayout.widths(of: data, width: proxy.size.width)
            if widths.allSatisfy({ $0 <= 0 }) {
                RoundedRectangle(cornerRadius: LevyBarLayout.partRadius)
                    .fill(Palette.fill)
            } else {
                HStack(spacing: LevyBarLayout.partGap) {
                    ForEach(data.segments.indices.filter { widths[$0] > 0 }, id: \.self) { index in
                        let segment = data.segments[index]
                        RoundedRectangle(cornerRadius: LevyBarLayout.partRadius)
                            .fill(segment.tone.color)
                            .frame(width: widths[index])
                            .opacity(opacity(ofGroup: segment.group))
                            .onHover { inside in
                                hover(segment.group, inside: inside)
                            }
                    }
                }
                .animation(.easeInOut(duration: SplitBarMetrics.fadeDuration), value: active)
            }
        }
        .frame(height: LevyBarLayout.barHeight)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(data.accessibilityLabel)
        .accessibilityAddTraits(.isImage)
    }

    /// The opacity of the parts of group `id`: full while no popover shows or while it is the group's own.
    private func opacity(ofGroup id: String) -> Double {
        active == nil || active == id ? 1 : LevyBarLayout.dimmedOpacity
    }

    // MARK: Legend

    /// The legend: a column of one width for each group.
    private var legend: some View {
        HStack(alignment: .top, spacing: SplitBarMetrics.legendGap) {
            ForEach(data.groups) { group in
                legendItem(group)
            }
        }
    }

    /// The item of `group`: its dots and short name in callout and secondary text, and its amount under them in body
    /// semibold, never cut, and in the red of text where it is below zero.
    private func legendItem(_ group: SplitBarGroup) -> some View {
        VStack(alignment: .leading, spacing: SplitBarMetrics.legendLineGap) {
            HStack(spacing: SplitBarMetrics.legendDotGap) {
                ForEach(group.dots.indices, id: \.self) { index in
                    Circle()
                        .fill(group.dots[index].color)
                        .frame(width: SplitBarMetrics.legendDotSize, height: SplitBarMetrics.legendDotSize)
                }
                Text(verbatim: group.shortTitle)
                    .font(Typography.callout)
                    .foregroundStyle(Palette.text2)
            }
            Text(verbatim: group.value)
                .font(Typography.bodySemibold)
                .monospacedDigit()
                .foregroundStyle(group.valueColor)
                .fixedSize()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .onHover { inside in
            hover(group.id, inside: inside)
        }
        .focusable(interactions: .activate)
        .focused($focused, equals: group.id)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(group.accessibilityLabel)
    }

    /// Notes that the pointer has come over the group `id` or left it. Leaving one that is no longer the one under
    /// the pointer changes nothing, as the pointer can come over the next one before it leaves the last.
    private func hover(_ id: String, inside: Bool) {
        if inside {
            hovered = id
        } else if hovered == id {
            hovered = nil
        }
    }

    // MARK: Popover

    /// The popover of the active group, `LevyBarLayout.popoverGap` points under the view, centred on the group and
    /// held inside the view. It takes no room and no pointer, and VoiceOver does not read it.
    private var popover: some View {
        GeometryReader { proxy in
            if let id = active, let group = data.groups.first(where: { $0.id == id }),
                let centre = SplitBarLayout.centre(ofGroup: id, in: data, width: proxy.size.width)
            {
                SplitBarPopoverView(popover: group.popover)
                    .offset(
                        x: LevyBarLayout.popoverX(centredOn: centre, panelWidth: proxy.size.width),
                        y: proxy.size.height + LevyBarLayout.popoverGap)
                    .zIndex(1)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// The popover of a group of the split bar: the dot, the name in bold and the subtitle in callout and tertiary text,
/// then the rows in two columns, and the note under them. A panel 260 points wide on the colour of a card, raised off
/// the page, as the popover of the levy bar is.
private struct SplitBarPopoverView: View {
    let popover: SplitBarPopover

    var body: some View {
        VStack(alignment: .leading, spacing: SplitBarMetrics.popoverSpacing) {
            HStack(spacing: SplitBarMetrics.popoverSpacing) {
                Circle()
                    .fill(popover.tone.color)
                    .frame(width: SplitBarMetrics.popoverDotSize, height: SplitBarMetrics.popoverDotSize)
                Text(verbatim: popover.title)
                    .font(Typography.bodyBold)
                    .foregroundStyle(Palette.text)
                Spacer(minLength: SplitBarMetrics.popoverSpacing)
                Text(verbatim: popover.subtitle)
                    .font(Typography.callout)
                    .foregroundStyle(Palette.text3)
            }
            // A label that a long value leaves too little room wraps, and the value stands on its first line.
            Grid(
                alignment: .leadingFirstTextBaseline, horizontalSpacing: SplitBarMetrics.rowColumnGap,
                verticalSpacing: SplitBarMetrics.rowGap
            ) {
                ForEach(popover.rows.indices, id: \.self) { index in
                    let row = popover.rows[index]
                    GridRow {
                        Text(verbatim: row.label)
                            .font(Typography.body)
                            .foregroundStyle(Palette.text2)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Text(verbatim: row.value)
                            .font(row.style.font)
                            .monospacedDigit()
                            .foregroundStyle(row.style.color)
                            .fixedSize()
                            .gridColumnAlignment(.trailing)
                    }
                }
            }
            if let note = popover.note {
                Text(verbatim: note)
                    .font(Typography.callout)
                    .foregroundStyle(Palette.text3)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, SplitBarMetrics.popoverVerticalPadding)
        .padding(.horizontal, SplitBarMetrics.popoverHorizontalPadding)
        .frame(width: LevyBarLayout.popoverWidth, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: DesignMetrics.panelRadius)
                .surface(Palette.bgCard, elevation: .pop)
        }
    }
}
