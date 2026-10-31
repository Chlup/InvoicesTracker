import SwiftUI

/// Nastavení: four tabs in the segmented control of the design — Aplikace, Moje údaje, Zabezpečení a zálohy and Rok Y —
/// and under them the green banner with the result of the last action, then the tab. The banner belongs to the tab it
/// came from and closes when another tab is chosen. The title and the line under it are the shell's.
///
/// The page fills the room the window gives it and asks for no minimum size of its own: what is under the tabs scrolls.
/// The tabs stand above what scrolls, and what scrolls is as wide as the room, so the tabs stay where they are whatever
/// the tab under them shows, also while it has nothing to show yet (`SettingsLoadingView`). A page that was only as
/// wide as its content would narrow to the tabs then, and stand in the middle of the window until the cards came.
struct SettingsScreen: View {
    let app: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            tabs
                .pagePadding([.horizontal, .top])
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if let banner = app.banner, banner.screen == .settings {
                        BannerView(text: banner.text) {
                            app.banner = nil
                        }
                    }
                    tabContent
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .pagePadding([.horizontal, .bottom])
            }
        }
    }

    /// The tabs in the segmented control "Části nastavení", which VoiceOver reads as a group of buttons. The control is
    /// as wide as its tabs and stands at the leading edge of the page.
    private var tabs: some View {
        SegmentedControl(
            "Části nastavení", selection: selectedTab,
            segments: SettingsTab.allCases.map { (value: $0, title: $0.title(year: app.asOf.year)) }
        )
    }

    private var selectedTab: Binding<SettingsTab> {
        Binding(get: { app.settingsTab }, set: { app.settingsTab = $0 })
    }

    @ViewBuilder
    private var tabContent: some View {
        switch app.settingsTab {
        case .application:
            AppSettingsTab(app: app)
        case .supplier:
            SupplierTab(app: app)
        case .security:
            SecurityTab(app: app)
        case .year:
            YearTab(app: app)
        }
    }
}
