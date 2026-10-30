import SwiftUI

/// The table of Faktury, in a card of its own: Číslo, Odběratel (with the line that says why the search found the
/// invoice, when no column shows it), Vystaveno, Zaplaceno, Bez DPH, V Kč, Čistý příjem (what the invoice leaves after
/// the tax and the insurance its payment adds, with the line that says how much they took) and Stav. The row of the
/// open invoice is tinted blue, with a blue edge on its leading side.
///
/// The table is as wide as its card: its columns grow and shrink with the card (`InvoiceTableColumns`) down to the
/// least width of the table, below which the table keeps that width and scrolls sideways. The names of the columns stay
/// at the top while the rows scroll.
///
/// A click on a row opens its invoice, and a click on the open row closes it (`click`). The click gives the table the
/// keyboard focus, and then ↑ and ↓ open the invoice of the row above or under the open one (`move`); the table scrolls
/// to the open row. VoiceOver reads each row as a button that names the columns (`InvoiceRow.spokenText(asOf:)`), says
/// which row is open, and presses a row as a click does.
struct InvoiceTableView: View {
    let rows: [InvoiceRow]

    /// The day the table is shown as of, which the pills are worded for.
    let shownDay: CivilDate

    /// The id of the open invoice, whose row is tinted.
    let openID: Int64?

