import Foundation
@testable import InvoicesTracker

/// A sole trader's data to predict a year's income from. Three clients: Foxtrot, Inc. (dollars, supplied outside the
/// country, 30 days to pay), Tango s.r.o. (crowns, 30 days) and Sierra, SE (crowns, 15 days); their invoices of 2024
/// to 2026 with the payments as the app stores them, in crowns, and Foxtrot's draft of October 2026; a template for
/// each client; and for 2024 to 2026 the planned advances, the deductions, the family and the expenses at 60 %. Today
/// is Saturday 17 October 2026, and a dollar costs 21,320 Kč, as the ČNB declared on Friday 16 October 2026. The tests
/// that use it expect figures that were worked out for the same data by a separate implementation. It is held in memory
/// (`input(year:)`, `yearInput(year:)`) and can be stored in the data of an app model (`store(in:)`).
///
/// The ids follow the order of the lists. Foxtrot, Tango and Sierra are the clients 1, 2 and 3, and their templates
/// have the same ids. The invoices of 2026 are 1 to 12, the draft last; then come Sierra's of 2024 (13 to 24) and of
/// 2025 (25 to 36), and Foxtrot's of 2025 (37 to 39).
enum PredictionSample {
    /// Saturday 17 October 2026.
    static let sampleToday = civilDate("2026-10-17")

    // MARK: Clients and templates

    static let foxtrot = Client(
        id: 1, name: "Foxtrot, Inc.", street: "100 Market Street", postcode: "94105", city: "San Francisco, CA",
        country: "US", currency: .usd, vatMode: .outsideCountry, dueDays: 30, language: .en)

    static let tango = Client(
        id: 2, name: "Tango s.r.o.", street: "Průmyslová 12", postcode: "301 00", city: "Plzeň", country: "CZ",
        currency: .czk, vatMode: .domestic21, dueDays: 30)

    static let sierra = Client(
        id: 3, name: "Sierra, SE", street: "Václavské náměstí 1", postcode: "110 00", city: "Praha",
        country: "CZ", currency: .czk, vatMode: .domestic21, dueDays: 15)

    static let clients = [foxtrot, tango, sierra]

    /// 172 hours at 70,00 USD for Foxtrot, 7,5 hours at 600,00 Kč for Tango and 168 hours at 1 250,00 Kč for Sierra.
    static let templates = [
        InvoiceTemplate(
            id: 1, name: "Foxtrot – měsíční vývoj", clientID: foxtrot.id,
            items: [hours("172", of: foxtrot, describedAs: "Software development")], vatMode: .outsideCountry,
            dueDays: 30),
        InvoiceTemplate(
            id: 2, name: "Tango – IT služby", clientID: tango.id,
            items: [hours("7.5", of: tango, describedAs: "IT služby")], vatMode: .domestic21, dueDays: 30),
        InvoiceTemplate(
            id: 3, name: "Sierra – hodiny", clientID: sierra.id,
            items: [hours("168", of: sierra, describedAs: "Vývoj – {měsíc} {rok}")], vatMode: .domestic21,
            dueDays: 15),
    ]

    /// `quantity` hours of the client's work at its price: 70,00 USD for Foxtrot, 600,00 Kč for Tango and 1 250,00 Kč
    /// for Sierra.
    private static func hours(_ quantity: String, of client: Client, describedAs description: String) -> TemplateItem {
        let unitPriceMinor: Int64 =
            switch client.id {
            case foxtrot.id: 7_000
            case tango.id: 60_000
            default: 125_000
            }
        let unit = client.id == foxtrot.id ? "h" : "hod"
        return TemplateItem(
            description: description, quantity: decimal(quantity), unit: unit, unitPriceMinor: unitPriceMinor)
    }

    // MARK: Invoices

