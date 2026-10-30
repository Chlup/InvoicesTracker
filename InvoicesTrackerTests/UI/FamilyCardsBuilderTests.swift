import Foundation
import Testing
@testable import InvoicesTracker

/// What the cards of the children and of the spouse say about the family of a year, with the figures of the engine: the
/// sample year 2026 of the engine's regression test as of 17. 10. 2026 (the tax after the taxpayer credit is
/// 94 440 Kč), with the sample family, unless a test says otherwise. The amounts were worked out by hand: 1 267, 1 860
/// and 2 320 Kč a month for the first, the second and the third child, 2 070 Kč a month for the spouse. In every
/// expected string `\u{00A0}` is the no-break space.
struct FamilyCardsBuilderTests {
    // MARK: The family of the tests

    /// A child of the year with what the year says about it: in the household the whole year and claimed by me unless
    /// told otherwise.
    private static func member(
        _ name: String, born day: String, id: Int64, order: Int, household: MonthRange? = MonthRange.wholeYear,
        claimant: Claimant = .me, ztpp: MonthRange? = nil, studies: MonthRange? = nil
    ) -> FamilyChild {
        FamilyChild(
            child: Child(id: id, name: name, birthDate: civilDate(day)),
            year: ChildYear(household: household, claimant: claimant, order: order, ztpp: ztpp, studies: studies),
            isStored: true)
    }

    /// Anna, born 3. 9. 2019.
    private static func anna(
        order: Int = 1, household: MonthRange? = MonthRange.wholeYear, claimant: Claimant = .me
    ) -> FamilyChild {
        member("Anna", born: "2019-09-03", id: 1, order: order, household: household, claimant: claimant)
    }

    /// Tomáš, born 12. 4. 2024.
    private static func tomas(order: Int = 2, ztpp: MonthRange? = nil) -> FamilyChild {
        member("Tomáš", born: "2024-04-12", id: 2, order: order, ztpp: ztpp)
    }

    /// Ema, born 15. 6. 2026.
    private static func ema(order: Int) -> FamilyChild {
        member("Ema", born: "2026-06-15", id: 3, order: order)
    }

    /// The spouse of the sample: claimed for the whole year, without own income, unless told otherwise.
    private static func spouse(
        ownIncome: Int64 = 0, ztpp: MonthRange? = nil, claim: Bool = true
    ) -> SpouseYear {
        SpouseYear(claim: claim, months: MonthRange.wholeYear, ownIncomeKc: ownIncome, ztpp: ztpp)
    }

    /// The whole year 2026 with one receipt of `kc` on 15. 6., 60 % flat-rate expenses and the taxpayer credit.
    private static func wholeYear2026(_ kc: Int64) -> YearInput {
        yearInput(2026, receipts: [payment("2026-06-15", kc: kc)])
    }

    /// What the cards say about `children` and `spouse` with `input` computed as of `asOf`, as Zálohy a odpočty has
    /// them in a year that goes on unless `mode` and `isWholeYear` say otherwise: the year's family is what the
    /// computation took.
    private static func content(
        _ children: [FamilyChild], spouse: SpouseYear? = spouse(),
        input: YearInput = TaxEngineRegressionTests.sampleYear2026, asOf: String = "2026-10-17",
        mode: FamilyCardsMode = .stored, isWholeYear: Bool = false
    ) throws -> FamilyCardsContent {
        var input = input
        input.family = FamilyFacts(children: children.map { ChildFacts($0) }, spouse: spouse)
        let result = try AppModel.compute(input, asOf: civilDate(asOf))
        let family = FamilyYear(year: input.year, children: children, spouse: spouse)
        return FamilyCardsBuilder.content(family: family, result: result, mode: mode, isWholeYear: isWholeYear)
    }

    // MARK: The children

