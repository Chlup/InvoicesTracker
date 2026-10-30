import Foundation

/// The network of a test of `URLSessionHTTPClient`: it answers requests itself, so nothing leaves the process.
///
/// It holds no state. What it answers is chosen by the path of the request:
///
/// - `/ok` answers 200 with the body `ok`.
/// - `/status/503` answers with that status and the body `body`.
/// - `/fail/-1009` fails the way a request fails with that `URLError` code.
/// - `/redirect/mf.gov.cz` answers 302 with a redirect to `https://mf.gov.cz/ok`, which is followed or refused by
///   whoever sent the request, as a server's redirect would be.
/// - `/echo` answers 200 with the method, the `User-Agent`, the `Accept-Language` and the `Cookie` of the request, one
///   to a line.
///
/// Only the two servers the app may ask are answered. A request to any other host fails with `resourceUnavailable`,
/// which the client does not take for a missing connection, so a test that sends a request there fails instead of
/// getting an answer.
final class StubURLProtocol: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let url = request.url,
            ["www.cnb.cz", "mf.gov.cz"].contains(url.host(percentEncoded: false)?.lowercased())
        else {
            client?.urlProtocol(self, didFailWithError: URLError(.resourceUnavailable))
            return
        }
        let parts = url.path.split(separator: "/").map(String.init)
        switch (parts.first, parts.dropFirst().first) {
        case ("ok", _):
            respond(status: 200, body: "ok", from: url)
        case ("status", let code?):
            respond(status: Int(code) ?? 500, body: "body", from: url)
        case ("fail", let code?):
            client?.urlProtocol(self, didFailWithError: URLError(URLError.Code(rawValue: Int(code) ?? 0)))
        case ("redirect", let host?):
            redirect(to: "https://\(host)/ok", from: url)
        case ("echo", _):
            let names = ["User-Agent", "Accept-Language", "Cookie"]
            let headers = names.map { request.value(forHTTPHeaderField: $0) ?? "" }
            respond(status: 200, body: ([request.httpMethod ?? ""] + headers).joined(separator: "\n"), from: url)
        default:
            respond(status: 404, body: "", from: url)
        }
    }

    override func stopLoading() {}

    private func respond(status: Int, body: String, from url: URL) {
        let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: "HTTP/1.1", headerFields: nil)
        guard let response else { preconditionFailure("Not an HTTP response.") }
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    /// Asks the client to follow a redirect, and then answers with the redirect itself, which is what the client gets
    /// when it refuses to follow.
    private func redirect(to location: String, from url: URL) {
        let headers = ["Location": location]
        let response = HTTPURLResponse(url: url, statusCode: 302, httpVersion: "HTTP/1.1", headerFields: headers)
        guard let response, let target = URL(string: location) else { preconditionFailure("Not a redirect.") }
        client?.urlProtocol(self, wasRedirectedTo: URLRequest(url: target), redirectResponse: response)
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocolDidFinishLoading(self)
    }
}
