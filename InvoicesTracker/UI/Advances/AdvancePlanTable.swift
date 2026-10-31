import SwiftUI

/// The card "Zálohy na rok …": the rate of the flat-rate expenses (with a note under it while 30 % is chosen), the
/// reduced base of the social insurance, the hint about the refunded advances while 2026 is shown, the helper that
/// fills the months from one on and copies the year before, and the table of the twelve months with the totals of the
/// year and to the day shown. The helper is a panel on the inset background with a primary button, Předvyplnit, and
/// Zkopírovat z roku … beside it, both 28 points tall as the buttons inside a card are. The cells are texts that are
/// saved by themselves; a cell whose text is not an amount in whole Kč has the message under its row and is not
/// saved.
struct AdvancePlanTable: View {
    let model: AdvancesModel

    @State private var prefillSocial = ""
    @State private var prefillHealth = ""
    @State private var prefillFromMonth = 1
    @State private var prefillErrors = PrefillErrors()

    /// The width the card gives the table, which it fills when it is more than `Width.table`.
    @State private var availableWidth: CGFloat = 0

    /// The widths of the columns of the table; the three of the amounts share the rest, and the table scrolls sideways
    /// where the card is narrower than `table`.
    private enum Width {
        static let month: CGFloat = 110
        static let secondary: CGFloat = 96
        static let status: CGFloat = 110
        static let amount: CGFloat = 96
        static let spacing: CGFloat = 12
        static let table: CGFloat = 720
    }

    /// The space between the parts of the card, in points: the header, the choices, the hint, the helper and the
    /// table, and the space between the parts of the helper.
    private enum Spacing {
        static let parts: CGFloat = 16
        static let prefill: CGFloat = 12
    }

    var body: some View {
        Card(spacing: Spacing.parts, label: "Zálohy") {
            header
            choices
            if let hint = model.refundHint {
                Note(.attention, icon: .info, text: hint)
            }
            prefillBox
            table
        }
    }

    // MARK: Header and choices

