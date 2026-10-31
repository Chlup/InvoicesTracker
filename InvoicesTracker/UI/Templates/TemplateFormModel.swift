import Foundation
import Observation

/// The form of an invoice template, for a new one or for one that is stored: the sheet "Nová šablona" / "Upravit
/// šablonu".
///
/// What the person types is held here as typed, and nothing is written until Uložit šablonu (`save()`): the sheet
/// stands for one edit, and Zrušit throws it away. A save is one call on the database, after which the app is told
/// (`AppModel.didWrite()`) so that the screens load again. Smazat šablonu is offered for a template that is stored: the
/// form asks first, in a box of its own (`askToDelete()`), and the answer deletes it (`delete()`).
///
/// - A new template starts with the first client (its VAT mode and due days apply), or with the client it is made for
///   (`init(app:preselectedClient:)`), and one item "Vývoj – {měsíc} {rok}" of one hour without a price. Choosing
///   another client applies its VAT mode and due days.
/// - The descriptions of the items may hold `{měsíc}`, `{rok}`, `{month}` and `{year}`, which an invoice made from the
///   template fills in from its DUZP (`TemplateText`); the form shows what they come to (`preview(duzp:)`), and after
///   the preview of the first item it says what they may hold (`previewLine(ofItem:)`).
/// - The form shows which bank account the invoices made from the template print (`accountLine`): the account in the
///   currency of the client chosen: one of Nastavení › Moje údaje, or, in a currency it has no boxes for, an imported
///   one. The template stores no account; an invoice made from it prints the account that the data has for its
///   currency then.
/// - A template, or the client chosen for it, that was deleted meanwhile is not brought back: the save says so
///   (`failure`) and writes nothing.
@MainActor
@Observable
final class TemplateFormModel {
    nonisolated static let nameMissing = "Vyplňte název šablony."
    nonisolated static let tooManyItems = "Šablona může mít nejvýše \(EditorLimits.items) položek."
    nonisolated static let templateDeleted = "Šablona mezitím byla smazána."
    nonisolated static let saveFailed = "Šablonu se nepodařilo uložit."
    nonisolated static let deleteFailed = "Šablonu se nepodařilo smazat."

    /// What a description may hold, over the cards of Šablony faktur.
    nonisolated static let placeholderHint =
        "V popisu lze použít {měsíc}, {rok}, {month} a {year} – doplní se podle DUZP."

    /// What a description may hold, after the preview of the first item of the form.
    nonisolated static let previewHint = "{měsíc}, {rok}, {month} a {year} se doplní podle DUZP"

    /// The description of the first item of a new template.
    nonisolated static let newDescription = "Vývoj – {měsíc} {rok}"

    /// What the sheet asks before a template is deleted.
    nonisolated static let deleteMessage =
        "Faktury, které z ní už vznikly, zůstanou, jak jsou. Smazání nejde vrátit zpět."

    /// The template as the form was opened on it, or nil for a new one.
    let template: InvoiceTemplate?

    // MARK: What is typed

    var name: String

    /// The client chosen, or 0 for none.
    var clientID: Int64
    var items: [EditableItem]
    var vatMode: VatMode

    /// The days from the day of issue to the due date, as typed.
    var dueDaysText: String

    var note: String

    // MARK: What is loaded and what happened

    /// The clients to choose from, by name. Empty until `load()` has run.
    private(set) var clients: [Client] = []

    /// The bank accounts the data holds, one for each currency at most: those of Nastavení › Moje údaje, and any
    /// imported in a currency it has no boxes for. Empty until `load()` has run.
    private(set) var accounts: [BankAccount] = []

    /// Whether the clients could not be read.
    private(set) var loadFailed = false

    /// Whether Uložit šablonu was pressed: the form says what is wrong with it from then on.
    private(set) var showsErrors = false

    /// What went wrong with the last save or deletion, until the next one.
    private(set) var failure: String?

    /// Whether a save or a deletion is running. A second one is refused.
    private(set) var isWorking = false

    /// Whether the form asks, in a red box in place of its buttons, before the template is deleted: from Smazat
    /// šablonu (`askToDelete()`) until the box is answered.
    private(set) var confirmsDeletion = false

    private let app: AppModel

    /// The form of `template`, or of a new template for nil (and for one that has no id).
    init(app: AppModel, template: InvoiceTemplate?) {
        self.app = app
        let stored = template.flatMap { $0.id == 0 ? nil : $0 }
        self.template = stored
        if let stored {
            name = stored.name
            clientID = stored.clientID
            items = stored.items.isEmpty ? [Self.newItem()] : stored.items.map { EditableItem(editingTemplateItem: $0) }
            vatMode = stored.vatMode
            dueDaysText = String(stored.dueDays)
            note = stored.note
        } else {
            name = ""
            clientID = 0
            items = [Self.newItem()]
            vatMode = .domestic21
            dueDaysText = "14"
            note = ""
        }
    }

