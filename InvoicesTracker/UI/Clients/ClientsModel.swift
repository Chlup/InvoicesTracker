import Foundation
import Observation

/// The model of Odběratelé: loads the clients and what each did in the selected year as of the day of "K datu", turns
/// them into the rows of the table (`ClientRowBuilder`), and makes the forms the screen opens.
///
/// The screen loads again whenever what the data depends on changes (`AppModel.reloadKey`), also after the form of a
/// client has saved. The model keeps the rows of the last load until the next one has finished, so that the screen
/// does not flash empty; a load that fails shows a line instead.
@MainActor
@Observable
final class ClientsModel {
    /// What the screen says in place of the rows when the clients cannot be loaded.
    static let loadFailureText = "Odběratele se nepodařilo načíst."

    /// The rows, in the order of the names of the clients in Czech, or nil until the first load has finished and after
    /// a load that failed.
    private(set) var rows: [ClientRow]?

    /// The year the rows are about, which the head of the column of the year names: the selected year as the last load
    /// found it.
    private(set) var year: Int

    /// What the screen says in place of the rows when the last load failed, otherwise nil.
    private(set) var errorText: String?

    private let app: AppModel

    /// The clients of the last load, by id, which a click on a row hands to the form.
    @ObservationIgnored private var clients: [Int64: Client] = [:]

    /// How many loads have started. Only the latest one may show its result: a load that was started for a year or a
    /// day that has been replaced since must not undo the newer one.
    @ObservationIgnored private var loadsStarted = 0

    init(app: AppModel) {
        self.app = app
        year = app.asOf.year
    }

    // MARK: Loading

    /// Loads the clients and their figures for the selected year as of the day shown. A failure is logged (the domain
    /// and the code of the error alone) and shows `errorText` in place of the rows.
    func load() async {
        loadsStarted += 1
        let thisLoad = loadsStarted
        // The year and the day as they are when the load starts: all of it is about them, however they change
        // meanwhile (a change starts a load of its own).
        let shown = app.asOf
        let received = app.receivedThrough
        do {
            guard let database = app.database else { throw VaultError.locked }
            let loaded = try await database.clients()
            let figures = try await database.clientFigures(
                year: shown.year, asOf: shown.asOf, receivedThrough: received)
            guard thisLoad == loadsStarted else { return }
            clients = Dictionary(uniqueKeysWithValues: loaded.map { ($0.id, $0) })
            rows = ClientRowBuilder.rows(clients: loaded, figures: figures)
            year = shown.year
            errorText = nil
        } catch {
            guard thisLoad == loadsStarted else { return }
            AppModel.log("Loading Odběratelé", failedWith: error)
            clients = [:]
            rows = nil
            errorText = Self.loadFailureText
        }
    }

    // MARK: Actions

    /// The form of a new client: Nový odběratel.
    func newClientForm() -> ClientFormModel {
        ClientFormModel(app: app, client: nil)
    }

    /// The form of the client with this id, as it was loaded: a click on its row. Nil for a client that is not there
    /// (any more).
    func form(editing id: Int64) -> ClientFormModel? {
        clients[id].map { ClientFormModel(app: app, client: $0) }
    }

    /// Nová faktura on the row of a client: the editor opens on a blank invoice for the client, on Faktury.
    func newInvoice(forClient id: Int64) {
        app.startNewInvoice(forClient: id)
    }
}
