import Foundation
import Testing
@testable import InvoicesTracker

/// The path of an issue as the index of 2026 writes it. Arguments of tests cannot use members of the suite.
private let sampleIssuePath = "/cs/dane-a-ucetnictvi/financni-zpravodaj/2026/financni-zpravodaj-cislo-1-2026-62457"

struct GFRParserTests {
    // MARK: Helpers

    private static let issueDirectory = "https://mf.gov.cz/cs/dane-a-ucetnictvi/financni-zpravodaj/2026/"

    private func entry(_ code: String, _ amount: Int, _ rate: String) -> UniformRateEntry {
        UniformRateEntry(currency: CurrencyCode(code)!, amount: amount, rate: decimal(rate))
    }

    private func entry(_ code: String, in rates: [UniformRateEntry]) -> UniformRateEntry? {
        rates.first { $0.currency.code == code }
    }

    /// An index page with a link for each of `hrefs`.
    private func indexPage(_ hrefs: [String]) -> String {
        let items = hrefs.map { "<li><a href=\"\($0)\">Finanční zpravodaj</a></li>" }
        return "<html><body><ul>" + items.joined() + "</ul></body></html>"
    }

    /// A path of an issue of 2026 as the index prints it.
    private func issuePath(_ number: Int, _ id: Int) -> String {
        "/cs/dane-a-ucetnictvi/financni-zpravodaj/2026/financni-zpravodaj-cislo-\(number)-2026-\(id)"
    }

    /// The text of the 2025 instruction as the two kinds of fixtures give it: `txt` is the saved text of the PDF with
    /// two spaces between the columns, `pdf` is what PDFKit reads from the saved PDF.
    private func instructionText(from source: String) throws -> String {
        switch source {
        case "txt": try gfrFixture("gfr_issue_2_2026", "txt")
        default: try #require(PDFTextExtractor.text(from: try gfrFixtureData("gfr_issue_2_2026", "pdf")))
        }
    }

    // MARK: The index of a year