    /// The form of a new template for `client`, which starts with that client and its VAT mode and due days, as
    /// choosing the client in the form would set them: Nová šablona in the detail of the client. The client stays
    /// chosen once the form has loaded the clients (`load()` takes the first client only for a form without one).
    convenience init(app: AppModel, preselectedClient client: Client) {
        self.init(app: app, template: nil)
        clientID = client.id
        vatMode = client.vatMode
        dueDaysText = String(client.dueDays)
    }

    /// The first item of a new template: one hour of "Vývoj – {měsíc} {rok}", without a price.
    private static func newItem() -> EditableItem {
        EditableItem(description: newDescription, quantityText: "1", unit: "hod", unitPriceText: "")
    }

    // MARK: The sheet

    var isNew: Bool {
        template == nil
    }

    var title: String {
        isNew ? "Nová šablona" : "Upravit šablonu"
    }

    var subtitle: String {
        isNew ? "Šablona předvyplní odběratele, položku, cenu, DPH a splatnost." : (template?.name ?? "")
    }

    /// "Smazat šablonu „Měsíční vývoj“?"
    var deleteTitle: String {
        "Smazat šablonu „\(template?.name ?? "")“?"
    }

    // MARK: Loading

    /// Reads the clients to choose from and the bank accounts; a new template takes the first of the clients. Both are
    /// kept together, so that a client is never chosen before the accounts are there. A failure is logged and said
    /// (`loadFailed`).
    func load() async {
        guard let database = app.database else {
            loadFailed = true
            return
        }
        do {
            let loadedClients = try await database.clients()
            let loadedAccounts = try await database.bankAccounts()
            clients = loadedClients
            accounts = loadedAccounts
            loadFailed = false
        } catch {
            AppModel.log("Loading the clients and the accounts of a template", failedWith: error)
            loadFailed = true
            return
        }
        if isNew, clientID == 0, let first = clients.first {
            pickClient(first.id)
        }
    }

    // MARK: The client

    var pickedClient: Client? {
        clients.first { $0.id == clientID }
    }

    /// The currency of the prices: the one of the client chosen, and crowns while there is none.
    var currency: CurrencyCode {
        pickedClient?.currency ?? .czk
    }

    var currencyCode: String {
        currency.code
    }

    /// The account that the invoices made from the template print: the one in the currency of the template, or that
    /// there is none. The form shows it once a client is chosen.
    var accountLine: TemplateAccountLine {
        TemplateAccountLine(currency: currency, accounts: accounts)
    }

    /// Chooses the client: its VAT mode and due days apply. Choosing the client that is chosen already changes nothing
    /// (what was typed for them stays), and so does choosing one that is not there.
    func pickClient(_ id: Int64) {
        guard id != clientID, let client = clients.first(where: { $0.id == id }) else { return }
        clientID = id
        vatMode = client.vatMode
        dueDaysText = String(client.dueDays)
    }

    // MARK: The items

    var canAddItem: Bool {
        items.count < EditorLimits.items
    }

    /// Adds an item of one unit of the kind of the item above, with no description and no price, up to the limit.
    func addItem() {
        guard canAddItem else { return }
        items.append(EditableItem.blank(unit: items.last?.unit ?? "hod"))
    }

    /// Removes the item at `index`. A template keeps its last item: there is nothing to make an invoice of without one.
    func removeItem(at index: Int) {
        guard items.count > 1, items.indices.contains(index) else { return }
        items.remove(at: index)
    }

    /// The day the previews are written for: the last day of the real current month, the DUZP a new invoice starts
    /// with, whatever year is shown.
    var previewDay: CivilDate {
        app.today.endOfMonth
    }

    /// The description of the item at `index` as an invoice with the DUZP `duzp` would have it: "Vývoj – září 2026" for
    /// "Vývoj – {měsíc} {rok}" on 30. 9. 2026. "—" for an item without a description.
    func preview(ofItem index: Int, duzp: CivilDate) -> String {
        guard items.indices.contains(index) else { return "—" }
        let filled = FormInput.trimmed(TemplateText.fill(items[index].description, duzp: duzp))
        return filled.isEmpty ? "—" : filled
    }

    /// The descriptions of all the items as an invoice with the DUZP `duzp` would have them, one line each.
    func preview(duzp: CivilDate) -> String {
        items.indices.map { preview(ofItem: $0, duzp: duzp) }.joined(separator: "\n")
    }

    /// The line under the description of the item at `index`: its preview for the DUZP a new invoice starts with
    /// (`previewDay`), "Náhled: Vývoj – říjen 2026", and for the first item after it what the descriptions may hold
    /// (`previewHint`), which the form says once for all of them.
    func previewLine(ofItem index: Int) -> String {
        let line = "Náhled: " + preview(ofItem: index, duzp: previewDay)
        return index == 0 ? line + " · " + Self.previewHint : line
    }

    // MARK: Checking

    /// The days the due time says, or nil when the text is not a number of days.
    var dueDays: Int? {
        FormInput.dueDays(in: dueDaysText)
    }

