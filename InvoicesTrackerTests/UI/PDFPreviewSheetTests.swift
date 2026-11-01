import AppKit
import SwiftUI
import Testing
import UniformTypeIdentifiers
@testable import InvoicesTracker

/// The sheet with the page of an invoice, which has to fit the smallest window the app has, and which has the buttons,
/// the header and the page of the design: Zavřít and Stáhnout PDF, 32 points tall, and the page on a soft shadow.
@Suite(.serialized)
@MainActor
struct PDFPreviewSheetTests {
    /// What a page needs is measured in the font it is set in, so the fonts are registered before any test, as the app
    /// does at its launch.
    init() {
        InvoiceFonts.register()
    }

    /// The window is at least 720 points tall, and a sheet hangs from its top edge, so the sheet has to be shorter than
    /// that for "Stáhnout PDF" and "Zavřít" to stay on screen.
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

    // MARK: What the sheet looks like

    /// The frame of the button that VoiceOver reads under `label` in `window`, in points from the top left of its
    /// content.
    private func buttonFrame(_ label: String, in window: NSWindow) throws -> CGRect {
        let screen = try #require(
            accessibilityButton(labelled: label, in: window)?.accessibilityFrame?(), "No button \(label)")
        return try pictureFrame(of: screen, in: window)
    }

    /// `screen`, a frame in the coordinates of the screen, as points from the top left of the content of `window`.
    private func pictureFrame(of screen: CGRect, in window: NSWindow) throws -> CGRect {
        let frame = window.convertFromScreen(screen)
        let height = try #require(window.contentView).bounds.height
        return CGRect(x: frame.minX, y: height - frame.maxY, width: frame.width, height: frame.height)
    }

    /// Whether the pixel at `point` of `picture` is `colour`, within 2 levels in every channel.
    private func isColour(_ colour: [Int], at point: CGPoint, in picture: OffscreenPicture) -> Bool {
        guard let found = pixel(at: point, in: picture) else { return false }
        return zip(found, colour).allSatisfy { abs($0 - $1) <= 2 }
    }

    /// The bytes of the pixel at `point` of `picture`, or nil where the point is outside it.
    private func pixel(at point: CGPoint, in picture: OffscreenPicture) -> [Int]? {
        guard CGRect(origin: .zero, size: picture.size).contains(point) else { return nil }
        return picture.bytes(at: point)
    }

    /// Expects the pixel at `point` of `picture` to be `colour`, and says what `what` is instead when it is not.
    private func expectColour(
        _ colour: [Int], at point: CGPoint, in picture: OffscreenPicture, _ what: String,
        sourceLocation: SourceLocation = #_sourceLocation
    ) {
        let found = pixel(at: point, in: picture).map { "\($0)" } ?? "outside the picture"
        #expect(isColour(colour, at: point, in: picture), "\(what) is \(found)", sourceLocation: sourceLocation)
    }

    /// The buttons of the sheet are the capsules of a dialog, 32 points tall, at its trailing end: Zavřít on the grey
    /// fill, and Stáhnout PDF in the accent. The sheet has no "Uložit PDF…" any more: the button saves the page, and
    /// the save panel asks where.
    @Test(arguments: [ColorScheme.light, .dark])
    func theButtonsAreZavritOnTheFillAndStahnoutPDFInTheAccent(scheme: ColorScheme) async throws {
        let document = InvoicePageFixtures.document(InvoicePageFixtures.crownInvoice())
        try await withHostedView(PDFPreviewSheet(document: document), size: CGSize(width: 560, height: 676)) { window in
            window.appearance = NSAppearance(named: scheme == .light ? .aqua : .darkAqua)
            try await withAccessibilityElements {
                try await waitUntil { accessibilityButton(labelled: "Stáhnout PDF", in: window) != nil }
                try await layOut(window)
                let close = try buttonFrame("Zavřít", in: window)
                let save = try buttonFrame("Stáhnout PDF", in: window)
                let picture = try OffscreenPicture(of: window)
                let fill = try OffscreenPicture.bytes(of: Palette.fill, in: scheme)
                let accent = try OffscreenPicture.bytes(of: Palette.accent, in: scheme)

                #expect(abs(close.height - DesignMetrics.regularControlHeight) < 0.5, "Zavřít: \(close)")
                #expect(abs(save.height - DesignMetrics.regularControlHeight) < 0.5, "Stáhnout PDF: \(save)")
                #expect(close.maxX < save.minX, "Zavřít stands before Stáhnout PDF")
                expectColour(fill, at: CGPoint(x: close.minX + 8, y: close.midY), in: picture, "\(scheme): Zavřít")
                expectColour(accent, at: CGPoint(x: save.minX + 8, y: save.midY), in: picture, "\(scheme): save")
                #expect(accessibilityButton(labelled: "Uložit PDF…", in: window) == nil)
            }
        }
    }

    /// The header is the title of a sheet with the line under it: "Faktura 20260902" and the client with the total.
    @Test func theHeaderNamesTheInvoiceAndTheClientWithTheTotal() async throws {
        let invoice = InvoicePageFixtures.crownInvoice()
        let document = InvoicePageFixtures.document(invoice)
        try await withHostedView(PDFPreviewSheet(document: document), size: CGSize(width: 560, height: 676)) { window in
            try await withAccessibilityElements {
                try await waitUntil { showsText("Faktura \(invoice.number)", in: window) }
                let total = CzechFormat.money(Money(minor: invoice.totalMinor, currency: invoice.currency))

                #expect(showsText("\(invoice.client.name) · \(total)", in: window))
            }
        }
    }

    /// The page casts its soft shadow under its bottom edge, on the ground of the sheet: the pixels just under the page
    /// are darker than those further down, in a light and in a dark window. The sheet is drawn off-screen, on the grey
    /// fill, because a window's picture leaves out shadows.
    @Test(arguments: [ColorScheme.light, .dark])
    func thePageCastsItsShadowUnderItsEdge(scheme: ColorScheme) throws {
        let document = InvoicePageFixtures.document(InvoicePageFixtures.crownInvoice())
        let sheet = PDFPreviewSheet(document: document)
            .background(Palette.fill)
        let picture = try OffscreenPicture(of: sheet, in: scheme)

        // The white of the page, between the header of the sheet and its buttons.
        let page = try #require(
            picture.extent(near: [255, 255, 255], in: CGRect(x: 0, y: 70, width: 560, height: 550), by: 2),
            "\(scheme): the page is not drawn")
        let under = picture.bytes(at: CGPoint(x: page.midX, y: page.maxY + 3))
        let faraway = picture.bytes(at: CGPoint(x: page.midX, y: page.maxY + 14))

        let deficit = zip(faraway, under).map { $0 - $1 }.max() ?? 0
        #expect(deficit >= 4, "\(scheme): \(faraway) further down and \(under) under the page")
    }

    /// What the sheet says under the page, when the invoice does not fit it, is in the orange of attention.
    @Test(arguments: [ColorScheme.light, .dark])
    func theWarningUnderThePageIsInTheOrangeOfAttention(scheme: ColorScheme) async throws {
        var invoice = InvoicePageFixtures.crownInvoice()
        invoice.items = InvoicePageFixtures.items(12, words: 8)
        invoice.note = InvoicePageFixtures.note(lines: 40)
        let document = InvoicePageFixtures.document(invoice)
        try await withHostedView(PDFPreviewSheet(document: document), size: CGSize(width: 560, height: 676)) { window in
            window.appearance = NSAppearance(named: scheme == .light ? .aqua : .darkAqua)
            try await withAccessibilityElements {
                let warning = "Poznámka se na stránku nevešla celá."
                try await waitUntil { frameOfText(startingWith: warning, in: window) != nil }
                try await layOut(window)
                let frame = try pictureFrame(
                    of: try #require(frameOfText(startingWith: warning, in: window)), in: window)
                let picture = try OffscreenPicture(of: window)
                let orange = try OffscreenPicture.bytes(of: Palette.orangeText, in: scheme)

                #expect(picture.count(near: orange, in: frame, by: 10) > 30, "\(scheme): the words are not orange")
            }
        }
    }

    // MARK: Saving

    /// "Stáhnout PDF" asks where to save the page in the panel of the system: for a PDF, with the number of the invoice
    /// as the name of the file, and the person can make a folder there. The test looks at what the panel is set to
    /// (`savePanelSettings(for:)`) and not at a panel: the panel of the system is a live one, which in a full run of
    /// the suite with the Mac's screen locked gave back none of what it was set to (no type, no name, no folders) after
    /// a stall of about a minute.
    @Test func theSavePanelIsForAPDFNamedAfterTheInvoice() {
        let document = InvoicePageFixtures.document(InvoicePageFixtures.crownInvoice())

        let settings = PDFPreviewSheet.savePanelSettings(for: document)

        #expect(settings.contentTypes == [.pdf])
        #expect(settings.fileName == document.fileName)
        #expect(settings.canCreateDirectories)
    }
}
