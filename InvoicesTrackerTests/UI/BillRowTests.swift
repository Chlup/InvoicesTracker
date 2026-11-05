import AppKit
import SwiftUI
import Testing
@testable import InvoicesTracker

/// The row of a bill that Rozpis výpočtu and the calculation cards share (`BillRow`, `BillRows`): what VoiceOver reads
/// for a row, the rule above each row, the green dot of the net income and the size of a value. The rows are drawn
/// off-screen in a window of a light and of a dark appearance and read pixel by pixel, at two pixels to the point, and
/// the sizes are measured from the rows hosted alone. In every expected string `\u{00A0}` is the no-break space.
@Suite(.serialized)
@MainActor
struct BillRowTests {
    // MARK: Helpers

    private let schemes = [ColorScheme.light, .dark]

    /// The picture of `rows` 400 points wide, with 20 points around them, on the colour of a card in `scheme`: the rows
    /// start 20 points from the left and the top.
    private func picture(of rows: [BillRow], in scheme: ColorScheme) throws -> OffscreenPicture {
        let view = BillRows(rows: rows)
            .frame(width: 400)
            .padding(20)
            .background(Palette.bgCard)
        return try OffscreenPicture(of: view, in: scheme)
    }

    /// The pixels of the column of `picture` at `x` points, from its top to its bottom, one for each half point.
    private func column(of picture: OffscreenPicture, at x: CGFloat) -> [[Int]] {
        stride(from: 0, to: picture.size.height, by: 0.5).map { picture.bytes(at: CGPoint(x: x, y: $0)) }
    }

    /// The runs of `colour` in `pixels`, from the top: where each starts, in pixels, and how many pixels it is.
    private func runs(of colour: [Int], in pixels: [[Int]]) -> [(start: Int, length: Int)] {
        var found: [(start: Int, length: Int)] = []
        var start: Int?
        for (index, pixel) in pixels.enumerated() {
            if isColour(pixel, colour) {
                start = start ?? index
            } else if let first = start {
                found.append((start: first, length: index - first))
                start = nil
            }
        }
        if let first = start {
            found.append((start: first, length: pixels.count - first))
        }
        return found
    }

    /// The height of `rows` where they are offered 400 points, as they are hosted alone.
    private func height(of rows: [BillRow]) -> CGFloat {
        NSHostingView(rootView: BillRows(rows: rows).frame(width: 400)).fittingSize.height
    }

    /// The height of a line of text set in `font`.
    private func lineHeight(of font: Font) -> CGFloat {
        NSHostingView(rootView: Text(verbatim: "Ž").font(font).fixedSize()).fittingSize.height
    }

    // MARK: What VoiceOver reads

