import Foundation

nonisolated extension ImportPlanner {
    /// The clients that are there and the clients the files have, matched and made from the rows of the CSV files and
    /// the customers of the ISDOC invoices one by one.
    nonisolated struct ClientBook {
        /// A client of the book: one that is there, or a new one that the files are making.
        struct Entry {
            /// The client as it is stored, or a blank client for a new one.
            let client: Client
            let isNew: Bool

            /// What the files of the client say so far, the newest last.
            var values = Values()

            /// The keys a file is matched by: the company number and the VAT number without white space (and the VAT
            /// number in capitals), and the name folded. What is empty in a client that is there but the files say is
            /// counted, since that is what the client is filled with.
            private(set) var icoKey = ""
            private(set) var dicKey = ""
            private(set) var nameKey = ""

            /// An entry of `client`, new or there already, with its keys.
            init(client: Client, isNew: Bool) {
                self.client = client
                self.isNew = isNew
                refreshKeys()
            }

            /// Works the keys out again from the client and from what the files say.
            mutating func refreshKeys() {
                icoKey = ClientBook.compact(client.ico.isEmpty ? values.ico : client.ico)
                dicKey = ClientBook.compact(client.dic.isEmpty ? values.dic : client.dic).uppercased()
                nameKey = SearchFolding.fold(isNew ? values.name : client.name)
            }

            /// Whether the client has another company number or another VAT number than the file, so that equal names
            /// are two companies.
            func disagrees(icoKey ico: String, dicKey dic: String) -> Bool {
                (!ico.isEmpty && !icoKey.isEmpty && icoKey != ico) || (!dic.isEmpty && !dicKey.isEmpty && dicKey != dic)
            }

            /// The client the files make: the newest file's values, with the defaults of a new client for the rest.
            func madeClient() -> Client {
                var made = Client()
                made.name = values.name
                made.street = values.street
                made.postcode = values.postcode
                made.city = values.city
                made.country = values.country
                made.ico = values.ico
                made.dic = values.dic
                made.email = values.email
                made.phone = values.phone
                made.currency = values.currency ?? made.currency
                made.vatMode = values.vatMode ?? made.vatMode
                made.dueDays = values.dueDays ?? made.dueDays
                if !values.paymentMethod.isEmpty {
                    made.paymentMethod = values.paymentMethod
                }
                made.language = values.language ?? made.language
                made.origin = .imported
                made.editedAfterImport = false
                return made
            }

            /// The client with its empty fields filled from the files, or nil when the files fill none.
            func filledClient() -> Client? {
                var filled = client
                func fill(_ field: inout String, with value: String) {
                    if field.isEmpty {
                        field = value
                    }
                }
                fill(&filled.street, with: values.street)
                fill(&filled.postcode, with: values.postcode)
                fill(&filled.city, with: values.city)
                fill(&filled.country, with: values.country)
                fill(&filled.ico, with: values.ico)
                fill(&filled.dic, with: values.dic)
                fill(&filled.email, with: values.email)
                fill(&filled.phone, with: values.phone)
                fill(&filled.paymentMethod, with: values.paymentMethod)
                return filled == client ? nil : filled
            }
        }

        /// What the files of a client say. A newer file's value replaces an older one's, unless it is empty (or a
        /// currency without rates): the client takes what the newest file that has a value has.
        struct Values {
            var name = ""
            var street = ""
            var postcode = ""
            var city = ""
            var country = ""
            var ico = ""
            var dic = ""
            var email = ""
            var phone = ""
            var paymentMethod = ""
            var currency: CurrencyCode?
            var vatMode: VatMode?
            var dueDays: Int?
            var language: InvoiceLanguage?

            /// Takes what `row` says of its client, of the currency, the VAT, the days until due, the language and the
            /// payment method of its invoice. A payment by transfer is worded as the invoice of the row prints it.
            mutating func absorb(_ row: FakturoidRow, knownCurrencies: Set<CurrencyCode>) {
                take(&name, row.clientName)
                take(&street, ImportPlanner.street(of: row))
                take(&postcode, row.clientZip)
                take(&city, row.clientCity)
                take(&country, ImportPlanner.country(row.clientCountry).text)
                take(&ico, row.clientRegistrationNo)
                take(&dic, row.clientVatNo)
                take(&email, row.clientEmail)
                take(&phone, row.clientPhone)
                take(
                    &paymentMethod,
                    ImportPlanner.paymentMethod(
                        code: row.paymentMethodCode, human: row.paymentMethodHuman,
                        language: ImportPlanner.language(of: row)))
                if let code = CurrencyCode(row.currency), code.isCZK || knownCurrencies.contains(code) {
                    currency = code
                }
                if let mode = ImportPlanner.vatMode(of: row) {
                    vatMode = mode
                }
                if let days = row.dueDays {
                    dueDays = days
                }
                if !row.language.isEmpty {
                    language = ImportPlanner.language(of: row)
                }
            }

            /// Takes what `isdoc` says of its customer: the name, the address, the IČO, the DIČ and the e-mail, and the
            /// currency and the VAT mode of the invoice. The file says nothing of the phone, the days until due, the
            /// language or the payment method of the client.
            mutating func absorb(_ isdoc: IsdocInvoice, knownCurrencies: Set<CurrencyCode>) {
                let customer = isdoc.customer
                let customerCountry = ImportPlanner.countryCode(of: customer.country)
                take(&name, customer.name)
                take(&street, customer.street)
                take(&postcode, customer.postcode)
                take(&city, customer.city)
                take(&country, customerCountry)
                take(&ico, customer.ico)
                take(&dic, customer.dic)
                take(&email, customer.email)
                if let code = CurrencyCode(isdoc.currency), code.isCZK || knownCurrencies.contains(code) {
                    currency = code
                }
                if let mode = IsdocInvoiceBuilder.vatMode(of: isdoc, existing: nil, clientCountry: customerCountry) {
                    vatMode = mode
                }
            }

            /// Puts `value` in `field` unless it is empty.
            private func take(_ field: inout String, _ value: String) {
                if !value.isEmpty {
                    field = value
                }
            }
        }

        /// Where an entry of the book went when the book was finished.
        enum Reference {
            /// A client that is there, by its id.
            case existing(Int64)

            /// A new client, by its index in `Finished.newClients`.
            case new(Int)
        }

        /// The clients the book makes and fills, and where each of its entries went.
        struct Finished {
            var newClients: [Client] = []
            var updates: [Client] = []

            /// By the place of the entry in the book.
            var references: [Int: Reference] = [:]
        }

        private var entries: [Entry]
        private let knownCurrencies: Set<CurrencyCode>

        /// A book of `clients`, the clients that are there, for files whose currencies are worth taking when they are
        /// among `knownCurrencies`.
        init(clients: [Client], knownCurrencies: Set<CurrencyCode>) {
            self.knownCurrencies = knownCurrencies
            entries = clients.map { Entry(client: $0, isNew: false) }
        }

        /// Puts the client of `row` in the book: the client it is matched to, or a new one, with the values of the
        /// row. Returns the place of the entry, or nil when the row names no client that is there and has no name to
        /// make one of.
        mutating func place(_ row: FakturoidRow) -> Int? {
            guard
                let index = entry(
                    ico: row.clientRegistrationNo, dic: row.clientVatNo, name: row.clientName)
            else {
                return nil
            }
            entries[index].values.absorb(row, knownCurrencies: knownCurrencies)
            entries[index].refreshKeys()
            return index
        }

        /// Puts the customer of `isdoc` in the book, as `place(_:)` puts the client of a row.
        mutating func place(_ isdoc: IsdocInvoice) -> Int? {
            let customer = isdoc.customer
            guard let index = entry(ico: customer.ico, dic: customer.dic, name: customer.name) else { return nil }
            entries[index].values.absorb(isdoc, knownCurrencies: knownCurrencies)
            entries[index].refreshKeys()
            return index
        }

        /// The language and the payment method of the client at `index`, for an invoice that has neither from a row:
        /// those of a client that is there, or what the rows of a new client said (nil and empty when they said
        /// nothing). Nil and empty for no entry.
        func defaults(of index: Int?) -> (language: InvoiceLanguage?, paymentMethod: String) {
            guard let index else { return (nil, "") }
            let entry = entries[index]
            if entry.isNew {
                return (entry.values.language, entry.values.paymentMethod)
            }
            return (entry.client.language, entry.client.paymentMethod)
        }

        /// The place of the entry a file with these numbers and this name is matched to, or of a new entry for it;
        /// nil when it is matched to none and has no name to make a client of.
        private mutating func entry(ico: String, dic: String, name: String) -> Int? {
            if let found = match(ico: ico, dic: dic, name: name) {
                return found
            }
            guard !name.isEmpty else { return nil }
            entries.append(Entry(client: Client(), isNew: true))
            return entries.count - 1
        }

        /// The first client with the company number, otherwise the first with the VAT number, otherwise the first with
        /// the name (folded) that does not have another number.
        private func match(ico: String, dic: String, name: String) -> Int? {
            let ico = Self.compact(ico)
            let dic = Self.compact(dic).uppercased()
            let name = SearchFolding.fold(name)
            if !ico.isEmpty, let index = entries.firstIndex(where: { $0.icoKey == ico }) {
                return index
            }
            if !dic.isEmpty, let index = entries.firstIndex(where: { $0.dicKey == dic }) {
                return index
            }
            if !name.isEmpty,
                let index = entries.firstIndex(where: { $0.nameKey == name && !$0.disagrees(icoKey: ico, dicKey: dic) })
            {
                return index
            }
            return nil
        }

        /// The new clients, the clients that are filled, and where each entry of the book went.
        func finish() -> Finished {
            var finished = Finished()
            for (index, entry) in entries.enumerated() {
                if entry.isNew {
                    finished.references[index] = .new(finished.newClients.count)
                    finished.newClients.append(entry.madeClient())
                } else {
                    finished.references[index] = .existing(entry.client.id)
                    if let filled = entry.filledClient() {
                        finished.updates.append(filled)
                    }
                }
            }
            return finished
        }

        /// `text` without any white space.
        static func compact(_ text: String) -> String {
            String(String.UnicodeScalarView(text.unicodeScalars.filter { !$0.properties.isWhitespace }))
        }
    }
}
