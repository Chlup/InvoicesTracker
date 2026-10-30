import AppKit
import SwiftUI

/// The window: the full-window states until the data is open — the first launch, the start with empty data, a restore,
/// the locked screen, the screen of a Mac that does not know the data, the damaged data, the data of a newer version
/// and the card after unlocking with the code — then the sidebar, the selected screen with its banner, and the
/// toolbar. While the app is locked after inactivity, the card of the lock covers the app (`IdleLockCover`). The
/// appearance follows Nastavení › Aplikace.
///
/// The app model is in the environment of the window, for what its sheets and its views need of it on their own: the
/// lock over a sheet, and what VoiceOver is told. While the window is open, it watches the activity in the app's
/// windows, which the lock after inactivity counts from, when the app checks the lock by itself
/// (`AppDependencies.startsIdleChecks`).
struct RootView: View {
    let model: AppModel

    var body: some View {
        content
            .environment(model)
            .frame(minWidth: 1100, minHeight: 720)
            .preferredColorScheme(model.appSettings.appearance.colorScheme)
            .background {
                if model.dependencies.startsIdleChecks {
                    ActivityWatch(model: model)
                }
            }
            .onAppear {
                // Not tied to the window: closing it during the Touch ID prompt must not cut the launch short.
                Task { await model.launch() }
            }
    }

    @ViewBuilder
    private var content: some View {
        switch model.phase {
        case .starting:
            Color.clear
        case .welcome:
            WelcomeView(model: model)
        case .onboarding(let step):
            OnboardingView(model: model, step: step)
        case .locked:
            LockedView(model: model)
        case .newMac:
            NewMacView(model: model)
        case .damaged(let reason):
            DamagedDataView(model: model, reason: reason)
        case .newerVersion:
            NewerVersionView()
        case .ready:
            Group {
                if let completion = model.completion {
                    UnlockCompletionView(model: model, completion: completion)
                } else {
                    AppWindow(model: model)
                }
            }
            .modifier(IdleLockCover(app: model, kind: .window))
        }
    }
}

/// The window once the data is open: the sidebar and the page, the confirmations that the window asks itself in dialogs
/// inside it over them, and the sheets over the window. While the app is locked after inactivity, the window has no
/// title and no toolbar: they show the invoice that is edited, the year and how it converts its income, and offer what
/// acts on the data.
private struct AppWindow: View {
    let model: AppModel

    var body: some View {
        NavigationSplitView {
            SidebarView(model: model)
                .navigationSplitViewColumnWidth(min: 200, ideal: 232, max: 320)
        } detail: {
            let header = shownHeader
            VStack(spacing: 0) {
                if let banner = model.banner, banner.screen == model.screen, !model.screen.showsItsOwnBanner {
                    BannerView(text: banner.text) {
                        model.banner = nil
                    }
                    .padding([.horizontal, .top], 16)
                }
                screenContent
            }
            .navigationTitle(model.isIdleLocked ? "" : header.title)
            .navigationSubtitle(model.isIdleLocked ? "" : header.subtitle)
            .toolbar {
                if !model.isIdleLocked {
                    MainToolbar(model: model)
                }
            }
        }
        .toolbar(removing: model.isIdleLocked ? .sidebarToggle : nil)
        // The dialogs cover the sidebar and the page alone: the sheets of the window, which are applied after them,
        // stay usable over a dialog.
        .windowDialog(item: Bindable(model).invoiceDeletion, title: { $0.summary.title }) { request in
            DeleteInvoiceDialog(
                summary: request.summary, delete: request.delete,
                cancel: { model.invoiceDeletion = nil },
                deleted: { model.invoiceDeletion = nil })
        }
        .discardQuestion(of: model)
        .sheet(isPresented: chooserShown) {
            NewInvoiceChooser(app: model)
                .idleLockCover()
        }
        .sheet(isPresented: uniformRateSheetShown) {
            if let finding = model.uniformRateOffer {
                UniformRateConfirmSheet(app: model, finding: finding)
                    // Another finding is another sheet.
                    .id(finding)
                    .idleLockCover()
            }
        }
        .task(id: model.editorKey) {
            // The app holds the editor, so that it stays while other screens are shown and when the window is closed.
            await model.openEditor()
        }
        .task(id: [model.asOf.year, model.dataVersion]) {
            // How the year shown converts its income in other currencies, which the line under the title of Faktury
            // names: it follows the year and every write of the data.
            await model.loadShownYearFX()
        }
    }

