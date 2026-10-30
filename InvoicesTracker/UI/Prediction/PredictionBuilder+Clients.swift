import Foundation

/// The rows of the clients and the twelve cells of each: how a client invoices and pays, what it still adds to the
/// year, what else is worth saying of it, and in each month what was invoiced or is expected.
nonisolated extension PredictionBuilder {
    /// The row of `client` in the prediction of its year.
    static func clientRow(_ client: ClientPrediction, in prediction: IncomePrediction) -> PredictionClientRow {
        let isClosed = prediction.isClosed
        // A client adds what it still brings, and in a year that is over shows what it brought.
        let hasUnknownAdds = client.hasUnknownCurrentYearAmount
        let adds =
            isClosed
            ? kc(ofHalere: client.receivedHalere)
            : (client.addsHalere != 0 ? "+\u{00A0}" + kc(ofHalere: client.addsHalere) : "letos už nic")
        let isMuted = client.addsHalere == 0 && !(isClosed && client.receivedHalere != 0)
        return PredictionClientRow(
            id: client.id, name: client.name, how: how(of: client, in: prediction),
            adds: hasUnknownAdds ? "—" : adds, addsIsMuted: hasUnknownAdds ? false : isMuted,
            note: note(of: client, in: prediction), isEdited: client.isEdited,
            cells: client.months.map { cell($0, of: client, in: prediction) })
    }

    // MARK: How the client invoices

    /// How the client invoices and pays. In a year that is over: the rhythm and the days it takes to pay, or that it
    /// had a single invoice or none. Otherwise by what is known of it: a regular client by its rhythm and the likely
    /// amount of the next invoice, one with a single invoice, one with several that is not regular, and one without
    /// invoices.
    private static func how(of client: ClientPrediction, in prediction: IncomePrediction) -> String {
        let pays = "platí za ~" + ComputationBuilder.counted(client.delayDays, "den", "dny", "dní")
        if prediction.isClosed {
            guard client.hasInvoiceInYear else { return "v roce \(prediction.year) bez faktur" }
            let isInvoicedRegularly = client.isRegular || client.issuedCount > 1
            return isInvoicedRegularly ? "\(rhythm(step: client.step)) · \(pays)" : "jedna faktura"
        }
        let amount = client.nextAmountHalere == nil
            ? "—" : estimate(amountText(of: client), isClosed: false)
        if client.isRegular {
            return "\(rhythm(step: client.step)) \(amount) · \(pays)"
        }
        let last = client.lastIssued.map(CzechFormat.date) ?? "—"
        switch client.issuedCount {
        case 0:
            return "zatím bez faktur" + (client.nextAmountFromTemplate ? " · částka ze šablony \(amount)" : "")
        case 1:
            let more = client.months.contains(where: \.isOn) ? "počítám s dalšími" : "další zatím nečekám"
            return "zatím jedna faktura (\(last)) \(amount) · \(more)"
        default:
            return "poslední faktura \(last)"
        }
    }

    /// How often the client invoices: "měsíčně", "každé dva měsíce", "čtvrtletně", "každé 4 měsíce", and from five
    /// months on "každých 5 měsíců".
    private static func rhythm(step: Int) -> String {
        switch step {
        case 1: "měsíčně"
        case 2: "každé dva měsíce"
        case 3: "čtvrtletně"
        case 4: "každé 4\u{00A0}měsíce"
        default: "každých \(step)\u{00A0}měsíců"
        }
    }

    /// The available estimate of the next invoice in whole crowns, or a dash when unavailable.
    private static func amountText(of client: ClientPrediction) -> String {
        guard let amount = client.nextAmountHalere else { return "—" }
        return kc(ofHalere: amount)
    }

    // MARK: The note

    /// What else is worth saying of the client, in this order: what it has paid this year, what of last year's invoices
    /// is to be paid, what is paid only next year, that an amount cannot be told, and that the person changed the
    /// months. Nil when there is none of it.
    private static func note(of client: ClientPrediction, in prediction: IncomePrediction) -> String? {
        var parts: [String] = []
        if client.receivedHalere != 0 && !prediction.isClosed {
            parts.append("letos přišlo " + kc(ofHalere: client.receivedHalere))
        }
        if client.previousYearWaitingHalere != 0 {
            parts.append(
                "čeká " + kc(ofHalere: client.previousYearWaitingHalere)
                    + " za faktury z roku \(prediction.year - 1)")
        }
        if client.hasUnknownCurrentYearAmount {
            let known = client.addsHalere != 0 ? " · známá část " + kc(ofHalere: client.addsHalere) : ""
            parts.append("částka příjmů letos není úplná – chybí kurz nebo podklady pro odhad" + known)
        }
        if client.hasUnknownNextYearAmount {
            parts.append("částka příjmů v roce \(prediction.year + 1) není úplná – chybí kurz nebo podklady pro odhad")
        }
        if client.nextYearHalere != 0 {
            parts.append(
                estimate(kc(ofHalere: client.nextYearHalere), isClosed: prediction.isClosed)
                    + " přijde až v roce \(prediction.year + 1)")
        }
        if client.averageSampleCount > 0 && client.nextAmountHalere == nil {
            parts.append("průměr není dostupný – chybí kurz ČNB některé faktury")
        }
        if client.months.contains(where: \.isOn) && client.nextAmountHalere == nil && client.averageSampleCount == 0 {
            if client.nextAmountFromTemplate {
                parts.append("částka ze šablony není dostupná – chybí kurz pro přepočet měny šablony")
            } else {
                parts.append("bez faktur a šablony neumím odhadnout částku – přidejte šablonu faktury")
            }
        }
        if client.isEdited {
            parts.append("měsíce upravené ručně")
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    // MARK: The cells

    /// The cell of `month` of `client`: invoices that are issued, a month that is over, or an invoice that is expected
    /// or not.
    private static func cell(
        _ month: PredictionMonth, of client: ClientPrediction, in prediction: IncomePrediction
    ) -> PredictionCell {
        let name = BuilderText.capitalized(CzechFormat.monthNames[month.month - 1])
        let nextYear = "→\u{00A0}\(prediction.year + 1)"
        var cell = PredictionCell(
            month: month.month, label: CzechFormat.monthShort[month.month - 1], value: "", sub: "", kind: .past,
            isToggle: month.kind.isOpen && client.allowsChoices, isOn: month.kind.isOpen && month.isOn,
            accessibilityLabel: "")
        switch month.kind {
        case .paid, .waiting, .waitingNextYear:
            // The invoices of the month, with what they bring: the payments received and the amounts that wait. An
            // amount that is not known is a "?", and VoiceOver leaves it out.
            let isPaid = month.kind == .paid
            cell.value = month.hasUnknownAmount ? "?" : shortAmount(ofHalere: month.amountHalere)
            cell.sub = isPaid ? "zaplaceno" : (month.kind == .waiting ? "čeká" : nextYear)
            cell.kind = isPaid ? .paid : .waiting
            let amount = month.hasUnknownAmount ? "" : ", " + kc(ofHalere: month.amountHalere)
            cell.accessibilityLabel =
                "\(name): \(invoices(month.invoiceNumbers))\(amount), " + (isPaid ? "zaplaceno" : "čeká na platbu")
        case .past:
            cell.value = "—"
            cell.kind = .past
            cell.accessibilityLabel = "\(name): žádná faktura"
        case .expected, .expectedNextYear:
            // Unknown metadata distinguishes an unavailable amount from a valid zero.
            let hasAmount = !month.hasUnknownAmount
            let isNextYear = month.kind == .expectedNextYear
            cell.value = hasAmount ? estimate(shortAmount(ofHalere: month.amountHalere), isClosed: false) : "—"
            cell.sub = isNextYear ? nextYear : (month.isFromDraft ? "koncept" : (hasAmount ? "čekám" : "bez částky"))
            cell.kind = month.kind == .expected ? .expected : .expectedNextYear
            cell.accessibilityLabel =
                "\(name): čekám fakturu"
                + (hasAmount ? " asi " + kc(ofHalere: month.amountHalere) : ", částka není známá")
                + (isNextYear ? ", zaplatí se až v roce \(prediction.year + 1)" : "") + draft(of: month)
        case .notExpected:
            cell.sub = "nečekám"
            cell.kind = .notExpected
            cell.accessibilityLabel = "\(name): fakturu nečekám" + draft(of: month)
        }
        return cell
    }

    /// The amount in a cell: thousands from 10 000 Kč ("289 tis."), otherwise whole crowns ("4 500").
    private static func shortAmount(ofHalere halere: Int64) -> String {
        let crowns = wholeCrowns(ofHalere: halere)
        guard crowns >= 10_000 else { return CzechFormat.grouped(crowns) }
        return CzechFormat.grouped(DecimalMath.halfUp(Decimal(crowns) / 1_000)) + "\u{00A0}tis."
    }

    /// The invoices of a month as VoiceOver says them: "faktura 20260601" for one, "2 faktury" up to four, and
    /// "5 faktur" from five.
    private static func invoices(_ numbers: [String]) -> String {
        switch numbers.count {
        case 1: "faktura \(numbers[0])"
        case 2...4: "\(numbers.count) faktury"
        default: "\(numbers.count) faktur"
        }
    }

    /// " (koncept 20261001)" for a month that has a draft, the first one when it has several.
    private static func draft(of month: PredictionMonth) -> String {
        guard month.isFromDraft, let number = month.invoiceNumbers.first else { return "" }
        return " (koncept \(number))"
    }
}
