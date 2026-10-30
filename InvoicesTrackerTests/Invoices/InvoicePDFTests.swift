import AppKit
import CoreGraphics
import CoreImage
import Foundation
import PDFKit
import SwiftUI
import Testing
@testable import InvoicesTracker

/// The invoice as a PDF: one A4 page of real text in IBM Plex Sans, read back with PDFKit. The supplier, the clients
/// and the accounts are invented. The text of a page is read with every no-break space as an ordinary space.
@MainActor
struct InvoicePDFTests {
    private typealias Fixtures = InvoicePageFixtures
    private typealias Probe = InvoicePageProbe

    // MARK: The fonts

    @Test func theThreeFacesOfPlexSansAreRegisteredByTheirPostScriptNamesAndRegisteringTwiceIsHarmless() {
        InvoiceFonts.register()
        InvoiceFonts.register()

        #expect(InvoiceFonts.regular == "IBMPlexSans")
        #expect(InvoiceFonts.medium == "IBMPlexSans-Medm")
        #expect(InvoiceFonts.bold == "IBMPlexSans-Bold")
        for name in [InvoiceFonts.regular, InvoiceFonts.medium, InvoiceFonts.bold] {
            #expect(NSFont(name: name, size: 12)?.fontName == name, "\(name) is not available")
        }
    }

    // MARK: The page

    /// The invoice and the sheet with the recovery code are made on the same paper.
    @Test func theInvoicePageIsA4InPoints() throws {
        #expect(PageSize.a4 == CGSize(width: 595.28, height: 841.89))

        let (_, pdf) = try Probe.render(Fixtures.crownInvoice())
        let box = try #require(pdf.page(at: 0)).bounds(for: .mediaBox)
        #expect(abs(box.width - PageSize.a4.width) < 0.01)
        #expect(abs(box.height - PageSize.a4.height) < 0.01)
    }

    // MARK: A Czech invoice in crowns

    @Test func aCzechInvoiceInCrownsIsOneA4PageWithItsTextAndQRCode() throws {
        let (_, pdf) = try Probe.render(Fixtures.crownInvoice())

        #expect(pdf.pageCount == 1)
        let box = try #require(pdf.page(at: 0)).bounds(for: .mediaBox)
        #expect(abs(box.width - 595.28) < 0.5)
        #expect(abs(box.height - 841.89) < 0.5)
        let text = try Probe.text(of: pdf)
        for expected in [
            "Faktura 20260902", "DAŇOVÝ DOKLAD", "5 445,00 Kč", "QR Platba",
            "Fyzická osoba zapsaná v živnostenském rejstříku.",
        ] {
            #expect(text.contains(expected), "\(expected) is missing from the page")
        }
    }

    @Test func aCzechInvoicePrintsTheLinesOfTheLayoutInCzech() throws {
        let (_, pdf) = try Probe.render(Fixtures.crownInvoice())

        let text = try Probe.text(of: pdf)

        for expected in [
            "DODAVATEL", "ODBĚRATEL", "Jan Novák", "Dlouhá 12", "110 00 Praha", "IČO", "11223344", "DIČ", "CZ11223344",
            "Alfa Systems s.r.o.", "Hlavní 1", "261 01 Příbram", "12345678", "CZ12345678", "Bankovní účet",
            "1234567890/0800", "CZ65 0800 0000 1920 0014 5399", "Variabilní symbol", "20260902", "Způsob platby",
            "Převodem", "Datum vystavení", "30. 09. 2026", "Datum splatnosti", "14. 10. 2026", "Datum zdan. plnění",
            "DPH", "CENA ZA MJ", "CELKEM BEZ DPH", "7,5", "hod", "Vývoj", "21 %", "600,00 Kč", "4 500,00 Kč",
            "SAZBA", "ZÁKLAD", "945,00 Kč",
        ] {
            #expect(text.contains(expected), "\(expected) is missing from the page")
        }
    }