    /// What the list says in place of rows, or nil when it has rows.
    let emptyText: String?

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
        let width = max(visibleWidth, InvoiceTableColumns.minimumWidth)
        let columns = InvoiceTableColumns.columnWidths(inTableOf: width)
        ScrollView(.horizontal) {
            VStack(alignment: .leading, spacing: 0) {
                header(columns: columns)
                Divider()
                ScrollView(.vertical) {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(rows) { row in
                            VStack(spacing: 0) {
                                if row.id != rows.first?.id {
                                    Divider()
                                }
                                rowView(row, columns: columns)
                            }
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
        .overlay(alignment: .top) {
            if let emptyText {
                Text(emptyText)
                    .foregroundStyle(.secondary)
                    .padding(.top, 48)
                    .padding(.horizontal, 20)
                    .multilineTextAlignment(.center)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .screenCard()
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

    // MARK: The names of the columns

    private func header(columns: [CGFloat]) -> some View {
        HStack(spacing: InvoiceTableColumns.spacing) {
            title("Číslo", width: columns[0])
            title("Odběratel", width: columns[1])
            title("Vystaveno", width: columns[2])
            title("Zaplaceno", width: columns[3])
            title("Bez DPH", width: columns[4], alignment: .trailing)
            title("V Kč", width: columns[5], alignment: .trailing)
            title("Čistý příjem", width: columns[6], alignment: .trailing)
            InvoiceColumnTitle(title: "Stav")
                .padding(.leading, InvoiceTableColumns.statusInset)
                .frame(width: columns[7], alignment: .leading)
        }
        .padding(.horizontal, InvoiceTableColumns.margin)
        .padding(.top, 12)
        .padding(.bottom, 8)
        // Each row says the names of its columns itself.
        .accessibilityHidden(true)
    }

    private func title(_ title: LocalizedStringKey, width: CGFloat, alignment: Alignment = .leading) -> some View {
        InvoiceColumnTitle(title: title)
            .frame(width: width, alignment: alignment)
    }

    // MARK: A row

    private func rowView(_ row: InvoiceRow, columns: [CGFloat]) -> some View {
        let isOpen = row.id == openID
        let status = row.status.label(asOf: shownDay)
        return Button {
            activate(row.id)
        } label: {
            HStack(spacing: InvoiceTableColumns.spacing) {
                cell(width: columns[0]) {
                    InvoiceNumberText(number: row.number)
                }
                cell(width: columns[1]) {
                    ClientCell(client: row.client, excerpt: row.excerpt)
                }
                cell(width: columns[2]) {
                    Text(verbatim: row.issued)
                        .lineLimit(1)
                }
                cell(width: columns[3]) {
                    Text(verbatim: row.paid ?? "—")
                        .lineLimit(1)
                }
                cell(width: columns[4], alignment: .trailing) {
                    InvoiceAmountText(amount: row.net)
                }
                cell(width: columns[5], alignment: .trailing) {
                    CrownsCell(row: row)
                }
                cell(width: columns[6], alignment: .trailing) {
                    NetIncomeCell(row: row)
                }
                cell(width: columns[7]) {
                    StatusPill(status: row.status, label: status)
                        .padding(.leading, InvoiceTableColumns.statusInset)
                }
            }
            .padding(.horizontal, InvoiceTableColumns.margin)
            .padding(.vertical, 8)
            .frame(minHeight: 52)
            .background {
                if isOpen {
                    Color(.selectedRow)
                        .overlay(alignment: .leading) {
                            Color(.selectedRowEdge)
                                .frame(width: 3)
                        }
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(RowButtonStyle())
        .accessibilityLabel(Text(verbatim: row.spokenText(asOf: shownDay)))
        .accessibilityAddTraits(isOpen ? .isSelected : [])
    }

    private func cell<Content: View>(
        width: CGFloat, alignment: Alignment = .leading, @ViewBuilder content: () -> Content
    ) -> some View {
        content()
            .monospacedDigit()
            .frame(width: width, alignment: alignment)
    }

    /// A click on a row: the table takes the keyboard focus, for ↑ and ↓, and the row opens or closes.
    private func activate(_ id: Int64) {
        hasFocus = true
        click(id)
    }
}

nonisolated extension InvoiceRow {
    /// What VoiceOver reads for the row in the table shown as of `shownDay`: the number, the client and the line of the
    /// search, then each other column with its name. A column that is empty for the invoice is left out: V Kč of an
    /// invoice in crowns, and Čistý příjem of an invoice with no net income. The net income is read with the line
    /// under it, "Čistý příjem 253 401 Kč, odvody snížila".
    func spokenText(asOf shownDay: CivilDate) -> String {
        var parts = [number, client]
        if let excerpt {
            parts.append("\(excerpt.label): \(excerpt.text)")
        }
        parts.append("Vystaveno \(issued)")
        if let paid {
            parts.append("Zaplaceno \(paid)")
        }
        parts.append("Bez DPH \(net)")
        if !czk.isEmpty {
            parts.append(czkNote.isEmpty ? "V Kč \(czk)" : "V Kč \(czk), \(czkNote)")
        }
        if netIncomeKind != .none {
            parts.append("Čistý příjem \(netIncome), \(netIncomeNote)")
        }
        parts.append("Stav: \(status.label(asOf: shownDay))")
        return parts.joined(separator: ", ")
    }
}

/// A row of the table is a button that looks the same while it is pressed: a click opens or closes it, and nothing
/// more.
private struct RowButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
    }
}

// MARK: - Cells

/// The number of an invoice as its cell shows it: semibold, with digits of one width, on one line. The least width of
/// the column holds the widest number in use (`InvoiceTableColumns`).
struct InvoiceNumberText: View {
    let number: String

    var body: some View {
        Text(verbatim: number)
            .fontWeight(.semibold)
            .monospacedDigit()
            .lineLimit(1)
            .truncationMode(.tail)
    }
}

/// The name of a column as the header of the table shows it: semibold, in the secondary colour, on one line, at the
/// size of the prototype's column names (`.callout` is 12 points on the Mac). The least widths of Vystaveno and
/// Zaplaceno hold their names whole (`InvoiceTableColumns`).
struct InvoiceColumnTitle: View {
    let title: LocalizedStringKey

    var body: some View {
        Text(title)
            .font(.callout.weight(.semibold))
            .foregroundStyle(.secondary)
            .lineLimit(1)
    }
}

/// The line under the value in crowns that says how it was worked out, or under the net income that says what the
/// levies took of it, as its cell shows it: small (`.caption`, 10 points on the Mac), in the secondary colour, with
/// digits of one width, on one line. The least width of V Kč holds the line of an estimate, "ČNB k vystavení 21,622",
/// whole, and that of Čistý příjem holds its longest lines, "odvody snížila" and "odvody 100,0 %"
/// (`InvoiceTableColumns`).
struct InvoiceCaptionText: View {
    let text: String

    var body: some View {
        Text(verbatim: text)
            .font(.caption)
            .foregroundStyle(.secondary)
            .monospacedDigit()
            .lineLimit(1)
    }
}

/// The net income of an invoice as its cell shows it: semibold, with digits of one width, on one line. That of a paid
/// invoice is in the green of the banners, and an estimate and a dash are in the secondary colour. The least width of
/// Čistý příjem holds 999 999 Kč with the sign of an estimate, whole (`InvoiceTableColumns`).
struct InvoiceNetIncomeText: View {
    let text: String
    let kind: NetIncomeKind

    var body: some View {
        Text(verbatim: text)
            .fontWeight(.semibold)
            .monospacedDigit()
            .lineLimit(1)
            .foregroundStyle(kind == .paid ? Color(.bannerText) : Color.secondary)
    }
}

/// An amount as its cell shows it, with its currency: digits of one width, on one line. The least width of the columns
/// of amounts holds 999 999,99 in any currency in use (`InvoiceTableColumns`).
struct InvoiceAmountText: View {
    let amount: String

    var body: some View {
        Text(verbatim: amount)
            .monospacedDigit()
            .lineLimit(1)
    }
}

/// The name of the client and, under it, why the search found the invoice: the label of the field and the text around
/// the match, which is highlighted.
private struct ClientCell: View {
    let client: String
    let excerpt: SearchExcerptResult?

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(verbatim: client)
                .lineLimit(1)
                .truncationMode(.tail)
            if let excerpt {
                Text(excerpt.attributedLine)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
        }
    }
}

extension SearchExcerptResult {
    /// "Poznámka: …Routing number…": the label of the field and the text around the match, with the matched text in
    /// bold on a yellow background.
    var attributedLine: AttributedString {
        var line = AttributedString("\(label): ")
        var excerpt = AttributedString(text)
        if let range = Range(highlight, in: excerpt) {
            excerpt[range].backgroundColor = Color.yellow.opacity(0.4)
            excerpt[range].foregroundColor = Color.primary
            excerpt[range].inlinePresentationIntent = .stronglyEmphasized
        }
        line.append(excerpt)
        return line
    }
}

/// The value in crowns of an invoice in a foreign currency, with the line under it that says how it was worked out.
/// Empty for an invoice in crowns. The value looks paid once the money has been received by the day the table is shown
/// as of, not when the status says paid: the status is as of today, so a paid invoice can still show an estimate.
private struct CrownsCell: View {
    let row: InvoiceRow

    var body: some View {
        VStack(alignment: .trailing, spacing: 1) {
            InvoiceAmountText(amount: row.czk)
                .foregroundStyle(row.hasReceivedPayment ? Color.primary : Color.secondary)
            if !row.czkNote.isEmpty {
                InvoiceCaptionText(text: row.czkNote)
            }
        }
    }
}

/// The net income of an invoice, with the line under it that says what the levies took of it, or that the net income
/// is an estimate. A dash has no line. The value is green when the invoice is paid, whatever day the table is shown
/// as of: a payment that comes after that day is a payment still, and its net income is worked out for the year it
/// came in.
private struct NetIncomeCell: View {
    let row: InvoiceRow

    var body: some View {
        VStack(alignment: .trailing, spacing: 1) {
            InvoiceNetIncomeText(text: row.netIncome, kind: row.netIncomeKind)
            if !row.netIncomeNote.isEmpty {
                InvoiceCaptionText(text: row.netIncomeNote)
            }
        }
    }
}

/// The status of an invoice as a tinted pill: grey for a draft, blue for one that waits for payment, red for one past
/// its due date, green for one that is paid, orange for one to check. VoiceOver reads "Stav" and the text.
struct StatusPill: View {
    let status: InvoiceDisplayStatus
    let label: String

    var body: some View {
        Text(verbatim: label)
            .font(.callout.weight(.semibold))
            .lineLimit(1)
            .padding(.horizontal, 8)
            .padding(.vertical, 1)
            .foregroundStyle(colors.foreground)
            .background(colors.background, in: Capsule())
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Stav: \(label)")
    }

    private var colors: (foreground: Color, background: Color) {
        switch status {
        case .draft: (Color.secondary, Color.secondary.opacity(0.16))
        case .needsReview: (Color(.simulationText), Color.orange.opacity(0.16))
        case .awaitingPayment: (Color.accentColor, Color.accentColor.opacity(0.14))
        case .overdue: (Color.red, Color.red.opacity(0.14))
        case .paid: (Color(.bannerText), Color.green.opacity(0.15))
        }
    }
}
