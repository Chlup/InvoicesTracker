import Foundation
import Testing
@testable import InvoicesTracker

/// The form of a client: what it starts with, what it says is wrong, and what saving it writes.
@Suite(.settlesBackups)
@MainActor
struct ClientFormModelTests {
    /// A form on a new client with a name, which can be saved as it is.
    private func newForm(_ f: ClientsFixture, name: String = "Epsilon Group a.s.") -> ClientFormModel {
        let model = ClientFormModel(app: f.app, client: nil)
        model.name = name
        return model
    }

    // MARK: A new client

    @Test func aNewClientStartsInCrownsWithTheUsualTermsInCzech() async throws {
        try await ClientsFixture.with { f in
            let model = ClientFormModel(app: f.app, client: nil)

            #expect(model.isNew)
            #expect(model.title == "Nový odběratel")
            #expect(model.subtitle == "Výchozí měna, DPH, splatnost a platba se použijí pro nové faktury.")
            #expect(model.name == "")
            #expect(model.country == "CZ")
            #expect(model.currency == .czk)
            #expect(model.vatMode == .domestic21)
            #expect(model.language == .cs)
            #expect(model.dueDaysText == "14")
            #expect(model.paymentMethod == "Převodem")
        }
    }

    @Test func aStoredClientStartsWithWhatItHas() async throws {
        try await ClientsFixture.with { f in
            let bravo = try await f.storedClient(f.bravoID)

            let model = ClientFormModel(app: f.app, client: bravo)

            #expect(!model.isNew)
            #expect(model.title == "Upravit odběratele")
            #expect(model.subtitle == "Bravo Labs, Inc.")
            #expect(model.name == "Bravo Labs, Inc.")
            #expect(model.street == "100 Congress Avenue")
            #expect(model.city == "Austin, TX")
            #expect(model.postcode == "78701")
            #expect(model.country == "US")
            #expect(model.email == "billing@example.org")
            #expect(model.currency == .usd)
            #expect(model.vatMode == .outsideCountry)
            #expect(model.language == .en)
            #expect(model.dueDaysText == "30")
            #expect(model.paymentMethod == "ACH (USD)")
        }
    }

    // MARK: What is wrong

    @Test func aFormWithAnIČOThatIsNotEightDigitsSaysSo() async throws {
        try await ClientsFixture.with { f in
            let model = newForm(f)
            model.ico = "1234"

            #expect(model.errors == ["IČO má 8 číslic."])
        }
    }

    @Test(arguments: ["", "12345678", "  12345678  ", "00000001"])
    func aCzechClientsIČOThatIsEmptyOrEightDigitsIsFine(ico: String) async throws {
        try await ClientsFixture.with { f in
            let model = newForm(f)
            model.ico = ico

            #expect(model.errors.isEmpty)
        }
    }

    @Test(arguments: ["1234567", "123456789", "1234567A", "1234 5678", "١٢٣٤٥٦٧٨", "HRB 123456"])
    func aCzechClientsIČOThatIsNotEightDigitsIsNotFine(ico: String) async throws {
        try await ClientsFixture.with { f in
            let model = newForm(f)
            #expect(model.country == "CZ")
            model.ico = ico

            #expect(model.errors == ["IČO má 8 číslic."])
        }
    }

    /// The registration number of a client of another country is whatever its country calls it, and the import copies
    /// it as it is.
    @Test(arguments: [
        "HRB 123456", "HRB 123456 B", "12-3456789", "CHE-123.456.789", "552 100 554 00825", "1234", "12345678",
        "ABCDEFGH", "  HRB 123456  ",
    ])
    func aClientOfAnotherCountryHasAnyRegistrationNumberAndItIsSavedAsTyped(ico: String) async throws {
        try await ClientsFixture.with { f in
            let model = newForm(f)
            model.country = "DE"
            model.ico = ico
            #expect(model.errors.isEmpty)

            let id = try await model.save()

            #expect(try await f.storedClient(id).ico == ico.trimmingCharacters(in: .whitespaces))
        }
    }

    @Test func theRegistrationNumberOfAnotherCountryHasALengthLimit() async throws {
        try await ClientsFixture.with { f in
            let model = newForm(f)
            model.country = "US"

            model.ico = String(repeating: "7", count: 40)
            #expect(model.errors.isEmpty)

            model.ico = String(repeating: "7", count: 41)
            #expect(model.errors == ["IČO může mít nejvýše 40 znaků."])

            // Spaces around it are not part of it.
            model.ico = "  " + String(repeating: "7", count: 40) + "  "
            #expect(model.errors.isEmpty)
        }
    }

