import SwiftUI

/// What a capsule button is for, which decides its colours. The kind is a plain value; the colours it stands for
/// (`background`, `foreground`) come from the palette and are on the main actor, like the views.
nonisolated enum CapsuleButtonKind: Sendable {
    /// The main action of a page, a card or a dialog, in the accent.
    case primary

    /// An action beside the main one, on the grey fill.
    case secondary

    /// An action that stands on the background of the window itself, where the grey fill would hardly show: a
    /// capsule in the colour of a card, raised off the page.
    case onWindow

    /// Like `onWindow`, with its label in the blue of a link: the action in a note, such as Začít znovu in the note at
    /// the top of the Simulátor.
    case onWindowAccent

    /// The way into something that cannot be undone, on a pale red.
    case destructive

    /// The action that carries out what cannot be undone once the person has chosen it, in solid red.
    case destructiveConfirm

    /// Whether the capsule stands off the page, with the elevation of a control.
    var isRaised: Bool {
        switch self {
        case .onWindow, .onWindowAccent: true
        case .primary, .secondary, .destructive, .destructiveConfirm: false
        }
    }
}

/// The colours of the kinds of capsule button, from the palette.
extension CapsuleButtonKind {
    /// The colour of the capsule.
    var background: Color {
        switch self {
        case .primary: Palette.accent
        case .secondary: Palette.fill
        case .onWindow, .onWindowAccent: Palette.bgCard
        case .destructive: Palette.redTint
        case .destructiveConfirm: Palette.red
        }
    }

    /// The colour of the label on the capsule.
    var foreground: Color {
        switch self {
        case .primary, .destructiveConfirm: Palette.onAccent
        case .secondary, .onWindow: Palette.text
        case .onWindowAccent: Palette.accentText
        case .destructive: Palette.redText
        }
    }
}

/// How tall a capsule button is: the regular one is for the actions of a page, a dialog and the toolbar, the small one
/// for the actions inside a card.
nonisolated enum CapsuleButtonSize: Sendable {
    /// 32 points tall.
    case regular

    /// 28 points tall.
    case small

    /// The height of the capsule, in points.
    var height: CGFloat {
        switch self {
        case .regular: DesignMetrics.regularControlHeight
        case .small: DesignMetrics.smallControlHeight
        }
    }

    /// The space between the edge of the capsule and its label, in points.
    var horizontalPadding: CGFloat {
        switch self {
        case .regular: 14
        case .small: 12
        }
    }
}

/// The look of a button as a capsule of the design: a label in body semibold on a capsule of the colour of the kind,
/// `size` points tall. A button that is pressed shows a little fainter, and one that is disabled much fainter.
///
///     Button("Uložit", action: save)
///         .buttonStyle(CapsuleButtonStyle(.primary))
struct CapsuleButtonStyle: ButtonStyle {
    let kind: CapsuleButtonKind
    let size: CapsuleButtonSize

    /// A style of `kind` and `size`, the regular size unless the button stands inside a card.
    init(_ kind: CapsuleButtonKind, size: CapsuleButtonSize = .regular) {
        self.kind = kind
        self.size = size
    }

    func makeBody(configuration: Configuration) -> some View {
        CapsuleButtonBody(configuration: configuration, kind: kind, size: size)
    }
}

/// How much of a button or a link still shows while it is pressed or disabled.
private enum ControlOpacity {
    /// While the control is pressed.
    static let pressed = 0.8

    /// While the control is disabled.
    static let disabled = 0.45
}

/// The view a capsule button is made of. It is a view of its own because the configuration of a button style does not
/// say whether the button is enabled, and the environment of a view does.
private struct CapsuleButtonBody: View {
    let configuration: ButtonStyleConfiguration
    let kind: CapsuleButtonKind
    let size: CapsuleButtonSize

    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        configuration.label
            .font(Typography.bodySemibold)
            .foregroundStyle(kind.foreground)
            .lineLimit(1)
            .padding(.horizontal, size.horizontalPadding)
            .frame(height: size.height)
            .background { capsule }
            .contentShape([.interaction, .focusEffect], Capsule())
            .opacity(opacity)
    }

    /// The capsule behind the label, raised off the page where the kind calls for it.
    @ViewBuilder
    private var capsule: some View {
        if kind.isRaised {
            Capsule().surface(kind.background, elevation: .control)
        } else {
            Capsule().fill(kind.background)
        }
    }

    /// How much of the button shows now.
    private var opacity: Double {
        if !isEnabled {
            return ControlOpacity.disabled
        }
        return configuration.isPressed ? ControlOpacity.pressed : 1
    }
}

