import Foundation
import Observation

/// The model of Nastavení › Moje údaje: the supplier's details printed on every invoice, the bank accounts in crowns,
/// dollars and euros, and the lines "Na fakturách" of what the invoices of each currency print and miss.
///
/// - The tab loads again whenever what the data depends on changes (`AppModel.reloadKey`). A field the person has
///   touched keeps the text they typed through every load, also one that was refused; the others show what is stored.
/// - A text is read when the typing has stopped, not key by key: `saveDelay` after the last key, when the person leaves
///   the field or presses Return, and when the screen is left (`saveNow()`). Until then it is only a text, and nothing
///   is saved of it.
/// - A text is saved without the white space around it. An IBAN that does not pass its check and a BIC that is not 8
///   or 11 letters and digits are refused: the field keeps the text with the message under it, the data keeps its
///   value, and a change that waited for the field is withdrawn. One that passes is saved, and shown, in capitals
///   without spaces.
/// - The country, the type of the account in dollars and the account in euros, added or removed, are saved at once.
/// - Each save writes only the fields that were changed, on top of what is stored at that moment, and then tells the
///   app (`didWrite()`). A save that fails is said (`saveFailure`), keeps the texts and the changes, and is tried again
///   with the next change.
/// - A change belongs to the data that was open when it was made, the `Database` object, which a restore or an unlock
///   replaces with another: it is written into that data alone. Changes whose data is no longer open when they would
///   be saved, when the tab loads or when the next change is made are dropped with what was typed, logged and not
///   written, and the tab says nothing of them. While no data is open at all, a change waits for the data the tab was
///   loaded from, as a save that fails does. A load that sees other data opened while it reads shows nothing of what it
///   read: the data open now loads again and shows itself.
@MainActor
@Observable
final class SupplierTabModel {
    // MARK: Texts

    nonisolated static let loadFailureText = "Údaje dodavatele se nepodařilo načíst."
    nonisolated static let saveFailureText = "Změnu se nepodařilo uložit."
    nonisolated static let ibanInvalid = "IBAN nesedí – zkontrolujte ho znak po znaku."
    nonisolated static let bicInvalid = "BIC (SWIFT) má 8 nebo 11 písmen a číslic."

    /// The types of an account in dollars to choose from.
    nonisolated static let accountTypes = ["Checking", "Savings"]

    /// How the delay before a save is waited out. A test replaces it with a wait that it ends itself.
    typealias Wait = DebounceTimer.Wait

    // MARK: State

    /// The supplier and the accounts as the person has them: what is stored, with every change made on the tab and not
    /// saved yet on top of it. Nil and empty until the first load has finished.
    private(set) var supplier: Supplier?
    private(set) var accounts: [BankAccount] = []

    /// The texts of the fields, and the messages under those that were refused.
    private var texts: [SupplierField: String] = [:]
    private var fieldErrors: [SupplierField: String] = [:]

    /// What the tab says when the last save failed, otherwise nil.
    private(set) var saveFailure: String?

    /// What the tab says in place of its content when the last load failed, otherwise nil.
    private(set) var errorText: String?

    private let app: AppModel
    private let saveDelay: Duration

    /// The wait before a save.
    private let saveTimer: DebounceTimer

    /// The supplier and the accounts as they were last read from the data or written to it.
    @ObservationIgnored private var stored: (supplier: Supplier, accounts: [BankAccount])?

    /// The changes made on the tab that are not written yet, the oldest first, and those that are being written.
    @ObservationIgnored private var pending: [SupplierEdit] = []
    @ObservationIgnored private var inFlight: [SupplierEdit] = []

    /// The write that runs.
    @ObservationIgnored private var writeTask: Task<Void, Never>?

    /// The fields the person has typed in, and of those the ones whose text has not been read yet.
    @ObservationIgnored private var touched: Set<SupplierField> = []
    @ObservationIgnored private var unread: Set<SupplierField> = []

    /// The data the changes that wait to be saved were made on (`noteWaitingChange()`). It says nothing while no change
    /// waits; what is being written belongs to the data its write was started for (`write(_:madeOn:)`).
    @ObservationIgnored private var changesBelongTo: Database?

    /// The data the tab was last loaded from.
    @ObservationIgnored private var shownFrom: Database?

