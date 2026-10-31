import SwiftUI

/// The sizes and gaps of a bill card and its rows, in points.
private nonisolated enum BillMetrics {
    /// The size of the dot before the title.
    static let dotSize: CGFloat = 10

    /// The space between the dot, the title and the tag in the header.
    static let headerSpacing: CGFloat = 8

    /// The space between the header and the first rule.
    static let headerBottom: CGFloat = 10

    /// The space under the last row, which has the 8 points of its own above it.
    static let footPadding: CGFloat = 12

    /// The width of the column of the signs.
    static let signWidth: CGFloat = 18

    /// The space between the sign, the texts of the row and its value.
    static let columnSpacing: CGFloat = 10

    /// The space between the label of a row and its note.
    static let noteSpacing: CGFloat = 2

    /// The space above and below the content of a row.
    static let rowPadding: CGFloat = 8

    /// The thickness of the heavy rule above the total, in the colour of text. The other rules are the hairline of the
    /// design (`Hairline`).
    static let totalRuleHeight: CGFloat = 1.5
}

/// A section of the breakdown as a bill: its title with the colour of its authority, or the grey of the income, or the
/// green of the net income, and its rows one under the other, each under a rule. The card is padded 20 points, and 12
/// at its foot, where the last row has 8 of its own.
struct ComputationCard: View {
    let section: ComputationSection

    /// The colour of the dot before the title: the green of the net income, the colour of the authority the section is
    /// about, or the grey of secondary text for a section that is about none, the income.
    private var dotColor: Color {
        if section.isNetIncome {
            return Palette.green
        }
        return section.authority?.color ?? Palette.text2
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: BillMetrics.headerSpacing) {
                Circle()
                    .fill(dotColor)
                    .frame(width: BillMetrics.dotSize, height: BillMetrics.dotSize)
                    .accessibilityHidden(true)
                Text(verbatim: section.title)
                    .font(Typography.title3)
                    .foregroundStyle(Palette.text)
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength: 0)
                if let tag = section.tag {
                    Text(verbatim: tag)
                        .font(Typography.callout)
                        .foregroundStyle(Palette.text3)
                }
            }
            .padding(.bottom, BillMetrics.headerBottom)
            ForEach(section.rows) { row in
                rule(before: row)
                ComputationRowView(row: row)
            }
        }
        .padding(.horizontal, DesignMetrics.cardPadding)
        .padding(.top, DesignMetrics.cardPadding)
        .padding(.bottom, BillMetrics.footPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
        .accessibilityElement(children: .contain)
    }

    /// The line above a row: a heavy one in the colour of text above a total, a stronger hairline above a result, and
    /// the ordinary hairline above the other rows.
    @ViewBuilder
    private func rule(before row: ComputationRow) -> some View {
        switch row.style {
        case .total:
            Rectangle()
                .fill(Palette.text)
                .frame(height: BillMetrics.totalRuleHeight)
        case .plain, .strong:
            Hairline(isStrong: row.sign == .equals)
        }
    }
}

/// A row: the sign, the label with its note under it, and the value on the right in digits of one width. A plain row
/// is set in regular weight, a result in semibold and the total in bold, with its value in title 2. The sign and the
/// note are in tertiary text, and the sign of the total is in the colour of text.
private struct ComputationRowView: View {
    let row: ComputationRow

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: BillMetrics.columnSpacing) {
            Text(verbatim: row.sign.rawValue)
                .font(Typography.bodyBold)
                .foregroundStyle(row.style == .total ? Palette.text : Palette.text3)
                .frame(width: BillMetrics.signWidth)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: BillMetrics.noteSpacing) {
                Text(verbatim: row.label)
                    .font(labelFont)
                    .foregroundStyle(Palette.text)
                    .fixedSize(horizontal: false, vertical: true)
                if let note = row.note {
                    Text(verbatim: note)
                        .font(Typography.callout)
                        .foregroundStyle(Palette.text3)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Text(verbatim: row.value)
                .font(valueFont)
                .foregroundStyle(Palette.text)
                .monospacedDigit()
                .multilineTextAlignment(.trailing)
                .fixedSize(horizontal: true, vertical: false)
        }
        .padding(.vertical, BillMetrics.rowPadding)
        // VoiceOver reads the label, the value with its sign and then the note in one phrase.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(row.spokenText)
    }

    /// The font of the label: body in the weight of the row.
    private var labelFont: Font {
        switch row.style {
        case .plain: Typography.body
        case .strong: Typography.bodySemibold
        case .total: Typography.bodyBold
        }
    }

    /// The font of the value: the weight of the label, and title 2 on the total.
    private var valueFont: Font {
        row.style == .total ? Typography.title2 : labelFont
    }
}