    @Test func thereIsNoQRCodeOnAnInvoiceThatDoesNotWantOne() throws {
        var invoice = Fixtures.crownInvoice()
        invoice.qrEnabled = false

        let (_, pdf) = try Probe.render(invoice)

        #expect(!(try Probe.text(of: pdf)).contains("QR Platba"))
        #expect(pdf.pageCount == 1)
    }

    // MARK: An English invoice in dollars

    @Test func anEnglishInvoiceInDollarsHasItsTextTheCrownEquivalentsAndTheNoteButNotTheCzechFooter() throws {
        let (data, pdf) = try Probe.render(Fixtures.dollarInvoice())

        let text = try Probe.text(of: pdf)

        for expected in ["Invoice 20260901", "TAX DOCUMENT", "$ 14,350.00", "306,501.65 CZK"] {
            #expect(text.contains(expected), "\(expected) is missing from the page")
        }
        for line in Fixtures.achNote.split(separator: "\n") {
            #expect(text.contains(line), "The note line \(line) is missing from the page")
        }
        #expect(!text.contains("Fyzická osoba zapsaná v živnostenském rejstříku."))
        #expect(data.range(of: Data("IBMPlexSans".utf8)) != nil)
    }

    @Test func anEnglishInvoicePrintsTheLinesOfTheLayoutInEnglish() throws {
        let (_, pdf) = try Probe.render(Fixtures.dollarInvoice())

        let text = try Probe.text(of: pdf)

        for expected in [
            "SUPPLIER", "CUSTOMER", "Czech Republic", "Bravo Labs, Inc.", "100 Congress Avenue", "78701 Austin, TX",
            "United States of America", "Bank account", "000123456789", "Routing number", "123456789", "Reference",
            "20260901", "Payment method", "ACH (USD)", "Issued on", "Sep 30, 2026", "Due on", "Oct 30, 2026",
            "Date of taxable supply", "VAT", "UNIT PRICE", "TOTAL W/O VAT", "205", "Software development", "0 %",
            "$ 70.00", "VAT RATE", "VAT BASE", "$ 0.00", "0.00 CZK",
        ] {
            #expect(text.contains(expected), "\(expected) is missing from the page")
        }
        #expect(!text.contains("QR payment"))
    }

    @Test func anEnglishInvoiceInEurosHasItsQRCodeLabelledInEnglish() throws {
        var invoice = Fixtures.crownInvoice()
        invoice.currency = .eur
        invoice.language = .en

        let (_, pdf) = try Probe.render(invoice)

        #expect(try Probe.text(of: pdf).contains("QR payment"))
    }

    @Test func theCrownEquivalentsOfADraftAreMarkedWithAnApproximatelySign() throws {
        let (_, pdf) = try Probe.render(Fixtures.dollarInvoice(status: .draft))

        #expect(try Probe.text(of: pdf).contains("≈ 306,501.65 CZK"))
    }

    // MARK: The fonts in the file

    @Test func theFileEmbedsPlexSansSoThePageLooksTheSameOnEveryMac() throws {
        let (data, _) = try Probe.render(Fixtures.crownInvoice())

        #expect(data.range(of: Data("IBMPlexSans-Bold".utf8)) != nil)
        #expect(data.range(of: Data("IBMPlexSans".utf8)) != nil)
        #expect(data.range(of: Data("/FontFile2".utf8)) != nil, "The fonts are named in the file but not embedded")
    }

    // MARK: One page

