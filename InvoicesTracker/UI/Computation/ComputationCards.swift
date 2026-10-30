import SwiftUI

/// The note above the cards about what the computation counts up to the day shown: a note of the information tone,
/// blue. Simulátor's note has a small secondary button at its end. VoiceOver reads a note without a button as one
/// phrase, and reaches the button of one that has it on its own.
struct ComputationBanner: View {
    let text: String

    /// The title and the action of the button at the end of the note, such as "Začít znovu", or nil for none.
    var button: (title: String, action: () -> Void)?

    var body: some View {
        if let button {
            Note(.info, text: text) {
                Button(button.title, action: button.action)
                    .buttonStyle(CapsuleButtonStyle(.secondary, size: .small))
            }
        } else {
            Note(.info, text: text)
        }
    }
}

// MARK: - Mezní odvod

/// The sizes and gaps of the marginal levy, in points.
private nonisolated enum MarginalMetrics {
    /// The space between the parts of the compact form, which is a section of a card and not a card.
    static let compactSpacing: CGFloat = 10

    /// The space between the title and the total, on one line or under each other.
    static let headingSpacing: CGFloat = 8

    /// The height of the bar of the three authorities, and the radius of its corners.
    static let barHeight: CGFloat = 8
    static let barRadius: CGFloat = 4
}

/// What the three levies take of the next crown: the heading "Mezní odvod" with the total at the other end of its line
/// in the title style, a bar that the part of each authority fills to its rate, and the sentence that says it in
/// crowns. VoiceOver reads the heading, the total and the sentence, and not the bar.
///
/// The full form is a card of its own, as Výpočet shows it, with a title 3 heading and the sentence in body text. The
/// compact form is a section of another card, as the Simulátor shows it in its result card: a headline for the heading,
/// the sentence in callout, and no card look of its own, no padding and no rule. The card it stands in sets it apart
/// from its other sections. Both are read as a group under "Mezní odvod".
struct MarginalCard: View {
    let marginal: ComputationMarginal

    /// Whether this is the compact form, a section of another card, and not a card of its own.
    let compact: Bool

    /// The marginal levy `marginal` as a card of its own, or as a section of another card where `compact` is true.
    init(marginal: ComputationMarginal, compact: Bool = false) {
        self.marginal = marginal
        self.compact = compact
    }

    var body: some View {
        if compact {
            VStack(alignment: .leading, spacing: MarginalMetrics.compactSpacing) {
                parts
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Mezní odvod")
        } else {
            Card(label: "Mezní odvod", fillsHeight: true) {
                parts
            }
        }
    }

    /// The heading, the bar and the sentence.
    @ViewBuilder
    private var parts: some View {
        heading
        AuthorityShareBar(shares: marginal.shares)
        Text(verbatim: marginal.text)
            .font(compact ? Typography.callout : Typography.body)
            .foregroundStyle(Palette.text2)
            .fixedSize(horizontal: false, vertical: true)
    }

    /// The title and the total on one line, baseline to baseline, or under each other where they do not fit one.
    private var heading: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .firstTextBaseline, spacing: MarginalMetrics.headingSpacing) {
                title
                Spacer(minLength: MarginalMetrics.headingSpacing)
                total
            }
            VStack(alignment: .leading, spacing: MarginalMetrics.headingSpacing) {
                title
                total
            }
        }
    }

    /// The title of the card, a heading of its group: title 3 in the card, headline in a section of another card.
    private var title: some View {
        Text("Mezní odvod")
            .font(compact ? Typography.headline : Typography.title3)
            .foregroundStyle(Palette.text)
            .accessibilityAddTraits(.isHeader)
    }

    /// What the three levies take of the next crown, "37,8 %", in the title style. It is never cut or broken.
    private var total: some View {
        Text(verbatim: marginal.total)
            .font(Typography.title)
            .monospacedDigit()
            .foregroundStyle(Palette.text)
            .fixedSize()
    }
}

/// The parts of the three authorities one after the other on a track, each in its colour and as wide as its fraction
/// of the whole bar, 8 points high with rounded ends. What no part fills is the track, so a bar of parts that add up to
/// less than 1 is partly empty, and nothing is drawn of a part of 0. Mezní odvod draws the rates of the next crown so,
/// and a bar of what the authorities are paid draws their shares of the total, which add up to 1.
struct AuthorityShareBar: View {
    let shares: [MarginalShare]

    var body: some View {
        GeometryReader { proxy in
            HStack(spacing: 0) {
                ForEach(shares) { share in
                    Rectangle()
                        .fill(share.authority.color)
                        .frame(width: proxy.size.width * share.fraction)
                }
                Spacer(minLength: 0)
            }
        }
        .frame(height: MarginalMetrics.barHeight)
        .background(Palette.fill)
        .clipShape(RoundedRectangle(cornerRadius: MarginalMetrics.barRadius))
        .accessibilityHidden(true)
    }
}

// MARK: - Hranice roku

/// How far the year is from its limits: a line with the title and where the year stands, and a bar of the way, for
/// each of them.
struct ThresholdsCard: View {
    let thresholds: ComputationThresholds

    var body: some View {
        Card(title: thresholds.heading, label: "Hranice roku", fillsHeight: true) {
            ForEach(thresholds.bars) { bar in
                ThresholdLine(bar: bar)
            }
        }
    }
}

