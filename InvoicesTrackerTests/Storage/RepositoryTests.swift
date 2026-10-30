import Foundation
import Testing
@testable import InvoicesTracker

/// The repositories for settings, clients, templates, years, uniform rates and logs: what is saved is what is read
/// back, also when the database is opened again; each save is one transaction; and a value that cannot be stored is
/// refused without changing anything. The data is invented.
struct RepositoryTests {
    // MARK: Invented data

    private static func appSettings() -> AppSettings {
        AppSettings(
            appearance: .dark, touchIDUnlock: false, backupFolderBookmark: Data([0x00, 0x01, 0xFE, 0xFF]),
            backupFolderName: "Záloha – externí disk", lastLocalBackup: Date(timeIntervalSince1970: 1_760_000_000),
            lastOffMacBackup: Date(timeIntervalSince1970: 1_760_003_600),
            localBackupPendingSince: Date(timeIntervalSince1970: 1_760_007_200), chartMode: .years, chartWithVAT: true
        )
    }

    /// Every field differs from the default.
    private static func supplier() -> Supplier {
        Supplier(
            name: "Jana Nováková", street: "Květinová 12", postcode: "110 00", city: "Praha 1", country: "SK",
            ico: "00000019", dic: "CZ0000000019", email: "jana@example.com", phone: "+420 777 000 111",
            czechFooter: "Zapsána v testovacím rejstříku."
        )
    }

    private static func bankAccounts() -> [BankAccount] {
        [
            BankAccount(
                currency: .czk, accountNumber: "1234567890/0300", iban: "CZ00 0000 0000 0000 0000 0000",
                bic: "TESTCZPP"
            ),
            BankAccount(
                currency: .usd, accountNumber: "000123456789", routingNumber: "000000000", accountType: "Checking",
                bankNameAndAddress: "Example Bank, 1 Example Street, New York, NY 10001, USA"
            ),
            BankAccount(currency: .eur, iban: "DE00 0000 0000 0000 0000 00", bic: "TESTDEFF"),
        ]
    }

    /// Every field differs from the default, and the name has Czech diacritics.
    private static func client(name: String = "Příbramská strojírna, s.r.o.") -> Client {
        Client(
            name: name, street: "Žižkova 12/3", postcode: "261 01", city: "Příbram – Orlov", country: "SK",
            ico: "12345679", dic: "SK2020123456", email: "účetní@example.com", phone: "+420 601 234 567",
            currency: .eur, vatMode: .euReverseCharge, dueDays: 30, paymentMethod: "Platba kartou", language: .en,
            origin: .imported, editedAfterImport: true
        )
    }

    private static func template(clientID: Int64, name: String = "Měsíční vývoj") -> InvoiceTemplate {
        InvoiceTemplate(
            name: name, clientID: clientID,
            items: [
                TemplateItem(
                    description: "Vývoj {měsíc} {rok}", quantity: decimal("7.5"), unit: "hod", unitPriceMinor: 60_000
                ),
                TemplateItem(
                    description: "Hosting {month} {year}", quantity: decimal("1"), unit: "ks", unitPriceMinor: 125_050
                ),
            ],
            vatMode: .domestic12, dueDays: 30, duzpAtMonthEnd: false, note: "Fakturovat za předchozí měsíc.\nDěkuji"
        )
    }

    /// Every field differs from the default, and the twelve advances of each kind are all different.
    private static func yearSettings(_ year: Int) -> YearSettings {
        YearSettings(
            year: year, expensePercent: 40, reducedSocialBase: true, activityFrom: 3, activityTo: 10,
            secondaryMonths: [4, 5, 9], healthExemptMonths: [3, 11],
            advances: AdvancePlan(
                social: (1...12).map { 3_800 + Int64($0) },
                health: (1...12).map { 2_900 + Int64($0) },
                tax: (1...12).map { $0 % 3 == 0 ? 1_500 + Int64($0) : 0 }
            ),
            deductions: Deductions(
                mortgageInterestPaid: 120_000, mortgageMonths: 9, mortgageCap: .before2021, lifeInsurance: 18_000,
                pensionSavings: 24_000, dip: 48_000, longTermCare: 6_000, gifts: 5_000
            ),
            taxpayerCredit: false, incomeFXMethod: .uniform
        )
    }

    private static func adjustment(_ day: String, _ amount: Int64, _ description: String) -> IncomeAdjustment {
        IncomeAdjustment(date: civilDate(day), amountHalere: amount, description: description)
    }

    private static func child(_ name: String, born day: String, id: Int64? = nil) -> Child {
        Child(id: id, name: name, birthDate: civilDate(day))
    }

    /// A child's year: in the household the whole year and claimed by me unless told otherwise, with no ZTP/P and no
    /// studies.
    private static func childYear(
        order: Int,
        household: MonthRange? = MonthRange(from: 1, to: 12),
        claimant: Claimant = .me,
        ztpp: MonthRange? = nil,
        studies: MonthRange? = nil
    ) -> ChildYear {
        ChildYear(household: household, claimant: claimant, order: order, ztpp: ztpp, studies: studies)
    }

    private static func spouse(months: MonthRange = MonthRange(from: 1, to: 12), ownIncome: Int64 = 0) -> SpouseYear {
        SpouseYear(claim: true, months: months, ownIncomeKc: ownIncome, ztpp: nil)
    }

    private static func uniformRate(
        year: Int, _ currency: CurrencyCode, amount: Int = 1, _ rate: String, origin: UniformRateOrigin = .manual
    ) -> UniformRate {
        UniformRate(
            year: year, currency: currency, amount: amount, rate: decimal(rate), instruction: "GFŘ-D-99",
            origin: origin
        )
    }

    private static func logEntry(_ index: Int, kind: FetchKind = .cnbDaily) -> FetchLogEntry {
        FetchLogEntry(
            at: Date(timeIntervalSince1970: 1_760_000_000 + Double(index) * 60), kind: kind,
            target: "2026-10-\(10 + index)", ok: index % 2 == 0, message: index % 2 == 0 ? "" : "Server neodpovídá."
        )
    }

    // MARK: App settings, supplier and bank accounts

    @Test func appSettingsAreTheDefaultsUntilTheyAreSaved() async throws {
        let (database, directory) = try makeDatabase()
        defer { removeTemporaryDirectory(directory) }

        #expect(try await database.appSettings() == AppSettings())
    }

    @Test func appSettingsRoundTripAndTheLastSaveWins() async throws {
        let (database, directory) = try makeDatabase()
        defer { removeTemporaryDirectory(directory) }

        try await database.saveAppSettings(Self.appSettings())
        #expect(try await database.appSettings() == Self.appSettings())

        let changed = AppSettings(appearance: .light, chartMode: .months)
        try await database.saveAppSettings(changed)
        #expect(try await database.appSettings() == changed)
        // One row holds the settings under the key `app`.
        #expect(try await database.integer("SELECT count(*) FROM app_settings") == 1)
        #expect(try await database.integer("SELECT count(*) FROM app_settings WHERE key = 'app'") == 1)
    }

    @Test func anUpdateOfTheSettingsChangesWhatItTouchesAndKeepsTheRestInOneWrite() async throws {
        let (database, directory) = try makeDatabase()
        defer { removeTemporaryDirectory(directory) }

        // Before anything is saved, the change applies to the defaults.
        let first = try await database.updateAppSettings { $0.chartWithVAT = true }
        #expect(first == AppSettings(chartWithVAT: true))
        try await database.saveAppSettings(Self.appSettings())
        let writes = await database.writeCount

        let updated = try await database.updateAppSettings { $0.touchIDUnlock = true }

        var expected = Self.appSettings()
        expected.touchIDUnlock = true
        #expect(updated == expected)
        #expect(try await database.appSettings() == expected)
        #expect(await database.writeCount == writes + 1)
    }

