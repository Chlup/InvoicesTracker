import Foundation
import Testing
@testable import InvoicesTracker

/// The one rule of the app for the noun that follows a count: the form for 1, the form for 2 to 4, and the form for
/// any other number, 0 included. The rule looks at the whole count, so 22 takes the form of the many.
struct CzechCountTests {
    @Test(arguments: [
        (0, "faktur"), (1, "faktura"), (2, "faktury"), (3, "faktury"), (4, "faktury"), (5, "faktur"), (11, "faktur"),
        (21, "faktur"), (22, "faktur"), (1_000, "faktur"),
    ])
    func theNounTakesTheFormThatCzechAsksForTheCount(count: Int, noun: String) {
        #expect(CzechCount.noun(for: count, one: "faktura", few: "faktury", many: "faktur") == noun)
    }

    @Test(arguments: [
        (0, "0 faktur"), (1, "1 faktura"), (2, "2 faktury"), (4, "4 faktury"), (5, "5 faktur"), (11, "11 faktur"),
        (21, "21 faktur"), (22, "22 faktur"), (1_000, "1\u{00A0}000 faktur"),
    ])
    func aCountedNounIsTheGroupedCountAPlainSpaceAndTheNoun(count: Int, text: String) {
        #expect(CzechCount.counted(count, one: "faktura", few: "faktury", many: "faktur") == text)
    }

    @Test(arguments: [
        (0, "0\u{00A0}šablon"), (1, "1\u{00A0}šablona"), (2, "2\u{00A0}šablony"), (4, "4\u{00A0}šablony"),
        (5, "5\u{00A0}šablon"), (11, "11\u{00A0}šablon"), (21, "21\u{00A0}šablon"), (22, "22\u{00A0}šablon"),
        (1_000, "1\u{00A0}000\u{00A0}šablon"),
    ])
    func theSeparatorBetweenTheCountAndTheNounIsTheCallersToo(count: Int, text: String) {
        let separator = "\u{00A0}"
        #expect(CzechCount.counted(count, one: "šablona", few: "šablony", many: "šablon", separator: separator) == text)
    }

    @Test(arguments: [(0, "dní"), (1, "den"), (2, "dny"), (4, "dny"), (5, "dní"), (22, "dní"), (1_000, "dní")])
    func theWordForDaysFollowsTheSameRule(count: Int, word: String) {
        #expect(CzechCount.dayWord(count) == word)
    }
}