/// The sizes and gaps of the line of a limit of the year, in points.
private nonisolated enum ThresholdMetrics {
    /// The space between the title and where the year stands, on the line of a limit.
    static let valueSpacing: CGFloat = 8

    /// The space between the line of a limit and its bar.
    static let lineSpacing: CGFloat = 6

    /// The height of the bar of a limit, and the radius of its corners.
    static let barHeight: CGFloat = 6
    static let barRadius: CGFloat = 3
}

/// A limit of the year: its title and, at the other end of the line, where the year stands, in secondary text, or in
/// the green of text where the limit is reached and the reaching is good news; under them the bar of the way there.
private struct ThresholdLine: View {
    let bar: ThresholdBar

    var body: some View {
        VStack(alignment: .leading, spacing: ThresholdMetrics.lineSpacing) {
            HStack(alignment: .firstTextBaseline, spacing: ThresholdMetrics.valueSpacing) {
                Text(verbatim: bar.title)
                    .font(Typography.body)
                    .foregroundStyle(Palette.text)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: ThresholdMetrics.valueSpacing)
                Text(verbatim: bar.value)
                    .font(Typography.body)
                    .monospacedDigit()
                    .foregroundStyle(bar.isHighlighted ? Palette.greenText : Palette.text2)
                    .fixedSize()
            }
            track
        }
        .accessibilityElement(children: .combine)
    }

    /// The way to the limit, in the colour of its authority, or in the grey of secondary text, on the track.
    private var track: some View {
        GeometryReader { proxy in
            Rectangle()
                .fill(bar.authority?.color ?? Palette.text2)
                .frame(width: proxy.size.width * bar.fraction)
        }
        .frame(height: ThresholdMetrics.barHeight)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.fill)
        .clipShape(RoundedRectangle(cornerRadius: ThresholdMetrics.barRadius))
        .accessibilityHidden(true)
    }
}

// MARK: - Předpoklady výpočtu

/// The sizes and gaps of the footnote of the assumptions, in points.
private nonisolated enum FootnoteMetrics {
    /// The space between the heading, the bullets and the link.
    static let spacing: CGFloat = 6

    /// The space around the footnote at its sides and above it. Under it there is none.
    static let inset: CGFloat = 4

    /// How far the list is set in from the left edge of the footnote: the dots of the bullets hang in it.
    static let indent: CGFloat = 16

    /// The space between a dot and the text of its bullet, which hangs out at the left of it.
    static let dotGap: CGFloat = 6

    /// The space under a bullet.
    static let bulletGap: CGFloat = 3

    /// The least width of a column of bullets, and the space between two columns. Two columns and their gap take 632
    /// points of the list; with less, the bullets stand in one.
    static let minimumColumnWidth: CGFloat = 300
    static let columnGap: CGFloat = 32
}

/// What the computation takes for granted, as the footnote of the page. It is not a card but small text in the grey of
/// secondary text: "Předpoklady výpočtu" in callout semibold, the assumptions as bullets under it, and the link
/// "Pravidla v Nastavení" under them, which opens the rules of the year. The bullets stand in two columns of at least
/// 300 points with 32 between them where the list has the 632 points that takes, the first half in the left column and
/// the rest in the right one, and in one column where it has less. VoiceOver reads the footnote as a group under its
/// heading, and the bullets one by one, without their dots.
struct AssumptionsFootnote: View {
    let assumptions: ComputationAssumptions
    let showSettings: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: FootnoteMetrics.spacing) {
            Text("Předpoklady výpočtu")
                .font(Typography.calloutSemibold)
                .accessibilityAddTraits(.isHeader)
            bullets
                .padding(.leading, FootnoteMetrics.indent)
            Button("Pravidla v Nastavení", action: showSettings)
                .buttonStyle(TextLinkButtonStyle())
        }
        .font(Typography.callout)
        .foregroundStyle(Palette.text2)
        .padding(.horizontal, FootnoteMetrics.inset)
        .padding(.top, FootnoteMetrics.inset)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Předpoklady výpočtu")
    }

    /// The bullets in two columns that come to one where the room is short, the first half of them (the larger one,
    /// when there is an odd number) on the left. The bullets touch, as the lines of a list do, also where the columns
    /// have come to one.
    private var bullets: some View {
        let split = (assumptions.items.count + 1) / 2
        return TwoColumnStack(
            minimumColumnWidth: FootnoteMetrics.minimumColumnWidth, spacing: FootnoteMetrics.columnGap,
            stackedSpacing: 0
        ) {
            column(Array(assumptions.items[..<split]))
        } right: {
            column(Array(assumptions.items[split...]))
        }
    }

    /// The bullets of `items` one under the other.
    private func column(_ items: [String]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(items, id: \.self) { item in
                bullet(item)
            }
        }
    }

    /// A bullet: its text, 3 points of room under it, and its dot hanging out at the left of the text, in the indent of
    /// the list or in the gap between the columns. The dot is only for the eyes.
    private func bullet(_ text: String) -> some View {
        Text(verbatim: text)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.bottom, FootnoteMetrics.bulletGap)
            .overlay(alignment: .topLeading) {
                Text(verbatim: "•")
                    .alignmentGuide(.leading) { dot in
                        dot[.trailing] + FootnoteMetrics.dotGap
                    }
                    .accessibilityHidden(true)
            }
    }
}
