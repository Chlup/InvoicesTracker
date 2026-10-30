import Foundation
import Testing
@testable import InvoicesTracker

/// The words of the banner on Přehled that reminds the person to enter the uniform rate by hand, once the search for it
/// has ended on 31 March without finding it.
struct UniformRateReminderBannerTests {
    @Test func theTextNamesTheYearAndWhereToEnterTheRate() {
        #expect(
            UniformRateReminderBanner.text(year: 2026)
                == "Jednotný kurz za rok 2026 se nepodařilo najít – zadejte ho ručně v Nastavení › Rok 2026.")
        #expect(
            UniformRateReminderBanner.text(year: 2027)
                == "Jednotný kurz za rok 2027 se nepodařilo najít – zadejte ho ručně v Nastavení › Rok 2027.")
    }
}