    @Test func theIndexOfAYearIsTheListOfIssuesPublishedTheNextYear() {
        #expect(
            GFRParser.indexURL(forYear: 2025)
                == webURL("https://mf.gov.cz/cs/dane-a-ucetnictvi/financni-zpravodaj/2026"))
        #expect(
            GFRParser.indexURL(forYear: 2026)
                == webURL("https://mf.gov.cz/cs/dane-a-ucetnictvi/financni-zpravodaj/2027"))
    }

    @Test func issueLinksOfTheIndexAreTheTwelveIssuesOfTheYearOldestFirst() throws {
        let links = GFRParser.issueLinks(indexHTML: try gfrFixture("gfr_index_2026", "html"), publicationYear: 2026)
        #expect(links.count == 12)
        #expect(links.first == webURL(Self.issueDirectory + "financni-zpravodaj-cislo-1-2026-62457"))
        #expect(links[1] == webURL(Self.issueDirectory + "financni-zpravodaj-cislo-2-2026-62472"))
        // By the number of the issue, not by the text of the address, which would put 10 before 2.
        #expect(
            links.map(\.lastPathComponent) == [
                "financni-zpravodaj-cislo-1-2026-62457",
                "financni-zpravodaj-cislo-2-2026-62472",
                "financni-zpravodaj-cislo-3-2026-62787",
                "financni-zpravodaj-cislo-4-2026-62809",
                "financni-zpravodaj-cislo-5-2026-63397",
                "financni-zpravodaj-cislo-6-2026-63429",
                "financni-zpravodaj-cislo-7-2026-63592",
                "financni-zpravodaj-cislo-8-2026-63672",
                "financni-zpravodaj-cislo-9-2026-63824",
                "financni-zpravodaj-cislo-10-2026-64098",
                "financni-zpravodaj-cislo-11-2026-64454",
                "financni-zpravodaj-cislo-12-2026-65270",
            ])
        #expect(links.allSatisfy { $0.absoluteString.hasPrefix(Self.issueDirectory) })
    }

    @Test func issuesOfOtherYearsAreNotLinksOfThisIndex() throws {
        let html = try gfrFixture("gfr_index_2026", "html")
        #expect(GFRParser.issueLinks(indexHTML: html, publicationYear: 2025) == [])
        #expect(GFRParser.issueLinks(indexHTML: html, publicationYear: 2027) == [])
    }

    @Test func linksAreUniqueAndKeepTheOrderOfTheNumbersWhateverTheOrderOfThePage() {
        let html = indexPage([issuePath(10, 64098), issuePath(2, 62472), issuePath(1, 62457), issuePath(2, 62472)])
        let links = GFRParser.issueLinks(indexHTML: html, publicationYear: 2026)
        #expect(
            links == [
                webURL(Self.issueDirectory + "financni-zpravodaj-cislo-1-2026-62457"),
                webURL(Self.issueDirectory + "financni-zpravodaj-cislo-2-2026-62472"),
                webURL(Self.issueDirectory + "financni-zpravodaj-cislo-10-2026-64098"),
            ])
    }

    @Test func linksMayBeWrittenWithSingleQuotesAndUppercaseAttributeNames() {
        let html = """
            <a href='\(issuePath(1, 62457))'>1</a>
            <a HREF = "\(issuePath(2, 62472))">2</a>
            <a
              href="\(issuePath(3, 62787))">3</a>
            """
        #expect(GFRParser.issueLinks(indexHTML: html, publicationYear: 2026).count == 3)
    }

    @Test(arguments: [
        "https://evil.example\(sampleIssuePath)",  // another site, even with the right path
        "//evil.example\(sampleIssuePath)",  // a protocol-relative address is another site
        "mailto:?subject=Finanční zpravodaj&body=https://mf.gov.cz\(sampleIssuePath)",
        "/cs/dane-a-ucetnictvi/financni-zpravodaj/2026",  // the index itself
        "/cs/dane-a-ucetnictvi/financni-zpravodaj/2026/financni-zpravodaj-cislo-1-2025-62457",  // another year's issue
        "/cs/dane-a-ucetnictvi/financni-zpravodaj/2025/financni-zpravodaj-cislo-1-2026-62457",  // folder of 2025
        "/cs/dane-a-ucetnictvi/financni-zpravodaj/2026/financni-zpravodaj-cislo-x-2026-62457",  // no number
        "/cs/dane-a-ucetnictvi/financni-zpravodaj/2026/financni-zpravodaj-cislo-1-2026-",  // no id
        "/cs/dane-a-ucetnictvi/financni-zpravodaj/2026/financni-zpravodaj-cislo-1-2026-62457/priloha",  // a deeper page
        "/cs/dane-a-ucetnictvi/financni-zpravodaj/2026/financni-zpravodaj-cislo-1-2026-62457?x=1",
        "/cs/dane-a-ucetnictvi/financni-zpravodaj/2026/financni-zpravodaj-cislo-99999999999999999999-2026-1",
        "/en/dane-a-ucetnictvi/financni-zpravodaj/2026/financni-zpravodaj-cislo-1-2026-62457",
        "https://mf.gov.cz.evil.example\(sampleIssuePath)",  // the name of the site only begins the name of another
        "https://mf.gov.cz@evil.example\(sampleIssuePath)",  // the site is the user
        "https://mf.gov.cz:8443\(sampleIssuePath)",
        "http://mf.gov.cz\(sampleIssuePath)",
        "https://www.mf.gov.cz\(sampleIssuePath)",
    ])
    func linksThatAreNotIssuesOfTheYearAreIgnored(_ href: String) {
        #expect(GFRParser.issueLinks(indexHTML: indexPage([href]), publicationYear: 2026) == [])
    }

    @Test func aLinkToAnIssueMayBeAbsoluteOnTheSameSite() {
        // Issue 2 is linked only with the address of the site in front, issue 3 in both ways, and counts once.
        let html = indexPage([
            "https://mf.gov.cz" + issuePath(2, 62472), issuePath(1, 62457), "https://mf.gov.cz" + issuePath(3, 62787),
            issuePath(3, 62787),
        ])
        #expect(
            GFRParser.issueLinks(indexHTML: html, publicationYear: 2026) == [
                webURL(Self.issueDirectory + "financni-zpravodaj-cislo-1-2026-62457"),
                webURL(Self.issueDirectory + "financni-zpravodaj-cislo-2-2026-62472"),
                webURL(Self.issueDirectory + "financni-zpravodaj-cislo-3-2026-62787"),
            ])
    }

    // MARK: Pages that are not what they should be

    @Test func theIndexAndTheIssueOfTheFixturesAreWhatTheyShouldBe() throws {
        #expect(GFRParser.isIssueIndex(indexHTML: try gfrFixture("gfr_index_2026", "html")))
        #expect(GFRParser.isIssuePage(issueHTML: try gfrFixture("gfr_issue_2_2026", "html")))
    }

    @Test(arguments: [
        "<a href=\"/cs/dane-a-ucetnictvi/financni-zpravodaj\">Finanční zpravodaj</a>",
        "<a href='/cs/dane-a-ucetnictvi/financni-zpravodaj/2027'>2027</a>",
        "<a href=\"/cs/dane-a-ucetnictvi/financni-zpravodaj/2026/financni-zpravodaj-cislo-1-2026-62457\">1</a>",
        "<a href=\"/cs/dane-a-ucetnictvi/financni-zpravodaj?rok=2027\">2027</a>",
        "<a href=\"/cs/dane-a-ucetnictvi/financni-zpravodaj#obsah\">obsah</a>",
        "<a href=\"https://mf.gov.cz/cs/dane-a-ucetnictvi/financni-zpravodaj/2027\">2027</a>",
    ])
    func aPageThatLinksIntoTheSectionIsAnIndex(_ html: String) {
        // The index of a new year may list no issue yet, but it still links into its section.
        #expect(GFRParser.isIssueIndex(indexHTML: html))
    }

    @Test(arguments: [
        "",
        "<html><body><h1>Údržba</h1></body></html>",
        "<html><body>503 Service Unavailable</body></html>",
        "<a href=\"/cs/dane-a-ucetnictvi\">Daně</a>",
        "<a href=\"/cs/dane-a-ucetnictvi/financni-zpravodaje\">other</a>",
        "<a href=\"/cs/dane-a-ucetnictvi/financni-zpravodaj-archiv\">other</a>",
        "<a href=\"/en/dane-a-ucetnictvi/financni-zpravodaj\">English</a>",
        "<a href=\"//evil.example/cs/dane-a-ucetnictvi/financni-zpravodaj\">other site</a>",
        "<a href=\"https://evil.example/cs/dane-a-ucetnictvi/financni-zpravodaj\">other site</a>",
        "<p>/cs/dane-a-ucetnictvi/financni-zpravodaj is only written here, not linked</p>",
    ])
    func aPageWithoutALinkIntoTheSectionIsNotAnIndex(_ html: String) {
        #expect(!GFRParser.isIssueIndex(indexHTML: html))
    }

    @Test(arguments: [
        "<title>Finanční zpravodaj číslo 3/2026 | Ministerstvo financí ČR</title>",
        "<title>Finan&#x10D;n&#xED; zpravodaj &#x10D;&#xED;slo 3/2026</title>",
        "<h1>Finan&#269;n&iacute;&nbsp;zpravodaj</h1>",
        "<h1>FINANČNÍ ZPRAVODAJ</h1>",
        "<h1>Finanční <small>zpravodaj</small></h1>",
    ])
    func aPageThatNamesTheFinancniZpravodajIsAnIssuePage(_ html: String) {
        #expect(GFRParser.isIssuePage(issueHTML: html))
    }

    @Test(arguments: [
        "",
        "<html><body><h1>Údržba</h1></body></html>",
        "<title>Ministerstvo financí ČR</title>",
        "<h1>Finanční správa</h1> <p>Zpravodaj</p>",
        // The announcement alone does not make a page an issue of the Finanční zpravodaj.
        "<li>Pokyn č. GFŘ-D-75 Stanovení jednotných kurzů za zdaňovací období 2025</li>",
    ])
    func aPageThatDoesNotNameTheFinancniZpravodajIsNotAnIssuePage(_ html: String) {
        #expect(!GFRParser.isIssuePage(issueHTML: html))
    }

    // MARK: The announcement in an issue

    @Test func theIssueOfJanuary2026AnnouncesTheRatesOf2025AndNotOfOtherYears() throws {
        let html = try gfrFixture("gfr_issue_2_2026", "html")
        #expect(GFRParser.announcesUniformRates(issueHTML: html, forYear: 2025))
        #expect(!GFRParser.announcesUniformRates(issueHTML: html, forYear: 2024))
        #expect(!GFRParser.announcesUniformRates(issueHTML: html, forYear: 2026))
    }

    @Test func theIndexPageAnnouncesNothing() throws {
        let html = try gfrFixture("gfr_index_2026", "html")
        #expect(!GFRParser.announcesUniformRates(issueHTML: html, forYear: 2025))
    }

    @Test func theAnnouncementCanBeInTheMetaDescriptionAlone() {
        let html = """
            <html><head><meta name="description"
              content="Pokyn č. GFŘ-D-75 Stanovení jednotných kurzů za zdaňovací období 2025 podle § 38"></head>
            <body><p>Nothing else</p></body></html>
            """
        #expect(GFRParser.announcesUniformRates(issueHTML: html, forYear: 2025))
    }

    @Test func theAnnouncementCanBeInTheTextOfThePageAloneWrittenWithCharacterReferences() {
        // The way the page of the fixture writes its list of contents: named references for the letters of Latin-1,
        // plain characters for the others.
        let html =
            "<ol><li>Pokyn č. GFŘ-D-75 Stanoven&iacute; jednotn&yacute;ch kurzů "
            + "za zdaňovac&iacute; obdob&iacute; 2025 podle &sect; 38</li></ol>"
        #expect(GFRParser.announcesUniformRates(issueHTML: html, forYear: 2025))
        // The same with numeric references for every letter with a mark.
        let numeric =
            "<li>Stanoven&#xED; jednotn&#xFD;ch kurz&#x16F; za zda&#x148;ovac&#xED; obdob&#xED; 2025</li>"
        #expect(GFRParser.announcesUniformRates(issueHTML: numeric, forYear: 2025))
    }

    @Test(arguments: [
        "Stanovení&nbsp;jednotných kurzů za zdaňovací období&nbsp;2025",
        "Stanovení\u{00A0}jednotných\u{202F}kurzů za  zdaňovací\n\t období\r\n2025",
        "Stanovení <strong>jednotných kurzů</strong> za <a href=\"/x\">zdaňovací</a> období <em>2025</em>",
        "STANOVENÍ JEDNOTNÝCH KURZŮ ZA ZDAŇOVACÍ OBDOBÍ 2025",
        "stanovení jednotných kurzů za zdaňovací období 2025.",
        "(Stanovení jednotných kurzů za zdaňovací období 2025, podle § 38)",
        // Marks written as separate characters, which is the same text.
        "Stanoveni\u{0301} jednotny\u{0301}ch kurzu\u{030A} za zdan\u{030C}ovaci\u{0301} obdobi\u{0301} 2025",
    ])
    func theAnnouncementIsFoundWhateverTheWhiteSpaceMarkupAndCase(_ text: String) {
        #expect(GFRParser.announcesUniformRates(issueHTML: "<li>\(text)</li>", forYear: 2025))
    }

    @Test(arguments: [
        "Stanovení jednotných kurzů za zdaňovací období 20250",  // another year, written longer
        "Stanovení jednotných kurzů za zdaňovací období 2025x2",
        "Stanovení jednotných kurzů za zdaňovací období 2024",
        "Stanovení jednotných kurzů za zdaňovací období",
        "Stanovení kurzů za zdaňovací období 2025",
        "Jednotné kurzy za zdaňovací období 2025",
        "Stanovení jednotných kurzů za rok 2025",
        "Sdělení o vydání pokynu",
        "",
    ])
    func otherTextDoesNotAnnounceTheRatesOf2025(_ text: String) {
        #expect(!GFRParser.announcesUniformRates(issueHTML: "<li>\(text)</li>", forYear: 2025))
    }

    @Test func theYearIsMatchedWholeAndNotByItsPrefix() {
        let html = "<li>Stanovení jednotných kurzů za zdaňovací období 2025 podle § 38</li>"
        #expect(!GFRParser.announcesUniformRates(issueHTML: html, forYear: 202))
        #expect(!GFRParser.announcesUniformRates(issueHTML: html, forYear: 20))
        #expect(!GFRParser.announcesUniformRates(issueHTML: html, forYear: 2))
    }

    @Test func aReferenceIsDecodedOnlyOnce() {
        // "&amp;iacute;" is the text "&iacute;", not an i with an acute accent.
        let html = "<li>Stanoven&amp;iacute; jednotných kurzů za zdaňovací období 2025</li>"
        #expect(!GFRParser.announcesUniformRates(issueHTML: html, forYear: 2025))
    }

    // MARK: The PDF of an issue

    @Test func theIssueOfJanuary2026LinksItsPDF() throws {
        let html = try gfrFixture("gfr_issue_2_2026", "html")
        #expect(
            GFRParser.pdfLink(issueHTML: html)
                == webURL("https://mf.gov.cz/assets/attachments/2026-01-14_Financni-zpravodaj-cislo-2-2026.pdf"))
    }

    @Test func theFirstPDFAttachmentIsTheLink() {
        let html = """
            <a href="/assets/img/logo.pdf">logo</a>
            <a href="/assets/attachments/other.docx">other</a>
            <a href="https://evil.example/assets/attachments/evil.pdf">evil</a>
            <a href='/assets/attachments/first.PDF'>first</a>
            <a href="/assets/attachments/second.pdf">second</a>
            """
        #expect(GFRParser.pdfLink(issueHTML: html) == webURL("https://mf.gov.cz/assets/attachments/first.PDF"))
    }

    @Test func everyPDFAttachmentIsALinkInTheOrderOfThePage() {
        let html = """
            <a href="/assets/img/logo.pdf">logo</a>
            <a href="/assets/attachments/other.docx">other</a>
            <a href="https://evil.example/assets/attachments/evil.pdf">evil</a>
            <a href='/assets/attachments/first.PDF'>first</a>
            <a href="/assets/attachments/second.pdf">second</a>
            <a href="/assets/attachments/first.PDF">first again</a>
            """
        #expect(
            GFRParser.pdfLinks(issueHTML: html) == [
                webURL("https://mf.gov.cz/assets/attachments/first.PDF"),
                webURL("https://mf.gov.cz/assets/attachments/second.pdf"),
            ])
    }

    @Test func aPDFLinkMayBeAbsoluteOnTheSameSiteAndMayHaveAQuery() {
        let html = """
            <a href="https://mf.gov.cz/assets/attachments/a.pdf">absolute</a>
            <a href="/assets/attachments/a.pdf">the same, relative</a>
            <a href="/assets/attachments/b.pdf?download=1">with a query</a>
            <a href="https://mf.gov.cz/assets/attachments/c.pdf?id=1&amp;lang=cs">absolute, with a query</a>
            """
        #expect(
            GFRParser.pdfLinks(issueHTML: html) == [
                webURL("https://mf.gov.cz/assets/attachments/a.pdf"),
                webURL("https://mf.gov.cz/assets/attachments/b.pdf?download=1"),
                webURL("https://mf.gov.cz/assets/attachments/c.pdf?id=1&lang=cs"),
            ])
        #expect(GFRParser.pdfLink(issueHTML: html) == webURL("https://mf.gov.cz/assets/attachments/a.pdf"))
    }

    @Test(arguments: [
        "",
        "<a href=\"/cs/dane-a-ucetnictvi/financni-zpravodaj\">index</a>",
        "<a href=\"/assets/attachments/report.docx\">docx</a>",
        "<a href=\"//evil.example/assets/attachments/evil.pdf\">evil</a>",
        "<a href=\"https://evil.example/assets/attachments/evil.pdf\">evil</a>",
        "<a href=\"https://mf.gov.cz.evil.example/assets/attachments/evil.pdf\">evil</a>",
        "<a href=\"https://mf.gov.cz@evil.example/assets/attachments/evil.pdf\">evil</a>",
        "<a href=\"https://mf.gov.cz:8443/assets/attachments/evil.pdf\">port</a>",
        "<a href=\"http://mf.gov.cz/assets/attachments/plain.pdf\">http</a>",
        "<a href=\"/assets/attachments/.pdf\">no name</a> <a href=\"/assets/attachments/.pdf?download=1\">no name</a>",
        "<a href=\"/assets/attachments/x.pdfx\">other</a> <a href=\"/assets/attachments/x.pdf.exe\">other</a>",
        // White space of any kind, a lone line feed or carriage return included, is not part of an address.
        "<a href=\"/assets/attachments/a b.pdf\">space</a> <a href=\"/assets/attachments/a\tb.pdf\">tab</a>",
        "<a href=\"/assets/attachments/a\nb.pdf\">line feed</a> <a href=\"/assets/attachments/a\rb.pdf\">return</a>",
        "<a href=\"/assets/attachments/a\r\nb.pdf\">both</a>",
        "<a href=\"/assets/attachments/a\u{00A0}b.pdf\">no-break space</a>",
    ])
    func aPageWithoutAPDFAttachmentHasNoLink(_ html: String) {
        #expect(GFRParser.pdfLink(issueHTML: html) == nil)
        #expect(GFRParser.pdfLinks(issueHTML: html) == [])
    }

    // MARK: The table in the PDF

    @Test(arguments: ["txt", "pdf"])
    func theInstructionOf2025IsReadFromItsTextAndFromItsPDF(_ source: String) throws {
        let parsed = try #require(GFRParser.parseRates(pdfText: try instructionText(from: source), forYear: 2025))
        #expect(parsed.instruction == "GFŘ-D-75")
        #expect(parsed.rates.count == 31)
        #expect(entry("USD", in: parsed.rates) == entry("USD", 1, "21.84"))
        #expect(entry("EUR", in: parsed.rates) == entry("EUR", 1, "24.66"))
        #expect(entry("TRY", in: parsed.rates) == entry("TRY", 100, "55.11"))
        #expect(entry("IDR", in: parsed.rates) == entry("IDR", 1000, "1.32"))
        #expect(entry("JPY", in: parsed.rates) == entry("JPY", 100, "14.59"))
        #expect(entry("GBP", in: parsed.rates) == entry("GBP", 1, "28.80"))
        // The table that shipped with the app is the same table.
        let difference = Set(parsed.rates).symmetricDifference(BuiltInUniformRates.rates(year: 2025))
        #expect(difference.isEmpty, "Differ in \(difference.sorted { $0.currency < $1.currency })")
    }

    @Test(arguments: ["txt", "pdf"])
    func eachCurrencyOfTheTableIsReadOnce(_ source: String) throws {
        let parsed = try #require(GFRParser.parseRates(pdfText: try instructionText(from: source), forYear: 2025))
        #expect(Set(parsed.rates.map(\.currency)).count == parsed.rates.count)
    }

    @Test(arguments: ["txt", "pdf"], [2024, 2026, 2022, 0])
    func theTextOfOneYearGivesNoRatesForAnotherYear(_ source: String, _ year: Int) throws {
        #expect(GFRParser.parseRates(pdfText: try instructionText(from: source), forYear: year) == nil)
    }

    @Test func theRatesAreReadFromTheTextOfAPDFWithRealText() throws {
        let pdf = makePDF(lines: [
            "Finanční zpravodaj 02/2099",
            "3. Pokyn č. GFŘ-D-99 Stanovení jednotných kurzů za zdaňovací období 2031 podle",
            "Pokyn č. GFŘ-D-99",
            "Stanovení jednotných kurzů za zdaňovací období 2031 podle § 38 zákona",
            "Země Měna Množství Kód Průměr",
            "EMU euro 1 EUR 24,66",
            "Japonsko jen 100 JPY 14,59",
            "Indonesie rupie 1000 IDR 1,32",
        ])
        let text = try #require(PDFTextExtractor.text(from: pdf))
        let parsed = try #require(GFRParser.parseRates(pdfText: text, forYear: 2031))
        #expect(parsed.instruction == "GFŘ-D-99")
        #expect(
            parsed.rates == [entry("EUR", 1, "24.66"), entry("JPY", 100, "14.59"), entry("IDR", 1000, "1.32")])
    }

    /// The first page of the instruction of 2022 spaces its number differently from the page that follows it, and the
    /// table is not in the order of the alphabet of the codes.
    @Test func theInstructionNumberMayBeSpacedOutAsInTheIssueOf2023() throws {
        let text = """
            1. Pokyn č . GFŘ -  D -  60 Stanovení jednotných kurzů za zdaňovací období 2022
            podle § 38 zákona č. 586/1992 Sb., o daních z příjmů, ve znění účinném do 31. 12. 2022
            Pokyn č. GFŘ - D - 60
            Stanovení jednotných kurzů za zdaňovací období 2022 podle § 38 zákona
            Země Měna Množství Kód Průměr
            Austrálie dolar 1 AUD 16,21
            Maďarsko forint 100 HUF 6,26
            Indonesie rupie 1000 IDR 1,57
            """
        let parsed = try #require(GFRParser.parseRates(pdfText: text, forYear: 2022))
        #expect(parsed.instruction == "GFŘ-D-60")
        #expect(
            parsed.rates == [entry("AUD", 1, "16.21"), entry("HUF", 100, "6.26"), entry("IDR", 1000, "1.57")])
    }

    @Test func theInstructionIsTheOneThatStandsInFrontOfTheTitleOfTheRates() throws {
        // An issue can hold other instructions. The one that announces the rates is the one in front of the title.
        let text = """
            2. Pokyn č. GFŘ-D-74 Změna postupu při podávání přiznání
            3. Pokyn č. GFŘ-D-75 Stanovení jednotných kurzů za zdaňovací období 2025 podle § 38
            Pokyn č. GFŘ-D-74
            Změna postupu při podávání přiznání
            Pokyn č. GFŘ-D-75
            Stanovení jednotných kurzů za zdaňovací období 2025 podle § 38 zákona
            EMU euro 1 EUR 24,66
            """
        let parsed = try #require(GFRParser.parseRates(pdfText: text, forYear: 2025))
        #expect(parsed.instruction == "GFŘ-D-75")
    }

    @Test func twoInstructionsForTheSameYearAreNotTheRatesOfEither() {
        let text = """
            Pokyn č. GFŘ-D-65 Stanovení jednotných kurzů za zdaňovací období 2024 podle § 38
            Pokyn č. GFŘ-D-66 Stanovení jednotných kurzů za zdaňovací období 2024 podle § 38
            EMU euro 1 EUR 25,16
            """
        #expect(GFRParser.parseRates(pdfText: text, forYear: 2024) == nil)
    }

    @Test func theSameTableTwiceIsOneTable() throws {
        let text = """
            Pokyn č. GFŘ-D-75 Stanovení jednotných kurzů za zdaňovací období 2025
            EMU euro 1 EUR 24,66
            USA dolar 1 USD 21,84
            EMU euro 1 EUR 24,66
            """
        let parsed = try #require(GFRParser.parseRates(pdfText: text, forYear: 2025))
        #expect(parsed.rates == [entry("EUR", 1, "24.66"), entry("USD", 1, "21.84")])
    }

    /// The correction GFŘ-D-66 of 2024 prints the Turkish lira three times, once of them as the mistake it corrects.
    @Test func aCurrencyWithTwoDifferentQuotesMakesTheTextUnreadable() {
        let text = """
            Pokyn č. GFŘ-D-66 Stanovení jednotných kurzů za zdaňovací období 2024 podle § 38 zákona
            Původně uvedeno:
            Turecko lira 1 TRY 70,48
            Nově uvedeno:
            Turecko lira 100 TRY 70,48
            EMU euro 1 EUR 25,16
            """
        #expect(GFRParser.parseRates(pdfText: text, forYear: 2024) == nil)
        let sameUnitDifferentRate = text.replacing("Turecko lira 1 TRY 70,48", with: "Turecko lira 100 TRY 71,48")
        #expect(GFRParser.parseRates(pdfText: sameUnitDifferentRate, forYear: 2024) == nil)
    }

    /// PDFKit reads the PDF of the instruction of 2022 with the code `THB` out of its row and in front of a note that
    /// stands beside it. Reading the other rows would be a table without the Thai baht, so the text is not read.
    @Test func aRowThatLostItsCodeMakesTheTextUnreadable() throws {
        let rows = """
            Pokyn č. GFŘ-D-60
            Stanovení jednotných kurzů za zdaňovací období 2022 podle § 38 zákona
            Švýcarsko frank 1 CHF 24,51
            Thajsko baht 100 THB 66,68
            Turecko lira 1 TRY 1,42
            """
        let parsed = try #require(GFRParser.parseRates(pdfText: rows, forYear: 2022))
        #expect(parsed.rates.map(\.currency.code) == ["CHF", "THB", "TRY"])

        let withoutTheCode = """
            Pokyn č. GFŘ-D-60
            Stanovení jednotných kurzů za zdaňovací období 2022 podle § 38 zákona
            Švýcarsko frank 1 CHF 24,51
            Thajsko baht 100 66,68
            Turecko lira 1 TRY 1,42
            THB Poznámka: S platností od 2. 3. 2022 ČNB pozastavuje vyhlašování kurzu ruského rublu (RUB)
            """
        #expect(GFRParser.parseRates(pdfText: withoutTheCode, forYear: 2022) == nil)
    }

    @Test func amountsOfMoneyInTheSameIssueAreNotRowsThatLostTheirCode() throws {
        // Another item of the issue can print amounts, and a thousands group written with a space looks like a unit
        // amount in front of a rate: "1 000,00" and "100 000,00". The rates of the table have no such group.
        let text = """
            Pokyn č. GFŘ-D-75 Stanovení jednotných kurzů za zdaňovací období 2025
            EMU euro 1 EUR 24,66
            Sdělení: částka 1 000,00 Kč, nejvýše 100 000,00 Kč, nejméně 1\u{00A0}000,50 Kč a 1 000 000,00 Kč.
            """
        let parsed = try #require(GFRParser.parseRates(pdfText: text, forYear: 2025))
        #expect(parsed.rates == [entry("EUR", 1, "24.66")])
    }

    @Test func textWithoutRatesGivesNothing() {
        let text = "Pokyn č. GFŘ-D-75 Stanovení jednotných kurzů za zdaňovací období 2025 podle § 38 zákona"
        #expect(GFRParser.parseRates(pdfText: text, forYear: 2025) == nil)
        #expect(GFRParser.parseRates(pdfText: "", forYear: 2025) == nil)
    }

    @Test(arguments: [
        "EMU euro 1 EUR 24,66",  // rates but no instruction
        "Pokyn č. GFŘ-D-75 EMU euro 1 EUR 24,66",  // an instruction that is not about the rates
        "Pokyn GFŘ-D-75 Stanovení jednotných kurzů za zdaňovací období 2025 EMU euro 1 EUR 24,66",  // no "č."
        "Pokyn č. D-75 Stanovení jednotných kurzů za zdaňovací období 2025 EMU euro 1 EUR 24,66",
        "Pokyn č. GFŘ-D- Stanovení jednotných kurzů za zdaňovací období 2025 EMU euro 1 EUR 24,66",
        "Pokyn č. GFŘ-D-75 Stanovení kurzů za zdaňovací období 2025 EMU euro 1 EUR 24,66",
        "Pokyn č. GFŘ-D-75 Stanovení jednotných kurzů za zdaňovací období EMU euro 1 EUR 24,66",
    ])
    func textWithoutTheInstructionOfTheRatesGivesNothing(_ text: String) {
        #expect(GFRParser.parseRates(pdfText: text, forYear: 2025) == nil)
    }

    @Test func rowsAreReadWithTheirTrueUnitAmountAndRate() throws {
        let text = """
            Pokyn č. GFŘ-D-75 Stanovení jednotných kurzů za zdaňovací období 2025
            Austrálie dolar 1 AUD 14,06
            Filipíny peso 100 PHP 37,90
            Indonesie rupie 1000 IDR 1,32
            """
        let parsed = try #require(GFRParser.parseRates(pdfText: text, forYear: 2025))
        #expect(parsed.rates == [entry("AUD", 1, "14.06"), entry("PHP", 100, "37.90"), entry("IDR", 1000, "1.32")])
        #expect(parsed.rates.map { DecimalMath.canonical($0.rate) } == ["14.06", "37.9", "1.32"])
    }

    /// A row that is not read must not give a table without that currency: the text is not read at all.
    @Test(arguments: [
        "Brazílie real 21 BRL 3,92",  // a digit in front of the unit amount
        "Kanada dolar 1 CAD 15,611",  // three decimals
        "Norsko koruna 10 NOK 2,11",  // a unit amount that is none
        "Polsko zlotý 1 PLN 5,8",  // one decimal
        "Rumunsko leu 1 RON 4,89,5",  // a second comma
        "Švédsko koruna 1 SEK 2.23",  // a point
    ])
    func aTableWithADamagedRowIsNotRead(_ damaged: String) throws {
        func text(withRow row: String) -> String {
            """
            Pokyn č. GFŘ-D-75 Stanovení jednotných kurzů za zdaňovací období 2025
            Austrálie dolar 1 AUD 14,06
            \(row)
            USA dolar 1 USD 21,84
            """
        }
        #expect(GFRParser.parseRates(pdfText: text(withRow: damaged), forYear: 2025) == nil)
        // Without the damage the very same text is a table.
        let valid = text(withRow: "Kanada dolar 1 CAD 15,61")
        let parsed = try #require(GFRParser.parseRates(pdfText: valid, forYear: 2025))
        #expect(parsed.rates.map(\.currency.code) == ["AUD", "CAD", "USD"])
    }

    /// Each of these damages one row of the real table, as the saved text of the PDF has it and as PDFKit reads the
    /// PDF. The other rows are fine, and a table without the damaged currency must not be the answer.
    @Test(arguments: ["txt", "pdf"], [
        ("Austrálie dolar 1 AUD 14,06", "Austrálie dolar 1 AUD 14,061"),  // the first row, three decimals
        ("Kanada dolar 1 CAD 15,61", "Kanada dolar 1 CAD 15,611"),  // three decimals
        ("Kanada dolar 1 CAD 15,61", "Kanada dolar 1CAD 15,61"),  // the unit glued to the code
        ("Kanada dolar 1 CAD 15,61", "Kanada dolar 1 CAD 15, 61"),  // the rate split
        ("Kanada dolar 1 CAD 15,61", "Kanada dolar 1 CAD 15 ,61"),
        ("Kanada dolar 1 CAD 15,61", "Kanada dolar 1 CAD"),  // the rate lost
        ("Kanada dolar 1 CAD 15,61", "Kanada dolar 1 CAD 15.61"),  // a point for the comma
        ("Kanada dolar 1 CAD 15,61", "Kanada dolar 1 cad 15,61"),  // the code in lowercase
        ("Kanada dolar 1 CAD 15,61", "Kanada dolar CAD 15,61"),  // the unit lost
        ("Kanada dolar 1 CAD 15,61", "Kanada dolar 1 15,61"),  // the code lost
        ("Kanada dolar 1 CAD 15,61", "Kanada dolar 1 CAD 15,6"),  // one decimal
        ("Kanada dolar 1 CAD 15,61", "Kanada dolar 1 CAD 1561"),  // the comma lost
        ("Kanada dolar 1 CAD 15,61", "Kanada dolar 15,61 1 CAD"),  // the rate in front of the unit
        ("Filipíny peso 100 PHP 37,90", "Filipíny peso 10 PHP 37,90"),  // a unit amount that is none
        ("Indonesie rupie 1000 IDR 1,32", "Indonesie rupie 1 000 IDR 1,32"),  // the unit with a thousands group
        ("Velká Británie libra 1 GBP 28,80", "Velká Británie libra 1 GBP 28,8"),  // the last row, one decimal
    ])
    func aDamagedRowOfTheRealTableMakesTheTextUnreadable(_ source: String, _ damage: (String, String)) throws {
        let (row, damaged) = damage
        let text = HTMLText.collapsingWhitespace(try instructionText(from: source))
        #expect(text.contains(row), "The row is in the text")
        #expect(GFRParser.parseRates(pdfText: text, forYear: 2025) != nil, "The text is a table")
        #expect(GFRParser.parseRates(pdfText: text.replacing(row, with: damaged), forYear: 2025) == nil)
    }

    @Test func numbersBeforeTheTitleOfTheRatesDoNotMatter() throws {
        // Another item of the issue, in front of the instruction, can print a percentage.
        let text = """
            1. Sdělení o sazbě 21,5 % a o částce 12,25 Kč
            2. Pokyn č. GFŘ-D-75 Stanovení jednotných kurzů za zdaňovací období 2025
            EMU euro 1 EUR 24,66
            """
        let parsed = try #require(GFRParser.parseRates(pdfText: text, forYear: 2025))
        #expect(parsed.rates == [entry("EUR", 1, "24.66")])
    }

    @Test(arguments: [
        "Sdělení o sazbě 21,5 %",
        "Částka 500,00 Kč",
        "Koeficient 0,5",
    ])
    func aNumberLikeARateAfterTheTitleThatIsNoRateOfARowMakesTheTextUnreadable(_ note: String) {
        // A number that looks like a rate and is not the rate of a row may be the rate of a row that was damaged.
        let text = """
            Pokyn č. GFŘ-D-75 Stanovení jednotných kurzů za zdaňovací období 2025
            EMU euro 1 EUR 24,66
            \(note)
            """
        #expect(GFRParser.parseRates(pdfText: text, forYear: 2025) == nil)
    }

    @Test func rowsCanFollowEachOtherOnOneLine() throws {
        let text =
            "Pokyn č. GFŘ-D-75 Stanovení jednotných kurzů za zdaňovací období 2025 "
            + "Austrálie dolar 1 AUD 14,06 Brazílie real 1 BRL 3,92 USA dolar 1 USD 21,84"
        let parsed = try #require(GFRParser.parseRates(pdfText: text, forYear: 2025))
        #expect(parsed.rates.map(\.currency.code) == ["AUD", "BRL", "USD"])
    }

    @Test(arguments: [
        "EMU euro 1 EUR 0,00",  // not a rate
        "EMU euro 1 EUR 99999999999999999999999999999999999999999,99",  // more digits than a decimal holds
    ])
    func aRateThatCannotBeTrustedMakesTheTextUnreadable(_ row: String) {
        let announcement = "Pokyn č. GFŘ-D-75 Stanovení jednotných kurzů za zdaňovací období 2025"
        let text = "\(announcement)\nUSA dolar 1 USD 21,84\n\(row)"
        #expect(GFRParser.parseRates(pdfText: text, forYear: 2025) == nil)
    }

    // MARK: Text of a PDF

    @Test func textOfThePDFOfJanuary2026() throws {
        let text = try #require(PDFTextExtractor.text(from: try gfrFixtureData("gfr_issue_2_2026", "pdf")))
        #expect(text.contains("Pokyn č. GFŘ-D-75"))
        #expect(text.contains("USA dolar 1 USD 21,84"))
    }

    @Test(arguments: [
        Data(),
        Data("not a pdf".utf8),
        Data("%PDF-1.4\n".utf8),
        Data("<html><body>Not found</body></html>".utf8),
    ])
    func dataThatIsNotAPDFHasNoText(_ data: Data) {
        #expect(PDFTextExtractor.text(from: data) == nil)
    }

    @Test func aPDFWithoutTextHasNoText() {
        #expect(PDFTextExtractor.text(from: makePDF(lines: [])) == nil)
        #expect(PDFTextExtractor.text(from: makePDF(lines: [" ", "  "])) == nil)
    }
}
