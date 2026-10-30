import Foundation
@testable import InvoicesTracker

/// Inserts a row into a table of the schema with every required column set, for tests of the schema itself (keys,
/// checks, cascades) that must not depend on a repository. The values are invented.
enum SchemaRows {
    /// With `id` nil the database picks the id.
    static func client(_ c: SQLiteConnection, id: Int64?) throws {
        try c.run(
            """
            INSERT INTO client(
                id, name, street, postcode, city, country, ico, dic, email, phone, currency, vat_mode, due_days,
                payment_method, language, origin, edited_after_import)
            VALUES (
                ?, 'Alfa Systems s.r.o.', 'Hlavní 1', '261 01', 'Příbram', 'CZ', '12345678', 'CZ12345678',
                'alfa@example.com', '', 'CZK', 'domestic21', 14, 'Převodem', 'cs', 'app', 0)
            """,
            [id.map { SQLValue.integer($0) } ?? .null]
        )
    }

    /// An issued CZK invoice. `digits` is both its number and the digits the number is unique by. With `id` nil the
    /// database picks the id.
    static func invoice(_ c: SQLiteConnection, id: Int64?, digits: String, clientID: Int64? = nil) throws {
        try c.run(
            """
            INSERT INTO invoice(
                id, number, number_digits, client_id,
                client_name, client_street, client_postcode, client_city, client_country, client_ico, client_dic,
                client_email, currency, issue_date, duzp, due_date, vat_mode,
                rate_currency, rate_amount, rate_value, rate_declared_on,
                qr_enabled, note, language, payment_method, status, review_reason,
                fakturoid_id, import_fingerprint, changed_in_app, net_minor, vat_minor, total_minor)
            VALUES (
                ?, ?, ?, ?,
                'Alfa Systems s.r.o.', 'Hlavní 1', '261 01', 'Příbram', 'CZ', '12345678', 'CZ12345678',
                'alfa@example.com', 'CZK', '2026-09-30', '2026-09-30', '2026-10-14', 'domestic21',
                NULL, NULL, NULL, NULL,
                1, '', 'cs', 'Převodem', 'issued', NULL,
                NULL, NULL, 0, 450000, 94500, 544500)
            """,
            [
                id.map { SQLValue.integer($0) } ?? .null, .text(digits), .text(digits),
                clientID.map { SQLValue.integer($0) } ?? .null,
            ]
        )
    }

    static func invoiceItem(_ c: SQLiteConnection, invoiceID: Int64) throws {
        try c.run(
            """
            INSERT INTO invoice_item(invoice_id, position, description, quantity, unit, unit_price_minor)
            VALUES (?, 0, 'Vývoj', '7.5', 'hod', 60000)
            """,
            [.integer(invoiceID)]
        )
    }

    static func payment(_ c: SQLiteConnection, invoiceID: Int64) throws {
        try c.run(
            """
            INSERT INTO payment(
                invoice_id, date, conversion, czk_net_halere, czk_vat_halere,
                rate_currency, rate_amount, rate_value, rate_declared_on, provisional, bank_czk_total_halere)
            VALUES (?, '2026-10-15', 'czk', 450000, 94500, NULL, NULL, NULL, NULL, 0, NULL)
            """,
            [.integer(invoiceID)]
        )
    }

    /// A template with one item.
    static func template(_ c: SQLiteConnection, id: Int64, clientID: Int64) throws {
        try c.run(
            """
            INSERT INTO template(id, name, client_id, vat_mode, due_days, duzp_at_month_end, note)
            VALUES (?, 'Měsíční vývoj', ?, 'domestic21', 14, 1, '')
            """,
            [.integer(id), .integer(clientID)]
        )
        try c.run(
            """
            INSERT INTO template_item(template_id, position, description, quantity, unit, unit_price_minor)
            VALUES (?, 0, 'Vývoj {měsíc} {rok}', '7.5', 'hod', 60000)
            """,
            [.integer(id)]
        )
    }

    static func yearSettings(
        _ c: SQLiteConnection,
        year: Int64,
        expensePercent: Int64 = 60,
        activityFrom: Int64 = 1,
        activityTo: Int64 = 12
    ) throws {
        try c.run(
            """
            INSERT INTO year_settings(
                year, expense_percent, reduced_social_base, activity_from, activity_to, secondary_months,
                health_exempt_months, taxpayer_credit, income_fx_method)
            VALUES (?, ?, 0, ?, ?, '', '', 1, 'cnbDaily')
            """,
            [.integer(year), .integer(expensePercent), .integer(activityFrom), .integer(activityTo)]
        )
    }

