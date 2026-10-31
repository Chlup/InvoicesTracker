import Foundation
import Testing
@testable import InvoicesTracker

/// The pieces of Nastavení that are worked out without the data: the titles of the tabs, the lines "Na fakturách" of
/// the bank accounts, the checks of an IBAN and a BIC, the words of times and days, and the rows of the rates on the
/// tab Aplikace. In every expected string `\u{00A0}` is the no-break space. The accounts and the codes are invented,
/// the IBANs the well-known example ones.
struct SettingsModelsTests {
    // MARK: The tabs

    @Test func theSupplierTabIsCalledMojeÚdaje() {
        #expect(SettingsTab.supplier.title(year: 2026) == "Moje údaje")
        #expect(
            SettingsTab.allCases.map { $0.title(year: 2026) }
                == ["Aplikace", "Moje údaje", "Zabezpečení a zálohy", "Rok 2026"])
    }

    // MARK: Na fakturách

    private let crowns = BankAccount(currency: .czk, accountNumber: "123456789/0100", iban: "CZ65 0800 0000 1920 0014 5399")
    private let dollars = BankAccount(
        currency: .usd, accountNumber: "000123456789", routingNumber: "123456789", accountType: "Checking",
        bankNameAndAddress: "Example Bank, 1 Main Street, Springfield")
    private let euros = BankAccount(currency: .eur, iban: "DE89 3704 0044 0532 0130 00", bic: "COBADEFFXXX")

    @Test func anAccountInCrownsWithItsIBANPrintsTheNumberAndMakesTheQRPlatba() {
        let lines = InvoiceAccountStatus.lines(accounts: [crowns, dollars])

        #expect(lines.first == "Faktury v Kč: účet 123456789/0100 · QR Platba z IBAN")
        #expect(InvoiceAccountStatus.entries(accounts: [crowns]).first?.kind == .ready)
    }

    @Test func anAccountInCrownsWithoutAnIBANAsksForIt() throws {
        var withoutIBAN = crowns
        withoutIBAN.iban = "  "

        let line = try #require(InvoiceAccountStatus.entries(accounts: [withoutIBAN]).first)

        #expect(line.text.contains("doplňte IBAN, jinak faktura nebude mít QR Platbu"))
        #expect(line.text == "Faktury v Kč: účet 123456789/0100 · doplňte IBAN, jinak faktura nebude mít QR Platbu")
        #expect(line.kind == .incomplete)
    }

    @Test func noAccountNumberInCrownsSaysThatTheInvoiceHasNowhereToSendThePayment() {
        let lines = InvoiceAccountStatus.lines(accounts: [])

        #expect(lines.first == "Faktury v Kč: doplňte číslo účtu – bez něj faktura nemá kam poslat platbu")
    }

    @Test func anAccountInDollarsPrintsTheNumberAndTheRoutingNumberAndHasNoQR() {
        let lines = InvoiceAccountStatus.lines(accounts: [crowns, dollars])

        #expect(lines[1].hasPrefix("Faktury v USD: "))
        #expect(lines[1].hasSuffix(" · bez QR (pro USD standard není)"))
        #expect(lines[1] == "Faktury v USD: účet 000123456789 · routing 123456789 · bez QR (pro USD standard není)")
    }

    @Test func anAccountInDollarsWithoutItsNumbersAsksForThem() {
        var incomplete = dollars
        incomplete.routingNumber = ""

        let entries = InvoiceAccountStatus.entries(accounts: [crowns, incomplete])

        #expect(entries[1].text == "Faktury v USD: doplňte account number a routing number")
        #expect(entries[1].kind == .incomplete)
    }

    @Test func noAccountInEurosSaysToAddOneBeforeTheFirstInvoiceInEuros() {
        let entries = InvoiceAccountStatus.entries(accounts: [crowns, dollars])

        #expect(entries.count == 3)
        #expect(
            entries[2].text
                == "Faktury v EUR: bez účtu v eurech – přidejte ho, než vystavíte první fakturu v eurech")
        #expect(entries[2].kind == .absent)
    }

    @Test func anAccountInEurosMakesTheSEPAPaymentOrAsksForItsIBAN() {
        var withoutIBAN = euros
        withoutIBAN.iban = ""

        #expect(
            InvoiceAccountStatus.lines(accounts: [crowns, dollars, euros])[2]
                == "Faktury v EUR: IBAN DE89 3704 0044 0532 0130 00 · QR platba SEPA")
        let incomplete = InvoiceAccountStatus.entries(accounts: [crowns, dollars, withoutIBAN])[2]
        #expect(incomplete.text == "Faktury v EUR: doplňte IBAN")
        #expect(incomplete.kind == .incomplete)
    }

    // MARK: IBAN and BIC

    @Test(arguments: [
        "CZ65 0800 0000 1920 0014 5399", "CZ6508000000192000145399", "cz65 0800 0000 1920 0014 5399",
        "DE89 3704 0044 0532 0130 00", "GB82 WEST 1234 5698 7654 32", "CZ65\u{00A0}0800\u{00A0}0000\u{00A0}1920\u{00A0}0014\u{00A0}5399",
    ])
    func anIBANWhoseCheckDigitsPassIsTaken(_ iban: String) {
        #expect(BankCodes.isValidIBAN(iban))
    }

    @Test(arguments: [
        // One digit typed wrong, two digits swapped, a letter for a digit.
        "CZ65 0800 0000 1920 0014 5398", "CZ65 0800 0000 1920 0014 3599", "CZ65 0800 0000 1920 0014 539O",
        // Too short, too long, no country, a dash.
        "CZ65", "CZ65 0800 0000 1920 0014 5399 0000 0000 0000", "6508 0000 0019 2000 1453 99", "CZ65-0800-0000-1920-0014-5399",
        "",
    ])
    func anIBANWithATypoIsRefused(_ iban: String) {
        #expect(!BankCodes.isValidIBAN(iban))
    }

    @Test func aCodeIsKeptInCapitalsWithoutItsSpaces() {
        #expect(BankCodes.normalized(" cz65 0800\u{00A0}0000\u{202F}1920 0014 5399 ") == "CZ6508000000192000145399")
        #expect(BankCodes.normalized("coba de ff xxx") == "COBADEFFXXX")
        #expect(BankCodes.normalized("CZ65-0800") == "CZ65-0800")
    }

    @Test(arguments: ["GIBACZPX", "COBADEFFXXX", "gibaczpx", "COBA DE FF XXX"])
    func aBICOfEightOrElevenCharactersIsTaken(_ bic: String) {
        #expect(BankCodes.isValidBIC(bic))
    }

    @Test(arguments: ["GIBACZP", "GIBACZPXX", "COBADEFFXXXX", "GIBA1ZPX", "GIBA-CZPX", ""])
    func aBICOfAnotherLengthOrShapeIsRefused(_ bic: String) {
        #expect(!BankCodes.isValidBIC(bic))
    }

    // MARK: Words of times and days

    private let prague = TimeZone(identifier: "Europe/Prague")!

    /// `hour`:`minute` of `day` in Prague.
    private func pragueTime(_ day: String, _ hour: Int, _ minute: Int) -> Date {
        CzechCalendar.pragueTime(civilDate(day), hour: hour, minute: minute)
    }

    @Test func aTimeIsWrittenWithoutALeadingZeroOfTheHourAndWithTheRightPreposition() {
        #expect(SettingsTexts.clockTime(pragueTime("2026-10-16", 9, 5), timeZone: prague) == "9:05")
        #expect(SettingsTexts.atClockTime(pragueTime("2026-10-16", 14, 36), timeZone: prague) == "ve 14:36")
        #expect(SettingsTexts.atClockTime(pragueTime("2026-10-16", 9, 5), timeZone: prague) == "v 9:05")
        #expect(SettingsTexts.atClockTime(pragueTime("2026-10-16", 21, 14), timeZone: prague) == "ve 21:14")
    }

    @Test func aWeekdayHasItsPreposition() {
        let days = (12...18).map { SettingsTexts.weekdayWithPreposition(civilDate("2026-10-\($0)")) }

        #expect(days == ["v pondělí", "v úterý", "ve středu", "ve čtvrtek", "v pátek", "v sobotu", "v neděli"])
    }

    @Test func theMomentOfABackupIsTodayOrItsDate() {
        let today = civilDate("2026-10-17")

        #expect(
            SettingsTexts.backupMoment(pragueTime("2026-10-17", 14, 5), today: today, timeZone: prague)
                == "dnes 14:05")
        #expect(
            SettingsTexts.backupMoment(pragueTime("2026-10-15", 18, 40), today: today, timeZone: prague)
                == "15.\u{00A0}10.\u{00A0}2026 18:40")
    }

    // MARK: Kurzy

    private func builtIn2025(_ code: String, _ rate: String) -> UniformRate {
        UniformRate(
            year: 2025, currency: CurrencyCode(code)!, amount: 1, rate: decimal(rate), instruction: "GFŘ-D-75",
            origin: .builtIn)
    }

    /// Saturday 17. 10. 2026 at 15:20 in Prague, the rates of Friday downloaded at 14:36, the uniform rates of 2025
    /// shipped with the app and none of 2026.
    private func saturdayFacts() -> RatesStatusFacts {
        RatesStatusFacts(
            now: pragueTime("2026-10-17", 15, 20), timeZone: prague, currentYear: 2026,
            newestDeclaration: civilDate("2026-10-16"), lastDownload: pragueTime("2026-10-16", 14, 36),
            finishedYearRates: [builtIn2025("EUR", "24.66"), builtIn2025("JPY", "14.59"), builtIn2025("USD", "21.84")],
            currentYearRates: [], finishedYearSearch: .notOut)
    }

    @Test func theRowsOfTheRatesSayHowCurrentTheyAreAndWhereTheUniformRatesStand() {
        let rows = RatesStatus.rows(saturdayFacts())

        #expect(
            rows == [
                RateStatusRow(
                    label: "Kurzy ČNB", value: "aktuální k 16.\u{00A0}10.\u{00A0}2026",
                    detail: "staženo v pátek 16.\u{00A0}10. ve 14:36 · další vyjdou v pondělí 19.\u{00A0}10. po 14:30",
                    tone: .current),
                RateStatusRow(
                    label: "Jednotný kurz 2025", value: "1\u{00A0}USD = 21,84\u{00A0}Kč · 1\u{00A0}EUR = 24,66\u{00A0}Kč",
                    detail: "pokyn GFŘ-D-75", tone: .plain),
                RateStatusRow(
                    label: "Jednotný kurz 2026", value: "zatím nevyšel",
                    detail: "GFŘ ho vydá v lednu 2027. Aplikace ho od 2.\u{00A0}1.\u{00A0}2027 jednou denně hledá a dá vám"
                        + " ho potvrdit.",
                    tone: .quiet),
            ])
    }

    @Test func ratesBehindTheLatestDeclarationAreAWarningAndNoRatesSaySo() {
        var behind = saturdayFacts()
        behind.newestDeclaration = civilDate("2026-10-14")
        behind.lastDownload = nil
        var none = saturdayFacts()
        none.newestDeclaration = nil
        none.lastDownload = nil

        let behindRow = RatesStatus.rows(behind)[0]
        let noneRow = RatesStatus.rows(none)[0]

        #expect(behindRow.value == "aktuální k 14.\u{00A0}10.\u{00A0}2026")
        #expect(behindRow.tone == .warning)
        #expect(behindRow.detail == "další vyjdou v pondělí 19.\u{00A0}10. po 14:30")
        #expect(noneRow.value == "zatím nestaženy")
        #expect(noneRow.tone == .warning)
    }

    @Test func onABusinessDayBeforeTheDeclarationTheNextRatesComeOutToday() {
        var monday = saturdayFacts()
        monday.now = pragueTime("2026-10-19", 10, 0)
        monday.lastDownload = pragueTime("2026-10-19", 9, 5)

        #expect(RatesStatus.rows(monday)[0].detail == "staženo dnes v 9:05 · další vyjdou dnes po 14:30")
        #expect(
            RatesStatus.checkedText(newest: civilDate("2026-10-16"), now: pragueTime("2026-10-17", 15, 20))
                == "Kurzy ČNB jsou aktuální k 16.\u{00A0}10.\u{00A0}2026. Další vyjdou v pondělí 19.\u{00A0}10. po 14:30.")
    }

    /// In January to March the finished year has no rate until the GFŘ publishes it: the row says what the search came
    /// to.
    @Test(arguments: [
        (UniformSearchState.notOut, "zatím nevyšel", RateStatusRow.Tone.quiet),
        (.waitingForConfirmation(instruction: "GFŘ-D-80"), "vyšel, čeká na potvrzení", .warning),
        (.unreadable, "nepodařilo se ho přečíst", .warning),
        (.gaveUp, "nenalezen", .warning),
    ])
    func theRowOfAFinishedYearWithoutARateSaysWhatTheSearchCameTo(
        state: UniformSearchState, value: String, tone: RateStatusRow.Tone
    ) {
        var january = saturdayFacts()
        january.now = pragueTime("2027-01-20", 10, 0)
        january.currentYear = 2027
        january.finishedYearRates = []
        january.finishedYearSearch = state

        let row = RatesStatus.rows(january)[1]

        #expect(row.label == "Jednotný kurz 2026")
        #expect(row.value == value)
        #expect(row.tone == tone)
        #expect(!row.detail.isEmpty)
    }

    /// Only the row of a rate that was found and waits for the person offers to show it again; no other row has an
    /// action.
    @Test func onlyTheRowOfARateThatWaitsForConfirmationOffersToShowIt() {
        var january = saturdayFacts()
        january.now = pragueTime("2027-01-20", 10, 0)
        january.currentYear = 2027
        january.finishedYearRates = []

        for state in [UniformSearchState.notOut, .unreadable, .gaveUp] {
            january.finishedYearSearch = state
            #expect(RatesStatus.rows(january).allSatisfy { $0.action == nil })
        }
        january.finishedYearSearch = .waitingForConfirmation(instruction: "GFŘ-D-80")
        let rows = RatesStatus.rows(january)

        #expect(rows.map(\.action) == [nil, .showFinding, nil])
        #expect(rows[1].value == "vyšel, čeká na potvrzení")
    }

    private func manual(_ year: Int, _ code: String, _ rate: String, instruction: String = "") -> UniformRate {
        UniformRate(
            year: year, currency: CurrencyCode(code)!, amount: 1, rate: decimal(rate), instruction: instruction,
            origin: .manual)
    }

    /// A rate entered by hand says so, with what it means for the official one: over the table that ships with the app
    /// it replaces that table, and for a year without one the app does not look for the official rate while it is
    /// stored.
    @Test func kurzyMarkAManualRate() {
        var facts = saturdayFacts()
        facts.finishedYearRates = [
            manual(2025, "EUR", "24.80", instruction: "GFŘ-D-80"), builtIn2025("JPY", "14.59"),
            manual(2025, "USD", "21.90", instruction: "GFŘ-D-80"),
        ]
        facts.currentYearRates = [manual(2026, "USD", "21.90")]

        let rows = RatesStatus.rows(facts)

        #expect(
            rows[1]
                == RateStatusRow(
                    label: "Jednotný kurz 2025",
                    value: "1\u{00A0}USD = 21,90\u{00A0}Kč · 1\u{00A0}EUR = 24,80\u{00A0}Kč",
                    detail: "pokyn GFŘ-D-80, zadáno ručně · nahrazuje kurz, který má aplikace od vydání", tone: .plain))
        #expect(
            rows[2]
                == RateStatusRow(
                    label: "Jednotný kurz 2026", value: "1\u{00A0}USD = 21,90\u{00A0}Kč",
                    detail: "zadáno ručně · oficiální kurz aplikace nehledá, dokud ručně zadaný neodstraníte",
                    tone: .plain))
    }

    /// The state of a row is in the green of text while the rates are current, in the colour of text for a fact such as
    /// a rate, in the grey of secondary text where there is nothing yet, and in the orange of text where something is
    /// behind. The colours are the tokens of the design, not the system's.
    @MainActor
    @Test func theStateOfARowOfKurzyTakesTheColourOfItsTone() {
        #expect(RateStatusRow.Tone.current.color == Palette.greenText)
        #expect(RateStatusRow.Tone.plain.color == Palette.text)
        #expect(RateStatusRow.Tone.quiet.color == Palette.text2)
        #expect(RateStatusRow.Tone.warning.color == Palette.orangeText)
    }

    /// The row of the uniform rate of 2026 without a rate follows the search of the app for it on the day, as the card
    /// of Nastavení › Rok and the toolbar do: until 2 January 2027 it says when the app starts looking, until 31 March
    /// that the app looks for it, and from 1 April that it was not found and is entered by hand.
    @Test func kurzySayWhereTheSearchForTheRateStandsOnTheDay() throws {
        func row(on day: String) throws -> RateStatusRow {
            var facts = saturdayFacts()
            facts.now = pragueTime(day, 10, 0)
            facts.currentYear = civilDate(day).year
            facts.newestDeclaration = nil
            facts.lastDownload = nil
            facts.finishedYearRates = []
            facts.currentYearRates = []
            return try #require(RatesStatus.rows(facts).first { $0.label == "Jednotný kurz 2026" })
        }
        let awaited = RateStatusRow(
            label: "Jednotný kurz 2026", value: "zatím nevyšel",
            detail: "GFŘ ho vydá v lednu 2027. Aplikace ho od 2.\u{00A0}1.\u{00A0}2027 jednou denně hledá a dá vám ho"
                + " potvrdit.",
            tone: .quiet)
        let looking = RateStatusRow(
            label: "Jednotný kurz 2026", value: "zatím nevyšel",
            detail: "GFŘ ho vydává v lednu. Aplikace ho jednou denně hledá a dá vám ho potvrdit.", tone: .quiet)
        let over = RateStatusRow(
            label: "Jednotný kurz 2026", value: "nenalezen",
            detail: "Do 31.\u{00A0}3.\u{00A0}2027 se ho najít nepodařilo – zadejte ho ručně na kartě Rok 2026.",
            tone: .warning)

        #expect(try row(on: "2026-12-31") == awaited)
        #expect(try row(on: "2027-01-01") == awaited)
        #expect(try row(on: "2027-01-02") == looking)
        #expect(try row(on: "2027-03-31") == looking)
        #expect(try row(on: "2027-04-01") == over)
    }
}