    /// One invoice: `hours` of the client's work, issued, due and paid on the days given (`YYYY-MM-DD`). A dollar
    /// invoice gives the payment as stored, `paidHalere` at the ČNB rate `paymentRate` of the day it was paid, and the
    /// rate `issueRate` fixed when it was issued.
    private struct Entry {
        var number: String
        var client: Client
        var hours: String
        var issued: String
        var duzp: String?
        var due: String
        var paid: String?
        var paidHalere: Int64?
        var paymentRate: String?
        var issueRate: String?
        var isDraft = false
    }

    private static let entries2026 = [
        Entry(
            number: "2026-01-01", client: sierra, hours: "176", issued: "2026-01-31", due: "2026-02-15",
            paid: "2026-02-03"),
        Entry(
            number: "2026-02-01", client: sierra, hours: "152", issued: "2026-02-28", due: "2026-03-14",
            paid: "2026-03-03"),
        Entry(
            number: "2026-03-01", client: sierra, hours: "168", issued: "2026-03-31", due: "2026-04-15",
            paid: "2026-04-07"),
        // Paid before it was issued, as is the next one.
        Entry(
            number: "2026-04-01", client: sierra, hours: "168", issued: "2026-04-30", due: "2026-05-15",
            paid: "2026-04-10"),
        Entry(
            number: "2026-05-01", client: sierra, hours: "168", issued: "2026-05-29", duzp: "2026-05-31",
            due: "2026-06-15", paid: "2026-05-05"),
        Entry(
            number: "20260601", client: foxtrot, hours: "196", issued: "2026-06-30", due: "2026-07-30",
            paid: "2026-07-07", paidHalere: 28_880_600, paymentRate: "21.050", issueRate: "21.287"),
        Entry(
            number: "20260701", client: foxtrot, hours: "184", issued: "2026-07-31", due: "2026-08-30",
            paid: "2026-08-07", paidHalere: 26_880_560, paymentRate: "20.870", issueRate: "21.076"),
        Entry(
            number: "20260801", client: tango, hours: "7.5", issued: "2026-08-18", due: "2026-09-17",
            paid: "2026-08-26"),
        Entry(
            number: "20260802", client: foxtrot, hours: "190", issued: "2026-08-31", due: "2026-09-30",
            paid: "2026-09-09", paidHalere: 27_943_300, paymentRate: "21.010", issueRate: "20.800"),
        Entry(
            number: "20260901", client: foxtrot, hours: "205", issued: "2026-09-30", due: "2026-10-30",
            paid: "2026-10-02", paidHalere: 30_572_675, paymentRate: "21.305", issueRate: "21.359"),
        Entry(
            number: "20260902", client: tango, hours: "7.5", issued: "2026-09-30", due: "2026-10-30",
            paid: "2026-10-15"),
        Entry(
            number: "20261001", client: foxtrot, hours: "172", issued: "2026-10-31", due: "2026-11-30",
            isDraft: true),
    ]

    /// Sierra's hours of each month of 2024 and 2025.
    private static let sierraHours = [
        2024: ["170", "164", "178", "172", "182", "168", "158", "176", "174", "186", "170", "166"],
        2025: ["162", "150", "170", "164", "172", "158", "154", "174", "166", "178", "168", "172"],
    ]

    /// Sierra's invoices of `year`, 2024 or 2025: issued on the last day of each month, due in 15 days and paid in
    /// 5, so December 2024's on 5. 1. 2025. December 2025's is issued on 22. 12. and paid on 30. 12.
    private static func sierraEntries(of year: Int) -> [Entry] {
        let hours = sierraHours[year] ?? []
        return hours.enumerated().map { index, hours in
            let month = index + 1
            let monthText = month < 10 ? "0\(month)" : "\(month)"
            let isLate = year == 2025 && month == 12
            let issued = isLate ? civilDate("2025-12-22") : civilDate("\(year)-\(monthText)-01").endOfMonth
            let paid = isLate ? civilDate("2025-12-30") : issued.adding(days: 5)
            return Entry(
                number: "\(year)-\(monthText)-01", client: sierra, hours: hours, issued: issued.iso,
                due: issued.adding(days: 15).iso, paid: paid.iso)
        }
    }

