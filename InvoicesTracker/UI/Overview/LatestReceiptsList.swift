import SwiftUI

/// The card "Poslední přijaté platby": the newest payments of the year up to the day shown, each with the invoice it
/// paid, what it was worth in crowns and what it added to the levies. A payment opens its invoice in Faktury.
struct LatestReceiptsList: View {
    let receipts: [LatestReceipt]

    /// A payment was chosen: shows the invoice with this id.
    let open: (Int64) -> Void

    /// Všechny faktury.
    let showInvoices: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text("Poslední přijaté platby")
                    .font(.title3.weight(.semibold))
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength: 0)
                Button("Všechny faktury", action: showInvoices)
                    .buttonStyle(.link)
                    .font(.callout)
            }
            if receipts.isEmpty {
                Text("Do tohoto dne nepřišla žádná platba.")
                    .foregroundStyle(.secondary)
                    .padding(.top, 8)
                    .padding(.bottom, 14)
            }
            VStack(spacing: 0) {
                ForEach(receipts, id: \.invoiceID) { receipt in
                    Divider()
                    Button {
                        open(receipt.invoiceID)
                    } label: {
                        row(receipt)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(.horizontal, 22)
        .padding(.top, 18)
        .padding(.bottom, 10)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .screenCard()
    }

    /// The client in bold and the number of the invoice after it, as one line that is cut at its end when it is long.
    private func title(of receipt: LatestReceipt) -> Text {
        let client = Text(verbatim: receipt.client).fontWeight(.semibold)
        let number = Text(verbatim: receipt.number).foregroundStyle(.secondary)
        return Text("\(client) · \(number)")
    }

    /// The day, the client with the number of the invoice and how it was written, and the income with the levies.
    private func row(_ receipt: LatestReceipt) -> some View {
        HStack(spacing: 14) {
            Text(receipt.date)
                .fontWeight(.semibold)
                .monospacedDigit()
                .frame(width: 52, alignment: .leading)
            VStack(alignment: .leading, spacing: 2) {
                title(of: receipt)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Text(receipt.original)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            VStack(alignment: .trailing, spacing: 2) {
                Text(receipt.czk)
                    .fontWeight(.semibold)
                    .monospacedDigit()
                Text(verbatim: "odvody " + receipt.effect)
                    .font(.callout)
                    .foregroundStyle(Color(.attentionText))
                    .monospacedDigit()
            }
        }
        .padding(.vertical, 10)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}
