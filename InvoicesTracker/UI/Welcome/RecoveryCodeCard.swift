import AppKit
import SwiftUI

/// The recovery code as the screens that make a code show it: its caption, the code in eight monospace groups of four,
/// and the two buttons that take it out of the app — "Vytisknout nebo uložit jako PDF…" and "Kopírovat".
///
/// The card keeps nothing of the code beyond the screen that shows it: its only state is whether it was copied.
struct RecoveryCodeCard: View {
    /// The code as the app makes it, such as `K7QF-2MWX-…`.
    let code: String

    /// What the card is headed with, such as "Kód č. 1 · vytvořen 17. 10. 2026".
    let caption: String

    /// What stands beside the caption, such as "32 znaků · velikost písmen ani pomlčky nehrají roli".
    let note: String

    /// The label of the code, such as "kód č. 1 z 17. 10. 2026", for the page that is printed.
    let label: String

    /// What VoiceOver calls the group of characters.
    var accessibilityName = "Kód pro obnovení"

    /// The size of the characters of a group.
    var groupFontSize: CGFloat = 18

    @State private var copied = false

    var body: some View {
        WelcomeBox {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(caption)
                    .fontWeight(.semibold)
                Spacer(minLength: 6)
                Text(note)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4), spacing: 8) {
                ForEach(Array(WelcomeTexts.codeGroups(code).enumerated()), id: \.offset) { _, group in
                    Text(group)
                        .font(.system(size: groupFontSize, weight: .semibold, design: .monospaced))
                        .tracking(2)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
                        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.separator))
                        .accessibilityLabel(group.map(String.init).joined(separator: " "))
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel(accessibilityName)
            HStack(spacing: 8) {
                Button("Vytisknout nebo uložit jako PDF…") {
                    RecoveryCodePrinter.print(code: code, label: label)
                }
                .welcomeBoxButton()
                Button(copied ? "Zkopírováno ✓" : "Kopírovat") {
                    copy()
                }
                .welcomeBoxButton()
            }
        }
    }

    /// Puts the code on the pasteboard, which is the person's own act. The pasteboard is asked to keep it on this Mac,
    /// out of the Universal Clipboard, and clipboard managers that honour the marker of concealed items leave it out of
    /// their history.
    private func copy() {
        let pasteboard = NSPasteboard.general
        pasteboard.prepareForNewContents(with: [.currentHostOnly])
        pasteboard.setString(code, forType: .string)
        pasteboard.setString("", forType: NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType"))
        copied = true
    }
}