    @Test func theEightDigitsAreCheckedWhileTheCountryIsCzechAndOnlyThen() async throws {
        try await ClientsFixture.with { f in
            let model = newForm(f)
            model.ico = "HRB 123456"
            #expect(model.errors == ["IČO má 8 číslic."])

            model.country = "DE"
            #expect(model.errors.isEmpty)

            model.country = "CZ"
            #expect(model.errors == ["IČO má 8 číslic."])

            // A client without a country has no country whose rule would apply.
            model.country = ""
            #expect(model.errors.isEmpty)
            model.ico = "12345678"
            model.country = "CZ"
            #expect(model.errors.isEmpty)
        }
    }

    @Test func aStoredNameOfTheCzechRepublicIsACzechClientToo() async throws {
        try await ClientsFixture.with { f in
            var client = SearchFixtures.alfa
            client.country = "Česká republika"
            client.ico = "HRB 123456"

            let model = ClientFormModel(app: f.app, client: client)

            #expect(model.country == "CZ")
            #expect(model.errors == ["IČO má 8 číslic."])
        }
    }

    @Test func anImportedClientOfAnotherCountryWithItsRegistrationNumberCanBeEdited() async throws {
        try await ClientsFixture.with { f in
            var client = ClientsFixture.imported
            client.ico = "HRB 123456"
            let imported = try await f.store(client)
            let model = ClientFormModel(app: f.app, client: imported)
            model.language = .cs

            #expect(model.errors.isEmpty)
            try await model.save()

            let stored = try await f.storedClient(imported.id)
            #expect(stored.ico == "HRB 123456")
            #expect(stored.language == .cs)
            #expect(stored.editedAfterImport)
        }
    }

    @Test func aNameIsNeeded() async throws {
        try await ClientsFixture.with { f in
            let model = ClientFormModel(app: f.app, client: nil)
            #expect(model.errors == ["Vyplňte název odběratele."])

            model.name = "   "
            #expect(model.errors == ["Vyplňte název odběratele."])

            model.name = "Epsilon"
            #expect(model.errors.isEmpty)
        }
    }

    @Test(arguments: [("", true), ("fakturace@example.com", true), ("a@b", true), ("fakturace.example.com", false)])
    func anEmailIsEmptyOrHasAnAtSign(email: String, fine: Bool) async throws {
        try await ClientsFixture.with { f in
            let model = newForm(f)
            model.email = email

            #expect(model.errors == (fine ? [] : ["E-mail musí obsahovat @."]))
        }
    }

    @Test(
        arguments: [
            ("14", 14), ("0", 0), ("999", 999), (" 30 ", 30), ("1000", nil), ("-1", nil), ("", nil), ("14 dní", nil),
            ("1,5", nil), ("99999999999999999999", nil),
        ] as [(String, Int?)])
    func theDueDaysAreAWholeNumberOfDaysTheEditorAccepts(text: String, days: Int?) async throws {
        try await ClientsFixture.with { f in
            let model = newForm(f)
            model.dueDaysText = text

            #expect(model.dueDays == days)
            #expect(model.errors == (days == nil ? ["Splatnost musí být 0 až 999 dní."] : []))
        }
    }

