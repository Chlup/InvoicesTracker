import SwiftUI

/// The three tiles above the table: the number of invoices of the category, their total without VAT in crowns at the
/// ČNB rates, and the same total at the uniform rate of the year. The two totals let the person compare the two lawful
/// ways to convert income for the year.
struct InvoiceTilesView: View {
    let tiles: [SummaryTile]

    var body: some View {
        AdaptiveColumns(minimumColumnWidth: 220, spacing: 12, equalRowHeights: true) {
            ForEach(tiles) { tile in
                TileView(tile: tile)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Souhrn")
    }
}

private struct TileView: View {
    let tile: SummaryTile

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(tile.title)
                .font(.callout)
                .foregroundStyle(.secondary)
            Text(verbatim: tile.value)
                .font(.system(size: 19, weight: .bold))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .foregroundStyle(tile.isMuted ? Color.secondary : Color.primary)
            Text(tile.subtitle)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .screenCard(cornerRadius: 14)
        .accessibilityElement(children: .combine)
    }
}
