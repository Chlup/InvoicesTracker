import SwiftUI

/// The tone of the pill of a status, which belongs to the views: the status itself is a plain value of the invoices,
/// free of anything the screens draw.
nonisolated extension InvoiceDisplayStatus {
    /// The tone of the pill that shows the status: green for a paid invoice, blue for one that waits for its payment,
    /// red for one past its due date, grey for a draft, and the orange of attention for one to check, a state the
    /// design does not draw.
    var pillTone: PillTone {
        switch self {
        case .draft: .draft
        case .needsReview: .review
        case .awaitingPayment: .waiting
        case .overdue: .overdue
        case .paid: .paid
        }
    }
}
