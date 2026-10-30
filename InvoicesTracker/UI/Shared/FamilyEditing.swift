import Foundation

/// What a screen that shows the cards of the family lets the cards and the dialog of a child do with the family of the
/// year it shows. Zálohy a odpočty stores it (`AdvancesModel`); the Simulátor keeps it in memory, for the simulation
/// alone.
///
/// - `family` lists the children of the year as `Database.family(year:)` does: by the date of birth, then by id. The
///   ranking of the engine settles a tie of the orders by that place. Every child has an id: the orders of the other
///   children are given by their ids, and a child is removed by its id. The Simulátor gives the children it keeps in
///   memory ids of their own.
/// - Every change is one change, made whole or not at all. A save of a child stores the child, what the year says about
///   it and the new orders of the other children of the year together; a removal takes the child out of every year
///   together with the new orders of the others of the year. So the orders of the year never have a gap or a tie, which
///   the dialog of a child keeps (`ChildDialogModel`). An entry of `otherOrders` that cannot apply — for a child that
///   is not among the other children of the year, for the child that is saved or removed itself, or an order below 1 —
///   makes the whole change throw: nothing of it is made, not even the entries that could apply.
/// - A change that is not made throws. A change of the children leaves the family as it was then, so that the dialog
///   of the child stays open and says so. A spouse that Zálohy a odpočty cannot save waits there for its next save, and
///   `family` shows it so (`setSpouse`); a spouse that is refused leaves the family as it was. What is thrown is the
///   cause: `VaultError.locked` while the data is locked, `FamilyEditingError` where no other error says it, or what
///   the data threw.
/// - `family` shows a change once it is made: Zálohy a odpočty once its screen has loaded again after the write, as it
///   does after every write; the Simulátor at once.
@MainActor
protocol FamilyEditing: AnyObject {
    /// The family of the year shown, or nil until it is loaded.
    var family: FamilyYear? { get }

    /// Saves `child` and what the year shown says about it, and gives each other child of the year with an id of
    /// `otherOrders` that order in the year, as one change. A child with `id` nil is a new one. A child of
    /// `otherOrders` keeps what else the year says about it; one without a row of its own for the year gets one, with
    /// the order. Throws when the change is not made; then nothing of it is.
    func saveChild(_ child: Child, childYear: ChildYear, otherOrders: [Int64: Int]) async throws

    /// Removes the child with `id` from every year, and gives each other child of the year shown with an id of
    /// `otherOrders` that order in the year, as one change. Throws when the change is not made; then the child is still
    /// there and no order changes.
    func removeChild(id: Int64, otherOrders: [Int64: Int]) async throws

    /// Makes `spouse` the spouse of the year shown, nil for none. Throws when it is not made: a spouse the engine would
    /// not take is refused (`FamilyEditingError.refused`) and changes nothing. A spouse that Zálohy a odpočty cannot
    /// save, it keeps as a change of its settings that waits for the next save, and says so next to its form, as for
    /// its other choices; the card of the spouse, which saves at once, leaves the saying to the screen.
    func setSpouse(_ spouse: SpouseYear?) async throws
}

/// Why a change of the family was not made, where no other error says it.
nonisolated enum FamilyEditingError: Error, Equatable {
    /// The change is one the engine would not take, such as a range of months that is not one.
    case refused

    /// The change was not written; the screen says why.
    case notSaved
}
