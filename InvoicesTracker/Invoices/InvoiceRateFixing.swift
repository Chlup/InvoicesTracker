import Foundation

/// The ČNB rate that is fixed on an invoice in a foreign currency when it is issued, for the CZK equivalent the
/// invoice prints. It is never changed afterwards, because the printed invoice is a tax document.
nonisolated enum InvoiceRateFixing {
    /// The rate to fix on an invoice issued with the taxable supply on `duzp`:
    /// - none for an invoice in crowns;
    /// - the rate the ČNB declared for the DUZP, with the day it declared it (the business day before when the DUZP is
    ///   a weekend day or a holiday), if `lookup` has it;
    /// - otherwise `latestBefore`, the latest rate declared before the DUZP, which is nil if there is none.
    ///
    /// - Parameters:
    ///   - currency: The currency of the invoice.
    ///   - duzp: The day of the taxable supply, which `lookup` and `latestBefore` were made for.
    ///   - lookup: The rate valid on `duzp`.
    ///   - latestBefore: The latest rate of `currency` declared before `duzp`.
    static func rateForIssue(
        currency: CurrencyCode, duzp: CivilDate, lookup: RateLookupResult, latestBefore: StoredRate?
    ) -> StoredRate? {
        guard !currency.isCZK else { return nil }
        if case .declared(let rate, let declaredOn) = lookup {
            return StoredRate(rate: rate, declaredOn: declaredOn)
        }
        return latestBefore
    }

    /// The rate that may be fixed on an invoice that is issued now: the rate declared for the DUZP, or, only while the
    /// declaration of the DUZP is still to come, the last declared rate. Never an older rate in place of one that
    /// should be there, which `rateForIssue` would take: `lookup` also says `.notYetAvailable` for a day whose rows
    /// are not loaded, and a rate from before the hole is a wrong rate that nobody would notice on a tax document.
    ///
    /// The declaration of the DUZP is still to come when the DUZP is after `expectedNewestDeclaration`, the newest
    /// declaration the cache should hold now, and the cache holds it (`newestCachedDeclaration` is not behind): then
    /// the last declared rate is the newest rate there is, provided it was declared in that newest declaration. With a
    /// cache that is behind, or a currency that the newest declaration left out, the last rate may be days old.
    ///
    /// - Returns: The rate to fix, or nil when none may be fixed yet: for crowns, for a rate that should be in the
    ///   cache and is not, for a currency the ČNB does not quote, for a cache that is behind and for a currency whose
    ///   last rate is older than the newest declaration.
    static func rateToFix(
        currency: CurrencyCode, duzp: CivilDate, lookup: RateLookupResult, latestBefore: StoredRate?,
        expectedNewestDeclaration: CivilDate, newestCachedDeclaration: CivilDate?
    ) -> StoredRate? {
        guard !currency.isCZK else { return nil }
        switch lookup {
        case .declared:
            return rateForIssue(currency: currency, duzp: duzp, lookup: lookup, latestBefore: latestBefore)
        case .notPublished:
            return nil
        case .notYetAvailable:
            guard duzp > expectedNewestDeclaration, let newestCachedDeclaration,
                newestCachedDeclaration >= expectedNewestDeclaration,
                let latestBefore, latestBefore.declaredOn >= expectedNewestDeclaration
            else { return nil }
            return latestBefore
        }
    }

    /// The years of the ČNB files that would fill the gap in front of the rate of `duzp`: the year of the declaration
    /// the DUZP needs (the newest one that should exist, for a DUZP that is ahead of it), and the year before it for
    /// the first declaration of a year, which needs the last declaration of the year before to tell a day the ČNB
    /// skipped. New Year's Day and the days up to the first declaration take the rate of the last business day of the
    /// year before, and so need that year alone.
    static func yearsToFetch(duzp: CivilDate, expectedNewestDeclaration: CivilDate) -> [Int] {
        let needed =
            duzp > expectedNewestDeclaration ? expectedNewestDeclaration : CzechCalendar.rateDeclarationDay(for: duzp)
        guard let newYear = CivilDate(year: needed.year, month: 1, day: 1),
            needed <= CzechCalendar.nextBusinessDay(onOrAfter: newYear)
        else { return [needed.year] }
        return [needed.year, needed.year - 1]
    }
}