/// The tab Aplikace on the data: the rows of the rates as the cache and the stored uniform rates have them, Zkontrolovat
/// teď, and the appearance.
@Suite(.settlesBackups)
@MainActor
struct AppTabModelTests {
    @Test func theRowsComeFromTheCachedRatesAndTheUniformRatesStored() async throws {
        try await EditorFixture.with { f in
            let model = AppTabModel(app: f.app)

            await model.load()

            #expect(model.rateRows.count == 3)
            #expect(model.rateRows[0].value == "aktuální k 16.\u{00A0}10.\u{00A0}2026")
            #expect(model.rateRows[1].value == "1\u{00A0}USD = 21,84\u{00A0}Kč · 1\u{00A0}EUR = 24,66\u{00A0}Kč")
            #expect(model.rateRows[2].value == "zatím nevyšel")
        }
    }

    @Test func zobrazitBringsBackTheSheetOfARateThatWasPutOff() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let app = try await makeSettingsApp(in: directory)
        try await #require(app.database).execute("DELETE FROM uniform_rate WHERE year = 2025")
        let finding = try gfrFinding2025()
        await app.offerUniformRate(finding)
        // The person put the sheet off with Později (or Esc): the finding waits.
        app.uniformRateOffer = nil
        let model = AppTabModel(app: app)

