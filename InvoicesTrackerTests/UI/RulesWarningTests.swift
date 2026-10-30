import Foundation
import Testing
@testable import InvoicesTracker

/// The text of the warning that Přehled, Výpočet, Odhad odvodů and Nastavení › Rok show for a year without rules of its
/// own.
struct RulesWarningTests {
    @Test func theWarningNamesTheYearAndTheYearItIsEstimatedWith() {
        #expect(
            RulesWarning.message(year: 2027, rulesYear: 2026)
                == "Pravidla pro rok 2027 zatím nejsou v aplikaci – výpočet je odhad podle roku 2026.")
        #expect(
            RulesWarning.message(year: 2021, rulesYear: 2022)
                == "Pravidla pro rok 2021 zatím nejsou v aplikaci – výpočet je odhad podle roku 2022.")
    }
}
