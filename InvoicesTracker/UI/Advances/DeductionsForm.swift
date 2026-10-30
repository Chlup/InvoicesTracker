import SwiftUI

/// The cards of the deductions and the credits: the interest on the mortgage, the savings and insurance for old age,
/// the gifts with the taxpayer credit, and the cards of the children and of the spouse once the year is worked out. The
/// fields are texts in whole Kč that are saved by themselves; a field whose text is refused has the message under it
/// and is not saved. What each deduction allows is said under its fields, from the computation of the year
/// (`DeductionHints`). The fields and the lines under them are those Simulátor shows too; the cards, their titles and
/// the names of the fields are this screen's, and the cards of the family are those of the Simulátor too.
struct DeductionsForm: View {
    let model: AdvancesModel

    /// Opens the dialog of a child of the year, or of a new one for nil.
    let openChild: (FamilyChild?) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            mortgage
            retirement
            giftsAndCredits
            if let cards = model.familyCards {
                ChildrenCard(content: cards.children, open: openChild)
                SpouseCard(content: cards.spouse, editing: model, income: spouseIncome)
            }
        }
    }

    // MARK: Interest

    private var mortgage: some View {
        Card(label: "Úroky z hypotéky") {
            HStack(alignment: .center, spacing: 8) {
                Text("Odpočty · úroky z úvěru na bydlení")
                    .font(.system(size: 15, weight: .semibold))
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength: 8)
                Text("odhad do potvrzení banky")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color(.simulationText))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 1)
                    .background(Color.orange.opacity(0.2), in: Capsule())
            }
            MortgageInterestFields(inputs: inputs, cap: mortgageCap)
            if let hints = model.deductionHints {
                MortgageClaimSummary(hints: hints)
            }
        }
    }

    // MARK: Savings and insurance for old age

    private var retirement: some View {
        Card(spacing: 10, label: "Spoření a pojištění na stáří") {
            Text("Odpočty · spoření a pojištění na stáří")
                .font(.system(size: 15, weight: .semibold))
                .accessibilityAddTraits(.isHeader)
            if let hints = model.deductionHints {
                RetirementLimitBars(limits: hints.retirementLimits)
            }
            RetirementFieldGrid(fields: retirementFieldList, inputs: inputs)
            RetirementNote(year: model.year, allowed: model.deductionHints?.retirementAllowed)
        }
    }

    /// The fields of the retirement products: DIP and long-term care insurance only from the year they exist in.
    private var retirementFieldList: [(field: DeductionField, title: String)] {
        var fields: [(field: DeductionField, title: String)] = [
            (.lifeInsurance, "Soukromé životní pojištění (Kč za rok)"),
            (.pensionSavings, "Penzijní spoření – částka k odpočtu z potvrzení"),
        ]
        if model.showsDIPAndLongTermCare {
            fields.append((.dip, "Dlouhodobý investiční produkt (DIP)"))
            fields.append((.longTermCare, "Pojištění dlouhodobé péče"))
        }
        return fields
    }

    // MARK: Gifts and credits

    private var giftsAndCredits: some View {
        Card(spacing: 0, label: "Dary a slevy") {
            Text("Dary a slevy na dani")
                .font(.system(size: 15, weight: .semibold))
                .accessibilityAddTraits(.isHeader)
                .padding(.bottom, 6)
            Divider()
            GiftsRow(inputs: inputs, hints: model.deductionHints)
            Divider()
            TaxpayerCreditRow(year: model.year, isOn: taxpayerCredit)
        }
    }

    // MARK: Bindings

    /// The texts of the fields, their messages, and Return, which saves what was typed at once.
    private var inputs: DeductionInputs {
        DeductionInputs(
            text: { field in
                Binding(
                    get: { model.deductionTexts[field] ?? "" },
                    set: { model.setDeductionText(field, $0) })
            },
            message: { model.deductionError($0) },
            submit: {
                Task { await model.saveNow() }
            })
    }

    /// The field of the spouse's own income: its text and message, and Return, which saves what was typed at once.
    private var spouseIncome: SpouseIncomeInput {
        SpouseIncomeInput(
            text: Binding(get: { model.spouseIncomeText }, set: { model.setSpouseIncomeText($0) }),
            message: model.spouseIncomeError,
            submit: {
                Task { await model.saveNow() }
            })
    }

    private var mortgageCap: Binding<MortgageCap> {
        Binding(
            get: { model.settings?.deductions.mortgageCap ?? .after2021 },
            set: { model.setMortgageCap($0) })
    }

    private var taxpayerCredit: Binding<Bool> {
        Binding(
            get: { model.settings?.taxpayerCredit ?? false },
            set: { model.setTaxpayerCredit($0) })
    }
}
