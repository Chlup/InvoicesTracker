import SwiftUI

// MARK: - The data

/// The sign in front of a row of a bill, which says how its value goes into the calculation: it is taken from the rows
/// above it, added to them, multiplied by a rate, divided by a number, or it is their result.
nonisolated enum BillSign: String, Sendable, Hashable {
    /// The row stands on its own or starts a calculation.
    case blank = ""
    case minus = "\u{2212}"
    case plus = "+"
    case equals = "="
    case times = "×"
    case divided = "÷"
}

/// How a row of a bill is set.
nonisolated enum BillRowStyle: Sendable, Hashable {
    case plain

    /// A result of the rows above it: bold.
    case strong

    /// What a section leads to: larger, with a rule above it.
    case total
}

/// The font of the value of a row where it is not the one the style of the row gives (`BillRowStyle`), as in the
/// calculations of the income, which set their amounts larger the further down they lead.
nonisolated enum BillValueStyle: Sendable, Hashable {
    /// The body style, semibold: an amount that the calculation starts from, such as the income and the levies.
    case semibold

    /// The title 3 style, bold: a result, such as the net income of a year or what to set aside each month.
    case title3Bold

    /// The title 2 style, bold: the figure the calculation leads to, such as the net income per month.
    case title2Bold
}

/// The line above a row of a bill where it is not the one the style and the sign of the row give
/// (`BillRow.standardRule`). The first case is named `hidden` and not `none`, as where a `BillRule?` is expected,
/// `.none` is nil, which is the rule the row would have anyway.
nonisolated enum BillRule: Sendable, Hashable {
    /// No line, as above the first row of a calculation and between the payments of the panel of how the levies are
    /// paid.
    case hidden

    /// The hairline of the design (`Hairline`), as above an ordinary row.
    case hairline

    /// The hairline in the stronger colour of the separators (`Hairline(isStrong: true)`), as above a result.
    case strong

    /// The 1-point line in the stronger colour of the separators that parts a sum from the amounts it is made of, as
    /// above what to set aside in the panel of how the levies are paid. It is drawn as the stronger hairline is, and
    /// named for its place.
    case separator

    /// The heavy line in the colour of text, 1,5 points thick, as above the total of a section.
    case heavy
}

/// A line of a bill: what it is, its value as it is shown, and under it, where there is something to explain (a cap, a
/// rounding, a convention), a note. Beside the label a row of a calculation can have the share of the income, the
/// months it is over and the green dot of the net income; its value can be set larger than its style sets it, and it
/// can ask for another line above it. A row that has none of these is set as the rows of Rozpis výpočtu are.
nonisolated struct BillRow: Identifiable, Sendable, Hashable {
    var label: String
    var value: String
    var note: String?
    var sign = BillSign.blank
    var style = BillRowStyle.plain

    /// The share of the income that the value is, beside the label in body and secondary text: "17,0 %".
    var share: String? = nil

    /// The months the value is over, beside the label after the share in tertiary text: "· 10 měsíců", with no-break spaces.
    var period: String? = nil

    /// Whether the row is the net income per month, which a green dot of 8 points in front of its label shows.
    var marksNetIncome = false

    /// The font of the value, or nil for the one its style gives: the weight of the label, and title 2 on a total.
    var valueStyle: BillValueStyle? = nil

    /// The line above the row, or nil for the one its style and sign give (`standardRule`).
    var rule: BillRule? = nil

    /// The label: no two rows of a section have the same one.
    var id: String {
        label
    }

    /// The line that the style and the sign of the row give above it: the heavy line above a total, the stronger
    /// hairline above a result, which has the sign "=", and the ordinary hairline above any other row.
    var standardRule: BillRule {
        if style == .total {
            return .heavy
        }
        return sign == .equals ? .strong : .hairline
    }

    /// What VoiceOver reads for the row: the label with the share and the months beside it, the value as it is
    /// written, and the note: "Odvody 17,0 %: 466 782 Kč. daň 114 786 · sociální 247 832 · zdravotní 104 164". The sign
    /// in front of the row and the dot are only for the eyes, so a subtracted value is read with the minus only where
    /// it is written in the value, as in Rozpis výpočtu ("Zálohy: −126 260"), and without it where the sign alone
    /// shows the subtraction, as in the calculations of the income ("Odvody 17,0 %: 466 782 Kč").
    var spokenText: String {
        let name = [label, share, period].compactMap { $0 }.joined(separator: " ")
        let spoken = "\(name): \(value)"
        guard let note else { return spoken }
        return "\(spoken). \(note)"
    }
}

// MARK: - The view

/// The sizes and gaps of a bill card and its rows, in points, which the bill of an invoice on Rozpočet shares.
nonisolated enum BillMetrics {
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

    /// The size of the green dot of the net income in front of the label of a row.
    static let netIncomeDotSize: CGFloat = 8

    /// The space between the dot of the net income and the label.
    static let netIncomeDotGap: CGFloat = 6

    /// The space between the label of a row and the share beside it.
    static let shareGap: CGFloat = 8
}

