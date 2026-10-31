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
            .frame(width: PreviewPane.width)
        let paneHeight = NSHostingView(rootView: pane).fittingSize.height

        let pixels = try await visiblePixels(
            of: pane, canvas: CGSize(width: PreviewPane.width, height: 3_000), boundary: paneHeight + 4)

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
            .frame(width: PreviewPane.width)
        let height = NSHostingView(rootView: pane).fittingSize.height

        #expect(height > 100 && height < 300)
        let pixels = try await visiblePixels(
            of: pane, canvas: CGSize(width: PreviewPane.width, height: 600), boundary: height + 4)
        #expect(pixels.above > 100)
        #expect(pixels.below == 0)
    }

    // MARK: The aside of the preview

    /// The aside is 461 points wide, as the prototype renders it: 429 points of content, which is the basis it gives
    /// its width (`flex: 0 1 429px`), and 16 points of padding on either side, which nothing in the prototype takes
    /// into the width (it sets no `box-sizing`).
    @Test func theAsideOfThePreviewIs429PointsOfContentAndSixteenOfPaddingOnEitherSide() {
        #expect(PreviewPane.contentWidth == 429)
        #expect(PreviewPane.width == 461)
    }

    /// The editor puts the preview beside the form from the width at which the form still has the 590 points its rows
    /// of items need, with the gap of 16, the aside and the margins of the page (24 and 16).
    @Test func thePreviewStandsBesideTheFormFromTheWidthThatHoldsTheFormTheGapAndTheAside() {
        #expect(InvoiceEditorView.sideBySideWidth == 590 + 16 + PreviewPane.width + 24 + 16)
        #expect(InvoiceEditorView.sideBySideWidth == 1_107)
    }

    /// The aside is on the fill of the design, the grey ground of a page, in a light and in a dark window, and the
    /// white page in it fills the width the padding leaves: 429 points, 16 in from either side, whatever the
    /// appearance.
    @Test(arguments: [ColorScheme.light, .dark])
    func thePreviewIsOnTheFillAndItsPageFillsTheWidthOfTheAside(scheme: ColorScheme) throws {
        let document = InvoicePageFixtures.document(InvoicePageFixtures.crownInvoice())
        let pane = PreviewPane(document: document)
            .frame(width: PreviewPane.width)
        let picture = try OffscreenPicture(of: pane, in: scheme)
        let fill = try OffscreenPicture.bytes(of: Palette.fill, in: scheme)

        // In the padding of the aside, left of its heading, where the shadow of the page does not reach.
        let beside = picture.bytes(at: CGPoint(x: 6, y: 12))
        #expect(
            zip(beside, fill).allSatisfy { abs($0 - $1) <= 2 }, "\(scheme): the aside is \(beside), the fill \(fill)")
        let page = try #require(picture.extent(near: [255, 255, 255], by: 2), "\(scheme): the page is not drawn")
        #expect(abs(page.minX - 16) <= 1.5, "\(scheme): the page is \(page)")
        #expect(abs(page.width - 429) <= 3, "\(scheme): the page is \(page)")
    }

    /// The page casts a soft shadow on the aside, under its bottom edge, which is darker than the fill there in a light
    /// and in a dark window.
    @Test(arguments: [ColorScheme.light, .dark])
    func thePageOfThePreviewCastsItsShadowOnTheAside(scheme: ColorScheme) throws {
        let document = InvoicePageFixtures.document(InvoicePageFixtures.crownInvoice())
        let pane = PreviewPane(document: document)
            .frame(width: PreviewPane.width)
        let picture = try OffscreenPicture(of: pane, in: scheme)
        let fill = try OffscreenPicture.bytes(of: Palette.fill, in: scheme)
        let page = try #require(picture.extent(near: [255, 255, 255], by: 2))

        let underEdge = picture.bytes(at: CGPoint(x: page.midX, y: page.maxY + 4))
        let deficit = zip(fill, underEdge).map { $0 - $1 }.max() ?? 0
        #expect(deficit >= 6, "\(scheme): the fill is \(fill) and just under the page \(underEdge)")
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
