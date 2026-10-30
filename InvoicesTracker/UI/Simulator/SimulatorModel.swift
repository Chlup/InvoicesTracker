import Foundation
import Observation

/// The model of the Simulátor: what the person has entered for a simulation — the year, the income, the flat-rate
/// expenses, the activity with its months and, for a secondary one, whether it is exempt from the health minimum, the
/// deductions, the taxpayer credit and the family — and the page the tax engine works out for it. Nothing of it is
/// stored, and nothing else in the app changes because of it.
///
/// - The app holds the model (`AppModel.simulatorModel`), not the screen, so what was entered stays while other screens
///   are shown. Other data gets a new one, and so does the data as it locks: the inputs, the family with them, live
///   until the data is locked or the app quits.
/// - A typed text is read as Zálohy a odpočty reads it: when the typing has stopped, not key by key — `typingDelay`
///   after the last key (every key starts the wait again), and when the person leaves the field or presses Return
///   (`readTypedTexts()`). Until then it is only a text, so the beginning of what is typed ("1", "2 5") is never taken
///   for an amount. The income and the deductions are whole Kč, the months of the activity 1 to 12 and those of the
///   interest 0 to 12. A text that is refused stays in its field with the message under it, and the simulation keeps
///   the value the field had. A field with nothing in it is zero, which the months of the activity refuse like any
///   other number outside 1 to 12.
/// - A menu, a toggle, the year, the copy of the deductions and family of the year and starting again apply at once.
/// - The family — the children, each with what the year says about it, and the spouse — lives in memory alone
///   (`FamilyEditing`): the copy takes the family of the year from Zálohy a odpočty, and the cards of the family and
///   the dialog of a child change it. Every change of it is made whole or not at all, as one write of the data is, and
///   the page follows it at once. It is the family of whichever year is simulated: a change of the year keeps it, a new
///   copy replaces it, and only starting again clears it. The spouse's own income is a typed field like the others.
/// - The page is worked out anew after every change that is taken, with the validated computation (`AppModel.compute`)
///   of the whole year as of its last day. It is there from the start, before the settings of the year are read.
/// - The data is only read: the settings of the year of the simulation, for the expense rate they prefill and the
///   deductions the copy takes, and the family of the year (`Database.family(year:)`), which the copy takes too. A year
///   without settings of its own has the settings Zálohy a odpočty shows for it, and the copy is on offer for it as for
///   any year, once it has been read. The rate follows the settings of the year until the person picks one. A read that
///   fails is said (`errorText`), and the inputs stay as they are.
@MainActor
@Observable
final class SimulatorModel {
    // MARK: Texts

    /// Under the months of the activity when their text is not a whole number from 1 to 12.
    static let activityMonthsMessage = "Zadejte počet měsíců od 1 do 12."

    /// What the screen says when the settings of the year could not be read.
    private static let readFailureText = "Simulátor nemůže načíst nastavení roku."

    // MARK: Years

    /// The years to choose from, newest first: those whose rules the app knows.
    static let years: [Int] = Array(TaxRules.supportedYears.reversed())

    /// The year a simulation starts on when the app shows `selected`: that year, or the nearest one whose rules the app
    /// knows.
    static func startingYear(for selected: Int) -> Int {
        min(max(selected, TaxRules.supportedYears.lowerBound), TaxRules.supportedYears.upperBound)
    }

    // MARK: State

    /// The year of the simulation, one of `years`.
    private(set) var year: Int

    /// The flat-rate expense percentage: 80, 60, 40 or 30.
    private(set) var expensePercent: Int

    /// Whether `expensePercent` comes from the settings of the year, which it does until the person picks one.
    private(set) var rateFromSettings = true

    private(set) var activity = SimulatorActivity.main

    /// Whether the person says that for the whole of the months of a secondary activity they are also employed with
    /// insurance from at least the minimum wage, study, receive a pension, are on parental leave, have a ZTP/P card or
    /// the like, so that these months have no health minimum. A secondary activity alone grants no exemption, and the
    /// main activity has the minimum whatever this says. It keeps its value while the main activity is chosen and
    /// applies again when the secondary one comes back.
    private(set) var healthMinimumExempt = false

