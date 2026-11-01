import AppKit
import SwiftUI
import Testing
@testable import InvoicesTracker

/// The parts of Výpočet that Odhad odvodů and the Simulátor share, drawn as the design has them: the bar of the three
/// authorities, the marginal levy in its two forms, the card of a limit of the year, and the bill card with its rows.
/// The views are drawn off-screen in a window of a light and of a dark appearance and read pixel by pixel, at two
/// pixels to the point, so a half point is a pixel; the sizes are measured from the views hosted alone.
@Suite(.serialized)
@MainActor
struct ComputationViewsTests {
    // MARK: Helpers

    private let schemes = [ColorScheme.light, .dark]

    /// The bytes of `colour` in a window of `scheme`, drawn as the pictures draw everything.
    private func bytes(_ colour: Color, _ scheme: ColorScheme) throws -> [Int] {
        try OffscreenPicture.bytes(of: colour, in: scheme)
    }

    /// The pixels of the column of `picture` at `x` points, from `top` to `bottom` points, one for each half point.
    private func column(
        of picture: OffscreenPicture, at x: CGFloat, from top: CGFloat, to bottom: CGFloat
    ) -> [[Int]] {
        stride(from: top, to: bottom, by: 0.5).map { picture.bytes(at: CGPoint(x: x, y: $0)) }
    }

    /// Where the first run of at least `length` pixels of `colour` in `pixels` is: the index of its first pixel and
    /// its length, or nil where there is none.
    private func firstRun(of colour: [Int], atLeast length: Int, in pixels: [[Int]]) -> (start: Int, length: Int)? {
        var start = 0
        while start < pixels.count {
            guard isColour(pixels[start], colour) else {
                start += 1
                continue
            }
            var end = start
            while end < pixels.count, isColour(pixels[end], colour) {
                end += 1
            }
            if end - start >= length {
                return (start, end - start)
            }
            start = end
        }
        return nil
    }

    /// The lengths, in pixels, of the runs of `colour` in `pixels`, from the top.
    private func runs(of colour: [Int], in pixels: [[Int]]) -> [Int] {
        var found: [Int] = []
        var length = 0
        for pixel in pixels {
            if isColour(pixel, colour) {
                length += 1
            } else if length > 0 {
                found.append(length)
                length = 0
            }
        }
        if length > 0 {
            found.append(length)
        }
        return found
    }

    /// How many pixels of the whole of `picture` are `colour`.
    private func count(of colour: [Int], in picture: OffscreenPicture) -> Int {
        var found = 0
        for y in stride(from: CGFloat(0), to: picture.size.height, by: 0.5) {
            for x in stride(from: CGFloat(0), to: picture.size.width, by: 0.5)
            where pixelIs(colour, at: CGPoint(x: x, y: y), in: picture) {
                found += 1
            }
        }
        return found
    }

    /// The size `view` takes where it is offered `width`, as it is hosted alone.
    private func fittingSize(of view: some View, width: CGFloat) -> CGSize {
        NSHostingView(rootView: view.frame(width: width)).fittingSize
    }

    /// The height of a line of text set in `font`.
    private func lineHeight(of font: Font) -> CGFloat {
        NSHostingView(rootView: Text(verbatim: "Ž").font(font).fixedSize()).fittingSize.height
    }

    /// The rates of the sample year: tax 15 %, social insurance 16,06 % and health insurance 6,75 % of the next crown.
    private let sampleShares = [
        MarginalShare(authority: .tax, fraction: 0.15),
        MarginalShare(authority: .social, fraction: 0.1606),
        MarginalShare(authority: .health, fraction: 0.0675),
    ]

    /// The engine's regression year, 2026 as of 17. 10., whose marginal levy and limits the tests draw.
    private let sample = TaxEngineRegressionTests.sampleYear2026

    // MARK: The bar of the three authorities

    /// A bar of `shares`, 400 points wide, on a card with 20 points around it: the bar is at 20 points from the left
    /// and the top of the picture, and 8 points high.
    private func bar(_ shares: [MarginalShare]) -> some View {
        AuthorityShareBar(shares: shares)
            .frame(width: 400)
            .padding(20)
            .background(Palette.bgCard)
    }

