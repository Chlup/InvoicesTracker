import SwiftUI

// MARK: - What the bar shows

/// How the value of a row of the popover of the levy bar is set.
nonisolated enum LevyRowStyle: Sendable, Hashable {
    /// Semibold, in the colour of text: the levy, and what is left to pay of it.
    case strong

    /// Regular, in the grey of secondary text: the advances.
    case muted

    /// Semibold, in the green of text: money that comes back, an overpayment or a tax bonus.
    case positive
}

/// A row of the popover of a part of the levy bar: a label in secondary text and a value at the trailing edge, such as
/// "Zbývá" and "71 440 Kč".
nonisolated struct LevyPopoverRow: Sendable, Hashable {
    /// What the value is, such as "Zaplaceno zálohami".
    var label: String

    /// The value as it is shown, such as "23 000 Kč".
    var value: String

    /// How the value is set.
    var style: LevyRowStyle
}

/// The part of one authority in the levy bar: how wide it is drawn, what the legend says of it, what its popover shows
/// and what VoiceOver reads for it. The texts are the builder's; the view only shows them.
nonisolated struct LevyBarPart: Sendable, Hashable, Identifiable {
    /// The authority of the part, whose colour and names it has.
    var authority: Authority

    /// The levy in whole Kč, which the width of the part is in proportion to. A levy of nothing or less, such as a tax
    /// bonus, draws no part (`LevyBarLayout.partWidths`).
    var weight: Int64

    /// The levy as the legend shows it under the short name of the authority: "94 440 Kč", "bonus 37 524 Kč" or "—".
    var legendValue: String

    /// The rows of the popover, in the order they are shown.
    var rows: [LevyPopoverRow]

    /// The share of the income that the levy takes, under the rows of the popover, such as "4,3 % z příjmů bez DPH",
    /// or nil for none.
    var shareLine: String?

    /// A note under the rows of the popover, such as the condition the Simulátor names for an insurance, or nil for
    /// none.
    var note: String?

    /// What VoiceOver reads for the item of the legend: the full name of the authority with the rows of the popover,
    /// its share line and its note, such as "Daň z příjmů: odvody z příjmů 94 440 Kč, zaplaceno zálohami 23 000 Kč,
    /// zbývá 71 440 Kč, 4,3 % z příjmů bez DPH" (`LevyBarBuilder.accessibilityLabel(of:rows:shareLine:note:)`).
    var accessibilityLabel: String

    /// A bar has one part of each authority, so the authority identifies the part.
    var id: Authority {
        authority
    }
}

/// What the levy bar shows: the header that says what the bar is of, the total of the levies with its share of the
/// income where the key figure beside the bar does not show it, and the parts of the three authorities. The texts are
/// the builder's; the view only shows them.
nonisolated struct LevyBarData: Sendable, Hashable {
    /// What the bar shows, such as "Odvody z příjmů do 17. 10.".
    var header: String

    /// The three levies together, such as "320 664 Kč", or nil where the bar shows no total.
    var total: String?

    /// The share of the income that the three levies take, such as "14,6 % z příjmů", or nil for none.
    var totalShare: String?

    /// The parts of the tax, the social insurance and the health insurance, in that order.
    var parts: [LevyBarPart]

    /// What VoiceOver reads for the bar: the header and the full name of each authority with its value in the legend,
    /// such as "Odvody z příjmů do 17. 10.: Daň z příjmů 94 440 Kč, Sociální pojištění 159 279 Kč, Zdravotní pojištění
    /// 66 945 Kč" (`LevyBarBuilder.accessibilityLabel(header:parts:)`).
    var accessibilityLabel: String
}

// MARK: - Layout

