import Foundation
import Observation

/// Why the sheet cannot save a payment.
nonisolated enum PaymentSheetError: Error, Equatable {
    /// There is no payment to save: the amount from the bank is missing or is not an amount, or the rate to convert
    /// the money with is not there.
    case noPayment

    /// The invoice was changed, by an import or by another edit, after the sheet was opened. Saving the payment on the
    /// invoice as the sheet knows it would undo that change.
    case invoiceChanged

    /// The day the money arrived is outside the days a payment can have; the text says why.
    case dateOutOfRange(String)
}

/// One of the ways to work out the income in crowns that the sheet offers, as a line with a title, a smaller line and
/// the value.
nonisolated struct PaymentOption: Equatable, Sendable {
    var title: String
    var detail: String
    var value: String
}

/// Why the payment by the method of the year is converted at a rate that stands in for the ČNB rate of its day (a
/// provisional payment), as the option of the method says it.
nonisolated enum PaymentStandIn: Equatable, Sendable {
    /// The ČNB has not declared the rate of the day yet.
    case notDeclaredYet

    /// The ČNB has declared the rate of the day by now, and only the database lacks it: its yearly file could not be
    /// downloaded.
    case notDownloaded

    /// The database has the rate of the day by now. The payment is the stored one, kept as it is, which was worked out
    /// before the rate came; the app converts it again with the rate (`AppModel.ratesUpdated()`), not the sheet.
    case rateCameSince
}

/// The sheet of the payment of an invoice: "Označit jako uhrazenou" for an invoice that has none, "Upravit platbu" for
/// one that has a payment, which the sheet opens on. It shows the day the money arrived, the income in crowns it is
/// worth and what it adds to the levies of its year, and saves it.
///
/// A payment the invoice has can be removed in a second step of the same sheet (`removal`), which "Odebrat platbu…"
/// shows in place of the payment and Zpět leaves again, with what was typed in either kept; the step only asks for the
/// number of the invoice (`typedNumber`), and the screen removes the payment.
///
/// A stored payment is kept exactly as it is, with its rate, while the day, the choice between the method of the year
/// and the amount from the bank, and that amount are as stored (`work(out:)`): the sheet shows it, and saving it writes
/// nothing. Only another day, another choice or another amount works the payment out afresh.
///
/// The income is converted by the method the year the money arrived in uses (`YearFXState.effective`): the ČNB rate of
/// the day, or the uniform rate of the year when it is chosen and the year has it, unless the person says the bank
/// credited crowns and types the amount. A payment in a currency whose uniform rate the year does not have is converted
/// at the ČNB rate of the day, and saving it turns the whole year to those rates until it has the rate
/// (`AppModel.recomputePaymentsAfterChanges(inYears:)`), which the notice says. A payment in a year that lacks the
/// uniform rate of another currency it was paid in is converted at the ČNB rate of the day too, and the notice names
/// that currency. An invoice that has no rate of its own (imported unpaid) is converted with the latest rate known on
/// or before its DUZP when the rate of the day is not there yet, never at nothing. A rate of the day that the ČNB has
/// declared but the database lacks (a past year whose file could not be downloaded) is asked for when the payment is
/// worked out afresh (`recompute()`).
///
/// The day the money arrived lies between a year before the invoice was issued and today (`dateError`): a mistyped
/// year would quietly move the income into another year.
@MainActor
@Observable
final class PaymentSheetModel {
    /// The invoice as the sheet was opened with it. The payment is saved on it only while it is still as it was.
    let invoice: Invoice

    /// The day the money arrived. The year of it is the year the income belongs to.
    var date: CivilDate

    /// Whether the bank credited crowns, and the amount it credited for the whole invoice as typed.
    var useBankCZK = false
    var bankCZKText = ""

    /// The payment as it would be stored for the day and the choice, or nil while there is none to save. While the day,
    /// the choice and the amount typed are as stored, it is the stored payment itself.
    private(set) var preview: Payment?