    @Test func theBarFillsEachPartToItsFractionOfTheWidthAndLeavesTheRestToTheTrack() throws {
        for scheme in schemes {
            let picture = try OffscreenPicture(of: bar(sampleShares), in: scheme)
            let tax = try bytes(Palette.tax, scheme)
            let social = try bytes(Palette.social, scheme)
            let health = try bytes(Palette.health, scheme)
            let track = try bytes(Palette.fill, scheme)
            let middle: CGFloat = 24

            // The parts end at 15 %, 31,06 % and 37,81 % of the 400 points, which are 80, 144,2 and 171,2 points from
            // the left of the picture: the colour changes there, and the track runs on to the end of the bar.
            #expect(pixelIs(tax, at: CGPoint(x: 50, y: middle), in: picture), "\(scheme): the middle of the tax")
            #expect(pixelIs(tax, at: CGPoint(x: 77, y: middle), in: picture), "\(scheme): before the tax ends")
            #expect(pixelIs(social, at: CGPoint(x: 83, y: middle), in: picture), "\(scheme): the social starts")
            #expect(pixelIs(social, at: CGPoint(x: 112, y: middle), in: picture), "\(scheme): the middle of it")
            #expect(pixelIs(social, at: CGPoint(x: 141, y: middle), in: picture), "\(scheme): before it ends")
            #expect(pixelIs(health, at: CGPoint(x: 147, y: middle), in: picture), "\(scheme): the health starts")
            #expect(pixelIs(health, at: CGPoint(x: 168, y: middle), in: picture), "\(scheme): before it ends")
            #expect(pixelIs(track, at: CGPoint(x: 175, y: middle), in: picture), "\(scheme): the track starts")
            #expect(pixelIs(track, at: CGPoint(x: 220, y: middle), in: picture), "\(scheme): the middle of the bar")
            #expect(pixelIs(track, at: CGPoint(x: 410, y: middle), in: picture), "\(scheme): the end of the bar")
        }
    }

    @Test func theBarIsEightPointsHighAndHasRoundedEnds() throws {
        let height = fittingSize(of: AuthorityShareBar(shares: sampleShares), width: 300).height
        #expect(height == 8)

        for scheme in schemes {
            let picture = try OffscreenPicture(of: bar(sampleShares), in: scheme)
            let tax = try bytes(Palette.tax, scheme)
            let card = try bytes(Palette.bgCard, scheme)

            // Eight points are 16 pixels of the column through the middle of a part, whatever is above and below.
            let pixels = column(of: picture, at: 112, from: 0, to: picture.size.height)
            #expect(runs(of: try bytes(Palette.social, scheme), in: pixels) == [16], "\(scheme)")
            // The end of the bar is rounded: a point in from the end, in the middle, is the first part, and the corner
            // is cut away, so it is the card.
            #expect(pixelIs(tax, at: CGPoint(x: 21, y: 24), in: picture), "\(scheme): the middle of the end")
            #expect(pixelIs(card, at: CGPoint(x: 20.25, y: 20.25), in: picture), "\(scheme): the corner is cut")
        }
    }

    @Test func aBarOfNoPartsIsTheTrackAlone() throws {
        let empty = Authority.allCases.map { MarginalShare(authority: $0, fraction: 0) }
        for scheme in schemes {
            let picture = try OffscreenPicture(of: bar(empty), in: scheme)
            let track = try bytes(Palette.fill, scheme)

            for x in [CGFloat(22), 120, 220, 418] {
                #expect(pixelIs(track, at: CGPoint(x: x, y: 24), in: picture), "\(scheme) at \(x)")
            }
        }
    }

    @Test func partsThatAddUpToTheWholeWidthFillTheBarToItsEnd() throws {
        // A bar is of rates, which are parts of the whole width of the bar. Rates that add up to 1 leave no track.
        let whole = [
            MarginalShare(authority: .tax, fraction: 0.25),
            MarginalShare(authority: .social, fraction: 0.5),
            MarginalShare(authority: .health, fraction: 0.25),
        ]
        for scheme in schemes {
            let picture = try OffscreenPicture(of: bar(whole), in: scheme)
            let health = try bytes(Palette.health, scheme)
            let social = try bytes(Palette.social, scheme)

            #expect(pixelIs(social, at: CGPoint(x: 150, y: 24), in: picture), "\(scheme): the half of the bar")
            #expect(pixelIs(health, at: CGPoint(x: 410, y: 24), in: picture), "\(scheme): the end of the bar")
        }
    }

    // MARK: The marginal levy

