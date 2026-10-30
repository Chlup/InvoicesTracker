import AppKit
import SwiftUI
import Testing
@testable import InvoicesTracker

/// The sheet with the page of an invoice, which has to fit the smallest window the app has.
@MainActor
struct PDFPreviewSheetTests {
    /// What a page needs is measured in the font it is set in, so the fonts are registered before any test, as the app
    /// does at its launch.
    init() {
        InvoiceFonts.register()
    }

    /// The window is at least 720 points tall, and a sheet hangs from its top edge, so the sheet has to be shorter than
    /// that for "Uložit PDF…" and "Zavřít" to stay on screen.
    @Test func theSheetIsShorterThanTheSmallestWindow() {
        let document = InvoicePageFixtures.document(InvoicePageFixtures.crownInvoice())

        let size = NSHostingView(rootView: PDFPreviewSheet(document: document)).fittingSize

        #expect(size.height <= 700, "The sheet is \(size.height) points tall")
        #expect(size.width == 560)
    }

    // MARK: The page in the sheet

    @Test func theLargestPageIsFourFifthsOfItsSize() {
        #expect(PDFPreviewSheet.previewScale(fitting: CGSize(width: 2_000, height: 2_000)) == 0.8)
    }

    @Test func aPageInLessHeightIsShownSmallerToFitIt() {
        let scale = PDFPreviewSheet.previewScale(fitting: CGSize(width: 512, height: 420.945))

        #expect(abs(scale - 0.5) < 0.0001)
        #expect(PDFPreviewSheet.previewScale(fitting: CGSize(width: 297.64, height: 2_000)) < 0.5001)
    }

    // MARK: What the sheet says

    @Test func anInvoiceThatFitsGetsNoWarning() {
        var invoice = InvoicePageFixtures.crownInvoice()
        invoice.note = InvoicePageFixtures.note(lines: 8)

        #expect(PDFPreviewSheet.overflowMessage(for: InvoicePageFixtures.document(invoice)) == nil)
    }

    @Test func aNoteThatIsTooLongIsSaidToHaveNotFit() {
        var invoice = InvoicePageFixtures.crownInvoice()
        invoice.items = InvoicePageFixtures.items(12, words: 8)
        invoice.note = InvoicePageFixtures.note(lines: 40)

        #expect(
            PDFPreviewSheet.overflowMessage(for: InvoicePageFixtures.document(invoice))
                == "Poznámka se na stránku nevešla celá.")
    }

    @Test func anInvoiceWhoseItemsAreTooLongIsSaidNotToFitOnOnePage() {
        var invoice = InvoicePageFixtures.crownInvoice()
        invoice.items = InvoicePageFixtures.items(12, words: 40)
        invoice.note = InvoicePageFixtures.note(lines: 2)

        #expect(
            PDFPreviewSheet.overflowMessage(for: InvoicePageFixtures.document(invoice))
                == "Faktura se nevejde na jednu stránku – zkraťte popisy položek nebo poznámku.")
    }
}
