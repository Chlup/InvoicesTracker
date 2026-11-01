import SwiftUI

/// The table of Faktury in a card of its own: on top the summary row, how many invoices the table shows and their
/// totals without VAT in crowns (`TableSummaryRow`); under it the names of the columns, 32 points high, and the rows,
/// 40 points high with one line of text each: Číslo, Odběratel (with the excerpt that says why the search found the
/// invoice, when no column shows it, after the name), Vystaveno, Zaplaceno, V Kč bez DPH, Bez DPH, Čistý příjem (what
/// the invoice leaves after the tax and the insurance its payment adds) and Stav. The row of the open invoice is tinted
/// pale blue, with a blue edge on its leading side. An empty list says why in a row under the names of the columns.
///
/// The table is as wide as its card: its columns grow and shrink with the card (`InvoiceTableColumns`) down to the
/// least width of the table, below which the table keeps that width and scrolls sideways under the summary row, which
/// stays as wide as the card and wraps in it. The names of the columns stay at the top while the rows scroll.
///
/// A click on a row opens its invoice, and a click on the open row closes it (`click`). The click gives the table the
/// keyboard focus, and then ↑ and ↓ open the invoice of the row above or under the open one (`move`); the table scrolls
/// to the open row. VoiceOver reads the card as "Seznam faktur", the summary row as a group "Souhrn" and each row as a
/// button that names the columns (`InvoiceRow.spokenText`), says which row is open, and presses a row as a click does.
struct InvoiceTableView: View {
    /// The rows, the summary and what the list says when it has no rows.
    let data: InvoiceListData

    /// The id of the open invoice, whose row is tinted.
    let openID: Int64?

    /// A row was clicked, or pressed with VoiceOver.
    let click: (Int64) -> Void

    /// ↓ (1) or ↑ (−1) was pressed while the table has the focus.
    let move: (Int) -> Void

    /// The width of the card, which the table fills where it is more than the least width of the table.
    @State private var visibleWidth: CGFloat = 0

    /// Whether the table has the focus of the keyboard, which a click on a row gives it.
    @FocusState private var hasFocus: Bool

    /// Where the rows are scrolled to, which the table moves to show the open row.
    @State private var rowsPosition = ScrollPosition(idType: Int64.self)

