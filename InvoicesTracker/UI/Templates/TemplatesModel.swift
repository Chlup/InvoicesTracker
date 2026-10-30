import Foundation
import Observation

/// The model of Šablony faktur: loads the templates with their clients, turns them into the cards of the screen
/// (`TemplateCardBuilder`), and makes the forms the screen opens.
///
/// The screen loads again whenever what the data depends on changes (`AppModel.reloadKey`), also after the form of a
/// template has saved or deleted. The model keeps the cards of the last load until the next one has finished, so that
/// the screen does not flash empty; a load that fails shows a line instead.
@MainActor
@Observable
final class TemplatesModel {
    /// What the screen says in place of the cards when the templates cannot be loaded.
    static let loadFailureText = "Šablony se nepodařilo načíst."

    /// The cards, or nil until the first load has finished and after a load that failed.
    private(set) var cards: [TemplateCard]?

    /// What the screen says in place of the cards when the last load failed, otherwise nil.
    private(set) var errorText: String?

    private let app: AppModel

    /// The templates of the last load, by id, which Upravit hands to the form.
    @ObservationIgnored private var templates: [Int64: InvoiceTemplate] = [:]

    /// How many loads have started. Only the latest one may show its result.
    @ObservationIgnored private var loadsStarted = 0

    init(app: AppModel) {
        self.app = app
    }

    // MARK: Loading

    /// Loads the templates and the clients they are written for. A failure is logged (the domain and the code of the
    /// error alone) and shows `errorText` in place of the cards.
    func load() async {
        loadsStarted += 1
        let thisLoad = loadsStarted
        do {
            guard let database = app.database else { throw VaultError.locked }
            let loadedTemplates = try await database.templates()
            let loadedClients = try await database.clients()
            guard thisLoad == loadsStarted else { return }
            templates = Dictionary(uniqueKeysWithValues: loadedTemplates.map { ($0.id, $0) })
            cards = TemplateCardBuilder.cards(templates: loadedTemplates, clients: loadedClients)
            errorText = nil
        } catch {
            guard thisLoad == loadsStarted else { return }
            AppModel.log("Loading Šablony faktur", failedWith: error)
            templates = [:]
            cards = nil
            errorText = Self.loadFailureText
        }
    }

    // MARK: Actions

    /// The form of a new template: Nová šablona.
    func newTemplateForm() -> TemplateFormModel {
        TemplateFormModel(app: app, template: nil)
    }

    /// The form of the template with this id, as it was loaded: Upravit. Nil for a template that is not there (any
    /// more).
    func form(editing id: Int64) -> TemplateFormModel? {
        templates[id].map { TemplateFormModel(app: app, template: $0) }
    }

    /// Použít on the card of a template: the editor opens on a new invoice made from it, on Faktury.
    func use(_ id: Int64) {
        app.startNewInvoice(templateID: id)
    }
}