    /// What the payment adds to the levies of its year on its day.
    private(set) var effect: ReceiptEffect?

    /// A line under the options: the year set to the uniform rate cannot convert the payment at it, and why, as every
    /// screen says it on the day of the app (`BuilderText.uniformRateMissing(_:year:)`): the year lacks the uniform
    /// rate of the currency of the payment, or has it and lacks that of another currency it was paid in, which the
    /// line names; or no rate is there.
    private(set) var notice: String?

    /// What is wrong with the amount typed, or nil.
    private(set) var bankCZKError: String?

    /// The payment by the method of the year, whichever is chosen, so that its option can show its value: the stored
    /// payment while the day is the stored one and the stored payment is converted the way the year converts now.
    private(set) var methodPayment: Payment?

    /// The method the payment is converted with by the method of the year the money arrived in: the uniform rate when
    /// the year uses it and has it for the currency, otherwise the ČNB rate of the day.
    private(set) var method = IncomeFXMethod.cnbDaily

    /// Why the payment by the method of the year is worked out with a rate that stands in for the ČNB rate of its day,
    /// or nil when it is not.
    private(set) var standIn: PaymentStandIn?

    /// Whether the payment by the method of the year is worked out with a rate that stands in for the ČNB rate of its
    /// day: it is provisional (`standIn`).
    var usesStandInRate: Bool {
        standIn != nil
    }

    /// The payment by the amount typed, when it is an amount.
    private var bankPayment: Payment?

    private let app: AppModel

    /// How many recomputations have started. Only the latest may show its result: one that was started for a date or a
    /// choice that has been replaced since must not undo the newer one.
    @ObservationIgnored private var recomputesStarted = 0

    /// The years whose yearly ČNB files the sheet asked for. A year is asked for once while the sheet is open.
    @ObservationIgnored private var askedYears: Set<Int> = []

    /// The date and the choices the preview was worked out for.
    @ObservationIgnored private var previewInputs: Inputs?

    private struct Inputs: Equatable {
        var date: CivilDate
        var useBankCZK: Bool
        var bankCZKText: String
    }

    /// The sheet for `invoice`: the day shown, or the day of issue when that is later, as the day the money arrived,
    /// but never a day after today, which the sheet would refuse (`dateError`): the reporting cutoff can be later than
    /// today (for the current year it is the end of the current month), and an invoice can be issued later than today.
    /// For an invoice that has a payment already, that payment as it is stored.
    init(app: AppModel, invoice: Invoice) {
        self.app = app
        self.invoice = invoice
        if let payment = invoice.payment {
            date = payment.date
            useBankCZK = payment.conversion == .bankCZK
            bankCZKText = payment.bankCZKTotalHalere.map { CzechFormat.amount($0) } ?? ""
        } else {
            date = min(max(app.asOf.asOf, invoice.issueDate), app.today)
        }
    }

    // MARK: Texts

    /// Whether the sheet changes the payment the invoice has already, rather than recording its first one.
    var isEditing: Bool {
        invoice.payment != nil
    }

    /// The title of the sheet: "Označit jako uhrazenou", or "Upravit platbu" for an invoice that has a payment
    /// already, which the sheet opens on; in the removal step, its own ("Odebrat platbu faktury 20260902?").
    var title: String {
        if let removal {
            return removal.title
        }
        return isEditing ? "Upravit platbu" : "Označit jako uhrazenou"
    }

    /// The label of the button that saves: "Označit jako uhrazenou", or "Uložit platbu" for an invoice that has a
    /// payment already.
    var saveTitle: String {
        isEditing ? "Uložit platbu" : "Označit jako uhrazenou"
    }

    /// Why the day the money arrived cannot be saved, or nil when it can: it is after today (`AppModel.today`), or more
    /// than a year before the invoice was issued (`earliestDay(issuedOn:)`), which a mistyped year would make, moving
    /// the income into another year.
    var dateError: String? {
        if date > app.today {
            return "Datum přijetí nemůže být později než dnes."
        }
        if date < Self.earliestDay(issuedOn: invoice.issueDate) {
            return "Datum přijetí je víc než rok před vystavením faktury."
        }
        return nil
    }

