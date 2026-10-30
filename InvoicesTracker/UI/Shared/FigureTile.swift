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

    /// Whether the tile is about the net income, which a green dot in front of its label marks.
    var marksNetIncome = false
}

/// The sizes and gaps of a figure tile.
private nonisolated enum FigureTileMetrics {
    /// The space between the label, the figure and the note.
    static let spacing: CGFloat = 2

    /// The space between the figure and its share.
    static let shareGap: CGFloat = 8

    /// The size of the dot that marks the net income.
    static let dotSize: CGFloat = 8

    /// The space between the dot and the label.
    static let dotGap: CGFloat = 6
}

/// A figure with its label, its share and its note: the label in callout and secondary text, the figure in title 2 with
/// the share beside it in body semibold and secondary text, and the note in callout and tertiary text. VoiceOver reads
/// the tile as one phrase, and not the dot.
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

    /// The label, with the green dot in front of it where the tile is about the net income.
    private var labelLine: some View {
        HStack(alignment: .firstTextBaseline, spacing: FigureTileMetrics.dotGap) {
            if data.marksNetIncome {
                Circle()
                    .fill(Palette.green)
                    .frame(width: FigureTileMetrics.dotSize, height: FigureTileMetrics.dotSize)
                    .accessibilityHidden(true)
            }
            Text(verbatim: data.label)
                .font(Typography.callout)
                .foregroundStyle(Palette.text2)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// The figure, with its share on its baseline. It is never cut or broken, as an amount cut short would read as a
    /// smaller one.
    private var figureLine: some View {
        HStack(alignment: .firstTextBaseline, spacing: FigureTileMetrics.shareGap) {
            Text(verbatim: data.figure)
                .font(Typography.title2)
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
