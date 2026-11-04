import Foundation

extension Database {
    /// The invoices a budget of `year` can be made from, as of `asOf`: those paid in the year on or before `asOf`, and
    /// those issued in the year that have no payment yet. Only an invoice that counts as income
    /// (`InvoiceDetailBuilder.countsAsIncome(_:)`: issued, without a review flag) is listed, each once, newest first by
    /// the day of issue, then by the digits of the number.
    ///
    /// An invoice paid in a later year is only in the list of that year. One with a payment dated after `asOf` is in
    /// neither: it is not unpaid, and its money has not come.
    func budgetInvoices(year: Int, asOf: CivilDate) throws -> [Invoice] {
        let paid = try invoices(scope: .paid, year: year, asOf: asOf)
        let unpaid = try invoices(scope: .issued, year: year, asOf: asOf).filter { $0.payment == nil }
        var seen = Set<Int64>()
        let union = (paid + unpaid).filter { invoice in
            InvoiceDetailBuilder.countsAsIncome(invoice) && seen.insert(invoice.id).inserted
        }
        // Each list is in the order of the lists already, but their union is not.
        return union.sorted { left, right in
            if left.issueDate != right.issueDate {
                return left.issueDate > right.issueDate
            }
            return left.numberDigits > right.numberDigits
        }
    }
}