    @Test func aSettingsRowWithoutSomeFieldsStillReads() async throws {
        let (database, directory) = try makeDatabase()
        defer { removeTemporaryDirectory(directory) }
        try await database.write {
            try $0.run("INSERT INTO app_settings(key, value) VALUES ('app', ?)", [.text(#"{"appearance":"dark"}"#)])
        }

        #expect(try await database.appSettings() == AppSettings(appearance: .dark))
    }

    @Test func theSupplierIsTheDefaultUntilItIsSaved() async throws {
        let (database, directory) = try makeDatabase()
        defer { removeTemporaryDirectory(directory) }

        #expect(try await database.supplier() == Supplier())
    }

    @Test func theSupplierRoundTripsAndOnlyOneRowIsKept() async throws {
        let (database, directory) = try makeDatabase()
        defer { removeTemporaryDirectory(directory) }

        try await database.saveSupplier(Self.supplier())
        #expect(try await database.supplier() == Self.supplier())

        var changed = Self.supplier()
        changed.name = "Jan Novák"
        changed.czechFooter = ""
        try await database.saveSupplier(changed)
        #expect(try await database.supplier() == changed)
        #expect(try await database.integer("SELECT count(*) FROM supplier") == 1)
    }

    @Test func bankAccountsForCrownsDollarsAndEurosRoundTripInTheOrderGiven() async throws {
        let (database, directory) = try makeDatabase()
        defer { removeTemporaryDirectory(directory) }
        #expect(try await database.bankAccounts().isEmpty)

        try await database.saveBankAccounts(Self.bankAccounts())

        #expect(try await database.bankAccounts() == Self.bankAccounts())
    }

    @Test func savingBankAccountsReplacesAllOfThem() async throws {
        let (database, directory) = try makeDatabase()
        defer { removeTemporaryDirectory(directory) }
        try await database.saveBankAccounts(Self.bankAccounts())

        let usdOnly = [Self.bankAccounts()[1]]
        try await database.saveBankAccounts(usdOnly)
        #expect(try await database.bankAccounts() == usdOnly)

        try await database.saveBankAccounts([])
        #expect(try await database.bankAccounts().isEmpty)
    }

    @Test func twoAccountsForOneCurrencyAreRefusedAndTheOldOnesStay() async throws {
        let (database, directory) = try makeDatabase()
        defer { removeTemporaryDirectory(directory) }
        try await database.saveBankAccounts(Self.bankAccounts())

        let twice = [Self.bankAccounts()[0], Self.bankAccounts()[0]]
        await #expect { try await database.saveBankAccounts(twice) } throws: { isConstraintViolation($0) }

        #expect(try await database.bankAccounts() == Self.bankAccounts())
    }

    @Test func anUpdateOfTheSupplierChangesWhatItTouchesInOneWrite() async throws {
        let (database, directory) = try makeDatabase()
        defer { removeTemporaryDirectory(directory) }
        try await database.saveSupplier(Self.supplier())
        try await database.saveBankAccounts(Self.bankAccounts())
        let writes = await database.writeCount

        let saved = try await database.updateSupplierDetails { supplier, accounts in
            supplier.city = "Brno"
            accounts.removeAll { $0.currency == .eur }
        }

        var expectedSupplier = Self.supplier()
        expectedSupplier.city = "Brno"
        let expectedAccounts = Array(Self.bankAccounts().prefix(2))
        #expect(saved.supplier == expectedSupplier)
        #expect(saved.accounts == expectedAccounts)
        #expect(try await database.supplier() == expectedSupplier)
        #expect(try await database.bankAccounts() == expectedAccounts)
        #expect(await database.writeCount == writes + 1)
    }

    @Test func anUpdateOfTheSupplierWithTwoAccountsForOneCurrencyChangesNothing() async throws {
        let (database, directory) = try makeDatabase()
        defer { removeTemporaryDirectory(directory) }
        try await database.saveSupplier(Self.supplier())
        try await database.saveBankAccounts(Self.bankAccounts())

        await #expect {
            try await database.updateSupplierDetails { supplier, accounts in
                supplier.name = "Jan Novák"
                accounts.append(BankAccount(currency: .czk, accountNumber: "1/0100"))
            }
        } throws: {
            isConstraintViolation($0)
        }

        #expect(try await database.supplier() == Self.supplier())
        #expect(try await database.bankAccounts() == Self.bankAccounts())
    }

    // MARK: Clients

    @Test func aClientWithDiacriticsAndEveryFieldSetRoundTrips() async throws {
        let (database, directory) = try makeDatabase()
        defer { removeTemporaryDirectory(directory) }
        let client = Self.client()

        let id = try await database.saveClient(client)

        #expect(id == 1)
        var expected = client
        expected.id = id
        #expect(try await database.client(id: id) == expected)
        #expect(try await database.clients() == [expected])
    }

    @Test func eachNewClientGetsItsOwnId() async throws {
        let (database, directory) = try makeDatabase()
        defer { removeTemporaryDirectory(directory) }

        let first = try await database.saveClient(Self.client(name: "Alfa"))
        let second = try await database.saveClient(Self.client(name: "Beta"))

        #expect(first == 1)
        #expect(second == 2)
        #expect(try await database.clients().map(\.id) == [1, 2])
    }

    @Test func aClientThatDoesNotExistIsNil() async throws {
        let (database, directory) = try makeDatabase()
        defer { removeTemporaryDirectory(directory) }
        try await database.saveClient(Self.client())

        #expect(try await database.client(id: 99) == nil)
        #expect(try await database.client(id: 0) == nil)
    }

    @Test func savingAnExistingClientUpdatesItInPlace() async throws {
        let (database, directory) = try makeDatabase()
        defer { removeTemporaryDirectory(directory) }
        var client = Self.client()
        client.id = try await database.saveClient(client)

        client.name = "Příbramská strojírna a.s."
        client.dueDays = 7
        client.language = .cs
        client.editedAfterImport = false
        let id = try await database.saveClient(client)

        #expect(id == client.id)
        #expect(try await database.clients() == [client])
    }

    /// Replacing the row would delete it, and with it the client's templates (`ON DELETE CASCADE`) and the link of
    /// its invoices (`ON DELETE SET NULL`).
    @Test func editingAClientKeepsItsTemplatesAndTheLinkOfItsInvoices() async throws {
        let (database, directory) = try makeDatabase()
        defer { removeTemporaryDirectory(directory) }
        var client = Self.client()
        client.id = try await database.saveClient(client)
        try await database.saveTemplate(Self.template(clientID: client.id))
        try await database.write { try SchemaRows.invoice($0, id: 10, digits: "20260901", clientID: client.id) }

        client.name = "Přejmenovaný odběratel"
        try await database.saveClient(client)

        #expect(try await database.templates().count == 1)
        #expect(try await database.integer("SELECT count(*) FROM invoice WHERE id = 10 AND client_id = 1") == 1)
    }

    @Test func clientsAreSortedByTheirNamesWithCaseAndDiacriticsIgnored() async throws {
        let (database, directory) = try makeDatabase()
        defer { removeTemporaryDirectory(directory) }
        for name in ["Zeta", "Ťuk", "Alfa"] {
            try await database.saveClient(Self.client(name: name))
        }

        #expect(try await database.clients().map(\.name) == ["Alfa", "Ťuk", "Zeta"])
    }

    @Test func foldingPlacesAccentedAndLowercaseNamesWithTheirPlainLetters() async throws {
        let (database, directory) = try makeDatabase()
        defer { removeTemporaryDirectory(directory) }
        for name in ["cyril s.r.o.", "Černý", "Zeman", "Čech", "ábel", "Adam", "Řehoř"] {
            try await database.saveClient(Self.client(name: name))
        }

        // Compared as "abel", "adam", "cech", "cerny", "cyril", "rehor", "zeman". A plain comparison would put
        // "Čech", "Černý" and "Řehoř" after "Zeman" and "ábel" after "cyril s.r.o.".
        let names = try await database.clients().map(\.name)
        #expect(names == ["ábel", "Adam", "Čech", "Černý", "cyril s.r.o.", "Řehoř", "Zeman"])
    }

    @Test func clientsWithTheSameFoldedNameKeepAFixedOrder() async throws {
        let (database, directory) = try makeDatabase()
        defer { removeTemporaryDirectory(directory) }
        // The same name once with and once without diacritics, and twice exactly alike.
        for name in ["Čech", "Cech", "Cech", "Alfa"] {
            try await database.saveClient(Self.client(name: name))
        }

        let clients = try await database.clients()
        #expect(clients.map(\.name) == ["Alfa", "Cech", "Cech", "Čech"])
        #expect(clients.map(\.id) == [4, 2, 3, 1])
    }

    @Test func aStoredClientWithAnUnknownVatModeThrowsInsteadOfStoppingTheApp() async throws {
        let (database, directory) = try makeDatabase()
        defer { removeTemporaryDirectory(directory) }
        try await database.write { c in
            try SchemaRows.client(c, id: 1)
            try c.run("UPDATE client SET vat_mode = 'reverseish' WHERE id = 1")
        }

        await #expect(throws: StoredValueError.self) { _ = try await database.clients() }
        await #expect(throws: StoredValueError.self) { _ = try await database.client(id: 1) }
    }

    // MARK: Templates

    @Test func aTemplateWithTwoItemsAndAFractionalQuantityRoundTrips() async throws {
        let (database, directory) = try makeDatabase()
        defer { removeTemporaryDirectory(directory) }
        let clientID = try await database.saveClient(Self.client())
        let template = Self.template(clientID: clientID)

        let id = try await database.saveTemplate(template)

        var expected = template
        expected.id = id
        #expect(id == 1)
        #expect(try await database.templates() == [expected])
        #expect(try await database.templates()[0].items[0].quantity == decimal("7.5"))
    }

    @Test func savingATemplateAgainReplacesItsItemsAndKeepsItsId() async throws {
        let (database, directory) = try makeDatabase()
        defer { removeTemporaryDirectory(directory) }
        let clientID = try await database.saveClient(Self.client())
        var template = Self.template(clientID: clientID)
        template.id = try await database.saveTemplate(template)

        template.name = "Roční licence"
        template.vatMode = .none
        template.dueDays = 14
        template.duzpAtMonthEnd = true
        template.note = ""
        template.items = [
            TemplateItem(description: "Licence", quantity: decimal("12"), unit: "měs", unitPriceMinor: 99_900)
        ]
        let id = try await database.saveTemplate(template)

        #expect(id == template.id)
        #expect(try await database.templates() == [template])
        #expect(try await database.integer("SELECT count(*) FROM template_item") == 1)
    }

    @Test func aTemplateKeepsItsItemsInTheOrderGiven() async throws {
        let (database, directory) = try makeDatabase()
        defer { removeTemporaryDirectory(directory) }
        let clientID = try await database.saveClient(Self.client())
        var template = Self.template(clientID: clientID)
        template.items = (0..<12).reversed().map { index in
            TemplateItem(description: "Položka \(index)", quantity: decimal("1"), unit: "ks", unitPriceMinor: 100)
        }

        template.id = try await database.saveTemplate(template)

        #expect(try await database.templates() == [template])
        #expect(try await database.templates()[0].items.first?.description == "Položka 11")
    }

    @Test func aTemplateCanHaveNoItems() async throws {
        let (database, directory) = try makeDatabase()
        defer { removeTemporaryDirectory(directory) }
        let clientID = try await database.saveClient(Self.client())
        var template = Self.template(clientID: clientID)
        template.items = []

        template.id = try await database.saveTemplate(template)

        #expect(try await database.templates() == [template])
    }

    @Test func templatesComeInTheOrderTheyWereCreated() async throws {
        let (database, directory) = try makeDatabase()
        defer { removeTemporaryDirectory(directory) }
        let alfa = try await database.saveClient(Self.client(name: "Alfa"))
        let beta = try await database.saveClient(Self.client(name: "Beta"))
        try await database.saveTemplate(Self.template(clientID: beta, name: "Zálohy"))
        try await database.saveTemplate(Self.template(clientID: alfa, name: "Audit"))
        try await database.saveTemplate(Self.template(clientID: beta, name: "Údržba"))

        #expect(try await database.templates().map(\.name) == ["Zálohy", "Audit", "Údržba"])
    }

    @Test func deletingATemplateDeletesItsItemsAndOnlyThem() async throws {
        let (database, directory) = try makeDatabase()
        defer { removeTemporaryDirectory(directory) }
        let clientID = try await database.saveClient(Self.client())
        let first = try await database.saveTemplate(Self.template(clientID: clientID, name: "První"))
        let second = try await database.saveTemplate(Self.template(clientID: clientID, name: "Druhá"))

        try await database.deleteTemplate(id: first)

        #expect(try await database.templates().map(\.id) == [second])
        #expect(try await database.integer("SELECT count(*) FROM template_item") == 2)
        let itemsOfFirst = try await database.integer(
            "SELECT count(*) FROM template_item WHERE template_id = ?", [.integer(first)])
        #expect(itemsOfFirst == 0)
        // A template that is not there is not an error.
        try await database.deleteTemplate(id: first)
        try await database.deleteTemplate(id: 99)
        #expect(try await database.templates().map(\.id) == [second])
    }

    @Test func aTemplateOfAClientThatDoesNotExistIsRefusedAndLeavesNothingBehind() async throws {
        let (database, directory) = try makeDatabase()
        defer { removeTemporaryDirectory(directory) }

        await #expect { try await database.saveTemplate(Self.template(clientID: 99)) } throws: {
            isConstraintViolation($0)
        }

        #expect(try await database.integer("SELECT count(*) FROM template") == 0)
        #expect(try await database.integer("SELECT count(*) FROM template_item") == 0)
    }

    @Test func aTemplateEditedToAnUnknownClientKeepsItsOldContents() async throws {
        let (database, directory) = try makeDatabase()
        defer { removeTemporaryDirectory(directory) }
        let clientID = try await database.saveClient(Self.client())
        var template = Self.template(clientID: clientID)
        template.id = try await database.saveTemplate(template)

        var broken = template
        broken.clientID = 99
        broken.items = []
        await #expect { try await database.saveTemplate(broken) } throws: { isConstraintViolation($0) }

        // The items were not deleted before the update failed.
        #expect(try await database.templates() == [template])
    }

    // MARK: Year settings

    @Test func yearSettingsWithEveryFieldChangedRoundTrip() async throws {
        let (database, directory) = try makeDatabase()
        defer { removeTemporaryDirectory(directory) }
        let settings = Self.yearSettings(2026)

        try await database.saveYearSettings(settings)

        #expect(try await database.yearSettings(2026) == settings)
        #expect(try await database.storedSettingsYears() == [2026])
    }

    @Test func savingYearSettingsAgainReplacesThemWithTheirAdvancesAndDeductions() async throws {
        let (database, directory) = try makeDatabase()
        defer { removeTemporaryDirectory(directory) }
        try await database.saveYearSettings(Self.yearSettings(2026))

        var changed = YearSettings(year: 2026)
        changed.expensePercent = 80
        changed.advances.social[0] = 4_000
        changed.advances.tax[11] = 7_000
        try await database.saveYearSettings(changed)

        #expect(try await database.yearSettings(2026) == changed)
        // A row for each of the twelve months, and one for the deductions.
        #expect(try await database.integer("SELECT count(*) FROM year_settings") == 1)
        #expect(try await database.integer("SELECT count(*) FROM advance_month WHERE year = 2026") == 12)
        #expect(try await database.integer("SELECT count(*) FROM deduction WHERE year = 2026") == 1)
    }

    @Test func anActivityThatEndsBeforeItStartsIsRefusedAndNothingChanges() async throws {
        let (database, directory) = try makeDatabase()
        defer { removeTemporaryDirectory(directory) }
        try await database.saveYearSettings(Self.yearSettings(2026))
        var backwards = Self.yearSettings(2026)
        backwards.activityFrom = 8
        backwards.activityTo = 4

        await #expect { try await database.saveYearSettings(backwards) } throws: { isConstraintViolation($0) }
        await #expect {
            try await database.updateYearSettings(2026) { settings in
                settings.activityFrom = 8
                settings.activityTo = 4
            }
        } throws: {
            isConstraintViolation($0)
        }

        #expect(try await database.yearSettings(2026) == Self.yearSettings(2026))
    }

