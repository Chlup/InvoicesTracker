import SwiftUI

/// The sheet "Nové dítě" / "Upravit dítě", with "v simulaci" in the Simulátor: the name and the date of birth, and what
/// the year says about the child — its months in the household or "V roce Y s vámi nežije", who claims it, its order in
/// the household, ZTP/P and, for a child from 18 to 25 in the year, the studies, each with their months — then what it
/// comes to in the year as the fields change, and what is wrong with them after Uložit dítě. Uložit dítě saves it and
/// Zrušit throws the edit away. Odebrat dítě removes a child: in Zálohy a odpočty after the question that the sheet
/// asks in a red box in place of its buttons, in the Simulátor at once. The words and the figures are the model's
/// (`ChildDialogModel`); the sheet only shows them.
struct ChildDialog: View {
    @Bindable var model: ChildDialogModel

    /// Closes the sheet: Zrušit, or the child was saved or removed.
    let close: () -> Void

    @FocusState private var nameFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            SheetHeader(title: model.title, subtitle: model.subtitle)
            nameAndBirth
            rows
            if let result = model.liveResult {
                Text(verbatim: result.text)
                    .fontWeight(.semibold)
                    .monospacedDigit()
                    .foregroundStyle(result.counts ? Color.primary : Color(.simulationText))
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.quaternary.opacity(0.6), in: RoundedRectangle(cornerRadius: 10))
            }
            if let error = model.error {
                Text(verbatim: error)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let failure = model.failure {
                Text(verbatim: failure)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if model.confirmsRemoval {
                ConfirmationBox(
                    title: ChildDialogModel.removalTitle, message: ChildDialogModel.removalMessage(year: model.year),
                    cancelTitle: "Zrušit", cancel: { model.cancelRemoval() },
                    confirmTitle: "Odebrat dítě", confirm: remove)
            } else {
                footer
            }
        }
        .padding(.top, 22)
        .padding(.horizontal, 24)
        .padding(.bottom, 20)
        .frame(width: 620)
        .defaultFocus($nameFocused, model.isNew)
    }

    // MARK: The child

    private var nameAndBirth: some View {
        HStack(alignment: .top, spacing: 16) {
            LabeledField("Jméno") {
                FormTextField("Jméno", text: $model.name, prompt: "např. Anna")
                    .focused($nameFocused)
            }
            LabeledField("Datum narození") {
                FormTextField(
                    "Datum narození", text: $model.birthDateText, prompt: ChildDialogModel.birthDatePrompt)
            }
        }
    }

    // MARK: The year

    private var rows: some View {
        VStack(alignment: .leading, spacing: 0) {
            Divider()
            household
            Divider()
            claimant
            Divider()
            order
            Divider()
            ztpp
            Divider()
            if model.showsStudies {
                studies
                Divider()
            }
        }
    }

    /// The months in the household, which are not asked for while "V roce Y s vámi nežije" is ticked.
    private var household: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                Text(verbatim: model.householdTitle)
                    .frame(maxWidth: .infinity, alignment: .leading)
                MonthChoice(label: "od", title: model.householdTitle + " od", month: $model.householdFrom)
                MonthChoice(label: "do", title: model.householdTitle + " do", month: $model.householdTo)
            }
            .disabled(model.livesApart)
            Toggle(model.livesApartTitle, isOn: $model.livesApart)
                .toggleStyle(.checkbox)
        }
        .padding(.vertical, 10)
    }

    private var claimant: some View {
        HStack(spacing: 12) {
            Text("Zvýhodnění uplatňuje")
                .frame(maxWidth: .infinity, alignment: .leading)
            Picker("Zvýhodnění uplatňuje", selection: $model.claimant) {
                Text("Já")
                    .tag(Claimant.me)
                Text("Druhý rodič")
                    .tag(Claimant.otherParent)
            }
            .labelsHidden()
            .pickerStyle(.segmented)
            .fixedSize()
        }
        .padding(.vertical, 10)
    }

    private var order: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Pořadí v domácnosti")
                Text(verbatim: ChildDialogModel.orderNote)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Picker("Pořadí v domácnosti", selection: $model.order) {
                ForEach(1...model.orderCount, id: \.self) { place in
                    Text(verbatim: "\(place). dítě")
                        .tag(place)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .fixedSize()
        }
        .padding(.vertical, 10)
    }

    private var ztpp: some View {
        HStack(spacing: 12) {
            Toggle("Průkaz ZTP/P – zvýhodnění dvojnásobné", isOn: $model.hasZTPP)
                .toggleStyle(.checkbox)
                .frame(maxWidth: .infinity, alignment: .leading)
            if model.hasZTPP {
                MonthChoice(label: "od", title: "Průkaz ZTP/P od", month: $model.ztppFrom)
                MonthChoice(label: "do", title: "Průkaz ZTP/P do", month: $model.ztppTo)
            }
        }
        .padding(.vertical, 10)
    }

    private var studies: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 12) {
                Toggle("Po 18. narozeninách studuje", isOn: $model.studies)
                    .toggleStyle(.checkbox)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if model.studies {
                    MonthChoice(label: "od", title: "Studium od", month: $model.studiesFrom)
                    MonthChoice(label: "do", title: "Studium do", month: $model.studiesTo)
                }
            }
            Text(verbatim: ChildDialogModel.studiesNote)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 10)
    }

    // MARK: The buttons

    private var footer: some View {
        HStack(spacing: 8) {
            if !model.isNew {
                Button("Odebrat dítě", role: .destructive) {
                    if model.asksBeforeRemoving {
                        model.askToRemove()
                    } else {
                        remove()
                    }
                }
                .buttonStyle(.bordered)
                .disabled(model.isWorking)
            }
            Spacer()
            Button("Zrušit", action: close)
                .buttonStyle(.bordered)
                .keyboardShortcut(.cancelAction)
            Button("Uložit dítě", action: save)
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(model.isWorking)
        }
        .buttonBorderShape(.capsule)
        .controlSize(.large)
    }

    private func save() {
        Task {
            // A save that does not happen says why in the sheet (`error` of the model).
            if await model.save() {
                close()
            }
        }
    }

    private func remove() {
        Task {
            if await model.remove() {
                close()
            }
        }
    }
}
