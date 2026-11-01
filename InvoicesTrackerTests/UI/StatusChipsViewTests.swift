import AppKit
import SwiftUI
import Testing

@testable import InvoicesTracker

/// The status chips of Faktury, "Vše 12", "Koncepty 1", …: the title of each and the number of its invoices. The
/// number is written like every other count the app shows (`CzechFormat.grouped`), with a no-break space between the
/// thousands, and below a thousand it is the digits alone. In every expected string `\u{00A0}` is the no-break space.
@Suite(.serialized)
@MainActor
struct StatusChipsViewTests {
    /// Shows the chips `chips` with `counts` in a window and expects a button under each of `labels`, in the words
    /// VoiceOver reads for it.
    private func expectChips(
        _ chips: [InvoiceStatusFilter], counts: [InvoiceStatusFilter: Int], labels: [String],
        sourceLocation: SourceLocation = #_sourceLocation
    ) async throws {
        let view = StatusChipsView(chips: chips, counts: counts, selection: .constant(.all)).padding(20)

        try await withHostedView(view, size: CGSize(width: 900, height: 120)) { window in
            try await withAccessibilityElements {
                try await waitUntil(sourceLocation: sourceLocation) {
                    accessibilityReadings(in: window).contains { $0.hasPrefix("Vše ") }
                }
                for label in labels {
                    #expect(
                        accessibilityButton(labelled: label, in: window) != nil,
                        "No chip \(label): read as \(accessibilityReadings(in: window))",
                        sourceLocation: sourceLocation)
                }
            }
        }
    }

    /// A thousand is "1 000", 1 234 is "Vše 1 234" and a million and more has its groups of three too.
    @Test func aCountOfAThousandOrMoreIsGroupedInThousandsWithANoBreakSpace() async throws {
        try await expectChips(
            [.all, .drafts, .paid], counts: [.all: 1_234, .drafts: 1_000, .paid: 1_234_567],
            labels: ["Vše 1\u{00A0}234", "Koncepty 1\u{00A0}000", "Uhrazené 1\u{00A0}234\u{00A0}567"])
    }

    /// Below a thousand the chip reads as it always did: the title, a space and the digits, 0 included.
    @Test func aCountBelowAThousandIsTheDigitsAlone() async throws {
        try await expectChips(
            [.all, .drafts, .awaiting, .overdue, .review],
            counts: [.all: 12, .drafts: 0, .awaiting: 999, .overdue: 7, .review: 1],
            labels: ["Vše 12", "Koncepty 0", "Čeká na platbu 999", "Po splatnosti 7", "Ke kontrole 1"])
    }
}
