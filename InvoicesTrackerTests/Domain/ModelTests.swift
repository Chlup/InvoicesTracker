import Foundation
import Testing
@testable import InvoicesTracker

struct ModelTests {
    // MARK: Helpers

    private func roundTrip<T: Codable>(_ value: T) throws -> T {
        try JSONDecoder().decode(T.self, from: JSONEncoder().encode(value))
    }

    private func quote(_ code: String, _ rate: String, declaredOn day: String) -> StoredRate {
        StoredRate(
            rate: ExchangeRate(currency: CurrencyCode(code)!, amount: 1, rate: decimal(rate)),
            declaredOn: civilDate(day)
        )
    }

    private func snapshot() -> ClientSnapshot {
        ClientSnapshot(
            name: "Alfa Systems s.r.o.", street: "Hlavní 1", postcode: "261 01", city: "Příbram", country: "CZ",
            ico: "12345678", dic: "CZ12345678", email: "ucetni@example.com"
        )
    }

    /// An invoice with every optional part set: the rate fixed at issue, a review flag and a payment with a rate of its
    /// own and a bank amount.
    private func paidInvoice(source: InvoiceSource) -> Invoice {
        Invoice(
            id: 42, number: "2026-09-01", clientID: 7, client: snapshot(), currency: .usd,
            issueDate: civilDate("2026-09-30"), duzp: civilDate("2026-09-30"), dueDate: civilDate("2026-10-14"),
            items: [
                InvoiceItem(description: "Vývoj – září", quantity: decimal("7.5"), unit: "hod", unitPriceMinor: 7000),
                InvoiceItem(description: "Konzultace", quantity: decimal("0.1"), unit: "hod", unitPriceMinor: 12_000),
                InvoiceItem(description: "Licence", quantity: decimal("205"), unit: "ks", unitPriceMinor: 1),
            ],
            vatMode: .outsideCountry, invoiceRate: quote("USD", "21.359", declaredOn: "2026-09-30"),
            qrEnabled: false, note: "Routing number: [ROUTING NUMBER]\nDěkuji", language: .en,
            paymentMethod: "ACH (USD)", status: .issued, review: ReviewFlag(reason: "Zkontrolovat částku"),
            payment: Payment(
                date: civilDate("2026-10-02"), conversion: .cnbDaily, czkNetHalere: 30_572_675, czkVatHalere: 0,
                rate: quote("USD", "21.305", declaredOn: "2026-10-02"), provisional: true,
                bankCZKTotalHalere: 30_600_000
            ),
            source: source
        )
    }

    // MARK: Year settings

    @Test func monthActivitiesFollowTheActivityRangeAndTheSecondaryMonths() {
        let settings = YearSettings(year: 2026, activityFrom: 7, secondaryMonths: [11, 12])

        let expected: [MonthActivity] = [
            .inactive, .inactive, .inactive, .inactive, .inactive, .inactive,
            .main, .main, .main, .main,
            .secondary, .secondary,
        ]
        #expect(settings.monthActivities() == expected)
    }

    @Test func aWholeYearOfMainActivityIsTheDefault() {
        #expect(YearSettings(year: 2026).monthActivities() == [MonthActivity](repeating: .main, count: 12))
    }

    @Test func activityEndsAtTheLastActiveMonth() {
        let settings = YearSettings(year: 2026, activityFrom: 3, activityTo: 5)

        let expected: [MonthActivity] = [
            .inactive, .inactive, .main, .main, .main,
            .inactive, .inactive, .inactive, .inactive, .inactive, .inactive, .inactive,
        ]
        #expect(settings.monthActivities() == expected)
    }

    @Test func aSecondaryMonthOutsideTheActivityRangeStaysInactive() {
        let settings = YearSettings(year: 2026, activityFrom: 7, secondaryMonths: [1, 7])

        let activities = settings.monthActivities()

        #expect(activities[0] == .inactive)
        #expect(activities[6] == .secondary)
        #expect(activities[7] == .main)
    }

    @Test func aReversedActivityRangeHasNoActiveMonth() {
        let settings = YearSettings(year: 2026, activityFrom: 9, activityTo: 4)

        #expect(settings.monthActivities() == [MonthActivity](repeating: .inactive, count: 12))
    }

