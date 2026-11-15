import SwiftUI

// MARK: - Jednotný kurz

/// The uniform rate of the year, in one of four states, and a page of the Finanční zpravodaj that could not be read,
/// with its link:
/// - official (shipped with the app, or fetched and confirmed): the rates of dollars and euros, where they are from and
///   Upravit;
/// - entered by hand: the same with "zadáno ručně", Upravit and a red Odstranit…, and a grey panel on what the rates
///   stand in for, in place of which Odstranit… asks in a red box what removing them leads to;
/// - computed by the app from the ČNB month-end rates: the orange pill Předběžný by the title, the rates with "≈", how
///   they were computed with Zadat ručně, the link that unfolds the ČNB rates of the month ends they average
///   (`MonthEndTable`), and a grey panel on what replaces them;
/// - none: what the app does about the rate, with Zadat ručně.
/// Upravit and Zadat ručně open the form to enter the rates by hand in place of all that.
struct UniformRateCard: View {
    @Bindable var model: YearTabModel

    var body: some View {
        Card(spacing: 10, label: "Jednotný kurz") {
            header
            if let page = model.unreadablePage {
                Note(
                    .attention, icon: .warning,
                    text: "Finanční zpravodaj s jednotným kurzem za rok \(model.year) se nepodařilo přečíst."
                        + " Kurz v něm najdete a zadáte ho ručně."
                ) {
                    SettingsLink(title: "Otevřít Finanční zpravodaj", destination: page)
                }
            }
            if model.editsRates {
                form
            } else if model.shownRates.isEmpty {
                Text(verbatim: model.missingRateText)
                    .font(Typography.body)
                    .foregroundStyle(Palette.text2)
                    .fixedSize(horizontal: false, vertical: true)
                Button("Zadat ručně", action: model.startEditingRates)
                    .settingsCardButton()
            } else {
                rates
                sourceLine
                if model.isComputed {
                    monthEnds
                }
                if model.asksToRemove {
                    ConfirmationBox(
                        title: YearTabModel.removalTitle, message: model.removalQuestion, cancelTitle: "Zrušit",
                        cancel: { model.cancelRemovingRates() }, confirmTitle: YearTabModel.removalConfirmTitle,
                        confirm: remove
                    )
                    .controlSize(.small)
                } else if let note = model.manualNote ?? model.computedNote {
                    Text(verbatim: note)
                        .font(Typography.callout)
                        .foregroundStyle(Palette.text2)
                        .fixedSize(horizontal: false, vertical: true)
                        .insetPanel(horizontal: 12, vertical: 10)
                }
            }
        }
    }

    /// The title of the card, and after it on its line the orange pill Předběžný while the card shows a rate the app
    /// computed, as the prototype draws it. The form hides the pill, as it replaces the rates.
    private var header: some View {
        HStack(alignment: .center, spacing: 8) {
            CardTitle(text: "Jednotný kurz \(model.year)")
            if model.isComputed, !model.editsRates {
                Pill("Předběžný", tone: .estimate)
            }
        }
    }

