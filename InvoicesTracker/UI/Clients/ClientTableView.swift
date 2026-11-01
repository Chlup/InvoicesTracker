import SwiftUI

/// The table of Odběratelé in a card of its own, the table of Faktury with the columns of the clients: on top the
/// summary row, how many clients and templates of invoices there are and the money that came from the clients in the
/// year, in whole Kč (`TableSummaryRow`); under it the names of the columns, 32 points high, and the rows, 40 points
/// high with one line of text each: Odběratel (the name), Měna a DPH (the code of the currency in a grey chip, and the
/// VAT mode in a few words), Šablony (how many templates the client has, or "žádná") and Přijato Y (what came from the
/// client in the year, or a dash). The row of the selected client is tinted pale blue, with a blue edge on its leading
/// side. Without a client the table says so in a row under the names of the columns.
///
/// The table is as wide as its card: its columns grow and shrink with the card (`ClientTableColumns`) down to the least
/// width of the table, below which the table keeps that width and scrolls sideways under the summary row, which stays
/// as wide as the card and wraps in it. The names of the columns stay at the top while the rows scroll, and the rows
/// scroll to the selected one where it is not shown, also when the client was selected before its row came, as a
/// client that was just saved is.
///
/// A click on a row selects its client, and a click on the selected row clears the selection (`click`). VoiceOver reads
/// the card as "Seznam odběratelů", the summary row as a group "Souhrn" and each row as a button that names the columns
/// (`ClientRow.spokenText(receivedHeader:)`), says which row is selected, and presses a row as a click does.
struct ClientTableView: View {
    /// The rows, the summary and the name of the column of the money received.
    let data: ClientsData

    /// The id of the selected client, whose row is tinted.
    let selectedID: Int64?

    /// A row was clicked, or pressed with VoiceOver.
    let click: (Int64) -> Void

    /// The width of the card, which the table fills where it is more than the least width of the table.
    @State private var visibleWidth: CGFloat = 0

    /// Where the rows are scrolled to, which the table moves to show the selected row.
    @State private var rowsPosition = ScrollPosition(idType: Int64.self)

    var body: some View {
        VStack(spacing: 0) {
            TableSummaryRow(count: data.countText, category: data.templatesText) {
                SummaryFigure(label: "Celkem přijato bez DPH", value: data.totalText)
            }
            table
        }
        .clipShape(RoundedRectangle(cornerRadius: DesignMetrics.cardRadius))
        .card()
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Seznam odběratelů")
    }

    /// The id of the selected client while the table has its row, which the rows scroll to: it changes when another
    /// row is selected, and when the row of a client that was selected before it was loaded comes.
    private var shownSelection: Int64? {
        guard let selectedID, data.rows.contains(where: { $0.id == selectedID }) else { return nil }
        return selectedID
    }

    // MARK: The table

