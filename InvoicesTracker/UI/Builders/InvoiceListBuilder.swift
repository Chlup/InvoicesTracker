import Foundation

// MARK: - Input

/// Everything the list of Faktury needs, already loaded: the invoices of the year and scope, what the search found, and
/// the rates that turn foreign amounts into crowns.
nonisolated struct InvoiceListInput: Sendable {
    var year: Int

    /// The day the screen is shown as of ("K datu"). It decides which payments have been received, and so the money:
    /// the list of what was paid in the year, the column in crowns and the tiles.
    var asOf: CivilDate

    /// The day the status of an invoice is worked out for: today, whatever year or day the screen is shown as of. It
    /// decides the status of a row and everything that follows from it: the pill, the chips with their counts and the
    /// chosen chip. What the tile of the uniform rate says of a rate the year lacks follows it too.
    var statusDay: CivilDate

    var scope: InvoiceScope

    /// The status chip that is chosen.
    var filter: InvoiceStatusFilter

    /// The invoices of `year` in `scope`. The builder applies the rule of the scope again, so the numbers do not
    /// depend on how much the caller loaded.
    var invoices: [Invoice]

    /// What is typed in the search field.
    var searchText: String

    /// The ids of the invoices the search found in `year` and `scope`, or nil when nothing is searched for. They are
    /// used while `searchText` has a word; a text of nothing but whitespace is no search.
    var matchingIDs: Set<Int64>?

    /// How many invoices the search found in each year of the scope, for the links to other years.
    var otherYearCounts: [Int: Int]

    /// By invoice id, the ČNB rate of the day the money for the invoice arrived.
    var paymentDayRates: [Int64: ExchangeRate]

    /// By invoice id, the ČNB rate valid on the day the invoice was issued.
    var issueDayRates: [Int64: ExchangeRate]

    /// The uniform rates known for `year`, by currency.
    var uniformRates: [CurrencyCode: UniformRate]

    /// By invoice id, what each invoice leaves after the levies its payment adds, or would add (`InvoiceNetIncome`), as
    /// of `asOf`. An invoice that has no entry has no net income and shows a dash.
    var netIncomes: [Int64: InvoiceNetIncome] = [:]
}

// MARK: - Output

/// One of the small tiles above the table: a number with a line that says what it is.
nonisolated struct Tile: Sendable, Hashable {
    var value: String
    var subtitle: String
}

/// The tile with the total at the uniform rate of the year.
nonisolated enum UniformTile: Hashable, Sendable {
    /// The total, and which rate it was worked out with.
    case value(String, subtitle: String)

    /// A currency of the category has no known rate. The tile shows "—" and this text, which names the currencies and
    /// says where the search of the app for the rate stands (`UniformRateSearch`).
    case notPublished(String)

    /// The category has no invoice in a foreign currency, so the total is the plain one.
    case noForeign(String, subtitle: String)
}

/// The matches of the search in another year: a link that switches to it.
nonisolated struct OtherYearMatches: Sendable, Hashable {
    var year: Int
    var count: Int

    /// "2025 (2)".
    var label: String {
        "\(year) (\(count))"
    }

    /// What VoiceOver says of the link, with the matches in the form of Czech that their number asks: "Zobrazit rok
    /// 2025, 1 shoda", "… 2 shody", "… 5 shod".
    var accessibilityLabel: String {
        "Zobrazit rok \(String(year)), " + ComputationBuilder.counted(count, "shoda", "shody", "shod")
    }
}

/// The line under the filters while a search is on.
nonisolated struct SearchLine: Sendable, Hashable {
    /// "Hledání „cetus“: 2 z 12 faktur v roce 2026".
    var text: String

    /// The other years with matches, the newest first.
    var otherYears: [OtherYearMatches]

    /// What the list says when nothing is found.
    var emptyText: String
}

