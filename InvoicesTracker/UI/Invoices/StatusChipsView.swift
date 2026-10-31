import SwiftUI

/// The segmented control that chooses which invoices the list holds, "Vystavené" or "Zaplacené", those issued in the
/// year or those paid in it. The year is the toolbar's to say. VoiceOver reads it as a group "Které faktury" with a
/// button for each segment (`SegmentedControl`).
struct ScopePicker: View {
    @Binding var scope: InvoiceScope

    var body: some View {
        SegmentedControl(
            "Které faktury", selection: $scope,
            segments: [
                (value: InvoiceScope.issued, title: "Vystavené"), (value: InvoiceScope.paid, title: "Zaplacené"),
            ]
        )
    }
}

/// The status chips with the number of invoices each has: "Vše 12", "Koncepty 1", … The chosen one is filled with the
/// accent (`FilterChip`). The chips stand in a line, 6 points apart, and wrap where the room is narrower than they are.
/// The chip for the invoices to check is among them only while it has an invoice or is the chosen one
/// (`InvoiceListData`).
struct StatusChipsView: View {
    let chips: [InvoiceStatusFilter]
    let counts: [InvoiceStatusFilter: Int]
    @Binding var selection: InvoiceStatusFilter

    var body: some View {
        FlowLayout(spacing: 6) {
            ForEach(chips, id: \.self) { chip in
                FilterChip("\(chip.title) \(counts[chip, default: 0])", isSelected: chip == selection) {
                    selection = chip
                }
            }
        }
    }
}