    private(set) var taxpayerCredit = true

    /// The limit on the mortgage interest, which depends on when the housing was acquired.
    private(set) var mortgageCap = Deductions().mortgageCap

    /// The texts of the fields as they were typed: the income, the months of the activity and the deductions.
    private(set) var incomeText = ""
    private(set) var monthsText = SimulatorModel.startingMonthsText
    private(set) var deductionTexts: [DeductionField: String] = SimulatorModel.texts(of: Deductions())

    /// The messages under the fields whose text was refused.
    private(set) var incomeError: String?
    private(set) var monthsError: String?
    private(set) var deductionErrors: [DeductionField: String] = [:]

    /// The page for the values that were taken. Nil only when the computation refuses them, which the fields do not let
    /// happen.
    private(set) var page: SimulatorPage?

    /// Whether `copyDeductionsAndFamily()` is on offer: once the year has been read, whether or not it has settings of
    /// its own. False until then, which a change of the year starts over.
    private(set) var canCopyDeductionsAndFamily = false

    /// What the screen says when the settings of the year could not be read, until a read succeeds.
    private(set) var errorText: String?

    /// The children of the simulation, each with what the year says about it, listed as `Database.family(year:)` lists
    /// the children of a year: by the date of birth, then by id.
    private var familyChildren: [FamilyChild] = []

    /// The spouse of the simulation, or nil for none.
    private var familySpouse: SpouseYear?

    /// The text of the field of the spouse's own income, and the message under it while its text is refused.
    private(set) var spouseIncomeText = ""
    private(set) var spouseIncomeError: String?

    /// What the texts were last read as: the values of the simulation. The limit on the interest is `mortgageCap`.
    @ObservationIgnored private var incomeKc: Int64 = 0
    @ObservationIgnored private var activityMonths = SimulatorModel.startingMonths
    @ObservationIgnored private var typedDeductions = Deductions()

    /// The largest id a child added in the simulation has had: the next one has a larger id.
    @ObservationIgnored private var largestChildID: Int64 = 0

    /// The app, held weakly: it holds this model.
    @ObservationIgnored private weak var app: AppModel?

    private let typingDelay: Duration

    /// The wait for the typing to stop.
    private let typingTimer: DebounceTimer

    /// The fields that were typed in and not read yet.
    @ObservationIgnored private var unread: Set<Field> = []

    /// How many reads of the settings have started. Only the latest may show its result: one that was started for a
    /// year that was replaced since, or before the inputs started again, must not undo the newer one.
    @ObservationIgnored private var loadsStarted = 0

    /// A field whose text is typed.
    private nonisolated enum Field: Hashable, Sendable {
        case income
        case months
        case deduction(DeductionField)
        case spouseIncome
    }

    /// A model of `app` with the starting values, and the page for them. `wait` waits out the typing pause; a test
    /// replaces it with a wait that it ends itself.
    init(
        app: AppModel, typingDelay: Duration = .milliseconds(500),
        wait: @escaping DebounceTimer.Wait = { try await Task.sleep(for: $0) }
    ) {
        self.app = app
        self.typingDelay = typingDelay
        typingTimer = DebounceTimer(wait: wait)
        let startingYear = Self.startingYear(for: app.asOf.year)
        year = startingYear
        // The rate of a year without settings, until the settings of the year are read.
        expensePercent = YearSettings(year: startingYear).expensePercent
        recompute()
    }

    // MARK: The settings of the year

