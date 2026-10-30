import Foundation

/// What a request to a public server was for.
nonisolated enum FetchKind: String, Sendable, Hashable, Codable {
    /// The ČNB file of one day.
    case cnbDaily

    /// The ČNB file of one year.
    case cnbYearly

    /// The index of the Finanční zpravodaj issues of a year.
    case gfrIndex

    /// The page of one issue.
    case gfrIssue

    /// The PDF of one issue.
    case gfrPDF
}

/// One request to a public server and how it went. The log never holds amounts or personal data, only what was asked
/// for and whether it worked.
nonisolated struct FetchLogEntry: Sendable, Hashable, Codable {
    var at: Date
    var kind: FetchKind

    /// What was asked for: a day, a year or an address.
    var target: String
    var ok: Bool
    var message: String
}
