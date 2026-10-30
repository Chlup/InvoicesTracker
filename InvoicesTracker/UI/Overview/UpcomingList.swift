import SwiftUI

/// The card "Nejbližší platby úřadům": the next payments after the day shown — the advances of the coming months and
/// the VAT returns not due yet — each with its day, what it is and how much. An advance leads to the plan of advances,
/// a VAT return to Faktury.
struct UpcomingList: View {
    let items: [UpcomingItem]

    /// An advance was chosen.
    let showAdvances: () -> Void

    /// A VAT return was chosen.
    let showInvoices: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text("Nejbližší platby úřadům")
                    .font(.title3.weight(.semibold))
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength: 0)
                Button("Plán záloh", action: showAdvances)
                    .buttonStyle(.link)
                    .font(.callout)
            }
            if items.isEmpty {
                Text("V tomto roce už žádná další platba není.")
                    .foregroundStyle(.secondary)
                    .padding(.top, 8)
                    .padding(.bottom, 14)
            }
            VStack(spacing: 0) {
                ForEach(items, id: \.title) { item in
                    Divider()
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
        .padding(.horizontal, 22)
        .padding(.top, 18)
        .padding(.bottom, 10)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .card()
    }

    /// The badge with the day, what is due with a dot that tells an advance from a VAT return, and the amount.
    private func row(_ item: UpcomingItem) -> some View {
        HStack(spacing: 14) {
            VStack(spacing: 0) {
                Text(item.day)
                    .font(.system(size: 14, weight: .bold))
                Text(item.month)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .frame(width: 52, height: 44)
            .background(.quaternary, in: RoundedRectangle(cornerRadius: 10))
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Circle()
                        .fill(Color.primary.opacity(item.isVAT ? 0.35 : 0.75))
                        .frame(width: 8, height: 8)
                        .accessibilityHidden(true)
                    Text(item.title)
                        .fontWeight(.semibold)
                }
                Text(item.subtitle)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Text(item.amount)
                .fontWeight(.semibold)
                .monospacedDigit()
        }
        .padding(.vertical, 9)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}
