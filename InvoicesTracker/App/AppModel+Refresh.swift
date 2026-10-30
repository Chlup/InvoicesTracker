import Foundation

/// The refresh of the open data, and what the model does with what it tells.
extension AppModel {
    /// A refresh of `database` that tells this model of a new day, of new ČNB rates and of the uniform rate. "Today"
    /// and its year are those of the clock in the time zone of the Mac, whatever year is selected.
    func makeRefresh(for database: Database) -> RefreshCoordinator {
        let clock = dependencies.clock
        let timeZone = dependencies.timeZone
        let refresh = RefreshCoordinator(
            clock: clock, scheduler: dependencies.scheduler, cnb: CNBFetcher(http: dependencies.http),
            gfr: GFRFetcher(http: dependencies.http), database: database,
            currentYear: { CivilDate.today(now: clock.now(), timeZone: timeZone()).year },
            followsToday: { [weak self] in self?.asOf.followsToday ?? false },
            timeZone: { timeZone() })
        refresh.onDayChanged = { [weak self] day in
            self?.handleDayChanged(day)
        }
        refresh.onRatesUpdated = { [weak self] in
            Task { await self?.ratesUpdated() }
        }
        refresh.onUniformRateFound = { [weak self] finding in
            Task { await self?.offerUniformRate(finding) }
        }
        refresh.onUniformRateReminder = { [weak self] year in
            self?.uniformRateReminderYear = year
        }
        return refresh
    }

    /// New ČNB rates came: the provisional payments are converted again in their turn (`recomputePayments(year:in:)`),
    /// and the screens load again, also when no payment changed, as they show the invoices that are not paid at the
    /// new rates too. A failure is logged.
    func ratesUpdated() async {
        let version = dataVersion
        await convertPaymentsInTurn { database in
            do {
                try await self.recomputePayments(year: nil, in: database)
            } catch {
                Self.log("Converting the provisional payments again", failedWith: error)
            }
        }
        if dataVersion == version {
            reloadScreens()
        }
    }
}

// MARK: - The uniform rate

/// Why confirming uniform rates did not end as the person asked.
nonisolated enum UniformRateConfirmationError: Error, Equatable {
    /// The rates of `year` are stored, and nothing waits for them any more, but the payments of the year could not be
    /// converted at them: the income of the year is not worked out with them yet.
    case paymentsNotConverted(year: Int)

    /// The year has rates stored already, which were not stored by this confirmation (typed by hand, or confirmed
    /// before): nothing is stored, and nothing waits for a table of that year any more.
    case alreadyStored(year: Int)

    /// The table has no rate, so there is nothing to store.
    case emptyTable
}

/// What the person does with the uniform rates the refresh found, and with the reminder to enter them by hand.
extension AppModel {
    /// The refresh found the uniform rates of a year, `finding`: they wait for the person, and a sheet asks them, each
    /// time the refresh finds them, also when the person put the sheet off before, as the rates are not stored. Nothing
    /// is offered for a year that has rates stored already (typed by hand, say, while the search ran), nor for a table
    /// with no rate in it, which there would be nothing to confirm in. A failure to read the rates of the year is
    /// logged and the finding offered: the confirmation looks again before it stores anything. While the app is locked
    /// after inactivity, the sheet waits until it is unlocked (`unlockAfterIdle()`), as it would show the rates over
    /// the lock.
    func offerUniformRate(_ finding: GFRFinding) async {
        guard !finding.rates.isEmpty, let database else { return }
        do {
            guard try await database.uniformRates(year: finding.year).isEmpty else { return }
        } catch {
            Self.log("Reading the uniform rates of the year", failedWith: error)
        }
        // The data were replaced while the rates were read: the finding is not about the data that are open now.
        guard self.database === database else { return }
        pendingUniformRate = finding
        if isIdleLocked {
            uniformRateOfferAfterUnlock = finding
        } else {
            uniformRateOffer = finding
        }
    }

