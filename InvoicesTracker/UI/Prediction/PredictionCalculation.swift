import Foundation

/// The estimate of a year as a calculation, as the card of the estimate on Přehled and the card Příjmy of Odhad odvodů
/// show it, and how its levies are paid, in the panel beside it. Every text is made by the builder
/// (`PredictionBuilder.calculation(_:incomeLabel:incomeNote:marksEstimate:)`); the view only lays them out
/// (`PredictionCalculationView`).
nonisolated struct PredictionCalculation: Sendable, Hashable {
    /// The income of the year less its levies, what that leaves, "Čistý příjem", and that per month, in the rows of a
    /// bill.
    var rows: [BillRow]

    /// The title of the panel of how the levies are paid: "Jak odvody zaplatíte".
    var payTitle: String

    /// How the levies are paid: the advances to the insurances, the tax advances, what is left to pay with the returns
    /// or what the advances overpay, and what to set aside each month for the payments that are not monthly.
    var payRows: [BillRow]
}

/// The calculation of a year's estimate and the panel of how its levies are paid, which both cards of the estimate
/// show.
nonisolated extension PredictionBuilder {
    /// The title of the panel of how the levies are paid.
    static let payTitle = "Jak odvody zaplatíte"

    /// The calculation of `outcome` as of 31 December, and how its levies are paid.
    ///
    /// The rows are the income of the year without VAT, under `incomeLabel` and with `incomeNote` under it, less the
    /// levies (`NetIncome`), with the share of the income they take beside them (`IncomeShares`) and what each
    /// authority takes of them under them (`BuilderText.leviesSplit(of:)`); what that leaves, "Čistý příjem", with its
    /// share; and that over the twelve months, "Průměrně za měsíc", with the green dot of the net income. Income,
    /// levies and net income all come from one result, so the calculation adds up. A share is left out while the
    /// income is not above zero.
    ///
    /// The panel has the advances planned to the social and the health insurance, which are paid every month; the tax
    /// advances, also where they are 0 Kč; what is left to pay with the returns beyond the advances, "Doplatek", or,
    /// only where nothing is owed and the advances pay more than the levies, what comes back, "Přeplatek", taken off;
    /// and, under the stronger line, what to set aside each month for the tax advances and the doplatek
    /// (`PredictionOutcome.setAsideMonthly`), with a note that says what it is made of, or, in a year without tax
    /// advances, that it is only the doplatek. A year that both owes and overpays shows Doplatek alone, as the result
    /// card does.
    ///
    /// With `marksEstimate` the figures that are made of the levies have the sign of an estimate in front of them
    /// (`estimateSign`): the levies, the net income, its average per month, the doplatek or the přeplatek and what to
    /// set aside. The income, the advances and the notes never have it.
    static func calculation(
        _ outcome: PredictionOutcome, incomeLabel: String, incomeNote: String?, marksEstimate: Bool
    ) -> PredictionCalculation {
        let result = outcome.result
        let net = NetIncome(result)
        let shares = IncomeShares(result)
        func marked(_ crowns: Int64) -> String {
            estimate(CzechFormat.wholeKc(crowns), when: marksEstimate)
        }
        let rows = [
            BillRow(
                label: incomeLabel, value: CzechFormat.wholeKc(net.incomeKc), note: incomeNote, valueStyle: .semibold),
            BillRow(
                label: "Odvody", value: marked(net.leviesKc), note: BuilderText.leviesSplit(of: result), sign: .minus,
                share: shares.map { BuilderText.share(tenths: $0.leviesTenths) }, valueStyle: .semibold,
                rule: .hairline),
            BillRow(
                label: "Čistý příjem", value: marked(net.yearKc), sign: .equals, style: .strong,
                share: shares.map { BuilderText.share(tenths: $0.netTenths) }, valueStyle: .title3Bold, rule: .strong),
            BillRow(
                label: "Průměrně za měsíc", value: marked(net.monthlyKc), sign: .divided,
                period: BuilderText.period(of: net), marksNetIncome: true, valueStyle: .title2Bold,
                rule: BillRule.none),
        ]
        let owed = outcome.owedTotal
        let overpaid = outcome.overpaidTotal
        let settlement =
            owed > 0 || overpaid == 0
            ? doplatekRow(value: marked(owed))
            : BillRow(
                label: "Přeplatek", value: marked(overpaid), note: "zálohy převýší odvody, vrátí se", sign: .minus,
                rule: BillRule.none)
        let taxAdvances = outcome.plannedTotal(.tax)
        let payRows = [
            insuranceAdvancesRow(
                value: CzechFormat.wholeKc(outcome.plannedTotal(.social) + outcome.plannedTotal(.health))),
            taxAdvancesRow(value: CzechFormat.wholeKc(taxAdvances)),
            settlement,
            setAsideRow(value: marked(outcome.setAsideMonthly), hasTaxAdvances: taxAdvances != 0),
        ]
        return PredictionCalculation(rows: rows, payTitle: payTitle, payRows: payRows)
    }

    /// The calculation of `outcome` while its estimate is not complete: the rows and the panel of
    /// `calculation(_:incomeLabel:incomeNote:marksEstimate:)` under the same labels and signs, with "—" for every value
    /// and no share. The income keeps `incomeNote`, whose figure is known, and the levies have no note, as it would
    /// hold the unknown parts. The panel names "Doplatek", as what is left to settle is not known; the note of what to
    /// set aside follows the planned tax advances, which are known. No row says that the estimate is incomplete: the
    /// card says it once.
    static func incompleteCalculation(
        _ outcome: PredictionOutcome, incomeLabel: String, incomeNote: String?
    ) -> PredictionCalculation {
        let net = NetIncome(outcome.result)
        let rows = [
            BillRow(label: incomeLabel, value: unknownAmount, note: incomeNote, valueStyle: .semibold),
            BillRow(label: "Odvody", value: unknownAmount, sign: .minus, valueStyle: .semibold, rule: .hairline),
            BillRow(
                label: "Čistý příjem", value: unknownAmount, sign: .equals, style: .strong, valueStyle: .title3Bold,
                rule: .strong),
            BillRow(
                label: "Průměrně za měsíc", value: unknownAmount, sign: .divided, period: BuilderText.period(of: net),
                marksNetIncome: true, valueStyle: .title2Bold, rule: BillRule.none),
        ]
        let payRows = [
            insuranceAdvancesRow(value: unknownAmount),
            taxAdvancesRow(value: unknownAmount),
            doplatekRow(value: unknownAmount),
            setAsideRow(value: unknownAmount, hasTaxAdvances: outcome.plannedTotal(.tax) != 0),
        ]
        return PredictionCalculation(rows: rows, payTitle: payTitle, payRows: payRows)
    }

    /// The advances planned to the social and the health insurance for the year, `value`, which are paid every month.
    private static func insuranceAdvancesRow(value: String) -> BillRow {
        BillRow(
            label: "Zálohy sociální a zdravotní", value: value, note: "platí se každý měsíc", rule: BillRule.none)
    }

    /// The tax advances planned for the year, `value`, added to the advances above them.
    private static func taxAdvancesRow(value: String) -> BillRow {
        BillRow(label: "Zálohy na daň", value: value, sign: .plus, rule: BillRule.none)
    }

    /// What is left to pay with the returns beyond the advances, `value`, added to them.
    private static func doplatekRow(value: String) -> BillRow {
        BillRow(label: "Doplatek", value: value, note: "s přiznáním a přehledy", sign: .plus, rule: BillRule.none)
    }

    /// What to set aside each month, `value`, under the stronger line, with what it is made of: the tax advances and
    /// the doplatek over twelve months, or, where there are no tax advances, the doplatek alone.
    private static func setAsideRow(value: String, hasTaxAdvances: Bool) -> BillRow {
        BillRow(
            label: "Odkládat průměrně za měsíc", value: value,
            note: hasTaxAdvances ? "(zálohy na daň + doplatek) ÷ 12" : "jen doplatek ÷ 12, bez záloh na daň",
            style: .strong, valueStyle: .title3Bold, rule: .separator)
    }
}
