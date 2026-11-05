import SwiftUI

/// A section of the breakdown as a bill: its title with the colour of its authority, or the grey of the income, or the
/// green of the net income, and its rows one under the other, each under a rule. The card is padded 20 points, and 12
/// at its foot, where the last row has 8 of its own.
struct ComputationCard: View {
    let section: ComputationSection

    /// The colour of the dot before the title: the green of the net income, the colour of the authority the section is
    /// about, or the grey of secondary text for a section that is about none, the income.
    private var dotColor: Color {
        if section.isNetIncome {
            return Palette.green
        }
        return section.authority?.color ?? Palette.text2
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: BillMetrics.headerSpacing) {
                Circle()
                    .fill(dotColor)
                    .frame(width: BillMetrics.dotSize, height: BillMetrics.dotSize)
                    .accessibilityHidden(true)
                Text(verbatim: section.title)
                    .font(Typography.title3)
                    .foregroundStyle(Palette.text)
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength: 0)
                if let tag = section.tag {
                    Text(verbatim: tag)
                        .font(Typography.callout)
                        .foregroundStyle(Palette.text3)
                }
            }
            .padding(.bottom, BillMetrics.headerBottom)
            BillRows(rows: section.rows, startsWithRule: true)
        }
        .padding(.horizontal, DesignMetrics.cardPadding)
        .padding(.top, DesignMetrics.cardPadding)
        .padding(.bottom, BillMetrics.footPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
        .accessibilityElement(children: .contain)
    }
}