    @Test func twelveItemsAndALongNoteStillFitOnOnePage() throws {
        var invoice = Fixtures.crownInvoice()
        invoice.items = (1...12).map { number in
            InvoiceItem(
                description: "Položka \(number)", quantity: decimal("1"), unit: "ks",
                unitPriceMinor: 10_000 * Int64(number))
        }
        invoice.note = (1...10).map { "Řádek poznámky \($0)" }.joined(separator: "\n")

        let (_, pdf) = try Probe.render(invoice)

        #expect(pdf.pageCount == 1)
        let page = try #require(pdf.page(at: 0)).bounds(for: .mediaBox)
        let text = try Probe.text(of: pdf)
        for expected in ["Položka 1", "Položka 12", "Řádek poznámky 1", "Řádek poznámky 10"] {
            #expect(text.contains(expected), "\(expected) is missing from the page")
        }
        let footer = try Probe.bounds(of: "Fyzická osoba zapsaná v živnostenském rejstříku.", in: pdf)
        let lastNoteLine = try Probe.bounds(of: "Řádek poznámky 10", in: pdf)
        let lastItem = try Probe.bounds(of: "Položka 12", in: pdf)
        #expect(footer.minY >= page.minY + 10, "The footer is cut off at the bottom of the page")
        #expect(lastNoteLine.minY > footer.maxY, "The note runs into the footer")
        #expect(lastItem.minY > lastNoteLine.maxY, "The last item runs into the note")
        #expect(lastItem.maxY < page.maxY)
    }

    @Test func aLongNoteOfAnInvoiceInDollarsStaysOnThePageToo() throws {
        var invoice = Fixtures.dollarInvoice()
        invoice.note = (1...14).map { "Note line \($0)" }.joined(separator: "\n")

        let (_, pdf) = try Probe.render(invoice)

        #expect(pdf.pageCount == 1)
        let page = try #require(pdf.page(at: 0)).bounds(for: .mediaBox)
        let lastLine = try Probe.bounds(of: "Note line 14", in: pdf)
        #expect(lastLine.minY >= page.minY + 10, "The note is cut off at the bottom of the page")
    }

    @Test func aNoteTooLongForThePageIsCutWithAnEllipsisAndTheLegalLineStaysOnIt() throws {
        var invoice = Fixtures.crownInvoice()
        invoice.note = (1...80).map { "Řádek poznámky \($0)" }.joined(separator: "\n")

        let (_, pdf) = try Probe.render(invoice)

        #expect(pdf.pageCount == 1)
        let page = try #require(pdf.page(at: 0)).bounds(for: .mediaBox)
        let footer = try Probe.bounds(of: "Fyzická osoba zapsaná v živnostenském rejstříku.", in: pdf)
        #expect(footer.minY >= page.minY + 10, "The legal line is cut off at the bottom of the page")
        let text = try Probe.text(of: pdf)
        #expect(text.contains("Řádek poznámky 1"))
        #expect(!text.contains("Řádek poznámky 80"))
        #expect(text.contains("…"))
    }

    /// The code is a picture in the PDF, so this draws the page and reads the code back as a scanner would.
    @Test func theQRCodeOnThePageScansAsThePaymentCodeOfTheInvoice() throws {
        let invoice = Fixtures.crownInvoice()
        let (data, _) = try Probe.render(invoice)

        let payload = try #require(Fixtures.document(invoice).text.qr).payload

        #expect(try Probe.scannedCodes(on: data) == [payload])
        #expect(payload.hasPrefix("SPD*1.0*ACC:CZ6508000000192000145399+GIBACZPX*AM:5445.00*CC:CZK*"))
    }

    @Test func aPageWithoutAQRCodeHasNothingToScan() throws {
        var invoice = Fixtures.crownInvoice()
        invoice.qrEnabled = false
        let (data, _) = try Probe.render(invoice)

        #expect(try Probe.scannedCodes(on: data).isEmpty)
    }

    // MARK: The layout

    /// The dark rule, "Faktura" and the number are over the column of the customer, as in the layout, and not over the
    /// whole page.
    @Test func theHeadingIsOverTheColumnOfTheCustomer() throws {
        let (_, pdf) = try Probe.render(Fixtures.crownInvoice())

        let title = try Probe.bounds(of: "Faktura 20260902", in: pdf)
        let customer = try Probe.bounds(of: "Alfa Systems s.r.o.", in: pdf)
        let supplier = try Probe.bounds(of: "Jan Novák", in: pdf)

        #expect(abs(title.minX - customer.minX) < 3, "The heading is not over the customer")
        #expect(title.minX > supplier.minX + 250, "The heading is over the supplier")
    }