    /// The earliest day money can arrive for an invoice issued on `issueDate`: the same day a year earlier, or the
    /// last day of February for an invoice of 29 February. An invoice of the year 1, which has no year before it in
    /// the calendar, takes its own day.
    nonisolated static func earliestDay(issuedOn issueDate: CivilDate) -> CivilDate {
        let year = issueDate.year - 1
        let day = min(issueDate.day, CivilDate.daysInMonth(year: year, month: issueDate.month))
        return CivilDate(year: year, month: issueDate.month, day: day) ?? issueDate
    }

    /// The amount of the invoice with VAT, in its currency: "5 445,00 Kč".
    var totalText: String {
        CzechFormat.money(Money(minor: invoice.totalMinor, currency: invoice.currency))
    }

    /// "Faktura 20260902 · Cetus Data s.r.o. · 5 445,00 Kč"; in the removal step, its own ("Cetus Data s.r.o. ·
    /// zaplaceno 15. 10. 2026 · 5 445,00 Kč").
    var subtitle: String {
        if let removal {
            return removal.subtitle
        }
        return "Faktura \(invoice.number) · \(invoice.client.name) · \(totalText)"
    }

    /// What an invoice in crowns is worth as income, and where its VAT goes. Nil for an invoice in a foreign currency.
    var crownText: String? {
        guard invoice.currency.isCZK, let preview else { return nil }
        var text = "Příjem \(CzechFormat.halere(preview.czkNetHalere))"
        if preview.czkVatHalere != 0 {
            let month = CzechFormat.monthNames[invoice.duzp.month - 1]
            text += ", DPH \(CzechFormat.halere(preview.czkVatHalere)) patří do přiznání k DPH za \(month)"
        }
        return text + "."
    }

    /// The method of the year: the ČNB rate of the day, or the uniform rate of the year. Nil for an invoice in crowns.
    /// The rate is written with the quantity it is quoted for, "6,220 Kč/100 HUF". While there is no payment worked out
    /// with a rate, it says that the rate is not available yet. A rate that stands in for the rate of the day says so
    /// and why (`standIn`): "kurz zatím nevyhlášen, předběžně 21,522 Kč/USD"; a stored payment kept as it is after the
    /// rate of its day came says only "předběžně 21,522 Kč/USD", as the reason it was given no longer holds.
    var methodOption: PaymentOption? {
        guard !invoice.currency.isCZK else { return nil }
        let cnbTitle = "Kurz ČNB ke dni přijetí"
        guard let payment = methodPayment, let rate = payment.rate else {
            return PaymentOption(title: cnbTitle, detail: "kurz zatím není k dispozici", value: "—")
        }
        let rateLabel = CzechFormat.rateLabel(rate.rate)
        let value = CzechFormat.halere(payment.czkNetHalere)
        if payment.conversion == .uniform {
            let year = payment.date.year
            return PaymentOption(
                title: "Jednotný kurz za rok \(year)", detail: "\(rateLabel) · přepočet zvolený pro rok \(year)",
                value: value)
        }
        let day = CzechFormat.date(payment.date)
        let detail: String
        switch standIn {
        case .notDeclaredYet: detail = "\(day) · kurz zatím nevyhlášen, předběžně \(rateLabel)"
        case .notDownloaded: detail = "\(day) · kurz ČNB zatím není stažený, předběžně \(rateLabel)"
        case .rateCameSince: detail = "\(day) · předběžně \(rateLabel)"
        case nil: detail = "\(day) · \(rateLabel)"
        }
        return PaymentOption(title: cnbTitle, detail: detail, value: value)
    }