    @Test func theFullFormIsACardAndTheCompactFormIsASectionWithNoCardLookOfItsOwn() throws {
        let marginal = computationPage(sample).marginal
        // Both stand on the window with 24 points around them, 360 wide. The point 8 points under the top edge and in
        // the middle is in the padding of a card, and in the line of the heading of a section, between its title and
        // its total.
        func picture(compact: Bool, scheme: ColorScheme) throws -> OffscreenPicture {
            let view = MarginalCard(marginal: marginal, compact: compact)
                .frame(width: 360)
                .padding(24)
                .background(Palette.bgWindow)
            return try OffscreenPicture(of: view, in: scheme)
        }

        for scheme in schemes {
            let card = try bytes(Palette.bgCard, scheme)
            let window = try bytes(Palette.bgWindow, scheme)
            let point = CGPoint(x: 24 + 180, y: 24 + 8)
            #expect(!isColour(card, window), "\(scheme): a card is not the colour of the window")

            #expect(pixelIs(card, at: point, in: try picture(compact: false, scheme: scheme)), "\(scheme): card")
            #expect(pixelIs(window, at: point, in: try picture(compact: true, scheme: scheme)), "\(scheme): section")
        }
    }

    @Test func theCompactFormIsSmallerThanTheFullOneByItsPaddingAndItsSmallerTypes() {
        let marginal = computationPage(sample).marginal
        let full = fittingSize(of: MarginalCard(marginal: marginal), width: 360).height
        let compact = fittingSize(of: MarginalCard(marginal: marginal, compact: true), width: 360).height

        // The card has 20 points of padding above and below and 12 between its parts, where the section has 10, and
        // its sentence is body, which is longer than the callout of the section.
        #expect(full - compact >= 40 + 2 * 2, "the card is \(full) high and the section \(compact)")
    }

    @Test func bothFormsAreReadAsAGroupUnderMezniOdvodWithTheHeadingTheTotalAndTheSentence() async throws {
        let marginal = computationPage(sample).marginal
        for compact in [false, true] {
            let view = MarginalCard(marginal: marginal, compact: compact).padding(24)

            try await withHostedView(view, size: CGSize(width: 480, height: 300)) { window in
                try await withAccessibilityElements {
                    try await waitUntil { frameOfCard(labelled: "Mezní odvod", in: window) != nil }
                    let group = try #require(accessibilityElement(labelled: "Mezní odvod", in: window))
                    let readings = accessibilityReadings(under: group)

                    // The group reads under its name, and holds the heading, the total and the sentence, and no bar.
                    #expect(readings == ["Mezní odvod", "Mezní odvod", "37,8\u{00A0}%", marginal.text], "\(compact)")
                }
            }
        }
    }

    // MARK: The limits of the year

    /// The card of `thresholds`, 440 wide with 24 points around it, on the window.
    private func thresholdsPicture(_ thresholds: ComputationThresholds, in scheme: ColorScheme) throws
        -> OffscreenPicture
    {
        let view = ThresholdsCard(thresholds: thresholds)
            .frame(width: 440)
            .padding(24)
            .background(Palette.bgWindow)
        return try OffscreenPicture(of: view, in: scheme)
    }

    @Test func eachLimitHasABarOfSixPointsInItsColourOnTheTrackFilledToItsFraction() throws {
        let thresholds = computationPage(sample).thresholds
        // The cap of the expenses is reached, so its bar is full; the band of 23 % is 47,4 % of the way and the maximum
        // of the social base 23,2 %. The bars are 400 points wide from 44 points, in the card of 440 at 24.
        #expect(thresholds.bars.map(\.authority) == [nil, .tax, .social])
        for scheme in schemes {
            let picture = try thresholdsPicture(thresholds, in: scheme)
            let neutral = try bytes(Palette.text2, scheme)
            let tax = try bytes(Palette.tax, scheme)
            let social = try bytes(Palette.social, scheme)
            let track = try bytes(Palette.fill, scheme)

            // Three bars of 12 pixels, 6 points, one under the other, found at the beginning of the first one.
            let start = column(of: picture, at: 47, from: 24, to: picture.size.height - 24)
            let neutralRuns = runs(of: neutral, in: start).filter { $0 >= 10 }
            let taxRuns = runs(of: tax, in: start).filter { $0 >= 10 }
            let socialRuns = runs(of: social, in: start).filter { $0 >= 10 }
            #expect(neutralRuns == [12], "\(scheme): neutral \(neutralRuns)")
            #expect(taxRuns == [12], "\(scheme): tax \(taxRuns)")
            #expect(socialRuns == [12], "\(scheme): social \(socialRuns)")

            // Where each bar is: the middle of the first run of its colour, in points from the top of the picture.
            func middleOfBar(_ colour: [Int]) throws -> CGFloat {
                let run = try #require(firstRun(of: colour, atLeast: 10, in: start))
                return 24 + CGFloat(run.start * 2 + run.length) / 4
            }
            let y = try [middleOfBar(neutral), middleOfBar(tax), middleOfBar(social)]
            #expect(y[0] < y[1] && y[1] < y[2], "\(scheme): the bars are in order \(y)")

            // The full bar runs to the end, the other two stop at their fractions, 233,5 and 136,8 points from the
            // left of the picture.
            #expect(pixelIs(neutral, at: CGPoint(x: 441, y: y[0]), in: picture), "\(scheme): the cap is full")
            #expect(pixelIs(tax, at: CGPoint(x: 228, y: y[1]), in: picture), "\(scheme): the tax before it ends")
            #expect(pixelIs(track, at: CGPoint(x: 239, y: y[1]), in: picture), "\(scheme): the track after it")
            #expect(pixelIs(social, at: CGPoint(x: 131, y: y[2]), in: picture), "\(scheme): the social before")
            #expect(pixelIs(track, at: CGPoint(x: 142, y: y[2]), in: picture), "\(scheme): the track after it")
        }
    }

