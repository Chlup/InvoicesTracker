import SwiftUI

/// What a note is about, which decides its colours. The tone is a plain value; the colours it stands for
/// (`background`, `iconColor`) come from the palette and are on the main actor, like the views.
nonisolated enum NoteTone: Sendable, Hashable {
    /// How something is computed or what a screen shows, in blue.
    case info

    /// An estimate, or something that needs attention, in orange.
    case attention

    /// The result of an action, in green.
    case success

    /// What is wrong and has to be put right, in red.
    case error
}

/// The colours of the tones of a note, from the palette.
extension NoteTone {
    /// The tint behind the note.
    var background: Color {
        switch self {
        case .info: Palette.accentTint
        case .attention: Palette.orangeTint
        case .success: Palette.greenTint
        case .error: Palette.redTint
        }
    }

    /// The colour of the icon in front of the text of the note.
    var iconColor: Color {
        switch self {
        case .info: Palette.accent
        case .attention: Palette.orange
        case .success: Palette.green
        case .error: Palette.red
        }
    }
}

/// The icon in front of the text of a note.
nonisolated enum NoteIcon: Sendable, Hashable {
    /// The circle with an "i", for what the screen tells.
    case info

    /// The triangle with an exclamation mark, for a warning and for what cannot be undone.
    case warning

    /// No icon: the text starts at the edge of the note.
    case none

    /// The name of the SF Symbol of the icon, or nil for none.
    var symbolName: String? {
        switch self {
        case .info: "info.circle"
        case .warning: "exclamationmark.triangle"
        case .none: nil
        }
    }
}

/// A box with a sentence or two, of one shape in four tones: a pale background of the tone, an icon in its colour, an
/// optional title in body semibold and the text in body, in the colour of text. A note may carry actions at its end,
/// such as a button that closes it.
///
/// The text is one block 4 points under the title. A note that says several things, such as the lines of the note that
/// warns of a deletion, is made of paragraphs instead: they stand 6 points apart, and 6 points under the title, as the
/// prototype draws that column.
///
/// A note without actions is one element to VoiceOver, which reads its title and text as one phrase. A note with
/// actions is a group, so that VoiceOver reaches each action on its own.
struct Note<Actions: View>: View {
    let tone: NoteTone
    let icon: NoteIcon
    let title: String?

    /// What the note says, paragraph by paragraph; one for a text, none for a title alone.
    let paragraphs: [String]

    /// The space between the title and the paragraphs, and between the paragraphs.
    private let gap: CGFloat
    private let actions: Actions

    /// The space between the title and the text of a note, in points.
    private static var textGap: CGFloat {
        4
    }

    /// The space between the title and the paragraphs of a note, and between the paragraphs, in points.
    private static var paragraphGap: CGFloat {
        6
    }

    /// A note of `tone` that says `text`, under `title` if there is one, with `actions` at its end. A note that is a
    /// title alone, such as the banner with the result of an action, passes an empty `text`.
    init(
        _ tone: NoteTone, icon: NoteIcon = .info, title: String? = nil, text: String,
        @ViewBuilder actions: () -> Actions
    ) {
        self.tone = tone
        self.icon = icon
        self.title = title
        self.paragraphs = text.isEmpty ? [] : [text]
        self.gap = Self.textGap
        self.actions = actions()
    }

    /// A note of `tone` that says `paragraphs`, one under the other, under `title` if there is one, with `actions` at
    /// its end.
    init(
        _ tone: NoteTone, icon: NoteIcon = .info, title: String? = nil, paragraphs: [String],
        @ViewBuilder actions: () -> Actions
    ) {
        self.tone = tone
        self.icon = icon
        self.title = title
        self.paragraphs = paragraphs
        self.gap = Self.paragraphGap
        self.actions = actions()
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            if let symbolName = icon.symbolName {
                Image(systemName: symbolName)
                    .imageScale(.large)
                    .foregroundStyle(tone.iconColor)
                    .accessibilityHidden(true)
            }
            VStack(alignment: .leading, spacing: gap) {
                if let title {
                    Text(verbatim: title)
                        .font(Typography.bodySemibold)
                }
                ForEach(Array(paragraphs.enumerated()), id: \.offset) { _, paragraph in
                    Text(verbatim: paragraph)
                        .font(Typography.body)
                }
            }
            .foregroundStyle(Palette.text)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            actions
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(tone.background, in: RoundedRectangle(cornerRadius: DesignMetrics.panelRadius))
        .accessibilityElement(children: hasActions ? .contain : .combine)
    }

    /// Whether the note has actions, which a note made without them does not.
    private var hasActions: Bool {
        Actions.self != EmptyView.self
    }
}

/// A note without actions.
extension Note where Actions == EmptyView {
    /// A note of `tone` that says `text`, under `title` if there is one, with no actions.
    init(_ tone: NoteTone, icon: NoteIcon = .info, title: String? = nil, text: String) {
        self.init(tone, icon: icon, title: title, text: text) {
            EmptyView()
        }
    }

    /// A note of `tone` that says `paragraphs`, one under the other, under `title` if there is one, with no actions.
    init(_ tone: NoteTone, icon: NoteIcon = .info, title: String? = nil, paragraphs: [String]) {
        self.init(tone, icon: icon, title: title, paragraphs: paragraphs) {
            EmptyView()
        }
    }
}
