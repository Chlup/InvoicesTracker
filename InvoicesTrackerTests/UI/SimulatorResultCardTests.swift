import AppKit
import SwiftUI
import Testing
@testable import InvoicesTracker

/// The result card of the Simulátor, drawn off-screen in a window of a light and of a dark appearance and read pixel by
/// pixel at two pixels to the point: the net income in the colour of text whether or not the levies are more than the
/// income, with the green dot of the net income before its words, and the hairlines that set the net income and the
/// marginal levy apart from what is above them. Where the parts of the card stand is the business of the window tests
/// (`AppWindowLayoutTests`).
@Suite(.serialized)
@MainActor
struct SimulatorResultCardTests {
    private let schemes = [ColorScheme.light, .dark]

    /// The page of the Simulátor for 2026 with `income` Kč, 60 % flat-rate expenses and a main activity of twelve
    /// months, as the model makes it.
    private func page(income: Int64) throws -> SimulatorPage {
        let choices = SimulatorInput(
            year: 2026, incomeKc: income, expensePercent: 60, activity: .main, healthMinimumExempt: false,
            months: 12, deductions: Deductions(), taxpayerCredit: true,
            family: FamilyYear(year: 2026, children: [], spouse: nil))
        let result = try AppModel.compute(SimulatorBuilder.input(choices), asOf: civilDate("2026-12-31"))
        return SimulatorBuilder.page(result, choices: choices, rateFromSettings: false)
    }

    // MARK: The net income

    /// The net income is set in the colour of text, in a card of the colour of a card: its figure was green, and orange
    /// where the levies are more than the income, but it is the same whatever the sign. Drawn, it has plenty of pixels
    /// of the colour of text, and none of the greens and oranges of text. The dot before its words is the green of the
    /// net income, 8 points across.
    @Test(arguments: [Int64(0), 2_500_000])
    func theNetIncomeIsSetInTheColourOfTextWhateverItsSignAndItsDotIsGreen(income: Int64) throws {
        let net = try page(income: income).summary.netIncome
        #expect(net.amount.hasPrefix("\u{2212}") == (income == 0))

        for scheme in schemes {
            let view = SimulatorNetIncomeView(netIncome: net)
                .frame(width: 320, alignment: .leading)
                .padding(20)
                .background(Palette.bgCard)
            let picture = try OffscreenPicture(of: view, in: scheme)
            let whole = CGRect(origin: .zero, size: picture.size)
            let text = try OffscreenPicture.bytes(of: Palette.text, in: scheme)
            let orangeText = try OffscreenPicture.bytes(of: Palette.orangeText, in: scheme)
            let greenText = try OffscreenPicture.bytes(of: Palette.greenText, in: scheme)
            let orange = try OffscreenPicture.bytes(of: Palette.orange, in: scheme)
            let green = try OffscreenPicture.bytes(of: Palette.green, in: scheme)

            #expect(picture.count(near: text, in: whole, by: 2) > 100, "\(scheme)")
            #expect(picture.count(near: orangeText, in: whole, by: 2) == 0, "\(scheme)")
            #expect(picture.count(near: greenText, in: whole, by: 2) == 0, "\(scheme)")
            #expect(picture.count(near: orange, in: whole, by: 2) == 0, "\(scheme)")
            let dot = try #require(picture.extent(near: green, by: 2), "\(scheme)")
            #expect((7...8.5).contains(dot.width) && (7...8.5).contains(dot.height), "\(scheme): the dot is \(dot)")
            // The dot is at the left edge of the card's content, before the words.
            #expect(abs(dot.minX - 20) <= 1, "\(scheme): the dot is \(dot)")
        }
    }

    /// The figure is set in the title size: in a room where the amount stands beside its words, the strip with the
    /// amount is as tall as the figure in `Typography.title` and the line of the callout under it, 3 points apart, and
    /// not as tall as it would be with the figure in body.
    @Test func theFigureOfTheNetIncomeIsSetInTheTitleSize() throws {
        let net = try page(income: 2_500_000).summary.netIncome
        func height(_ font: Font) -> CGFloat {
            NSHostingView(rootView: Text(verbatim: "Ž").font(font).fixedSize()).fittingSize.height
        }
        let strip = NSHostingView(rootView: SimulatorNetIncomeView(netIncome: net).frame(width: 600)).fittingSize

        // The figure is the tallest of the first line, and the sentence under it is a line of callout 3 points lower.
        let expected = height(Typography.title) + 3 + height(Typography.callout)
        #expect(abs(strip.height - expected) <= 1.5, "\(strip.height) and \(expected)")
    }