    /// The amount the bank credited. Nil for an invoice in crowns.
    var bankOption: PaymentOption? {
        guard !invoice.currency.isCZK else { return nil }
        return PaymentOption(
            title: "Částka v Kč podle banky", detail: "jen když peníze přišly přímo v Kč",
            value: bankPayment?.bankCZKTotalHalere.map { CzechFormat.halere($0) } ?? "—")
    }

    /// The heading of what the payment adds to the levies of the year of the day in the sheet: "Odvody za rok 2026
    /// vzrostou o", or "Dopad platby na odvody 2026" for an invoice that has a payment already.
    var effectHeading: String {
        isEditing ? "Dopad platby na odvody \(date.year)" : "Odvody za rok \(date.year) vzrostou o"
    }

    /// "+1 702 Kč".
    var effectTotalText: String? {
        effect.map { InvoiceDetailBuilder.signed($0.total) + "\u{00A0}Kč" }
    }

    /// "37,8 % z příjmu 4 500,00 Kč", and the thresholds of the year the income reaches: "37,8 % z příjmu 4 500,00 Kč.
    /// Celá platba je nad stropem paušálu (příjmy 2 mil. Kč), kde je celý další příjem ziskem."
    var effectShareText: String? {
        guard let effect, let preview else { return nil }
        let share = InvoiceDetailBuilder.share(of: effect, income: preview.czkNetHalere) ?? "—"
        let text = "\(share) z příjmu \(CzechFormat.halere(preview.czkNetHalere))"
        guard let thresholds = InvoiceDetailBuilder.thresholdsText(of: effect) else { return text }
        return text + ". " + thresholds
    }

    var effectRows: [EffectRow] {
        effect.map { InvoiceDetailBuilder.effectRows($0) } ?? []
    }

    /// What to tell the person when saving failed with `error`.
    static func failureText(for error: any Error) -> String {
        if let error = error as? InvoiceError, error == .notFound {
            return "Faktura mezitím byla smazána."
        }
        switch error as? PaymentSheetError {
        case .invoiceChanged: return "Faktura se mezitím změnila. Zavřete toto okno a zkuste to znovu."
        case .noPayment: return "Platbu zatím nejde uložit."
        case .dateOutOfRange(let text): return text
        case nil: return "Platbu se nepodařilo uložit."
        }
    }

    // MARK: The removal step

    /// What the removal step says, while the sheet shows it in place of the payment: the step that removes the payment
    /// the invoice has, which "Odebrat platbu…" opens (`showRemoval(_:)`) and Zpět closes (`showPayment()`). Nil while
    /// the sheet shows the payment.
    private(set) var removal: PaymentRemovalSummary?

    /// The number typed in the removal step to confirm it. It stays while the sheet goes back to the payment and shows
    /// the step again, and goes with the sheet.
    var typedNumber = ""

    /// Whether the number typed in the removal step is the number of the invoice, or the digits of it
    /// (`DeleteConfirmation`): only then can Odebrat platbu remove the payment.
    var typedNumberMatches: Bool {
        DeleteConfirmation.matches(typed: typedNumber, number: removal?.number ?? invoice.number)
    }

    /// "Odebrat platbu…": the sheet shows the removal step, which says what `summary` says, with the number typed so
    /// far.
    func showRemoval(_ summary: PaymentRemovalSummary) {
        removal = summary
    }

    /// Zpět, or Esc, in the removal step: the sheet shows the payment again, with the day, the choice and the amount as
    /// they were typed.
    func showPayment() {
        removal = nil
    }

    // MARK: Working it out

