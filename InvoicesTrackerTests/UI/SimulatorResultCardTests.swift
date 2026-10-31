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

    /// The bytes of `colour` in a window of `scheme`.
    private func bytes(_ colour: Color, _ scheme: ColorScheme) throws -> [Int] {
        try OffscreenPicture.bytes(of: colour, in: scheme)
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

            #expect(picture.count(near: try bytes(Palette.text, scheme), in: whole, by: 2) > 100, "\(scheme)")
            #expect(picture.count(near: try bytes(Palette.orangeText, scheme), in: whole, by: 2) == 0, "\(scheme)")
            #expect(picture.count(near: try bytes(Palette.greenText, scheme), in: whole, by: 2) == 0, "\(scheme)")
            #expect(picture.count(near: try bytes(Palette.orange, scheme), in: whole, by: 2) == 0, "\(scheme)")
            let dot = try #require(picture.extent(near: try bytes(Palette.green, scheme), by: 2), "\(scheme)")
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
            let rows = picture.rows(near: try bytes(Palette.sep, scheme), from: 44, to: 340, by: 2)
            let found = lines(in: rows)

            #expect(found.count == 2, "\(scheme): \(found)")
            guard found.count == 2 else { continue }
            for line in found {
                // A point is two pixel rows, or three where it lies between pixels.
                #expect((1...1.5).contains(CGFloat(line.count) / 2), "\(scheme): a line of \(line.count) pixel rows")
            }
            let dot = try #require(picture.extent(near: try bytes(Palette.green, scheme), by: 2), "\(scheme)")
            #expect(found[0][0] < dot.minY && dot.maxY < found[1][0], "\(scheme): the dot is not between the lines")
            // The marginal levy stands under the last line, with its bar of 8 points in the colour of the tax.
            let bar = try #require(
                picture.extent(near: try bytes(Palette.tax, scheme), by: 2), "\(scheme): the bar of the marginal levy")
            #expect(bar.maxY > found[1][0], "\(scheme): the bar of the marginal levy is not under the last line")
        }
    }
}
