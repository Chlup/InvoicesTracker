import SwiftUI

/// The field that asks for a recovery code, as every screen that asks for one has it: one monospace field, under the
/// label that names the code that is needed. What is typed is read as the code (`RecoveryCode.normalize`) wherever it
/// is used, so case, spaces and dashes do not matter, and a 0 is read as an O and a 1 as an I, as the code has neither
/// digit. The letters show in capitals as they are typed, as the code is printed.
struct RecoveryCodeField: View {
    /// What names the code that is needed, such as "Kód pro obnovení – kód č. 1 z 17. 10. 2026".
    let label: String

    @Binding var text: String

    /// What is wrong with the code that was typed, or nil.
    var errorText: String?

    /// What Return in the field does.
    var submit: () -> Void = {}

    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(Typography.callout)
                .foregroundStyle(Palette.text2)
                // The field has it as its own label.
                .accessibilityHidden(true)
            TextField("", text: shownText, prompt: Text(verbatim: "XXXX-XXXX-XXXX-XXXX-XXXX-XXXX-XXXX-XXXX"))
                .textFieldStyle(.roundedBorder)
                .font(Typography.bodyMonospaced)
                .controlSize(.large)
                .autocorrectionDisabled()
                .focused($isFocused)
                .onSubmit(submit)
                .overlay(
                    RoundedRectangle(cornerRadius: DesignMetrics.controlRadius)
                        .strokeBorder(Palette.red, lineWidth: errorText == nil ? 0 : 1.5)
                )
                .accessibilityLabel(label)
            Text("Velikost písmen, mezery a pomlčky nehrají roli.")
                .font(Typography.callout)
                .foregroundStyle(Palette.text3)
            if let errorText {
                WelcomeErrorLine(text: errorText)
            }
        }
        .task { isFocused = true }
    }

    /// The text with its letters in capitals: what is typed, and what is pasted, goes into the binding as the code is
    /// printed.
    private var shownText: Binding<String> {
        Binding(get: { text }, set: { text = Self.shown($0) })
    }

    /// `typed` with its letters of the alphabet in capitals. Only those change: a key of the Czech number row (ě š č ř
    /// ž ý) stays as it is, which `RecoveryCode.normalize` reads as the digit it types, and spaces and dashes stay too.
    nonisolated static func shown(_ typed: String) -> String {
        String(
            typed.map { character in
                guard let ascii = character.asciiValue, (UInt8(ascii: "a")...UInt8(ascii: "z")).contains(ascii) else {
                    return character
                }
                return Character(UnicodeScalar(ascii - UInt8(ascii: "a") + UInt8(ascii: "A")))
            })
    }
}

/// A card that asks for a recovery code: the key symbol, the title and the text, the field with its error, what the
/// screen adds under it (the explanation of "Nemám kód"), and the two buttons that end the card. The unlocking of a new
/// Mac and of a backup are both this card.
struct RecoveryCodeAsk<Extra: View>: View {
    let title: String
    let text: String

    /// The label of the field, which names the code that is needed.
    let fieldLabel: String

    @Binding var typed: String
    var errorText: String?
    var isWorking = false

    /// The button on the left and what it does, and whether Esc does the same.
    let backTitle: String
    let back: () -> Void
    var backIsCancel = false

    /// The button on the right, which sends the code, and what it does.
    let submitTitle: String
    let submit: () -> Void

    @ViewBuilder let extra: Extra

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // The key lies on its side with its bow at the left, as the design draws it: the symbol has its bow at the
            // right, so it is mirrored.
            Image(systemName: "key.horizontal")
                .font(Typography.symbolCompact)
                .scaleEffect(x: -1, y: 1)
                .foregroundStyle(Palette.text2)
                .frame(width: 44, height: 44)
                .background(Palette.fill, in: Circle())
                .accessibilityHidden(true)
            WelcomeHeading(title: title, text: text)
                .padding(.top, 4)
        }
        RecoveryCodeField(label: fieldLabel, text: $typed, errorText: errorText, submit: submit)
        extra
        WelcomeFooter(
            backTitle: backTitle, back: back, backIsCancel: backIsCancel, isWorking: isWorking, goTitle: submitTitle,
            go: submit)
    }
}
