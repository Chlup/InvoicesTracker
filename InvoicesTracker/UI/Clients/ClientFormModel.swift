import Foundation
import Observation

/// A country to choose in the form of a client and for the supplier in Nastavení: its code, and its name in Czech.
nonisolated struct CountryChoice: Identifiable, Hashable, Sendable {
    var code: String
    var name: String

    var id: String {
        code
    }

    /// Every country of ISO 3166-1 by its Czech name, in the order of the names (`Countries.all`).
    static let listed: [CountryChoice] = Countries.all.map {
        CountryChoice(code: $0, name: Countries.name($0, language: .cs))
    }
}

/// The form of a client, for a new one or for one that is stored: the sheet "Nový odběratel" / "Upravit odběratele".
///
/// What the person types is held here as typed, and nothing is written until Uložit odběratele (`save()`): the sheet
/// stands for one edit, and Zrušit throws it away. A save is one call on the database, after which the app is told
/// (`AppModel.didWrite()`) so that the screens load again.
///
/// - A new client starts with Česko, crowns, Tuzemsko 21 %, 14 days, Převodem and Czech.
/// - A client created by the import is marked as edited once it is saved (`Client.editedAfterImport`). Its origin
///   stays.
/// - The phone of a client is not in the form; a client that has one keeps it.
/// - A client that was deleted meanwhile is not brought back: the save says so (`failure`) and writes nothing.
@MainActor
@Observable
final class ClientFormModel {
    nonisolated static let nameMissing = "Vyplňte název odběratele."
    nonisolated static let registrationNumberInvalid = "IČO má 8 číslic."

    /// The registration number of a client of another country is what its country calls it, as the import copies it. It
    /// has no more characters than the longest of them with their prefixes, and room to spare.
    nonisolated static let registrationNumberLimit = 40
    nonisolated static let registrationNumberTooLong = "IČO může mít nejvýše \(registrationNumberLimit) znaků."
    nonisolated static let emailInvalid = "E-mail musí obsahovat @."
    nonisolated static let clientDeleted = "Odběratel mezitím byl smazán."
    nonisolated static let saveFailed = "Odběratele se nepodařilo uložit."

    /// The way of payment of a client whose field is left empty.
    nonisolated static let defaultPaymentMethod = "Převodem"

    /// The client as the form was opened on it: a blank one with id 0 for a new client.
    let client: Client

    // MARK: What is typed

    var name: String
    var street: String
    var city: String
    var postcode: String

    /// The ISO code of the country, or the text of a country the import could not map to one (`countryChoices`).
    var country: String
    var ico: String
    var dic: String
    var email: String
    var currency: CurrencyCode
    var vatMode: VatMode
    var language: InvoiceLanguage

    /// The days from the day of issue to the due date, as typed.
    var dueDaysText: String
    var paymentMethod: String

    // MARK: What is loaded and what happened

    /// The currencies to choose from: crowns, euros and dollars, then the other currencies the ČNB quotes, as far as
    /// the stored rates tell (`load()`).
    private(set) var currencies: [CurrencyCode]

    /// Whether Uložit odběratele was pressed: the form says what is wrong with it from then on.
    private(set) var showsErrors = false

    /// What went wrong with the last save, until the next one.
    private(set) var failure: String?

    /// Whether a save is running. A second one is refused.
    private(set) var isSaving = false

    private let app: AppModel

    /// The form of `client`, or of a new client for nil.
    init(app: AppModel, client: Client?) {
        self.app = app
        let opened = client ?? Client()
        self.client = opened
        name = opened.name
        street = opened.street
        city = opened.city
        postcode = opened.postcode
        country = Self.countryCode(of: opened.country)
        ico = opened.ico
        dic = opened.dic
        email = opened.email
        currency = opened.currency
        vatMode = opened.vatMode
        language = opened.language
        dueDaysText = String(opened.dueDays)
        paymentMethod = opened.paymentMethod
        currencies = Self.currencyChoices(cached: [], including: opened.currency)
    }

    // MARK: The sheet

    var isNew: Bool {
        client.id == 0
    }

    var title: String {
        isNew ? "Nový odběratel" : "Upravit odběratele"
    }

    var subtitle: String {
        isNew ? "Výchozí měna, DPH, splatnost a platba se použijí pro nové faktury." : client.name
    }

    // MARK: Checking

    /// The days the due time says, or nil when the text is not a number of days.
    var dueDays: Int? {
        FormInput.dueDays(in: dueDaysText)
    }

    /// What is wrong with the form, one sentence each, in the order of the fields; empty when it can be saved. The IČO
    /// of a Czech client is empty or eight digits; for any other country the field is the registration number of that
    /// country, any text up to `registrationNumberLimit` characters. The country decides, so the error comes and goes
    /// as it is chosen.
    var errors: [String] {
        var errors: [String] = []
        if FormInput.trimmed(name).isEmpty {
            errors.append(Self.nameMissing)
        }
        let registrationNumber = FormInput.trimmed(ico)
        if country == "CZ" {
            if !registrationNumber.isEmpty && !Self.isCzechRegistrationNumber(registrationNumber) {
                errors.append(Self.registrationNumberInvalid)
            }
        } else if registrationNumber.count > Self.registrationNumberLimit {
            errors.append(Self.registrationNumberTooLong)
        }
        let address = FormInput.trimmed(email)
        if !address.isEmpty && !address.contains("@") {
            errors.append(Self.emailInvalid)
        }
        if dueDays == nil {
            errors.append(EditorText.invalidDueDays)
        }
        return errors
    }

