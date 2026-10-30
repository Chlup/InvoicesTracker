import Foundation

/// The payment of an invoice that was paid, worked out again when the invoice is edited, and what the change does to
/// the levies; and for an invoice that is not paid what its payment would add.
extension InvoiceEditorModel {
    /// The payment of an invoice that was paid, worked out again for the invoice as it would be saved, and what the
    /// change does to the levies; or, for an invoice that is not paid, what its payment would add, as far as its due
    /// date is the one typed (`estimating`).
    func finishPayment(
        of invoice: inout Invoice, estimating: Bool, into computed: inout Computed
    ) async {
        guard let database = app?.database else { return }
        if let old = editing?.payment {
            do {
                switch try await paymentAfterEdit(of: invoice, from: old, in: database) {
                case .payment(let new):
                    invoice.payment = new
                    computed.impact = await change(from: old, to: new)
                case .cannotConvert:
                    computed.problems.append(EditorProblem(text: EditorText.paymentNotConvertible, blocksDraft: true))
                }
            } catch {
                AppModel.log("Working out the payment of an edited invoice", failedWith: error)
                computed.problems.append(EditorProblem(text: EditorText.notPrepared, blocksDraft: true))
            }
        } else if estimating {
            computed.impact = await estimate(for: invoice)
        }
    }

    private enum PaymentOutcome {
        case payment(Payment)

        /// The payment cannot be worked out for another currency: no rate is known for the day.
        case cannotConvert
    }

    /// The payment `old`, worked out again for `updated`, the invoice as it would be saved.
    ///
    /// It is applied again, with the method and the rate it has, when it has them to apply: a payment in crowns, a
    /// payment of an amount the bank credited (the amount stays and is shared between the base and the VAT again), and
    /// a payment converted at a rate that was declared. A payment that still waits for its rate is converted afresh
    /// with the rate known now, as is any payment of an invoice whose currency changed: the old rate does not belong
    /// to a new currency. Afresh is by the method the year of the payment uses (`YearFXState.effective`); the save
    /// converts the year again when the new currency changes that (`AppModel.recomputePaymentsAfterChanges(inYears:)`).
    private func paymentAfterEdit(
        of updated: Invoice, from old: Payment, in database: Database
    ) async throws -> PaymentOutcome {
        let sameCurrency = editing?.currency == updated.currency
        let canApplyAgain =
            switch old.conversion {
            case .bankCZK: true
            case .czk: sameCurrency
            case .cnbDaily, .uniform: sameCurrency && old.rate != nil && !old.provisional
            }
        if canApplyAgain {
            return .payment(PaymentConverter.reapply(old, to: updated))
        }
        let method = try await database.effectiveFXMethod(year: old.date.year)
        guard let app else { throw VaultError.locked }
        let converted = try await app.convert(updated, paidOn: old.date, method: method, in: database)
        if AppModel.isWorthNothing(converted) {
            // No rate is known for the day. The rate the payment has stands for the same currency, and nothing does
            // for another.
            return sameCurrency ? .payment(PaymentConverter.reapply(old, to: updated)) : .cannotConvert
        }
        return .payment(converted)
    }

    /// What the change of the payment of the invoice that is edited does to the levies of its year, when the invoice
    /// counts as income; nil otherwise, and where that cannot be worked out (stored values the computation does not
    /// take). The invoice can be saved without it.
    private func change(from old: Payment, to new: Payment) async -> EditorLevyImpact.Sentences? {
        guard let app, let editing, InvoiceDetailBuilder.countsAsIncome(editing) else { return nil }
        do {
            return try await EditorLevyImpact.change(app: app, invoiceID: editing.id, from: old, to: new)
        } catch {
            AppModel.log("Working out what a changed payment does to the levies", failedWith: error)
            return nil
        }
    }

    /// What the payment of the invoice would add to the levies of the year of its due date, when it arrives on that
    /// day; nil where that cannot be worked out (a foreign currency without a rate, or stored values the computation
    /// does not take).
    private func estimate(for invoice: Invoice) async -> EditorLevyImpact.Sentences? {
        guard let app else { return nil }
        let net: Int64
        let vat: Int64
        if invoice.currency.isCZK {
            net = invoice.netMinor
            vat = invoice.vatMinor
        } else {
            guard let rate = invoice.invoiceRate else { return nil }
            net = rate.rate.czkHalere(fromMinor: invoice.netMinor)
            vat = rate.rate.czkHalere(fromMinor: invoice.vatMinor)
        }
        do {
            return try await EditorLevyImpact.estimate(
                app: app, invoiceID: editing?.id, dueDate: invoice.dueDate, netHalere: net, vatHalere: vat)
        } catch {
            AppModel.log("Working out what a payment would add to the levies", failedWith: error)
            return nil
        }
    }
}
