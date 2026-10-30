import SwiftUI

// MARK: - Rok a příjem

/// "Rok a příjem": the year of the simulation with the rules it is computed with, the income of the year in a large
/// field with what it is a month, and the assumptions — the flat-rate expenses, the activity (a secondary one with the
/// box that asks for the exemption from the health minimum) and its months — with what the expenses come to under
/// them. A text that was refused has its message under its field.
struct SimulatorYearAndIncomeCard: View {
    let model: SimulatorModel

    var body: some View {
        Card(spacing: 14, label: "Rok a příjem") {
            year
            Divider()
            income
            Divider()
            assumptions
        }
    }

    private var year: some View {
        VStack(alignment: .leading, spacing: 8) {
            inputTitle("Rok")
            Picker("Rok", selection: yearChoice) {
                ForEach(SimulatorModel.years, id: \.self) { year in
                    Text(verbatim: String(year))
                        .tag(year)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .fixedSize()
            Text(verbatim: SimulatorBuilder.rulesLine(year: model.year))
                .simulatorNote()
        }
    }

    /// The field stays in its place whatever comes beside it or under it: a field that moved to another arrangement
    /// in the pause of the typing would lose the focus.
    private var income: some View {
        VStack(alignment: .leading, spacing: 8) {
            inputTitle("Příjem za rok bez DPH")
            HStack(alignment: .firstTextBaseline, spacing: 14) {
                incomeField
                perMonth
            }
            if let message = model.incomeError {
                FieldMessage(text: message)
            }
            Text("V Kč. Bez zaměstnání a jiných zdanitelných příjmů.")
                .simulatorNote()
        }
    }

    private var incomeField: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            AmountTextField(
                title: "Příjem za rok bez DPH", text: incomeText, width: 210,
                submit: {
                    model.readTypedTexts()
                }
            )
            .font(.system(size: 20, weight: .semibold))
            // The unit keeps its width, which the row would otherwise share out with the amount a month.
            Text("Kč")
                .font(.system(size: 15))
                .fixedSize()
        }
    }

    /// "≈ 208 333 Kč měsíčně", while there is an income. It breaks where the row is too narrow for it.
    @ViewBuilder
    private var perMonth: some View {
        if let perMonth = model.page?.incomePerMonth {
            Text(verbatim: perMonth)
                .foregroundStyle(.secondary)
                .monospacedDigit()
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// The three choices in a row where they fit, else the rate over the other two. The message of the months comes
    /// under them all, so that it never changes the arrangement: the field would lose the focus. The line under the
    /// box of the health minimum, which a secondary activity shows, is wider than the menu above it, but it breaks
    /// within `healthNoteWidth`, so it asks no more room than a line of that width. Choosing that activity takes the
    /// choices to the second arrangement only where the card has no room for the row with it, and only the choice of
    /// the activity does, never the typing in the months.
    private var assumptions: some View {
        VStack(alignment: .leading, spacing: 10) {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: 20) {
                    expenseRate
                    activity
                    months
                }
                VStack(alignment: .leading, spacing: 12) {
                    expenseRate
                    HStack(alignment: .top, spacing: 20) {
                        activity
                        months
                    }
                }
            }
            if let message = model.monthsError {
                FieldMessage(text: message)
            }
            if let note = model.page?.expenseNote {
                Text(verbatim: note)
                    .simulatorNote()
            }
        }
    }