    /// A rule is under the heads of the columns and under every item. They are three quarters of a point thick, so a
    /// renderer that snaps to whole points would lose some of them where they fall between two points.
    @Test func everyItemHasItsRuleAndTheHeadsOfTheColumnsHaveOne() throws {
        let (oneItem, _) = try Probe.render(Fixtures.crownInvoice())
        #expect(try Probe.ruleCount(in: oneItem) == 2)

        var invoice = Fixtures.crownInvoice()
        invoice.items = (1...12).map { number in
            InvoiceItem(
                description: "Položka \(number)", quantity: decimal("1"), unit: "ks", unitPriceMinor: 10_000)
        }
        invoice.note = (1...10).map { "Řádek poznámky \($0)" }.joined(separator: "\n")
        let (twelveItems, _) = try Probe.render(invoice)
        #expect(try Probe.ruleCount(in: twelveItems) == 13)

        let (dollars, _) = try Probe.render(Fixtures.dollarInvoice())
        #expect(try Probe.ruleCount(in: dollars) == 2)
    }

    /// The preview on a display of one pixel to the point has no room for a rule of three quarters of a point, which
    /// would vanish. The rules keep one pixel at least, and the PDF, laid out on a finer grid, is not affected.
    @Test func everyRuleSurvivesALayoutOnAGridOfWholePoints() throws {
        let document = Fixtures.document(Fixtures.crownInvoice())

        let data = Probe.pdfData(of: document, displayScale: 1)

        #expect(try Probe.ruleCount(in: data) == 2)
    }

    /// A column is as wide as its widest line, so wide numbers must not run into the text beside them.
    @Test func wideNumbersKeepClearOfTheirNeighboursInTheTable() throws {
        var invoice = Fixtures.crownInvoice()
        invoice.items = [
            InvoiceItem(description: "Vývoj", quantity: decimal("1234.5"), unit: "hodin", unitPriceMinor: 123_456_789)
        ]

        let (_, pdf) = try Probe.render(invoice)

        let quantity = try Probe.bounds(of: "1234,5", in: pdf)
        let unit = try Probe.bounds(of: "hodin", in: pdf)
        let unitPrice = try Probe.bounds(of: "1 234 567,89 Kč", in: pdf)
        let amount = try Probe.bounds(of: "1 524 074 060,21 Kč", in: pdf)
        #expect(unit.minX - quantity.maxX > 4, "The quantity runs into the unit")
        #expect(amount.minX - unitPrice.maxX > 4, "The unit price runs into the amount")
    }

    // MARK: Paper

    /// The page is made of colours of its own, so it is white paper with dark ink when the Mac is in dark mode too.
    @Test func thePageIsWhitePaperWithDarkInkInDarkMode() throws {
        InvoiceFonts.register()
        let page = InvoiceDocumentView(document: Fixtures.document(Fixtures.crownInvoice()))
        let renderer = ImageRenderer(content: page.environment(\.colorScheme, .dark))
        renderer.scale = 1

        let image = try #require(renderer.cgImage)
        let pixels = try Probe.pixels(of: image)

        let corners = [(2, 2), (image.width - 3, 2), (2, image.height - 3), (image.width - 3, image.height - 3)]
        for (x, y) in corners {
            let offset = (y * image.width + x) * 4
            #expect(Array(pixels[offset..<offset + 4]) == [255, 255, 255, 255], "The corner (\(x), \(y)) is not paper")
        }
        let darkest = stride(from: 0, to: pixels.count, by: 4).map { Int(pixels[$0]) }.min() ?? 255
        #expect(darkest < 80, "There is no dark ink on the page")
    }
}
