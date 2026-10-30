import SwiftUI

/// What a pill says, which decides its colours. The tone is a plain value; the colours it stands for (`background`,
/// `foreground`) come from the palette and are on the main actor, like the views.
nonisolated enum PillTone: Sendable, Hashable {
    /// An invoice that is paid, in green.
    case paid

    /// An invoice that waits for its payment, in blue.
    case waiting

    /// An invoice that is overdue, in red.
    case overdue

    /// A draft, in grey.
    case draft

    /// A figure that is an estimate, in orange.
    case estimate

    /// A figure the person has changed by hand, in grey.
    case edited

    /// An invoice that needs to be checked, in the orange of attention.
    case review
}

/// The colours of the tones of a pill, from the palette.
extension PillTone {
    /// The tint behind the text of the pill.
    var background: Color {
        switch self {
        case .paid: Palette.greenTint
        case .waiting: Palette.accentTint
        case .overdue: Palette.redTint
        case .draft, .edited: Palette.fill
        case .estimate, .review: Palette.orangeTint
        }
    }

    /// The colour of the text of the pill.
    var foreground: Color {
        switch self {
        case .paid: Palette.greenText
        case .waiting: Palette.accentText
        case .overdue: Palette.redText
        case .draft, .edited: Palette.text2
        case .estimate, .review: Palette.orangeText
        }
    }
}

/// A short word in a tinted capsule, such as the state of an invoice: the subheadline in semibold, on one line, with 8
/// points at the sides and 2 above and below.
struct Pill: View {
    let text: String
    let tone: PillTone

    /// A pill that reads `text` in the colours of `tone`.
    init(_ text: String, tone: PillTone) {
        self.text = text
        self.tone = tone
    }

    var body: some View {
        Text(verbatim: text)
            .font(Typography.subheadlineSemibold)
            .foregroundStyle(tone.foreground)
            .lineLimit(1)
            .fixedSize()
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .background(tone.background, in: Capsule())
    }
}
