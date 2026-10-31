import SwiftUI

/// Nastavení › Aplikace: the appearance of the app, the state of the rates with Zkontrolovat teď, and the licences of
/// the third-party parts with the version of the app. The rows of the rates load again whenever the data changes,
/// which new rates do too.
struct AppSettingsTab: View {
    let app: AppModel
    @State private var model: AppTabModel

    /// The licence whose text is shown in a sheet.
    @State private var shownLicence: Licence?

    init(app: AppModel) {
        self.app = app
        _model = State(initialValue: AppTabModel(app: app))
    }

    var body: some View {
        AdaptiveColumns(minimumColumnWidth: 440, spacing: DesignMetrics.cardSpacing) {
            appearanceCard
            VStack(spacing: DesignMetrics.cardSpacing) {
                ratesCard
                licencesCard
            }
        }
        .task(id: app.reloadKey) {
            await model.load()
        }
        .sheet(item: $shownLicence) { licence in
            LicenseSheet(licence: licence) {
                shownLicence = nil
            }
            .sheetChrome()
        }
    }

    // MARK: Vzhled

    private var appearanceCard: some View {
        Card(title: "Vzhled", subtitle: "Světlý nebo tmavý vzhled aplikace", spacing: 16) {
            HStack(alignment: .top, spacing: 20) {
                ForEach([Appearance.system, .light, .dark], id: \.self) { appearance in
                    AppearanceChoice(appearance: appearance, isChosen: model.appearance == appearance) {
                        Task { await model.setAppearance(appearance) }
                    }
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Vzhled")
            Text(verbatim: AppTabModel.appearanceNote(model.appearance))
                .font(Typography.body)
                .foregroundStyle(Palette.text2)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: Kurzy

    private var ratesCard: some View {
        Card(
            title: "Kurzy", subtitle: "Aplikace je stahuje sama, dokud běží. Nic jiného se neodesílá.", spacing: 6
        ) {
            VStack(alignment: .leading, spacing: 0) {
                if let errorText = model.errorText {
                    SettingsFailureLine(text: errorText)
                        .padding(.vertical, 8)
                }
                ForEach(model.rateRows, id: \.label) { row in
                    SettingsRow(label: row.label, detail: row.detail) {
                        HStack(spacing: 10) {
                            Text(verbatim: row.value)
                                .font(Typography.bodySemibold)
                                .monospacedDigit()
                                .foregroundStyle(row.tone.color)
                            if row.action == .showFinding {
                                Button("Zobrazit") {
                                    model.showPendingFinding()
                                }
                                .settingsCardButton()
                                .accessibilityLabel("Zobrazit – \(row.label)")
                            }
                        }
                    }
                }
                if let lastError = model.lastError {
                    Hairline()
                    SettingsFailureLine(text: lastError)
                        .font(Typography.callout)
                        .padding(.vertical, 8)
                }
                Hairline()
                HStack(spacing: 8) {
                    Button("Zkontrolovat teď") {
                        Task { await model.checkNow() }
                    }
                    .settingsCardButton()
                    .disabled(model.isChecking || app.refresh == nil)
                    if model.isChecking {
                        ProgressView()
                            .controlSize(.small)
                    }
                }
                .padding(.top, 10)
            }
        }
    }

    // MARK: Licence

    private var licencesCard: some View {
        Card(title: "Licence", spacing: 6) {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(AppTabModel.licences) { licence in
                    Hairline()
                    HStack(alignment: .center, spacing: 12) {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(verbatim: licence.name)
                                .font(Typography.bodySemibold)
                                .foregroundStyle(Palette.text)
                            Text(verbatim: licence.detail)
                                .font(Typography.callout)
                                .foregroundStyle(Palette.text2)
                        }
                        Spacer(minLength: 8)
                        Button("Zobrazit licenci") {
                            shownLicence = licence
                        }
                        .calloutLink()
                        .accessibilityLabel("Zobrazit licenci – \(licence.name)")
                    }
                    .padding(.vertical, 10)
                }
                Hairline()
                Text(verbatim: model.versionLine)
                    .font(Typography.callout)
                    .foregroundStyle(Palette.text3)
                    .padding(.top, 10)
            }
        }
    }
}

/// The colours of the tones of the state of a row of the card Kurzy, from the palette.
extension RateStatusRow.Tone {
    /// The colour of the state: the green of text while the rates are current, the colour of text for a fact, the
    /// grey of secondary text where there is nothing yet, and the orange of text where something is behind.
    var color: Color {
        switch self {
        case .current: Palette.greenText
        case .plain: Palette.text
        case .quiet: Palette.text2
        case .warning: Palette.orangeText
        }
    }
}

/// One choice of the appearance: a small picture of the window in it, and its name under it. The chosen one has a ring
/// in the accent colour round the picture, 3 points wide, and its name in semibold; the others have a hairline ring.
/// VoiceOver reads the three as choices with the chosen one selected.
struct AppearanceChoice: View {
    let appearance: Appearance
    let isChosen: Bool
    let choose: () -> Void

    var body: some View {
        Button(action: choose) {
            VStack(spacing: 8) {
                picture
                    .frame(width: 116, height: 74)
                    .clipShape(RoundedRectangle(cornerRadius: DesignMetrics.controlRadius))
                    .overlay { ring }
                    .accessibilityHidden(true)
                ChoiceText(
                    title: AppTabModel.appearanceName(appearance),
                    font: isChosen ? Typography.bodySemibold : Typography.body
                )
                .foregroundStyle(Palette.text)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(AppTabModel.appearanceName(appearance))
        .accessibilityAddTraits(isChosen ? .isSelected : [])
    }

    /// The ring round the picture, drawn outside it as the shadow of the design is, so that it takes none of the
    /// picture: the accent while the look is chosen, a hairline of the colour of the lines of a field otherwise.
    private var ring: some View {
        let width: CGFloat = isChosen ? 3 : 0.5
        return RoundedRectangle(cornerRadius: DesignMetrics.controlRadius + width / 2)
            .stroke(isChosen ? Palette.accent : Palette.sepStrong, lineWidth: width)
            .padding(-width / 2)
    }

    /// A window of the appearance: the sidebar on the left and two cards. The colours are those of the appearance it
    /// shows, whatever the appearance of the app is.
    @ViewBuilder
    private var picture: some View {
        switch appearance {
        case .system:
            // One window, light on the left half and dark on the right.
            ZStack {
                ThumbnailWindow(background: light.background, sidebar: light.sidebar, card: light.card)
                ThumbnailWindow(background: dark.background, sidebar: dark.sidebar, card: dark.card)
                    .mask {
                        HStack(spacing: 0) {
                            Color.clear
                            Color.black
                        }
                    }
            }
        case .light:
            ThumbnailWindow(background: light.background, sidebar: light.sidebar, card: light.card)
        case .dark:
            ThumbnailWindow(background: dark.background, sidebar: dark.sidebar, card: dark.card)
        }
    }

    // These literal colours are exempt from the palette: the pictures draw a light and a dark window on purpose,
    // whatever the appearance of the app is.
    private let light = (background: Color(white: 0.91), sidebar: Color(white: 0.85), card: Color.white)
    private let dark = (background: Color(white: 0.12), sidebar: Color(white: 0.18), card: Color(white: 0.24))
}

/// The picture of a window of a choice of the appearance, in the colours it is given: the colours of a light and a dark
/// window, which are exempt from the palette.
private struct ThumbnailWindow: View {
    let background: Color
    let sidebar: Color
    let card: Color

    var body: some View {
        GeometryReader { size in
            ZStack(alignment: .topLeading) {
                background
                RoundedRectangle(cornerRadius: 5)
                    .fill(sidebar)
                    .frame(width: 26, height: max(size.size.height - 16, 0))
                    .offset(x: 8, y: 8)
                RoundedRectangle(cornerRadius: 5)
                    .fill(card)
                    .frame(width: max(size.size.width - 50, 0), height: 22)
                    .offset(x: 42, y: 8)
                RoundedRectangle(cornerRadius: 5)
                    .fill(card)
                    .frame(width: max(size.size.width - 50, 0), height: max(size.size.height - 44, 0))
                    .offset(x: 42, y: 36)
            }
        }
    }
}
