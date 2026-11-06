import Foundation

/// One list of the summary of an import: its title with the number of its items, a note that says what the list means,
/// and the lines, each with the number of an invoice and what became of it.
nonisolated struct ImportList: Hashable, Sendable {
    var title: String
    var note: String
    var items: [String]
}

/// The words of the Import screen that are put together from the summary of an import.
nonisolated enum ImportText {
    /// One count of the line of counts, and the colour the card of the progress shows it in.
    struct CountPart: Hashable, Sendable {
        enum Tone: Hashable, Sendable {
            case added
            case updated
            case unchanged
            case skipped
        }

        var text: String
        var tone: Tone
    }

    /// The counts of an import in the order of the card: "nové 11", "přepsané 0", "beze změny 0" and "přeskočené 2".
    /// The invoices to check have no count of their own: they are listed under "Ke kontrole".
    static func countParts(of summary: ImportSummary) -> [CountPart] {
        [
            CountPart(text: "nové \(summary.added)", tone: .added),
            CountPart(text: "přepsané \(summary.updated)", tone: .updated),
            CountPart(text: "beze změny \(summary.unchanged)", tone: .unchanged),
            CountPart(text: "přeskočené \(summary.skipped)", tone: .skipped),
        ]
    }

    /// "nové 11, přepsané 0, beze změny 0, přeskočené 2".
    static func counts(of summary: ImportSummary) -> String {
        countParts(of: summary).map(\.text).joined(separator: ", ")
    }

    /// "Hotovo – nové 11, přepsané 0, beze změny 0, přeskočené 2."
    static func headline(of summary: ImportSummary) -> String {
        "Hotovo – " + counts(of: summary) + "."
    }

    /// "noví odběratelé 4, doplněné údaje u 3": the clients the import made and those whose empty fields it filled.
    static func clientsLine(of summary: ImportSummary) -> String {
        "noví odběratelé \(summary.newClients), doplněné údaje u \(summary.filledClients)"
    }

    /// What the green box of the summary says: the headline and the line of the clients.
    static func summaryLines(of summary: ImportSummary) -> [String] {
        [headline(of: summary), clientsLine(of: summary)]
    }

    /// The lists under the summary: the invoices the import overwrote (one line of their numbers), what is to check,
    /// what could not be added, and the notes. A list with no item is left out. The rows that the logs of older imports
    /// kept as the app had them are not listed: an import overwrites what was changed in the app now.
    static func lists(of summary: ImportSummary) -> [ImportList] {
        var lists: [ImportList] = []
        if !summary.overwrittenItems.isEmpty {
            lists.append(
                ImportList(
                    title: "Přepsané (\(summary.overwrittenItems.count))",
                    note: "U těchto faktur nahradila data ze souborů to, co jste změnili v aplikaci.",
                    items: [summary.overwrittenItems.joined(separator: ", ")]))
        }
        if !summary.reviewItems.isEmpty {
            lists.append(
                ImportList(
                    title: "Ke kontrole (\(summary.reviewItems.count))",
                    note: "Tyto faktury se nezapočítají do příjmů, dokud je nevyřešíte: označte je jako zaplacené,"
                        + " smažte je nebo zapište úpravu příjmů v Nastavení › Rok.",
                    items: summary.reviewItems))
        }
        if !summary.conflictItems.isEmpty {
            lists.append(
                ImportList(
                    title: "Nepřidáno (\(summary.conflictItems.count))",
                    note: "Tyto řádky se nepodařilo přidat, důvod je u každého.", items: summary.conflictItems))
        }
        if !summary.notes.isEmpty {
            lists.append(
                ImportList(
                    title: "Upozornění (\(summary.notes.count))",
                    note: "Tyto faktury se započítají. Zkontrolujte u nich uvedený údaj.", items: summary.notes))
        }
        return lists
    }

    /// "Poslední import 17. 10. 2026 · 2 soubory · nové 11, přepsané 0, beze změny 0, přeskočené 2": the
    /// import of `summary`, made on `day`.
    static func lastImportLine(of summary: ImportSummary, on day: CivilDate) -> String {
        let files = CzechCount.counted(
            summary.files.count, one: "soubor", few: "soubory", many: "souborů", separator: CzechFormat.noBreakSpace)
        return "Poslední import \(CzechFormat.date(day)) · \(files) · " + counts(of: summary)
    }

    /// "1 řádek", "2 řádky", "13 řádků", "1 234 řádků": the rows of a file, with a no-break space between the number
    /// and the word.
    static func rows(_ count: Int) -> String {
        CzechCount.counted(count, one: "řádek", few: "řádky", many: "řádků", separator: CzechFormat.noBreakSpace)
    }

    /// "5,5 kB": the size of a file in kilobytes of 1 024 bytes, with a tenth, never less than 0,1.
    static func fileSize(bytes: Int) -> String {
        let tenths = max(1, (max(bytes, 0) * 10 + 512) / 1024)
        return CzechFormat.grouped(Int64(tenths / 10)) + "," + String(tenths % 10) + "\u{00A0}kB"
    }
}
