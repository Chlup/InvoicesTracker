import Foundation

/// Payments converted again: when new ČNB rates arrive for the provisional ones, and when the method a year converts
/// its income in other currencies with may have changed: its choice, its uniform rate or its payments.
///
/// Every such conversion takes its turn (`convertPaymentsInTurn(_:)`): it starts once every conversion asked for before
/// it has ended, so it lists the payments with what those wrote and converts them by what the year has then. Otherwise
/// a conversion that read the method or the rates of a year before they changed could write a payment after the
/// conversion that the change asked for had listed it, and the payment would keep the conversion of before, with
/// nothing to convert it again.
extension AppModel {
    // MARK: One conversion at a time

    /// Runs `pass` in its turn: once every conversion of payments asked for before it has ended, on the data that is
    /// open now, which `pass` reads and writes alone. Returns what `pass` returned, or nil when it did not run: the
    /// data is locked now, or by the time its turn came it was replaced (`adopt(_:)`, a restore) or let go (a lock),
    /// so that a choice or a conversion asked for before never reaches the data opened after it.
    ///
    /// Every conversion of payments asks for its turn here, where it starts: a choice of how a year converts its income
    /// (`setFXMethod(_:year:)`), new ČNB rates (`ratesUpdated()`), a uniform rate stored or removed
    /// (`convertPaymentsAfterUniformRatesChanged(year:)`), payments that changed
    /// (`recomputePaymentsAfterChanges(inYears:)`) and the stand-ins of an earlier version
    /// (`convertUniformStandIns()`). What `pass` is made of never asks for a turn (`recomputePayments(year:in:)`,
    /// `recomputePayments(of:in:)`): a turn waits only for the turns asked for before it, so one that asked for another
    /// turn and waited for it would wait for its own end. Nor does `pass` wait for a step of Zabezpečení a zálohy
    /// (`runSecurityStep(_:)`), which may itself wait for a turn.
    @discardableResult
    func convertPaymentsInTurn<T: Sendable>(_ pass: @escaping @MainActor (Database) async -> T) async -> T? {
        guard let queuedFor = database else { return nil }
        let previous = latestConversion
        let turn = Task { () -> T? in
            await previous?.value
            guard self.database === queuedFor else { return nil }
            return await pass(queuedFor)
        }
        latestConversion = Task { _ = await turn.value }
        return await turn.value
    }

    /// Tells the app of `saved` payments written to `database` (`didWrite()`), when there are any and it is the data
    /// that is open: a conversion that was running when the data was replaced wrote to the data before, and what the
    /// app does after a write is about the data that is open.
    private func tellOfWrites(_ saved: Int, to database: Database) async {
        guard saved > 0, self.database === database else { return }
        await didWrite()
    }

    // MARK: Converting payments

    /// Converts payments again with `PaymentConverter.convert`, by the method the year of each payment uses now
    /// (`YearFXState.effective`): the provisional ones of every year when `year` is nil (new ČNB rates came), otherwise
    /// every payment of `year` but those of an amount from the bank (its choice, its uniform rate or its payments
    /// changed). A year set to the uniform rate that does not have it for every currency it was paid in is converted at
    /// the ČNB rates of the days, so switching back and forth gives every payment the very amount it had. A payment
    /// that would be worth nothing, for want of a rate, stays as it is. Everything is read from `database` and written
    /// to it. Throws what the database throws.
    ///
    /// A step of a conversion in its turn (`convertPaymentsInTurn(_:)`), which it never asks for itself.
    func recomputePayments(year: Int?, in database: Database) async throws {
        let invoices: [Invoice]
        if let year {
            invoices = try await database.paidInvoices(year: year)
        } else {
            invoices = try await database.provisionalPayments()
        }
        try await recomputePayments(of: invoices, in: database)
    }