    private static let foxtrotEntries2025 = [
        Entry(
            number: "20250902", client: foxtrot, hours: "52", issued: "2025-09-30", due: "2025-10-30",
            paid: "2025-10-08", paidHalere: 7_878_052, paymentRate: "21.643", issueRate: "21.627"),
        Entry(
            number: "20251002", client: foxtrot, hours: "61", issued: "2025-10-31", due: "2025-11-30",
            paid: "2025-11-07", paidHalere: 9_080_582, paymentRate: "21.266", issueRate: "21.245"),
        Entry(
            number: "20251102", client: foxtrot, hours: "47", issued: "2025-11-30", due: "2025-12-30",
            paid: "2025-12-09", paidHalere: 6_907_355, paymentRate: "20.995", issueRate: "21.123"),
    ]

    /// Every invoice of the sample, with the ids of the list's order.
    static let invoices: [Invoice] = {
        let entries = entries2026 + sierraEntries(of: 2024) + sierraEntries(of: 2025) + foxtrotEntries2025
        return entries.enumerated().map { index, entry in invoice(Int64(index + 1), entry) }
    }()

    private static func invoice(_ id: Int64, _ entry: Entry) -> Invoice {
        let client = entry.client
        let description =
            client.id == foxtrot.id ? "Software development" : client.id == tango.id ? "IT služby" : "Vývoj"
        let work = hours(entry.hours, of: client, describedAs: description)
        let supplied = entry.duzp ?? entry.issued
        var invoice = Invoice(
            id: id, number: entry.number, clientID: client.id, client: ClientSnapshot(client: client),
            currency: client.currency, issueDate: civilDate(entry.issued), duzp: civilDate(supplied),
            dueDate: civilDate(entry.due),
            items: [
                InvoiceItem(
                    description: work.description, quantity: work.quantity, unit: work.unit,
                    unitPriceMinor: work.unitPriceMinor)
            ],
            vatMode: client.vatMode, invoiceRate: entry.issueRate.map { storedRate("USD", $0, declaredOn: supplied) },
            qrEnabled: false, note: "", language: client.language, paymentMethod: "Převodem",
            status: entry.isDraft ? .draft : .issued, review: nil, payment: nil, source: .app)
        if let paid = entry.paid {
            if let paidHalere = entry.paidHalere, let rate = entry.paymentRate {
                invoice.payment = Payment(
                    date: civilDate(paid), conversion: .cnbDaily, czkNetHalere: paidHalere, czkVatHalere: 0,
                    rate: storedRate("USD", rate, declaredOn: paid))
            } else {
                invoice.payment = Payment(
                    date: civilDate(paid), conversion: .czk, czkNetHalere: invoice.netMinor,
                    czkVatHalere: invoice.vatMinor, rate: nil)
            }
        }
        return invoice
    }

    // MARK: Rates

    /// 21,320 Kč for a dollar.
    static let usdRate = ExchangeRate(currency: .usd, amount: 1, rate: decimal("21.32"))

    static let rates = [CurrencyCode.usd: usdRate]

    /// Friday 16 October 2026, the day the ČNB declared `usdRate`.
    static let rateDay = civilDate("2026-10-16")

    /// Independent daily declarations for both paid and pending invoice variants; stored payments stay unchanged.
    static let averageRates: [PredictionRateKey: StoredRate] = {
        var result: [PredictionRateKey: StoredRate] = [:]
        let entries = entries2026 + foxtrotEntries2025
        for entry in entries where entry.client.currency == .usd {
            if let paid = entry.paid, let rate = entry.paymentRate {
                let day = civilDate(paid)
                result[PredictionRateKey(currency: .usd, day: day)] = storedRate(
                    "USD", rate, declaredOn: CzechCalendar.rateDeclarationDay(for: day).iso)
            }
            let day = civilDate(entry.issued)
            let declared = CzechCalendar.rateDeclarationDay(for: min(day, sampleToday))
            result[PredictionRateKey(currency: .usd, day: day)] = storedRate(
                "USD", entry.issueRate ?? "21.32", declaredOn: declared.iso)
        }
        return result
    }()

