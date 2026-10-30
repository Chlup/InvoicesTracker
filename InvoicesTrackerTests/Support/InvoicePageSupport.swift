import CoreGraphics
import CoreImage
import Foundation
import PDFKit
import SwiftUI
import Testing
@testable import InvoicesTracker

/// The invented supplier, accounts and invoices that the tests of the invoice document and of its page share. The IBANs
/// are the well-known example ones, the account and routing numbers are made up, and the clients are those of the other
/// fixtures.
enum InvoicePageFixtures {
    static let supplier = Supplier(
        name: "Jan Novák", street: "Dlouhá 12", postcode: "110 00", city: "Praha", country: "CZ", ico: "11223344",
        dic: "CZ11223344", email: "jan@example.com", phone: "+420 123 456 789")

    static let czkAccount = BankAccount(
        currency: .czk, accountNumber: "1234567890/0800", iban: "CZ65 0800 0000 1920 0014 5399", bic: "GIBACZPX")
    static let usdAccount = dollarAccount(bankNameAndAddress: "Example Bank, 1 Main Street, Springfield")
    static let eurAccount = BankAccount(currency: .eur, iban: "DE89 3704 0044 0532 0130 00", bic: "COBADEFFXXX")
    static let accounts = [czkAccount, usdAccount, eurAccount]

    /// An account in dollars at the bank `bankNameAndAddress`.
    static func dollarAccount(bankNameAndAddress: String) -> BankAccount {
        BankAccount(
            currency: .usd, accountNumber: "000123456789", routingNumber: "123456789", accountType: "Checking",
            bankNameAndAddress: bankNameAndAddress)
    }

    /// A bank name and an invented address of 91 characters, which no invoice prints.
    static let longBankName =
        "Example Community Federal Savings Bank, 12 Sample Rd, 14th Floor, Exampleton, EX 00000, USA"

    /// A client name of 91 characters and a payment method of 51, each of which wraps on the page.
    static let longCustomerName =
        "Alfa Systems Czech Republic Holding and Development Services s.r.o., odštěpný závod Příbram"
    static let longPaymentMethod = "Převodem na účet dodavatele uvedený na této faktuře"

    /// The note of the invoice in dollars, written like the ACH instructions of a real one, with invented numbers.
    static let achNote = """
        Payment method:
        ACH (USD)

        Bank Name and Address:
        Example Bank, 1 Main Street, Springfield

        Name: Jan Novák
        Account type: Checking
        Routing number: 123456789
        Account number: 000123456789
        """

    /// 7,5 hours at 600,00 Kč and 21 % VAT: 4 500,00 Kč and 945,00 Kč VAT, 5 445,00 Kč in all, in Czech, with a QR
    /// code.
    static func crownInvoice() -> Invoice {
        var invoice = Invoice.fixture(number: "20260902")
        invoice.qrEnabled = true
        return invoice
    }

    /// 205 hours at 70,00 USD outside the VAT scope: 14 350,00 USD, at 21,359 on the day of supply, in English, with
    /// the ACH note.
    static func dollarInvoice(status: InvoiceStatus = .issued) -> Invoice {
        var invoice = Invoice.fixture(
            number: "20260901", currency: .usd, dueDate: "2026-10-30",
            items: [
                InvoiceItem(
                    description: "Software development", quantity: decimal("205"), unit: "h", unitPriceMinor: 7_000)
            ],
            vatMode: .outsideCountry, invoiceRate: storedRate("USD", "21.359", declaredOn: "2026-09-30"),
            status: status)
        invoice.client = ClientSnapshot(client: SearchFixtures.bravo)
        invoice.language = .en
        invoice.paymentMethod = "ACH (USD)"
        invoice.note = achNote
        return invoice
    }

    /// `count` items of 100,00 each times their number, whose descriptions are `words` words long, such as
    /// `Vývoj a nasazení modulu 3 pro zpracování faktur`.
    static func items(_ count: Int, words: Int) -> [InvoiceItem] {
        (1...count).map { number in
            var parts = [
                "Vývoj", "a", "nasazení", "modulu", String(number), "pro", "zpracování", "faktur", "včetně",
                "dokumentace", "a", "školení", "uživatelů", "zákazníka", "na", "pobočkách",
            ]
            while parts.count < words {
                parts.append("dalších")
            }
            return InvoiceItem(
                description: parts.prefix(words).joined(separator: " "), quantity: decimal("1"), unit: "ks",
                unitPriceMinor: 10_000 * Int64(number))
        }
    }

    /// A note of `lines` lines, `Note line 1` and so on.
    static func note(lines: Int) -> String {
        (0..<lines).map { "Note line \($0 + 1)" }.joined(separator: "\n")
    }

    /// The document of `invoice` by the invented supplier, with the accounts of all three currencies.
    static func document(
        _ invoice: Invoice, supplier: Supplier = InvoicePageFixtures.supplier,
        accounts: [BankAccount] = InvoicePageFixtures.accounts
    ) -> InvoiceDocument {
        InvoiceDocument.make(invoice: invoice, supplier: supplier, accounts: accounts)
    }
}

