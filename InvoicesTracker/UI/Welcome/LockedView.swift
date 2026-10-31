import SwiftUI

/// The locked screen, "InvoicesTracker je zamčený": the data are there, and Touch ID or the password of the Mac unlocks
/// them. It is of one of two locks (`Kind`):
/// - at a launch, when the prompt did not unlock the data (`AppPhase.locked`). Odemknout asks again, the recovery code
///   opens the data from the screen of a Mac that does not know them, and the note says when the app asks — at the
///   launch, and after the time without activity that the app keeps outside the data for this screen
///   (`AppModel.idleLockBeforeOpening`);
/// - after inactivity, over the window, whose data stay open under it (`AppModel.isIdleLocked`): after how long it
///   locked, and that the window is where it was once unlocked. Odemknout asks for Touch ID or the password alone
///   (`AppModel.unlockAfterIdle()`), which always unlock it, so it has no way to the recovery code.
struct LockedView: View {
    /// Which lock the screen is of.
    enum Kind {
        /// The data are locked at a launch.
        case launch

        /// The app is locked after inactivity, with the data open under the lock.
        case inactivity
    }

    /// The title of both locks, which a sheet under the lock after inactivity shows too (`sheetChrome()`).
    static let title: LocalizedStringKey = "InvoicesTracker je zamčený"

    /// The width the text of the lock wraps at: the prototype's `max-width: 30em` at the 13-point body, 390 points.
    static let textWidth: CGFloat = 390

    let model: AppModel
    var kind = Kind.launch

    @State private var runner = StepRunner()

    var body: some View {
        WelcomeCard(label: "Zamčeno", width: 480) {
            VStack(spacing: 10) {
                LockSymbol()
                Text(Self.title)
                    .font(Typography.title)
                    .foregroundStyle(Palette.text)
                    .padding(.top, 4)
                    .accessibilityAddTraits(.isHeader)
                text
                    .font(Typography.body)
                    .foregroundStyle(Palette.text2)
                    .frame(maxWidth: Self.textWidth)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
            VStack(spacing: 10) {
                UnlockButton(runner: runner, unlock: unlock)
                if kind == .launch {
                    Button("Odemknout kódem pro obnovení…") {
                        model.useRecoveryCode()
                    }
                    .buttonStyle(TextLinkButtonStyle())
                    // The way to another screen is a link to VoiceOver, as the system's link style made it.
                    .accessibilityAddTraits(.isLink)
                    .font(Typography.callout)
                    .disabled(runner.isWorking)
                }
            }
            .frame(maxWidth: .infinity)
            footnote
                .font(Typography.callout)
                .foregroundStyle(Palette.text3)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity)
        }
    }

    private var text: Text {
        switch kind {
        case .launch:
            Text(
                """
                Data se odemknou přes Touch ID nebo heslem k tomuto Macu. Dokud je neodemknete, zůstávají \
                zašifrovaná.
                """
            )
        case .inactivity:
            Text(verbatim: WelcomeTexts.idleLockText(model.appSettings.idleLock))
        }
    }

    private var footnote: Text {
        switch kind {
        case .launch:
            Text(verbatim: WelcomeTexts.launchLockNote(model.idleLockBeforeOpening))
        case .inactivity:
            Text(
                """
                Po odemčení budete tam, kde jste skončili. Dobu do zamčení změníte v Nastavení › Zabezpečení a \
                zálohy.
                """
            )
        }
    }

    /// Odemknout: the data are opened with the device key of this Mac, or the lock after inactivity asks for Touch ID
    /// or the password alone.
    private func unlock() async {
        switch kind {
        case .launch: await model.unlockWithDevice()
        case .inactivity: await model.unlockAfterIdle()
        }
    }
}

/// The lock in a circle at the top of a locked screen: a symbol in the grey text on the grey fill, 64 points across.
struct LockSymbol: View {
    var body: some View {
        Image(systemName: "lock")
            .font(Typography.symbolLarge)
            .imageScale(.large)
            .foregroundStyle(Palette.text2)
            .frame(width: 64, height: 64)
            .background(Palette.fill, in: Circle())
            .accessibilityHidden(true)
    }
}

/// Odemknout of a locked screen, its default button (Return): the capsule of the accent with the symbol of Touch ID,
/// 6 points wider at each end than the capsule of a dialog, as the prototype draws it (20 points of padding). It runs
/// `unlock` with `runner`, and waits while it runs.
struct UnlockButton: View {
    let runner: StepRunner
    let unlock: @MainActor () async -> Void

    var body: some View {
        Button {
            Task { await runner.perform { await unlock() } }
        } label: {
            Label("Odemknout", systemImage: "touchid")
                .padding(.horizontal, 6)
        }
        .buttonStyle(CapsuleButtonStyle(.primary))
        .keyboardShortcut(.defaultAction)
        .disabled(runner.isWorking)
    }
}
