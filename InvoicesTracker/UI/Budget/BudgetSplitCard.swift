import SwiftUI

/// The sizes and gaps of the card Rozdělení of Rozpočet and of its rows, in points.
private nonisolated enum BudgetSplitMetrics {
    /// The space between the header of the card and the first row under it.
    static let headerBottom: CGFloat = 14

    /// The space between the title and its subtitle.
    static let titleSpacing: CGFloat = 2

    /// The least space between the subtitle and the choice of the remainder.
    static let headerSpacing: CGFloat = 16

    /// The space between "Zbytek dostane" and its segmented control.
    static let remainderLabelGap: CGFloat = 10

    /// The space above and below the content of the row of a category.
    static let rowPadding: CGFloat = 12

    /// The space between the line of the controls of a row and the hint under it.
    static let hintGap: CGFloat = 6

    /// The space between the columns of a row.
    static let columnGap: CGFloat = 16

    /// The space between the lines of a row where the slider goes under the rest.
    static let lineGap: CGFloat = 8

    /// The width the name of a row grows from, by a quarter of what is left of the row.
    static let nameBasis: CGFloat = 170

    /// The width the slider of a row grows from, by three quarters of what is left of the row.
    static let sliderBasis: CGFloat = 220

    /// The narrowest the name becomes before the slider goes under the rest of the row.
    static let nameMinimumWidth: CGFloat = 120

    /// The narrowest the slider becomes.
    static let sliderMinimumWidth: CGFloat = 160

    /// The width of the column of the share.
    static let percentColumnWidth: CGFloat = 84

    /// The width of the column of the amount.
    static let amountColumnWidth: CGFloat = 146

    /// The width of the last column, with the checkbox or the pill.
    static let lastColumnWidth: CGFloat = 116

    /// The width of the field of the share.
    static let percentFieldWidth: CGFloat = 60

    /// The width of the field of the amount.
    static let amountFieldWidth: CGFloat = 106

    /// The space between a field and its unit.
    static let unitGap: CGFloat = 4

    /// The space between the amount and the year under it.
    static let yearGap: CGFloat = 2

    /// The space at the right of the amount of the remainder and of the year, which lines them up with the fields.
    static let amountInset: CGFloat = 2

    /// The size of the dot of a category.
    static let dotSize: CGFloat = 10

    /// The space between the dot of a category and its name.
    static let dotGap: CGFloat = 8

    /// How far the purpose of a category stands in, so that it starts under the name.
    static let purposeIndent: CGFloat = 18

    /// The space between the name of a category and its purpose.
    static let purposeGap: CGFloat = 1

    /// The space between the lock, the label and the note of a row of the bill that the app works out, and between
    /// the share and the amount at its right.
    static let lockGap: CGFloat = 8
}

/// The card Rozdělení: the title "Rozdělení" with the line under it and, at the right, "Zbytek dostane" with the
/// segmented control of the category that gets what the others leave; in Faktura mode the bill of the invoice; and a
/// row for each category, in the order Náklady, Útrata, Úspory, Investice, each under a hairline. The card is padded
/// 20 points, and the last row has no space of its own under it, so that its content ends 20 points above the edge, as
/// it would with the 12 of a row and the 8 of the foot of the design.
///
/// A field of a row that is typed into sets `editedCategory` to its category, whose editing the screen ends when the
/// field is left. VoiceOver reads the card as a group under "Rozdělení".
struct BudgetSplitCard: View {
    let data: BudgetData
    let model: BudgetModel
    @Binding var editedCategory: BudgetCategory?

    var body: some View {
        Card(spacing: 0, label: "Rozdělení") {
            header
                .padding(.bottom, BudgetSplitMetrics.headerBottom)
            ForEach(data.billRows, id: \.label) { row in
                BudgetBillRuleView(isResult: row.isResult)
                BudgetBillRowView(row: row)
            }
            ForEach(data.rows) { row in
                Hairline()
                BudgetCategoryRowView(row: row, model: model, editedCategory: $editedCategory)
                    .padding(.top, BudgetSplitMetrics.rowPadding)
                    .padding(.bottom, row.id == data.rows.last?.id ? 0 : BudgetSplitMetrics.rowPadding)
            }
        }
    }