    /// Converts the payments of `invoices` again (see `recomputePayments(year:in:)`) and saves each that changed to
    /// `database`, and then tells of the write (`didWrite()`). An invoice that is not stored as it was listed any
    /// more — deleted meanwhile, or changed — is left to whatever changed it: it is never brought back or overwritten
    /// (see `Database.saveInvoice(_:ifUnchangedFrom:)`). An invoice imported from Fakturoid keeps its source as it is,
    /// because the conversion follows from its row and the rates. Returns how many were saved.
    ///
    /// The invoice that the editor holds is converted and saved like any other, with changes typed in the editor or
    /// without. The editor then edits it as it is saved (`InvoiceEditorModel.rebase(onto:replacing:)`), so that the
    /// app's own conversion never makes the editor's save refuse it as changed meanwhile; an editor that held the
    /// invoice as it was before a change made elsewhere takes nothing, and its save is still refused. Neither the
    /// editor nor the app is told of what is written once `database` is not the data that is open any more.
    ///
    /// A step of a conversion in its turn (`convertPaymentsInTurn(_:)`), which it never asks for itself.
    @discardableResult
    func recomputePayments(of invoices: [Invoice], in database: Database) async throws -> Int {
        var methods: [Int: IncomeFXMethod] = [:]
        var saved = 0
        do {
            for listed in invoices {
                guard let payment = listed.payment, payment.conversion != .bankCZK else { continue }
                let year = payment.date.year
                let method: IncomeFXMethod
                if let known = methods[year] {
                    method = known
                } else {
                    method = try await database.effectiveFXMethod(year: year)
                    methods[year] = method
                }
                let converted = try await convert(listed, paidOn: payment.date, method: method, in: database)
                guard converted != payment, !Self.isWorthNothing(converted) else { continue }
                var updated = listed
                updated.payment = converted
                if try await database.saveInvoice(updated, ifUnchangedFrom: listed) {
                    saved += 1
                    if self.database === database {
                        await editor?.rebase(onto: updated, replacing: listed)
                    }
                }
            }
        } catch {
            await tellOfWrites(saved, to: database)
            throw error
        }
        await tellOfWrites(saved, to: database)
        return saved
    }

    /// The payment of `invoice` received on `date`, converted by `method` with the rates in `database`; an invoice in
    /// crowns is worth its own amounts, and the uniform rate of a currency that its year does not have gives way to
    /// the ČNB rate of the day. The invoice editor converts the payment of an invoice it changed with it too.
    func convert(
        _ invoice: Invoice, paidOn date: CivilDate, method: IncomeFXMethod, in database: Database
    ) async throws -> Payment {
        let requested: PaymentConversion
        if invoice.currency.isCZK {
            requested = .czk
        } else {
            requested = method == .uniform ? .uniform : .cnbDaily
        }
        var uniformRate: ExchangeRate?
        if requested == .uniform {
            uniformRate = try await database.uniformRate(invoice.currency, year: date.year)?.exchangeRate
        }
        let cnbRate = try await database.cnbRate(invoice.currency, on: date)
        return PaymentConverter.convert(
            invoice: invoice, date: date, requested: requested, bankCZKTotalHalere: nil, cnbRate: cnbRate,
            uniformRate: uniformRate)
    }

    /// Whether `payment` is a conversion at a rate that had no rate to convert with: it would be worth nothing.
    nonisolated static func isWorthNothing(_ payment: Payment) -> Bool {
        (payment.conversion == .cnbDaily || payment.conversion == .uniform) && payment.rate == nil
    }
}

// MARK: - The conversion of a year

/// What `AppModel.setFXMethod(_:year:)` did.
nonisolated enum FXMethodChange: Sendable, Equatable {
    /// The choice is stored, and the payments of the year, and of the later years that take their choices from it,
    /// are converted by the method each uses now.
    case saved

    /// Nothing is stored: the year has that choice already, or the choice is the uniform rate, which the year cannot
    /// use (`UniformAvailability.isReady`): it is not published yet, the app looks for it, the app does not have it, or
    /// it lacks the rate of a currency the year was paid in.
    case unchanged

    /// The choice could not be stored, the data is locked, or other data was opened before the choice's turn came
    /// (`AppModel.convertPaymentsInTurn(_:)`): nothing changed.
    case notSaved

    /// The choice is stored, but the payments of `year` could not be converted again: of the year chosen or of a later
    /// year that takes its choice, whichever is the first of them that failed.
    case paymentsNotConverted(year: Int)
}

nonisolated extension FXMethodChange {
    /// "Změnu se nepodařilo uložit.": what a screen says of a choice that could not be stored.
    static let notSavedText = "Změnu se nepodařilo uložit."

    /// "Změna je uložená, platby roku 2025 se ale nepodařilo přepočítat.": what a screen says of a change that is
    /// stored, whose payments of `year` could not be converted again.
    static func paymentsNotConvertedText(year: Int) -> String {
        "Změna je uložená, platby roku \(year) se ale nepodařilo přepočítat."
    }

    /// Whether the choice is stored, with its payments converted again or not.
    var isStored: Bool {
        switch self {
        case .saved, .paymentsNotConverted: true
        case .unchanged, .notSaved: false
        }
    }

    /// What a screen says of the choice when it did not do all it was asked to: one of the texts above, naming the year
    /// whose payments could not be converted, and nil for a choice that is stored with its payments, or that had
    /// nothing to store.
    var failureText: String? {
        switch self {
        case .saved, .unchanged: nil
        case .notSaved: Self.notSavedText
        case .paymentsNotConverted(let year): Self.paymentsNotConvertedText(year: year)
        }
    }
}

