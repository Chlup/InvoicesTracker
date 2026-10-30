import Foundation
import Observation

/// What the dialog of a child says it comes to in the year, as the fields are now.
nonisolated struct ChildDialogResult: Sendable, Hashable {
    var text: String

    /// Whether the child counts in a month of the year; a result that it does not is a warning.
    var counts: Bool
}

/// The dialog of a child, "Nové dítě" or "Upravit dítě": the name and the date of birth, which are the child's in every
/// year, and what the year shown says about it — the months in the household or none, who claims it, its order in the
/// household, and the months of ZTP/P and of studies. Nothing is written until Uložit dítě; Zrušit throws the edit
/// away.
///
/// - What the child comes to in the year is said as the fields change (`liveResult`): the engine's figures for the
///   family of the year with the child as the fields say.
/// - The order is the child's place among the children of the year, 1 to their number. Taking a place moves the
///   children from that place on one down, and a save or a removal writes the order of every other child of the year
///   that changes, so that the orders of the year stay 1 to their number without a gap or a tie. A child without a row
///   of its own for the year gets one with its order, so that its order stays what the year shows when the children
///   of the year change.
/// - In Zálohy a odpočty the child is removed from every year after a question in a red box in place of the buttons;
///   in the Simulátor, where nothing is stored, at once. The Simulátor's dialog says that nothing is stored.
/// - A save or a removal is one change of the family (`FamilyEditing`), with the orders of the other children. One
///   that is not made keeps the dialog open with what is typed in it, says so (`failure`), and changes nothing.
@MainActor
@Observable
final class ChildDialogModel {
    // MARK: Texts

    nonisolated static let birthDateMissing = "Vyplňte datum narození."

    /// A save or a removal that was not made.
    nonisolated static let saveFailed = "Dítě se nepodařilo uložit."
    nonisolated static let removeFailed = "Dítě se nepodařilo odebrat."
    nonisolated static let birthDateUnreadable = "Datum narození zadejte ve tvaru 3.\u{00A0}9.\u{00A0}2019."
    nonisolated static let monthsOutOfOrder = "Měsíc „od“ musí být před měsícem „do“."
    nonisolated static let ztppMonthsOutOfOrder = "U průkazu ZTP/P musí být měsíc „od“ před měsícem „do“."

    /// What the field of the date of birth shows while it is empty.
    nonisolated static let birthDatePrompt = "např. 3.\u{00A0}9.\u{00A0}2019"

    /// Under "Pořadí v domácnosti".
    nonisolated static let orderNote =
        "Určuje sazbu. V měsíci, kdy dítě s nižším pořadím podmínky nesplňuje, se ostatní posunou."

    /// Under the studies.
    nonisolated static let studiesNote =
        "Soustavná příprava na povolání do 26 let – nebo se připravovat nemůže kvůli nemoci či úrazu. Počítají se i"
        + " prázdniny po maturitě, když v témže roce nastoupí na vysokou, a měsíc po ukončení studia, pokud v něm"
        + " nepracuje."

    /// The title of the question before a stored child is removed.
    nonisolated static let removalTitle = "Odebrat dítě ze všech let?"

    /// In Zálohy a odpočty, a date of birth after `year`: the year has no row for a child born after it.
    nonisolated static func birthDateAfter(_ year: Int) -> String {
        "Datum narození musí být nejpozději v roce \(year)."
    }

    /// What removing a stored child does, and what to do instead when it only stopped living with the person.
    nonisolated static func removalMessage(year: Int) -> String {
        "Zmizí i z výpočtu minulých let. Pokud s vámi jen přestalo žít, zaškrtněte místo toho „V roce \(year) s vámi"
            + " nežije“."
    }

    // MARK: What the dialog is for

    /// The year whose family the dialog edits.
    let year: Int

    let mode: FamilyCardsMode

    /// The child as the dialog was opened on it, nil for a new one.
    let child: FamilyChild?

    private let editing: any FamilyEditing

    // MARK: What is typed and chosen

    /// Every change of a field takes away the message of what was wrong.
    var name: String {
        didSet { error = nil }
    }

    /// The date of birth as typed: "3. 9. 2019".
    var birthDateText: String {
        didSet { error = nil }
    }

    /// Whether the child does not live in the household in the year: "V roce Y s vámi nežije". The months in the
    /// household are not asked for then.
    var livesApart: Bool {
        didSet { error = nil }
    }

    /// The months in the household, 1 to 12.
    var householdFrom: Int {
        didSet { error = nil }
    }

    var householdTo: Int {
        didSet { error = nil }
    }

    var claimant: Claimant {
        didSet { error = nil }
    }

