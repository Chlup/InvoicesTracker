import SwiftUI

/// Nastavení › Rok Y, the settings of the selected year: Profil, Činnost, Jednotný kurz Y, Pravidla výpočtu and Úpravy
/// příjmů (`YearTabModel`). Every choice is saved at once; the forms of the uniform rate and of an adjustment by their
/// buttons. Another year is chosen in the toolbar. Until the first load has ended the tab says "Načítám…" where the
/// cards will be, and a load again, of another year too, leaves the cards as they are until the new ones are read.
struct YearTab: View {
    let app: AppModel
    @State private var model: YearTabModel

    init(app: AppModel) {
        self.app = app
        _model = State(initialValue: YearTabModel(app: app))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(verbatim: "Platí jen pro rok \(model.year) · jiný rok vyberete v liště nahoře")
                .font(.callout)
                .foregroundStyle(.secondary)
            if let warning = model.rulesWarning {
                RulesWarning(text: warning)
            }
            if let line = model.saveFailure ?? model.errorText {
                SettingsFailureLine(text: line)
            }
            if let settings = model.settings {
                AdaptiveColumns(minimumColumnWidth: 440, spacing: 16) {
                    ProfileCard(model: model, showAdvances: { app.screen = .advances })
                    ActivityCard(model: model, settings: settings)
                    UniformRateCard(model: model)
                    RulesCard(model: model)
                }
                AdjustmentsCard(model: model, timeZone: app.dependencies.timeZone())
            } else if model.errorText == nil {
                // The first load has not ended. A load that failed says so above instead (`errorText`).
                SettingsLoadingView()
            }
        }
        .task(id: app.reloadKey) {
            await model.load()
        }
        .onChange(of: app.settingsAction, initial: true) {
            // Zadat ručně of the sheet of a uniform rate that was found, or of the reminder of Přehled.
            model.openRequestedForm()
        }
    }
}

// MARK: - Profil

/// The expenses and the VAT of the year, its health insurance company and the conversion of the income in other
/// currencies.
private struct ProfileCard: View {
    let model: YearTabModel

    /// Opens Zálohy a odpočty, where the flat-rate expenses are set.
    let showAdvances: () -> Void

    var body: some View {
        SettingsCard(title: "Profil", spacing: 6) {
            VStack(alignment: .leading, spacing: 0) {
                SettingsRow(label: "Výdaje") {
                    Button(model.expenseText, action: showAdvances)
                        .buttonStyle(.link)
                }
                SettingsRow(label: "DPH") {
                    Text("plátce · měsíčně")
                }
                SettingsRow(label: "Zdravotní pojišťovna") {
                    Text("VZP (111)")
                }
                SettingsRow(label: "Příjmy v cizí měně") {
                    // The conversion the year uses; the uniform rate cannot be chosen until the year has it.
                    Picker("Příjmy v cizí měně", selection: fxMethod) {
                        Text("kurz ČNB ke dni přijetí")
                            .tag(IncomeFXMethod.cnbDaily)
                        Text(verbatim: model.uniformOptionLabel)
                            .tag(IncomeFXMethod.uniform)
                            .selectionDisabled(!model.canChooseUniform)
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .fixedSize()
                }
            }
        }
    }

    private var fxMethod: Binding<IncomeFXMethod> {
        Binding(get: { model.shownFXMethod }, set: { method in Task { await model.setFXMethod(method) } })
    }
}

// MARK: - Činnost

/// The first and the last month of the activity, the months without the health minimum with the rule, and the hint
/// about the months of secondary activity that are not marked.
private struct ActivityCard: View {
    let model: YearTabModel
    let settings: YearSettings

    var body: some View {
        SettingsCard(title: "Činnost") {
            HStack(alignment: .center, spacing: 12) {
                monthPicker("od", selection: from)
                monthPicker("do", selection: to)
                Text(verbatim: model.activityText)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Divider()
            Text("Měsíce bez minima zdravotního pojištění")
                .fontWeight(.semibold)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 6), spacing: 6) {
                ForEach(1...12, id: \.self) { month in
                    MonthToggle(
                        month: month, isOn: settings.healthExemptMonths.contains(month),
                        isActive: YearTabModel.isActiveMonth(month, in: settings)
                    ) {
                        Task { await model.setHealthExempt(month: month, !settings.healthExemptMonths.contains(month)) }
                    }
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Měsíce bez minima zdravotního pojištění")
            Text(
                """
                Minimum se nepočítá za měsíc, kdy jste po celý měsíc byli i zaměstnaní s pojistným aspoň z minimální \
                mzdy, studovali, pobírali důchod, byli na rodičovské, měli průkaz ZTP/P a podobně (§ 3a zákona \
                592/1992). Vedlejší činnost pro sociální pojištění se nastavuje v Zálohách.
                """
            )
            .font(.callout)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            if let hint = model.secondaryHint {
                SettingsBox(kind: .hint) {
                    ViewThatFits(in: .horizontal) {
                        HStack(alignment: .center, spacing: 8) {
                            Text(verbatim: hint)
                                .fixedSize(horizontal: false, vertical: true)
                            markButton
                        }
                        VStack(alignment: .leading, spacing: 8) {
                            Text(verbatim: hint)
                                .fixedSize(horizontal: false, vertical: true)
                            markButton
                        }
                    }
                    .font(.callout)
                }
            }
        }
    }

    private var markButton: some View {
        Button("Označit i tady") {
            Task { await model.markSecondaryAsExempt() }
        }
        .settingsCardButton()
    }

    private func monthPicker(_ label: String, selection: Binding<Int>) -> some View {
        HStack(spacing: 6) {
            Text(verbatim: label)
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            Picker(label == "od" ? "Činnost od" : "Činnost do", selection: selection) {
                ForEach(1...12, id: \.self) { month in
                    Text(verbatim: CzechFormat.monthNames[month - 1])
                        .tag(month)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .fixedSize()
        }
    }

    /// Od: a later first month moves the last one with it.
    private var from: Binding<Int> {
        Binding(
            get: { settings.activityFrom },
            set: { month in Task { await model.setActivity(from: month, to: max(month, settings.activityTo)) } })
    }

    /// Do: an earlier last month moves the first one with it.
    private var to: Binding<Int> {
        Binding(
            get: { settings.activityTo },
            set: { month in Task { await model.setActivity(from: min(month, settings.activityFrom), to: month) } })
    }
}

/// A month of the toggles: dark when the health minimum does not apply in it, dimmed when the activity was not carried
/// on in it. VoiceOver reads its full name and whether it is marked.
private struct MonthToggle: View {
    let month: Int
    let isOn: Bool
    let isActive: Bool
    let toggle: () -> Void

    var body: some View {
        Button(action: toggle) {
            Text(verbatim: CzechFormat.monthShort[month - 1])
                .font(.callout)
                .fontWeight(.semibold)
                .frame(maxWidth: .infinity, minHeight: 28)
                .foregroundStyle(isOn ? Color(nsColor: .windowBackgroundColor) : (isActive ? .primary : .secondary))
                .background(
                    isOn ? Color.primary : Color.secondary.opacity(isActive ? 0.08 : 0.04),
                    in: RoundedRectangle(cornerRadius: 8)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(Color.secondary.opacity(isOn ? 0 : 0.25), lineWidth: 0.5)
                )
                .contentShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(CzechFormat.monthNames[month - 1])
        .accessibilityValue(isOn ? "bez minima" : "")
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}