    @Test func aRowIsReadAsItsLabelWithItsShareItsValueAndItsNote() {
        let row = BillRow(
            label: "Odvody", value: "466\u{00A0}782\u{00A0}Kč",
            note: "daň 114\u{00A0}786 · sociální 247\u{00A0}832 · zdravotní 104\u{00A0}164", sign: .minus,
            share: "17,0\u{00A0}%")

        #expect(
            row.spokenText
                == "Odvody 17,0\u{00A0}%: 466\u{00A0}782\u{00A0}Kč."
                + " daň 114\u{00A0}786 · sociální 247\u{00A0}832 · zdravotní 104\u{00A0}164")
    }

    @Test func thePeriodOfARowIsReadAfterItsLabel() {
        let row = BillRow(
            label: "Průměrně za měsíc", value: "189\u{00A0}698\u{00A0}Kč", sign: .divided,
            period: "·\u{00A0}12\u{00A0}měsíců", marksNetIncome: true)

        #expect(row.spokenText == "Průměrně za měsíc ·\u{00A0}12\u{00A0}měsíců: 189\u{00A0}698\u{00A0}Kč")
    }

    @Test func aRowWithoutTheNewPartsIsReadAsBefore() {
        let row = BillRow(label: "Zisk", value: "991\u{00A0}771,00", note: "po výdajích", sign: .equals, style: .strong)

        #expect(row.spokenText == "Zisk: 991\u{00A0}771,00. po výdajích")
    }

    // MARK: The rules

    /// A calculation of four rows: the first has no rule above it, the subtracted one the hairline, the result the
    /// stronger hairline, and the average that is told to have none has none, although a plain row would have the
    /// hairline. The column 2 points in from the left of the rows lies in the column of the signs, left of any sign,
    /// so the rules are the only lines in it.
    @Test func eachRowStandsUnderItsRuleAndTheFirstUnderNone() throws {
        let rows = [
            BillRow(label: "Příjmy za rok 2026", value: "2\u{00A0}743\u{00A0}157\u{00A0}Kč"),
            BillRow(label: "Odvody", value: "466\u{00A0}782\u{00A0}Kč", sign: .minus),
            BillRow(label: "Čistý příjem", value: "2\u{00A0}276\u{00A0}375\u{00A0}Kč", sign: .equals, style: .strong),
            BillRow(label: "Průměrně za měsíc", value: "189\u{00A0}698\u{00A0}Kč", sign: .divided, rule: .hidden),
        ]
        let first = height(of: [rows[0]])
        let second = height(of: [rows[1]])
        for scheme in schemes {
            let picture = try picture(of: rows, in: scheme)
            let hairline = try OffscreenPicture.bytes(of: Palette.sep, in: scheme)
            let strong = try OffscreenPicture.bytes(of: Palette.sepStrong, in: scheme)
            let text = try OffscreenPicture.bytes(of: Palette.text, in: scheme)
            let pixels = column(of: picture, at: 22)

            let hairlines = runs(of: hairline, in: pixels)
            let strongLines = runs(of: strong, in: pixels)
            #expect(hairlines.map(\.length) == [2], "\(scheme): the hairlines are \(hairlines)")
            #expect(strongLines.map(\.length) == [2], "\(scheme): the stronger lines are \(strongLines)")
            #expect(runs(of: text, in: pixels).isEmpty, "\(scheme): a heavy rule")
            guard let below = hairlines.first, let result = strongLines.first else { continue }
            // The hairline is under the first row, which has none above it, and the stronger one is under the second.
            // A hosted view is as high as a whole number of points, so the rows are up to a point lower.
            let hairlineTop = CGFloat(below.start) / 2
            let strongTop = CGFloat(result.start) / 2
            #expect(
                hairlineTop > 20 + first - 1.5 && hairlineTop < 20 + first + 0.5,
                "\(scheme): the hairline is at \(hairlineTop), the first row \(first) high")
            #expect(
                strongTop - hairlineTop - 1 > second - 1.5 && strongTop - hairlineTop - 1 < second + 0.5,
                "\(scheme): the stronger line is at \(strongTop), the second row \(second) high")
        }
    }

    /// The rules a row can ask for besides the hairlines: the 1-point line in the stronger colour of the separators,
    /// and the heavy one in the colour of text, 1,5 points.
    @Test func aRowCanStandUnderTheStrongerLineOrTheHeavyOne() throws {
        let rows = [
            BillRow(label: "Zálohy na daň", value: "46\u{00A0}000\u{00A0}Kč", rule: .hidden),
            BillRow(label: "Odkládat průměrně za měsíc", value: "20\u{00A0}392\u{00A0}Kč", rule: .separator),
            BillRow(label: "Zbývá", value: "71\u{00A0}440\u{00A0}Kč", rule: .heavy),
        ]
        for scheme in schemes {
            let picture = try picture(of: rows, in: scheme)
            let hairline = try OffscreenPicture.bytes(of: Palette.sep, in: scheme)
            let strong = try OffscreenPicture.bytes(of: Palette.sepStrong, in: scheme)
            let text = try OffscreenPicture.bytes(of: Palette.text, in: scheme)
            let pixels = column(of: picture, at: 22)

            #expect(runs(of: hairline, in: pixels).isEmpty, "\(scheme): a hairline")
            #expect(runs(of: strong, in: pixels).map(\.length) == [2], "\(scheme): the stronger line")
            #expect(runs(of: text, in: pixels).map(\.length) == [3], "\(scheme): the heavy rule")
        }
    }

    /// Rows in a bill card stand each under its rule, the first one too, where it parts them from the header: a plain
    /// row under the hairline, a result under the stronger one and a total under the heavy rule in the colour of text.
    @Test func rowsThatStartWithARuleHaveOneAboveTheFirstRowToo() throws {
        let rows = [
            BillRow(label: "Zisk", value: "991\u{00A0}771,00"),
            BillRow(label: "Základ daně", value: "835\u{00A0}200", sign: .equals, style: .strong),
            BillRow(label: "Zbývá", value: "71\u{00A0}440\u{00A0}Kč", sign: .equals, style: .total),
        ]
        for scheme in schemes {
            let view = BillRows(rows: rows, startsWithRule: true)
                .frame(width: 400)
                .padding(20)
                .background(Palette.bgCard)
            let picture = try OffscreenPicture(of: view, in: scheme)
            let hairline = try OffscreenPicture.bytes(of: Palette.sep, in: scheme)
            let strong = try OffscreenPicture.bytes(of: Palette.sepStrong, in: scheme)
            let text = try OffscreenPicture.bytes(of: Palette.text, in: scheme)
            let pixels = column(of: picture, at: 22)

            let hairlines = runs(of: hairline, in: pixels)
            #expect(hairlines.map(\.length) == [2], "\(scheme): the hairlines are \(hairlines)")
            #expect(hairlines.first.map { CGFloat($0.start) / 2 } == 20, "\(scheme): the first rule")
            #expect(runs(of: strong, in: pixels).map(\.length) == [2], "\(scheme): the result")
            #expect(runs(of: text, in: pixels).map(\.length) == [3], "\(scheme): the total")
        }
    }

    // MARK: The dot of the net income

    /// The row of the net income has a dot of 8 points in its green before its label, after the column of the signs (18
    /// points) and its gap (10): the dot starts 48 points from the left of the picture, where the label of a row
    /// without it starts. The label moves right by the dot and its gap, so no text stands where the dot is.
    @Test func theRowOfTheNetIncomeHasAGreenDotOf8PointsBeforeItsLabel() throws {
        func row(marksNetIncome: Bool) -> BillRow {
            BillRow(
                label: "Průměrně za měsíc", value: "189\u{00A0}698\u{00A0}Kč", sign: .divided,
                period: "·\u{00A0}12\u{00A0}měsíců", marksNetIncome: marksNetIncome)
        }
        for scheme in schemes {
            let green = try OffscreenPicture.bytes(of: Palette.green, in: scheme)
            let text = try OffscreenPicture.bytes(of: Palette.text, in: scheme)
            let marked = try picture(of: [row(marksNetIncome: true)], in: scheme)
            let plain = try picture(of: [row(marksNetIncome: false)], in: scheme)

            let dot = try #require(marked.extent(near: green, by: 6), "\(scheme): no green dot")
            #expect((dot.width - 8).magnitude <= 1, "\(scheme): the dot is \(dot.width) points wide")
            #expect((dot.height - 8).magnitude <= 1, "\(scheme): the dot is \(dot.height) points high")
            #expect((dot.minX - 48).magnitude <= 1, "\(scheme): the dot starts at \(dot.minX)")
            #expect(plain.extent(near: green, by: 6) == nil, "\(scheme): a row that is not marked is green")
            // Where the label of the plain row starts, the marked row has the dot and no text.
            let start = CGRect(x: 47, y: 0, width: 10, height: marked.size.height)
            #expect(plain.count(near: text, in: start, by: 40) > 0, "\(scheme): the plain label")
            #expect(marked.count(near: text, in: start, by: 40) == 0, "\(scheme): text where the dot is")
        }
    }

    // MARK: The value

    /// A row of one line is as high as its tallest text, which is its value: in title 2 bold it is taller than in body
    /// semibold by the difference of their lines.
    @Test func aValueInTitle2BoldIsSetLargerThanOneInBodySemibold() {
        func row(_ style: BillValueStyle) -> BillRow {
            BillRow(label: "Průměrně za měsíc", value: "189\u{00A0}698\u{00A0}Kč", sign: .divided, valueStyle: style)
        }

        let semibold = height(of: [row(.semibold)])
        let title3 = height(of: [row(.title3Bold)])
        let title2 = height(of: [row(.title2Bold)])

        let expected = lineHeight(of: Typography.title2) - lineHeight(of: Typography.bodySemibold)
        #expect(abs(title2 - semibold - expected) <= 1, "title 2: \(title2), body semibold: \(semibold)")
        #expect(title3 > semibold && title3 < title2, "title 3: \(title3)")
    }
}