    /// What is wrong with the form, one sentence each, in the order of the fields; empty when it can be saved. A
    /// quantity has to be a number above zero, a price empty (to be written on the invoice) or an amount.
    var errors: [String] {
        var errors: [String] = []
        if FormInput.trimmed(name).isEmpty {
            errors.append(Self.nameMissing)
        }
        if clientID == 0 {
            errors.append(EditorText.chooseClient)
        }
        if items.count > EditorLimits.items {
            errors.append(Self.tooManyItems)
        }
        for (index, item) in items.enumerated() {
            let position = index + 1
            if item.quantity.map({ $0 > 0 }) != true {
                errors.append(EditorText.quantity(ofItem: position))
            }
            if !item.priceIsBlank && item.unitPriceMinor == nil {
                errors.append(EditorText.price(ofItem: position))
            }
        }
        if dueDays == nil {
            errors.append(EditorText.invalidDueDays)
        }
        if InvoiceEditorChecks.lineCount(of: note) > EditorLimits.noteLines {
            errors.append(EditorText.noteTooLong)
        }
        return errors
    }

    // MARK: Saving and deleting

    /// Saves the template and tells the app, and returns the id of the template. Throws `FormSaveError.invalid` for a
    /// form with `errors` (they show from then on), `FormSaveError.alreadySaving`, `VaultError.locked` while the data
    /// is locked, and what the database throws; nothing is written then, and `failure` says what happened, for
    /// everything but the first two (the problems of the form are `errors`, and the save that is running says itself).
    @discardableResult
    func save() async throws -> Int64 {
        showsErrors = true
        guard errors.isEmpty else { throw FormSaveError.invalid }
        guard !isWorking else { throw FormSaveError.alreadySaving }
        guard let database = app.database else {
            failure = WelcomeTexts.vaultErrorText(.locked)
            throw VaultError.locked
        }
        isWorking = true
        failure = nil
        defer { isWorking = false }
        let edited = editedTemplate()
        let id: Int64
        do {
            if edited.id == 0 {
                id = try await database.saveTemplate(edited)
            } else {
                try await database.updateTemplate(edited)
                id = edited.id
            }
        } catch {
            failure = Self.failureText(for: error)
            if error as? TemplateError != .notFound {
                AppModel.log("Saving a template", failedWith: error)
            }
            throw error
        }
        await app.didWrite()
        return id
    }

    /// Smazat šablonu: the form asks before the template is deleted. A new template has nothing to delete, and nothing
    /// is asked while a save or a deletion runs.
    func askToDelete() {
        guard !isNew, !isWorking else { return }
        confirmsDeletion = true
    }

    /// Zrušit in the box: nothing is deleted, and the buttons of the form are back.
    func cancelDeletion() {
        confirmsDeletion = false
    }

    /// Deletes the template and tells the app; the box that asked before it closes. Does nothing for a new template.
    /// A template that is gone already is deleted as far as the person is concerned. Throws
    /// `FormSaveError.alreadySaving`, `VaultError.locked` while the data is locked, and what the database throws;
    /// `failure` says what happened, for all but the first.
    func delete() async throws {
        confirmsDeletion = false
        guard let id = template?.id else { return }
        guard !isWorking else { throw FormSaveError.alreadySaving }
        guard let database = app.database else {
            failure = WelcomeTexts.vaultErrorText(.locked)
            throw VaultError.locked
        }
        isWorking = true
        failure = nil
        defer { isWorking = false }
        do {
            try await database.deleteTemplate(id: id)
        } catch {
            failure = Self.deleteFailed
            AppModel.log("Deleting a template", failedWith: error)
            throw error
        }
        await app.didWrite()
    }

    /// The template as the form says it: the one it was opened on with the typed fields put in. The numbers are those
    /// the checks have read. The form has no field for the old setting of the DUZP (`InvoiceTemplate.duzpAtMonthEnd`),
    /// which no longer affects new invoices: a template that has one keeps it as it is stored, a new one gets the
    /// default.
    private func editedTemplate() -> InvoiceTemplate {
        InvoiceTemplate(
            id: template?.id ?? 0, name: FormInput.trimmed(name), clientID: clientID,
            items: items.map { item in
                TemplateItem(
                    description: FormInput.trimmed(item.description), quantity: item.quantity ?? 1,
                    unit: FormInput.trimmed(item.unit), unitPriceMinor: item.unitPriceMinor ?? 0)
            },
            vatMode: vatMode, dueDays: dueDays ?? 14, duzpAtMonthEnd: template?.duzpAtMonthEnd ?? true,
            note: FormInput.trimmed(note))
    }

    /// What a save that failed with `error` says. The only constraint a template can break, once the form has checked
    /// it, is the one that ties it to its client, which was deleted meanwhile.
    nonisolated static func failureText(for error: any Error) -> String {
        if error as? TemplateError == .notFound {
            return templateDeleted
        }
        if case .constraint? = error as? SQLiteError {
            return ClientFormModel.clientDeleted
        }
        return saveFailed
    }
}

extension TemplateFormModel: Identifiable {
    /// The sheet is the sheet of one form.
    nonisolated var id: ObjectIdentifier {
        ObjectIdentifier(self)
    }
}
