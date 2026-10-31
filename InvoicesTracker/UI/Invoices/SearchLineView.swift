import SwiftUI

/// The line under the filters while a search is on: how many invoices of the year match, links to the other years that
/// have matches ("další shody v letech 2025 (2)"), and Zrušit hledání. The line is a panel on the window, in the colour
/// of a card with the corners of a panel; the links to the years are capsules 28 points tall in the pale blue of the
/// accent, and Zrušit hledání is a link.
struct SearchLineView: View {
    let line: SearchLine

    /// A link to another year was chosen: shows that year and keeps the search.
    let showYear: (Int) -> Void

    /// Zrušit hledání.
    let clear: () -> Void

    var body: some View {
        // The line is a panel on the window, not a card: the corners of a panel, with the elevation of a card.
        let shape = RoundedRectangle(cornerRadius: DesignMetrics.panelRadius)
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                found
                Spacer(minLength: 8)
                cancel
            }
            VStack(alignment: .leading, spacing: 6) {
                found
                cancel
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            shape.surface(Palette.bgCard, elevation: .card)
        }
        .accessibilityElement(children: .contain)
    }

    /// What the search found, and the years where it found more.
    private var found: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(line.text)
                .font(Typography.bodySemibold)
                .foregroundStyle(Palette.text)
                .lineLimit(1)
            if !line.otherYears.isEmpty {
                Text("další shody v letech")
                    .font(Typography.body)
                    .foregroundStyle(Palette.text2)
                    .lineLimit(1)
                ForEach(line.otherYears, id: \.year) { matches in
                    Button {
                        showYear(matches.year)
                    } label: {
                        Text(verbatim: matches.label)
                            .font(Typography.bodySemibold)
                            .monospacedDigit()
                            .foregroundStyle(Palette.accentText)
                            .padding(.horizontal, 10)
                            .frame(height: DesignMetrics.smallControlHeight)
                            .background(Palette.accentTint, in: Capsule())
                            .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(matches.accessibilityLabel)
                }
            }
        }
    }

    /// Zrušit hledání, a link in callout.
    private var cancel: some View {
        Button("Zrušit hledání", action: clear)
            .buttonStyle(TextLinkButtonStyle())
            .font(Typography.callout)
    }
}
