import Foundation
import Testing
@testable import InvoicesTracker

/// What happens when the text of an invoice is long: the page is made smaller until everything fits it, an invoice
/// never loses a word of its parties, its bank details, its payment method or its items, and only a note that is too
/// long for the page, even at the smallest size, is cut.
@MainActor
struct InvoicePageFitTests {
    private typealias Fixtures = InvoicePageFixtures
    private typealias Probe = InvoicePageProbe

    /// What a page needs is measured in the font it is set in, so the fonts are registered before any test, as the app
    /// does at its launch.
    init() {
        InvoiceFonts.register()
    }

    // MARK: Text that wraps

    /// An account in dollars with a long bank name and address, three items and a note of six lines: the page has room
    /// for the address, and none of it is on the page, while the numbers of the account and the whole note are.
    @Test func aBankNameAndAddressIsNotPrintedHoweverLongItIs() throws {
        var invoice = Fixtures.dollarInvoice()
        invoice.items = Fixtures.items(3, words: 8)
        invoice.note = Fixtures.note(lines: 6)
        let accounts = [Fixtures.dollarAccount(bankNameAndAddress: Fixtures.longBankName)]

        let (_, pdf) = try Probe.render(invoice, accounts: accounts)

        let text = try Probe.text(of: pdf)
        // The words of the address that the note of the invoice (the ACH instructions) does not have.
        for word in ["Community", "Federal", "Savings", "Sample", "Floor", "Exampleton"] {
            #expect(!text.contains(word), "\(word) of the bank's name and address is on the page")
        }
        for printed in ["Bank account", "000123456789", "Routing number", "123456789"] {
            #expect(text.contains(printed), "\(printed) is missing from the page")
        }
        #expect(!text.contains("…"), "Something on the page is cut with an ellipsis")
        for line in 1...6 {
            #expect(text.contains("Note line \(line)"), "Note line \(line) is missing from the page")
        }
    }

    /// A client name and a payment method that wrap, one item and a note of eight lines.
    @Test func aLongCustomerNameAndPaymentMethodArePrintedInFull() throws {
        var invoice = Fixtures.crownInvoice()
        invoice.client.name = Fixtures.longCustomerName
        invoice.paymentMethod = Fixtures.longPaymentMethod
        invoice.items = Fixtures.items(1, words: 8)
        invoice.note = Fixtures.note(lines: 8)

        let (_, pdf) = try Probe.render(invoice)

        let text = try Probe.text(of: pdf)
        #expect(!text.contains("…"), "Something on the page is cut with an ellipsis")
        for word in (Fixtures.longCustomerName + " " + Fixtures.longPaymentMethod).split(separator: " ")
        where word.count >= 3 {
            #expect(text.contains(word), "\(word) is missing from the page")
        }
        for line in 1...8 {
            #expect(text.contains("Note line \(line)"), "Note line \(line) is missing from the page")
        }
        #expect(text.contains("Fyzická osoba zapsaná v živnostenském rejstříku."))
    }

    // MARK: Whether an invoice fits

    /// The two invoices above, whose page has room for their items, their note and the text that wraps, fit it.
    @Test func anInvoiceInDollarsWithANoteAndAnInvoiceWithTextThatWrapsFitOnOnePage() {
        var dollars = Fixtures.dollarInvoice()
        dollars.items = Fixtures.items(3, words: 8)
        dollars.note = Fixtures.note(lines: 6)
        var crowns = Fixtures.crownInvoice()
        crowns.client.name = Fixtures.longCustomerName
        crowns.paymentMethod = Fixtures.longPaymentMethod
        crowns.items = Fixtures.items(1, words: 8)
        crowns.note = Fixtures.note(lines: 8)

        #expect(InvoicePDFRenderer.fitsOnOnePage(Fixtures.document(dollars)))
        #expect(InvoicePDFRenderer.fitsOnOnePage(Fixtures.document(crowns)))
    }

    @Test func twelveItemsWithLongDescriptionsAndALongNoteDoNotFit() {
        var invoice = Fixtures.crownInvoice()
        invoice.items = Fixtures.items(12, words: 32)
        invoice.note = Fixtures.note(lines: 24)

        #expect(!InvoicePDFRenderer.fitsOnOnePage(Fixtures.document(invoice)))
        #expect(InvoiceDocumentView.fittingScale(for: Fixtures.document(invoice)) == nil)
    }

    @Test func anOrdinaryInvoiceIsSetAtFullSize() {
        #expect(InvoiceDocumentView.fittingScale(for: Fixtures.document(Fixtures.crownInvoice())) == 1)
        #expect(InvoiceDocumentView.fittingScale(for: Fixtures.document(Fixtures.dollarInvoice())) == 1)
    }

    @Test func manyItemsAndANoteAreSetSmallerUntilTheyFit() throws {
        var invoice = Fixtures.crownInvoice()
        invoice.items = Fixtures.items(12, words: 8)
        invoice.note = Fixtures.note(lines: 10)

        let scale = try #require(InvoiceDocumentView.fittingScale(for: Fixtures.document(invoice)))

        #expect(scale < 1)
        #expect(scale >= 0.7)
    }

