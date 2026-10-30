import Foundation
import Testing
@testable import InvoicesTracker

/// The words the first-launch, restore, locked and new-Mac screens put together: the code in groups, what a wrong code
/// says, the card of a backup file, the text of every error and the card after unlocking.
struct WelcomeTextsTests {
    /// The label of the first recovery code, made on 17 October 2026, as the keys file names it.
    private static let label = "kód č. 1 z 17.\u{00A0}10.\u{00A0}2026"

    private static let firstSlot = RecoverySlot(
        number: 1, created: civilDate("2026-10-17"), salt: Data(repeating: 1, count: 16),
        wrappedKey: Data(repeating: 2, count: 40))

    /// The header of a backup of 13 invoices and 3 clients over 2024 to 2026, made at 21:14 on 16 October 2026 in
    /// Prague (19:14 UTC) on another Mac, which the first code opens.
    private func header(
        invoiceCount: Int = 13,
        clientCount: Int? = 3,
        years: ClosedRange<Int>? = 2024...2026,
        created: Date = date("2026-10-16T19:14:00Z"),
        deviceName: String = "Testovací MacBook",
        keys: KeysFile = KeysFile(recoverySlots: [WelcomeTextsTests.firstSlot])
    ) -> BackupHeader {
        BackupHeader(
            created: created, appVersion: "1.0", schemaVersion: Schema.latestVersion, invoiceCount: invoiceCount,
            clientCount: clientCount, years: years, deviceName: deviceName, keys: keys)
    }

    private func zone(_ identifier: String) throws -> TimeZone {
        try #require(TimeZone(identifier: identifier))
    }

    // MARK: The code

    @Test func theCodeIsShownInEightGroupsOfFour() {
        let groups = WelcomeTexts.codeGroups("K7QF-2MWX-HC4T-RWPA-R3DN-6YJE-Q5VB-TL2S")

        #expect(groups.count == 8)
        #expect(groups.first == "K7QF")
        #expect(groups == ["K7QF", "2MWX", "HC4T", "RWPA", "R3DN", "6YJE", "Q5VB", "TL2S"])
    }

    @Test func aCodeWithoutDashesIsGroupedTheSameAndEveryCodeTheAppMakesHasEightGroups() {
        #expect(WelcomeTexts.codeGroups("K7QF2MWXHC4TRWPAR3DN6YJEQ5VBTL2S").count == 8)
        for _ in 0..<20 {
            let code = RecoveryCode.display(RecoveryCode.randomSecret())
            let groups = WelcomeTexts.codeGroups(code)
            #expect(groups.count == 8)
            #expect(groups.joined(separator: "-") == code)
        }
    }

