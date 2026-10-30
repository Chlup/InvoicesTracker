import SwiftUI

// MARK: - Jednotný kurz

/// The uniform rate of the year, in one of three states, and a page of the Finanční zpravodaj that could not be read,
/// with its link:
/// - official (shipped with the app, or fetched and confirmed): the rates of dollars and euros, where they are from and
///   Upravit;
/// - entered by hand: the same with "zadáno ručně", Upravit and a red Odstranit…, and a grey note on what the rates
///   stand in for, in place of which Odstranit… asks in a red box what removing them leads to;
/// - none: what the app does about the rate, with Zadat ručně.
/// Upravit and Zadat ručně open the form to enter the rates by hand in place of all that.
struct UniformRateCard: View {
    @Bindable var model: YearTabModel

    var body: some View {
        Card(title: "Jednotný kurz \(model.year)", spacing: 10) {
            if let page = model.unreadablePage {
                SettingsBox(kind: .warning) {
                    Text(
                        verbatim: "Finanční zpravodaj s jednotným kurzem za rok \(model.year) se nepodařilo přečíst."
                            + " Kurz v něm najdete a zadáte ho ručně.")
                    Link("Otevřít Finanční zpravodaj", destination: page)
                        .font(.callout)
                }
            }
            if model.editsRates {
                form
            } else if model.shownRates.isEmpty {
                Text(verbatim: model.missingRateText)
                    .fixedSize(horizontal: false, vertical: true)
                Button("Zadat ručně", action: model.startEditingRates)
                    .settingsCardButton()
            } else {
                rates
                sourceLine
                if model.asksToRemove {
                    ConfirmationBox(
                        title: YearTabModel.removalTitle, message: model.removalQuestion, cancelTitle: "Zrušit",
                        cancel: { model.cancelRemovingRates() }, confirmTitle: YearTabModel.removalConfirmTitle,
                        confirm: remove
                    )
                    .controlSize(.small)
                } else if let note = model.manualNote {
                    SettingsBox(kind: .note) {
                        Text(verbatim: note)
                            .font(.callout)
                    }
                }
            }
        }
    }

    /// The rates of dollars and euros, a row each.
    private var rates: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(model.shownRates, id: \.currency) { rate in
                Divider()
                HStack {
                    Text(verbatim: YearTabModel.rateUnit(rate))
                    Spacer(minLength: 8)
                    Text(verbatim: YearTabModel.rateText(rate))
                        .fontWeight(.semibold)
                }
                .monospacedDigit()
                .padding(.vertical, 8)
                .accessibilityElement(children: .combine)
            }
        }
    }

    /// Where the rates are from, with Upravit and, for rates entered by hand, the red Odstranit….
    private var sourceLine: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(verbatim: model.rateSource)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 8)
            HStack(alignment: .firstTextBaseline, spacing: 14) {
                // The year is read as it is written, not as a number with its thousands apart.
                Button("Upravit", action: model.startEditingRates)
                    .buttonStyle(.link)
                    .font(.callout)
                    .accessibilityLabel(Text(verbatim: "Upravit jednotný kurz \(model.year)"))
                if model.isManual {
                    Button("Odstranit…", action: model.askToRemoveRates)
                        .buttonStyle(.link)
                        .font(.callout)
                        .foregroundStyle(.red)
                        .accessibilityLabel(Text(verbatim: "Odstranit ručně zadaný jednotný kurz \(model.year)"))
                }
            }
            .fixedSize()
        }
    }

    /// 1 USD, 1 EUR and the instruction of the GFŘ, with Zrušit and Uložit kurz, which Return in a field presses too.
    /// Over the table that ships with the app, the form says what saving it does.
    private var form: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let hint = model.formHint {
                Text(verbatim: hint)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            AdaptiveColumns(minimumColumnWidth: 120, spacing: 10) {
                SettingsTextField(label: "1 USD v Kč", text: $model.usdText, prompt: "21,84", trailing: true)
                SettingsTextField(label: "1 EUR v Kč", text: $model.eurText, prompt: "24,66", trailing: true)
                SettingsTextField(label: "Pokyn GFŘ", text: $model.instructionText, prompt: "GFŘ-D-…")
            }
            .onSubmit(save)
            if let error = model.rateError {
                SettingsFailureLine(text: error)
            }
            HStack(spacing: 8) {
                Button("Zrušit", action: model.cancelEditingRates)
                    .buttonStyle(.bordered)
                Button("Uložit kurz", action: save)
                    .buttonStyle(.borderedProminent)
            }
            .buttonBorderShape(.capsule)
            .controlSize(.small)
        }
    }

    private func save() {
        Task {
            await model.saveManualUniformRates(
                usd: model.usdText, eur: model.eurText, instruction: model.instructionText)
        }
    }

    private func remove() {
        Task {
            await model.removeManualUniformRates()
        }
    }
}

// MARK: - Pravidla výpočtu

/// The values of the rules the year is computed with, their version, and the conventions of the app that the law
/// leaves open, in the words of Výpočet.
struct RulesCard: View {
    let model: YearTabModel

