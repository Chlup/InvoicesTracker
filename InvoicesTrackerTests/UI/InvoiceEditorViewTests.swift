import AppKit
import SwiftUI
import Testing
@testable import InvoicesTracker

/// The views of the editor, laid out in a hosting view: the live preview is cut to the page, and the chooser takes the
/// room of its sheet.
@Suite(.settlesBackups)
@MainActor
struct InvoiceEditorViewTests {
    /// What a page needs is measured in the font it is set in, so the fonts are registered before any test, as the app
    /// does at its launch.
    init() {
        InvoiceFonts.register()
    }

    /// An invoice that does not fit one page, by far: twelve items of descriptions of 64 words and a note of 24 lines.
    /// Its page runs well over the bottom of the paper.
    private func documentThatDoesNotFit() -> InvoiceDocument {
        var invoice = InvoicePageFixtures.crownInvoice()
        invoice.items = InvoicePageFixtures.items(12, words: 64)
        invoice.note = InvoicePageFixtures.note(lines: 24)
        return InvoicePageFixtures.document(invoice)
    }

    /// How many sampled pixels of `view`, drawn on a transparent canvas of `canvas` points from its top edge, are not
    /// transparent above the row `boundary` (in points from the top) and below it.
    private func visiblePixels(
        of view: some View, canvas: CGSize, boundary: CGFloat
    ) async throws -> (above: Int, below: Int) {
        let hosting = NSHostingView(rootView: view.frame(width: canvas.width, height: canvas.height, alignment: .top))
        hosting.frame = NSRect(origin: .zero, size: canvas)
        let window = NSWindow(contentRect: hosting.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = hosting
        window.orderFront(nil)
        defer { window.orderOut(nil) }
        // The content of a geometry reader is laid out in a pass of its own.
        try await Task.sleep(for: .milliseconds(400))
        hosting.layoutSubtreeIfNeeded()
        let rep = try #require(hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds))
        hosting.cacheDisplay(in: hosting.bounds, to: rep)
        let scale = CGFloat(rep.pixelsHigh) / canvas.height
        var above = 0
        var below = 0
        for row in stride(from: 0, to: rep.pixelsHigh, by: 2) {
            for column in stride(from: 0, to: rep.pixelsWide, by: 2) {
                guard let color = rep.colorAt(x: column, y: row), color.alphaComponent > 0.01 else { continue }
                if CGFloat(row) < boundary * scale {
                    above += 1
                } else {
                    below += 1
                }
            }
        }
        return (above, below)
    }

    @Test func thePreviewOfAnInvoiceThatDoesNotFitIsCutToThePage() async throws {
        let document = documentThatDoesNotFit()
        #expect(!InvoicePDFRenderer.fitsOnOnePage(document), "The test needs an invoice that does not fit")
        let pane = PreviewPane(document: document)
            .frame(width: 380)
        let paneHeight = NSHostingView(rootView: pane).fittingSize.height

        let pixels = try await visiblePixels(
            of: pane, canvas: CGSize(width: 380, height: 3_000), boundary: paneHeight + 4)

        // The page is drawn, and nothing of it sticks out under the pane.
        #expect(pixels.above > 1_000, "The pane drew nothing")
        #expect(pixels.below == 0, "\(pixels.below) pixels are drawn under the pane")
    }

    @Test func thePageUncutDoesStickOutOfItsPaper() async throws {
        // What the preview is made of, drawn without the cut, goes below the paper, so the test above can fail.
        let page = InvoiceDocumentView(document: documentThatDoesNotFit())
            .scaleEffect(0.6, anchor: .topLeading)
            .frame(width: PageSize.a4.width * 0.6, height: PageSize.a4.height * 0.6, alignment: .topLeading)

        let pixels = try await visiblePixels(
            of: page, canvas: CGSize(width: 380, height: 3_000), boundary: PageSize.a4.height * 0.6 + 1)

        #expect(pixels.above > 1_000)
        #expect(pixels.below > 0, "Without the cut the page does not stick out")
    }

    @Test func aPaneWithoutAPageSaysWhy() async throws {
        let pane = PreviewPane(document: nil)
            .frame(width: 380)
        let height = NSHostingView(rootView: pane).fittingSize.height

        #expect(height > 100 && height < 300)
        let pixels = try await visiblePixels(
            of: pane, canvas: CGSize(width: 380, height: 600), boundary: height + 4)
        #expect(pixels.above > 100)
        #expect(pixels.below == 0)
    }

    @Test func theChooserSheetIs620PointsWideAndNoTallerThanTheWindow() async throws {
        try await EditorFixture.with { f in
            let hosting = NSHostingView(rootView: NewInvoiceChooser(app: f.app))
            try await Task.sleep(for: .milliseconds(600))

            let size = hosting.fittingSize

            #expect(size.width == 620)
            #expect(size.height <= 700, "The sheet is \(size.height) points tall")
        }
    }
}