    /// How many loads have started. Only the latest may show its result.
    @ObservationIgnored private var loadsStarted = 0

    init(
        app: AppModel, saveDelay: Duration = .milliseconds(500),
        wait: @escaping Wait = { try await Task.sleep(for: $0) }
    ) {
        self.app = app
        self.saveDelay = saveDelay
        saveTimer = DebounceTimer(wait: wait)
    }

    // MARK: What the tab shows

    /// The text of `field`: what was typed in it, or what is stored.
    func text(_ field: SupplierField) -> String {
        texts[field] ?? ""
    }

    /// The message under `field` when its text was refused, otherwise nil.
    func error(_ field: SupplierField) -> String? {
        fieldErrors[field]
    }

    var hasEURAccount: Bool {
        accounts.contains { $0.currency == .eur }
    }

    /// The type of the account in dollars: Checking until another one is chosen.
    var usdAccountType: String {
        let type = accounts.first { $0.currency == .usd }?.accountType ?? ""
        return type.isEmpty ? Self.accountTypes[0] : type
    }

    /// The types to choose from, with a type the data has that is none of them.
    var usdAccountTypeChoices: [String] {
        Self.accountTypes.contains(usdAccountType) ? Self.accountTypes : [usdAccountType] + Self.accountTypes
    }

    /// The countries to choose from, by their Czech names, with the supplier's country first when it is none of them.
    var countryChoices: [CountryChoice] {
        let country = supplier?.country ?? ""
        let listed = CountryChoice.listed
        guard !listed.contains(where: { $0.code == country }) else { return listed }
        return [CountryChoice(code: country, name: country.isEmpty ? "—" : country)] + listed
    }

    /// The lines "Na fakturách" for the accounts as the person has them.
    var statusLines: [InvoiceAccountStatus.Line] {
        InvoiceAccountStatus.entries(accounts: accounts)
    }

    // MARK: Loading

    /// Loads the supplier and the accounts from the data open as the load starts. What was changed on the tab and is
    /// not saved yet stays on it, unless it waits for other data than the data open now: that is dropped first
    /// (`dropChanges()`). A failure is logged and shows `errorText`; what was on the tab stays as it was. Other data
    /// opened while the load reads keeps what was shown without publishing this load (`mayShow(_:readFrom:)`). The
    /// model is known to the app from its first load on, so that a quit waits for what is typed (`hasUnsavedInput`).
    func load() async {
        app.quitFlushes.register(self)
        loadsStarted += 1
        let thisLoad = loadsStarted
        let openData = app.database
        if let openData, hasWaitingChanges, changesBelongTo !== openData {
            dropChanges()
        }
        do {
            guard let database = openData else { throw VaultError.locked }
            let readSupplier = try await database.supplier()
            let readAccounts = try await database.bankAccounts()
            guard mayShow(thisLoad, readFrom: database) else { return }
            shownFrom = database
            stored = (readSupplier, readAccounts)
            refreshEffective()
            seedTexts()
            errorText = nil
        } catch {
            guard mayShow(thisLoad, readFrom: openData) else { return }
            AppModel.log("Loading the supplier", failedWith: error)
            errorText = Self.loadFailureText
        }
    }

    /// Whether the load numbered `load`, which started while the app had `database` open (nil when it had none), may
    /// show what it read: it is the newest load, and the data open now is still `database`.
    private func mayShow(_ load: Int, readFrom database: Database?) -> Bool {
        load == loadsStarted && app.database === database
    }

    /// Puts what the supplier and the accounts have into the texts of the fields the person has not touched.
    private func seedTexts() {
        guard let supplier else { return }
        var seeded = texts
        for field in SupplierField.allCases where !touched.contains(field) {
            seeded[field] = field.value(in: supplier, accounts: accounts)
        }
        if seeded != texts {
            texts = seeded
        }
    }

    // MARK: Editing

    /// A field has been typed in. This records the text and starts the wait again, nothing more: the text is read when
    /// the typing stops.
    func setText(_ field: SupplierField, _ text: String) {
        guard stored != nil else { return }
        texts[field] = text
        noteWaitingChange()
        touched.insert(field)
        unread.insert(field)
        scheduleSave(after: saveDelay)
    }

