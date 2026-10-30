import Foundation

/// Everything the list of Faktury is made of, read in one call so that its parts agree: the invoices of the year and
/// scope, what the search found among them, how many invoices each year has for the search, and the rates that turn the
/// amounts of foreign invoices into crowns. `InvoiceListInput` is made of it.
nonisolated struct InvoiceListSource: Sendable {
    /// The invoices of the year in the scope, in the order of `Database.invoices(scope:year:asOf:)`.
    var invoices: [Invoice]

    /// The ids of the invoices the search found in the year and scope, or nil when nothing is searched for.
    var matchingIDs: Set<Int64>?

    /// How many invoices the search found in each year of the scope, the year shown included. Empty when nothing is
    /// searched for.
    var otherYearCounts: [Int: Int]

    /// By invoice id, the ČNB rate valid on the day the money for an invoice in a foreign currency arrived. An invoice
    /// paid in crowns by the bank and one whose rate is not known has none.
    var paymentDayRates: [Int64: ExchangeRate]

    /// By invoice id, the ČNB rate valid on the day an invoice in a foreign currency was issued, for each one that is
    /// not paid yet by the day shown. One whose rate is not known has none.
    var issueDayRates: [Int64: ExchangeRate]

    /// The uniform rates known for the year, by currency.
    var uniformRates: [CurrencyCode: UniformRate]
}

/// A currency on a day: what a rate is looked up for. Many invoices are issued on the same day, so each is looked up
/// once.
private nonisolated struct RateLookupKey: Hashable {
    let currency: CurrencyCode
    let day: CivilDate
}

extension Database {
    /// What the list of Faktury shows for `year` in `scope` as of `asOf`, with the words of `searchText` searched for:
    /// the invoices, the ids the search found and its counts in other years, and the ČNB and uniform rates the list
    /// converts with. It is one call on the database, so a write cannot come in between and make the parts disagree.
    ///
    /// A text of nothing but whitespace is no search. The rates are those of `RateLookup`: an invoice paid by the day
    /// shown has the rate of the day the money arrived (unless the bank credited crowns), any other the rate of the
    /// day it was issued; a rate the ČNB has not declared yet is left out.
    func invoiceListSource(
        scope: InvoiceScope, year: Int, asOf: CivilDate, searchText: String
    ) throws -> InvoiceListSource {
        let invoices = try self.invoices(scope: scope, year: year, asOf: asOf)
        var matchingIDs: Set<Int64>?
        var otherYearCounts: [Int: Int] = [:]
        if !SearchFolding.words(searchText).isEmpty {
            matchingIDs = try searchInvoiceIDs(searchText, scope: scope, year: year, asOf: asOf)
            otherYearCounts = try searchCountsByYear(searchText, scope: scope, asOf: asOf)
        }

        var lookups: [RateLookupKey: ExchangeRate?] = [:]
        func rate(_ currency: CurrencyCode, on day: CivilDate) throws -> ExchangeRate? {
            let key = RateLookupKey(currency: currency, day: day)
            if let known = lookups[key] {
                return known
            }
            var found: ExchangeRate?
            if case .declared(let declared, _) = try cnbRate(currency, on: day) {
                found = declared
            }
            lookups[key] = .some(found)
            return found
        }
        var paymentDayRates: [Int64: ExchangeRate] = [:]
        var issueDayRates: [Int64: ExchangeRate] = [:]
        for invoice in invoices where !invoice.currency.isCZK {
            if let payment = invoice.payment, payment.date <= asOf {
                if payment.conversion != .bankCZK {
                    paymentDayRates[invoice.id] = try rate(invoice.currency, on: payment.date)
                }
            } else {
                issueDayRates[invoice.id] = try rate(invoice.currency, on: invoice.issueDate)
            }
        }

        let uniformRates = Dictionary(
            uniqueKeysWithValues: try self.uniformRates(year: year).map { ($0.currency, $0) })
        return InvoiceListSource(
            invoices: invoices, matchingIDs: matchingIDs, otherYearCounts: otherYearCounts,
            paymentDayRates: paymentDayRates, issueDayRates: issueDayRates, uniformRates: uniformRates)
    }
}
