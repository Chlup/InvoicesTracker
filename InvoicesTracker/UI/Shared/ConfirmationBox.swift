import SwiftUI

/// A question that a sheet asks itself, in a red box in place of its buttons, before what cannot be undone: the title
/// in bold red text, what answering does under it, and the two answers, the one that does it in solid red. Esc is the
/// other one. The sheet asks so rather than in an alert, which would come down over the sheet. A card of Nastavení asks
/// the same way, in place of its note (Odstranit… of a uniform rate entered by hand).
///
/// The answers are the capsules of a dialog, 32 points tall; where the box stands in a card and is given a small
/// control size (`controlSize(.small)`), they are the capsules of a card, 28 points tall.
struct ConfirmationBox: View {
    let title: String
    var message: String?

    /// The answer that does nothing, such as Zrušit, and what it does.
    let cancelTitle: String
    let cancel: () -> Void

    /// The answer that does what cannot be undone, such as Smazat šablonu, and what it does.
    let confirmTitle: String
    let confirm: () -> Void

    @Environment(\.controlSize) private var controlSize

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(verbatim: title)
                .font(Typography.bodyBold)
                .foregroundStyle(Palette.redText)
                .fixedSize(horizontal: false, vertical: true)
            if let message {
                Text(verbatim: message)
                    .font(Typography.callout)
                    .foregroundStyle(Palette.text)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack(spacing: 8) {
                Button(cancelTitle, action: cancel)
                    .buttonStyle(CapsuleButtonStyle(.secondary, size: buttonSize))
                    .keyboardShortcut(.cancelAction)
                Button(confirmTitle, action: confirm)
                    .buttonStyle(CapsuleButtonStyle(.destructiveConfirm, size: buttonSize))
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.redTint, in: RoundedRectangle(cornerRadius: DesignMetrics.panelRadius))
        .accessibilityElement(children: .contain)
        .accessibilityLabel(title)
    }

    /// The size of the answers: a small control size asks for the capsules of a card.
    private var buttonSize: CapsuleButtonSize {
        switch controlSize {
        case .mini, .small: .small
        default: .regular
        }
    }
}
