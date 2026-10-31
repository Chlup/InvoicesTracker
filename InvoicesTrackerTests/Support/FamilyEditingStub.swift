import Foundation
@testable import InvoicesTracker

/// The family of a year for a view that only draws it: the children and the spouse it is given, and changes that it
/// takes and does not keep. The cards and the dialog of a child are drawn from the content and the model they are
/// given, and need something to edit; the tests that read their pixels need nothing to be stored.
@MainActor
final class FamilyEditingStub: FamilyEditing {
    var family: FamilyYear?

    /// A family of 2026 with `children` and `spouse`.
    init(children: [FamilyChild] = [], spouse: SpouseYear? = nil) {
        family = FamilyYear(year: 2026, children: children, spouse: spouse)
    }

    func saveChild(_ child: Child, childYear: ChildYear, otherOrders: [Int64: Int]) async throws {}

    func removeChild(id: Int64, otherOrders: [Int64: Int]) async throws {}

    func setSpouse(_ spouse: SpouseYear?) async throws {}
}
