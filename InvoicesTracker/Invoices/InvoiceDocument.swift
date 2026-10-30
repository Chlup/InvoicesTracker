import Foundation

/// A label with the value printed beside it: a line of the payment block, of the dates or of the identifiers of a
/// party.
nonisolated struct InvoiceField: Sendable, Hashable {
    var label: String
    var value: String
}

/// An invoice together with what its page needs besides the invoice itself: who issues it, the account to pay to and
/// the QR code. `InvoiceDocumentView` draws it, `InvoicePDFRenderer` makes the PDF of it, and `text` is every line it
/// prints.
nonisolated struct InvoiceDocument: Sendable, Hashable {
    var invoice: Invoice
    var supplier: Supplier

    /// The supplier's account in the currency of the invoice, or nil when there is none
    /// (`InvoiceBankDetails.account(for:in:)`).
    var account: BankAccount?

    /// The payment code to print, or why there is none. It is never a code for an invoice that wants none.
    var qr: QRPayloadResult

    /// Whether the page is the preview of a draft: its number and the rate behind its crown equivalents can still
    /// change, so the equivalents are marked as approximate.
    var isProvisional: Bool

    private static let withoutQR = "Faktura je bez QR kódu."

    /// The document of `invoice` for `supplier`, with the account of the invoice's currency from `accounts`
    /// (`InvoiceBankDetails.account(for:in:)`). The QR code is made only if the invoice wants one (`qrEnabled`), from
    /// the same account.
    static func make(invoice: Invoice, supplier: Supplier, accounts: [BankAccount]) -> InvoiceDocument {
        InvoiceDocument(
            invoice: invoice, supplier: supplier,
            account: InvoiceBankDetails.account(for: invoice.currency, in: accounts),
            qr: invoice.qrEnabled
                ? QRPayload.payload(for: invoice, supplier: supplier, accounts: accounts) : .unavailable(withoutQR),
            isProvisional: invoice.status == .draft)
    }

    /// The name to save the PDF under: the number and `.pdf`. A slash or a colon, which a file name cannot have,
    /// becomes a hyphen.
    var fileName: String {
        String(invoice.number.map { $0 == "/" || $0 == ":" ? "-" : $0 }) + ".pdf"
    }

    /// Every line the page prints, in the language of the invoice.
    var text: InvoiceDocumentText {
        InvoiceDocumentText(self)
    }
}
