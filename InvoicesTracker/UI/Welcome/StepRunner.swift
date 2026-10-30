import Observation

/// Runs the one step a full-window screen waits for — making the data, unlocking, restoring a backup — and keeps what
/// the screen shows of it: whether it works, and the Czech text of the error it ended in.
///
/// One step at a time: a step started while another runs is not run, as the vault would refuse it anyway.
@MainActor
@Observable
final class StepRunner {
    /// Whether a step runs, for the screen to wait and to keep its buttons from starting another one.
    private(set) var isWorking = false

    /// What the screen says of the error the last step ended in, or nil when it ended well or in nothing to say (a
    /// prompt of Touch ID that was dismissed). The screen clears it when the person changes what it was about.
    var errorText: String?

    /// Where a failure that the screen has nothing particular to say of goes, with the step it ended: the person is
    /// told only "Nepodařilo se to dokončit", so the log is what says more. By default the log of the app, which
    /// keeps the domain and the code of the error alone.
    private let report: @MainActor (String, any Error) -> Void

    init(
        report: @escaping @MainActor (String, any Error) -> Void = { step, error in
            AppModel.log(step, failedWith: error)
        }
    ) {
        self.report = report
    }

    /// Runs `step`, and keeps the text of the error it throws (`WelcomeTexts.errorText(_:codeLabel:forBackup:)`), and
    /// reports an error that has no text of its own to say. `codeLabel` names the code that is asked for and
    /// `forBackup` says whether it opens a backup, for a code that does not fit. The text of the step before goes when
    /// this one starts.
    func perform(
        codeLabel: String? = nil,
        forBackup: Bool = false,
        _ step: @MainActor () async throws -> Void
    ) async {
        guard !isWorking else { return }
        isWorking = true
        errorText = nil
        defer { isWorking = false }
        do {
            try await step()
        } catch {
            let text = WelcomeTexts.errorText(error, codeLabel: codeLabel, forBackup: forBackup)
            errorText = text
            if text == WelcomeTexts.genericError {
                report("Running a step of a full-window screen", error)
            }
        }
    }
}