    /// Reads the settings of the year as Zálohy a odpočty shows them, a year without settings of its own included: the
    /// rate they prefill, while the rate follows them. Once the year is read, its deductions and family can be copied
    /// (`copyDeductionsAndFamily()`). Nothing is written. A failure is logged (the domain and the code of the error
    /// alone) and shows `errorText`; the inputs stay as they are.
    func load() async {
        loadsStarted += 1
        let thisLoad = loadsStarted
        let shownYear = year
        do {
            guard let database = app?.database else { throw VaultError.locked }
            let settings = try await database.yearSettings(shownYear)
            guard thisLoad == loadsStarted else { return }
            canCopyDeductionsAndFamily = true
            if rateFromSettings, TaxRules.expenseCap(percent: settings.expensePercent) != nil {
                expensePercent = settings.expensePercent
            }
            errorText = nil
            recompute()
        } catch {
            guard thisLoad == loadsStarted else { return }
            AppModel.log("Reading the settings of the year of the Simulátor", failedWith: error)
            errorText = Self.readFailureText
        }
    }

    /// Makes `year` the year of the simulation at once, and then reads its settings (`load()`). A year whose rules the
    /// app does not know is not taken.
    func selectYear(_ year: Int) async {
        guard TaxRules.supportedYears.contains(year) else { return }
        if year != self.year {
            self.year = year
            // The year can be copied from once it is read.
            canCopyDeductionsAndFamily = false
            recompute()
        }
        await load()
    }

    /// "Převzít ze Záloh a odpočtů": puts the deductions of the year into their fields, with the limit on the interest
    /// and the choice of the taxpayer credit, makes the family of the year (`Database.family(year:)`) the family of the
    /// simulation, in place of the one it had, and works out the page. It is what Zálohy a odpočty shows for the year,
    /// also for a year without settings of its own: the choice of the taxpayer credit that year takes from the nearest
    /// earlier year with settings, no deductions, the children carried from the earlier years, and no spouse, since a
    /// spouse is never carried. A deduction of zero leaves its field empty, and so does the own income of a spouse who
    /// has none. The fields are read as typed ones, so a stored value no field takes shows the message of its field.
    /// Nothing is written. Does nothing until the year has been read (`canCopyDeductionsAndFamily`); a read that fails
    /// is said in `errorText` and leaves the inputs as they are.
    func copyDeductionsAndFamily() async {
        guard canCopyDeductionsAndFamily else { return }
        let loadsBefore = loadsStarted
        let shownYear = year
        do {
            guard let database = app?.database else { throw VaultError.locked }
            let settings = try await database.yearSettings(shownYear)
            let family = try await database.family(year: shownYear)
            // Another year, or starting again, has started a read of its own meanwhile: the copy is not for it.
            guard loadsStarted == loadsBefore else { return }
            for field in DeductionField.allCases {
                deductionTexts[field] = Self.text(of: field.amount(in: settings.deductions), in: field)
                unread.remove(.deduction(field))
                read(.deduction(field))
            }
            mortgageCap = settings.deductions.mortgageCap
            taxpayerCredit = settings.taxpayerCredit
            familyChildren = family.children
            familySpouse = family.spouse
            spouseIncomeText = Self.incomeText(of: family.spouse)
            spouseIncomeError = nil
            unread.remove(.spouseIncome)
            errorText = nil
            recompute()
        } catch {
            guard loadsStarted == loadsBefore else { return }
            AppModel.log("Reading the deductions and the family of the year for the Simulátor", failedWith: error)
            errorText = Self.readFailureText
        }
    }

    // MARK: Choices

    /// The flat-rate expenses: 80, 60, 40 or 30 %. Any other percentage is not taken. A rate the person picks no longer
    /// follows the settings of the year.
    func setExpensePercent(_ percent: Int) {
        guard TaxRules.expenseCap(percent: percent) != nil else { return }
        expensePercent = percent
        rateFromSettings = false
        recompute()
    }

    /// The main activity, or a secondary one.
    func setActivity(_ activity: SimulatorActivity) {
        self.activity = activity
        recompute()
    }

    /// Whether a secondary activity is exempt from the health minimum for the whole of its months, because the person
    /// is also employed with insurance from at least the minimum wage, studies, receives a pension, is on parental
    /// leave, has a ZTP/P card or the like then (`healthMinimumExempt`).
    func setHealthMinimumExempt(_ on: Bool) {
        healthMinimumExempt = on
        recompute()
    }

