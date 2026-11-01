import SwiftUI

/// The question and the field that confirm what cannot be undone by the number of an invoice, "Pro potvrzení napište
/// číslo faktury 20260901": the dialog that deletes an invoice and the step of the payment sheet that removes its
/// payment ask it alike. The field takes the focus when it appears, so what is typed goes into it at once, and it is
/// framed in red once what is typed is the number (or the digits of it), which is when the button that does it turns
/// on. Return in the field does what that button does.
struct NumberConfirmationField: View {
    /// The number of the invoice, which is to be typed.
    let number: String

    /// What is typed.
    @Binding var typed: String

    /// Whether what is typed is the number of the invoice, or the digits of it.
    let matches: Bool

    /// What Return in the field does.
    let submit: () -> Void

    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            let shownNumber = Text(verbatim: number).font(Typography.bodySemibold).monospacedDigit()
            Text("Pro potvrzení napište číslo faktury \(shownNumber)")
                .font(Typography.body)
                .foregroundStyle(Palette.text)
            TextField("Číslo faktury", text: $typed)
                .labelsHidden()
                .textFieldStyle(.roundedBorder)
                .monospacedDigit()
                .autocorrectionDisabled()
                .overlay(
                    RoundedRectangle(cornerRadius: DesignMetrics.controlRadius)
                        .strokeBorder(Palette.red, lineWidth: matches ? 1.5 : 0)
                )
                .focused($isFocused)
                .onSubmit(submit)
                .onAppear {
                    isFocused = true
                }
        }
    }
}
