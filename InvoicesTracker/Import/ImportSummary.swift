import Foundation

/// What an import did, for the Import screen to show and for the import log to keep (as JSON).
///
/// It holds numbers and the lines that go with them, and it holds no amounts. A line is a number of an invoice and
/// what became of it: "20260902 — změněno v aplikaci — ponecháno".
nonisolated struct ImportSummary: Codable, Sendable, Hashable {
    /// The names of the files.
    var files: [String] = []

    /// Invoices added.
    var added = 0

    /// Invoices replaced by the changed row of the export.
    var updated = 0

    /// Rows whose invoice is there as the row has it.
    var unchanged = 0

    /// Proforma invoices and cancelled invoices that were not imported.
    var skipped = 0

    /// Invoices added or updated as "ke kontrole": not counted in income until they are resolved.
    var needsReview = 0

    /// Rows not applied because the invoice was changed in the app.
    var keptChangedInApp = 0

    /// Rows that could not be added: the number is taken by an invoice of the app, to name one.
    var conflicts = 0

    /// Invoices imported earlier that are cancelled in Fakturoid now and are held for review, not counted.
    var flaggedCancelled = 0

    /// Clients made by the import.
    var newClients = 0

    /// Clients that were there and had fields filled.
    var filledClients = 0

    /// The invoices to check (see `needsReview` and `flaggedCancelled`) and the notes on countries that are no codes.
    var reviewItems: [String] = []

    /// The rows kept as the app has them.
    var keptItems: [String] = []

    /// The rows that could not be added.
    var conflictItems: [String] = []

    /// The supplier the export prints in its "Your …" columns, taken from the first row, for the Import screen to
    /// offer to fill an empty supplier profile with. Nothing is written to the profile.
    var exportSupplier: Supplier?

    /// The newest year in which an invoice was issued that this import added, updated or flagged as cancelled in
    /// Fakturoid: the year the Import screen opens Faktury on. Nil when the import changed no invoice.
    var newestYear: Int?
}

nonisolated extension ImportSummary {
    /// The summary of an import that does what `plan` says.
    init(plan: ImportPlan, files: [String], exportSupplier: Supplier?) {
        self.init(
            files: files, added: plan.inserts.count, updated: plan.updates.count, unchanged: plan.unchanged.count,
            skipped: plan.skipped.count,
            needsReview: (plan.inserts + plan.updates).filter { $0.review != nil }.count,
            keptChangedInApp: plan.kept.count, conflicts: plan.conflicts.count,
            flaggedCancelled: plan.flaggedCancelled.count, newClients: plan.newClients.count,
            filledClients: plan.clientUpdates.count, reviewItems: plan.reviewItems, keptItems: plan.kept,
            conflictItems: plan.conflicts, exportSupplier: exportSupplier,
            newestYear: (plan.inserts + plan.updates + plan.flaggedCancelled).map(\.issueDate.year).max()
        )
    }
}
