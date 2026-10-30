import SwiftUI

/// The table of Odběratelé, in a card of its own: a row of two lines, at least 60 points high, for every client, with
/// Odběratel (the name, and under it the city, the country unless it is Česko, and the IČO), Měna a DPH, Jazyk faktury,
/// Rok Y (what the client paid in the year, how many of its invoices were issued in it, and the day of the last one), a
/// chevron and the button Nová faktura. The names of the columns stay above the rows.
///
/// The table is as wide as its card: its columns grow and shrink with the card (`ClientTableColumns`) down to the least
/// width of the table, below which the table keeps that width and scrolls sideways.
///
/// A click on a row anywhere but on Nová faktura opens the form of its client (`edit`), and Nová faktura opens the
/// editor on a blank invoice for the client (`newInvoice`). VoiceOver reads each row as a button that names the columns
/// (`ClientRow.spokenText(year:)`) with the hint "Otevře úpravu odběratele.", and Nová faktura as a button of its own,
/// "Nová faktura pro" and the client.
struct ClientTableView: View {
    let rows: [ClientRow]

    /// The year the rows are about, which the fourth column is named after.
    let year: Int

    /// A row was clicked, or pressed with VoiceOver.
    let edit: (Int64) -> Void

    /// Nová faktura of a row was clicked, or pressed with VoiceOver.
    let newInvoice: (Int64) -> Void

    /// The width of the card, which the table fills where it is more than the least width of the table.
    @State private var visibleWidth: CGFloat = 0

    var body: some View {
        let width = max(visibleWidth, ClientTableColumns.minimumWidth)
        let columns = ClientTableColumns.columnWidths(inTableOf: width)
        ScrollView(.horizontal) {
            VStack(alignment: .leading, spacing: 0) {
                header(columns: columns)
                ForEach(rows) { row in
                    Divider()
                    rowView(row, columns: columns)
                }
            }
            .frame(width: width, alignment: .leading)
        }
        .onGeometryChange(for: CGFloat.self) { proxy in
            proxy.size.width
        } action: { width in
            visibleWidth = width
        }
        .clipShape(RoundedRectangle(cornerRadius: DesignMetrics.cardRadius))
        .card()
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Seznam odběratelů")
    }

    // MARK: The names of the columns

    private func header(columns: [CGFloat]) -> some View {
        HStack(spacing: ClientTableColumns.columnGap) {
            Text("Odběratel")
                .clientColumnTitle()
                .frame(width: columns[0], alignment: .leading)
            Text("Měna a DPH")
                .clientColumnTitle()
                .frame(width: columns[1], alignment: .leading)
            Text("Jazyk faktury")
                .clientColumnTitle()
                .frame(width: columns[2], alignment: .leading)
            Text(verbatim: "Rok \(year)")
                .clientColumnTitle()
                .frame(width: columns[3], alignment: .trailing)
            Color.clear
                .frame(width: columns[4], height: 1)
        }
        .padding(.leading, ClientTableColumns.margin)
        .padding(.trailing, trailingRoom)
        .padding(.top, 12)
        .padding(.bottom, 8)
        // Each row says the names of its columns itself.
        .accessibilityHidden(true)
    }

    /// The room after the chevron: up to the button Nová faktura, its room, and the margin.
    private var trailingRoom: CGFloat {
        ClientTableColumns.margin + ClientTableColumns.buttonGap + ClientTableColumns.buttonRoom
    }

    // MARK: A row

    /// The row is a button over its whole width, and Nová faktura a button of its own on top of it, at its end.
    private func rowView(_ row: ClientRow, columns: [CGFloat]) -> some View {
        ZStack(alignment: .trailing) {
            Button {
                edit(row.id)
            } label: {
                HStack(spacing: ClientTableColumns.columnGap) {
                    NameCell(name: row.name, detail: row.detailLine)
                        .frame(width: columns[0], alignment: .leading)
                    ClientCurrencyCell(currency: row.currency, vat: row.vatShort)
                        .frame(width: columns[1], alignment: .leading)
                    Text(verbatim: row.language)
                        .lineLimit(1)
                        .frame(width: columns[2], alignment: .leading)
                    ClientYearCell(row: row)
                        .frame(width: columns[3], alignment: .trailing)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.tertiary)
                        .frame(width: columns[4])
                }
                .padding(.leading, ClientTableColumns.margin)
                .padding(.trailing, trailingRoom)
                .padding(.vertical, 10)
                .frame(maxWidth: .infinity, minHeight: 60, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text(verbatim: row.spokenText(year: year)))
            .accessibilityHint("Otevře úpravu odběratele.")
            newInvoiceButton(row)
                .padding(.trailing, ClientTableColumns.margin)
        }
    }

    private func newInvoiceButton(_ row: ClientRow) -> some View {
        Button {
            newInvoice(row.id)
        } label: {
            ClientNewInvoiceLabel()
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(verbatim: "Nová faktura pro \(row.name)"))
    }
}

// MARK: - Cells

/// The name of the client and, under it, its city, its country unless it is Česko, and its IČO.
private struct NameCell: View {
    let name: String
    let detail: String

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(verbatim: name)
                .fontWeight(.semibold)
                .lineLimit(1)
                .truncationMode(.tail)
            Text(verbatim: detail)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.tail)
        }
    }
}

/// The currency of the client in a small grey tag, and its VAT mode in a few words. The least width of Měna a DPH holds
/// the widest of them whole (`ClientTableColumns`).
struct ClientCurrencyCell: View {
    let currency: String
    let vat: String

    var body: some View {
        HStack(spacing: 8) {
            Text(verbatim: currency)
                .font(.system(size: 12, weight: .semibold))
                .lineLimit(1)
                .padding(.horizontal, 7)
                .padding(.vertical, 1)
                .background(Color.secondary.opacity(0.14), in: RoundedRectangle(cornerRadius: 6))
                .fixedSize()
            Text(verbatim: vat)
                .lineLimit(1)
                .truncationMode(.tail)
        }
    }
}

/// What the client paid in the year, in grey where it paid nothing, and under it the count of its invoices. The least
/// width of Rok Y holds the longest of the lines whole (`ClientTableColumns`).
struct ClientYearCell: View {
    let row: ClientRow

    var body: some View {
        VStack(alignment: .trailing, spacing: 1) {
            Text(verbatim: row.received)
                .fontWeight(.semibold)
                .foregroundStyle(row.hasReceived ? Color.primary : Color.secondary)
                .lineLimit(1)
            Text(verbatim: row.countLine)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .monospacedDigit()
    }
}

/// The pill Nová faktura at the end of a row: blue words on a capsule with a hairline edge, 30 points high. It fits the
/// room of the button (`ClientTableColumns.buttonRoom`).
struct ClientNewInvoiceLabel: View {
    var body: some View {
        Text("Nová faktura")
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(Color.accentColor)
            .lineLimit(1)
            .padding(.horizontal, 12)
            .frame(height: 30)
            .background(Color(nsColor: .controlBackgroundColor), in: Capsule())
            .overlay(Capsule().strokeBorder(.separator))
            .contentShape(Capsule())
    }
}

extension View {
    /// The name of a column above the rows: 12 points, semibold, in grey, on one line. The least width of a column
    /// holds its name whole (`ClientTableColumns`).
    func clientColumnTitle() -> some View {
        font(.system(size: 12, weight: .semibold))
            .foregroundStyle(.secondary)
            .lineLimit(1)
    }
}
