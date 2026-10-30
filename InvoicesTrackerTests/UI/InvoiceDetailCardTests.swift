import AppKit
import SwiftUI
import Testing
@testable import InvoicesTracker

/// The card of the detail of an invoice on its own, in a window: the row "Čistý příjem" is in the grey box of the
/// payment, under the day and the amount received, and it is there exactly when the section "Dopad na odvody" is. The
/// tests read the card as VoiceOver does, through the accessibility tree. In every expected string `\u{00A0}` is the
/// no-break space.
@Suite(.serialized)
@MainActor
struct InvoiceDetailCardTests {
    // MARK: Helpers

    /// What the payment of the first invoice of the prediction sample adds to the levies: the invoice of 220 000,00 Kč
    /// is paid on 3. 2. 2026, and the payment brings the tax bonus, so the tax falls by 37 524 Kč and the social
    /// insurance rises by 4 123 Kč.
    private let levies = ReceiptEffect(
        receipt: Receipt(day: civilDate("2026-02-03"), czkNetHalere: 22_000_000, czkVatHalere: 0, source: .invoice(1)),
        tax: -37_524, social: 4_123, health: 0, total: -33_401)

    /// The detail of that invoice as the builder makes it, with `paymentEffect` for what the payment adds to the levies
    /// when it is known.
    private func detail(paymentEffect: ReceiptEffect?) -> InvoiceDetail {
        var invoice = Invoice.fixture(
            number: "2026-01-01", duzp: "2026-01-31", dueDate: "2026-02-15", items: [.fixture("1", at: 22_000_000)],
            vatMode: .none, payment: .fixture(on: "2026-02-03", net: 22_000_000, vat: 0))
        invoice.id = 1
        return InvoiceDetailBuilder.build(
            InvoiceDetailInput(
                invoice: invoice, asOf: civilDate("2026-10-17"), statusDay: civilDate("2026-10-17"), duzpRate: nil,
                paymentEffect: paymentEffect, estimate: nil))
    }

    /// The card of `detail`, with buttons that do nothing.
    private func card(of detail: InvoiceDetail) -> InvoiceDetailCard {
        InvoiceDetailCard(detail: detail, close: {}, pay: {}, issue: {}, edit: {}, showPDF: {}, delete: {})
    }

    // MARK: The row of the net income

    /// The box of the payment is one element for VoiceOver (it combines what is in it), so the row is in the box when
    /// the one reading holds the day and the amount of the payment, the words "Čistý příjem" and the net.
    @Test func theRowOfTheNetIncomeIsInThePaymentBox() async throws {
        let detail = detail(paymentEffect: levies)
        let payment = try #require(detail.payment)
        #expect(payment.netIncome == "253\u{00A0}401\u{00A0}Kč")

        try await withHostedView(card(of: detail), size: CGSize(width: 400, height: 1_000)) { window in
            try await withAccessibilityElements {
                let netIncome = "253\u{00A0}401\u{00A0}Kč"
                try await waitUntil {
                    accessibilityReadings(in: window).contains { $0.contains("Čistý příjem") && $0.contains(netIncome) }
                }

                let box = try #require(
                    accessibilityReadings(in: window).first { $0.contains("Čistý příjem") && $0.contains(netIncome) })
                #expect(box.contains(payment.line))
                #expect(box.contains(payment.crowns))
                // The section of the levies is an element of its own, not a part of the box.
                #expect(!box.contains("Dopad na odvody"))
            }
        }
    }

    /// A payment whose effect is not known has no section of the levies, and no row of the net income either: the box
    /// holds the payment alone.
    @Test func aPaymentWithoutItsEffectHasNoRowOfTheNetIncome() async throws {
        let detail = detail(paymentEffect: nil)
        let payment = try #require(detail.payment)
        #expect(payment.netIncome == nil)

        try await withHostedView(card(of: detail), size: CGSize(width: 400, height: 1_000)) { window in
            try await withAccessibilityElements {
                try await waitUntil { accessibilityReadings(in: window).contains { $0.contains(payment.line) } }

                let readings = accessibilityReadings(in: window)
                #expect(!readings.contains { $0.contains("Čistý příjem") })
                #expect(!readings.contains { $0.contains("Dopad na odvody") })
            }
        }
    }
}