    @Test func theCaptionOfTheCodeNamesItsNumberAndDay() {
        #expect(
            WelcomeTexts.codeCaption(number: 1, created: civilDate("2026-10-17"))
                == "Kód č. 1 · vytvořen 17.\u{00A0}10.\u{00A0}2026")
        #expect(
            WelcomeTexts.codeCaption(number: 12, created: civilDate("2027-01-02"))
                == "Kód č. 12 · vytvořen 2.\u{00A0}1.\u{00A0}2027")
    }

    @Test func theFieldForACodeNamesTheCodeThatIsNeeded() {
        #expect(
            WelcomeTexts.codeFieldLabel(for: Self.label) == "Kód pro obnovení – kód č. 1 z 17.\u{00A0}10.\u{00A0}2026")
        #expect(WelcomeTexts.codeFieldLabel(for: nil) == "Kód pro obnovení")
    }

    // MARK: A wrong code

    @Test func aWrongCodeNamesTheCodeTheDataNeed() {
        #expect(
            WelcomeTexts.wrongCode(label: Self.label, forBackup: false)
                == "Kód nesedí. Tato data potřebují kód č. 1 z 17.\u{00A0}10.\u{00A0}2026 "
                + "– zkontrolujte ho znak po znaku.")
    }

    @Test func aWrongCodeNamesTheCodeTheBackupNeeds() {
        #expect(
            WelcomeTexts.wrongCode(label: Self.label, forBackup: true)
                == "Kód nesedí. Tahle záloha potřebuje kód č. 1 z 17.\u{00A0}10.\u{00A0}2026 "
                + "– zkontrolujte ho znak po znaku.")
    }

    // MARK: The card of a backup file

    @Test func theCardOfABackupFromAnotherMacNamesTheCodeThatOpensIt() {
        let card = WelcomeTexts.backupCard(header(), opensWithThisMac: false)

        #expect(card.contains("Odemkne ji kód č. 1 z 17.\u{00A0}10.\u{00A0}2026."))
    }

    @Test func theCardSaysWhenAndWhereTheBackupWasMadeAndWhatItHoldsOnOneLine() throws {
        let card = WelcomeTexts.backupCard(header(), opensWithThisMac: false, timeZone: try zone("Europe/Prague"))

        #expect(
            card == [
                "vytvořena 16.\u{00A0}10.\u{00A0}2026 ve 21:14 na Macu „Testovací MacBook“"
                    + " · 13 faktur, 3 odběratelé, roky 2024–2026",
                "Odemkne ji kód č. 1 z 17.\u{00A0}10.\u{00A0}2026.",
            ])
    }

    @Test func theCardStartsWithTheNameOfTheFileWhenItHasOne() throws {
        let card = WelcomeTexts.backupCard(
            header(), fileName: "InvoicesTracker 2026-10-16 21-14-00.ttbackup", opensWithThisMac: false,
            timeZone: try zone("Europe/Prague"))

        #expect(card.count == 3)
        #expect(card.first == "InvoicesTracker 2026-10-16 21-14-00.ttbackup")
        #expect(card.last == "Odemkne ji kód č. 1 z 17.\u{00A0}10.\u{00A0}2026.")
    }

    @Test func theTimeAndTheDayAreThoseOfTheTimeZoneOfTheMac() throws {
        // 19:14 UTC is 15:14 in New York, still on 16 October, and 4:14 on the 17th in Tokyo.
        let newYork = WelcomeTexts.backupCard(header(), opensWithThisMac: false, timeZone: try zone("America/New_York"))
        let tokyo = WelcomeTexts.backupCard(header(), opensWithThisMac: false, timeZone: try zone("Asia/Tokyo"))

        #expect(newYork[0].hasPrefix("vytvořena 16.\u{00A0}10.\u{00A0}2026 v 15:14 na Macu „Testovací MacBook“ · "))
        #expect(tokyo[0].hasPrefix("vytvořena 17.\u{00A0}10.\u{00A0}2026 ve 4:14 na Macu „Testovací MacBook“ · "))
    }

    @Test func theTimeTakesVeBeforeTheHoursWhoseNamesStartWithDvTrOrCt() throws {
        let prague = try zone("Europe/Prague")
        func line(at utc: String) -> String {
            WelcomeTexts.backupCard(header(created: date(utc)), opensWithThisMac: false, timeZone: prague)[0]
        }

        // October 2026 is summer time in Prague: UTC+2. Ve dvě, ve tři, ve čtyři, ve dvanáct, ve třináct, ve čtrnáct
        // and ve dvacet to ve třiadvacet; v pět, v devět, v deset, v patnáct and the rest.
        #expect(line(at: "2026-10-15T23:05:00Z").contains(" v 1:05 "))
        #expect(line(at: "2026-10-16T00:05:00Z").contains(" ve 2:05 "))
        #expect(line(at: "2026-10-16T01:05:00Z").contains(" ve 3:05 "))
        #expect(line(at: "2026-10-16T02:05:00Z").contains(" ve 4:05 "))
        #expect(line(at: "2026-10-16T03:05:00Z").contains(" v 5:05 "))
        #expect(line(at: "2026-10-16T07:30:00Z").contains(" v 9:30 "))
        #expect(line(at: "2026-10-16T08:00:00Z").contains(" v 10:00 "))
        #expect(line(at: "2026-10-16T10:00:00Z").contains(" ve 12:00 "))
        #expect(line(at: "2026-10-16T11:00:00Z").contains(" ve 13:00 "))
        #expect(line(at: "2026-10-16T12:59:00Z").contains(" ve 14:59 "))
        #expect(line(at: "2026-10-16T13:00:00Z").contains(" v 15:00 "))
        #expect(line(at: "2026-10-16T14:00:00Z").contains(" v 16:00 "))
        #expect(line(at: "2026-10-16T18:00:00Z").contains(" ve 20:00 "))
        #expect(line(at: "2026-10-16T19:14:00Z").contains(" ve 21:14 "))
        #expect(line(at: "2026-10-16T21:00:00Z").contains(" ve 23:00 "))
        #expect(line(at: "2026-10-16T22:00:00Z").contains(" v 0:00 "))
    }

    @Test func aBackupOfThisMacSaysSoAndNeedsNoCode() throws {
        let card = WelcomeTexts.backupCard(header(), opensWithThisMac: true, timeZone: try zone("Europe/Prague"))

        let made = "vytvořena 16.\u{00A0}10.\u{00A0}2026 ve 21:14 na tomto Macu"
        #expect(card[0] == made + " · 13 faktur, 3 odběratelé, roky 2024–2026")
        #expect(card.last == "Odemkne ji tento Mac, kód pro obnovení nepotřebujete.")
        #expect(!card.contains { $0.contains("Odemkne ji kód") })
    }

    @Test func aBackupWithoutTheNameOfItsMacSaysItWasMadeOnAnotherMac() throws {
        let card = WelcomeTexts.backupCard(
            header(deviceName: ""), opensWithThisMac: false, timeZone: try zone("Europe/Prague"))

        #expect(card[0].hasPrefix("vytvořena 16.\u{00A0}10.\u{00A0}2026 ve 21:14 na jiném Macu · "))
    }

    @Test func aHeaderWithoutTheClientsAndTheYearsShowsTheInvoicesAlone() {
        let card = WelcomeTexts.backupCard(header(clientCount: nil, years: nil), opensWithThisMac: false)

        #expect(card[0].hasSuffix(" · 13 faktur"))
        #expect(card.count == 2)
    }

    @Test func theContentsNameTheClientsAndTheYearsThatTheHeaderHas() {
        #expect(WelcomeTexts.backupContents(header()) == "13 faktur, 3 odběratelé, roky 2024–2026")
        #expect(WelcomeTexts.backupContents(header(years: nil)) == "13 faktur, 3 odběratelé")
        #expect(WelcomeTexts.backupContents(header(clientCount: nil)) == "13 faktur, roky 2024–2026")
        #expect(WelcomeTexts.backupContents(header(years: 2026...2026)) == "13 faktur, 3 odběratelé, rok 2026")
        #expect(
            WelcomeTexts.backupContents(header(invoiceCount: 0, clientCount: 0, years: nil))
                == "0 faktur, 0 odběratelů")
    }

    @Test func theCountsAreInTheFormOfCzechThatTheirNumberAsks() {
        #expect(WelcomeTexts.invoiceCount(0) == "0 faktur")
        #expect(WelcomeTexts.invoiceCount(1) == "1 faktura")
        #expect(WelcomeTexts.invoiceCount(2) == "2 faktury")
        #expect(WelcomeTexts.invoiceCount(4) == "4 faktury")
        #expect(WelcomeTexts.invoiceCount(5) == "5 faktur")
        #expect(WelcomeTexts.invoiceCount(13) == "13 faktur")
        #expect(WelcomeTexts.clientCount(0) == "0 odběratelů")
        #expect(WelcomeTexts.clientCount(1) == "1 odběratel")
        #expect(WelcomeTexts.clientCount(2) == "2 odběratelé")
        #expect(WelcomeTexts.clientCount(4) == "4 odběratelé")
        #expect(WelcomeTexts.clientCount(5) == "5 odběratelů")
        #expect(WelcomeTexts.clientCount(13) == "13 odběratelů")
    }

    @Test func aBackupWithoutARecoverySlotStillSaysThatACodeOpensIt() {
        let card = WelcomeTexts.backupCard(header(keys: KeysFile(recoverySlots: [])), opensWithThisMac: false)

        #expect(card.last == "Odemkne ji kód pro obnovení.")
    }

    @Test func theCodeThatOpensABackupIsTheNewestOneItCarries() {
        let newer = RecoverySlot(
            number: 2, created: civilDate("2026-10-18"), salt: Data(repeating: 3, count: 16),
            wrappedKey: Data(repeating: 4, count: 40))
        let keys = KeysFile(recoverySlots: [Self.firstSlot, newer])

        #expect(WelcomeTexts.backupCodeLabel(header(keys: keys)) == "kód č. 2 z 18.\u{00A0}10.\u{00A0}2026")
        #expect(WelcomeTexts.backupCodeLabel(header()) == Self.label)
        #expect(WelcomeTexts.backupCodeLabel(header(keys: KeysFile(recoverySlots: []))) == nil)
    }

    // MARK: Errors

    struct ErrorText: Sendable {
        let error: any Error
        let text: String?
    }

    static let errorTexts: [ErrorText] = [
        ErrorText(
            error: KeyError.wrongRecoveryCode,
            text: "Kód nesedí. Tato data potřebují kód č. 1 z 17.\u{00A0}10.\u{00A0}2026 "
                + "– zkontrolujte ho znak po znaku."),
        // A text that is not a code gets the same words.
        ErrorText(
            error: KeyError.malformedRecoveryCode,
            text: "Kód nesedí. Tato data potřebují kód č. 1 z 17.\u{00A0}10.\u{00A0}2026 "
                + "– zkontrolujte ho znak po znaku."),
        ErrorText(error: KeyError.userCancelled, text: nil),
        ErrorText(
            error: KeyError.keysFileDamaged,
            text: "Soubor s klíči k datům je poškozený, takže se data nedají odemknout."),
        ErrorText(
            error: VaultError.busy,
            text: "Aplikace ještě dokončuje jiný krok s daty. Zkuste to za chvíli znovu."),
        ErrorText(error: VaultError.alreadyOpen, text: "Data jsou už odemčená."),
        ErrorText(error: VaultError.noData, text: "Data se nenašla: chybí databáze nebo soubor s klíči k datům."),
        ErrorText(error: VaultError.locked, text: "Data jsou zamčená. Nejdřív je odemkněte."),
        ErrorText(
            error: VaultError.outdatedCode,
            text: "Mezitím se změnil kód pro obnovení, proto se nový kód nepoužil. Vytvořte ho prosím znovu."),
        ErrorText(
            error: BackupError.notABackup, text: "Tohle není záloha InvoicesTracker, nebo je soubor poškozený."),
        ErrorText(
            error: BackupError.newerSchema(Schema.latestVersion + 1),
            text: "Tuhle zálohu uložila novější verze aplikace InvoicesTracker. Aktualizujte aplikaci a zkuste to znovu."),
        // Any other error is a short sentence that names nothing: not a path, not a code.
        ErrorText(error: KeyError.deviceKeyUnusable, text: "Nepodařilo se to dokončit. Zkuste to prosím znovu."),
        ErrorText(error: BackupError.folderUnavailable, text: "Nepodařilo se to dokončit. Zkuste to prosím znovu."),
        ErrorText(error: CocoaError(.fileReadNoPermission), text: "Nepodařilo se to dokončit. Zkuste to prosím znovu."),
    ]

    @Test(arguments: errorTexts)
    func everyErrorOfTheScreensHasACzechText(_ item: ErrorText) {
        #expect(WelcomeTexts.errorText(item.error, codeLabel: Self.label, forBackup: false) == item.text)
    }

    @Test func aWrongCodeOfABackupNamesTheBackupAndOneWithoutALabelStillSaysItDoesNotFit() {
        #expect(
            WelcomeTexts.errorText(KeyError.wrongRecoveryCode, codeLabel: Self.label, forBackup: true)
                == "Kód nesedí. Tahle záloha potřebuje kód č. 1 z 17.\u{00A0}10.\u{00A0}2026 "
                + "– zkontrolujte ho znak po znaku.")
        #expect(
            WelcomeTexts.errorText(KeyError.wrongRecoveryCode, codeLabel: nil, forBackup: false)
                == "Kód nesedí. Zkontrolujte ho znak po znaku.")
        #expect(
            WelcomeTexts.errorText(KeyError.malformedRecoveryCode, codeLabel: nil, forBackup: true)
                == "Kód nesedí. Zkontrolujte ho znak po znaku.")
    }

    @Test func noErrorTextShowsACodeAPathOrAnErrorDescription() {
        for item in Self.errorTexts {
            guard let text = WelcomeTexts.errorText(item.error, codeLabel: nil, forBackup: false) else { continue }
            #expect(!text.contains("/"))
            #expect(!text.contains("Error"))
            #expect(!text.contains("error"))
            #expect(!text.contains("\(item.error)"))
        }
    }

    // MARK: Data of a newer version

    @Test func theScreenOfDataFromANewerVersionAdvisesUpdatingTheAppAndNothingElse() {
        #expect(WelcomeTexts.newerVersionTitle == "Data jsou z novější verze aplikace")
        #expect(WelcomeTexts.newerVersionText.contains("Aktualizujte aplikaci"))
        // Nothing was changed, and neither a backup nor empty data would open these data.
        #expect(WelcomeTexts.newerVersionReassurance.hasPrefix("Nic se nesmazalo ani nezměnilo."))
        #expect(WelcomeTexts.newerVersionReassurance.contains("nemusíte"))
    }

    // MARK: The card after unlocking

    @Test func unlockingWithTheCodeEndsInOdemcenoAndNamesTheCodeThatStaysValid() {
        let completion = UnlockCompletion(kind: .unlocked, codeLabel: Self.label)

        #expect(WelcomeTexts.doneTitle(completion) == "Odemčeno")
        #expect(
            WelcomeTexts.doneText(completion, touchID: true)
                == "Tento Mac si data pamatuje – příště je odemkne Touch ID. "
                + "Kód č. 1 z 17.\u{00A0}10.\u{00A0}2026 platí dál.")
    }

    @Test func restoringABackupEndsInDataJsouObnovenaAndSaysWhatWasOpened() {
        let completion = UnlockCompletion(
            kind: .restored(created: civilDate("2026-10-16"), invoiceCount: 13, clientCount: 3), codeLabel: Self.label)

        #expect(WelcomeTexts.doneTitle(completion) == "Data jsou obnovená")
        #expect(
            WelcomeTexts.doneText(completion, touchID: true)
                == "Otevřela se záloha z 16.\u{00A0}10.\u{00A0}2026 (13 faktur, 3 odběratelé). "
                + "Tento Mac ji odteď odemyká přes Touch ID a kód č. 1 z 17.\u{00A0}10.\u{00A0}2026 platí dál.")
    }

    @Test func aRestoredBackupThatDidNotCountItsClientsNamesTheInvoicesAlone() {
        let completion = UnlockCompletion(
            kind: .restored(created: civilDate("2026-10-16"), invoiceCount: 1, clientCount: nil), codeLabel: Self.label)

        #expect(
            WelcomeTexts.doneText(completion, touchID: true)
                .hasPrefix("Otevřela se záloha z 16.\u{00A0}10.\u{00A0}2026 (1 faktura). "))
    }

    @Test func withoutTouchIDTheCardSaysTheDataOpenWithoutAskingForIt() {
        let unlocked = UnlockCompletion(kind: .unlocked, codeLabel: Self.label)
        let restored = UnlockCompletion(
            kind: .restored(created: civilDate("2026-10-16"), invoiceCount: 13, clientCount: 3), codeLabel: Self.label)

        #expect(
            WelcomeTexts.doneText(unlocked, touchID: false)
                == "Tento Mac si data pamatuje – příště se otevřou bez ověření. "
                + "Kód č. 1 z 17.\u{00A0}10.\u{00A0}2026 platí dál.")
        #expect(
            WelcomeTexts.doneText(restored, touchID: false)
                == "Otevřela se záloha z 16.\u{00A0}10.\u{00A0}2026 (13 faktur, 3 odběratelé). "
                + "Tento Mac ji odteď otevírá bez ověření a kód č. 1 z 17.\u{00A0}10.\u{00A0}2026 platí dál.")
    }

    @Test func theCardWithoutALabelStillSaysThatTheCodeStaysValid() {
        let completion = UnlockCompletion(kind: .unlocked, codeLabel: nil)

        #expect(
            WelcomeTexts.doneText(completion, touchID: true)
                == "Tento Mac si data pamatuje – příště je odemkne Touch ID. Kód pro obnovení platí dál.")
    }

    @Test func theHintOffersANewCode() {
        #expect(
            WelcomeTexts.newCodeHint
                == "Chcete raději nový kód pro obnovení? Vytvoříte ho v Nastavení › Zabezpečení a zálohy "
                + "– data pak dostanou nový klíč.")
    }

    // MARK: The locks

    /// The note of the locked screen of a launch: when the app asks, at the launch and after the time without activity,
    /// with a no-break space after its number, or at the launch alone (Nikdy).
    @Test func theLockedScreenOfALaunchSaysWhenTheAppAsks() {
        let change = " Změníte to v Nastavení › Zabezpečení a zálohy."

        #expect(
            WelcomeTexts.launchLockNote(.tenMinutes)
                == "Aplikace se ptá při spuštění a po 10\u{00A0}minutách nečinnosti." + change)
        #expect(
            WelcomeTexts.launchLockNote(.oneMinute)
                == "Aplikace se ptá při spuštění a po 1\u{00A0}minutě nečinnosti." + change)
        #expect(
            WelcomeTexts.launchLockNote(.oneHour)
                == "Aplikace se ptá při spuštění a po 1\u{00A0}hodině nečinnosti." + change)
        #expect(WelcomeTexts.launchLockNote(.never) == "Aplikace se ptá jen při spuštění." + change)
    }

    /// What the card of the lock after inactivity says: after how long it locked. Under Nikdy the app does not lock;
    /// a lock that came before Nikdy was chosen names the 10 minutes of the default.
    @Test func theCardOfTheLockAfterInactivitySaysAfterHowLongItLocked() {
        let unlock = " nečinnosti a data skryl. Odemknete ho přes Touch ID nebo heslem k tomuto Macu."

        #expect(WelcomeTexts.idleLockText(.tenMinutes) == "Zamkl se po 10\u{00A0}minutách" + unlock)
        #expect(WelcomeTexts.idleLockText(.fiveMinutes) == "Zamkl se po 5\u{00A0}minutách" + unlock)
        #expect(WelcomeTexts.idleLockText(.oneHour) == "Zamkl se po 1\u{00A0}hodině" + unlock)
        #expect(WelcomeTexts.idleLockText(.never) == "Zamkl se po 10\u{00A0}minutách" + unlock)
    }
}
