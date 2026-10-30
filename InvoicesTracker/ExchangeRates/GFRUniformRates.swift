import Foundation

/// The uniform rates of a year as the GFŘ published them, found and read.
nonisolated struct GFRFinding: Sendable, Hashable {
    /// The tax period the rates are for.
    let year: Int

    /// The number of the GFŘ instruction, such as `GFŘ-D-75`.
    let instruction: String

    /// The issue of the Finanční zpravodaj that announces the instruction.
    let issueURL: URL

    /// The PDF of that issue, where the table is.
    let pdfURL: URL

    /// The rates, as read from the PDF and in its order. They are not stored until the person confirms them.
    let rates: [UniformRateEntry]
}

/// What a search for the uniform rates of a year came to.
nonisolated enum GFROutcome: Sendable, Hashable {
    /// The announcement was found and its table read.
    case found(GFRFinding)

    /// No issue announces the rates yet. `checkedIssues` are all the issues now known not to: the ones the caller said
    /// were checked before, and the ones this search checked. A caller that keeps them asks for no issue twice.
    case notYet(checkedIssues: Set<URL>)

    /// The search cannot go on because a page is not what it should be, or the announcement cannot be read: the server
    /// answered 200 with a page that is no index or no issue of the Finanční zpravodaj (a maintenance page, say), or
    /// the PDF or its table is not what the parser expects. The address is the page that was being read, and the text
    /// says what was wrong with it, for a log or a message. Such a page is never counted as checked.
    case unreadable(URL, String)
}

