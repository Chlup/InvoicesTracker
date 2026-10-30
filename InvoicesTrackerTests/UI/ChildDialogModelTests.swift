import Foundation
import Testing
@testable import InvoicesTracker

/// The dialog of a child: the fields it opens with, what the child comes to in the year as they are filled in, what is
/// wrong with them, the order of the household without gaps or ties after every save and removal, and the removal from
/// every year after a question. Zálohy a odpočty is the family it edits: the sample year 2026 of the engine's
/// regression test, as of 17. 10. 2026, with the sample family stored for 2026 — Anna (3. 9. 2019) and Tomáš
/// (12. 4. 2024), the first and the second child, and the spouse — unless a test says otherwise. The Simulátor's is a
/// family in memory. The amounts were worked out by hand. In every expected string `\u{00A0}` is the no-break space.
@Suite(.settlesBackups)
@MainActor
struct ChildDialogModelTests {
    // MARK: The family of the tests

    /// The stored sample family with the model of Zálohy a odpočty loaded on it.
    @MainActor
    private struct Fixture {
        let app: AppModel
        let database: Database
        let model: AdvancesModel
        let anna: Int64
        let tomas: Int64

        /// The child with `id` as the year shown has it.
        func member(_ id: Int64) throws -> FamilyChild {
            try #require(model.family?.children.first { $0.child.id == id })
        }

        /// The dialog of the child with `id`, or of a new child for nil, in Zálohy a odpočty.
        func dialog(_ id: Int64?) throws -> ChildDialogModel {
            ChildDialogModel(editing: model, year: 2026, child: try id.map { try member($0) }, mode: .stored)
        }

        /// The order of each child of `year` as the data has it, by name.
        func orders(_ year: Int = 2026) async throws -> [String: Int] {
            let children = try await database.family(year: year).children
            return Dictionary(uniqueKeysWithValues: children.map { ($0.child.name, $0.year.order) })
        }
    }

