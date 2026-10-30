import Foundation

/// What a client has done in a year, for its row in Odběratelé.
nonisolated struct ClientFigures: Sendable, Hashable {
    /// How many invoices of the client were issued in the year up to the day shown. A draft is not issued; an invoice
    /// held for review is.
    var invoiceCount: Int

    /// The money received in the year up to the day shown, without VAT, in haléře: the payments of the invoices of the
    /// client that count as income, those that are issued and have no review flag.
    var receivedHalere: Int64

    /// The day the last of those invoices was issued, or nil when the client has none in the year up to the day shown
    /// (money that arrived in the year for an invoice of an earlier one gives figures with no invoice).
    var lastIssueDate: CivilDate?
}

/// The statements that read the figures of the clients. Both find their rows by a day, in an index, so they cost the
/// same with one year of invoices stored and with ten.
nonisolated enum ClientQueries {
    /// The clients, how many invoices that are not drafts each was issued between two days, both included, and the day
    /// the last of them was issued. Columns: the id of the client, the count, the day. Arguments: the first day, the
    /// last day.
    static let issuedInvoices = """
        SELECT client_id, count(*), max(issue_date) FROM invoice
        WHERE issue_date BETWEEN ? AND ? AND status <> '\(InvoiceStatus.draft.rawValue)' AND client_id IS NOT NULL
        GROUP BY client_id
        """

    /// The clients and the sum of the payments without VAT, in haléře, dated between two days, both included, of their
    /// invoices that are issued and have no review flag (those the receipts of the tax computation are made of).
    /// Columns: the id of the client, the sum. Arguments: the first day, the last day.
    static let receivedMoney = """
        SELECT invoice.client_id, sum(payment.czk_net_halere) FROM payment
        JOIN invoice ON invoice.id = payment.invoice_id
        WHERE payment.date BETWEEN ? AND ?
          AND invoice.status = '\(InvoiceStatus.issued.rawValue)' AND invoice.review_reason IS NULL
          AND invoice.client_id IS NOT NULL
        GROUP BY invoice.client_id
        """
}

extension Database {
    /// What each client has done in `year`, as of the day `asOf`, by the id of the client: the invoices issued in the
    /// year up to that day, with the day of the last one, and the money received in it up to `receivedThrough`, which
    /// is `asOf` unless it is given: the reporting cutoff reaches the end of the month, but the money counts only up to
    /// today. An invoice issued after the day shown, and a payment after the day it is received by, have not happened
    /// yet. A client with neither is not in the answer, and an invoice without a client belongs to no one. A year
    /// outside the calendar has no figures.
    func clientFigures(
        year: Int, asOf: CivilDate, receivedThrough: CivilDate? = nil
    ) throws -> [Int64: ClientFigures] {
        guard let period = Period(year: year) else { return [:] }
        return try read { connection in
            // BETWEEN finds nothing when the day shown is before the year.
            let byDay = [SQLValue.day(period.first), .day(min(period.last, asOf))]
            let moneyByDay = [SQLValue.day(period.first), .day(min(period.last, asOf, receivedThrough ?? asOf))]
            var figures: [Int64: ClientFigures] = [:]
            for row in try connection.query(ClientQueries.issuedInvoices, byDay) {
                figures[row.int64(0)] = try ClientFigures(
                    invoiceCount: row.int(1), receivedHalere: 0, lastIssueDate: row.day(2))
            }
            for row in try connection.query(ClientQueries.receivedMoney, moneyByDay) {
                figures[row.int64(0), default: ClientFigures(invoiceCount: 0, receivedHalere: 0, lastIssueDate: nil)]
                    .receivedHalere = row.int64(1)
            }
            return figures
        }
    }
}
