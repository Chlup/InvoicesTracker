import Foundation

/// A statement with the arguments for its `?` placeholders.
nonisolated struct SearchStatement: Sendable, Equatable {
    var sql: String
    var arguments: [SQLValue]
}

/// The statements that look for the words of a query among the search documents. A word of three characters or more
/// is one of the terms of a single full-text `MATCH` (a trigram finds any piece of the text); shorter words, which
/// have no trigram, and every word when the search table is the plain one, are `LIKE` patterns. All of them, with the
/// days of the scope, are conditions of one statement, so the answer is the invoices that have every word.
nonisolated enum SearchQueries {
    /// The fewest characters a word needs to be looked up in the trigram index.
    static let shortestMatchedWord = 3

    /// The ids of the invoices of `scope` in `year` whose documents have every one of `words`. The first two arguments
    /// are the first and the last day, the others the words. Nil for a year outside the calendar.
    ///
    /// - `.issued`: the invoices issued in the year, drafts included.
    /// - `.paid`: the invoices with a payment dated in the year and on or before `asOf`.
    ///
    /// Without words every invoice of the scope is an answer.
    static func invoiceIDs(
        words: [String], kind: SearchIndexKind, scope: InvoiceScope, year: Int, asOf: CivilDate
    ) -> SearchStatement? {
        guard let period = Period(year: year) else { return nil }
        let documents = documentConditions(words: words, kind: kind)
        switch scope {
        case .issued:
            return SearchStatement(
                sql: """
                    SELECT invoice.id FROM invoice\(documents.join(on: "invoice.id"))
                    WHERE invoice.issue_date BETWEEN ? AND ?\(documents.sql)
                    """,
                arguments: period.arguments + documents.arguments
            )
        case .paid:
            // BETWEEN finds nothing when the as-of day is before the year.
            let days = [SQLValue.day(period.first), .day(min(period.last, asOf))]
            return SearchStatement(
                sql: """
                    SELECT payment.invoice_id FROM payment\(documents.join(on: "payment.invoice_id"))
                    WHERE payment.date BETWEEN ? AND ?\(documents.sql)
                    """,
                arguments: days + documents.arguments
            )
        }
    }

    /// How many invoices of `scope` have every one of `words`, by year: for `.issued` the year of issue, for `.paid`
    /// the year of the payment, counting the payments on or before `asOf`. Columns: the first four characters of the
    /// day, the count. A year without a match is not a row.
    static func countsByYear(
        words: [String], kind: SearchIndexKind, scope: InvoiceScope, asOf: CivilDate
    ) -> SearchStatement {
        let documents = documentConditions(words: words, kind: kind)
        switch scope {
        case .issued:
            return SearchStatement(
                sql: """
                    SELECT substr(invoice.issue_date, 1, 4), count(*) FROM invoice\(documents.join(on: "invoice.id"))
                    \(documents.clause) GROUP BY 1
                    """,
                arguments: documents.arguments
            )
        case .paid:
            return SearchStatement(
                sql: """
                    SELECT substr(payment.date, 1, 4), count(*) FROM payment\(documents.join(on: "payment.invoice_id"))
                    WHERE payment.date <= ?\(documents.sql) GROUP BY 1
                    """,
                arguments: [.day(asOf)] + documents.arguments
            )
        }
    }

    // MARK: Conditions on the documents

    /// The conditions on `invoice_search` for the words, as the text to add to a statement and its arguments.
    private nonisolated struct DocumentConditions {
        /// The conditions, each to be added with AND. Empty for no words.
        var conditions: [String] = []
        var arguments: [SQLValue] = []

        /// The join with the search table, or nothing when there is no condition on the documents.
        func join(on column: String) -> String {
            conditions.isEmpty ? "" : " JOIN invoice_search ON invoice_search.rowid = \(column)"
        }

        /// The conditions to add after a condition that is there already.
        var sql: String {
            conditions.map { " AND " + $0 }.joined()
        }

        /// The conditions as a clause of their own, for a statement that has no other condition.
        var clause: String {
            conditions.isEmpty ? "" : "WHERE " + conditions.joined(separator: " AND ")
        }
    }

    private static func documentConditions(words: [String], kind: SearchIndexKind) -> DocumentConditions {
        var terms: [String] = []
        var patterns: [String] = []
        var seen: Set<String> = []
        for word in words {
            // A word typed twice is looked for once.
            guard seen.insert(word).inserted else { continue }
            if kind == .fts5 && word.unicodeScalars.count >= shortestMatchedWord {
                // A phrase of its own, so that nothing in the word is syntax. A quote in it is written twice.
                terms.append("\"" + word.replacingOccurrences(of: "\"", with: "\"\"") + "\"")
            } else {
                patterns.append(likePattern(for: word))
            }
        }
        var found = DocumentConditions()
        if !terms.isEmpty {
            found.conditions.append("invoice_search MATCH ?")
            found.arguments.append(.text(terms.joined(separator: " AND ")))
        }
        for pattern in patterns {
            found.conditions.append(#"invoice_search.doc LIKE ? ESCAPE '\'"#)
            found.arguments.append(.text(pattern))
        }
        return found
    }

    /// The pattern that finds `word` anywhere in a document. `%`, `_` and the escape character itself are only
    /// themselves in it.
    private static func likePattern(for word: String) -> String {
        let escaped = word
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "%", with: "\\%")
            .replacingOccurrences(of: "_", with: "\\_")
        return "%" + escaped + "%"
    }
}