    /// Runs `body` with the sample year, and with the sample family stored unless `family` is false, in a temporary
    /// folder that is removed afterwards.
    private func withFixture(family: Bool = true, _ body: (Fixture) async throws -> Void) async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let app = try await makeAdvancesApp(in: directory)
        let database = try #require(app.database)
        var anna: Int64 = 0
        var tomas: Int64 = 0
        if family {
            anna = try await database.saveChild(
                Child(id: nil, name: "Anna", birthDate: civilDate("2019-09-03")), year: 2026,
                childYear: Self.childYear(order: 1))
            tomas = try await database.saveChild(
                Child(id: nil, name: "Tomáš", birthDate: civilDate("2024-04-12")), year: 2026,
                childYear: Self.childYear(order: 2))
            try await database.saveSpouse(
                SpouseYear(claim: true, months: MonthRange.wholeYear, ownIncomeKc: 0, ztpp: nil), year: 2026)
            await app.didWriteAndBackUp()
        }
        let model = await loadedAdvancesModel(of: app)
        try await body(Fixture(app: app, database: database, model: model, anna: anna, tomas: tomas))
    }

    /// A child's year: in the household the whole year and claimed by me unless told otherwise.
    private static func childYear(
        order: Int, household: MonthRange? = MonthRange.wholeYear, claimant: Claimant = .me,
        ztpp: MonthRange? = nil, studies: MonthRange? = nil
    ) -> ChildYear {
        ChildYear(household: household, claimant: claimant, order: order, ztpp: ztpp, studies: studies)
    }

    // MARK: Opening

    @Test func aNewChildStartsLastInTheHouseholdForTheWholeYear() async throws {
        try await withFixture { f in
            let dialog = try f.dialog(nil)

            #expect(dialog.title == "Nové dítě")
            #expect(dialog.subtitle == "Dítě, které s vámi žije ve společné domácnosti")
            #expect(dialog.householdTitle == "Ve společné domácnosti v roce 2026")
            #expect(dialog.livesApartTitle == "V roce 2026 s vámi nežije")
            #expect(dialog.name.isEmpty)
            #expect(dialog.birthDateText.isEmpty)
            #expect(!dialog.livesApart)
            #expect((dialog.householdFrom, dialog.householdTo) == (1, 12))
            #expect(dialog.claimant == .me)
            #expect(dialog.orderCount == 3)
            #expect(dialog.order == 3)
            #expect(!dialog.hasZTPP)
            #expect(!dialog.studies)
            #expect(dialog.liveResult == nil)
            #expect(dialog.asksBeforeRemoving)
        }
    }

    @Test func aStoredChildOpensWithWhatTheYearSaysAboutIt() async throws {
        try await withFixture { f in
            try await f.database.saveChild(
                Child(id: f.tomas, name: "Tomáš", birthDate: civilDate("2024-04-12")), year: 2026,
                childYear: Self.childYear(
                    order: 2, household: MonthRange(from: 2, to: 11), claimant: .otherParent,
                    ztpp: MonthRange(from: 3, to: 5)))
            await f.model.load()

            let dialog = try f.dialog(f.tomas)

            #expect(dialog.title == "Upravit dítě")
            #expect(dialog.subtitle == "Tomáš · rok 2026")
            #expect(dialog.name == "Tomáš")
            #expect(dialog.birthDateText == "12.\u{00A0}4.\u{00A0}2024")
            #expect(dialog.birthDate == civilDate("2024-04-12"))
            #expect(!dialog.livesApart)
            #expect((dialog.householdFrom, dialog.householdTo) == (2, 11))
            #expect(dialog.claimant == .otherParent)
            #expect(dialog.order == 2)
            #expect(dialog.orderCount == 2)
            #expect(dialog.hasZTPP)
            #expect((dialog.ztppFrom, dialog.ztppTo) == (3, 5))
        }
    }

    /// A child that does not live in the household in the year opens with "V roce 2026 s vámi nežije", and the order it
    /// shows is its place among the children of the year, whatever number is stored.
    @Test func aChildAwayOpensAwayAndAtItsPlaceInTheOrder() async throws {
        try await withFixture { f in
            try await f.database.saveChild(
                Child(id: f.anna, name: "Anna", birthDate: civilDate("2019-09-03")), year: 2026,
                childYear: Self.childYear(order: 5, household: nil))
            await f.model.load()

            let dialog = try f.dialog(f.anna)

            #expect(dialog.livesApart)
            // Tomáš is 2 and Anna 5: she is the second.
            #expect(dialog.order == 2)
            #expect(dialog.orderCount == 2)
        }
    }

    // MARK: What the child comes to

    @Test func whatTheChildComesToIsSaidAsTheFieldsAreFilledIn() async throws {
        try await withFixture(family: false) { f in
            let dialog = try f.dialog(nil)
            dialog.name = "Anna"
            #expect(dialog.liveResult == nil)

            dialog.birthDateText = "3. 9. 2019"

            #expect(
                dialog.liveResult
                    == ChildDialogResult(
                        text: "V roce 2026: 12\u{00A0}měsíců jako 1. dítě · 15\u{00A0}204\u{00A0}Kč", counts: true))

            dialog.hasZTPP = true
            #expect(
                dialog.liveResult?.text
                    == "V roce 2026: 12\u{00A0}měsíců jako 1. dítě (se ZTP/P dvojnásobek) · 30\u{00A0}408\u{00A0}Kč")

            dialog.claimant = .otherParent
            #expect(
                dialog.liveResult
                    == ChildDialogResult(
                        text: "V roce 2026: 12\u{00A0}měsíců · uplatňuje druhý rodič, ve vašem výpočtu se nepočítá.",
                        counts: true))

            dialog.livesApart = true
            #expect(
                dialog.liveResult
                    == ChildDialogResult(
                        text: "V roce 2026 nesplňuje podmínky – zvýhodnění se neuplatní.", counts: false))
        }
    }

    /// The result counts the children of the year: Ema, born 15. 6. 2026 and put last, is the third child from June.
    /// Put first, she moves the others down and is the first child herself.
    @Test func whatANewChildComesToCountsTheOtherChildren() async throws {
        try await withFixture { f in
            let dialog = try f.dialog(nil)
            dialog.name = "Ema"
            dialog.birthDateText = "15.6.2026"

            #expect(
                dialog.liveResult?.text == "V roce 2026: 7\u{00A0}měsíců jako 3. a další dítě · 16\u{00A0}240\u{00A0}Kč"
            )

            dialog.order = 1
            #expect(dialog.liveResult?.text == "V roce 2026: 7\u{00A0}měsíců jako 1. dítě · 8\u{00A0}869\u{00A0}Kč")
        }
    }

    // MARK: What is wrong

    @Test func theDateOfBirthMustBeFilledInAndReadable() async throws {
        try await withFixture { f in
            let dialog = try f.dialog(nil)
            dialog.name = "Ema"

            #expect(await !dialog.save())
            #expect(dialog.error == "Vyplňte datum narození.")

            for text in ["31. 2. 2020", "Ema", "3. 9. 19", "3. 9.", "2019-09-03"] {
                dialog.birthDateText = text
                #expect(dialog.error == nil, "A change takes the message away")
                #expect(await !dialog.save())
                #expect(dialog.error == "Datum narození zadejte ve tvaru 3.\u{00A0}9.\u{00A0}2019.", "\(text)")
            }
            #expect(try await f.database.family(year: 2026).children.map(\.child.name) == ["Anna", "Tomáš"])
        }
    }

    /// The dates are read as they are written, with spaces or without, with leading zeros or without.
    @Test(arguments: ["3. 9. 2019", "3.9.2019", "03.09.2019", " 3.\u{00A0}9.\u{00A0}2019 ", "3. 9. 2019."])
    func aDateOfBirthIsReadAsItIsWritten(_ text: String) async throws {
        try await withFixture { f in
            let dialog = try f.dialog(nil)
            dialog.birthDateText = text

            #expect(dialog.birthDate == civilDate("2019-09-03"))
        }
    }

    @Test func theMonthsMustRunForward() async throws {
        try await withFixture { f in
            let dialog = try f.dialog(nil)
            dialog.name = "Ema"
            dialog.birthDateText = "15. 6. 2026"
            dialog.householdFrom = 8
            dialog.householdTo = 3

            #expect(await !dialog.save())
            #expect(dialog.error == "Měsíc „od“ musí být před měsícem „do“.")
            #expect(dialog.liveResult == nil)

            dialog.householdFrom = 3
            #expect(dialog.error == nil)
            dialog.hasZTPP = true
            dialog.ztppFrom = 12
            dialog.ztppTo = 1
            #expect(await !dialog.save())
            #expect(dialog.error == "U průkazu ZTP/P musí být měsíc „od“ před měsícem „do“.")
            #expect(try await f.database.family(year: 2026).children.count == 2)
        }
    }

    /// The studies are asked about for a child that is an adult on the 1st of a month of the year and not 26 on
    /// 1 January, and their months must run forward too.
    @Test func theStudiesAreAskedAboutOnlyForAChildFrom18To25InTheYear() async throws {
        try await withFixture { f in
            let dialog = try f.dialog(nil)
            #expect(!dialog.showsStudies)

            let shown = [
                ("1. 12. 2008", true), ("2. 12. 2008", false), ("2. 1. 2000", true), ("1. 1. 2000", false),
                ("3. 9. 2019", false), ("15. 3. 2005", true),
            ]
            for (day, expected) in shown {
                dialog.birthDateText = day
                #expect(dialog.showsStudies == expected, "\(day)")
            }

            dialog.name = "Petr"
            dialog.birthDateText = "15. 3. 2005"
            dialog.studies = true
            dialog.studiesFrom = 9
            dialog.studiesTo = 6
            #expect(await !dialog.save())
            #expect(dialog.error == "Měsíc „od“ musí být před měsícem „do“.")
        }
    }

    /// Zálohy a odpočty keeps no row of a year before the child's birth: any day of 2026 is taken, 2027 is not.
    @Test func inZálohyTheChildMustBeBornByTheEndOfTheYear() async throws {
        try await withFixture { f in
            let dialog = try f.dialog(nil)
            dialog.name = "Ema"
            dialog.birthDateText = "1. 1. 2027"

            #expect(await !dialog.save())
            #expect(dialog.error == "Datum narození musí být nejpozději v roce 2026.")

            dialog.birthDateText = "31. 12. 2026"
            #expect(await dialog.save())
            #expect(try await f.database.family(year: 2026).children.map(\.child.name) == ["Anna", "Tomáš", "Ema"])
        }
    }

    // MARK: Saving

    @Test func aNewChildIsSavedWithItsYear() async throws {
        try await withFixture { f in
            let dialog = try f.dialog(nil)
            dialog.name = "  Ema "
            dialog.birthDateText = "15. 6. 2026"
            dialog.householdFrom = 6
            dialog.hasZTPP = true
            dialog.ztppFrom = 9

            #expect(await dialog.save())

            let ema = try #require(try await f.database.family(year: 2026).children.last)
            #expect(ema.child.name == "Ema")
            #expect(ema.child.birthDate == civilDate("2026-06-15"))
            #expect(
                ema.year
                    == Self.childYear(
                        order: 3, household: MonthRange(from: 6, to: 12), ztpp: MonthRange(from: 9, to: 12)))
            #expect(ema.isStored)
            #expect(dialog.error == nil)
        }
    }

    /// Order 1 for a new child moves Anna to 2 and Tomáš to 3: the orders of the year stay 1, 2, 3.
    @Test func settingOrder1MovesAnnaTo2AndTomasTo3() async throws {
        try await withFixture { f in
            let dialog = try f.dialog(nil)
            dialog.name = "Ema"
            dialog.birthDateText = "15. 6. 2026"
            dialog.order = 1

            #expect(await dialog.save())

            #expect(try await f.orders() == ["Ema": 1, "Anna": 2, "Tomáš": 3])
        }
    }

    /// A child moved up takes the place it is given, and the children between move down one each, in their order; no
    /// two children share an order and none is missing.
    @Test func aChildMovedInTheOrderMovesTheOthersAlong() async throws {
        try await withFixture { f in
            let add = try f.dialog(nil)
            add.name = "Ema"
            add.birthDateText = "15. 6. 2026"
            #expect(await add.save())
            await f.model.load()
            #expect(try await f.orders() == ["Anna": 1, "Tomáš": 2, "Ema": 3])

            let ema = try #require(f.model.family?.children.first { $0.child.name == "Ema" })
            let move = ChildDialogModel(editing: f.model, year: 2026, child: ema, mode: .stored)
            #expect(move.order == 3)
            move.order = 1
            #expect(await move.save())
            #expect(try await f.orders() == ["Ema": 1, "Anna": 2, "Tomáš": 3])

            await f.model.load()
            let back = try f.dialog(f.anna)
            back.order = 3
            #expect(await back.save())
            #expect(try await f.orders() == ["Ema": 1, "Tomáš": 2, "Anna": 3])
        }
    }

    /// Children of the year without a row of their own get one with their order, so that the order the year shows
    /// stays 1, 2, 3 when a child older than them comes: in 2025 Anna and Tomáš have no row and are ordered by their
    /// dates of birth.
    @Test func theOrdersOfChildrenWithoutARowOfTheYearAreKeptWhenAChildComes() async throws {
        try await withFixture { f in
            f.app.selectYear(2025)
            await f.model.load()
            let before = try await f.database.family(year: 2025).children
            #expect(before.map(\.isStored) == [false, false])

            let petr = ChildDialogModel(editing: f.model, year: 2025, child: nil, mode: .stored)
            petr.name = "Petr"
            petr.birthDateText = "1. 5. 2015"
            #expect(await petr.save())

            let orders = try await f.orders(2025)
            #expect(orders == ["Petr": 3, "Anna": 1, "Tomáš": 2])
        }
    }

    @Test func vRoce2026SVamiNezijeStoresNoHousehold() async throws {
        try await withFixture { f in
            let dialog = try f.dialog(f.anna)
            dialog.livesApart = true
            dialog.householdFrom = 8
            dialog.householdTo = 3

            // The months are not asked for once the child does not live in the household.
            #expect(await dialog.save())

            let anna = try #require(try await f.database.family(year: 2026).children.first)
            #expect(anna.year.household == nil)
            #expect(anna.year.order == 1)
        }
    }

    @Test func aStoredChildIsChangedInPlace() async throws {
        try await withFixture { f in
            let dialog = try f.dialog(f.tomas)
            dialog.name = "Tomík"
            dialog.birthDateText = "13. 4. 2024"
            dialog.claimant = .otherParent

            #expect(await dialog.save())

            let children = try await f.database.family(year: 2026).children
            #expect(children.map(\.child.id) == [f.anna, f.tomas])
            #expect(children.last?.child == Child(id: f.tomas, name: "Tomík", birthDate: civilDate("2024-04-13")))
            #expect(children.last?.year == Self.childYear(order: 2, claimant: .otherParent))
        }
    }

    // MARK: Removing

    @Test func removingAsksFirstAndThenRemovesTheChildFromEveryYear() async throws {
        try await withFixture { f in
            try await f.database.saveChild(
                Child(id: f.anna, name: "Anna", birthDate: civilDate("2019-09-03")), year: 2025,
                childYear: Self.childYear(order: 1))
            let dialog = try f.dialog(f.anna)
            #expect(ChildDialogModel.removalTitle == "Odebrat dítě ze všech let?")
            #expect(
                ChildDialogModel.removalMessage(year: 2026)
                    == "Zmizí i z výpočtu minulých let. Pokud s vámi jen přestalo žít, zaškrtněte místo toho „V roce"
                    + " 2026 s vámi nežije“.")

            dialog.askToRemove()
            #expect(dialog.confirmsRemoval)
            dialog.cancelRemoval()
            #expect(!dialog.confirmsRemoval)
            #expect(try await f.database.family(year: 2026).children.count == 2)

            dialog.askToRemove()
            #expect(await dialog.remove())

            #expect(!dialog.confirmsRemoval)
            for year in [2025, 2026, 2027] {
                #expect(try await f.database.family(year: year).children.map(\.child.name) == ["Tomáš"], "\(year)")
            }
            #expect(
                try await f.database.integer("SELECT count(*) FROM child_year WHERE child_id = ?", [.integer(f.anna)])
                    == 0)
            // Tomáš is the first child of 2026 now.
            #expect(try await f.orders() == ["Tomáš": 1])
        }
    }

    // MARK: A change that is not stored

    /// A save that cannot be written keeps the dialog with what is typed in it and says so in it; nothing of the family
    /// changes, no other child is given another order. Once the data takes writes again, the same dialog saves.
    @Test func aSaveThatCannotBeWrittenKeepsTheDialogWithItsFailureAndChangesNothing() async throws {
        try await withFixture { f in
            let before = try await f.database.family(year: 2026)
            let dialog = try f.dialog(nil)
            dialog.name = "Ema"
            dialog.birthDateText = "15. 6. 2026"
            dialog.order = 1
            try await setDatabaseReadOnly(true, f.database)

            #expect(await !dialog.save())

            #expect(dialog.failure == "Dítě se nepodařilo uložit.")
            #expect(dialog.error == nil)
            #expect(dialog.name == "Ema")
            #expect(try await f.database.family(year: 2026) == before)

            try await setDatabaseReadOnly(false, f.database)
            #expect(await dialog.save())
            #expect(dialog.failure == nil)
            #expect(try await f.orders() == ["Ema": 1, "Anna": 2, "Tomáš": 3])
        }
    }

    /// A removal that cannot be written keeps the dialog, says so in it, and leaves the child and the others' orders.
    @Test func aRemovalThatCannotBeWrittenKeepsTheDialogWithItsFailureAndChangesNothing() async throws {
        try await withFixture { f in
            let before = try await f.database.family(year: 2026)
            let dialog = try f.dialog(f.anna)
            try await setDatabaseReadOnly(true, f.database)

            dialog.askToRemove()
            #expect(await !dialog.remove())

            #expect(dialog.failure == "Dítě se nepodařilo odebrat.")
            #expect(!dialog.confirmsRemoval)
            #expect(try await f.database.family(year: 2026) == before)
            try await setDatabaseReadOnly(false, f.database)
        }
    }

    /// The dialog makes one change of the family for a save and one for a removal, with the orders of the other
    /// children that change, or that have no row of their own for the year, so that they are made together or not at
    /// all. A change the family does not make keeps the dialog with the failure in it.
    @Test func aSaveOrARemovalIsOneChangeOfTheFamilyWithTheOrdersOfTheOthers() async throws {
        let anna = FamilyChild(
            child: Child(id: 1, name: "Anna", birthDate: civilDate("2019-09-03")), year: Self.childYear(order: 1),
            isStored: true)
        let tomas = FamilyChild(
            child: Child(id: 2, name: "Tomáš", birthDate: civilDate("2024-04-12")), year: Self.childYear(order: 2),
            isStored: false)
        let family = MemoryFamily(FamilyYear(year: 2026, children: [anna, tomas], spouse: nil))

        let new = ChildDialogModel(editing: family, year: 2026, child: nil, mode: .stored)
        new.name = "Ema"
        new.birthDateText = "15. 6. 2026"
        new.order = 1
        #expect(await new.save())
        #expect(family.saved.map(\.child.name) == ["Ema"])
        #expect(family.saved.map(\.childYear.order) == [1])
        #expect(family.saved.map(\.otherOrders) == [[1: 2, 2: 3]])

        // Tomáš has no row of his own for the year: he is written with his order though it stays.
        let edit = ChildDialogModel(editing: family, year: 2026, child: anna, mode: .stored)
        #expect(await edit.save())
        #expect(family.saved.map(\.child.id) == [nil, 1])
        #expect(family.saved.last?.otherOrders == [2: 2])

        let removal = ChildDialogModel(editing: family, year: 2026, child: anna, mode: .stored)
        #expect(await removal.remove())
        #expect(family.removed.map(\.id) == [1])
        #expect(family.removed.map(\.otherOrders) == [[2: 1]])

        family.failing = true
        let failing = ChildDialogModel(editing: family, year: 2026, child: tomas, mode: .stored)
        #expect(await !failing.save())
        #expect(failing.failure == "Dítě se nepodařilo uložit.")
        #expect(await !failing.remove())
        #expect(failing.failure == "Dítě se nepodařilo odebrat.")
        #expect(family.saved.count == 2)
        #expect(family.removed.count == 1)
    }

    // MARK: The Simulátor

    /// In the Simulátor the dialog says that nothing is stored, takes a child born after the year, and removes a child
    /// at once, as nothing is lost from a stored year.
    @Test func inTheSimulationTheDialogSaysSoAndRemovesAtOnce() async throws {
        let anna = FamilyChild(
            child: Child(id: 1, name: "Anna", birthDate: civilDate("2019-09-03")), year: Self.childYear(order: 1),
            isStored: true)
        let family = MemoryFamily(FamilyYear(year: 2026, children: [anna], spouse: nil))

        let new = ChildDialogModel(editing: family, year: 2026, child: nil, mode: .simulation)
        #expect(new.title == "Nové dítě v simulaci")
        #expect(new.subtitle == "Jen pro simulaci roku 2026 – nic se neukládá")
        new.name = "Ema"
        new.birthDateText = "15. 6. 2027"
        #expect(
            new.liveResult
                == ChildDialogResult(text: "V roce 2026 nesplňuje podmínky – zvýhodnění se neuplatní.", counts: false))
        #expect(await new.save())
        #expect(family.saved.map(\.child.name) == ["Ema"])
        #expect(family.saved.map(\.childYear.order) == [2])
        #expect(family.saved.map(\.otherOrders) == [[:]])

        let edit = ChildDialogModel(editing: family, year: 2026, child: anna, mode: .simulation)
        #expect(edit.title == "Upravit dítě v simulaci")
        #expect(edit.subtitle == "Jen pro simulaci roku 2026 – nic se neukládá")
        #expect(!edit.asksBeforeRemoving)
        #expect(await edit.remove())
        #expect(family.removed.map(\.id) == [1])
    }
}

/// A family that lives in memory, as the Simulátor's does: what the dialog saves and removes is noted, and the family
/// stays as it is. While `failing`, it makes no change and throws, as a family that cannot be stored does.
@MainActor
private final class MemoryFamily: FamilyEditing {
    var family: FamilyYear?
    var failing = false
    private(set) var saved: [(child: Child, childYear: ChildYear, otherOrders: [Int64: Int])] = []
    private(set) var removed: [(id: Int64, otherOrders: [Int64: Int])] = []

    /// What a change throws while `failing`.
    struct Refused: Error {}

    init(_ family: FamilyYear) {
        self.family = family
    }

    func saveChild(_ child: Child, childYear: ChildYear, otherOrders: [Int64: Int]) async throws {
        if failing {
            throw Refused()
        }
        saved.append((child: child, childYear: childYear, otherOrders: otherOrders))
    }

    func removeChild(id: Int64, otherOrders: [Int64: Int]) async throws {
        if failing {
            throw Refused()
        }
        removed.append((id: id, otherOrders: otherOrders))
    }

    func setSpouse(_ spouse: SpouseYear?) async throws {
        if failing {
            throw Refused()
        }
        family?.spouse = spouse
    }
}
