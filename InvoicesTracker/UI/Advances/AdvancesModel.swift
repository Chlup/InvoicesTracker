import Foundation
import Observation

/// A cell of the plan of advances: a month, 1 to 12, and a column.
nonisolated struct AdvanceCell: Hashable, Sendable {
    var month: Int
    var column: AdvanceColumn
}

/// What the person has typed into, which a reload of the screen leaves as it is.
nonisolated enum TypedField: Hashable, Sendable {
    case cell(AdvanceCell)
    case deduction(DeductionField)

    /// The spouse's own income for the year.
    case spouseIncome
}

/// What the prefill refused: the box of each column whose text is not an amount in whole Kč, with the message for it.
nonisolated struct PrefillErrors: Equatable, Sendable {
    var social: String?
    var health: String?

    var isEmpty: Bool {
        social == nil && health == nil
    }
}

/// The model of Zálohy a odpočty: the plan of advances of the selected year as texts that are typed, the totals of the
/// year and to the day shown, the deductions with their limits, the taxpayer credit, the family with the spouse credit
/// and the child tax benefit, and the impact of the deductions and the credits on the tax. Every change is saved by
/// itself.
///
/// - The screen loads again whenever what the data depends on changes (`AppModel.reloadKey`). A load reads the year
///   from the data, puts on it what has been changed and is not saved yet, and works out the impact with the
///   validated computation (`AppModel.compute`), so the panel follows each change once it is saved. A stored year the
///   computation refuses shows a line (`impactError`) in place of numbers, and the plan stays there to be corrected.
/// - A field the person has touched keeps the text they typed through every reload, also one that was refused, so a
///   save, or a load, never writes over what is being typed. The others show what is stored.
/// - A text that is typed is read when the typing has stopped, not key by key: `saveDelay` after the last key (every
///   key starts the wait again), when the person leaves the field or presses Return, and when the screen or the year is
///   left (`saveNow()`). Until then it is only a text: nothing is read of it, no message comes of it and nothing is
///   saved, so the beginning of what is typed ("1", "11 8") is never taken for an amount.
/// - A text is read with `AmountParser`. The advances and the deductions are whole Kč, so a text with haléře is
///   refused with the message under its field; so is a negative amount. A text that is refused is never saved, not even
///   its beginning: the field keeps the text, the data keeps its value, and a change that waited for the field is
///   withdrawn.
/// - Each save writes only the fields that were changed, on top of what is stored at that moment
///   (`Database.updateYearSettings`), and then tells the app (`didWrite()`). A menu, a checkbox, the prefill and the
///   copy are saved at once. A save that fails is said on the screen (`saveFailure`), keeps the typed texts and the
///   values, and is tried again with the next change.
///
/// - The children are written at once through `FamilyEditing`, each change of the dialog of a child in one write with
///   the orders of the other children, and one that is not written throws for the dialog to say so. The spouse belongs
///   to the settings of the year and is saved with them, at once, and its own income is a typed field like those of
///   the deductions.
///
/// Months are 1 to 12 (January is 1) everywhere in the interface of the model, like the months of `YearSettings`;
/// `cells` has a row for each month, so month `m` is `cells[m - 1]`.
@MainActor
@Observable
final class AdvancesModel {
    // MARK: Texts

    /// What the screen says in place of its content when the year cannot be loaded.
    static let loadFailureText = "Zálohy a odpočty se nepodařilo načíst."

    /// What the screen says next to the form when a change could not be saved.
    static let saveFailureText = "Změnu se nepodařilo uložit."

    /// What the screen says next to the form when the plan of the year before could not be copied.
    static let copyFailureText = "Zálohy z minulého roku se nepodařilo zkopírovat."

    /// What the screen says next to the form when the screen moved to another year while changes of `year` could not be
    /// saved: they are lost.
    static func unsavedYearText(_ year: Int) -> String {
        "Změny roku \(year) se nepodařilo uložit."
    }

    /// Under a field of whole crowns that has a text which is not one. It says how a whole amount is written: the
    /// common message of the amounts ("13 340 nebo 13 340,50") would invite haléře, which these fields refuse.
    static let wholeKcMessage = "Zadejte částku v celých korunách, například 13 340."

    /// Under the months of mortgage interest.
    static let monthsMessage = "Zadejte počet měsíců od 0 do 12."

