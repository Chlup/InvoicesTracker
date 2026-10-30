import SwiftUI

/// A capsule 28 points tall that chooses one of several filters, such as the states of the invoices: the chosen one is
/// filled with the accent and has its title in semibold on it, the others stand off the page in the colour of a card
/// with a title in medium. VoiceOver reads each as a button that is selected while it is chosen.
struct FilterChip: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    /// A chip that reads `title`, is filled while `isSelected`, and runs `action` when it is clicked.
    init(_ title: String, isSelected: Bool, action: @escaping () -> Void) {
        self.title = title
        self.isSelected = isSelected
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            ChoiceText(title: title, font: isSelected ? Typography.bodySemibold : Typography.body.weight(.medium))
                .foregroundStyle(isSelected ? Palette.onAccent : Palette.text)
                .padding(.horizontal, 12)
                .frame(height: DesignMetrics.smallControlHeight)
                .background { capsule }
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    /// The capsule behind the title: the accent while the chip is chosen, the colour of a card and raised otherwise.
    @ViewBuilder
    private var capsule: some View {
        if isSelected {
            Capsule().fill(Palette.accent)
        } else {
            Capsule().fill(Palette.bgCard).elevation(.control)
        }
    }
}
