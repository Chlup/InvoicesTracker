import SwiftUI

/// The line under the filters while a search is on: how many invoices of the year match, links to the other years that
/// have matches ("další shody v letech 2025 (2)"), and Zrušit hledání.
struct SearchLineView: View {
    let line: SearchLine

    /// A link to another year was chosen: shows that year and keeps the search.
    let showYear: (Int) -> Void

    /// Zrušit hledání.
    let clear: () -> Void

    var body: some View {
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
        .screenCard(cornerRadius: 12)
        .accessibilityElement(children: .contain)
    }

    /// What the search found, and the years where it found more.
    private var found: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(line.text)
                .fontWeight(.semibold)
                .lineLimit(1)
            if !line.otherYears.isEmpty {
                Text("další shody v letech")
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                ForEach(line.otherYears, id: \.year) { matches in
                    Button {
                        showYear(matches.year)
                    } label: {
                        Text(verbatim: matches.label)
                            .font(.callout.weight(.semibold))
                            .monospacedDigit()
                            .foregroundStyle(Color.accentColor)
                            .padding(.horizontal, 10)
                            .frame(height: 24)
                            .background(Color.accentColor.opacity(0.14), in: Capsule())
                            .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(matches.accessibilityLabel)
                }
            }
        }
    }

    private var cancel: some View {
        Button("Zrušit hledání", action: clear)
            .buttonStyle(.link)
            .font(.callout)
    }
}
