import Foundation

/// What the template functions refuse to do.
nonisolated enum TemplateError: Error, Equatable {
    /// No template has the id that was to be changed: it was deleted meanwhile, or the template was never saved.
    case notFound
}

extension Database {
    /// All templates in the order they were created, each with its items in their order.
    func templates() throws -> [InvoiceTemplate] {
        try read { connection in
            let templateRows = try connection.query(
                """
                SELECT id, name, client_id, vat_mode, due_days, duzp_at_month_end, note
                FROM template ORDER BY id
                """
            )
            let itemRows = try connection.query(
                """
                SELECT template_id, description, quantity, unit, unit_price_minor
                FROM template_item ORDER BY template_id, position
                """
            )
            var itemsByTemplate: [Int64: [TemplateItem]] = [:]
            for row in itemRows {
                let item = try TemplateItem(row: row)
                itemsByTemplate[row.int64(0), default: []].append(item)
            }
            return try templateRows.map { row in
                try InvoiceTemplate(row: row, items: itemsByTemplate[row.int64(0)] ?? [])
            }
        }
    }

    /// Saves `template` and returns its id: a template with `id == 0` is inserted and gets a new id, any other is
    /// updated in place, or inserted with that id if no template has it. Its items replace the stored ones. The
    /// template must belong to a client that exists.
    @discardableResult
    func saveTemplate(_ template: InvoiceTemplate) throws -> Int64 {
        try write { connection in
            try template.store(in: connection)
        }
    }

    /// Saves the changes to the stored template with the id of `template`, the items with them. Unlike `saveTemplate`,
    /// which inserts a template with an id that no template has, this never brings a template back that was deleted
    /// meanwhile: it throws `TemplateError.notFound` and writes nothing, also for a template that was never saved
    /// (`id == 0`). The template must belong to a client that exists, as for `saveTemplate`.
    func updateTemplate(_ template: InvoiceTemplate) throws {
        try write { connection in
            guard try connection.query("SELECT 1 FROM template WHERE id = ?", [.integer(template.id)]).first != nil
            else {
                throw TemplateError.notFound
            }
            _ = try template.store(in: connection)
        }
    }

    /// Deletes the template with its items. A template that is not there is not an error.
    func deleteTemplate(id: Int64) throws {
        try write { connection in
            try connection.run("DELETE FROM template WHERE id = ?", [.integer(id)])
        }
    }
}

private nonisolated extension InvoiceTemplate {
    /// Writes the template row and its items in the transaction of `connection` and returns the id of the template: a
    /// template with `id == 0` is inserted and gets a new id, any other is updated in place, or inserted with that id
    /// if no template has it.
    func store(in connection: SQLiteConnection) throws -> Int64 {
        try connection.run(
            """
            INSERT INTO template(id, name, client_id, vat_mode, due_days, duzp_at_month_end, note)
            VALUES (?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(id) DO UPDATE SET
                name = excluded.name, client_id = excluded.client_id, vat_mode = excluded.vat_mode,
                due_days = excluded.due_days, duzp_at_month_end = excluded.duzp_at_month_end,
                note = excluded.note
            """,
            [
                id == 0 ? .null : .integer(id), .text(name), .integer(clientID), .choice(vatMode), .int(dueDays),
                .flag(duzpAtMonthEnd), .text(note),
            ]
        )
        let storedID = id == 0 ? connection.lastInsertRowID : id
        try connection.run("DELETE FROM template_item WHERE template_id = ?", [.integer(storedID)])
        for (position, item) in items.enumerated() {
            try connection.run(
                """
                INSERT INTO template_item(template_id, position, description, quantity, unit, unit_price_minor)
                VALUES (?, ?, ?, ?, ?, ?)
                """,
                [
                    .integer(storedID), .int(position), .text(item.description), .decimal(item.quantity),
                    .text(item.unit), .integer(item.unitPriceMinor),
                ]
            )
        }
        return storedID
    }
}

private nonisolated extension TemplateItem {
    /// A row of `SELECT template_id, description, quantity, unit, unit_price_minor`.
    init(row: SQLRow) throws {
        self.init(
            description: row.text(1), quantity: try row.decimal(2), unit: row.text(3), unitPriceMinor: row.int64(4)
        )
    }
}

private nonisolated extension InvoiceTemplate {
    /// A row of `SELECT id, name, client_id, vat_mode, due_days, duzp_at_month_end, note`, with its items.
    init(row: SQLRow, items: [TemplateItem]) throws {
        self.init(
            id: row.int64(0), name: row.text(1), clientID: row.int64(2), items: items, vatMode: try row.choice(3),
            dueDays: row.int(4), duzpAtMonthEnd: row.bool(5), note: row.text(6)
        )
    }
}
