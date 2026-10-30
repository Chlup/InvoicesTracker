import AppKit
import Foundation
import Testing
import os
@testable import InvoicesTracker

/// What a quit does about the text that was typed in a screen that saves a moment after the last key (Zálohy a
/// odpočty, Nastavení › Moje údaje): the app waits, within a limit, for it to be saved, and only then quits. The
/// data is invented.
@Suite(.settlesBackups)
@MainActor
struct QuitFlushTests {
    /// A model of a screen that saves typed input, which the test controls: whether it holds any, what saving it does,
    /// and how often it was asked to save.
    @MainActor
    private final class FakeSaver: SavesTypedInput {
        var hasUnsavedInput: Bool
        private(set) var saves = 0
        private let gate: Gate?

        /// Called when `saveNow()` starts.
        var onSave: (() -> Void)?

        /// `gate` holds `saveNow()` back until the test opens it.
        init(hasUnsavedInput: Bool = true, gate: Gate? = nil) {
            self.hasUnsavedInput = hasUnsavedInput
            self.gate = gate
        }

        func saveNow() async {
            saves += 1
            onSave?()
            if let gate {
                await gate.pass()
            }
            hasUnsavedInput = false
        }
    }

    /// A wait that never ends by itself, as a long delay does; it ends when its task is cancelled.
    private let waitsForever: @Sendable (Duration) async throws -> Void = { _ in
        try await Task.sleep(for: .seconds(3_600))
    }

    /// A wait that is over as soon as it is asked for, as a delay that has run out.
    private let runsOut: @Sendable (Duration) async throws -> Void = { _ in }

    // MARK: The registry

    @Test func aScreenWithInputThatIsNotSavedMakesTheQuitWait() {
        let flushes = QuitFlushes()
        let idle = FakeSaver(hasUnsavedInput: false)
        let typing = FakeSaver()

        flushes.register(idle)
        #expect(!flushes.hasUnsavedInput)
        flushes.register(typing)
        #expect(flushes.hasUnsavedInput)
    }

    @Test func aScreenThatIsGoneIsForgotten() {
        let flushes = QuitFlushes()
        // The saver lives only as long as this call does, as a screen that is left does.
        func registerAScreenThatGoes() {
            flushes.register(FakeSaver())
        }

        registerAScreenThatGoes()

        #expect(!flushes.hasUnsavedInput)
    }

    @Test func aScreenRegisteredAgainIsSavedOnce() async {
        let flushes = QuitFlushes()
        let typing = FakeSaver()
        flushes.register(typing)
        flushes.register(typing)

        await flushes.flush(within: .seconds(3), sleep: waitsForever)

        #expect(typing.saves == 1)
    }

    @Test func theFlushSavesWhatWaitsAndReturnsWhenItIsWritten() async {
        let flushes = QuitFlushes()
        let first = FakeSaver()
        let second = FakeSaver()
        let idle = FakeSaver(hasUnsavedInput: false)
        flushes.register(first)
        flushes.register(second)
        flushes.register(idle)

        await flushes.flush(within: .seconds(3), sleep: waitsForever)

        #expect(first.saves == 1 && second.saves == 1)
        // A screen with nothing typed has nothing to save.
        #expect(idle.saves == 0)
        #expect(!flushes.hasUnsavedInput)
    }

    @Test(.hangGuard)
    func aSaveThatTakesLongerThanTheLimitIsNotWaitedFor() async {
        let flushes = QuitFlushes()
        let gate = Gate()
        let stuck = FakeSaver(gate: gate)
        flushes.register(stuck)

        // The limit runs out while the save is held back.
        await flushes.flush(within: .seconds(3), sleep: runsOut)

        #expect(stuck.saves == 1)
        #expect(stuck.hasUnsavedInput)

        await gate.open()
        try? await waitUntil { !stuck.hasUnsavedInput }
        #expect(!stuck.hasUnsavedInput)
    }

