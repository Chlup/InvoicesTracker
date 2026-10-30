import Foundation
import Testing
@testable import InvoicesTracker

/// Saving an invoice only when it is still as it was read: what work that reads an invoice, works something out from
/// it and writes it back relies on, so that an edit saved in between is never overwritten.
struct InvoiceRecomputeRepositoryTests {
    @Test func anInvoiceThatIsStillAsItWasReadIsSaved() async throws {
        let (database, directory) = try makeDatabase()
        defer { removeTemporaryDirectory(directory) }
        let id = try await database.saveInvoice(Invoice.fixture())
        let listed = try #require(try await database.invoice(id: id))
        var updated = listed
        updated.payment = Payment.fixture(on: "2026-10-03")

        let saved = try await database.saveInvoice(updated, ifUnchangedFrom: listed)

        #expect(saved)
        #expect(try await database.invoice(id: id) == updated)
    }

    @Test func anInvoiceChangedSinceItWasReadIsLeftAsItWasChanged() async throws {
        let (database, directory) = try makeDatabase()
        defer { removeTemporaryDirectory(directory) }
        let id = try await database.saveInvoice(Invoice.fixture())
        let listed = try #require(try await database.invoice(id: id))
        var edited = listed
        edited.note = "Opraveno po vystavení."
        try await database.saveInvoice(edited)
        var updated = listed
        updated.payment = Payment.fixture(on: "2026-10-03")

        let saved = try await database.saveInvoice(updated, ifUnchangedFrom: listed)

        #expect(!saved)
        #expect(try await database.invoice(id: id) == edited)
    }

    @Test func anInvoiceDeletedSinceItWasReadIsNotBroughtBack() async throws {
        let (database, directory) = try makeDatabase()
        defer { removeTemporaryDirectory(directory) }
        let id = try await database.saveInvoice(Invoice.fixture())
        let listed = try #require(try await database.invoice(id: id))
        try await database.deleteInvoice(id: id)
        var updated = listed
        updated.payment = Payment.fixture(on: "2026-10-03")

        let saved = try await database.saveInvoice(updated, ifUnchangedFrom: listed)

        #expect(!saved)
        #expect(try await database.invoiceCount() == 0)
    }

    @Test func anotherInvoiceThanTheOneReadIsNotSaved() async throws {
        let (database, directory) = try makeDatabase()
        defer { removeTemporaryDirectory(directory) }
        let first = try await database.saveInvoice(Invoice.fixture(number: "20260901"))
        let second = try await database.saveInvoice(Invoice.fixture(number: "20260902"))
        let listed = try #require(try await database.invoice(id: first))
        var other = try #require(try await database.invoice(id: second))
        other.note = "Jiná faktura."

        let saved = try await database.saveInvoice(other, ifUnchangedFrom: listed)

        #expect(!saved)
        #expect(try await database.invoice(id: second)?.note == "")
    }
}