/// How a year converts its income in other currencies: what it can use, the choice, and its payments converted again
/// whenever the method it uses may have changed.
extension AppModel {
    /// How `year` converts its income in other currencies (`YearFXState`), with today deciding where a year without
    /// its uniform rate stands (`UniformRateSearch`): the rate is not published yet, the app looks for it once a day,
    /// or the app does not have it. Throws `VaultError.locked` while the data is locked, and what the database throws.
    func fxState(year: Int) async throws -> YearFXState {
        guard let database else { throw VaultError.locked }
        return try await database.fxState(year: year, today: today)
    }

    /// The levies of `year` (its tax, social and health insurance) with its payments in other currencies converted
    /// each way: at the ČNB rates of their days, and at the uniform rate of the year. They are those as of the day
    /// shown (`asOf`), and for a year other than the one shown as of the day the year menu would show it as of. Nil
    /// unless the year has payments in other currencies and its uniform rate (`UniformAvailability.isReady`), so that
    /// both methods can be chosen and the choice changes something.
    ///
    /// Each payment is converted from its invoice and its day as the year converts it when it switches
    /// (`recomputePayments(of:in:)`): an amount the bank credited in crowns stays, and so does a payment that would be
    /// worth nothing. So each figure is what Výpočet shows once the year converts that way, whichever way it converts
    /// now. Nothing is stored. Throws `ComputationError.invalidYear` for stored values the computation does not take,
    /// `VaultError.locked` while the data is locked, and what the database throws.
    func levyComparison(year: Int) async throws -> (daily: Int64, uniform: Int64)? {
        guard let database else { throw VaultError.locked }
        let state = try await database.fxState(year: year, today: today)
        guard state.hasForeignPayments, state.uniform.isReady else { return nil }
        let day = dayShown(of: year)
        let input = try await yearInput(for: year).input
        let paid = try await database.paidInvoices(year: year)

        // The levies with each receipt of a payment in another currency converted by `method`.
        func levies(convertedBy method: IncomeFXMethod) async throws -> Int64 {
            var converted = input
            // A payment in crowns is worth its own amounts either way.
            for invoice in paid where !invoice.currency.isCZK {
                guard let payment = invoice.payment, payment.conversion != .bankCZK,
                    let index = converted.receipts.firstIndex(where: { $0.source == .invoice(invoice.id) })
                else {
                    continue
                }
                let other = try await convert(invoice, paidOn: payment.date, method: method, in: database)
                guard !Self.isWorthNothing(other) else { continue }
                converted.receipts[index].czkNetHalere = other.czkNetHalere
                converted.receipts[index].czkVatHalere = other.czkVatHalere
            }
            return try Self.compute(converted, asOf: day).liabilityTotal
        }

        let daily = try await levies(convertedBy: .cnbDaily)
        let uniform = try await levies(convertedBy: .uniform)
        return (daily: daily, uniform: uniform)
    }

    /// The day `year` is shown as of: the day of "K datu" for the year shown, and for another year the day the year
    /// menu would show it as of (`AsOfState.selectYear(_:today:)`).
    private func dayShown(of year: Int) -> CivilDate {
        guard year != asOf.year else { return asOf.asOf }
        var other = asOf
        other.selectYear(year, today: today)
        return other.asOf
    }

    /// Chooses how `year` converts its income in other currencies: stores the choice, converts the payments of the year
    /// again by the method it uses now (`recomputePayments(year:in:)`), and tells of the write (`didWrite()`). The
    /// uniform rate is chosen only for a year that has it (`UniformAvailability.isReady`); choosing it for another, or
    /// choosing what is chosen already, changes nothing. What could not be done is logged, and the result says what
    /// was.
    ///
    /// A year without settings of its own takes the choices of the nearest earlier year that has them
    /// (`Database.yearSettings(_:)`), so the later years up to the next one with settings of its own switch with
    /// `year`, and their payments are converted again too, up to the current year. They keep taking their choices from
    /// it: nothing is stored for them.
    ///
    /// A choice is a conversion in its turn (`convertPaymentsInTurn(_:)`), wherever it comes from (the menu of the
    /// toolbar, Nastavení › Rok): it reads what the year has only once the conversions asked for before it have
    /// stored what they store and converted their payments.
    @discardableResult
    func setFXMethod(_ method: IncomeFXMethod, year: Int) async -> FXMethodChange {
        await convertPaymentsInTurn { database in
            await self.storeFXMethod(method, year: year, in: database)
        } ?? .notSaved
    }