        model.showPendingFinding()

        #expect(app.uniformRateOffer == finding)
    }

    @Test func zobrazitDoesNothingWhenNoRateWaits() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let app = try await makeSettingsApp(in: directory)
        let model = AppTabModel(app: app)

        model.showPendingFinding()

        #expect(app.uniformRateOffer == nil)
    }

    @Test func checkingNowRunsTheRefreshAndSaysHowCurrentTheRatesAre() async throws {
        try await EditorFixture.with { f in
            let model = AppTabModel(app: f.app)
            f.app.showSettings(.application)
            await model.load()

            await model.checkNow()

            #expect(
                f.app.banner
                    == AppBanner(
                        text: "Kurzy ČNB jsou aktuální k 16.\u{00A0}10.\u{00A0}2026. Další vyjdou v pondělí 19.\u{00A0}10."
                            + " po 14:30.",
                        screen: .settings))
            #expect(!model.isChecking)
        }
    }

    @Test func theAppearanceIsSavedAtOnce() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let app = try await makeSettingsApp(in: directory)
        let model = AppTabModel(app: app)

        await model.setAppearance(.dark)

        #expect(app.appSettings.appearance == .dark)
        #expect(try await #require(app.database).appSettings().appearance == .dark)
        #expect(AppTabModel.appearanceNote(.dark) == "Aplikace bude tmavá, i když má systém světlý vzhled.")
    }

    @Test func theLicencesAreTheBundledTexts() throws {
        #expect(AppTabModel.licences.map(\.name) == ["IBM Plex Sans", "SQLCipher Community Edition"])
        #expect(
            AppTabModel.licences.map(\.detail)
                == ["písmo faktur · SIL Open Font License 1.1", "šifrování databáze · licence BSD"])
        for licence in AppTabModel.licences {
            let text = try #require(licence.text())
            #expect(!text.isEmpty)
        }
        #expect(try #require(AppTabModel.licences[1].text()).contains("ZETETIC LLC"))
        #expect(AppTabModel.versionLine("1.0") == "InvoicesTracker 1.0 · data jen v tomto Macu")
    }
}
