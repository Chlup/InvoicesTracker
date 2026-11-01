import Foundation

/// The unpaid invoices that the average net income per month of the current year on Přehled counts as paid: the days
/// that bound which ones they are, and the receipt each of them brings the engine. The invoices themselves are read by
/// `Database.dueUnpaidRows(issuedFrom:dueThrough:today:)`, and `OverviewModel` works out the levies of the year with
/// these receipts added (`DueNetIncome`).
nonisolated enum DueInvoices {
    /// The first day of issue of an invoice that counts: 1 January of the year before the year of `today`, the bound
    /// the estimate of the whole year has too, so an unpaid invoice of this year or of the year before is expected to
    /// be paid and an older one is not. Traps for a `today` in the year 1.
    static func issuedFrom(today: CivilDate) -> CivilDate {
        guard let day = CivilDate(year: today.year - 1, month: 1, day: 1) else {
            preconditionFailure("1 January \(today.year - 1) is not a date in the years 1 to 9999.")
        }
        return day
    }

    /// The last day an invoice that counts may be due: the last day of the month of `today`. An invoice that is overdue
    /// was due before it, so it counts as well.
    static func dueThrough(today: CivilDate) -> CivilDate {
        today.endOfMonth
    }

    /// The receipts that make the engine count the unpaid invoices in `rows` as paid on `day`, today: one for each
    /// invoice worth more than nothing, in the order of the rows. The rows are the unpaid invoices as
    /// `Database.dueUnpaidRows(issuedFrom:dueThrough:today:)` reads them: drafts and invoices held for review are
    /// already left out there. An invoice is worth what the charts count for it with the money received through `day`
    /// (`OverviewBuilder.issuedValue(of:receivedThrough:)`): its amounts as they are in crowns, otherwise its amounts
    /// at the ČNB rate of its day of issue. The receipt has the amount without VAT as the income and the VAT apart, as
    /// a payment has. An invoice worth nothing (one in another currency that has no rate, or one of no amount) brings
    /// none, so that there is nothing to count and nothing to mark as an estimate.
    static func receipts(of rows: [InvoiceChartRow], on day: CivilDate) -> [Receipt] {
        rows.compactMap { row in
            let value = OverviewBuilder.issuedValue(of: row, receivedThrough: day)
            guard value.net > 0 else { return nil }
            return Receipt(day: day, czkNetHalere: value.net, czkVatHalere: value.gross - value.net, source: .synthetic)
        }
    }
}
