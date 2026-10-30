import Foundation
import Testing
@testable import InvoicesTracker

/// What the supplier step makes of the fields as they were typed.
struct SupplierDraftTests {
    private func filledDraft() -> SupplierDraft {
        var draft = SupplierDraft()
        draft.name = "  Jana Nováková "
        draft.street = "Dlouhá 12"
        draft.postcode = " 110 00"
        draft.city = "Praha  "
        draft.ico = "12345678"
        draft.dic = " CZ12345678"
        draft.czkAccount = " 19-2000145399/0800 "
        draft.czkIban = "CZ65 0800 0000 1920 0014 5399"
        return draft
    }

    @Test func aDraftWithNothingTypedHasNoAccount() {
        var draft = SupplierDraft()

        #expect(draft.czkBankAccount == nil)

        // Spaces and line breaks are nothing.
        draft.czkAccount = "   "
        draft.czkIban = "\n"

        #expect(draft.czkBankAccount == nil)
    }

    @Test func theSupplierIsWhatWasTypedWithoutTheSpacesAroundIt() {
        let supplier = filledDraft().supplier

        #expect(supplier.name == "Jana Nováková")
        #expect(supplier.street == "Dlouhá 12")
        #expect(supplier.postcode == "110 00")
        #expect(supplier.city == "Praha")
        #expect(supplier.ico == "12345678")
        #expect(supplier.dic == "CZ12345678")
        // What the step does not ask for stays as a new supplier has it.
        #expect(supplier.country == Supplier().country)
        #expect(supplier.email.isEmpty)
        #expect(supplier.czechFooter == Supplier().czechFooter)
    }

    @Test func theAccountInCrownsHasTheNumberAndTheIBANInCapitalsWithoutSpaces() {
        var draft = filledDraft()
        draft.czkIban = " cz65 0800\u{00A0}0000 1920 0014 5399 "

        #expect(
            draft.czkBankAccount
                == BankAccount(currency: .czk, accountNumber: "19-2000145399/0800", iban: "CZ6508000000192000145399"))
        #expect(draft.ibanError == nil)
    }

    @Test func anIBANWithATypoIsRefusedAsMojeÚdajeRefusesIt() {
        var draft = filledDraft()
        draft.czkIban = "CZ65 0800 0000 1920 0014 5398"

        #expect(draft.ibanError == SupplierTabModel.ibanInvalid)

        draft.czkIban = "  "
        #expect(draft.ibanError == nil)
    }

    @Test func anAccountWithOnlyANumberOrOnlyAnIBANIsKept() {
        var number = SupplierDraft()
        number.czkAccount = "19-2000145399/0800"
        var iban = SupplierDraft()
        iban.czkIban = "CZ6508000000192000145399"

        #expect(number.czkBankAccount == BankAccount(currency: .czk, accountNumber: "19-2000145399/0800"))
        #expect(iban.czkBankAccount == BankAccount(currency: .czk, iban: "CZ6508000000192000145399"))
    }
}
