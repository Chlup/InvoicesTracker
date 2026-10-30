import SwiftUI

/// The segmented control that chooses which invoices the list holds: "Vystavené v roce 2026" or "Zaplacené v roce
/// 2026".
struct ScopePicker: View {
    let year: Int
    @Binding var scope: InvoiceScope

    var body: some View {
        Picker("Které faktury", selection: $scope) {
            Text("Vystavené v roce \(String(year))")
                .tag(InvoiceScope.issued)
            Text("Zaplacené v roce \(String(year))")
                .tag(InvoiceScope.paid)
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .fixedSize()
        .accessibilityLabel("Které faktury")
    }
}

/// The status chips with the number of invoices each has: "Vše 12", "Koncepty 1", … The chosen one is filled. The chip
/// for the invoices to check is among them only while it has an invoice or is the chosen one (`InvoiceListData`).
struct StatusChipsView: View {
    let chips: [InvoiceStatusFilter]
    let counts: [InvoiceStatusFilter: Int]
    @Binding var selection: InvoiceStatusFilter

    var body: some View {
        HStack(spacing: 6) {
            ForEach(chips, id: \.self) { chip in
                StatusChip(title: "\(chip.title) \(counts[chip, default: 0])", isOn: chip == selection) {
                    selection = chip
                }
            }
        }
    }
}

private struct StatusChip: View {
    let title: String
    let isOn: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(verbatim: title)
                .font(.callout.weight(.semibold))
                .monospacedDigit()
                .lineLimit(1)
                .padding(.horizontal, 12)
                .frame(height: 28)
                .foregroundStyle(isOn ? Color(nsColor: .windowBackgroundColor) : Color.primary)
                .background(isOn ? Color.primary : Color(nsColor: .controlBackgroundColor), in: Capsule())
                .overlay(Capsule().strokeBorder(.separator, lineWidth: isOn ? 0 : 1))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}
