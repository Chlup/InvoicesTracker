import Foundation
import Testing
@testable import InvoicesTracker

struct HTMLTextTests {
    // MARK: Character references

    @Test(arguments: [
        // The letters of Latin-1 the pages of the Ministry write by name, and the marks around them.
        ("&aacute;", "á"), ("&Aacute;", "Á"), ("&eacute;", "é"), ("&iacute;", "í"), ("&oacute;", "ó"),
        ("&uacute;", "ú"), ("&yacute;", "ý"), ("&Yacute;", "Ý"), ("&sect;", "§"), ("&copy;", "©"),
        ("&nbsp;", "\u{00A0}"),
        // The first and the last name of each row of sixteen in the table, which catches a table that slipped.
        ("&iexcl;", "¡"), ("&macr;", "¯"), ("&deg;", "°"), ("&iquest;", "¿"), ("&Agrave;", "À"), ("&Iuml;", "Ï"),
        ("&ETH;", "Ð"), ("&szlig;", "ß"), ("&agrave;", "à"), ("&iuml;", "ï"), ("&eth;", "ð"), ("&yuml;", "ÿ"),
        ("&times;", "×"), ("&divide;", "÷"), ("&THORN;", "Þ"), ("&thorn;", "þ"),
        // The markup characters and the punctuation.
        ("&amp;", "&"), ("&lt;", "<"), ("&gt;", ">"), ("&quot;", "\""), ("&apos;", "'"),
        ("&ndash;", "–"), ("&mdash;", "—"), ("&hellip;", "…"), ("&lsquo;", "‘"), ("&rsquo;", "’"),
        ("&ldquo;", "“"), ("&rdquo;", "”"), ("&bdquo;", "„"),
        // The letters of Czech that are not in Latin-1.
        ("&Ccaron;", "Č"), ("&ccaron;", "č"), ("&Dcaron;", "Ď"), ("&dcaron;", "ď"), ("&Ecaron;", "Ě"),
        ("&ecaron;", "ě"), ("&Ncaron;", "Ň"), ("&ncaron;", "ň"), ("&Rcaron;", "Ř"), ("&rcaron;", "ř"),
        ("&Scaron;", "Š"), ("&scaron;", "š"), ("&Tcaron;", "Ť"), ("&tcaron;", "ť"), ("&Uring;", "Ů"),
        ("&uring;", "ů"), ("&Zcaron;", "Ž"), ("&zcaron;", "ž"),
    ])
    func namedReferencesAreDecoded(_ reference: String, _ expected: String) {
        #expect(HTMLText.decodingReferences(reference) == expected)
        #expect(HTMLText.decodingReferences("a\(reference)b") == "a\(expected)b")
    }

    @Test(arguments: [
        ("&#237;", "í"), ("&#xED;", "í"), ("&#XED;", "í"), ("&#xed;", "í"), ("&#x10C;", "Č"), ("&#x16F;", "ů"),
        ("&#8211;", "–"), ("&#x2B;", "+"), ("&#160;", "\u{00A0}"), ("&#38;", "&"), ("&#x1F600;", "\u{1F600}"),
        ("&#0237;", "í"),
    ])
    func numericReferencesAreDecoded(_ reference: String, _ expected: String) {
        #expect(HTMLText.decodingReferences(reference) == expected)
    }

    @Test(arguments: [
        "&unknown;", "&;", "&", "&&", "& iacute;", "&iacute", "&#;", "&#x;", "&#xZZ;", "&#12a;", "&#-5;",
        "&#0;", "&#x0;", "&#xD800;", "&#xDFFF;", "&#x110000;", "&#99999999999999999999;", "&#xFFFFFFFFFFFF;",
        "&AAcute;", "&IACUTE;", "&Iacute", "&amp",
    ])
    func referencesThatAreNotKnownOrNotCharactersStayAsTheyAre(_ text: String) {
        #expect(HTMLText.decodingReferences(text) == text)
        #expect(HTMLText.decodingReferences("<\(text)>") == "<\(text)>")
    }

    @Test func aReferenceIsDecodedOnce() {
        #expect(HTMLText.decodingReferences("&amp;iacute;") == "&iacute;")
        #expect(HTMLText.decodingReferences("&amp;#237;") == "&#237;")
        #expect(HTMLText.decodingReferences("&amp;amp;") == "&amp;")
    }

    @Test func referencesAreDecodedAmongOtherText() {
        let html = "Pokyn č. GFŘ-D-75 Stanoven&iacute; jednotn&yacute;ch kurz&#x16F; &sect; 38 &amp; 39 &lt;ok&gt;"
        #expect(HTMLText.decodingReferences(html) == "Pokyn č. GFŘ-D-75 Stanovení jednotných kurzů § 38 & 39 <ok>")
        #expect(HTMLText.decodingReferences("") == "")
        #expect(HTMLText.decodingReferences("No references; just text & more") == "No references; just text & more")
    }

    // MARK: Tags

    @Test func tagsAreReplacedBySpaces() {
        #expect(HTMLText.removingTags("<p>One</p><p>Two</p>") == " One  Two ")
        #expect(HTMLText.removingTags("a<br>b<br/>c") == "a b c")
        #expect(HTMLText.removingTags("<!DOCTYPE html><html lang=\"cs\"><body>x</body></html>") == "   x  ")
        #expect(HTMLText.removingTags("no tags") == "no tags")
        #expect(HTMLText.removingTags("") == "")
    }

    @Test func aTagIsEndedByItsClosingBracketAndNotByOneInsideAQuotedAttribute() {
        #expect(HTMLText.removingTags("<a title=\"a > b\" href='x > y'>link</a>") == " link ")
        #expect(HTMLText.removingTags("<a\n  href=\"x\"\n  class=\"y\">link</a>") == " link ")
    }

    @Test func aLessThanSignThatOpensNoTagIsText() {
        #expect(HTMLText.removingTags("1 < 2 and 3 > 2") == "1 < 2 and 3 > 2")
        #expect(HTMLText.removingTags("<a href=\"unterminated>text") == "<a href=\"unterminated>text")
    }

    // MARK: White space

    @Test func whiteSpaceIsSqueezedToSingleSpaces() {
        #expect(HTMLText.collapsingWhitespace("  a \t b\n\nc\r\nd  ") == "a b c d")
        // No-break spaces, the narrow one of the Czech typography, and other spaces of Unicode.
        #expect(HTMLText.collapsingWhitespace("a\u{00A0}b\u{202F}c\u{2009}d\u{2003}e\u{3000}f") == "a b c d e f")
        #expect(HTMLText.collapsingWhitespace("a\u{00A0}\u{00A0} \u{00A0}b") == "a b")
    }

    @Test func nothingButWhiteSpaceIsNothing() {
        #expect(HTMLText.collapsingWhitespace("") == "")
        #expect(HTMLText.collapsingWhitespace(" \n\t\u{00A0}") == "")
    }

    @Test func lettersWithMarksAreComposed() {
        let decomposed = "Stanoveni\u{0301} kurzu\u{030A} zdan\u{030C}ovaci\u{0301}"
        let collapsed = HTMLText.collapsingWhitespace(decomposed)
        #expect(Array(collapsed.unicodeScalars) == Array("Stanovení kurzů zdaňovací".unicodeScalars))
    }
}
