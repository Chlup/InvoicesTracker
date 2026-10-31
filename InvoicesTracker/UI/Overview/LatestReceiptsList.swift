import SwiftUI

/// The sizes and gaps of the card of the latest payments.
private nonisolated enum LatestReceiptsMetrics {
    /// The space between the heading and the rows, and under the empty line.
    static let spacing: CGFloat = 6

    /// The space between the card and the rows at its foot, which have a padding of their own.
    static let bottomPadding: CGFloat = 10

    /// The space between the heading and its link.
    static let headingSpacing: CGFloat = 12

    /// The space above and below a row.
    static let rowPadding: CGFloat = 10

    /// The space between the columns of a row.
    static let columnSpacing: CGFloat = 14

    /// The width of the column of the day.
    static let dayWidth: CGFloat = 52

    /// The space between the two lines of a column of a row.
    static let lineSpacing: CGFloat = 2
}

/// The card "Poslední přijaté platby": the newest payments of the year up to the day shown, each with the invoice it
/// paid, what it was worth in crowns and what it added to the levies. A payment opens its invoice in Faktury. The card
/// is padded 20 points, 10 at its foot, where the last row has a padding of its own, and a hairline stands above every
/// row. The link Všechny faktury is at the end of the heading.
struct LatestReceiptsList: View {
    let receipts: [LatestReceipt]

    /// A payment was chosen: shows the invoice with this id.
    let open: (Int64) -> Void

    /// Všechny faktury.
    let showInvoices: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: LatestReceiptsMetrics.spacing) {
            HStack(alignment: .firstTextBaseline, spacing: LatestReceiptsMetrics.headingSpacing) {
                Text("Poslední přijaté platby")
                    .font(Typography.title3)
                    .foregroundStyle(Palette.text)
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength: 0)
                Button("Všechny faktury", action: showInvoices)
                    .calloutLink()
            }
            if receipts.isEmpty {
                Text("Do tohoto dne nepřišla žádná platba.")
                    .font(Typography.body)
                    .foregroundStyle(Palette.text2)
                    .padding(.top, 8)
                    .padding(.bottom, 14)
            }
            VStack(spacing: 0) {
                ForEach(receipts, id: \.invoiceID) { receipt in
                    Hairline()
                    Button {
                        open(receipt.invoiceID)
                    } label: {
                        row(receipt)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(.horizontal, DesignMetrics.cardPadding)
        .padding(.top, DesignMetrics.cardPadding)
        .padding(.bottom, LatestReceiptsMetrics.bottomPadding)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .card()
    }

    /// The client in semibold and the number of the invoice after it in grey, as one line that is cut at its end when
    /// it is long.
    private func title(of receipt: LatestReceipt) -> Text {
        let client = Text(verbatim: receipt.client)
            .font(Typography.bodySemibold)
            .foregroundStyle(Palette.text)
        let number = Text(verbatim: " · " + receipt.number)
            .font(Typography.body)
            .foregroundStyle(Palette.text2)
        return Text("\(client)\(number)")
    }

    /// The day, the client with the number of the invoice and how it was written, and the income with the levies.
    private func row(_ receipt: LatestReceipt) -> some View {
        HStack(spacing: LatestReceiptsMetrics.columnSpacing) {
            Text(verbatim: receipt.date)
                .font(Typography.bodySemibold)
                .foregroundStyle(Palette.text)
                .monospacedDigit()
                .frame(width: LatestReceiptsMetrics.dayWidth, alignment: .leading)
            VStack(alignment: .leading, spacing: LatestReceiptsMetrics.lineSpacing) {
                title(of: receipt)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Text(verbatim: receipt.original)
                    .font(Typography.callout)
                    .foregroundStyle(Palette.text2)
                    .monospacedDigit()
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            VStack(alignment: .trailing, spacing: LatestReceiptsMetrics.lineSpacing) {
                Text(verbatim: receipt.czk)
                    .font(Typography.bodySemibold)
                    .foregroundStyle(Palette.text)
                    .monospacedDigit()
                Text(verbatim: "odvody " + receipt.effect)
                    .font(Typography.callout)
                    .foregroundStyle(Palette.orangeText)
                    .monospacedDigit()
            }
        }
        .padding(.vertical, LatestReceiptsMetrics.rowPadding)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}