    @Test func theValueOfALimitIsGreenOnlyWhereItIsReachedAndTheCapIsTheOneThatCounts() throws {
        // In the sample year the cap of the expenses is reached; with a small income no limit is.
        let reached = computationPage(sample).thresholds
        let far = computationPage(computationYearInput(netHalere: 10_000_150)).thresholds
        #expect(reached.bars.map(\.isHighlighted) == [true, false, false])
        #expect(far.bars.map(\.isHighlighted) == [false, false, false])

        for scheme in schemes {
            let green = try bytes(Palette.greenText, scheme)

            let withGreen = count(of: green, in: try thresholdsPicture(reached, in: scheme))
            let withoutGreen = count(of: green, in: try thresholdsPicture(far, in: scheme))
            #expect(withGreen > 20, "\(scheme): the reached cap is set in green, \(withGreen) pixels")
            #expect(withoutGreen == 0, "\(scheme): no other value is, \(withoutGreen) pixels")
        }
    }

    // MARK: The bill card

    /// A section of three rows, the last of them the total, for the tests of the card of a bill.
    private func billSection(
        authority: Authority? = .tax, isNetIncome: Bool = false, tag: String? = "Finanční úřad"
    ) -> ComputationSection {
        ComputationSection(
            title: "Daň z příjmů",
            rows: [
                ComputationRow(label: "Zisk", value: "991\u{00A0}771,00"),
                ComputationRow(label: "Nezdanitelné části základu", value: "\u{2212}156\u{00A0}480,00", sign: .minus),
                ComputationRow(label: "Základ daně", value: "835\u{00A0}200", sign: .equals, style: .strong),
                ComputationRow(label: "Zbývá", value: "71\u{00A0}440\u{00A0}Kč", sign: .equals, style: .total),
            ],
            authority: authority, tag: tag, isNetIncome: isNetIncome)
    }

    /// The card of `section`, 400 wide with 24 points around it, on the window: the card is at 24 points from the left
    /// and the top, and its content at 44.
    private func billPicture(_ section: ComputationSection, in scheme: ColorScheme) throws -> OffscreenPicture {
        let view = ComputationCard(section: section)
            .frame(width: 400)
            .padding(24)
            .background(Palette.bgWindow)
        return try OffscreenPicture(of: view, in: scheme)
    }

    @Test func theDotBeforeTheTitleIsInTheColourOfTheAuthorityTheGreenOfTheNetIncomeOrTheGreyOfTheIncome() throws {
        let kinds: [(String, ComputationSection, Color)] = [
            ("tax", billSection(authority: .tax), Palette.tax),
            ("social", billSection(authority: .social), Palette.social),
            ("health", billSection(authority: .health), Palette.health),
            ("net income", billSection(authority: nil, isNetIncome: true), Palette.green),
            ("income", billSection(authority: nil), Palette.text2),
        ]
        for scheme in schemes {
            for (name, section, colour) in kinds {
                let picture = try billPicture(section, in: scheme)
                let expected = try bytes(colour, scheme)

                // The dot is 10 points across, from the padding of 20: its column through the middle is 10 points, 20
                // pixels, high, and in the middle of it the dot starts at 44 points.
                let pixels = column(of: picture, at: 49, from: 25, to: 70)
                #expect(runs(of: expected, in: pixels) == [20], "\(scheme) \(name)")
                let run = try #require(firstRun(of: expected, atLeast: 20, in: pixels), "\(scheme) \(name)")
                let middle = 25 + CGFloat(run.start * 2 + run.length) / 4
                #expect(!pixelIs(expected, at: CGPoint(x: 43.5, y: middle), in: picture), "\(scheme) \(name)")
                #expect(pixelIs(expected, at: CGPoint(x: 45, y: middle), in: picture), "\(scheme) \(name)")
            }
        }
    }

