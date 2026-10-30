import SwiftUI

/// A client to choose: a pill that is dark while it is chosen. The editor of an invoice and the form of a template
/// choose their client with a row of them.
struct ClientChip: View {
    let name: String
    let isOn: Bool
    let pick: () -> Void

    var body: some View {
        Button(action: pick) {
            Text(verbatim: name)
                .fontWeight(isOn ? .semibold : .medium)
                .foregroundStyle(isOn ? Color(nsColor: .textBackgroundColor) : Color.primary)
                .padding(.horizontal, 12)
                .frame(height: 30)
                .background(isOn ? Color.primary : Color.secondary.opacity(0.12), in: Capsule())
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}
