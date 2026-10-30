import SwiftUI

/// The card after unlocking with the recovery code ("Odemčeno") or restoring a backup ("Data jsou obnovená"): what was
/// done, the code that stays valid, and a hint that a new code can be made. Pokračovat shows the app.
struct UnlockCompletionView: View {
    let model: AppModel
    let completion: UnlockCompletion

    var body: some View {
        WelcomeCard(label: "Hotovo", width: 520) {
            VStack(spacing: 10) {
                Image(systemName: "checkmark")
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(Color(.bannerText))
                    .frame(width: 56, height: 56)
                    .background(Color.green.opacity(0.18), in: Circle())
                    .accessibilityHidden(true)
                Text(WelcomeTexts.doneTitle(completion))
                    .font(.title.weight(.bold))
                    .padding(.top, 4)
                    .accessibilityAddTraits(.isHeader)
                Text(WelcomeTexts.doneText(completion, touchID: model.appSettings.touchIDUnlock))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: 400)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
            Text(WelcomeTexts.newCodeHint)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 12))
            HStack {
                Spacer(minLength: 0)
                Button("Pokračovat") {
                    model.dismissCompletion()
                }
                .buttonStyle(.borderedProminent)
                .buttonBorderShape(.capsule)
                .controlSize(.large)
                .keyboardShortcut(.defaultAction)
                Spacer(minLength: 0)
            }
        }
    }
}