    /// The rates of dollars and euros, a row each.
    private var rates: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(model.shownRates, id: \.currency) { rate in
                Hairline()
                HStack {
                    Text(verbatim: YearTabModel.rateUnit(rate))
                        .font(Typography.body)
                        .foregroundStyle(Palette.text)
                    Spacer(minLength: 8)
                    Text(verbatim: YearTabModel.rateText(rate))
                        .font(Typography.bodySemibold)
                        .foregroundStyle(Palette.text)
                }
                .monospacedDigit()
                .padding(.vertical, 8)
                .accessibilityElement(children: .combine)
            }
        }
    }

    /// Where the rates are from, with Upravit, or Zadat ručně for rates the app computed, and, for rates entered by
    /// hand, the red Odstranit….
    private var sourceLine: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(verbatim: model.rateSource)
                .font(Typography.callout)
                .foregroundStyle(Palette.text3)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 8)
            HStack(alignment: .firstTextBaseline, spacing: 14) {
                // The year is read as it is written, not as a number with its thousands apart.
                Button(model.editRatesTitle, action: model.startEditingRates)
                    .calloutLink()
                    .accessibilityLabel(Text(verbatim: "\(model.editRatesTitle) jednotný kurz \(model.year)"))
                if model.isManual {
                    Button("Odstranit…", action: model.askToRemoveRates)
                        .calloutLink(.destructive)
                        .accessibilityLabel(Text(verbatim: "Odstranit ručně zadaný jednotný kurz \(model.year)"))
                }
            }
            .fixedSize()
        }
    }

    /// Kurzy ke konci měsíců: a text button in the blue of a link, with a chevron that turns down while the table of
    /// the ČNB rates of the month ends shows under it, and Skrýt kurzy ke konci měsíců then. It acts in place, so
    /// VoiceOver reads it as a button, under what it says.
    private var monthEnds: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button(action: model.toggleMonthEnds) {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Image(systemName: "chevron.right")
                        .font(Typography.subheadlineSemibold)
                        .imageScale(.small)
                        .rotationEffect(.degrees(model.showsMonthEnds ? 90 : 0))
                        .accessibilityHidden(true)
                    Text(verbatim: model.monthEndsTitle)
                }
            }
            .calloutLink(isLink: false)
            .accessibilityLabel(Text(verbatim: model.monthEndsTitle))
            if model.showsMonthEnds {
                MonthEndTable(year: model.year, rows: model.monthEndRows, average: model.monthEndAverage)
            }
        }
    }

    /// 1 USD, 1 EUR and the instruction of the GFŘ, with Zrušit and Uložit kurz, which Return in a field presses too.
    /// Over a rate the app computed or the table that ships with the app, the form says what saving it does.
    private var form: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let hint = model.formHint {
                Text(verbatim: hint)
                    .font(Typography.callout)
                    .foregroundStyle(Palette.text2)
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
                    .buttonStyle(CapsuleButtonStyle(.secondary, size: .small))
                Button("Uložit kurz", action: save)
                    .buttonStyle(CapsuleButtonStyle(.primary, size: .small))
            }
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

// MARK: - Kurzy ke konci měsíců

/// The table of the ČNB rates of the month ends that a computed uniform rate averages, in callout with digits of one
/// width: the titles of the columns in semibold secondary text; a row for each month of the year with its name, the day
/// of its rate and the rates of 1 USD and 1 EUR, the months that have not ended in tertiary text, each under a
/// hairline; the average of the months under the strong hairline, in semibold; and the caption of how a month takes its
/// rate. The month and the rates have columns of fixed widths, so that they line up from row to row, and the day takes
/// the rest. VoiceOver reads the table as a group under its name, "Kurzy ČNB ke konci měsíců 2026", and each row as one
/// phrase.
private struct MonthEndTable: View {
    let year: Int
    let rows: [YearTabModel.MonthEndRow]
    let average: (label: String, usd: String, eur: String)?

    /// The widths of the column of the months and of each column of the rates.
    private static let monthWidth: CGFloat = 80
    private static let rateWidth: CGFloat = 64

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            let columns = YearTabModel.monthEndColumns
            row(columns[0], columns[1], columns[2], columns[3])
                .font(Typography.calloutSemibold)
                .foregroundStyle(Palette.text2)
                .padding(.vertical, 6)
            ForEach(rows, id: \.month) { month in
                Hairline()
                row(month.month, month.day, month.usd, month.eur)
                    .foregroundStyle(month.hasEnded ? Palette.text : Palette.text3)
                    .padding(.vertical, 5)
            }
            if let average {
                Hairline(isStrong: true)
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(verbatim: average.label)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    rate(average.usd)
                    rate(average.eur)
                }
                .font(Typography.calloutSemibold)
                .foregroundStyle(Palette.text)
                .padding(.vertical, 6)
                .accessibilityElement(children: .combine)
            }
            Text(verbatim: YearTabModel.monthEndsCaption)
                .foregroundStyle(Palette.text3)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 6)
        }
        .font(Typography.callout)
        .monospacedDigit()
        .accessibilityElement(children: .contain)
        // The year is read as it is written, not as a number with its thousands apart.
        .accessibilityLabel(Text(verbatim: "Kurzy ČNB ke konci měsíců \(year)"))
    }

    /// A row of four cells: the month, the day that takes the rest of the width, and the two rates at the trailing
    /// edge of their columns. VoiceOver reads it as one phrase.
    private func row(_ month: String, _ day: String, _ usd: String, _ eur: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(verbatim: month)
                .frame(width: Self.monthWidth, alignment: .leading)
            Text(verbatim: day)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            rate(usd)
            rate(eur)
        }
        .accessibilityElement(children: .combine)
    }

    /// A rate in its column, at the trailing edge.
    private func rate(_ text: String) -> some View {
        Text(verbatim: text)
            .frame(width: Self.rateWidth, alignment: .trailing)
    }
}