    /// `setFXMethod(_:year:)` in its turn, on `database`.
    private func storeFXMethod(_ method: IncomeFXMethod, year: Int, in database: Database) async -> FXMethodChange {
        do {
            let state = try await database.fxState(year: year, today: today)
            guard state.chosen != method, method == .cnbDaily || state.uniform.isReady else { return .unchanged }
            try await database.updateYearSettings(year) { $0.incomeFXMethod = method }
        } catch {
            Self.log("Saving the conversion of the income of a year", failedWith: error)
            return .notSaved
        }
        // The years whose payments could not be converted again. The later years count from the first of them when
        // the years with settings of their own, which tell how far they go, cannot be read.
        var failed: [Int] = []
        var later: [Int] = []
        if year < today.year {
            do {
                later = Self.yearsInheritingSettings(
                    of: year, storedYears: try await database.storedSettingsYears(), through: today.year)
            } catch {
                Self.log("Reading the years with settings of their own", failedWith: error)
                failed.append(year + 1)
            }
        }
        for converted in [year] + later {
            do {
                try await recomputePayments(year: converted, in: database)
            } catch {
                Self.log("Converting the payments of the year again", failedWith: error)
                failed.append(converted)
            }
        }
        // The choice is stored: a write, which the app is told of while the data written to is the data open.
        if self.database === database {
            await didWrite()
        }
        return failed.min().map { FXMethodChange.paymentsNotConverted(year: $0) } ?? .saved
    }

    /// The years after `year`, up to `lastYear`, that take their settings from it: those before the next year of
    /// `storedYears`, the years with settings of their own.
    nonisolated static func yearsInheritingSettings(of year: Int, storedYears: [Int], through lastYear: Int) -> [Int] {
        let nextOwn = storedYears.filter { $0 > year }.min() ?? Int.max
        let last = min(lastYear, nextOwn - 1)
        return year < last ? Array((year + 1)...last) : []
    }

    /// The uniform rates of `year` were stored or removed (Nastavení › Rok, the sheet of rates that were found): its
    /// payments are converted again in their turn, by the method the year uses then (`recomputePayments(year:in:)`),
    /// whatever the screen that changed the rates last read of the year. Returns whether they were; a failure is
    /// logged.
    func convertPaymentsAfterUniformRatesChanged(year: Int) async -> Bool {
        await convertPaymentsInTurn { database in
            do {
                try await self.recomputePayments(year: year, in: database)
                return true
            } catch {
                Self.log("Converting the payments of the year again", failedWith: error)
                return false
            }
        } ?? false
    }

    /// Converts again the payments that earlier versions of the app stored as provisional stand-ins for a uniform rate
    /// their year did not have (`.uniform`, at the ČNB rate of the day): a year without its uniform rate is converted
    /// at the ČNB rates of the days now, so each becomes the daily payment it stood in for, by the method its year
    /// uses (`recomputePayments(of:in:)`), in its turn. It runs when the app opens its data, so that none waits for the
    /// next ČNB rates; with none, nothing is written. A failure is logged, and the next ČNB rates convert them as
    /// before.
    func convertUniformStandIns() async {
        await convertPaymentsInTurn { database in
            do {
                let standIns = try await database.provisionalPayments().filter { $0.payment?.conversion == .uniform }
                guard !standIns.isEmpty else { return }
                try await self.recomputePayments(of: standIns, in: database)
            } catch {
                Self.log("Converting the stand-ins of uniform rates again", failedWith: error)
            }
        }
    }

    /// The payments of `years` changed: one was recorded or edited, an invoice was edited or deleted, an import added
    /// or changed some. Each of these years is converted again in its turn, by the method it uses then
    /// (`recomputePayments(year:in:)`), whatever it is set to. Whether it has the uniform rate of every currency it was
    /// paid in, and so the method it converts with, may have changed with them; and what changed them converted them
    /// outside the turns, by the method the year used when it did, which a choice stored before they were written may
    /// have changed since. A failure is logged: the year stays as it is until it is converted again.
    func recomputePaymentsAfterChanges(inYears years: Set<Int>) async {
        guard !years.isEmpty else { return }
        await convertPaymentsInTurn { database in
            for year in years.sorted() {
                do {
                    try await self.recomputePayments(year: year, in: database)
                } catch {
                    Self.log("Converting the payments of a changed year again", failedWith: error)
                }
            }
        }
    }
}
