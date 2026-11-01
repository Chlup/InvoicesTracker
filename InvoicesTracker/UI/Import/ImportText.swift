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
            case review
        }

        var text: String
        var tone: Tone
    }

    /// The counts of an import in the order of the card: "nové 11", "aktualizované 0", "beze změny 0", "přeskočené 2"
    /// and "ke kontrole 4". The invoices to check are those added or updated in review, and those that Fakturoid
    /// cancelled after they were imported: all of them are held for review.
    static func countParts(of summary: ImportSummary) -> [CountPart] {
        [
            CountPart(text: "nové \(summary.added)", tone: .added),
            CountPart(text: "aktualizované \(summary.updated)", tone: .updated),
            CountPart(text: "beze změny \(summary.unchanged)", tone: .unchanged),
            CountPart(text: "přeskočené \(summary.skipped)", tone: .skipped),
            CountPart(text: "ke kontrole \(summary.needsReview + summary.flaggedCancelled)", tone: .review),
        ]
    }

    /// "nové 11, aktualizované 0, beze změny 0, přeskočené 2, ke kontrole 4".
    static func counts(of summary: ImportSummary) -> String {
        countParts(of: summary).map(\.text).joined(separator: ", ")
    }

    /// "Hotovo – nové 11, aktualizované 0, beze změny 0, přeskočené 2, ke kontrole 4."
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

    /// The lists under the summary: what is to check, what the app kept as it had it, and what could not be added. A
    /// list with no item is left out.
    static func lists(of summary: ImportSummary) -> [ImportList] {
        var lists: [ImportList] = []
        if !summary.reviewItems.isEmpty {
            lists.append(
                ImportList(
                    title: "Ke kontrole (\(summary.reviewItems.count))",
                    note: "Tyto faktury se nezapočítají do příjmů, dokud je nevyřešíte: označte je jako zaplacené,"
                        + " smažte je nebo zapište úpravu příjmů v Nastavení › Rok.",
                    items: summary.reviewItems))
        }
        if !summary.keptItems.isEmpty {
            lists.append(
                ImportList(
                    title: "Ponecháno, jak je v aplikaci (\(summary.keptItems.count))",
                    note: "Tyto faktury jste po importu změnili v aplikaci, proto je nový import nepřepsal.",
                    items: summary.keptItems))
        }
        if !summary.conflictItems.isEmpty {
            lists.append(
                ImportList(
                    title: "Nepřidáno (\(summary.conflictItems.count))",
                    note: "Tyto řádky se nepodařilo přidat, důvod je u každého.", items: summary.conflictItems))
        }
        return lists
    }

    /// "Poslední import 17. 10. 2026 · 2 soubory · nové 11, aktualizované 0, beze změny 0, přeskočené 2, ke kontrole
    /// 4": the import of `summary`, made on `day`.
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
