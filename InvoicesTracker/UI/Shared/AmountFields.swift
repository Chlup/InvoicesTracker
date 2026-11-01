import SwiftUI

/// The text field of an amount typed in a form, without a title: whole Kč or a number of months, against the right
/// edge in digits of one width. VoiceOver reads it under `title`, and Return in it calls `submit`.
struct AmountTextField: View {
    let title: String
    let text: Binding<String>
    let width: CGFloat?
    let submit: () -> Void

    var body: some View {
        TextField("", text: text)
            .labelsHidden()
            .multilineTextAlignment(.trailing)
            .textFieldStyle(.roundedBorder)
            .monospacedDigit()
            .frame(width: width)
            .accessibilityLabel(title)
            .onSubmit(submit)
    }
}

/// An amount with its title over it and, while its text is refused, the message under it. A field of no width of its
/// own (`width` nil) is as wide as its column.
///
/// The message breaks within the width of the title and the field, so a message that comes or goes never changes the
/// width the field asks for, and the fields around it stay where they are. A screen reads a text in the pause of the
/// typing, and a field that its message moved to another arrangement would lose the focus.
struct TitledAmountField: View {
    let title: String
    let text: Binding<String>
    let width: CGFloat?
    let message: String?
    let submit: () -> Void

    var body: some View {
        WidthOfFieldLayout(spacing: 4) {
            titleText
            AmountTextField(title: title, text: text, width: width, submit: submit)
            if let message {
                FieldMessage(text: message)
                    .layoutValue(key: IsFieldMessage.self, value: true)
            }
        }
        .frame(maxWidth: width == nil ? .infinity : nil, alignment: .leading)
    }

    /// A title over a field of its own width stays on one line. One over a field as wide as its column breaks where
    /// the column is too narrow for it.
    private var titleText: some View {
        Text(title)
            .font(Typography.callout)
            .foregroundStyle(Palette.text2)
            .fixedSize(horizontal: width != nil, vertical: true)
    }
}

extension TitledAmountField {
    /// The field of `field` of the deductions, with its text and its message from `inputs`.
    init(_ field: DeductionField, title: String, width: CGFloat?, inputs: DeductionInputs) {
        self.init(
            title: title, text: inputs.text(field), width: width, message: inputs.message(field), submit: inputs.submit)
    }
}

/// Stacks the title, the field and the message of a `TitledAmountField` from the top, at the leading edge and
/// `spacing` apart, as a VStack does. Its width comes from the title and the field alone: the message, which is marked
/// with `IsFieldMessage`, breaks within that width rather than widen the stack.
private struct WidthOfFieldLayout: Layout {
    let spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = width(for: proposal, of: subviews)
        let heights = subviews.map { $0.sizeThatFits(ProposedViewSize(width: width, height: nil)).height }
        return CGSize(width: width, height: heights.reduce(0, +) + spacing * CGFloat(max(0, subviews.count - 1)))
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let placement = ProposedViewSize(width: bounds.width, height: nil)
        var top = bounds.minY
        for subview in subviews {
            subview.place(at: CGPoint(x: bounds.minX, y: top), anchor: .topLeading, proposal: placement)
            top += subview.sizeThatFits(placement).height + spacing
        }
    }

    /// The width of the widest subview but the message, at the width proposed.
    private func width(for proposal: ProposedViewSize, of subviews: Subviews) -> CGFloat {
        subviews.filter { !$0[IsFieldMessage.self] }
            .map { $0.sizeThatFits(ProposedViewSize(width: proposal.width, height: nil)).width }
            .max() ?? 0
    }
}

/// Marks the message of a `TitledAmountField` for `WidthOfFieldLayout`.
private nonisolated struct IsFieldMessage: LayoutValueKey {
    static let defaultValue = false
}

/// The message under a field whose text was refused, in callout and the red of text.
struct FieldMessage: View {
    let text: String

    var body: some View {
        Text(verbatim: text)
            .font(Typography.callout)
            .foregroundStyle(Palette.redText)
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// How the fields of the deductions of a screen read and change what is typed in them: the text of each field, the
/// message of a field whose text was refused, and what Return in a field does. Zálohy a odpočty saves its fields, and
/// Simulátor only reads them.
struct DeductionInputs {
    let text: (DeductionField) -> Binding<String>
    let message: (DeductionField) -> String?
    let submit: () -> Void
}
