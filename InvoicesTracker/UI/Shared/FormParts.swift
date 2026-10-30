import SwiftUI

/// The title and the line under it at the top of a sheet.
struct SheetHeader: View {
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(verbatim: title)
                .font(.system(size: 17, weight: .bold))
                .accessibilityAddTraits(.isHeader)
            Text(verbatim: subtitle)
                .foregroundStyle(.secondary)
        }
    }
}

/// A field of a form: its label in small type over the control. The control carries
/// the label for VoiceOver (`labelsHidden()` keeps the label it was made with), so the text above it is not read twice.
struct LabeledField<Content: View>: View {
    let label: String
    let content: Content

    init(_ label: String, @ViewBuilder content: () -> Content) {
        self.label = label
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(verbatim: label)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            content
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

/// A text field of a form: it carries its label for VoiceOver and shows no text of its own while it is empty, unless it
/// is given a prompt. `trailing` sets the text against the right edge, for numbers.
struct FormTextField: View {
    let label: String
    @Binding var text: String
    let prompt: String?
    let trailing: Bool

    init(_ label: String, text: Binding<String>, prompt: String? = nil, trailing: Bool = false) {
        self.label = label
        _text = text
        self.prompt = prompt
        self.trailing = trailing
    }

    var body: some View {
        TextField("", text: $text, prompt: prompt.map { Text($0) })
            .labelsHidden()
            .multilineTextAlignment(trailing ? .trailing : .leading)
            .textFieldStyle(.roundedBorder)
            .accessibilityLabel(label)
    }
}

/// What is wrong with a form, in red over its buttons, one line each, and what went wrong with the last save. A form
/// with many problems scrolls them within a few lines, so that the sheet stays no taller than the window.
struct FormProblems: View {
    /// The most points the problems take.
    static let maximumHeight: CGFloat = 64

    let errors: [String]
    let failure: String?

    var body: some View {
        if !errors.isEmpty || failure != nil {
            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(errors, id: \.self) { text in
                        Text(verbatim: text)
                    }
                    if let failure {
                        Text(verbatim: failure)
                    }
                }
                .foregroundStyle(.red)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityElement(children: .combine)
            }
            .frame(maxHeight: Self.maximumHeight)
            .fixedSize(horizontal: false, vertical: true)
        }
    }
}