    /// The supplier's country, an ISO code. Saved at once.
    func setCountry(_ code: String) {
        queue([.country(code)])
    }

    /// The type of the account in dollars. Saved at once.
    func setUSDAccountType(_ type: String) {
        queue([.usdAccountType(type)])
    }

    /// + Přidat účet v eurech: an empty account in euros, saved at once.
    func addEURAccount() {
        queue([.eurAccount(true)])
    }

    /// Odebrat: the account in euros goes, with what was typed in its fields. Saved at once.
    func removeEURAccount() {
        for field in SupplierField.allCases where field.currency == .eur {
            touched.remove(field)
            unread.remove(field)
            fieldErrors[field] = nil
            texts[field] = ""
            pending.removeAll { $0.target == .text(field) }
        }
        queue([.eurAccount(false)])
    }

    // MARK: Saving

    /// Makes `edits` the changes that wait for their targets, and saves them at once.
    private func queue(_ edits: [SupplierEdit]) {
        guard stored != nil else { return }
        noteWaitingChange()
        for edit in edits {
            stage(edit)
        }
        refreshEffective()
        if !pending.isEmpty {
            scheduleSave(after: .zero)
        }
    }

    /// Makes `edit` the change that waits for its target, in place of the one that waited for it. No change waits for
    /// the target when the data holds the value anyway, or will once what is being written is written.
    private func stage(_ edit: SupplierEdit) {
        guard var expected = stored else { return }
        pending.removeAll { $0.target == edit.target }
        for written in inFlight {
            written.apply(to: &expected.supplier, accounts: &expected.accounts)
        }
        var changed = expected
        edit.apply(to: &changed.supplier, accounts: &changed.accounts)
        if changed.supplier != expected.supplier || changed.accounts != expected.accounts {
            pending.append(edit)
        }
    }