    /// Eight digits, which is what a Czech IČO has.
    private static func isCzechRegistrationNumber(_ text: String) -> Bool {
        text.unicodeScalars.count == 8 && text.unicodeScalars.allSatisfy { ("0"..."9").contains($0) }
    }

    // MARK: Choices

    /// The countries to choose from, by their Czech names, with the country of the client first if it is none of them:
    /// text that an import left in place of a code stays selectable, and so does a client without a country.
    var countryChoices: [CountryChoice] {
        let listed = CountryChoice.listed
        guard !listed.contains(where: { $0.code == country }) else { return listed }
        return [CountryChoice(code: country, name: country.isEmpty ? "—" : country)] + listed
    }

    /// The code the form selects for the country a client is stored with: a code in capitals, the code of a name the
    /// import knows (Česká republika), and any other text as it is.
    private static func countryCode(of stored: String) -> String {
        ImportPlanner.countryCode(of: FormInput.trimmed(stored))
    }

    /// Crowns, euros and dollars, then the other currencies of `cached` by their codes, and `including` if it is none
    /// of them: a client in a currency the stored rates do not have yet can still be edited.
    nonisolated static func currencyChoices(cached: Set<CurrencyCode>, including current: CurrencyCode)
        -> [CurrencyCode]
    {
        let first: [CurrencyCode] = [.czk, .eur, .usd]
        return first + cached.union([current]).subtracting(first).sorted()
    }

    /// "CZK – česká koruna": the code with the name of the currency in Czech, which the system gives for any but the
    /// three usual ones. A currency the system knows no name of is the code alone.
    nonisolated static func currencyLabel(_ currency: CurrencyCode) -> String {
        switch currency {
        case .czk: return "CZK – česká koruna"
        case .eur: return "EUR – euro"
        case .usd: return "USD – americký dolar"
        default:
            guard let name = Locale(identifier: "cs").localizedString(forCurrencyCode: currency.code),
                !name.isEmpty, name != currency.code
            else {
                return currency.code
            }
            return currency.code + " – " + name
        }
    }

    /// "Čeština" and "Angličtina".
    nonisolated static func languageLabel(_ language: InvoiceLanguage) -> String {
        switch language {
        case .cs: "Čeština"
        case .en: "Angličtina"
        }
    }

    /// Reads the currencies the ČNB quotes, as far as its stored rates tell. A failure is logged and the three usual
    /// currencies stay.
    func load() async {
        guard let database = app.database else { return }
        do {
            let cached = try await database.cnbCurrencies()
            currencies = Self.currencyChoices(cached: cached, including: client.currency)
        } catch {
            AppModel.log("Reading the currencies of a client", failedWith: error)
        }
    }

    // MARK: Saving

    /// Saves the client and tells the app, and returns the id of the client. Throws `FormSaveError.invalid` for a
    /// form with `errors` (they show from then on), `FormSaveError.alreadySaving`, `VaultError.locked` while the
    /// data is locked, and what the database throws; nothing is written then, and `failure` says what happened, for
    /// everything but the first two (the problems of the form are `errors`, and the save that is running says itself).
    @discardableResult
    func save() async throws -> Int64 {
        showsErrors = true
        guard errors.isEmpty else { throw FormSaveError.invalid }
        guard !isSaving else { throw FormSaveError.alreadySaving }
        guard let database = app.database else {
            failure = WelcomeTexts.vaultErrorText(.locked)
            throw VaultError.locked
        }
        isSaving = true
        failure = nil
        defer { isSaving = false }
        let edited = editedClient()
        let id: Int64
        do {
            if edited.id == 0 {
                id = try await database.saveClient(edited)
            } else {
                try await database.updateClient(edited)
                id = edited.id
            }
        } catch {
            failure = Self.failureText(for: error)
            if error as? ClientError != .notFound {
                AppModel.log("Saving a client", failedWith: error)
            }
            throw error
        }
        await app.didWrite()
        return id
    }

    /// The client as the form says it: the client it was opened on with the typed fields put in, and an imported
    /// client marked as edited.
    private func editedClient() -> Client {
        var edited = client
        edited.name = FormInput.trimmed(name)
        edited.street = FormInput.trimmed(street)
        edited.city = FormInput.trimmed(city)
        edited.postcode = FormInput.trimmed(postcode)
        edited.country = country
        edited.ico = FormInput.trimmed(ico)
        edited.dic = FormInput.trimmed(dic)
        edited.email = FormInput.trimmed(email)
        edited.currency = currency
        edited.vatMode = vatMode
        edited.language = language
        edited.dueDays = dueDays ?? edited.dueDays
        let method = FormInput.trimmed(paymentMethod)
        edited.paymentMethod = method.isEmpty ? Self.defaultPaymentMethod : method
        if edited.origin == .imported {
            edited.editedAfterImport = true
        }
        return edited
    }

    /// What a save that failed with `error` says.
    nonisolated static func failureText(for error: any Error) -> String {
        if error as? ClientError == .notFound {
            return clientDeleted
        }
        return saveFailed
    }
}

extension ClientFormModel: Identifiable {
    /// The sheet is the sheet of one form.
    nonisolated var id: ObjectIdentifier {
        ObjectIdentifier(self)
    }
}
