import AppKit
import Testing
@testable import InvoicesTracker

/// The card Aktualizace of Nastavení › Aplikace in the window of the app, as VoiceOver reaches it, with a `FakeUpdater`
/// in the place of Sparkle, on the data of `EditorFixture` (the clock is at noon of 17. 10. 2026):
/// - the card shows the version installed, when the updater last checked and the switch of the daily check, the switch
///   turns the daily check off and on, and Zkontrolovat teď asks the updater for a check;
/// - the button waits while the updater cannot check;
/// - without an updater the card shows the version and its controls are disabled;
/// - the card stands under Vzhled in the left column, and the licences end with the footer in place of a version.
///
/// The tab has two buttons that show Zkontrolovat teď, this card's and the one of the rates (Kurzy). VoiceOver names
/// this card's after the card (`UpdatesTexts.checkNowAccessibilityLabel`), and the controls of this card are looked for
/// in the card, never in the whole window. A switch is found by its role, as the text beside it reads the same. One
/// window at a time, so that what a test sees settle is its own window.
@Suite(.serialized, .settlesBackups)
@MainActor
struct UpdatesCardWindowTests {
    /// Shows Nastavení › Aplikace in `window` and gives `body` the card Aktualizace once the page has it.
    private func withTheCard(
        of app: AppModel, in window: NSWindow, _ body: (AnyObject) async throws -> Void
    ) async throws {
        app.showSettings(.application)
        try await waitUntil { window.title == "Nastavení" }
        try await withAccessibilityElements {
            try await waitUntil { accessibilityElement(labelled: UpdatesTexts.title, in: window) != nil }
            try await body(try #require(accessibilityElement(labelled: UpdatesTexts.title, in: window)))
        }
    }

    /// The button of the card, found in the card by the name VoiceOver gives it. The card Kurzy has a button that shows
    /// the same title, so the lookup is made in the card and not in the window.
    private func checkButton(in window: NSWindow) -> AnyObject? {
        accessibilityElement(labelled: UpdatesTexts.title, in: window).flatMap {
            accessibilityElement(labelled: UpdatesTexts.checkNowAccessibilityLabel, role: .button, under: $0)
        }
    }

    /// The switch of the daily check, found in the card by its role, as the text beside it reads the same.
    private func dailySwitch(in window: NSWindow) -> AnyObject? {
        accessibilityElement(labelled: UpdatesTexts.title, in: window).flatMap {
            accessibilityElement(labelled: UpdatesTexts.automaticLabel, role: .checkBox, under: $0)
        }
    }

    /// Whether the switch `element` is on, as VoiceOver reads it: the value of a switch, 1 or 0. Nil when it reads no
    /// such value.
    private func isOn(_ element: AnyObject) -> Bool? {
        // Asked for as a function of its type, because the protocols of accessibility declare `accessibilityValue()`
        // with more than one type.
        let value: (() -> Any?)? = element.accessibilityValue
        return ((value?() ?? nil) as? NSNumber)?.boolValue
    }

    /// 9:14 on the day of the clock of `app`, in its time zone: "dnes 9:14" on the card.
    private func nineFourteen(of app: AppModel) throws -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = app.dependencies.timeZone()
        let today = CivilDate.today(now: app.dependencies.clock.now(), timeZone: calendar.timeZone)
        let time = DateComponents(year: today.year, month: today.month, day: today.day, hour: 9, minute: 14)
        return try #require(calendar.date(from: time))
    }

