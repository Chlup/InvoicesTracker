import SwiftUI

/// The line at the bottom of the income card with the uniform rates of the year: a pill for the rate of every foreign
/// currency of the year, then where the rates are from and what the income of the year is converted with.
struct UniformRateLine: View {
    let line: UniformLine

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Divider()
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    rates
                    source
                }
                VStack(alignment: .leading, spacing: 6) {
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        rates
                    }
                    source
                }
            }
        }
    }

    /// The title and a pill for each rate.
    @ViewBuilder
    private var rates: some View {
        Text(line.title)
            .fontWeight(.semibold)
        ForEach(line.rates, id: \.self) { rate in
            Text(rate)
                .fontWeight(.semibold)
                .monospacedDigit()
                .lineLimit(1)
                .padding(.horizontal, 9)
                .padding(.vertical, 3)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 10))
        }
    }

    private var source: some View {
        Text(line.source)
            .font(.callout)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}