/// What kind of net income a row has, which is how its cell looks and what VoiceOver says of it.
nonisolated enum NetIncomeKind: Sendable, Hashable {
    /// The invoice is paid: its net income is what the payment left after the levies it added. The cell is green, also
    /// while the payment waits for its rate and has the sign of an estimate.
    case paid

    /// The invoice is not paid: its net income is an estimate of what the payment expected would leave. The cell is
    /// grey.
    case estimate

    /// The invoice has no net income, and the cell shows a dash. The cell is grey.
    case none
}

/// A row of the table: Číslo, Odběratel, Vystaveno, Zaplaceno, Bez DPH, V Kč, Čistý příjem and Stav, with the line
/// that says why the search found the invoice.
nonisolated struct InvoiceRow: Sendable, Hashable, Identifiable {
    var id: Int64
    var number: String
    var client: String

    /// The day of issue, "30. 9.", with the year when it is not the year of the chosen day.
    var issued: String

    /// The day the money arrived, "2. 10.", with the year when it is not the year of the chosen day, or nil for an
    /// invoice without a payment.
    var paid: String?

    /// The amount without VAT in the currency of the invoice.
    var net: String

    /// The value in crowns of an invoice in a foreign currency: what was paid, or for an invoice that is not paid an
    /// estimate. "≈" stands before an estimate and before a payment that waits for its rate, and "—" stands for an
    /// estimate that cannot be made while the rate of the day of issue is not known. Empty for an invoice in crowns,
    /// which needs no conversion.
    var czk: String

    /// The line under `czk`: how a payment was converted, "ČNB 21,305 · 2. 10.", "jednotný kurz 21,840 · 2. 10." or
    /// "podle banky"; for an estimate the rate of the day of issue it is worked out with, "ČNB k vystavení 21,622".
    /// Empty for an invoice in crowns.
    var czkNote: String

    /// Whether the payment of the invoice has been received by the chosen day ("K datu"): `czk` is then what was paid,
    /// and otherwise an estimate. The status cannot tell, as it does not depend on the chosen day.
    var hasReceivedPayment: Bool

    /// What the invoice leaves after the levies its payment adds, or would add, in whole Kč: for a payment,
    /// "253 401 Kč", with "≈" before it while the payment waits for its rate; for an invoice that is not paid, an
    /// estimate of the payment expected, "≈ 159 636 Kč"; and "—" for an invoice with no net income
    /// (`InvoiceListInput.netIncomes`).
    var netIncome: String

    /// The line under `netIncome`: for a payment, what the levies took of it, "odvody 29,0 %", or "odvody snížila" when
    /// the payment lowered them, as a tax bonus does; "odhad" under an estimate. Empty when there is no net income.
    var netIncomeNote: String

    /// Whether `netIncome` is a payment, an estimate or nothing.
    var netIncomeKind: NetIncomeKind

    /// The status on `InvoiceListInput.statusDay`. `status.label(asOf:)` is what the pill says, with the year of a
    /// payment from another year than the chosen day.
    var status: InvoiceDisplayStatus

    /// Why the search found the invoice, when no column of the table shows it.
    var excerpt: SearchExcerptResult?
}

/// What Faktury shows.
nonisolated struct InvoiceListData: Sendable, Hashable {
    var rows: [InvoiceRow]

    /// How many invoices each chip has, among those of the scope that the search found. The chosen chip does not
    /// change them.
    var chipCounts: [InvoiceStatusFilter: Int]

    /// The chips to show, in order. The chip for invoices to check is among them only when it has an invoice, or when
    /// it is the chosen one, so that the list never has a chosen filter without a chip.
    var visibleChips: [InvoiceStatusFilter]

    /// "Počet faktur".
    var countTile: Tile

    /// "Celkem bez DPH v Kč". Invoices in review are not counted in it until they are resolved.
    var czkTile: Tile
    var czkTotalHalere: Int64

    /// "Celkem bez DPH jednotným kurzem". Invoices in review are not counted in it either.
    var uniformTile: UniformTile

    /// The total of that tile in haléře, or nil while a rate is not published.
    var uniformTotalHalere: Int64?

    /// The line about the search; nil when nothing is searched for.
    var searchLine: SearchLine?

    /// What the list says in place of rows, or nil when it has rows.
    var emptyText: String? {
        guard rows.isEmpty else { return nil }
        return searchLine?.emptyText ?? "Pro tento filtr tu nic není."
    }
}