// MARK: - Pravidla výpočtu

/// The values of the rules the year is computed with, their version, and the conventions of the app that the law
/// leaves open, in the words of Výpočet.
struct RulesCard: View {
    let model: YearTabModel

    var body: some View {
        Card(title: "Pravidla výpočtu", accessory: model.rulesVersion, spacing: 6, label: "Pravidla") {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(model.ruleRows, id: \.label) { row in
                    Hairline()
                    HStack(alignment: .firstTextBaseline, spacing: 12) {
                        Text(verbatim: row.label)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 8)
                        Text(verbatim: row.value)
                    }
                    .font(Typography.body)
                    .foregroundStyle(Palette.text)
                    .monospacedDigit()
                    .padding(.vertical, 9)
                    .accessibilityElement(children: .combine)
                }
                Hairline()
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
                .font(Typography.callout)
                .foregroundStyle(Palette.text3)
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
                "Příjmy mimo faktury – dobropis, vrácená platba, platba v Kč mimo fakturu. Počítají se do příjmů roku"
                + " ke svému datu.",
            accessory: model.adjustmentsTotal, accessoryIsAmount: true, spacing: 6
        ) {
            VStack(alignment: .leading, spacing: 0) {
                if model.adjustments.isEmpty {
                    Hairline()
                    Text("Žádné úpravy.")
                        .font(Typography.body)
                        .foregroundStyle(Palette.text3)
                        .padding(.vertical, 10)
                }
                ForEach(model.adjustments) { adjustment in
                    Hairline()
                    row(adjustment)
                }
                Hairline()
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

    /// An adjustment: its date, what it is, its amount in the red of text where the income went down and the green of
    /// text where it went up, and Smazat.
    private func row(_ adjustment: IncomeAdjustment) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(verbatim: CzechFormat.date(adjustment.date))
                .font(Typography.body)
                .foregroundStyle(Palette.text)
                .frame(width: 90, alignment: .leading)
            Text(verbatim: adjustment.description.isEmpty ? "—" : adjustment.description)
                .font(Typography.body)
                .foregroundStyle(Palette.text)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
            Text(verbatim: YearTabModel.adjustmentAmountText(adjustment.amountHalere))
                .font(Typography.bodySemibold)
                .foregroundStyle(adjustment.amountHalere < 0 ? Palette.redText : Palette.greenText)
            Button("Smazat") {
                Task { await model.deleteAdjustment(id: adjustment.id) }
            }
            .calloutLink(.destructive)
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
            label: "Částka v Kč (+ / −)", text: $model.adjustmentAmount, prompt: YearTabModel.adjustmentAmountPrompt,
            trailing: true)
    }

    private var descriptionField: some View {
        SettingsTextField(
            label: "Popis", text: $model.adjustmentDescription, prompt: "např. dobropis k faktuře 20260801")
    }

    /// Přidat: a capsule in the accent 28 points tall, as every button inside a card is. The prototype draws it 32 tall
    /// to match its fields of 32; the fields of the app are the native ones, so that reason does not carry over.
    private var addButton: some View {
        Button("Přidat", action: add)
            .buttonStyle(CapsuleButtonStyle(.primary, size: .small))
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
