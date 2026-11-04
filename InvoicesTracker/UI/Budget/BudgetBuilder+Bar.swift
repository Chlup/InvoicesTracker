import Foundation

nonisolated extension BudgetBuilder {
    /// The split bar of the result card. In Faktura mode it starts with the DPH, where the invoice has some, and the
    /// three levies, which a group "Odvody" stands for in the legend; then come the four categories, each as wide as
    /// its amount. A remainder below zero has no width, and while there is nothing to divide no part has a width and
    /// the legend says "—".
    /// `invoice` and `figures` are those of the chosen invoice in Faktura mode.
    static func bar(division: Division, invoice: BudgetInvoice?, figures: InvoiceFigures?) -> SplitBarData {
        var segments: [SplitBarSegment] = []
        var groups: [SplitBarGroup] = []
        if let invoice, let figures {
            if figures.hasVAT {
                segments.append(SplitBarSegment(group: vatGroupID, tone: .vat, weight: figures.vatKc))
                groups.append(vatGroup(invoice, figures: figures))
            }
            for authority in Authority.allCases {
                let weight = max(0, figures.levy(of: authority))
                segments.append(SplitBarSegment(group: leviesGroupID, tone: .authority(authority), weight: weight))
            }
            groups.append(leviesGroup(figures))
        }
        for category in BudgetCategory.allCases {
            segments.append(
                SplitBarSegment(
                    group: category.rawValue, tone: .category(category),
                    weight: max(0, division.month?.amounts[category] ?? 0)))
            groups.append(categoryGroup(category, division: division))
        }
        let header = division.isInvoice ? "Kam peníze z faktury poslat" : "Rozdělení za měsíc"
        let parts = groups.map { $0.popover.title + " " + $0.value }
        return SplitBarData(
            header: header, segments: segments, groups: groups,
            accessibilityLabel: header + ": " + parts.joined(separator: ", "))
    }

    /// The id of the group of the DPH.
    private static let vatGroupID = "vat"

    /// The id of the group of the three levies.
    private static let leviesGroupID = "levies"

    /// The group of the DPH of `invoice`: its rate, its base and the DPH, and when it is filed and paid.
    private static func vatGroup(_ invoice: BudgetInvoice, figures: InvoiceFigures) -> SplitBarGroup {
        let popover = SplitBarPopover(
            title: "DPH", subtitle: "finanční úřad", tone: .vat,
            rows: [
                LevyPopoverRow(label: "Sazba", value: vatRate(of: invoice), style: .muted),
                LevyPopoverRow(label: "Základ", value: CzechFormat.wholeKc(figures.incomeKc), style: .muted),
                LevyPopoverRow(label: "DPH", value: CzechFormat.wholeKc(figures.vatKc), style: .strong),
            ],
            note: "Za " + supplyMonth(of: invoice) + ", odvádí se s přiznáním k DPH do "
                + CzechFormat.date(vatDue(of: invoice)) + ".")
        return group(
            id: vatGroupID, dots: [.vat], shortTitle: "DPH", value: CzechFormat.wholeKc(figures.vatKc),
            isNegative: false, popover: popover)
    }

    /// The group of the three levies the invoice adds, each by its authority's full name, and their total.
    private static func leviesGroup(_ figures: InvoiceFigures) -> SplitBarGroup {
        let rows =
            Authority.allCases.map { authority in
                LevyPopoverRow(
                    label: authority.title, value: CzechFormat.wholeKc(figures.levy(of: authority)), style: .muted)
            } + [LevyPopoverRow(label: "Celkem", value: CzechFormat.wholeKc(figures.leviesKc), style: .strong)]
        let popover = SplitBarPopover(
            title: "Daně a odvody", subtitle: "spočítá aplikace", tone: .authority(.tax), rows: rows,
            note: "O tolik platba zvýší odvody za rok \(figures.day.year), stejně jako Dopad na odvody v detailu"
                + " faktury.")
        return group(
            id: leviesGroupID, dots: Authority.allCases.map { SplitBarTone.authority($0) }, shortTitle: "Odvody",
            value: CzechFormat.wholeKc(figures.leviesKc), isNegative: figures.leviesKc < 0, popover: popover)
    }

    /// The group of `category`: how it is held, its share of the net income, and its amount of the month and the
    /// year, or of the invoice.
    private static func categoryGroup(_ category: BudgetCategory, division: Division) -> SplitBarGroup {
        let amount = division.month?.amounts[category]
        let value = amount.map(CzechFormat.wholeKc) ?? unknown
        let share = shareText(of: category, in: division)
        var rows = [LevyPopoverRow(label: "Podíl z čistého příjmu", value: share, style: .strong)]
        if division.isInvoice {
            rows.append(LevyPopoverRow(label: "Z faktury", value: value, style: .muted))
        } else {
            let year = division.year?.amounts[category].map(CzechFormat.wholeKc) ?? unknown
            rows.append(LevyPopoverRow(label: "Za měsíc", value: value, style: .muted))
            rows.append(LevyPopoverRow(label: "Za rok", value: year, style: .muted))
        }
        let subtitle: String
        let note: String?
        switch division.mode(of: category) {
        case .remainder:
            subtitle = "zbytek"
            note = "Dostane, co zůstane po ostatních kategoriích."
        case .fixed:
            subtitle = "pevná částka"
            note = "Částka je pevná, podíl se dopočítá z čistého příjmu."
        case .share:
            subtitle = "podílem"
            note = nil
        }
        let popover = SplitBarPopover(
            title: category.title, subtitle: subtitle, tone: .category(category), rows: rows, note: note)
        return group(
            id: category.rawValue, dots: [.category(category)], shortTitle: category.title, value: value,
            isNegative: (amount ?? 0) < 0, popover: popover)
    }

    /// A group of the legend with what VoiceOver reads for it: the title and the subtitle of `popover`, then each of
    /// its rows as its label with a small first letter and its value, then its note, as "Útrata, zbytek: podíl z
    /// čistého příjmu 100,0 %, za měsíc 187 111 Kč, za rok 2 245 332 Kč, Dostane, co zůstane po ostatních
    /// kategoriích.".
    private static func group(
        id: String, dots: [SplitBarTone], shortTitle: String, value: String, isNegative: Bool,
        popover: SplitBarPopover
    ) -> SplitBarGroup {
        let rows = popover.rows.map { smallFirstLetter($0.label) + " " + $0.value }
        let phrases = rows + [popover.note].compactMap { $0 }
        let label = popover.title + ", " + popover.subtitle + ": " + phrases.joined(separator: ", ")
        return SplitBarGroup(
            id: id, dots: dots, shortTitle: shortTitle, value: value, valueIsNegative: isNegative, popover: popover,
            accessibilityLabel: label)
    }

    /// `text` with its first letter small, as a label reads in the middle of a sentence, unless it is an abbreviation
    /// in capitals: "Za rok" is "za rok", but "DPH" stays "DPH".
    private static func smallFirstLetter(_ text: String) -> String {
        let second = text.dropFirst().first
        if let second, second.isUppercase {
            return text
        }
        return text.prefix(1).lowercased() + String(text.dropFirst())
    }
}
