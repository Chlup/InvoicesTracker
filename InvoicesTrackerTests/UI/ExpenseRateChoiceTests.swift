import Testing
@testable import InvoicesTracker

/// The rates of the flat-rate expenses as the menus of Zálohy a odpočty and of Simulátor offer them, and the note that
/// goes with the lowest of them.
struct ExpenseRateChoiceTests {
    @Test func theRateOf30PercentIsNamedAsTheRentOfBusinessProperty() {
        let rent = ExpenseRateChoice.all.first { $0.percent == 30 }

        #expect(rent?.label == "30 % – nájem obchodního majetku")
    }

    @Test func only30PercentHasTheNoteThatOrdinaryRentIsNotCounted() {
        #expect(
            ExpenseRateChoice.note(forPercent: 30)
                == "Běžný pronájem podle § 9 aplikace nepočítá – není to příjem z podnikání.")
        for percent in [80, 60, 40] {
            #expect(ExpenseRateChoice.note(forPercent: percent) == nil, "\(percent) %")
        }
    }
}