    /// Works out the payment, its effect on the levies and the notice again, for the date and the choices as they are
    /// now. A failure is logged (the domain and the code of the error alone) and leaves no payment to save.
    ///
    /// When the ČNB has declared the rate of the day but the database does not have it (the yearly file of a past year
    /// could not be downloaded), the yearly files that bring it are asked for, each once while the sheet is open, and
    /// the payment is worked out again when they brought rates. A stored payment that is kept as it is needs no rate,
    /// and nothing is asked for it.
    func recompute() async {
        recomputesStarted += 1
        let thisRun = recomputesStarted
        let inputs = Inputs(date: date, useBankCZK: useBankCZK, bankCZKText: bankCZKText)
        let worked: Worked
        do {
            worked = try await work(out: inputs)
        } catch {
            guard thisRun == recomputesStarted else { return }
            AppModel.log("Working out a payment", failedWith: error)
            preview = nil
            methodPayment = nil
            bankPayment = nil
            standIn = nil
            notice = "Příjem se nepodařilo přepočítat."
            bankCZKError = nil
            effect = nil
            previewInputs = nil
            return
        }
        guard thisRun == recomputesStarted else { return }
        preview = worked.preview
        methodPayment = worked.methodPayment
        bankPayment = worked.bankPayment
        method = worked.method
        standIn = worked.standIn
        notice = worked.notice
        bankCZKError = worked.bankCZKError
        effect = worked.effect
        previewInputs = inputs
        if await askForRates(inYears: worked.rateYears) {
            await recompute()
        }
    }

    /// Asks the refresh for the yearly ČNB files of `years` that the sheet has not asked for yet, and says whether
    /// rates were stored. The download is not cut short when the date changes, which cancels the task that waits for
    /// it.
    private func askForRates(inYears years: [Int]) async -> Bool {
        let new = years.filter { !askedYears.contains($0) }
        guard !new.isEmpty, let refresh = app.refresh else { return false }
        askedYears.formUnion(new)
        return await Task { await refresh.fetchYears(new) }.value
    }

    /// What `work(out:)` worked out for the date and the choices of one recomputation, which `recompute()` shows when
    /// it is still the latest one.
    private struct Worked {
        var preview: Payment?
        var methodPayment: Payment?
        var bankPayment: Payment?
        var method: IncomeFXMethod
        var standIn: PaymentStandIn?

        /// The yearly ČNB files that would bring the rate of the day, which the ČNB has declared and the database
        /// lacks, for a payment by the method of the year that is worked out afresh.
        var rateYears: [Int] = []
        var notice: String?
        var bankCZKError: String?
        var effect: ReceiptEffect?
    }