/// The sizes of the levy bar, and the rules that share its width among the parts and place the popover of a part.
nonisolated enum LevyBarLayout {
    /// The height of the bar.
    static let barHeight: CGFloat = 16

    /// The corner radius of a part, and of the empty track.
    static let partRadius: CGFloat = 4

    /// The space between two parts that are drawn.
    static let partGap: CGFloat = 2

    /// The least width of a part that is drawn, so that a small levy still shows.
    static let minimumPartWidth: CGFloat = 4

    /// The width of the popover.
    static let popoverWidth: CGFloat = 260

    /// The space between the bottom of the panel and the popover under it.
    static let popoverGap: CGFloat = 8

    /// The opacity of the parts other than the one whose popover is shown.
    static let dimmedOpacity: Double = 0.35

    /// The widths of the parts of `weights` in a bar `width` points wide. The parts of the weights above zero are
    /// drawn, with `gap` points between them: they share the room the gaps leave in proportion to their weights, each
    /// at least `minimum` points wide, a part held at the least width taking its points from the others. A weight of
    /// zero or less, such as a tax bonus, gets no width and no gap, and where every weight is so, every width is zero.
    /// Where the room cannot give every part that is drawn its least width, they share it equally. The widths of the
    /// parts that are drawn and their gaps add up to `width`.
    static func partWidths(
        weights: [Int64], width: CGFloat, gap: CGFloat = LevyBarLayout.partGap,
        minimum: CGFloat = LevyBarLayout.minimumPartWidth
    ) -> [CGFloat] {
        var widths = [CGFloat](repeating: 0, count: weights.count)
        let drawn = weights.indices.filter { weights[$0] > 0 }
        guard !drawn.isEmpty else { return widths }
        let room = max(0, width - gap * CGFloat(drawn.count - 1))
        guard room > minimum * CGFloat(drawn.count) else {
            for index in drawn {
                widths[index] = room / CGFloat(drawn.count)
            }
            return widths
        }
        // Each pass holds the parts that their proportion would make narrower than the least width at that width, and
        // shares what is left among the others, until none of them is too narrow. A part held never comes free again,
        // and every pass holds one more part or ends, so there are at most as many passes as parts.
        var held: Set<Int> = []
        while true {
            let free = drawn.filter { !held.contains($0) }
            let freeRoom = room - minimum * CGFloat(held.count)
            let freeWeight = CGFloat(free.reduce(Int64(0)) { $0 + weights[$1] })
            let tooNarrow = free.filter { freeRoom * CGFloat(weights[$0]) / freeWeight < minimum }
            guard tooNarrow.isEmpty else {
                held.formUnion(tooNarrow)
                continue
            }
            for index in free {
                widths[index] = freeRoom * CGFloat(weights[index]) / freeWeight
            }
            for index in held {
                widths[index] = minimum
            }
            return widths
        }
    }

    /// The middle of each part of `widths` (`partWidths`), in points from the leading edge of the bar, with `gap`
    /// points between the parts that are drawn. A part of no width lies where a part after it would begin.
    static func partCentres(widths: [CGFloat], gap: CGFloat = LevyBarLayout.partGap) -> [CGFloat] {
        var start: CGFloat = 0
        return widths.map { width in
            guard width > 0 else { return start }
            let centre = start + width / 2
            start += width + gap
            return centre
        }
    }

    /// The leading edge of the popover of the part whose middle is at `centre`, in points from the leading edge of a
    /// panel `panelWidth` points wide: the popover, `popoverWidth` points wide, is centred on its part, but held inside
    /// the panel, and at its leading edge where the panel is narrower than the popover.
    static func popoverX(
        centredOn centre: CGFloat, panelWidth: CGFloat, popoverWidth: CGFloat = LevyBarLayout.popoverWidth
    ) -> CGFloat {
        max(0, min(centre - popoverWidth / 2, panelWidth - popoverWidth))
    }
}

// MARK: - The view

extension LevyRowStyle {
    /// The font of a value of this style: semibold for the levy, what is left of it and what comes back, the body for
    /// the advances.
    var font: Font {
        switch self {
        case .strong, .positive: Typography.bodySemibold
        case .muted: Typography.body
        }
    }

    /// The colour of a value of this style: the colour of text, the grey of secondary text, or the green of text.
    var color: Color {
        switch self {
        case .strong: Palette.text
        case .muted: Palette.text2
        case .positive: Palette.greenText
        }
    }
}

