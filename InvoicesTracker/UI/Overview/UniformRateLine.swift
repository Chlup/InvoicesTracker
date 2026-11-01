import SwiftUI

/// The sizes and gaps of the line of the uniform rates.
private nonisolated enum UniformRateLineMetrics {
    /// The space between the hairline and the words under it.
    static let hairlineGap: CGFloat = 12

    /// The space between the title, the pills and the source on a row.
    static let spacing: CGFloat = 10

    /// The space between the rows where they do not fit one.
    static let lineSpacing: CGFloat = 6

    /// The space between the edge of a pill and its words, at the sides and above and below.
    static let pillPadding = EdgeInsets(top: 2, leading: 8, bottom: 2, trailing: 8)
}

/// The line at the bottom of the income card with the uniform rates of the year, under a hairline: the title, a pill
/// for the rate of every foreign currency of the year, then where the rates are from and what the income of the year
/// is converted with. All in the callout size and the grey of secondary text, the title in semibold and the colour of
/// text, the pills on the inset colour as capsules. They stand on one row where there is room, and go on to the next
/// where there is not.
struct UniformRateLine: View {
    let line: UniformLine

    var body: some View {
        VStack(alignment: .leading, spacing: UniformRateLineMetrics.hairlineGap) {
            Hairline()
            FlowLayout(
                spacing: UniformRateLineMetrics.spacing, lineSpacing: UniformRateLineMetrics.lineSpacing
            ) {
                Text(verbatim: line.title)
                    .font(Typography.calloutSemibold)
                    .foregroundStyle(Palette.text)
                ForEach(line.rates, id: \.self) { rate in
                    Text(verbatim: rate)
                        .font(Typography.calloutSemibold)
                        .monospacedDigit()
                        .foregroundStyle(Palette.text)
                        .lineLimit(1)
                        .padding(UniformRateLineMetrics.pillPadding)
                        .background(Palette.bgInset, in: Capsule())
                }
                Text(verbatim: line.source)
                    .font(Typography.callout)
                    .foregroundStyle(Palette.text2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
