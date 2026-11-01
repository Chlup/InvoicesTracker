import SwiftUI

/// A card of a screen: its content on a card of the design, padded 20 points, with the width of the room it is in. An
/// optional heading comes first: the title in title 3 with the subtitle under it in callout and secondary text, and
/// at the end of the line of the title an accessory, a note such as the version of the rules or an amount such as the
/// sum of the adjustments. The parts of the card are `spacing` points apart, 12 unless told otherwise.
///
/// VoiceOver reads the card as a group under `label`, or under the title where there is no label, and the title as a
/// heading in it. Give a label where the card is read under another name than the one it shows.
struct Card<Content: View>: View {
    let title: String?
    let subtitle: String?
    let accessory: String?

    /// Whether the accessory is an amount, in semibold text of the colour of text, rather than a note in callout.
    let accessoryIsAmount: Bool
    let spacing: CGFloat
    let label: String?

    /// Whether the card takes the height it is offered, so that the cards of a row of equal heights
    /// (`AdaptiveColumns`) are of one height. Offered none, or where this is false, it is as high as its content.
    let fillsHeight: Bool
    private let content: Content

    /// A card with `content`, which has a heading where there is a `title`, a `subtitle` or an `accessory`.
    init(
        title: String? = nil, subtitle: String? = nil, accessory: String? = nil, accessoryIsAmount: Bool = false,
        spacing: CGFloat = DesignMetrics.innerSpacing, label: String? = nil, fillsHeight: Bool = false,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.subtitle = subtitle
        self.accessory = accessory
        self.accessoryIsAmount = accessoryIsAmount
        self.spacing = spacing
        self.label = label
        self.fillsHeight = fillsHeight
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: spacing) {
            if title != nil || subtitle != nil || accessory != nil {
                header
            }
            content
        }
        .padding(DesignMetrics.cardPadding)
        .frame(maxWidth: .infinity, maxHeight: fillsHeight ? .infinity : nil, alignment: .topLeading)
        .card()
        .accessibilityElement(children: .contain)
        .labelled(label ?? title)
    }

    /// The title with the subtitle under it, and the accessory at the end of the line of the title.
    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                if let title {
                    CardTitle(text: title)
                }
                if let subtitle {
                    Text(verbatim: subtitle)
                        .font(Typography.callout)
                        .foregroundStyle(Palette.text2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 8)
            if let accessory {
                Text(verbatim: accessory)
                    .font(accessoryIsAmount ? Typography.bodySemibold : Typography.callout)
                    .monospacedDigit()
                    .foregroundStyle(accessoryIsAmount ? Palette.text : Palette.text2)
            }
        }
    }
}

/// The title of a card: title 3 in the colour of text, a heading for VoiceOver. A card draws it in its header. A card
/// whose header holds more beside the title than a note or an amount, such as the pill of the interest on a mortgage,
/// draws it itself in a header of its own, so that the title is the same everywhere.
struct CardTitle: View {
    let text: String

    var body: some View {
        Text(verbatim: text)
            .font(Typography.title3)
            .foregroundStyle(Palette.text)
            .accessibilityAddTraits(.isHeader)
    }
}

/// The heading of a section of a page that stands outside any card, such as "Rozpis výpočtu" over the cards of a
/// breakdown: the title of a card (`CardTitle`: title 3 in the colour of text, a heading for VoiceOver) set 4 points in
/// from the sides, as the prototype sets it.
struct SectionHeading: View {
    let text: String

    /// The space at the sides of the heading, in points.
    static let inset: CGFloat = 4

    var body: some View {
        CardTitle(text: text)
            .padding(.horizontal, Self.inset)
    }
}

extension View {
    /// The look of a card: the colour of a card on a rounded rectangle with the corners of a card (16 points), raised
    /// off the page by the elevation of a card, a hairline ring and a faint shadow. It takes the colours from the
    /// palette, so it follows the appearance of the window. Give the view its padding first, and clip it first where
    /// its content runs to the edge, as a table does.
    ///
    /// The look is the background of the view, so it lies under all of its content: the content casts no shadow of its
    /// own, and what hangs out of the view, such as a popover, covers the edge of the card. Only the rounded rectangle
    /// casts the shadow of the card (`InsettableShape.surface(_:elevation:)`).
    func card() -> some View {
        background {
            RoundedRectangle(cornerRadius: DesignMetrics.cardRadius)
                .surface(Palette.bgCard, elevation: .card)
        }
    }

    /// The look of a panel that pops up over a chart, such as the box that follows the pointer along the columns of a
    /// chart: its content in body text of the colour of text, padded 14 points at the sides and 12 above and below, as
    /// wide as the content needs, on the colour of a card with the corners of a panel (10 points), raised off the chart
    /// by the elevation of a pop. Like the look of a card it is the background of the view, so it lies under all of its
    /// content. What VoiceOver reads of the panel is the caller's to say.
    func popPanel() -> some View {
        font(Typography.body)
            .foregroundStyle(Palette.text)
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .fixedSize(horizontal: true, vertical: false)
            .background {
                RoundedRectangle(cornerRadius: DesignMetrics.panelRadius)
                    .surface(Palette.bgCard, elevation: .pop)
            }
    }

    /// Reads the view to VoiceOver as a group named `name` that holds one group of its own, as the aside of the design
    /// holds its section: the Simulátor's column with the result is "Výsledek simulace" and the card in it "Kolik
    /// zaplatíte". SwiftUI makes one element of a group that holds only a group and gives it the outer name, so the
    /// view gets an empty overlay that VoiceOver never reads, which keeps the two apart and changes no layout.
    func accessibilityAside(named name: String) -> some View {
        overlay {
            Color.clear
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(name)
    }

    /// Reads the view to VoiceOver under `name`, or leaves it as it is where there is none.
    @ViewBuilder
    fileprivate func labelled(_ name: String?) -> some View {
        if let name {
            accessibilityLabel(name)
        } else {
            self
        }
    }
}
