import Foundation

/// The placeholders in the text of a template item, filled in for the invoice that is made from it.
nonisolated enum TemplateText {
    private static let englishMonthNames = [
        "January", "February", "March", "April", "May", "June",
        "July", "August", "September", "October", "November", "December",
    ]

    /// `text` with the placeholders replaced by the month and the year of `duzp`:
    /// - `{měsíc}` by the name of the month in Czech, in the nominative and in lower case (`září`);
    /// - `{month}` by the name of the month in English (`September`);
    /// - `{rok}` and `{year}` by the year (`2026`).
    ///
    /// Anything else is left as it is, and so is a placeholder written in another case.
    static func fill(_ text: String, duzp: CivilDate) -> String {
        text
            .replacing("{měsíc}", with: CzechFormat.monthNames[duzp.month - 1])
            .replacing("{month}", with: englishMonthNames[duzp.month - 1])
            .replacing("{rok}", with: String(duzp.year))
            .replacing("{year}", with: String(duzp.year))
    }
}