    /// The hint for 2026, when the minimum advance of social insurance dropped in the middle of the year.
    static let refundHintText =
        "Od července 2026 je minimální záloha nižší (zákon 90/2026 Sb.). Pokud vám ČSSZ vrátila část záloh za leden"
        + " až červen, snižte tyto měsíce o vrácenou částku – vrácená záloha se nepočítá jako zaplacená."

    /// How the delay before a save is waited out. A test replaces it with a wait that it ends itself.
    typealias Wait = DebounceTimer.Wait

    /// The advances of the year added up, and added up to the day shown.
    typealias Totals = (
        yearSocial: Int64, yearHealth: Int64, yearTax: Int64, toDateSocial: Int64, toDateHealth: Int64,
        toDateTax: Int64
    )

    // MARK: State

    /// The settings of the year shown as the person has them: what is stored, with every change made on the screen and
    /// not saved yet on top of it. Nil until the first load has finished.
    private(set) var settings: YearSettings?

    /// The texts of the plan: twelve rows, January first, of the social insurance, the health insurance and the income
    /// tax. A cell shows what is stored, or what was typed in it.
    var cells = AdvancesModel.emptyCells

    /// The messages under the cells whose text was refused.
    private var cellErrors: [AdvanceCell: String] = [:]

    /// The texts of the fields of the deductions, and the messages under those that were refused.
    private(set) var deductionTexts: [DeductionField: String] = [:]
    private var deductionErrors: [DeductionField: String] = [:]

    /// What the screen says next to the form when the last save failed, otherwise nil.
    private(set) var saveFailure: String?

    /// Whether the year before has settings of its own, so that its plan can be copied.
    private(set) var hasPreviousYear = false

    /// What the screen says in place of its content when the last load failed, otherwise nil.
    private(set) var errorText: String?

    /// What the screen says in place of the numbers of the impact when the stored year cannot be computed.
    private(set) var impactError: String?

    /// The deductions worked out as of the day shown: their effect on the tax, the totals and the hints of the form.
    /// Nil until the first load, and for a year the computation refuses.
    private var computed: AdvanceImpact?

    /// The day the data was loaded as of, which the totals count to.
    private var shownAsOf: CivilDate?

    /// The family of the year shown as the data holds it, read with the year; its spouse is the one of `settings`.
    /// Nil until the first load.
    private(set) var loadedFamily: FamilyYear?

    /// The cards of the family: the children and the spouse of the year with the figures of the engine. Nil until the
    /// first load, and for a year the computation refuses.
    private(set) var familyCards: FamilyCardsContent?

    /// The text of the field of the spouse's own income, and the message under it while it is refused.
    private(set) var spouseIncomeText = ""
    private(set) var spouseIncomeError: String?

    let app: AppModel
    private let saveDelay: Duration

    /// The wait before a save.
    private let saveTimer: DebounceTimer

    /// The settings of the year as they were last read from the data or written to it: what `settings` is made from.
    @ObservationIgnored private var stored: YearSettings?

    /// The changes made on the screen that are not written yet, the oldest first, and those that are being written.
    /// They belong to the year of `settings`.
    @ObservationIgnored private var pending: [YearSettingsEdit] = []
    @ObservationIgnored private var inFlight: [YearSettingsEdit] = []

    /// The write that runs.
    @ObservationIgnored private var writeTask: Task<Void, Never>?

    /// What the person has touched since the year was shown, and of that what has been typed and not read yet.
    @ObservationIgnored private var touched: Set<TypedField> = []
    @ObservationIgnored private var unread: Set<TypedField> = []

    /// How many loads have started. Only the latest may show its result: one that was started for a year that has been
    /// replaced since must not undo the newer one.
    @ObservationIgnored private var loadsStarted = 0

    init(
        app: AppModel, saveDelay: Duration = .milliseconds(500),
        wait: @escaping Wait = { try await Task.sleep(for: $0) }
    ) {
        self.app = app
        self.saveDelay = saveDelay
        saveTimer = DebounceTimer(wait: wait)
    }

    // MARK: What the screen shows

    /// The year shown.
    var year: Int {
        settings?.year ?? app.asOf.year
    }

    /// Whether DIP and long-term care insurance are deductible items in the year, which they are from 2024.
    var showsDIPAndLongTermCare: Bool {
        TaxRules.forYear(app.asOf.year).rules.hasDIPAndLongTermCare
    }

    /// The hint about refunded advances, for 2026 only.
    var refundHint: String? {
        app.asOf.year == 2026 ? Self.refundHintText : nil
    }