    @Test func theSampleFamilyShowsEachChildWithItsRateMonthsAndAmount() throws {
        let cards = try Self.content([Self.anna(), Self.tomas()])

        #expect(cards.children.total == "37\u{00A0}524\u{00A0}Kč za rok")
        #expect(
            cards.children.rows.map(\.heading) == [
                "Anna · nar. 3.\u{00A0}9.\u{00A0}2019", "Tomáš · nar. 12.\u{00A0}4.\u{00A0}2024",
            ])
        #expect(cards.children.rows.map(\.status) == ["1. dítě · 12\u{00A0}měsíců", "2. dítě · 12\u{00A0}měsíců"])
        #expect(cards.children.rows.map(\.amount) == ["15\u{00A0}204\u{00A0}Kč", "22\u{00A0}320\u{00A0}Kč"])
        #expect(cards.children.rows.map(\.countsInNoMonth) == [false, false])
        #expect(cards.children.rows.map(\.hasAmount) == [true, true])
        // A row opens the dialog on its child.
        #expect(cards.children.rows.map(\.member) == [Self.anna(), Self.tomas()])
        #expect(
            cards.children.rows.first?.spokenText
                == "Anna · nar. 3.\u{00A0}9.\u{00A0}2019, 1. dítě · 12\u{00A0}měsíců, 15\u{00A0}204\u{00A0}Kč")
        #expect(
            cards.children.rates
                == "Za každý měsíc, na jehož začátku s vámi dítě žilo a bylo vyživované, a za měsíc narození. Sazba"
                + " podle pořadí v domácnosti: 1. dítě 15\u{00A0}204\u{00A0}Kč, 2. dítě 22\u{00A0}320\u{00A0}Kč, 3. a"
                + " další 27\u{00A0}840\u{00A0}Kč za rok, se ZTP/P dvojnásobek.")
        // The tax takes the whole benefit, so there is no bonus; Zálohy says what the return asks for.
        #expect(cards.children.bonusHint == nil)
        #expect(
            cards.children.proofHint
                == "Druhý rodič, který s vámi žije, na stejné dítě ve stejném měsíci zvýhodnění uplatnit nemůže."
                + " K přiznání se přikládá potvrzení jeho zaměstnavatele, nebo prohlášení na volném listu.")
        #expect(cards.children.hint == cards.children.proofHint)
    }

    /// Anna, claimed by the other parent, keeps the first place in the household, so Tomáš stays the second child.
    @Test func aChildTheOtherParentClaimsKeepsItsPlaceAndBringsMeNothing() throws {
        let cards = try Self.content([Self.anna(claimant: .otherParent), Self.tomas()])

        #expect(
            cards.children.rows.map(\.status) == [
                "uplatňuje druhý rodič · 12\u{00A0}měsíců", "2. dítě · 12\u{00A0}měsíců",
            ])
        #expect(cards.children.rows.map(\.amount) == ["—", "22\u{00A0}320\u{00A0}Kč"])
        #expect(cards.children.rows.map(\.hasAmount) == [false, true])
        #expect(cards.children.rows.map(\.countsInNoMonth) == [false, false])
        #expect(cards.children.total == "22\u{00A0}320\u{00A0}Kč za rok")
        #expect(
            cards.children.proofHint
                == "Pořadí dětí se s druhým rodičem dohodněte – sazbu 1. dítěte nemůžete uplatnit oba. K přiznání"
                + " přiložte jeho prohlášení, že na vaše děti zvýhodnění neuplatňuje (u zaměstnance potvrzení"
                + " zaměstnavatele).")

        // When the other parent claims every child, nothing of it is mine: no total and nothing to attach.
        let theirs = try Self.content([Self.anna(claimant: .otherParent)])
        #expect(theirs.children.total == nil)
        #expect(theirs.children.proofHint == nil)
        #expect(theirs.children.hint == nil)
    }

    /// A child that counts in no month says why, in place of its rates, and brings nothing.
    @Test func aChildThatCountsInNoMonthSaysWhy() throws {
        let year2023 = yearInput(2023, receipts: [payment("2023-06-15", kc: 1_000_000)])
        let notBorn = try Self.content([Self.anna(), Self.tomas()], input: year2023, asOf: "2023-12-31")
        #expect(notBorn.children.rows.last?.status == "narodí se až 12.\u{00A0}4.\u{00A0}2024")

        let cases: [(child: FamilyChild, reason: String)] = [
            (Self.anna(household: nil), "v roce 2026 s vámi nežije"),
            (
                Self.member("Eva", born: "2000-01-01", id: 4, order: 1, studies: MonthRange.wholeYear),
                "už 26 let – zvýhodnění nelze uplatnit"
            ),
            (
                Self.member("Petr", born: "2007-03-01", id: 5, order: 1),
                "zletilé a nestuduje – zvýhodnění nelze uplatnit"
            ),
            (
                Self.member("Ema", born: "2026-06-15", id: 3, order: 1, household: MonthRange(from: 1, to: 5)),
                "v roce 2026 nesplňuje podmínky"
            ),
        ]
        for (child, reason) in cases {
            let row = try #require(try Self.content([child]).children.rows.first)
            #expect(row.status == reason)
            #expect(row.countsInNoMonth, "\(reason)")
            #expect(row.amount == "—", "\(reason)")
            #expect(!row.hasAmount, "\(reason)")
        }
        #expect(notBorn.children.rows.last?.countsInNoMonth == true)
    }

    /// A child at two rates in the year has both, and ZTP/P doubles what it brings.
    @Test func theRowSaysEveryRateOfTheChildAndItsZTPP() throws {
        // Ema, born 15. 6. 2026, is put first: from June Anna is the second child.
        let moved = try Self.content([Self.anna(order: 2), Self.tomas(order: 3), Self.ema(order: 1)])
        #expect(
            moved.children.rows.map(\.status) == [
                "1. dítě · 5\u{00A0}měsíců, 2. dítě · 7\u{00A0}měsíců",
                "2. dítě · 5\u{00A0}měsíců, 3. a další dítě · 7\u{00A0}měsíců",
                "1. dítě · 7\u{00A0}měsíců",
            ])
        #expect(
            moved.children.rows.map(\.amount) == [
                "19\u{00A0}355\u{00A0}Kč", "25\u{00A0}540\u{00A0}Kč", "8\u{00A0}869\u{00A0}Kč",
            ])
        #expect(moved.children.total == "53\u{00A0}764\u{00A0}Kč za rok")

        let ztpp = try Self.content([Self.anna(), Self.tomas(ztpp: MonthRange.wholeYear)])
        #expect(ztpp.children.rows.last?.status == "2. dítě · 12\u{00A0}měsíců · se ZTP/P")
        #expect(ztpp.children.rows.last?.amount == "44\u{00A0}640\u{00A0}Kč")
    }

    /// A child without a name is "Dítě".
    @Test func aChildWithoutANameIsDítě() throws {
        let unnamed = Self.member("", born: "2024-04-12", id: 2, order: 1)
        let cards = try Self.content([unnamed])

        #expect(cards.children.rows.first?.heading == "Dítě · nar. 12.\u{00A0}4.\u{00A0}2024")
    }

    @Test func aYearWithoutChildrenHasNoRowsNoTotalAndNoHint() throws {
        let cards = try Self.content([], spouse: nil)

        #expect(cards.children.rows.isEmpty)
        #expect(cards.children.total == nil)
        #expect(cards.children.hint == nil)
        #expect(
            ChildrenCardContent.noChildren
                == "Zatím žádné dítě. Přidejte děti, které s vámi žijí ve společné domácnosti.")
    }

    /// The box under the rows says what the benefit leaves after its credit: paid as a bonus, not paid because it is
    /// less than 100 Kč, or not paid yet because the income has not reached six minimum wages of the year.
    @Test func theBoxSaysWhetherWhatTheBenefitLeavesAfterTheTaxIsPaidAsABonus() throws {
        // 150 000 Kč: 9 000 Kč of tax, which the taxpayer credit takes; the children's 37 524 Kč are paid as a bonus,
        // as the income is more than six minimum wages (134 400 Kč).
        let paid = try Self.content(
            [Self.anna(), Self.tomas()], input: Self.wholeYear2026(150_000), asOf: "2026-12-31")
        #expect(
            paid.children.bonusHint
                == "Zvýhodnění převyšuje daň o 37\u{00A0}524\u{00A0}Kč – tolik vám finanční úřad vyplatí jako daňový"
                + " bonus.")
        #expect(try #require(paid.children.hint).hasSuffix(try #require(paid.children.bonusHint)))

        // 100 000 Kč is less than six minimum wages.
        let low = try Self.content([Self.anna(), Self.tomas()], input: Self.wholeYear2026(100_000), asOf: "2026-12-31")
        #expect(
            low.children.bonusHint
                == "Zvýhodnění převyšuje daň o 37\u{00A0}524\u{00A0}Kč, bonus se ale zatím nevyplatí: příjmy roku"
                + " nedosáhly 6× minimální mzdy (134\u{00A0}400\u{00A0}Kč).")

        // 766 500 Kč: 306 600 Kč of profit, 45 990 Kč of tax and 15 150 Kč after the taxpayer credit, of which Anna's
        // 15 204 Kč leave 54 Kč.
        let small = try Self.content([Self.anna()], spouse: nil, input: Self.wholeYear2026(766_500), asOf: "2026-12-31")
        #expect(
            small.children.bonusHint
                == "Zvýhodnění převyšuje daň o 54\u{00A0}Kč, bonus se ale pod 100\u{00A0}Kč nevyplácí.")
        #expect(
            small.children.hint
                == "Druhý rodič, který s vámi žije, na stejné dítě ve stejném měsíci zvýhodnění uplatnit nemůže."
                + " K přiznání se přikládá potvrzení jeho zaměstnavatele, nebo prohlášení na volném listu."
                + " Zvýhodnění převyšuje daň o 54\u{00A0}Kč, bonus se ale pod 100\u{00A0}Kč nevyplácí.")
    }

    /// Income below six minimum wages pays no bonus yet in a year that goes on, which Zálohy a odpočty shows of the
    /// current year; once the income is all the year's, of a year that is over or of a simulation, the bonus is not
    /// paid, not "not yet".
    @Test func aBonusIsNotPaidYetOnlyWhileTheIncomeOfTheYearMayStillGrow() throws {
        let input = Self.wholeYear2026(100_000)
        let goesOn = try Self.content([Self.anna(), Self.tomas()], input: input, asOf: "2026-12-31")
        let over = try Self.content([Self.anna(), Self.tomas()], input: input, asOf: "2026-12-31", isWholeYear: true)
        let simulated = try Self.content(
            [Self.anna(), Self.tomas()], input: input, asOf: "2026-12-31", mode: .simulation, isWholeYear: true)

        let notPaid =
            "Zvýhodnění převyšuje daň o 37\u{00A0}524\u{00A0}Kč, bonus se ale nevyplatí: příjmy roku nedosáhly"
            + " 6× minimální mzdy (134\u{00A0}400\u{00A0}Kč)."
        #expect(
            goesOn.children.bonusHint
                == "Zvýhodnění převyšuje daň o 37\u{00A0}524\u{00A0}Kč, bonus se ale zatím nevyplatí: příjmy roku"
                + " nedosáhly 6× minimální mzdy (134\u{00A0}400\u{00A0}Kč).")
        #expect(over.children.bonusHint == notPaid)
        #expect(simulated.children.bonusHint == notPaid)
    }

    /// The Simulátor leaves out what the return asks for, and keeps the rest.
    @Test func theSimulationLeavesOutTheProofForTheReturn() throws {
        let cards = try Self.content(
            [Self.anna(claimant: .otherParent), Self.tomas()], input: Self.wholeYear2026(150_000), asOf: "2026-12-31",
            mode: .simulation)

        #expect(cards.children.proofHint == nil)
        #expect(
            cards.children.hint
                == "Zvýhodnění převyšuje daň o 22\u{00A0}320\u{00A0}Kč – tolik vám finanční úřad vyplatí jako daňový"
                + " bonus.")
        #expect(cards.children.rows.map(\.amount) == ["—", "22\u{00A0}320\u{00A0}Kč"])
    }

    /// The Simulátor says beside Přidat dítě that nothing of its family is stored, with children or without; Zálohy
    /// a odpočty, which stores the family, says nothing there.
    @Test func theSimulationSaysBesideTheButtonThatNothingIsStored() throws {
        let simulated = try Self.content([Self.anna(), Self.tomas()], mode: .simulation)
        let empty = try Self.content([], spouse: nil, mode: .simulation)
        let stored = try Self.content([Self.anna(), Self.tomas()])

        #expect(simulated.children.addNote == "Jen pro simulaci – nic se neukládá.")
        #expect(empty.children.addNote == "Jen pro simulaci – nic se neukládá.")
        #expect(stored.children.addNote == nil)
    }

    // MARK: The spouse

    @Test func theSampleSpouseIsWithinTheLimitWithTomasUnderThreeAllYear() throws {
        let cards = try Self.content([Self.anna(), Self.tomas()])

        #expect(cards.spouse.total == "24\u{00A0}840\u{00A0}Kč za rok")
        #expect(cards.spouse.totalCounts)
        #expect(
            cards.spouse.claimLine
                == "24\u{00A0}840\u{00A0}Kč za rok – 2\u{00A0}070\u{00A0}Kč za každý měsíc, na jehož začátku byly"
                + " podmínky splněné. Snižuje jen daň, nejvýš na nulu.")
        #expect(cards.spouse.incomeTitle == "Vlastní příjmy manžela / manželky za rok 2026")
        #expect(cards.spouse.incomeStatus == "do limitu 68\u{00A0}000\u{00A0}Kč")
        #expect(!cards.spouse.incomeIsOverLimit)
        #expect(
            cards.spouse.youngChild
                == YoungChildNote(
                    text: "Dítě do 3 let ve společné domácnosti: Tomáš (12\u{00A0}měsíců). Od roku 2024 se sleva počítá"
                        + " jen za tyto měsíce.",
                    isMet: true))
        #expect(cards.spouse.result == "Sleva za 12\u{00A0}měsíců: 24\u{00A0}840\u{00A0}Kč")
        #expect(
            SpouseCardContent.incomeNote
                == "Hrubé příjmy za celý rok: mzda, podnikání, nájem, důchod, nemocenská, peněžitá pomoc v mateřství,"
                + " podpora v nezaměstnanosti, výživné pro manžela či manželku. Nepočítá se rodičovský příspěvek,"
                + " porodné, přídavek na dítě, stipendium ani výživné na dítě.")
    }

    /// The own income may be 68 000 Kč at most.
    @Test func aSpouseWithAnIncomeOverTheLimitGetsNoCredit() throws {
        let over = try Self.content([Self.anna(), Self.tomas()], spouse: Self.spouse(ownIncome: 70_000))

        #expect(over.spouse.incomeStatus == "nad limitem 68\u{00A0}000\u{00A0}Kč – slevu nejde uplatnit")
        #expect(over.spouse.incomeIsOverLimit)
        #expect(over.spouse.result == "V roce 2026 se sleva neuplatní – příjmy jsou nad limitem.")
        #expect(over.spouse.total == "neuplatní se")
        #expect(!over.spouse.totalCounts)

        let atTheLimit = try Self.content([Self.anna(), Self.tomas()], spouse: Self.spouse(ownIncome: 68_000))
        #expect(atTheLimit.spouse.incomeStatus == "do limitu 68\u{00A0}000\u{00A0}Kč")
        #expect(atTheLimit.spouse.result == "Sleva za 12\u{00A0}měsíců: 24\u{00A0}840\u{00A0}Kč")
    }

    /// From 2024 the credit asks for a child under three in the household; Anna is older.
    @Test func withoutAChildUnderThreeTheBoxSaysWhatTheCreditNeeds() throws {
        let cards = try Self.content([Self.anna()])

        #expect(
            cards.spouse.youngChild
                == YoungChildNote(
                    text: "Od roku 2024 se sleva uplatní jen za měsíce, kdy s vámi žije i vaše vyživované dítě mladší 3"
                        + " let. Mezi dětmi žádné takové není – přidejte ho, i když na něj zvýhodnění uplatňuje druhý"
                        + " rodič.",
                    isMet: false))
        #expect(cards.spouse.result == "V roce 2026 se sleva neuplatní – žádný měsíc nesplňuje podmínky.")
        #expect(cards.spouse.total == "neuplatní se")
    }

    /// Every child under three is named with its own months, which the engine counts for it: Ema, born 15. 6. 2026,
    /// is under three from July. A child without a name is "dítě".
    @Test func theBoxNamesEveryChildUnderThreeWithItsMonths() throws {
        let cards = try Self.content([Self.anna(), Self.tomas(), Self.ema(order: 3)])
        #expect(
            cards.spouse.youngChild?.text
                == "Dítě do 3 let ve společné domácnosti: Tomáš (12\u{00A0}měsíců), Ema (6\u{00A0}měsíců). Od roku 2024"
                + " se sleva počítá jen za tyto měsíce.")

        let unnamed = try Self.content([Self.member("", born: "2026-06-15", id: 3, order: 1)])
        #expect(
            unnamed.spouse.youngChild?.text.hasPrefix("Dítě do 3 let ve společné domácnosti: dítě (6\u{00A0}měsíců).")
                == true)
        #expect(unnamed.spouse.result == "Sleva za 6\u{00A0}měsíců: 12\u{00A0}420\u{00A0}Kč")
    }

    /// The spouse credit takes the tax down to zero at most: what the tax has no room for is said.
    @Test func theResultSaysWhenTheTaxHasNoRoomForTheWholeCredit() throws {
        // 680 750 Kč: 272 300 Kč of profit, 40 845 Kč of tax, 10 005 Kč after the taxpayer credit.
        let part = try Self.content([Self.tomas(order: 1)], input: Self.wholeYear2026(680_750), asOf: "2026-12-31")
        #expect(
            part.spouse.result
                == "Sleva za 12\u{00A0}měsíců: 24\u{00A0}840\u{00A0}Kč – uplatní se jen 10\u{00A0}005\u{00A0}Kč,"
                + " víc daně nezbývá")

        // 150 000 Kč: the taxpayer credit takes all the tax.
        let none = try Self.content([Self.tomas(order: 1)], input: Self.wholeYear2026(150_000), asOf: "2026-12-31")
        #expect(
            none.spouse.result
                == "Sleva za 12\u{00A0}měsíců: 24\u{00A0}840\u{00A0}Kč – daň už je nulová, sleva se neprojeví")
        #expect(none.spouse.total == "24\u{00A0}840\u{00A0}Kč za rok")
    }

    /// ZTP/P doubles the months it covers: three of them make fifteen months' worth.
    @Test func theResultSaysTheMonthsWithZTPP() throws {
        let cards = try Self.content(
            [Self.anna(), Self.tomas()], spouse: Self.spouse(ztpp: MonthRange(from: 9, to: 11)))

        #expect(cards.spouse.result == "Sleva za 12\u{00A0}měsíců, z toho 3 se ZTP/P: 31\u{00A0}050\u{00A0}Kč")
        #expect(cards.spouse.total == "31\u{00A0}050\u{00A0}Kč za rok")
    }

    /// Before 2024 the credit needs no young child, so there is no box about one.
    @Test func before2024TheCreditNeedsNoYoungChild() throws {
        let year2023 = yearInput(2023, receipts: [payment("2023-06-15", kc: 1_000_000)])
        let cards = try Self.content([Self.anna()], input: year2023, asOf: "2023-12-31")

        #expect(cards.spouse.youngChild == nil)
        #expect(cards.spouse.result == "Sleva za 12\u{00A0}měsíců: 24\u{00A0}840\u{00A0}Kč")
        #expect(cards.spouse.incomeTitle == "Vlastní příjmy manžela / manželky za rok 2023")
    }

    /// A spouse who is not claimed, or no spouse, has only the claim to tick.
    @Test func aSpouseWhoIsNotClaimedHasOnlyTheClaim() throws {
        for spouse in [Self.spouse(claim: false), nil] {
            let cards = try Self.content([Self.anna(), Self.tomas()], spouse: spouse)
            #expect(cards.spouse.total == nil)
            #expect(cards.spouse.incomeStatus == nil)
            #expect(cards.spouse.youngChild == nil)
            #expect(cards.spouse.result == nil)
            #expect(cards.spouse.claimLine.hasPrefix("24\u{00A0}840\u{00A0}Kč za rok – "))
        }
    }

    // MARK: Ranges of months chosen in a card

    /// Choosing a first month after the last moves the last along, and the other way round, so a range that is chosen
    /// is always one.
    @Test func aChosenMonthMovesTheOtherEndOfTheRangeAlong() {
        let summer = MonthRange(from: 6, to: 8)

        #expect(summer.withFrom(3) == MonthRange(from: 3, to: 8))
        #expect(summer.withFrom(10) == MonthRange(from: 10, to: 10))
        #expect(summer.withTo(12) == MonthRange(from: 6, to: 12))
        #expect(summer.withTo(2) == MonthRange(from: 2, to: 2))
        #expect(summer.withFrom(8) == MonthRange(from: 8, to: 8))
    }
}
