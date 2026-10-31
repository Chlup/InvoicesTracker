import Foundation
import Testing
@testable import InvoicesTracker

/// The form of an invoice template: what it starts with, what its descriptions come to, which bank account its invoices
/// print, what it says is wrong, and what saving and deleting it write.
@Suite(.settlesBackups)
@MainActor
struct TemplateFormModelTests {
    /// A form on a new template that has loaded its clients, with a name, which can be saved as it is.
    private func newForm(_ f: ClientsFixture, name: String = "Měsíční vývoj") async -> TemplateFormModel {
        let model = TemplateFormModel(app: f.app, template: nil)
        await model.load()
        model.name = name
        return model
    }

    // MARK: The previews

    @Test func theDescriptionOfANewTemplateIsFilledInForTheDUZP() async throws {
        try await ClientsFixture.with { f in
            let model = TemplateFormModel(app: f.app, template: nil)

            #expect(model.items.map(\.description) == ["Vývoj – {měsíc} {rok}"])
            #expect(model.preview(duzp: civilDate("2026-09-30")) == "Vývoj – září 2026")
        }
    }

    @Test func thePlaceholdersInEnglishAndTheYearAreFilledInToo() async throws {
        try await ClientsFixture.with { f in
            let model = TemplateFormModel(app: f.app, template: nil)
            model.items[0].description = "Development {month} {year} / {měsíc} {rok} / {MONTH}"

            #expect(
                model.preview(duzp: civilDate("2026-01-31")) == "Development January 2026 / leden 2026 / {MONTH}")
        }
    }

    @Test func anItemWithoutADescriptionPreviewsAsADash() async throws {
        try await ClientsFixture.with { f in
            let model = TemplateFormModel(app: f.app, template: nil)
            model.items[0].description = "   "

            #expect(model.preview(duzp: civilDate("2026-09-30")) == "—")
            #expect(model.preview(ofItem: 7, duzp: civilDate("2026-09-30")) == "—")
        }
    }

    @Test func everyItemHasALineOfItsOwnInThePreview() async throws {
        try await ClientsFixture.with { f in
            let model = TemplateFormModel(app: f.app, template: nil)
            model.addItem()
            model.items[1].description = " Hosting {month} "
            model.addItem()

            let day = civilDate("2026-09-30")

            #expect(model.preview(duzp: day) == "Vývoj – září 2026\nHosting September\n—")
            #expect(model.preview(ofItem: 1, duzp: day) == "Hosting September")
        }
    }

    /// The line under the description of the first item is its preview and, after it, what the descriptions may hold;
    /// the lines of the other items are their previews alone, as that is said once. The previews are for the DUZP a
    /// new invoice starts with: today is 17. 10. 2026, so the end of October.
    @Test func thePreviewLineOfTheFirstItemEndsWithWhatTheDescriptionsMayHold() async throws {
        try await ClientsFixture.with { f in
            let model = TemplateFormModel(app: f.app, template: nil)
            model.addItem()
            model.items[1].description = "Hosting {month}"
            model.addItem()

            #expect(
                model.previewLine(ofItem: 0)
                    == "Náhled: Vývoj – říjen 2026 · {měsíc}, {rok}, {month} a {year} se doplní podle DUZP")
            #expect(model.previewLine(ofItem: 1) == "Náhled: Hosting October")
            #expect(model.previewLine(ofItem: 2) == "Náhled: —")
            #expect(TemplateFormModel.previewHint == "{měsíc}, {rok}, {month} a {year} se doplní podle DUZP")

            model.removeItem(at: 0)
            #expect(
                model.previewLine(ofItem: 0)
                    == "Náhled: Hosting October · {měsíc}, {rok}, {month} a {year} se doplní podle DUZP")

            // A first item without a description previews as a dash, and the line still says what one may hold.
            model.items[0].description = "  "
            #expect(
                model.previewLine(ofItem: 0) == "Náhled: — · {měsíc}, {rok}, {month} a {year} se doplní podle DUZP")
        }
    }

    @Test func thePreviewUsesRealCurrentMonthEvenWhenAnotherYearIsSelected() async throws {
        try await ClientsFixture.with { f in
            let model = TemplateFormModel(app: f.app, template: nil)

            // Today is 17. 10. 2026.
            #expect(model.previewDay == civilDate("2026-10-31"))
            #expect(model.preview(duzp: model.previewDay) == "Vývoj – říjen 2026")
            f.app.selectYear(2025)
            #expect(model.previewDay == civilDate("2026-10-31"))
        }
    }

    // MARK: A new template

    @Test func aNewTemplateStartsWithTheFirstClientAndItsTerms() async throws {
        try await ClientsFixture.with { f in
            let model = TemplateFormModel(app: f.app, template: nil)
            #expect(model.isNew)
            #expect(model.title == "Nová šablona")
            #expect(model.subtitle == "Šablona předvyplní odběratele, položku, cenu, DPH a splatnost.")
            #expect(model.clientID == 0)

            await model.load()

            // Alfa comes before Bravo by name.
            #expect(model.clientID == f.alfaID)
            #expect(model.clients.map(\.name) == ["Alfa Systems s.r.o.", "Bravo Labs, Inc."])
            #expect(model.vatMode == .domestic21)
            #expect(model.dueDaysText == "14")
            #expect(model.currencyCode == "CZK")
            #expect(model.name == "")
            #expect(model.note == "")
            #expect(model.items.count == 1)
            #expect(model.items[0].quantityText == "1")
            #expect(model.items[0].unit == "hod")
            #expect(model.items[0].unitPriceText == "")
        }
    }

    /// The form of a new template for a client, which Nová šablona in the detail of the client opens, starts with that
    /// client, its VAT mode and its due days, and keeps them once it has loaded the clients, where the form of a new
    /// template takes the first of them otherwise. The rest is that of any new template.
    @Test func aNewTemplateForAClientStartsWithThatClientAndItsTermsAndKeepsThem() async throws {
        try await ClientsFixture.with { f in
            let bravo = try await f.storedClient(f.bravoID)
            let model = TemplateFormModel(app: f.app, preselectedClient: bravo)
            #expect(model.isNew)
            #expect(model.title == "Nová šablona")
            #expect(model.clientID == f.bravoID)
            #expect(model.vatMode == .outsideCountry)
            #expect(model.dueDaysText == "30")

            await model.load()

            // Alfa comes before Bravo by name, and is not taken.
            #expect(model.clientID == f.bravoID)
            #expect(model.pickedClient?.name == "Bravo Labs, Inc.")
            #expect(model.vatMode == .outsideCountry)
            #expect(model.dueDaysText == "30")
            #expect(model.currencyCode == "USD")
            #expect(model.name == "")
            #expect(model.items.map(\.description) == ["Vývoj – {měsíc} {rok}"])
        }
    }

    @Test func choosingAClientAppliesItsVATModeAndDueDaysAndItsCurrencyShowsInThePrice() async throws {
        try await ClientsFixture.with { f in
            let model = await newForm(f)

            model.pickClient(f.bravoID)

            #expect(model.clientID == f.bravoID)
            #expect(model.vatMode == .outsideCountry)
            #expect(model.dueDaysText == "30")
            #expect(model.currencyCode == "USD")
        }
    }

    @Test func choosingTheClientThatIsChosenOrOneThatIsNotThereChangesNothing() async throws {
        try await ClientsFixture.with { f in
            let model = await newForm(f)
            model.vatMode = .none
            model.dueDaysText = "7"

            model.pickClient(f.alfaID)
            model.pickClient(999)

            #expect(model.clientID == f.alfaID)
            #expect(model.vatMode == .none)
            #expect(model.dueDaysText == "7")
        }
    }

    @Test func aNewTemplateWithoutClientsHasNoneToChooseAndSaysSo() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let app = makeAppModel(in: directory)
        try await startFresh(app)
        let model = TemplateFormModel(app: app, template: nil)
        await model.load()
        model.name = "Měsíční vývoj"

        #expect(model.clients.isEmpty)
        #expect(model.clientID == 0)
        #expect(model.errors == ["Vyberte odběratele."])
    }

    // MARK: A stored template

    @Test func aStoredTemplateStartsWithWhatItHasAndItsDescriptionsAreNotFilledIn() async throws {
        try await ClientsFixture.with { f in
            var template = ClientsFixture.template(for: f.bravoID, name: "Služby pro Bravo")
            template.items.append(
                TemplateItem(description: "Hosting", quantity: decimal("1"), unit: "ks", unitPriceMinor: 125_050))
            template.vatMode = .none
            template.dueDays = 7
            template.duzpAtMonthEnd = false
            template.note = "Platba do 7 dní.\nDěkuji."
            let stored = try await f.store(template)

            let model = TemplateFormModel(app: f.app, template: stored)
            await model.load()

            #expect(!model.isNew)
            #expect(model.title == "Upravit šablonu")
            #expect(model.subtitle == "Služby pro Bravo")
            #expect(model.name == "Služby pro Bravo")
            #expect(model.clientID == f.bravoID)
            #expect(model.items.map(\.description) == ["Služby {měsíc} {rok}", "Hosting"])
            #expect(model.items.map(\.quantityText) == ["7,5", "1"])
            #expect(model.items.map(\.unit) == ["hod", "ks"])
            #expect(model.items.map(\.unitPriceText) == ["600,00", "1\u{00A0}250,50"])
            // The client chosen before does not overwrite what the template has.
            #expect(model.vatMode == .none)
            #expect(model.dueDaysText == "7")
            #expect(model.note == "Platba do 7 dní.\nDěkuji.")
            #expect(model.errors.isEmpty)
        }
    }

    @Test func aTemplateWithoutItemsOpensWithABlankOne() async throws {
        try await ClientsFixture.with { f in
            var template = ClientsFixture.template(for: f.alfaID)
            template.items = []
            let stored = try await f.store(template)

            let model = TemplateFormModel(app: f.app, template: stored)

            #expect(model.items.count == 1)
        }
    }

    @Test func aTemplateWithoutAnIdIsANewOne() async throws {
        try await ClientsFixture.with { f in
            let model = TemplateFormModel(app: f.app, template: ClientsFixture.template(for: f.alfaID))

            #expect(model.isNew)
        }
    }

    // MARK: The items

    @Test func itemsAreAddedUpToTheLimitAndTheLastOneStays() async throws {
        try await ClientsFixture.with { f in
            let model = TemplateFormModel(app: f.app, template: nil)

            model.removeItem(at: 0)
            #expect(model.items.count == 1)

            for _ in 1..<EditorLimits.items {
                model.addItem()
            }
            #expect(model.items.count == 12 && !model.canAddItem)
            model.addItem()
            #expect(model.items.count == 12)

            model.removeItem(at: 3)
            model.removeItem(at: 40)
            #expect(model.items.count == 11 && model.canAddItem)
        }
    }

    @Test func anAddedItemIsOfOneUnitOfTheKindOfTheOneAbove() async throws {
        try await ClientsFixture.with { f in
            let model = TemplateFormModel(app: f.app, template: nil)
            model.items[0].unit = "měs."

            model.addItem()

            #expect(model.items[1].description == "")
            #expect(model.items[1].quantityText == "1")
            #expect(model.items[1].unit == "měs.")
            #expect(model.items[1].unitPriceText == "")
        }
    }

    // MARK: The bank account

    /// The accounts of Nastavení › Moje údaje, one for each currency: the name and address of the bank is in the data,
    /// and no line shows it.
    private let crownAccount = BankAccount(
        currency: .czk, accountNumber: "2000123456/2010", iban: "CZ6520100000002000123456")
    private let dollarAccount = BankAccount(
        currency: .usd, accountNumber: "123456789", routingNumber: "021000021", accountType: "Checking",
        bankNameAndAddress: "Chase Bank, 270 Park Ave, New York")
    private let euroAccount = BankAccount(currency: .eur, iban: "DE89370400440532013000", bic: "COBADEFFXXX")

    @Test func theTemplateShowsTheAccountOfItsCurrency() async throws {
        try await ClientsFixture.with { f in
            try await f.database.saveBankAccounts([crownAccount, dollarAccount, euroAccount])
            let euroClient = try await f.store(ClientsFixture.imported)
            let model = await newForm(f)

            // The first client, Alfa, is in crowns.
            #expect(model.accountLine == .account("2000123456/2010 · IBAN CZ6520100000002000123456"))

            model.pickClient(f.bravoID)
            #expect(model.accountLine == .account("123456789 · routing 021000021"))

            model.pickClient(euroClient.id)
            #expect(model.accountLine == .account("IBAN DE89370400440532013000 · BIC COBADEFFXXX"))
        }
    }

    @Test func theTemplateSaysWhenItsCurrencyHasNoAccount() async throws {
        try await ClientsFixture.with { f in
            try await f.database.saveBankAccounts([crownAccount, dollarAccount])
            let euroClient = try await f.store(ClientsFixture.imported)
            let model = await newForm(f)

            model.pickClient(euroClient.id)

            #expect(model.accountLine == .missing(.eur))
            #expect(model.accountLine.text == "Pro měnu EUR nemáte účet – doplníte ho v Nastavení › Moje údaje.")
        }
    }

    @Test func aStoredTemplateShowsTheAccountOfItsOwnClientNotOfTheFirstOne() async throws {
        try await ClientsFixture.with { f in
            try await f.database.saveBankAccounts([crownAccount, dollarAccount])
            let stored = try await f.store(ClientsFixture.template(for: f.bravoID))
            let model = TemplateFormModel(app: f.app, template: stored)

            await model.load()

            #expect(model.accountLine == .account("123456789 · routing 021000021"))
        }
    }

    @Test func theAccountLineSaysWhatTheAccountIsAndNothingElse() {
        let line = TemplateAccountLine.account("2000123456/2010 · IBAN CZ6520100000002000123456")
        let imported = TemplateAccountLine.importedAccount("12345678 · IBAN GB33BUKB20201555555555")

        #expect(line.text == "2000123456/2010 · IBAN CZ6520100000002000123456")
        #expect(imported.text == "12345678 · IBAN GB33BUKB20201555555555")
    }

    /// Where the account comes from is said of an account: an account of Nastavení › Moje údaje comes from there, by
    /// the currency of the invoice, and one in a currency that it has no boxes for comes from the imported data. A
    /// line that says there is none, or that the app keeps none, has no account to say it of.
    @Test func theSourceHintSaysWhereTheAccountComesFrom() throws {
        let pounds = try #require(CurrencyCode("GBP"))

        #expect(
            TemplateAccountLine.account("2000123456/2010 · IBAN CZ6520100000002000123456").sourceHint
                == "Tiskne se účet z Nastavení › Moje údaje podle měny faktury.")
        #expect(
            TemplateAccountLine.importedAccount("12345678 · IBAN GB33BUKB20201555555555").sourceHint
                == "Tiskne se účet z importovaných dat. V Nastavení › Moje údaje ho neupravíte.")
        #expect(TemplateAccountLine.missing(.czk).sourceHint == nil)
        #expect(TemplateAccountLine.notKept(pounds).sourceHint == nil)
    }

    /// A field that its invoices do not print is not on the line, and one that the account does not have, or has with
    /// nothing but white space, is left out.
    @Test func theLineHasTheFieldsOfTheAccountThatItsInvoicesPrint() {
        let crowns = BankAccount(
            currency: .czk, accountNumber: " 2000123456/2010 ", bic: "KOMBCZPP", routingNumber: "021000021")
        let dollars = BankAccount(currency: .usd, accountNumber: "123456789", iban: "CZ6520100000002000123456")
        let euros = BankAccount(currency: .eur, iban: "DE89370400440532013000", bic: "  ")

        #expect(TemplateAccountLine(currency: .czk, accounts: [crowns]) == .account("2000123456/2010"))
        #expect(TemplateAccountLine(currency: .usd, accounts: [dollars]) == .account("123456789"))
        #expect(TemplateAccountLine(currency: .eur, accounts: [euros]) == .account("IBAN DE89370400440532013000"))
    }

    @Test func anAccountWithNothingInItsInvoicesPrintIsNoAccount() {
        // What "+ Přidat účet v eurech" adds, before anything is typed in it.
        let added = BankAccount(currency: .eur)
        let crowns = BankAccount(currency: .czk, bic: "KOMBCZPP", routingNumber: "021000021")

        #expect(TemplateAccountLine(currency: .eur, accounts: [added]) == .missing(.eur))
        #expect(TemplateAccountLine(currency: .czk, accounts: [crowns]) == .missing(.czk))
    }

    @Test func theAccountOfAnotherCurrencyIsNeverTheLine() {
        let accounts = [crownAccount, euroAccount]

        #expect(TemplateAccountLine(currency: .usd, accounts: accounts) == .missing(.usd))
        #expect(TemplateAccountLine(currency: .czk, accounts: []) == .missing(.czk))
    }

    /// An account in pounds with every number, as data the app did not make itself could hold one.
    private func poundAccount() throws -> BankAccount {
        BankAccount(
            currency: try #require(CurrencyCode("GBP")), accountNumber: "12345678", iban: "GB33BUKB20201555555555",
            bic: "BUKBGB22", routingNumber: "200000", bankNameAndAddress: "Barclays, 1 Churchill Place, London")
    }

    /// A client in pounds, as an import brings one: Echo Ltd in London.
    private func britishClient() throws -> Client {
        var british = ClientsFixture.imported
        british.name = "Echo Ltd"
        british.country = "GB"
        british.currency = try #require(CurrencyCode("GBP"))
        british.vatMode = .outsideCountry
        return british
    }

    /// Nastavení › Moje údaje has boxes for accounts in crowns, dollars and euros alone, but imported data can hold an
    /// account in pounds. A template for a client in pounds shows it, as its invoices print it, and says that it comes
    /// from the imported data.
    @Test func aTemplateInPoundsShowsTheAccountInPoundsThatTheDataHolds() async throws {
        try await ClientsFixture.with { f in
            try await f.database.saveBankAccounts([crownAccount, dollarAccount, euroAccount, try poundAccount()])
            let client = try await f.store(try britishClient())
            let model = await newForm(f)

            model.pickClient(client.id)

            #expect(
                model.accountLine
                    == .importedAccount("12345678 · IBAN GB33BUKB20201555555555 · BIC BUKBGB22 · routing 200000"))
            #expect(
                model.accountLine.sourceHint
                    == "Tiskne se účet z importovaných dat. V Nastavení › Moje údaje ho neupravíte.")
            #expect(printedAccount(of: Invoice.fixture(currency: client.currency), accounts: model.accounts) == [
                "12345678", "GB33BUKB20201555555555", "BUKBGB22", "200000",
            ])
        }
    }

    /// Without an account in pounds, which Nastavení › Moje údaje has no box for, a template for a client in pounds
    /// says that the app keeps none and that its invoices print none, as they do.
    @Test func aTemplateInPoundsWithoutAnAccountSaysThatItsInvoicesPrintNone() async throws {
        try await ClientsFixture.with { f in
            try await f.database.saveBankAccounts([crownAccount, dollarAccount, euroAccount])
            let client = try await f.store(try britishClient())
            let model = await newForm(f)

            model.pickClient(client.id)

            #expect(model.accountLine == .notKept(client.currency))
            #expect(
                model.accountLine.text
                    == "Pro měnu GBP aplikace účet nevede – faktura se vytiskne bez bankovního účtu.")
            #expect(printedAccount(of: Invoice.fixture(currency: client.currency), accounts: model.accounts).isEmpty)
        }
    }

    /// Under that line, which says the app keeps no account in pounds, the form does not say where an account comes
    /// from: its invoices print none.
    @Test func aTemplateInPoundsWithoutAnAccountHasNoSourceHintToShow() async throws {
        try await ClientsFixture.with { f in
            try await f.database.saveBankAccounts([crownAccount, dollarAccount, euroAccount])
            let client = try await f.store(try britishClient())
            let model = await newForm(f)

            model.pickClient(client.id)

            #expect(model.accountLine == .notKept(client.currency))
            #expect(model.accountLine.sourceHint == nil)
        }
    }

    /// As on the invoice, a currency that has no layout of its own shows whatever numbers its account has.
    @Test func anAccountInAnotherCurrencyShowsWhatNumbersItHas() throws {
        #expect(
            TemplateAccountLine(currency: try #require(CurrencyCode("GBP")), accounts: [try poundAccount()])
                == .importedAccount("12345678 · IBAN GB33BUKB20201555555555 · BIC BUKBGB22 · routing 200000"))
    }

    /// For every currency a client can be in — crowns, dollars and euros, and every other one the ČNB quotes — the line
    /// of the template shows what the page of an invoice in it prints of the account: the same numbers in the same
    /// order, or no account when it prints none. So it is with an account of every currency that has every number, with
    /// accounts that have the number alone, and with none. The account is one of Nastavení › Moje údaje in the three
    /// currencies that it has boxes for, and an imported one in every other.
    @Test func theLineShowsWhatTheInvoicePrintsInEveryCurrency() throws {
        let currencies = ClientFormModel.currencyChoices(
            cached: Set(try cnbYearlyRows([2026]).map(\.currency)), including: .czk)
        #expect(currencies.count > 3)
        for currency in currencies {
            let full = BankAccount(
                currency: currency, accountNumber: " 2000123456/2010 ", iban: "CZ6520100000002000123456",
                bic: "KOMBCZPP", routingNumber: "021000021", accountType: "Checking",
                bankNameAndAddress: "Banka, Na Příkopě 33, Praha")
            let numberAlone = BankAccount(currency: currency, accountNumber: "123456789")
            for accounts in [[full], [numberAlone], []] {
                let line = TemplateAccountLine(currency: currency, accounts: accounts)
                let printed = printedAccount(of: Invoice.fixture(currency: currency), accounts: accounts)
                switch line {
                case .account(let text):
                    #expect([CurrencyCode.czk, .eur, .usd].contains(currency), "\(currency) \(accounts)")
                    #expect(Self.numbers(of: text) == printed, "\(currency) \(accounts)")
                case .importedAccount(let text):
                    #expect(![CurrencyCode.czk, .eur, .usd].contains(currency), "\(currency) \(accounts)")
                    #expect(Self.numbers(of: text) == printed, "\(currency) \(accounts)")
                case .missing, .notKept:
                    #expect(printed.isEmpty, "\(currency) \(accounts)")
                }
            }
        }
    }

    /// The numbers of the account that the page of `invoice` prints with `accounts`: the values of its rows before the
    /// reference of the payment.
    private func printedAccount(of invoice: Invoice, accounts: [BankAccount]) -> [String] {
        let text = InvoiceDocument.make(invoice: invoice, supplier: Supplier(), accounts: accounts).text
        return text.paymentRows.prefix { $0.label != text.labels.reference }.map(\.value)
    }

    /// The numbers on the line of an account, "2000123456/2010 · IBAN CZ65…", without the words that name them.
    private static func numbers(of line: String) -> [String] {
        line.components(separatedBy: " · ").map { part in
            for label in ["IBAN ", "BIC ", "routing "] where part.hasPrefix(label) {
                return String(part.dropFirst(label.count))
            }
            return part
        }
    }

    // MARK: What is wrong

    @Test func aNameAndAClientAreNeeded() async throws {
        try await ClientsFixture.with { f in
            let model = TemplateFormModel(app: f.app, template: nil)

            #expect(model.errors == ["Vyplňte název šablony.", "Vyberte odběratele."])

            await model.load()
            #expect(model.errors == ["Vyplňte název šablony."])

            model.name = "  Měsíční vývoj "
            #expect(model.errors.isEmpty)
        }
    }

    @Test(arguments: [
        ("1", true), ("6,5", true), ("6.5", true), ("0,25", true), ("0", false), ("-1", false), ("", false),
        ("abc", false), ("6,5 h", false), ("1 000 000", false),
    ])
    func aQuantityIsANumberAboveZero(quantity: String, fine: Bool) async throws {
        try await ClientsFixture.with { f in
            let model = await newForm(f)
            model.items[0].quantityText = quantity

            #expect(model.errors == (fine ? [] : ["Položka 1: zadejte počet větší než nula."]))
        }
    }

    @Test(arguments: [
        ("", true), ("0", true), ("800", true), ("13 340,50", true), ("1.5", true), ("−12,5", true),
        ("12,345", false), ("1.234,50", false), ("abc", false), ("12 50", false),
    ])
    func aPriceIsEmptyOrAnAmount(price: String, fine: Bool) async throws {
        try await ClientsFixture.with { f in
            let model = await newForm(f)
            model.addItem()
            model.items[1].unitPriceText = price

            #expect(
                model.errors
                    == (fine ? [] : ["Položka 2: zadejte cenu za MJ ve tvaru 13 340 nebo 13 340,50."]))
        }
    }

    @Test func theItemsSayTheirOwnMessagesUnderTheirFieldsToo() async throws {
        try await ClientsFixture.with { f in
            let model = await newForm(f)
            model.items[0].quantityText = "x"
            model.items[0].unitPriceText = "y"

            #expect(model.items[0].quantityError == "Zadejte počet, například 6,5.")
            #expect(model.items[0].priceError == "Zadejte částku ve tvaru 13 340 nebo 13 340,50.")
        }
    }

    @Test func theDueDaysAndTheNoteHaveLimitsToo() async throws {
        try await ClientsFixture.with { f in
            let model = await newForm(f)
            model.dueDaysText = "1000"
            model.note = (1...21).map { "Řádek \($0)" }.joined(separator: "\n")

            #expect(model.errors == ["Splatnost musí být 0 až 999 dní.", "Poznámka může mít nejvýše 20 řádků."])

            model.dueDaysText = "999"
            model.note = (1...20).map { "Řádek \($0)" }.joined(separator: "\n")
            #expect(model.errors.isEmpty)
        }
    }

    @Test func theErrorsShowOnlyOnceASaveWasTried() async throws {
        try await ClientsFixture.with { f in
            let model = TemplateFormModel(app: f.app, template: nil)
            #expect(!model.showsErrors)

            await #expect(throws: FormSaveError.invalid) { try await model.save() }

            #expect(model.showsErrors)
        }
    }

    // MARK: Saving

    @Test func savingANewTemplateStoresItWithItsItemsAndTellsTheApp() async throws {
        try await ClientsFixture.with { f in
            let model = await newForm(f, name: "  Služby pro Bravo ")
            model.pickClient(f.bravoID)
            model.items[0].description = " Software development {month} {year} "
            model.items[0].quantityText = "176"
            model.items[0].unit = "h"
            model.items[0].unitPriceText = "70,00"
            model.addItem()
            model.items[1].description = "Hosting"
            model.items[1].quantityText = "0,5"
            model.items[1].unit = "měs."
            model.items[1].unitPriceText = "1 250,50"
            model.note = "\nPayment due within 30 days.\n"
            let version = f.app.dataVersion

            let id = try await model.save()

            #expect(
                try await f.database.templates() == [
                    InvoiceTemplate(
                        id: id, name: "Služby pro Bravo", clientID: f.bravoID,
                        items: [
                            TemplateItem(
                                description: "Software development {month} {year}", quantity: decimal("176"),
                                unit: "h", unitPriceMinor: 7_000),
                            TemplateItem(
                                description: "Hosting", quantity: decimal("0.5"), unit: "měs.",
                                unitPriceMinor: 125_050),
                        ],
                        vatMode: .outsideCountry, dueDays: 30, duzpAtMonthEnd: true,
                        note: "Payment due within 30 days.")
                ])
            #expect(f.app.dataVersion == version + 1)
        }
    }

    @Test func anItemWithoutAPriceIsStoredFreeToBePricedOnTheInvoice() async throws {
        try await ClientsFixture.with { f in
            let model = await newForm(f)

            let id = try await model.save()

            let template = try #require(try await f.database.templates().first { $0.id == id })
            #expect(template.items.map(\.unitPriceMinor) == [0])
            #expect(template.items.map(\.description) == ["Vývoj – {měsíc} {rok}"])
        }
    }

    @Test func savingAStoredTemplateChangesItInPlaceAndReplacesItsItems() async throws {
        try await ClientsFixture.with { f in
            var legacy = ClientsFixture.template(for: f.alfaID)
            legacy.duzpAtMonthEnd = false
            let stored = try await f.store(legacy)
            let other = try await f.store(ClientsFixture.template(for: f.bravoID, name: "Druhá"))
            let model = TemplateFormModel(app: f.app, template: stored)
            await model.load()
            model.name = "Roční licence"
            model.items = [
                EditableItem(description: "Licence {rok}", quantityText: "12", unit: "měs.", unitPriceText: "999")
            ]
            model.pickClient(f.bravoID)
            model.vatMode = .domestic12

            let id = try await model.save()

            #expect(id == stored.id)
            var expected = stored
            expected.name = "Roční licence"
            expected.items = [
                TemplateItem(
                    description: "Licence {rok}", quantity: decimal("12"), unit: "měs.", unitPriceMinor: 99_900)
            ]
            expected.clientID = f.bravoID
            // Choosing the client applied its terms, and the VAT mode typed after it is the one that counts.
            expected.vatMode = .domestic12
            expected.dueDays = 30
            #expect(try await f.database.templates() == [expected, other])
            // Editing supported fields preserves the legacy value that the form no longer exposes.
            #expect(try await f.database.templates().first { $0.id == id }?.duzpAtMonthEnd == false)
        }
    }

    @Test func aFormThatIsNotRightWritesNothing() async throws {
        try await ClientsFixture.with { f in
            let model = await newForm(f)
            model.items[0].unitPriceText = "12,345"
            let version = f.app.dataVersion
            let writes = await f.database.writeCount

            await #expect(throws: FormSaveError.invalid) { try await model.save() }

            let templates = try await f.database.templates()
            #expect(templates.isEmpty)
            #expect(f.app.dataVersion == version)
            #expect(await f.database.writeCount == writes)
        }
    }

    @Test func aTemplateThatWasDeletedMeanwhileIsNotBroughtBack() async throws {
        try await ClientsFixture.with { f in
            let stored = try await f.store(ClientsFixture.template(for: f.alfaID))
            let model = TemplateFormModel(app: f.app, template: stored)
            await model.load()
            model.name = "Přejmenovaná"
            try await f.database.deleteTemplate(id: stored.id)
            let version = f.app.dataVersion

            await #expect(throws: TemplateError.notFound) { try await model.save() }

            #expect(model.failure == "Šablona mezitím byla smazána.")
            #expect(try await f.database.templates().isEmpty)
            #expect(f.app.dataVersion == version)
        }
    }

    /// The template is a new one, or one that is stored for another client and is moved to the client that is deleted.
    @Test(arguments: [false, true])
    func aClientThatWasDeletedMeanwhileIsNotBroughtBackEitherAndTheTemplateIsNotSaved(storedTemplate: Bool)
        async throws
    {
        try await ClientsFixture.with { f in
            let stored = storedTemplate ? try await f.store(ClientsFixture.template(for: f.alfaID)) : nil
            let model = TemplateFormModel(app: f.app, template: stored)
            await model.load()
            model.name = "Měsíční vývoj"
            model.pickClient(f.bravoID)
            try await f.deleteClient(f.bravoID)
            let version = f.app.dataVersion

            await #expect(throws: (any Error).self) { try await model.save() }

            #expect(model.failure == "Odběratel mezitím byl smazán.")
            #expect(try await f.database.templates() == (stored.map { [$0] } ?? []))
            #expect(f.app.dataVersion == version)
        }
    }

    @Test func aTemplateGoesWithItsClientWhenTheClientIsDeleted() async throws {
        try await ClientsFixture.with { f in
            let stored = try await f.store(ClientsFixture.template(for: f.bravoID))
            let model = TemplateFormModel(app: f.app, template: stored)
            await model.load()
            try await f.deleteClient(f.bravoID)

            await #expect(throws: TemplateError.notFound) { try await model.save() }

            #expect(model.failure == "Šablona mezitím byla smazána.")
        }
    }

    @Test func aSaveThatFailsSaysSoAndTheNextOneStartsAfresh() async throws {
        try await ClientsFixture.with { f in
            let model = await newForm(f)
            try await setDatabaseReadOnly(true, f.database)

            await #expect(throws: (any Error).self) { try await model.save() }

            #expect(model.failure == "Šablonu se nepodařilo uložit.")
            try await setDatabaseReadOnly(false, f.database)
            try await model.save()
            #expect(model.failure == nil)
            #expect(try await f.database.templates().count == 1)
        }
    }

    @Test func aSaveInAFormThatLostTheDataFindsItLocked() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let app = makeAppModel(in: directory)
        let model = TemplateFormModel(app: app, template: nil)

        await model.load()
        #expect(model.loadFailed)
        model.name = "Měsíční vývoj"
        model.clientID = 1

        await #expect(throws: VaultError.locked) { try await model.save() }

        #expect(model.failure == "Data jsou zamčená. Nejdřív je odemkněte.")
    }

    @Test func aDeletionInAFormThatLostTheDataFindsItLocked() async throws {
        try await ClientsFixture.with { f in
            let stored = try await f.store(ClientsFixture.template(for: f.alfaID))
            let model = TemplateFormModel(app: f.app, template: stored)
            f.app.database = nil

            await #expect(throws: VaultError.locked) { try await model.delete() }

            #expect(model.failure == "Data jsou zamčená. Nejdřív je odemkněte.")
        }
    }

    @Test func aSecondSaveWhileOneIsRunningIsRefused() async throws {
        try await ClientsFixture.with { f in
            let model = await newForm(f)
            #expect(model.isWorking == false)

            // The first save has begun, and waits for the data, when its task is made.
            let first = Task.immediate { try await model.save() }
            #expect(model.isWorking)
            await #expect(throws: FormSaveError.alreadySaving) { try await model.save() }
            let id = try await first.value

            #expect(model.isWorking == false)
            #expect(model.failure == nil)
            let templates = try await f.database.templates()
            #expect(templates.map(\.id) == [id])
        }
    }

    @Test func aDeletionWhileASaveIsRunningIsRefusedAndSoIsASaveWhileADeletionIsRunning() async throws {
        try await ClientsFixture.with { f in
            let stored = try await f.store(ClientsFixture.template(for: f.alfaID))
            let model = TemplateFormModel(app: f.app, template: stored)
            await model.load()

            let saving = Task.immediate { try await model.save() }
            #expect(model.isWorking)
            await #expect(throws: FormSaveError.alreadySaving) { try await model.delete() }
            _ = try await saving.value
            #expect(try await f.database.templates().map(\.id) == [stored.id])

            let deleting = Task.immediate { try await model.delete() }
            #expect(model.isWorking)
            await #expect(throws: FormSaveError.alreadySaving) { try await model.save() }
            try await deleting.value
            #expect(try await f.database.templates().isEmpty)
        }
    }

    // MARK: Deleting

    @Test func deletingATemplateAsksByNameAndRemovesItAndTellsTheApp() async throws {
        try await ClientsFixture.with { f in
            let stored = try await f.store(ClientsFixture.template(for: f.alfaID, name: "Služby pro Alfa"))
            let other = try await f.store(ClientsFixture.template(for: f.bravoID, name: "Druhá"))
            let model = TemplateFormModel(app: f.app, template: stored)
            #expect(model.deleteTitle == "Smazat šablonu „Služby pro Alfa“?")
            #expect(
                TemplateFormModel.deleteMessage
                    == "Faktury, které z ní už vznikly, zůstanou, jak jsou. Smazání nejde vrátit zpět.")
            let version = f.app.dataVersion

            try await model.delete()

            #expect(try await f.database.templates() == [other])
            #expect(try await f.database.integer("SELECT count(*) FROM template_item") == 1)
            #expect(f.app.dataVersion == version + 1)
        }
    }

    /// Smazat šablonu asks in a box of the form itself, not in an alert over the sheet: nothing is deleted until the
    /// box is answered, Zrušit in it deletes nothing, and the deletion closes it.
    @Test func deletingATemplateAsksInline() async throws {
        try await ClientsFixture.with { f in
            let stored = try await f.store(ClientsFixture.template(for: f.alfaID, name: "Služby pro Alfa"))
            let model = TemplateFormModel(app: f.app, template: stored)
            await model.load()
            #expect(!model.confirmsDeletion)

            model.askToDelete()

            #expect(model.confirmsDeletion)
            #expect(try await f.database.templates() == [stored])

            model.cancelDeletion()

            #expect(!model.confirmsDeletion)
            #expect(try await f.database.templates() == [stored])

            model.askToDelete()
            try await model.delete()

            #expect(!model.confirmsDeletion)
            #expect(try await f.database.templates().isEmpty)
        }
    }

    /// A new template has nothing to delete, so nothing is asked; nor while a save runs.
    @Test func nothingIsAskedForANewTemplateNorWhileASaveRuns() async throws {
        try await ClientsFixture.with { f in
            let new = await newForm(f)
            new.askToDelete()
            #expect(!new.confirmsDeletion)

            let stored = try await f.store(ClientsFixture.template(for: f.alfaID))
            let model = TemplateFormModel(app: f.app, template: stored)
            await model.load()
            let saving = Task.immediate { try await model.save() }
            #expect(model.isWorking)
            model.askToDelete()
            #expect(!model.confirmsDeletion)
            _ = try await saving.value
        }
    }

    @Test func deletingATemplateThatIsGoneIsDeletedAsFarAsThePersonIsConcerned() async throws {
        try await ClientsFixture.with { f in
            let stored = try await f.store(ClientsFixture.template(for: f.alfaID))
            let model = TemplateFormModel(app: f.app, template: stored)
            try await f.database.deleteTemplate(id: stored.id)

            try await model.delete()

            #expect(model.failure == nil)
        }
    }

    @Test func aNewTemplateHasNothingToDelete() async throws {
        try await ClientsFixture.with { f in
            let model = await newForm(f)
            let version = f.app.dataVersion

            try await model.delete()

            #expect(f.app.dataVersion == version)
        }
    }

    @Test func aDeletionThatFailsSaysSoAndKeepsTheTemplate() async throws {
        try await ClientsFixture.with { f in
            let stored = try await f.store(ClientsFixture.template(for: f.alfaID))
            let model = TemplateFormModel(app: f.app, template: stored)
            try await setDatabaseReadOnly(true, f.database)
            let version = f.app.dataVersion

            await #expect(throws: (any Error).self) { try await model.delete() }

            #expect(model.failure == "Šablonu se nepodařilo smazat.")
            try await setDatabaseReadOnly(false, f.database)
            #expect(try await f.database.templates() == [stored])
            #expect(f.app.dataVersion == version)
        }
    }
}