    /// The place of the child in the order of the household, 1 to `orderCount`.
    var order: Int {
        didSet { error = nil }
    }

    var hasZTPP: Bool {
        didSet { error = nil }
    }

    var ztppFrom: Int {
        didSet { error = nil }
    }

    var ztppTo: Int {
        didSet { error = nil }
    }

    /// Whether the child studies after its 18th birthday, and in which months. Asked only while `showsStudies`.
    var studies: Bool {
        didSet { error = nil }
    }

    var studiesFrom: Int {
        didSet { error = nil }
    }

    var studiesTo: Int {
        didSet { error = nil }
    }

    // MARK: What happened

    /// What is wrong with the fields, said after Uložit dítě until a field changes.
    private(set) var error: String?

    /// What went wrong with the last save or removal, until the next one: the change was not made.
    private(set) var failure: String?

    /// Whether the dialog asks, in a red box in place of its buttons, before a stored child is removed.
    private(set) var confirmsRemoval = false

    /// Whether a save or a removal runs. A second one is not started.
    private(set) var isWorking = false

    /// The dialog of `child` of the family of `year` that `editing` holds, or of a new child for nil. A child opens
    /// with what the year says about it, and at its place among the children of the year; a new child in the household
    /// the whole year, claimed by me, after the children of the year.
    init(editing: any FamilyEditing, year: Int, child: FamilyChild?, mode: FamilyCardsMode) {
        self.editing = editing
        self.year = year
        self.child = child
        self.mode = mode
        let children = Self.ranked(editing.family?.children ?? [])
        if let child {
            name = child.child.name
            birthDateText = CzechFormat.date(child.child.birthDate)
            livesApart = child.year.household == nil
            householdFrom = child.year.household?.from ?? 1
            householdTo = child.year.household?.to ?? 12
            claimant = child.year.claimant
            let place = children.firstIndex { Self.isSame($0, as: child) } ?? children.count
            order = min(place + 1, max(children.count, 1))
            hasZTPP = child.year.ztpp != nil
            ztppFrom = child.year.ztpp?.from ?? 1
            ztppTo = child.year.ztpp?.to ?? 12
            studies = child.year.studies != nil
            studiesFrom = child.year.studies?.from ?? 1
            studiesTo = child.year.studies?.to ?? 12
        } else {
            name = ""
            birthDateText = ""
            livesApart = false
            householdFrom = 1
            householdTo = 12
            claimant = .me
            order = children.count + 1
            hasZTPP = false
            ztppFrom = 1
            ztppTo = 12
            studies = false
            studiesFrom = 1
            studiesTo = 12
        }
    }

    // MARK: The sheet

    var isNew: Bool {
        child == nil
    }

    var title: String {
        (isNew ? "Nové dítě" : "Upravit dítě") + (mode == .simulation ? " v simulaci" : "")
    }

    var subtitle: String {
        if mode == .simulation {
            return "Jen pro simulaci roku \(year) – nic se neukládá"
        }
        guard let child else { return "Dítě, které s vámi žije ve společné domácnosti" }
        return (child.child.name.isEmpty ? "Dítě" : child.child.name) + " · rok \(year)"
    }

    /// "Ve společné domácnosti v roce 2026".
    var householdTitle: String {
        "Ve společné domácnosti v roce \(year)"
    }

    /// "V roce 2026 s vámi nežije".
    var livesApartTitle: String {
        "V roce \(year) s vámi nežije"
    }

    /// How many places the order has: the children of the year, this one among them.
    var orderCount: Int {
        others.count + 1
    }

    /// Whether the dialog asks before it removes the child: in Zálohy a odpočty, where it goes from every stored year.
    var asksBeforeRemoving: Bool {
        mode == .stored
    }

    /// The date of birth that is typed, or nil while it is not one.
    var birthDate: CivilDate? {
        Self.date(from: birthDateText)
    }

    /// Whether the studies are asked about: for a child that is an adult on the 1st of a month of the year and not 26
    /// on 1 January, a birthday on the 1st of a month being reached that day, as the engine has it.
    var showsStudies: Bool {
        guard let born = birthDate else { return false }
        let adultBeforeTheYearEnds = (born.year + 18, born.month, born.day) <= (year, 12, 1)
        let not26OnNewYear = (born.year + 26, born.month, born.day) > (year, 1, 1)
        return adultBeforeTheYearEnds && not26OnNewYear
    }