/// What a link is for, which decides the colour of its text.
nonisolated enum LinkTone: Sendable {
    /// An ordinary link, in the blue of text.
    case accent

    /// The way into something that cannot be undone, in the red of text.
    case destructive
}

/// The colour of the tones of a link, from the palette.
extension LinkTone {
    /// The colour of the text of the link.
    var color: Color {
        switch self {
        case .accent: Palette.accentText
        case .destructive: Palette.redText
        }
    }
}

/// The look of a button as a link: its text in the colour of the tone, with no background. The font is the one the
/// button is given from outside, so a link in a card can be set in the callout size.
///
///     Button("Odebrat dítě", action: remove)
///         .buttonStyle(TextLinkButtonStyle(.destructive))
///
/// The style only draws; what VoiceOver reads is the button's own. The rule for a new control: one that leads
/// somewhere else, to another screen, a tab or a file, is read as a link, as the system's link style made it, so it
/// adds the trait of a link (`.accessibilityAddTraits(.isLink)`), which `calloutLink(_:isLink:)` does by itself, and
/// one that does something where it stands, such as the red entry points Odebrat dítě and Odebrat platbu…, stays a
/// button. A control that the app read as a link before the redesign keeps the role even where it acts in place:
/// Zrušit hledání (`SearchLineView`), Odebrat (`SupplierTab`), and Upravit, Odstranit… and Smazat (`YearTabCards`) are
/// links on purpose.
///
/// SwiftUI has a `LinkButtonStyle` of its own (`.buttonStyle(.link)`), so this style has another name: a type of the
/// same name in the app would shadow SwiftUI's in the app, and in a test, which imports both modules, a bare
/// `LinkButtonStyle()` would silently be SwiftUI's.
struct TextLinkButtonStyle: ButtonStyle {
    let tone: LinkTone

    /// A style of `tone`, the blue one unless the link leads to something that cannot be undone.
    init(_ tone: LinkTone = .accent) {
        self.tone = tone
    }

    func makeBody(configuration: Configuration) -> some View {
        TextLinkButtonBody(configuration: configuration, tone: tone)
    }
}

extension View {
    /// The look of a link in a card or in a heading, such as Zobrazit licenci: the text of a button in callout, in the
    /// blue of a link, or in the red of text where it leads to something that cannot be undone, such as Odstranit….
    /// The buttons below the view take the look from it (`TextLinkButtonStyle`).
    ///
    /// VoiceOver reads them as links (`.accessibilityAddTraits(.isLink)`), as the system's link style made it. That is
    /// the rule for a control that leads somewhere else; pass `isLink: false` for a new text button that does
    /// something where it stands and leads nowhere, such as Vrátit odhad aplikace, which was always read as a button.
    /// A text button that the app read as a link before the redesign keeps the role even where it acts in place:
    /// Zrušit hledání, Odebrat, Upravit, Odstranit… and Smazat are links on purpose.
    func calloutLink(_ tone: LinkTone = .accent, isLink: Bool = true) -> some View {
        buttonStyle(TextLinkButtonStyle(tone))
            .font(Typography.callout)
            .accessibilityAddTraits(isLink ? .isLink : [])
    }
}

/// The view a link is made of, a view of its own for the same reason as `CapsuleButtonBody`.
private struct TextLinkButtonBody: View {
    let configuration: ButtonStyleConfiguration
    let tone: LinkTone

    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        configuration.label
            .foregroundStyle(tone.color)
            .contentShape(Rectangle())
            .opacity(opacity)
    }

    /// How much of the link shows now: less while it is pressed, and still less while it is disabled.
    private var opacity: Double {
        if !isEnabled {
            return ControlOpacity.disabled
        }
        return configuration.isPressed ? ControlOpacity.pressed : 1
    }
}
