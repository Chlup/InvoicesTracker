import Foundation
import PDFKit

/// Reads the text of a PDF with PDFKit.
nonisolated enum PDFTextExtractor {
    /// The text of every page of the PDF in `data`, or nil if `data` is not a PDF or the PDF has no text.
    static func text(from data: Data) -> String? {
        guard let text = PDFDocument(data: data)?.string, !text.allSatisfy(\.isWhitespace) else { return nil }
        return text
    }
}