    /// The effect of each deduction that is claimed on the tax, in the order of the form.
    var impact: [ImpactLine] {
        computed?.lines ?? []
    }

    var impactTotals: ImpactTotals? {
        computed?.totals
    }

    var deductionHints: DeductionHints? {
        computed?.hints
    }

    /// The advances of the year added up, and added up to the end of the month of the day shown. A cell that was
    /// refused counts with the value it had.
    var totals: Totals {
        guard let advances = settings?.advances else { return (0, 0, 0, 0, 0, 0) }
        let counted = shownAsOf?.month ?? 0
        func sum(_ plan: [Int64], months: Int) -> Int64 {
            plan.prefix(months).reduce(0, +)
        }
        return (
            yearSocial: sum(advances.social, months: 12), yearHealth: sum(advances.health, months: 12),
            yearTax: sum(advances.tax, months: 12), toDateSocial: sum(advances.social, months: counted),
            toDateHealth: sum(advances.health, months: counted), toDateTax: sum(advances.tax, months: counted)
        )
    }

    /// "Započteno k 17. 10." for the day shown, and "Zaplaceno za rok" when that is the last day of a year that is
    /// over. Any earlier day of a past year is that year as it was then, with the advances after it still to come.
    var toDateLabel: String {
        guard let shownAsOf else { return "" }
        let isOver = AsOfState.isFinishedYear(asOf: shownAsOf, today: app.today)
        return isOver ? "Zaplaceno za rok" : "Započteno k " + CzechFormat.dayMonth(shownAsOf)
    }

    /// Whether the advance of `month` counts as paid on the day shown (`true`: "započteno"), or is only planned.
    func isCounted(month: Int) -> Bool {
        month <= (shownAsOf?.month ?? 0)
    }

    /// The message under a cell whose text was refused, otherwise nil.
    func cellError(month: Int, column: Int) -> String? {
        guard let column = AdvanceColumn(rawValue: column) else { return nil }
        return cellErrors[AdvanceCell(month: month, column: column)]
    }

    /// The message under a field of the deductions whose text was refused, otherwise nil.
    func deductionError(_ field: DeductionField) -> String? {
        deductionErrors[field]
    }

    // MARK: Loading

    /// Loads the selected year as of the day shown. What was changed on the screen and is not saved yet stays on it;
    /// what waits to be saved for the year that was shown before is saved first. A failure is logged (the domain and
    /// the code of the error alone) and shows `errorText`; the plan that was on the screen stays as it was. The model
    /// is known to the app from its first load on, so that a quit waits for what is typed (`hasUnsavedInput`).
    func load() async {
        app.quitFlushes.register(self)
        loadsStarted += 1
        let thisLoad = loadsStarted
        let shown = app.asOf
        let day = app.receivedThrough
        do {
            guard let database = app.database else { throw VaultError.locked }
            // What waits to be saved belongs to the year it was typed in, not to the one that comes.
            if let shownBefore = settings?.year, shownBefore != shown.year {
                await saveNow()
            }
            let (input, readSettings) = try await app.yearInput(for: shown.year)
            let readFamily = try await database.family(year: shown.year)
            let previousYearIsThere = try await database.storedSettingsYears().contains(shown.year - 1)
            guard thisLoad == loadsStarted else { return }

            if let shownBefore = settings?.year, shownBefore != shown.year {
                // What could not be saved before the year was left is lost with it, and the screen says so.
                readTypedTexts()
                let lostChanges = !pending.isEmpty
                forgetTheYear()
                if lostChanges {
                    saveFailure = Self.unsavedYearText(shownBefore)
                }
            }
            stored = readSettings
            loadedFamily = readFamily
            refreshSettings()
            let effective = settings ?? readSettings
            seedTexts(from: effective)
            hasPreviousYear = previousYearIsThere
            shownAsOf = day
            errorText = nil
            // The family the cards show is the one the computation takes, with the spouse the person has.
            let family = FamilyYear(year: readFamily.year, children: readFamily.children, spouse: effective.spouse)
            computeImpact(
                of: AppModel.yearInput(effective, receipts: input.receipts, family: FamilyFacts(family)),
                family: family, asOf: day)
        } catch {
            guard thisLoad == loadsStarted else { return }
            AppModel.log("Loading Zálohy a odpočty", failedWith: error)
            errorText = Self.loadFailureText
        }
    }

