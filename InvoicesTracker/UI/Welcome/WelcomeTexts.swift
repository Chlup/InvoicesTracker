import Foundation

/// The words of the first-launch, restore, locked and new-Mac screens that are put together from what the app knows:
/// the code in groups, what a wrong code says, the card of a backup file, the text of every error the screens can end
/// in, the card after unlocking, and when the locks ask. The words that never change are the screens' own.
nonisolated enum WelcomeTexts {
    // MARK: The code

    /// The code in groups of four characters, for the grid that shows it: eight of them for a code the app makes. The
    /// dashes and any spaces of `display` are not part of the groups.
    static func codeGroups(_ display: String) -> [String] {
        let characters = Array(display.filter { $0 != "-" && !$0.isWhitespace })
        return stride(from: 0, to: characters.count, by: groupLength).map {
            String(characters[$0..<min($0 + groupLength, characters.count)])
        }
    }

    private static let groupLength = 4

    /// "Kód č. 1 · vytvořen 17. 10. 2026": the caption over the code of the code step.
    static func codeCaption(number: Int, created: CivilDate) -> String {
        "Kód č. \(number) · vytvořen \(CzechFormat.date(created))"
    }

    /// The label of the field that asks for the code, which names the code that is needed when it is known.
    static func codeFieldLabel(for label: String?) -> String {
        label.map { "Kód pro obnovení – \($0)" } ?? "Kód pro obnovení"
    }

    /// What a code that does not fit says, naming the code that is needed: `label` is such as
    /// "kód č. 1 z 17. 10. 2026", and `forBackup` says whether the code is asked for to open a backup (and not the data
    /// of this Mac).
    static func wrongCode(label: String, forBackup: Bool) -> String {
        let needs = forBackup ? "Tahle záloha potřebuje " : "Tato data potřebují "
        return "Kód nesedí. " + needs + label + " – zkontrolujte ho znak po znaku."
    }

    // MARK: A backup file

    /// The lines of the card of a backup file, in the order they are shown: the name of the file (when `fileName` is
    /// given), when and where the backup was made (the time in `timeZone`, the time zone of the Mac) and what it holds,
    /// on one line joined by " · ", and which code opens it. `opensWithThisMac` says that this Mac opens the backup
    /// itself, so that no code is needed.
    static func backupCard(
        _ header: BackupHeader,
        fileName: String? = nil,
        opensWithThisMac: Bool,
        timeZone: TimeZone = .autoupdatingCurrent
    ) -> [String] {
        var lines = [String]()
        if let fileName {
            lines.append(fileName)
        }
        lines.append(
            backupCreated(header, opensWithThisMac: opensWithThisMac, timeZone: timeZone) + " · "
                + backupContents(header))
        lines.append(backupKey(header, opensWithThisMac: opensWithThisMac))
        return lines
    }

    /// What the backup holds, such as "13 faktur, 3 odběratelé, roky 2024–2026": the invoices, and the clients and the
    /// years when the header has them (a backup from before they were counted has not).
    static func backupContents(_ header: BackupHeader) -> String {
        var parts = [invoiceCount(header.invoiceCount)]
        if let clients = header.clientCount {
            parts.append(clientCount(clients))
        }
        if let years = header.years {
            if years.lowerBound == years.upperBound {
                parts.append("rok \(years.lowerBound)")
            } else {
                parts.append("roky \(years.lowerBound)–\(years.upperBound)")
            }
        }
        return parts.joined(separator: ", ")
    }

    /// The label of the code that opens the backup, such as "kód č. 1 z 17. 10. 2026": the newest recovery code the
    /// backup carries. Nil for a backup that carries none.
    static func backupCodeLabel(_ header: BackupHeader) -> String? {
        header.keys.newestRecoverySlot?.label
    }

    /// "13 faktur", "1 faktura", "2 faktury".
    static func invoiceCount(_ count: Int) -> String {
        counted(count, one: "faktura", few: "faktury", many: "faktur")
    }

    /// "3 odběratelé", "1 odběratel", "5 odběratelů".
    static func clientCount(_ count: Int) -> String {
        counted(count, one: "odběratel", few: "odběratelé", many: "odběratelů")
    }

    /// `count` grouped in thousands, and after it the form of the noun that Czech asks for the number: `one` for 1,
    /// `few` for 2 to 4 and `many` for any other number, 0 included. The two are apart by `separator`: a plain space,
    /// as the lines of these screens have it ("13 faktur"), or a no-break space where the number must stay on the line
    /// of its noun, as in the summary row of Odběratelé ("3 odběratelé", "1 šablona").
    static func counted(_ count: Int, one: String, few: String, many: String, separator: String = " ") -> String {
        let noun =
            switch count {
            case 1: one
            case 2...4: few
            default: many
            }
        return CzechFormat.grouped(Int64(count)) + separator + noun
    }

    /// "vytvořena 16. 10. 2026 ve 21:14 na Macu „Jméno“": the day and the time of the backup in `timeZone`, and the
    /// Mac.
    private static func backupCreated(_ header: BackupHeader, opensWithThisMac: Bool, timeZone: TimeZone) -> String {
        let day = CivilDate.today(now: header.created, timeZone: timeZone)
        let utcSeconds = Int(header.created.timeIntervalSince1970.rounded(.down))
        let localSeconds = utcSeconds + timeZone.secondsFromGMT(for: header.created)
        let secondOfDay = (localSeconds % 86_400 + 86_400) % 86_400
        let hour = secondOfDay / 3600
        let minute = secondOfDay % 3600 / 60
        let time = "\(hour):" + (minute < 10 ? "0" : "") + "\(minute)"
        let place =
            if opensWithThisMac {
                "na tomto Macu"
            } else if header.deviceName.isEmpty {
                "na jiném Macu"
            } else {
                "na Macu „\(header.deviceName)“"
            }
        return "vytvořena \(CzechFormat.date(day)) \(veHours.contains(hour) ? "ve" : "v") \(time) \(place)"
    }

    /// The hours that Czech says with "ve" and not "v": ve dvě, ve tři, ve čtyři, ve dvanáct, ve třináct, ve čtrnáct,
    /// and ve dvacet to ve třiadvacet.
    private static let veHours: Set<Int> = [2, 3, 4, 12, 13, 14, 20, 21, 22, 23]

    /// Which code opens the backup, or that this Mac does.
    private static func backupKey(_ header: BackupHeader, opensWithThisMac: Bool) -> String {
        if opensWithThisMac {
            return "Odemkne ji tento Mac, kód pro obnovení nepotřebujete."
        }
        return backupCodeLabel(header).map { "Odemkne ji \($0)." } ?? "Odemkne ji kód pro obnovení."
    }

    // MARK: Errors

    /// What the screens say when a step ends in `error`, or nil when they say nothing: a prompt of Touch ID or the
    /// password that was dismissed leaves the screen as it was. `codeLabel` names the code the data or the backup needs
    /// (`forBackup`), for a code that does not fit. No text names a path, a code or what the system says of the error.
    static func errorText(_ error: any Error, codeLabel: String?, forBackup: Bool) -> String? {
        switch error {
        case let error as KeyError:
            keyErrorText(error, codeLabel: codeLabel, forBackup: forBackup)
        case let error as VaultError:
            vaultErrorText(error)
        case let error as BackupError:
            backupErrorText(error)
        default:
            genericError
        }
    }

    /// What the screens say of an error they have nothing particular to say of.
    static let genericError = "Nepodařilo se to dokončit. Zkuste to prosím znovu."

    private static func keyErrorText(_ error: KeyError, codeLabel: String?, forBackup: Bool) -> String? {
        switch error {
        case .userCancelled:
            nil
        case .wrongRecoveryCode, .malformedRecoveryCode:
            codeLabel.map { wrongCode(label: $0, forBackup: forBackup) } ?? "Kód nesedí. Zkontrolujte ho znak po znaku."
        case .keysFileDamaged:
            "Soubor s klíči k datům je poškozený, takže se data nedají odemknout."
        case .deviceKeyUnusable, .noDeviceSlot:
            genericError
        }
    }

    /// What the screens say when the vault cannot do what a step asks: "Data jsou zamčená. Nejdřív je odemkněte." for
    /// data that are locked, which a sheet that is open meets when the data are locked under it.
    static func vaultErrorText(_ error: VaultError) -> String {
        switch error {
        case .busy:
            "Aplikace ještě dokončuje jiný krok s daty. Zkuste to za chvíli znovu."
        case .alreadyOpen:
            "Data jsou už odemčená."
        case .noData:
            "Data se nenašla: chybí databáze nebo soubor s klíči k datům."
        case .locked:
            "Data jsou zamčená. Nejdřív je odemkněte."
        case .outdatedCode:
            "Mezitím se změnil kód pro obnovení, proto se nový kód nepoužil. Vytvořte ho prosím znovu."
        }
    }

    private static func backupErrorText(_ error: BackupError) -> String {
        switch error {
        case .notABackup:
            "Tohle není záloha InvoicesTracker, nebo je soubor poškozený."
        case .newerSchema:
            "Tuhle zálohu uložila novější verze aplikace InvoicesTracker. Aktualizujte aplikaci a zkuste to znovu."
        case .folderUnavailable:
            genericError
        }
    }

    // MARK: Data of a newer version

    /// The title of the screen of data that a newer version of the app saved.
    static let newerVersionTitle = "Data jsou z novější verze aplikace"

    /// What that screen advises: updating the app, and not restoring a backup or starting with empty data, which would
    /// not open these data either.
    static let newerVersionText = """
        Tato data uložila novější verze aplikace InvoicesTracker, než je tato. Aktualizujte aplikaci a spusťte ji znovu.
        """

    /// What that screen says of the data: they are untouched, and nothing else needs doing.
    static let newerVersionReassurance = """
        Nic se nesmazalo ani nezměnilo. Zálohu obnovovat ani začínat s prázdnými daty nemusíte – data zůstávají na \
        disku a po aktualizaci se otevřou.
        """

    // MARK: After unlocking

    /// The title of the card after unlocking with the recovery code or restoring a backup.
    static func doneTitle(_ completion: UnlockCompletion) -> String {
        switch completion.kind {
        case .unlocked: "Odemčeno"
        case .restored: "Data jsou obnovená"
        }
    }

    /// What the card says: that this Mac knows the data now, what was opened, and that the code stays valid. `touchID`
    /// says whether the app asks for Touch ID or the password to open the data from now on.
    static func doneText(_ completion: UnlockCompletion, touchID: Bool) -> String {
        let label = completion.codeLabel ?? "kód pro obnovení"
        switch completion.kind {
        case .unlocked:
            let opening = touchID ? "příště je odemkne Touch ID." : "příště se otevřou bez ověření."
            let capitalised = label.prefix(1).uppercased() + label.dropFirst()
            return "Tento Mac si data pamatuje – \(opening) \(capitalised) platí dál."
        case .restored(let created, let invoices, let clients):
            let counts = [invoiceCount(invoices)] + (clients.map { [clientCount($0)] } ?? [])
            let opening = touchID ? "odemyká přes Touch ID" : "otevírá bez ověření"
            return "Otevřela se záloha z \(CzechFormat.date(created)) (\(counts.joined(separator: ", "))). "
                + "Tento Mac ji odteď \(opening) a \(label) platí dál."
        }
    }

    /// The hint under the card: the code that stays valid can be replaced by a new one.
    static let newCodeHint = """
        Chcete raději nový kód pro obnovení? Vytvoříte ho v Nastavení › Zabezpečení a zálohy – data pak dostanou nový \
        klíč.
        """

    // MARK: The locks

    /// The note of the locked screen of a launch: when the app asks for Touch ID or the password — at the launch and
    /// after `time` without activity, or at the launch alone (Nikdy) — and where that is changed.
    static func launchLockNote(_ time: IdleLockTime) -> String {
        let asks = time.afterText.map { "Aplikace se ptá při spuštění a \($0) nečinnosti." }
        return (asks ?? "Aplikace se ptá jen při spuštění.") + " Změníte to v Nastavení › Zabezpečení a zálohy."
    }

    /// "Zamkl se po 10 minutách nečinnosti a data skryl. …": what the card of the lock after inactivity says, with the
    /// time chosen. Under Nikdy the app does not lock; a lock that came before Nikdy was chosen names the default.
    static func idleLockText(_ time: IdleLockTime) -> String {
        let after = (time == .never ? AppSettings().idleLock : time).afterText ?? ""
        return "Zamkl se \(after) nečinnosti a data skryl. Odemknete ho přes Touch ID nebo heslem k tomuto Macu."
    }
}
