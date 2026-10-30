import SwiftUI

/// The data were saved by a newer version of the app than this one. Nothing opens them but that version or a newer one,
/// so the screen advises updating the app: restoring a backup or starting with empty data would only put the person at
/// risk of leaving these data behind. Nothing was changed.
struct NewerVersionView: View {
    var body: some View {
        WelcomeCard(label: WelcomeTexts.newerVersionTitle, width: 520) {
            VStack(spacing: 10) {
                Image(systemName: "arrow.down.circle")
                    .font(.system(size: 28, weight: .regular))
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 64, height: 64)
                    .background(Color.accentColor.opacity(0.15), in: Circle())
                    .accessibilityHidden(true)
                Text(WelcomeTexts.newerVersionTitle)
                    .font(.title.weight(.bold))
                    .padding(.top, 4)
                    .accessibilityAddTraits(.isHeader)
                Text(WelcomeTexts.newerVersionText)
                    .fontWeight(.semibold)
                    .fixedSize(horizontal: false, vertical: true)
                Text(WelcomeTexts.newerVersionReassurance)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: 400)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
        }
    }
}
