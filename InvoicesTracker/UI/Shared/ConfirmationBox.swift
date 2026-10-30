import SwiftUI

/// A question that a sheet asks itself, in a red box in place of its buttons, before what cannot be undone: the title
/// in bold red, what answering does under it, and the two answers, the one that does it red (#C9221A). Esc is the
/// other one. The sheet asks so rather than in an alert, which would come down over the sheet. A card of Nastavení asks
/// the same way, in place of its note (Odstranit… of a uniform rate entered by hand).
struct ConfirmationBox: View {
    let title: String
    var message: String?

    /// The answer that does nothing, such as Zrušit, and what it does.
    let cancelTitle: String
    let cancel: () -> Void

    /// The answer that does what cannot be undone, such as Smazat šablonu, and what it does.
    let confirmTitle: String
    let confirm: () -> Void

    /// The red of the answer that does it.
    static let destructiveRed = Color(.sRGB, red: 0xC9 / 255, green: 0x22 / 255, blue: 0x1A / 255)

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(verbatim: title)
                .fontWeight(.bold)
                .foregroundStyle(.red)
                .fixedSize(horizontal: false, vertical: true)
            if let message {
                Text(verbatim: message)
                    .font(.callout)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack(spacing: 8) {
                Button(cancelTitle, action: cancel)
                    .buttonStyle(.bordered)
                    .keyboardShortcut(.cancelAction)
                Button(confirmTitle, action: confirm)
                    .buttonStyle(.borderedProminent)
                    .tint(Self.destructiveRed)
            }
            .buttonBorderShape(.capsule)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.red.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
        .accessibilityElement(children: .contain)
        .accessibilityLabel(title)
    }
}