    /// The selected screen: Přehled, Faktury (or the invoice editor in its place), Zálohy a odpočty, Výpočet,
    /// Odhad odvodů, Odběratelé, Šablony faktur, Simulátor, Nastavení and Import.
    @ViewBuilder
    private var screenContent: some View {
        switch model.screen {
        case .overview:
            OverviewScreen(app: model)
        case .invoices:
            if model.shownEditorRequest != nil {
                editorContent
            } else {
                InvoicesScreen(app: model)
            }
        case .advances:
            AdvancesScreen(app: model)
        case .computation:
            ComputationScreen(app: model)
        case .prediction:
            PredictionScreen(app: model)
        case .clients:
            ClientsScreen(app: model)
        case .templates:
            TemplatesScreen(app: model)
        case .simulator:
            SimulatorScreen(app: model)
        case .settings:
            SettingsScreen(app: model)
        case .importer:
            ImportScreen(app: model)
        }
    }

    // MARK: The editor

    /// The title and the line under it: the screen's, or the editor's while an invoice is edited. The editor's are its
    /// own (the header of a screen leaves them out) because they name the invoice.
    private var shownHeader: ScreenHeader {
        guard model.screen == .invoices, let request = model.shownEditorRequest else {
            return model.screen.header(
                year: model.asOf.year, asOf: model.asOf.asOf, today: model.today, incomeFX: model.shownYearFXMethod)
        }
        if let editor = model.editor {
            return ScreenHeader(title: editor.title, subtitle: editor.subtitle)
        }
        // While the editor is read.
        if case .edit = request {
            return ScreenHeader(title: "Upravit fakturu", subtitle: "")
        }
        return ScreenHeader(title: "Nová faktura", subtitle: "")
    }

    @ViewBuilder
    private var editorContent: some View {
        if let editor = model.editor {
            InvoiceEditorView(
                model: editor, timeZone: model.dependencies.timeZone(), asksToDiscard: model.pendingDiscard != nil
            )
            .id(ObjectIdentifier(editor))
        } else if let editorProblem = model.editorProblem {
            Text(verbatim: editorProblem)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            Color.clear
        }
    }

    /// Whether the sheet that asks to confirm a uniform rate that was found is open, over whichever screen is shown.
    /// Closing it without a choice leaves the finding pending.
    private var uniformRateSheetShown: Binding<Bool> {
        Binding(
            get: { model.uniformRateOffer != nil },
            set: { shown in
                if !shown {
                    model.uniformRateOffer = nil
                }
            }
        )
    }

    private var chooserShown: Binding<Bool> {
        Binding(
            get: { model.editorRequest == .chooser },
            set: { shown in
                if !shown {
                    model.cancelChooser()
                }
            }
        )
    }
}

/// Watches the activity in the app's windows for the lock after inactivity (`IdleActivityMonitor`) while the window it
/// is in is open: from when it is put in the window until the window closes, or it leaves the window. A window that is
/// closed goes, and the window that opens in its place watches with a monitor of its own.
private struct ActivityWatch: NSViewRepresentable {
    let model: AppModel

    func makeNSView(context: Context) -> WatchView {
        let view = WatchView()
        view.monitor = IdleActivityMonitor(app: model)
        return view
    }

    func updateNSView(_ view: WatchView, context: Context) {}

    static func dismantleNSView(_ view: WatchView, coordinator: ()) {
        view.stopWatching()
    }

    final class WatchView: NSView {
        var monitor: IdleActivityMonitor?

        /// The observation of the closing of the window, while the monitor watches.
        private var closing: (any NSObjectProtocol)?

        /// A click goes to the views over it.
        override func hitTest(_ point: NSPoint) -> NSView? {
            nil
        }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            stopWatching()
            guard let window else { return }
            monitor?.start()
            closing = NotificationCenter.default.addObserver(
                forName: NSWindow.willCloseNotification, object: window, queue: nil
            ) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.stopWatching()
                }
            }
        }

        func stopWatching() {
            monitor?.stop()
            if let closing {
                NotificationCenter.default.removeObserver(closing)
            }
            closing = nil
        }
    }
}

private extension Appearance {
    /// The colour scheme the window asks for: none when it follows the system.
    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}
