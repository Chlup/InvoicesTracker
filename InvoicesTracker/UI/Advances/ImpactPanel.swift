import SwiftUI

/// The panel "Dopad odpočtů a slev na daň": what the deductions and the credits of the family save on the tax of the
/// year as of the day shown, in big rounded numerals, the totals it is made of — the deductions, the spouse credit and
/// the child benefit used, the tax without them and after them — and the effect of each deduction. It is worked out
/// again after each saved change. A year the computation cannot take shows the line that says so in place of the
/// numbers.
struct ImpactPanel: View {
    let model: AdvancesModel

    /// Under the lines of the deductions: why a deduction saves what it does.
    nonisolated static let orderNote = "Úspora u každého odpočtu se počítá po odpočtech uvedených nad ním."

    /// Zobrazit dopad v Přehledu.
    let showOverview: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Dopad odpočtů a slev na daň")
                .font(.system(size: 15, weight: .semibold))
                .accessibilityAddTraits(.isHeader)
            if let totals = model.impactTotals {
                numbers(totals)
            } else if let message = model.impactError {
                Text(verbatim: message)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Divider()
            Text(
                verbatim: "Počítá se z příjmů do zvoleného data. Odpočty a slevy se uplatní za celý rok hned – na děti"
                    + " a manžela/ku za měsíce roku, kdy splňují podmínky. Sociální a zdravotní pojištění se jimi"
                    + " nesnižuje."
            )
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            Button("Zobrazit dopad v Přehledu", action: showOverview)
                .buttonStyle(.link)
                .font(.callout)
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Dopad na daň")
    }

    // MARK: The numbers

    @ViewBuilder
    private func numbers(_ totals: ImpactTotals) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(verbatim: ImpactTotals.savedTitle)
                .font(.callout)
                .foregroundStyle(.secondary)
            Text(verbatim: totals.savedText)
                .font(.system(size: 32, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(Color(.bannerText))
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .accessibilityElement(children: .combine)
        VStack(alignment: .leading, spacing: 6) {
            ForEach(totals.rows, id: \.title) { row in
                totalRow(row)
            }
        }
        if !model.impact.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(model.impact) { line in
                    lineView(line)
                }
                Text(Self.orderNote)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// A line of the totals: its title, which breaks where the panel is narrow, and its value at the other end, which
    /// breaks only when it is longer than the room the title leaves.
    private func totalRow(_ row: ImpactTotalRow) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(verbatim: row.title)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(minWidth: 110, maxWidth: .infinity, alignment: .leading)
            Text(verbatim: row.value)
                .fontWeight(row.isEmphasized ? .semibold : .regular)
                .monospacedDigit()
                .multilineTextAlignment(.trailing)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }

    /// A deduction with what comes off for it and what it saves.
    private func lineView(_ line: ImpactLine) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(line.title)
                .fontWeight(.semibold)
            let applied = CzechFormat.wholeKc(line.appliedKc)
            let saved = CzechFormat.wholeKc(line.taxSavedKc)
            Text("uplatníte \(applied) · ušetříte \(saved)")
                .font(.callout)
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
        .accessibilityElement(children: .combine)
    }
}