    @Test func theLimitIsTheOneThatWasAskedFor() async {
        let flushes = QuitFlushes()
        let typing = FakeSaver()
        flushes.register(typing)
        let asked = OSAllocatedUnfairLock(initialState: [Duration]())

        await flushes.flush(
            within: .seconds(3),
            sleep: { limit in
                asked.withLock { $0.append(limit) }
                try await Task.sleep(for: .seconds(3_600))
            })

        #expect(asked.withLock { $0 } == [.seconds(3)])
        #expect(typing.saves == 1)
    }

    @Test func theScreensAreSavedOneAfterTheOtherInTheOrderTheyWereRegisteredIn() async {
        let flushes = QuitFlushes()
        let first = FakeSaver()
        let second = FakeSaver()
        let third = FakeSaver()
        var order: [String] = []
        first.onSave = { order.append("first") }
        second.onSave = { order.append("second") }
        third.onSave = { order.append("third") }
        flushes.register(first)
        flushes.register(second)
        // Registered again, a screen keeps its place.
        flushes.register(first)
        flushes.register(third)

        await flushes.flush(within: .seconds(3), sleep: waitsForever)

        #expect(order == ["first", "second", "third"])
    }

    @Test func aQuitWaitsThreeSecondsAtMostAndABackupOutsideTheMacTwenty() {
        #expect(AppModel.quitFlushLimit == .seconds(3))
        #expect(AppModel.offMacWaitLimit == .seconds(20))
    }

    // MARK: The screens

    @Test func theTextTypedInZalohyAOdpoctyIsSavedByAFlush() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let app = try await makeAdvancesApp(in: directory)
        // The save would come an hour after the last key: only the quit saves it.
        let model = await loadedAdvancesModel(of: app, saveDelay: .seconds(3_600))
        #expect(!app.hasUnsavedInput)

        model.setCell(month: 3, column: 0, text: "13\u{00A0}000")
        #expect(app.hasUnsavedInput)
        #expect(try await storedYear(2026, in: app).advances.social[2] == 13_340)

        await app.flushUnsavedInput()

