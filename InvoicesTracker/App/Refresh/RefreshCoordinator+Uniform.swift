import Foundation
import os

/// The search for the uniform rate of the finished year, and the fetch log of the refresh.
extension RefreshCoordinator {
    // MARK: The uniform rate

    /// Looks for the uniform rates that `actions` ask for, and gives the reminders that end the searches.
    func searchUniformRates(_ actions: [RefreshAction], now: Date, state: inout RefreshState) async {
        var found: Set<Int> = []
        for action in actions {
            switch action {
            case .checkUniformRate(let year):
                if await search(year, now: now, state: &state) {
                    found.insert(year)
                }
                guard !Task.isCancelled else { return }
            case .uniformRateReminder(let year):
                remind(year, found: found.contains(year), state: &state)
            case .fetchCNBDays, .fetchCNBYears, .fetchCNBYearsForPayments:
                break
            }
        }
        if state.finishedYearsLookedForUniformRate.allSatisfy({ state.gaveUpUniform.contains($0) }) {
            uniformError = nil
        }
    }

    /// One search for the uniform rates of `year`, away from the main actor, with its requests logged. Returns
    /// whether the rates were found.
    ///
    /// - An answer uses up the search of the (Prague) day: the rates found, nothing out yet, or a page that cannot be
    ///   read. So does a failure of the server, but not a missing connection: then the next trigger searches again.
    /// - A 404 for the index of the issues means that the index of the new year is not published yet: nothing out yet.
    /// - A page that cannot be read stays shown with its address until a later search of the year gets another answer,
    ///   and it is not counted as checked, so the next search reads it again.
    private func search(_ year: Int, now: Date, state: inout RefreshState) async -> Bool {
        let search = await Self.findUniformRate(
            year: year, alreadyChecked: state.checkedIssues[year] ?? [], http: gfr.http, clock: clock)
        await logRequests(of: search, year: year)
        guard !Task.isCancelled else { return false }
        let today = CzechCalendar.pragueDate(now)
        switch search.result {
        case .success(.found(let finding)):
            state.lastUniformCheck = today
            state.unreadableUniformPages[year] = nil
            foundUniformInstructions[year] = finding.instruction
            uniformError = nil
            onUniformRateFound?(finding)
            return true
        case .success(.notYet(let checkedIssues)):
            state.lastUniformCheck = today
            state.checkedIssues[year] = checkedIssues
            state.unreadableUniformPages[year] = nil
            foundUniformInstructions[year] = nil
            uniformError = nil
        case .success(.unreadable(let url, _)):
            state.lastUniformCheck = today
            state.unreadableUniformPages[year] = url
            foundUniformInstructions[year] = nil
            uniformError = nil
        case .failure where search.isMissingIndex(of: year):
            state.lastUniformCheck = today
            state.unreadableUniformPages[year] = nil
            foundUniformInstructions[year] = nil
            uniformError = nil
        case .failure(let error):
            if (error as? HTTPError) != .offline {
                state.lastUniformCheck = today
            }
            uniformError = "Jednotný kurz \(year) se nepodařilo zkontrolovat: \(Self.reason(error))."
        }
        return false
    }

    /// Ends the search for the uniform rate of `year`, on or after 31 March of the next year: unless the rate was
    /// found in this run, the person is reminded to enter it by hand, and it is not looked for any more. A rate that
    /// was found is offered without a reminder, and looked for again while it is not stored.
    private func remind(_ year: Int, found: Bool, state: inout RefreshState) {
        guard !found else { return }
        state.gaveUpUniform.insert(year)
        onUniformRateReminder?(year)
    }

    /// A search for the uniform rates of a year, and every request it made.
    private nonisolated struct UniformSearch: Sendable {
        let result: Result<GFROutcome, any Error>
        let requests: [RecordedRequest]

        /// Whether the search failed because the index of the issues does not exist (yet).
        func isMissingIndex(of year: Int) -> Bool {
            guard case .failure(let error) = result, (error as? HTTPError) == .status(404), let last = requests.last
            else {
                return false
            }
            return last.url == GFRParser.indexURL(forYear: year)
        }
    }

