import Foundation

nonisolated extension ImportPlanner {
    /// One run of `plan(sources:existingInvoices:clients:knownCurrencies:payments:invoiceRates:)`: the plan as it is
    /// made, and what it is made from. The rules are those of that function.
    nonisolated struct Pass {
        /// A source of the import: a row of a CSV file or an ISDOC invoice, by its place in `ImportSources`.
        enum Source: Hashable {
            case row(Int)
            case isdoc(Int)
        }

        /// The sources of the import that are one invoice: those with the same digits in the number and the same
        /// currency, and for a row whose number has no digit (which says nothing about the invoice) the same Fakturoid
        /// id.
        struct Group {
            let digits: String
            let currency: CurrencyCode

            /// The source the group is dealt with at: the first of it, the rows coming before the ISDOC invoices.
            let first: Source

            /// The offsets of the rows and of the ISDOC invoices, each in the order of the files.
            var rowOffsets: [Int] = []
            var isdocOffsets: [Int] = []

            /// The offset of the first row that is cancelled in Fakturoid, if one is.
            var cancelledOffset: Int?
        }

        /// A document as the outcomes of the plan count it: by the digits of its number and its currency, as invoices
        /// are matched, and by whether it is a proforma invoice. A proforma invoice is a document of its own: it never
        /// joins the group of the invoice with the same digits, so it is never counted as that invoice either.
        struct DocumentKey: Hashable {
            let digits: String
            let currency: CurrencyCode
            let proforma: Bool
        }

        /// A source that is skipped, kept until the plan is made: it is counted then unless its document is counted
        /// already (`finishSkips()`).
        struct Skip {
            let label: String
            let reason: String

            /// The document of the source, or nil when its number has no digit or its currency is no code, which says
            /// nothing of which document it is: such a source is always counted.
            let key: DocumentKey?
        }

        private static let anotherWithoutDigits = "jiná faktura už má číslo bez číslic"
        private static let anotherCurrency = "číslo už používá faktura v jiné měně"
        private static let anotherFakturoidInvoice = "číslo už používá jiná faktura z Fakturoidu"

        /// Whether an invoice of the plan is added or replaces one that is there.
        private enum Addition {
            case insert
            case update
        }

        private let rows: [FakturoidRow]
        private let isdocs: [IsdocInvoice]
        private let rowClasses: [RowClass]
        private let isdocClasses: [IsdocClass]
        private let knownCurrencies: Set<CurrencyCode>
        private let payments: [String: Payment]
        private let invoiceRates: [String: StoredRate]
        private let existingByDigits: [String: Invoice]
        private let existingByFakturoidID: [String: Invoice]
        private var book: ClientBook
        private(set) var plan = ImportPlan()

        /// The digits of the numbers of the invoices this import adds. A number belongs to one invoice.
        private var addedDigits: Set<String> = []

        /// The place in the book of the client of each source that has one.
        private var entryOfSource: [Source: Int] = [:]

        /// The place in the book of the client of each invoice that is added or updated, by the digits of its number.
        private var entryOfInvoice: [String: Int] = [:]

        /// The countries noted as no code already.
        private var notedCountries: Set<String> = []

        /// The sources that are skipped, in the order they are met (`finishSkips()`).
        private var skips: [Skip] = []

        /// The invoices of the groups that are added, overwritten, unchanged or not added: a source of one of them
        /// that is skipped is not counted again.
        private var countedInvoices: Set<DocumentKey> = []

        /// A pass over `sources` against the invoices and clients that are there. See `plan` for the parameters.
        init(
            sources: ImportSources, existingInvoices: [Invoice], clients: [Client], knownCurrencies: Set<CurrencyCode>,
            payments: [String: Payment], invoiceRates: [String: StoredRate]
        ) {
            rows = sources.rows
            isdocs = sources.isdocs
            rowClasses = sources.rows.map {
                ImportPlanner.classify($0, knownCurrencies: knownCurrencies, invoiceRates: invoiceRates)
            }
            isdocClasses = sources.isdocs.map { ImportPlanner.classify($0) }
            self.knownCurrencies = knownCurrencies
            self.payments = payments
            self.invoiceRates = invoiceRates
            existingByDigits = Dictionary(
                existingInvoices.map { ($0.numberDigits, $0) }, uniquingKeysWith: { first, _ in first })
            existingByFakturoidID = Dictionary(
                existingInvoices.compactMap { invoice -> (String, Invoice)? in
                    guard case .imported(let id, _, _) = invoice.source, !id.isEmpty else { return nil }
                    return (id, invoice)
                }, uniquingKeysWith: { first, _ in first })
            book = ClientBook(clients: clients, knownCurrencies: knownCurrencies)
        }

        /// Makes the plan: the clients of the groups first, then each source in the order of the files (a group where
        /// its first source is), and the skipped sources and the links of the invoices to their clients last.
        mutating func run() {
            let (groups, groupOfSource) = groups()
            placeClients(of: groups)
            let sources = rows.indices.map { Source.row($0) } + isdocs.indices.map { Source.isdoc($0) }
            for source in sources {
                if let index = groupOfSource[source] {
                    if groups[index].first == source {
                        visit(groups[index])
                    }
                    continue
                }
                switch source {
                case .row(let offset):
                    visitAlone(row: offset)
                case .isdoc(let offset):
                    visitAlone(isdoc: offset)
                }
            }
            finishSkips()
            finishClients()
        }

        /// A row that is in no group: a proforma invoice and a cancelled row that says a currency that is no code are
        /// skipped, and a row no invoice can be made of is a conflict.
        private mutating func visitAlone(row offset: Int) {
            let row = rows[offset]
            let currency = ImportPlanner.currency(of: row)
            switch rowClasses[offset] {
            case .skipProforma:
                skip(
                    Self.label(row.number), "zálohová faktura",
                    key: Self.key(number: row.number, currency: currency, proforma: true))
            case .skipCancelled:
                skip(
                    Self.label(row.number), ImportPlanner.cancelledReason,
                    key: Self.key(number: row.number, currency: currency, proforma: false))
            case .invoice:
                if let reason = ImportPlanner.unstorableReason(row) {
                    addConflict(Self.label(row.number), reason)
                }
            }
        }

        /// An ISDOC invoice that is in no group: one that is skipped or cannot be added (`IsdocClass`).
        private mutating func visitAlone(isdoc offset: Int) {
            let isdoc = isdocs[offset]
            let label = Self.label(isdoc.number)
            switch isdocClasses[offset] {
            case .skip(let reason):
                let key = Self.key(
                    number: isdoc.number, currency: CurrencyCode(isdoc.currency), proforma: isdoc.documentType == 4)
                skip(label, reason, key: key)
            case .conflict(let reason):
                addConflict(label, reason)
            case .invoice:
                // Every ISDOC invoice that can be an invoice is in a group.
                break
            }
        }

        // MARK: Groups

        /// The groups of the sources, in the order of their first sources, and the group each source is in. A row is in
        /// none when it is a proforma invoice, when no invoice can be made of it (it is a conflict by itself) or when
        /// it is cancelled and says a currency that is no code (it is skipped by itself). An ISDOC invoice is in none
        /// when it is skipped or cannot be added whatever the app holds.
        private func groups() -> (groups: [Group], groupOfSource: [Source: Int]) {
            struct Key: Hashable {
                let digits: String
                let currency: CurrencyCode

                /// Of a row whose number has no digit: the Fakturoid id, and the row when it has none.
                let fakturoidID: String
                let offset: Int
            }
            var indexOfKey: [Key: Int] = [:]
            var groups: [Group] = []
            var groupOfSource: [Source: Int] = [:]
            func index(of key: Key, first: Source) -> Int {
                if let known = indexOfKey[key] {
                    return known
                }
                indexOfKey[key] = groups.count
                groups.append(Group(digits: key.digits, currency: key.currency, first: first))
                return groups.count - 1
            }
            for (offset, row) in rows.enumerated() {
                let cancelled: Bool
                switch rowClasses[offset] {
                case .skipProforma:
                    continue
                case .skipCancelled:
                    cancelled = true
                case .invoice:
                    guard ImportPlanner.unstorableReason(row) == nil else { continue }
                    cancelled = false
                }
                guard let currency = ImportPlanner.currency(of: row) else { continue }
                let digits = InvoiceNumbering.digits(of: row.number)
                let withoutDigits = digits.isEmpty
                let key = Key(
                    digits: digits, currency: currency, fakturoidID: withoutDigits ? row.fakturoidID : "",
                    offset: withoutDigits && row.fakturoidID.isEmpty ? offset : -1)
                let group = index(of: key, first: .row(offset))
                groups[group].rowOffsets.append(offset)
                if cancelled && groups[group].cancelledOffset == nil {
                    groups[group].cancelledOffset = offset
                }
                groupOfSource[.row(offset)] = group
            }
            for (offset, isdoc) in isdocs.enumerated() {
                guard case .invoice(let currency) = isdocClasses[offset] else { continue }
                let key = Key(
                    digits: InvoiceNumbering.digits(of: isdoc.number), currency: currency, fakturoidID: "", offset: -1)
                let group = index(of: key, first: .isdoc(offset))
                groups[group].isdocOffsets.append(offset)
                groupOfSource[.isdoc(offset)] = group
            }
            return (groups, groupOfSource)
        }

        /// Deals with a group: a cancelled one, or an invoice. A group that is not skipped counts its invoice, so that
        /// a source of it that is skipped is not counted again.
        private mutating func visit(_ group: Group) {
            let skipsBefore = skips.count
            if let cancelled = group.cancelledOffset {
                visitCancelled(group, row: rows[cancelled])
            } else {
                visitInvoice(group)
            }
            if skips.count == skipsBefore, !group.digits.isEmpty {
                countedInvoices.insert(DocumentKey(digits: group.digits, currency: group.currency, proforma: false))
            }
        }

        // MARK: Clients

        /// Puts the client of every source that is going to be an invoice in the book, whatever becomes of the
        /// invoice, the oldest first: the newest gives the values. On one day an ISDOC invoice comes before the rows,
        /// as it is applied before the row of its invoice. The sources of an invoice that is cancelled are not.
        private mutating func placeClients(of groups: [Group]) {
            /// A source to place, with what it is ordered by.
            struct Placement {
                let source: Source
                let day: CivilDate?
                let rank: Int
                let order: Int
            }
            var placements: [Placement] = []
            for group in groups where group.cancelledOffset == nil {
                for offset in group.rowOffsets {
                    placements.append(
                        Placement(source: .row(offset), day: rows[offset].issuedOn, rank: 1, order: offset))
                }
                for offset in group.isdocOffsets {
                    placements.append(
                        Placement(
                            source: .isdoc(offset), day: isdocs[offset].issueDate, rank: 0, order: rows.count + offset))
                }
            }
            placements.sort { first, second in
                guard let firstDay = first.day, let secondDay = second.day else { return first.order < second.order }
                return (firstDay, first.rank, first.order) < (secondDay, second.rank, second.order)
            }
            for placement in placements {
                switch placement.source {
                case .row(let offset):
                    entryOfSource[placement.source] = book.place(rows[offset])
                case .isdoc(let offset):
                    entryOfSource[placement.source] = book.place(isdocs[offset])
                }
            }
        }

        /// The place in the book of the client of `group`: the customer of its ISDOC invoice, which owns the printed
        /// client, or else the client of its first row.
        private func entry(of group: Group) -> Int? {
            if let offset = group.isdocOffsets.first, let entry = entryOfSource[.isdoc(offset)] {
                return entry
            }
            return group.rowOffsets.first.flatMap { entryOfSource[.row($0)] }
        }

        /// Makes the clients and gives the added and updated invoices their clients: the id of one that is there, the
        /// index of one that is new.
        private mutating func finishClients() {
            let finished = book.finish()
            plan.newClients = finished.newClients
            plan.clientUpdates = finished.updates
            for index in plan.inserts.indices {
                linkClient(ofInsert: index, finished)
            }
            for index in plan.updates.indices {
                linkClient(ofUpdate: index, finished)
            }
        }

        /// Links the invoice to add at `index` to its client.
        private mutating func linkClient(ofInsert index: Int, _ finished: ClientBook.Finished) {
            let digits = plan.inserts[index].numberDigits
            switch entryOfInvoice[digits].flatMap({ finished.references[$0] }) {
            case .existing(let id)?: plan.inserts[index].clientID = id
            case .new(let position)?: plan.newClientIndexByDigits[digits] = position
            case nil: break
            }
        }

        /// Links the invoice to update at `index` to its client.
        private mutating func linkClient(ofUpdate index: Int, _ finished: ClientBook.Finished) {
            let digits = plan.updates[index].numberDigits
            switch entryOfInvoice[digits].flatMap({ finished.references[$0] }) {
            case .existing(let id)?:
                plan.updates[index].clientID = id
            case .new(let position)?:
                plan.updates[index].clientID = nil
                plan.newClientIndexByDigits[digits] = position
            case nil:
                // No client could be made of the files, or the invoice is only held for review: it keeps its link.
                break
            }
        }

        // MARK: Invoices

        /// The number of a source as the lines of the plan show it.
        private static func label(_ number: String) -> String {
            number.isEmpty ? "(bez čísla)" : number
        }

        /// The number of a group as the lines of the plan show it: that of its ISDOC invoice, which owns the number,
        /// or else that of its first row.
        private func label(of group: Group) -> String {
            if let offset = group.isdocOffsets.first {
                return Self.label(isdocs[offset].number)
            }
            return Self.label(group.rowOffsets.first.map { rows[$0].number } ?? "")
        }

        /// The line of the summary for an invoice held for review.
        private func reviewLine(_ label: String, _ reason: String) -> String {
            reason == ImportPlanner.differingRowsReason ? "\(label) — \(reason) — ke kontrole" : "\(label) — \(reason)"
        }

        /// Whether `fingerprints`, those of the rows or of the ISDOC invoices of a group, are not all the same.
        private static func differ(_ fingerprints: [String]) -> Bool {
            Set(fingerprints).count > 1
        }

        /// An invoice that is not cancelled: added, updated, held for its files that differ, unchanged, or a conflict.
        private mutating func visitInvoice(_ group: Group) {
            let row = group.rowOffsets.first.map { rows[$0] }
            let isdoc = group.isdocOffsets.first.map { isdocs[$0] }
            let label = label(of: group)
            let digits = group.digits
            let differing =
                Self.differ(group.rowOffsets.map { rows[$0].fingerprint })
                || Self.differ(group.isdocOffsets.map { isdocs[$0].fingerprint })
            // Another invoice of this import has the number already: in another currency, or without a digit.
            guard !addedDigits.contains(digits) else {
                addConflict(label, digits.isEmpty ? Self.anotherWithoutDigits : Self.anotherCurrency)
                return
            }
            guard let existing = existingByDigits[digits] else {
                if let row, !row.fakturoidID.isEmpty, let renumbered = existingByFakturoidID[row.fakturoidID] {
                    addConflict(label, "už importováno pod číslem \(renumbered.number)")
                } else {
                    addNew(group, row: row, isdoc: isdoc, differing: differing, label: label)
                }
                return
            }
            // A number without a digit says nothing about which invoice it is: only the invoice with the Fakturoid
            // id of the row is the invoice of the row.
            if digits.isEmpty && !isInvoice(existing, ofFakturoidID: row?.fakturoidID ?? "") {
                addConflict(label, Self.anotherWithoutDigits)
                return
            }
            guard existing.currency == group.currency else {
                addConflict(label, Self.anotherCurrency)
                return
            }
            // Two invoices of Fakturoid whose numbers have the same digits: the stored one is not the row's.
            if let row, case .imported(let storedID, _, _) = existing.source,
                Self.areOtherFakturoidInvoices(storedID, row.fakturoidID)
            {
                addConflict(label, Self.anotherFakturoidInvoice)
                return
            }
            if differing {
                holdForDifferingFiles(existing, of: group, label: label)
            } else {
                update(existing, group: group, row: row, isdoc: isdoc, label: label)
            }
        }

        /// A group the app has no invoice of: the invoice its files make is added, held for review without a payment
        /// when its rows or its ISDOC invoices differ (`heldForDifferingFiles(_:of:isNew:)`). The first row and the
        /// first ISDOC invoice make it then, as they make any new invoice, and the hold takes the payment and the
        /// review of the row away. A foreign invoice of an ISDOC file alone that has no rate is a conflict.
        private mutating func addNew(
            _ group: Group, row: FakturoidRow?, isdoc: IsdocInvoice?, differing: Bool, label: String
        ) {
            guard
                let made = composed(
                    over: nil, row: row, applyingRow: row != nil, isdoc: isdoc, applyingIsdoc: isdoc != nil,
                    entry: entry(of: group), label: label)
            else {
                return
            }
            var invoice = made.invoice
            if row == nil && !invoice.currency.isCZK && invoice.invoiceRate == nil {
                addConflict(label, ImportPlanner.missingInvoiceRateReason)
                return
            }
            if differing {
                invoice = heldForDifferingFiles(invoice, of: group, isNew: true)
                invoice.payment = nil
            }
            add(invoice, notes: made.notes, of: group, label: label, as: .insert)
        }

        /// A group whose invoice is there and whose files do not differ: the ISDOC invoice is applied when it differs
        /// from the file the invoice was last imported from, and the row when the invoice was made in the app or the
        /// row differs from the one it has taken (`takenRow(of:)`). When neither is, the invoice is unchanged.
        ///
        /// An invoice still held because files of it differed ends its hold only with a group that brings every kind of
        /// file it is held for (`heldKinds(of:)`). Such a group applies the files of those kinds whatever the invoice
        /// is stored under, and each file is stored as any applied file is. The row's status, payment and review then
        /// replace the flag, and the flag goes when no row is applied. A group that lacks a kind the invoice is held
        /// for settles nothing: it applies no file of a held kind and leaves the flag, while a kind the invoice is not
        /// held for is applied as usual. A flag the person has resolved, or a flag of another reason, does not count:
        /// the invoice is compared as usual then. An invoice the group leaves not held for its rows is stored under the
        /// row it has taken, not under the marker of it that a resolved hold left (`released(_:)`).
        private mutating func update(
            _ existing: Invoice, group: Group, row: FakturoidRow?, isdoc: IsdocInvoice?, label: String
        ) {
            var applyingIsdoc = isdoc.map { $0.fingerprint != existing.isdocFingerprint } ?? false
            var applyingRow = false
            if let row {
                switch existing.source {
                case .app:
                    applyingRow = true
                case .imported:
                    applyingRow = Self.takenRow(of: existing) != row.fingerprint
                }
            }
            let held = Self.heldKinds(of: existing)
            let ending = held.map { (!$0.rows || row != nil) && (!$0.isdocs || isdoc != nil) } ?? false
            if let held {
                if held.rows {
                    applyingRow = ending
                }
                if held.isdocs {
                    applyingIsdoc = ending
                }
            }
            guard applyingIsdoc || applyingRow else {
                plan.unchangedNumbers.append(label)
                return
            }
            guard
                var made = composed(
                    over: existing, row: row, applyingRow: applyingRow, isdoc: isdoc, applyingIsdoc: applyingIsdoc,
                    entry: entry(of: group), label: label)
            else {
                return
            }
            if held != nil {
                if !ending {
                    made.invoice.review = existing.review
                } else if !applyingRow {
                    made.invoice.review = nil
                }
            }
            if held?.rows != true {
                made.invoice.source = Self.released(made.invoice.source)
            }
            add(made.invoice, notes: made.notes, of: group, label: label, as: .update)
        }

        /// The kinds of file an invoice held for review by a hold (`ImportPlanner.differingRowsReason`) is held for, or
        /// nil when the invoice is not held so: it has no flag, the person has resolved it, or it has a flag of another
        /// reason. A kind is held when the invoice's fingerprint of it holds it (`ImportPlanner.isHoldingFingerprint`):
        /// the fingerprint of a set of files it has not taken, such as files that differed, or the marker of a row it
        /// has taken but is held for all the same. An invoice with the flag and neither was held by the import as it
        /// was before ISDOC files, which held an invoice only for its rows and stored it under the row it was made
        /// from: it is held for its rows.
        private static func heldKinds(of invoice: Invoice) -> (rows: Bool, isdocs: Bool)? {
            guard invoice.review?.reason == ImportPlanner.differingRowsReason else { return nil }
            let rows = rowFingerprint(of: invoice).map { ImportPlanner.isHoldingFingerprint($0) } ?? false
            let isdocs = invoice.isdocFingerprint.map { ImportPlanner.isHoldingFingerprint($0) } ?? false
            return rows || isdocs ? (rows: rows, isdocs: isdocs) : (rows: true, isdocs: false)
        }

        /// The invoice the files of a group make over `stored` (nil for a new invoice), and the notes on it; nil when
        /// there is nothing to make it of.
        ///
        /// A new invoice starts as the invoice of the row, or else as the invoice of the ISDOC file alone, in the
        /// language and with the payment method of the client at `entry`. The ISDOC file is applied first when
        /// `applyingIsdoc` is set, then the row when `applyingRow` is: only its own fields on an invoice the ISDOC
        /// owns, the whole invoice of the row on any other. The payment and the source follow the row that is applied,
        /// or stay with the stored invoice when none is.
        private func composed(
            over stored: Invoice?, row: FakturoidRow?, applyingRow: Bool, isdoc: IsdocInvoice?, applyingIsdoc: Bool,
            entry: Int?, label: String
        ) -> (invoice: Invoice, notes: [String])? {
            let csv = row.flatMap {
                ImportPlanner.invoice(from: $0, knownCurrencies: knownCurrencies, invoiceRates: invoiceRates)
            }
            var result: Invoice
            var notes: [String] = []
            var isdocApplied = false
            if let stored {
                result = stored
            } else if let csv {
                result = csv
            } else if let isdoc {
                let defaults = book.defaults(of: entry)
                let language = defaults.language ?? ImportPlanner.language(ofCustomer: isdoc.customer)
                let paymentMethod =
                    IsdocInvoiceBuilder.paymentMethod(code: isdoc.paymentMeansCode, language: language)
                    ?? defaults.paymentMethod
                guard
                    let made = ImportPlanner.invoice(
                        fromIsdoc: isdoc, language: language, paymentMethod: paymentMethod)
                else {
                    return nil
                }
                result = made.invoice
                notes = made.notes
                isdocApplied = true
            } else {
                return nil
            }
            if applyingIsdoc && !isdocApplied, let isdoc {
                let applied = ImportPlanner.applying(isdoc, to: result, keepingZeroMode: true)
                result = applied.invoice
                notes += applied.notes
            }
            if applyingRow, let row, let csv {
                if result.isdocFingerprint != nil {
                    result = ImportPlanner.applyingOwnFields(of: row, csv: csv, to: result)
                } else {
                    var replaced = csv
                    replaced.id = result.id
                    replaced.clientID = result.clientID
                    result = replaced
                }
                result.payment = payment(of: row, csv: csv, stored: stored, final: result)
                result.source = .imported(
                    fakturoidID: row.fakturoidID.isEmpty ? Self.fakturoidID(of: stored) : row.fakturoidID,
                    fingerprint: row.fingerprint, changedInApp: false)
            } else {
                if let stored {
                    result.payment = stored.payment.map { ImportPlanner.reapplied($0, from: stored, to: result) }
                }
                result.source = Self.unmarked(result.source)
            }
            if let row, result.isdocFingerprint != nil, let subtotal = row.subtotalMinor, !row.vatUnreadable,
                subtotal != result.netMinor || (row.vatMinor ?? 0) != result.vatMinor
            {
                notes.append("\(label) — \(ImportPlanner.amountsDisagreeNote)")
            }
            return (result, notes)
        }

        /// The payment the applied `row` gives `final`, the invoice it ends in: none when the row holds the invoice for
        /// review or is not paid. A row paid on the day of the payment of `stored` keeps that payment, which keeps how
        /// it was converted, and any other paid row gives its converted payment of `payments`, which was converted for
        /// `csv`. Either is converted again the way it was when `final` has other amounts.
        private func payment(of row: FakturoidRow, csv: Invoice, stored: Invoice?, final: Invoice) -> Payment? {
            guard final.review == nil, row.status == "paid", let day = row.paidOn else { return nil }
            if let stored, let kept = stored.payment, kept.date == day {
                return ImportPlanner.reapplied(kept, from: stored, to: final)
            }
            return payments[row.fingerprint].map { ImportPlanner.reapplied($0, from: csv, to: final) }
        }

        /// The Fakturoid id `stored` was imported with, or empty for a new invoice or one made in the app.
        private static func fakturoidID(of stored: Invoice?) -> String {
            guard case .imported(let id, _, _)? = stored?.source else { return "" }
            return id
        }

        /// `source` as an invoice the plan updates has it: imported, and not marked as changed in the app. An invoice
        /// made in the app, or a new one, that no row is applied to has no Fakturoid id and no fingerprint of a row.
        private static func unmarked(_ source: InvoiceSource) -> InvoiceSource {
            switch source {
            case .app:
                .imported(fakturoidID: "", fingerprint: "", changedInApp: false)
            case .imported(let id, let fingerprint, _):
                .imported(fakturoidID: id, fingerprint: fingerprint, changedInApp: false)
            }
        }

        /// `source` as an invoice the plan stores without holding it for its rows has it: `unmarked(_:)`, and with the
        /// marker of a row it has taken (`ImportPlanner.fingerprint(ofTakenRow:)`) written back as the fingerprint of
        /// that row. The marker holds the invoice for its rows only while the hold that wrote it lasts. Kept after the
        /// person has resolved that hold, it would make a later hold that is not for the rows, such as one for ISDOC
        /// files alone, hold them too: the unchanged row would be forced over what the person did, and an ISDOC file
        /// alone would no longer end that hold.
        private static func released(_ source: InvoiceSource) -> InvoiceSource {
            guard case .imported(let id, let fingerprint, _) = source else { return unmarked(source) }
            return .imported(
                fakturoidID: id, fingerprint: ImportPlanner.takenFingerprint(fingerprint) ?? fingerprint,
                changedInApp: false)
        }

        /// The rows or the ISDOC invoices of the import for an invoice that is there differ, so none of them is
        /// applied: the invoice keeps all it holds, and is held for review (`heldForDifferingFiles(_:of:isNew:)`).
        /// When it is stored under these very files already (`isStored(_:underTheFilesOf:)`), it is unchanged,
        /// whatever its flag: it was held for them by an earlier import, and whatever the person did with it since
        /// stays until Fakturoid's data changes.
        private mutating func holdForDifferingFiles(_ existing: Invoice, of group: Group, label: String) {
            if isStored(existing, underTheFilesOf: group) {
                plan.unchangedNumbers.append(label)
                return
            }
            plan.updates.append(heldForDifferingFiles(existing, of: group, isNew: false))
            plan.overwrittenNumbers.append(label)
            plan.reviewItems.append(reviewLine(label, ImportPlanner.differingRowsReason))
        }

        /// `invoice` held for review because the files of `group` differ, and stored so that the same files in a later
        /// import leave it alone (`isStored(_:underTheFilesOf:)`) and the hold ends only with an import that brings
        /// every kind of file it is held for (`heldKinds(of:)`). `isNew` tells whether the group's files have just made
        /// `invoice` (`addNew`), or whether it is the invoice that is there.
        ///
        /// Each kind of file the group has (the rows, or the ISDOC invoices) is held: it is stored under the
        /// fingerprint of the set of its files in the group (`ImportPlanner.fingerprint(ofAll:)`), which is never that
        /// of a single file, so that only an import that brings that kind ends the hold and applies its file. The
        /// exception is a kind whose files are all alike and whose very file the invoice has taken already: the file it
        /// was last imported from (its CSV row, or its `isdocFingerprint`), or, on a new invoice, the ISDOC file that
        /// made it. The rows of a new invoice are never taken, since the hold takes their payment and review away. Such
        /// a file is not applied again over what the person did in the app since:
        /// - the kind keeps the fingerprint of that file, and the invoice is not held for it;
        /// - or, for the rows, the invoice is held for them all the same, under the marker of the taken row
        ///   (`ImportPlanner.fingerprint(ofTakenRow:)`): when the hold displaces a flag of the invoice's own that only
        ///   the row brings back, such as "zrušeno ve Fakturoidu", or when the invoice is held for its rows already, so
        ///   that a hold never drops a kind (an invoice held the old way, with the flag and under its own row, is held
        ///   for its rows). While the hold lasts, an import that ends it applies the row again; once the person has
        ///   resolved it, the same row is unchanged.
        ///
        /// A kind the group has none of keeps its fingerprint, unless the invoice is held for its rows all the same, as
        /// above: the rows are then stored under the marker of the row the invoice has taken, or keep the fingerprint
        /// of a set they are held under already. Rows this hold does not hold keep no marker: one that a hold the
        /// person has resolved left goes back to the fingerprint of its row (`released(_:)`), so that the rows are not
        /// held again by a hold for the ISDOC invoices alone. The fingerprint of the rows goes with the Fakturoid id of
        /// the first row (or the one the invoice has), and an imported invoice is not marked as changed in the app any
        /// more.
        private func heldForDifferingFiles(_ invoice: Invoice, of group: Group, isNew: Bool) -> Invoice {
            var held = invoice
            held.review = ReviewFlag(reason: ImportPlanner.differingRowsReason)
            let already = isNew ? nil : Self.heldKinds(of: invoice)
            let displacesFlag = !isNew && invoice.review != nil && already == nil
            let holdingRows = displacesFlag || already?.rows == true
            let takenRow = isNew ? nil : Self.takenRow(of: invoice)
            let rowPrints = group.rowOffsets.map { rows[$0].fingerprint }
            let isdocPrints = group.isdocOffsets.map { isdocs[$0].fingerprint }
            if !rowPrints.isEmpty {
                let rowID = group.rowOffsets.first.map { rows[$0].fakturoidID } ?? ""
                var rowPrint = Self.heldFingerprint(of: rowPrints, taken: takenRow)
                if holdingRows, let takenRow, rowPrint == takenRow {
                    rowPrint = ImportPlanner.fingerprint(ofTakenRow: takenRow)
                }
                held.source = .imported(
                    fakturoidID: rowID.isEmpty ? Self.fakturoidID(of: invoice) : rowID, fingerprint: rowPrint,
                    changedInApp: false)
            } else if holdingRows, let stored = Self.rowFingerprint(of: invoice) {
                let rowPrint = takenRow.map { ImportPlanner.fingerprint(ofTakenRow: $0) } ?? stored
                held.source = .imported(
                    fakturoidID: Self.fakturoidID(of: invoice), fingerprint: rowPrint, changedInApp: false)
            } else if case .imported = invoice.source {
                held.source = Self.released(invoice.source)
            }
            if !isdocPrints.isEmpty {
                let taken = invoice.isdocFingerprint.flatMap { ImportPlanner.takenFingerprint($0) }
                held.isdocFingerprint = Self.heldFingerprint(of: isdocPrints, taken: taken)
            }
            return held
        }

        /// The fingerprint an invoice held for files of one kind, with the fingerprints `prints`, is stored under for
        /// that kind: the fingerprint of those files when they are all alike and it is `taken`, the fingerprint of the
        /// file of that kind the invoice has taken (nil when it has taken none), and otherwise the fingerprint of their
        /// set (`ImportPlanner.fingerprint(ofAll:)`).
        private static func heldFingerprint(of prints: [String], taken: String?) -> String {
            if let single = alike(prints), single == taken {
                return single
            }
            return ImportPlanner.fingerprint(ofAll: prints)
        }

        /// Whether `invoice` is stored under the files of `group` the way `heldForDifferingFiles(_:of:isNew:)` stores
        /// an invoice held for them, so that they bring nothing new: for each kind of file the group has, the invoice's
        /// fingerprint of that kind (of its CSV row, or `isdocFingerprint`) is the fingerprint of the set of those
        /// files, or, when they are all alike, the fingerprint of that one file or the marker of it as a taken row. An
        /// invoice that has never been held for these files is not stored so, since a kind whose files differ has only
        /// the fingerprint of their set.
        private func isStored(_ invoice: Invoice, underTheFilesOf group: Group) -> Bool {
            let rowPrints = group.rowOffsets.map { rows[$0].fingerprint }
            let isdocPrints = group.isdocOffsets.map { isdocs[$0].fingerprint }
            if !rowPrints.isEmpty && !Self.isHeld(Self.rowFingerprint(of: invoice), for: rowPrints) {
                return false
            }
            if !isdocPrints.isEmpty && !Self.isHeld(invoice.isdocFingerprint, for: isdocPrints) {
                return false
            }
            return true
        }

        /// Whether `stored`, an invoice's fingerprint of one kind of file, is one that an invoice held for files of
        /// that kind, with the fingerprints `prints`, is stored under: the fingerprint of their set, or, when they are
        /// all alike, a fingerprint whose taken file is theirs (`ImportPlanner.takenFingerprint(_:)`).
        private static func isHeld(_ stored: String?, for prints: [String]) -> Bool {
            guard let stored else { return false }
            if stored == ImportPlanner.fingerprint(ofAll: prints) {
                return true
            }
            guard let single = alike(prints) else { return false }
            return ImportPlanner.takenFingerprint(stored) == single
        }

        /// The fingerprint of `prints` when they are all alike, or nil when they differ or there are none.
        private static func alike(_ prints: [String]) -> String? {
            let distinct = Set(prints)
            return distinct.count == 1 ? distinct.first : nil
        }

        /// The fingerprint `invoice` is stored under for its CSV row, or nil when no row has been imported for it, such
        /// as an invoice made in the app or one known only from an ISDOC file. It may hold the invoice for its rows
        /// (`ImportPlanner.isHoldingFingerprint(_:)`).
        private static func rowFingerprint(of invoice: Invoice) -> String? {
            guard case .imported(_, let fingerprint, _) = invoice.source, !fingerprint.isEmpty else { return nil }
            return fingerprint
        }

        /// The fingerprint of the CSV row `invoice` has taken: the one it was last imported from, also when it is held
        /// for its rows under the marker of that row (`ImportPlanner.fingerprint(ofTakenRow:)`). It is nil when the
        /// invoice has taken no row: none has been imported for it, or it is stored under the fingerprint of a set of
        /// rows.
        private static func takenRow(of invoice: Invoice) -> String? {
            rowFingerprint(of: invoice).flatMap { ImportPlanner.takenFingerprint($0) }
        }

        /// Whether `invoice` was imported from the invoice with the Fakturoid id `id`.
        private func isInvoice(_ invoice: Invoice, ofFakturoidID id: String) -> Bool {
            guard case .imported(let importedID, _, _) = invoice.source else { return false }
            return !id.isEmpty && importedID == id
        }

        /// Whether the Fakturoid ids `stored` and `row` say they are two invoices: both are known, and they differ. An
        /// id that is missing tells nothing, and the digits of the number decide then.
        private static func areOtherFakturoidInvoices(_ stored: String, _ row: String) -> Bool {
            !stored.isEmpty && !row.isEmpty && stored != row
        }

        /// A source that cannot be added: the number, why, and what became of it.
        private mutating func addConflict(_ label: String, _ reason: String) {
            plan.conflicts.append("\(label) — \(reason) — nepřidáno")
            plan.notAdded.append(ImportNotAddedItem(number: label, reason: reason))
        }

        /// A source that is skipped: the number, why, and the document it is (nil when that cannot be told).
        private mutating func skip(_ label: String, _ reason: String, key: DocumentKey?) {
            skips.append(Skip(label: label, reason: reason, key: key))
        }

        /// The document a source with `number` in `currency` is, a proforma invoice or not, or nil when the number has
        /// no digit or the currency is no code.
        private static func key(number: String, currency: CurrencyCode?, proforma: Bool) -> DocumentKey? {
            let digits = InvoiceNumbering.digits(of: number)
            guard !digits.isEmpty, let currency else { return nil }
            return DocumentKey(digits: digits, currency: currency, proforma: proforma)
        }

        /// Puts the skipped sources in the plan in the order they were met, each document once: a source is left out
        /// when its document is counted already, by a group or by a source skipped before it. A proforma invoice in
        /// both exports is one line, and the ISDOC file of a credit note whose row is added is none.
        private mutating func finishSkips() {
            var counted = countedInvoices
            for skip in skips {
                if let key = skip.key, !counted.insert(key).inserted {
                    continue
                }
                plan.skipped.append("\(skip.label) — \(skip.reason)")
                plan.skippedNumbers.append(skip.label)
            }
        }

        /// Puts `invoice` of `group` in the plan, to add or to update, with its notes, its line of review, and the note
        /// on a country of its row that is no code.
        private mutating func add(
            _ invoice: Invoice, notes: [String], of group: Group, label: String, as addition: Addition
        ) {
            switch addition {
            case .insert:
                plan.inserts.append(invoice)
                plan.newNumbers.append(label)
                addedDigits.insert(invoice.numberDigits)
            case .update:
                plan.updates.append(invoice)
                plan.overwrittenNumbers.append(label)
            }
            entryOfInvoice[invoice.numberDigits] = entry(of: group)
            plan.notes += notes
            if let review = invoice.review {
                plan.reviewItems.append(reviewLine(label, review.reason))
            }
            if let offset = group.rowOffsets.first {
                noteCountry(of: rows[offset])
            }
        }

        /// Notes the country of `row` once when it is neither a code nor a name the import knows: it is kept as it is
        /// written. The note does not hold the invoice, so it is one of `notes`, not a line to check.
        private mutating func noteCountry(of row: FakturoidRow) {
            guard case .unknown(let text) = ImportPlanner.country(row.clientCountry) else { return }
            if notedCountries.insert(text).inserted {
                plan.notes.append("země „\(text)“ — není kód země, ponecháno jak je")
            }
        }

        // MARK: Cancelled invoices

        /// An invoice with a row that is cancelled in Fakturoid, which wins over the other rows and the ISDOC invoices
        /// of the group: none of them is applied. An invoice that is there, imported or made in the app, is held for
        /// review with all it has, and is not marked as changed in the app any more. The row the invoice has taken
        /// (`takenRow(of:)`) leaves it as it is, unless a hold still holds the invoice for its rows (`heldKinds(of:)`):
        /// the cancelled row ends that hold and holds the invoice as cancelled again. Without such an invoice the row
        /// is skipped, and the row of another invoice of Fakturoid whose number has the same digits is a conflict,
        /// which leaves the stored invoice as it is.
        private mutating func visitCancelled(_ group: Group, row: FakturoidRow) {
            let label = Self.label(row.number)
            guard let existing = existingByDigits[group.digits], existing.currency == group.currency,
                !group.digits.isEmpty || isInvoice(existing, ofFakturoidID: row.fakturoidID)
            else {
                let key =
                    group.digits.isEmpty
                    ? nil : DocumentKey(digits: group.digits, currency: group.currency, proforma: false)
                skip(label, ImportPlanner.cancelledReason, key: key)
                return
            }
            let storedID = Self.fakturoidID(of: existing)
            guard !Self.areOtherFakturoidInvoices(storedID, row.fakturoidID) else {
                addConflict(label, Self.anotherFakturoidInvoice)
                return
            }
            if Self.heldKinds(of: existing)?.rows != true && Self.takenRow(of: existing) == row.fingerprint {
                plan.unchangedNumbers.append(label)
                return
            }
            var flagged = existing
            flagged.review = ReviewFlag(reason: ImportPlanner.cancelledReason)
            flagged.source = .imported(
                fakturoidID: row.fakturoidID.isEmpty ? storedID : row.fakturoidID, fingerprint: row.fingerprint,
                changedInApp: false)
            plan.flaggedCancelled.append(flagged)
            plan.overwrittenNumbers.append(label)
            plan.reviewItems.append("\(label) — \(ImportPlanner.cancelledReason)")
        }
    }
}
