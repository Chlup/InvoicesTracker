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
                    Text(verbatim: title)
                        .font(Typography.title3)
                        .foregroundStyle(Palette.text)
                        .accessibilityAddTraits(.isHeader)
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

extension View {
    /// The look of a card: the colour of a card on a rounded rectangle with the corners of a card (16 points), raised
    /// off the page by the elevation of a card, a hairline ring and a faint shadow. It takes the colours from the
    /// palette, so it follows the appearance of the window. Give the view its padding first, and clip it first where
    /// its content runs to the edge, as a table does.
    func card() -> some View {
        let shape = RoundedRectangle(cornerRadius: DesignMetrics.cardRadius)
        return background(Palette.bgCard, in: shape)
            .elevation(.card, in: shape)
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
