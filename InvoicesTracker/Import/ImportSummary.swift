import Foundation

/// What an import did, for the Import screen to show and for the import log to keep (as JSON).
///
/// It holds numbers and the lines that go with them, and it holds no amounts. A line is a number of an invoice and
/// what became of it: "20261003 — záporná částka".
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

    /// Rows not applied because the invoice was changed in the app, as the logs of older imports say. An import
    /// overwrites what was changed in the app now, so it writes 0; the field stays so that those logs still decode.
    var keptChangedInApp = 0

    /// Invoices that could not be added: the number is taken by an invoice in another currency, to name one.
    var conflicts = 0

    /// Invoices imported earlier that are cancelled in Fakturoid now and are held for review, not counted.
    var flaggedCancelled = 0

    /// Clients made by the import.
    var newClients = 0

    /// Clients that were there and had fields filled.
    var filledClients = 0

    /// The invoices to check (see `needsReview` and `flaggedCancelled`). The logs of older imports also have the notes
    /// on countries that are no codes here; `notes` has them now.
    var reviewItems: [String] = []

    /// The rows kept as the app had them, as the logs of older imports say. An import writes none now and no code
    /// reads the field; it stays so that those logs still decode.
    var keptItems: [String] = []

    /// The rows that could not be added.
    var conflictItems: [String] = []

    /// The supplier the export prints in its "Your …" columns, taken from the first row, for the Import screen to
    /// offer to fill an empty supplier profile with. Nothing is written to the profile.
    var exportSupplier: Supplier?

    /// The newest year in which an invoice was issued that this import added, updated or flagged as cancelled in
    /// Fakturoid: the year the Import screen opens Faktury on. Nil when the import changed no invoice.
    var newestYear: Int?

    /// The notes that do not hold an invoice ("Upozornění"), such as a country that is no code or a CSV row whose
    /// amount disagrees with the lines of its ISDOC file. A log stored before the summary kept them has none.
    var notes: [String] = []

    /// The numbers of the invoices the import overwrote ("Přepsané"): those it updated and those it flagged as
    /// cancelled. A log stored before the summary kept them has none.
    var overwrittenItems: [String] = []
}

nonisolated extension ImportSummary {
    /// The summary of an import that does what `plan` says.
    init(plan: ImportPlan, files: [String], exportSupplier: Supplier?) {
        self.init(
            files: files, added: plan.inserts.count, updated: plan.updates.count,
            unchanged: plan.unchangedNumbers.count, skipped: plan.skipped.count,
            needsReview: (plan.inserts + plan.updates).filter { $0.review != nil }.count,
            conflicts: plan.conflicts.count, flaggedCancelled: plan.flaggedCancelled.count,
            newClients: plan.newClients.count, filledClients: plan.clientUpdates.count, reviewItems: plan.reviewItems,
            conflictItems: plan.conflicts, exportSupplier: exportSupplier,
            newestYear: (plan.inserts + plan.updates + plan.flaggedCancelled).map(\.issueDate.year).max(),
            notes: plan.notes, overwrittenItems: plan.overwrittenNumbers
        )
    }

    /// Reads a summary from the import log. A log stored before a field was added to the summary does not have it:
    /// the year (`newestYear`) and the supplier are nil then, and `notes` and `overwrittenItems` are
    /// empty. Every other field must be there.
    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            files: try container.decode([String].self, forKey: .files),
            added: try container.decode(Int.self, forKey: .added),
            updated: try container.decode(Int.self, forKey: .updated),
            unchanged: try container.decode(Int.self, forKey: .unchanged),
            skipped: try container.decode(Int.self, forKey: .skipped),
            needsReview: try container.decode(Int.self, forKey: .needsReview),
            keptChangedInApp: try container.decode(Int.self, forKey: .keptChangedInApp),
            conflicts: try container.decode(Int.self, forKey: .conflicts),
            flaggedCancelled: try container.decode(Int.self, forKey: .flaggedCancelled),
            newClients: try container.decode(Int.self, forKey: .newClients),
            filledClients: try container.decode(Int.self, forKey: .filledClients),
            reviewItems: try container.decode([String].self, forKey: .reviewItems),
            keptItems: try container.decode([String].self, forKey: .keptItems),
            conflictItems: try container.decode([String].self, forKey: .conflictItems),
            exportSupplier: try container.decodeIfPresent(Supplier.self, forKey: .exportSupplier),
            newestYear: try container.decodeIfPresent(Int.self, forKey: .newestYear),
            notes: try container.decodeIfPresent([String].self, forKey: .notes) ?? [],
            overwrittenItems: try container.decodeIfPresent([String].self, forKey: .overwrittenItems) ?? []
        )
    }
}