    // MARK: The year's settings

    /// The advances of `year` in whole Kč: none for a year other than 2024 to 2026. 2026 has the advances of the
    /// engine's sample year: insurance advances that drop from May, and 23 000 Kč of income tax in June and in
    /// December.
    static func plan(of year: Int) -> AdvancePlan {
        switch year {
        case 2024:
            AdvancePlan(social: everyMonth(8_600), health: everyMonth(4_300), tax: juneAndDecember(16_500))
        case 2025:
            AdvancePlan(social: everyMonth(9_450), health: everyMonth(4_700), tax: juneAndDecember(19_000))
        case 2026:
            TaxEngineRegressionTests.sampleYear2026.advances
        default:
            AdvancePlan.empty
        }
    }

    /// The deductions of `year`: mortgage interest above the yearly limit of 150 000 Kč (236 000 Kč in 2024,
    /// 228 000 Kč in 2025, 219 000 Kč in 2026) and 6 480 Kč of life insurance.
    static func deductions(of year: Int) -> Deductions {
        let interest: Int64 =
            switch year {
            case 2024: 236_000
            case 2025: 228_000
            default: 219_000
            }
        return Deductions(
            mortgageInterestPaid: interest, mortgageMonths: 12, mortgageCap: .after2021, lifeInsurance: 6_480)
    }

    /// The settings of `year`: 60 % flat-rate expenses, the main activity the whole year, the taxpayer credit, the
    /// deductions and the advances.
    static func settings(of year: Int) -> YearSettings {
        var settings = YearSettings(year: year)
        settings.expensePercent = 60
        settings.deductions = deductions(of: year)
        settings.advances = plan(of: year)
        return settings
    }

    private static func everyMonth(_ amount: Int64) -> [Int64] {
        [Int64](repeating: amount, count: 12)
    }

    private static func juneAndDecember(_ amount: Int64) -> [Int64] {
        var months = [Int64](repeating: 0, count: 12)
        months[5] = amount
        months[11] = amount
        return months
    }

    // MARK: Inputs

    /// The receipts of `year` that `invoices` bring, as the data gives them: the payments dated in the year of the
    /// issued invoices, in the order of the invoices.
    static func receipts(of invoices: [Invoice], year: Int) -> [Receipt] {
        invoices.compactMap { invoice in
            guard invoice.status == .issued, invoice.review == nil, let payment = invoice.payment,
                payment.date.year == year
            else {
                return nil
            }
            return Receipt(
                day: payment.date, czkNetHalere: payment.czkNetHalere, czkVatHalere: payment.czkVatHalere,
                source: .invoice(invoice.id))
        }
    }

    /// What the prediction of `year` is made from as of `today`, with the person's `changes`: the clients, the issued
    /// invoices of every year and the drafts of `year`, the templates, the receipts of `year` and the dollar's rate.
    static func input(
        year: Int, today: CivilDate = sampleToday, changes: [Int64: [Int: Bool]] = [:]
    ) -> PredictionInput {
        PredictionInput(
            year: year, today: today, clients: clients,
            invoices: invoices.filter { $0.status == .issued || $0.issueDate.year == year }, templates: templates,
            changes: changes, receipts: receipts(of: invoices, year: year), rates: rates, usesUniformRate: false,
            rateDay: rateDay, averageRates: averageRates)
    }

    /// What the engine is given for `year`: its settings, its receipts and the sample family, Anna (3. 9. 2019) and
    /// Tomáš (12. 4. 2024), both in the household and claimed by me, and a spouse without income of her own.
    static func yearInput(year: Int) -> YearInput {
        AppModel.yearInput(
            settings(of: year), receipts: receipts(of: invoices, year: year),
            family: TaxEngineFamilyTests.sampleFamily)
    }

    /// The prediction of `input`'s year with the levies the engine works out from it: the settings, the deductions, the
    /// advances and the family of the year in the sample, and the receipts of `input`.
    static func outcome(of input: PredictionInput) throws -> PredictionOutcome {
        var taxInput = yearInput(year: input.year)
        taxInput.receipts = input.receipts
        return try PredictionOutcome.make(prediction: IncomePrediction.make(input), yearInput: taxInput)
    }

