import AppKit
import SwiftUI

/// A part of the sentence under a key figure, and whether it stands out.
nonisolated struct KeyFigureSentencePart: Sendable, Hashable {
    var text: String

    /// Whether the part is set in semibold text, as the amount in the middle of a sentence is.
    var isEmphasised: Bool
}

/// What a key figure says: the one figure a screen is about, with the small label over it, the share of the income
/// that goes with it, and a sentence on what it is made of. The texts are the builder's; the view only shows them.
nonisolated struct KeyFigureData: Sendable, Hashable {
    /// The small label over the figure, such as "Zbývá zaplatit k 17. 10. 2026". It is set in capitals.
    var eyebrow: String

    /// The figure as it is shown, such as "42 159 Kč".
    var figure: String

    /// The share of the income that goes with the figure, such as "16,7 % z příjmů", or nil for none. It stands on the
    /// line of the figure.
    var share: String?

    /// The sentence under the figure, or nil for none.
    var sentence: String?

    /// A part of `sentence` that is set in semibold text of the colour of text rather than in secondary text, such as
    /// the amount in "navíc k zálohám 252 720 Kč, které platíte průběžně". Nil, or a text that is not in the sentence,
    /// sets the whole sentence alike.
    var sentenceEmphasis: String?

    /// The sentence in the parts it is set in, in order: the part before the emphasis, the emphasis, and the part
    /// after it, of which those that are empty are left out. The whole sentence is one part where there is no
    /// emphasis, and there are none where there is no sentence.
    var sentenceParts: [KeyFigureSentencePart] {
        guard let sentence else { return [] }
        guard let emphasis = sentenceEmphasis, !emphasis.isEmpty, let range = sentence.firstRange(of: emphasis) else {
            return [KeyFigureSentencePart(text: sentence, isEmphasised: false)]
        }
        var parts: [KeyFigureSentencePart] = []
        let before = String(sentence[..<range.lowerBound])
        let after = String(sentence[range.upperBound...])
        if !before.isEmpty {
            parts.append(KeyFigureSentencePart(text: before, isEmphasised: false))
        }
        parts.append(KeyFigureSentencePart(text: emphasis, isEmphasised: true))
        if !after.isEmpty {
            parts.append(KeyFigureSentencePart(text: after, isEmphasised: false))
        }
        return parts
    }
}

/// The spaces a screen gives its key figure around the figure, in points, counted from the line of the figure, which
/// is as tall as its 44 points: from the eyebrow down to that line, and from it down to the sentence. The board has 8
/// and 8, and each screen of the prototype sets its own, by the gap of the column the key figure stands in and the
/// margin above its sentence.
nonisolated struct KeyFigureSpacing: Sendable, Hashable {
    /// The space between the eyebrow and the line of the figure.
    var aboveFigure: CGFloat

    /// The space between the line of the figure and the sentence.
    var belowFigure: CGFloat

    /// The board's key figure, and the Simulátor's: a column 8 points apart.
    static let board = KeyFigureSpacing(aboveFigure: 8, belowFigure: 8)

    /// Přehled: a column 8 points apart, and the sentence 4 points lower (its margin of 4).
    static let overview = KeyFigureSpacing(aboveFigure: 8, belowFigure: 12)

    /// Výpočet: a column 8 points apart, and the sentence 2 points lower (its margin of 2).
    static let computation = KeyFigureSpacing(aboveFigure: 8, belowFigure: 10)

    /// The levies of the year on Odhad odvodů: a column 8 points apart, and the sentence 2 points lower.
    static let prediction = KeyFigureSpacing(aboveFigure: 8, belowFigure: 10)

    /// What is left to settle on Odhad odvodů: a column 6 points apart.
    static let predictionDue = KeyFigureSpacing(aboveFigure: 6, belowFigure: 6)
}

/// The sizes and gaps of a key figure.
private nonisolated enum KeyFigureMetrics {
    /// How far the letters of the figure are pulled up into its line, which the design makes as tall as the figure's
    /// size (`line-height: 1`): half of what the line of the display font is taller than its size, which is what such
    /// a line height leaves out above the letters, and the same again below them (the half-leading). The font keeps
    /// about 52 points of line for its 44 points, for its highest and lowest letters, so this is about 4 points.
    static let figureHalfLeading: CGFloat = {
        let size = Typography.displaySize
        let bold = NSFont.systemFont(ofSize: size, weight: .bold)
        let font = bold.fontDescriptor.withDesign(.rounded).flatMap { NSFont(descriptor: $0, size: size) } ?? bold
        return max(0, (font.ascender - font.descender + font.leading - size) / 2)
    }()

    /// The space between the figure and its share where they stand on one line.
    static let shareGap: CGFloat = 14

    /// The space between the figure and its share where the share has gone under the figure.
    static let shareLineGap: CGFloat = 4

    /// The tracking of the figure: −0.02 em of its 44 points.
    static let figureTracking: CGFloat = -0.88

    /// How far the figure may be scaled down before it is cut, where the room is narrower than it.
    static let minimumFigureScale: CGFloat = 0.6

    /// The widest the sentence is set unless a screen gives it another width, which the initializer of the view takes
    /// (`sentenceMaximumWidth`): 32 em of its 13-point type, so that it does not run to the whole width of a wide
    /// window.
    static let sentenceMaximumWidth: CGFloat = 416
}

