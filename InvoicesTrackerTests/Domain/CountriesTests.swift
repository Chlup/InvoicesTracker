import Foundation
import Testing
@testable import InvoicesTracker

/// The countries of the client form and of the printed invoice: one list of codes and one set of names. (What the
/// invoice prints for a country is pinned by the tests of `InvoiceTextFormat`, which asks `Countries`.)
struct CountriesTests {
    @Test func theUnitedStatesAreNamedInFullInCzech() {
        #expect(Countries.name("US", language: .cs) == "Spojené státy americké")
    }

    @Test func theCountriesOfTheAppAreNamedInBothLanguagesAsTheInvoiceNamesThem() {
        #expect(Countries.name("CZ", language: .cs) == "Česko")
        #expect(Countries.name("CZ", language: .en) == "Czech Republic")
        #expect(Countries.name("US", language: .en) == "United States of America")
    }

    @Test func aCodeIsReadInAnyCaseAndWithoutSurroundingSpaces() {
        #expect(Countries.name("us", language: .en) == "United States of America")
        #expect(Countries.name(" cz ", language: .cs) == "Česko")
    }

    @Test func aCountryOutsideTheWrittenOutOnesTakesTheNameTheSystemHasForTheLanguage() {
        #expect(Countries.name("JP", language: .en) == "Japan")
        #expect(Countries.name("JP", language: .cs) == "Japonsko")
    }

    @Test func aTextThatIsNoCodeIsGivenBackAsTypedAndNothingStaysNothing() {
        #expect(Countries.name("Brazil", language: .cs) == "Brazil")
        #expect(Countries.name("  Nový Zéland ", language: .en) == "Nový Zéland")
        #expect(Countries.name("ZZ", language: .en) == "ZZ")
        #expect(Countries.name("", language: .cs) == "")
        #expect(Countries.name("   ", language: .en) == "")
    }

    // MARK: The list

    @Test func theListHasEveryCountryOfISO3166OnceByItsCodeOfTwoCapitals() {
        #expect(Countries.all.count == 249)
        #expect(Set(Countries.all).count == 249)
        for code in Countries.all {
            #expect(
                code.utf8.count == 2 && code.utf8.allSatisfy { (UInt8(ascii: "A")...UInt8(ascii: "Z")).contains($0) })
        }
    }

    @Test func theListHasTheCountriesAFreelancerInvoicesAndTheRestOfTheWorld() {
        let plausible = [
            "CZ", "SK", "DE", "AT", "PL", "GB", "CH", "US", "CA", "AU", "IE", "NL", "FR", "NO", "IS", "LI",
        ]
        for code in plausible {
            #expect(Countries.all.contains(code), "\(code) is not offered")
        }
        #expect(Countries.all.contains("JP"))
        #expect(Countries.all.contains("NZ"))
    }

    @Test func everyCountryOfTheListHasANameInBothLanguagesThatIsNotItsCode() {
        for code in Countries.all {
            for language in [InvoiceLanguage.cs, .en] {
                let name = Countries.name(code, language: language)
                #expect(!name.isEmpty && name != code, "\(code) has no name in \(language.rawValue)")
            }
        }
    }

    @Test func theListGoesByTheCzechNamesInTheCzechOrderOfLetters() {
        let names = Countries.all.map { Countries.name($0, language: .cs) }
        let sorted = names.sorted { $0.compare($1, locale: Locale(identifier: "cs")) == .orderedAscending }
        #expect(names == sorted)
        // In Czech "Ch" is a letter of its own after "H".
        let hongkong = Countries.all.firstIndex(of: "HK")
        let chile = Countries.all.firstIndex(of: "CL")
        let india = Countries.all.firstIndex(of: "IN")
        #expect(hongkong != nil && chile != nil && india != nil)
        if let hongkong, let chile, let india {
            #expect(hongkong < chile && chile < india)
        }
        // And "Č" is a letter of its own after "C": Curaçao, Česko, Čína, Dánsko.
        let curacao = Countries.all.firstIndex(of: "CW")
        let czechia = Countries.all.firstIndex(of: "CZ")
        let china = Countries.all.firstIndex(of: "CN")
        let denmark = Countries.all.firstIndex(of: "DK")
        #expect(curacao != nil && czechia != nil && china != nil && denmark != nil)
        if let curacao, let czechia, let china, let denmark {
            #expect(curacao < czechia && czechia < china && china < denmark)
        }
    }
}