    var body: some View {
        Card(title: "Pravidla výpočtu", accessory: model.rulesVersion, spacing: 6) {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(model.ruleRows, id: \.label) { row in
                    Divider()
                    HStack(alignment: .firstTextBaseline, spacing: 12) {
                        Text(verbatim: row.label)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 8)
                        Text(verbatim: row.value)
                    }
                    .monospacedDigit()
                    .padding(.vertical, 8)
                    .accessibilityElement(children: .combine)
                }
                Divider()
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(model.conventions, id: \.self) { convention in
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Text(verbatim: "•")
                                .accessibilityHidden(true)
                            Text(verbatim: convention)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    Text(verbatim: YearTabModel.rulesNote)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 4)
                }
                .font(.callout)
                .foregroundStyle(.secondary)
                .padding(.top, 10)
            }
        }
    }
}

// MARK: - Úpravy příjmů

/// The income adjustments of the year with their sum and Smazat, and the form of a new one: its date in the year, the
/// amount in crowns, positive or negative, and what it is.
struct AdjustmentsCard: View {
    @Bindable var model: YearTabModel

    /// The time zone of the Mac, in which the date picker counts its days.
    let timeZone: TimeZone

    var body: some View {
        Card(
            title: "Úpravy příjmů",
            subtitle:
                "Příjmy mimo faktury – dobropis, vrácená platba, platba v Kč mimo fakturu. Počítají se do příjmů roku ke"
                + " svému datu.",
            accessory: model.adjustmentsTotal, accessoryIsAmount: true, spacing: 6
        ) {
            VStack(alignment: .leading, spacing: 0) {
                if model.adjustments.isEmpty {
                    Divider()
                    Text("Žádné úpravy.")
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 10)
                }
                ForEach(model.adjustments) { adjustment in
                    Divider()
                    row(adjustment)
                }
                Divider()
                form
                    .onSubmit(add)
                    .padding(.top, 12)
                if let error = model.adjustmentError {
                    SettingsFailureLine(text: error)
                        .padding(.top, 8)
                }
            }
        }
    }

    private func row(_ adjustment: IncomeAdjustment) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(verbatim: CzechFormat.date(adjustment.date))
                .frame(width: 90, alignment: .leading)
            Text(verbatim: adjustment.description.isEmpty ? "—" : adjustment.description)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
            Text(verbatim: YearTabModel.adjustmentAmountText(adjustment.amountHalere))
                .fontWeight(.semibold)
                .foregroundStyle(adjustment.amountHalere < 0 ? Color.red : Color(.bannerText))
            Button("Smazat") {
                Task { await model.deleteAdjustment(id: adjustment.id) }
            }
            .buttonStyle(.link)
            .font(.callout)
            .foregroundStyle(.red)
            .accessibilityLabel("Smazat úpravu")
        }
        .monospacedDigit()
        .padding(.vertical, 9)
    }

    /// Datum, Částka v Kč (+ / −), Popis and Přidat, in a row as long as the card is wide enough. Return in a field
    /// presses Přidat.
    private var form: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .bottom, spacing: 10) {
                dateField
                    .frame(width: 150)
                amountField
                    .frame(width: 150)
                descriptionField
                addButton
            }
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .bottom, spacing: 10) {
                    dateField
                    amountField
                }
                descriptionField
                addButton
            }
        }
    }

    private var dateField: some View {
        LabeledField("Datum") {
            DatePicker("Datum", selection: dateSelection, in: daysOfTheYear, displayedComponents: .date)
                .datePickerStyle(.field)
                .labelsHidden()
                // Another year is another date picker. One whose days moved to the new year together with its day
                // would take the day into the days of the old year first, and show the first or the last day of the
                // new one.
                .id(model.year)
                .environment(\.timeZone, timeZone)
                .environment(\.calendar, calendar)
                .environment(\.locale, Locale(identifier: "cs_CZ"))
        }
    }

    private var amountField: some View {
        SettingsTextField(
            label: "Částka v Kč (+ / −)", text: $model.adjustmentAmount, prompt: "\u{2212}4\u{00A0}500", trailing: true)
    }

    private var descriptionField: some View {
        SettingsTextField(
            label: "Popis", text: $model.adjustmentDescription, prompt: "např. dobropis k faktuře 20260801")
    }

    private var addButton: some View {
        Button("Přidat", action: add)
            .buttonStyle(.borderedProminent)
            .buttonBorderShape(.capsule)
    }

    private func add() {
        Task {
            await model.addAdjustment(
                date: model.adjustmentDate, amount: model.adjustmentAmount, description: model.adjustmentDescription)
        }
    }

    // MARK: The date

    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        return calendar
    }

    /// The day as an instant the date picker takes: noon of it in the time zone of the Mac, whatever the clock changes
    /// of the day.
    private var dateSelection: Binding<Date> {
        Binding(
            get: { noon(of: model.adjustmentDate) },
            set: { model.adjustmentDate = CivilDate.today(now: $0, timeZone: timeZone) }
        )
    }

    /// The days of the year shown.
    private var daysOfTheYear: ClosedRange<Date> {
        guard let first = CivilDate(year: model.year, month: 1, day: 1),
            let last = CivilDate(year: model.year, month: 12, day: 31)
        else {
            return Date.distantPast...Date.distantFuture
        }
        return noon(of: first)...noon(of: last)
    }

    private func noon(of day: CivilDate) -> Date {
        calendar.date(from: DateComponents(year: day.year, month: day.month, day: day.day, hour: 12)) ?? Date()
    }
}