    /// What the child comes to in the year as the fields are: the engine's figures for the children of the year with
    /// this one as the fields say and in the order it takes. Nil while the date of birth or the months are not right.
    var liveResult: ChildDialogResult? {
        guard let born = birthDate, monthsProblem == nil else { return nil }
        let edited = FamilyChild(child: editedChild(born: born), year: editedChildYear, isStored: true)
        // The children as the family lists them: by the date of birth, then by id, a new child after those born the
        // same day. The engine settles a tie of the orders by that place; after the reorder there is none.
        let listed = (othersInOrder(placing: order).map { $0.member } + [edited]).enumerated().sorted { first, second in
            (first.element.child.birthDate, first.element.child.id ?? Int64.max, first.offset)
                < (second.element.child.birthDate, second.element.child.id ?? Int64.max, second.offset)
        }
        guard let place = listed.firstIndex(where: { $0.offset == listed.count - 1 }) else { return nil }
        let credits = FamilyCredits.evaluate(
            FamilyFacts(children: listed.map { ChildFacts($0.element) }), year: year,
            rules: TaxRules.forYear(year).rules)
        return Self.result(of: credits.children[place], year: year)
    }

    /// What `credit` comes to in `year`, in words.
    private static func result(of credit: ChildCredit, year: Int) -> ChildDialogResult {
        let months = credit.monthsByRate.values.reduce(0, +)
        if credit.ineligibility != nil || months == 0 {
            return ChildDialogResult(
                text: "V roce \(year) nesplňuje podmínky – zvýhodnění se neuplatní.", counts: false)
        }
        if credit.claimedByOther {
            return ChildDialogResult(
                text: "V roce \(year): \(ComputationBuilder.months(months)) · uplatňuje druhý rodič, ve vašem výpočtu"
                    + " se nepočítá.",
                counts: true)
        }
        let rates = credit.monthsByRate.keys.sorted().map { rate in
            ComputationBuilder.months(credit.monthsByRate[rate] ?? 0) + " jako " + FamilyCardsBuilder.rateName(rate)
        }
        return ChildDialogResult(
            text: "V roce \(year): " + rates.joined(separator: ", ")
                + (credit.ztppMonths > 0 ? " (se ZTP/P dvojnásobek)" : "") + " · " + CzechFormat.wholeKc(credit.amount),
            counts: true)
    }

    // MARK: Saving and removing

    /// Uložit dítě: saves the child and its year together with the order of each other child of the year whose order
    /// changes or which has no row of its own for the year, as one change. Returns whether it was made. When a field is
    /// not right, `error` says what and nothing is saved; when the change is not made, `failure` says so, and nothing
    /// of it is.
    func save() async -> Bool {
        guard !isWorking else { return false }
        if let problem = birthDateProblem ?? monthsProblem {
            error = problem
            return false
        }
        guard let born = birthDate else { return false }
        isWorking = true
        failure = nil
        defer { isWorking = false }
        do {
            try await editing.saveChild(
                editedChild(born: born), childYear: editedChildYear, otherOrders: otherOrders(placing: order))
        } catch {
            failure = Self.failureText(for: error, otherwise: Self.saveFailed)
            return false
        }
        return true
    }

    /// Odebrat dítě, in Zálohy a odpočty: the dialog asks first.
    func askToRemove() {
        guard !isNew, !isWorking else { return }
        confirmsRemoval = true
    }

    /// Zrušit in the box: nothing is removed, and the buttons are back.
    func cancelRemoval() {
        confirmsRemoval = false
    }

    /// Removes the child from every year together with the order without the gap of each other child of the year whose
    /// order changes, or which has no row of its own for the year, as one change. Returns whether it was made; when it
    /// is not, `failure` says so, the child is still there and no order changes.
    func remove() async -> Bool {
        confirmsRemoval = false
        guard !isWorking, let id = child?.child.id else { return false }
        isWorking = true
        failure = nil
        defer { isWorking = false }
        do {
            try await editing.removeChild(id: id, otherOrders: otherOrders(placing: nil))
        } catch {
            failure = Self.failureText(for: error, otherwise: Self.removeFailed)
            return false
        }
        return true
    }

    /// What the dialog says when a change was not made because of `error`: that the data is locked, or `otherwise`.
    private static func failureText(for error: any Error, otherwise: String) -> String {
        error as? VaultError == .locked ? WelcomeTexts.vaultErrorText(.locked) : otherwise
    }

    // MARK: What is wrong

    /// What is wrong with the date of birth: none is typed, it is not a date, or, in Zálohy a odpočty, it is after the
    /// year. Nil when it is right.
    private var birthDateProblem: String? {
        if FormInput.trimmed(birthDateText).isEmpty {
            return Self.birthDateMissing
        }
        guard let born = birthDate else { return Self.birthDateUnreadable }
        if mode == .stored && born.year > year {
            return Self.birthDateAfter(year)
        }
        return nil
    }

