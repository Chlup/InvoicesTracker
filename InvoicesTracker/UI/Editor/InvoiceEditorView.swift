import AppKit
import SwiftUI

/// The invoice editor, in the place of the content of Faktury: the bar of the template or of the invoice that is
/// edited, the sections of the form (Odběratel a doklad, Platba, měna a DPH, Položky, Poznámka), the effect on the
/// levies, the buttons, and beside them the live preview of the page, which is white whatever the appearance. Where
/// the window is too narrow for both, the preview comes under the form.
///
/// The fields write into the model as they are typed. The model works the invoice out again whenever one of them
/// changes (a moment after the last key); nothing is saved until a button says so.
///
/// The question "Zahodit rozepsanou fakturu?" takes the keyboard focus to its dialog while it is asked
/// (`asksToDiscard`); Pokračovat v úpravách gives it back to the field of the editor that had it (`FocusReturn`), so
/// that the person types on where they were.
struct InvoiceEditorView: View {
    @Bindable var model: InvoiceEditorModel

    /// The time zone of the Mac, in which the date is chosen.
    let timeZone: TimeZone

    /// Whether the app asks whether to throw the invoice away (`AppModel.pendingDiscard`), in a dialog of the window
    /// over the editor or in the chooser.
    let asksToDiscard: Bool

    /// The window is wide enough for the form and the preview side by side from this width: the form keeps the 590
    /// points its rows of items need, the preview has 380, and there are the margins and the gap between them.
    private static let sideBySideWidth: CGFloat = 1_040
    private static let previewWidth: CGFloat = 380

    var body: some View {
        GeometryReader { geometry in
            if geometry.size.width >= Self.sideBySideWidth {
                HStack(alignment: .top, spacing: 16) {
                    ScrollView {
                        form
                            .pagePadding(.vertical)
                    }
                    ScrollView {
                        PreviewPane(document: model.document)
                            .pagePadding(.vertical)
                    }
                    .frame(width: Self.previewWidth)
                }
                .pagePadding(.horizontal)
            } else {
                ScrollView {
                    VStack(spacing: 16) {
                        form
                        PreviewPane(document: model.document)
                    }
                    .pagePadding()
                }
            }
        }
        .background(FocusReturn(asksToDiscard: asksToDiscard))
        .task(id: model.refreshKey) {
            // A moment after the last key, so that typing is not worked out key by key.
            do {
                try await Task.sleep(for: .milliseconds(150))
            } catch {
                return
            }
            await model.recompute()
        }
    }

    // MARK: The form

    private var form: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let name = model.templateBarName {
                templateBar(name)
            }
            if let state = model.editBarState {
                editBar(state)
            }
            clientSection
            paymentSection
            InvoiceItemsEditor(model: model)
            noteSection
            if let heading = model.impactText {
                impactBox(heading: heading, detail: model.impactDetail)
            }
            problemsAndFailure
            buttons
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: Bars

