import AppKit
import SwiftUI
import Testing
@testable import InvoicesTracker

/// The sheet that opens by itself when the app finds the uniform rates of a year, over whatever the person is doing: a
/// stray Return must not store a table that changes the income of the year, so "Použít" has to be clicked, and Esc puts
/// the decision off. The keys are sent to the sheet in a window as events (`press(_:in:)`). The finding is the table of
/// the instruction D-75 for 2025; the data is invented.
@Suite(.settlesBackups)
@MainActor
struct UniformRateConfirmSheetTests {
    /// An app model whose 2025 has no rates stored, offered the finding for it.
    private func makeApp(in directory: URL) async throws -> (app: AppModel, finding: GFRFinding) {
        let app = makeAppModel(in: directory)
        try await startFresh(app)
        try await #require(app.database).execute("DELETE FROM uniform_rate WHERE year = 2025")
        let finding = try gfrFinding2025()
        await app.offerUniformRate(finding)
        return (app, finding)
    }

    @Test func returnDoesNotStoreTheTableBecauseNoButtonOfTheSheetIsTheDefaultOne() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let (app, finding) = try await makeApp(in: directory)

        let sheet = UniformRateConfirmSheet(app: app, finding: finding)
        try await withHostedView(sheet, size: CGSize(width: 560, height: 480)) { window in
            let taken = try press(.return, in: window)
            await letWaitingJobsRun()

            #expect(!taken)
            #expect(app.uniformRateOffer == finding)
            #expect(app.pendingUniformRate == finding)
            #expect(try await #require(app.database).uniformRates(year: 2025).isEmpty)
        }
    }

    @Test func escPutsTheDecisionOffAndLeavesTheFindingPending() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let (app, finding) = try await makeApp(in: directory)

        let sheet = UniformRateConfirmSheet(app: app, finding: finding)
        try await withHostedView(sheet, size: CGSize(width: 560, height: 480)) { window in
            let taken = try press(.escape, in: window)

            #expect(taken)
            #expect(app.uniformRateOffer == nil)
            #expect(app.pendingUniformRate == finding)
            #expect(try await #require(app.database).uniformRates(year: 2025).isEmpty)
        }
    }
}
