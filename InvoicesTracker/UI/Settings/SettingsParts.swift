import SwiftUI

/// A row of a card under a hairline: the label on the left, the value on the right, and a line of detail under both.
/// The value can be a control, such as a menu, which VoiceOver keeps as a control of its own. The hairline is the one
/// of the design and the row is 10 points tall above and below its text; the label is in secondary text, the value in
/// the colour of text unless it sets its own, and the detail under them in callout and tertiary text.
struct SettingsRow<Value: View>: View {
    let label: String
    var detail: String?
    @ViewBuilder let value: Value

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Hairline()
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Text(verbatim: label)
                        .font(Typography.body)
                        .foregroundStyle(Palette.text2)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 8)
                    value
                        .font(Typography.body)
                        .foregroundStyle(Palette.text)
                        .multilineTextAlignment(.trailing)
                }
                if let detail, !detail.isEmpty {
                    Text(verbatim: detail)
                        .font(Typography.callout)
                        .foregroundStyle(Palette.text3)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.vertical, 10)
        }
        .accessibilityElement(children: .contain)
    }
}

/// A field of a form of Nastavení: its label over it, and the message under it when what was typed was refused. The
/// field is outlined in the red of an error while it has a message.
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
                    .overlay(
                        RoundedRectangle(cornerRadius: DesignMetrics.controlRadius)
                            .strokeBorder(Palette.red, lineWidth: error == nil ? 0 : 1)
                    )
                if let error {
                    FieldMessage(text: error)
                }
            }
        }
    }
}

/// A line in the red of text that says what went wrong, in the font it is given (body unless told otherwise). VoiceOver
/// reads it out when it appears, or once the app is unlocked when it appears under the lock after inactivity.
struct SettingsFailureLine: View {
    let text: String

    @Environment(AppModel.self) private var app: AppModel?

    var body: some View {
        Text(verbatim: text)
            .foregroundStyle(Palette.redText)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .onAppear { VoiceOverAnnouncement.post(text, by: app) }
            .onChange(of: text) { _, newText in VoiceOverAnnouncement.post(newText, by: app) }
    }
}

/// A link to a page on the web, as the design draws a link: its words in callout in the blue of a link. VoiceOver reads
/// it as a link, and a click opens the page in the browser.
struct SettingsLink: View {
    let title: String
    let destination: URL

    var body: some View {
        Link(destination: destination) {
            Text(verbatim: title)
                .font(Typography.callout)
                .foregroundStyle(Palette.accentText)
        }
    }
}

extension View {
    /// The look of a button inside a card, such as Zkontrolovat teď: a capsule 28 points tall on the grey fill. The
    /// buttons below the view take the look from it, so it can be given to a row of them.
    func settingsCardButton() -> some View {
        buttonStyle(CapsuleButtonStyle(.secondary, size: .small))
    }

    /// The look of a link inside a card, such as Zobrazit licenci: the text of a button in callout, in the blue of a
    /// link, or in the red of text where it leads to something that cannot be undone, such as Odstranit….
    func settingsCardLink(_ tone: LinkTone = .accent) -> some View {
        buttonStyle(TextLinkButtonStyle(tone))
            .font(Typography.callout)
    }
}
