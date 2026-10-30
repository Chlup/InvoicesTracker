import Foundation
import Testing
@testable import InvoicesTracker

struct TaxEngineGoldenTests {
    /// The cases in which every month is main activity: S1, S2, S3, S4, S8 and S8g of each year.
    static let mainActivityCases = GoldenCases.all.filter { $0.months.allSatisfy { $0 == "M" } }

    /// A whole year (31 December, every month counted) gives every value of the vector.
    @Test(arguments: TaxEngineGoldenTests.mainActivityCases)
    func mainActivity(case c: GoldenCase) {
        let result = TaxEngine.compute(input(for: c), asOf: civilDate("\(c.year)-12-31"))
        expectResult(result, matches: c)
    }

    /// Guards the filter above, so a typo in the vectors cannot quietly drop cases from the test.
    @Test func mainActivityCasesAreSixScenariosOfEveryYear() {
        let cases = TaxEngineGoldenTests.mainActivityCases
        #expect(cases.count == 30)
        for year in 2022...2026 {
            let names = cases.filter { $0.year == year }.map(\.name)
            #expect(names == ["S1", "S2", "S3", "S4", "S8", "S8g"], "\(year)")
        }
    }
}