    // MARK: The share of the key figure

    /// The share of the key figure, "18,4 %", stands 12 points after the figure in the card of the Simulátor, where the
    /// prototype has a gap of 12 (the board and the other screens that have a share have 14): its letters start 2
    /// points nearer the figure than in a key figure with the spacing of the board, both under the padding of 20.
    @Test func theShareStands12PointsAfterTheFigureInTheCardOfTheSimulator() throws {
        let summary = try page(income: 2_500_000).summary
        let data = summary.keyFigure
        #expect(data.share != nil, "The key figure has no share")
        // The line of the figure: under the padding of 20, the eyebrow and the 8 points of the spacing, 44 points tall.
        let eyebrow = fittingHeight(of: Text(verbatim: data.eyebrow).eyebrow(), width: 320)
        let top = 20 + eyebrow + 8

        for scheme in schemes {
            let text = try OffscreenPicture.bytes(of: Palette.text, in: scheme)
            let text2 = try OffscreenPicture.bytes(of: Palette.text2, in: scheme)
            /// Where the share starts: the left edge of the grey letters in the line of the figure, from 3 points after
            /// the figure, whose soft edge passes through every shade of grey.
            func shareStart(of view: some View) throws -> CGFloat {
                let picture = try OffscreenPicture(of: view.background(Palette.bgCard), in: scheme)
                let line = CGRect(x: 10, y: top, width: picture.size.width - 20, height: 44)
                let figure = try #require(picture.extent(near: text, in: line, by: 3), "\(scheme): no figure")
                let after = CGRect(x: figure.maxX + 3, y: top, width: picture.size.width - figure.maxX - 13, height: 44)
                return try #require(picture.extent(near: text2, in: after, by: 3), "\(scheme): no share").minX
            }
            let card = try shareStart(of: SimulatorResultCard(summary: summary).frame(width: 360))
            let board = try shareStart(
                of: KeyFigureView(data, sentenceFont: Typography.callout, spacing: .board).frame(width: 320)
                    .padding(20))

            #expect(
                abs((board - card) - 2) <= 0.5,
                "\(scheme): the share starts at \(card), with the board's gap at \(board)")
        }
    }

    // MARK: The hairlines

    /// The groups of consecutive `rows` (the y of pixel rows, half a point apart) that are one line each.
    private func lines(in rows: [CGFloat]) -> [[CGFloat]] {
        var found: [[CGFloat]] = []
        for row in rows {
            if let last = found.last?.last, row - last <= 0.75 {
                found[found.count - 1].append(row)
            } else {
                found.append([row])
            }
        }
        return found
    }

    /// The card has two hairlines across its content, a point thick and in the colour of the separators of a card: one
    /// above the net income, one above the marginal levy. The green dot of the net income is between them, and the
    /// last of them is above the bar of the marginal levy, which is the last thing in the card.
    @Test func theCardHasAHairlineAboveTheNetIncomeAndAboveTheMarginalLevyAndNoOther() throws {
        let summary = try page(income: 2_500_000).summary

        for scheme in schemes {
            let card = SimulatorResultCard(summary: summary)
                .frame(width: 360)
                .padding(24)
                .background(Palette.bgWindow)
            let picture = try OffscreenPicture(of: card, in: scheme)
            // Inside the padding of the card, 20 points in from its edges at 24.
            let separator = try OffscreenPicture.bytes(of: Palette.sep, in: scheme)
            let rows = picture.rows(near: separator, from: 44, to: 340, by: 2)
            let found = lines(in: rows)

            #expect(found.count == 2, "\(scheme): \(found)")
            guard found.count == 2 else { continue }
            for line in found {
                // A point is two pixel rows, or three where it lies between pixels.
                #expect((1...1.5).contains(CGFloat(line.count) / 2), "\(scheme): a line of \(line.count) pixel rows")
            }
            let green = try OffscreenPicture.bytes(of: Palette.green, in: scheme)
            let dot = try #require(picture.extent(near: green, by: 2), "\(scheme)")
            #expect(found[0][0] < dot.minY && dot.maxY < found[1][0], "\(scheme): the dot is not between the lines")
            // The marginal levy stands under the last line, with its bar of 8 points in the colour of the tax.
            let tax = try OffscreenPicture.bytes(of: Palette.tax, in: scheme)
            let bar = try #require(picture.extent(near: tax, by: 2), "\(scheme): the bar of the marginal levy")
            #expect(bar.maxY > found[1][0], "\(scheme): the bar of the marginal levy is not under the last line")
        }
    }
}