    /// Works out the payment for `inputs` with the rates and the method of the year of its day, as the database has
    /// them now: the payment by the method of the year, the one by the amount typed, which of them is the preview, the
    /// notice and what the preview adds to the levies. The stored payment of the invoice is kept exactly as it is: as
    /// the payment by the method while its day is the day of `inputs` and it is converted the way the year converts
    /// now, and as the payment by the amount from the bank while that amount is the one typed. Throws what the
    /// database throws, and `VaultError.locked` while the data is locked.
    private func work(out inputs: Inputs) async throws -> Worked {
        guard let database = app.database else { throw VaultError.locked }
        let day = inputs.date
        let isForeign = !invoice.currency.isCZK
        var worked = Worked(method: .cnbDaily)
        var basis = invoice
        var cnbRate = RateLookupResult.notYetAvailable
        var isDeclared = true
        var uniformRate: ExchangeRate?
        // Why the year, set to the uniform rate, cannot convert this payment at it. Nil when it can or is not set so.
        var missingUniformRate: UniformAvailability?
        if isForeign {
            let conversion = try await app.fxState(year: day.year)
            cnbRate = try await database.cnbRate(invoice.currency, on: day)
            let rateOfTheYear = try await database.uniformRate(invoice.currency, year: day.year)?.exchangeRate
            if conversion.effective == .uniform, let rateOfTheYear {
                worked.method = .uniform
                uniformRate = rateOfTheYear
            }
            // Set to the uniform rate, but unable to use it: the payment is converted at the ČNB rate of its day, as
            // the whole year is — or will be once it is saved. The year lacks the rate of this currency: a year
            // without any uniform rate says where the search for it stands, and one with rates of other currencies
            // lacks this one. Or it has the rate of this currency but lacks that of another currency it was paid in,
            // which the notice names: the whole year is at the daily rates until it has that one, and so is
            // this payment.
            if conversion.chosen == .uniform {
                if rateOfTheYear == nil {
                    switch conversion.uniform {
                    case .notPublishedYet, .searchedFor, .notInApp: missingUniformRate = conversion.uniform
                    case .ready, .missingCurrency: missingUniformRate = .missingCurrency(invoice.currency)
                    }
                } else if case .missingCurrency(let other) = conversion.uniform {
                    missingUniformRate = .missingCurrency(other)
                }
            }
            // The rate of the day is not declared yet: the invoice's own rate stands in, and for an invoice without one
            // the latest rate known up to its DUZP, so that the payment is never worth nothing.
            if case .declared = cnbRate {
                isDeclared = true
            } else {
                isDeclared = false
            }
            if !isDeclared && basis.invoiceRate == nil {
                basis.invoiceRate = try await database.latestCNBRate(invoice.currency, onOrBefore: invoice.duzp)
            }
        }

        let requested: PaymentConversion
        if !isForeign {
            requested = .czk
        } else {
            requested = worked.method == .uniform ? .uniform : .cnbDaily
        }
        // The keep rule: the stored payment stays exactly as it is, with its rate, while its day is the day in the
        // sheet and it is converted the way the year converts now; an amount from the bank stays while the amount
        // typed is the one stored. A rate that stood in for the rate of the day stays too, even once that rate has
        // come: the app converts the stored payment again then, not the sheet. Anything else is worked out afresh.
        let storedOfTheDay = invoice.payment.flatMap { $0.date == day ? $0 : nil }
        let keptByMethod = storedOfTheDay.flatMap { $0.conversion == requested ? $0 : nil }
        let byMethod =
            keptByMethod
            ?? PaymentConverter.convert(
                invoice: basis, date: day, requested: requested, bankCZKTotalHalere: nil, cnbRate: cnbRate,
                uniformRate: uniformRate)
        let methodIsWorthNothing = isForeign && byMethod.rate == nil
        worked.methodPayment = methodIsWorthNothing ? nil : byMethod
        // The ČNB rate of the day is what the method needs (the uniform rate needs none), and the ČNB has declared it
        // by now: only the database lacks it, and the yearly files may bring it. A payment that is kept as it is needs
        // no rate, so nothing is asked for it.
        var rateIsNotDownloaded = false
        if isForeign, requested == .cnbDaily, case .notYetAvailable = cnbRate {
            let expected = RefreshPlanner.expectedNewestDeclaration(now: app.dependencies.clock.now())
            if CzechCalendar.rateDeclarationDay(for: day) <= expected {
                rateIsNotDownloaded = true
                if keptByMethod == nil {
                    worked.rateYears = InvoiceRateFixing.yearsToFetch(duzp: day, expectedNewestDeclaration: expected)
                }
            }
        }
        // A payment worked out afresh is provisional only while the rate of the day is not declared; a stored one
        // that is kept may be provisional once it is.
        if byMethod.provisional {
            if isDeclared {
                worked.standIn = .rateCameSince
            } else {
                worked.standIn = rateIsNotDownloaded ? .notDownloaded : .notDeclaredYet
            }
        }

        if isForeign {
            let typed = inputs.bankCZKText.trimmingCharacters(in: .whitespacesAndNewlines)
            if !typed.isEmpty {
                switch AmountParser.minor(typed) {
                case nil:
                    worked.bankCZKError = "Zadejte částku ve tvaru 13 340 nebo 13 340,50."
                case let halere? where halere <= 0:
                    worked.bankCZKError = "Zadejte částku větší než nula."
                case let halere?:
                    if let stored = storedOfTheDay, stored.conversion == .bankCZK, stored.bankCZKTotalHalere == halere {
                        worked.bankPayment = stored
                    } else {
                        worked.bankPayment = PaymentConverter.convert(
                            invoice: basis, date: day, requested: .bankCZK, bankCZKTotalHalere: halere,
                            cnbRate: cnbRate, uniformRate: uniformRate)
                    }
                }
            }
        }

        if isForeign && inputs.useBankCZK {
            worked.preview = worked.bankPayment
        } else {
            worked.preview = worked.methodPayment
            if methodIsWorthNothing {
                worked.notice =
                    "Kurz ČNB ke dni přijetí zatím není k dispozici – bez něj nejde příjem přepočítat."
                    + " Počkejte na stažení kurzů nebo zadejte částku v Kč podle banky."
            } else if let missingUniformRate,
                let reason = BuilderText.uniformRateMissing(missingUniformRate, year: day.year)
            {
                worked.notice =
                    "Jednotný kurz \(day.year): \(reason). Platba i celý rok \(day.year) se proto zatím přepočtou"
                    + " kurzem ČNB ke dni přijetí."
            }
        }

        if let payment = worked.preview, invoice.status == .issued {
            let receipt = Receipt(
                day: day, czkNetHalere: payment.czkNetHalere, czkVatHalere: payment.czkVatHalere,
                source: .invoice(invoice.id))
            do {
                worked.effect = try await app.effect(of: receipt)
            } catch {
                // The payment can be saved without the figure; the sheet only leaves out what it would add.
                AppModel.log("Working out what a payment adds to the levies", failedWith: error)
            }
        }
        return worked
    }

