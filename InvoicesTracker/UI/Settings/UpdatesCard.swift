import SwiftUI

/// The card Aktualizace of Nastavení › Aplikace: the version of the app, when the updater last checked for a new
/// version, the switch of the daily check, and Zkontrolovat teď, which asks the updater for a check at once. The
/// updater shows what it finds in its own windows.
///
/// The prototype of the design predates the updates and has no such card, so the card is made like the card Kurzy
/// beside it: the shared card with its title and subtitle, rows under hairlines with their values in semibold body, a
/// hairline over the button, which is a capsule 28 points tall, and colours and fonts from the palette and the
/// typography. The switch is the native one, as the form controls of the app are. The button of Kurzy shows the same
/// title, so VoiceOver names this card's button after the card (`UpdatesTexts.checkNowAccessibilityLabel`).
///
/// Without `updates` (the app has no updater while it hosts the unit tests) the card still names the version, the last
/// check never was, the switch is off, and neither the switch nor the button can be used. The button can be used
/// exactly while the updater can start a check.
struct UpdatesCard: View {
    let updates: UpdatesModel?

    /// The instant and the time zone the last check is told by: "dnes" is the day of `now` in `timeZone`.
    let now: Date
    let timeZone: TimeZone

    var body: some View {
        Card(title: UpdatesTexts.title, subtitle: UpdatesTexts.subtitle, spacing: 6) {
            VStack(alignment: .leading, spacing: 0) {
                SettingsRow(label: "Verze") {
                    Text(verbatim: UpdatesTexts.installedVersion)
                        .font(Typography.bodySemibold)
                        .monospacedDigit()
                }
                SettingsRow(label: "Poslední kontrola") {
                    Text(verbatim: UpdatesTexts.lastCheck(updates?.lastCheck, now: now, timeZone: timeZone))
                        .font(Typography.bodySemibold)
                        .monospacedDigit()
                }
                SettingsRow(label: UpdatesTexts.automaticLabel) {
                    Toggle(UpdatesTexts.automaticLabel, isOn: checksAutomatically)
                        .toggleStyle(.switch)
                        .controlSize(.small)
                        .labelsHidden()
                        .accessibilityLabel(UpdatesTexts.automaticLabel)
                        .disabled(updates == nil)
                }
                Hairline()
                Button(UpdatesTexts.checkNowTitle) {
                    updates?.checkNow()
                }
                .settingsCardButton()
                .accessibilityLabel(UpdatesTexts.checkNowAccessibilityLabel)
                .disabled(updates?.canCheck != true)
                .padding(.top, 10)
            }
        }
        .onAppear {
            updates?.refresh()
        }
    }

    /// The switch of the daily check: it shows what the updater says and passes the choice on to the updater. It is off
    /// while there is no updater.
    private var checksAutomatically: Binding<Bool> {
        Binding(
            get: { updates?.checksAutomatically ?? false },
            set: { isOn in updates?.setChecksAutomatically(isOn) }
        )
    }
}