    @Test func theErrorsComeInTheOrderOfTheFields() async throws {
        try await ClientsFixture.with { f in
            let model = ClientFormModel(app: f.app, client: nil)
            model.ico = "12"
            model.email = "x"
            model.dueDaysText = "x"

            #expect(
                model.errors == [
                    "Vyplňte název odběratele.", "IČO má 8 číslic.", "E-mail musí obsahovat @.",
                    "Splatnost musí být 0 až 999 dní.",
                ])
        }
    }

    @Test func theErrorsShowOnlyOnceASaveWasTried() async throws {
        try await ClientsFixture.with { f in
            let model = ClientFormModel(app: f.app, client: nil)
            #expect(!model.showsErrors)

            await #expect(throws: FormSaveError.invalid) { try await model.save() }

            #expect(model.showsErrors)
        }
    }

    // MARK: Saving

    @Test func savingANewClientStoresItAndTellsTheApp() async throws {
        try await ClientsFixture.with { f in
            let model = newForm(f, name: "  Epsilon Group a.s. ")
            model.street = "Dlouhá 1"
            model.city = "Praha"
            model.postcode = "110 00"
            model.ico = "87654321"
            model.dic = "CZ87654321"
            model.email = "fakturace@example.com"
            model.vatMode = .domestic12
            model.dueDaysText = " 21 "
            model.paymentMethod = "  Hotově "
            let version = f.app.dataVersion

            let id = try await model.save()

            let stored = try await f.storedClient(id)
            #expect(
                stored
                    == Client(
                        id: id, name: "Epsilon Group a.s.", street: "Dlouhá 1", postcode: "110 00", city: "Praha",
                        country: "CZ", ico: "87654321", dic: "CZ87654321", email: "fakturace@example.com", phone: "",
                        currency: .czk, vatMode: .domestic12, dueDays: 21, paymentMethod: "Hotově", language: .cs,
                        origin: .app, editedAfterImport: false))
            #expect(f.app.dataVersion == version + 1)
            #expect(try await f.database.clientCount() == 3)
        }
    }

    @Test func anEmptyWayOfPaymentIsTransfer() async throws {
        try await ClientsFixture.with { f in
            let model = newForm(f)
            model.paymentMethod = "  "

            let id = try await model.save()

            #expect(try await f.storedClient(id).paymentMethod == "Převodem")
        }
    }

    @Test func savingAStoredClientChangesItInPlaceAndKeepsWhatTheFormDoesNotShow() async throws {
        try await ClientsFixture.with { f in
            var alfa = try await f.storedClient(f.alfaID)
            alfa.phone = "+420 777 111 222"
            try await f.database.saveClient(alfa)
            let template = try await f.store(ClientsFixture.template(for: f.alfaID))
            let model = ClientFormModel(app: f.app, client: alfa)
            model.name = "Alfa Systems a.s."
            model.currency = .eur
            model.language = .en

            let id = try await model.save()

            #expect(id == f.alfaID)
            let stored = try await f.storedClient(f.alfaID)
            #expect(stored.name == "Alfa Systems a.s.")
            #expect(stored.currency == .eur)
            #expect(stored.language == .en)
            #expect(stored.phone == "+420 777 111 222")
            #expect(stored.origin == .app && !stored.editedAfterImport)
            #expect(try await f.database.clientCount() == 2)
            // The templates of the client are still its own.
            #expect(try await f.database.templates() == [template])
        }
    }

    @Test func savingAnImportedClientMarksItAsEditedAndKeepsItsOrigin() async throws {
        try await ClientsFixture.with { f in
            let imported = try await f.store(ClientsFixture.imported)
            #expect(!imported.editedAfterImport)
            let model = ClientFormModel(app: f.app, client: imported)

            try await model.save()

            let stored = try await f.storedClient(imported.id)
            #expect(stored.editedAfterImport)
            #expect(stored.origin == .imported)
            #expect(stored.name == "Delta Import GmbH")
            #expect(stored.phone == "+49 30 000000")
        }
    }

    @Test func aClientOfTheAppIsNeverMarkedAsEditedAfterAnImport() async throws {
        try await ClientsFixture.with { f in
            let model = ClientFormModel(app: f.app, client: try await f.storedClient(f.alfaID))

            try await model.save()

            #expect(try await f.storedClient(f.alfaID).editedAfterImport == false)
        }
    }

    @Test func aFormThatIsNotRightWritesNothing() async throws {
        try await ClientsFixture.with { f in
            let model = ClientFormModel(app: f.app, client: try await f.storedClient(f.alfaID))
            model.name = "Přejmenovaný"
            model.ico = "1234"
            let version = f.app.dataVersion
            let writes = await f.database.writeCount

            await #expect(throws: FormSaveError.invalid) { try await model.save() }

            #expect(try await f.storedClient(f.alfaID).name == "Alfa Systems s.r.o.")
            #expect(f.app.dataVersion == version)
            #expect(await f.database.writeCount == writes)
        }
    }

    @Test func aClientThatWasDeletedMeanwhileIsNotBroughtBack() async throws {
        try await ClientsFixture.with { f in
            let model = ClientFormModel(app: f.app, client: try await f.storedClient(f.alfaID))
            model.name = "Přejmenovaný"
            try await f.deleteClient(f.alfaID)
            let version = f.app.dataVersion

            await #expect(throws: ClientError.notFound) { try await model.save() }

            #expect(model.failure == "Odběratel mezitím byl smazán.")
            #expect(try await f.database.client(id: f.alfaID) == nil)
            #expect(try await f.database.clientCount() == 1)
            #expect(f.app.dataVersion == version)
        }
    }

    @Test func aSaveThatFailsSaysSoAndWritesNothing() async throws {
        try await ClientsFixture.with { f in
            let model = ClientFormModel(app: f.app, client: try await f.storedClient(f.alfaID))
            model.name = "Přejmenovaný"
            try await setDatabaseReadOnly(true, f.database)
            let version = f.app.dataVersion

            await #expect(throws: (any Error).self) { try await model.save() }

            #expect(model.failure == "Odběratele se nepodařilo uložit.")
            #expect(f.app.dataVersion == version)
            try await setDatabaseReadOnly(false, f.database)
            #expect(try await f.storedClient(f.alfaID).name == "Alfa Systems s.r.o.")
            // The next try starts afresh, and works.
            try await model.save()
            #expect(model.failure == nil)
            #expect(try await f.storedClient(f.alfaID).name == "Přejmenovaný")
        }
    }

    @Test func aRenamedClientIsFoundByItsNewNameInTheSearch() async throws {
        try await ClientsFixture.with { f in
            try await f.database.saveInvoice(SearchFixtures.crownInvoice(clientID: f.alfaID))
            let model = ClientFormModel(app: f.app, client: try await f.storedClient(f.alfaID))
            model.name = "Zlatnice Systems s.r.o."

            try await model.save()

            let found = try await f.database.searchInvoiceIDs(
                "zlatnice", scope: .issued, year: 2026, asOf: civilDate("2026-10-17"))
            #expect(found.count == 1)
        }
    }

    @Test func aSaveInAFormThatLostTheDataFindsItLocked() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let app = makeAppModel(in: directory)
        let model = ClientFormModel(app: app, client: nil)
        model.name = "Epsilon"

        await #expect(throws: VaultError.locked) { try await model.save() }

        #expect(model.failure == "Data jsou zamčená. Nejdřív je odemkněte.")
    }

    @Test func aSecondSaveWhileOneIsRunningIsRefused() async throws {
        try await ClientsFixture.with { f in
            let model = newForm(f)
            #expect(model.isSaving == false)

            // The first save has begun, and waits for the data, when its task is made.
            let first = Task.immediate { try await model.save() }
            #expect(model.isSaving)
            await #expect(throws: FormSaveError.alreadySaving) { try await model.save() }
            let id = try await first.value

            #expect(model.isSaving == false)
            #expect(model.failure == nil)
            // One client was made, not two.
            #expect(try await f.database.clientCount() == 3)
            #expect(try await f.storedClient(id).name == "Epsilon Group a.s.")
        }
    }

    // MARK: Countries

    @Test func theCountriesToChooseAreAllOfThemByTheirCzechNames() async throws {
        try await ClientsFixture.with { f in
            let model = ClientFormModel(app: f.app, client: nil)

            let choices = model.countryChoices

            #expect(choices.map(\.code) == Countries.all)
            #expect(choices.first { $0.code == "CZ" }?.name == "Česko")
            #expect(choices.first { $0.code == "US" }?.name == "Spojené státy americké")
        }
    }

    @Test func aCountryThatAnImportLeftAsTextStaysSelectableAndKeepsItsText() async throws {
        try await ClientsFixture.with { f in
            var client = ClientsFixture.imported
            client.country = "Brazil"
            let stored = try await f.store(client)
            let model = ClientFormModel(app: f.app, client: stored)

            #expect(model.country == "Brazil")
            #expect(model.countryChoices.first == CountryChoice(code: "Brazil", name: "Brazil"))
            #expect(model.countryChoices.dropFirst().map(\.code) == Countries.all)

            try await model.save()

            #expect(try await f.storedClient(stored.id).country == "Brazil")
        }
    }

    @Test func aNameOfACountryThatTheImportKnowsIsOpenedAsItsCode() async throws {
        try await ClientsFixture.with { f in
            for (stored, shown) in [("Česká republika", "CZ"), ("cz", "CZ"), (" us ", "US"), ("Německo", "DE")] {
                var client = SearchFixtures.alfa
                client.country = stored

                let model = ClientFormModel(app: f.app, client: client)

                #expect(model.country == shown)
                #expect(model.countryChoices.map(\.code) == Countries.all)
            }
        }
    }

    @Test func aClientWithoutACountryHasADashToChoose() async throws {
        try await ClientsFixture.with { f in
            var client = SearchFixtures.alfa
            client.country = ""

            let model = ClientFormModel(app: f.app, client: client)

            #expect(model.country == "")
            #expect(model.countryChoices.first == CountryChoice(code: "", name: "—"))
        }
    }

    // MARK: Currencies and choices

    @Test func theCurrenciesAreCrownsEurosAndDollarsAndThenTheOnesTheCnbQuotes() {
        let cached: Set<CurrencyCode> = [.usd, .czk, CurrencyCode("GBP")!, CurrencyCode("AUD")!, .eur]

        let choices = ClientFormModel.currencyChoices(cached: cached, including: .czk)

        #expect(choices.map(\.code) == ["CZK", "EUR", "USD", "AUD", "GBP"])
    }

    @Test func aCurrencyTheClientHasIsOfferedEvenWhenNoRateIsStored() {
        let choices = ClientFormModel.currencyChoices(cached: [], including: CurrencyCode("PLN")!)

        #expect(choices.map(\.code) == ["CZK", "EUR", "USD", "PLN"])
        #expect(ClientFormModel.currencyChoices(cached: [], including: .usd).map(\.code) == ["CZK", "EUR", "USD"])
    }

    @Test func theUsualCurrenciesAreNamedInCzechAndTheOthersBySystemName() {
        #expect(ClientFormModel.currencyLabel(.czk) == "CZK – česká koruna")
        #expect(ClientFormModel.currencyLabel(.usd) == "USD – americký dolar")
        #expect(ClientFormModel.currencyLabel(.eur) == "EUR – euro")
        #expect(ClientFormModel.currencyLabel(CurrencyCode("GBP")!) == "GBP – britská libra")
        // A code that no currency has is the code alone.
        #expect(ClientFormModel.currencyLabel(CurrencyCode("QQQ")!) == "QQQ")
    }

    @Test func loadingOffersTheCurrenciesOfTheStoredRates() async throws {
        try await ClientsFixture.with { f in
            let model = ClientFormModel(app: f.app, client: nil)
            #expect(model.currencies.map(\.code) == ["CZK", "EUR", "USD"])
            let pound = CNBRateRow(
                declaredOn: civilDate("2026-10-16"), currency: CurrencyCode("GBP")!, amount: 1, rate: decimal("27.5"))
            try await f.database.insertCNBRates([pound])

            await model.load()

            #expect(model.currencies.map(\.code) == ["CZK", "EUR", "USD", "GBP"])
        }
    }

    @Test func aLoadThatFailsLeavesTheThreeUsualCurrenciesAndTheOneTheClientHas() async throws {
        try await ClientsFixture.with { f in
            try await storeUnreadableRate(in: f.database)
            let blank = ClientFormModel(app: f.app, client: nil)
            var pounds = SearchFixtures.alfa
            pounds.currency = CurrencyCode("GBP")!
            let stored = ClientFormModel(app: f.app, client: pounds)

            await blank.load()
            await stored.load()

            #expect(blank.currencies.map(\.code) == ["CZK", "EUR", "USD"])
            #expect(stored.currencies.map(\.code) == ["CZK", "EUR", "USD", "GBP"])
            // The form still works: a client can be saved without the list of currencies.
            blank.name = "Epsilon"
            try await blank.save()
        }
    }

    @Test func theVATModesAreNamedInTheFormWithTheLongestOneShortened() {
        #expect(
            VatMode.allCases.map(\.formLabel) == [
                "Tuzemsko 21 %", "Tuzemsko 12 %", "Mimo tuzemsko – § 9 odst. 1", "Přenesená povinnost – EU", "Bez DPH",
            ])
    }

    @Test func theLanguagesAreNamedCzechAndEnglish() {
        #expect(ClientFormModel.languageLabel(.cs) == "Čeština")
        #expect(ClientFormModel.languageLabel(.en) == "Angličtina")
    }
}
