import Foundation

/// The key in `app_settings` under which `AppSettings` is kept, as JSON.
private nonisolated let appSettingsKey = "app"

/// The choices of the person for the app, the supplier and the supplier's bank accounts.
extension Database {
    /// The choices of the person for the app: the defaults until they have been saved once.
    func appSettings() throws -> AppSettings {
        try read { connection in
            try connection.storedAppSettings()
        }
    }

    /// Saves `settings`, replacing the stored ones.
    func saveAppSettings(_ settings: AppSettings) throws {
        try write { connection in
            try connection.storeAppSettings(settings)
        }
    }

    /// Changes the stored settings with `change` (the defaults when none are stored yet) and saves them, in one
    /// transaction: no other write comes in between, so a change of one setting never undoes a change of another made
    /// meanwhile. Returns the settings as saved.
    @discardableResult
    func updateAppSettings(_ change: @Sendable (inout AppSettings) -> Void) throws -> AppSettings {
        try write { connection in
            var settings = try connection.storedAppSettings()
            change(&settings)
            try connection.storeAppSettings(settings)
            return settings
        }
    }

    /// The supplier: empty (`Supplier()`) until it has been saved once.
    func supplier() throws -> Supplier {
        try read { connection in
            try connection.storedSupplier()
        }
    }

    /// Saves `supplier`, replacing the stored one.
    func saveSupplier(_ supplier: Supplier) throws {
        try write { connection in
            try connection.storeSupplier(supplier)
        }
    }

    /// The bank accounts, one for a currency at most, in the order they were saved in.
    func bankAccounts() throws -> [BankAccount] {
        try read { connection in
            try connection.storedBankAccounts()
        }
    }

    /// Replaces all the bank accounts with `accounts`. Two accounts for one currency are refused.
    func saveBankAccounts(_ accounts: [BankAccount]) throws {
        try write { connection in
            try connection.storeBankAccounts(accounts)
        }
    }

    /// Changes the stored supplier and bank accounts with `change` and saves them, in one transaction: no other write
    /// comes in between, so a change of one field never undoes a change of another made meanwhile. Returns the supplier
    /// and the accounts as saved. Two accounts for one currency are refused, and nothing is changed then.
    @discardableResult
    func updateSupplierDetails(
        _ change: @Sendable (inout Supplier, inout [BankAccount]) -> Void
    ) throws -> (supplier: Supplier, accounts: [BankAccount]) {
        try write { connection in
            var supplier = try connection.storedSupplier()
            var accounts = try connection.storedBankAccounts()
            change(&supplier, &accounts)
            try connection.storeSupplier(supplier)
            try connection.storeBankAccounts(accounts)
            return (supplier, accounts)
        }
    }
}

/// The supplier and the bank accounts in their tables.
private nonisolated extension SQLiteConnection {
    func storedSupplier() throws -> Supplier {
        let rows = try query(
            """
            SELECT name, street, postcode, city, country, ico, dic, email, phone, czech_footer
            FROM supplier WHERE id = 1
            """
        )
        return rows.first.map { Supplier(row: $0) } ?? Supplier()
    }

    func storeSupplier(_ supplier: Supplier) throws {
        try run(
            """
            INSERT INTO supplier(
                id, name, street, postcode, city, country, ico, dic, email, phone, czech_footer)
            VALUES (1, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(id) DO UPDATE SET
                name = excluded.name, street = excluded.street, postcode = excluded.postcode,
                city = excluded.city, country = excluded.country, ico = excluded.ico, dic = excluded.dic,
                email = excluded.email, phone = excluded.phone, czech_footer = excluded.czech_footer
            """,
            [
                .text(supplier.name), .text(supplier.street), .text(supplier.postcode), .text(supplier.city),
                .text(supplier.country), .text(supplier.ico), .text(supplier.dic), .text(supplier.email),
                .text(supplier.phone), .text(supplier.czechFooter),
            ]
        )
    }

    func storedBankAccounts() throws -> [BankAccount] {
        try query(
            """
            SELECT currency, account_number, iban, bic, routing_number, account_type, bank_name_and_address
            FROM bank_account ORDER BY rowid
            """
        ).map { try BankAccount(row: $0) }
    }

    /// Replaces all the bank accounts with `accounts`, in the order given.
    func storeBankAccounts(_ accounts: [BankAccount]) throws {
        try run("DELETE FROM bank_account")
        for account in accounts {
            try run(
                """
                INSERT INTO bank_account(
                    currency, account_number, iban, bic, routing_number, account_type, bank_name_and_address)
                VALUES (?, ?, ?, ?, ?, ?, ?)
                """,
                [
                    .currency(account.currency), .text(account.accountNumber), .text(account.iban),
                    .text(account.bic), .text(account.routingNumber), .text(account.accountType),
                    .text(account.bankNameAndAddress),
                ]
            )
        }
    }
}

/// `AppSettings` as the JSON value of the row `app` in `app_settings`.
private nonisolated extension SQLiteConnection {
    func storedAppSettings() throws -> AppSettings {
        let stored = try scalar("SELECT value FROM app_settings WHERE key = ?", [.text(appSettingsKey)])
        guard case .text(let json)? = stored else { return AppSettings() }
        return try JSONDecoder().decode(AppSettings.self, from: Data(json.utf8))
    }

    func storeAppSettings(_ settings: AppSettings) throws {
        let json = String(decoding: try JSONEncoder().encode(settings), as: UTF8.self)
        try run(
            """
            INSERT INTO app_settings(key, value) VALUES (?, ?)
            ON CONFLICT(key) DO UPDATE SET value = excluded.value
            """,
            [.text(appSettingsKey), .text(json)]
        )
    }
}

private nonisolated extension Supplier {
    /// A row of `SELECT name, street, postcode, city, country, ico, dic, email, phone, czech_footer`.
    init(row: SQLRow) {
        self.init(
            name: row.text(0), street: row.text(1), postcode: row.text(2), city: row.text(3), country: row.text(4),
            ico: row.text(5), dic: row.text(6), email: row.text(7), phone: row.text(8), czechFooter: row.text(9)
        )
    }
}

private nonisolated extension BankAccount {
    /// A row of `SELECT currency, account_number, iban, bic, routing_number, account_type, bank_name_and_address`.
    init(row: SQLRow) throws {
        self.init(
            currency: try row.currency(0), accountNumber: row.text(1), iban: row.text(2), bic: row.text(3),
            routingNumber: row.text(4), accountType: row.text(5), bankNameAndAddress: row.text(6)
        )
    }
}
