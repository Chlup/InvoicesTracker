import Testing
@testable import InvoicesTracker

/// How text is folded for the search: lowercase, without diacritics, with every whitespace as one plain space. The
/// documents of the invoices and the words of a query are folded by the same function, so these rules are the rules of
/// the search.
struct SearchFoldingTests {
    // MARK: fold

    @Test func foldingRemovesCaseAndTheDiacriticsOfCzech() {
        #expect(SearchFolding.fold("Příbram – Brod") == "pribram – brod")
        #expect(SearchFolding.fold("ŽLUŤOUČKÝ\u{00A0}kůň") == "zlutoucky kun")
    }

    @Test func everyCzechLetterWithAMarkLosesItInCapitalsAndInSmallLetters() {
        #expect(SearchFolding.fold("ÁČĎÉĚÍŇÓŘŠŤÚŮÝŽ") == "acdeeinorstuuyz")
        #expect(SearchFolding.fold("áčďéěíňóřšťúůýž") == "acdeeinorstuuyz")
        let sentence = SearchFolding.fold("Příliš žluťoučký kůň úpěl ďábelské ódy")
        #expect(sentence == "prilis zlutoucky kun upel dabelske ody")
    }

    @Test func aLetterWrittenWithACombiningMarkFoldsLikeTheSingleCharacter() {
        // r + caron, i + acute: nine code points where "Příbram" has seven
        let decomposed = "Pr\u{030C}i\u{0301}bram"
        #expect(decomposed.unicodeScalars.count == 9)
        #expect(SearchFolding.fold(decomposed) == "pribram")
        #expect(SearchFolding.fold(decomposed) == SearchFolding.fold("Příbram"))
    }

    @Test(arguments: [
        "a\u{00A0}b", "a\u{202F}b", "a\tb", "a\nb", "a\r\nb", "a\u{2009}b", "a\u{2028}b", "a   b",
        "a \u{00A0}\u{202F}\t\n b",
    ])
    func everyKindOfWhitespaceBecomesOneSpace(text: String) {
        #expect(SearchFolding.fold(text) == "a b")
    }

    @Test func whitespaceAtTheEndsIsDropped() {
        #expect(SearchFolding.fold("  \u{00A0}x\n ") == "x")
        #expect(SearchFolding.fold("x\u{202F}") == "x")
        #expect(SearchFolding.fold("") == "")
        #expect(SearchFolding.fold(" \t\u{00A0}\u{202F}\n") == "")
    }

    @Test func digitsPunctuationAndSignsStayAsTheyAre() {
        #expect(SearchFolding.fold("14\u{00A0}350,00 Kč") == "14 350,00 kc")
        #expect(SearchFolding.fold("30.9.2026, 2026-09-30") == "30.9.2026, 2026-09-30")
        #expect(SearchFolding.fold("\u{2212}12,5 [A_B] 100 %") == "\u{2212}12,5 [a_b] 100 %")
        #expect(SearchFolding.fold("ab\"c") == "ab\"c")
    }

    /// SQLite reads a pattern and a query string up to the first NUL, so neither could say what the text says.
    @Test func theNulCharacterIsDropped() {
        #expect(SearchFolding.fold("a\u{0000}b") == "ab")
        #expect(SearchFolding.fold("\u{0000}") == "")
        #expect(SearchFolding.words("alfa\u{0000} 2026") == ["alfa", "2026"])
        #expect(SearchFolding.words("\u{0000}").isEmpty)
    }

    @Test func foldingTwiceIsTheSameAsFoldingOnce() {
        for text in ["Příbram – Brod", "ŽLUŤOUČKÝ\u{00A0}kůň", "  Straße  ", "Pr\u{030C}i\u{0301}bram", "Ⅷ ǅ İ ﬁ"] {
            let once = SearchFolding.fold(text)
            #expect(SearchFolding.fold(once) == once, "\(text)")
        }
    }

    // MARK: words

    @Test func aQueryIsSplitIntoItsFoldedWords() {
        #expect(SearchFolding.words("Příbram – Brod") == ["pribram", "–", "brod"])
        #expect(SearchFolding.words("  ALFA\t2026\u{00A0}\u{00A0}") == ["alfa", "2026"])
        #expect(SearchFolding.words("14\u{00A0}350,00") == ["14", "350,00"])
        #expect(SearchFolding.words("alfa alfa") == ["alfa", "alfa"])
    }

    @Test func aQueryWithoutWordsHasNone() {
        #expect(SearchFolding.words("").isEmpty)
        #expect(SearchFolding.words("   \u{00A0}\t\n").isEmpty)
    }
}