/// Reads the pages and the PDF of the Finanční zpravodaj of the Ministry of Finance, where the GFŘ announces the
/// uniform exchange rates of the year that has ended.
///
/// The instruction appears in the first weeks of January in an issue of the Finanční zpravodaj, and the year's index
/// lists the issues. An issue page names the instruction in its text, and its PDF holds the table:
///
/// ```
/// Pokyn č. GFŘ-D-75
/// Stanovení jednotných kurzů za zdaňovací období 2025 podle § 38 zákona č. 586/1992 Sb., …
/// Země Měna Množství Kód Průměr
/// Austrálie dolar 1 AUD 14,06
/// ```
///
/// The readers do not guess. A page that is not what it should be is not read, and a text is read as a table only if
/// the table is whole: every number after the title that looks like a rate is the rate of a complete row, and every
/// unit amount with a code has its rate. So a damaged row makes the text unreadable instead of a table without that
/// currency. What no reader can see is a row that is missing altogether, or replaced by words with no number in them,
/// which leaves a table of fewer currencies that looks whole. A table is a proposal for the person to confirm, and the
/// caller can compare its currencies with last year's before it asks.
nonisolated enum GFRParser {
    private static let site = "https://mf.gov.cz"
    private static let issuesSection = "/cs/dane-a-ucetnictvi/financni-zpravodaj"
    private static let attachmentsDirectory = "/assets/attachments/"

    /// The index of the issues in which the rates of `year` can be announced: the issues of the next year.
    static func indexURL(forYear year: Int) -> URL {
        guard let url = URL(string: site + issuesSection + "/" + String(year + 1)) else {
            preconditionFailure("Not an address of the Ministry of Finance: \(year)")
        }
        return url
    }

    /// Whether the page is a page of the Finanční zpravodaj section of the site, as an index is, even one that lists no
    /// issue yet: it links into the section, to `/cs/dane-a-ucetnictvi/financni-zpravodaj` or a page below it. The
    /// server can answer 200 with any other page (of maintenance, a firewall or a proxy, say), which is not an index
    /// with no issue.
    ///
    /// The menu of the site links to the section from every page of the site, so this tells a page of the site from a
    /// page of something else, not an index from another page of the site.
    static func isIssueIndex(indexHTML: String) -> Bool {
        hrefs(in: indexHTML).contains { href in
            guard let path = sitePath(ofHref: href), path.hasPrefix(issuesSection) else { return false }
            // The section itself or a page below it, not another section whose name begins like it.
            let next = path.dropFirst(issuesSection.count).first
            return next == nil || next == "/" || next == "?" || next == "#"
        }
    }

    /// The addresses of the issues of `publicationYear` that the index page links, oldest first. They are absolute and
    /// unique. An issue is a link to `financni-zpravodaj-cislo-<N>-<publicationYear>-<id>` in the folder
    /// `/cs/dane-a-ucetnictvi/financni-zpravodaj/<publicationYear>/`, and the addresses are ordered by the number `N`,
    /// so that issue 2 comes before issue 10. A link may be written with the address of the site in front of the path.
    static func issueLinks(indexHTML: String, publicationYear: Int) -> [URL] {
        var seen: Set<String> = []
        var issues: [(number: Int, path: String)] = []
        for href in hrefs(in: indexHTML) {
            guard let path = sitePath(ofHref: href), !seen.contains(path),
                let number = issueNumber(ofPath: path, publicationYear: publicationYear)
            else {
                continue
            }
            seen.insert(path)
            issues.append((number, path))
        }
        return issues.sorted { ($0.number, $0.path) < ($1.number, $1.path) }.compactMap { URL(string: site + $0.path) }
    }

    /// Whether the page is a page of an issue of the Finanční zpravodaj: its text, or its title, names it. The server
    /// can answer 200 with any other page, and what such a page says about the rates is not an announcement.
    ///
    /// The menu of the site names the Finanční zpravodaj on every page of the site, so this tells a page of the site
    /// from a page of something else (maintenance, a firewall or a proxy), not an issue from another page of the site.
    static func isIssuePage(issueHTML: String) -> Bool {
        readings(of: issueHTML).contains { containsWholeWords("Finanční zpravodaj", in: $0) }
    }

    /// Whether the issue page announces the uniform rates of `year`: its text, or its description, has "Stanovení
    /// jednotných kurzů za zdaňovací období" and the year. White space (no-break spaces too), tags, the case of the
    /// letters and the way a letter is written do not matter, and the year has to be the whole number.
    static func announcesUniformRates(issueHTML: String, forYear year: Int) -> Bool {
        let phrase = "Stanovení jednotných kurzů za zdaňovací období \(year)"
        return readings(of: issueHTML).contains { containsWholeWords(phrase, in: $0) }
    }

    /// The first PDF of the issue, as `pdfLinks(issueHTML:)` lists them. Nil if there is none.
    static func pdfLink(issueHTML: String) -> URL? {
        pdfLinks(issueHTML: issueHTML).first
    }

    /// The PDFs of the issue, in the order of the page and without repeats: the links to a PDF in
    /// `/assets/attachments/` as absolute addresses. A link may have the address of the site in front of the path, and
    /// may have a query after the name of the file (`…/x.pdf?download=1`). A link to any other site is none.
    static func pdfLinks(issueHTML: String) -> [URL] {
        var seen: Set<String> = []
        var urls: [URL] = []
        for href in hrefs(in: issueHTML) {
            guard let path = sitePath(ofHref: href), isPDFAttachment(path), seen.insert(path).inserted,
                let url = URL(string: site + path)
            else {
                continue
            }
            urls.append(url)
        }
        return urls
    }

    /// The instruction and the rates of the table in the text of an issue, for the uniform rates of `year`. Nil unless
    /// all of this holds. Everything about the table is looked for from the first title of the rates to the end of the
    /// text, so that numbers in front of the title, in other items of the issue, do not matter.
    ///
    /// - The text has an instruction, `Pokyn č. GFŘ-D-<n>`, which is followed by the title "Stanovení jednotných kurzů
    ///   za zdaňovací období" and `year`. There may be other instructions in the issue, and their numbers are not
    ///   taken. The title is also printed on the first page of the issue, with the number spaced differently, which
    ///   is the same instruction. Two different instructions for the year are no instruction.
    /// - There is at least one row of the table: `1`, `100` or `1000` units, a code of three capital letters and a rate
    ///   with a decimal comma and two decimals (`14,06`). A number that is only part of a longer one is not a row.
    /// - The table is whole. Every number that looks like a rate (one to three digits, a comma and decimals) is the
    ///   rate of a row, except the groups of thousands in an amount of money (`1 000,00`). Every unit amount with a
    ///   code (`1 CAD`) has its rate. No unit amount stands directly in front of a rate, which is a row that lost its
    ///   code. A row damaged in any of these ways makes the text unreadable, not a table without that currency.
    /// - Every rate is above zero and can be held exactly, and a currency that appears more than once always has the
    ///   same quote. A currency with two different quotes, as in a correction that prints the mistake and the fix,
    ///   makes the text unreadable.
    static func parseRates(pdfText: String, forYear year: Int) -> (instruction: String, rates: [UniformRateEntry])? {
        let text = HTMLText.collapsingWhitespace(pdfText)
        guard let announcement = announcement(inText: text, forYear: year),
            let rates = rates(inTable: text[announcement.start...]),
            !rates.isEmpty
        else {
            return nil
        }
        return (announcement.instruction, rates)
    }

    // MARK: Pages and links

    /// The text of a page, read in the two ways it can be found in. The page as it is has its description in the
    /// attributes of a tag. The page without its tags has the text that tags split. Each has its character references
    /// decoded and its white space collapsed.
    private static func readings(of html: String) -> [String] {
        [html, HTMLText.removingTags(html)].map { HTMLText.collapsingWhitespace(HTMLText.decodingReferences($0)) }
    }

    /// The value of every `href` attribute of the page, in the order of the page, with its character references
    /// decoded (`&amp;` in a query is `&`).
    private static func hrefs(in html: String) -> [String] {
        html.matches(of: #/(?i)\bhref\s*=\s*(?:"([^"]*)"|'([^']*)')/#).map {
            HTMLText.decodingReferences(String($0.1 ?? $0.2 ?? ""))
        }
    }

    /// The path of a link to this site, with its query if it has one: a link that begins with a slash (but not two,
    /// which is another site) or with the address of the site and a slash. Nil for a link to any other place.
    private static func sitePath(ofHref href: String) -> String? {
        if href.hasPrefix(site + "/") {
            return String(href.dropFirst(site.count))
        }
        if href.hasPrefix("/"), !href.hasPrefix("//") {
            return href
        }
        return nil
    }

    /// The number of the issue a path is to, if it is the path of an issue of `publicationYear`.
    private static func issueNumber(ofPath path: String, publicationYear: Int) -> Int? {
        let prefix = "\(issuesSection)/\(publicationYear)/financni-zpravodaj-cislo-"
        guard path.hasPrefix(prefix) else { return nil }
        let parts = path.dropFirst(prefix.count).split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count == 3,
            isDigits(parts[0]), parts[1] == String(publicationYear)[...], isDigits(parts[2])
        else {
            return nil
        }
        return Int(parts[0])
    }

    /// Whether a path is that of a PDF in the attachments of this site. The query, if there is one, is not part of the
    /// name of the file.
    private static func isPDFAttachment(_ path: String) -> Bool {
        let extensionName = ".pdf"
        // No white space of any kind (a "\r\n" is one character in Swift, so a set of characters would miss a lone
        // "\n"), no quote or bracket that ends or breaks a value, no fragment, no backslash.
        let isForbidden: (Character) -> Bool = { $0.isWhitespace || "\"'<>#\\".contains($0) }
        guard path.hasPrefix(attachmentsDirectory), !path.contains(where: isForbidden) else {
            return false
        }
        let file = path.prefix { $0 != "?" }
        let nameLength = file.count - attachmentsDirectory.count - extensionName.count
        return file.lowercased().hasSuffix(extensionName) && nameLength > 0
    }

    private static func isDigits(_ text: Substring) -> Bool {
        !text.isEmpty && text.utf8.allSatisfy { (UInt8(ascii: "0")...UInt8(ascii: "9")).contains($0) }
    }

    /// Whether `text` has `phrase` and what follows it is not part of the same word or number.
    private static func containsWholeWords(_ phrase: String, in text: String) -> Bool {
        var remaining = text.startIndex..<text.endIndex
        while let found = text.range(of: phrase, options: .caseInsensitive, range: remaining) {
            let end = found.upperBound
            if end == text.endIndex || !(text[end].isLetter || text[end].isNumber) {
                return true
            }
            remaining = end..<text.endIndex
        }
        return false
    }

    // MARK: The table

    /// The instruction that announces the uniform rates of `year`, as `GFŘ-D-<n>`, and where its first title begins.
    /// The text has been squeezed to single spaces, and the instruction number is spaced differently in places
    /// (`GFŘ - D - 60`).
    private static func announcement(
        inText text: String,
        forYear year: Int
    ) -> (instruction: String, start: String.Index)? {
        let title =
            #/(?i)Pokyn č ?\. ?GFŘ ?- ?D ?- ?([0-9]+) Stanovení jednotných kurzů za zdaňovací období ([0-9]+)/#
        let titles = text.matches(of: title).filter { Int($0.2) == year }
        let numbers = Set(titles.map { String($0.1) })
        guard numbers.count == 1, let number = numbers.first, let first = titles.first else { return nil }
        return ("GFŘ-D-\(number)", first.range.lowerBound)
    }

    /// The rows of the table in `table`, the text from the title of the rates to the end. Nil if the table is not whole
    /// or a row cannot be trusted. See `parseRates` for what that is.
    private static func rates(inTable table: Substring) -> [UniformRateEntry]? {
        // A row that has lost its code leaves a unit amount directly in front of a rate. PDFKit does that when the code
        // is beside a note in the table (the `THB` of GFŘ-D-60). A rate of the table has one or two digits before the
        // comma, which tells it from a thousands group in an amount of money: "1 000,00" is not a unit amount and a
        // rate.
        let lostCode = #/(?:^|[^0-9,.])(?:1|100|1000) [0-9]{1,2},[0-9]{2}(?![0-9,])/#
        // The character in front of a unit amount cannot be a digit or a decimal separator, or the unit is the end of a
        // longer number (the `1 AUD` of `21 AUD`), and what follows the rate cannot be one, or the rate is the start of
        // a longer one (the `15,61` of `15,611`).
        let row = #/(?:^|[^0-9,.])(1|100|1000) ([A-Z]{3}) ([0-9]+,[0-9]{2})(?![0-9,])/#
        let unitAndCode = #/(?:^|[^0-9,.])(?:1|100|1000) [A-Z]{3}(?![A-Za-z])/#
        // Anything that looks like a rate: one to three digits, a comma and decimals. It does not count when a digit
        // and a space are in front of it, which makes it the last group of an amount of money (`1 000,00`).
        let rateLike = #/(?:^|[^0-9,. ]|[^0-9] )([0-9]{1,3},[0-9]+)(?![0-9,])/#

        guard table.firstMatch(of: lostCode) == nil else { return nil }
        let rows = table.matches(of: row)
        // The rows are counted before repeats are taken out, as the other two are counted. A unit amount with a code
        // that is not a row is a row that did not end in a rate in the form of the table.
        guard table.matches(of: unitAndCode).count == rows.count else { return nil }
        // And a number that looks like a rate but is not the rate of a row belongs to a row that was damaged.
        guard Set(table.matches(of: rateLike).map { $0.1.startIndex }) == Set(rows.map { $0.3.startIndex }) else {
            return nil
        }
        var entries: [UniformRateEntry] = []
        var quoted: [CurrencyCode: UniformRateEntry] = [:]
        for match in rows {
            guard let amount = Int(match.1),
                let currency = CurrencyCode(String(match.2)),
                let rate = DecimalMath.decimal(String(match.3.replacing(",", with: "."))),
                rate > 0
            else {
                return nil
            }
            let entry = UniformRateEntry(currency: currency, amount: amount, rate: rate)
            if let earlier = quoted[currency] {
                guard earlier == entry else { return nil }
                continue
            }
            quoted[currency] = entry
            entries.append(entry)
        }
        return entries
    }
}