    @Test func theRulesAreHairlinesAStrongerOneAboveAResultAndAHeavyOneInTheColourOfTextAboveTheTotal() throws {
        for scheme in schemes {
            let picture = try billPicture(billSection(), in: scheme)

            // The column 2 points in from the content, which holds no text: the rules are the only lines in it. Above
            // the first two rows is the hairline of 1 point, 2 pixels, above the result the stronger one, and above the
            // total the line in the colour of text, 1,5 points, 3 pixels.
            let pixels = column(of: picture, at: 46, from: 26, to: picture.size.height - 26)
            #expect(runs(of: try bytes(Palette.sep, scheme), in: pixels) == [2, 2], "\(scheme): hairlines")
            #expect(runs(of: try bytes(Palette.sepStrong, scheme), in: pixels) == [2], "\(scheme): a result")
            #expect(runs(of: try bytes(Palette.text, scheme), in: pixels) == [3], "\(scheme): the total")
        }
    }

    @Test func theRulesRunFromThePaddingOfTheLeftEdgeToThePaddingOfTheRightEdge() throws {
        for scheme in schemes {
            let picture = try billPicture(billSection(), in: scheme)
            let strong = try bytes(Palette.sepStrong, scheme)
            let card = try bytes(Palette.bgCard, scheme)
            let pixels = column(of: picture, at: 46, from: 26, to: picture.size.height - 26)
            let top = 26 + CGFloat(pixels.firstIndex { isColour($0, strong) } ?? 0) / 2

            // The card is 400 wide from 24, the padding is 20 points: the rule is from 44 to 404.
            #expect(pixelIs(card, at: CGPoint(x: 43.5, y: top), in: picture), "\(scheme): left of the rule")
            #expect(pixelIs(strong, at: CGPoint(x: 44.25, y: top), in: picture), "\(scheme): its beginning")
            #expect(pixelIs(strong, at: CGPoint(x: 403.75, y: top), in: picture), "\(scheme): its end")
            #expect(pixelIs(card, at: CGPoint(x: 404.25, y: top), in: picture), "\(scheme): right of the rule")
        }
    }

    @Test func theCardIsPaddedBy20AboveAndBesideTheHeaderBy10UnderItBy8AboveAndBelowARowAndBy12AtItsFoot() {
        let section = ComputationSection(
            title: "Daň z příjmů", rows: [ComputationRow(label: "Zisk", value: "991\u{00A0}771,00", sign: .minus)],
            authority: .tax, tag: "Finanční úřad")
        let height = fittingSize(of: ComputationCard(section: section), width: 400).height

        // The padding of 20, the header, 10 points, the rule of 1 point, the row of a line with 8 points above and
        // below, and the foot of 12. A hosted view is as high as a whole number of points.
        let expected = 20 + lineHeight(of: Typography.title3) + 10 + 1 + 8 + lineHeight(of: Typography.body) + 8 + 12
        #expect(abs(height - expected) <= 0.5, "the card is \(height) high, not \(expected)")
    }

    @Test func theValueOfATotalIsSetInTitle2AndTheValueOfAnotherRowInBody() {
        func height(of row: ComputationRow) -> CGFloat {
            let section = ComputationSection(title: "Daň", rows: [row], authority: .tax)
            return fittingSize(of: ComputationCard(section: section), width: 400).height
        }

        let plain = height(of: ComputationRow(label: "Zisk", value: "71\u{00A0}440", sign: .minus))
        let total = height(
            of: ComputationRow(label: "Zbývá", value: "71\u{00A0}440\u{00A0}Kč", sign: .equals, style: .total))

        // The row of a line is as high as its tallest text: the value, in title 2 on the total, in body on the others.
        // The rule above the total is half a point thicker. A hosted view is as high as a whole number of points.
        let difference = lineHeight(of: Typography.title2) - lineHeight(of: Typography.body) + 0.5
        #expect(abs(total - plain - difference) <= 0.5, "a total is \(total) high and a plain row \(plain)")
    }
}
