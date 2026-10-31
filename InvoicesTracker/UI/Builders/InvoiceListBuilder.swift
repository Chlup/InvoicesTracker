import Foundation

// MARK: - Input

/// Everything the list of Faktury needs, already loaded: the invoices of the year and scope, what the search found, and
/// the rates that turn foreign amounts into crowns.
nonisolated struct InvoiceListInput: Sendable {
    var year: Int

    /// The day the screen is shown as of ("K datu"). It decides which payments have been received, and so the money:
    /// the list of what was paid in the year, the column in crowns and the totals of the summary row.
    var asOf: CivilDate

    /// The day the status of an invoice is worked out for: today, whatever year or day the screen is shown as of. It
    /// decides the status of a row and everything that follows from it: the pill, the chips with their counts and the
    /// chosen chip. What the summary row says of a uniform rate the year lacks follows it too, and so does whether the
    /// date of a payment is a later one, after today.
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

/// The figure of the summary row with the total at the uniform rate of the year, "Jednotným kurzem 2026".
nonisolated enum UniformSummary: Hashable, Sendable {
    /// The shown invoices have no invoice in a foreign currency that counts, so the total at the uniform rate is the
    /// total in crowns, and the row does not show it.
    case hidden

    /// The total in whole Kč, `text`, and its tooltip, `help`, which says which rates it was worked out with.
    case value(text: String, help: String)

    /// A currency of the shown invoices has no known rate, so there is no total: `text` says so in a word, muted, and
    /// the tooltip, `help`, names the currencies and says where the search of the app for the rate stands.
    case missing(text: String, help: String)
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

    /// The invoice has no net income, and the cell shows a dash in the faintest grey.
    case none
}

/// When the payment of an invoice came, which is how the cell of Zaplaceno looks.
nonisolated enum PaidTone: Sendable, Hashable {
    /// The invoice has no payment: the cell shows a dash in the faintest grey.
    case none

    /// The payment is dated today or earlier: the date is in the colour of text.
    case received

    /// The payment is dated after today, as an import or a clock that was set back can leave one: the date is in the
    /// grey of notes, as the payment does not count until that day.
    case later
}

/// What kind of value in crowns a row shows in V Kč bez DPH, which is how its cell looks.
nonisolated enum CrownsKind: Sendable, Hashable {
    /// What was received by the day shown, or the amount of an invoice in crowns: in the colour of text. A payment
    /// that waits for its rate has the sign of an estimate in front, and is in the colour of text all the same.
    case actual

    /// An invoice in a foreign currency whose money has not been received by the day shown, at the ČNB rate of the day
    /// it was issued, with the sign of an estimate in front: in secondary grey.
    case estimate

    /// An estimate that cannot be made while the rate of the day of issue is not known: a dash in the faintest grey.
    case unknown
}

/// A row of the table: Číslo, Odběratel, Vystaveno, Zaplaceno, V Kč bez DPH, Bez DPH, Čistý příjem and Stav, each
/// one line, with the excerpt that says why the search found the invoice.
nonisolated struct InvoiceRow: Sendable, Hashable, Identifiable {
    var id: Int64
    var number: String
    var client: String

    /// The day of issue, "30. 9.", with the year when it is not the year of the chosen day.
    var issued: String

    /// The day the money arrived, "2. 10.", with the year when it is not the year of the chosen day, or "—" for an
    /// invoice without a payment.
    var paidDate: String

    /// Whether the invoice has a payment, and whether it is dated after today (`InvoiceListInput.statusDay`).
    var paidTone: PaidTone

    /// The amount without VAT in the currency of the invoice.
    var net: String

    /// The amount without VAT in crowns. For an invoice in crowns its net, the same as `net`; for one in a foreign
    /// currency what was paid, or for an invoice whose money has not been received an estimate at the rate of the day
    /// of issue. "≈" stands before an estimate and before a payment that waits for its rate, and "—" stands for an
    /// estimate that cannot be made while the rate of the day of issue is not known.
    var czk: String

    /// Whether `czk` is what was received, an estimate or a dash.
    var czkKind: CrownsKind

    /// The tooltip of `czk` for an estimate, which names the conversion: "Odhad kurzem ČNB ke dni vystavení: 21,622
    /// Kč/USD". Nil for every other value.
    var czkHelp: String?

    /// Whether the payment of the invoice has been received by the chosen day ("K datu"): `czk` is then what was paid,
    /// and otherwise an estimate. The status cannot tell, as it does not depend on the chosen day.
    var hasReceivedPayment: Bool

    /// What the invoice leaves after the levies its payment adds, or would add, in whole Kč: for a payment,
    /// "253 401 Kč", with "≈" before it while the payment waits for its rate; for an invoice that is not paid, an
    /// estimate of the payment expected, "≈ 159 636 Kč"; and "—" for an invoice with no net income
    /// (`InvoiceListInput.netIncomes`). What the levies took of it is told in the detail.
    var netIncome: String

    /// Whether `netIncome` is a payment, an estimate or nothing.
    var netIncomeKind: NetIncomeKind

    /// The status on `InvoiceListInput.statusDay`. The detail says it with the day of a payment
    /// (`InvoiceDisplayStatus.label(asOf:)`).
    var status: InvoiceDisplayStatus

    /// What the pill of the row says: the status without a date, "Uhrazená" (`InvoiceDisplayStatus.listLabel`).
    var listStatus: String

    /// The tone of the pill of the row (`InvoiceDisplayStatus.pillTone`).
    var pillTone: PillTone

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

    /// How many rows the table shows, with the noun in the form Czech asks for the number: "12 faktur".
    var countText: String

    /// Which rows they are, after the count, with its own leading separator: " · všechny stavy", and
    /// " · všechny stavy · podle hledání" while a search is on. The scope is the segment's to say.
    var categoryText: String

    /// After the category, " · mimo součet: 1 faktura ke kontrole" when the table lists an invoice in a foreign
    /// currency that is to be checked and so left out of both totals, and no other foreign invoice is counted: the
    /// row would otherwise show no total at the uniform rate while the table lists one. Nil otherwise.
    var reviewHint: String?

    /// "Celkem v Kč bez DPH": the total of `czkTotalHalere` in whole Kč, rounded once from the sum in haléře.
    var totalText: String

    /// The total without VAT in crowns of the rows, in haléře: invoices in crowns at their net, money received at the
    /// ČNB rate of the day it arrived (or as the bank credited it), and invoices not paid yet at the rate of the day
    /// they were issued. Invoices in review are not counted until they are resolved.
    var czkTotalHalere: Int64

    /// The label of the total at the uniform rate: "Jednotným kurzem 2026".
    var uniformLabel: String

    /// The figure of the total at the uniform rate, with its tooltip, or nothing for a category without invoices in a
    /// foreign currency.
    var uniform: UniformSummary

    /// The total at the uniform rate in haléře, or nil while a rate is not known. Invoices in review are not counted
    /// in it either.
    var uniformTotalHalere: Int64?

    /// Whether a row of the table prints a day of issue of another year than the one shown, "30. 12. 2025", which the
    /// column of Vystaveno is widened for.
    var issueDatesShowYear: Bool

    /// Whether a row of the table prints a day of payment of another year than the one shown, which the column of
    /// Zaplaceno is widened for.
    var paymentDatesShowYear: Bool

    /// The line about the search; nil when nothing is searched for.
    var searchLine: SearchLine?

    /// What the list says in place of rows, or nil when it has rows.
    var emptyText: String? {
        guard rows.isEmpty else { return nil }
        return searchLine?.emptyText ?? "Pro tento filtr tu nic není."
    }
}

// MARK: - Builder

/// Turns the invoices of a year into the table, the chips and the summary row of Faktury.
nonisolated enum InvoiceListBuilder {
    /// A click on an invoice opens its detail, and a click on the invoice that is open closes it.
    static func toggleDetail(open: Int64?, clicked: Int64) -> Int64? {
        open == clicked ? nil : clicked
    }

    /// The list of `input`: the invoices of the scope that the search found, counted in the chips; the rows of the
    /// chosen chip, the newest number first; the summary row of those rows; and the line about the search.
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

        let summary = summaryRow(of: shown, input: input, isSearching: isSearching)
        let otherYears = input.otherYearCounts
            .filter { $0.key != input.year && $0.value > 0 }
            .sorted { $0.key > $1.key }
            .map { OtherYearMatches(year: $0.key, count: $0.value) }
        let year = input.asOf.year

        return InvoiceListData(
            rows: shown.map { row(for: $0, input: input, words: isSearching ? words : []) },
            chipCounts: counts,
            visibleChips: InvoiceStatusFilter.allCases.filter {
                $0 != .review || counts[.review, default: 0] > 0 || input.filter == .review
            },
            countText: summary.count, categoryText: summary.category, reviewHint: summary.reviewHint,
            totalText: PredictionBuilder.kc(ofHalere: summary.czkTotal), czkTotalHalere: summary.czkTotal,
            uniformLabel: "Jednotným kurzem \(input.year)", uniform: summary.uniform,
            uniformTotalHalere: summary.uniformTotal,
            issueDatesShowYear: shown.contains { $0.invoice.issueDate.year != year },
            paymentDatesShowYear: shown.contains { $0.invoice.payment.map { $0.date.year != year } ?? false },
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

    /// The row of `entry`: its texts, each one line, and the tones of its cells. The dates leave out the year of the
    /// day shown; a payment dated after today is a later one.
    private static func row(for entry: Entry, input: InvoiceListInput, words: [String]) -> InvoiceRow {
        let invoice = entry.invoice
        let day = { (date: CivilDate) in BuilderText.date(date, omittingYear: input.asOf.year) }
        let money = { (minor: Int64) in CzechFormat.money(Money(minor: minor, currency: invoice.currency)) }
        let crowns = crowns(of: entry, input: input)
        let afterLevies = netIncome(of: invoice, input: input)
        let paidTone: PaidTone = invoice.payment.map { $0.date > input.statusDay ? .later : .received } ?? .none
        return InvoiceRow(
            id: invoice.id, number: invoice.number, client: invoice.client.name, issued: day(invoice.issueDate),
            paidDate: invoice.payment.map { day($0.date) } ?? "—", paidTone: paidTone, net: money(entry.net),
            czk: crowns.value, czkKind: crowns.kind, czkHelp: crowns.help,
            hasReceivedPayment: entry.receivedPayment != nil, netIncome: afterLevies.value,
            netIncomeKind: afterLevies.kind, status: entry.status, listStatus: entry.status.listLabel,
            pillTone: entry.status.pillTone,
            excerpt: words.isEmpty ? nil : SearchExcerpt.excerpt(for: invoice, words: words)
        )
    }

    /// The column "V Kč bez DPH" of an invoice: an invoice in crowns at its net; money received by the day shown as it
    /// was converted when it came, with the sign of an estimate while its rate is provisional; an invoice whose money
    /// has not been received at the rate of the day it was issued, with the sign of an estimate and a tooltip that
    /// names the conversion; and a dash while that rate is not known.
    private static func crowns(
        of entry: Entry, input: InvoiceListInput
    ) -> (value: String, kind: CrownsKind, help: String?) {
        let invoice = entry.invoice
        if invoice.currency.isCZK {
            return (CzechFormat.halere(entry.net), .actual, nil)
        }
        if let payment = entry.receivedPayment {
            let value = (payment.provisional ? "≈ " : "") + CzechFormat.halere(payment.czkNetHalere)
            return (value, .actual, nil)
        }
        guard let rate = input.issueDayRates[invoice.id] else { return ("—", .unknown, nil) }
        let estimate = rate.czkHalere(fromMinor: entry.net)
        return (
            "≈ " + CzechFormat.halere(estimate), .estimate,
            "Odhad kurzem ČNB ke dni vystavení: " + CzechFormat.rateLabel(rate)
        )
    }

    /// The column "Čistý příjem" of an invoice, from its net in `input.netIncomes`: what a payment left after the
    /// levies it added, with the sign of an estimate in front while it waits for its rate; for an invoice that is not
    /// paid an estimate of what its payment would leave; and "—" for an invoice with no net.
    private static func netIncome(
        of invoice: Invoice, input: InvoiceListInput
    ) -> (value: String, kind: NetIncomeKind) {
        guard let worked = input.netIncomes[invoice.id] else { return ("—", .none) }
        let amount = PredictionBuilder.kc(ofHalere: worked.netHalere)
        if worked.isEstimate {
            return (PredictionBuilder.estimateSign + amount, .estimate)
        }
        return ((worked.isProvisional ? PredictionBuilder.estimateSign : "") + amount, .paid)
    }

    // MARK: The summary row

    /// What the summary row says of the rows and the totals behind it.
    private nonisolated struct Summary {
        var count: String
        var category: String
        var reviewHint: String?
        var czkTotal: Int64
        var uniform: UniformSummary
        var uniformTotal: Int64?
    }

    /// The summary row of the rows `shown`: their count and category, and their totals without VAT in crowns.
    /// Invoices in a foreign currency are worked out once at the ČNB rates (what was paid, or an estimate at the rate
    /// of the issue day) and once at the uniform rate of the year. The count is of all rows, but an invoice in review
    /// is not counted until it is resolved, so the two totals leave it out: it adds nothing to them, and a rate it
    /// lacks does not stop the second one. Each total is rounded to whole Kč once, from its sum in haléře.
    private static func summaryRow(of shown: [Entry], input: InvoiceListInput, isSearching: Bool) -> Summary {
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
        let uniform = uniformSummary(total: uniformTotal, foreign: foreign, missing: missing, input: input)
        return Summary(
            count: ComputationBuilder.counted(shown.count, "faktura", "faktury", "faktur"),
            category: " · " + categoryName(input.filter) + (isSearching ? " · podle hledání" : ""),
            reviewHint: hintAboutInvoicesToCheck(in: shown, uniform: uniform), czkTotal: czkTotal, uniform: uniform,
            uniformTotal: missing.isEmpty ? uniformTotal : nil
        )
    }

    /// " · mimo součet: 2 faktury ke kontrole" when the summary row shows no total at the uniform rate though the rows
    /// hold an invoice in a foreign currency, because every such invoice is one to check, which neither total counts.
    /// The hint counts every invoice to check among the rows, in crowns too, as both totals leave them out. Nil
    /// otherwise.
    private static func hintAboutInvoicesToCheck(in shown: [Entry], uniform: UniformSummary) -> String? {
        let toCheck = shown.filter { $0.invoice.review != nil }
        guard uniform == .hidden, toCheck.contains(where: { !$0.invoice.currency.isCZK }) else { return nil }
        return " · mimo součet: " + ComputationBuilder.counted(toCheck.count, "faktura", "faktury", "faktur")
            + " ke kontrole"
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

    /// The uniform rate of `currency` for the year of `input`, or nil when the year has none that can be used: none is
    /// known, it is of another year or currency, or it is not a positive rate of a positive amount.
    private static func knownUniformRate(_ currency: CurrencyCode, _ input: InvoiceListInput) -> UniformRate? {
        guard let rate = input.uniformRates[currency], rate.currency == currency, rate.year == input.year else {
            return nil
        }
        return rate.rate > 0 && rate.amount > 0 ? rate : nil
    }

    /// The figure with the total at the uniform rate of the year, `total` in haléře. A category without invoices in a
    /// foreign currency has none. While a currency of the category has no known rate, the figure says so in a word and
    /// its tooltip names the currencies in the order of their codes and says where the search of the app for the rate
    /// stands (`UniformRateSearch`): "zatím nevyhlášen" while the rate is not out, with the January in which the GFŘ
    /// publishes it, and then that the app looks for it once a day; "v aplikaci není" once it no longer does, when the
    /// rate is out but not in the app, with which of the missing rates are typed in Nastavení › Rok and which cannot be
    /// typed by hand, those of the currencies it does not take (`UniformRate.currenciesEnteredByHand`). Otherwise the
    /// figure is the total in whole Kč, and its tooltip names the rates and where they are from; or, when every
    /// foreign invoice was paid in crowns by the bank, says that no rate was needed.
    private static func uniformSummary(
        total: Int64, foreign: Set<CurrencyCode>, missing: Set<CurrencyCode>, input: InvoiceListInput
    ) -> UniformSummary {
        if foreign.isEmpty {
            return .hidden
        }
        if !missing.isEmpty {
            let codes = missing.sorted()
            let rate = "Jednotný kurz " + codes.map(\.code).joined(separator: ", ") + " za rok \(input.year)"
            let notOut = "zatím nevyhlášen"
            // What is said of the rate follows the search of the app for it today, so that the row never promises a
            // January that has passed.
            switch UniformRateSearch(year: input.year, today: input.statusDay) {
            case .notStarted:
                return .missing(
                    text: notOut, help: rate + " ještě není vyhlášený – GFŘ ho zveřejní v lednu \(input.year + 1).")
            case .looking:
                return .missing(text: notOut, help: rate + " ještě není vyhlášený – aplikace ho jednou denně hledá.")
            case .over:
                return .missing(
                    text: "v aplikaci není", help: rate + " v aplikaci není – " + whereToEnter(codes, input))
            }
        }
        let value = PredictionBuilder.kc(ofHalere: total)
        let rates = foreign.sorted().compactMap { knownUniformRate($0, input) }
        guard !rates.isEmpty else {
            // Every foreign invoice of the category was paid in crowns by the bank, so no rate was needed.
            return .value(text: value, help: "Částky v Kč podle banky – jednotný kurz se nepoužije")
        }
        var help = "Jednotný kurz \(input.year): " + rates.map(BuilderText.uniformRate).joined(separator: ", ")
        if let source = BuilderText.uniformSource(of: rates) {
            help += " · " + source
        }
        return .value(text: value, help: help)
    }

    /// Where the missing uniform rates of `codes` are entered, once the app no longer looks for them: Nastavení › Rok
    /// takes the rates of some currencies only, so the text says which of them are typed there and that the others
    /// cannot be, and tells the two apart when it names both.
    private static func whereToEnter(_ codes: [CurrencyCode], _ input: InvoiceListInput) -> String {
        let enterable = codes.filter { UniformRate.currenciesEnteredByHand.contains($0) }
        let others = codes.filter { !UniformRate.currenciesEnteredByHand.contains($0) }
        if others.isEmpty {
            return "zadáte ho v Nastavení › Rok \(input.year)."
        }
        if enterable.isEmpty {
            return "ručně ho zadat nelze."
        }
        let enterableNames = enterable.map(\.code).joined(separator: ", ")
        let otherNames = others.map(\.code).joined(separator: ", ")
        return "kurz \(enterableNames) zadáte v Nastavení › Rok \(input.year), kurz \(otherNames) ručně zadat nelze."
    }

    /// The name of a category in the summary row, after the count: "čekají na platbu".
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

    /// The line about a search for `query`, which found `found` of the `inScope` invoices of the scope in `year`, with
    /// the links to `otherYears`, and what the list says when it found nothing.
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
