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

    /// Loads the supplier and the accounts. What was changed on the tab and is not saved yet stays on it. A failure is
    /// logged and shows `errorText`; what was on the tab stays as it was. The model is known to the app from its first
    /// load on, so that a quit waits for what is typed (`hasUnsavedInput`).
    func load() async {
        app.quitFlushes.register(self)
        loadsStarted += 1
        let thisLoad = loadsStarted
        do {
            guard let database = app.database else { throw VaultError.locked }
            let readSupplier = try await database.supplier()
            let readAccounts = try await database.bankAccounts()
            guard thisLoad == loadsStarted else { return }
            stored = (readSupplier, readAccounts)
            refreshEffective()
            seedTexts()
            errorText = nil
        } catch {
            guard thisLoad == loadsStarted else { return }
            AppModel.log("Loading the supplier", failedWith: error)
            errorText = Self.loadFailureText
        }
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

    /// Starts the wait before the save again. No delay at all is no wait.
    private func scheduleSave(after delay: Duration) {
        saveTimer.restart(after: delay) {
            await self.saveNow()
        }
    }

    /// Reads the texts that were typed, saves what waits to be saved, and returns when it is written and the app has
    /// been told of it. The screen calls this when the person leaves a field, presses Return or leaves the screen; the
    /// end of the wait does too. When a save is already running this waits for it and then saves what has come since.
    func saveNow() async {
        saveTimer.cancel()
        while let running = writeTask {
            await running.value
        }
        readTypedTexts()
        guard !pending.isEmpty else { return }
        let edits = pending
        inFlight = edits
        pending = []
        let task = Task { await self.write(edits) }
        writeTask = task
        await task.value
    }

    /// Writes `edits` on top of what is stored, in one transaction, and tells the app.
    private func write(_ edits: [SupplierEdit]) async {
        defer {
            inFlight = []
            writeTask = nil
            refreshEffective()
        }
        guard let database = app.database else {
            restore(edits)
            saveFailure = Self.saveFailureText
            return
        }
        do {
            let saved = try await database.updateSupplierDetails { supplier, accounts in
                for edit in edits {
                    edit.apply(to: &supplier, accounts: &accounts)
                }
            }
            stored = (saved.supplier, saved.accounts)
        } catch {
            AppModel.log("Saving the supplier", failedWith: error)
            restore(edits)
            saveFailure = Self.saveFailureText
            return
        }
        saveFailure = nil
        await app.didWrite()
    }

    /// Puts `edits`, which could not be written, back in front of those that came meanwhile.
    private func restore(_ edits: [SupplierEdit]) {
        let newer = pending
        pending = edits.filter { edit in !newer.contains { $0.target == edit.target } } + newer
    }
}

extension SupplierTabModel: SavesTypedInput {}
