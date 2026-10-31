import SwiftUI

/// The rate capsule of the toolbar: how the year shown converts its income in other currencies, "Denní kurz", or
/// "Jednotný kurz" tinted blue while the year uses its uniform rate, between an exchange icon and a chevron. VoiceOver
/// reads it as "Přepočet cizích měn v roce 2025: jednotný kurz". A click opens its menu under it (`RateMenu`), which
/// switches the year between the daily ČNB rates and its uniform rate.
///
/// It names the method the year uses (`AppModel.shownYearFXMethod`), which the window reads again whenever the year
/// shown or the data changes, and the menu once a choice in it is stored; until it has been read, the capsule names the
/// daily rates.
///
/// The toolbar draws the glass around it, so the button has no bezel of its own: with one, the toolbar might not fit
/// the least window, and Nová faktura would go into the menu of the items that do not fit.
struct RateCapsule: View {
    let model: AppModel

    /// Whether the menu is open.
    @State private var menuShown = false

    var body: some View {
        let capsule = RateMenuBuilder.capsule(year: model.asOf.year, effective: model.shownYearFXMethod)
        Button {
            menuShown = true
        } label: {
            HStack(spacing: 4) {
                // The arrow of the symbol that points right is drawn under the other: mirrored, it is on top.
                Image(systemName: "arrow.left.arrow.right")
                    .scaleEffect(x: -1, y: 1)
                Text(verbatim: capsule.title)
                    .font(Typography.bodySemibold)
                Image(systemName: "chevron.down")
                    .font(Typography.subheadlineSemibold)
                    .foregroundStyle(Palette.text2)
            }
            .foregroundStyle(capsule.isTinted ? Palette.accentText : Palette.text)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background {
                if capsule.isTinted {
                    Capsule().fill(Palette.accentTint)
                }
            }
            .contentShape(Capsule())
        }
        .buttonStyle(.borderless)
        .accessibilityLabel(capsule.accessibilityLabel)
        .popover(isPresented: $menuShown, arrowEdge: .bottom) {
            RateMenu(app: model) {
                menuShown = false
            }
        }
    }
}

// MARK: - The menu

/// The menu of the rate capsule (`RateMenuModel`), in a popover under it: the heading "Cizí měny v roce Y", the daily
/// ČNB rates and the uniform rate of the year, each with the line under it and the levies of the year with it when
/// both can be chosen, a check mark at the one the year uses, and the note under them. A choice closes the menu once
/// the year is converted by it; one that could not be saved keeps the menu open and says so.
private struct RateMenu: View {
    let app: AppModel
    let close: () -> Void

    @State private var menu: RateMenuModel

    init(app: AppModel, close: @escaping () -> Void) {
        self.app = app
        self.close = close
        _menu = State(initialValue: RateMenuModel(app: app))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(verbatim: menu.heading)
                .font(Typography.calloutSemibold)
                .foregroundStyle(Palette.text2)
                .padding(EdgeInsets(top: 6, leading: 10, bottom: 4, trailing: 10))
            if let content = menu.content {
                ForEach(content.items, id: \.method) { item in
                    RateMenuRow(item: item, waits: menu.isChoosing) {
                        Task {
                            if await menu.choose(item.method) {
                                close()
                            }
                        }
                    }
                }
                if let failure = menu.choiceFailure {
                    failureLine(failure)
                }
                Hairline()
                    .padding(.top, 4)
                Text(verbatim: content.footer)
                    .font(Typography.callout)
                    .foregroundStyle(Palette.text2)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(EdgeInsets(top: 8, leading: 10, bottom: 4, trailing: 10))
            } else if let errorText = menu.errorText {
                failureLine(errorText)
            }
        }
        .padding(6)
        .frame(width: 330, alignment: .leading)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Přepočet cizích měn")
        .task(id: RateMenuKey(shown: app.reloadKey, today: app.today)) {
            await menu.load()
        }
    }

    private func failureLine(_ text: String) -> some View {
        SettingsFailureLine(text: text)
            .font(Typography.callout)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
    }
}

/// What the menu reads again when it changes while the menu is open: the year and the day shown with the data, and
/// today, which decides where a year without its uniform rate stands (`UniformRateSearch`): the rate is not published
/// yet, the app looks for it once a day, or the app does not have it.
private struct RateMenuKey: Hashable {
    var shown: ReloadKey
    var today: CivilDate
}

/// A choice of the rate menu: a check mark when the year uses it, its title, the line under it and the levies of the
/// year with it. VoiceOver reads the title, then the lines under it, and whether it is chosen. A choice that cannot be
/// made is dimmed, and a click on it does nothing; so does a click while another choice is being made (`waits`).
private struct RateMenuRow: View {
    let item: RateMenuItem

    /// Whether a choice of the menu is being made, which the choices wait for.
    let waits: Bool

    let choose: () -> Void

    /// Whether the pointer is over the choice, which is then highlighted when it can be made.
    @State private var hovered = false

    var body: some View {
        Button(action: choose) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Image(systemName: "checkmark")
                    .font(Typography.calloutSemibold)
                    .opacity(item.isChecked ? 1 : 0)
                    .frame(width: 16)
                VStack(alignment: .leading, spacing: 1) {
                    Text(verbatim: item.title)
                        .font(Typography.bodySemibold)
                        .foregroundStyle(item.isEnabled ? Palette.text : Palette.text3)
                    Text(verbatim: item.detail)
                        .font(Typography.callout)
                        .foregroundStyle(item.isEnabled ? Palette.text2 : Palette.text3)
                        .fixedSize(horizontal: false, vertical: true)
                    if let comparison = item.comparison {
                        Text(verbatim: comparison)
                            .font(Typography.callout)
                            .monospacedDigit()
                            .foregroundStyle(Palette.text2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(EdgeInsets(top: 7, leading: 6, bottom: 8, trailing: 10))
            .contentShape(Rectangle())
            .background(
                hovered && item.isEnabled && !waits ? Palette.fillStrong : Color.clear,
                in: RoundedRectangle(cornerRadius: DesignMetrics.controlRadius))
        }
        .buttonStyle(.plain)
        .disabled(!item.isEnabled || waits)
        .onHover { hovered = $0 }
        .accessibilityLabel(item.title)
        .accessibilityValue(([item.detail] + [item.comparison].compactMap { $0 }).joined(separator: ", "))
        .accessibilityAddTraits(item.isChecked ? .isSelected : [])
    }
}
