import SwiftUI

/// The gifts of the year: the field, which gifts count and what they allow, from the computation of the year once
/// there is one (`hints`), and the message of a text that was refused.
struct GiftsRow: View {
    let inputs: DeductionInputs
    let hints: DeductionHints?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 14) {
                Text("Dary za rok")
                    .frame(maxWidth: .infinity, alignment: .leading)
                AmountTextField(title: "Dary za rok", text: inputs.text(.gifts), width: 110, submit: inputs.submit)
            }
            if let hints {
                Text(hints.giftsNote + " · uplatníte " + hints.giftsAllowed)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let message = inputs.message(.gifts) {
                FieldMessage(text: message)
            }
        }
        .padding(.vertical, 10)
    }
}

/// The taxpayer credit of `year`, with its amount, and whether it is claimed.
struct TaxpayerCreditRow: View {
    let year: Int
    let isOn: Binding<Bool>

    var body: some View {
        HStack(spacing: 14) {
            Text("Sleva na poplatníka")
                .fontWeight(.semibold)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(CzechFormat.wholeKc(TaxRules.forYear(year).rules.taxpayerCredit))
                .monospacedDigit()
            Toggle("Sleva na poplatníka", isOn: isOn)
                .labelsHidden()
        }
        .padding(.vertical, 10)
    }
}
