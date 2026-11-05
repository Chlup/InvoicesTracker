import Foundation
@testable import InvoicesTracker

extension OverviewData {
    /// The row of the calculation of the card Příjmy whose label is `label`, such as "Odvody", or nil where the
    /// calculation has no such row.
    func calculationRow(_ label: String) -> BillRow? {
        calculation.first { $0.label == label }
    }

    /// The row of the calculation that says what the income of the year so far leaves after the levies, "Čistý
    /// příjem", or nil where the calculation has none.
    var netIncomeRow: BillRow? {
        calculationRow("Čistý příjem")
    }

    /// The row of the calculation that says the net income per month, "Průměrně za měsíc", which Rozpočet takes as its
    /// Skutečnost, or nil where the calculation has none.
    var averageRow: BillRow? {
        calculationRow("Průměrně za měsíc")
    }
}
