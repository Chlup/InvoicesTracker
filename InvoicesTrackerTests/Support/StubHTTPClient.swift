import Foundation
import os
@testable import InvoicesTracker

/// An `HTTPClient` for tests: it answers from a table by exact URL and remembers every request, in order. A URL that is
/// not in the table gets a 404, like a page that does not exist. It never touches the network.
final class StubHTTPClient: HTTPClient {
    private let answers: [URL: Result<Data, any Error>]
    private let log = OSAllocatedUnfairLock<[URL]>(initialState: [])

    /// - Parameters:
    ///   - bodies: The body to answer with, by URL.
    ///   - failures: The error to fail with, by URL (an `HTTPError`, or any other error a client can throw). A URL in
    ///     both tables fails.
    init(_ bodies: [URL: Data] = [:], failures: [URL: any Error] = [:]) {
        var answers = bodies.mapValues { Result<Data, any Error>.success($0) }
        for (url, error) in failures {
            answers[url] = .failure(error)
        }
        self.answers = answers
    }

    /// Every URL asked for so far, in the order of the requests.
    var requests: [URL] {
        log.withLock { $0 }
    }

    func get(_ url: URL) async throws -> Data {
        log.withLock { $0.append(url) }
        switch answers[url] {
        case .success(let body)?: return body
        case .failure(let error)?: throw error
        case nil: throw HTTPError.status(404)
        }
    }
}
