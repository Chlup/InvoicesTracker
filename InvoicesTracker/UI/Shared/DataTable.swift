import SwiftUI

/// The sizes of a table in a card, in points: the row of the names of the columns, a row of the table, the space at
/// the sides of both, and the space between two columns.
nonisolated enum DataTableMetrics {
    /// The height of the row of the names of the columns.
    static let headerHeight: CGFloat = 32

    /// The height of a row of the table, which holds one line of text.
    static let rowHeight: CGFloat = 40

    /// The space between the edge of the table and its first and last column.
    static let margin: CGFloat = 16

    /// The space between two columns.
    static let gap: CGFloat = 8
}

/// The sizes of the summary row on top of a table and of the stripe of a selected row, in points.
private nonisolated enum DataTableDetailMetrics {
    /// The space above the line of the summary.
    static let summaryTop: CGFloat = 14

    /// The space under the line of the summary, above the hairline.
    static let summaryBottom: CGFloat = 12

    /// The space between the count and the figures where the figures stand under it, and between two lines of figures
    /// where they wrap.
    static let lineGap: CGFloat = 6

    /// The space between two figures of the summary, and between the count and the figures where they stand beside
    /// it.
    static let figureGap: CGFloat = 24

    /// The space between two lines of figures where the figures wrap.
    static let figureLineGap: CGFloat = 4

    /// The space between the label of a figure and its value.
    static let labelGap: CGFloat = 8

    /// The width of the stripe along the leading edge of a selected row.
    static let stripeWidth: CGFloat = 3
}

/// The row on top of a table, inside its card: at the leading side how many rows the table shows and which ones, in
/// semibold text and secondary text, and at the trailing side the totals, which are `SummaryFigure`s. A hairline
/// closes it off from the names of the columns.
///
/// The figures stand at the trailing side of the line of the count where the room has them, and under the count, from
/// the leading side, where it has not; they wrap among themselves where even a line of their own is too narrow.
///
/// The count is shown as it is given, and so is the category, which has its own leading separator: "12 faktur" and
/// " · všechny stavy". VoiceOver reads the row as a group called "Souhrn".
struct TableSummaryRow<Trailing: View>: View {
    let count: String
    let category: String
    private let trailing: Trailing

    /// A row that says `count` and `category`, with `trailing` at its trailing side.
    init(count: String, category: String, @ViewBuilder trailing: () -> Trailing) {
        self.count = count
        self.category = category
        self.trailing = trailing()
    }

    var body: some View {
        VStack(spacing: 0) {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .firstTextBaseline, spacing: 0) {
                    summary
                    Spacer(minLength: DataTableDetailMetrics.figureGap)
                    HStack(alignment: .firstTextBaseline, spacing: DataTableDetailMetrics.figureGap) {
                        trailing
                    }
                }
                VStack(alignment: .leading, spacing: DataTableDetailMetrics.lineGap) {
                    summary
                    FlowLayout(
                        spacing: DataTableDetailMetrics.figureGap, lineSpacing: DataTableDetailMetrics.figureLineGap,
                        alignment: .firstTextBaseline
                    ) {
                        trailing
                    }
                }
            }
            .padding(
                EdgeInsets(
                    top: DataTableDetailMetrics.summaryTop, leading: DataTableMetrics.margin,
                    bottom: DataTableDetailMetrics.summaryBottom, trailing: DataTableMetrics.margin)
            )
            .frame(maxWidth: .infinity, alignment: .leading)
            Palette.sep
                .frame(height: 1)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Souhrn")
    }

    /// The count in semibold text and the category after it in secondary text, which wrap together where the room is
    /// narrower than they are.
    private var summary: some View {
        var counted = AttributedString(count)
        counted.font = Typography.bodySemibold
        counted.foregroundColor = Palette.text
        var categorised = AttributedString(category)
        categorised.font = Typography.body
        categorised.foregroundColor = Palette.text2
        counted.append(categorised)
        return Text(counted)
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// A total or another figure of the summary row: its label in callout and secondary text, and its value after it on
/// the same baseline, in title 3 bold with digits of one width. Where the figure is not known, as with a rate that is
/// not out yet, the value is muted: a word in body and tertiary text instead of a figure. A `help` is its tooltip,
/// which says what the figure is made of. VoiceOver reads the figure as one phrase, the label and the value.
struct SummaryFigure: View {
    let label: String
    let value: String
    let help: String?
    let valueIsMuted: Bool

    /// A figure that reads `value` after `label`, with `help` as its tooltip where there is one.
    init(label: String, value: String, help: String? = nil, valueIsMuted: Bool = false) {
        self.label = label
        self.value = value
        self.help = help
        self.valueIsMuted = valueIsMuted
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: DataTableDetailMetrics.labelGap) {
            Text(verbatim: label)
                .font(Typography.callout)
                .foregroundStyle(Palette.text2)
            Text(verbatim: value)
                .font(valueIsMuted ? Typography.body : Typography.title3Bold)
                .foregroundStyle(valueIsMuted ? Palette.text3 : Palette.text)
                .monospacedDigit()
        }
        .fixedSize()
        .help(help ?? "")
        .accessibilityElement(children: .combine)
    }
}

extension View {
    /// The style of the row of the names of the columns of a table: callout in semibold and secondary text, on one
    /// line, in a row 32 points high with the names in the middle of it. The table gives the row its sides
    /// (`DataTableMetrics.margin`) and the columns their widths.
    func tableHeaderStyle() -> some View {
        font(Typography.calloutSemibold)
            .foregroundStyle(Palette.text2)
            .lineLimit(1)
            .frame(height: DataTableMetrics.headerHeight)
    }

    /// The background of a row of a table: where the row is selected, the pale blue of a selection with a stripe of the
    /// accent, 3 points wide, along its leading edge; where it is not, nothing, so that the card shows. A selection
    /// always uses the accent.
    func tableRowBackground(isSelected: Bool) -> some View {
        background {
            if isSelected {
                Palette.accentTint
                    .overlay(alignment: .leading) {
                        Palette.accent
                            .frame(width: DataTableDetailMetrics.stripeWidth)
                    }
            }
        }
    }
}