    /// Whether the taxpayer credit is claimed.
    func setTaxpayerCredit(_ on: Bool) {
        taxpayerCredit = on
        recompute()
    }

    /// The limit on the interest: for housing acquired before 1. 1. 2021, or later.
    func setMortgageCap(_ cap: MortgageCap) {
        mortgageCap = cap
        recompute()
    }

    // MARK: Typed text

    /// The income has been typed in. This records the text and starts the wait again, nothing more: the text is read
    /// when the typing stops (see above), so it never has a message, nor changes the page, key by key.
    func setIncomeText(_ text: String) {
        incomeText = text
        typed(.income)
    }

    /// The months of the activity have been typed in. Like the income, the text is read when the typing stops.
    func setMonthsText(_ text: String) {
        monthsText = text
        typed(.months)
    }

    /// A field of the deductions has been typed in. Like the income, the text is read when the typing stops.
    func setDeductionText(_ field: DeductionField, _ text: String) {
        deductionTexts[field] = text
        typed(.deduction(field))
    }

    /// Reads the texts that were typed and not read yet, now that the typing has stopped: Return, leaving a field, or
    /// the end of the wait. A text that stands for a value makes it the value of its field, and the page is worked out
    /// again; any other text keeps its place in the field with the message under it, and the field keeps its value.
    func readTypedTexts() {
        typingTimer.cancel()
        guard !unread.isEmpty else { return }
        let fields = unread
        unread = []
        for field in fields {
            read(field)
        }
        recompute()
    }

    /// Marks `field` as typed and not read, and starts the wait again.
    private func typed(_ field: Field) {
        unread.insert(field)
        typingTimer.restart(after: typingDelay) { [weak self] in
            self?.readTypedTexts()
        }
    }

    /// Reads the text of `field`: the value it stands for becomes the value of the field, and a text that stands for
    /// none gets the message of the field.
    private func read(_ field: Field) {
        switch field {
        case .income:
            switch TypedKc(incomeText) {
            case .blank:
                incomeKc = 0
                incomeError = nil
            case .value(let kc):
                incomeKc = kc
                incomeError = nil
            case .refused:
                incomeError = AdvancesModel.wholeKcMessage
            }
        case .months:
            if let months = Self.activityMonths(in: monthsText) {
                activityMonths = months
                monthsError = nil
            } else {
                monthsError = Self.activityMonthsMessage
            }
        case .deduction(let deduction):
            if let value = deduction.value(of: deductionTexts[deduction] ?? "") {
                deduction.set(value, in: &typedDeductions)
                deductionErrors[deduction] = nil
            } else {
                deductionErrors[deduction] =
                    deduction.isMonthCount ? AdvancesModel.monthsMessage : AdvancesModel.wholeKcMessage
            }
        case .spouseIncome:
            switch TypedKc(spouseIncomeText) {
            case .blank:
                familySpouse?.ownIncomeKc = 0
                spouseIncomeError = nil
            case .value(let kc):
                familySpouse?.ownIncomeKc = kc
                spouseIncomeError = nil
            case .refused:
                spouseIncomeError = AdvancesModel.wholeKcMessage
            }
        }
    }

    // MARK: Starting again

    /// "Začít znovu": every input goes back to where a simulation starts — the year the app shows (or the nearest one
    /// with rules) with the rate of its settings, no income, the main activity for twelve months and no exemption from
    /// the health minimum, no deductions with twelve months of interest under the limit of 150 000 Kč, the taxpayer
    /// credit, and no family — and what was being typed goes with it. Then the settings of the year are read
    /// (`load()`).
    func reset() async {
        typingTimer.cancel()
        unread = []
        let startingYear = Self.startingYear(for: app?.asOf.year ?? year)
        if startingYear != year {
            year = startingYear
            canCopyDeductionsAndFamily = false
        }
        expensePercent = YearSettings(year: startingYear).expensePercent
        rateFromSettings = true
        activity = .main
        healthMinimumExempt = false
        taxpayerCredit = true
        mortgageCap = Deductions().mortgageCap
        incomeText = ""
        monthsText = Self.startingMonthsText
        deductionTexts = Self.texts(of: Deductions())
        incomeError = nil
        monthsError = nil
        deductionErrors = [:]
        incomeKc = 0
        activityMonths = Self.startingMonths
        typedDeductions = Deductions()
        familyChildren = []
        familySpouse = nil
        spouseIncomeText = ""
        spouseIncomeError = nil
        recompute()
        await load()
    }