        #expect(try await storedYear(2026, in: app).advances.social[2] == 13_000)
        #expect(!app.hasUnsavedInput)
    }

    @Test func theTextTypedInTheSupplierTabIsSavedByAFlush() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let app = try await makeSettingsApp(in: directory)
        let model = SupplierTabModel(app: app, saveDelay: .seconds(3_600))
        await model.load()
        #expect(!app.hasUnsavedInput)

        model.setText(.name, "Vzorový dodavatel")
        #expect(app.hasUnsavedInput)
        let database = try #require(app.database)
        #expect(try await database.supplier().name == "")

        await app.flushUnsavedInput()

        #expect(try await database.supplier().name == "Vzorový dodavatel")
        #expect(!app.hasUnsavedInput)
    }

    // MARK: The delegate

    /// The person at the question of a quit, and what the application was told once the quit could go on.
    private final class Quit {
        var answer = false
        var questions = 0
        var replies: [Bool] = []
    }

    private func delegate(of app: AppModel, quit: Quit) -> AppDelegate {
        let delegate = AppDelegate()
        delegate.model = app
        delegate.asksToDiscard = {
            quit.questions += 1
            return quit.answer
        }
        delegate.replyToQuit = { quit.replies.append($0) }
        return delegate
    }

    @Test func quittingWithNothingTypedQuitsAtOnce() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let app = try await makeAdvancesApp(in: directory)
        _ = await loadedAdvancesModel(of: app, saveDelay: .seconds(3_600))
        let quit = Quit()
        let delegate = delegate(of: app, quit: quit)

        #expect(delegate.applicationShouldTerminate(NSApplication.shared) == .terminateNow)
        #expect(quit.replies.isEmpty)
    }

    @Test func quittingWithTextTypedWaitsForItToBeSavedAndThenQuits() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let app = try await makeAdvancesApp(in: directory)
        let model = await loadedAdvancesModel(of: app, saveDelay: .seconds(3_600))
        model.setCell(month: 3, column: 0, text: "13\u{00A0}000")
        let quit = Quit()
        let delegate = delegate(of: app, quit: quit)

        #expect(delegate.applicationShouldTerminate(NSApplication.shared) == .terminateLater)
        // The application is told to go on only once the text is saved.
        #expect(quit.replies.isEmpty)
        await delegate.flush?.value

        #expect(try await storedYear(2026, in: app).advances.social[2] == 13_000)
        #expect(quit.replies == [true])
    }

    @Test(.hangGuard)
    func aSecondQuitWhileTheTextIsBeingSavedStartsNoSecondFlush() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let app = try await makeAdvancesApp(in: directory)
        let gate = Gate()
        let typing = FakeSaver(gate: gate)
        app.quitFlushes.register(typing)
        let quit = Quit()
        let delegate = delegate(of: app, quit: quit)

        #expect(delegate.applicationShouldTerminate(NSApplication.shared) == .terminateLater)
        await gate.untilARequestWaits()
        #expect(delegate.applicationShouldTerminate(NSApplication.shared) == .terminateLater)
        await gate.open()
        await delegate.flush?.value

        #expect(typing.saves == 1)
        #expect(quit.replies == [true])
    }

    /// A second ⌘Q while the first quit waits for the text to be saved asks nothing more: the person has answered for
    /// the invoice that is being written already, and the quit goes on.
    @Test(.hangGuard)
    func aSecondQuitWhileTheTextIsBeingSavedAsksNothingAboutTheInvoice() async throws {
        try await EditorFixture.with { f in
            f.app.startNewInvoice(templateID: f.dollarTemplate.id)
            await f.app.openEditor()
            try #require(f.app.editor).note = "Typed note"
            let gate = Gate()
            let typing = FakeSaver(gate: gate)
            f.app.quitFlushes.register(typing)
            let quit = Quit()
            quit.answer = true
            let delegate = delegate(of: f.app, quit: quit)
            #expect(delegate.applicationShouldTerminate(NSApplication.shared) == .terminateLater)
            #expect(quit.questions == 1)
            await gate.untilARequestWaits()

            quit.answer = false
            #expect(delegate.applicationShouldTerminate(NSApplication.shared) == .terminateLater)

            #expect(quit.questions == 1)
            await gate.open()
            await delegate.flush?.value
            #expect(typing.saves == 1)
            #expect(quit.replies == [true])
        }
    }

    @Test(.hangGuard)
    func aSaveThatNeverEndsDoesNotKeepTheAppFromQuitting() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let gate = Gate()
        // The limit of the quit has run out as soon as it starts.
        let app = makeAppModel(in: directory, sleep: { _ in })
        let stuck = FakeSaver(gate: gate)
        app.quitFlushes.register(stuck)
        let quit = Quit()
        let delegate = delegate(of: app, quit: quit)

        #expect(delegate.applicationShouldTerminate(NSApplication.shared) == .terminateLater)
        await delegate.flush?.value

        #expect(quit.replies == [true])
        await gate.open()
    }

    @Test func theQuestionAboutTheInvoiceComesFirstAndAKeptInvoiceCancelsTheQuitWithoutFlushing() async throws {
        try await EditorFixture.with { f in
            f.app.startNewInvoice(templateID: f.dollarTemplate.id)
            await f.app.openEditor()
            try #require(f.app.editor).note = "Typed note"
            let model = await loadedAdvancesModel(of: f.app, saveDelay: .seconds(3_600))
            model.setCell(month: 3, column: 0, text: "13\u{00A0}000")
            let quit = Quit()
            let delegate = delegate(of: f.app, quit: quit)

            #expect(delegate.applicationShouldTerminate(NSApplication.shared) == .terminateCancel)
            #expect(quit.questions == 1)
            #expect(delegate.flush == nil)
            // The text is still waiting for its moment.
            #expect(f.app.hasUnsavedInput)

            quit.answer = true
            #expect(delegate.applicationShouldTerminate(NSApplication.shared) == .terminateLater)
            #expect(quit.questions == 2)
            await delegate.flush?.value
            #expect(quit.replies == [true])
            #expect(!f.app.hasUnsavedInput)
        }
    }
}