/// The key figure of a screen: the eyebrow over it in grey capitals, the figure in the display size with its share on
/// the same baseline, or under it where the room is too narrow for both, and the sentence under them in secondary text,
/// at most `sentenceMaximumWidth` points wide: 416 unless the screen gives it the width its design has. The sentence is
/// set in the body size unless the screen gives it another font, as the Simulátor sets the one line of context under
/// its figure in callout. The figure stands in a line as tall as its size, and the spaces between that line and the
/// eyebrow and the sentence are those the screen gives it (`KeyFigureSpacing`), 8 points each unless it gives others.
/// VoiceOver reads the lot as one phrase.
struct KeyFigureView: View {
    let data: KeyFigureData

    /// The widest the sentence under the figure is set, in points.
    let sentenceMaximumWidth: CGFloat

    /// The font of the sentence under the figure. The part of it that is emphasised is in this font, semibold.
    let sentenceFont: Font

    /// The spaces around the figure that the screen gives it.
    let spacing: KeyFigureSpacing

    /// A key figure that shows `data`, its sentence at most `sentenceMaximumWidth` points wide and set in
    /// `sentenceFont`, with the spaces around the figure of `spacing`.
    init(
        _ data: KeyFigureData, sentenceMaximumWidth: CGFloat = KeyFigureMetrics.sentenceMaximumWidth,
        sentenceFont: Font = Typography.body, spacing: KeyFigureSpacing = .board
    ) {
        self.data = data
        self.sentenceMaximumWidth = sentenceMaximumWidth
        self.sentenceFont = sentenceFont
        self.spacing = spacing
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(verbatim: data.eyebrow)
                .eyebrow()
                .fixedSize(horizontal: false, vertical: true)
            figureLine
                .padding(.top, spacing.aboveFigure)
            if data.sentence != nil {
                Text(sentence)
                    .font(sentenceFont)
                    .foregroundStyle(Palette.text2)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: sentenceMaximumWidth, alignment: .leading)
                    .padding(.top, spacing.belowFigure)
            }
        }
        .accessibilityElement(children: .combine)
    }

    /// The figure, with its share beside it where both fit the room, and under it where they do not.
    @ViewBuilder
    private var figureLine: some View {
        if let share = data.share {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .firstTextBaseline, spacing: KeyFigureMetrics.shareGap) {
                    figure
                    shareText(share)
                }
                // The share stands on the baseline of the figure, inside its line: the line stays 44 points tall,
                // where the share's own line would otherwise reach a tenth of a point below it.
                .frame(height: Typography.displaySize, alignment: .top)
                VStack(alignment: .leading, spacing: KeyFigureMetrics.shareLineGap) {
                    figure
                    shareText(share)
                }
            }
        } else {
            figure
        }
    }

    /// The figure in the display size: on one line, scaled down before it is cut where the room is too narrow, in a
    /// line as tall as its size, as the board sets it (`line-height: 1`). The text keeps the height of its own line,
    /// so the line of 44 points never scales it down; its letters are pulled up by the half-leading and the line ends
    /// 44 points under its top, so the rest of the font's line, under the letters, takes no room.
    private var figure: some View {
        Text(verbatim: data.figure)
            .font(Typography.display)
            .monospacedDigit()
            .tracking(KeyFigureMetrics.figureTracking)
            .lineLimit(1)
            .minimumScaleFactor(KeyFigureMetrics.minimumFigureScale)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.top, -KeyFigureMetrics.figureHalfLeading)
            .frame(height: Typography.displaySize, alignment: .top)
    }

    /// The share of the income, in title 2 semibold and secondary text.
    private func shareText(_ share: String) -> some View {
        Text(verbatim: share)
            .font(Typography.title2.weight(.semibold))
            .monospacedDigit()
            .foregroundStyle(Palette.text2)
    }

    /// The sentence with its emphasis in semibold text of the colour of text.
    private var sentence: AttributedString {
        var sentence = AttributedString()
        for part in data.sentenceParts {
            var run = AttributedString(part.text)
            if part.isEmphasised {
                run.font = sentenceFont.weight(.semibold)
                run.foregroundColor = Palette.text
            }
            sentence.append(run)
        }
        return sentence
    }
}