    // MARK: Computing

    /// Works out the page for the values that were taken: the whole year, as of its last day. A computation that
    /// refuses them is logged and leaves no page.
    private func recompute() {
        var deductions = typedDeductions
        deductions.mortgageCap = mortgageCap
        let choices = SimulatorInput(
            year: year, incomeKc: incomeKc, expensePercent: expensePercent, activity: activity,
            healthMinimumExempt: healthMinimumExempt, months: activityMonths, deductions: deductions,
            taxpayerCredit: taxpayerCredit, family: simulatedFamily)
        do {
            guard let lastDay = CivilDate(year: year, month: 12, day: 31) else {
                throw ComputationError.invalidYear(year)
            }
            let result = try AppModel.compute(SimulatorBuilder.input(choices), asOf: lastDay)
            let worked = SimulatorBuilder.page(result, choices: choices, rateFromSettings: rateFromSettings)
            if worked != page {
                page = worked
            }
        } catch {
            AppModel.log("Computing a simulation", failedWith: error)
            page = nil
        }
    }

    // MARK: Texts of the fields

    /// The months of the activity a simulation starts with.
    private static let startingMonths = 12
    private static let startingMonthsText = String(startingMonths)

    /// A deduction as its field shows it: nothing for zero, the months of interest as a number, and crowns with the
    /// thousands separated.
    private static func text(of value: Int64, in field: DeductionField) -> String {
        if value == 0 {
            return ""
        }
        return field.isMonthCount ? String(value) : CzechFormat.grouped(value)
    }

    /// The texts of the fields of the deductions for `deductions`.
    private static func texts(of deductions: Deductions) -> [DeductionField: String] {
        Dictionary(
            uniqueKeysWithValues: DeductionField.allCases.map { field in
                (field, text(of: field.amount(in: deductions), in: field))
            })
    }

    /// The field of the own income of `spouse` as it shows it: nothing for no income, as a deduction of nothing, and
    /// otherwise the crowns with the thousands separated.
    private static func incomeText(of spouse: SpouseYear?) -> String {
        guard let income = spouse?.ownIncomeKc, income != 0 else { return "" }
        return CzechFormat.grouped(income)
    }

    /// The months of the activity in `text`: 1 to 12; nil for anything else, nothing at all too, which counts as no
    /// month.
    private static func activityMonths(in text: String) -> Int? {
        guard let number = AmountParser.decimal(text, maxFractionDigits: 0), (1...12).contains(number) else {
            return nil
        }
        return NSDecimalNumber(decimal: number).intValue
    }
}

// MARK: - The family

extension SimulatorModel: FamilyEditing {
    /// The family of the simulation, as a family of the year simulated: its children, listed as
    /// `Database.family(year:)` lists those of a year, and its spouse. Never nil; a simulation without a family has an
    /// empty one.
    var family: FamilyYear? {
        simulatedFamily
    }

    /// The family of the simulation, as the computation takes it.
    private var simulatedFamily: FamilyYear {
        FamilyYear(year: year, children: familyChildren, spouse: familySpouse)
    }

    /// The field of the spouse's own income has been typed in. Like the income, the text is read when the typing stops:
    /// an amount in whole Kč, or nothing for no income, becomes the income of the spouse, and the page is worked out
    /// again; any other text stays in the field with the message under it, and the income keeps its value. A simulation
    /// without a spouse has no such field.
    func setSpouseIncomeText(_ text: String) {
        guard familySpouse != nil else { return }
        spouseIncomeText = text
        typed(.spouseIncome)
    }

