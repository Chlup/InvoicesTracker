import Foundation

/// The one rule that folds text for the search. The document of an invoice and the words of a query are both folded
/// with it, so that finding a word is finding a piece of plain text: lowercase, without diacritics, with every run of
/// whitespace as one space.
nonisolated enum SearchFolding {
    /// The locale that diacritics are removed with: Czech, so that "Ť" and "T" fold alike.
    private static let czechLocale = Locale(identifier: "cs_CZ")

    /// `text` in lowercase and without diacritics, with every run of whitespace (a no-break space U+00A0 and a narrow
    /// no-break space U+202F among it) as one space, and none at the ends: `Příbram – Brod` is `pribram – brod`.
    ///
    /// The NUL character is dropped, because SQLite reads a pattern and a query string only up to the first one.
    static func fold(_ text: String) -> String {
        collapsingWhitespace(letters(text))
    }

    /// The words of a query: the folded query split at its spaces. A query of nothing but whitespace has none.
    static func words(_ query: String) -> [String] {
        fold(query).split(separator: " ").map { String($0) }
    }

    /// `text` with the case and the diacritics of its letters folded and nothing else changed, which is what the
    /// excerpt needs to find where a word sits in the text as it is written.
    static func letters(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: czechLocale)
    }

    /// `text` with every run of whitespace as one space, none at the ends, and without NUL characters.
    static func collapsingWhitespace(_ text: String) -> String {
        var collapsed = String.UnicodeScalarView()
        var gap = false
        for scalar in text.unicodeScalars where scalar.value != 0 {
            if scalar.properties.isWhitespace {
                gap = !collapsed.isEmpty
            } else {
                if gap {
                    collapsed.append(" ")
                    gap = false
                }
                collapsed.append(scalar)
            }
        }
        return String(collapsed)
    }
}
