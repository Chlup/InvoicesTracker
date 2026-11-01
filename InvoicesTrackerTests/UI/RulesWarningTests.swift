import Foundation
import Testing
@testable import InvoicesTracker

/// The texts of the warnings that Přehled, Výpočet, Odhad odvodů and Nastavení › Rok show: for a year without rules of
/// its own, and for income that is converted at a provisional rate.
struct RulesWarningTests {
    @Test func theWarningNamesTheYearAndTheYearItIsEstimatedWith() {
        #expect(
            RulesWarning.message(year: 2027, rulesYear: 2026)
                == "Pravidla pro rok 2027 zatím nejsou v aplikaci – výpočet je odhad podle roku 2026.")
        #expect(
            RulesWarning.message(year: 2021, rulesYear: 2022)
                == "Pravidla pro rok 2021 zatím nejsou v aplikaci – výpočet je odhad podle roku 2022.")
    }

    /// The sign "≈" marks a lone estimate among actual figures; this line is not one, and the warning icon of its note
    /// already says that it needs attention, so the line starts with the words.
    @Test func theLineOfProvisionalIncomeStartsWithWordsAndNotWithTheSignOfAnEstimate() {
        #expect(
            RulesWarning.provisionalIncome
                == "Část příjmů je zatím přepočtená předběžným kurzem."
                + " Přepočte se sama, až budou kurzy ČNB k dispozici.")
        #expect(!RulesWarning.provisionalIncome.contains("≈"))
    }
}
