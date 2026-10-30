import Foundation

/// The filters of the invoice list, one chip each. Every invoice belongs to exactly one filter other than `all`, which
/// shows them all.
nonisolated enum InvoiceStatusFilter: String, CaseIterable, Sendable {
    case all
    case drafts
    case awaiting
    case overdue
    case paid

    /// The invoices to check. The list shows this chip only when it counts at least one invoice.
    case review

    /// The text on the chip.
    var title: String {
        switch self {
        case .all: "Vše"
        case .drafts: "Koncepty"
        case .awaiting: "Čeká na platbu"
        case .overdue: "Po splatnosti"
        case .paid: "Uhrazené"
        case .review: "Ke kontrole"
        }
    }
}

/// The status of an invoice on a day, as the list shows it. It is not stored: `Invoice.displayStatus(asOf:)` works it
/// out from the invoice and the day. The screens ask for today, whatever year or day they are shown as of, so an
/// invoice has one status wherever it is seen.
nonisolated enum InvoiceDisplayStatus: Hashable, Sendable {
    /// Not issued yet.
    case draft

    /// The import could not tell what the invoice is. The value is the reason it gave. Such an invoice is not counted
    /// until it has been resolved.
    case needsReview(String)

    /// Issued, not paid and not past its due date.
    case awaitingPayment

    /// Issued, not paid and past its due date.
    case overdue

    /// Paid. The value is the day the money was received.
    case paid(CivilDate)

    /// The filter whose chip lists invoices with this status.
    var filter: InvoiceStatusFilter {
        switch self {
        case .draft: .drafts
        case .needsReview: .review
        case .awaitingPayment: .awaiting
        case .overdue: .overdue
        case .paid: .paid
        }
    }

    /// The text of the status. For a paid invoice it is "Uhrazená" and the day and month of the payment
    /// (`Uhrazená 2. 10.`). It does not know which year the list is for, so it has no year. Use `label(asOf:)` where a
    /// payment from another year can appear.
    var label: String {
        switch self {
        case .draft: "Koncept"
        case .needsReview: "Ke kontrole"
        case .awaitingPayment: "Čeká na platbu"
        case .overdue: "Po splatnosti"
        case .paid(let day): "Uhrazená " + CzechFormat.dayMonth(day)
        }
    }

    /// The text of the status for a screen shown as of `asOf` ("K datu"): the same as `label`, but a payment from
    /// another year than the one of `asOf` shows its year as well (`Uhrazená 20. 12. 2025`). The day that counts here
    /// is the one the screen is shown as of, not the one the status was worked out for: the list of 2025 says
    /// "Uhrazená 2. 1. 2026" of a payment of January 2026.
    func label(asOf: CivilDate) -> String {
        if case .paid(let day) = self, day.year != asOf.year {
            return "Uhrazená " + CzechFormat.date(day)
        }
        return label
    }
}

nonisolated extension Invoice {
    /// The status of the invoice on `asOf`, in this order:
    /// 1. a draft is a draft;
    /// 2. an invoice with a review flag needs review, even when it has a payment;
    /// 3. an invoice with a payment on or before `asOf` is paid, and a later payment does not count yet;
    /// 4. an invoice that is not paid is overdue from the day after its due date, and otherwise it awaits payment.
    ///
    /// The screens pass today, never the year or the day they are shown as of ("K datu"): the status does not depend on
    /// what is looked at, so an invoice issued in 2025 and paid in January 2026 is paid in the list of 2025 too.
    func displayStatus(asOf: CivilDate) -> InvoiceDisplayStatus {
        if status == .draft {
            return .draft
        }
        if let review {
            return .needsReview(review.reason)
        }
        if let payment, payment.date <= asOf {
            return .paid(payment.date)
        }
        return dueDate < asOf ? .overdue : .awaitingPayment
    }
}
