import SwiftUI

/// The sidebar: the screens of the selected year under "Rok 2026", Faktury with the number of its drafts, the records
/// under "Evidence", the tools under "Nástroje" (Simulátor, and Import with the progress of an import that runs), and
/// Nastavení pinned at the bottom with the version of the app under it.
struct SidebarView: View {
    let model: AppModel

    /// The drafts issued in the selected year, read again whenever the screens load again.
    @State private var draftCount = 0

    var body: some View {
        List(selection: selection) {
            Section("Rok \(String(model.asOf.year))") {
                row(.overview)
                row(.invoices, badge: draftCount)
                row(.advances)
                row(.computation)
                row(.prediction)
            }
            Section("Evidence") {
                row(.clients)
            }
            Section("Nástroje") {
                row(.simulator)
                row(.importer, badge: model.importBadge)
            }
        }
        .listStyle(.sidebar)
        .task(id: model.reloadKey) {
            draftCount = await model.draftCountOfSelectedYear()
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                pinnedRow(.settings)
                SidebarVersionLine(text: Self.versionText(info: Bundle.main.infoDictionary))
                    .padding(.leading, 8)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 12)
        }
    }

    /// The line under Nastavení, "Verze 1.6.0 (9)": the marketing version and the build of the app from `info`, its
    /// Info.plist. A value it lacks reads "?".
    nonisolated static func versionText(info: [String: Any]?) -> String {
        let version = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        return "Verze \(version) (\(build))"
    }

    private var selection: Binding<Screen?> {
        Binding(
            get: { model.screen },
            set: { screen in
                if let screen {
                    model.screen = screen
                }
            }
        )
    }

    /// A row of the list, with `badge` beside its name when it is more than 0. The tag comes last, on the row as a
    /// whole: a badge put on the row after its tag hides the tag from the list, and the row can then be neither chosen
    /// nor shown as chosen.
    private func row(_ screen: Screen, badge: Int = 0) -> some View {
        Label(screen.title, systemImage: screen.systemImage)
            .badge(badge)
            .tag(screen)
    }

    /// A row of the list, with `badge` as text beside its name, such as the "3/12" of an import that runs, and nothing
    /// while it is nil. The tag comes last here too, for the reason given above.
    private func row(_ screen: Screen, badge: String?) -> some View {
        Label(screen.title, systemImage: screen.systemImage)
            .badge(badge.map { Text(verbatim: $0) })
            .tag(screen)
    }

    /// A row below the list, which stays at the bottom however long the list is. It is selected like a row of the list.
    private func pinnedRow(_ screen: Screen) -> some View {
        let selected = model.screen == screen
        return Button {
            model.screen = screen
        } label: {
            HStack(spacing: 8) {
                Label {
                    Text(screen.title)
                        .fontWeight(selected ? .semibold : .regular)
                } icon: {
                    Image(systemName: screen.systemImage)
                        .foregroundStyle(.tint)
                }
                Spacer(minLength: 4)
            }
            .padding(.horizontal, 8)
            .frame(minHeight: 28)
            .contentShape(Rectangle())
            .background {
                if selected {
                    RoundedRectangle(cornerRadius: DesignMetrics.controlRadius).fill(Palette.fillStrong)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// The line under Nastavení that names the version of the app: small print, the subheadline in the third colour of
/// text, with digits of one width, so that the line does not shift when the version or the build changes.
struct SidebarVersionLine: View {
    let text: String

    var body: some View {
        Text(verbatim: text)
            .font(Typography.subheadline)
            .monospacedDigit()
            .foregroundStyle(Palette.text3)
    }
}

private extension Screen {
    /// The symbol of the screen in the sidebar.
    var systemImage: String {
        switch self {
        case .overview: "gauge.with.needle"
        case .invoices: "doc.text"
        case .advances: "calendar"
        case .computation: "sum"
        case .prediction: "chart.line.uptrend.xyaxis"
        case .clients: "person.2"
        case .simulator: "plus.forwardslash.minus"
        case .settings: "gearshape"
        case .importer: "square.and.arrow.down"
        }
    }
}
