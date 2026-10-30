import Foundation
import os

/// A way to ask a public server for a file: one plain GET request that gives the body of the answer.
///
/// The app reaches the network only through this protocol, so that the code which reads the answers can be tested with
/// answers made up in advance and never needs a network.
nonisolated protocol HTTPClient: Sendable {
    /// The body of the answer to a GET request for `url`.
    /// - Throws: `HTTPError` when the request is not made (the address is not one the app may ask), the server cannot
    ///   be reached, or it answers with anything but a success. Any other failure escapes as the error it is: the
    ///   `URLError` of a failed TLS handshake, a cancellation, a response that is no HTTP. So a caller handles any
    ///   `Error`, and not only `HTTPError`.
    func get(_ url: URL) async throws -> Data
}

/// Why a request for a public file gave no file.
nonisolated enum HTTPError: Error, Equatable {
    /// The server answered with a status outside 200 to 299. The number is the status.
    case status(Int)

    /// The address is not one the app may ask, so nothing was sent. Only `https` addresses on `www.cnb.cz` and
    /// `mf.gov.cz` are. The text is the host of the address, and empty when the address has none.
    case hostNotAllowed(String)

    /// The server could not be reached: there is no connection to the internet, the connection broke or timed out, the
    /// name of the server is not known (the DNS lookup failed), or no connection to it could be made.
    case offline
}

/// The `HTTPClient` of the app: plain GET requests over an ephemeral `URLSession`, to the two servers the app needs
/// and to no others.
///
/// - `www.cnb.cz` publishes the exchange rates of the ČNB, and `mf.gov.cz` the Finanční zpravodaj of the Ministry of
///   Finance, which announces the uniform rates of the GFŘ. Both are public files.
/// - Nothing is kept: no disk cache, no cookies, no credentials. Every request asks the server again.
/// - The request says the name of the app (`User-Agent: InvoicesTracker`) and a fixed language (`Accept-Language: cs`, not
///   the languages the Mac is set to), and nothing else of its own: no identifier, no version, no cookie. The system
///   adds the headers every HTTP request has (`Accept`, `Accept-Encoding`, `Connection`, `Host`), which say nothing
///   about the person.
///
/// An address on any other host is refused before anything is sent, and so is a redirect to one: a server cannot send
/// the app to another place.
nonisolated struct URLSessionHTTPClient: HTTPClient {
    /// The servers the app may ask, and no others. A host has to be exactly one of these: `www.mf.gov.cz`,
    /// `api.cnb.cz` and `www.cnb.cz.example.com` are not.
    static let allowedHosts: Set<String> = ["www.cnb.cz", "mf.gov.cz"]

    /// What the app calls itself to a server.
    private static let userAgent = "InvoicesTracker"

    /// The language the app asks for, whatever the Mac is set to: both servers publish in Czech. Without it the system
    /// sends the list of the languages of the Mac.
    private static let language = "cs"

    /// How long a request may take before it is given up, in seconds. It is the time without a byte coming in, and
    /// also the time for the whole answer.
    private static let timeout: TimeInterval = 30

    /// The failures that mean the server could not be reached. Others (a failed TLS handshake, a cancellation, a
    /// response that is no HTTP) are not that, and escape as they are.
    private static let offlineCodes: Set<URLError.Code> = [
        .notConnectedToInternet, .networkConnectionLost, .timedOut, .cannotFindHost, .dnsLookupFailed,
        .cannotConnectToHost,
    ]

    private let session: URLSession

    init() {
        self.init(configuration: Self.makeConfiguration())
    }

    /// A client over a session made from `configuration`. The app uses `init()`; a test adds a network of its own to
    /// `makeConfiguration()`.
    init(configuration: URLSessionConfiguration) {
        session = URLSession(configuration: configuration)
    }

    /// Whether the app may ask `url`: it is an `https` address on one of `allowedHosts`, with no port or with the port
    /// of `https`, 443. The scheme and the host are compared without regard to case, as the servers do.
    static func isAllowed(_ url: URL) -> Bool {
        guard url.scheme?.lowercased() == "https",
            let host = url.host(percentEncoded: false)?.lowercased(),
            allowedHosts.contains(host),
            url.port == nil || url.port == 443
        else {
            return false
        }
        return true
    }

    /// The session the app asks over. It is ephemeral and it keeps nothing: no cache, no cookies and no credentials. A
    /// request that is not answered within 30 seconds is given up, and one that finds no connection fails at once
    /// instead of waiting for one.
    static func makeConfiguration() -> URLSessionConfiguration {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.httpCookieAcceptPolicy = .never
        configuration.urlCredentialStorage = nil
        configuration.timeoutIntervalForRequest = timeout
        configuration.timeoutIntervalForResource = timeout
        configuration.waitsForConnectivity = false
        return configuration
    }

    /// A GET request for `url` that ignores any cached copy, sends no cookies and says the name of the app and a fixed
    /// language, and nothing else of its own.
    static func makeRequest(for url: URL) -> URLRequest {
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: timeout)
        request.httpMethod = "GET"
        request.httpShouldHandleCookies = false
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue(language, forHTTPHeaderField: "Accept-Language")
        return request
    }

    func get(_ url: URL) async throws -> Data {
        guard Self.isAllowed(url) else {
            throw HTTPError.hostNotAllowed(url.host(percentEncoded: false) ?? "")
        }
        let redirects = AllowedRedirects()
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: Self.makeRequest(for: url), delegate: redirects)
        } catch let error as URLError where Self.offlineCodes.contains(error.code) {
            throw HTTPError.offline
        }
        // A refused redirect leaves the answer that holds it (a 3xx) as the final one, which is not what to report.
        if let host = redirects.refusedHost {
            throw HTTPError.hostNotAllowed(host)
        }
        guard let http = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }
        guard (200...299).contains(http.statusCode) else {
            throw HTTPError.status(http.statusCode)
        }
        return data
    }
}

/// Follows a redirect only to an address the client may ask, and remembers the host of the first one it refused.
private nonisolated final class AllowedRedirects: NSObject, URLSessionTaskDelegate, Sendable {
    private let refused = OSAllocatedUnfairLock<String?>(initialState: nil)

    /// The host of the first redirect that was not followed, if there was one. It is empty for an address with no
    /// host.
    var refusedHost: String? {
        refused.withLock { $0 }
    }

    /// This is the form with a completion handler and not the `async` one: the Swift compiler of Xcode 27.0 crashes on
    /// the `async` form in this target (it fails while it builds the Objective-C thunk of the method).
    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping @Sendable (URLRequest?) -> Void
    ) {
        if let url = request.url, URLSessionHTTPClient.isAllowed(url) {
            completionHandler(request)
            return
        }
        refused.withLock { host in
            if host == nil {
                host = request.url?.host(percentEncoded: false) ?? ""
            }
        }
        completionHandler(nil)
    }
}

/// The text of a file that was downloaded.
nonisolated enum ResponseText {
    /// The text of `data`. It is read as UTF-8, and when it is not UTF-8, as Windows-1250, the encoding that Czech
    /// files were written in before UTF-8. Nil if the bytes are neither.
    static func decode(_ data: Data) -> String? {
        String(data: data, encoding: .utf8) ?? String(data: data, encoding: .windowsCP1250)
    }
}