    var body: some View {
        VStack(spacing: 0) {
            summary
            table
        }
        .clipShape(RoundedRectangle(cornerRadius: DesignMetrics.cardRadius))
        .card()
        .focusable(interactions: .edit)
        .focused($hasFocus)
        .focusEffectDisabled()
        .onKeyPress(.downArrow) {
            move(1)
            return .handled
        }
        .onKeyPress(.upArrow) {
            move(-1)
            return .handled
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Seznam faktur")
    }

    // MARK: The summary

    /// The count and the category of the rows, with the hint about invoices to check where there is one, and the
    /// totals: in crowns, and at the uniform rate of the year where the rows have an invoice in a foreign currency.
    private var summary: some View {
        TableSummaryRow(count: data.countText, category: data.categoryText + (data.reviewHint ?? "")) {
            SummaryFigure(label: "Celkem v Kč bez DPH", value: data.totalText)
            switch data.uniform {
            case .hidden:
                EmptyView()
            case .value(let text, let help):
                SummaryFigure(label: data.uniformLabel, value: text, help: help)
            case .missing(let text, let help):
                SummaryFigure(label: data.uniformLabel, value: text, help: help, valueIsMuted: true)
            }
        }
    }

    // MARK: The table

    /// The names of the columns and the rows under them, as wide as the card or as the least width of the table,
    /// whichever is more, in a view that scrolls sideways.
    private var table: some View {
        let columns = InvoiceTableColumns(
            issueDatesShowYear: data.issueDatesShowYear, paymentDatesShowYear: data.paymentDatesShowYear)
        let width = max(visibleWidth, columns.minimumWidth)
        let widths = columns.columnWidths(inTableOf: width)
        return ScrollView(.horizontal) {
            VStack(alignment: .leading, spacing: 0) {
                header(widths: widths)
                ScrollView(.vertical) {
                    VStack(alignment: .leading, spacing: 0) {
                        if let emptyText = data.emptyText {
                            TableEmptyRow(text: emptyText)
                        }
                        ForEach(data.rows) { row in
                            rowView(row, widths: widths)
                                .id(row.id)
                        }
                    }
                    .scrollTargetLayout()
                }
                .scrollPosition($rowsPosition)
                .onChange(of: openID) { _, id in
                    if let id {
                        rowsPosition.scrollTo(id: id)
                    }
                }
            }
            .frame(width: width, alignment: .leading)
        }
        .onGeometryChange(for: CGFloat.self) { proxy in
            proxy.size.width
        } action: { width in
            visibleWidth = width
        }
    }

    /// The names of the columns, in the style of the header of a table, the amounts aligned to the right as their
    /// columns are. Each row says the names of its columns itself, so VoiceOver does not read them.
    private func header(widths: [CGFloat]) -> some View {
        HStack(spacing: DataTableMetrics.gap) {
            title("Číslo", width: widths[0])
            title("Odběratel", width: widths[1])
            title("Vystaveno", width: widths[2])
            title("Zaplaceno", width: widths[3])
            title("V Kč bez DPH", width: widths[4], alignment: .trailing)
            title("Bez DPH", width: widths[5], alignment: .trailing)
            title("Čistý příjem", width: widths[6], alignment: .trailing)
            title("Stav", width: widths[7])
        }
        .padding(.horizontal, DataTableMetrics.margin)
        .accessibilityHidden(true)
    }

    /// The name `title` of a column `width` points wide, at the side of the column that its cells are aligned to.
    private func title(_ title: LocalizedStringKey, width: CGFloat, alignment: Alignment = .leading) -> some View {
        InvoiceColumnTitle(title: title)
            .frame(width: width, alignment: alignment)
    }

    // MARK: A row

    /// The row of `row` as a button: its cells, the tint of the open row behind them and the hairline across its top.
    private func rowView(_ row: InvoiceRow, widths: [CGFloat]) -> some View {
        let isOpen = row.id == openID
        return Button {
            activate(row.id)
        } label: {
            InvoiceRowCells(row: row, widths: widths)
                .tableRowBackground(isSelected: isOpen)
                .overlay(alignment: .top) {
                    Hairline()
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(TableRowButtonStyle())
        .accessibilityLabel(Text(verbatim: row.spokenText))
        .accessibilityAddTraits(isOpen ? .isSelected : [])
    }

    /// A click on a row: the table takes the keyboard focus, for ↑ and ↓, and the row opens or closes.
    private func activate(_ id: Int64) {
        hasFocus = true
        click(id)
    }
}

nonisolated extension InvoiceRow {
    /// What VoiceOver reads for the row: the number, the client and the excerpt of the search, then each other column
    /// with its name. A column that is empty for the invoice is left out, Zaplaceno of an invoice without a payment and
    /// Čistý příjem of one with no net income, and so is V Kč bez DPH of an invoice in crowns, which repeats Bez DPH.
    /// The status is read without a date, as the date of the payment is read before it.
    var spokenText: String {
        var parts = [number, client]
        if let excerpt {
            parts.append("\(excerpt.label): \(excerpt.text)")
        }
        parts.append("Vystaveno \(issued)")
        if paidTone != .none {
            parts.append("Zaplaceno \(paidDate)")
        }
        if czk != net {
            parts.append("V Kč bez DPH \(czk)")
        }
        parts.append("Bez DPH \(net)")
        if netIncomeKind != .none {
            parts.append("Čistý příjem \(netIncome)")
        }
        parts.append("Stav: \(listStatus)")
        return parts.joined(separator: ", ")
    }
}

// MARK: - Cells

/// The cells of a row of the table, one line each, in the widths of the columns (`InvoiceTableColumns`) with the gap of
/// a table between them and its margin at the ends, in a row 40 points high. Each cell is in the colour of what it
/// shows: the amounts with digits of one width, aligned to the right; Bez DPH in secondary grey; an estimate in
/// secondary grey; a dash in the faintest grey; the date of a payment dated after today in the grey of notes; the net
/// income of a payment in the green of text; and the status as a pill in its tone, without a date.
struct InvoiceRowCells: View {
    let row: InvoiceRow

    /// The widths of the eight columns, in their order.
    let widths: [CGFloat]

    var body: some View {
        HStack(spacing: DataTableMetrics.gap) {
            cell(width: widths[0]) {
                InvoiceNumberText(number: row.number)
            }
            cell(width: widths[1]) {
                InvoiceClientText(client: row.client, excerpt: row.excerpt)
            }
            cell(width: widths[2]) {
                InvoiceDateText(text: row.issued)
            }
            cell(width: widths[3]) {
                InvoiceDateText(text: row.paidDate, color: paidColor)
            }
            cell(width: widths[4], alignment: .trailing) {
                InvoiceAmountText(amount: row.czk)
                    .foregroundStyle(crownsColor)
                    .help(row.czkHelp ?? "")
            }
            cell(width: widths[5], alignment: .trailing) {
                InvoiceAmountText(amount: row.net)
                    .foregroundStyle(Palette.text2)
            }
            cell(width: widths[6], alignment: .trailing) {
                InvoiceNetIncomeText(text: row.netIncome, kind: row.netIncomeKind)
            }
            cell(width: widths[7]) {
                Pill(row.listStatus, tone: row.pillTone)
            }
        }
        .font(Typography.body)
        .foregroundStyle(Palette.text)
        .padding(.horizontal, DataTableMetrics.margin)
        .frame(height: DataTableMetrics.rowHeight)
    }

    /// The colour of the day of the payment: the colour of text for a payment that came, the grey of notes for one
    /// dated after today, and the faintest grey for the dash of an invoice without a payment.
    private var paidColor: Color {
        switch row.paidTone {
        case .none: Palette.text4
        case .received: Palette.text
        case .later: Palette.text3
        }
    }

    /// The colour of the value in crowns: the colour of text for what was received or an amount in crowns, secondary
    /// grey for an estimate, and the faintest grey for the dash of an estimate that cannot be made.
    private var crownsColor: Color {
        switch row.czkKind {
        case .actual: Palette.text
        case .estimate: Palette.text2
        case .unknown: Palette.text4
        }
    }

    /// A cell `width` points wide that holds `content` at its leading side, or at the side `alignment` says.
    private func cell<Content: View>(
        width: CGFloat, alignment: Alignment = .leading, @ViewBuilder content: () -> Content
    ) -> some View {
        content()
            .frame(width: width, alignment: alignment)
    }
}

/// The number of an invoice as its cell shows it: body semibold, with digits of one width, on one line. The width of
/// the column holds the widest number in use (`InvoiceTableColumns`).
struct InvoiceNumberText: View {
    let number: String

    var body: some View {
        Text(verbatim: number)
            .font(Typography.bodySemibold)
            .monospacedDigit()
            .lineLimit(1)
            .truncationMode(.tail)
    }
}

/// The name of a column as the header of the table shows it: callout semibold in secondary text, on one line
/// (`View.tableHeaderStyle()`). The width of each column holds its name whole (`InvoiceTableColumns`).
struct InvoiceColumnTitle: View {
    let title: LocalizedStringKey

    var body: some View {
        Text(title)
            .tableHeaderStyle()
    }
}

/// A date as its cell shows it, "31. 10." or "30. 12. 2025": body with digits of one width, on one line, in the colour
/// it is given, the colour of text unless the column says otherwise. The width of a date column holds a date with its
/// year once it is widened for one (`InvoiceTableColumns`).
struct InvoiceDateText: View {
    let text: String
    var color = Palette.text

    var body: some View {
        Text(verbatim: text)
            .font(Typography.body)
            .monospacedDigit()
            .foregroundStyle(color)
            .lineLimit(1)
    }
}

/// The net income of an invoice as its cell shows it: body semibold, with digits of one width, on one line. That of a
/// paid invoice is in the green of text, an estimate is in secondary grey, and the dash of an invoice without a net
/// income in the faintest grey. The least width of Čistý příjem holds 999 999 Kč with the sign of an estimate, whole
/// (`InvoiceTableColumns`).
struct InvoiceNetIncomeText: View {
    let text: String
    let kind: NetIncomeKind

    var body: some View {
        Text(verbatim: text)
            .font(Typography.bodySemibold)
            .monospacedDigit()
            .lineLimit(1)
            .foregroundStyle(color)
    }

    /// The colour of the net income of `kind`.
    private var color: Color {
        switch kind {
        case .paid: Palette.greenText
        case .estimate: Palette.text2
        case .none: Palette.text4
        }
    }
}

/// An amount as its cell shows it, with its currency: body with digits of one width, on one line. The least width of
/// the columns of amounts holds 999 999,99 in any currency in use (`InvoiceTableColumns`).
struct InvoiceAmountText: View {
    let amount: String

    var body: some View {
        Text(verbatim: amount)
            .font(Typography.body)
            .monospacedDigit()
            .lineLimit(1)
    }
}

/// The name of the client and, after it on the same line, why the search found the invoice: the label of the field
/// and the text around the match, smaller and in the grey of notes, with the match highlighted
/// (`SearchExcerptResult.attributedLine`). A line longer than the column is cut short at its end.
struct InvoiceClientText: View {
    let client: String
    let excerpt: SearchExcerptResult?

    var body: some View {
        Text(line)
            .lineLimit(1)
            .truncationMode(.tail)
    }

    /// The name in body and the colour of text, and the excerpt after it.
    private var line: AttributedString {
        var line = AttributedString(client)
        line.font = Typography.body
        line.foregroundColor = Palette.text
        if let excerpt {
            line.append(excerpt.attributedLine)
        }
        return line
    }
}

extension SearchExcerptResult {
    /// " · Poznámka: …Routing number…": the label of the field and the text around the match, as they follow the name
    /// of the client, in callout and the grey of notes, with the matched text bold, in the colour of text and on the
    /// yellow of a highlight.
    var attributedLine: AttributedString {
        var line = AttributedString(" · \(label): ")
        line.foregroundColor = Palette.text3
        var excerpt = AttributedString(text)
        excerpt.foregroundColor = Palette.text3
        if let range = Range(highlight, in: excerpt) {
            excerpt[range].backgroundColor = Palette.highlight
            excerpt[range].foregroundColor = Palette.text
            excerpt[range].inlinePresentationIntent = .stronglyEmphasized
        }
        line.append(excerpt)
        line.font = Typography.callout
        return line
    }
}
