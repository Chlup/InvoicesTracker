import AppKit
import SwiftUI
import Testing
@testable import InvoicesTracker

/// The shared controls of the V2 design: the colours that pills, notes, links and capsule buttons take from their tone
/// or kind, and the buttons, the segmented control, the filter chip and the notes as VoiceOver reads and presses them
/// in a window.
@Suite(.serialized)
@MainActor
struct DesignControlsTests {
    // MARK: Tones and kinds

    @Test func pillTonesTakeTheTintAndTextOfTheirMeaning() {
        let tones: [(tone: PillTone, background: Color, foreground: Color)] = [
            (.paid, Palette.greenTint, Palette.greenText),
            (.waiting, Palette.accentTint, Palette.accentText),
            (.overdue, Palette.redTint, Palette.redText),
            (.draft, Palette.fill, Palette.text2),
            (.edited, Palette.fill, Palette.text2),
            (.estimate, Palette.orangeTint, Palette.orangeText),
            (.review, Palette.orangeTint, Palette.orangeText),
        ]

        #expect(Set(tones.map(\.tone)).count == 7)
        for entry in tones {
            #expect(entry.tone.background == entry.background, "\(entry.tone) has the wrong background")
            #expect(entry.tone.foreground == entry.foreground, "\(entry.tone) has the wrong text colour")
        }
        // A comparison of colours that held for any two of them would pass the loop above for nothing.
        #expect(PillTone.paid.background != PillTone.overdue.background)
        #expect(PillTone.paid.foreground != PillTone.waiting.foreground)
    }

    @Test func noteTonesTakeTheirTintAndIconColour() {
        let tones: [(tone: NoteTone, background: Color, icon: Color)] = [
            (.info, Palette.accentTint, Palette.accent),
            (.attention, Palette.orangeTint, Palette.orange),
            (.success, Palette.greenTint, Palette.green),
            (.error, Palette.redTint, Palette.red),
        ]

        #expect(Set(tones.map(\.tone)).count == 4)
        for entry in tones {
            #expect(entry.tone.background == entry.background, "\(entry.tone) has the wrong background")
            #expect(entry.tone.iconColor == entry.icon, "\(entry.tone) has the wrong icon colour")
        }
        #expect(NoteTone.info.background != NoteTone.error.background)
        #expect(NoteTone.info.iconColor != NoteTone.success.iconColor)
    }

    @Test func aNoteIconIsTheInfoCircleOrTheWarningTriangleOrNothing() {
        #expect(NoteIcon.info.symbolName == "info.circle")
        #expect(NoteIcon.warning.symbolName == "exclamationmark.triangle")
        #expect(NoteIcon.none.symbolName == nil)
    }

