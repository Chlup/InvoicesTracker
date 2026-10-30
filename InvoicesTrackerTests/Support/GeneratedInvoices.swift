import Foundation
@testable import InvoicesTracker

extension Database {
    /// Test support: inserts `perYear` invoices for each of `years` in one transaction, without the repository, with
    /// plain SQL, so a timed test does not depend on the writer it measures. No invoice gets a search document: a test
    /// that searches calls `rebuildAllSearchDocuments()` afterwards.
    ///
    /// Invoice `k` of a year is issued in month `k % 12 + 1`, numbered `YYYYMMNN` (`NN` is `k / 12 + 1`), on a day
    /// that grows with `NN` from the 1st to the 28th, as numbers do in a month. It is in crowns, dollars or euros by
    /// `NN`, and for one of four clients, also by `NN`: Acme, Alfa, Beta and Gama. Each has two items (4 600,00 in its
    /// currency) and 21 % VAT (966,00). A foreign invoice has the rate of its issue day fixed on it (21,5 or 24,3).
    /// Four of five are paid 12 days after the day of issue, so the December invoices issued from the 20th on are paid
    /// in January, and one in thirty-one of those payments is provisional. (The divisors are not factors of 12, so
    /// that paid and provisional invoices are spread over all months.)
    func insertGeneratedInvoices(years: ClosedRange<Int>, perYear: Int) throws {
        let count = years.count * perYear
        // The invoices of the busiest month, which the day of issue is spread over.
        let busiestMonth = max(1, (perYear + 11) / 12)
        let numberText = "printf('%04d%02d%02d', year, month, sequence)"
        let dayText = "printf('%04d-%02d-%02d', year, month, day)"
        try write { connection in
            try connection.run(
                """
                WITH RECURSIVE n(i) AS (SELECT 0 UNION ALL SELECT i + 1 FROM n WHERE i < \(count - 1)),
                clients(k, name, street, postcode, city, country, ico, dic, email) AS (VALUES
                    (0, 'Acme Industries s.r.o.', 'Průmyslová 5', '301 00', 'Plzeň', 'CZ', '10000001', 'CZ10000001',
                     'fakturace@acme.example'),
                    (1, 'Alfa Systems s.r.o.', 'Hlavní 1', '261 01', 'Příbram', 'CZ', '12345678', 'CZ12345678',
                     'ucetni@alfa.example'),
                    (2, 'Beta Software, Inc.', '500 Main Street', '78701', 'Austin, TX', 'US', '', '',
                     'billing@beta.example'),
                    (3, 'Gama Consulting GmbH', 'Hauptstraße 7', '10115', 'Berlin', 'DE', '', 'DE123456789',
                     'rechnung@gama.example')),
                slots(i, year, month, sequence, day, currency, client) AS (
                    SELECT i, \(years.lowerBound) + i / \(perYear), (i % \(perYear)) % 12 + 1,
                           (i % \(perYear)) / 12 + 1,
                           1 + (((i % \(perYear)) / 12) * 28) / \(busiestMonth),
                           CASE ((i % \(perYear)) / 12) % 3 WHEN 0 THEN 'CZK' WHEN 1 THEN 'USD' ELSE 'EUR' END,
                           ((i % \(perYear)) / 12 + 1) % 4
                    FROM n)
                INSERT INTO invoice(
                    id, number, number_digits, client_id,
                    client_name, client_street, client_postcode, client_city, client_country, client_ico, client_dic,
                    client_email, currency, issue_date, duzp, due_date, vat_mode,
                    rate_currency, rate_amount, rate_value, rate_declared_on,
                    qr_enabled, note, language, payment_method, status, review_reason,
                    fakturoid_id, import_fingerprint, changed_in_app, net_minor, vat_minor, total_minor)
                SELECT
                    i + 1, \(numberText), \(numberText), NULL,
                    clients.name, clients.street, clients.postcode, clients.city, clients.country, clients.ico,
                    clients.dic, clients.email, currency, \(dayText), \(dayText), date(\(dayText), '+14 days'),
                    'domestic21',
                    CASE currency WHEN 'CZK' THEN NULL ELSE currency END, CASE currency WHEN 'CZK' THEN NULL ELSE 1 END,
                    CASE currency WHEN 'CZK' THEN NULL WHEN 'USD' THEN '21.5' ELSE '24.3' END,
                    CASE currency WHEN 'CZK' THEN NULL ELSE \(dayText) END,
                    0, '', 'cs', 'Převodem', 'issued', NULL,
                    NULL, NULL, 0, 460000, 96600, 556600
                FROM slots JOIN clients ON clients.k = slots.client
                """
            )
            try connection.run(
                """
                INSERT INTO invoice_item(invoice_id, position, description, quantity, unit, unit_price_minor)
                SELECT id, 0, 'Vývoj', '7.5', 'hod', 60000 FROM invoice
                UNION ALL SELECT id, 1, 'Hosting', '1', 'ks', 10000 FROM invoice
                """
            )
            try connection.run(
                """
                INSERT INTO payment(
                    invoice_id, date, conversion, czk_net_halere, czk_vat_halere,
                    rate_currency, rate_amount, rate_value, rate_declared_on, provisional, bank_czk_total_halere)
                SELECT
                    id, date(issue_date, '+12 days'), CASE currency WHEN 'CZK' THEN 'czk' ELSE 'cnbDaily' END,
                    CASE currency WHEN 'CZK' THEN 460000 WHEN 'USD' THEN 11395000 ELSE 12879000 END,
                    CASE currency WHEN 'CZK' THEN 96600 WHEN 'USD' THEN 2392950 ELSE 2704590 END,
                    rate_currency, rate_amount, rate_value, rate_declared_on, id % 31 = 0, NULL
                FROM invoice WHERE id % 5 <> 0
                """
            )
        }
    }
}
