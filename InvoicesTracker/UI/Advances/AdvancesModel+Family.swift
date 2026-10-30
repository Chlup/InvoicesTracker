import Foundation

/// The family on Zálohy a odpočty (`AdvancesModel`): the field of the spouse's own income, and the changes of the
/// family that the cards and the dialog of a child make through `FamilyEditing`. A change of the children is one write
/// of the data, with the orders of the other children of the year; the spouse is saved with the settings of the year,
/// at once.
extension AdvancesModel {
    /// The field of the spouse's own income has been typed in. Like a field of the deductions, it records the text and
    /// starts the wait again, and the text is read when the typing stops: an amount in whole Kč, or nothing for no
    /// income, becomes the income of the spouse; any other text stays in the field with the message under it, and the
    /// income keeps the value it had. A year without a spouse has no such field.
    func setSpouseIncomeText(_ text: String) {
        guard settings?.spouse != nil else { return }
        recordTyping(text, in: .spouseIncome)
    }

    /// Runs `write`, one write of the data, for the year shown and tells the app. A write that fails is logged as
    /// `what` and thrown on, and so is `VaultError.locked` while the data is locked; nothing is written then.
    fileprivate func writeFamily(_ what: String, _ write: (Database, Int) async throws -> Void) async throws {
        guard let year = loadedFamily?.year, let database = app.database else {
            throw VaultError.locked
        }
        do {
            try await write(database, year)
        } catch {
            AppModel.log(what, failedWith: error)
            throw error
        }
        await app.didWrite()
    }
}

extension AdvancesModel: FamilyEditing {
    /// The family of the year shown: the children as the data holds them, and the spouse as the person has it, with a
    /// change that is not saved yet.
    var family: FamilyYear? {
        guard let loadedFamily else { return nil }
        return FamilyYear(year: loadedFamily.year, children: loadedFamily.children, spouse: settings?.spouse)
    }

    /// Saves `child` and what the year shown says about it with the orders of the other children, in one write
    /// (`Database.saveChild`), and tells the app. Throws what the write throws, and nothing is stored then.
    func saveChild(_ child: Child, childYear: ChildYear, otherOrders: [Int64: Int]) async throws {
        try await writeFamily("Saving a child") { database, year in
            try await database.saveChild(child, year: year, childYear: childYear, otherOrders: otherOrders)
        }
    }

    /// Removes the child with `id` from every year with the orders of the other children of the year shown, in one
    /// write (`Database.removeChild`), and tells the app. Throws what the write throws, and nothing changes then.
    func removeChild(id: Int64, otherOrders: [Int64: Int]) async throws {
        try await writeFamily("Removing a child") { database, year in
            try await database.removeChild(id: id, year: year, otherOrders: otherOrders)
        }
    }

    /// Makes `spouse` the spouse of the year shown and saves it at once, with what waits to be saved, and with the
    /// income typed in its field. Throws `FamilyEditingError.notSaved` when it is not written: the save failed, which
    /// the screen says (`saveFailure`), and the spouse waits for the next save, as a change of the screen does; or the
    /// year is not loaded yet. A spouse the engine would not take (a range of months that is not one, an income below
    /// zero) is refused with `FamilyEditingError.refused`.
    func setSpouse(_ spouse: SpouseYear?) async throws {
        if let spouse, !spouse.months.isValid || !(spouse.ztpp?.isValid ?? true) || spouse.ownIncomeKc < 0 {
            throw FamilyEditingError.refused
        }
        let saved = await saveAtOnce([.spouse(spouse)])
        seedSpouseIncome(from: settings?.spouse)
        if !saved {
            throw FamilyEditingError.notSaved
        }
    }
}
