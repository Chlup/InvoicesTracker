import SwiftUI

/// A section of the breakdown: its title with the colour of its authority, or the green of the net income, and its rows
/// one under the other.
struct ComputationCard: View {
    let section: ComputationSection

    /// The colour of the dot before the title: the green of the net income, the colour of the authority the section is
    /// about, or grey for a section that is about none.
    private var dotColor: Color {
        if section.isNetIncome {
            return Color(.netIncome)
        }
        return section.authority?.color ?? Color.secondary
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Circle()
                    .fill(dotColor)
                    .frame(width: 10, height: 10)
                    .accessibilityHidden(true)
                Text(verbatim: section.title)
                    .font(.system(size: 15, weight: .semibold))
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength: 0)
                if let tag = section.tag {
                    Text(verbatim: tag)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.bottom, 10)
            ForEach(section.rows) { row in
                rule(before: row)
                ComputationRowView(row: row)
            }
        }
        .padding(.horizontal, 22)
        .padding(.top, 18)
        .padding(.bottom, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
        .accessibilityElement(children: .contain)
    }

    /// The line above a row: a heavy one above a total, a darker hairline above a result, and a light one above the
    /// other rows. The lines are the text colour at a low opacity, so they follow the appearance.
    @ViewBuilder
    private func rule(before row: ComputationRow) -> some View {
        switch row.style {
        case .total:
            Rectangle()
                .fill(Color.primary)
                .frame(height: 1.5)
        case .plain, .strong:
            Rectangle()
                .fill(Color.primary.opacity(row.sign == .equals ? 0.16 : 0.07))
                .frame(height: 1)
        }
    }
}

/// A row: the sign, the label with its note under it, and the value on the right in digits of one width.
private struct ComputationRowView: View {
    let row: ComputationRow

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(verbatim: row.sign.rawValue)
                .fontWeight(.bold)
                .foregroundStyle(row.style == .total ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary))
                .frame(width: 18)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: row.label)
                    .fontWeight(weight)
                    .fixedSize(horizontal: false, vertical: true)
                if let note = row.note {
                    Text(verbatim: note)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Text(verbatim: row.value)
                .font(row.style == .total ? .system(size: 17, weight: .bold) : .body.weight(weight))
                .monospacedDigit()
                .multilineTextAlignment(.trailing)
                .fixedSize(horizontal: true, vertical: false)
        }
        .padding(.vertical, 8)
        // VoiceOver reads the label, the value with its sign and then the note in one phrase.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(row.spokenText)
    }

    private var weight: Font.Weight {
        switch row.style {
        case .plain: .regular
        case .strong: .semibold
        case .total: .bold
        }
    }
}
