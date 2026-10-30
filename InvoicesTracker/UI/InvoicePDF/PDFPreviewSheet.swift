import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// The sheet with the page of an invoice as it prints, and the way to keep it: "Uložit PDF…" asks where to save the
/// file, which is named after the number of the invoice, and "Zavřít" closes the sheet. The page is the same view that
/// makes the PDF, shown smaller: it is a close look at what the file will hold, laid out the same way, but not a
/// proof of it down to the pixel, as hairlines and the place of a line can differ a little at the smaller size. When
/// the invoice does not fit the page whole, a line under the page says so.
///
/// The sheet is 676 points tall, so that it hangs inside the smallest window (720 points) with both buttons on screen,
/// and the page is shown as large as the height left for it allows.
struct PDFPreviewSheet: View {
    let document: InvoiceDocument

    @Environment(\.dismiss) private var dismiss
    @State private var saveFailed = false
    @State private var overflowMessage: String?

    private static let sheetSize = CGSize(width: 560, height: 676)

    /// The page is shown at four fifths of its size at most, which is 476 points wide.
    private static let largestPreviewScale: CGFloat = 0.8

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            page
            if let overflowMessage {
                Text(overflowMessage)
                    .font(.callout)
                    .foregroundStyle(Color(.simulationText))
                    .frame(maxWidth: .infinity)
            }
            if saveFailed {
                Text("PDF se nepodařilo uložit.")
                    .foregroundStyle(.red)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
            buttons
        }
        .padding(.top, 22)
        .padding(.horizontal, 24)
        .padding(.bottom, 20)
        .frame(width: Self.sheetSize.width, height: Self.sheetSize.height)
        .task(id: document) {
            overflowMessage = Self.overflowMessage(for: document)
        }
    }

    // MARK: Parts

    /// "Faktura 20260902" and under it the client with the total, as the invoice lists have them.
    private var header: some View {
        let invoice = document.invoice
        let total = CzechFormat.money(Money(minor: invoice.totalMinor, currency: invoice.currency))
        return VStack(alignment: .leading, spacing: 2) {
            Text(verbatim: "Faktura \(invoice.number)")
                .font(.system(size: 17, weight: .bold))
            Text(verbatim: "\(invoice.client.name) · \(total)")
                .foregroundStyle(.secondary)
        }
    }

    /// The page, in the middle of the height that the rest of the sheet leaves, as large as fits it.
    private var page: some View {
        GeometryReader { geometry in
            let scale = Self.previewScale(fitting: geometry.size)
            InvoiceDocumentView(document: document)
                .scaleEffect(scale, anchor: .topLeading)
                .frame(width: PageSize.a4.width * scale, height: PageSize.a4.height * scale, alignment: .topLeading)
                .clipShape(RoundedRectangle(cornerRadius: 4))
                .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(.separator))
                .shadow(color: .black.opacity(0.1), radius: 12, y: 8)
                .frame(width: geometry.size.width, height: geometry.size.height)
        }
    }

    private var buttons: some View {
        HStack(spacing: 8) {
            Spacer()
            Button("Zavřít") {
                dismiss()
            }
            .buttonStyle(.bordered)
            .keyboardShortcut(.cancelAction)
            Button("Uložit PDF…", action: save)
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
        }
        .buttonBorderShape(.capsule)
        .controlSize(.large)
    }

    // MARK: What the page is shown at and what is said about it

    /// The share of its size at which the page is shown in the space `available`: four fifths at most, and less where
    /// it would not fit the space.
    static func previewScale(fitting available: CGSize) -> CGFloat {
        min(largestPreviewScale, available.width / PageSize.a4.width, available.height / PageSize.a4.height)
    }

    /// What the sheet says under the page, or nil when the invoice fits it whole. When only the note is too long it
    /// says so; when the rest of the invoice is too long as well, it says that the invoice does not fit.
    static func overflowMessage(for document: InvoiceDocument) -> String? {
        guard !InvoicePDFRenderer.fitsOnOnePage(document) else { return nil }
        var withoutNote = document
        withoutNote.invoice.note = ""
        if InvoicePDFRenderer.fitsOnOnePage(withoutNote) {
            return "Poznámka se na stránku nevešla celá."
        }
        return InvoicePDFRenderer.doesNotFitMessage
    }

    // MARK: Saving

    /// Asks where to save the PDF, as a sheet of the window the person works in, and writes it there. The page is made
    /// once the place is chosen. A file that cannot be written is told in the sheet.
    private func save() {
        saveFailed = false
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.pdf]
        panel.nameFieldStringValue = document.fileName
        panel.canCreateDirectories = true
        let write: (NSApplication.ModalResponse) -> Void = { response in
            guard response == .OK, let url = panel.url else { return }
            do {
                try InvoicePDFRenderer.pdfData(for: document).write(to: url, options: .atomic)
            } catch {
                AppModel.log("Saving the invoice PDF", failedWith: error)
                saveFailed = true
            }
        }
        if let window = NSApp.keyWindow {
            panel.beginSheetModal(for: window, completionHandler: write)
        } else {
            panel.begin(completionHandler: write)
        }
    }
}
