import Foundation

/// One of the three tiles above the table of Faktury.
nonisolated struct SummaryTile: Sendable, Hashable, Identifiable {
    var title: String
    var value: String
    var subtitle: String

    /// Whether the value is a dash for something that is not known yet, shown in a quieter colour.
    var isMuted: Bool

    var id: String {
        title
    }
}

/// The texts of the three tiles: the count of the invoices, their total in crowns at the ČNB rates and their total at
/// the uniform rate of the year.
nonisolated enum SummaryTiles {
    /// The tiles of `data`, in order. The numbers are those of the builder. The one thing added is a hint under the
    /// two totals in crowns: an invoice to check is left out of both, so when every invoice in a foreign currency that
    /// the table lists is one of them, the tiles would say that the category has none while the table lists one. They
    /// say how many invoices are left out instead.
    static func make(from data: InvoiceListData) -> [SummaryTile] {
        let hint = hintAboutInvoicesToCheck(in: data)
        let uniform: SummaryTile
        switch data.uniformTile {
        case .value(let value, let subtitle):
            uniform = SummaryTile(title: uniformTitle, value: value, subtitle: subtitle, isMuted: false)
        case .notPublished(let text):
            uniform = SummaryTile(title: uniformTitle, value: "—", subtitle: text, isMuted: true)
        case .noForeign(let value, let subtitle):
            uniform = SummaryTile(title: uniformTitle, value: value, subtitle: subtitle + hint, isMuted: false)
        }
        var crowns = SummaryTile(
            title: "Celkem bez DPH v Kč", value: data.czkTile.value, subtitle: data.czkTile.subtitle, isMuted: false)
        if case .noForeign = data.uniformTile {
            crowns.subtitle += hint
        }
        return [
            SummaryTile(
                title: "Počet faktur", value: data.countTile.value, subtitle: data.countTile.subtitle, isMuted: false),
            crowns, uniform,
        ]
    }

    private static let uniformTitle = "Celkem bez DPH jednotným kurzem"

    /// " · mimo součet: 2 faktury ke kontrole" when the category has invoices to check and the table lists an invoice
    /// in a foreign currency, though the totals count none (the tile of the uniform rate says so, in the same words as
    /// the one in crowns); otherwise nothing.
    private static func hintAboutInvoicesToCheck(in data: InvoiceListData) -> String {
        guard case .noForeign = data.uniformTile else { return "" }
        let count = data.chipCounts[.review, default: 0]
        // A row in a foreign currency has a value in crowns to show; a row in crowns has none.
        guard count > 0, data.rows.contains(where: { !$0.czk.isEmpty }) else { return "" }
        let word: String
        switch count {
        case 1: word = "faktura"
        case 2...4: word = "faktury"
        default: word = "faktur"
        }
        return " · mimo součet: \(count) \(word) ke kontrole"
    }
}
