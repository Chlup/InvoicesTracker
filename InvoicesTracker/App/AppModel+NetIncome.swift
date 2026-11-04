import Foundation

/// The average net income per month of the selected year, as Přehled shows it: what the money received leaves after
/// the levies, and, where Přehled counts them, the same with the unpaid invoices due by the end of the month counted as
/// paid today.
nonisolated struct AverageNetIncome: Sendable {
    /// The net income of the year as of the day the money is received by (`AppModel.receivedThrough`).
    var net: NetIncome

    /// The levies with the unpaid invoices due this month counted as paid today, or nil where no invoice counts or the
    /// year is not the current one as of today.
    var due: DueNetIncome?

    /// The average per month in whole Kč: the one with the due invoices counted when there is one, otherwise the one of
    /// the money received.
    var monthlyKc: Int64 {
        if let due {
            return NetIncome(due.result).monthlyKc
        }
        return net.monthlyKc
    }

    /// Whether the average counts the unpaid invoices due, which makes it an estimate.
    var isEstimate: Bool {
        due != nil
    }
}

extension AppModel {
    /// The average net income per month of the selected year (`asOf.year`) as of `receivedThrough`, with the unpaid
    /// invoices due this month counted exactly as Přehled counts them for the year it shows: only when that is the
    /// current year and its levies are worked out as of today. A failure of the due part is logged and leaves `due`
    /// nil; cancellation is rethrown. Throws `VaultError.locked` while the data is locked.
    func averageNetIncome() async throws -> AverageNetIncome {
        guard let database else { throw VaultError.locked }
        let year = asOf.year
        let today = self.today
        let input = try await yearInput(for: year).input
        let result = try Self.compute(input, asOf: receivedThrough)
        var due: DueNetIncome?
        if year == today.year {
            do {
                due = try await dueNetIncome(adding: input, result: result, today: today, in: database)
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                Self.log("Loading the due invoices", failedWith: error)
            }
        }
        return AverageNetIncome(net: NetIncome(result), due: due)
    }

    /// The levies of the year of `input` as of `today` with the unpaid invoices due by the end of the month counted as
    /// paid on `today`, or nil when `result` is not as of `today` or no invoice counts. The invoices are read by
    /// `Database.dueUnpaidRows(issuedFrom:dueThrough:today:)` and turned into receipts of today
    /// (`DueInvoices.receipts(of:on:)`), which are added to the receipts of `input`. `input` must be the input of the
    /// year of `result`.
    func dueNetIncome(
        adding input: YearInput, result: TaxResult, today: CivilDate, in database: Database
    ) async throws -> DueNetIncome? {
        guard result.asOf == today else { return nil }
        let dueThrough = DueInvoices.dueThrough(today: today)
        let rows = try await database.dueUnpaidRows(
            issuedFrom: DueInvoices.issuedFrom(today: today), dueThrough: dueThrough, today: today)
        let receipts = DueInvoices.receipts(of: rows, on: today)
        guard !receipts.isEmpty else { return nil }
        var counted = input
        counted.receipts += receipts
        return DueNetIncome(result: try Self.compute(counted, asOf: today), dueThrough: dueThrough)
    }
}
