import SwiftUI

/// Makes the PDF of an invoice.
@MainActor
enum InvoicePDFRenderer {
    /// The PDF of `document`: one A4 page, the page of `InvoiceDocumentView` drawn into a PDF context. Its text stays
    /// text, which can be selected and searched, and the fonts it uses are embedded in the file. The fonts have to be
    /// registered before (`InvoiceFonts.register()`, which the app does at its launch), or the text is set in the
    /// system font.
    ///
    /// Making a PDF in memory cannot fail unless the page size is invalid, which it is not, so this traps rather than
    /// hand back a file that is empty.
    static func pdfData(for document: InvoiceDocument) -> Data {
        let renderer = ImageRenderer(content: InvoiceDocumentView(document: document))
        renderer.proposedSize = ProposedViewSize(PageSize.a4)
        renderer.scale = InvoiceDocumentView.gridDensity
        let data = NSMutableData()
        var mediaBox = CGRect(origin: .zero, size: PageSize.a4)
        guard let consumer = CGDataConsumer(data: data as CFMutableData),
            let context = CGContext(consumer: consumer, mediaBox: &mediaBox, nil)
        else {
            preconditionFailure("A PDF context for an A4 page could not be made.")
        }
        renderer.render { _, draw in
            context.beginPDFPage(nil)
            draw(context)
            context.endPDFPage()
        }
        context.closePDF()
        return data as Data
    }

    /// Whether all of `document`, its note included, fits on the page at one of the sizes the page is set at, the
    /// smallest of which is 70 %. A document that does not fit still prints on one page, but not whole: the note is cut
    /// with an ellipsis, and if the rest is too long as well, the bottom of the page is cut off. An invoice that is
    /// saved or issued should be checked with this first. The page is measured in its font, so the fonts have to be
    /// registered, as for `pdfData(for:)`.
    static func fitsOnOnePage(_ document: InvoiceDocument) -> Bool {
        InvoiceDocumentView.fittingScale(for: document) != nil
    }

    /// What a person is told of an invoice that does not fit one page, even without its note: the sheet with the page
    /// says it, and the editor refuses to save or issue such an invoice with it.
    static let doesNotFitMessage = "Faktura se nevejde na jednu stránku – zkraťte popisy položek nebo poznámku."
}