/// Rows of a bill one under the other, each under its line (`BillRow.rule`, or the one its style and sign give). The
/// first row has none above it unless it asks for one, as a calculation stands under a hairline of its card; with
/// `startsWithRule` it has the line of its style too, as in a bill card, where that line parts the rows from the
/// header.
struct BillRows: View {
    let rows: [BillRow]

    /// Whether the first row has the line of its style above it, and not none.
    var startsWithRule = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(rows) { row in
                BillRuleView(rule: rule(above: row))
                BillRowView(row: row)
            }
        }
    }

    /// The line above `row`: the one it asks for, none above the first row unless the rows start with a rule, and the
    /// one its style and sign give otherwise.
    private func rule(above row: BillRow) -> BillRule {
        if let rule = row.rule {
            return rule
        }
        return !startsWithRule && row.id == rows.first?.id ? BillRule.hidden : row.standardRule
    }
}

/// A line above a row of a bill: nothing, the hairline, the stronger hairline, or the heavy line in the colour of text.
private struct BillRuleView: View {
    let rule: BillRule

    var body: some View {
        switch rule {
        case .hidden:
            EmptyView()
        case .hairline:
            Hairline()
        case .strong, .separator:
            Hairline(isStrong: true)
        case .heavy:
            Rectangle()
                .fill(Palette.text)
                .frame(height: BillMetrics.totalRuleHeight)
        }
    }
}

/// A row: the sign, the label with its note under it, and the value on the right in digits of one width. A plain row
/// is set in regular weight, a result in semibold and the total in bold, with its value in title 2; a row can set its
/// value in another font of its own (`BillRow.valueStyle`). The sign and the note are in tertiary text, and the sign of
/// the total is in the colour of text. Beside the label stand the share, in body and secondary text, and the months,
/// in tertiary text; the green dot of the net income stands in front of it, on the baseline of its first line. The
/// label and its note wrap where the row is narrow; the value is never cut or broken. VoiceOver reads the row as one
/// phrase (`BillRow.spokenText`).
struct BillRowView: View {
    let row: BillRow

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: BillMetrics.columnSpacing) {
            Text(verbatim: row.sign.rawValue)
                .font(Typography.bodyBold)
                .foregroundStyle(row.style == .total ? Palette.text : Palette.text3)
                .frame(width: BillMetrics.signWidth)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: BillMetrics.noteSpacing) {
                labelLine
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

    /// The label alone, as the rows of Rozpis výpočtu have it, or, where the row has a share, months or the dot, the
    /// label with them.
    @ViewBuilder
    private var labelLine: some View {
        if row.share == nil && row.period == nil && !row.marksNetIncome {
            Text(verbatim: row.label)
                .font(labelFont)
                .foregroundStyle(Palette.text)
                .fixedSize(horizontal: false, vertical: true)
        } else {
            HStack(alignment: .firstTextBaseline, spacing: BillMetrics.netIncomeDotGap) {
                if row.marksNetIncome {
                    Circle()
                        .fill(Palette.green)
                        .frame(width: BillMetrics.netIncomeDotSize, height: BillMetrics.netIncomeDotSize)
                        .accessibilityHidden(true)
                }
                HStack(alignment: .firstTextBaseline, spacing: BillMetrics.shareGap) {
                    Text(labelText)
                        .fixedSize(horizontal: false, vertical: true)
                    if let shareText {
                        Text(shareText)
                            .fixedSize()
                    }
                }
            }
        }
    }

    /// The label in the font of the row and the colour of text, with the months after it where the row has no share.
    private var labelText: AttributedString {
        var text = AttributedString(row.label)
        text.font = labelFont
        text.foregroundColor = Palette.text
        if row.share == nil, let period = row.period {
            text.append(periodText(period))
        }
        return text
    }

    /// The share in body and secondary text, in digits of one width, with the months after it; nil where there is no
    /// share.
    private var shareText: AttributedString? {
        guard let share = row.share else { return nil }
        var text = AttributedString(share)
        text.font = Typography.body.monospacedDigit()
        text.foregroundColor = Palette.text2
        if let period = row.period {
            text.append(periodText(period))
        }
        return text
    }

    /// The months, a space after what they follow, in body and tertiary text.
    private func periodText(_ period: String) -> AttributedString {
        var text = AttributedString(" " + period)
        text.font = Typography.body
        text.foregroundColor = Palette.text3
        return text
    }

    /// The font of the label: body in the weight of the row.
    private var labelFont: Font {
        switch row.style {
        case .plain: Typography.body
        case .strong: Typography.bodySemibold
        case .total: Typography.bodyBold
        }
    }

    /// The font of the value: the one the row asks for, or the weight of the label, and title 2 on the total.
    private var valueFont: Font {
        switch row.valueStyle {
        case .semibold: Typography.bodySemibold
        case .title3Bold: Typography.title3Bold
        case .title2Bold: Typography.title2
        case nil: row.style == .total ? Typography.title2 : labelFont
        }
    }
}
