import SwiftUI

/// The fields of the interest on a mortgage, as Zálohy a odpočty and Simulátor lay them out: the interest paid in the
/// year, the months it was paid for and the limit by when the housing was acquired, in a row that wraps where it is
/// narrow, the rows 12 points apart and the fields 20.
struct MortgageInterestFields: View {
    let inputs: DeductionInputs
    let cap: Binding<MortgageCap>

    var body: some View {
        FlowLayout(spacing: 20, lineSpacing: 12) {
            HStack(alignment: .bottom, spacing: 6) {
                TitledAmountField(.mortgageInterest, title: "Zaplacené úroky za rok", width: 120, inputs: inputs)
                Text("Kč")
                    .font(Typography.body)
                    .foregroundStyle(Palette.text)
                    .padding(.bottom, 4)
            }
            TitledAmountField(.mortgageMonths, title: "Placeno měsíců", width: 64, inputs: inputs)
            capPicker
        }
    }

    private var capPicker: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Limit podle data pořízení bydlení")
                .font(Typography.callout)
                .foregroundStyle(Palette.text2)
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

/// What the interest allows, from the computation of the year, in a panel on the inset background: "Uplatníte
/// 150 000 Kč", what of it is over the limit and does not count, in the orange of text, and the limit for the months of
/// the interest, in the grey of captions.
struct MortgageClaimSummary: View {
    let hints: DeductionHints

    var body: some View {
        FlowLayout(spacing: 16, lineSpacing: 8) {
            HStack(spacing: 4) {
                Text("Uplatníte")
                    .font(Typography.body)
                    .foregroundStyle(Palette.text)
                Text(hints.mortgageAllowed)
                    .font(Typography.bodySemibold)
                    .foregroundStyle(Palette.text)
            }
            .monospacedDigit()
            if let over = hints.mortgageOverLimit {
                Text("\(over) nad limit se neuplatní")
                    .font(Typography.body)
                    .foregroundStyle(Palette.orangeText)
                    .monospacedDigit()
            }
            Text(hints.mortgageLimit + " · limit platí pro celou domácnost")
                .font(Typography.callout)
                .foregroundStyle(Palette.text3)
        }
        .insetPanel(horizontal: 14, vertical: 12)
        .accessibilityElement(children: .combine)
    }
}
