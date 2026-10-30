import Foundation

/// The checks of the codes of a bank account that an invoice prints and a QR payment carries: the IBAN (ISO 13616) and
/// the BIC (ISO 9362). A typo in either prints a QR code that banks reject, so a code that does not pass is not saved.
///
/// Spaces (the plain one, the no-break space and the narrow no-break space) and the case of the letters do not matter,
/// as a bank writes an IBAN in groups of four: `CZ65 0800 0000 1920 0014 5399`. Any other character is a typo.
nonisolated enum BankCodes {
    /// The lengths an IBAN has: Norway's is the shortest, and none is longer than 34 characters.
    private static let ibanLengths = 15...34

    /// Whether `text` is an IBAN: the two letters of a country, two check digits and the letters and digits of the
    /// account, 15 to 34 characters together, whose check digits pass the test of ISO 7064 (the whole number, read with
    /// the first four characters moved to its end and every letter as two digits, A = 10 to Z = 35, leaves 1 when it is
    /// divided by 97).
    static func isValidIBAN(_ text: String) -> Bool {
        guard let code = compact(text), ibanLengths.contains(code.count) else { return false }
        guard isLetter(code[0]), isLetter(code[1]), isDigit(code[2]), isDigit(code[3]) else { return false }
        var remainder = 0
        for scalar in code[4...] + code[..<4] {
            if isDigit(scalar) {
                remainder = (remainder * 10 + Int(scalar.value - zero)) % 97
            } else {
                // A letter is two digits.
                remainder = (remainder * 100 + Int(scalar.value - capitalA) + 10) % 97
            }
        }
        return remainder == 1
    }

    /// `text` in capitals without its spaces, as an IBAN or a BIC is stored, printed and put into a QR code:
    /// `CZ6508000000192000145399`. Any other character stays as it is.
    static func normalized(_ text: String) -> String {
        String(String.UnicodeScalarView(text.unicodeScalars.filter { !spaces.contains($0) })).uppercased()
    }

    /// Whether `text` is a BIC: 8 or 11 letters and digits, the code of the bank (four) and of the place (two) and of
    /// the branch (three, which may be left out) around the two letters of the country.
    static func isValidBIC(_ text: String) -> Bool {
        guard let code = compact(text), code.count == 8 || code.count == 11 else { return false }
        return isLetter(code[4]) && isLetter(code[5])
    }

    // MARK: Characters

    private static let zero = UnicodeScalar("0").value
    private static let capitalA = UnicodeScalar("A").value

    /// The spaces a code is written with: the plain one, the no-break space and the narrow no-break space.
    private static let spaces: Set<UnicodeScalar> = [" ", "\u{00A0}", "\u{202F}"]

    /// The characters of `text` in capitals without its spaces, or nil when it has any character other than an ASCII
    /// letter, an ASCII digit or a space.
    private static func compact(_ text: String) -> [UnicodeScalar]? {
        var code: [UnicodeScalar] = []
        for scalar in text.unicodeScalars {
            switch scalar {
            case _ where spaces.contains(scalar):
                continue
            case "a"..."z":
                code.append(UnicodeScalar(scalar.value - 32) ?? scalar)
            case "A"..."Z", "0"..."9":
                code.append(scalar)
            default:
                return nil
            }
        }
        return code
    }

    private static func isLetter(_ scalar: UnicodeScalar) -> Bool {
        ("A"..."Z").contains(scalar)
    }

    private static func isDigit(_ scalar: UnicodeScalar) -> Bool {
        ("0"..."9").contains(scalar)
    }
}