/// The sizes and gaps of the levy bar that only its view needs.
private nonisolated enum LevyBarMetrics {
    /// The least space between the header and the total at the end of its line.
    static let headerGap: CGFloat = 16

    /// The space between the header and the total where the total has gone under it.
    static let headerLineGap: CGFloat = 4

    /// The space between the total and its share.
    static let totalShareGap: CGFloat = 8

    /// The space between two columns of the legend.
    static let legendGap: CGFloat = 16

    /// The space between the name of an authority and its value in the legend.
    static let legendLineGap: CGFloat = 2

    /// The size of the dot of an authority in the legend.
    static let legendDotSize: CGFloat = 8

    /// The space between the dot and the name in the legend.
    static let legendDotGap: CGFloat = 6

    /// The size of the dot of the authority in the popover.
    static let popoverDotSize: CGFloat = 10

    /// The space between the parts of the popover, and between the dot, the name and the office at its top.
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

/// The bar of the levies ("Pruh odvodů"), at the right of the result card of Přehled, Výpočet, Odhad odvodů and the
/// Simulátor: the header with the total and its share at the end of its line, one bar split into the levies of the
/// three authorities in their colours, each part as wide as its levy, and a legend of three equal columns with the
/// short name and the value of each. The advances and what is left to pay are only in the popover of a part, which
/// shows while the pointer is over the part or its item of the legend, or while that item has the focus of the
/// keyboard (with keyboard navigation, as a button has it); the other parts then fade.
///
/// The popover hangs under the frame of the view, 8 points below it, and makes the view no taller. It is drawn over
/// what follows the view in the stack the view is in, but a container of the view must itself be drawn over what
/// follows it (a higher `zIndex`), and must not clip it, for the popover to show whole over the content under it. It
/// does not take the pointer, and VoiceOver does not read it: each item of the legend reads what its popover shows.
/// VoiceOver reads the bar as one picture named by its three parts.
struct LevyBarView: View {
    let data: LevyBarData

    /// The authority whose part or item of the legend the pointer is over.
    @State private var hovered: Authority?

    /// The authority whose item of the legend has the focus of the keyboard.
    @FocusState private var focused: Authority?

    /// A bar that shows `data`.
    init(_ data: LevyBarData) {
        self.init(data, showing: nil)
    }

    /// A bar that shows `data` with the popover of `authority` open and the other parts faded, as they are while the
    /// pointer is over the part of `authority`, or with no popover for nil. It is for previews and tests, which cannot
    /// move the pointer; the pointer and the focus then change the bar as they change any other.
    init(_ data: LevyBarData, showing authority: Authority?) {
        self.data = data
        _hovered = State(initialValue: authority)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DesignMetrics.innerSpacing) {
            header
            bar
            legend
        }
        .overlay(alignment: .topLeading) {
            popover
        }
        .zIndex(1)
    }

    /// The authority whose popover shows and whose part keeps its colour: the one under the pointer, or else the one
    /// whose item of the legend has the focus. Nil while there is neither.
    private var active: Authority? {
        hovered ?? focused
    }

    // MARK: Header

    /// The header, with the total and its share on its baseline at the end of its line, or under it where the two do
    /// not fit one line.
    @ViewBuilder
    private var header: some View {
        if let total = data.total {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .firstTextBaseline, spacing: 0) {
                    headerText
                    Spacer(minLength: LevyBarMetrics.headerGap)
                    totalLine(total)
                }
                VStack(alignment: .leading, spacing: LevyBarMetrics.headerLineGap) {
                    headerText
                    totalLine(total)
                }
            }
        } else {
            headerText
        }
    }

    /// What the bar shows, in body semibold.
    private var headerText: some View {
        Text(verbatim: data.header)
            .font(Typography.bodySemibold)
            .foregroundStyle(Palette.text)
            .fixedSize(horizontal: false, vertical: true)
    }

    /// The total in the title style, with its share beside it in body semibold and secondary text, on one baseline.
    /// Neither is ever cut, as an amount cut short would read as a smaller one.
    private func totalLine(_ total: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: LevyBarMetrics.totalShareGap) {
            Text(verbatim: total)
                .font(Typography.title)
                .monospacedDigit()
                .foregroundStyle(Palette.text)
            if let share = data.totalShare {
                Text(verbatim: share)
                    .font(Typography.bodySemibold)
                    .monospacedDigit()
                    .foregroundStyle(Palette.text2)
            }
        }
        .fixedSize()
    }

    // MARK: Bar

    /// The bar: the parts of the levies above zero in the colours of their authorities, each as wide as its levy
    /// (`LevyBarLayout.partWidths`), or the empty track where no levy is above zero. While a popover shows, the other
    /// parts fade.
    private var bar: some View {
        GeometryReader { proxy in
            if data.parts.allSatisfy({ $0.weight <= 0 }) {
                RoundedRectangle(cornerRadius: LevyBarLayout.partRadius)
                    .fill(Palette.fill)
            } else {
                let widths = LevyBarLayout.partWidths(weights: data.parts.map(\.weight), width: proxy.size.width)
                HStack(spacing: LevyBarLayout.partGap) {
                    ForEach(data.parts.indices.filter { widths[$0] > 0 }, id: \.self) { index in
                        let authority = data.parts[index].authority
                        RoundedRectangle(cornerRadius: LevyBarLayout.partRadius)
                            .fill(authority.color)
                            .frame(width: widths[index])
                            .opacity(opacity(of: authority))
                            .onHover { inside in
                                hover(authority, inside: inside)
                            }
                    }
                }
                .animation(.easeInOut(duration: LevyBarMetrics.fadeDuration), value: active)
            }
        }
        .frame(height: LevyBarLayout.barHeight)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(data.accessibilityLabel)
        .accessibilityAddTraits(.isImage)
    }

    /// The opacity of the part of `authority`: full while no popover shows or while the popover is its own, faded
    /// while another part's is.
    private func opacity(of authority: Authority) -> Double {
        active == nil || active == authority ? 1 : LevyBarLayout.dimmedOpacity
    }

    // MARK: Legend

    /// The legend: a column of one width for each authority, with its dot, its short name and its value. VoiceOver
    /// reads each item as what its popover shows.
    private var legend: some View {
        HStack(alignment: .top, spacing: LevyBarMetrics.legendGap) {
            ForEach(data.parts) { part in
                legendItem(part)
            }
        }
    }

    /// The item of `part` in the legend: the dot and the short name in callout and secondary text, and the value under
    /// them in body semibold, which is never cut. The pointer over the item, or the focus on it, shows the popover of
    /// the part.
    private func legendItem(_ part: LevyBarPart) -> some View {
        VStack(alignment: .leading, spacing: LevyBarMetrics.legendLineGap) {
            HStack(spacing: LevyBarMetrics.legendDotGap) {
                Circle()
                    .fill(part.authority.color)
                    .frame(width: LevyBarMetrics.legendDotSize, height: LevyBarMetrics.legendDotSize)
                Text(verbatim: part.authority.shortTitle)
                    .font(Typography.callout)
                    .foregroundStyle(Palette.text2)
            }
            Text(verbatim: part.legendValue)
                .font(Typography.bodySemibold)
                .monospacedDigit()
                .foregroundStyle(Palette.text)
                .fixedSize()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .onHover { inside in
            hover(part.authority, inside: inside)
        }
        .focusable(interactions: .activate)
        .focused($focused, equals: part.authority)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(part.accessibilityLabel)
    }

    /// Notes that the pointer has come over the part or the item of the legend of `authority`, or has left it. Leaving
    /// one that is no longer the one under the pointer changes nothing, as the pointer can come over the next one
    /// before it leaves the last.
    private func hover(_ authority: Authority, inside: Bool) {
        if inside {
            hovered = authority
        } else if hovered == authority {
            hovered = nil
        }
    }

    // MARK: Popover

    /// The popover of the active part, `LevyBarLayout.popoverGap` points under the panel, centred on its part and held
    /// inside the panel (`LevyBarLayout.popoverX`). It takes no room and does not take the pointer, and VoiceOver does
    /// not read it.
    private var popover: some View {
        GeometryReader { proxy in
            if let index = data.parts.firstIndex(where: { $0.authority == active }) {
                let widths = LevyBarLayout.partWidths(weights: data.parts.map(\.weight), width: proxy.size.width)
                let centre = LevyBarLayout.partCentres(widths: widths)[index]
                LevyPopover(part: data.parts[index])
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

/// The popover of a part of the levy bar: at its top the dot, the full name of the authority in bold and its office in
/// callout and tertiary text, then the rows in two columns, the labels in secondary text and the values at the trailing
/// edge in their style, and last the share line and the note in callout and tertiary text. It is a panel 260 points
/// wide on the colour of a card, raised off the page as a popover is.
private struct LevyPopover: View {
    let part: LevyBarPart

    var body: some View {
        VStack(alignment: .leading, spacing: LevyBarMetrics.popoverSpacing) {
            HStack(spacing: LevyBarMetrics.popoverSpacing) {
                Circle()
                    .fill(part.authority.color)
                    .frame(width: LevyBarMetrics.popoverDotSize, height: LevyBarMetrics.popoverDotSize)
                Text(verbatim: part.authority.title)
                    .font(Typography.bodyBold)
                    .foregroundStyle(Palette.text)
                Spacer(minLength: LevyBarMetrics.popoverSpacing)
                Text(verbatim: part.authority.office)
                    .font(Typography.callout)
                    .foregroundStyle(Palette.text3)
            }
            // A label that a long value leaves too little room wraps, and the value stands on its first line.
            Grid(
                alignment: .leadingFirstTextBaseline, horizontalSpacing: LevyBarMetrics.rowColumnGap,
                verticalSpacing: LevyBarMetrics.rowGap
            ) {
                ForEach(part.rows.indices, id: \.self) { index in
                    let row = part.rows[index]
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
            if let shareLine = part.shareLine {
                footnote(shareLine)
            }
            if let note = part.note {
                footnote(note)
            }
        }
        .padding(.vertical, LevyBarMetrics.popoverVerticalPadding)
        .padding(.horizontal, LevyBarMetrics.popoverHorizontalPadding)
        .frame(width: LevyBarLayout.popoverWidth, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: DesignMetrics.panelRadius)
                .surface(Palette.bgCard, elevation: .pop)
        }
    }

    /// A line under the rows, the share line or the note, in callout and tertiary text, which wraps in the popover.
    private func footnote(_ text: String) -> some View {
        Text(verbatim: text)
            .font(Typography.callout)
            .foregroundStyle(Palette.text3)
            .fixedSize(horizontal: false, vertical: true)
    }
}
