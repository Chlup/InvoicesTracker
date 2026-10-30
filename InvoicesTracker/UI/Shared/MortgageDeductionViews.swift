import SwiftUI

/// The fields of the interest on a mortgage, as Zálohy a odpočty and Simulátor lay them out: the interest paid in the
/// year, the months it was paid for and the limit by when the housing was acquired, in a row that wraps where it is
/// narrow.
struct MortgageInterestFields: View {
    let inputs: DeductionInputs
    let cap: Binding<MortgageCap>

    var body: some View {
        FlowLayout(spacing: 20) {
            HStack(alignment: .bottom, spacing: 6) {
                TitledAmountField(.mortgageInterest, title: "Zaplacené úroky za rok", width: 120, inputs: inputs)
                Text("Kč")
                    .padding(.bottom, 4)
            }
            TitledAmountField(.mortgageMonths, title: "Placeno měsíců", width: 64, inputs: inputs)
            capPicker
        }
    }

    private var capPicker: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Limit podle data pořízení bydlení")
                .font(.callout)
                .foregroundStyle(.secondary)
            Picker("Limit podle data pořízení bydlení", selection: cap) {
                ForEach(MortgageCap.choices, id: \.self) { choice in
                    Text(choice.choiceLabel)
                        .tag(choice)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .fixedSize()
        }
    }
}

/// What the interest allows, from the computation of the year: "Uplatníte 150 000 Kč", what of it is over the limit and
/// does not count, and the limit for the months of the interest.
struct MortgageClaimSummary: View {
    let hints: DeductionHints

    var body: some View {
        FlowLayout(spacing: 16) {
            HStack(spacing: 4) {
                Text("Uplatníte")
                Text(hints.mortgageAllowed)
                    .fontWeight(.semibold)
            }
            .monospacedDigit()
            if let over = hints.mortgageOverLimit {
                Text("\(over) nad limit se neuplatní")
                    .monospacedDigit()
                    .foregroundStyle(Color(.simulationText))
            }
            Text(hints.mortgageLimit + " · limit platí pro celou domácnost")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.6), in: RoundedRectangle(cornerRadius: 12))
        .accessibilityElement(children: .combine)
    }
}
