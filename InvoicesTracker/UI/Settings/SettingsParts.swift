import SwiftUI

/// A card of Nastavení: its title with a line under it and, on the right of the title, a value of its own (the version
/// of the rules, the sum of the adjustments), then its content. It is made of semantic colours, so it follows the
/// appearance of the window.
struct SettingsCard<Content: View>: View {
    let title: String
    var subtitle: String?
    var accessory: String?

    /// Whether the value beside the title is an amount, in the colour of the text, rather than a note.
    var accessoryIsAmount = false
    var spacing: CGFloat = 12
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: spacing) {
            header
            content
        }
        .padding(.horizontal, 20)
        .padding(.top, 16)
        .padding(.bottom, 18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .screenCard()
        .accessibilityElement(children: .contain)
        .accessibilityLabel(title)
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: title)
                    .font(.system(size: 15, weight: .semibold))
                    .accessibilityAddTraits(.isHeader)
                if let subtitle {
                    Text(verbatim: subtitle)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 8)
            if let accessory {
                Text(verbatim: accessory)
                    .font(accessoryIsAmount ? .body : .callout)
                    .fontWeight(accessoryIsAmount ? .semibold : .regular)
                    .monospacedDigit()
                    .foregroundStyle(accessoryIsAmount ? .primary : .secondary)
            }
        }
    }
}

/// A row of a card under a hairline: the label on the left, the value on the right, and a line under both. The value
/// can be a control, such as a menu, which VoiceOver keeps as a control of its own.
struct SettingsRow<Value: View>: View {
    let label: String
    var detail: String?
    @ViewBuilder let value: Value

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Divider()
            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Text(verbatim: label)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 8)
                    value
                        .multilineTextAlignment(.trailing)
                }
                if let detail, !detail.isEmpty {
                    Text(verbatim: detail)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.vertical, 9)
        }
        .accessibilityElement(children: .contain)
    }
}

/// A box of a card: an orange warning with its sign, a blue hint, a green reassurance or a grey note, in the semantic
/// colour at a low opacity.
struct SettingsBox<Content: View>: View {
    enum Kind {
        case warning
        case hint
        case reassurance
        case note
    }

    let kind: Kind
    @ViewBuilder let content: Content

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            if kind == .warning {
                Image(systemName: "exclamationmark.triangle")
                    .foregroundStyle(.orange)
                    .accessibilityHidden(true)
            }
            VStack(alignment: .leading, spacing: 6) {
                content
            }
            .foregroundStyle(kind == .warning ? Color(.simulationText) : Color.primary)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(tint.opacity(kind == .note ? 0.1 : 0.14), in: RoundedRectangle(cornerRadius: 12))
        // A box can hold a button or a link, which VoiceOver keeps as controls of their own.
        .accessibilityElement(children: .contain)
    }

    private var tint: Color {
        switch kind {
        case .warning: .orange
        case .hint: .blue
        case .reassurance: .green
        case .note: .secondary
        }
    }
}

/// A field of a form of Nastavení: its label over it, and the message under it when what was typed was refused.
struct SettingsTextField: View {
    let label: String
    @Binding var text: String
    var prompt: String?
    var trailing = false
    var error: String?

    var body: some View {
        LabeledField(label) {
            VStack(alignment: .leading, spacing: 4) {
                FormTextField(label, text: $text, prompt: prompt, trailing: trailing)
                    .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(.red, lineWidth: error == nil ? 0 : 1))
                if let error {
                    Text(verbatim: error)
                        .font(.callout)
                        .foregroundStyle(.red)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}

/// A line in red that says what went wrong. VoiceOver reads it out when it appears, or once the app is unlocked when it
/// appears under the lock after inactivity.
struct SettingsFailureLine: View {
    let text: String

    @Environment(AppModel.self) private var app: AppModel?

    var body: some View {
        Text(verbatim: text)
            .foregroundStyle(.red)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .onAppear { VoiceOverAnnouncement.post(text, by: app) }
            .onChange(of: text) { _, newText in VoiceOverAnnouncement.post(newText, by: app) }
    }
}

extension View {
    /// The small round-cornered button of a card, such as Zkontrolovat teď.
    func settingsCardButton() -> some View {
        buttonStyle(.bordered)
            .buttonBorderShape(.capsule)
            .controlSize(.small)
    }
}