    /// The same row for a database of version 1 or 2, whose `year_settings` still has the column `minimum_mode`, which
    /// is NOT NULL and has no default until version 3 drops it; `mode` is what the column holds. For the tests that
    /// fill a database of an earlier version before it is migrated.
    static func yearSettingsBeforeVersionThree(
        _ c: SQLiteConnection,
        year: Int64,
        expensePercent: Int64 = 60,
        activityFrom: Int64 = 1,
        mode: String = "monthsToDate"
    ) throws {
        try c.run(
            """
            INSERT INTO year_settings(
                year, expense_percent, reduced_social_base, activity_from, activity_to, secondary_months,
                health_exempt_months, taxpayer_credit, minimum_mode, income_fx_method)
            VALUES (?, ?, 0, ?, 12, '', '', 1, ?, 'cnbDaily')
            """,
            [.integer(year), .integer(expensePercent), .integer(activityFrom), .text(mode)]
        )
    }

    static func advanceMonth(
        _ c: SQLiteConnection,
        year: Int64,
        month: Int64 = 1,
        social: Int64 = 3852,
        health: Int64 = 2968,
        tax: Int64 = 0
    ) throws {
        try c.run(
            "INSERT INTO advance_month(year, month, social, health, tax) VALUES (?, ?, ?, ?, ?)",
            [.integer(year), .integer(month), .integer(social), .integer(health), .integer(tax)]
        )
    }

    static func deduction(
        _ c: SQLiteConnection,
        year: Int64,
        mortgageInterestPaid: Int64 = 0,
        mortgageMonths: Int64 = 12
    ) throws {
        try c.run(
            """
            INSERT INTO deduction(
                year, mortgage_interest_paid, mortgage_months, mortgage_cap, life_insurance, pension_savings, dip,
                long_term_care, gifts)
            VALUES (?, ?, ?, 'after2021', 0, 0, 0, 0, 0)
            """,
            [.integer(year), .integer(mortgageInterestPaid), .integer(mortgageMonths)]
        )
    }

    static func cnbRate(
        _ c: SQLiteConnection,
        declaredOn day: String,
        currency: String,
        amount: Int64 = 1,
        rate: String = "21.622"
    ) throws {
        try c.run(
            "INSERT INTO cnb_rate(declared_on, currency, amount, rate) VALUES (?, ?, ?, ?)",
            [.text(day), .text(currency), .integer(amount), .text(rate)]
        )
    }

    /// A child born on `birthDate`. With `id` nil the database picks the id.
    static func child(_ c: SQLiteConnection, id: Int64?, birthDate: String = "2019-09-03") throws {
        try c.run(
            "INSERT INTO child(id, name, birth_date) VALUES (?, 'Anna', ?)",
            [id.map { SQLValue.integer($0) } ?? .null, .text(birthDate)]
        )
    }

    /// What `year` says about the child with `childID`: in the household the whole year, claimed by me, the first
    /// child, with no ZTP/P and no studies, unless the arguments say otherwise. A range of months is its first and its
    /// last month, both nil for none.
    static func childYear(
        _ c: SQLiteConnection,
        childID: Int64,
        year: Int64,
        householdFrom: Int64? = 1,
        householdTo: Int64? = 12,
        order: Int64 = 1,
        ztppFrom: Int64? = nil,
        ztppTo: Int64? = nil,
        studiesFrom: Int64? = nil,
        studiesTo: Int64? = nil
    ) throws {
        try c.run(
            """
            INSERT INTO child_year(
                child_id, year, household_from, household_to, claimant, child_order, ztpp_from, ztpp_to,
                studies_from, studies_to)
            VALUES (?, ?, ?, ?, 'me', ?, ?, ?, ?, ?)
            """,
            [
                .integer(childID), .integer(year), number(householdFrom), number(householdTo), .integer(order),
                number(ztppFrom), number(ztppTo), number(studiesFrom), number(studiesTo),
            ]
        )
    }

    /// Gives the stored year `year` a spouse: claimed, married and in the household the whole year, with no own income
    /// and no ZTP/P, unless the arguments say otherwise. All nil is a year without a spouse.
    static func spouse(
        _ c: SQLiteConnection,
        year: Int64,
        claim: Int64? = 1,
        from: Int64? = 1,
        to: Int64? = 12,
        ownIncome: Int64? = 0,
        ztppFrom: Int64? = nil,
        ztppTo: Int64? = nil
    ) throws {
        try c.run(
            """
            UPDATE year_settings SET
                spouse_claim = ?, spouse_from = ?, spouse_to = ?, spouse_own_income = ?, spouse_ztpp_from = ?,
                spouse_ztpp_to = ?
            WHERE year = ?
            """,
            [
                number(claim), number(from), number(to), number(ownIncome), number(ztppFrom), number(ztppTo),
                .integer(year),
            ]
        )
    }

    private static func number(_ value: Int64?) -> SQLValue {
        value.map { SQLValue.integer($0) } ?? .null
    }
}