    @Test func yearSettingsOfDifferentYearsDoNotMix() async throws {
        let (database, directory) = try makeDatabase()
        defer { removeTemporaryDirectory(directory) }
        var other = Self.yearSettings(2025)
        other.expensePercent = 60
        other.advances.social[0] = 1
        other.deductions.gifts = 1
        try await database.saveYearSettings(other)
        try await database.saveYearSettings(Self.yearSettings(2026))

        #expect(try await database.yearSettings(2025) == other)
        #expect(try await database.yearSettings(2026) == Self.yearSettings(2026))
    }

    @Test func yearSettingsOfAYearWithNothingStoredAreTheDefaults() async throws {
        let (database, directory) = try makeDatabase()
        defer { removeTemporaryDirectory(directory) }

        let settings = try await database.yearSettings(2026)

        #expect(settings == YearSettings(year: 2026))
        #expect(settings.expensePercent == 60)
        #expect(settings.advances == AdvancePlan.empty)
        // Reading a default stores nothing.
        #expect(try await database.storedSettingsYears().isEmpty)
    }

    @Test func aNewYearTakesTheChoicesOfTheEarlierYearButStartsWithEmptyAdvancesAndDeductions() async throws {
        let (database, directory) = try makeDatabase()
        defer { removeTemporaryDirectory(directory) }
        try await database.saveYearSettings(Self.yearSettings(2025))

        let settings = try await database.yearSettings(2026)

        // Copied: the expense rate, the reduced social base, the taxpayer credit and the method.
        #expect(settings.year == 2026)
        #expect(settings.expensePercent == 40)
        #expect(settings.reducedSocialBase)
        #expect(!settings.taxpayerCredit)
        #expect(settings.incomeFXMethod == .uniform)
        // Not copied.
        #expect(settings.advances == AdvancePlan.empty)
        #expect(settings.deductions == Deductions())
        #expect(settings.activityFrom == 1)
        #expect(settings.activityTo == 12)
        #expect(settings.secondaryMonths.isEmpty)
        #expect(settings.healthExemptMonths.isEmpty)
        // Still only the year that was saved.
        #expect(try await database.storedSettingsYears() == [2025])
    }

    @Test func aNewYearTakesTheChoicesOfTheNearestEarlierYearAndNeverOfALaterOne() async throws {
        let (database, directory) = try makeDatabase()
        defer { removeTemporaryDirectory(directory) }
        var y2023 = YearSettings(year: 2023)
        y2023.expensePercent = 80
        var y2025 = YearSettings(year: 2025)
        y2025.expensePercent = 30
        var y2027 = YearSettings(year: 2027)
        y2027.expensePercent = 40
        for settings in [y2027, y2023, y2025] {
            try await database.saveYearSettings(settings)
        }

        #expect(try await database.yearSettings(2026).expensePercent == 30)
        #expect(try await database.yearSettings(2024).expensePercent == 80)
        #expect(try await database.yearSettings(2028).expensePercent == 40)
        // Nothing before 2023 is stored, and the later years are not copied backwards.
        #expect(try await database.yearSettings(2022) == YearSettings(year: 2022))
        // A stored year is its own row, whatever lies around it.
        #expect(try await database.yearSettings(2025) == y2025)
    }

    @Test func storedSettingsYearsAreListedOldestFirst() async throws {
        let (database, directory) = try makeDatabase()
        defer { removeTemporaryDirectory(directory) }
        #expect(try await database.storedSettingsYears().isEmpty)

        for year in [2026, 2022, 2025] {
            try await database.saveYearSettings(YearSettings(year: year))
        }

        #expect(try await database.storedSettingsYears() == [2022, 2025, 2026])
    }

    @Test func monthsAreStoredAsAscendingCommaSeparatedText() async throws {
        let (database, directory) = try makeDatabase()
        defer { removeTemporaryDirectory(directory) }
        var settings = YearSettings(year: 2026)
        settings.secondaryMonths = [12, 11]
        settings.healthExemptMonths = []
        try await database.saveYearSettings(settings)

        let rows = try await database.read { connection in
            try connection.query("SELECT secondary_months, health_exempt_months FROM year_settings WHERE year = 2026")
        }

        #expect(rows.map { $0.text(0) } == ["11,12"])
        #expect(rows.map { $0.text(1) } == [""])
    }

    @Test func yearSettingsTheEngineWouldRefuseAreRefusedAndTheStoredOnesStay() async throws {
        let (database, directory) = try makeDatabase()
        defer { removeTemporaryDirectory(directory) }
        let stored = Self.yearSettings(2026)
        try await database.saveYearSettings(stored)

        var badExpense = stored
        badExpense.expensePercent = 50
        var badActivity = stored
        badActivity.activityFrom = 0
        var negativeAdvance = stored
        negativeAdvance.advances.health[5] = -1
        var negativeDeduction = stored
        negativeDeduction.deductions.gifts = -1
        var tooManyMortgageMonths = stored
        tooManyMortgageMonths.deductions.mortgageMonths = 13
        var shortAdvances = stored
        shortAdvances.advances.tax.removeLast()
        var secondaryMonthOutOfRange = stored
        secondaryMonthOutOfRange.secondaryMonths = [4, 13]
        var exemptMonthOutOfRange = stored
        exemptMonthOutOfRange.healthExemptMonths = [0]

        let refused = [
            badExpense, badActivity, negativeAdvance, negativeDeduction, tooManyMortgageMonths, shortAdvances,
            secondaryMonthOutOfRange, exemptMonthOutOfRange,
        ]
        for (index, settings) in refused.enumerated() {
            await #expect(throws: SQLiteError.self, "case \(index)") {
                try await database.saveYearSettings(settings)
            }
        }

