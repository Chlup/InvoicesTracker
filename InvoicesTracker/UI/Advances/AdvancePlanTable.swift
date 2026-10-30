import SwiftUI

/// The card "Zálohy na rok …": the rate of the flat-rate expenses (with a note under it while 30 % is chosen), the
/// reduced base of the social insurance, the box that fills the months from one on, the copy of the year before, and
/// the table of the twelve months with the totals of the year and to the day shown. The cells are texts that are saved
/// by themselves; a cell whose text is not an amount in whole Kč has the message under its row and is not saved.
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

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            choices
            if let hint = model.refundHint {
                HintBox(text: hint)
            }
            prefillBox
            table
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .screenCard()
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Zálohy")
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

    private var title: some View {
        Text("Zálohy na rok \(String(model.year))")
            .font(.system(size: 17, weight: .bold))
            .accessibilityAddTraits(.isHeader)
    }

    private var caption: some View {
        Text("záloha se počítá jako zaplacená v měsíci, ke kterému patří · změny se ukládají hned")
            .font(.callout)
            .foregroundStyle(.secondary)
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
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var ratePicker: some View {
        HStack(spacing: 8) {
            Text("Sazba paušálních výdajů")
                .foregroundStyle(.secondary)
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

    private var reducedBaseToggle: some View {
        HStack(spacing: 8) {
            Toggle("Snížený vyměřovací základ pro sociální pojištění", isOn: reducedSocialBase)
            Text("(bez vlivu na výpočet)")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: Prefill

    private var prefillBox: some View {
        VStack(alignment: .leading, spacing: 10) {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .bottom, spacing: 12) {
                    prefillFields
                    prefillButtons
                    Spacer(minLength: 0)
                }
                VStack(alignment: .leading, spacing: 10) {
                    HStack(alignment: .bottom, spacing: 12) {
                        prefillFields
                    }
                    HStack(spacing: 12) {
                        prefillButtons
                    }
                }
            }
            ForEach(prefillMessages, id: \.self) { message in
                Text(verbatim: message)
                    .font(.callout)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Text(
                verbatim: "Předvyplnit zapíše částky do všech měsíců od zvoleného měsíce do konce roku."
                    + " Jednotlivé měsíce pak můžete upravit níž."
            )
            .font(.callout)
            .foregroundStyle(Color(.simulationText))
            .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.orange.opacity(0.14), in: RoundedRectangle(cornerRadius: 12))
        // A message goes when the text it is about is changed.
        .onChange(of: prefillSocial) {
            prefillErrors.social = nil
        }
        .onChange(of: prefillHealth) {
            prefillErrors.health = nil
        }
    }

    @ViewBuilder
    private var prefillFields: some View {
        prefillField("Sociální pojištění", text: $prefillSocial)
        prefillField("Zdravotní pojištění", text: $prefillHealth)
        VStack(alignment: .leading, spacing: 4) {
            Text("Platí od")
                .font(.callout)
                .foregroundStyle(Color(.simulationText))
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

    private func prefillField(_ title: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.callout)
                .foregroundStyle(Color(.simulationText))
            TextField("", text: text)
                .labelsHidden()
                .multilineTextAlignment(.trailing)
                .textFieldStyle(.roundedBorder)
                .monospacedDigit()
                .frame(width: 130)
                .accessibilityLabel(title + " – předvyplnění")
        }
    }

    @ViewBuilder
    private var prefillButtons: some View {
        Button("Předvyplnit") {
            prefillErrors = model.prefill(social: prefillSocial, health: prefillHealth, fromMonth: prefillFromMonth)
        }
        .buttonStyle(.borderedProminent)
        if model.hasPreviousYear {
            Button("Zkopírovat z roku \(String(model.year - 1))") {
                prefillErrors = PrefillErrors()
                Task { await model.copyFromPreviousYear() }
            }
            .buttonStyle(.bordered)
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
                Divider()
                row(month)
                ForEach(messages(ofMonth: month), id: \.self) { message in
                    // Under the three columns of amounts, which it is about, as far as they go.
                    GridRow {
                        Color.clear
                            .frame(height: 0)
                        Text(verbatim: message)
                            .font(.callout)
                            .foregroundStyle(.red)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .trailing)
                            .gridCellColumns(3)
                    }
                }
            }
            Rectangle()
                .fill(Color.primary.opacity(0.7))
                .frame(height: 1.5)
            totalRow
            toDateRow
        }
    }

    private func head(_ title: String, width: CGFloat?, alignment: Alignment) -> some View {
        Text(title)
            .font(.callout.weight(.semibold))
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .frame(width: width, alignment: alignment)
            .frame(maxWidth: width == nil ? .infinity : nil, alignment: alignment)
    }

    private func row(_ month: Int) -> some View {
        GridRow {
            Text(Self.monthName(month))
                .fontWeight(.semibold)
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

    /// "započteno" for a month that counts as paid on the day shown, "plán" for one that is only planned.
    private func status(_ month: Int) -> some View {
        let counted = model.isCounted(month: month)
        return HStack(spacing: 6) {
            Circle()
                .fill(counted ? Color.green : Color.secondary.opacity(0.5))
                .frame(width: 7, height: 7)
                .accessibilityHidden(true)
            Text(counted ? "započteno" : "plán")
                .font(.callout)
                .foregroundStyle(counted ? Color(.bannerText) : Color.secondary)
        }
        .frame(width: Width.status, alignment: .leading)
    }

    private var totalRow: some View {
        let totals = model.totals
        return GridRow {
            Text("Celkem za rok")
                .fontWeight(.semibold)
            amount(totals.yearSocial, weight: .semibold)
            amount(totals.yearHealth, weight: .semibold)
            amount(totals.yearTax, weight: .semibold)
            Color.clear
                .frame(height: 0)
            Color.clear
                .frame(height: 0)
        }
    }

    /// The totals to the day shown, in green: what counts as paid.
    private var toDateRow: some View {
        let totals = model.totals
        return GridRow {
            Text(model.toDateLabel)
                .font(.callout)
                .foregroundStyle(Color(.bannerText))
            amount(totals.toDateSocial, weight: .regular, color: Color(.bannerText))
            amount(totals.toDateHealth, weight: .regular, color: Color(.bannerText))
            amount(totals.toDateTax, weight: .regular, color: Color(.bannerText))
            Color.clear
                .frame(height: 0)
            Color.clear
                .frame(height: 0)
        }
    }

    private func amount(_ kc: Int64, weight: Font.Weight, color: Color = .primary) -> some View {
        Text(CzechFormat.wholeKc(kc))
            .fontWeight(weight)
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

/// A hint in an orange box, in the semantic colour at a low opacity, so that it follows the appearance of the window.
struct HintBox: View {
    let text: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: "info.circle")
                .foregroundStyle(.orange)
                .accessibilityHidden(true)
            Text(verbatim: text)
                .foregroundStyle(Color(.simulationText))
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(Color.orange.opacity(0.14), in: RoundedRectangle(cornerRadius: 12))
        .accessibilityElement(children: .combine)
    }
}
