import Foundation

/// What the parsers of the pages and the PDFs of the Ministry of Finance need to read their text: character references
/// turned into characters, tags taken out, and white space squeezed (the last is for the text of a PDF too). It does
/// not parse HTML, and it never loads anything.
nonisolated enum HTMLText {
    /// `html` with the character references replaced by the characters they stand for: `&iacute;` and `&#237;` and
    /// `&#xED;` all become í. A reference that is not known, or is not a character, stays as it is. A reference is
    /// decoded once, so `&amp;iacute;` becomes `&iacute;`.
    ///
    /// The named references are the ones of Latin-1 (`&iacute;`, `&sect;`, `&nbsp;`), the markup characters, the
    /// usual punctuation, and the letters of Czech that are not in Latin-1 (`&ccaron;`). The pages of the Ministry
    /// write the others as plain characters or as numbers.
    static func decodingReferences(_ html: String) -> String {
        html.replacing(#/&(#[0-9]+|#[xX][0-9a-fA-F]+|[A-Za-z][A-Za-z0-9]*);/#) { match in
            character(forReference: match.1) ?? String(match.0)
        }
    }

    /// `html` with every tag replaced by a space, so that words in neighbouring elements stay apart. A tag starts with
    /// `<` and a letter, `/`, `!` or `?`, and ends at the first `>` outside the quotes of its attributes. A `<` that
    /// starts no tag is text.
    static func removingTags(_ html: String) -> String {
        html.replacing(#/<[A-Za-z\/!?](?:[^>"']|"[^"]*"|'[^']*')*>/#, with: " ")
    }

    /// `text` with every run of white space, no-break spaces included, replaced by one space, and with no space at
    /// either end. The letters are composed, so that a letter with a mark is one character whichever way it was
    /// written.
    static func collapsingWhitespace(_ text: String) -> String {
        text.split(whereSeparator: \.isWhitespace).joined(separator: " ").precomposedStringWithCanonicalMapping
    }

    // MARK: Character references

    /// The text a reference stands for. `body` is what is between `&` and `;`.
    private static func character(forReference body: Substring) -> String? {
        guard body.first == "#" else { return named[String(body)] }
        let digits = body.dropFirst()
        let isHexadecimal = digits.first == "x" || digits.first == "X"
        guard let number = UInt32(isHexadecimal ? digits.dropFirst() : digits, radix: isHexadecimal ? 16 : 10),
            number != 0,
            let scalar = Unicode.Scalar(number)
        else {
            return nil
        }
        return String(Character(scalar))
    }

    /// The names of the characters 160 to 255 of Latin-1, in the order of the characters: `nbsp` is 160 and `yuml` is
    /// 255.
    private static let latin1Names = """
        nbsp iexcl cent pound curren yen brvbar sect uml copy ordf laquo not shy reg macr
        deg plusmn sup2 sup3 acute micro para middot cedil sup1 ordm raquo frac14 frac12 frac34 iquest
        Agrave Aacute Acirc Atilde Auml Aring AElig Ccedil Egrave Eacute Ecirc Euml Igrave Iacute Icirc Iuml
        ETH Ntilde Ograve Oacute Ocirc Otilde Ouml times Oslash Ugrave Uacute Ucirc Uuml Yacute THORN szlig
        agrave aacute acirc atilde auml aring aelig ccedil egrave eacute ecirc euml igrave iacute icirc iuml
        eth ntilde ograve oacute ocirc otilde ouml divide oslash ugrave uacute ucirc uuml yacute thorn yuml
        """

    private static let named: [String: String] = {
        var table: [String: String] = [
            "amp": "&", "lt": "<", "gt": ">", "quot": "\"", "apos": "'",
            "ndash": "\u{2013}", "mdash": "\u{2014}", "hellip": "\u{2026}",
            "lsquo": "\u{2018}", "rsquo": "\u{2019}", "ldquo": "\u{201C}", "rdquo": "\u{201D}", "bdquo": "\u{201E}",
            // The letters of Czech that are not in Latin-1.
            "Ccaron": "\u{010C}", "ccaron": "\u{010D}", "Dcaron": "\u{010E}", "dcaron": "\u{010F}",
            "Ecaron": "\u{011A}", "ecaron": "\u{011B}", "Ncaron": "\u{0147}", "ncaron": "\u{0148}",
            "Rcaron": "\u{0158}", "rcaron": "\u{0159}", "Scaron": "\u{0160}", "scaron": "\u{0161}",
            "Tcaron": "\u{0164}", "tcaron": "\u{0165}", "Uring": "\u{016E}", "uring": "\u{016F}",
            "Zcaron": "\u{017D}", "zcaron": "\u{017E}",
        ]
        for (offset, name) in latin1Names.split(whereSeparator: \.isWhitespace).enumerated() {
            guard let scalar = Unicode.Scalar(UInt32(160 + offset)) else {
                preconditionFailure("Not a character of Latin-1: \(name)")
            }
            table[String(name)] = String(Character(scalar))
        }
        return table
    }()
}
