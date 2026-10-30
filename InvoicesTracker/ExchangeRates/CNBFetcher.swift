import Foundation

/// The addresses of the files with the exchange rates of the ČNB.
nonisolated enum CNBEndpoints {
    private static let directory =
        "https://www.cnb.cz/cs/financni-trhy/devizovy-trh/kurzy-devizoveho-trhu/kurzy-devizoveho-trhu/"

    /// The yearly file of `year`: a row of rates for each business day of the year that the ČNB has declared rates on.
    static func yearly(_ year: Int) -> URL {
        address("rok.txt?rok=\(year)")
    }

    /// The daily file for `day`: the rates the ČNB declared on that day. The first line of the file says on which day
    /// they were declared, which may not be `day` when the ČNB declared nothing on it.
    static func daily(_ day: CivilDate) -> URL {
        // The ISO text has four digits for the year and two for the month and the day, like the text the ČNB wants, but
        // the other way round: 2026-10-16 is 16.10.2026.
        let parts = day.iso.split(separator: "-")
        return address("denni_kurz.txt?date=\(parts[2]).\(parts[1]).\(parts[0])")
    }

    private static func address(_ file: String) -> URL {
        guard let url = URL(string: directory + file) else {
            preconditionFailure("Not an address of the ČNB: \(file)")
        }
        return url
    }
}

/// Downloads the exchange-rate files of the ČNB and reads them.
///
/// A file that cannot be read is an error, never a part of its rates: the parsers reject a file as a whole, and so does
/// the fetcher, which adds nothing to them.
nonisolated struct CNBFetcher: Sendable {
    let http: any HTTPClient

    /// The rates of every business day of `year` that the ČNB has declared rates on so far.
    /// - Throws: `HTTPError` when the file cannot be downloaded, `CNBParseError` when it cannot be read, and any other
    ///   error the client throws as it is (a failure of TLS, a cancellation), so a caller handles any `Error`.
    func fetchYear(_ year: Int) async throws -> [CNBRateRow] {
        let text = try await text(of: CNBEndpoints.yearly(year))
        return try CNBYearlyParser.parse(text)
    }

    /// The rates in the daily file for `day`, and the day the file says they were declared on. That is not `day` when
    /// the ČNB declared no rates on it and answers with the file of an earlier day.
    /// - Throws: `HTTPError` when the file cannot be downloaded, `CNBParseError` when it cannot be read, and any other
    ///   error the client throws as it is (a failure of TLS, a cancellation), so a caller handles any `Error`.
    func fetchDay(_ day: CivilDate) async throws -> (declaredOn: CivilDate, rows: [CNBRateRow]) {
        let text = try await text(of: CNBEndpoints.daily(day))
        return try CNBDailyParser.parse(text)
    }

    /// The text of the file at `url`. Bytes that are no text in either encoding are a file in a format the parsers do
    /// not read.
    private func text(of url: URL) async throws -> String {
        let data = try await http.get(url)
        guard let text = ResponseText.decode(data) else { throw CNBParseError.malformedHeader }
        return text
    }
}