    /// The reminder to enter a uniform rate by hand, for the newest finished year that the search gave up on and that
    /// has no rate stored, as the refresh kept it (`RefreshState.gaveUpUniform`), so that it is there at every launch,
    /// not only in the session in which the search gave up. A reminder that is there already stays.
    func restoreUniformRateReminder(from database: Database) async {
        guard uniformRateReminderYear == nil else { return }
        do {
            guard let state = try await database.refreshState() else { return }
            for year in state.gaveUpUniform.sorted(by: >) {
                if try await database.uniformRates(year: year).isEmpty {
                    uniformRateReminderYear = year
                    return
                }
            }
        } catch {
            Self.log("Reading the state of the search for the uniform rate", failedWith: error)
        }
    }

    /// Použít: stores the rates of `finding` as the uniform rates of its year, each with its amount, its instruction,
    /// the PDF the table was read from and the day of the confirmation, as rates that were fetched. Then nothing waits
    /// for the rates any more (`noteUniformRatesStored(forYear:)`), the screens load again, the payments of the year
    /// are converted again in their turn (`convertPaymentsAfterUniformRatesChanged(year:)`), and the refresh is told,
    /// so that Nastavení › Aplikace tells of the rate that is stored. It is one step at a time with the changes of the
    /// keys, the restores and the imports (`runSecurityStep(_:)`).
    ///
    /// Rates are stored only for a year that has none, and never an empty table: what is stored is the person's or was
    /// confirmed before, and a finding does not replace it.
    ///
    /// Throws `VaultError.locked` while the data is locked, `VaultError.busy` while another step runs, and what the
    /// database throws: nothing is stored then. Throws `UniformRateConfirmationError.emptyTable` and `.alreadyStored`
    /// when there is nothing to store or the year has rates, and `.paymentsNotConverted` when the rates are stored but
    /// their payments could not be converted.
    func confirmUniformRate(_ finding: GFRFinding) async throws {
        try await runSecurityStep {
            guard let database else { throw VaultError.locked }
            guard !finding.rates.isEmpty else { throw UniformRateConfirmationError.emptyTable }
            let confirmedAt = dependencies.clock.now()
            let rates = finding.rates.map { entry in
                UniformRate(
                    year: finding.year, currency: entry.currency, amount: entry.amount, rate: entry.rate,
                    instruction: finding.instruction, sourceURL: finding.pdfURL.absoluteString,
                    confirmedAt: confirmedAt, origin: .fetched)
            }
            // Looked at in the transaction that stores them: rates saved meanwhile are never replaced.
            guard try await database.storeUniformRatesIfNone(rates, year: finding.year) else {
                noteUniformRatesStored(forYear: finding.year)
                throw UniformRateConfirmationError.alreadyStored(year: finding.year)
            }
            noteUniformRatesStored(forYear: finding.year)
            await didWrite()
            let converted = await convertPaymentsAfterUniformRatesChanged(year: finding.year)
            if dependencies.startsRefresh, let refresh {
                Task { await refresh.refresh(.settingsChanged) }
            }
            guard converted else { throw UniformRateConfirmationError.paymentsNotConverted(year: finding.year) }
        }
    }

    /// Zadat ručně: closes the sheet of the uniform rate and shows the form of Nastavení › Rok for `year`, the year of
    /// the rates that were found or of the reminder, which the sheet, the banner and the row of Nastavení know. A
    /// finding stays pending: nothing is stored until the form is saved.
    func enterUniformRateManually(year: Int) {
        uniformRateOffer = nil
        if asOf.year != year {
            selectYear(year)
        }
        request(.enterUniformRate)
    }

    /// The uniform rates of `year` are stored: the rates that were found for it no longer wait for the person, and the
    /// reminder to enter them by hand is no longer true. What is about another year stays.
    func noteUniformRatesStored(forYear year: Int) {
        if pendingUniformRate?.year == year {
            pendingUniformRate = nil
        }
        if uniformRateReminderYear == year {
            uniformRateReminderYear = nil
        }
    }
}