        #expect(try await database.yearSettings(2026) == stored)
        #expect(try await database.integer("SELECT count(*) FROM advance_month") == 12)
    }

    @Test func aRefusedNewYearLeavesNoRowsBehind() async throws {
        let (database, directory) = try makeDatabase()
        defer { removeTemporaryDirectory(directory) }
        var settings = YearSettings(year: 2026)
        settings.advances.social[11] = -5

        await #expect { try await database.saveYearSettings(settings) } throws: { isConstraintViolation($0) }

        #expect(try await database.storedSettingsYears().isEmpty)
        #expect(try await database.integer("SELECT count(*) FROM advance_month") == 0)
        #expect(try await database.integer("SELECT count(*) FROM deduction") == 0)
    }

    @Test func anUpdateOfAYearChangesWhatItTouchesAndKeepsTheRestInOneWrite() async throws {
        let (database, directory) = try makeDatabase()
        defer { removeTemporaryDirectory(directory) }
        let stored = Self.yearSettings(2026)
        try await database.saveYearSettings(stored)
        let writesBefore = await database.writeCount

        let updated = try await database.updateYearSettings(2026) { settings in
            settings.advances.social[2] = 9_999
            settings.deductions.gifts = 0
            settings.secondaryMonths.insert(8)
        }

        var expected = stored
        expected.advances.social[2] = 9_999
        expected.deductions.gifts = 0
        expected.secondaryMonths.insert(8)
        #expect(updated == expected)
        #expect(try await database.yearSettings(2026) == expected)
        #expect(await database.writeCount == writesBefore + 1)
    }

    @Test func anUpdateOfAYearWithNothingStoredStartsFromTheChoicesOfTheEarlierYear() async throws {
        let (database, directory) = try makeDatabase()
        defer { removeTemporaryDirectory(directory) }
        try await database.saveYearSettings(Self.yearSettings(2025))

        try await database.updateYearSettings(2026) { settings in
            settings.advances.health[0] = 4_321
        }

        // The choices of 2025 (40 %, the reduced base, no credit, the uniform rate) are those of 2026 now, and its
        // advances and deductions are not.
        var expected = YearSettings(year: 2026)
        expected.expensePercent = 40
        expected.reducedSocialBase = true
        expected.taxpayerCredit = false
        expected.incomeFXMethod = .uniform
        expected.advances.health[0] = 4_321
        #expect(try await database.yearSettings(2026) == expected)
        #expect(try await database.storedSettingsYears() == [2025, 2026])
    }

    @Test func anUpdateTheEngineWouldRefuseIsRefusedAndTheStoredYearStays() async throws {
        let (database, directory) = try makeDatabase()
        defer { removeTemporaryDirectory(directory) }
        let stored = Self.yearSettings(2026)
        try await database.saveYearSettings(stored)
        let writesBefore = await database.writeCount

        await #expect { try await database.updateYearSettings(2026) { $0.expensePercent = 55 } } throws: {
            isConstraintViolation($0)
        }
        await #expect { try await database.updateYearSettings(2026) { $0.advances.social[0] = -1 } } throws: {
            isConstraintViolation($0)
        }
        await #expect { try await database.updateYearSettings(2026) { $0.advances.tax.removeLast() } } throws: {
            isConstraintViolation($0)
        }
        await #expect { try await database.updateYearSettings(2026) { $0.secondaryMonths = [13] } } throws: {
            isConstraintViolation($0)
        }
        await #expect { try await database.updateYearSettings(2026) { $0.deductions.mortgageMonths = 13 } } throws: {
            isConstraintViolation($0)
        }

        #expect(try await database.yearSettings(2026) == stored)
        #expect(await database.writeCount == writesBefore)
    }

    @Test func anUpdateStaysInTheYearItWasAskedFor() async throws {
        let (database, directory) = try makeDatabase()
        defer { removeTemporaryDirectory(directory) }
        try await database.saveYearSettings(Self.yearSettings(2026))

        let updated = try await database.updateYearSettings(2026) { settings in
            settings.year = 2030
            settings.expensePercent = 80
        }

        #expect(updated.year == 2026)
        #expect(updated.expensePercent == 80)
        #expect(try await database.storedSettingsYears() == [2026])
    }

    // MARK: The family

    @Test func aChildIsSavedAndReadBack() async throws {
        let (database, directory) = try makeDatabase()
        defer { removeTemporaryDirectory(directory) }
        let childYear = Self.childYear(
            order: 2, household: MonthRange(from: 2, to: 11), claimant: .otherParent, ztpp: MonthRange(from: 3, to: 12),
            studies: MonthRange(from: 9, to: 12)
        )

        let id = try await database.saveChild(Self.child("Anna", born: "2019-09-03"), year: 2026, childYear: childYear)

        let saved = Self.child("Anna", born: "2019-09-03", id: id)
        #expect(
            try await database.family(year: 2026).children
                == [FamilyChild(child: saved, year: childYear, isStored: true)]
        )
        // Saving the child with its id again changes it in place, and the row of the year with it.
        let renamed = Self.child("Anička", born: "2019-09-30", id: id)
        let changed = Self.childYear(order: 1, household: nil)
        #expect(try await database.saveChild(renamed, year: 2026, childYear: changed) == id)
        #expect(
            try await database.family(year: 2026).children
                == [FamilyChild(child: renamed, year: changed, isStored: true)]
        )
        #expect(try await database.integer("SELECT count(*) FROM child") == 1)
        #expect(try await database.integer("SELECT count(*) FROM child_year") == 1)
        // A new child gets an id of its own.
        let second = try await database.saveChild(
            Self.child("Tomáš", born: "2024-04-12"), year: 2026, childYear: Self.childYear(order: 2)
        )
        #expect(second != id)
    }

    @Test func removingAChildRemovesItFromEveryYear() async throws {
        let (database, directory) = try makeDatabase()
        defer { removeTemporaryDirectory(directory) }
        let anna = try await database.saveChild(
            Self.child("Anna", born: "2019-09-03"), year: 2025, childYear: Self.childYear(order: 1)
        )
        try await database.saveChild(
            Self.child("Anna", born: "2019-09-03", id: anna), year: 2026, childYear: Self.childYear(order: 2)
        )
        let tomas = try await database.saveChild(
            Self.child("Tomáš", born: "2024-04-12"), year: 2026, childYear: Self.childYear(order: 1)
        )

        try await database.removeChild(id: anna)

        // Gone from the years that had a row for her, from those that took one, and from the years before.
        for year in [2020, 2025, 2026, 2027] {
            let expected: [Int64?] = year >= 2024 ? [tomas] : []
            #expect(try await database.family(year: year).children.map(\.child.id) == expected, "\(year)")
        }
        #expect(try await database.integer("SELECT count(*) FROM child_year WHERE child_id = ?", [.integer(anna)]) == 0)
        #expect(try await database.family(year: 2026).children.map(\.year) == [Self.childYear(order: 1)])
        // The years stay, and removing a child that is not there is not an error.
        #expect(try await database.storedSettingsYears() == [2025, 2026])
        try await database.removeChild(id: anna)
    }

    @Test func aSpouseYearIsSavedAndReadBack() async throws {
        let (database, directory) = try makeDatabase()
        defer { removeTemporaryDirectory(directory) }
        try await database.saveYearSettings(Self.yearSettings(2026))
        let spouse = SpouseYear(
            claim: true, months: MonthRange(from: 5, to: 12), ownIncomeKc: 67_999, ztpp: MonthRange(from: 6, to: 9)
        )

        try await database.saveSpouse(spouse, year: 2026)

        // The rest of the year's settings stay as they were.
        var expected = Self.yearSettings(2026)
        expected.spouse = spouse
        #expect(try await database.yearSettings(2026) == expected)
        #expect(try await database.family(year: 2026).spouse == spouse)
        // A spouse who is not claimed keeps what was entered.
        let unclaimed = SpouseYear(claim: false, months: MonthRange(from: 1, to: 12), ownIncomeKc: 120_000, ztpp: nil)
        try await database.saveSpouse(unclaimed, year: 2026)
        #expect(try await database.family(year: 2026).spouse == unclaimed)
        // Other changes of the year keep the spouse.
        try await database.updateYearSettings(2026) { $0.expensePercent = 80 }
        #expect(try await database.yearSettings(2026).spouse == unclaimed)
        // No spouse is stored as none.
        try await database.saveSpouse(nil, year: 2026)
        var withoutSpouse = Self.yearSettings(2026)
        withoutSpouse.expensePercent = 80
        #expect(try await database.yearSettings(2026) == withoutSpouse)
        #expect(try await database.family(year: 2026).spouse == nil)
    }

    @Test func aNewYearHasNoSpouse() async throws {
        let (database, directory) = try makeDatabase()
        defer { removeTemporaryDirectory(directory) }
        try await database.saveSpouse(Self.spouse(), year: 2025)

        #expect(try await database.yearSettings(2026).spouse == nil)
        #expect(try await database.family(year: 2026).spouse == nil)
        // Nor once the year is stored for a child of it.
        try await database.saveChild(
            Self.child("Anna", born: "2019-09-03"), year: 2026, childYear: Self.childYear(order: 1)
        )
        #expect(try await database.storedSettingsYears() == [2025, 2026])
        #expect(try await database.yearSettings(2026).spouse == nil)
        #expect(try await database.family(year: 2026).spouse == nil)
        #expect(try await database.family(year: 2025).spouse == Self.spouse())
    }

    @Test func familyListsOnlyChildrenBornByTheEndOfTheYear() async throws {
        let (database, directory) = try makeDatabase()
        defer { removeTemporaryDirectory(directory) }
        // Saved youngest first, each with a row of 2027 only.
        let children = [
            ("Ema", "2027-01-01"), ("Silvie", "2026-12-31"), ("Tomáš", "2024-04-12"), ("Anna", "2019-09-03"),
        ]
        var ids: [String: Int64] = [:]
        for (name, day) in children {
            ids[name] = try await database.saveChild(
                Self.child(name, born: day), year: 2027, childYear: Self.childYear(order: 1)
            )
        }

        func names(_ year: Int) async throws -> [String] {
            try await database.family(year: year).children.map(\.child.name)
        }

        // Oldest first, from the year of birth on.
        #expect(try await names(2026) == ["Anna", "Tomáš", "Silvie"])
        #expect(try await names(2027) == ["Anna", "Tomáš", "Silvie", "Ema"])
        #expect(try await names(2024) == ["Anna", "Tomáš"])
        #expect(try await names(2023) == ["Anna"])
        #expect(try await names(2019) == ["Anna"])
        #expect(try await names(2018) == [])
        #expect(
            try await database.family(year: 2026).children.map(\.child.id) == [ids["Anna"], ids["Tomáš"], ids["Silvie"]]
        )
    }

    /// A year without a row of its own for a child shows what the nearest earlier year said, read for a new year; with
    /// no earlier row, the defaults, ordered by the date of birth.
    @Test func aYearWithoutItsOwnRowsResolvesTheChildrenFromEarlierYearsOrTheDefaults() async throws {
        let (database, directory) = try makeDatabase()
        defer { removeTemporaryDirectory(directory) }
        // Tomáš is saved first and put first in 2026; Anna is older.
        let tomas = try await database.saveChild(
            Self.child("Tomáš", born: "2024-04-12"), year: 2026, childYear: Self.childYear(order: 1)
        )
        let annaIn2026 = Self.childYear(
            order: 2, household: MonthRange(from: 1, to: 6), claimant: .otherParent, ztpp: MonthRange(from: 3, to: 12),
            studies: MonthRange(from: 1, to: 6)
        )
        let anna = try await database.saveChild(
            Self.child("Anna", born: "2019-09-03"), year: 2026, childYear: annaIn2026
        )
        let annaChild = Self.child("Anna", born: "2019-09-03", id: anna)
        let tomasChild = Self.child("Tomáš", born: "2024-04-12", id: tomas)

        // Before 2026 neither has a row: the defaults, with the order by the date of birth, oldest first.
        #expect(
            try await database.family(year: 2025).children == [
                FamilyChild(child: annaChild, year: Self.childYear(order: 1), isStored: false),
                FamilyChild(child: tomasChild, year: Self.childYear(order: 2), isStored: false),
            ]
        )
        #expect(
            try await database.family(year: 2024).children == [
                FamilyChild(child: annaChild, year: Self.childYear(order: 1), isStored: false),
                FamilyChild(
                    child: tomasChild, year: Self.childYear(order: 2, household: MonthRange(from: 4, to: 12)),
                    isStored: false
                ),
            ]
        )
        // 2026 has their rows.
        #expect(
            try await database.family(year: 2026).children == [
                FamilyChild(child: annaChild, year: annaIn2026, isStored: true),
                FamilyChild(child: tomasChild, year: Self.childYear(order: 1), isStored: true),
            ]
        )
        // 2027 takes them from 2026: Anna left the household in June, her ZTP/P goes on, her studies ended.
        #expect(
            try await database.family(year: 2027).children == [
                FamilyChild(
                    child: annaChild,
                    year: Self.childYear(
                        order: 2, household: nil, claimant: .otherParent, ztpp: MonthRange(from: 1, to: 12)
                    ),
                    isStored: false
                ),
                FamilyChild(child: tomasChild, year: Self.childYear(order: 1), isStored: false),
            ]
        )
        // Reading stores nothing.
        #expect(try await database.storedSettingsYears() == [2026])
        #expect(try await database.integer("SELECT count(*) FROM child_year") == 2)
    }

    /// Saving a child's year or the spouse in a year without settings of its own stores the settings the year had
    /// from the nearest earlier year, the conversion of its income included, so nothing the year shows changes: not
    /// for that year, and not for the years after it that take their settings from it.
    @Test func theFamilyOfAYearWithoutSettingsStoresTheSettingsTheYearTook() async throws {
        let (database, directory) = try makeDatabase()
        defer { removeTemporaryDirectory(directory) }
        try await database.saveYearSettings(Self.yearSettings(2025))
        var took: [Int: YearSettings] = [:]
        for year in 2026...2029 {
            took[year] = try await database.yearSettings(year)
        }
        #expect(took[2026]?.incomeFXMethod == .uniform)

        let anna = try await database.saveChild(
            Self.child("Anna", born: "2019-09-03"), year: 2026, childYear: Self.childYear(order: 1)
        )
        try await database.saveSpouse(Self.spouse(), year: 2027)
        try await database.setChildOrders(year: 2028, orders: [anna: 2])

        #expect(try await database.storedSettingsYears() == [2025, 2026, 2027, 2028])
        var expected = took
        expected[2027]?.spouse = Self.spouse()
        for year in 2026...2029 {
            #expect(try await database.yearSettings(year) == expected[year], "\(year)")
        }
    }

    @Test func settingTheOrdersStoresEachChildsYearWithItsNewOrder() async throws {
        let (database, directory) = try makeDatabase()
        defer { removeTemporaryDirectory(directory) }
        let annaIn2025 = Self.childYear(order: 1, ztpp: MonthRange(from: 6, to: 12))
        let anna = try await database.saveChild(
            Self.child("Anna", born: "2019-09-03"), year: 2025, childYear: annaIn2025
        )
        let tomas = try await database.saveChild(
            Self.child("Tomáš", born: "2024-04-12"), year: 2025,
            childYear: Self.childYear(order: 2, claimant: .otherParent)
        )
        // The ids are keys of the dictionaries below, together with ids no child has, so they have to differ.
        try #require(Set([anna, tomas, 404, 999]).count == 4)
        let before2025 = try await database.family(year: 2025)

        try await database.setChildOrders(year: 2026, orders: [tomas: 1, anna: 2])

        // Each child's year as 2026 took it from 2025, now stored, with the new order.
        let family = try await database.family(year: 2026)
        #expect(
            family.children.map(\.year) == [
                Self.childYear(order: 2, ztpp: MonthRange(from: 1, to: 12)),
                Self.childYear(order: 1, claimant: .otherParent),
            ]
        )
        #expect(family.children.map(\.isStored) == [true, true])
        #expect(try await database.family(year: 2025) == before2025)
        // A child that is not in the family of the year is refused, and nothing changes.
        for orders in [[anna: 1, 404: 2], [tomas: 2, anna: 1, Int64(999): 3]] {
            await #expect { try await database.setChildOrders(year: 2026, orders: orders) } throws: {
                isConstraintViolation($0)
            }
        }
        await #expect { try await database.setChildOrders(year: 2023, orders: [tomas: 1]) } throws: {
            isConstraintViolation($0)
        }
        #expect(try await database.family(year: 2026) == family)
        #expect(try await database.family(year: 2023).children.map(\.isStored) == [false])
        #expect(try await database.storedSettingsYears() == [2025, 2026])
    }

    /// A child's year or a spouse the engine could not use is refused with nothing stored, not even the settings of
    /// the year.
    @Test func aFamilyThatCannotBeStoredIsRefusedAndNothingChanges() async throws {
        let (database, directory) = try makeDatabase()
        defer { removeTemporaryDirectory(directory) }
        let anna = Self.child("Anna", born: "2019-09-03")
        let refusedYears = [
            Self.childYear(order: 1, household: MonthRange(from: 8, to: 3)),
            Self.childYear(order: 1, household: MonthRange(from: 0, to: 12)),
            Self.childYear(order: 1, ztpp: MonthRange(from: 1, to: 13)),
            Self.childYear(order: 1, studies: MonthRange(from: 12, to: 11)),
            Self.childYear(order: 0),
        ]
        for (index, childYear) in refusedYears.enumerated() {
            await #expect("case \(index)") {
                try await database.saveChild(anna, year: 2026, childYear: childYear)
            } throws: {
                isConstraintViolation($0)
            }
        }
        let refusedSpouses = [
            Self.spouse(months: MonthRange(from: 7, to: 6)),
            Self.spouse(months: MonthRange(from: 1, to: 13)),
            Self.spouse(ownIncome: -1),
            SpouseYear(
                claim: true, months: MonthRange(from: 1, to: 12), ownIncomeKc: 0, ztpp: MonthRange(from: 0, to: 5)
            ),
        ]
        for (index, spouse) in refusedSpouses.enumerated() {
            await #expect("case \(index)") {
                try await database.saveSpouse(spouse, year: 2026)
            } throws: {
                isConstraintViolation($0)
            }
        }
        // A year before the year of the child's birth: its row would be what the year of birth takes.
        await #expect {
            try await database.saveChild(anna, year: 2018, childYear: Self.childYear(order: 1))
        } throws: {
            isConstraintViolation($0)
        }

        #expect(try await database.storedSettingsYears().isEmpty)
        #expect(try await database.integer("SELECT count(*) FROM child") == 0)
        // An order below 1 is refused for a child that is stored, too.
        let id = try await database.saveChild(anna, year: 2026, childYear: Self.childYear(order: 1))
        await #expect { try await database.setChildOrders(year: 2026, orders: [id: 0]) } throws: {
            isConstraintViolation($0)
        }
        // And so is a year before its birth.
        await #expect {
            try await database.saveChild(
                Self.child("Anna", born: "2019-09-03", id: id), year: 2018, childYear: Self.childYear(order: 1))
        } throws: {
            isConstraintViolation($0)
        }
        #expect(try await database.family(year: 2026).children.map(\.year) == [Self.childYear(order: 1)])
        #expect(try await database.integer("SELECT count(*) FROM child_year") == 1)
        #expect(try await database.storedSettingsYears() == [2026])
    }

    /// A change of a year's settings keeps what the year says about its children: the settings are updated in place,
    /// never replaced, so the rows of the children's years that belong to them stay.
    @Test func anUpdateOfAYearKeepsWhatItSaysAboutItsChildren() async throws {
        let (database, directory) = try makeDatabase()
        defer { removeTemporaryDirectory(directory) }
        try await database.saveChild(
            Self.child("Anna", born: "2019-09-03"), year: 2026,
            childYear: Self.childYear(order: 1, ztpp: MonthRange(from: 3, to: 12)))
        let family = try await database.family(year: 2026)
        #expect(try await database.integer("SELECT count(*) FROM child_year") == 1)

        try await database.updateYearSettings(2026) { $0.expensePercent = 80 }

        #expect(try await database.yearSettings(2026).expensePercent == 80)
        #expect(try await database.family(year: 2026) == family)
        #expect(try await database.integer("SELECT count(*) FROM child_year") == 1)
    }

    /// A date of birth moved to a later year takes the child's rows of the years before the birth with it, in the same
    /// write: the year of birth, without a row of its own, would otherwise take the household of such a row, with the
    /// months before the birth. Tomáš has rows for 2023 and 2024; born 12. 4. 2025 instead and saved for 2026, he has
    /// only that row, and 2025 resolves to the default, in the household from the month of his birth.
    @Test func aBirthDateMovedLaterRemovesTheRowsOfTheYearsBeforeTheBirth() async throws {
        let (database, directory) = try makeDatabase()
        defer { removeTemporaryDirectory(directory) }
        let tomas = try await database.saveChild(
            Self.child("Tomáš", born: "2023-04-12"), year: 2023,
            childYear: Self.childYear(order: 1, household: MonthRange(from: 4, to: 12)))
        try await database.saveChild(
            Self.child("Tomáš", born: "2023-04-12", id: tomas), year: 2024,
            childYear: Self.childYear(order: 1, ztpp: MonthRange(from: 1, to: 12)))
        let anna = try await database.saveChild(
            Self.child("Anna", born: "2019-09-03"), year: 2023, childYear: Self.childYear(order: 2))

        let moved = Self.child("Tomáš", born: "2025-04-12", id: tomas)
        try await database.saveChild(moved, year: 2026, childYear: Self.childYear(order: 1))

        let rows = "SELECT count(*) FROM child_year WHERE child_id = ?"
        #expect(try await database.integer(rows + " AND year < 2025", [.integer(tomas)]) == 0)
        #expect(try await database.integer(rows, [.integer(tomas)]) == 1)
        #expect(
            try await database.family(year: 2025).children.first { $0.child.id == tomas }
                == FamilyChild(
                    child: moved, year: Self.childYear(order: 2, household: MonthRange(from: 4, to: 12)),
                    isStored: false)
        )
        // The rows of another child stay.
        #expect(try await database.integer(rows, [.integer(anna)]) == 1)
    }

    /// A child is saved together with the orders of the other children of its year, in one write: Ema comes first, and
    /// Anna and Tomáš, who had no row of 2027, get rows with their new orders. Orders that cannot be stored — for a
    /// child that is not in the family of the year, for the child that is saved, or below 1 — are refused, and nothing
    /// of the save is stored: not the child, not its year, not the others' orders.
    @Test func aChildIsSavedWithTheOrdersOfTheOtherChildrenInOneWrite() async throws {
        let (database, directory) = try makeDatabase()
        defer { removeTemporaryDirectory(directory) }
        let anna = try await database.saveChild(
            Self.child("Anna", born: "2019-09-03"), year: 2026, childYear: Self.childYear(order: 1))
        let tomas = try await database.saveChild(
            Self.child("Tomáš", born: "2024-04-12"), year: 2026, childYear: Self.childYear(order: 2))
        try #require(Set([anna, tomas, 999]).count == 3)
        let before = try await database.family(year: 2027)
        let ema = Self.child("Ema", born: "2026-06-15")

        for refused in [[anna: 2, 999: 3], [anna: 2, tomas: 0]] {
            let writes = await database.writeCount
            await #expect {
                try await database.saveChild(
                    ema, year: 2027, childYear: Self.childYear(order: 1), otherOrders: refused)
            } throws: {
                isConstraintViolation($0)
            }
            #expect(await database.writeCount == writes)
            #expect(try await database.family(year: 2027) == before)
        }
        await #expect {
            try await database.saveChild(
                Self.child("Anna", born: "2019-09-03", id: anna), year: 2027, childYear: Self.childYear(order: 1),
                otherOrders: [anna: 2])
        } throws: {
            isConstraintViolation($0)
        }
        #expect(try await database.family(year: 2027) == before)

        let writes = await database.writeCount
        let id = try await database.saveChild(
            ema, year: 2027, childYear: Self.childYear(order: 1), otherOrders: [anna: 2, tomas: 3])

        #expect(await database.writeCount == writes + 1)
        let family = try await database.family(year: 2027)
        #expect(family.children.map(\.child.id) == [anna, tomas, id])
        #expect(family.children.map(\.year.order) == [2, 3, 1])
        #expect(family.children.map(\.isStored) == [true, true, true])
        // What the year said about Anna and Tomáš is kept: only the order is new. Their rows of 2026 are not touched.
        #expect(family.children.prefix(2).map(\.year.household) == before.children.map(\.year.household))
        let year2026 = try await database.family(year: 2026).children.filter { $0.child.id != id }
        #expect(year2026.map(\.year.order) == [1, 2])
    }

    /// A child is removed together with the orders of the other children of a year, in one write: without Anna, Tomáš
    /// is the first child of 2026. Orders that cannot be stored are refused, and the child is not removed either.
    @Test func aChildIsRemovedWithTheOrdersOfTheOtherChildrenInOneWrite() async throws {
        let (database, directory) = try makeDatabase()
        defer { removeTemporaryDirectory(directory) }
        let anna = try await database.saveChild(
            Self.child("Anna", born: "2019-09-03"), year: 2025, childYear: Self.childYear(order: 1))
        try await database.saveChild(
            Self.child("Anna", born: "2019-09-03", id: anna), year: 2026, childYear: Self.childYear(order: 1))
        let tomas = try await database.saveChild(
            Self.child("Tomáš", born: "2024-04-12"), year: 2026, childYear: Self.childYear(order: 2))
        try #require(Set([anna, tomas, 999]).count == 3)
        let before = try await database.family(year: 2026)

        for refused in [[tomas: 1, 999: 2], [anna: 1], [tomas: 0]] {
            let writes = await database.writeCount
            await #expect {
                try await database.removeChild(id: anna, year: 2026, otherOrders: refused)
            } throws: {
                isConstraintViolation($0)
            }
            #expect(await database.writeCount == writes)
            #expect(try await database.family(year: 2026) == before)
        }

        let writes = await database.writeCount
        try await database.removeChild(id: anna, year: 2026, otherOrders: [tomas: 1])

        #expect(await database.writeCount == writes + 1)
        #expect(try await database.family(year: 2026).children.map(\.child.id) == [tomas])
        #expect(try await database.family(year: 2026).children.map(\.year.order) == [1])
        #expect(try await database.integer("SELECT count(*) FROM child_year WHERE child_id = ?", [.integer(anna)]) == 0)
    }

    // MARK: Income adjustments

    @Test func adjustmentsOfAYearAreSortedByDateAndTheOtherYearsAreLeftOut() async throws {
        let (database, directory) = try makeDatabase()
        defer { removeTemporaryDirectory(directory) }
        let late = Self.adjustment("2026-11-30", 150_000, "Vrácená záloha")
        let early = Self.adjustment("2026-02-01", -25_050, "Dobropis č. 3")
        let sameDay = Self.adjustment("2026-02-01", 1, "Zaokrouhlení")
        let firstDay = Self.adjustment("2026-01-01", 10, "Nový rok")
        let lastDay = Self.adjustment("2026-12-31", 20, "Silvestr")
        let before = Self.adjustment("2025-12-31", 30, "Loni")
        let after = Self.adjustment("2027-01-01", 40, "Příští rok")
        for adjustment in [late, early, sameDay, before, lastDay, after, firstDay] {
            try await database.saveAdjustment(adjustment)
        }

        let adjustments = try await database.adjustments(year: 2026)

        // Equal dates keep the order the adjustments were saved in.
        #expect(
            adjustments.map(\.description)
                == ["Nový rok", "Dobropis č. 3", "Zaokrouhlení", "Vrácená záloha", "Silvestr"])
        #expect(adjustments.map(\.amountHalere) == [10, -25_050, 1, 150_000, 20])
        #expect(try await database.adjustments(year: 2025).map(\.description) == ["Loni"])
        #expect(try await database.adjustments(year: 2027).map(\.description) == ["Příští rok"])
        #expect(try await database.adjustments(year: 2024).isEmpty)
    }

    @Test func anAdjustmentRoundTripsAndEachNewOneGetsItsOwnId() async throws {
        let (database, directory) = try makeDatabase()
        defer { removeTemporaryDirectory(directory) }
        let refund = Self.adjustment("2026-03-15", -1_234_567, "Vrácení přeplatku – Příbram")

        let first = try await database.saveAdjustment(refund)
        let second = try await database.saveAdjustment(Self.adjustment("2026-03-16", 5, "Další"))

        #expect(first == 1)
        #expect(second == 2)
        var expected = refund
        expected.id = first
        #expect(try await database.adjustments(year: 2026).first == expected)
    }

    @Test func savingAnExistingAdjustmentUpdatesItInPlaceEvenWhenItMovesToAnotherYear() async throws {
        let (database, directory) = try makeDatabase()
        defer { removeTemporaryDirectory(directory) }
        var adjustment = Self.adjustment("2026-03-15", 1_000, "Původní")
        adjustment.id = try await database.saveAdjustment(adjustment)

        adjustment.date = civilDate("2027-01-02")
        adjustment.amountHalere = -2_000
        adjustment.description = "Opravená"
        let id = try await database.saveAdjustment(adjustment)

        #expect(id == adjustment.id)
        #expect(try await database.adjustments(year: 2026).isEmpty)
        #expect(try await database.adjustments(year: 2027) == [adjustment])
    }

    @Test func deletingAnAdjustmentRemovesOnlyThatOne() async throws {
        let (database, directory) = try makeDatabase()
        defer { removeTemporaryDirectory(directory) }
        let first = try await database.saveAdjustment(Self.adjustment("2026-03-15", 1, "První"))
        let second = try await database.saveAdjustment(Self.adjustment("2026-03-16", 2, "Druhá"))

        try await database.deleteAdjustment(id: first)

        #expect(try await database.adjustments(year: 2026).map(\.id) == [second])
        // An adjustment that is not there is not an error.
        try await database.deleteAdjustment(id: first)
        try await database.deleteAdjustment(id: 99)
        #expect(try await database.adjustments(year: 2026).map(\.id) == [second])
    }

    // MARK: Uniform rates

    @Test func theBuiltInUniformRateOfAPublishedYearIsThereAfterAFreshOpen() async throws {
        let key = randomKey()
        let (database, directory) = try makeDatabase(key: key)
        defer { removeTemporaryDirectory(directory) }
        await database.close()
        let reopened = try Database(fileURL: database.fileURL, key: key)

        let rate = try #require(try await reopened.uniformRate(.usd, year: 2025))

        #expect(rate.rate == decimal("21.84"))
        #expect(rate.amount == 1)
        #expect(rate.instruction == "GFŘ-D-75")
        #expect(rate.origin == .builtIn)
        #expect(rate.year == 2025)
        #expect(rate.currency == .usd)
        #expect(rate.sourceURL == nil)
        #expect(rate.confirmedAt == nil)
        #expect(rate.exchangeRate == ExchangeRate(currency: .usd, amount: 1, rate: decimal("21.84")))
    }

    @Test func aRateQuotedPer100UnitsKeepsItsAmount() async throws {
        let (database, directory) = try makeDatabase()
        defer { removeTemporaryDirectory(directory) }

        let code = try #require(CurrencyCode("HUF"))
        let huf = try #require(try await database.uniformRate(code, year: 2022))

        #expect(huf.amount == 100)
        #expect(huf.rate == decimal("6.26"))
        #expect(huf.instruction == "GFŘ-D-60")
    }

    @Test func aUniformRateThatDoesNotExistIsNil() async throws {
        let (database, directory) = try makeDatabase()
        defer { removeTemporaryDirectory(directory) }

        let kuna = try #require(CurrencyCode("HRK"))

        // 2026 is not published, and the kuna was only in the table of 2022.
        #expect(try await database.uniformRate(.usd, year: 2026) == nil)
        #expect(try await database.uniformRate(kuna, year: 2025) == nil)
        #expect(try await database.uniformRate(.czk, year: 2025) == nil)
    }

    @Test func uniformRatesOfAYearAreSortedByCurrency() async throws {
        let (database, directory) = try makeDatabase()
        defer { removeTemporaryDirectory(directory) }

        let rates = try await database.uniformRates(year: 2025)

        #expect(rates.count == BuiltInUniformRates.rates(year: 2025).count)
        #expect(rates.map(\.currency) == rates.map(\.currency).sorted())
        #expect(rates.allSatisfy { $0.year == 2025 && $0.instruction == "GFŘ-D-75" && $0.origin == .builtIn })
        #expect(try await database.uniformRates(year: 2026).isEmpty)
    }

    @Test func savingUniformRatesReplacesTheRowsOfThatYearAndKeepsTheOthers() async throws {
        let (database, directory) = try makeDatabase()
        defer { removeTemporaryDirectory(directory) }
        let kept2024 = try await database.uniformRates(year: 2024)
        let kept2023 = try await database.uniformRates(year: 2023)
        let replacements = [
            Self.uniformRate(year: 2025, .usd, "21.90", origin: .manual),
            Self.uniformRate(year: 2025, .eur, "24.80", origin: .manual),
        ]

        try await database.saveUniformRates(replacements, year: 2025)

        #expect(try await database.uniformRates(year: 2025) == replacements.sorted { $0.currency < $1.currency })
        #expect(try await database.uniformRates(year: 2024) == kept2024)
        #expect(try await database.uniformRates(year: 2023) == kept2023)
        #expect(try await database.uniformRate(.usd, year: 2025)?.rate == decimal("21.90"))
        let pound = try #require(CurrencyCode("GBP"))
        #expect(try await database.uniformRate(pound, year: 2025) == nil)
    }

    @Test func savingNoUniformRatesEmptiesTheYear() async throws {
        let (database, directory) = try makeDatabase()
        defer { removeTemporaryDirectory(directory) }
        let kept2024 = try await database.uniformRates(year: 2024)

        try await database.saveUniformRates([], year: 2025)

        #expect(try await database.uniformRates(year: 2025).isEmpty)
        #expect(try await database.uniformRate(.usd, year: 2025) == nil)
        #expect(try await database.uniformRates(year: 2024) == kept2024)
    }

    @Test func uniformRatesAreStoredOnlyForAYearThatHasNone() async throws {
        let (database, directory) = try makeDatabase()
        defer { removeTemporaryDirectory(directory) }
        let kept2025 = try await database.uniformRates(year: 2025)
        let fetched = Self.uniformRate(year: 2026, .usd, "20.69", origin: .fetched)

        // 2026 has none: the rates are stored, and the other years are not touched.
        #expect(try await database.storeUniformRatesIfNone([fetched], year: 2026))
        #expect(try await database.uniformRates(year: 2026) == [fetched])
        #expect(try await database.uniformRates(year: 2025) == kept2025)

        // 2026 has rates now, and 2025 has its built-in ones: neither is replaced.
        let other = Self.uniformRate(year: 2026, .eur, "24.10", origin: .fetched)
        let replacing2025 = Self.uniformRate(year: 2025, .usd, "1")
        #expect(try await database.storeUniformRatesIfNone([other], year: 2026) == false)
        #expect(try await database.storeUniformRatesIfNone([replacing2025], year: 2025) == false)
        #expect(try await database.uniformRates(year: 2026) == [fetched])
        #expect(try await database.uniformRates(year: 2025) == kept2025)
    }

    @Test func noUniformRatesAtAllAreNotStoredAsATableForTheYear() async throws {
        let (database, directory) = try makeDatabase()
        defer { removeTemporaryDirectory(directory) }

        #expect(try await database.storeUniformRatesIfNone([], year: 2026) == false)

        #expect(try await database.uniformRates(year: 2026).isEmpty)
    }

    @Test func uniformRatesThatCannotBeStoredAreRefusedByTheStoreForAYearWithNoneToo() async throws {
        let (database, directory) = try makeDatabase()
        defer { removeTemporaryDirectory(directory) }
        let good = Self.uniformRate(year: 2026, .usd, "21.90")
        let wrongYear = Self.uniformRate(year: 2025, .eur, "24.80")
        let zeroRate = Self.uniformRate(year: 2026, .eur, "0")

        for rates in [[good, wrongYear], [good, zeroRate]] {
            await #expect { try await database.storeUniformRatesIfNone(rates, year: 2026) } throws: {
                isConstraintViolation($0)
            }
        }

        #expect(try await database.uniformRates(year: 2026).isEmpty)
    }

    @Test func aFetchedUniformRateKeepsItsSourceAndTheTimeItWasConfirmed() async throws {
        let (database, directory) = try makeDatabase()
        defer { removeTemporaryDirectory(directory) }
        let fetched = UniformRate(
            year: 2026, currency: .usd, amount: 1, rate: decimal("20.69"), instruction: "GFŘ-D-99",
            sourceURL: "https://mf.gov.cz/example", confirmedAt: Date(timeIntervalSince1970: 1_798_000_000),
            origin: .fetched
        )

        try await database.saveUniformRates([fetched], year: 2026)

        #expect(try await database.uniformRate(.usd, year: 2026) == fetched)
        // The time is stored as whole Unix seconds.
        #expect(try await database.integer("SELECT confirmed_at FROM uniform_rate WHERE year = 2026") == 1_798_000_000)
    }

    @Test func uniformRatesThatCannotBeStoredAreRefusedAndTheYearStaysAsItWas() async throws {
        let (database, directory) = try makeDatabase()
        defer { removeTemporaryDirectory(directory) }
        let before = try await database.uniformRates(year: 2025)
        let good = Self.uniformRate(year: 2025, .usd, "21.90")
        let wrongYear = Self.uniformRate(year: 2026, .eur, "24.80")
        let zeroRate = Self.uniformRate(year: 2025, .eur, "0")
        let negativeRate = Self.uniformRate(year: 2025, .eur, "-24.80")
        let zeroAmount = Self.uniformRate(year: 2025, .eur, amount: 0, "24.80")
        let twice = Self.uniformRate(year: 2025, .usd, "22.00")

        for rates in [[good, wrongYear], [good, zeroRate], [good, negativeRate], [good, zeroAmount], [good, twice]] {
            await #expect { try await database.saveUniformRates(rates, year: 2025) } throws: {
                isConstraintViolation($0)
            }
        }

        #expect(try await database.uniformRates(year: 2025) == before)
    }

    @Test func deletingTheUniformRatesOfAYearLeavesTheOtherYearsAlone() async throws {
        let (database, directory) = try makeDatabase()
        defer { removeTemporaryDirectory(directory) }
        let kept2024 = try await database.uniformRates(year: 2024)
        try await database.saveUniformRates([Self.uniformRate(year: 2026, .usd, "21.90")], year: 2026)

        try await database.deleteUniformRates(year: 2026)
        try await database.deleteUniformRates(year: 2025)

        #expect(try await database.uniformRates(year: 2026).isEmpty)
        #expect(try await database.uniformRates(year: 2025).isEmpty)
        #expect(try await database.uniformRates(year: 2024) == kept2024)
        // A year without rates stays without them.
        try await database.deleteUniformRates(year: 2026)
        #expect(try await database.uniformRates(year: 2026).isEmpty)
    }

    /// The rows of the uniform rates of `year` as they are stored, every column as its text, one row after another by
    /// currency: what a test compares exactly.
    private func storedUniformRows(of year: Int, in database: Database) async throws -> String {
        try await database.text(
            """
            SELECT group_concat(line, ';') FROM (
                SELECT year || '|' || currency || '|' || amount || '|' || rate || '|' || instruction || '|'
                    || ifnull(source_url, '-') || '|' || ifnull(confirmed_at, '-') || '|' || origin AS line
                FROM uniform_rate WHERE year = \(year) ORDER BY currency)
            """)
    }

    /// The table that ships with the app comes back after rates entered by hand replaced it, row by row as a new
    /// database has it, and the other years are not touched.
    @Test(arguments: [2022, 2023, 2024, 2025])
    func restoringABuiltInYearBringsBackItsShippedTableExactly(_ year: Int) async throws {
        let (database, directory) = try makeDatabase()
        defer { removeTemporaryDirectory(directory) }
        let shipped = try await storedUniformRows(of: year, in: database)
        let rates = try await database.uniformRates(year: year)
        let otherYear = year == 2025 ? 2024 : 2025
        let other = try await database.uniformRates(year: otherYear)
        try await database.saveUniformRates(
            [Self.uniformRate(year: year, .usd, "21.90"), Self.uniformRate(year: year, .eur, "24.80")], year: year)

        try await database.restoreBuiltInUniformRates(year: year)

        #expect(try await storedUniformRows(of: year, in: database) == shipped)
        #expect(try await database.uniformRates(year: year) == rates)
        #expect(rates.count == BuiltInUniformRates.rates(year: year).count)
        #expect(rates.allSatisfy { $0.origin == .builtIn && $0.instruction == BuiltInUniformRates.instructions[year] })
        #expect(try await database.uniformRates(year: otherYear) == other)
    }

    @Test func restoringAYearWithoutAShippedTableLeavesItAsItIs() async throws {
        let (database, directory) = try makeDatabase()
        defer { removeTemporaryDirectory(directory) }
        let manual = [Self.uniformRate(year: 2026, .usd, "21.90")]
        try await database.saveUniformRates(manual, year: 2026)

        try await database.restoreBuiltInUniformRates(year: 2026)
        try await database.restoreBuiltInUniformRates(year: 2021)

        #expect(try await database.uniformRates(year: 2026) == manual)
        #expect(try await database.uniformRates(year: 2021).isEmpty)
    }

    // MARK: Logs

    @Test func theFetchLogReturnsTheNewestEntriesFirstAndKeepsTheLimit() async throws {
        let (database, directory) = try makeDatabase()
        defer { removeTemporaryDirectory(directory) }
        let entries = (0..<5).map { Self.logEntry($0) }
        for entry in entries {
            try await database.appendFetchLog(entry)
        }

        #expect(try await database.recentFetchLog(limit: 3) == [entries[4], entries[3], entries[2]])
        #expect(try await database.recentFetchLog(limit: 1) == [entries[4]])
        #expect(try await database.recentFetchLog(limit: 5) == Array(entries.reversed()))
        #expect(try await database.recentFetchLog(limit: 50) == Array(entries.reversed()))
        #expect(try await database.recentFetchLog(limit: 0).isEmpty)
        #expect(try await database.recentFetchLog(limit: -1).isEmpty)
    }

    @Test func anEmptyFetchLogHasNoEntries() async throws {
        let (database, directory) = try makeDatabase()
        defer { removeTemporaryDirectory(directory) }

        #expect(try await database.recentFetchLog(limit: 10).isEmpty)
    }

    @Test func fetchLogEntriesOfEveryKindRoundTrip() async throws {
        let (database, directory) = try makeDatabase()
        defer { removeTemporaryDirectory(directory) }
        let kinds: [FetchKind] = [.cnbDaily, .cnbYearly, .gfrIndex, .gfrIssue, .gfrPDF]
        let entries = kinds.enumerated().map { Self.logEntry($0.offset, kind: $0.element) }
        for entry in entries {
            try await database.appendFetchLog(entry)
        }

        #expect(try await database.recentFetchLog(limit: 10) == Array(entries.reversed()))
    }

    /// The log is in the order the entries were appended, even for entries made in the same second or after the
    /// clock was set back.
    @Test func fetchLogEntriesAreOrderedByAppendingNotByTime() async throws {
        let (database, directory) = try makeDatabase()
        defer { removeTemporaryDirectory(directory) }
        let moment = Date(timeIntervalSince1970: 1_760_000_000)
        let entries = [
            FetchLogEntry(at: moment, kind: .cnbDaily, target: "a", ok: true, message: ""),
            FetchLogEntry(at: moment, kind: .cnbDaily, target: "b", ok: true, message: ""),
            FetchLogEntry(at: moment.addingTimeInterval(-3600), kind: .cnbDaily, target: "c", ok: false, message: "x"),
        ]
        for entry in entries {
            try await database.appendFetchLog(entry)
        }

        #expect(try await database.recentFetchLog(limit: 2).map(\.target) == ["c", "b"])
        #expect(try await database.recentFetchLog(limit: 3).map(\.target) == ["c", "b", "a"])
    }

    @Test func aFetchLogTimeIsStoredAsWholeUnixSeconds() async throws {
        let (database, directory) = try makeDatabase()
        defer { removeTemporaryDirectory(directory) }

        try await database.appendFetchLog(Self.logEntry(0))
        // A part of a second is dropped.
        try await database.appendFetchLog(
            FetchLogEntry(
                at: Date(timeIntervalSince1970: 1_760_000_100.75), kind: .cnbYearly, target: "2026", ok: true,
                message: ""))

        #expect(try await database.integer("SELECT at FROM fetch_log WHERE id = 1") == 1_760_000_000)
        #expect(try await database.integer("SELECT at FROM fetch_log WHERE id = 2") == 1_760_000_100)
        #expect(try await database.integer("SELECT ok FROM fetch_log WHERE id = 1") == 1)
    }

    @Test func theImportLogReturnsTheLastSummaryWithItsExactBytes() async throws {
        let (database, directory) = try makeDatabase()
        defer { removeTemporaryDirectory(directory) }
        #expect(try await database.lastImportLog() == nil)

        let first = Data(#"{"imported":12,"skipped":1}"#.utf8)
        // Bytes that are not text, with zero bytes inside: it is a blob, not a string.
        let second = Data([0x7B, 0x00, 0xFF, 0xFE, 0x00, 0x7D])
        try await database.saveImportLog(first, at: Date(timeIntervalSince1970: 1_760_000_000))
        let afterFirst = try #require(try await database.lastImportLog())
        #expect(afterFirst.json == first)
        #expect(afterFirst.at == Date(timeIntervalSince1970: 1_760_000_000))

        try await database.saveImportLog(second, at: Date(timeIntervalSince1970: 1_760_086_400))
        let afterSecond = try #require(try await database.lastImportLog())
        #expect(afterSecond.json == second)
        #expect(afterSecond.at == Date(timeIntervalSince1970: 1_760_086_400))
        // Every import is kept.
        #expect(try await database.integer("SELECT count(*) FROM import_log") == 2)
    }

    @Test func theImportLogCanHoldAnEmptySummary() async throws {
        let (database, directory) = try makeDatabase()
        defer { removeTemporaryDirectory(directory) }

        try await database.saveImportLog(Data(), at: Date(timeIntervalSince1970: 1_760_000_000))

        let last = try #require(try await database.lastImportLog())
        #expect(last.json.isEmpty)
    }

    // MARK: Saving with an id

    /// A save is "make the stored row this value": an id that nobody has yet is inserted as it is, so a client,
    /// template or adjustment that was deleted can be saved again as it was.
    @Test func savingAnIdThatIsNotStoredInsertsItWithThatId() async throws {
        let (database, directory) = try makeDatabase()
        defer { removeTemporaryDirectory(directory) }
        var client = Self.client()
        client.id = 7

        #expect(try await database.saveClient(client) == 7)
        #expect(try await database.client(id: 7) == client)
        // The ids of new clients go on above it.
        #expect(try await database.saveClient(Self.client(name: "Další")) == 8)

        var template = Self.template(clientID: 7)
        template.id = 5
        #expect(try await database.saveTemplate(template) == 5)
        #expect(try await database.templates() == [template])

        var adjustment = Self.adjustment("2026-03-15", 1, "x")
        adjustment.id = 3
        #expect(try await database.saveAdjustment(adjustment) == 3)
        #expect(try await database.adjustments(year: 2026) == [adjustment])
    }

    // MARK: Damaged data

    /// The rows of an app that wrote them never hold these values, but a file that was changed by something else
    /// may. Reading it has to throw an error that can be shown, not stop the app.
    @Test func damagedStoredValuesAreReportedInsteadOfStoppingTheApp() async throws {
        let (database, directory) = try makeDatabase()
        defer { removeTemporaryDirectory(directory) }
        try await database.write { c in
            try c.run(
                """
                INSERT INTO bank_account(
                    currency, account_number, iban, bic, routing_number, account_type, bank_name_and_address)
                VALUES ('dollars', '', '', '', '', '', '')
                """
            )
            try SchemaRows.client(c, id: 1)
            try SchemaRows.template(c, id: 1, clientID: 1)
            try c.run("UPDATE template_item SET quantity = '6,5'")
            try SchemaRows.yearSettings(c, year: 2026)
            try c.run("UPDATE year_settings SET secondary_months = '4,13' WHERE year = 2026")
            try SchemaRows.yearSettings(c, year: 2025)
            try c.run("UPDATE year_settings SET income_fx_method = 'sometimes' WHERE year = 2025")
            try c.run(
                "INSERT INTO income_adjustment(date, amount_halere, description) VALUES ('2026-02-30', 1, 'x')"
            )
            try c.run(
                """
                INSERT INTO uniform_rate(year, currency, amount, rate, instruction, source_url, confirmed_at, origin)
                VALUES (2030, 'USD', 1, '21,84', 'x', NULL, NULL, 'manual')
                """
            )
            try SchemaRows.cnbRate(c, declaredOn: "2026-13-40", currency: "usd")
            try c.run("INSERT INTO fetch_log(at, kind, target, ok, message) VALUES (1, 'carrierPigeon', 'x', 1, '')")
        }

        await #expect(throws: StoredValueError.self, "bank account") { _ = try await database.bankAccounts() }
        await #expect(throws: StoredValueError.self, "quantity") { _ = try await database.templates() }
        await #expect(throws: StoredValueError.self, "months") { _ = try await database.yearSettings(2026) }
        await #expect(throws: StoredValueError.self, "enum") { _ = try await database.yearSettings(2025) }
        await #expect(throws: StoredValueError.self, "adjustment date") {
            _ = try await database.adjustments(year: 2026)
        }
        await #expect(throws: StoredValueError.self, "uniform rate") { _ = try await database.uniformRates(year: 2030) }
        await #expect(throws: StoredValueError.self, "newest declaration") {
            _ = try await database.newestCNBDeclaration()
        }
        await #expect(throws: StoredValueError.self, "currencies") { _ = try await database.cnbCurrencies() }
        await #expect(throws: StoredValueError.self, "fetch log kind") {
            _ = try await database.recentFetchLog(limit: 5)
        }
    }

    /// Settings that cannot be read are an error, not a reason to start again with the defaults and lose them.
    @Test func settingsThatCannotBeReadAreAnErrorAndNotTheDefaults() async throws {
        let (database, directory) = try makeDatabase()
        defer { removeTemporaryDirectory(directory) }
        try await database.write {
            try $0.run("INSERT INTO app_settings(key, value) VALUES ('app', 'not json')")
        }

        await #expect(throws: DecodingError.self) { _ = try await database.appSettings() }
    }

    // MARK: Transactions and persistence

    @Test func everySaveIsOneWriteAndReadingIsNone() async throws {
        let (database, directory) = try makeDatabase()
        defer { removeTemporaryDirectory(directory) }
        let rows = try cnbYearlyRows([2026])

        func expectOneWrite(_ what: String, _ save: () async throws -> Void) async throws {
            let before = await database.writeCount
            try await save()
            #expect(await database.writeCount == before + 1, "\(what)")
        }

        try await expectOneWrite("app settings") { try await database.saveAppSettings(Self.appSettings()) }
        try await expectOneWrite("supplier") { try await database.saveSupplier(Self.supplier()) }
        try await expectOneWrite("bank accounts") { try await database.saveBankAccounts(Self.bankAccounts()) }
        try await expectOneWrite("client") { try await database.saveClient(Self.client()) }
        try await expectOneWrite("template with two items") {
            try await database.saveTemplate(Self.template(clientID: 1))
        }
        try await expectOneWrite("template deletion") { try await database.deleteTemplate(id: 1) }
        try await expectOneWrite("year settings") { try await database.saveYearSettings(Self.yearSettings(2026)) }
        try await expectOneWrite("adjustment") {
            try await database.saveAdjustment(Self.adjustment("2026-03-15", 1, "x"))
        }
        try await expectOneWrite("adjustment deletion") { try await database.deleteAdjustment(id: 1) }
        try await expectOneWrite("child of a year without settings") {
            try await database.saveChild(
                Self.child("Anna", born: "2019-09-03"), year: 2027, childYear: Self.childYear(order: 1)
            )
        }
        try await expectOneWrite("child orders") { try await database.setChildOrders(year: 2028, orders: [1: 2]) }
        try await expectOneWrite("spouse of a year without settings") {
            try await database.saveSpouse(Self.spouse(), year: 2029)
        }
        try await expectOneWrite("child with the orders of the others") {
            try await database.saveChild(
                Self.child("Tomáš", born: "2024-04-12"), year: 2027, childYear: Self.childYear(order: 1),
                otherOrders: [1: 2])
        }
        try await expectOneWrite("child removal with the orders of the others") {
            try await database.removeChild(id: 2, year: 2027, otherOrders: [1: 1])
        }
        try await expectOneWrite("child removal") { try await database.removeChild(id: 1) }
        try await expectOneWrite("uniform rates") {
            try await database.saveUniformRates([Self.uniformRate(year: 2026, .usd, "20.5")], year: 2026)
        }
        try await expectOneWrite("a year of ČNB rates") { try await database.insertCNBRates(rows) }
        try await expectOneWrite("fetch log entry") { try await database.appendFetchLog(Self.logEntry(0)) }
        try await expectOneWrite("import log") {
            try await database.saveImportLog(Data("{}".utf8), at: Date(timeIntervalSince1970: 1_760_000_000))
        }

        let before = await database.writeCount
        _ = try await database.appSettings()
        _ = try await database.supplier()
        _ = try await database.bankAccounts()
        _ = try await database.clients()
        _ = try await database.client(id: 1)
        _ = try await database.templates()
        _ = try await database.yearSettings(2026)
        _ = try await database.storedSettingsYears()
        _ = try await database.family(year: 2026)
        _ = try await database.adjustments(year: 2026)
        _ = try await database.uniformRates(year: 2026)
        _ = try await database.uniformRate(.usd, year: 2026)
        _ = try await database.cnbRate(.usd, on: civilDate("2026-10-16"))
        _ = try await database.latestCNBRate(.usd, onOrBefore: civilDate("2026-10-16"))
        _ = try await database.newestCNBDeclaration()
        _ = try await database.cnbCurrencies()
        _ = try await database.recentFetchLog(limit: 5)
        _ = try await database.lastImportLog()
        #expect(await database.writeCount == before)
    }

    @Test func everythingSavedIsStillThereWhenTheDatabaseIsOpenedAgain() async throws {
        let key = randomKey()
        let (database, directory) = try makeDatabase(key: key)
        defer { removeTemporaryDirectory(directory) }
        var client = Self.client()
        client.id = try await database.saveClient(client)
        var template = Self.template(clientID: client.id)
        template.id = try await database.saveTemplate(template)
        var adjustment = Self.adjustment("2026-03-15", -500, "Dobropis")
        adjustment.id = try await database.saveAdjustment(adjustment)
        let uniform = UniformRate(
            year: 2026, currency: .usd, amount: 1, rate: decimal("20.69"), instruction: "GFŘ-D-99",
            sourceURL: "https://mf.gov.cz/example", confirmedAt: Date(timeIntervalSince1970: 1_798_000_000),
            origin: .fetched
        )
        let logEntry = Self.logEntry(3)
        let importJSON = Data(#"{"imported":3}"#.utf8)
        try await database.saveAppSettings(Self.appSettings())
        try await database.saveSupplier(Self.supplier())
        try await database.saveBankAccounts(Self.bankAccounts())
        try await database.saveYearSettings(Self.yearSettings(2026))
        try await database.saveUniformRates([uniform], year: 2026)
        try await database.insertCNBRates(cnbYearlyRows([2026]))
        try await database.appendFetchLog(logEntry)
        try await database.saveImportLog(importJSON, at: Date(timeIntervalSince1970: 1_760_000_000))
        await database.close()

        let reopened = try Database(fileURL: database.fileURL, key: key)

        #expect(try await reopened.appSettings() == Self.appSettings())
        #expect(try await reopened.supplier() == Self.supplier())
        #expect(try await reopened.bankAccounts() == Self.bankAccounts())
        #expect(try await reopened.clients() == [client])
        #expect(try await reopened.templates() == [template])
        #expect(try await reopened.yearSettings(2026) == Self.yearSettings(2026))
        #expect(try await reopened.storedSettingsYears() == [2026])
        #expect(try await reopened.adjustments(year: 2026) == [adjustment])
        #expect(try await reopened.uniformRates(year: 2026) == [uniform])
        #expect(try await reopened.newestCNBDeclaration() == civilDate("2026-10-16"))
        #expect(try await reopened.recentFetchLog(limit: 5) == [logEntry])
        let importLog = try #require(try await reopened.lastImportLog())
        #expect(importLog.json == importJSON)
    }
}
