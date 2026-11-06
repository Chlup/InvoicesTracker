import Foundation

/// One row of the preview of an import ("Před importem"): what will become of some invoices, how many, and their
/// numbers in a note.
nonisolated struct ImportOutcomeRow: Hashable, Sendable {
    /// The colour of the dot of the row.
    enum Tone: Hashable, Sendable {
        /// Invoices that are added: green.
        case new

        /// Invoices that are overwritten: orange.
        case overwrite

        /// Everything else: grey.
        case neutral
    }

    /// The title of the row: "Nové", "Přepíší se" …
    var label: String

    /// How many invoices the row is about.
    var count: Int

    /// The colour of the dot of the row.
    var tone: Tone

    /// The numbers of the invoices and what becomes of them, in a sentence.
    var note: String
}

/// The words of the preview of an import ("Před importem") and of its progress: the rows of what the import will do,
/// the title of its button, and the lines of its files.
nonisolated enum ImportPreviewText {
    /// The rows of what the import of `plan` will do, in the order New, Overwritten, Unchanged, Skipped and Not added,
    /// each only with numbers. A plan with none of them has the one row "Žádná faktura k importu".
    static func outcomeRows(of plan: ImportPlan) -> [ImportOutcomeRow] {
        var rows: [ImportOutcomeRow] = []
        if !plan.newNumbers.isEmpty {
            rows.append(
                ImportOutcomeRow(
                    label: "Nové", count: plan.newNumbers.count, tone: .new,
                    note: "Přidají se: " + list(plan.newNumbers) + "."))
        }
        if !plan.overwrittenNumbers.isEmpty {
            let single = plan.overwrittenNumbers.count == 1
            let tail =
                single
                ? " – už ji v aplikaci máte. Co jste u ní v aplikaci změnili, se ztratí."
                : " – už je v aplikaci máte. Co jste u nich v aplikaci změnili, se ztratí."
            rows.append(
                ImportOutcomeRow(
                    label: "Přepíší se", count: plan.overwrittenNumbers.count, tone: .overwrite,
                    note: list(plan.overwrittenNumbers) + tail))
        }
        if !plan.unchangedNumbers.isEmpty {
            rows.append(
                ImportOutcomeRow(
                    label: "Beze změny", count: plan.unchangedNumbers.count, tone: .neutral,
                    note: "V aplikaci už jsou stejné: " + list(plan.unchangedNumbers) + "."))
        }
        if !plan.skippedNumbers.isEmpty {
            rows.append(
                ImportOutcomeRow(
                    label: "Přeskočí se", count: plan.skippedNumbers.count, tone: .neutral,
                    note: "Zálohové a stornované faktury: " + list(plan.skippedNumbers) + "."))
        }
        if !plan.notAdded.isEmpty {
            rows.append(
                ImportOutcomeRow(
                    label: "Nepřidají se", count: plan.notAdded.count, tone: .neutral,
                    note: plan.notAdded.map { "\($0.number) – \($0.reason)" }.joined(separator: "; ")))
        }
        if rows.isEmpty {
            rows.append(
                ImportOutcomeRow(
                    label: "Žádná faktura k importu", count: 0, tone: .neutral,
                    note: "Ve zvolených souborech není žádná faktura, kterou by šlo naimportovat."))
        }
        return rows
    }

    /// "Importovat 3 faktury" (with a no-break space before the noun), or "Importovat" when there is nothing to
    /// import.
    static func importButtonTitle(count: Int) -> String {
        guard count > 0 else { return "Importovat" }
        return "Importovat " + invoices(count, one: "fakturu", few: "faktury")
    }

    /// "1 soubor", "2 soubory", "5 souborů": the header of the files of the preview.
    static func filesHeader(count: Int) -> String {
        CzechCount.counted(count, one: "soubor", few: "soubory", many: "souborů", separator: CzechFormat.noBreakSpace)
    }

    /// The line under the name of `file`: "12 faktur · 5,5 kB" for a CSV, "faktura 20260902 · 5,8 kB" for an ISDOC
    /// invoice, and the error with the size for a file that cannot be used. A file of unknown size has no size.
    static func fileDetail(of file: ImportFile) -> String {
        let what: String
        switch file.content {
        case .rows(let rows): what = invoices(rows.count, one: "faktura", few: "faktury")
        case .invoice(let invoice): what = "faktura " + invoice.number
        case .failed(let error): what = error.errorDescription ?? ""
        }
        guard let size = file.size else { return what }
        return what + " · " + ImportText.fileSize(bytes: size)
    }

    /// "CSV", "ISDOC" or "?" for a file that is neither.
    static func pill(of file: ImportFile) -> String {
        switch file.kind {
        case .csv: "CSV"
        case .isdoc: "ISDOC"
        case nil: "?"
        }
    }

    /// "Importuji 3 z 12…": the progress of an import.
    static func progress(done: Int, total: Int) -> String {
        "Importuji \(done) z \(total)…"
    }

    /// The numbers joined with ", ".
    private static func list(_ numbers: [String]) -> String {
        numbers.joined(separator: ", ")
    }

    /// "1 faktura", "3 faktury" or "5 faktur" with a no-break space; `one` and `few` are the forms the sentence needs.
    private static func invoices(_ count: Int, one: String, few: String) -> String {
        CzechCount.counted(count, one: one, few: few, many: "faktur", separator: CzechFormat.noBreakSpace)
    }
}
