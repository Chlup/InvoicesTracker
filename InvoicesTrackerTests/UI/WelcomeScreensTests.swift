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