    /// The names of the columns and the rows under them, as wide as the card or as the least width of the table,
    /// whichever is more, in a view that scrolls sideways. The rows scroll up and down under the names.
    private var table: some View {
        let width = max(visibleWidth, ClientTableColumns.minimumWidth)
        let widths = ClientTableColumns.columnWidths(inTableOf: width)
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
                .onChange(of: shownSelection) { _, id in
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

    /// The names of the columns, in the style of the header of a table, the money received aligned to the right as its
    /// column is. Each row says the names of its columns itself, so VoiceOver does not read them.
    private func header(widths: [CGFloat]) -> some View {
        HStack(spacing: ClientTableColumns.gap) {
            title("Odběratel", width: widths[0])
            title("Měna a DPH", width: widths[1])
            title("Šablony", width: widths[2])
            Text(verbatim: data.receivedHeader)
                .tableHeaderStyle()
                .frame(width: widths[3], alignment: .trailing)
        }
        .padding(.horizontal, DataTableMetrics.margin)
        .accessibilityHidden(true)
    }

    /// The name `title` of a column `width` points wide, at its leading side.
    private func title(_ title: LocalizedStringKey, width: CGFloat) -> some View {
        Text(title)
            .tableHeaderStyle()
            .frame(width: width, alignment: .leading)
    }

    // MARK: A row

    /// The row of `row` as a button: its cells, the tint of the selected row behind them and the hairline across its
    /// top.
    private func rowView(_ row: ClientRow, widths: [CGFloat]) -> some View {
        let isSelected = row.id == selectedID
        return Button {
            click(row.id)
        } label: {
            ClientRowCells(row: row, widths: widths)
                .tableRowBackground(isSelected: isSelected)
                .overlay(alignment: .top) {
                    Hairline()
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(TableRowButtonStyle())
        .accessibilityLabel(Text(verbatim: row.spokenText(receivedHeader: data.receivedHeader)))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

// MARK: - Cells

/// The cells of a row of the table of Odběratelé, one line each, in the widths of the columns (`ClientTableColumns`)
/// with the gap of the table between them and its margin at the ends, in a row 40 points high.
struct ClientRowCells: View {
    let row: ClientRow

    /// The widths of the four columns, in their order.
    let widths: [CGFloat]

    var body: some View {
        HStack(spacing: ClientTableColumns.gap) {
            ClientNameCell(name: row.name)
                .frame(width: widths[0], alignment: .leading)
            ClientCurrencyCell(currency: row.currency, vat: row.vatShort)
                .frame(width: widths[1], alignment: .leading)
            ClientTemplatesCell(row: row)
                .frame(width: widths[2], alignment: .leading)
            ClientReceivedCell(row: row)
                .frame(width: widths[3], alignment: .trailing)
        }
        .padding(.horizontal, DataTableMetrics.margin)
        .frame(height: DataTableMetrics.rowHeight)
    }
}

/// The name of the client: body semibold in the colour of text, on one line, cut short at its end where the column is
/// narrower than the name.
struct ClientNameCell: View {
    let name: String

    var body: some View {
        Text(verbatim: name)
            .font(Typography.bodySemibold)
            .foregroundStyle(Palette.text)
            .lineLimit(1)
            .truncationMode(.tail)
    }
}

/// The code of the currency of the client in a small chip, callout semibold on the grey fill, and after it the VAT mode
/// in a few words, in body and secondary text. Where the column is narrower than the two, as it can be at its least
/// width (`ClientTableColumns`), the VAT text is cut at its tail on its one line and the chip stays whole, as the
/// prototype draws the cell; VoiceOver reads the whole text with the row (`ClientRow.spokenText(receivedHeader:)`).
struct ClientCurrencyCell: View {
    let currency: String
    let vat: String

    var body: some View {
        HStack(spacing: 8) {
            Text(verbatim: currency)
                .font(Typography.calloutSemibold)
                .foregroundStyle(Palette.text)
                .lineLimit(1)
                .padding(.horizontal, 7)
                .padding(.vertical, 1)
                .background(Palette.fill, in: RoundedRectangle(cornerRadius: DesignMetrics.controlRadius))
                .fixedSize()
            Text(verbatim: vat)
                .font(Typography.body)
                .foregroundStyle(Palette.text2)
                .lineLimit(1)
                .truncationMode(.tail)
        }
    }
}

/// How many templates the client has, in body and the colour of text with digits of one width, or "žádná" in the grey
/// of notes. The least width of Šablony holds the longest of them whole (`ClientTableColumns`).
struct ClientTemplatesCell: View {
    let row: ClientRow

    var body: some View {
        Text(verbatim: row.templates)
            .font(Typography.body)
            .monospacedDigit()
            .foregroundStyle(row.hasTemplates ? Palette.text : Palette.text3)
            .lineLimit(1)
            .truncationMode(.tail)
    }
}

/// The money that came from the client in the year, in whole Kč: body semibold in the colour of text, with digits of
/// one width, or a dash in the grey of notes where nothing came. The least width of Přijato Y holds the widest amount
/// whole (`ClientTableColumns`).
struct ClientReceivedCell: View {
    let row: ClientRow

    var body: some View {
        Text(verbatim: row.received)
            .font(Typography.bodySemibold)
            .monospacedDigit()
            .foregroundStyle(row.hasReceived ? Palette.text : Palette.text3)
            .lineLimit(1)
    }
}