    /// The prediction of `year` as of `today`, with the person's `changes`, and its levies (`outcome(of:)`): what the
    /// page of Odhad odvodů and the card of Přehled are made from once the sample is stored in the data of an app model
    /// as of the same day.
    static func outcome(
        year: Int, today: CivilDate = sampleToday, changes: [Int64: [Int: Bool]] = [:]
    ) throws -> PredictionOutcome {
        try outcome(of: input(year: year, today: today, changes: changes))
    }

    /// The page of Odhad odvodů for `year` as of `today`, with the person's `changes`: what the screen shows once the
    /// sample is stored in the data of an app model as of the same day.
    static func page(
        year: Int, today: CivilDate = sampleToday, changes: [Int64: [Int: Bool]] = [:]
    ) throws -> PredictionPage {
        PredictionBuilder.page(try outcome(year: year, today: today, changes: changes))
    }
}

// MARK: - In an app

/// Why the sample could not be stored as it is numbered.
enum PredictionSampleError: Error {
    /// The database numbered an invoice differently from `PredictionSample.invoices`, because it was not empty.
    case idsDiffer(expected: Int64, stored: Int64)
}

extension PredictionSample {
    /// Runs `body` with an app model on a new folder, its clock at noon of `sampleToday` unless given, and the sample
    /// stored in its data (`store(in:)`). The folder is removed afterwards.
    @MainActor
    static func withStoredSample(
        clock: ManualClock = ManualClock(localNoon(2026, 10, 17)), _ body: (AppModel) async throws -> Void
    ) async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let app = makeAppModel(in: directory, clock: clock)
        try await startFresh(app)
        try await store(in: app)
        try await body(app)
    }

    /// Stores the sample in the data of `app`, which must be open and empty, and tells the app of the writes
    /// (`didWriteAndBackUp()`): the settings of 2024 to 2026, each with the sample's spouse; Anna and Tomáš, with the
    /// household, the claimant and the order of the sample family in 2026 (the years before take the defaults, which
    /// are the same, but for Tomáš living in the household only from the month of his birth in 2024); the clients and
    /// their templates; the invoices with their payments; and the ČNB rate of the dollar, `usdRate` declared on
    /// `rateDay`. The clients, the templates and the invoices get the ids of their lists. Throws `VaultError.locked`
    /// while the data is locked, and `PredictionSampleError.idsDiffer` when the database numbers an invoice differently
    /// because it was not empty.
    @MainActor
    static func store(in app: AppModel) async throws {
        guard let database = app.database else { throw VaultError.locked }
        let family = TaxEngineFamilyTests.sampleFamily
        for year in 2024...2026 {
            var yearSettings = Self.settings(of: year)
            yearSettings.spouse = family.spouse
            try await database.saveYearSettings(yearSettings)
        }
        for facts in family.children {
            let child = Child(id: nil, name: facts.label, birthDate: facts.birthDate)
            let childYear = ChildYear(
                household: facts.household, claimant: facts.claimant, order: facts.order, ztpp: facts.ztpp,
                studies: facts.studies)
            try await database.saveChild(child, year: 2026, childYear: childYear)
        }
        for client in clients {
            try await database.saveClient(client)
        }
        for template in templates {
            try await database.saveTemplate(template)
        }
        for sample in invoices {
            var invoice = sample
            invoice.id = 0
            let stored = try await database.saveInvoice(invoice)
            guard stored == sample.id else {
                throw PredictionSampleError.idsDiffer(expected: sample.id, stored: stored)
            }
        }
        let daily = Set(averageRates.values).map { stored in
            CNBRateRow(
                declaredOn: stored.declaredOn, currency: stored.rate.currency, amount: stored.rate.amount,
                rate: stored.rate.rate)
        }
        try await database.insertCNBRates(daily)
        await app.didWriteAndBackUp()
    }
}