    /// "Šablona <name>" with "Vybrat jinou", over a new invoice.
    private func templateBar(_ name: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "doc.on.doc")
                .foregroundStyle(.tint)
                .accessibilityHidden(true)
            Text("Šablona")
                .foregroundStyle(.secondary)
            Text(verbatim: name)
                .fontWeight(.semibold)
            Button("Vybrat jinou") {
                model.chooseAnotherTemplate()
            }
            .buttonStyle(.bordered)
            .buttonBorderShape(.capsule)
            .controlSize(.small)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }

    /// "Upravujete fakturu <number>" with its state, and for an invoice that is issued the warning.
    private func editBar(_ state: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "pencil")
                    .foregroundStyle(.tint)
                    .accessibilityHidden(true)
                Text("Upravujete fakturu")
                    .foregroundStyle(.secondary)
                Text(verbatim: model.editing?.number ?? "")
                    .fontWeight(.semibold)
                    .monospacedDigit()
                Text(verbatim: state)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
            }
            if let warning = model.editWarning {
                Text(verbatim: warning)
                    .font(.callout)
                    .foregroundStyle(Color(.simulationText))
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.orange.opacity(0.14), in: RoundedRectangle(cornerRadius: 10))
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }

    // MARK: Sections

    private var clientSection: some View {
        VStack(spacing: 0) {
            FormRow("Odběratel", alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    FlowLayout(spacing: 6) {
                        ForEach(model.clients) { client in
                            ClientChip(name: client.name, isOn: client.id == model.clientID) {
                                model.pickClient(client.id)
                            }
                        }
                    }
                    if model.clients.isEmpty {
                        Text(verbatim: EditorText.noClients)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                    if !model.clientInfo.isEmpty {
                        Text(verbatim: model.clientInfo)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            Divider()
            FormRow("Číslo faktury") {
                HStack(spacing: 10) {
                    if model.numberIsEditable {
                        TextField("Číslo faktury", text: $model.number)
                            .labelsHidden()
                            .textFieldStyle(.roundedBorder)
                            .monospacedDigit()
                            .frame(width: 180)
                    } else {
                        Text(verbatim: model.number)
                            .fontWeight(.semibold)
                            .monospacedDigit()
                    }
                    Text(verbatim: model.numberHint)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
            Divider()
            FormRow("Datum vystavení") {
                dateField("Datum vystavení", selection: issueDateSelection)
            }
            Divider()
            FormRow("DUZP") {
                dateField("DUZP", selection: dutySelection)
            }
            Divider()
            FormRow("Splatnost") {
                HStack(spacing: 8) {
                    TextField("Splatnost ve dnech", text: $model.dueDaysText)
                        .labelsHidden()
                        .multilineTextAlignment(.trailing)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 64)
                    Text(verbatim: model.dueDaysLine)
                        .monospacedDigit()
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Odběratel a doklad")
    }

    private var paymentSection: some View {
        VStack(spacing: 0) {
            FormRow("Platba") {
                Text(verbatim: model.methodText.isEmpty ? "—" : model.methodText)
            }
            Divider()
            FormRow("Měna a kurz") {
                Text(verbatim: model.currencyText)
                    .monospacedDigit()
                    .fixedSize(horizontal: false, vertical: true)
            }
            Divider()
            FormRow("Režim DPH") {
                Picker("Režim DPH", selection: $model.vatMode) {
                    ForEach(VatMode.allCases, id: \.self) { mode in
                        Text(mode.label)
                            .tag(mode)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .fixedSize()
            }
            Divider()
            FormRow("QR platba", alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Toggle("Přidat na fakturu QR kód pro platbu", isOn: qrSelection)
                        .disabled(!model.qrAvailable)
                    Text(verbatim: model.qrNote)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.leading, 22)
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Platba, měna a DPH")
    }

    private var noteSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Poznámka na faktuře")
                .font(.system(size: 15, weight: .semibold))
                .accessibilityAddTraits(.isHeader)
            TextEditor(text: $model.note)
                .font(.body)
                .scrollContentBackground(.hidden)
                .padding(6)
                .frame(height: 110)
                .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.separator))
                .accessibilityLabel("Poznámka na faktuře")
            let tooLong = model.noteLineCount > EditorLimits.noteLines
            Text(
                "Vytiskne se dole na faktuře. Ze šablony se předvyplní, tady ji můžete pro tuto fakturu změnit."
                    + " Nejvýše \(EditorLimits.noteLines) řádků (teď \(model.noteLineCount))."
            )
            .font(.callout)
            .foregroundStyle(tooLong ? Color.red : Color.secondary)
            .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
        .accessibilityElement(children: .contain)
    }

    /// "Až přijde platba, přibude k odvodům …" or "Po úpravě se odvody za rok … změní o …".
    private func impactBox(heading: String, detail: String?) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: "info.circle")
                .font(.system(size: 18))
                .foregroundStyle(.orange)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(verbatim: heading)
                    .fontWeight(.semibold)
                    .fixedSize(horizontal: false, vertical: true)
                if let detail {
                    Text(verbatim: detail)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.orange.opacity(0.14), in: RoundedRectangle(cornerRadius: 16))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Dopad na odvody")
    }

    // MARK: Buttons

    /// What stops the invoice from being saved, and what went wrong with the last attempt.
    @ViewBuilder
    private var problemsAndFailure: some View {
        if !model.validation.isEmpty {
            VStack(alignment: .trailing, spacing: 2) {
                ForEach(model.validation, id: \.self) { text in
                    Text(verbatim: text)
                        .font(.callout)
                        .foregroundStyle(Color(.simulationText))
                        .multilineTextAlignment(.trailing)
                }
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
            .accessibilityElement(children: .combine)
        }
        if let failure = model.failure {
            Text(verbatim: failure)
                .foregroundStyle(.red)
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
    }

    private var buttons: some View {
        HStack(spacing: 8) {
            Spacer(minLength: 0)
            Button("Zrušit") {
                model.cancel()
            }
            .buttonStyle(.bordered)
            .keyboardShortcut(.cancelAction)
            if model.showsSaveDraft {
                Button("Uložit koncept") {
                    run { try await model.saveDraft() }
                }
                .buttonStyle(.bordered)
                .disabled(!model.canSaveDraft || model.isSaving)
            }
            Button(model.primaryTitle) {
                if model.editing?.status == .issued {
                    run { try await model.saveChanges() }
                } else {
                    run { try await model.issue() }
                }
            }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut(.return, modifiers: .command)
            .disabled(!model.canIssue || model.isSaving)
        }
        .buttonBorderShape(.capsule)
        .controlSize(.large)
    }

    /// Saves with `action`. The model closes the editor when it has saved; a failure is said under the form until the
    /// next edit (`failure` of the model), and the editor stays open.
    private func run(_ action: @escaping () async throws -> Int64) {
        Task {
            do {
                _ = try await action()
            } catch {
                AppModel.log("Saving an invoice", failedWith: error)
            }
        }
    }

    // MARK: Bindings

    /// The box is ticked only while a code is possible for the currency.
    private var qrSelection: Binding<Bool> {
        Binding(
            get: { model.qrEnabled && model.qrAvailable },
            set: { model.qrEnabled = $0 })
    }

    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        return calendar
    }

    /// The days the date picker offers: those of the years of an invoice.
    private var dateRange: ClosedRange<Date> {
        let first = DateComponents(year: EditorLimits.years.lowerBound, month: 1, day: 1, hour: 12)
        let last = DateComponents(year: EditorLimits.years.upperBound, month: 12, day: 31, hour: 12)
        guard let from = calendar.date(from: first), let through = calendar.date(from: last) else {
            return Date.distantPast...Date.distantFuture
        }
        return from...through
    }

    /// A date field of the form, in Czech and in the time zone of the Mac.
    private func dateField(_ title: String, selection: Binding<Date>) -> some View {
        DatePicker(title, selection: selection, in: dateRange, displayedComponents: .date)
            .datePickerStyle(.field)
            .labelsHidden()
            .environment(\.timeZone, timeZone)
            .environment(\.calendar, calendar)
            .environment(\.locale, Locale(identifier: "cs_CZ"))
    }

    /// The day of issue as an instant the date picker takes (`instant(of:)`).
    private var issueDateSelection: Binding<Date> {
        Binding(
            get: { instant(of: model.issueDate) },
            set: { model.issueDate = CivilDate.today(now: $0, timeZone: timeZone) }
        )
    }

    /// The DUZP as an instant the date picker takes (`instant(of:)`).
    private var dutySelection: Binding<Date> {
        Binding(
            get: { instant(of: model.duzp) },
            set: { model.duzp = CivilDate.today(now: $0, timeZone: timeZone) }
        )
    }

    /// Noon of `day` in the time zone of the Mac, whatever the clock changes of the day.
    private func instant(of day: CivilDate) -> Date {
        let parts = DateComponents(year: day.year, month: day.month, day: day.day, hour: 12)
        return calendar.date(from: parts) ?? Date()
    }
}

// MARK: - Parts

/// Gives the keyboard focus back to the view of the editor that had it — a field, the date, the note — once the
/// question whether to throw the invoice away is answered with Pokračovat v úpravách, as the dialog of the window takes
/// the focus while it asks (`FocusKeeper`). A field gets back what was selected in it, or else the insertion point at
/// the end of its text, never all of it selected: a key typed then would replace it. It follows the first responder of
/// the window, as the cover of the lock after inactivity does, because SwiftUI's focus state follows only a window that
/// is key.
private struct FocusReturn: NSViewRepresentable {
    let asksToDiscard: Bool

    func makeNSView(context: Context) -> ReturnView {
        let view = ReturnView()
        view.asksToDiscard = asksToDiscard
        return view
    }

    func updateNSView(_ view: ReturnView, context: Context) {
        view.asksToDiscard = asksToDiscard
    }

    final class ReturnView: NSView {
        private var observation: NSKeyValueObservation?

        /// The view of the editor that had the focus last, and what was selected in it as the question came.
        private weak var focusedView: NSView?
        private var selection: NSRange?

        /// Whether the question is asked: the focus is noted as it comes, and given back once it is answered.
        var asksToDiscard = false {
            didSet {
                guard asksToDiscard != oldValue else { return }
                if asksToDiscard {
                    noteSelection()
                } else {
                    giveFocusBack()
                }
            }
        }

        /// A click goes to the views over it.
        override func hitTest(_ point: NSPoint) -> NSView? {
            nil
        }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            observation = window?.observe(\.firstResponder, options: [.new]) { [weak self] _, change in
                MainActor.assumeIsolated {
                    self?.focusMoved(to: change.newValue ?? nil)
                }
            }
        }

        /// Notes the view of the editor that `responder` stands for, while no question is asked.
        private func focusMoved(to responder: NSResponder?) {
            guard !asksToDiscard, let responder, let view = Self.view(of: responder), isInTheEditor(view) else {
                return
            }
            focusedView = view
            selection = nil
        }

        /// What is selected in the field that has the focus as the question comes, if it still has it.
        private func noteSelection() {
            guard let editor = window?.firstResponder as? NSTextView, editor.isFieldEditor,
                let view = focusedView, editor.delegate as? NSView === view
            else { return }
            selection = editor.selectedRange()
        }

        /// The view that had the focus has it again, once the editor is enabled again, which SwiftUI does in the update
        /// that closes the dialog: unless the focus is in the editor already, or the view is gone.
        private func giveFocusBack() {
            guard let view = focusedView else { return }
            let range = selection
            selection = nil
            DispatchQueue.main.async { [weak self] in
                guard let self, !asksToDiscard, let window, view.window === window else { return }
                if let current = window.firstResponder.flatMap(Self.view(of:)), isInTheEditor(current) {
                    return
                }
                guard window.makeFirstResponder(view),
                    let editor = (view as? NSTextField)?.currentEditor() as? NSTextView
                else { return }
                let length = (editor.string as NSString).length
                if let range, NSMaxRange(range) <= length {
                    editor.setSelectedRange(range)
                } else {
                    editor.setSelectedRange(NSRange(location: length, length: 0))
                }
            }
        }

        /// Whether `view` is a view of the editor: not this one, and within the room of the editor, which this view
        /// is the background of.
        private func isInTheEditor(_ view: NSView) -> Bool {
            view !== self && convert(bounds, to: nil).intersects(view.convert(view.bounds, to: nil))
        }

        /// The view that `responder` stands for: the text field that a field editor edits, or `responder` itself.
        private static func view(of responder: NSResponder) -> NSView? {
            if let editor = responder as? NSTextView, editor.isFieldEditor {
                return editor.delegate as? NSView
            }
            return responder as? NSView
        }
    }
}

/// A row of a section: the label on the left, the content beside it.
private struct FormRow<Content: View>: View {
    let label: String
    let alignment: VerticalAlignment
    let content: Content

    init(_ label: String, alignment: VerticalAlignment = .center, @ViewBuilder content: () -> Content) {
        self.label = label
        self.alignment = alignment
        self.content = content()
    }

    var body: some View {
        HStack(alignment: alignment, spacing: 14) {
            Text(label)
                .foregroundStyle(.secondary)
                .frame(width: 140, alignment: .leading)
            content
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 10)
    }
}

/// "Náhled PDF": the page of the invoice as it prints, as large as the width allows, on a grey ground. The page is cut
/// to the paper: an invoice that does not fit it draws below it, and what is cut is not the editor's to judge (the
/// check of the page is `InvoicePDFRenderer.fitsOnOnePage`).
struct PreviewPane: View {
    let document: InvoiceDocument?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Náhled PDF")
                .font(.system(size: 13, weight: .semibold))
                .accessibilityAddTraits(.isHeader)
            if let document {
                GeometryReader { geometry in
                    let scale = min(1, geometry.size.width / PageSize.a4.width)
                    InvoiceDocumentView(document: document)
                        .scaleEffect(scale, anchor: .topLeading)
                        .frame(
                            width: PageSize.a4.width * scale, height: PageSize.a4.height * scale,
                            alignment: .topLeading
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                        .shadow(color: .black.opacity(0.12), radius: 8, y: 4)
                }
                .aspectRatio(PageSize.a4.width / PageSize.a4.height, contentMode: .fit)
            } else {
                Text("Náhled se zobrazí, až bude faktura úplná.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 120)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 14)
        .padding(.bottom, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 16))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Náhled PDF")
    }
}