// MARK: - Builder

/// Turns the invoices of a year into the table, the chips and the tiles of Faktury.
nonisolated enum InvoiceListBuilder {
    /// A click on an invoice opens its detail, and a click on the invoice that is open closes it.
    static func toggleDetail(open: Int64?, clicked: Int64) -> Int64? {
        open == clicked ? nil : clicked
    }

    static func build(_ input: InvoiceListInput) -> InvoiceListData {
        let query = input.searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        let words = SearchFolding.words(query)
        let isSearching = !words.isEmpty

        let inScope = input.invoices.filter { isInScope($0, input) }
        let found = isSearching ? inScope.filter { input.matchingIDs?.contains($0.id) ?? true } : inScope
        let entries = found.map { entry(for: $0, asOf: input.asOf, statusDay: input.statusDay) }

        var counts = Dictionary(uniqueKeysWithValues: InvoiceStatusFilter.allCases.map { ($0, 0) })
        counts[.all] = entries.count
        for entry in entries {
            counts[entry.status.filter, default: 0] += 1
        }

        let shown = entries.enumerated()
            .filter { input.filter == .all || $0.element.status.filter == input.filter }
            .sorted { first, second in
                if first.element.digits != second.element.digits {
                    return first.element.digits > second.element.digits
                }
                return first.offset < second.offset
            }
            .map(\.element)

        let summary = tiles(for: shown, input: input, isSearching: isSearching)
        let otherYears = input.otherYearCounts
            .filter { $0.key != input.year && $0.value > 0 }
            .sorted { $0.key > $1.key }
            .map { OtherYearMatches(year: $0.key, count: $0.value) }

        return InvoiceListData(
            rows: shown.map { row(for: $0, input: input, words: isSearching ? words : []) },
            chipCounts: counts,
            visibleChips: InvoiceStatusFilter.allCases.filter {
                $0 != .review || counts[.review, default: 0] > 0 || input.filter == .review
            },
            countTile: summary.count, czkTile: summary.czk, czkTotalHalere: summary.czkTotal,
            uniformTile: summary.uniform, uniformTotalHalere: summary.uniformTotal,
            searchLine: isSearching
                ? searchLine(
                    query: query, found: entries.count, inScope: inScope.count, otherYears: otherYears,
                    year: input.year)
                : nil
        )
    }

    // MARK: Which invoices

    /// The invoices issued in the year, or those paid in the year on or before the chosen day.
    private static func isInScope(_ invoice: Invoice, _ input: InvoiceListInput) -> Bool {
        switch input.scope {
        case .issued:
            return invoice.issueDate.year == input.year
        case .paid:
            guard let payment = invoice.payment else { return false }
            return payment.date.year == input.year && payment.date <= input.asOf
        }
    }

    /// An invoice with the figures the list works from, worked out once.
    private nonisolated struct Entry {
        var invoice: Invoice

        /// The status as of the status day, which is today: the same whichever year or day the list is shown as of.
        var status: InvoiceDisplayStatus
        var net: Int64

        /// The digits of the number, which the list is in the order of.
        var digits: String

        /// The payment, once the chosen day has reached it. Money that arrives after it has not been received yet,
        /// although the invoice may be paid by today.
        var receivedPayment: Payment?
    }

    /// The figures of `invoice`: its money as of `asOf`, the day the list is shown as of, and its status as of
    /// `statusDay`, which is today.
    private static func entry(for invoice: Invoice, asOf: CivilDate, statusDay: CivilDate) -> Entry {
        let net = invoice.netMinor
        let payment = invoice.payment.flatMap { $0.date <= asOf ? $0 : nil }
        return Entry(
            invoice: invoice, status: invoice.displayStatus(asOf: statusDay), net: net, digits: invoice.numberDigits,
            receivedPayment: payment
        )
    }

    // MARK: Rows

    private static func row(for entry: Entry, input: InvoiceListInput, words: [String]) -> InvoiceRow {
        let invoice = entry.invoice
        let day = { (date: CivilDate) in BuilderText.date(date, omittingYear: input.asOf.year) }
        let money = { (minor: Int64) in CzechFormat.money(Money(minor: minor, currency: invoice.currency)) }
        let (czk, note) = crowns(of: entry, input: input, day: day)
        let afterLevies = netIncome(of: invoice, input: input)
        return InvoiceRow(
            id: invoice.id, number: invoice.number, client: invoice.client.name, issued: day(invoice.issueDate),
            paid: invoice.payment.map { day($0.date) }, net: money(entry.net), czk: czk, czkNote: note,
            hasReceivedPayment: entry.receivedPayment != nil, netIncome: afterLevies.value,
            netIncomeNote: afterLevies.note, netIncomeKind: afterLevies.kind, status: entry.status,
            excerpt: words.isEmpty ? nil : SearchExcerpt.excerpt(for: invoice, words: words)
        )
    }

    /// The column "V Kč" of an invoice in a foreign currency and the line under it. The sign of an estimate is on the
    /// amount, not on the line.
    private static func crowns(
        of entry: Entry, input: InvoiceListInput, day: (CivilDate) -> String
    ) -> (value: String, note: String) {
        let invoice = entry.invoice
        guard !invoice.currency.isCZK else { return ("", "") }
        if let payment = entry.receivedPayment {
            let value = (payment.provisional ? "≈ " : "") + CzechFormat.halere(payment.czkNetHalere)
            return (value, paymentNote(payment, day: day))
        }
        guard let rate = input.issueDayRates[invoice.id] else { return ("—", "") }
        let estimate = rate.czkHalere(fromMinor: entry.net)
        return ("≈ " + CzechFormat.halere(estimate), "ČNB k vystavení " + CzechFormat.rate(rate.rate))
    }

    /// How a payment was converted: "ČNB 21,305 · 2. 10.", "jednotný kurz 21,840 · 2. 10." or "podle banky".
    private static func paymentNote(_ payment: Payment, day: (CivilDate) -> String) -> String {
        let rate = payment.rate.map { " " + CzechFormat.rate($0.rate.rate) } ?? ""
        switch payment.conversion {
        case .bankCZK: return "podle banky"
        case .uniform: return "jednotný kurz" + rate + " · " + day(payment.date)
        case .cnbDaily, .czk: return "ČNB" + rate + " · " + day(payment.date)
        }
    }

    /// The column "Čistý příjem" of an invoice and the line under it, from its net in `input.netIncomes`.
    ///
    /// A payment shows what it left after the levies it added, with the sign of an estimate in front while it waits for
    /// its rate, and what the levies took of it: their share of the income ("odvody 29,0 %"), or "odvody snížila" when
    /// the payment lowered them, where a share would be negative. A payment of nothing took 0 %. An invoice that is not
    /// paid shows an estimate of what its payment would leave, with the line "odhad". An invoice with no net shows "—"
    /// and no line.
    private static func netIncome(
        of invoice: Invoice, input: InvoiceListInput
    ) -> (value: String, note: String, kind: NetIncomeKind) {
        guard let worked = input.netIncomes[invoice.id] else { return ("—", "", .none) }
        let amount = PredictionBuilder.kc(ofHalere: worked.netHalere)
        if worked.isEstimate {
            return (PredictionBuilder.estimateSign + amount, "odhad", .estimate)
        }
        let sign = worked.isProvisional ? PredictionBuilder.estimateSign : ""
        let share = InvoiceDetailBuilder.share(of: worked.effect, income: worked.incomeHalere) ?? "0\u{00A0}%"
        return (sign + amount, worked.effect.total < 0 ? "odvody snížila" : "odvody " + share, .paid)
    }

    // MARK: Tiles

    private nonisolated struct Tiles {
        var count: Tile
        var czk: Tile
        var czkTotal: Int64
        var uniform: UniformTile
        var uniformTotal: Int64?
    }

    /// The three tiles of the category. Invoices in a foreign currency are worked out once at the ČNB rates (what was
    /// paid, or an estimate at the rate of the issue day) and once at the uniform rate of the year. The count is of
    /// all rows of the category, but an invoice in review is not counted until it is resolved, so the two tiles in
    /// crowns leave it out: it adds nothing to them and a rate it lacks does not stop the second one.
    private static func tiles(for shown: [Entry], input: InvoiceListInput, isSearching: Bool) -> Tiles {
        var czkTotal: Int64 = 0
        var uniformTotal: Int64 = 0
        var foreign: Set<CurrencyCode> = []
        var missing: Set<CurrencyCode> = []
        for entry in shown where entry.invoice.review == nil {
            let currency = entry.invoice.currency
            czkTotal += atCNBRates(entry, input)
            if let atUniformRate = atUniformRate(entry, input) {
                uniformTotal += atUniformRate
            } else {
                missing.insert(currency)
            }
            if !currency.isCZK {
                foreign.insert(currency)
            }
        }
        let count = Tile(
            value: String(shown.count),
            subtitle: (input.scope == .paid ? "zaplacené" : "vystavené") + " v roce \(input.year) · "
                + categoryName(input.filter) + (isSearching ? " · podle hledání" : ""))
        let czkSubtitle = foreign.isEmpty
            ? "bez faktur v cizí měně" : "přijaté kurzem ČNB ke dni přijetí, nezaplacené ke dni vystavení"
        let czk = Tile(value: CzechFormat.halere(czkTotal), subtitle: czkSubtitle)
        return Tiles(
            count: count, czk: czk, czkTotal: czkTotal,
            uniform: uniformTile(total: uniformTotal, foreign: foreign, missing: missing, input: input),
            uniformTotal: missing.isEmpty ? uniformTotal : nil
        )
    }

    /// The invoice in haléře at the ČNB rates: crowns as they are; money received at the amount the bank credited when
    /// that was entered, otherwise at the rate of the day it arrived, even when the year converts income by the
    /// uniform rate; an invoice not paid yet at the rate of the day it was issued, and at nothing while that rate is
    /// not known. A payment whose rate of the day is missing counts as it was stored.
    private static func atCNBRates(_ entry: Entry, _ input: InvoiceListInput) -> Int64 {
        let invoice = entry.invoice
        if invoice.currency.isCZK {
            return entry.net
        }
        if let payment = entry.receivedPayment {
            if payment.conversion == .bankCZK {
                return payment.czkNetHalere
            }
            return input.paymentDayRates[invoice.id]?.czkHalere(fromMinor: entry.net) ?? payment.czkNetHalere
        }
        return input.issueDayRates[invoice.id]?.czkHalere(fromMinor: entry.net) ?? 0
    }

    /// The invoice in haléře at the uniform rate of the year: crowns and amounts the bank credited as they are, every
    /// other invoice at the rate of its currency. Nil when that rate is not known.
    private static func atUniformRate(_ entry: Entry, _ input: InvoiceListInput) -> Int64? {
        let invoice = entry.invoice
        if invoice.currency.isCZK {
            return entry.net
        }
        if let payment = entry.receivedPayment, payment.conversion == .bankCZK {
            return payment.czkNetHalere
        }
        return knownUniformRate(invoice.currency, input)?.exchangeRate.czkHalere(fromMinor: entry.net)
    }

    private static func knownUniformRate(_ currency: CurrencyCode, _ input: InvoiceListInput) -> UniformRate? {
        guard let rate = input.uniformRates[currency], rate.currency == currency, rate.year == input.year else {
            return nil
        }
        return rate.rate > 0 && rate.amount > 0 ? rate : nil
    }

    /// The tile with the total at the uniform rate of the year. While a currency of the category has no known rate, it
    /// names the currencies in the order of their codes and says where the search of the app for the rate stands
    /// (`UniformRateSearch`): that the GFŘ publishes it in January, that the app looks for it once a day, or, once it
    /// no longer does, that the app does not have it and which of the missing rates are typed in Nastavení › Rok and
    /// which cannot be typed by hand, those of the currencies it does not take
    /// (`UniformRate.currenciesEnteredByHand`), and tells the two apart when it names both.
    private static func uniformTile(
        total: Int64, foreign: Set<CurrencyCode>, missing: Set<CurrencyCode>, input: InvoiceListInput
    ) -> UniformTile {
        let value = CzechFormat.halere(total)
        if foreign.isEmpty {
            return .noForeign(value, subtitle: "bez faktur v cizí měně – jednotný kurz se nepoužije")
        }
        if !missing.isEmpty {
            let codes = missing.sorted()
            let rate = "Jednotný kurz " + codes.map(\.code).joined(separator: ", ") + " za rok \(input.year)"
            // What is said of the rate follows the search of the app for it today, so that the tile never promises a
            // January that has passed.
            switch UniformRateSearch(year: input.year, today: input.statusDay) {
            case .notStarted:
                return .notPublished(rate + " ještě není vyhlášený – GFŘ ho zveřejní v lednu \(input.year + 1).")
            case .looking:
                return .notPublished(rate + " ještě není vyhlášený – aplikace ho jednou denně hledá.")
            case .over:
                // Nastavení › Rok takes the rates of some currencies only: the tile says which of the missing ones are
                // typed there and that the others cannot be.
                let enterable = codes.filter { UniformRate.currenciesEnteredByHand.contains($0) }
                let others = codes.filter { !UniformRate.currenciesEnteredByHand.contains($0) }
                if others.isEmpty {
                    return .notPublished(rate + " v aplikaci není – zadáte ho v Nastavení › Rok \(input.year).")
                }
                if enterable.isEmpty {
                    return .notPublished(rate + " v aplikaci není – ručně ho zadat nelze.")
                }
                let enterableNames = enterable.map(\.code).joined(separator: ", ")
                let otherNames = others.map(\.code).joined(separator: ", ")
                return .notPublished(
                    rate + " v aplikaci není – kurz \(enterableNames) zadáte v Nastavení › Rok \(input.year),"
                        + " kurz \(otherNames) ručně zadat nelze.")
            }
        }
        let rates = foreign.sorted().compactMap { knownUniformRate($0, input) }
        guard !rates.isEmpty else {
            // Every foreign invoice of the category was paid in crowns by the bank, so no rate was needed.
            return .value(value, subtitle: "částky v Kč podle banky – jednotný kurz se nepoužije")
        }
        var subtitle = "jednotný kurz \(input.year): " + rates.map(BuilderText.uniformRate).joined(separator: ", ")
        if let source = BuilderText.uniformSource(of: rates) {
            subtitle += " · " + source
        }
        return .value(value, subtitle: subtitle)
    }

    /// The name of a category in the line under the count: "čekají na platbu".
    private static func categoryName(_ filter: InvoiceStatusFilter) -> String {
        switch filter {
        case .all: "všechny stavy"
        case .drafts: "koncepty"
        case .awaiting: "čekají na platbu"
        case .overdue: "po splatnosti"
        case .paid: "uhrazené"
        case .review: "ke kontrole"
        }
    }

    // MARK: Search

    private static func searchLine(
        query: String, found: Int, inScope: Int, otherYears: [OtherYearMatches], year: Int
    ) -> SearchLine {
        let invoices = inScope == 1 ? "faktury" : "faktur"
        let emptyEnding = otherYears.isEmpty ? "." : " – zkuste jiný rok výše."
        return SearchLine(
            text: "Hledání „\(query)“: \(found) z \(inScope) \(invoices) v roce \(year)",
            otherYears: otherYears, emptyText: "Hledání „\(query)“ tu nic nenašlo" + emptyEnding
        )
    }
}
