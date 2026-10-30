import Foundation
import Testing
@testable import InvoicesTracker

/// Days are counted in Czech words wherever the app writes a number of them: "1 den", "2 dny", "5 dní".
@Suite(.settlesBackups)
@MainActor
struct DueDaysTextTests {
    @Test(arguments: [
        (0, "dní"), (1, "den"), (2, "dny"), (3, "dny"), (4, "dny"), (5, "dní"), (11, "dní"), (14, "dní"), (21, "dní"),
        (22, "dní"), (101, "dní"), (999, "dní"),
    ])
    func aNumberOfDaysTakesTheWordOfItsCount(count: Int, word: String) {
        #expect(CzechCount.dayWord(count) == word)
        #expect(CzechCount.days(count) == "\(count) \(word)")
    }

    @Test(arguments: [(1, "1 den"), (2, "2 dny"), (4, "4 dny"), (5, "5 dní"), (14, "14 dní"), (30, "30 dní")])
    func theLineOfTheClientInTheEditorSaysItsDueTimeInCzechWords(days: Int, text: String) async throws {
        try await EditorFixture.with { f in
            var alfa = try #require(try await f.database.client(id: f.alfaID))
            alfa.dueDays = days
            try await f.database.saveClient(alfa)
            await f.app.didWrite()

            let model = await f.newEditor()

            #expect(model.pickedClient?.id == f.alfaID)
            #expect(
                model.clientInfo == "výchozí: CZK · Převodem · splatnost \(text) · Tuzemsko 21 % · faktura česky")
        }
    }

    @Test func theWordAfterTheDueDaysFieldFollowsTheDaysTyped() async throws {
        try await EditorFixture.with { f in
            let model = await f.newEditor(template: f.dollarTemplate)

            for (typed, word) in [("30", "dní"), ("1", "den"), ("2", "dny"), ("4", "dny"), ("5", "dní"), ("0", "dní")] {
                model.dueDaysText = typed
                #expect(model.dueDaysLine == word + " · " + model.dueDateText, "\(typed)")
            }
            model.dueDaysText = " 3 "
            #expect(model.dueDaysLine == "dny · " + CzechFormat.date(civilDate("2026-10-20")))
            // A text that is not a number of days is said as the many.
            model.dueDaysText = "x"
            #expect(model.dueDaysLine == "dní · —")
        }
    }
}