    private var header: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                title
                Spacer(minLength: 8)
                caption
            }
            VStack(alignment: .leading, spacing: 4) {
                title
                caption
            }
        }
    }

    /// "Zálohy na rok …" in title 2, the heading of the card.
    private var title: some View {
        Text("Zálohy na rok \(String(model.year))")
            .font(Typography.title2)
            .foregroundStyle(Palette.text)
            .accessibilityAddTraits(.isHeader)
    }

    /// What the advances are counted as, in callout and secondary text, at the end of the line of the title.
    private var caption: some View {
        Text("záloha se počítá jako zaplacená v měsíci, ke kterému patří · změny se ukládají hned")
            .font(Typography.callout)
            .foregroundStyle(Palette.text2)
    }

    /// The rate and the reduced base side by side where they fit, else one over the other. The note of the rate stands
    /// under the rate, so under the row where they are side by side and between the two where they are not.
    private var choices: some View {
        ViewThatFits(in: .horizontal) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .center, spacing: 24) {
                    ratePicker
                    reducedBaseToggle
                    Spacer(minLength: 0)
                }
                rateNote
            }
            VStack(alignment: .leading, spacing: 10) {
                VStack(alignment: .leading, spacing: 4) {
                    ratePicker
                    rateNote
                }
                reducedBaseToggle
            }
        }
    }

    /// The note under the rate while 30 % is chosen. It is shown whole: it breaks over more lines where the card is
    /// narrow, and is never cut.
    @ViewBuilder
    private var rateNote: some View {
        if let note = ExpenseRateChoice.note(forPercent: expensePercent.wrappedValue) {
            Text(verbatim: note)
                .font(Typography.callout)
                .foregroundStyle(Palette.text3)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// The rate of the flat-rate expenses: its title in secondary text and the menu of the four rates.
    private var ratePicker: some View {
        HStack(spacing: 8) {
            Text("Sazba paušálních výdajů")
                .font(Typography.body)
                .foregroundStyle(Palette.text2)
            Picker("Sazba paušálních výdajů", selection: expensePercent) {
                ForEach(ExpenseRateChoice.all, id: \.percent) { rate in
                    Text(rate.label)
                        .tag(rate.percent)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .fixedSize()
        }
    }

    /// The box of the reduced base of the social insurance, with the grey caption that it changes no figure.
    private var reducedBaseToggle: some View {
        HStack(spacing: 8) {
            Toggle("Snížený vyměřovací základ pro sociální pojištění", isOn: reducedSocialBase)
            Text("(bez vlivu na výpočet)")
                .font(Typography.callout)
                .foregroundStyle(Palette.text3)
        }
    }

    // MARK: Prefill

    /// The helper that fills the months: a panel on the inset background with the fields of the amounts, the month
    /// they hold from, and the buttons, in a row where they fit and else the fields over the buttons; under them the
    /// messages of a field whose text was refused, and the note of what Předvyplnit does.
    private var prefillBox: some View {
        VStack(alignment: .leading, spacing: Spacing.prefill) {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .bottom, spacing: Spacing.prefill) {
                    prefillFields
                    prefillButtons
                    Spacer(minLength: 0)
                }
                VStack(alignment: .leading, spacing: Spacing.prefill) {
                    HStack(alignment: .bottom, spacing: Spacing.prefill) {
                        prefillFields
                    }
                    HStack(spacing: Spacing.prefill) {
                        prefillButtons
                    }
                }
            }
            ForEach(prefillMessages, id: \.self) { message in
                Text(verbatim: message)
                    .font(Typography.callout)
                    .foregroundStyle(Palette.redText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Text(
                verbatim: "Předvyplnit zapíše částky do všech měsíců od zvoleného měsíce do konce roku."
                    + " Jednotlivé měsíce pak můžete upravit níž."
            )
            .font(Typography.callout)
            .foregroundStyle(Palette.text3)
            .fixedSize(horizontal: false, vertical: true)
        }
        .insetPanel(horizontal: 16, vertical: 12)
        // A message goes when the text it is about is changed.
        .onChange(of: prefillSocial) {
            prefillErrors.social = nil
        }
        .onChange(of: prefillHealth) {
            prefillErrors.health = nil
        }
    }

    /// The fields of the helper: the amounts of the social and of the health insurance, and the month they hold from.
    @ViewBuilder
    private var prefillFields: some View {
        prefillField("Sociální pojištění", text: $prefillSocial)
        prefillField("Zdravotní pojištění", text: $prefillHealth)
        VStack(alignment: .leading, spacing: 4) {
            Text("Platí od")
                .font(Typography.callout)
                .foregroundStyle(Palette.text2)
            Picker("Platí od", selection: $prefillFromMonth) {
                ForEach(1...12, id: \.self) { month in
                    Text(Self.monthName(month))
                        .tag(month)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .fixedSize()
        }
    }

    /// A field of an amount of the helper under its title in callout and secondary text. VoiceOver reads the field as
    /// its title and "– předvyplnění", to tell it from the cells of the table that have the same names.
    private func prefillField(_ title: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(Typography.callout)
                .foregroundStyle(Palette.text2)
            TextField("", text: text)
                .labelsHidden()
                .multilineTextAlignment(.trailing)
                .textFieldStyle(.roundedBorder)
                .monospacedDigit()
                .frame(width: 130)
                .accessibilityLabel(title + " – předvyplnění")
        }
    }

    /// Předvyplnit, a capsule in the accent, and, while the year before has a plan, Zkopírovat z roku …, a capsule in
    /// the colour of a card raised off the panel; both 28 points tall.
    @ViewBuilder
    private var prefillButtons: some View {
        Button("Předvyplnit") {
            prefillErrors = model.prefill(social: prefillSocial, health: prefillHealth, fromMonth: prefillFromMonth)
        }
        .buttonStyle(CapsuleButtonStyle(.primary, size: .small))
        if model.hasPreviousYear {
            Button("Zkopírovat z roku \(String(model.year - 1))") {
                prefillErrors = PrefillErrors()
                Task { await model.copyFromPreviousYear() }
            }
            .buttonStyle(CapsuleButtonStyle(.onWindow, size: .small))
        }
    }

    /// The messages of the boxes whose text was refused, each with the name of its box.
    private var prefillMessages: [String] {
        [
            prefillErrors.social.map { "Sociální pojištění: " + $0 },
            prefillErrors.health.map { "Zdravotní pojištění: " + $0 },
        ].compactMap { $0 }
    }

    // MARK: The table

    private var table: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            grid
                // A little room around the fields, so that their borders are not cut by the scroll view.
                .padding(.horizontal, 2)
                .padding(.vertical, 3)
                .frame(width: max(Width.table, availableWidth), alignment: .leading)
        }
        .onGeometryChange(for: CGFloat.self) { proxy in
            proxy.size.width
        } action: { width in
            availableWidth = width
        }
    }

    private var grid: some View {
        // The rows are 10 points apart, the lines between them in the middle.
        Grid(alignment: .leading, horizontalSpacing: Width.spacing, verticalSpacing: 10) {
            GridRow {
                head("Měsíc", width: Width.month, alignment: .leading)
                head("Sociální pojištění", width: nil, alignment: .trailing)
                head("Zdravotní pojištění", width: nil, alignment: .trailing)
                head("Daň z příjmů", width: nil, alignment: .trailing)
                head("Vedl. činnost", width: Width.secondary, alignment: .center)
                head("Stav", width: Width.status, alignment: .leading)
            }
            ForEach(1...12, id: \.self) { month in
                Hairline()
                row(month)
                ForEach(messages(ofMonth: month), id: \.self) { message in
                    // Under the three columns of amounts, which it is about, as far as they go.
                    GridRow {
                        Color.clear
                            .frame(height: 0)
                        Text(verbatim: message)
                            .font(Typography.callout)
                            .foregroundStyle(Palette.redText)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .trailing)
                            .gridCellColumns(3)
                    }
                }
            }
            // The rule over the totals is the colour of text, 1,5 points thick.
            Rectangle()
                .fill(Palette.text)
                .frame(height: 1.5)
            totalRow
            toDateRow
        }
    }

    /// The heading of a column of the table in callout semibold and secondary text, `width` points wide, or as wide as
    /// its column where that is nil.
    private func head(_ title: String, width: CGFloat?, alignment: Alignment) -> some View {
        Text(title)
            .font(Typography.calloutSemibold)
            .foregroundStyle(Palette.text2)
            .lineLimit(1)
            .frame(width: width, alignment: alignment)
            .frame(maxWidth: width == nil ? .infinity : nil, alignment: alignment)
    }

    /// The row of `month`: its name, the cells of the three amounts (the income tax only in the months it is paid), the
    /// box of the secondary activity and the status.
    private func row(_ month: Int) -> some View {
        GridRow {
            Text(Self.monthName(month))
                .font(Typography.bodySemibold)
                .foregroundStyle(Palette.text)
                .frame(width: Width.month, alignment: .leading)
            cellField(month, .social)
            cellField(month, .health)
            // The income tax is paid every quarter, so only March, June, September and December have a cell for it.
            if month % 3 == 0 {
                cellField(month, .tax)
            } else {
                Color.clear
                    .frame(height: 0)
            }
            Toggle("Vedlejší činnost – " + Self.monthName(month), isOn: secondary(month))
                .toggleStyle(.checkbox)
                .labelsHidden()
                .accessibilityLabel("Vedlejší činnost – " + Self.monthName(month))
                .frame(width: Width.secondary)
            status(month)
        }
    }

    private func cellField(_ month: Int, _ column: AdvanceColumn) -> some View {
        let label = Self.columnName(column) + " – " + Self.monthName(month)
        return TextField("", text: cell(month, column))
            .labelsHidden()
            .multilineTextAlignment(.trailing)
            .textFieldStyle(.roundedBorder)
            .monospacedDigit()
            .frame(minWidth: Width.amount, maxWidth: .infinity)
            .accessibilityLabel(label)
            .onSubmit {
                Task { await model.saveNow() }
            }
    }

    /// "započteno" for a month that counts as paid on the day shown, in the green of text with a dot of the same green,
    /// "plán" for one that is only planned, in the grey of captions with a dot of the stronger line.
    private func status(_ month: Int) -> some View {
        let counted = model.isCounted(month: month)
        return HStack(spacing: 6) {
            Circle()
                .fill(counted ? Palette.greenText : Palette.sepStrong)
                .frame(width: 7, height: 7)
                .accessibilityHidden(true)
            Text(counted ? "započteno" : "plán")
                .font(Typography.callout)
                .foregroundStyle(counted ? Palette.greenText : Palette.text3)
        }
        .frame(width: Width.status, alignment: .leading)
    }

    /// "Celkem za rok" with the three totals of the year, in semibold text.
    private var totalRow: some View {
        let totals = model.totals
        return GridRow {
            Text("Celkem za rok")
                .font(Typography.bodySemibold)
                .foregroundStyle(Palette.text)
            amount(totals.yearSocial, font: Typography.bodySemibold, color: Palette.text)
            amount(totals.yearHealth, font: Typography.bodySemibold, color: Palette.text)
            amount(totals.yearTax, font: Typography.bodySemibold, color: Palette.text)
            Color.clear
                .frame(height: 0)
            Color.clear
                .frame(height: 0)
        }
    }

    /// The totals to the day shown, in the green of text: what counts as paid.
    private var toDateRow: some View {
        let totals = model.totals
        return GridRow {
            Text(model.toDateLabel)
                .font(Typography.callout)
                .foregroundStyle(Palette.greenText)
            amount(totals.toDateSocial, font: Typography.body, color: Palette.greenText)
            amount(totals.toDateHealth, font: Typography.body, color: Palette.greenText)
            amount(totals.toDateTax, font: Typography.body, color: Palette.greenText)
            Color.clear
                .frame(height: 0)
            Color.clear
                .frame(height: 0)
        }
    }

    /// A total in whole Kč, in `font` and `color`, against the right edge of its column.
    private func amount(_ kc: Int64, font: Font, color: Color) -> some View {
        Text(CzechFormat.wholeKc(kc))
            .font(font)
            .monospacedDigit()
            .foregroundStyle(color)
            .frame(maxWidth: .infinity, alignment: .trailing)
    }

    /// The messages under the cells of `month`, one for each cell whose text was refused.
    private func messages(ofMonth month: Int) -> [String] {
        let found = AdvanceColumn.allCases.compactMap { model.cellError(month: month, column: $0.rawValue) }
        // The same message for several cells of a row is said once.
        return found.reduce(into: [String]()) { messages, message in
            if !messages.contains(message) {
                messages.append(message)
            }
        }
    }

    // MARK: Bindings

    private func cell(_ month: Int, _ column: AdvanceColumn) -> Binding<String> {
        Binding(
            get: { model.cells[month - 1][column.rawValue] },
            set: { model.setCell(month: month, column: column.rawValue, text: $0) })
    }

    private func secondary(_ month: Int) -> Binding<Bool> {
        Binding(
            get: { model.settings?.secondaryMonths.contains(month) ?? false },
            set: { model.setSecondary(month: month, $0) })
    }

    private var expensePercent: Binding<Int> {
        Binding(
            get: { model.settings?.expensePercent ?? 0 },
            set: { model.setExpensePercent($0) })
    }

    private var reducedSocialBase: Binding<Bool> {
        Binding(
            get: { model.settings?.reducedSocialBase ?? false },
            set: { model.setReducedSocialBase($0) })
    }

    // MARK: Names

    /// "Leden" … "Prosinec".
    private static func monthName(_ month: Int) -> String {
        let name = CzechFormat.monthNames[month - 1]
        return name.prefix(1).uppercased() + name.dropFirst()
    }

    private static func columnName(_ column: AdvanceColumn) -> String {
        switch column {
        case .social: "Sociální pojištění"
        case .health: "Zdravotní pojištění"
        case .tax: "Daň z příjmů"
        }
    }
}
