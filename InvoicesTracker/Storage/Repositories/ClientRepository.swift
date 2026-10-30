import Foundation

/// What the client functions refuse to do.
nonisolated enum ClientError: Error, Equatable {
    /// No client has the id that was to be changed: it was deleted meanwhile, or the client was never saved.
    case notFound
}

extension Database {
    /// All clients, ordered by their names with case and diacritics ignored: "Alfa", "Ťuk", "Zeta". Clients whose
    /// names fold alike come in the order of the names as written, and then of their ids.
    func clients() throws -> [Client] {
        let clients = try read { connection in
            try connection.query("SELECT \(Client.columns) FROM client").map { try Client(row: $0) }
        }
        return Client.sortedByFoldedName(clients)
    }

    /// How many clients are stored.
    func clientCount() throws -> Int {
        try read { connection in
            guard case .integer(let count)? = try connection.scalar("SELECT count(*) FROM client") else {
                throw SQLiteError.step("count(*) returned no number.")
            }
            return Int(count)
        }
    }

    func client(id: Int64) throws -> Client? {
        try read { connection in
            let rows = try connection.query("SELECT \(Client.columns) FROM client WHERE id = ?", [.integer(id)])
            return try rows.first.map { try Client(row: $0) }
        }
    }

    /// Saves `client` and returns its id: a client with `id == 0` is inserted and gets a new id, any other is updated
    /// in place, or inserted with that id if no client has it. A stored client is never replaced by a new row, which
    /// would delete its templates and unlink its invoices.
    ///
    /// The search documents of the invoices of the client are made again in the same transaction, because an invoice
    /// is found by what its client is called now as well as by what it printed.
    @discardableResult
    func saveClient(_ client: Client) throws -> Int64 {
        try write { connection in
            let id = try client.store(in: connection)
            try rebuildSearchDocuments(ofClient: id, in: connection)
            return id
        }
    }

    /// Saves the changes to the stored client with the id of `client`. Unlike `saveClient`, which inserts a client with
    /// an id that no client has, this never brings a client back that was deleted meanwhile: it throws
    /// `ClientError.notFound` and writes nothing, also for a client that was never saved (`id == 0`).
    ///
    /// The search documents of the invoices of the client are made again in the same transaction, as `saveClient`
    /// does.
    func updateClient(_ client: Client) throws {
        try write { connection in
            guard try connection.query("SELECT 1 FROM client WHERE id = ?", [.integer(client.id)]).first != nil else {
                throw ClientError.notFound
            }
            let id = try client.store(in: connection)
            try rebuildSearchDocuments(ofClient: id, in: connection)
        }
    }

    /// The printed data of the client with `id` as they are now, or nil if there is none. For code that already runs in
    /// a `write`, so it takes the connection of it. Only the columns an invoice prints are read.
    func printedData(ofClient id: Int64, in connection: SQLiteConnection) throws -> ClientSnapshot? {
        let rows = try connection.query(
            "SELECT \(ClientSnapshot.columns) FROM client WHERE id = ?", [.integer(id)])
        return rows.first.map { ClientSnapshot(row: $0, from: 0) }
    }

    /// The printed data of every client as they are now, by the id of the client. Like `printedData(ofClient:in:)` it
    /// takes the connection of a `write`.
    func printedDataOfAllClients(in connection: SQLiteConnection) throws -> [Int64: ClientSnapshot] {
        var printed: [Int64: ClientSnapshot] = [:]
        for row in try connection.query("SELECT id, \(ClientSnapshot.columns) FROM client") {
            printed[row.int64(0)] = ClientSnapshot(row: row, from: 1)
        }
        return printed
    }
}

nonisolated extension Client {
    /// Writes the client row and returns its id: a client with `id == 0` is inserted and gets a new id, any other is
    /// updated in place, or inserted with that id if no client has it. It runs in the transaction of `connection`, and
    /// the search documents of the invoices of the client are for the caller to make again.
    func store(in connection: SQLiteConnection) throws -> Int64 {
        try connection.run(
            """
            INSERT INTO client(
                id, name, street, postcode, city, country, ico, dic, email, phone, currency, vat_mode, due_days,
                payment_method, language, origin, edited_after_import)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(id) DO UPDATE SET
                name = excluded.name, street = excluded.street, postcode = excluded.postcode,
                city = excluded.city, country = excluded.country, ico = excluded.ico, dic = excluded.dic,
                email = excluded.email, phone = excluded.phone, currency = excluded.currency,
                vat_mode = excluded.vat_mode, due_days = excluded.due_days,
                payment_method = excluded.payment_method, language = excluded.language,
                origin = excluded.origin, edited_after_import = excluded.edited_after_import
            """,
            [
                id == 0 ? .null : .integer(id), .text(name), .text(street), .text(postcode), .text(city),
                .text(country), .text(ico), .text(dic), .text(email), .text(phone), .currency(currency),
                .choice(vatMode), .int(dueDays), .text(paymentMethod), .choice(language), .choice(origin),
                .flag(editedAfterImport),
            ]
        )
        // The id is read before anything else is written, which changes the last row id of the connection.
        return id == 0 ? connection.lastInsertRowID : id
    }
}

private nonisolated extension ClientSnapshot {
    /// The columns of a client row that an invoice prints, in the order `init(row:from:)` reads them.
    static let columns = "name, street, postcode, city, country, ico, dic, email"

    /// The columns of `columns` that start at `first`.
    init(row: SQLRow, from first: Int) {
        self.init(
            name: row.text(first), street: row.text(first + 1), postcode: row.text(first + 2),
            city: row.text(first + 3), country: row.text(first + 4), ico: row.text(first + 5),
            dic: row.text(first + 6), email: row.text(first + 7)
        )
    }
}

private nonisolated extension Client {
    /// The columns of a client row, in the order `init(row:)` reads them.
    static let columns = """
        id, name, street, postcode, city, country, ico, dic, email, phone, currency, vat_mode, due_days, \
        payment_method, language, origin, edited_after_import
        """

    init(row: SQLRow) throws {
        self.init(
            id: row.int64(0), name: row.text(1), street: row.text(2), postcode: row.text(3), city: row.text(4),
            country: row.text(5), ico: row.text(6), dic: row.text(7), email: row.text(8), phone: row.text(9),
            currency: try row.currency(10), vatMode: try row.choice(11), dueDays: row.int(12),
            paymentMethod: row.text(13), language: try row.choice(14), origin: try row.choice(15),
            editedAfterImport: row.bool(16)
        )
    }

    /// `clients` in the order of their folded names, then of the names as written, then of their ids. A plain
    /// comparison of the names would put "Ťuk" after "Zeta".
    static func sortedByFoldedName(_ clients: [Client]) -> [Client] {
        let keyed = clients.map { (folded: SearchFolding.fold($0.name), client: $0) }
        let sorted = keyed.sorted { first, second in
            (first.folded, first.client.name, first.client.id) < (second.folded, second.client.name, second.client.id)
        }
        return sorted.map { $0.client }
    }
}