    /// Works out the impact of the deductions and the credits in `input`, and the cards of `family`, the family of the
    /// input, or says why they cannot be.
    private func computeImpact(of input: YearInput, family: FamilyYear, asOf: CivilDate) {
        do {
            let impact = try AdvanceImpactBuilder.build(input, asOf: asOf)
            computed = impact
            familyCards = FamilyCardsBuilder.content(
                family: family, result: impact.result, mode: .stored,
                isWholeYear: AsOfState.isFinishedYear(asOf: asOf, today: app.today))
            impactError = nil
        } catch {
            AppModel.log("Working out the impact of the deductions", failedWith: error)
            computed = nil
            familyCards = nil
            impactError = "Dopad na daň se nepodařilo spočítat – uložené hodnoty roku \(input.year) jsou neplatné."
        }
    }

    /// Puts the stored values into the texts of the fields the person has not touched.
    private func seedTexts(from settings: YearSettings) {
        var seeded = cells
        for month in 1...12 {
            for column in AdvanceColumn.allCases {
                let cell = AdvanceCell(month: month, column: column)
                if !touched.contains(.cell(cell)) {
                    seeded[month - 1][column.rawValue] = Self.text(of: settings.advances.amount(column, month: month))
                }
            }
        }
        if seeded != cells {
            cells = seeded
        }
        var texts = deductionTexts
        for field in DeductionField.allCases where !touched.contains(.deduction(field)) {
            texts[field] = Self.text(of: field, in: settings.deductions)
        }
        if texts != deductionTexts {
            deductionTexts = texts
        }
        seedSpouseIncome(from: settings.spouse)
    }

    /// Puts the income of `spouse` into its field, unless the person has touched it.
    func seedSpouseIncome(from spouse: SpouseYear?) {
        let text = Self.text(ofIncomeOf: spouse)
        if !touched.contains(.spouseIncome) && text != spouseIncomeText {
            spouseIncomeText = text
        }
    }

    /// Forgets everything of the year that was shown: the texts and the messages, and the changes that were not saved.
    private func forgetTheYear() {
        pending = []
        inFlight = []
        touched = []
        unread = []
        cells = Self.emptyCells
        cellErrors = [:]
        deductionTexts = [:]
        deductionErrors = [:]
        spouseIncomeText = ""
        spouseIncomeError = nil
        saveFailure = nil
    }

    // MARK: Editing

    /// A cell of the plan has been typed in. This records the text and starts the wait again, nothing more: the text is
    /// read when the typing stops (see above), so what is typed key by key is never read, never has a message and is
    /// never saved. A text that is an amount in whole Kč (or nothing, for no advance) then becomes the value of the
    /// cell; any other text stays in the cell with the message under it, and the cell keeps the value it had. `month`
    /// is 1 to 12, `column` 0 for the social insurance, 1 for the health insurance and 2 for the income tax; a cell
    /// outside the plan is left alone.
    func setCell(month: Int, column: Int, text: String) {
        guard settings != nil, (1...12).contains(month), let column = AdvanceColumn(rawValue: column) else { return }
        recordTyping(text, in: .cell(AdvanceCell(month: month, column: column)))
    }

    /// Puts `text` into `field` as it is typed, and nothing more: the field keeps the text through every reload, the
    /// text is read when the typing stops (see above), and the wait before the save starts again. Every typed field of
    /// the screen comes here.
    func recordTyping(_ text: String, in field: TypedField) {
        switch field {
        case .cell(let cell):
            cells[cell.month - 1][cell.column.rawValue] = text
        case .deduction(let deduction):
            deductionTexts[deduction] = text
        case .spouseIncome:
            spouseIncomeText = text
        }
        touched.insert(field)
        unread.insert(field)
        scheduleSave(after: saveDelay)
    }

    /// Marks the activity of `month` as secondary, or as the main one. Saved at once.
    func setSecondary(month: Int, _ on: Bool) {
        guard (1...12).contains(month) else { return }
        queue([.secondary(month: month, on: on)], after: .zero)
    }

