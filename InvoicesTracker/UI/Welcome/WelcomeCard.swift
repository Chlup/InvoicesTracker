import SwiftUI

/// The card in the middle of a full-window state, which has no sidebar: one column of content on a card of the design
/// (the colour of a card, the corners of a card, the shadow of a card), on the background of the window. The card
/// scrolls when the window is too low for it. Everything on it takes its colours from the palette, so that it follows
/// the appearance of the window.
struct WelcomeCard<Content: View>: View {
    /// What VoiceOver calls the card.
    let label: String

    /// The width of the card, padding included; the content is as wide as it allows.
    var width: CGFloat = 560

    @ViewBuilder let content: Content

    var body: some View {
        GeometryReader { window in
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    content
                }
                .padding(EdgeInsets(top: 30, leading: 34, bottom: 28, trailing: 34))
                .frame(maxWidth: width)
                .card()
                .accessibilityElement(children: .contain)
                .accessibilityLabel(label)
                .padding(28)
                .frame(maxWidth: .infinity, minHeight: window.size.height)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
        .background(Palette.bgWindow.ignoresSafeArea())
    }
}

/// The heading of a screen on a card, with the paragraph under it.
struct WelcomeHeading: View {
    let title: String
    var text: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(Typography.title)
                .foregroundStyle(Palette.text)
                .accessibilityAddTraits(.isHeader)
            if let text {
                Text(text)
                    .font(Typography.body)
                    .foregroundStyle(Palette.text2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

/// The error a step ended in, in the red of text under what it was about. VoiceOver reads it out when it appears, or
/// once the app is unlocked when it appears under the lock after inactivity, as in the sheet of a restore.
struct WelcomeErrorLine: View {
    let text: String

    @Environment(AppModel.self) private var app: AppModel?

    var body: some View {
        Text(text)
            .font(Typography.body)
            .foregroundStyle(Palette.redText)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .onAppear { announce(text) }
            .onChange(of: text) { _, newText in announce(newText) }
    }

    private func announce(_ text: String) {
        VoiceOverAnnouncement.post(text, by: app)
    }
}

/// What a choice on a card is about, which decides the colours of its circle: the pale tint of the colour with its
/// symbol in the colour of text, as the design draws the two ways to begin and the offer to import.
enum WelcomeOptionTone {
    /// To begin, to import: the accent.
    case accent

    /// To restore: green.
    case green

    /// To go on without: no colour.
    case neutral

    /// The colour of the circle.
    var background: Color {
        switch self {
        case .accent: Palette.accentTint
        case .green: Palette.greenTint
        case .neutral: Palette.fill
        }
    }

    /// The colour of the symbol in the circle.
    var foreground: Color {
        switch self {
        case .accent: Palette.accent
        case .green: Palette.greenText
        case .neutral: Palette.text2
        }
    }
}

/// A choice on a card: a symbol in a circle, a title, a line of explanation and, usually, a chevron, on an inset panel
/// with a ring.
struct WelcomeOptionRow: View {
    let systemImage: String
    let tone: WelcomeOptionTone
    let title: String
    let detail: String
    var showsChevron = true
    var isDisabled = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: systemImage)
                    .font(Typography.symbolSmall)
                    .foregroundStyle(tone.foreground)
                    .frame(width: 40, height: 40)
                    .background(tone.background, in: Circle())
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(Typography.bodySemibold)
                        .foregroundStyle(Palette.text)
                    Text(detail)
                        .font(Typography.callout)
                        .foregroundStyle(Palette.text2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                if showsChevron {
                    Image(systemName: "chevron.right")
                        .font(Typography.calloutSemibold)
                        .foregroundStyle(Palette.text4)
                        .accessibilityHidden(true)
                }
            }
            .insetPanel(horizontal: 18, vertical: 16, ringed: true)
            .contentShape(RoundedRectangle(cornerRadius: DesignMetrics.panelRadius))
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
    }
}

/// A panel that holds a part of a card: the code, the file, the explanation. It is an inset panel, with the ring of the
/// code and of the file, and without it for what only explains. It is padded 18 across and 16 down unless told
/// otherwise.
struct WelcomeBox<Content: View>: View {
    var spacing: CGFloat = 10
    var horizontalPadding: CGFloat = 18
    var verticalPadding: CGFloat = 16

    /// Whether the panel has the hairline along its edge.
    var ringed = true
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: spacing) {
            content
        }
        .insetPanel(horizontal: horizontalPadding, vertical: verticalPadding, ringed: ringed)
    }
}

/// The two buttons that end a card: the one that goes back or away on the left, and the one that goes on on the right,
/// which is the default one (Return). The one that goes on waits while a step works. The one that goes back answers
/// Esc too when `backIsCancel` says that going back is what Esc means on the card.
struct WelcomeFooter: View {
    var backTitle: String?
    var back: () -> Void = {}

    /// Whether Esc is the same as the button that goes back.
    var backIsCancel = false
    var isWorking = false
    let goTitle: String
    var goDisabled = false
    let go: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            if let backTitle {
                Button(backTitle, action: back)
                    .buttonStyle(CapsuleButtonStyle(.secondary))
                    .keyboardShortcut(backIsCancel ? .cancelAction : nil)
                    .disabled(isWorking)
            }
            Spacer(minLength: 0)
            if isWorking {
                ProgressView()
                    .controlSize(.small)
            }
            Button(goTitle, action: go)
                .buttonStyle(CapsuleButtonStyle(.primary))
                .keyboardShortcut(.defaultAction)
                .disabled(goDisabled || isWorking)
        }
    }
}

extension View {
    /// The small round-cornered button of a box on a card, such as Kopírovat: a capsule 28 points tall in the colour
    /// of a card, raised off the panel it stands on.
    func welcomeBoxButton() -> some View {
        buttonStyle(CapsuleButtonStyle(.onWindow, size: .small))
    }
}
