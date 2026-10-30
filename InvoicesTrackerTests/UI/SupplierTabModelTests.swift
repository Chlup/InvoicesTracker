import Foundation
import Testing
@testable import InvoicesTracker

/// The tab Moje údaje: the supplier's details and bank accounts are saved by themselves a moment after the last key (at
/// once in these tests, unless a test waits itself), a menu and the account in euros at once, and an IBAN or a BIC with
/// a typo is kept in its field with a message and never saved. The data is invented, the IBANs the well-known example
/// ones.
@Suite(.settlesBackups)
@MainActor
struct SupplierTabModelTests {
    /// The tab of a new app model, loaded as the screen loads it, which saves after `wait` lets it (at once by
    /// default).
    private func loadedModel(of app: AppModel, wait: ManualDelay? = nil) async -> SupplierTabModel {
        let model =
            if let wait {
                SupplierTabModel(app: app, saveDelay: .milliseconds(500), wait: wait.wait)
            } else {
                SupplierTabModel(app: app, saveDelay: .zero)
            }
        await model.load()
        return model
    }

    @Test func theDetailsAndTheAccountsAreSavedOnceTheTypingStops() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let app = try await makeSettingsApp(in: directory)
        let database = try #require(app.database)
        let delay = ManualDelay()
        let model = await loadedModel(of: app, wait: delay)
        let version = app.dataVersion

        model.setText(.name, "Jan")
        model.setText(.name, "Jan Novák")
        model.setText(.czkAccountNumber, "123456789/0100")

        // Nothing is read or saved before the typing stops.
        #expect(try await database.supplier().name == "")
        #expect(model.text(.name) == "Jan Novák")
        try await waitUntil { delay.armed == 1 }
        #expect(delay.fire())
        try await waitUntil { try await database.supplier().name == "Jan Novák" }

