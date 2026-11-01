import SwiftUI

/// The first launch: one centred card without a sidebar, "Vítejte v InvoicesTracker", with the two ways to begin — with
/// empty data, which goes on to the recovery code, and from a backup — and a note for a Mac that was restored whole.
struct WelcomeView: View {
    let model: AppModel

    @State private var restoring = false
    @State private var runner = StepRunner()

    var body: some View {
        if restoring {
            RestoreFlowView(model: model) {
                restoring = false
            }
        } else {
            WelcomeCard(label: "Vítejte") {
                VStack(spacing: 10) {
                    AppTile()
                    Text("Vítejte v InvoicesTracker")
                        .font(Typography.title)
                        .foregroundStyle(Palette.text)
                        .padding(.top, 4)
                        .accessibilityAddTraits(.isHeader)
                    Text(
                        """
                        Faktury, daň a pojištění na jednom místě. Data zůstávají jen v tomto Macu – aplikace je \
                        šifruje a klíč k nim chrání Secure Enclave tohoto Macu.
                        """
                    )
                    .font(Typography.body)
                    .foregroundStyle(Palette.text2)
                    .frame(maxWidth: Self.textWidth)
                    .fixedSize(horizontal: false, vertical: true)
                }
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                VStack(spacing: 10) {
                    WelcomeOptionRow(
                        systemImage: "plus", tone: .accent, title: "Začít s prázdnými daty",
                        detail: """
                            Uložíte si kód pro obnovení, vyplníte své údaje na faktury a můžete importovat faktury z \
                            Fakturoidu.
                            """,
                        isDisabled: runner.isWorking
                    ) {
                        Task { await runner.perform { try await model.startFresh() } }
                    }
                    WelcomeOptionRow(
                        systemImage: "arrow.counterclockwise", tone: .green, title: "Obnovit ze zálohy",
                        detail: "Máte zálohu z InvoicesTracker (soubor .ttbackup), třeba z jiného Macu.",
                        isDisabled: runner.isWorking
                    ) {
                        restoring = true
                    }
                }
                if let errorText = runner.errorText {
                    WelcomeErrorLine(text: errorText)
                }
                Text(
                    """
                    Obnovili jste celý Mac z Time Machine nebo jste data přenesli Průvodcem migrací? Pak je aplikace \
                    najde sama a zeptá se jen na kód pro obnovení.
                    """
                )
                .font(Typography.callout)
                .foregroundStyle(Palette.text3)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity)
            }
        }
    }

    /// The width the text under the title wraps at: the prototype's `max-width: 32em` at the 13-point body, 416
    /// points.
    static let textWidth: CGFloat = 416
}

/// The tile of the app at the top of the first card: 64 points, with the corners of a card, a gradient from the accent
/// to the accent text running down and a little to the right (the prototype's 160°), the glyph of a document in the
/// colour of text on an accent, about 27 points tall as the design draws it, and the blue glow under it.
private struct AppTile: View {
    var body: some View {
        Image(systemName: "doc.text")
            .font(Typography.symbolLarge)
            .foregroundStyle(Palette.onAccent)
            .frame(width: 64, height: 64)
            .background {
                RoundedRectangle(cornerRadius: DesignMetrics.cardRadius)
                    .surface(
                        LinearGradient(
                            colors: [Palette.accent, Palette.accentText], startPoint: UnitPoint(x: 0.28, y: -0.1),
                            endPoint: UnitPoint(x: 0.72, y: 1.1)),
                        elevation: .glow)
            }
            .accessibilityHidden(true)
    }
}
