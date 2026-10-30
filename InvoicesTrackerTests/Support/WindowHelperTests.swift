import AppKit
import SwiftUI
import Testing

/// What the helpers of the tests that show windows share among the tests that run at the same time: the turn to type
/// into a window (`whileTypingAlone(_:)`), which a hosted view waits for, and the accessibility elements
/// (`withAccessibilityElements(_:)`), which stay while any test still wants them.
@MainActor
struct WindowHelperTests {
    /// What the tasks of a test saw.
    @MainActor
    private final class Seen {
        var otherHasTheTurn = false
        var otherMayGo = false
        var hostedViewShown = false
        var turnTaken = false
    }

    /// Waits for `task`, which makes `isDone` hold as its last step. A task whose turn does not come within a minute
    /// fails the test and is left waiting, rather than holding up the run.
    private func wait(for task: Task<Void, any Error>, doneWhen isDone: @MainActor () -> Bool) async throws {
        try await waitUntil(timeout: .seconds(60)) { isDone() }
        if isDone() {
            try await task.value
        }
    }

    // MARK: The turn to type into a window

    /// A field of a hosted view may take the focus as the window shows it, and with it the field editor that the
    /// fields of all windows share. So the view is shown only in the turn of its test.
    @Test func aHostedViewWaitsWhileAnotherTestHasTheTurn() async throws {
        let seen = Seen()
        let other = Task {
            try await whileTypingAlone {
                seen.otherHasTheTurn = true
                try await waitUntil(timeout: .seconds(60)) { seen.otherMayGo }
            }
        }
        try await waitUntil(timeout: .seconds(60)) { seen.otherHasTheTurn }

        let hosted = Task {
            try await withHostedView(Text(verbatim: "Zálohy a odpočty")) { _ in
                seen.hostedViewShown = true
            }
        }
        // A view that does not wait is shown in a fraction of this. Nothing is expected to happen: a fixed moment.
        try await Task.sleep(for: .milliseconds(500))
        #expect(!seen.hostedViewShown)

        seen.otherMayGo = true
        try await other.value
        try await wait(for: hosted) { seen.hostedViewShown }
    }

    /// A test that throws in a hosted view lets the next test have the turn.
    @Test func theTurnPassesOnWhenTheBodyOfAHostedViewThrows() async throws {
        struct Thrown: Error {}
        await #expect(throws: Thrown.self) {
            try await withHostedView(Text(verbatim: "Zálohy a odpočty")) { _ in
                throw Thrown()
            }
        }

        let seen = Seen()
        let next = Task {
            try await whileTypingAlone {
                seen.turnTaken = true
            }
        }
        try await wait(for: next) { seen.turnTaken }
    }

    /// A test that has the turn and shows a hosted view goes on with its turn: it does not wait for itself.
    @Test func aTestThatHasTheTurnShowsAHostedViewInIt() async throws {
        let seen = Seen()
        let nested = Task {
            try await whileTypingAlone {
                try await withHostedView(Text(verbatim: "Zálohy a odpočty")) { _ in
                    seen.hostedViewShown = true
                }
            }
        }
        try await wait(for: nested) { seen.hostedViewShown }
    }

    // MARK: The accessibility elements

    /// A test that is done with the elements leaves them to a test that still looks up cards or fields by them.
    @Test func theElementsStayWhileAnotherTestStillWantsThem() async throws {
        try await withAccessibilityElements {
            try await withAccessibilityElements {}
            #expect(hasEnhancedUserInterface())
        }
    }
}