    /// Reads the texts that were typed and not read yet, now that the typing has stopped. A text the field accepts
    /// becomes the change that waits for the field; any other keeps its place in the field with its message, and the
    /// change that waited for the field goes.
    private func readTypedTexts() {
        guard stored != nil else { return }
        let fields = unread
        unread = []
        for field in fields {
            let value = (texts[field] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if field.accepts(value) {
                let stored = field.stored(value)
                if field.refusal != nil {
                    texts[field] = stored
                }
                fieldErrors[field] = nil
                stage(.text(field, stored))
            } else {
                fieldErrors[field] = field.refusal
                pending.removeAll { $0.target == .text(field) }
            }
        }
        refreshEffective()
    }

    /// Puts what is being written and what waits to be written on the stored supplier and accounts.
    private func refreshEffective() {
        guard var effective = stored else { return }
        for edit in inFlight + pending {
            edit.apply(to: &effective.supplier, accounts: &effective.accounts)
        }
        if effective.supplier != supplier {
            supplier = effective.supplier
        }
        if effective.accounts != accounts {
            accounts = effective.accounts
        }
    }

    /// Whether something typed or changed is not written yet: a text that waits for the typing to stop, a change that
    /// waits to be saved, or a save that runs.
    var hasUnsavedInput: Bool {
        !unread.isEmpty || !pending.isEmpty || writeTask != nil
    }

    /// Whether changes wait to be saved: a text that waits for the typing to stop, or a change that waits for its save.
    /// What is being written does not count: it belongs to the data its write was started for.
    private var hasWaitingChanges: Bool {
        !unread.isEmpty || !pending.isEmpty
    }

    /// A change starts to wait to be saved, or joins those that wait. The first one records the data the app has open,
    /// or the data the tab was loaded from while the app has none open (`changesBelongTo`), and the later ones join it.
    /// Changes that wait for data that is no longer open, as other data has been opened since, are dropped first
    /// (`dropChanges()`), and this one belongs to the data open now.
    private func noteWaitingChange() {
        let openData = app.database
        if let openData, hasWaitingChanges, changesBelongTo !== openData {
            dropChanges()
        }
        if !hasWaitingChanges {
            changesBelongTo = openData ?? shownFrom
        }
    }

    /// The line logged when changes are dropped because they were made on data that is no longer open: a restore or
    /// an unlock replaced it, or it was let go.
    private static let droppedChangesNote = "Dropped the changes of Moje údaje made on data that is no longer open"

    /// Drops the changes that wait to be saved, which were made on data that is no longer open, and logs it when there
    /// were some (`forgetChanges()`).
    private func dropChanges() {
        if hasWaitingChanges {
            AppModel.log(Self.droppedChangesNote)
        }
        forgetChanges()
    }

    /// Forgets the changes that wait to be saved and the wait for the save, what was typed, the messages under the
    /// texts that were refused and the line of a save that failed: they were made on data that is no longer open, and
    /// nothing of them is written. The supplier and the accounts shown are those stored again, and every field shows
    /// what the data holds once the tab loads, which a restore and an unlock make it do.
    private func forgetChanges() {
        saveTimer.cancel()
        pending = []
        unread = []
        touched = []
        changesBelongTo = nil
        fieldErrors = [:]
        saveFailure = nil
        refreshEffective()
    }

    /// What was being written was made on data that is no longer open: it is neither written nor put back to wait. The
    /// changes that wait go with it, and what was typed (`forgetChanges()`), unless they were made on the data open
    /// now. It is logged, and the tab says nothing of it.
    private func dropWhatWasWritten() {
        AppModel.log(Self.droppedChangesNote)
        if !hasWaitingChanges || changesBelongTo !== app.database {
            forgetChanges()
        }
    }

    /// Starts the wait before the save again. No delay at all is no wait.
    private func scheduleSave(after delay: Duration) {
        saveTimer.restart(after: delay) {
            await self.saveNow()
        }
    }

    /// Reads the texts that were typed, saves what waits to be saved, and returns when it is written and the app has
    /// been told of it. The screen calls this when the person leaves a field, presses Return or leaves the screen; the
    /// end of the wait does too, and so does a quit. When a save is already running this waits for it and then saves
    /// what has come since. Changes made on data that is no longer open are dropped instead (`write(_:madeOn:)`).
    func saveNow() async {
        saveTimer.cancel()
        while let running = writeTask {
            await running.value
        }
        readTypedTexts()
        guard !pending.isEmpty else { return }
        let edits = pending
        let madeOn = changesBelongTo
        inFlight = edits
        pending = []
        let task = Task { await self.write(edits, madeOn: madeOn) }
        writeTask = task
        await task.value
    }

    /// Writes `edits`, which were made on the data `madeOn`, on top of what is stored, in one transaction, and tells
    /// the app. It writes into `madeOn` alone, and only while it is the data the app has open as the write starts:
    /// edits made on data that a restore or an unlock has replaced since are dropped instead (`dropWhatWasWritten()`),
    /// and so are those whose write fails because other data was opened meanwhile. While no data is open they wait for
    /// the next save, and the failure is said, as it is for a write that fails. A write that ends after other data was
    /// opened shows nothing of what it wrote, and does not tell the app.
    private func write(_ edits: [SupplierEdit], madeOn: Database?) async {
        defer {
            inFlight = []
            writeTask = nil
            refreshEffective()
        }
        guard let database = app.database else {
            restore(edits, madeOn: madeOn)
            saveFailure = Self.saveFailureText
            return
        }
        guard database === madeOn else {
            dropWhatWasWritten()
            return
        }
        do {
            let saved = try await database.updateSupplierDetails { supplier, accounts in
                for edit in edits {
                    edit.apply(to: &supplier, accounts: &accounts)
                }
            }
            if let openData = app.database, openData !== database {
                return
            }
            stored = (saved.supplier, saved.accounts)
        } catch {
            if let openData = app.database, openData !== database {
                dropWhatWasWritten()
                return
            }
            AppModel.log("Saving the supplier", failedWith: error)
            restore(edits, madeOn: database)
            saveFailure = Self.saveFailureText
            return
        }
        saveFailure = nil
        if !hasWaitingChanges {
            changesBelongTo = nil
        }
        await app.didWrite()
    }

    /// Puts `edits`, which were made on the data `madeOn` and could not be written, back in front of those that came
    /// meanwhile. When none came, they wait for `madeOn` again.
    private func restore(_ edits: [SupplierEdit], madeOn: Database?) {
        if !hasWaitingChanges {
            changesBelongTo = madeOn
        }
        let newer = pending
        pending = edits.filter { edit in !newer.contains { $0.target == edit.target } } + newer
    }
}

extension SupplierTabModel: SavesTypedInput {}