    /// The box above the table: writes `social` and `health` into the months from `fromMonth` (1 to 12; a month
    /// outside the year is taken as the nearest one) to the end of the year, and leaves the earlier months and the
    /// income tax alone. A box with nothing in it leaves its column as it is. If a text is not an amount in whole Kč,
    /// nothing is written and the result says which box to put the message under.
    @discardableResult
    func prefill(social: String, health: String, fromMonth: Int) -> PrefillErrors {
        let socialAmount = TypedKc(social)
        let healthAmount = TypedKc(health)
        var errors = PrefillErrors()
        if socialAmount == .refused {
            errors.social = Self.wholeKcMessage
        }
        if healthAmount == .refused {
            errors.health = Self.wholeKcMessage
        }
        guard errors.isEmpty, settings != nil else { return errors }

        var edits: [YearSettingsEdit] = []
        for month in min(max(fromMonth, 1), 12)...12 {
            for (column, amount) in [(AdvanceColumn.social, socialAmount), (AdvanceColumn.health, healthAmount)] {
                guard case .value(let kc) = amount else { continue }
                edits.append(.advance(column, month: month, kc: kc))
                show(kc, inCellOf: month, column)
            }
        }
        queue(edits, after: .zero)
        return errors
    }

    /// Copies the advances and the secondary months of the year before into the year shown, and saves them before it
    /// returns. Nothing else of the year before is copied. Does nothing when the year before has no settings.
    func copyFromPreviousYear() async {
        guard hasPreviousYear, let shown = settings, let database = app.database else { return }
        do {
            let previous = try await database.yearSettings(shown.year - 1)
            // The person may have moved to another year meanwhile.
            guard settings?.year == shown.year else { return }
            var edits: [YearSettingsEdit] = []
            for month in 1...12 {
                for column in AdvanceColumn.allCases {
                    let kc = previous.advances.amount(column, month: month)
                    edits.append(.advance(column, month: month, kc: kc))
                    show(kc, inCellOf: month, column)
                }
                edits.append(.secondary(month: month, on: previous.secondaryMonths.contains(month)))
            }
            queue(edits, after: .zero)
        } catch {
            AppModel.log("Reading the year before", failedWith: error)
            saveFailure = Self.copyFailureText
            return
        }
        await saveNow()
    }

    /// Puts `kc` into the cell as it is shown, in place of whatever was typed there, and takes its message away.
    private func show(_ kc: Int64, inCellOf month: Int, _ column: AdvanceColumn) {
        let cell = AdvanceCell(month: month, column: column)
        cells[month - 1][column.rawValue] = Self.text(of: kc)
        cellErrors[cell] = nil
        unread.remove(.cell(cell))
    }

    // MARK: Rate, reduced base and credit

    /// The flat-rate expenses: 80, 60, 40 or 30 %. Any other percentage is not taken. Saved at once.
    func setExpensePercent(_ percent: Int) {
        guard TaxRules.expenseCap(percent: percent) != nil else { return }
        queue([.expensePercent(percent)], after: .zero)
    }

    /// The reduced base of the social insurance, which is only stored. Saved at once.
    func setReducedSocialBase(_ on: Bool) {
        queue([.reducedSocialBase(on)], after: .zero)
    }

    /// Whether the taxpayer credit is claimed. Saved at once.
    func setTaxpayerCredit(_ on: Bool) {
        queue([.taxpayerCredit(on)], after: .zero)
    }

    // MARK: Deductions

    /// The most a typed amount can be, in Kč: the amounts of the forms are below this (see `AmountParser`).
    private static let largestAmountKc: Int64 = 9_999_999_999

    /// Makes `deductions` the deductions of the year, and shows them in the fields. A value the tax engine would refuse
    /// (a negative amount, an amount no form takes, more than 12 months of interest) is not taken: nothing changes and
    /// the result is `false`. Saved at once.
    @discardableResult
    func setDeductions(_ deductions: Deductions) -> Bool {
        guard let current = settings?.deductions, Self.accepts(deductions) else { return false }
        var edits: [YearSettingsEdit] = []
        for field in DeductionField.allCases where field.amount(in: deductions) != field.amount(in: current) {
            edits.append(.deduction(field, value: field.amount(in: deductions)))
            deductionTexts[field] = Self.text(of: field, in: deductions)
            deductionErrors[field] = nil
            unread.remove(.deduction(field))
        }
        if deductions.mortgageCap != current.mortgageCap {
            edits.append(.mortgageCap(deductions.mortgageCap))
        }
        queue(edits, after: .zero)
        return true
    }

