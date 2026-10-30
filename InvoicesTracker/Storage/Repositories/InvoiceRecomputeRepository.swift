import Foundation

/// Saving an invoice only when it is still as it was read: for work that reads invoices, works something out from them
/// and writes them back while the app goes on, such as converting payments again when new rates arrive.
extension Database {
    /// Saves `updated`, worked out from `listed`, only when the stored invoice is still `listed` as it was read. The
    /// comparison and the save run in one call on the database, with nothing in between, so an edit saved meanwhile is
    /// never overwritten and an invoice deleted meanwhile never comes back. Returns whether it was saved: false when
    /// the invoice changed or was deleted since it was read, and when `updated` is another invoice than `listed`.
    ///
    /// Throws what `invoice(id:)` and `saveInvoice(_:)` throw.
    func saveInvoice(_ updated: Invoice, ifUnchangedFrom listed: Invoice) throws -> Bool {
        guard updated.id == listed.id, try invoice(id: listed.id) == listed else {
            return false
        }
        try saveInvoice(updated)
        return true
    }
}
