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

    /// The frame `screen` of a view, given in the coordinates of the screen with the origin at its bottom left, as a
    /// picture of `window` counts it: in points from the top left of the content of the window.
    private func pictureFrame(of screen: CGRect, in window: NSWindow) throws -> CGRect {
        let frame = window.convertFromScreen(screen)
        let height = try #require(window.contentView).bounds.height
        return CGRect(x: frame.minX, y: height - frame.maxY, width: frame.width, height: frame.height)
    }

    /// The three answers are the capsules of the design, 32 points tall as the buttons of a dialog are: Použít, the
    /// one that stores the table, in the accent, and Později and Zadat ručně on the grey fill. The headline stands in
    /// the colour of text, with the seal of the finding in the accent in front of it, and the two links of the source
    /// are in the blue of a link.
    @Test(arguments: [ColorScheme.light, .dark])
    func theAnswersAreCapsulesOfTheDesignAndTheSealIsTheAccent(scheme: ColorScheme) async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let (app, finding) = try await makeApp(in: directory)

        let sheet = UniformRateConfirmSheet(app: app, finding: finding)
        try await withHostedView(sheet, size: CGSize(width: 560, height: 480)) { window in
            window.appearance = NSAppearance(named: scheme == .light ? .aqua : .darkAqua)
            try await withAccessibilityElements {
                try await waitUntil { accessibilityButton(labelled: "Použít", in: window) != nil }
                try await layOut(window)
                var frames: [String: CGRect] = [:]
                for title in ["Později", "Zadat ručně", "Použít"] {
                    let screen = try #require(accessibilityButton(labelled: title, in: window)?.accessibilityFrame?())
                    #expect(abs(screen.height - 32) < 0.5, "\(scheme): \(title) is \(screen.height) points tall")
                    frames[title] = try pictureFrame(of: screen, in: window)
                }
                let picture = try OffscreenPicture(of: window)
                let accent = try OffscreenPicture.bytes(of: Palette.accent, in: scheme)
                let fill = try OffscreenPicture.bytes(of: Palette.fill, in: scheme)
                let text = try OffscreenPicture.bytes(of: Palette.text, in: scheme)
                @MainActor func extent(_ colour: [Int], in title: String) throws -> CGRect? {
                    picture.extent(near: colour, in: try #require(frames[title]).insetBy(dx: -2, dy: -2), by: 2)
                }

                #expect(try extent(accent, in: "Použít") != nil, "\(scheme): Použít is not in the accent")
                #expect(try extent(fill, in: "Později") != nil, "\(scheme): Později is not on the grey fill")
                #expect(try extent(fill, in: "Zadat ručně") != nil, "\(scheme): Zadat ručně is not on the grey fill")
                // The headline is text, and the seal in front of it, above the answers, is the accent.
                let top = CGRect(x: 0, y: 0, width: picture.size.width, height: 90)
                #expect(picture.count(near: text, in: top, by: 8) > 100, "\(scheme): the headline is not text")
                #expect(picture.count(near: accent, in: top, by: 8) > 40, "\(scheme): the seal is not the accent")
                // The links stand to the right of "Zdroj:", on its line.
                let source = try pictureFrame(
                    of: try #require(frameOfText(startingWith: "Zdroj:", in: window)), in: window)
                let links = CGRect(
                    x: source.maxX, y: source.minY - 2, width: picture.size.width - source.maxX,
                    height: source.height + 4)
                let blue = try OffscreenPicture.bytes(of: Palette.accentText, in: scheme)
                #expect(
                    picture.count(near: blue, in: links, by: 8) > 100, "\(scheme): the links are not the blue of a link"
                )
            }
        }
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
