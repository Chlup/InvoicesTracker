import Foundation
import Testing
@testable import InvoicesTracker

/// The words of the Import screen that are put together from the summary of an import: its counts, its lines, the lists
/// of what is to check and not added, the line of the last import and the size of a file. In every expected string
/// `\u{00A0}` is the no-break space.
struct ImportTextTests {
    private let summary = ImportSummary(
        files: ["a.csv", "b.csv"], added: 11, updated: 2, unchanged: 5, skipped: 3, needsReview: 4,
        keptChangedInApp: 1, conflicts: 1, flaggedCancelled: 2, newClients: 4, filledClients: 3,
        reviewItems: ["20261003 — záporná částka", "20260901 — zrušeno ve Fakturoidu"],
        keptItems: ["20260902 — změněno v aplikaci — ponecháno"],
        conflictItems: ["20261102 — číslo už používá faktura vytvořená v aplikaci — nepřidáno"],
        notes: ["země „Švýcarsko“ — není kód země, ponecháno jak je"], overwrittenItems: ["20260902", "20260903"])

    // MARK: Counts

    @Test func theCountsAreNewOverwrittenUnchangedAndSkippedWithNoCountOfInvoicesToCheck() {
        #expect(ImportText.counts(of: summary) == "nové 11, přepsané 2, beze změny 5, přeskočené 3")
        #expect(ImportText.counts(of: ImportSummary()) == "nové 0, přepsané 0, beze změny 0, přeskočené 0")
        #expect(ImportText.countParts(of: summary).map(\.tone) == [.added, .updated, .unchanged, .skipped])
    }

    @Test func theSummaryLinesAreTheHeadlineAndTheClients() {
        #expect(
            ImportText.summaryLines(of: summary) == [
                "Hotovo – nové 11, přepsané 2, beze změny 5, přeskočené 3.",
                "noví odběratelé 4, doplněné údaje u 3",
            ])
    }

    // MARK: Lists

    @Test func theListsHaveATitleWithTheirCountANoteAndTheirItemsAndAreLeftOutWhenEmpty() {
        let lists = ImportText.lists(of: summary)

        #expect(lists.map(\.title) == ["Přepsané (2)", "Ke kontrole (2)", "Nepřidáno (1)", "Upozornění (1)"])
        #expect(lists[0].items == ["20260902, 20260903"])
        #expect(lists[0].note == "U těchto faktur nahradila data ze souborů to, co jste změnili v aplikaci.")
        #expect(lists[1].items == summary.reviewItems)
        #expect(lists[2].items == summary.conflictItems)
        #expect(lists[3].items == summary.notes)
        #expect(lists[3].note == "Tyto faktury se započítají. Zkontrolujte u nich uvedený údaj.")
        #expect(
            lists[1].note
                == "Tyto faktury se nezapočítají do příjmů, dokud je nevyřešíte: označte je jako zaplacené, smažte je"
                + " nebo zapište úpravu příjmů v Nastavení › Rok.")
        #expect(lists[2].note == "Tyto řádky se nepodařilo přidat, důvod je u každého.")
        #expect(ImportText.lists(of: ImportSummary()).isEmpty)
        // The rows that older logs kept as the app had them are not listed.
        #expect(ImportText.lists(of: ImportSummary(keptItems: ["x"])).isEmpty)
    }

    @Test func anInvoiceCancelledInFakturoidCountsAmongTheOverwrittenOnesInTheHeadlineAndTheList() throws {
        let made = ImportPlanner.plan(
            sources: ImportSources(rows: try fakturoidFixtureRows(), isdocs: []), existingInvoices: [], clients: [],
            knownCurrencies: [.czk, .usd, .eur], payments: [:], invoiceRates: [:])
        var plan = ImportPlan()
        plan.updates = [made.inserts[0]]
        plan.flaggedCancelled = [made.inserts[1]]
        plan.overwrittenNumbers = [made.inserts[0].number, made.inserts[1].number]

        let summary = ImportSummary(plan: plan, files: ["a.csv"], exportSupplier: nil)

        #expect(ImportText.headline(of: summary).contains("přepsané 2"))
        #expect(ImportText.lists(of: summary).first?.title == "Přepsané (2)")
    }

    // MARK: A stored log

    @Test func aLogStoredBeforeTheseFieldsStillDecodes() throws {
        let json = """
            {"files":["a.csv"],"added":3,"updated":1,"unchanged":2,"skipped":1,"needsReview":1,"keptChangedInApp":2,
            "conflicts":1,"flaggedCancelled":0,"newClients":1,"filledClients":0,"reviewItems":["1 — x"],
            "keptItems":["2 — y"],"conflictItems":["3 — z"]}
            """

        let summary = try JSONDecoder().decode(ImportSummary.self, from: Data(json.utf8))

        #expect(summary.added == 3 && summary.updated == 1 && summary.keptChangedInApp == 2)
        #expect(summary.keptItems == ["2 — y"] && summary.reviewItems == ["1 — x"])
        #expect(summary.overwrittenItems.isEmpty && summary.notes.isEmpty && summary.newestYear == nil)
        #expect(ImportText.counts(of: summary) == "nové 3, přepsané 1, beze změny 2, přeskočené 1")
    }

    // MARK: The last import

    @Test(arguments: [
        (1, "1\u{00A0}soubor"), (2, "2\u{00A0}soubory"), (4, "4\u{00A0}soubory"), (5, "5\u{00A0}souborů"),
    ])
    func theLastImportLineCountsItsFilesInCzech(count: Int, files: String) {
        let summary = ImportSummary(files: (1...count).map { "\($0).csv" }, added: 1)

        let line = ImportText.lastImportLine(of: summary, on: civilDate("2026-10-17"))

        #expect(
            line
                == "Poslední import 17.\u{00A0}10.\u{00A0}2026 · \(files) · nové 1, přepsané 0, beze změny 0,"
                + " přeskočené 0")
    }

    // MARK: Rows of a file

    @Test(arguments: [
        (0, "0\u{00A0}řádků"), (1, "1\u{00A0}řádek"), (2, "2\u{00A0}řádky"), (4, "4\u{00A0}řádky"),
        (5, "5\u{00A0}řádků"), (13, "13\u{00A0}řádků"), (21, "21\u{00A0}řádků"), (1_234, "1\u{00A0}234\u{00A0}řádků"),
    ])
    func theRowsOfAFileAreCountedInTheFormOfCzechTheirNumberAsks(count: Int, text: String) {
        #expect(ImportText.rows(count) == text)
    }

    // MARK: Size of a file

    @Test(arguments: [
        (0, "0,1\u{00A0}kB"), (1, "0,1\u{00A0}kB"), (5_620, "5,5\u{00A0}kB"), (1_024, "1,0\u{00A0}kB"),
        (1_075, "1,0\u{00A0}kB"), (1_076, "1,1\u{00A0}kB"), (1_500_000, "1\u{00A0}464,8\u{00A0}kB"),
    ])
    func theSizeOfAFileIsInKilobytesWithATenthAndADecimalComma(bytes: Int, text: String) {
        #expect(ImportText.fileSize(bytes: bytes) == text)
    }
}