    @Test func yearSettingsDefaultsAreWhatTheEngineAccepts() {
        let settings = YearSettings(year: 2026)
        let input = YearInput(
            year: settings.year, receipts: [], expensePercent: settings.expensePercent,
            months: settings.monthActivities(), healthExemptMonths: settings.healthExemptMonths,
            deductions: settings.deductions, taxpayerCredit: settings.taxpayerCredit, advances: settings.advances
        )

        // The engine traps on an expense percentage outside 80, 60, 40 and 30, on lists that do not have twelve
        // entries and on negative amounts, so getting a result at all is the check.
        let result = TaxEngine.compute(input, asOf: civilDate("2026-10-17"))

        #expect(result.year == 2026)
        #expect(settings.expensePercent == 60)
        #expect(!settings.reducedSocialBase)
        #expect(settings.activityFrom == 1)
        #expect(settings.activityTo == 12)
        #expect(settings.secondaryMonths.isEmpty)
        #expect(settings.healthExemptMonths.isEmpty)
        #expect(settings.advances == AdvancePlan.empty)
        #expect(settings.deductions == Deductions())
        #expect(settings.taxpayerCredit)
        #expect(settings.incomeFXMethod == .cnbDaily)
    }

    // MARK: Ranges of months

    /// A range of months is one when both its months are 1 to 12 and the first is no later than the last; one month is
    /// a range too. It holds the months from its first to its last.
    @Test func aRangeOfMonthsIsOneFromJanuaryToDecemberInOrderAndHoldsItsMonths() {
        #expect(MonthRange.wholeYear.isValid)
        #expect(MonthRange(from: 7, to: 7).isValid)
        #expect(MonthRange(from: 4, to: 12).isValid)
        #expect(!MonthRange(from: 8, to: 3).isValid)
        #expect(!MonthRange(from: 0, to: 12).isValid)
        #expect(!MonthRange(from: 1, to: 13).isValid)

        let spring = MonthRange(from: 3, to: 5)
        #expect((1...12).filter { spring.contains($0) } == [3, 4, 5])
        #expect((1...12).filter { MonthRange.wholeYear.contains($0) } == Array(1...12))
    }

    // MARK: Defaults

    @Test func newRecordsStartWithTheDocumentedDefaults() {
        let client = Client()
        #expect(client.id == 0)
        #expect([client.name, client.street, client.postcode, client.city].allSatisfy { $0.isEmpty })
        #expect([client.ico, client.dic, client.email, client.phone].allSatisfy { $0.isEmpty })
        #expect(client.country == "CZ")
        #expect(client.currency == .czk)
        #expect(client.vatMode == .domestic21)
        #expect(client.dueDays == 14)
        #expect(client.paymentMethod == "Převodem")
        #expect(client.language == .cs)
        #expect(client.origin == .app)
        #expect(!client.editedAfterImport)

        let supplier = Supplier()
        #expect(supplier.country == "CZ")
        #expect(supplier.czechFooter == "Fyzická osoba zapsaná v živnostenském rejstříku.")

        let account = BankAccount(currency: .eur)
        #expect(account.currency == .eur)
        #expect(
            [account.accountNumber, account.iban, account.bic, account.routingNumber, account.accountType]
                .allSatisfy { $0.isEmpty }
        )
        #expect(account.bankNameAndAddress.isEmpty)

        let template = InvoiceTemplate(name: "Měsíční vývoj", clientID: 3, items: [], vatMode: .none, dueDays: 30)
        #expect(template.id == 0)
        #expect(template.duzpAtMonthEnd)
        #expect(template.note.isEmpty)

        let settings = AppSettings()
        #expect(settings.appearance == .system)
        #expect(settings.touchIDUnlock)
        #expect(settings.backupFolderBookmark == nil)
        #expect(settings.backupFolderName == nil)
        #expect(settings.lastLocalBackup == nil)
        #expect(settings.lastOffMacBackup == nil)
        #expect(settings.localBackupPendingSince == nil)
        #expect(settings.chartMode == .months)
        #expect(!settings.chartWithVAT)
        #expect(settings.idleLock == .tenMinutes)

