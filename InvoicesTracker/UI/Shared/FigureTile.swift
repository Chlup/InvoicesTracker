import SwiftUI

/// What a figure tile says: a figure with the label over it, the share of the income next to it, and a note under it.
/// The texts are the builder's; the view only shows them.
nonisolated struct FigureTileData: Sendable, Hashable {
    /// The label over the figure, such as "Doplatek".
    var label: String

    /// The figure as it is shown, such as "5 371 Kč".
    var figure: String

    /// The share of the income that goes with the figure, such as "16,7 %", or nil for none. It stands beside the
    /// figure.
    var share: String?

    /// The note under the figure, such as "s přiznáním a přehledy za rok 2026", or nil for none.
    var note: String?

    /// Whether the tile is about the net income, which a green mark in front of its label shows (`marker`).
    var marksNetIncome = false

    /// What the mark in front of the label of a tile about the net income looks like. A tile that is not about the net
    /// income has none, whatever this is.
    var marker = NetIncomeMarker.dot
}

/// The green mark in front of the label of a tile about the net income. The two shapes are the two ways the design
/// marks the net income: as a dot where a card gives it a figure of its own, and as the short line of the key of the
/// net income line in the legend of a chart where the figure stands over that chart.
nonisolated enum NetIncomeMarker: Sendable, Hashable {
    /// A dot of 8 points, as the card of Odhad odvodů marks it.
    case dot

    /// A line of 16 by 3 points, like the key of the net income in the legend of the charts, as the strip over the
    /// chart of Příjmy marks it.
    case line
}

/// The sizes and gaps of a figure tile.
private nonisolated enum FigureTileMetrics {
    /// The space between the label, the figure and the note.
    static let spacing: CGFloat = 2

    /// The space between the figure and its share.
    static let shareGap: CGFloat = 8

    /// The size of the dot that marks the net income.
    static let dotSize: CGFloat = 8

    /// The size of the line that marks the net income.
    static let lineSize = CGSize(width: 16, height: 3)

    /// The space between the mark and the label.
    static let dotGap: CGFloat = 6
}

/// A figure with its label, its share and its note: the label in callout and secondary text, the figure in title 2 and
/// the colour of text with the share beside it in body semibold and secondary text, and the note in callout and
/// tertiary text. A tile about the net income has a green mark in front of its label, a dot or a line
/// (`NetIncomeMarker`). VoiceOver reads the tile as one phrase, and not the mark.
///
/// Tiles stand next to each other in a `FigureRow`; they are as wide as their texts are, and never stretched into
/// columns.
struct FigureTile: View {
    let data: FigureTileData

    /// A tile that shows `data`.
    init(_ data: FigureTileData) {
        self.data = data
    }

    var body: some View {
        VStack(alignment: .leading, spacing: FigureTileMetrics.spacing) {
            labelLine
            figureLine
            if let note = data.note {
                Text(verbatim: note)
                    .font(Typography.callout)
                    .foregroundStyle(Palette.text3)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
    }

    /// The label, with the green mark in front of it where the tile is about the net income: a dot that sits on the
    /// baseline of the first line of the label, or a line that is centred on the height of the label, as the key of a
    /// legend is.
    @ViewBuilder
    private var labelLine: some View {
        if data.marksNetIncome, data.marker == .line {
            HStack(alignment: .center, spacing: FigureTileMetrics.dotGap) {
                Capsule()
                    .fill(Palette.green)
                    .frame(width: FigureTileMetrics.lineSize.width, height: FigureTileMetrics.lineSize.height)
                    .accessibilityHidden(true)
                label
            }
        } else {
            HStack(alignment: .firstTextBaseline, spacing: FigureTileMetrics.dotGap) {
                if data.marksNetIncome {
                    Circle()
                        .fill(Palette.green)
                        .frame(width: FigureTileMetrics.dotSize, height: FigureTileMetrics.dotSize)
                        .accessibilityHidden(true)
                }
                label
            }
        }
    }

    /// The words that say what the figure is.
    private var label: some View {
        Text(verbatim: data.label)
            .font(Typography.callout)
            .foregroundStyle(Palette.text2)
            .fixedSize(horizontal: false, vertical: true)
    }

    /// The figure, with its share on its baseline. It is never cut or broken, as an amount cut short would read as a
    /// smaller one.
    private var figureLine: some View {
        HStack(alignment: .firstTextBaseline, spacing: FigureTileMetrics.shareGap) {
            Text(verbatim: data.figure)
                .font(Typography.title2)
                .foregroundStyle(Palette.text)
                .monospacedDigit()
            if let share = data.share {
                Text(verbatim: share)
                    .font(Typography.bodySemibold)
                    .monospacedDigit()
                    .foregroundStyle(Palette.text2)
            }
        }
        .fixedSize()
    }
}

/// How the figures of a row sit.
private nonisolated enum FigureRowMetrics {
    /// The space between two rows of tiles, where they do not fit one.
    static let lineSpacing: CGFloat = 12
}

/// Tiles next to each other with one gap between them, `spacing` points, 48 unless told otherwise. They go on to the
/// next row, 12 points lower, where they do not fit the width, and they line up at their top. A tile is never stretched
/// to fill the width, and is held to `maxTileWidth` where that is given, so that its texts break there.
struct FigureRow<Content: View>: View {
    let spacing: CGFloat
    let maxTileWidth: CGFloat?
    private let content: Content

    /// A row of the tiles in `content`.
    init(spacing: CGFloat = 48, maxTileWidth: CGFloat? = nil, @ViewBuilder content: () -> Content) {
        self.spacing = spacing
        self.maxTileWidth = maxTileWidth
        self.content = content()
    }

    var body: some View {
        FlowLayout(
            spacing: spacing, lineSpacing: FigureRowMetrics.lineSpacing, alignment: .top,
            maximumSubviewWidth: maxTileWidth
        ) {
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
