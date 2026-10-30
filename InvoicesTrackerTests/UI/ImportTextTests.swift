import Foundation
import Testing
@testable import InvoicesTracker

/// The words of the Import screen that are put together from the summary of an import: its counts, its lines, the lists
/// of what is to check, kept and not added, the line of the last import and the size of a file. In every expected
/// string `\u{00A0}` is the no-break space.
struct ImportTextTests {
    private let summary = ImportSummary(
        files: ["a.csv", "b.csv"], added: 11, updated: 2, unchanged: 5, skipped: 3, needsReview: 4,
        keptChangedInApp: 1, conflicts: 1, flaggedCancelled: 2, newClients: 4, filledClients: 3,
        reviewItems: ["20261003 — záporná částka", "20260901 — zrušeno ve Fakturoidu"],
        keptItems: ["20260902 — změněno v aplikaci — ponecháno"],
        conflictItems: ["20261102 — číslo už používá faktura vytvořená v aplikaci — nepřidáno"])

    // MARK: Counts

    @Test func theCountsAreSaidInTheOrderOfTheCardWithTheInvoicesToCheckLast() {
        #expect(
            ImportText.counts(of: summary)
                == "nové 11, aktualizované 2, beze změny 5, přeskočené 3, ke kontrole 6")
        #expect(
            ImportText.counts(of: ImportSummary())
                == "nové 0, aktualizované 0, beze změny 0, přeskočené 0, ke kontrole 0")
        // Each count has the tone the card shows it in.
        #expect(
            ImportText.countParts(of: summary).map(\.tone) == [.added, .updated, .unchanged, .skipped, .review])
    }

    @Test func theInvoicesToCheckAreThoseAddedOrUpdatedInReviewAndThoseCancelledInFakturoid() {
        let onlyCancelled = ImportSummary(flaggedCancelled: 1)
        let onlyRows = ImportSummary(needsReview: 3)

        #expect(ImportText.counts(of: onlyCancelled).hasSuffix("ke kontrole 1"))
        #expect(ImportText.counts(of: onlyRows).hasSuffix("ke kontrole 3"))
    }

    @Test func theSummaryLinesAreTheHeadlineAndTheClients() {
        #expect(
            ImportText.summaryLines(of: summary) == [
                "Hotovo – nové 11, aktualizované 2, beze změny 5, přeskočené 3, ke kontrole 6.",
                "noví odběratelé 4, doplněné údaje u 3",
            ])
    }

    // MARK: Lists

    @Test func theListsHaveATitleWithTheirCountANoteAndTheirItemsAndAreLeftOutWhenEmpty() {
        let lists = ImportText.lists(of: summary)

        #expect(lists.map(\.title) == ["Ke kontrole (2)", "Ponecháno, jak je v aplikaci (1)", "Nepřidáno (1)"])
        #expect(lists[0].items == summary.reviewItems)
        #expect(lists[1].items == summary.keptItems)
        #expect(lists[2].items == summary.conflictItems)
        #expect(
            lists[0].note
                == "Tyto faktury se nezapočítají do příjmů, dokud je nevyřešíte: označte je jako zaplacené, smažte je"
                + " nebo zapište úpravu příjmů v Nastavení › Rok.")
        #expect(lists[1].note == "Tyto faktury jste po importu změnili v aplikaci, proto je nový import nepřepsal.")
        #expect(lists[2].note == "Tyto řádky se nepodařilo přidat, důvod je u každého.")
        #expect(ImportText.lists(of: ImportSummary()).isEmpty)
        let onlyKept = ImportSummary(keptItems: ["x"])
        #expect(ImportText.lists(of: onlyKept).map(\.title) == ["Ponecháno, jak je v aplikaci (1)"])
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
                == "Poslední import 17.\u{00A0}10.\u{00A0}2026 · \(files) · nové 1, aktualizované 0, beze změny 0,"
                + " přeskočené 0, ke kontrole 0")
    }

    // MARK: Rows of a file

    @Test(arguments: [
        (0, "0\u{00A0}řádků"), (1, "1\u{00A0}řádek"), (2, "2\u{00A0}řádky"), (4, "4\u{00A0}řádky"),
        (5, "5\u{00A0}řádků"), (13, "13\u{00A0}řádků"), (21, "21\u{00A0}řádků"),
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
