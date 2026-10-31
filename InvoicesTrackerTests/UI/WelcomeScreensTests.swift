import AppKit
import SwiftUI
import Testing
@testable import InvoicesTracker

/// The cards before the data is open, shown in a window with the keys a person presses: Esc goes back on the cards of a
/// restore and nowhere else, and what is typed in the field of a recovery code shows in capitals. The keys are sent to
/// the window as events (`press(_:in:)`), so it is the real shortcuts of the buttons that are tried. The card of the
/// supplier's details is read as VoiceOver reads it.
@Suite(.settlesBackups)
@MainActor
struct WelcomeScreensTests {
    /// What the cards were told to do.
    private final class Calls {
        var back = 0
        var submit = 0
    }

    // MARK: Esc

    @Test func escOnTheCardThatChoosesTheBackupGoesBack() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let model = makeAppModel(in: directory)
        let calls = Calls()

        try await withHostedView(RestoreFlowView(model: model, back: { calls.back += 1 })) { window in
            let taken = try press(.escape, in: window)
            #expect(taken)
            #expect(calls.back == 1)
        }
    }

    @Test func escOnTheCardThatAsksForTheCodeOfABackupGoesBack() async throws {
        let calls = Calls()
        let card = RecoveryCodeAsk(
            title: "Odemkněte zálohu", text: "", fieldLabel: "Kód pro obnovení", typed: .constant(""),
            backTitle: "Zpět", back: { calls.back += 1 }, backIsCancel: true, submitTitle: "Odemknout zálohu",
            submit: { calls.submit += 1 }
        ) {
            EmptyView()
        }

        try await withHostedView(card) { window in
            let taken = try press(.escape, in: window)
            #expect(taken)
            #expect(calls.back == 1 && calls.submit == 0)
        }
    }

    /// "Nemám kód" only shows what the person can do without the code: it is no way out that Esc should take.
    @Test func escDoesNotPressTheButtonThatOnlyShowsWhatToDoWithoutACode() async throws {
        let calls = Calls()
        let card = RecoveryCodeAsk(
            title: "Tento Mac data zatím nezná", text: "", fieldLabel: "Kód pro obnovení", typed: .constant(""),
            backTitle: "Nemám kód", back: { calls.back += 1 }, submitTitle: "Odemknout", submit: { calls.submit += 1 }
        ) {
            EmptyView()
        }

        try await withHostedView(card) { window in
            let taken = try press(.escape, in: window)
            #expect(!taken)
            #expect(calls.back == 0)
        }
    }

    // MARK: The pointers to Moje údaje

    /// The card of the supplier's details says twice where the rest of the details are filled in later. The card takes
    /// the focus in its first field, and so the test takes its turn among the tests that type into a window
    /// (`whileTypingAlone`).
    @Test func theCardOfTheSuppliersDetailsPointsToMojeÚdajeWhereTheRestIsFilledIn() async throws {
        try await whileTypingAlone {
            let directory = try makeTemporaryDirectory()
            defer { removeTemporaryDirectory(directory) }
            let model = makeAppModel(in: directory)
            let pointers = [
                "Vytisknou se jako dodavatel na každé faktuře. Všechno můžete později změnit v Nastavení › Moje údaje.",
                "E-mail, telefon, účet v USD nebo v eurech a patičku českých faktur doplníte v Nastavení › Moje údaje.",
            ]

            try await withHostedView(OnboardingView(model: model, step: .supplier)) { window in
                try await withAccessibilityElements {
                    // The card has its elements once the label of its first field is there.
                    try await waitUntil { frameOfText(startingWith: "Jméno nebo název", in: window) != nil }
                    for pointer in pointers {
                        #expect(frameOfText(startingWith: pointer, in: window) != nil, "\(pointer) is not on the card")
                    }
                }
            }
        }
    }

    // MARK: When the app asks for Touch ID

    /// The locked screen of a launch says when the app asks for Touch ID or the password: at the launch, and after the
    /// time without activity that the app keeps outside the data for this screen, which is read before the data is
    /// open; before the app has kept any, after the 10 minutes of the default. The recovery code still opens the data
    /// from here.
    @Test(arguments: [
        (
            IdleLockTime?.none,
            "Aplikace se ptá při spuštění a po 10\u{00A0}minutách nečinnosti. Změníte to v Nastavení › Zabezpečení a"
                + " zálohy."
        ),
        (
            IdleLockTime.oneMinute,
            "Aplikace se ptá při spuštění a po 1\u{00A0}minutě nečinnosti. Změníte to v Nastavení › Zabezpečení a"
                + " zálohy."
        ),
        (IdleLockTime.never, "Aplikace se ptá jen při spuštění. Změníte to v Nastavení › Zabezpečení a zálohy."),
    ])
    func theLockedScreenOfALaunchSaysWhenTheAppAsks(kept: IdleLockTime?, note: String) async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let mirror = MemoryIdleLockMirror()
        if let kept {
            mirror.write(kept)
        }
        let model = makeAppModel(in: directory, idleLockMirror: mirror)

        try await withHostedView(LockedView(model: model)) { window in
            try await withAccessibilityElements {
                try await waitUntil { accessibilityReadings(in: window).contains("InvoicesTracker je zamčený") }
                let readings = accessibilityReadings(in: window)
                #expect(readings.contains(note), "The screen reads \(readings)")
                #expect(readings.contains("Odemknout kódem pro obnovení…"))
            }
        }
    }

    /// The choice of Touch ID on the step of the recovery code says that the app then asks at the launch and after 10
    /// minutes without activity, which Nastavení changes.
    @Test func theCodeStepSaysTheAppAsksAtTheLaunchAndAfterInactivity() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let model = makeAppModel(in: directory)
        let step = OnboardingStep.recoveryCode(
            code: "K7QF-2MWX-HC4T-RWPA-R3DN-6YJE-Q5VB-TL2S", label: "kód č. 1 z 17.\u{00A0}10.\u{00A0}2026", number: 1,
            created: civilDate("2026-10-17"))

        try await withHostedView(OnboardingView(model: model, step: step), size: CGSize(width: 1_000, height: 1_100)) {
            window in
            try await withAccessibilityElements {
                try await waitUntil { accessibilityReadings(in: window).contains("Uložte si kód pro obnovení") }
                let readings = accessibilityReadings(in: window)
                #expect(readings.contains { $0.contains("Odemykat přes Touch ID") })
                #expect(!readings.contains { $0.contains("Při spuštění odemykat přes Touch ID") })
                let note =
                    "Doporučeno. Aplikace se zeptá na Touch ID nebo heslo k Macu při spuštění a po 10\u{00A0}minutách"
                    + " nečinnosti (dobu změníte v Nastavení). Bez Touch ID se otevře bez ověření; data na disku"
                    + " zůstanou šifrovaná."
                #expect(readings.contains { $0.contains(note) }, "The step reads \(readings)")
            }
        }
    }

    // MARK: The cards of the design

    /// The frame of the card of `window` that VoiceOver reads under `label`, in points from the top left of the
    /// content.
    private func cardFrame(_ label: String, in window: NSWindow) throws -> CGRect {
        let frame = try #require(frameOfCard(labelled: label, in: window), "No card \(label)")
        return try pictureFrame(ofScreenFrame: frame, in: window)
    }

    /// The frame of the button of `window` that VoiceOver reads under `label`, in points from the top left.
    private func buttonFrame(_ label: String, in window: NSWindow) throws -> CGRect {
        let frame = try #require(accessibilityButton(labelled: label, in: window)?.accessibilityFrame?(), "No \(label)")
        return try pictureFrame(ofScreenFrame: frame, in: window)
    }

    /// The frame of the first element of `window` whose label starts with `prefix`, in points from the top left.
    private func elementFrame(startingWith prefix: String, in window: NSWindow) throws -> CGRect {
        let element = try #require(accessibilityElement(labelStartingWith: prefix, in: window), "No \(prefix)")
        return try pictureFrame(ofScreenFrame: try #require(element.accessibilityFrame?()), in: window)
    }

    /// The largest difference in a channel between two colours.
    private func distance(_ first: [Int], _ second: [Int]) -> Int {
        zip(first, second).map { abs($0 - $1) }.max() ?? 0
    }

    /// The first launch is the white card of the design on the background of the window, not a material: the card has
    /// the corners of a card, 16 points (a corner of 22 would still be outside at 5 points in), and the window behind
    /// it is `bgWindow`. The tile of the app is a gradient from the accent to the accent text, and the two ways to
    /// begin are inset panels with a ring. The title is the title style, 22 points, and the name is the app's own.
    @Test(arguments: [ColorScheme.light, .dark])
    func theFirstLaunchIsACardOfTheDesignOnTheBackgroundOfTheWindow(scheme: ColorScheme) async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let model = makeAppModel(in: directory)

        try await withHostedView(WelcomeView(model: model), size: CGSize(width: 1_000, height: 800)) { window in
            window.appearance = appearance(of: scheme)
            try await withAccessibilityElements {
                try await waitUntil { frameOfCard(labelled: "Vítejte", in: window) != nil }
                try await layOut(window)
                let card = try cardFrame("Vítejte", in: window)
                let picture = try OffscreenPicture(of: window)
                let background = try OffscreenPicture.bytes(of: Palette.bgWindow, in: scheme)
                let cardColour = try OffscreenPicture.bytes(of: Palette.bgCard, in: scheme)
                let inset = try OffscreenPicture.bytes(of: Palette.bgInset, in: scheme)
                let separator = try OffscreenPicture.bytes(of: Palette.sep, in: scheme)

                #expect(pixelIs(background, at: CGPoint(x: 6, y: 6), in: picture), "\(scheme): the window")
                #expect(pixelIs(cardColour, at: CGPoint(x: card.maxX - 40, y: card.minY + 12), in: picture))
                #expect(!pixelIs(cardColour, at: CGPoint(x: card.minX + 3.5, y: card.minY + 3.5), in: picture))
                #expect(
                    pixelIs(cardColour, at: CGPoint(x: card.minX + 5.5, y: card.minY + 5.5), in: picture),
                    "\(scheme): the corner of the card is rounded by more than 16 points")

                // The tile, 64 points under the top padding of 30, in the middle: the accent at its upper left end
                // of the gradient and the accent text at its lower right end.
                let accent = try OffscreenPicture.bytes(of: Palette.accent, in: scheme)
                let accentText = try OffscreenPicture.bytes(of: Palette.accentText, in: scheme)
                let upper = picture.bytes(at: CGPoint(x: card.midX - 22, y: card.minY + 30 + 12))
                let lower = picture.bytes(at: CGPoint(x: card.midX + 22, y: card.minY + 30 + 52))
                #expect(
                    distance(lower, accentText) < distance(lower, accent),
                    "\(scheme): the lower right of the tile \(lower) is not nearer the accent text than the accent")
                #expect(
                    distance(upper, accent) < distance(upper, accentText),
                    "\(scheme): the upper left of the tile \(upper) is not nearer the accent than the accent text")

                let start = try elementFrame(startingWith: "Začít s prázdnými daty", in: window)
                #expect(pixelIs(inset, at: CGPoint(x: start.minX + 8, y: start.midY), in: picture))
                #expect(pixelIs(separator, at: CGPoint(x: start.minX + 0.5, y: start.midY), in: picture))

                let readings = accessibilityReadings(in: window)
                #expect(readings.contains("Vítejte v InvoicesTracker"), "The card reads \(readings)")
                let backupLine = "Máte zálohu z InvoicesTracker (soubor .ttbackup), třeba z jiného Macu."
                #expect(readings.contains { $0.contains(backupLine) })
                #expect(!readings.contains { $0.contains("TaxesTracker") })
                let heading = try #require(accessibilityElement(labelled: "Vítejte v InvoicesTracker", in: window))
                let title = try #require(heading.accessibilityFrame?())
                let expected = fittingHeight(
                    of: Text(verbatim: "Vítejte v InvoicesTracker").font(Typography.title), width: 900)
                #expect(abs(title.height - expected) < 1.5, "The title is \(title.height) points tall, not \(expected)")
            }
        }
    }

    /// The locked screen of a launch: the lock is a circle on the grey fill, Odemknout is the accent capsule 32 points
    /// tall, and the way to the recovery code is a link in the accent text, where the system colours of a bordered
    /// button and a link were.
    @Test(arguments: [ColorScheme.light, .dark])
    func theLockedScreenHasAFillCircleAnAccentCapsuleAndALinkInTheAccentText(scheme: ColorScheme) async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let model = makeAppModel(in: directory)

        try await withHostedView(LockedView(model: model), size: CGSize(width: 900, height: 700)) { window in
            window.appearance = appearance(of: scheme)
            try await withAccessibilityElements {
                try await waitUntil {
                    accessibilityElement(labelled: "Odemknout kódem pro obnovení…", in: window) != nil
                }
                try await layOut(window)
                let card = try cardFrame("Zamčeno", in: window)
                let picture = try OffscreenPicture(of: window)
                let background = try OffscreenPicture.bytes(of: Palette.bgWindow, in: scheme)
                let cardColour = try OffscreenPicture.bytes(of: Palette.bgCard, in: scheme)
                let fill = try OffscreenPicture.bytes(of: Palette.fill, in: scheme)
                let accent = try OffscreenPicture.bytes(of: Palette.accent, in: scheme)
                let accentText = try OffscreenPicture.bytes(of: Palette.accentText, in: scheme)

                #expect(pixelIs(background, at: CGPoint(x: 6, y: 6), in: picture), "\(scheme): the window")
                #expect(pixelIs(cardColour, at: CGPoint(x: card.maxX - 40, y: card.minY + 12), in: picture))
                // The circle of the lock is 64 points across under the top padding of 30.
                #expect(
                    pixelIs(fill, at: CGPoint(x: card.midX - 26, y: card.minY + 30 + 32), in: picture),
                    "\(scheme): the circle of the lock is not on the grey fill")
                let unlock = try buttonFrame("Odemknout", in: window)
                #expect(abs(unlock.height - 32) < 0.5, "Odemknout is \(unlock.height) points tall")
                #expect(pixelIs(accent, at: CGPoint(x: unlock.minX + 6, y: unlock.midY), in: picture))
                let linkElement = try #require(
                    accessibilityElement(labelled: "Odemknout kódem pro obnovení…", in: window))
                let link = try pictureFrame(ofScreenFrame: try #require(linkElement.accessibilityFrame?()), in: window)
                #expect(
                    picture.count(near: accentText, in: link, by: 6) > 15,
                    "\(scheme): the link is not in the accent text")
            }
        }
    }

    /// The step of the recovery code: the step it is at is the accent circle, the warning is the orange note of the
    /// design, the code is a panel on the inset background with a ring and the groups of the code are on the colour of
    /// a card, its two buttons are capsules 28 points tall and the two at the foot are 32.
    @Test(arguments: [ColorScheme.light, .dark])
    func theStepOfTheRecoveryCodeIsMadeOfTheComponentsOfTheDesign(scheme: ColorScheme) async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let model = makeAppModel(in: directory)
        let step = OnboardingStep.recoveryCode(
            code: "K7QF-2MWX-HC4T-RWPA-R3DN-6YJE-Q5VB-TL2S", label: "kód č. 1 z 17.\u{00A0}10.\u{00A0}2026", number: 1,
            created: civilDate("2026-10-17"))

        try await withHostedView(OnboardingView(model: model, step: step), size: CGSize(width: 1_000, height: 1_200)) {
            window in
            window.appearance = appearance(of: scheme)
            try await withAccessibilityElements {
                try await waitUntil { accessibilityReadings(in: window).contains("Uložte si kód pro obnovení") }
                try await layOut(window)
                let picture = try OffscreenPicture(of: window)
                let accent = try OffscreenPicture.bytes(of: Palette.accent, in: scheme)
                let tint = try OffscreenPicture.bytes(of: Palette.orangeTint, in: scheme)
                let inset = try OffscreenPicture.bytes(of: Palette.bgInset, in: scheme)
                let cardColour = try OffscreenPicture.bytes(of: Palette.bgCard, in: scheme)

                let steps = try #require(frameOfCard(labelled: "Kroky nastavení", in: window))
                let stepsFrame = try pictureFrame(ofScreenFrame: steps, in: window)
                #expect(
                    pixelIs(accent, at: CGPoint(x: stepsFrame.minX + 9, y: stepsFrame.midY - 5), in: picture),
                    "\(scheme): the step the person is at is not the accent circle")
                let warning = try pictureFrame(
                    ofScreenFrame: try #require(frameOfText(startingWith: "Kód nikam neposíláme", in: window)),
                    in: window)
                #expect(
                    pixelIs(tint, at: CGPoint(x: warning.minX + 4, y: warning.minY + 4), in: picture),
                    "\(scheme): the warning is not the orange note of the design, rounded by 10 points")
                let printFrame = try buttonFrame("Vytisknout nebo uložit jako PDF…", in: window)
                let copyFrame = try buttonFrame("Kopírovat", in: window)
                for (label, frame) in [("Vytisknout nebo uložit jako PDF…", printFrame), ("Kopírovat", copyFrame)] {
                    #expect(abs(frame.height - 28) < 0.5, "\(label) is \(frame.height) points tall")
                    #expect(pixelIs(cardColour, at: CGPoint(x: frame.minX + 8, y: frame.midY), in: picture))
                }
                // The panel of the code is on the inset background, 12 points over the buttons of the code.
                #expect(
                    pixelIs(inset, at: CGPoint(x: printFrame.minX - 8, y: printFrame.minY - 14), in: picture),
                    "\(scheme): the panel of the code is not on the inset background")
                for label in ["Zpět", "Pokračovat"] {
                    let height = try buttonFrame(label, in: window).height
                    #expect(abs(height - 32) < 0.5, "\(scheme): \(label) is \(height) points tall")
                }
            }
        }
    }

    /// The card after unlocking: a check in a green circle, a hint on the inset background and Pokračovat as the accent
    /// capsule 32 points tall.
    @Test(arguments: [ColorScheme.light, .dark])
    func theCardAfterUnlockingHasAGreenCircleAnInsetHintAndAnAccentCapsule(scheme: ColorScheme) async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let model = makeAppModel(in: directory)
        let completion = UnlockCompletion(kind: .unlocked, codeLabel: nil)

        try await withHostedView(
            UnlockCompletionView(model: model, completion: completion), size: CGSize(width: 900, height: 700)
        ) { window in
            window.appearance = appearance(of: scheme)
            try await withAccessibilityElements {
                try await waitUntil { accessibilityButton(labelled: "Pokračovat", in: window) != nil }
                try await layOut(window)
                let card = try cardFrame("Hotovo", in: window)
                let picture = try OffscreenPicture(of: window)
                let green = try OffscreenPicture.bytes(of: Palette.greenTint, in: scheme)
                let inset = try OffscreenPicture.bytes(of: Palette.bgInset, in: scheme)
                let accent = try OffscreenPicture.bytes(of: Palette.accent, in: scheme)

                // The circle is 56 points across under the top padding of 30.
                #expect(
                    pixelIs(green, at: CGPoint(x: card.midX - 22, y: card.minY + 30 + 28), in: picture),
                    "\(scheme): the circle is not the green tint")
                let hint = try pictureFrame(
                    ofScreenFrame: try #require(frameOfText(startingWith: "Chcete raději nový kód", in: window)),
                    in: window)
                #expect(
                    pixelIs(inset, at: CGPoint(x: hint.minX - 6, y: hint.midY), in: picture),
                    "\(scheme): the hint is not on the inset background")
                let proceed = try buttonFrame("Pokračovat", in: window)
                #expect(abs(proceed.height - 32) < 0.5, "Pokračovat is \(proceed.height) points tall")
                #expect(pixelIs(accent, at: CGPoint(x: proceed.minX + 6, y: proceed.midY), in: picture))
            }
        }
    }

    /// The drop zone of the choice of the backup is the accent tint with a ring of the soft accent, rounded by 10
    /// points as a panel is: a corner of 14 would still be outside at 3.5 points in, where the ring is.
    @Test(arguments: [ColorScheme.light, .dark])
    func theDropZoneOfTheBackupIsTheAccentTintWithARingOfTheSoftAccent(scheme: ColorScheme) async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let model = makeAppModel(in: directory)

        try await withHostedView(RestoreFlowView(model: model, back: {}), size: CGSize(width: 900, height: 800)) {
            window in
            window.appearance = appearance(of: scheme)
            try await withAccessibilityElements {
                try await waitUntil {
                    accessibilityElement(labelStartingWith: "Vybrat soubor zálohy…", in: window) != nil
                }
                try await layOut(window)
                let zone = try elementFrame(startingWith: "Vybrat soubor zálohy…", in: window)
                let picture = try OffscreenPicture(of: window)
                let tint = try OffscreenPicture.bytes(of: Palette.accentTint, in: scheme)
                let soft = try OffscreenPicture.bytes(of: Palette.accentSoft, in: scheme)

                #expect(
                    pixelIs(tint, at: CGPoint(x: zone.minX + 12, y: zone.midY), in: picture),
                    "\(scheme): the zone is not the accent tint")
                #expect(
                    pixelIs(soft, at: CGPoint(x: zone.minX + 3.5, y: zone.minY + 3.5), in: picture),
                    "\(scheme): the zone has no ring of the soft accent rounded by 10 points")
                // The prototype's "TaxesTracker" is the app's own name here.
                let readings = accessibilityReadings(in: window)
                #expect(readings.contains { $0.contains("Vyberte soubor zálohy InvoicesTracker (.ttbackup).") })
                #expect(!readings.contains { $0.contains("TaxesTracker") })
            }
        }
    }

    /// The panel of "Nemám kód" is on the inset background with no ring, and its two buttons are the capsules of a
    /// card on the window, 28 points tall.
    @Test(arguments: [ColorScheme.light, .dark])
    func thePanelOfNemamKodIsInsetWithTwoCapsulesOfTheCardColour(scheme: ColorScheme) async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let model = makeAppModel(in: directory)

        try await whileTypingAlone {
            try await withHostedView(NewMacView(model: model), size: CGSize(width: 900, height: 900)) { window in
                window.appearance = appearance(of: scheme)
                try await withAccessibilityElements {
                    try await waitUntil { accessibilityButton(labelled: "Nemám kód", in: window) != nil }
                    let noCode = try #require(accessibilityButton(labelled: "Nemám kód", in: window))
                    #expect(noCode.accessibilityPerformPress?() == true)
                    try await waitUntil { accessibilityButton(labelled: "Obnovit ze zálohy…", in: window) != nil }
                    try await layOut(window)
                    let picture = try OffscreenPicture(of: window)
                    let inset = try OffscreenPicture.bytes(of: Palette.bgInset, in: scheme)
                    let cardColour = try OffscreenPicture.bytes(of: Palette.bgCard, in: scheme)
                    let title = try pictureFrame(
                        ofScreenFrame: try #require(
                            frameOfText(startingWith: "Bez kódu se tato data otevřít nedají", in: window)),
                        in: window)
                    #expect(
                        pixelIs(inset, at: CGPoint(x: title.minX - 8, y: title.midY), in: picture),
                        "\(scheme): the panel is not on the inset background")
                    for label in ["Obnovit ze zálohy…", "Začít s prázdnými daty"] {
                        let frame = try buttonFrame(label, in: window)
                        #expect(abs(frame.height - 28) < 0.5, "\(label) is \(frame.height) points tall")
                        #expect(
                            pixelIs(cardColour, at: CGPoint(x: frame.minX + 8, y: frame.midY), in: picture),
                            "\(scheme): \(label) is not a capsule of the card colour")
                    }
                }
            }
        }
    }

    /// The screens that have no counterpart in the prototype take the tokens: the circle of the screen of data from a
    /// newer version is the accent tint, and that of the damaged data the orange tint.
    @Test(arguments: [ColorScheme.light, .dark])
    func theCirclesOfTheScreensWithoutAPrototypeTakeTheTints(scheme: ColorScheme) async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let model = makeAppModel(in: directory)
        let cases: [(label: String, view: AnyView, tint: Color)] = [
            (WelcomeTexts.newerVersionTitle, AnyView(NewerVersionView()), Palette.accentTint),
            (
                "Data se nedají otevřít", AnyView(DamagedDataView(model: model, reason: "Soubory nesedí.")),
                Palette.orangeTint
            ),
        ]

        for entry in cases {
            try await withHostedView(entry.view, size: CGSize(width: 900, height: 800)) { window in
                window.appearance = appearance(of: scheme)
                try await withAccessibilityElements {
                    try await waitUntil { frameOfCard(labelled: entry.label, in: window) != nil }
                    try await layOut(window)
                    let card = try cardFrame(entry.label, in: window)
                    let picture = try OffscreenPicture(of: window)
                    let tint = try OffscreenPicture.bytes(of: entry.tint, in: scheme)
                    #expect(
                        pixelIs(tint, at: CGPoint(x: card.midX - 26, y: card.minY + 30 + 32), in: picture),
                        "\(scheme): the circle of \(entry.label) is not the tint")
                }
            }
        }
    }

    // MARK: The code in capitals

    @Test func theLettersOfATypedCodeShowInCapitals() {
        #expect(RecoveryCodeField.shown("k7qf-2mwx hc4t") == "K7QF-2MWX HC4T")
        #expect(RecoveryCodeField.shown("K7QF") == "K7QF")
        #expect(RecoveryCodeField.shown("") == "")
    }

    /// The number row of a Czech keyboard types ě š č ř ž ý for 2 to 7: they stay as typed, so that they are still read
    /// as the digits, whatever else is changed.
    @Test(arguments: [
        "k7qf-2mwx-hc4t-rwpa", "ěščřžý", "k7qf-ěšč-hc4t", "e\u{030C}s\u{030C}c\u{030C} abc", "0123 o i l", "ABC-xyz",
    ])
    func capitalsChangeNothingOfWhatTheTextIsReadAs(typed: String) {
        #expect(RecoveryCode.normalize(RecoveryCodeField.shown(typed)) == RecoveryCode.normalize(typed))
    }

    @Test func onlyTheLettersOfTheAlphabetAreChanged() {
        #expect(RecoveryCodeField.shown("ěščřžý") == "ěščřžý")
        #expect(RecoveryCodeField.shown("a-b c") == "A-B C")
        #expect(RecoveryCodeField.shown("1é+") == "1é+")
    }
}
