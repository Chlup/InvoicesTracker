import SwiftUI

/// The card after unlocking with the recovery code ("Odemčeno") or restoring a backup ("Data jsou obnovená"): what was
/// done, the code that stays valid, and a hint that a new code can be made. Pokračovat shows the app: the capsule of
/// the accent, 8 points wider at each end than the capsule of a dialog, as the prototype draws it (22 points of
/// padding).
struct UnlockCompletionView: View {
    let model: AppModel
    let completion: UnlockCompletion

    var body: some View {
        WelcomeCard(label: "Hotovo", width: 520) {
            VStack(spacing: 10) {
                // The check of the system is square: at the small scale it is 17,5 points across, where the prototype
                // draws a flatter one 19 wide and 14 tall, and at the medium scale it would be 21,5.
                Image(systemName: "checkmark")
                    .font(Typography.symbolLarge)
                    .imageScale(.small)
                    .foregroundStyle(Palette.greenText)
                    .frame(width: 56, height: 56)
                    .background(Palette.greenTint, in: Circle())
                    .accessibilityHidden(true)
                Text(WelcomeTexts.doneTitle(completion))
                    .font(Typography.title)
                    .foregroundStyle(Palette.text)
                    .padding(.top, 4)
                    .accessibilityAddTraits(.isHeader)
                Text(WelcomeTexts.doneText(completion, touchID: model.appSettings.touchIDUnlock))
                    .font(Typography.body)
                    .foregroundStyle(Palette.text2)
                    .frame(maxWidth: WelcomeView.textWidth)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
            Text(WelcomeTexts.newCodeHint)
                .font(Typography.callout)
                .foregroundStyle(Palette.text2)
                .fixedSize(horizontal: false, vertical: true)
                .insetPanel(horizontal: 14, vertical: 12)
            HStack {
                Spacer(minLength: 0)
                Button {
                    model.dismissCompletion()
                } label: {
                    Text("Pokračovat")
                        .padding(.horizontal, 8)
                }
                .buttonStyle(CapsuleButtonStyle(.primary))
                .keyboardShortcut(.defaultAction)
                Spacer(minLength: 0)
            }
        }
    }
}