    private var expenseRate: some View {
        VStack(alignment: .leading, spacing: 4) {
            FieldTitle(text: "Výdaje paušálem")
            Picker("Výdaje paušálem", selection: rateChoice) {
                ForEach(ExpenseRateChoice.all, id: \.percent) { rate in
                    Text(verbatim: rate.label)
                        .tag(rate.percent)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .fixedSize()
        }
    }

    private var activity: some View {
        VStack(alignment: .leading, spacing: 4) {
            FieldTitle(text: "Činnost")
            Picker("Činnost", selection: activityChoice) {
                Text("Hlavní")
                    .tag(SimulatorActivity.main)
                Text("Vedlejší")
                    .tag(SimulatorActivity.secondary)
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .fixedSize()
            if model.activity == .secondary {
                healthMinimumSwitch
            }
        }
    }

    /// The most the line under the box of the health minimum is wide, in points: the width the line had when it named
    /// only employment and studies, which was 364 points in the font of a note. The line breaks within it, and it is
    /// the width the column of the activity asks for, so that the longer line does not widen the column and take the
    /// three choices out of their row where the row had room for the shorter one.
    private static let healthNoteWidth: CGFloat = 364

    /// The box that asks for the exemption from the health minimum, with the line that says when it applies, under the
    /// menu of the activity. Only a secondary activity has it: the main one pays the minimum. The line is at most
    /// `healthNoteWidth` wide, and narrower where the column has less room, and it breaks within that width.
    private var healthMinimumSwitch: some View {
        VStack(alignment: .leading, spacing: 2) {
            Toggle("Bez minima zdravotního pojištění", isOn: healthMinimumChoice)
                .toggleStyle(.checkbox)
            Text(
                """
                Po celé měsíce činnosti jste zároveň zaměstnaní s pojistným aspoň z minimální mzdy, studujete, \
                pobíráte důchod, jste na rodičovské, máte průkaz ZTP/P a podobně.
                """
            )
            .simulatorNote()
            .frame(maxWidth: Self.healthNoteWidth, alignment: .leading)
            .padding(.leading, 20)
        }
        .padding(.top, 4)
    }

    private var months: some View {
        TitledAmountField(
            title: "Měsíců činnosti", text: monthsText, width: 64, message: nil,
            submit: {
                model.readTypedTexts()
            })
    }

    /// The title of the year and of the income, which their controls carry for VoiceOver.
    private func inputTitle(_ title: String) -> some View {
        Text(verbatim: title)
            .font(.system(size: 15, weight: .semibold))
            .accessibilityHidden(true)
    }

    private var incomeText: Binding<String> {
        Binding(get: { model.incomeText }, set: { model.setIncomeText($0) })
    }

    private var monthsText: Binding<String> {
        Binding(get: { model.monthsText }, set: { model.setMonthsText($0) })
    }

    /// The year at once; the settings of the new year are read after it.
    private var yearChoice: Binding<Int> {
        Binding(get: { model.year }, set: { year in Task { await model.selectYear(year) } })
    }

    private var rateChoice: Binding<Int> {
        Binding(get: { model.expensePercent }, set: { model.setExpensePercent($0) })
    }

    private var activityChoice: Binding<SimulatorActivity> {
        Binding(get: { model.activity }, set: { model.setActivity($0) })
    }

    private var healthMinimumChoice: Binding<Bool> {
        Binding(get: { model.healthMinimumExempt }, set: { model.setHealthMinimumExempt($0) })
    }
}

// MARK: - Odpočty a slevy

/// The heading over the cards of the deductions and of the family, with the button that copies the deductions and the
/// family of the year into them as Zálohy a odpočty shows them, once the year has been read. The fields and the lines
/// under them in the cards are those of Zálohy a odpočty.
struct SimulatorDeductionsHeading: View {
    let model: SimulatorModel

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            SimulatorCardTitle(text: "Odpočty a slevy")
            Spacer(minLength: 8)
            if model.canCopyDeductionsAndFamily {
                Button("Převzít ze Záloh a odpočtů \(String(model.year))") {
                    Task { await model.copyDeductionsAndFamily() }
                }
            }
        }
        .padding(.horizontal, 4)
        .padding(.top, 4)
    }
}

/// "Úroky z úvěru na bydlení": the interest paid, its months and the limit by when the housing was acquired, and what
/// of it is claimed, from the computation.
struct SimulatorMortgageCard: View {
    let model: SimulatorModel

    var body: some View {
        Card(label: "Úroky z úvěru na bydlení") {
            SimulatorCardTitle(text: "Úroky z úvěru na bydlení")
            MortgageInterestFields(inputs: model.deductionInputs, cap: capChoice)
            if let hints = model.page?.hints {
                MortgageClaimSummary(hints: hints)
            }
        }
    }

    private var capChoice: Binding<MortgageCap> {
        Binding(get: { model.mortgageCap }, set: { model.setMortgageCap($0) })
    }
}

/// "Spoření a pojištění na stáří": how much of the limit or the limits the products use, their fields — DIP and the
/// long-term care insurance only in the years whose rules have them — and what they allow together.
struct SimulatorRetirementCard: View {
    let model: SimulatorModel