    /// What is wrong with the months: a range that is asked for and does not run forward. Nil when they are right.
    private var monthsProblem: String? {
        if !livesApart && !MonthRange(from: householdFrom, to: householdTo).isValid {
            return Self.monthsOutOfOrder
        }
        if hasZTPP && !MonthRange(from: ztppFrom, to: ztppTo).isValid {
            return Self.ztppMonthsOutOfOrder
        }
        if showsStudies && studies && !MonthRange(from: studiesFrom, to: studiesTo).isValid {
            return Self.monthsOutOfOrder
        }
        return nil
    }

    // MARK: The child as the fields say

    private func editedChild(born: CivilDate) -> Child {
        Child(id: child?.child.id, name: FormInput.trimmed(name), birthDate: born)
    }

    /// What the year says about the child as the fields say: the studies only while they are asked about.
    private var editedChildYear: ChildYear {
        ChildYear(
            household: livesApart ? nil : MonthRange(from: householdFrom, to: householdTo), claimant: claimant,
            order: order, ztpp: hasZTPP ? MonthRange(from: ztppFrom, to: ztppTo) : nil,
            studies: showsStudies && studies ? MonthRange(from: studiesFrom, to: studiesTo) : nil)
    }

    // MARK: The order

    /// The other children of the year, in the order the engine ranks them: by their order, then the older first, then
    /// by id.
    private var others: [FamilyChild] {
        let children = editing.family?.children ?? []
        guard let child else { return Self.ranked(children) }
        return Self.ranked(children.filter { !Self.isSame($0, as: child) })
    }

    /// The other children of the year with the orders they have once this child is at `place`, or is gone for nil: 1
    /// to their number with this one, in the order they had. Each says whether it has to be written: its order changes,
    /// or it has no row of its own for the year, whose order would follow the children of the year.
    private func othersInOrder(placing place: Int?) -> [(member: FamilyChild, mustBeWritten: Bool)] {
        let others = self.others
        let slot = place.map { min(max($0 - 1, 0), others.count) }
        return others.enumerated().map { index, member in
            var moved = member
            moved.year.order = index + 1 + (slot.map { index >= $0 ? 1 : 0 } ?? 0)
            return (member: moved, mustBeWritten: moved.year.order != member.year.order || !member.isStored)
        }
    }

    /// The orders of `othersInOrder(placing:)` that have to be written, by the ids of the children.
    private func otherOrders(placing place: Int?) -> [Int64: Int] {
        var orders: [Int64: Int] = [:]
        for (member, mustBeWritten) in othersInOrder(placing: place) where mustBeWritten {
            if let id = member.child.id {
                orders[id] = member.year.order
            }
        }
        return orders
    }

    /// `children` ranked as the engine ranks them: by their order, then the older first, then by id.
    private static func ranked(_ children: [FamilyChild]) -> [FamilyChild] {
        children.sorted { first, second in
            (first.year.order, first.child.birthDate, first.child.id ?? Int64.max)
                < (second.year.order, second.child.birthDate, second.child.id ?? Int64.max)
        }
    }

    /// Whether `member` is `child`: the child with its id, or one without an id that is the same.
    private static func isSame(_ member: FamilyChild, as child: FamilyChild) -> Bool {
        if let id = child.child.id {
            return member.child.id == id
        }
        return member == child
    }

    // MARK: Reading a date

    /// The date that `text` writes as Czech does: the day, the month and the year, the first two each followed by a
    /// dot, with spaces or without ("3. 9. 2019", "03.09.2019"), and a dot after the year too. Nil for any other text,
    /// a year of other than four digits and a day that does not exist.
    nonisolated static func date(from text: String) -> CivilDate? {
        var parts = text.filter { !$0.isWhitespace }.split(separator: ".", omittingEmptySubsequences: false)
        if parts.count == 4 && parts[3].isEmpty {
            parts.removeLast()
        }
        guard parts.count == 3, (1...2).contains(parts[0].count), (1...2).contains(parts[1].count),
            parts[2].count == 4,
            parts.allSatisfy({ $0.allSatisfy { $0.isASCII && $0.isNumber } }),
            let day = Int(parts[0]), let month = Int(parts[1]), let year = Int(parts[2])
        else {
            return nil
        }
        return CivilDate(year: year, month: month, day: day)
    }
}

extension ChildDialogModel: Identifiable {
    /// The sheet is the sheet of one dialog.
    nonisolated var id: ObjectIdentifier {
        ObjectIdentifier(self)
    }
}