    /// The largest note, in lines, that `invoice` fits the page with.
    private func largestNote(of invoice: Invoice, accounts: [BankAccount]) -> Int {
        var invoice = invoice
        var lines = 0
        while lines < 80 {
            invoice.note = Fixtures.note(lines: lines + 1)
            guard InvoicePDFRenderer.fitsOnOnePage(Fixtures.document(invoice, accounts: accounts)) else { break }
            lines += 1
        }
        return lines
    }

    /// The text of the page shows a note that is whole, with no ellipsis, and one that was cut.
    private func isWhole(_ invoice: Invoice, accounts: [BankAccount], noteLines: Int) throws -> Bool {
        let (_, pdf) = try Probe.render(invoice, accounts: accounts)
        let text = try Probe.text(of: pdf)
        return !text.contains("…") && text.contains("Note line \(noteLines)")
    }

    /// Where `fitsOnOnePage` turns from true to false, the printed note turns from whole to cut, with one line more or
    /// less: the answer is the page's, not a guess.
    @Test(arguments: [
        (InvoiceLanguage.en, 1, 8), (.en, 9, 8), (.en, 12, 8), (.en, 6, 24), (.cs, 1, 8), (.cs, 9, 8), (.cs, 12, 8),
        (.cs, 12, 16),
    ])
    func theNoteIsPrintedWholeExactlyWhileTheInvoiceFits(
        language: InvoiceLanguage, itemCount: Int, descriptionWords: Int
    ) throws {
        var invoice = language == .en ? Fixtures.dollarInvoice() : Fixtures.crownInvoice()
        let accounts = Fixtures.accounts
        if language == .cs {
            invoice.client.name = Fixtures.longCustomerName
            invoice.paymentMethod = Fixtures.longPaymentMethod
        }
        invoice.items = Fixtures.items(itemCount, words: descriptionWords)
        let largest = largestNote(of: invoice, accounts: accounts)
        #expect(largest > 0 && largest < 80, "The test found no largest note")

        invoice.note = Fixtures.note(lines: largest)
        #expect(try isWhole(invoice, accounts: accounts, noteLines: largest), "\(largest) lines should fit")

        invoice.note = Fixtures.note(lines: largest + 1)
        #expect(!(try isWhole(invoice, accounts: accounts, noteLines: largest + 1)), "\(largest + 1) lines are cut")
    }

    /// A note that is too long is the only thing cut: the parties, the payment details, the items, the summary and the
    /// legal line are printed whole.
    @Test func aNoteThatIsTooLongIsTheOnlyThingCut() throws {
        var invoice = Fixtures.crownInvoice()
        invoice.client.name = Fixtures.longCustomerName
        invoice.paymentMethod = Fixtures.longPaymentMethod
        invoice.items = Fixtures.items(12, words: 8)
        invoice.note = Fixtures.note(lines: 40)

        let (_, pdf) = try Probe.render(invoice)

        let text = try Probe.text(of: pdf)
        #expect(!InvoicePDFRenderer.fitsOnOnePage(Fixtures.document(invoice)))
        #expect(text.contains("…"))
        #expect(!text.contains("Note line 40"))
        for word in (Fixtures.longCustomerName + " " + Fixtures.longPaymentMethod).split(separator: " ")
        where word.count >= 3 {
            #expect(text.contains(word), "\(word) is missing from the page")
        }
        for number in 1...12 {
            #expect(text.contains("Vývoj a nasazení modulu \(number) pro"), "Item \(number) is missing")
        }
        #expect(text.contains("Fyzická osoba zapsaná v živnostenském rejstříku."))
        #expect(text.contains("QR Platba"))
    }

    // MARK: The QR code on a small page

    /// With a long note the page is set at 70 %, and the QR code with it: about 21 mm.
    @Test func theQRCodeOfAPageSetAtSeventyPercentStillScans() throws {
        var invoice = Fixtures.crownInvoice()
        invoice.items = Fixtures.items(12, words: 8)
        invoice.note = Fixtures.note(lines: 22)
        let document = Fixtures.document(invoice)
        #expect(InvoiceDocumentView.fittingScale(for: document) == 0.7, "The page is not set at 70 %")

        let (data, _) = try Probe.render(invoice)

        let payload = try #require(document.text.qr).payload
        #expect(try Probe.scannedCodes(on: data) == [payload])
    }

    /// The code of an invoice in euros carries more (the name of the supplier and the remittance), and at 70 % its
    /// modules are about 0,4 mm.
    @Test func theLongerQRCodeOfAnInvoiceInEurosOnAPageSetAtSeventyPercentStillScans() throws {
        var supplier = Fixtures.supplier
        supplier.name = "Jan Novák, vývoj a správa softwaru pro malé a střední podniky a živnostníky"
        var invoice = Fixtures.crownInvoice()
        invoice.currency = .eur
        invoice.language = .en
        invoice.items = Fixtures.items(12, words: 8)
        invoice.note = Fixtures.note(lines: 22)
        let document = Fixtures.document(invoice, supplier: supplier)
        #expect(InvoiceDocumentView.fittingScale(for: document) == 0.7, "The page is not set at 70 %")

        InvoiceFonts.register()
        let data = InvoicePDFRenderer.pdfData(for: document)

        let payload = try #require(document.text.qr).payload
        #expect(payload.utf8.count > 150, "The code is not a long one")
        #expect(try Probe.scannedCodes(on: data) == [payload])
    }
}