/// Finds the announcement of the uniform rates of a year, in the Finanční zpravodaj, and reads its table.
nonisolated struct GFRFetcher: Sendable {
    let http: any HTTPClient

    /// The most issues one search looks at. The rest wait for the next search, which skips the ones already checked.
    static let issuesPerSearch = 6

    /// Looks for the uniform rates of the tax period `year`: in the issues of the next year, oldest first, that are not
    /// in `alreadyChecked`, the first `issuesPerSearch` of them. The first issue that announces the rates is read: its
    /// PDFs are downloaded in the order of the page, until the table is taken out of one of them. Issues after it are
    /// not looked at.
    ///
    /// A page that the server answers with 200 and that is not what it should be (an index with no link into the
    /// section, an issue that does not name the Finanční zpravodaj) is `.unreadable`. It is not "nothing yet", and it
    /// is not counted as checked, so the next search looks at it again.
    ///
    /// - Throws: `HTTPError` when a page or a PDF cannot be downloaded, and any other error the client throws as it is
    ///   (a failure of TLS, a cancellation), so a caller handles any `Error`. What was learned before is not kept, so
    ///   the next search begins again.
    func find(year: Int, alreadyChecked: Set<URL>) async throws -> GFROutcome {
        let indexURL = GFRParser.indexURL(forYear: year)
        guard let indexHTML = ResponseText.decode(try await http.get(indexURL)) else {
            return .unreadable(indexURL, "The index of the issues is not text.")
        }
        guard GFRParser.isIssueIndex(indexHTML: indexHTML) else {
            let reason = "The page is no index of the Finanční zpravodaj: it has no link into its section."
            return .unreadable(indexURL, reason)
        }
        let unchecked = GFRParser.issueLinks(indexHTML: indexHTML, publicationYear: year + 1)
            .filter { !alreadyChecked.contains($0) }
            .prefix(Self.issuesPerSearch)
        var checked = alreadyChecked
        for issueURL in unchecked {
            guard let issueHTML = ResponseText.decode(try await http.get(issueURL)) else {
                return .unreadable(issueURL, "The page of the issue is not text.")
            }
            guard GFRParser.isIssuePage(issueHTML: issueHTML) else {
                return .unreadable(issueURL, "The page is no issue of the Finanční zpravodaj: it does not name it.")
            }
            guard GFRParser.announcesUniformRates(issueHTML: issueHTML, forYear: year) else {
                checked.insert(issueURL)
                continue
            }
            return try await readAnnouncement(inIssue: issueURL, html: issueHTML, year: year)
        }
        return .notYet(checkedIssues: checked)
    }

    /// Downloads the PDFs of an issue that announces the rates, one after the other, and reads the table in the first
    /// that has it. The issue is unreadable only if none has.
    private func readAnnouncement(inIssue issueURL: URL, html: String, year: Int) async throws -> GFROutcome {
        let pdfURLs = GFRParser.pdfLinks(issueHTML: html)
        guard !pdfURLs.isEmpty else {
            return .unreadable(issueURL, "The issue announces the rates, but its page has no link to a PDF.")
        }
        var reasons: [String] = []
        for pdfURL in pdfURLs {
            let pdf = try await http.get(pdfURL)
            guard let text = PDFTextExtractor.text(from: pdf) else {
                reasons.append("A PDF of the issue is not a PDF or has no text.")
                continue
            }
            guard let parsed = GFRParser.parseRates(pdfText: text, forYear: year) else {
                reasons.append("The text of a PDF has no instruction with a whole table of the rates for \(year).")
                continue
            }
            return .found(
                GFRFinding(
                    year: year, instruction: parsed.instruction, issueURL: issueURL, pdfURL: pdfURL,
                    rates: parsed.rates))
        }
        if reasons.count == 1 {
            return .unreadable(issueURL, reasons[0])
        }
        let all = reasons.joined(separator: " ")
        return .unreadable(issueURL, "None of the \(reasons.count) PDFs of the issue can be read. \(all)")
    }
}