    // MARK: Saving

    /// Stores the payment on the invoice, tells the app of the write and shows the detail of the invoice, which shows
    /// the payment; no banner says so. An invoice to check is resolved by it: the review flag goes, and an imported
    /// invoice is marked as changed in the app, so that a later import keeps this version. The year of the payment,
    /// and the year of the payment it replaces, are converted again by the method each uses then, as the payment may
    /// give them a currency without the uniform rate, and a choice made while the sheet was open may have changed the
    /// method (`AppModel.recomputePaymentsAfterChanges(inYears:)`).
    ///
    /// The stored payment that the sheet keeps as it is, while the day, the choice and the amount typed are as stored
    /// (`work(out:)`), changes nothing, and nothing is written: the database is not called, an imported invoice is not
    /// marked as changed in the app, no year is converted again and the app is told of no write. The sheet just closes.
    ///
    /// A payment is saved in one call on the database, and only while the invoice is still as the sheet knows it.
    /// Throws `PaymentSheetError.dateOutOfRange` for a day that `dateError` refuses, `PaymentSheetError.noPayment`
    /// when there is no payment to save, `InvoiceError.notFound` when the invoice was deleted meanwhile (it is never
    /// brought back), `PaymentSheetError.invoiceChanged` when it was changed, and what the database throws.
    func save() async throws {
        if let dateError {
            throw PaymentSheetError.dateOutOfRange(dateError)
        }
        if previewInputs != Inputs(date: date, useBankCZK: useBankCZK, bankCZKText: bankCZKText) {
            await recompute()
        }
        guard let payment = preview else { throw PaymentSheetError.noPayment }
        var updated = invoice
        updated.payment = payment
        updated.review = nil
        // Nothing changed: the payment is the stored one, kept as it is, and the invoice has nothing to resolve.
        guard updated != invoice else { return }
        guard let database = app.database else { throw VaultError.locked }
        if case .imported(let fakturoidID, let fingerprint, _) = updated.source {
            updated.source = .imported(fakturoidID: fakturoidID, fingerprint: fingerprint, changedInApp: true)
        }
        guard try await database.saveInvoice(updated, ifUnchangedFrom: invoice) else {
            if try await database.invoice(id: invoice.id) == nil {
                throw InvoiceError.notFound
            }
            throw PaymentSheetError.invoiceChanged
        }
        // The year of the payment, and the year of the one it replaced, may use another method now that they have it.
        let years = Set([payment.date.year] + [invoice.payment?.date.year].compactMap { $0 })
        await app.recomputePaymentsAfterChanges(inYears: years)
        app.pendingDetailInvoiceID = invoice.id
        await app.didWrite()
    }
}
