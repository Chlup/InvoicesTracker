import Foundation

/// The statements that read what a prediction is made from. They are conditions of `InvoiceQueries`, so the invoices
/// come with their items and payments as the lists have them.
nonisolated enum PredictionQueries {
    /// The invoices a prediction of a year is made from: the issued ones of every year, and the drafts issued between
    /// two days, both included. An invoice with a review flag is among them, and a draft issued on any other day is
    /// not. It looks at all years, so it reads the whole table of invoices. Arguments: the first day, the last day.
    static let invoices = """
        (invoice.status = '\(InvoiceStatus.issued.rawValue)'
            OR (invoice.status = '\(InvoiceStatus.draft.rawValue)' AND invoice.issue_date BETWEEN ? AND ?))
        """
}

extension Database {
    /// The invoices the prediction of `year` is made from, with their items and payments, in the order of the lists
    /// (`invoices(scope:year:asOf:)`): every issued invoice of every year, and the drafts issued in `year`. A client's
    /// rhythm comes from its whole history, and an invoice of an earlier year may still be unpaid, or be paid in a
    /// later one, so the issued invoices are not cut to a year.
    ///
    /// An invoice with a review flag is loaded like any other: the prediction leaves it out itself, as the receipts of
    /// the tax computation do (`receipts(year:)`). A year outside the calendar has none.
    func predictionInvoices(year: Int) throws -> [Invoice] {
        guard let period = Period(year: year) else { return [] }
        return try read { connection in
            try Invoice.load(where: PredictionQueries.invoices, period.arguments, in: connection)
        }
    }
}