    /// The card names the version installed and the last check, shows the switch on, and its button asks the updater
    /// for one check. The button is the card's own: it is in the frame of the card.
    @Test func theCardShowsTheUpdaterAndChecksOnRequest() async throws {
        try await EditorFixture.with { f in
            let fake = FakeUpdater(canCheck: true, automatic: true, lastCheck: try nineFourteen(of: f.app))
            f.app.updates = UpdatesModel(updater: fake)
            try await withAppWindow(of: f.app, size: AppWindowSize.minimum) { window in
                try await withTheCard(of: f.app, in: window) { card in
                    let readings = accessibilityReadings(under: card)
                    #expect(readings.contains(UpdatesTexts.subtitle))
                    #expect(readings.contains("Verze"))
                    #expect(readings.contains(UpdatesTexts.installedVersion))
                    #expect(readings.contains("Poslední kontrola"))
                    #expect(readings.contains("dnes 9:14"))

                    let automatic = try #require(dailySwitch(in: window))
                    #expect(isOn(automatic) == true)
                    #expect(automatic.isAccessibilityEnabled?() == true)

                    let button = try #require(checkButton(in: window))
                    let cardFrame = try #require(card.accessibilityFrame?())
                    let buttonFrame = try #require(button.accessibilityFrame?())
                    #expect(cardFrame.contains(buttonFrame), "\(buttonFrame) is not in \(cardFrame)")
                    #expect(button.isAccessibilityEnabled?() == true)
                    #expect(fake.checkCount == 0)

                    #expect(button.accessibilityPerformPress?() == true)

                    #expect(fake.checkCount == 1)
                }
            }
        }
    }