    /// Searches with a `GFRFetcher` away from the main actor, through a client that records every request.
    @concurrent
    private nonisolated static func findUniformRate(
        year: Int, alreadyChecked: Set<URL>, http: any HTTPClient, clock: any AppClock
    ) async -> UniformSearch {
        let recorder = RecordingHTTPClient(base: http, clock: clock)
        let result: Result<GFROutcome, any Error>
        do {
            result = .success(try await GFRFetcher(http: recorder).find(year: year, alreadyChecked: alreadyChecked))
        } catch {
            result = .failure(error)
        }
        return UniformSearch(result: result, requests: recorder.requests)
    }

    // MARK: Fetch log

    /// Adds a request to the fetch log: what was asked for, whether it worked, and a few words. Never a body of an
    /// answer. A failure to add it is logged and does not stop the refresh.
    func logRequest(_ kind: FetchKind, _ url: URL, ok: Bool, message: String, at time: Date? = nil) async {
        let entry = FetchLogEntry(
            at: time ?? clock.now(), kind: kind, target: url.absoluteString, ok: ok, message: message)
        do {
            try await database.appendFetchLog(entry)
        } catch {
            Self.log("Adding a request to the fetch log", failedWith: error)
        }
    }

    /// Adds a failed request to the fetch log, with the kind of the failure.
    func logRequest(_ kind: FetchKind, _ url: URL, failedWith error: any Error) async {
        await logRequest(kind, url, ok: false, message: Self.logReason(error))
    }

    /// Logs the requests of a search in their order. A page or a PDF that came but cannot be read is logged as failed:
    /// the PDFs when PDFs were read, otherwise the page the outcome names.
    private func logRequests(of search: UniformSearch, year: Int) async {
        var unreadable: Set<Int> = []
        if case .success(.unreadable(let url, _)) = search.result {
            let pdfs = search.requests.indices.filter { Self.kind(of: search.requests[$0].url, year: year) == .gfrPDF }
            unreadable = Set(pdfs.isEmpty ? search.requests.indices.filter { search.requests[$0].url == url } : pdfs)
        }
        for (index, request) in search.requests.enumerated() {
            let kind = Self.kind(of: request.url, year: year)
            if let error = request.error {
                await logRequest(kind, request.url, ok: false, message: Self.logReason(error), at: request.at)
            } else if unreadable.contains(index) {
                await logRequest(kind, request.url, ok: false, message: "not readable", at: request.at)
            } else {
                await logRequest(kind, request.url, ok: true, message: "", at: request.at)
            }
        }
    }

    /// What a request of a search for a uniform rate was for: the index of the year, a PDF, or the page of an issue.
    private nonisolated static func kind(of url: URL, year: Int) -> FetchKind {
        if url == GFRParser.indexURL(forYear: year) {
            return .gfrIndex
        }
        return url.path(percentEncoded: false).lowercased().hasSuffix(".pdf") ? .gfrPDF : .gfrIssue
    }

    /// A few English words for the fetch log about why a request failed. Never more than the kind of failure.
    private nonisolated static func logReason(_ error: any Error) -> String {
        switch error {
        case HTTPError.offline: "offline"
        case HTTPError.status(let status): "status \(status)"
        case HTTPError.hostNotAllowed: "address not allowed"
        case is CNBParseError: "file not readable"
        default: "request failed"
        }
    }
}

/// A request that `RecordingHTTPClient` passed on: where to, when it ended, and the error it ended with, if any.
private nonisolated struct RecordedRequest: Sendable {
    let url: URL
    let at: Date
    let error: (any Error)?
}

/// An `HTTPClient` that passes every request on to another one and remembers it, so that every request of a search
/// can be logged, whatever the search ended with.
private nonisolated final class RecordingHTTPClient: HTTPClient {
    private let base: any HTTPClient
    private let clock: any AppClock
    private let log = OSAllocatedUnfairLock<[RecordedRequest]>(initialState: [])

    init(base: any HTTPClient, clock: any AppClock) {
        self.base = base
        self.clock = clock
    }

    /// The requests so far, in order.
    var requests: [RecordedRequest] {
        log.withLock { $0 }
    }

    func get(_ url: URL) async throws -> Data {
        do {
            let data = try await base.get(url)
            let request = RecordedRequest(url: url, at: clock.now(), error: nil)
            log.withLock { $0.append(request) }
            return data
        } catch {
            let request = RecordedRequest(url: url, at: clock.now(), error: error)
            log.withLock { $0.append(request) }
            throw error
        }
    }
}
