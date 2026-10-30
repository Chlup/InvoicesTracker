import Foundation
import Testing
@testable import InvoicesTracker

/// The runner that a full-window screen keeps for the one step it waits for: whether it works, and the Czech text of
/// the error it ended in.
@MainActor
struct StepRunnerTests {
    private let label = "kód č. 1 z 17.\u{00A0}10.\u{00A0}2026"

    @Test func aStepThatSucceedsLeavesNoText() async {
        let runner = StepRunner()
        var ran = false

        await runner.perform { ran = true }

        #expect(ran)
        #expect(runner.errorText == nil)
        #expect(!runner.isWorking)
    }

    @Test func aStepWorksWhileItRunsAndAnErrorItEndsInIsToldInCzech() async {
        let runner = StepRunner()
        var workedWhileRunning = false

        await runner.perform(codeLabel: label, forBackup: true) {
            workedWhileRunning = runner.isWorking
            throw KeyError.wrongRecoveryCode
        }

        #expect(workedWhileRunning)
        #expect(!runner.isWorking)
        #expect(runner.errorText == WelcomeTexts.wrongCode(label: label, forBackup: true))
    }

    @Test func aDismissedPromptShowsNothing() async {
        let runner = StepRunner()

        await runner.perform { throw KeyError.userCancelled }

        #expect(runner.errorText == nil)
        #expect(!runner.isWorking)
    }

    @Test func theTextOfAnErrorGoesWhenTheNextStepStartsOrThePersonTypes() async {
        let runner = StepRunner()
        await runner.perform { throw VaultError.busy }
        #expect(runner.errorText == WelcomeTexts.errorText(VaultError.busy, codeLabel: nil, forBackup: false))

        await runner.perform { throw KeyError.userCancelled }
        #expect(runner.errorText == nil)

        await runner.perform { throw VaultError.busy }
        runner.errorText = nil
        #expect(runner.errorText == nil)

        var textWhileRunning: String?
        await runner.perform { throw VaultError.busy }
        await runner.perform { textWhileRunning = runner.errorText }
        #expect(textWhileRunning == nil)
        #expect(runner.errorText == nil)
    }

    /// What a runner reported of the failures of its steps, as the log would have it.
    private final class Reports {
        var steps: [String] = []
        var domainsAndCodes: [String] = []
    }

    private func runner(reporting reports: Reports) -> StepRunner {
        StepRunner(report: { step, error in
            let error = error as NSError
            reports.steps.append(step)
            reports.domainsAndCodes.append("\(error.domain) \(error.code)")
        })
    }

    @Test func aFailureThatTheScreenHasNothingParticularToSayOfIsReportedForTheLog() async {
        let reports = Reports()
        let runner = runner(reporting: reports)

        await runner.perform { throw NSError(domain: "Elsewhere", code: 7) }
        #expect(runner.errorText == WelcomeTexts.genericError)
        #expect(reports.domainsAndCodes == ["Elsewhere 7"])
        #expect(reports.steps.count == 1 && !(reports.steps.first ?? "").isEmpty)

        // A device key that cannot be used is told as the same words, and is reported as well.
        await runner.perform { throw KeyError.deviceKeyUnusable }
        #expect(runner.errorText == WelcomeTexts.genericError)
        #expect(reports.domainsAndCodes.count == 2)
    }

    @Test func aFailureThatTheScreenExplainsIsNotReported() async {
        let reports = Reports()
        let runner = runner(reporting: reports)

        await runner.perform(codeLabel: label, forBackup: false) { throw KeyError.wrongRecoveryCode }
        await runner.perform { throw KeyError.userCancelled }
        await runner.perform { throw VaultError.busy }
        await runner.perform { throw BackupError.notABackup }
        await runner.perform {}

        #expect(reports.steps.isEmpty)
    }

    @Test func aStepStartedWhileAnotherOneRunsDoesNotRun() async {
        let runner = StepRunner()
        let (gate, release) = AsyncStream<Void>.makeStream()
        // The step has begun, and waits for the gate, when its task is made.
        let first = Task.immediate {
            await runner.perform {
                for await _ in gate {
                    break
                }
            }
        }
        #expect(runner.isWorking)
        var secondRan = false

        await runner.perform { secondRan = true }

        #expect(!secondRan)
        #expect(runner.isWorking)

        release.yield()
        await first.value

        #expect(!runner.isWorking)
        #expect(!secondRan)
    }
}
