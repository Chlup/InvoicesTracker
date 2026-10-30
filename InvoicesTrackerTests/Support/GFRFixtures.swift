import CoreGraphics
import CoreText
import Foundation
@testable import InvoicesTracker

/// The text of a GFŘ fixture, such as `gfr_index_2026` with `html` or `gfr_issue_2_2026` with `txt`.
///
/// `gfr_index_2026.html` and `gfr_issue_2_2026.html` are the pages of mf.gov.cz as they were downloaded, except that
/// the value of the Google Maps `apiKey` in each of them (the ministry's key for its own map) is replaced by
/// `REDACTED`, so that no secret scanner takes it for a leaked key. The PDF and the text of the PDF are unchanged.
func gfrFixture(_ name: String, _ ext: String) throws -> String {
    try String(contentsOf: fixtureURL(name, ext), encoding: .utf8)
}

/// The bytes of a GFŘ fixture, such as the PDF `gfr_issue_2_2026`.
func gfrFixtureData(_ name: String, _ ext: String) throws -> Data {
    try Data(contentsOf: fixtureURL(name, ext))
}

/// An address from its text. Traps on malformed input, because a bad literal in a test is a bug in the test.
func webURL(_ text: String) -> URL {
    guard let url = URL(string: text) else {
        preconditionFailure("Not a URL: \(text)")
    }
    return url
}

/// The finding for 2025 as the refresh makes it of the saved text of the instruction D-75: 31 currencies, the issue
/// 2/2026 of the Finanční zpravodaj and its PDF. Nothing of it is stored.
func gfrFinding2025() throws -> GFRFinding {
    guard let parsed = GFRParser.parseRates(pdfText: try gfrFixture("gfr_issue_2_2026", "txt"), forYear: 2025) else {
        throw TestSupportError.fixtureNotFound("the instruction of 2025 in gfr_issue_2_2026.txt")
    }
    return GFRFinding(
        year: 2025, instruction: parsed.instruction, issueURL: gfrIssue2025URL, pdfURL: gfrPDF2025URL,
        rates: parsed.rates)
}

/// Where the finding of `gfrFinding2025()` says its table was read.
let gfrIssue2025URL = webURL(
    "https://mf.gov.cz/cs/dane-a-ucetnictvi/financni-zpravodaj/2026/financni-zpravodaj-cislo-2-2026-62472")
let gfrPDF2025URL = webURL("https://mf.gov.cz/assets/attachments/2026-01-14_Financni-zpravodaj-c-2-2026.pdf")

/// A PDF of one page with real, selectable text: `lines` from top to bottom, one line each. For tests that need a PDF
/// whose text is known. Without lines the page is blank.
func makePDF(lines: [String]) -> Data {
    let data = NSMutableData()
    var mediaBox = CGRect(x: 0, y: 0, width: 600, height: 80 + 16 * lines.count)
    guard let consumer = CGDataConsumer(data: data),
        let context = CGContext(consumer: consumer, mediaBox: &mediaBox, nil)
    else {
        preconditionFailure("A PDF context cannot be made.")
    }
    context.beginPDFPage(nil)
    let font = CTFontCreateWithName("Helvetica" as CFString, 11, nil)
    for (index, text) in lines.enumerated() {
        let attributes = [NSAttributedString.Key(kCTFontAttributeName as String): font]
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: attributes))
        context.textPosition = CGPoint(x: 20, y: mediaBox.height - 40 - 16 * Double(index))
        CTLineDraw(line, context)
    }
    context.endPDFPage()
    context.closePDF()
    return data as Data
}
