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

    private func bar(_ use: LimitUse) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text(use.title)
                Spacer(minLength: 8)
                Text(use.usedText)
                    .monospacedDigit()
            }
            .font(.callout)
            .foregroundStyle(.secondary)
            ProgressView(value: Double(use.usedPermille), total: 1_000)
                .tint(Authority.tax.color)
                .accessibilityHidden(true)
        }
        .accessibilityElement(children: .combine)
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
/// together (`allowed`), once the computation of the year says so.
struct RetirementNote: View {
    let year: Int
    let allowed: String?

    var body: some View {
        let advice = DeductionHints.pensionAdvice(year: year)
        Group {
            if let allowed {
                Text("\(advice). Uplatníte \(Text(allowed).fontWeight(.semibold).foregroundStyle(.primary)).")
            } else {
                Text("\(advice).")
            }
        }
        .font(.callout)
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)
    }
}