        let payment = Payment(date: civilDate("2026-10-02"), conversion: .czk, czkNetHalere: 100, czkVatHalere: 21)
        #expect(payment.rate == nil)
        #expect(!payment.provisional)
        #expect(payment.bankCZKTotalHalere == nil)
    }

    // MARK: VAT modes

    @Test func vatModesKnowTheirRateAndTheirLabel() {
        #expect(
            VatMode.allCases == [.domestic21, .domestic12, .outsideCountry, .euReverseCharge, VatMode.none]
        )
        #expect(VatMode.allCases.map(\.ratePercent) == [21, 12, 0, 0, 0])
        #expect(
            VatMode.allCases.map(\.label) == [
                "Tuzemsko 21 %", "Tuzemsko 12 %", "Mimo tuzemsko – § 9 odst. 1 (bez DPH)", "Přenesená povinnost – EU",
                "Bez DPH",
            ]
        )
    }

    /// The database stores these strings, so renaming a case would orphan every row that holds it.
    @Test func rawValuesStoredInTheDatabaseAreStable() {
        let vatModes = ["domestic21", "domestic12", "outsideCountry", "euReverseCharge", "none"]
        #expect(VatMode.allCases.map(\.rawValue) == vatModes)
        #expect([InvoiceLanguage.cs, .en].map(\.rawValue) == ["cs", "en"])
        #expect([ClientOrigin.app, .imported].map(\.rawValue) == ["app", "imported"])
        #expect([InvoiceStatus.draft, .issued].map(\.rawValue) == ["draft", "issued"])
        let conversions = ["czk", "cnbDaily", "uniform", "bankCZK"]
        #expect([PaymentConversion.czk, .cnbDaily, .uniform, .bankCZK].map(\.rawValue) == conversions)
        #expect([IncomeFXMethod.cnbDaily, .uniform].map(\.rawValue) == ["cnbDaily", "uniform"])
        #expect([UniformRateOrigin.builtIn, .fetched, .manual].map(\.rawValue) == ["builtIn", "fetched", "manual"])
        let kinds = ["cnbDaily", "cnbYearly", "gfrIndex", "gfrIssue", "gfrPDF"]
        #expect([FetchKind.cnbDaily, .cnbYearly, .gfrIndex, .gfrIssue, .gfrPDF].map(\.rawValue) == kinds)
        #expect([Appearance.system, .light, .dark].map(\.rawValue) == ["system", "light", "dark"])
        #expect([ChartMode.months, .years].map(\.rawValue) == ["months", "years"])
        #expect(IdleLockTime.allCases.map(\.rawValue) == [1, 5, 10, 15, 30, 60, 0])
        #expect([SearchIndexKind.automatic, .fts5, .plain].map(\.rawValue) == ["automatic", "fts5", "plain"])
    }

    // MARK: Client snapshot

    @Test func clientSnapshotCopiesThePrintedFields() {
        let client = Client(
            id: 7, name: "Příbramská stavební a.s.", street: "Nádražní 12", postcode: "261 01", city: "Příbram",
            country: "SK", ico: "12345678", dic: "SK2023456789", email: "ucetni@example.com", phone: "+420 123 456 789",
            currency: .eur, vatMode: .euReverseCharge, dueDays: 30, paymentMethod: "Hotově", language: .en,
            origin: .imported, editedAfterImport: true
        )

        let copy = ClientSnapshot(client: client)

        #expect(
            copy == ClientSnapshot(
                name: "Příbramská stavební a.s.", street: "Nádražní 12", postcode: "261 01", city: "Příbram",
                country: "SK", ico: "12345678", dic: "SK2023456789", email: "ucetni@example.com"
            )
        )
    }

    @Test func aSnapshotDoesNotFollowLaterChangesOfTheClient() {
        var client = Client(name: "Alfa", city: "Příbram")
        let copy = ClientSnapshot(client: client)

        client.name = "Alfa Prime"
        client.city = "Brno"

        #expect(copy.name == "Alfa")
        #expect(copy.city == "Příbram")
    }

    // MARK: Uniform rates

    @Test func aUniformRateConvertsLikeAnExchangeRate() {
        let rate = UniformRate(
            year: 2022, currency: CurrencyCode("HUF")!, amount: 100, rate: decimal("6.26"), instruction: "GFŘ-D-60",
            origin: .builtIn
        )

        #expect(rate.exchangeRate == ExchangeRate(currency: CurrencyCode("HUF")!, amount: 100, rate: decimal("6.26")))
        #expect(rate.exchangeRate.czkHalere(fromMinor: 100_000) == 6260)
        #expect(rate.sourceURL == nil)
        #expect(rate.confirmedAt == nil)
    }

    // MARK: JSON

    @Test func anInvoiceWithAPaymentAndAnImportedSourceSurvivesJSON() throws {
        let invoice = paidInvoice(
            source: .imported(fakturoidID: "1234567", fingerprint: "9f2c1ab07d", changedInApp: true)
        )

        let decoded = try roundTrip(invoice)

        #expect(decoded == invoice)
        // The rates and quantities must come back as exactly the numbers that went in, not as the nearest Double.
        #expect(decoded.invoiceRate?.rate.rate == decimal("21.359"))
        #expect(decoded.payment?.rate?.rate.rate == decimal("21.305"))
        #expect(decoded.items.map(\.quantity) == [decimal("7.5"), decimal("0.1"), decimal("205")])
    }

    @Test func anInvoiceWithoutOptionalPartsSurvivesJSON() throws {
        var invoice = paidInvoice(source: .app)
        invoice.clientID = nil
        invoice.invoiceRate = nil
        invoice.review = nil
        invoice.payment = nil
        invoice.status = .draft

        #expect(try roundTrip(invoice) == invoice)
    }

    @Test func decimalsSurviveJSONExactly() throws {
        let texts = [
            "21.359", "6.5", "0.1", "0.335", "21.622", "70.48", "0.0000001", "1234567.891234", "-12.5", "1000",
            "12345678901234567890.12345678",
        ]
        for text in texts {
            let value = decimal(text)
            let rate = ExchangeRate(currency: .usd, amount: 100, rate: value)
            let item = InvoiceItem(description: "x", quantity: value, unit: "ks", unitPriceMinor: 1)
            let templateItem = TemplateItem(description: "x", quantity: value, unit: "ks", unitPriceMinor: 1)

            #expect(try roundTrip(rate).rate == value, "rate \(text)")
            #expect(try roundTrip(item).quantity == value, "invoice item \(text)")
            #expect(try roundTrip(templateItem).quantity == value, "template item \(text)")
        }
    }

    @Test func aTemplateSurvivesJSON() throws {
        let template = InvoiceTemplate(
            id: 3, name: "Měsíční vývoj", clientID: 7,
            items: [
                TemplateItem(
                    description: "Vývoj {měsíc} {rok}", quantity: decimal("7.5"), unit: "hod", unitPriceMinor: 60_000
                ),
                TemplateItem(description: "Hosting", quantity: decimal("1"), unit: "ks", unitPriceMinor: 12_300),
            ],
            vatMode: .domestic21, dueDays: 14, duzpAtMonthEnd: false, note: "Děkuji\nza spolupráci"
        )

        #expect(try roundTrip(template) == template)
    }

    @Test func clientsSupplierAndRecordsSurviveJSON() throws {
        let client = Client(
            id: 7, name: "Příbramská stavební a.s.", street: "Nádražní 12", postcode: "261 01", city: "Příbram",
            country: "US", ico: "12345678", dic: "", email: "ucetni@example.com", phone: "+1 555 0100",
            currency: .usd, vatMode: .outsideCountry, dueDays: 30, paymentMethod: "ACH (USD)", language: .en,
            origin: .imported, editedAfterImport: true
        )
        let supplier = Supplier(
            name: "Jan Novák", street: "Dlouhá 1", postcode: "110 00", city: "Praha", country: "CZ", ico: "00000001",
            dic: "CZ0000000001", email: "jan@example.com", phone: "+420 000 000 000", czechFooter: "Zapsán v rejstříku."
        )
        let account = BankAccount(
            currency: .usd, accountNumber: "000123456789", iban: "", bic: "ABCDUS33", routingNumber: "123456789",
            accountType: "Checking", bankNameAndAddress: "Example Bank, 1 Main Street"
        )
        let adjustment = IncomeAdjustment(
            id: 9, date: civilDate("2026-03-01"), amountHalere: -100_000, description: "Dobropis"
        )
        let year = YearSettings(
            year: 2026, expensePercent: 40, reducedSocialBase: true, activityFrom: 2, activityTo: 11,
            secondaryMonths: [2, 3], healthExemptMonths: [4],
            advances: AdvancePlan(
                social: [Int64](repeating: 3852, count: 12), health: [Int64](repeating: 2968, count: 12),
                tax: [Int64](repeating: 0, count: 12)
            ),
            deductions: Deductions(
                mortgageInterestPaid: 90_000, mortgageMonths: 10, mortgageCap: .before2021, gifts: 2000
            ),
            taxpayerCredit: false, incomeFXMethod: .uniform
        )
        let uniform = UniformRate(
            year: 2026, currency: .usd, amount: 1, rate: decimal("21.84"), instruction: "GFŘ-D-99",
            sourceURL: "https://mf.gov.cz/example", confirmedAt: Date(timeIntervalSince1970: 1_800_000_000),
            origin: .fetched
        )
        let log = FetchLogEntry(
            at: Date(timeIntervalSince1970: 1_800_000_123), kind: .gfrPDF, target: "https://mf.gov.cz/x.pdf", ok: false,
            message: "Nepodařilo se přečíst PDF."
        )

        #expect(try roundTrip(client) == client)
        #expect(try roundTrip(supplier) == supplier)
        #expect(try roundTrip(account) == account)
        #expect(try roundTrip(adjustment) == adjustment)
        #expect(try roundTrip(year) == year)
        #expect(try roundTrip(uniform) == uniform)
        #expect(try roundTrip(log) == log)
    }

    // MARK: App settings

    @Test func appSettingsSurviveJSON() throws {
        let settings = AppSettings(
            appearance: .dark, touchIDUnlock: false, idleLock: .oneHour, backupFolderBookmark: Data([0, 1, 2, 255]),
            backupFolderName: "Záloha – disk", lastLocalBackup: Date(timeIntervalSince1970: 1_800_000_000.25),
            lastOffMacBackup: Date(timeIntervalSince1970: 1_700_000_000),
            localBackupPendingSince: Date(timeIntervalSince1970: 1_800_000_600), chartMode: .years, chartWithVAT: true,
            replacedRecoveryCodeLabel: "kód č. 1 z 17.\u{00A0}10.\u{00A0}2026", replacedRecoveryCodeNumber: 1,
            backupFolderChosen: Date(timeIntervalSince1970: 1_799_000_000)
        )

        #expect(try roundTrip(settings) == settings)
    }

    /// The settings are kept as JSON in one row, so a field added by a later version must not make a row written
    /// before it unreadable.
    @Test func appSettingsMissingFieldsTakeTheirDefaults() throws {
        let decoder = JSONDecoder()

        #expect(try decoder.decode(AppSettings.self, from: Data("{}".utf8)) == AppSettings())
        let partial = try decoder.decode(AppSettings.self, from: Data(#"{"appearance":"light","extra":1}"#.utf8))
        #expect(partial == AppSettings(appearance: .light))
    }

    /// The settings stored before the lock after inactivity have no time for it: they read as 10 minutes, the default,
    /// and keep everything else they say.
    @Test func anOlderSettingsRecordReadsTenMinutes() throws {
        let older = Data(#"{"appearance":"dark","touchIDUnlock":true,"chartMode":"years","chartWithVAT":true}"#.utf8)

        let settings = try JSONDecoder().decode(AppSettings.self, from: older)

        #expect(settings.idleLock == .tenMinutes)
        #expect(
            settings == AppSettings(appearance: .dark, touchIDUnlock: true, chartMode: .years, chartWithVAT: true))
        let stored = try JSONEncoder().encode(AppSettings(idleLock: .never))
        #expect(try JSONDecoder().decode(AppSettings.self, from: stored).idleLock == .never)
    }
}
