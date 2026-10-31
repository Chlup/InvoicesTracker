import Foundation
import Testing
@testable import InvoicesTracker

/// The words of the card Aktualizace in Nastavení › Aplikace: its fixed texts, the version installed, and the moment of
/// the last check, which is told as the moment of a backup is: "dnes 9:14" on the day of `now`, otherwise the date and
/// the time. The clock is at noon of 30. 10. 2026 in Prague. In every expected string `\u{00A0}` is the no-break space.
struct UpdatesTextsTests {
    private let prague = TimeZone(identifier: "Europe/Prague")!
    private let utc = TimeZone(identifier: "UTC")!

    /// Noon of 30. 10. 2026 in Prague.
    private var now: Date {
        pragueTime("2026-10-30", 12, 0)
    }

    /// `hour`:`minute` of `day` in Prague.
    private func pragueTime(_ day: String, _ hour: Int, _ minute: Int) -> Date {
        CzechCalendar.pragueTime(civilDate(day), hour: hour, minute: minute)
    }

    @Test func theCardKeepsItsCopy() {
        #expect(UpdatesTexts.title == "Aktualizace")
        #expect(UpdatesTexts.subtitle == "Jednou denně se podívá, jestli je nová verze. Nic jiného se neodesílá.")
        #expect(UpdatesTexts.automaticLabel == "Kontrolovat automaticky")
        #expect(UpdatesTexts.checkNowTitle == "Zkontrolovat teď")
    }

    @Test func theVersionIsTheMarketingVersionAndTheBuildInParentheses() {
        #expect(UpdatesTexts.version(shortVersion: "1.7.0", build: "10") == "1.7.0 (10)")
    }

    @Test func theInstalledVersionIsThatOfTheBundleOfTheApp() throws {
        let info = try #require(Bundle.main.infoDictionary)
        let shortVersion = try #require(info["CFBundleShortVersionString"] as? String)
        let build = try #require(info["CFBundleVersion"] as? String)

        #expect(!shortVersion.isEmpty)
        #expect(!build.isEmpty)
        #expect(UpdatesTexts.installedVersion == "\(shortVersion) (\(build))")
    }

    @Test func aCheckThatNeverRanIsNotThereYet() {
        #expect(UpdatesTexts.lastCheck(nil, now: now, timeZone: prague) == "zatím žádná")
    }

    @Test func aCheckOfTodayIsToldWithItsTimeAndAnOlderOneWithItsDate() {
        #expect(UpdatesTexts.lastCheck(pragueTime("2026-10-30", 9, 14), now: now, timeZone: prague) == "dnes 9:14")
        #expect(
            UpdatesTexts.lastCheck(pragueTime("2026-10-15", 18, 40), now: now, timeZone: prague)
                == "15.\u{00A0}10.\u{00A0}2026 18:40")
    }

    /// A check at 23:30 on 30. 10. in Prague (22:30 in UTC) is looked at an hour later, at 00:30 on 31. 10. in Prague
    /// (23:30 on 30. 10. in UTC): it is a check of the day before in Prague and a check of today in UTC.
    @Test func theDayOfACheckIsTheDayInTheTimeZoneGiven() {
        let check = pragueTime("2026-10-30", 23, 30)
        let afterMidnight = pragueTime("2026-10-31", 0, 30)

        #expect(
            UpdatesTexts.lastCheck(check, now: afterMidnight, timeZone: prague) == "30.\u{00A0}10.\u{00A0}2026 23:30")
        #expect(UpdatesTexts.lastCheck(check, now: afterMidnight, timeZone: utc) == "dnes 22:30")
    }
}
