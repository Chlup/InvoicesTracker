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

/// The sizes and gaps of a key figure.
private nonisolated enum KeyFigureMetrics {
    /// The space between the eyebrow, the figure and the sentence.
    static let spacing: CGFloat = 8

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
/// its figure in callout. VoiceOver reads the lot as one phrase.
struct KeyFigureView: View {
    let data: KeyFigureData

    /// The widest the sentence under the figure is set, in points.
    let sentenceMaximumWidth: CGFloat

    /// The font of the sentence under the figure. The part of it that is emphasised is in this font, semibold.
    let sentenceFont: Font

    /// A key figure that shows `data`, its sentence at most `sentenceMaximumWidth` points wide and set in
    /// `sentenceFont`.
    init(
        _ data: KeyFigureData, sentenceMaximumWidth: CGFloat = KeyFigureMetrics.sentenceMaximumWidth,
        sentenceFont: Font = Typography.body
    ) {
        self.data = data
        self.sentenceMaximumWidth = sentenceMaximumWidth
        self.sentenceFont = sentenceFont
    }

    var body: some View {
        VStack(alignment: .leading, spacing: KeyFigureMetrics.spacing) {
            Text(verbatim: data.eyebrow)
                .eyebrow()
                .fixedSize(horizontal: false, vertical: true)
            figureLine
            if data.sentence != nil {
                Text(sentence)
                    .font(sentenceFont)
                    .foregroundStyle(Palette.text2)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: sentenceMaximumWidth, alignment: .leading)
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
                VStack(alignment: .leading, spacing: KeyFigureMetrics.shareLineGap) {
                    figure
                    shareText(share)
                }
            }
        } else {
            figure
        }
    }

    /// The figure in the display size: on one line, scaled down before it is cut.
    private var figure: some View {
        Text(verbatim: data.figure)
            .font(Typography.display)
            .monospacedDigit()
            .tracking(KeyFigureMetrics.figureTracking)
            .lineLimit(1)
            .minimumScaleFactor(KeyFigureMetrics.minimumFigureScale)
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
