import Foundation
import Observation

/// The model of Odběratelé: loads the clients, their templates and what each did in the selected year, turns them into
/// what the screen shows (`ClientsBuilder`), keeps one client selected or none, and makes the forms the screen opens.
///
/// The money is what came in the year through today (`AppModel.receivedThrough`), and a year that is over is counted
/// whole. The screen loads again whenever what the data depends on changes (`AppModel.reloadKey`), also after the form
/// of a client has saved. The model keeps the data of the last load until the next one has finished, so that the screen
/// does not flash empty; a load that fails shows a line instead.
///
/// Nothing is selected when the screen is entered (a new model starts with nothing selected). A click on a row selects
/// its client, whose detail opens beside the table, and a click on the selected row or the ✕ of the detail clears the
/// selection. A client saved in its form becomes the selected one. The selection stays when the year or the day
/// changes, and goes when a load finds its client gone (deleted in another window, or by a restore).
@MainActor
@Observable
final class ClientsModel {
    /// What the screen says in place of the table when the clients cannot be loaded.
    static let loadFailureText = "Odběratele se nepodařilo načíst."

    /// What the screen shows: nil until the first load has finished, and after a load that failed.
    private(set) var data: ClientsData?

    /// What the screen says in place of the table when the last load failed, otherwise nil.
    private(set) var errorText: String?

    /// The client whose row is selected and whose detail stands beside the table, or nil.
    private(set) var selectedClientID: Int64?

    private let app: AppModel

    /// The clients of the last load, by id, which Upravit hands to the form.
    @ObservationIgnored private var clients: [Int64: Client] = [:]

    /// The templates of the last load, by id, which Upravit of a template hands to its form.
    @ObservationIgnored private var templates: [Int64: InvoiceTemplate] = [:]

    /// How many loads have started. Only the latest one may show its result: a load that was started for a year or a
    /// day that has been replaced since must not undo the newer one.
    @ObservationIgnored private var loadsStarted = 0

    init(app: AppModel) {
        self.app = app
    }

    // MARK: Loading

    /// Loads the clients, the templates and the figures of the clients in the selected year. A failure is logged (the
    /// domain and the code of the error alone) and shows `errorText` in place of the table.
    func load() async {
        loadsStarted += 1
        let thisLoad = loadsStarted
        // The year and the day as they are when the load starts: all of it is about them, however they change
        // meanwhile (a change starts a load of its own).
        let shown = app.asOf
        let received = app.receivedThrough
        do {
            guard let database = app.database else { throw VaultError.locked }
            let loadedClients = try await database.clients()
            let loadedTemplates = try await database.templates()
            let figures = try await database.clientFigures(
                year: shown.year, asOf: shown.asOf, receivedThrough: received)
            guard thisLoad == loadsStarted else { return }
            clients = Dictionary(uniqueKeysWithValues: loadedClients.map { ($0.id, $0) })
            templates = Dictionary(uniqueKeysWithValues: loadedTemplates.map { ($0.id, $0) })
            data = ClientsBuilder.build(
                ClientsInput(
                    year: shown.year, clients: loadedClients, templates: loadedTemplates, figures: figures))
            errorText = nil
            if let selected = selectedClientID, clients[selected] == nil {
                selectedClientID = nil
            }
        } catch {
            guard thisLoad == loadsStarted else { return }
            AppModel.log("Loading Odběratelé", failedWith: error)
            clients = [:]
            templates = [:]
            data = nil
            errorText = Self.loadFailureText
        }
    }

    // MARK: The selection

    /// A click on the row of the client `id`: selects the client, and clears the selection when the client is the one
    /// selected already, as a click on a row of Faktury opens and closes its invoice.
    func click(_ id: Int64) {
        selectedClientID = selectedClientID == id ? nil : id
    }

    /// The ✕ of the detail, or anything else that clears the selection.
    func closeDetail() {
        selectedClientID = nil
    }

    /// The form of a client saved the client `id`: it becomes the selected one, a new client too, whose row and detail
    /// show once the load that the save started has it.
    func didSaveClient(_ id: Int64) {
        selectedClientID = id
    }

    // MARK: Actions

    /// The form of a new client: Nový odběratel.
    func newClientForm() -> ClientFormModel {
        ClientFormModel(app: app, client: nil)
    }

    /// The form of the client with this id, as it was loaded: Upravit in its detail. Nil for a client that is not there
    /// (any more).
    func form(editing id: Int64) -> ClientFormModel? {
        clients[id].map { ClientFormModel(app: app, client: $0) }
    }

    /// The form of the template with this id, as it was loaded: Upravit of a template of a client. Nil for a template
    /// that is not there (any more).
    func templateForm(editing id: Int64) -> TemplateFormModel? {
        templates[id].map { TemplateFormModel(app: app, template: $0) }
    }

    /// Nová faktura in the detail of a client: the editor opens on a blank invoice for the client, on Faktury.
    func newInvoice(forClient id: Int64) {
        app.startNewInvoice(forClient: id)
    }
}