    @Test func capsuleButtonsTakeTheColoursOfTheirKind() {
        let kinds: [(kind: CapsuleButtonKind, background: Color, foreground: Color)] = [
            (.primary, Palette.accent, Palette.onAccent),
            (.secondary, Palette.fill, Palette.text),
            (.onWindow, Palette.bgCard, Palette.text),
            (.destructive, Palette.redTint, Palette.redText),
            (.destructiveConfirm, Palette.red, Palette.onAccent),
        ]

        for entry in kinds {
            #expect(entry.kind.background == entry.background, "\(entry.kind) has the wrong background")
            #expect(entry.kind.foreground == entry.foreground, "\(entry.kind) has the wrong text colour")
        }
        #expect(CapsuleButtonKind.primary.background != CapsuleButtonKind.secondary.background)
        // Only the button on the window background stands off the page.
        #expect(CapsuleButtonKind.onWindow.isRaised)
        #expect(
            [CapsuleButtonKind.primary, .secondary, .destructive, .destructiveConfirm].allSatisfy { !$0.isRaised })
    }

    @Test func aRegularButtonIs32PointsTallAndASmallOne28() {
        #expect(CapsuleButtonSize.regular.height == 32)
        #expect(CapsuleButtonSize.small.height == 28)
        #expect(CapsuleButtonSize.regular.height == DesignMetrics.regularControlHeight)
        #expect(CapsuleButtonSize.small.height == DesignMetrics.smallControlHeight)
    }

    @Test func aLinkTakesTheTextColourOfTheAccentOrOfAnError() {
        #expect(LinkTone.accent.color == Palette.accentText)
        #expect(LinkTone.destructive.color == Palette.redText)
        #expect(LinkTone.accent.color != LinkTone.destructive.color)
    }

    // MARK: Controls in a window

    /// The scopes the segmented control of the tests chooses between.
    enum Scope: Hashable {
        case issued
        case paid
    }

    /// What the segmented control of a test has chosen, which the view that hosts the control watches.
    @MainActor
    @Observable
    final class Choice {
        var scope = Scope.issued
    }

    /// The segmented control "Které faktury" of Faktury, bound to a `Choice`.
    struct ScopeSwitch: View {
        @Bindable var choice: Choice

        var body: some View {
            SegmentedControl(
                "Které faktury", selection: $choice.scope,
                segments: [(value: Scope.issued, title: "Vystavené"), (value: Scope.paid, title: "Zaplacené")]
            )
            .padding(20)
        }
    }

    @Test func theSegmentedControlMarksTheChosenSegmentAndSwitchesOnAClick() async throws {
        let choice = Choice()

        try await withHostedView(ScopeSwitch(choice: choice), size: CGSize(width: 420, height: 120)) { window in
            try await withAccessibilityElements {
                try await waitUntil { accessibilityButton(labelled: "Zaplacené", in: window) != nil }
                // VoiceOver reads the two segments as a group under the name of the control.
                let group = try #require(accessibilityElement(labelled: "Které faktury", in: window))
                #expect(group.accessibilityRole?() == .group)
                let issued = try #require(accessibilityButton(labelled: "Vystavené", in: window))
                let paid = try #require(accessibilityButton(labelled: "Zaplacené", in: window))
                #expect(issued.isAccessibilitySelected?() == true)
                #expect(paid.isAccessibilitySelected?() != true)

                // A click on the other segment, as VoiceOver makes it, changes the binding and moves the mark.
                #expect(paid.accessibilityPerformPress?() == true)
                try await waitUntil { choice.scope == .paid }
                try await waitUntil {
                    accessibilityButton(labelled: "Zaplacené", in: window)?.isAccessibilitySelected?() == true
                }
                #expect(accessibilityButton(labelled: "Vystavené", in: window)?.isAccessibilitySelected?() != true)

                // A click on the segment that is chosen leaves it chosen.
                let chosen = try #require(accessibilityButton(labelled: "Zaplacené", in: window))
                #expect(chosen.accessibilityPerformPress?() == true)
                #expect(choice.scope == .paid)
            }
        }
    }

    @Test func aFilterChipSaysWhetherItIsChosen() async throws {
        var pressed: [String] = []
        let chips = HStack(spacing: 6) {
            FilterChip("Vše 12", isSelected: true) { pressed.append("Vše 12") }
            FilterChip("Koncepty 1", isSelected: false) { pressed.append("Koncepty 1") }
        }
        .padding(20)

        try await withHostedView(chips, size: CGSize(width: 420, height: 120)) { window in
            try await withAccessibilityElements {
                try await waitUntil { accessibilityButton(labelled: "Koncepty 1", in: window) != nil }
                let chosen = try #require(accessibilityButton(labelled: "Vše 12", in: window))
                let other = try #require(accessibilityButton(labelled: "Koncepty 1", in: window))
                #expect(chosen.isAccessibilitySelected?() == true)
                #expect(other.isAccessibilitySelected?() != true)

                #expect(other.accessibilityPerformPress?() == true)
                #expect(pressed == ["Koncepty 1"])
            }
        }
    }

    @Test func theControlsHaveTheHeightsOfTheirSize() async throws {
        let controls = VStack(alignment: .leading, spacing: 12) {
            Button("Uložit") {}
                .buttonStyle(CapsuleButtonStyle(.primary))
            Button("Zrušit") {}
                .buttonStyle(CapsuleButtonStyle(.secondary, size: .small))
            FilterChip("Vše 12", isSelected: true) {}
            ScopeSwitch(choice: Choice())
        }
        .padding(20)

        try await withHostedView(controls, size: CGSize(width: 420, height: 300)) { window in
            try await withAccessibilityElements {
                try await waitUntil { accessibilityButton(labelled: "Vystavené", in: window) != nil }
                @MainActor func height(of label: String) throws -> CGFloat {
                    try #require(accessibilityButton(labelled: label, in: window)?.accessibilityFrame?()).height
                }
                #expect(abs(try height(of: "Uložit") - 32) < 0.5)
                #expect(abs(try height(of: "Zrušit") - 28) < 0.5)
                #expect(abs(try height(of: "Vše 12") - 28) < 0.5)
                // A segment is as tall as a chip, on a track that leaves 2 points around it.
                #expect(abs(try height(of: "Vystavené") - 28) < 0.5)
                let group = try #require(accessibilityElement(labelled: "Které faktury", in: window))
                let track = try #require(group.accessibilityFrame?())
                #expect(abs(track.height - 32) < 0.5)
            }
        }
    }

    @Test func aButtonThatIsDisabledCannotBePressedAndIsReadAsDisabled() async throws {
        var pressed = 0
        let button = Button("Odebrat platbu") { pressed += 1 }
            .buttonStyle(CapsuleButtonStyle(.destructiveConfirm))
            .disabled(true)
            .padding(20)

        try await withHostedView(button, size: CGSize(width: 320, height: 100)) { window in
            try await withAccessibilityElements {
                try await waitUntil { accessibilityButton(labelled: "Odebrat platbu", in: window) != nil }
                let element = try #require(accessibilityButton(labelled: "Odebrat platbu", in: window))
                #expect(element.isAccessibilityEnabled?() == false)
                _ = element.accessibilityPerformPress?()
                #expect(pressed == 0)
            }
        }
    }

    @Test func aLinkIsPressedAndADisabledOneIsNot() async throws {
        var pressed: [String] = []
        let links = HStack(spacing: 16) {
            Button("Odebrat dítě") { pressed.append("Odebrat dítě") }
                .buttonStyle(TextLinkButtonStyle(.destructive))
            Button("Pravidla v Nastavení") { pressed.append("Pravidla v Nastavení") }
                .buttonStyle(TextLinkButtonStyle())
                .disabled(true)
        }
        .padding(20)

        try await withHostedView(links, size: CGSize(width: 420, height: 100)) { window in
            try await withAccessibilityElements {
                try await waitUntil { accessibilityButton(labelled: "Odebrat dítě", in: window) != nil }
                let enabled = try #require(accessibilityButton(labelled: "Odebrat dítě", in: window))
                let disabled = try #require(accessibilityButton(labelled: "Pravidla v Nastavení", in: window))
                #expect(enabled.isAccessibilityEnabled?() != false)
                #expect(disabled.isAccessibilityEnabled?() == false)

                #expect(enabled.accessibilityPerformPress?() == true)
                _ = disabled.accessibilityPerformPress?()
                #expect(pressed == ["Odebrat dítě"])
            }
        }
    }

    // MARK: The notes in a window

    @Test func aWarningIsReadAsOnePhrase() async throws {
        let message = RulesWarning.message(year: 2027, rulesYear: 2026)

        try await withHostedView(RulesWarning(text: message).padding(16), size: CGSize(width: 640, height: 100)) {
            window in
            try await withAccessibilityElements {
                try await waitUntil { showsText(message, in: window) }
                #expect(accessibilityReadings(in: window) == [message])
            }
        }
    }

    @Test func theIconOfANoteIsNotReadAloud() async throws {
        // A note with an action is a group, in which an icon that was not hidden would be an element of its own.
        @MainActor func readings(of icon: NoteIcon) async throws -> [String] {
            var found: [String] = []
            let note = Note(.info, icon: icon, text: "Poznámka") { Button("Zavřít") {} }
            try await withHostedView(note.padding(16), size: CGSize(width: 420, height: 100)) { window in
                try await withAccessibilityElements {
                    try await waitUntil { accessibilityButton(labelled: "Zavřít", in: window) != nil }
                    found = accessibilityReadings(in: window)
                }
            }
            return found
        }

        let withoutIcon = try await readings(of: .none)
        #expect(withoutIcon.contains("Poznámka"))
        #expect(try await readings(of: .info) == withoutIcon)
        #expect(try await readings(of: .warning) == withoutIcon)
    }

    @Test func theBannerShowsItsSentenceAndCloses() async throws {
        let sentence = "Faktura 2026-001 je uložená."
        var closed = 0

        let banner = BannerView(text: sentence) { closed += 1 }
        try await withHostedView(banner.padding(16), size: CGSize(width: 640, height: 100)) { window in
            try await withAccessibilityElements {
                try await waitUntil { showsText(sentence, in: window) }
                let close = try #require(accessibilityButton(labelled: "Zavřít", in: window))
                #expect(close.accessibilityPerformPress?() == true)
                #expect(closed == 1)
            }
        }
    }

    @Test func theNoteAboveACardIsReadAsOnePhraseAndItsButtonIsReachedOnItsOwn() async throws {
        let sentence = "Simulace pro libovolný rok a příjem."
        var restarted = 0

        let notes = VStack(spacing: 12) {
            ComputationBanner(text: sentence)
            ComputationBanner(
                text: "Nic z toho se neukládá.", button: (title: "Začít znovu", action: { restarted += 1 }))
        }
        .padding(16)
        try await withHostedView(notes, size: CGSize(width: 640, height: 200)) { window in
            try await withAccessibilityElements {
                try await waitUntil { accessibilityButton(labelled: "Začít znovu", in: window) != nil }
                // The note without a button is one phrase, and the one with a button is a group that reads its text
                // and holds the button.
                #expect(showsText(sentence, in: window))
                #expect(showsText("Nic z toho se neukládá.", in: window))
                let restart = try #require(accessibilityButton(labelled: "Začít znovu", in: window))
                #expect(restart.accessibilityPerformPress?() == true)
                #expect(restarted == 1)
            }
        }
    }
}
