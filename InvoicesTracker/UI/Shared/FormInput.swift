import Foundation

/// Why a form did not save what was typed in it.
nonisolated enum FormSaveError: Error, Equatable {
    /// Something typed is not right; the `errors` of the form say what.
    case invalid

    /// Another save of the form is still running.
    case alreadySaving
}

/// Reading what is typed into the fields that the forms of a client and of a template share.
nonisolated enum FormInput {
    /// `text` without the white space around it.
    static func trimmed(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// The days of a due time as typed: digits only, around which spaces do not matter, and no more than
    /// `EditorLimits.dueDays` allows. Nil for any other text, an empty one too.
    static func dueDays(in text: String) -> Int? {
        let digits = trimmed(text)
        guard !digits.isEmpty, digits.unicodeScalars.allSatisfy({ ("0"..."9").contains($0) }),
            let days = Int(digits), EditorLimits.dueDays.contains(days)
        else {
            return nil
        }
        return days
    }
}

nonisolated extension VatMode {
    /// The name of the mode in the choice of the forms of a client and of a template, where the longest one is
    /// written without "(bez DPH)", which Faktury and the editor write in full.
    var formLabel: String {
        self == .outsideCountry ? "Mimo tuzemsko – § 9 odst. 1" : label
    }
}
