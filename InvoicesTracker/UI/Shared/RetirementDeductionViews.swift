import SwiftUI

/// How much of each limit of the retirement products the claim uses, one under the other: the limit, such as
/// "Společný limit", and "6 480 z 48 000 Kč" at the right, over a bar as full as the claim is of the limit.
struct RetirementLimitBars: View {
    let limits: [LimitUse]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(limits) { use in
                bar(use)
            }
        }
    }

    /// One limit: its title and the claim of it in secondary text, and under them the bar of the use.
    private func bar(_ use: LimitUse) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text(use.title)
                Spacer(minLength: 8)
                Text(use.usedText)
                    .monospacedDigit()
            }
            .font(Typography.callout)
            .foregroundStyle(Palette.text2)
            LimitBar(permille: use.usedPermille)
        }
        .accessibilityElement(children: .combine)
    }
}

/// The bar of a limit: a track 6 points tall in the grey fill, rounded at both ends, and over it from the start the use
/// in the colour of the income tax, as wide as the claim is of the limit (`permille`, thousandths of it). The track
/// clips the use, so it is rounded at the start and straight where it ends. VoiceOver does not read the bar: the line
/// over it says the same in words.
private struct LimitBar: View {
    let permille: Int

    /// The height of the track, in points.
    private static let height: CGFloat = 6

    var body: some View {
        GeometryReader { proxy in
            Capsule()
                .fill(Palette.fill)
                .overlay(alignment: .leading) {
                    Rectangle()
                        .fill(Palette.tax)
                        .frame(width: proxy.size.width * CGFloat(min(max(permille, 0), 1_000)) / 1_000)
                }
                .clipShape(Capsule())
        }
        .frame(height: Self.height)
        .accessibilityHidden(true)
    }
}

/// The fields of the retirement products in as many columns as fit without a title having to break, down to one. The
/// fields of a row start at the same height, because no title breaks. Each screen names the fields itself.
struct RetirementFieldGrid: View {
    let fields: [(field: DeductionField, title: String)]
    let inputs: DeductionInputs

    var body: some View {
        ViewThatFits(in: .horizontal) {
            grid(columns: 4)
            grid(columns: 2)
            grid(columns: 1)
        }
    }

    private func grid(columns: Int) -> some View {
        let rows = stride(from: 0, to: fields.count, by: columns).map { start in
            Array(fields[start..<min(start + columns, fields.count)])
        }
        return Grid(alignment: .topLeading, horizontalSpacing: 20, verticalSpacing: 12) {
            ForEach(rows.indices, id: \.self) { index in
                GridRow(alignment: .top) {
                    ForEach(rows[index], id: \.field) { entry in
                        TitledAmountField(entry.field, title: entry.title, width: nil, inputs: inputs)
                    }
                }
            }
        }
    }
}

/// What to enter for pension savings, with the contributions that count in `year`, and what the products allow
/// together (`allowed`, in semibold text), once the computation of the year says so. The note is in callout and the
/// grey of captions.
struct RetirementNote: View {
    let year: Int
    let allowed: String?

    var body: some View {
        let advice = DeductionHints.pensionAdvice(year: year)
        Group {
            if let allowed {
                let amount = Text(allowed).font(Typography.calloutSemibold).foregroundStyle(Palette.text)
                Text("\(advice). Uplatníte \(amount).")
            } else {
                Text("\(advice).")
            }
        }
        .font(Typography.callout)
        .foregroundStyle(Palette.text3)
        .fixedSize(horizontal: false, vertical: true)
    }
}