    /// A field of the deductions has been typed in. Like a cell of the plan, it records the text and starts the wait
    /// again, and the text is read when the typing stops: an amount in whole Kč (the number of months, 0 to 12, for the
    /// months of interest), or nothing for zero, becomes the value of the deduction; any other text stays in the field
    /// with the message under it, and the deduction keeps the value it had.
    func setDeductionText(_ field: DeductionField, _ text: String) {
        guard settings != nil else { return }
        recordTyping(text, in: .deduction(field))
    }

    /// The limit on the interest: for housing acquired before 1. 1. 2021, or later. Saved at once.
    func setMortgageCap(_ cap: MortgageCap) {
        queue([.mortgageCap(cap)], after: .zero)
    }

    /// Whether the engine takes `deductions` and every amount is one a form could have typed.
    private static func accepts(_ deductions: Deductions) -> Bool {
        let amounts = DeductionField.allCases.filter { !$0.isMonthCount }.map { $0.amount(in: deductions) }
        return (0...12).contains(deductions.mortgageMonths)
            && amounts.allSatisfy { (0...largestAmountKc).contains($0) }
    }

    // MARK: Saving

    /// Makes `edits` the changes that wait for their fields, and saves them `delay` after the last change.
    private func queue(_ edits: [YearSettingsEdit], after delay: Duration) {
        guard stored != nil else { return }
        for edit in edits {
            stage(edit)
        }
        refreshSettings()
        if !pending.isEmpty {
            scheduleSave(after: delay)
        }
    }

    /// Makes `edit` the change that waits for its field, in place of the one that waited for it. No change waits for
    /// the field when the data holds the value anyway, or will once what is being written and what waits is written:
    /// the income of the spouse is a change of the spouse that waits too.
    private func stage(_ edit: YearSettingsEdit) {
        guard let stored else { return }
        pending.removeAll { $0.target == edit.target }
        var expected = stored
        for written in inFlight + pending {
            written.apply(to: &expected)
        }
        var changed = expected
        edit.apply(to: &changed)
        if changed != expected {
            pending.append(edit)
        }
    }

    /// Reads the texts that were typed and not read yet, now that the typing has stopped. A text that is an amount
    /// becomes the change that waits for its field. Any other text keeps its place in the field with its message, and
    /// the change that waited for the field goes, so that nothing of it is saved and the data keeps its value.
    private func readTypedTexts() {
        guard stored != nil else { return }
        let fields = unread
        unread = []
        for field in fields {
            switch field {
            case .cell(let cell):
                let target = YearSettingsEdit.Target.advance(cell.column, month: cell.month)
                switch TypedKc(cells[cell.month - 1][cell.column.rawValue]) {
                case .refused:
                    cellErrors[cell] = Self.wholeKcMessage
                    pending.removeAll { $0.target == target }
                case .blank:
                    cellErrors[cell] = nil
                    stage(.advance(cell.column, month: cell.month, kc: 0))
                case .value(let kc):
                    cellErrors[cell] = nil
                    stage(.advance(cell.column, month: cell.month, kc: kc))
                }
            case .deduction(let deduction):
                if let value = deduction.value(of: deductionTexts[deduction] ?? "") {
                    deductionErrors[deduction] = nil
                    stage(.deduction(deduction, value: value))
                } else {
                    deductionErrors[deduction] = deduction.isMonthCount ? Self.monthsMessage : Self.wholeKcMessage
                    pending.removeAll { $0.target == .deduction(deduction) }
                }
            case .spouseIncome:
                switch TypedKc(spouseIncomeText) {
                case .refused:
                    spouseIncomeError = Self.wholeKcMessage
                    pending.removeAll { $0.target == .spouseIncome }
                case .blank:
                    spouseIncomeError = nil
                    stage(.spouseIncome(0))
                case .value(let kc):
                    spouseIncomeError = nil
                    stage(.spouseIncome(kc))
                }
            }
        }
        refreshSettings()
    }

    /// Puts what is being written and what waits to be written on the stored settings: the settings the person has.
    private func refreshSettings() {
        guard var effective = stored else { return }
        for edit in inFlight + pending {
            edit.apply(to: &effective)
        }
        if effective != settings {
            settings = effective
        }
    }

    /// Whether something typed or changed is not written yet: a text that waits for the typing to stop, a change that
    /// waits to be saved, or a save that runs.
    var hasUnsavedInput: Bool {
        !unread.isEmpty || !pending.isEmpty || writeTask != nil
    }

