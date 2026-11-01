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
        VStack(alignment: .leading, spacing: DesignMetrics.cardSpacing) {
            Text(verbatim: "Platí jen pro rok \(model.year) · jiný rok vyberete v liště nahoře")
                .font(Typography.callout)
                .foregroundStyle(Palette.text3)
            if let warning = model.rulesWarning {
                RulesWarning(text: warning)
            }
            if let line = model.saveFailure ?? model.errorText {
                SettingsFailureLine(text: line)
            }
            if let settings = model.settings {
                AdaptiveColumns(minimumColumnWidth: 440, spacing: DesignMetrics.cardSpacing) {
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
        Card(title: "Profil", spacing: 6) {
            VStack(alignment: .leading, spacing: 0) {
                SettingsRow(label: "Výdaje") {
                    Button(model.expenseText, action: showAdvances)
                        .buttonStyle(TextLinkButtonStyle(.accent))
                        .accessibilityAddTraits(.isLink)
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
        Card(title: "Činnost") {
            HStack(alignment: .center, spacing: 12) {
                monthPicker("od", selection: from)
                monthPicker("do", selection: to)
                Text(verbatim: model.activityText)
                    .font(Typography.callout)
                    .foregroundStyle(Palette.text3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Hairline()
            VStack(alignment: .leading, spacing: 6) {
                Text("Měsíce bez minima zdravotního pojištění")
                    .font(Typography.bodySemibold)
                    .foregroundStyle(Palette.text)
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 6), spacing: 6) {
                    ForEach(1...12, id: \.self) { month in
                        MonthToggle(
                            month: month, isOn: settings.healthExemptMonths.contains(month),
                            isActive: YearTabModel.isActiveMonth(month, in: settings)
                        ) {
                            Task {
                                await model.setHealthExempt(month: month, !settings.healthExemptMonths.contains(month))
                            }
                        }
                    }
                }
                .accessibilityElement(children: .contain)
                .accessibilityLabel("Měsíce bez minima zdravotního pojištění")
                Text(
                    """
                    Minimum se nepočítá za měsíc, kdy jste po celý měsíc byli i zaměstnaní s pojistným aspoň z \
                    minimální mzdy, studovali, pobírali důchod, byli na rodičovské, měli průkaz ZTP/P a podobně (§ 3a \
                    zákona 592/1992). Vedlejší činnost pro sociální pojištění se nastavuje v Zálohách.
                    """
                )
                .font(Typography.callout)
                .foregroundStyle(Palette.text3)
                .fixedSize(horizontal: false, vertical: true)
                if let hint = model.secondaryHint {
                    Note(.info, icon: .none, text: hint) {
                        markButton
                    }
                }
            }
        }
    }

    /// Označit i tady: a capsule in the colour of a card with its words in the blue of a link, as a button in a note
    /// is.
    private var markButton: some View {
        Button("Označit i tady") {
            Task { await model.markSecondaryAsExempt() }
        }
        .buttonStyle(CapsuleButtonStyle(.onWindowAccent, size: .small))
    }

    private func monthPicker(_ label: String, selection: Binding<Int>) -> some View {
        HStack(spacing: 6) {
            Text(verbatim: label)
                .font(Typography.body)
                .foregroundStyle(Palette.text2)
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

/// What a month of the toggles of the months without the health minimum shows: marked, or not marked while the activity
/// was carried on in it, or not marked and outside the activity.
nonisolated enum MonthToggleTone: Sendable, Hashable {
    /// The health minimum does not apply in the month.
    case selected

    /// The month has the minimum, and the activity was carried on in it.
    case available

    /// The month has the minimum, but the activity was not carried on in it.
    case outsideActivity

    /// The tone of a month that is marked as without the minimum (`isOn`) or not, and that the activity was carried on
    /// in (`isActive`) or not. A marked month is selected whether the activity was carried on in it or not.
    init(isOn: Bool, isActive: Bool) {
        if isOn {
            self = .selected
        } else {
            self = isActive ? .available : .outsideActivity
        }
    }
}

/// The colours of the tones of a month toggle, from the palette.
extension MonthToggleTone {
    /// The colour of the toggle: the accent, as every choice of the design is, while the month is selected; the colour
    /// of a card while it has the minimum, and the inset background where the activity was not carried on.
    var background: Color {
        switch self {
        case .selected: Palette.accent
        case .available: Palette.bgCard
        case .outsideActivity: Palette.bgInset
        }
    }

    /// Whether the toggle stands off the page, with the elevation of a control, as a button on the window does: every
    /// month that is not selected, inside the activity and outside it, as the prototype rings both of those tones.
    var isRaised: Bool {
        self != .selected
    }

    /// The colour of the name of the month: on an accent while it is selected, the colour of text, and the faintest
    /// text where the activity was not carried on.
    var foreground: Color {
        switch self {
        case .selected: Palette.onAccent
        case .available: Palette.text
        case .outsideActivity: Palette.text4
        }
    }
}

/// A month of the toggles: a capsule 28 points tall, in the accent when the health minimum does not apply in it, and
/// otherwise raised with the ring of a control, dimmed when the activity was not carried on in it (`MonthToggleTone`).
/// VoiceOver reads its full name and whether it is marked.
struct MonthToggle: View {
    let month: Int
    let isOn: Bool
    let isActive: Bool
    let toggle: () -> Void

    /// What the toggle shows, from whether the month is marked and whether the activity was carried on in it.
    private var tone: MonthToggleTone {
        MonthToggleTone(isOn: isOn, isActive: isActive)
    }

    var body: some View {
        Button(action: toggle) {
            Text(verbatim: CzechFormat.monthShort[month - 1])
                .font(Typography.calloutSemibold)
                .foregroundStyle(tone.foreground)
                .frame(maxWidth: .infinity)
                .frame(height: DesignMetrics.smallControlHeight)
                .background { capsule }
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(CzechFormat.monthNames[month - 1])
        .accessibilityValue(isOn ? "bez minima" : "")
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }

    /// The capsule behind the name, raised off the page where the tone calls for it.
    @ViewBuilder
    private var capsule: some View {
        if tone.isRaised {
            Capsule().surface(tone.background, elevation: .control)
        } else {
            Capsule().fill(tone.background)
        }
    }
}