    /// Puts `child` and what the year says about it into the simulation, a child with `id` nil as a new one with an id
    /// of its own, gives the other children the orders of `otherOrders` in the same change, and works out the page.
    /// Nothing is stored. Throws `FamilyEditingError.refused` and changes nothing when an entry of `otherOrders` cannot
    /// apply, for a child that is not among the other children, for this child, or an order below 1, or when the
    /// engine would not take the child, as one write of the data does. A child with an id that is not in the simulation
    /// is added with it, as the data adds one.
    func saveChild(_ child: Child, childYear: ChildYear, otherOrders: [Int64: Int]) async throws {
        let id = child.id ?? nextChildID
        var children = try Self.ordering(
            familyChildren.filter { $0.child.id != id }, by: otherOrders, besides: id)
        children.append(
            FamilyChild(
                child: Child(id: id, name: child.name, birthDate: child.birthDate), year: childYear, isStored: true))
        try take(children)
        largestChildID = max(largestChildID, id)
    }

    /// Takes the child with `id` out of the simulation, gives the other children the orders of `otherOrders` in the
    /// same change, and works out the page. Nothing is stored. Throws `FamilyEditingError.refused` and changes nothing
    /// when an entry of `otherOrders` cannot apply: for a child that is not among the others, for the child taken out,
    /// or an order below 1.
    func removeChild(id: Int64, otherOrders: [Int64: Int]) async throws {
        try take(Self.ordering(familyChildren.filter { $0.child.id != id }, by: otherOrders, besides: id))
    }

    /// Makes `spouse` the spouse of the simulation, nil for none, and works out the page. Nothing is stored. A spouse
    /// the engine would not take (a range of months that is not one, an income below zero) is refused with
    /// `FamilyEditingError.refused`, and nothing changes. The field of the income keeps what is typed in it; without a
    /// spouse it goes.
    func setSpouse(_ spouse: SpouseYear?) async throws {
        guard FamilyFacts(spouse: spouse).isValid else {
            throw FamilyEditingError.refused
        }
        familySpouse = spouse
        if spouse == nil {
            spouseIncomeText = ""
            spouseIncomeError = nil
            unread.remove(.spouseIncome)
        }
        recompute()
    }

    /// An id for a child added in the simulation: larger than any a child of the simulation has had, so that it is its
    /// own and the child comes after those born the same day, as the child saved last does in the data.
    private var nextChildID: Int64 {
        max(largestChildID, familyChildren.compactMap(\.child.id).max() ?? 0) + 1
    }

    /// Makes `children` the children of the simulation, listed as `Database.family(year:)` lists them, and works out
    /// the page. Throws `FamilyEditingError.refused`, and changes nothing, when the engine would not take them: a range
    /// of months that is not one, or an order below 1.
    private func take(_ children: [FamilyChild]) throws {
        let listed = children.sorted { first, second in
            (first.child.birthDate, first.child.id ?? Int64.max)
                < (second.child.birthDate, second.child.id ?? Int64.max)
        }
        guard FamilyFacts(children: listed.map { ChildFacts($0) }).isValid else {
            throw FamilyEditingError.refused
        }
        familyChildren = listed
        recompute()
    }

    /// `children` with the orders of `orders` given to them by id, all or none, as one change of the family gives them:
    /// an entry that cannot apply — for a child that is not among `children`, for the child with id `excluded`, which
    /// the change saves or removes, or an order below 1 — throws `FamilyEditingError.refused`, and then the simulation
    /// gets none of them. A child given an order has what the year says about it as its own, as in the data.
    private static func ordering(
        _ children: [FamilyChild], by orders: [Int64: Int], besides excluded: Int64
    ) throws -> [FamilyChild] {
        var ordered = children
        for (id, order) in orders {
            guard id != excluded, order >= 1, let index = ordered.firstIndex(where: { $0.child.id == id }) else {
                throw FamilyEditingError.refused
            }
            ordered[index].year.order = order
            ordered[index].isStored = true
        }
        return ordered
    }
}
