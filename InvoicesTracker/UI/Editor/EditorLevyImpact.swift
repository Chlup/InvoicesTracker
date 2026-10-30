import Foundation

/// What an invoice does to the levies of its year, in the words of the editor: the change that an edited payment makes,
/// and what the payment of an invoice that is not paid would add. Both are worked out with the engine through
/// `AppModel`, which checks the input first, never with `TaxEngine.compute` called on its own.
@MainActor
enum EditorLevyImpact {
    /// The heading with the amount, and the sentences under it.
    struct Sentences: Equatable, Sendable {
        var heading: String
        var detail: String
    }

    /// How the levies of the year of `old` change when the payment of the invoice `invoiceID` is `new` and not `old`:
    /// the levies of the whole year as of the day of the payment, once with each payment. The receipt of the payment
    /// stands for the stored one with the same source, so it is never counted twice. Nil when the stored receipts of
    /// the year hold no receipt of the invoice (it does not count as income).
    ///
    /// Throws `ComputationError.invalidYear` for stored values the computation does not take, and `VaultError.locked`.
    static func change(app: AppModel, invoiceID: Int64, from old: Payment, to new: Payment) async throws -> Sentences? {
        let day = old.date
        let input = try await app.yearInput(for: day.year).input
        guard input.receipts.contains(where: { $0.source == .invoice(invoiceID) }) else { return nil }
        let before = try AppModel.compute(input, asOf: day).liabilityTotal
        var changed = input
        changed.receipts.removeAll { $0.source == .invoice(invoiceID) }
        changed.receipts.append(
            Receipt(
                day: day, czkNetHalere: new.czkNetHalere, czkVatHalere: new.czkVatHalere, source: .invoice(invoiceID)))
        let after = try AppModel.compute(changed, asOf: day).liabilityTotal
        let delta = after - before
        let heading =
            "Po úpravě se odvody za rok \(day.year) změní o " + (delta > 0 ? "+" : "") + CzechFormat.wholeKc(delta)
        var detail =
            "Faktura je uhrazená \(CzechFormat.date(day)). Příjem z ní bude \(CzechFormat.halere(new.czkNetHalere))"
        detail +=
            new.czkNetHalere == old.czkNetHalere ? " jako dosud" : " místo \(CzechFormat.halere(old.czkNetHalere))"
        detail += old.conversion == .bankCZK ? " – částka v Kč podle banky se nemění." : "."
        return Sentences(heading: heading, detail: detail)
    }

    /// What the payment of an invoice that is not paid would add to the levies of the year of its due date, when the
    /// money arrives on that day: `netHalere` of income (and `vatHalere` of VAT) in crowns, and the thresholds of the
    /// year that income would reach. The receipt is the one of the invoice `invoiceID` when it is stored, otherwise a
    /// made-up one.
    ///
    /// Throws what `AppModel.effect(of:)` throws.
    static func estimate(
        app: AppModel, invoiceID: Int64?, dueDate: CivilDate, netHalere: Int64, vatHalere: Int64
    ) async throws -> Sentences {
        let receipt = Receipt(
            day: dueDate, czkNetHalere: netHalere, czkVatHalere: vatHalere,
            source: invoiceID.map { ReceiptSource.invoice($0) } ?? ReceiptSource.synthetic)
        let effect = try await app.effect(of: receipt)
        let heading =
            "Až přijde platba, přibude k odvodům za rok \(dueDate.year) zhruba "
            + CzechFormat.wholeKc(InvoiceDetailBuilder.roundedToHundreds(effect.total))
        let share = InvoiceDetailBuilder.share(of: effect, income: netHalere) ?? "0\u{00A0}%"
        var detail =
            "To je \(share) z příjmu bez DPH \(CzechFormat.halere(netHalere)), pokud zaplatí do splatnosti"
            + " \(CzechFormat.date(dueDate))."
        if let thresholds = InvoiceDetailBuilder.thresholdsText(of: effect) {
            detail += " " + thresholds
        }
        detail += " Když peníze dorazí až v dalším roce, patří příjem i odvody tam."
        return Sentences(heading: heading, detail: detail)
    }
}