    /// The title with the line under it, and "Zbytek dostane" with its segmented control at the end of the line of the
    /// title. "Zbytek dostane" is the name VoiceOver reads the control under, so its words are not read twice.
    private var header: some View {
        HStack(alignment: .center, spacing: BudgetSplitMetrics.headerSpacing) {
            VStack(alignment: .leading, spacing: BudgetSplitMetrics.titleSpacing) {
                CardTitle(text: "Rozdělení")
                Text(verbatim: data.cardSubtitle)
                    .font(Typography.callout)
                    .foregroundStyle(Palette.text2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            HStack(spacing: BudgetSplitMetrics.remainderLabelGap) {
                Text("Zbytek dostane")
                    .font(Typography.callout)
                    .foregroundStyle(Palette.text2)
                    .accessibilityHidden(true)
                SegmentedControl(
                    "Zbytek dostane",
                    selection: Binding(get: { data.remainder }, set: { model.chooseRemainder($0) }),
                    segments: data.remainderChoices.map { (value: $0, title: $0.title) })
            }
            .fixedSize()
        }
    }
}

// MARK: - The bill

/// The line above a row of the bill: the heavy one in the colour of text above the result, as above the total of a
/// bill of Výpočet, and the hairline above the other rows.
private struct BudgetBillRuleView: View {
    let isResult: Bool

    var body: some View {
        if isResult {
            Rectangle()
                .fill(Palette.text)
                .frame(height: BillMetrics.totalRuleHeight)
                .accessibilityHidden(true)
        } else {
            Hairline()
        }
    }
}

/// A row of the bill of the invoice in Faktura mode, as a row of a bill of Výpočet: the operator, the label with its
/// note under it, and the amount at the right with the share of the income before it where there is one. A row that
/// the app works out carries a lock and "spočítá aplikace, nejde měnit" after its label. The result, "= Čistý příjem k
/// rozdělení", is in bold, its amount in title 2, with its operator in the colour of text and more space under it.
/// VoiceOver reads each row as one phrase: the label, the amount and its share, that the app works it out, and the
/// note.
private struct BudgetBillRowView: View {
    let row: BudgetBillRow

    /// What a row that the app works out says after its label.
    static let lockText = "spočítá aplikace, nejde měnit"

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: BillMetrics.columnSpacing) {
            sign
            VStack(alignment: .leading, spacing: BillMetrics.noteSpacing) {
                label
                if let note = row.note {
                    Text(verbatim: note)
                        .font(Typography.callout)
                        .foregroundStyle(Palette.text3)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            HStack(alignment: .firstTextBaseline, spacing: BudgetSplitMetrics.lockGap) {
                if let share = row.share {
                    Text(verbatim: share)
                        .font(Typography.callout)
                        .monospacedDigit()
                        .foregroundStyle(Palette.text2)
                }
                Text(verbatim: row.value)
                    .font(row.isResult ? Typography.title2 : Typography.bodySemibold)
                    .monospacedDigit()
                    .foregroundStyle(Palette.text)
            }
            .fixedSize()
        }
        .padding(.top, BillMetrics.rowPadding)
        .padding(.bottom, row.isResult ? BillMetrics.footPadding : BillMetrics.rowPadding)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spokenText)
    }

    /// The operator, in a column of its own: in bold, in tertiary text, and in the colour of text on the result. The
    /// first row has none, and its column stays empty.
    @ViewBuilder
    private var sign: some View {
        if row.sign.isEmpty {
            Color.clear
                .frame(width: BillMetrics.signWidth, height: 0)
        } else {
            Text(verbatim: row.sign)
                .font(Typography.bodyBold)
                .foregroundStyle(row.isResult ? Palette.text : Palette.text3)
                .frame(width: BillMetrics.signWidth)
        }
    }

    /// The label: with the lock before it and "spočítá aplikace, nejde měnit" after it where the app works the amount
    /// out, and in bold on the result.
    @ViewBuilder
    private var label: some View {
        if row.isLocked {
            HStack(alignment: .firstTextBaseline, spacing: BudgetSplitMetrics.lockGap) {
                Image(systemName: "lock")
                    .font(Typography.callout)
                    .foregroundStyle(Palette.text3)
                Text(verbatim: row.label)
                    .font(Typography.body)
                    .foregroundStyle(Palette.text)
                Text(verbatim: Self.lockText)
                    .font(Typography.callout)
                    .foregroundStyle(Palette.text3)
                    .fixedSize(horizontal: false, vertical: true)
            }
        } else {
            Text(verbatim: row.label)
                .font(row.isResult ? Typography.bodyBold : Typography.body)
                .foregroundStyle(Palette.text)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// What VoiceOver reads for the row: "Daně a odvody: −1 130 Kč (25,1 % z faktury), spočítá aplikace, nejde
    /// měnit. daň 0 · sociální 640 · zdravotní 490". The operator is only for the eyes; the amount carries its sign.
    private var spokenText: String {
        var spoken = row.label + ": " + row.value
        if let share = row.share {
            spoken += " (" + share + ")"
        }
        if row.isLocked {
            spoken += ", " + Self.lockText
        }
        if let note = row.note {
            spoken += ". " + note
        }
        return spoken
    }
}

// MARK: - The rows of the categories

/// The row of a category: the dot in its colour with its name in headline and its purpose under it, the slider of its
/// share (or, for a category held by a fixed amount and for the remainder, the rail of the share it comes to), the
/// share (a field of a category held by a share, text otherwise), the amount (a field, or the amount of the remainder
/// in bold title 3, in the red of text below zero) with the year under it outside Faktura mode, and the checkbox
/// "pevná částka", or the pill "zbytek" of the remainder. The hint of the row, where it has one, stands under it in the
/// orange of text, or in the red of text for the shortfall.
private struct BudgetCategoryRowView: View {
    let row: BudgetRow
    let model: BudgetModel
    @Binding var editedCategory: BudgetCategory?

    var body: some View {
        VStack(alignment: .leading, spacing: BudgetSplitMetrics.hintGap) {
            BudgetRowLayout {
                name
                rail
                percentColumn
                amountColumn
                lastColumn
            }
            if let hint = row.hint {
                Text(verbatim: hint.text)
                    .font(Typography.callout)
                    .foregroundStyle(hint.tone.color)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// The colour of the category, as the bar draws it.
    private var color: Color {
        SplitBarTone.category(row.category).color
    }

    /// The dot and the name, with the purpose under them.
    private var name: some View {
        VStack(alignment: .leading, spacing: BudgetSplitMetrics.purposeGap) {
            HStack(spacing: BudgetSplitMetrics.dotGap) {
                Circle()
                    .fill(color)
                    .frame(width: BudgetSplitMetrics.dotSize, height: BudgetSplitMetrics.dotSize)
                    .accessibilityHidden(true)
                Text(verbatim: row.name)
                    .font(Typography.headline)
                    .foregroundStyle(Palette.text)
            }
            Text(verbatim: row.purpose)
                .font(Typography.callout)
                .foregroundStyle(Palette.text2)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.leading, BudgetSplitMetrics.purposeIndent)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// The slider of a category held by a share, which ends the slide when it is let go, or the rail of the share of
    /// any other.
    @ViewBuilder
    private var rail: some View {
        if row.mode == .share {
            ShareSlider(
                label: row.sliderAccessibilityLabel, fraction: row.fillFraction, limitFraction: row.limitFraction,
                color: color, valueText: row.sliderValueText,
                onChange: { percent in
                    model.slide(row.category, toPercent: percent)
                },
                onCommit: {
                    model.endSliding(row.category)
                })
        } else {
            ShareRail(fraction: row.fillFraction, color: color)
                .frame(height: ShareSliderLayout.height)
        }
    }

    /// The share: the field with "%" after it for a category held by a share, the share as text in secondary text for
    /// one held by a fixed amount, and in semibold for the remainder.
    private var percentColumn: some View {
        Group {
            switch row.mode {
            case .share:
                HStack(spacing: BudgetSplitMetrics.unitGap) {
                    field(
                        title: row.percentFieldAccessibilityLabel, text: row.percentText,
                        width: BudgetSplitMetrics.percentFieldWidth
                    ) {
                        model.typePercent($0, for: row.category)
                    }
                    unit("%")
                }
            case .fixed:
                Text(verbatim: row.percentText)
                    .font(Typography.body)
                    .monospacedDigit()
                    .foregroundStyle(Palette.text2)
                    .fixedSize()
            case .remainder:
                Text(verbatim: row.percentText)
                    .font(Typography.bodySemibold)
                    .monospacedDigit()
                    .foregroundStyle(Palette.text)
                    .fixedSize()
            }
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
    }

    /// The amount, with the year under it outside Faktura mode: the field with "Kč" after it for a category held by a
    /// share or a fixed amount, which takes no typing while there is nothing to divide for a share, and the amount of
    /// the remainder in bold title 3, in the red of text below zero.
    private var amountColumn: some View {
        VStack(alignment: .trailing, spacing: BudgetSplitMetrics.yearGap) {
            if row.mode == .remainder {
                Text(verbatim: row.amountText)
                    .font(Typography.title3Bold)
                    .monospacedDigit()
                    .foregroundStyle(row.amountIsNegative ? Palette.redText : Palette.text)
                    .fixedSize()
                    .padding(.trailing, BudgetSplitMetrics.amountInset)
            } else {
                HStack(spacing: BudgetSplitMetrics.unitGap) {
                    field(
                        title: row.amountFieldAccessibilityLabel, text: row.amountText,
                        width: BudgetSplitMetrics.amountFieldWidth
                    ) {
                        model.typeAmount($0, for: row.category)
                    }
                    .disabled(!row.amountFieldIsEnabled)
                    unit("Kč")
                }
            }
            if let yearText = row.yearText {
                Text(verbatim: yearText)
                    .font(Typography.callout)
                    .monospacedDigit()
                    .foregroundStyle(Palette.text3)
                    .fixedSize()
                    .padding(.trailing, BudgetSplitMetrics.amountInset)
            }
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
    }

    /// The checkbox "pevná částka", which holds the category by its amount or by its share, or the pill of the
    /// remainder, which has no checkbox.
    private var lastColumn: some View {
        Group {
            if row.mode == .remainder {
                Pill("zbytek", tone: .neutral)
            } else {
                Toggle(
                    isOn: Binding(
                        get: { row.mode == .fixed },
                        set: { _ in model.toggleFixed(row.category) })
                ) {
                    Text("pevná částka")
                        .font(Typography.callout)
                        .foregroundStyle(Palette.text2)
                }
                .toggleStyle(.checkbox)
                .accessibilityLabel(row.fixedToggleAccessibilityLabel)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// A field `width` points wide that VoiceOver reads under `title`, shows `text` and hands what is typed to `type`,
    /// noting the category of the row as the one being edited. Return in it ends the editing of the row, and so does
    /// leaving it (the screen hears the field end its editing).
    private func field(
        title: String, text: String, width: CGFloat, type: @escaping @MainActor (String) -> Void
    ) -> some View {
        AmountTextField(
            title: title,
            text: Binding(
                get: { text },
                set: { typed in
                    editedCategory = row.category
                    type(typed)
                }),
            width: width,
            submit: {
                model.endEditing(row.category)
            }
        )
    }

    /// A unit after a field, "%" or "Kč", in secondary text.
    private func unit(_ text: String) -> some View {
        Text(verbatim: text)
            .font(Typography.body)
            .foregroundStyle(Palette.text2)
            .fixedSize()
    }
}

extension BudgetHintTone {
    /// The colour of a hint under a row: the orange of text for a value that was not taken as typed, the red of text
    /// for the shortfall.
    var color: Color {
        switch self {
        case .attention: Palette.orangeText
        case .error: Palette.redText
        }
    }
}

// MARK: - The layout of a row

/// Lays out the five parts of the row of a category, as the design lays them out: the name, the slider, the share, the
/// amount and the last column. The share, the amount and the last column have widths of their own (84, 146 and 116
/// points), and the name and the slider share the rest, 16 points apart: they grow from 170 and 220 points in 1 to 3,
/// and shrink from them in the same proportion, the slider to no less than 160 points. Where the name would then have
/// less than 120 points, the slider goes under the other four, over the whole width, 8 points under them. The parts of
/// a line are centred on each other, and each is offered its width.
private struct BudgetRowLayout: Layout {
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width.flatMap { $0.isFinite ? $0 : nil } ?? idealWidth
        let frames = frames(in: width, subviews: subviews)
        return CGSize(width: width, height: frames.map(\.maxY).max() ?? 0)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for (subview, frame) in zip(subviews, frames(in: bounds.width, subviews: subviews)) {
            subview.place(
                at: CGPoint(x: bounds.minX + frame.minX, y: bounds.minY + frame.minY), anchor: .topLeading,
                proposal: ProposedViewSize(width: frame.width, height: frame.height))
        }
    }

    /// The width of a row whose name and slider have their widths to grow from.
    private var idealWidth: CGFloat {
        BudgetSplitMetrics.nameBasis + BudgetSplitMetrics.sliderBasis + fixedWidths.reduce(0, +)
            + 4 * BudgetSplitMetrics.columnGap
    }

    /// The widths of the share, the amount and the last column.
    private var fixedWidths: [CGFloat] {
        [
            BudgetSplitMetrics.percentColumnWidth, BudgetSplitMetrics.amountColumnWidth,
            BudgetSplitMetrics.lastColumnWidth,
        ]
    }

    /// The frames of the five parts in a row `width` points wide, from its top left.
    private func frames(in width: CGFloat, subviews: Subviews) -> [CGRect] {
        guard subviews.count == 5 else { return subviews.map { _ in .zero } }
        let gap = BudgetSplitMetrics.columnGap
        let free = width - fixedWidths.reduce(0, +) - 4 * gap
        let shared = sharedWidths(free)
        if shared.name >= BudgetSplitMetrics.nameMinimumWidth {
            return line(widths: [shared.name, shared.slider] + fixedWidths, of: Array(subviews), top: 0)
        }
        // The slider goes under the other four, and the name takes what they leave.
        let name = max(0, width - fixedWidths.reduce(0, +) - 3 * gap)
        let others = [subviews[0], subviews[2], subviews[3], subviews[4]]
        let first = line(widths: [name] + fixedWidths, of: others, top: 0)
        let top = (first.map(\.maxY).max() ?? 0) + BudgetSplitMetrics.lineGap
        let slider = subviews[1].sizeThatFits(ProposedViewSize(width: width, height: nil))
        let sliderFrame = CGRect(x: 0, y: top, width: width, height: slider.height)
        return [first[0], sliderFrame, first[1], first[2], first[3]]
    }

    /// The widths of the name and the slider out of `free` points: grown from their bases in 1 to 3 where there is
    /// more, shrunk from them in proportion to them where there is less, and the slider no narrower than its least.
    private func sharedWidths(_ free: CGFloat) -> (name: CGFloat, slider: CGFloat) {
        let bases = BudgetSplitMetrics.nameBasis + BudgetSplitMetrics.sliderBasis
        if free >= bases {
            let extra = free - bases
            return (BudgetSplitMetrics.nameBasis + extra / 4, BudgetSplitMetrics.sliderBasis + extra * 3 / 4)
        }
        let scale = max(0, free) / bases
        let slider = max(BudgetSplitMetrics.sliderMinimumWidth, BudgetSplitMetrics.sliderBasis * scale)
        return (free - slider, slider)
    }

    /// The frames of `subviews` side by side, `widths` wide and a gap apart, from `top`, centred on the tallest.
    private func line(widths: [CGFloat], of subviews: [LayoutSubview], top: CGFloat) -> [CGRect] {
        let heights = zip(subviews, widths).map { subview, width in
            subview.sizeThatFits(ProposedViewSize(width: width, height: nil)).height
        }
        let tallest = heights.max() ?? 0
        var x: CGFloat = 0
        var frames: [CGRect] = []
        for (width, height) in zip(widths, heights) {
            frames.append(CGRect(x: x, y: top + (tallest - height) / 2, width: width, height: height))
            x += width + BudgetSplitMetrics.columnGap
        }
        return frames
    }
}
