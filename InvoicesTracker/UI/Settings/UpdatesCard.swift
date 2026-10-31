import SwiftUI

/// The card Aktualizace of Nastavení › Aplikace: the version of the app, when the updater last checked for a new
/// version, the switch of the daily check, and Zkontrolovat teď, which asks the updater for a check at once. The
/// updater shows what it finds in its own windows. The card is made like the card Kurzy, whose button reads the same.
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
        SettingsCard(title: UpdatesTexts.title, subtitle: UpdatesTexts.subtitle, spacing: 6) {
            VStack(alignment: .leading, spacing: 0) {
                SettingsRow(label: "Verze") {
                    Text(verbatim: UpdatesTexts.installedVersion)
                        .fontWeight(.semibold)
                        .monospacedDigit()
                }
                SettingsRow(label: "Poslední kontrola") {
                    Text(verbatim: UpdatesTexts.lastCheck(updates?.lastCheck, now: now, timeZone: timeZone))
                        .fontWeight(.semibold)
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
                Divider()
                Button(UpdatesTexts.checkNowTitle) {
                    updates?.checkNow()
                }
                .settingsCardButton()
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