        #expect(try await database.bankAccounts() == [BankAccount(currency: .czk, accountNumber: "123456789/0100")])
        #expect(app.dataVersion > version)
        #expect(
            model.statusLines.first?.text
                == "Faktury v Kč: účet 123456789/0100 · doplňte IBAN, jinak faktura nebude mít QR Platbu")
        // The test ends once the write that the timer started has told the app of it: the backups that this starts are
        // waited for as the test ends (`.settlesBackups`).
        await model.saveNow()
    }

    @Test(.hangGuard)
    func aTimerThatWakesAfterTheNextKeyReplacedItReadsNothing() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let app = try await makeSettingsApp(in: directory)
        let database = try #require(app.database)
        let delay = StubbornDelay()
        let model = SupplierTabModel(app: app, saveDelay: .milliseconds(500), wait: delay.wait)
        await model.load()

        // The first key starts a wait; the second one replaces it, but the first wait ends all the same.
        model.setText(.name, "Jan")
        try await waitUntil { delay.armed == 1 }
        model.setText(.name, "Jan Novák")
        try await waitUntil { delay.armed == 2 }
        #expect(delay.fireOldest())
        await letWaitingJobsRun()

        // The timer that was replaced reads nothing: the text waits for the timer of the last key.
        #expect(model.supplier?.name == "")
        #expect(model.hasUnsavedInput)

        #expect(delay.fireOldest())
        try await waitUntil { try await database.supplier().name == "Jan Novák" }
        await model.saveNow()
    }

    @Test func anIBANWithATypoIsKeptInItsFieldWithAMessageAndNotSaved() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let app = try await makeSettingsApp(in: directory)
        let database = try #require(app.database)
        let model = await loadedModel(of: app)

        model.setText(.czkIBAN, "CZ65 0800 0000 1920 0014 5398")
        await model.saveNow()

        #expect(model.text(.czkIBAN) == "CZ65 0800 0000 1920 0014 5398")
        #expect(model.error(.czkIBAN) == SupplierTabModel.ibanInvalid)
        #expect(try await database.bankAccounts().isEmpty)

        model.setText(.czkIBAN, "CZ65 0800 0000 1920 0014 5399")
        await model.saveNow()

        #expect(model.error(.czkIBAN) == nil)
        #expect(try await database.bankAccounts().first?.iban == "CZ6508000000192000145399")
    }

    @Test func anIBANAndABICAreSavedInCapitalsWithoutSpaces() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let app = try await makeSettingsApp(in: directory)
        let database = try #require(app.database)
        let model = await loadedModel(of: app)

        model.setText(.czkIBAN, " cz65\u{00A0}0800 0000 1920 0014 5399 ")
        model.setText(.czkBIC, "giba czpx")
        await model.saveNow()

        let account = try #require(try await database.bankAccounts().first)
        #expect(account.iban == "CZ6508000000192000145399")
        #expect(account.bic == "GIBACZPX")
        #expect(model.text(.czkIBAN) == "CZ6508000000192000145399")
        #expect(model.text(.czkBIC) == "GIBACZPX")
    }

    @Test func aBICOfAnotherLengthIsKeptInItsFieldWithAMessageAndNotSaved() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let app = try await makeSettingsApp(in: directory)
        let database = try #require(app.database)
        let model = await loadedModel(of: app)

        model.setText(.czkBIC, "GIBACZP")
        model.setText(.czkAccountNumber, "123456789/0100")
        await model.saveNow()

        #expect(model.error(.czkBIC) == SupplierTabModel.bicInvalid)
        #expect(try await database.bankAccounts() == [BankAccount(currency: .czk, accountNumber: "123456789/0100")])
    }

    @Test func theCountryAndTheTypeOfTheAccountInDollarsAreSavedAtOnce() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let app = try await makeSettingsApp(in: directory)
        let database = try #require(app.database)
        let model = await loadedModel(of: app)

        model.setCountry("SK")
        model.setUSDAccountType("Savings")
        try await waitUntil { try await database.bankAccounts().first?.accountType == "Savings" }

        #expect(try await database.supplier().country == "SK")
        #expect(model.usdAccountType == "Savings")
        // The test ends once the write that the timer started has told the app of it: the backups that this starts are
        // waited for as the test ends (`.settlesBackups`).
        await model.saveNow()
    }

    @Test func theUSDAccountHasNoBankAddressField() {
        let fields = SupplierField.allCases.filter { $0.currency == .usd }

        #expect(fields == [.usdAccountNumber, .usdRoutingNumber])
    }

    /// The tab no longer asks for the name and address of the bank, but what the data has stays with the account while
    /// its other fields are edited.
    @Test func theBankNameAndAddressOfTheAccountInDollarsStaysWhileItsOtherFieldsAreEdited() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let app = try await makeSettingsApp(in: directory)
        let database = try #require(app.database)
        try await database.saveBankAccounts([
            BankAccount(
                currency: .usd, accountNumber: "000123456789", routingNumber: "123456789", accountType: "Checking",
                bankNameAndAddress: "Chase Bank, 270 Park Ave, New York")
        ])
        let model = await loadedModel(of: app)

        model.setText(.usdRoutingNumber, "021000021")
        model.setUSDAccountType("Savings")
        await model.saveNow()

        #expect(
            try await database.bankAccounts() == [
                BankAccount(
                    currency: .usd, accountNumber: "000123456789", routingNumber: "021000021",
                    accountType: "Savings", bankNameAndAddress: "Chase Bank, 270 Park Ave, New York")
            ])
    }

    @Test func theAccountInEurosIsAddedAndRemovedAtOnce() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let app = try await makeSettingsApp(in: directory)
        let database = try #require(app.database)
        let model = await loadedModel(of: app)
        #expect(!model.hasEURAccount)

        model.addEURAccount()
        try await waitUntil { try await database.bankAccounts().contains { $0.currency == .eur } }

        #expect(model.hasEURAccount)
        #expect(model.statusLines.last?.text == "Faktury v EUR: doplňte IBAN")
        model.setText(.eurIBAN, "DE89 3704 0044 0532 0130 00")
        await model.saveNow()
        #expect(try await database.bankAccounts().first { $0.currency == .eur }?.iban == "DE89370400440532013000")

        model.setText(.eurBIC, "COBADEFFXXX")
        model.removeEURAccount()
        try await waitUntil { try await !database.bankAccounts().contains { $0.currency == .eur } }

        #expect(!model.hasEURAccount)
        #expect(model.text(.eurIBAN) == "")
        #expect(model.text(.eurBIC) == "")
        #expect(
            model.statusLines.last?.text
                == "Faktury v EUR: bez účtu v eurech – přidejte ho, než vystavíte první fakturu v eurech")
        // The test ends once the write that the timer started has told the app of it: the backups that this starts are
        // waited for as the test ends (`.settlesBackups`).
        await model.saveNow()
    }

    @Test func whatIsTypedSurvivesALoadAndWhatIsNotTouchedFollowsTheData() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let app = try await makeSettingsApp(in: directory)
        let database = try #require(app.database)
        let delay = ManualDelay()
        let model = await loadedModel(of: app, wait: delay)

        model.setText(.city, "Praha")
        var elsewhere = try await database.supplier()
        elsewhere.name = "Jana Nováková"
        try await database.saveSupplier(elsewhere)
        await app.didWrite()
        await model.load()

        #expect(model.text(.city) == "Praha")
        #expect(model.text(.name) == "Jana Nováková")
        try await waitUntil { delay.armed == 1 }
        #expect(delay.fire())
        try await waitUntil { try await database.supplier().city == "Praha" }
        #expect(try await database.supplier().name == "Jana Nováková")
        // The test ends once the write that the timer started has told the app of it: the backups that this starts are
        // waited for as the test ends (`.settlesBackups`).
        await model.saveNow()
    }

    @Test func aSaveThatFailsIsSaidAndMadeWithTheNextChange() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let app = try await makeSettingsApp(in: directory)
        let database = try #require(app.database)
        let model = await loadedModel(of: app)
        try await setDatabaseReadOnly(true, database)

        model.setText(.name, "Jan Novák")
        await model.saveNow()

        #expect(model.saveFailure == SupplierTabModel.saveFailureText)
        #expect(model.supplier?.name == "Jan Novák")
        #expect(try await database.supplier().name == "")
        try await setDatabaseReadOnly(false, database)
        model.setText(.city, "Praha")
        await model.saveNow()
        #expect(model.saveFailure == nil)
        #expect(try await database.supplier().name == "Jan Novák")
        #expect(try await database.supplier().city == "Praha")
    }

    @Test func theFieldsAreTrimmedWhenTheyAreSaved() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let app = try await makeSettingsApp(in: directory)
        let database = try #require(app.database)
        let model = await loadedModel(of: app)

        model.setText(.email, "  jan@example.com \n")
        await model.saveNow()

        #expect(try await database.supplier().email == "jan@example.com")
        #expect(model.text(.email) == "  jan@example.com \n")
    }
}
