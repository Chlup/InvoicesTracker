import Foundation
import Testing
@testable import InvoicesTracker

/// The one rule of the app for the noun that follows a count: the form for 1, the form for 2 to 4, and the form for
/// any other number, 0 included. The rule looks at the whole count, so 22 takes the form of the many.
struct CzechCountTests {
    /// The noun takes the form that Czech asks for the count, 22 and 1 000 included.
    @Test(arguments: [
        (0, "faktur"), (1, "faktura"), (2, "faktury"), (3, "faktury"), (4, "faktury"), (5, "faktur"), (11, "faktur"),
        (21, "faktur"), (22, "faktur"), (1_000, "faktur"),
    ])
    func theNounTakesTheFormThatCzechAsksForTheCount(count: Int, noun: String) {
        #expect(CzechCount.noun(for: count, one: "faktura", few: "faktury", many: "faktur") == noun)
    }

    /// A counted noun is the count grouped in thousands, a plain space and the noun in its form.
    @Test(arguments: [
        (0, "0 faktur"), (1, "1 faktura"), (2, "2 faktury"), (4, "4 faktury"), (5, "5 faktur"), (11, "11 faktur"),
        (21, "21 faktur"), (22, "22 faktur"), (1_000, "1\u{00A0}000 faktur"),
    ])
    func aCountedNounIsTheGroupedCountAPlainSpaceAndTheNoun(count: Int, text: String) {
        #expect(CzechCount.counted(count, one: "faktura", few: "faktury", many: "faktur") == text)
    }

    /// The caller chooses the separator between the count and the noun, such as the no-break space that keeps them on
    /// one line, and the count is grouped all the same.
    @Test(arguments: [
        (0, "0\u{00A0}šablon"), (1, "1\u{00A0}šablona"), (2, "2\u{00A0}šablony"), (4, "4\u{00A0}šablony"),
        (5, "5\u{00A0}šablon"), (11, "11\u{00A0}šablon"), (21, "21\u{00A0}šablon"), (22, "22\u{00A0}šablon"),
        (1_000, "1\u{00A0}000\u{00A0}šablon"),
    ])
    func theSeparatorBetweenTheCountAndTheNounIsTheCallersToo(count: Int, text: String) {
        let separator = "\u{00A0}"
        #expect(CzechCount.counted(count, one: "šablona", few: "šablony", many: "šablon", separator: separator) == text)
    }

    /// The word for days follows the same rule as every other noun.
    @Test(arguments: [(0, "dní"), (1, "den"), (2, "dny"), (4, "dny"), (5, "dní"), (22, "dní"), (1_000, "dní")])
    func theWordForDaysFollowsTheSameRule(count: Int, word: String) {
        #expect(CzechCount.dayWord(count) == word)
    }

    /// Days are counted like any other noun: the count grouped in thousands, then the separator of the caller and the
    /// word, so that a thousand days are "1 000 dní" and not "1000 dní".
    @Test(arguments: [
        (1, " ", "1 den"), (3, " ", "3 dny"), (30, "\u{00A0}", "30\u{00A0}dní"), (1_000, " ", "1\u{00A0}000 dní"),
        (1_000, "\u{00A0}", "1\u{00A0}000\u{00A0}dní"),
    ])
    func daysAreCountedLikeAnyOtherNoun(count: Int, separator: String, text: String) {
        #expect(CzechCount.days(count, separator: separator) == text)
    }
}