    /// Makes `edits` changes that wait for no field and saves them at once, with what waits to be saved, as the choices
    /// of the screen are saved. Returns whether they are written: a save that fails is said (`saveFailure`), and they
    /// wait for the next save. False before the year is loaded, as there is nothing to change yet.
    func saveAtOnce(_ edits: [YearSettingsEdit]) async -> Bool {
        guard stored != nil else { return false }
        queue(edits, after: .zero)
        await saveNow()
        return !pending.contains { waiting in edits.contains { $0.target == waiting.target } }
    }

    /// Starts the wait before the save again. Every change starts it again, so a text that is typed key by key is read
    /// once the typing has stopped for `delay`. No delay at all is no wait: the save is made as soon as the change is.
    private func scheduleSave(after delay: Duration) {
        saveTimer.restart(after: delay) {
            await self.saveNow()
        }
    }

    /// Reads the texts that were typed, saves what waits to be saved, and returns when it is written and the app has
    /// been told of it. The screen calls this when the person leaves a field, presses Return or leaves the screen, and
    /// when the year changes; the end of the wait does. When a save is already running this waits for it and then
    /// saves what has come since. A save that fails is not tried again here: it is said in `saveFailure`, and the
    /// changes wait for the next one.
    func saveNow() async {
        saveTimer.cancel()
        while let running = writeTask {
            await running.value
        }
        readTypedTexts()
        guard !pending.isEmpty else { return }
        let edits = pending
        inFlight = edits
        pending = []
        let task = Task { await self.write(edits) }
        writeTask = task
        await task.value
    }

    /// Writes `edits` on top of what is stored for the year shown, in one transaction, and tells the app.
    private func write(_ edits: [YearSettingsEdit]) async {
        defer {
            inFlight = []
            writeTask = nil
            refreshSettings()
        }
        guard let year = stored?.year, let database = app.database else {
            restore(edits)
            saveFailure = Self.saveFailureText
            return
        }
        do {
            let saved = try await database.updateYearSettings(year) { settings in
                for edit in edits {
                    edit.apply(to: &settings)
                }
            }
            if stored?.year == saved.year {
                stored = saved
            }
        } catch {
            AppModel.log("Saving the advances and deductions", failedWith: error)
            restore(edits)
            saveFailure = Self.saveFailureText
            return
        }
        saveFailure = nil
        await app.didWrite()
    }

    /// Puts `edits`, which could not be written, back in front of those that came meanwhile.
    private func restore(_ edits: [YearSettingsEdit]) {
        let newer = pending
        pending = edits.filter { edit in !newer.contains { $0.target == edit.target } } + newer
    }

    // MARK: Texts of the fields

    private static let emptyCells = [[String]](repeating: [String](repeating: "", count: 3), count: 12)

    /// An advance as it is shown in a cell: nothing for zero, and otherwise the crowns with thousands separated.
    private static func text(of kc: Int64) -> String {
        kc == 0 ? "" : CzechFormat.grouped(kc)
    }

    /// A deduction field as it is shown: the crowns with thousands separated, or the months.
    private static func text(of field: DeductionField, in deductions: Deductions) -> String {
        CzechFormat.grouped(field.amount(in: deductions))
    }

    /// The field of the spouse's own income as it is shown: the crowns with thousands separated, and nothing without a
    /// spouse.
    private static func text(ofIncomeOf spouse: SpouseYear?) -> String {
        spouse.map { CzechFormat.grouped($0.ownIncomeKc) } ?? ""
    }
}

/// A text typed in a field of whole crowns: nothing at all, an amount, or text that is refused.
nonisolated enum TypedKc: Equatable, Sendable {
    /// Nothing but white space. A field with nothing in it is no amount: zero crowns, or in the prefill box, leave the
    /// column as it is.
    case blank

    /// A whole amount of crowns, not negative.
    case value(Int64)

    /// Anything else: haléře, a negative amount, or text that is no amount.
    case refused

    init(_ text: String) {
        if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            self = .blank
        } else if let kc = AmountParser.wholeKc(text), kc >= 0 {
            self = .value(kc)
        } else {
            self = .refused
        }
    }
}

nonisolated extension AdvancePlan {
    /// The advance of `column` for `month`, 1 to 12.
    func amount(_ column: AdvanceColumn, month: Int) -> Int64 {
        switch column {
        case .social: social[month - 1]
        case .health: health[month - 1]
        case .tax: tax[month - 1]
        }
    }
}

extension AdvancesModel: SavesTypedInput {}
