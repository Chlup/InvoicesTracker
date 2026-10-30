import SwiftUI

/// "Zaplatíte za rok …": the three levies together in big rounded digits, what they are a month and of the income, the
/// bar of their parts, a line for each with what applies to it, and under a divider the net income, what the income
/// leaves after them: its average per month in bold green, with the sum of the whole year under it. Where the levies
/// are more than the income, the average is negative and in the orange of a warning.
struct SimulatorResultCard: View {
    let summary: SimulatorSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            SimulatorCardTitle(text: summary.heading)
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: summary.total)
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                Text(verbatim: summary.subline)
                    .monospacedDigit()
                    .simulatorNote()
            }
            .accessibilityElement(children: .combine)
            AuthorityShareBar(shares: summary.shares)
            VStack(alignment: .leading, spacing: 10) {
                ForEach(summary.lines) { line in
                    levyLine(line)
                }
            }
            Divider()
            netIncome
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
        .accessibilityElement(children: .contain)
        .accessibilityLabel(summary.heading)
    }

    /// The dot of the authority, the levy with its note under it, and the amount.
    private func levyLine(_ line: SimulatorLevyLine) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Circle()
                .fill(line.authority.color)
                .frame(width: 8, height: 8)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: line.label)
                if let note = line.note {
                    Text(verbatim: note)
                        .simulatorNote()
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Text(verbatim: line.amount)
                .fontWeight(.semibold)
                .monospacedDigit()
                .fixedSize()
        }
        .accessibilityElement(children: .combine)
    }

    /// The net income: the dot in the green of the net income with its words, the average per month, and under them the
    /// sum of the year with the reminder that the real expenses are not taken off. The amount stands beside its words
    /// where they fit together, else under them. It is in the green of the text of a banner, or, where the levies are
    /// more than the income, in the orange of a warning, while the words keep their colour. VoiceOver reads the three
    /// as one phrase.
    private var netIncome: some View {
        let net = summary.netIncome
        let words = HStack(alignment: .firstTextBaseline, spacing: 10) {
            Circle()
                .fill(Color(.netIncome))
                .frame(width: 8, height: 8)
                .accessibilityHidden(true)
            Text(verbatim: net.label)
        }
        let figure = Text(verbatim: net.amount)
            .fontWeight(.bold)
            .monospacedDigit()
            .foregroundStyle(net.isNegative ? Color(.simulationText) : Color(.bannerText))
        return VStack(alignment: .leading, spacing: 2) {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    words
                    Spacer(minLength: 0)
                    figure
                }
                VStack(alignment: .leading, spacing: 2) {
                    words
                    figure
                }
            }
            Text(verbatim: net.sub)
                .monospacedDigit()
                .simulatorNote()
        }
        .accessibilityElement(children: .combine)
    }
}