// MARK: - Queries

extension Database {
    /// The ids of the invoices of `scope` in `year` whose search document has every word of `query`. Case, diacritics
    /// and the kind of whitespace do not matter, and a word can be any part of the text. The scope is the one of
    /// `invoices(scope:year:asOf:)`: the invoices issued in the year, drafts included, or those with a payment dated in
    /// the year on or before `asOf`.
    ///
    /// A query without words is no search: it gives every invoice of the scope. A year outside the calendar has none.
    func searchInvoiceIDs(_ query: String, scope: InvoiceScope, year: Int, asOf: CivilDate) throws -> Set<Int64> {
        let words = SearchFolding.words(query)
        guard let statement = SearchQueries.invoiceIDs(
            words: words, kind: searchIndexKind, scope: scope, year: year, asOf: asOf)
        else {
            return []
        }
        return try read { connection in
            Set(try connection.query(statement.sql, statement.arguments).map { $0.int64(0) })
        }
    }

    /// How many invoices have every word of `query`, by year, for the links to other years: in the `.issued` scope by
    /// the year of issue, in the `.paid` scope by the year of the payment, counting the payments on or before `asOf`.
    /// The years without a match are not in the answer. A query without words counts every invoice of the scope.
    func searchCountsByYear(_ query: String, scope: InvoiceScope, asOf: CivilDate) throws -> [Int: Int] {
        let words = SearchFolding.words(query)
        let statement = SearchQueries.countsByYear(words: words, kind: searchIndexKind, scope: scope, asOf: asOf)
        return try read { connection in
            var counts: [Int: Int] = [:]
            for row in try connection.query(statement.sql, statement.arguments) {
                counts[try row.yearOfStoredDate(0)] = row.int(1)
            }
            return counts
        }
    }
}

// MARK: - Documents

extension Database {
    /// Brings the search document of the invoice up to date, inside the `write` that `connection` belongs to. Every
    /// save of an invoice calls it after the invoice, its items and its payment are written, and a save of its client
    /// does, so a document is never older than the data it is made of. An invoice that is not there has no document.
    ///
    /// The document is that of the invoice with the printed data of its client, and for an invoice that is still linked
    /// to a client the client's data as they are now as well.
    func rebuildSearchDocument(invoiceID: Int64, in connection: SQLiteConnection) throws {
        try connection.run("DELETE FROM invoice_search WHERE rowid = ?", [.integer(invoiceID)])
        let found = try Invoice.load(where: InvoiceQueries.byID, [.integer(invoiceID)], in: connection)
        guard let invoice = found.first else { return }
        var current: ClientSnapshot?
        if let clientID = invoice.clientID {
            current = try printedData(ofClient: clientID, in: connection)
        }
        try insertSearchDocument(of: invoice, currentClient: current, in: connection)
    }

    /// Makes the search documents of the invoices written for the client again, inside the `write` that `connection`
    /// belongs to.
    func rebuildSearchDocuments(ofClient clientID: Int64, in connection: SQLiteConnection) throws {
        for row in try connection.query("SELECT id FROM invoice WHERE client_id = ?", [.integer(clientID)]) {
            try rebuildSearchDocument(invoiceID: row.int64(0), in: connection)
        }
    }

    /// Makes every search document again, in one transaction, and drops the rows of the search table that no invoice
    /// has. For a database whose documents were made by other rules, and for the day the rules change.
    func rebuildAllSearchDocuments() throws {
        try write { connection in
            try connection.run("DELETE FROM invoice_search")
            let clients = try printedDataOfAllClients(in: connection)
            for invoice in try Invoice.load(where: InvoiceQueries.all, [], in: connection) {
                let current = invoice.clientID.flatMap { clients[$0] }
                try insertSearchDocument(of: invoice, currentClient: current, in: connection)
            }
        }
    }

    private func insertSearchDocument(
        of invoice: Invoice, currentClient: ClientSnapshot?, in connection: SQLiteConnection
    ) throws {
        var document = SearchDocumentBuilder.document(for: invoice)
        if let currentClient {
            let additional = SearchDocumentBuilder.additionalDocument(
                forCurrent: currentClient, besides: invoice.client)
            if !additional.isEmpty {
                document += " | " + additional
            }
        }
        try connection.run(
            "INSERT INTO invoice_search(rowid, doc) VALUES (?, ?)", [.integer(invoice.id), .text(document)])
    }
}
