import SwiftUI

/// One line of the facts of a detail: a label, its value, and under the value a note, such as the date of a rate under
/// the rate. A fact whose value is empty is not a fact: the builder of a detail leaves it out.
nonisolated struct DetailFact: Sendable, Hashable {
    var label: String
    var value: String
    var note: String?
}

/// The sizes of the parts of a detail panel, in points.
private nonisolated enum DetailPanelMetrics {
    /// The space between the header and the content, and between the parts of the content.
    static let partSpacing: CGFloat = 16

    /// The space between the line of the title and the actions under it.
    static let headerSpacing: CGFloat = 10

    /// The space between the title, the pill and the button that closes the panel, and between two actions.
    static let itemSpacing: CGFloat = 8

    /// The space between the label and the value of a fact.
    static let factColumnGap: CGFloat = 14

    /// The space between two facts.
    static let factRowGap: CGFloat = 6

    /// The space between the label of a figure, the figure and its context.
    static let figureSpacing: CGFloat = 2

    /// How far a figure is scaled down before it is cut, where the room is narrower than it.
    static let minimumFigureScale: CGFloat = 0.6
}

/// The card beside a table that shows one of its rows: a header with the title in title 2 on one line, an optional
/// pill and the button that closes the panel, under it the actions in a row of small buttons that wraps, and under them
/// the content, 16 points apart. The panel is as wide as the room it is given and as high as its content, and its
/// content is padded 20 points like that of every card.
///
/// The close button is a circle of 28 points on the grey fill with an ✕, which VoiceOver reads under `closeLabel`.
/// The actions are buttons of `CapsuleButtonStyle` of the small size, whose kind the caller chooses for each; the
/// panel only sets them in a row, 8 points apart. VoiceOver reads the panel as a group under its title, which a
/// caller renames with `accessibilityLabel(_:)`.
struct DetailPanel<Actions: View, Content: View>: View {
    let title: String
    let pill: (text: String, tone: PillTone)?
    let closeLabel: String
    let close: () -> Void
    private let actions: Actions
    private let content: Content
    private let hasActions: Bool

    /// A panel titled `title`, with `pill` after the title where there is one, `actions` under the header and `content`
    /// under them. `close` runs when the ✕ is pressed.
    init(
        title: String, pill: (text: String, tone: PillTone)?, closeLabel: String = "Zavřít detail",
        close: @escaping () -> Void, @ViewBuilder actions: () -> Actions, @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.pill = pill
        self.closeLabel = closeLabel
        self.close = close
        self.actions = actions()
        self.content = content()
        hasActions = true
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DetailPanelMetrics.partSpacing) {
            header
            content
        }
        .padding(DesignMetrics.cardPadding)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .card()
        .accessibilityElement(children: .contain)
        .accessibilityLabel(title)
    }

    /// The title, the pill and the ✕ on one line, and the actions under them.
    private var header: some View {
        VStack(alignment: .leading, spacing: DetailPanelMetrics.headerSpacing) {
            HStack(spacing: DetailPanelMetrics.itemSpacing) {
                Text(verbatim: title)
                    .font(Typography.title2)
                    .foregroundStyle(Palette.text)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .accessibilityAddTraits(.isHeader)
                if let pill {
                    Pill(pill.text, tone: pill.tone)
                }
                Spacer(minLength: 0)
                closeButton
            }
            if hasActions {
                FlowLayout(spacing: DetailPanelMetrics.itemSpacing) {
                    actions
                }
            }
        }
    }

    /// The circle on the grey fill with the ✕ that closes the panel.
    private var closeButton: some View {
        Button(action: close) {
            Image(systemName: "xmark")
                .font(Typography.subheadlineSemibold)
                .foregroundStyle(Palette.text2)
                .frame(width: DesignMetrics.smallControlHeight, height: DesignMetrics.smallControlHeight)
                .background(Palette.fill, in: Capsule())
                .contentShape([.interaction, .focusEffect], Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(closeLabel)
    }
}

/// A panel that has no actions under its header.
extension DetailPanel where Actions == EmptyView {
    /// A panel titled `title`, with `pill` after the title where there is one and `content` under the header, which
    /// has no actions under it. `close` runs when the ✕ is pressed.
    init(
        title: String, pill: (text: String, tone: PillTone)?, closeLabel: String = "Zavřít detail",
        close: @escaping () -> Void, @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.pill = pill
        self.closeLabel = closeLabel
        self.close = close
        actions = EmptyView()
        self.content = content()
        hasActions = false
    }
}

/// The facts of a detail as a table of two columns: the labels in secondary text, as wide as the widest of them, and
/// the values after them in the colour of text, which break their lines where the room is short. A note under a
/// value is in callout and tertiary text. The facts are `DetailFact`s, and the builder has left out those that have
/// no value.
struct DetailFacts: View {
    let facts: [DetailFact]

    /// A table of `facts`, one line each, in the order they are given.
    init(_ facts: [DetailFact]) {
        self.facts = facts
    }

    var body: some View {
        Grid(
            alignment: .leadingFirstTextBaseline, horizontalSpacing: DetailPanelMetrics.factColumnGap,
            verticalSpacing: DetailPanelMetrics.factRowGap
        ) {
            ForEach(facts.indices, id: \.self) { index in
                let fact = facts[index]
                GridRow {
                    Text(verbatim: fact.label)
                        .font(Typography.body)
                        .foregroundStyle(Palette.text2)
                        .fixedSize(horizontal: false, vertical: true)
                    VStack(alignment: .leading, spacing: 0) {
                        Text(verbatim: fact.value)
                            .font(Typography.body)
                            .foregroundStyle(Palette.text)
                            .fixedSize(horizontal: false, vertical: true)
                        if let note = fact.note {
                            Text(verbatim: note)
                                .font(Typography.callout)
                                .foregroundStyle(Palette.text3)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
        }
    }
}

/// The figure a detail is about: the label over it in callout and secondary text, the figure in the large title with
/// digits of one width, and under it the context in body and secondary text. The figure is never broken; it is scaled
/// down before it is cut, where the room is narrower than it, as an amount cut short would read as a smaller one.
struct DetailFigure: View {
    let label: String?
    let figure: String
    let context: String?

    /// The figure `figure`, with `label` over it and `context` under it where there are any.
    init(label: String?, figure: String, context: String?) {
        self.label = label
        self.figure = figure
        self.context = context
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DetailPanelMetrics.figureSpacing) {
            if let label {
                Text(verbatim: label)
                    .font(Typography.callout)
                    .foregroundStyle(Palette.text2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Text(verbatim: figure)
                .font(Typography.largeTitle)
                .foregroundStyle(Palette.text)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(DetailPanelMetrics.minimumFigureScale)
            if let context {
                Text(verbatim: context)
                    .font(Typography.body)
                    .foregroundStyle(Palette.text2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