/// Makes PDFs of invoices and reads the pages back, for the tests of the invoice page.
@MainActor
enum InvoicePageProbe {
    /// The PDF of `invoice`, as bytes and read back. The fonts are registered the way the app does at its launch.
    static func render(
        _ invoice: Invoice, accounts: [BankAccount] = InvoicePageFixtures.accounts
    ) throws -> (data: Data, pdf: PDFDocument) {
        InvoiceFonts.register()
        let data = InvoicePDFRenderer.pdfData(for: InvoicePageFixtures.document(invoice, accounts: accounts))
        return (data, try #require(PDFDocument(data: data)))
    }

    /// The PDF of `document` made like `InvoicePDFRenderer` makes it, but laid out on a grid of `1 / displayScale`
    /// points.
    static func pdfData(of document: InvoiceDocument, displayScale: CGFloat) -> Data {
        InvoiceFonts.register()
        let renderer = ImageRenderer(content: InvoiceDocumentView(document: document))
        renderer.proposedSize = ProposedViewSize(PageSize.a4)
        renderer.scale = displayScale
        let data = NSMutableData()
        var mediaBox = CGRect(origin: .zero, size: PageSize.a4)
        guard let consumer = CGDataConsumer(data: data as CFMutableData),
            let context = CGContext(consumer: consumer, mediaBox: &mediaBox, nil)
        else {
            preconditionFailure("A PDF context could not be made.")
        }
        renderer.render { _, draw in
            context.beginPDFPage(nil)
            draw(context)
            context.endPDFPage()
        }
        context.closePDF()
        return data as Data
    }

    /// The text of the page with every no-break space read as an ordinary space.
    static func text(of pdf: PDFDocument) throws -> String {
        try #require(pdf.string).replacing("\u{00A0}", with: " ")
    }

    /// Where `text` is on the first page, in the points of the page from its lower left corner.
    static func bounds(of text: String, in pdf: PDFDocument) throws -> CGRect {
        let page = try #require(pdf.page(at: 0))
        let found = try #require(pdf.findString(text, withOptions: .literal).first, "\(text) is not on the page")
        return found.bounds(for: page)
    }

    /// The first page of `pdf` drawn on white at `scale` times its size.
    static func renderedPage(of pdf: Data, scale: CGFloat) throws -> CGImage {
        let provider = try #require(CGDataProvider(data: pdf as CFData))
        let page = try #require(CGPDFDocument(provider)?.page(at: 1))
        let box = page.getBoxRect(.mediaBox)
        let width = Int((box.width * scale).rounded())
        let height = Int((box.height * scale).rounded())
        let space = try #require(CGColorSpace(name: CGColorSpace.sRGB))
        let context = try #require(
            CGContext(
                data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.scaleBy(x: scale, y: scale)
        context.drawPDFPage(page)
        return try #require(context.makeImage())
    }

    /// The pixels of `image` as RGBA bytes, row by row from the top.
    static func pixels(of image: CGImage) throws -> [UInt8] {
        var pixels = [UInt8](repeating: 0, count: image.width * image.height * 4)
        let drawn = try pixels.withUnsafeMutableBytes { buffer -> Bool in
            let space = try #require(CGColorSpace(name: CGColorSpace.sRGB))
            guard
                let context = CGContext(
                    data: buffer.baseAddress, width: image.width, height: image.height, bitsPerComponent: 8,
                    bytesPerRow: image.width * 4, space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
            else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
            return true
        }
        #expect(drawn)
        return pixels
    }

    /// How many horizontal light-grey rules run across the page in `pdf`, counted on the page drawn at four times its
    /// size: the rows of pixels that are grey and not white or black over the width of the table, a rule being the rows
    /// that follow each other.
    static func ruleCount(in pdf: Data) throws -> Int {
        let image = try renderedPage(of: pdf, scale: 4)
        let bytes = try pixels(of: image)
        let width = image.width
        let columns = (width / 8)..<(width * 7 / 8)
        var count = 0
        var inRule = false
        for row in 0..<image.height {
            var grey = 0
            var offset = (row * width + columns.lowerBound) * 4
            for _ in columns {
                if bytes[offset] > 120 && bytes[offset] < 245 {
                    grey += 1
                }
                offset += 4
            }
            let isRule = Double(grey) >= 0.95 * Double(columns.count)
            if isRule && !inRule {
                count += 1
            }
            inRule = isRule
        }
        return count
    }

    /// The texts of the QR codes that a scanner finds on the first page of `pdf`.
    static func scannedCodes(on pdf: Data) throws -> [String] {
        let image = try renderedPage(of: pdf, scale: 3)
        let options = [CIDetectorAccuracy: CIDetectorAccuracyHigh]
        let detector = try #require(CIDetector(ofType: CIDetectorTypeQRCode, context: nil, options: options))
        return detector.features(in: CIImage(cgImage: image)).compactMap { ($0 as? CIQRCodeFeature)?.messageString }
    }
}