    var body: some View {
        Card(spacing: 10, label: "Spoření a pojištění na stáří") {
            SimulatorCardTitle(text: "Spoření a pojištění na stáří")
            if let hints = model.page?.hints {
                RetirementLimitBars(limits: hints.retirementLimits)
            }
            RetirementFieldGrid(fields: fieldList, inputs: model.deductionInputs)
            RetirementNote(year: model.year, allowed: model.page?.hints.retirementAllowed)
        }
    }

    private var fieldList: [(field: DeductionField, title: String)] {
        var fields: [(field: DeductionField, title: String)] = [
            (.lifeInsurance, "Soukromé životní pojištění (Kč za rok)"),
            (.pensionSavings, "Penzijní spoření – částka k odpočtu"),
        ]
        if TaxRules.forYear(model.year).rules.hasDIPAndLongTermCare {
            fields.append((.dip, "Dlouhodobý investiční produkt (DIP)"))
            fields.append((.longTermCare, "Pojištění dlouhodobé péče"))
        }
        return fields
    }
}

/// "Dary a slevy na dani": the gifts of the year with the rule they follow and what they allow, and the taxpayer credit
/// of the year to claim or not.
struct SimulatorGiftsCard: View {
    let model: SimulatorModel

    var body: some View {
        Card(spacing: 0, label: "Dary a slevy na dani") {
            SimulatorCardTitle(text: "Dary a slevy na dani")
                .padding(.bottom, 6)
            Divider()
            GiftsRow(inputs: model.deductionInputs, hints: model.page?.hints)
            Divider()
            TaxpayerCreditRow(year: model.year, isOn: creditChoice)
        }
    }

    private var creditChoice: Binding<Bool> {
        Binding(get: { model.taxpayerCredit }, set: { model.setTaxpayerCredit($0) })
    }
}

// MARK: - The family

/// The cards of the children and of the spouse of the simulation, after "Dary a slevy na dani": those of Zálohy a
/// odpočty, without what the tax return asks for. A row of a child and Přidat dítě open the dialog of a child of the
/// simulation (`openChild`); a choice of the spouse changes the simulation at once, and the spouse's own income is a
/// typed field, read as the other amounts of the Simulátor are. Nothing of it is stored.
struct SimulatorFamilyCards: View {
    let model: SimulatorModel

    /// Opens the dialog of a child of the simulation, or of a new one for nil.
    let openChild: (FamilyChild?) -> Void

    var body: some View {
        if let cards = model.page?.family {
            VStack(spacing: 16) {
                ChildrenCard(content: cards.children, open: openChild)
                SpouseCard(content: cards.spouse, editing: model, income: spouseIncome)
            }
        }
    }

    /// The field of the spouse's own income: its text and its message, and Return, which reads what was typed.
    private var spouseIncome: SpouseIncomeInput {
        SpouseIncomeInput(
            text: Binding(get: { model.spouseIncomeText }, set: { model.setSpouseIncomeText($0) }),
            message: model.spouseIncomeError,
            submit: {
                model.readTypedTexts()
            })
    }
}

// MARK: - Parts

/// The title of a card of the Simulátor, a heading for VoiceOver.
struct SimulatorCardTitle: View {
    let text: String

    var body: some View {
        Text(verbatim: text)
            .font(.system(size: 15, weight: .semibold))
            .accessibilityAddTraits(.isHeader)
    }
}

/// The small title over a menu, which the menu carries for VoiceOver.
private struct FieldTitle: View {
    let text: String

    var body: some View {
        Text(verbatim: text)
            .font(.callout)
            .foregroundStyle(.secondary)
            .accessibilityHidden(true)
    }
}

extension SimulatorModel {
    /// The fields of the deductions of the Simulátor: their texts as typed, the messages of those that were refused,
    /// and Return, which reads what was typed.
    fileprivate var deductionInputs: DeductionInputs {
        DeductionInputs(
            text: { field in
                Binding(get: { self.deductionTexts[field] ?? "" }, set: { self.setDeductionText(field, $0) })
            },
            message: { self.deductionErrors[$0] },
            submit: {
                self.readTypedTexts()
            })
    }
}

extension View {
    /// A line of the Simulátor in small secondary type that breaks where it has to.
    func simulatorNote() -> some View {
        font(.callout)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}
