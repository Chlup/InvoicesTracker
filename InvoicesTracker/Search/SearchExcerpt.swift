import Foundation

/// The line under a row of the list that says why an invoice was found, when no column of the table shows the reason.
nonisolated struct SearchExcerptResult: Sendable, Hashable {
    /// The label of the field the text is from: "Poznámka" for the note.
    let label: String

    /// The part of the field around the word, on one line, with … where it was cut.
    let text: String

    /// The characters of `text` that the word matched, as they are written there. A range of `text` itself.
    let highlight: Range<String.Index>
}

nonisolated enum SearchExcerpt {
    /// How much of the field is shown before the word and after it, so that a line is about 60 characters.
    private static let charactersBefore = 24
    private static let charactersAfter = 32

    /// Why `invoice` was found for `words` (the folded words of the query, `SearchFolding.words(_:)`), when the table
    /// of the list does not show it: the first field the table does not show that has the first word no field of the
    /// table has, cut to about 60 characters around the word.
    ///
    /// Nil when every word is in a field of the table, so there is nothing to explain, and when a word is in no field
    /// at all, because the invoice does not match the query.
    static func excerpt(for invoice: Invoice, words: [String]) -> SearchExcerptResult? {
        let fields = SearchDocumentBuilder.fields(for: invoice)
        let folded = fields.map { SearchFolding.fold($0.text) }
        var explanation: SearchExcerptResult?
        for word in words {
            if fields.indices.contains(where: { fields[$0].shownInTable && occurs(word, in: folded[$0]) }) {
                continue
            }
            // No field of the table has the word, so the fields that have it are the ones the table does not show.
            let hidden = fields.indices.filter { occurs(word, in: folded[$0]) }
            guard let first = hidden.lazy.compactMap({ excerpt(of: fields[$0], around: word) }).first else {
                return nil
            }
            explanation = explanation ?? first
        }
        return explanation
    }

    // MARK: Pieces

    /// Whether the folded `text` has the word in it. Like the search, it compares code points.
    private static func occurs(_ word: String, in text: String) -> Bool {
        text.utf8.firstRange(of: word.utf8) != nil
    }

    /// The excerpt of a field around the first place its text has the word, or nil if the text, taken letter by letter,
    /// does not have it.
    private static func excerpt(of field: SearchField, around word: String) -> SearchExcerptResult? {
        let text = SearchFolding.collapsingWhitespace(field.text)
        guard let match = locate(word, in: text) else { return nil }
        let from = text.index(match.lowerBound, offsetBy: -charactersBefore, limitedBy: text.startIndex)
            ?? text.startIndex
        let to = text.index(match.upperBound, offsetBy: charactersAfter, limitedBy: text.endIndex) ?? text.endIndex
        var line = from > text.startIndex ? "…" : ""
        line += text[from..<match.lowerBound]
        let markStart = line.unicodeScalars.count
        line += text[match]
        let markEnd = line.unicodeScalars.count
        line += text[match.upperBound..<to]
        if to < text.endIndex {
            line += "…"
        }
        // The range is made of indexes of the line itself, counted by code points, so that it holds whatever the
        // characters around the word are.
        let scalars = line.unicodeScalars
        let lower = scalars.index(scalars.startIndex, offsetBy: markStart)
        let upper = scalars.index(lower, offsetBy: markEnd - markStart)
        return SearchExcerptResult(label: field.label, text: line, highlight: lower..<upper)
    }

    /// The characters of `text` that fold into the first occurrence of the folded `word`. A character may fold into
    /// more than one letter ("ß" is "ss"), so the word is searched among the folded letters and carried back to the
    /// characters they came from.
    private static func locate(_ word: String, in text: String) -> Range<String.Index>? {
        let needle = Array(word.unicodeScalars)
        guard !needle.isEmpty else { return nil }
        var letters: [Unicode.Scalar] = []
        var origins: [Range<String.Index>] = []
        for index in text.indices {
            let origin = index..<text.index(after: index)
            let folded = text[index].isWhitespace ? " " : SearchFolding.letters(String(text[index]))
            for letter in folded.unicodeScalars {
                letters.append(letter)
                origins.append(origin)
            }
        }
        guard letters.count >= needle.count else { return nil }
        for start in 0...(letters.count - needle.count) {
            let end = start + needle.count
            if letters[start..<end].elementsEqual(needle) {
                return origins[start].lowerBound..<origins[end - 1].upperBound
            }
        }
        return nil
    }
}
