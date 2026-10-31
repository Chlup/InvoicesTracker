import SwiftUI

/// The sizes and gaps of the card of the upcoming payments.
private nonisolated enum UpcomingMetrics {
    /// The space between the heading and the rows, and under the empty line.
    static let spacing: CGFloat = 6

    /// The space between the card and the rows at its foot, which have a padding of their own.
    static let bottomPadding: CGFloat = 10

    /// The space between the heading and its link.
    static let headingSpacing: CGFloat = 12

    /// The space above and below a row.
    static let rowPadding: CGFloat = 9

    /// The space between the columns of a row.
    static let columnSpacing: CGFloat = 14

    /// The size of the badge with the day.
    static let badgeSize = CGSize(width: 52, height: 44)

    /// The size of the dot in front of the title.
    static let dotSize: CGFloat = 8

    /// The space between the dot and the title.
    static let dotSpacing: CGFloat = 6

    /// The space between the title of a row and the line under it.
    static let lineSpacing: CGFloat = 2
}

/// The card "Nejbližší platby úřadům": the next payments after the day shown — the advances of the coming months and
/// the VAT returns not due yet — each with its day, what it is and how much. An advance leads to the plan of advances,
/// a VAT return to Faktury. The card is padded like the one of the latest payments, with a hairline above every row;
/// the badge with the day is a panel of the inset colour, and the dot in front of the title is grey for an advance
/// and fainter for a VAT return.
struct UpcomingList: View {
    let items: [UpcomingItem]

    /// An advance was chosen.
    let showAdvances: () -> Void

    /// A VAT return was chosen.
    let showInvoices: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: UpcomingMetrics.spacing) {
            HStack(alignment: .firstTextBaseline, spacing: UpcomingMetrics.headingSpacing) {
                Text("Nejbližší platby úřadům")
                    .font(Typography.title3)
                    .foregroundStyle(Palette.text)
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength: 0)
                Button("Plán záloh", action: showAdvances)
                    .calloutLink()
            }
            if items.isEmpty {
                Text("V tomto roce už žádná další platba není.")
                    .font(Typography.body)
                    .foregroundStyle(Palette.text2)
                    .padding(.top, 8)
                    .padding(.bottom, 14)
            }
            VStack(spacing: 0) {
                ForEach(items, id: \.title) { item in
                    Hairline()
                    Button {
                        if item.isVAT {
                            showInvoices()
                        } else {
                            showAdvances()
                        }
                    } label: {
                        row(item)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(.horizontal, DesignMetrics.cardPadding)
        .padding(.top, DesignMetrics.cardPadding)
        .padding(.bottom, UpcomingMetrics.bottomPadding)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .card()
    }

    /// The badge with the day, what is due with a dot that tells an advance from a VAT return, and the amount.
    private func row(_ item: UpcomingItem) -> some View {
        HStack(spacing: UpcomingMetrics.columnSpacing) {
            VStack(spacing: 0) {
                Text(verbatim: item.day)
                    .font(Typography.bodyBold)
                    .foregroundStyle(Palette.text)
                Text(verbatim: item.month)
                    .font(Typography.subheadline)
                    .foregroundStyle(Palette.text2)
            }
            .frame(width: UpcomingMetrics.badgeSize.width, height: UpcomingMetrics.badgeSize.height)
            .background(Palette.bgInset, in: RoundedRectangle(cornerRadius: DesignMetrics.panelRadius))
            VStack(alignment: .leading, spacing: UpcomingMetrics.lineSpacing) {
                HStack(spacing: UpcomingMetrics.dotSpacing) {
                    Circle()
                        .fill(item.isVAT ? Palette.text4 : Palette.text2)
                        .frame(width: UpcomingMetrics.dotSize, height: UpcomingMetrics.dotSize)
                        .accessibilityHidden(true)
                    Text(verbatim: item.title)
                        .font(Typography.bodySemibold)
                        .foregroundStyle(Palette.text)
                }
                Text(verbatim: item.subtitle)
                    .font(Typography.callout)
                    .foregroundStyle(Palette.text2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Text(verbatim: item.amount)
                .font(Typography.bodySemibold)
                .foregroundStyle(Palette.text)
                .monospacedDigit()
        }
        .padding(.vertical, UpcomingMetrics.rowPadding)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}
