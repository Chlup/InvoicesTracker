import SwiftUI

/// The card in the middle of a full-window state, which has no sidebar: one column of content on a rounded card. The
/// card scrolls when the window is too low for it. Everything on it uses semantic colours and materials, so that it
/// follows the appearance of the window.
struct WelcomeCard<Content: View>: View {
    /// What VoiceOver calls the card.
    let label: String

    /// The width of the card; the content is as wide as it allows.
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
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 22))
                .overlay(RoundedRectangle(cornerRadius: 22).strokeBorder(.separator))
                .shadow(color: .black.opacity(0.08), radius: 20, y: 12)
                .accessibilityElement(children: .contain)
                .accessibilityLabel(label)
                .padding(28)
                .frame(maxWidth: .infinity, minHeight: window.size.height)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
    }
}

/// The heading of a screen on a card, with the paragraph under it.
struct WelcomeHeading: View {
    let title: String
    var text: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.title.weight(.bold))
                .accessibilityAddTraits(.isHeader)
            if let text {
                Text(text)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

/// The error a step ended in, in red under what it was about. VoiceOver reads it out when it appears, or once the app
/// is unlocked when it appears under the lock after inactivity, as in the sheet of a restore.
struct WelcomeErrorLine: View {
    let text: String

    @Environment(AppModel.self) private var app: AppModel?

    var body: some View {
        Text(text)
            .foregroundStyle(.red)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .onAppear { announce(text) }
            .onChange(of: text) { _, newText in announce(newText) }
    }

    private func announce(_ text: String) {
        VoiceOverAnnouncement.post(text, by: app)
    }
}

/// A choice on a card: a tinted symbol, a title, a line of explanation and, usually, a chevron.
struct WelcomeOptionRow: View {
    let systemImage: String
    let tint: Color
    let title: String
    let detail: String
    var showsChevron = true
    var isDisabled = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: systemImage)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(tint)
                    .frame(width: 40, height: 40)
                    .background(tint.opacity(0.15), in: Circle())
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .fontWeight(.semibold)
                    Text(detail)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                if showsChevron {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.tertiary)
                        .accessibilityHidden(true)
                }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 16)
            .frame(maxWidth: .infinity)
            .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(.separator))
            .contentShape(RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
    }
}

/// A rounded box that holds a part of a card: the code, the file, the explanation.
struct WelcomeBox<Content: View>: View {
    var spacing: CGFloat = 10
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: spacing) {
            content
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(.separator))
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
                    .buttonStyle(.bordered)
                    .buttonBorderShape(.capsule)
                    .controlSize(.large)
                    .keyboardShortcut(backIsCancel ? .cancelAction : nil)
                    .disabled(isWorking)
            }
            Spacer(minLength: 0)
            if isWorking {
                ProgressView()
                    .controlSize(.small)
            }
            Button(goTitle, action: go)
                .buttonStyle(.borderedProminent)
                .buttonBorderShape(.capsule)
                .controlSize(.large)
                .keyboardShortcut(.defaultAction)
                .disabled(goDisabled || isWorking)
        }
    }
}

extension View {
    /// The small round-cornered button of a box on a card, such as Kopírovat.
    func welcomeBoxButton() -> some View {
        buttonStyle(.bordered)
            .buttonBorderShape(.capsule)
            .controlSize(.small)
    }
}
