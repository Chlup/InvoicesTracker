import Foundation
import Testing
@testable import InvoicesTracker

/// The real client, `URLSessionHTTPClient`, without a network: its session is the one the app uses, with
/// `StubURLProtocol` as its only network.
struct HTTPClientTests {
    private func client() -> URLSessionHTTPClient {
        let configuration = URLSessionHTTPClient.makeConfiguration()
        configuration.protocolClasses = [StubURLProtocol.self]
        return URLSessionHTTPClient(configuration: configuration)
    }

    private func body(of address: String) async throws -> String {
        String(decoding: try await client().get(webURL(address)), as: UTF8.self)
    }

    // MARK: The two servers

    @Test func anAddressOutsideTheTwoServersIsRefusedWithoutARequest() async {
        // The client of the app, with no stub: it must refuse before it asks anyone, so this needs no network.
        await #expect(throws: HTTPError.hostNotAllowed("example.com")) {
            try await URLSessionHTTPClient().get(webURL("https://example.com"))
        }
    }

    @Test(arguments: [
        ("https://example.com/ok", "example.com"),
        ("http://www.cnb.cz/ok", "www.cnb.cz"),  // not https
        ("http://mf.gov.cz/ok", "mf.gov.cz"),
        ("ftp://www.cnb.cz/ok", "www.cnb.cz"),
        ("https://www.cnb.cz.evil.example/ok", "www.cnb.cz.evil.example"),  // the name only begins like one
        ("https://mf.gov.cz.evil.example/ok", "mf.gov.cz.evil.example"),
        ("https://evil.example/www.cnb.cz/ok", "evil.example"),  // the name is in the path
        ("https://www.cnb.cz@evil.example/ok", "evil.example"),  // the name is the user
        ("https://www.mf.gov.cz/ok", "www.mf.gov.cz"),  // exactly the two names and no neighbours
        ("https://cnb.cz/ok", "cnb.cz"),
        ("https://gov.cz/ok", "gov.cz"),
        ("https://api.cnb.cz/ok", "api.cnb.cz"),
        ("https://www.cnb.cz./ok", "www.cnb.cz."),
        ("https://www.cnb.cz:8443/ok", "www.cnb.cz"),  // not the port of https
        ("https://mf.gov.cz:80/ok", "mf.gov.cz"),
        ("https://www.cnb.cz:443@evil.example/ok", "evil.example"),  // the name and the port are the user
        ("file:///etc/hosts", ""),
        ("mailto:someone@example.com", ""),
    ])
    func addressesOutsideTheTwoServersAreRefused(_ address: String, _ host: String) async {
        // With the stub as the only network, a request that is not refused fails differently, or is answered.
        await #expect(throws: HTTPError.hostNotAllowed(host)) {
            try await client().get(webURL(address))
        }
    }

    @Test(arguments: [
        "HTTPS://WWW.CNB.CZ/ok", "https://Www.Cnb.Cz/ok", "HtTpS://MF.GOV.CZ/ok", "https://www.cnb.cz:443/ok",
        "https://mf.gov.cz:443/ok",
    ])
    func theSchemeAndTheHostAreComparedWithoutRegardToCaseAndTheStandardPortIsAllowed(_ address: String) async throws {
        #expect(URLSessionHTTPClient.isAllowed(webURL(address)))
        #expect(try await body(of: address) == "ok")
    }

    @Test func theTwoServersAreAllowed() async throws {
        #expect(URLSessionHTTPClient.allowedHosts == ["www.cnb.cz", "mf.gov.cz"])
        #expect(try await body(of: "https://www.cnb.cz/ok") == "ok")
        #expect(try await body(of: "https://mf.gov.cz/ok") == "ok")
        #expect(URLSessionHTTPClient.isAllowed(webURL("https://www.cnb.cz/cs/financni-trhy/x.txt?rok=2026")))
        #expect(URLSessionHTTPClient.isAllowed(webURL("https://mf.gov.cz/assets/attachments/x.pdf")))
        #expect(!URLSessionHTTPClient.isAllowed(webURL("https://example.com/")))
    }

    // MARK: Answers

    @Test func aStatusOf200IsAnAnswerWithItsBody() async throws {
        #expect(try await body(of: "https://www.cnb.cz/status/200") == "body")
    }

    @Test(arguments: [201, 204, 299])
    func otherStatusesOf2xxAreAnswersToo(_ status: Int) async throws {
        _ = try await client().get(webURL("https://www.cnb.cz/status/\(status)"))
    }

    @Test(arguments: [300, 301, 304, 400, 403, 404, 410, 500, 503])
    func anyOtherStatusIsAnError(_ status: Int) async {
        await #expect(throws: HTTPError.status(status)) {
            try await client().get(webURL("https://www.cnb.cz/status/\(status)"))
        }
    }

    @Test(arguments: [
        URLError.Code.notConnectedToInternet, URLError.Code.networkConnectionLost, URLError.Code.timedOut,
        URLError.Code.cannotFindHost, URLError.Code.dnsLookupFailed, URLError.Code.cannotConnectToHost,
    ])
    func aMissingConnectionIsOffline(_ code: URLError.Code) async {
        await #expect(throws: HTTPError.offline) {
            try await client().get(webURL("https://mf.gov.cz/fail/\(code.rawValue)"))
        }
    }

    @Test(arguments: [
        URLError.Code.secureConnectionFailed, URLError.Code.serverCertificateUntrusted, URLError.Code.cancelled,
        URLError.Code.badServerResponse, URLError.Code.userAuthenticationRequired,
    ])
    func otherFailuresEscapeAsTheyAre(_ code: URLError.Code) async {
        await #expect(
            performing: { try await client().get(webURL("https://mf.gov.cz/fail/\(code.rawValue)")) },
            throws: { ($0 as? URLError)?.code == code }
        )
    }

    // MARK: Redirects

    @Test func aRedirectToAnotherServerIsNotFollowed() async {
        // The stub fails any request to a host that is not one of the two, so a redirect that was followed would end
        // in a different error.
        await #expect(throws: HTTPError.hostNotAllowed("example.com")) {
            try await client().get(webURL("https://www.cnb.cz/redirect/example.com"))
        }
        await #expect(throws: HTTPError.hostNotAllowed("www.cnb.cz.evil.example")) {
            try await client().get(webURL("https://mf.gov.cz/redirect/www.cnb.cz.evil.example"))
        }
    }

    @Test func aRedirectBetweenTheTwoServersIsFollowed() async throws {
        #expect(try await body(of: "https://www.cnb.cz/redirect/mf.gov.cz") == "ok")
        #expect(try await body(of: "https://mf.gov.cz/redirect/www.cnb.cz") == "ok")
    }

    // MARK: What the request says and what the session keeps

    @Test func theRequestIsAPlainGetThatSaysTheNameOfTheAppAndAFixedLanguageAndSendsNoCookie() async throws {
        let echo = try await body(of: "https://www.cnb.cz/echo")
        let echoed = echo.split(separator: "\n", omittingEmptySubsequences: false)
        // The method, the User-Agent, the Accept-Language (not the languages of the Mac), and an empty Cookie.
        #expect(echoed == ["GET", "InvoicesTracker", "cs", ""])
    }

    @Test func theRequestIgnoresTheCacheAndCookiesAndTimesOutAfterThirtySeconds() {
        let request = URLSessionHTTPClient.makeRequest(for: webURL("https://www.cnb.cz/ok"))
        #expect(request.url == webURL("https://www.cnb.cz/ok"))
        #expect(request.httpMethod == "GET")
        #expect(request.httpBody == nil)
        #expect(request.httpBodyStream == nil)
        #expect(request.cachePolicy == .reloadIgnoringLocalCacheData)
        #expect(request.timeoutInterval == 30)
        #expect(request.httpShouldHandleCookies == false)
        #expect(request.allHTTPHeaderFields == ["User-Agent": "InvoicesTracker", "Accept-Language": "cs"])
    }

    @Test func theSessionKeepsNothing() {
        let configuration = URLSessionHTTPClient.makeConfiguration()
        #expect(configuration.urlCache == nil)
        #expect(configuration.requestCachePolicy == .reloadIgnoringLocalCacheData)
        #expect(configuration.httpCookieStorage == nil)
        #expect(configuration.httpShouldSetCookies == false)
        #expect(configuration.httpCookieAcceptPolicy == .never)
        #expect(configuration.urlCredentialStorage == nil)
        #expect(configuration.timeoutIntervalForRequest == 30)
        #expect(configuration.timeoutIntervalForResource == 30)
        #expect(configuration.waitsForConnectivity == false)
    }
}
