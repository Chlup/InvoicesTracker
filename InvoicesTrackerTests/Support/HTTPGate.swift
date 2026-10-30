import Foundation
@testable import InvoicesTracker

/// Holds requests back until the test opens it, so that a run can be kept in progress.
actor Gate {
    private var isOpen = false
    private var held: [CheckedContinuation<Void, Never>] = []
    private var watchers: [(count: Int, continuation: CheckedContinuation<Void, Never>)] = []

    /// Returns at once when the gate is open, otherwise when it opens.
    func pass() async {
        guard !isOpen else { return }
        await withCheckedContinuation { continuation in
            held.append(continuation)
            let reached = watchers.filter { $0.count <= held.count }
            watchers.removeAll { $0.count <= held.count }
            for watcher in reached {
                watcher.continuation.resume()
            }
        }
    }

    /// Returns once `count` requests are held at the gate.
    func untilRequestsWait(_ count: Int) async {
        guard held.count < count else { return }
        await withCheckedContinuation { watchers.append((count, $0)) }
    }

    /// Returns once a request is held at the gate.
    func untilARequestWaits() async {
        await untilRequestsWait(1)
    }

    func open() {
        isOpen = true
        for continuation in held {
            continuation.resume()
        }
        held = []
    }
}

/// A server whose every request waits at `gate` before the stub answers it.
final class GatedHTTPClient: HTTPClient {
    let base: StubHTTPClient
    let gate: Gate

    init(base: StubHTTPClient, gate: Gate) {
        self.base = base
        self.gate = gate
    }

    func get(_ url: URL) async throws -> Data {
        await gate.pass()
        return try await base.get(url)
    }
}