    /// The tab has two buttons that show Zkontrolovat teď, and VoiceOver, its rotor and Voice Control list buttons by
    /// name. The card's button is named after the card, so that the two are listed apart, and the button of the card
    /// Kurzy keeps its name: it is the only one outside the card that reads the title alone.
    @Test func theButtonIsNamedAfterTheCardApartFromTheOneOfKurzy() async throws {
        try await EditorFixture.with { f in
            f.app.updates = UpdatesModel(updater: FakeUpdater(canCheck: true, automatic: true, lastCheck: nil))
            try await withAppWindow(of: f.app, size: AppWindowSize.minimum) { window in
                try await withTheCard(of: f.app, in: window) { card in
                    try await waitUntil { accessibilityButton(labelled: UpdatesTexts.checkNowTitle, in: window) != nil }
                    let button = try #require(checkButton(in: window))
                    #expect(button.accessibilityLabel?() == "Zkontrolovat teď – Aktualizace")
                    #expect(
                        accessibilityElement(labelled: UpdatesTexts.checkNowTitle, role: .button, under: card) == nil)

                    let rates = try #require(accessibilityButton(labelled: UpdatesTexts.checkNowTitle, in: window))
                    let cardFrame = try #require(card.accessibilityFrame?())
                    let ratesFrame = try #require(rates.accessibilityFrame?())
                    #expect(!cardFrame.intersects(ratesFrame), "\(ratesFrame) is in the card \(cardFrame)")
                }
            }
        }
    }

    /// The switch is the daily check of the updater: pressed, it turns the check off and then on again, in the updater
    /// and on the card.
    @Test func theSwitchTurnsTheDailyCheckOffAndOn() async throws {
        try await EditorFixture.with { f in
            let fake = FakeUpdater(canCheck: true, automatic: true, lastCheck: nil)
            f.app.updates = UpdatesModel(updater: fake)
            try await withAppWindow(of: f.app, size: AppWindowSize.minimum) { window in
                try await withTheCard(of: f.app, in: window) { _ in
                    let automatic = try #require(dailySwitch(in: window))
                    #expect(isOn(automatic) == true)

                    #expect(automatic.accessibilityPerformPress?() == true)

                    try await waitUntil { fake.automaticallyChecksForUpdates == false }
                    try await waitUntil { dailySwitch(in: window).flatMap(isOn) == false }

                    #expect(try #require(dailySwitch(in: window)).accessibilityPerformPress?() == true)

                    try await waitUntil { fake.automaticallyChecksForUpdates }
                    try await waitUntil { dailySwitch(in: window).flatMap(isOn) == true }
                }
            }
        }
    }

    /// While Sparkle cannot check, the button is disabled and asks for nothing. Once it can, the button can be
    /// pressed.
    @Test func theButtonWaitsWhileSparkleCannotCheck() async throws {
        try await EditorFixture.with { f in
            let fake = FakeUpdater(canCheck: false, automatic: true, lastCheck: nil)
            let updates = UpdatesModel(updater: fake)
            f.app.updates = updates
            try await withAppWindow(of: f.app, size: AppWindowSize.minimum) { window in
                try await withTheCard(of: f.app, in: window) { _ in
                    let button = try #require(checkButton(in: window))
                    #expect(button.isAccessibilityEnabled?() == false)
                    #expect(fake.checkCount == 0)

                    fake.canCheckForUpdates = true
                    updates.refresh()

                    try await waitUntil { checkButton(in: window)?.isAccessibilityEnabled?() == true }
                    #expect(try #require(checkButton(in: window)).accessibilityPerformPress?() == true)
                    #expect(fake.checkCount == 1)
                }
            }
        }
    }

    /// An app with no updater, as the app hosting the tests has none, still names the version it is. The last check
    /// never was, the switch is off, and neither the switch nor the button can be used.
    @Test func theCardShowsTheVersionWithDisabledControlsWithoutAnUpdater() async throws {
        try await EditorFixture.with { f in
            f.app.updates = nil
            try await withAppWindow(of: f.app, size: AppWindowSize.minimum) { window in
                try await withTheCard(of: f.app, in: window) { card in
                    let readings = accessibilityReadings(under: card)
                    #expect(readings.contains("Verze"))
                    #expect(readings.contains(UpdatesTexts.installedVersion))
                    #expect(readings.contains("Poslední kontrola"))
                    #expect(readings.contains("zatím žádná"))

                    let automatic = try #require(dailySwitch(in: window))
                    #expect(isOn(automatic) == false)
                    #expect(automatic.isAccessibilityEnabled?() == false)
                    #expect(try #require(checkButton(in: window)).isAccessibilityEnabled?() == false)
                }
            }
        }
    }

    /// The left column of a wide window holds Vzhled with Aktualizace under it, 16 points apart and as wide, and the
    /// right column Kurzy with Licence under it.
    @Test func theCardStandsUnderVzhledInTheLeftColumn() async throws {
        try await EditorFixture.with { f in
            f.app.updates = UpdatesModel(updater: FakeUpdater(canCheck: true, automatic: true, lastCheck: nil))
            try await withAppWindow(of: f.app, size: AppWindowSize.large) { window in
                try await withTheCard(of: f.app, in: window) { _ in
                    try await waitUntil { frameOfCard(labelled: "Licence", in: window) != nil }
                    try await layOut(window)
                    let appearance = try #require(frameOfCard(labelled: "Vzhled", in: window))
                    let updates = try #require(frameOfCard(labelled: UpdatesTexts.title, in: window))
                    let rates = try #require(frameOfCard(labelled: "Kurzy", in: window))
                    let licences = try #require(frameOfCard(labelled: "Licence", in: window))

                    // The origin of the screen is at the bottom left, so a card under another has the lower edges.
                    #expect(abs(updates.minX - appearance.minX) < 1)
                    #expect(abs(updates.width - appearance.width) < 1)
                    #expect(abs((appearance.minY - updates.maxY) - 16) < 1, "\(appearance) over \(updates)")
                    #expect(rates.minX > appearance.maxX)
                    #expect(abs(rates.maxY - appearance.maxY) < 1)
                    #expect(abs(licences.minX - rates.minX) < 1)
                    #expect(licences.maxY < rates.minY)
                }
            }
        }
    }

    /// The card Licence lists Sparkle after the other two, and ends with the footer that says where the data stay: it
    /// shows no version, which is the card Aktualizace's.
    @Test func theLicenceCardListsSparkleAndEndsWithTheFooterInsteadOfAVersion() async throws {
        try await EditorFixture.with { f in
            try await withAppWindow(of: f.app, size: AppWindowSize.minimum) { window in
                try await withTheCard(of: f.app, in: window) { _ in
                    try await waitUntil { accessibilityElement(labelled: "Licence", in: window) != nil }
                    let card = try #require(accessibilityElement(labelled: "Licence", in: window))
                    let readings = accessibilityReadings(under: card)

                    #expect(readings.contains("Sparkle"))
                    #expect(readings.contains("aktualizace aplikace · licence MIT"))
                    // The link that shows the text of the licence is a link for VoiceOver, not a button.
                    #expect(
                        accessibilityElement(labelled: "Zobrazit licenci – Sparkle", role: .link, under: card) != nil)
                    #expect(readings.last == AppTabModel.licenceFooter)
                    let shortVersion = try #require(
                        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String)
                    #expect(!readings.contains { $0.contains(shortVersion) }, "\(readings)")
                }
            }
        }
    }
}
