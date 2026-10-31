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

    /// The least width of the form beside the preview: the 590 points its rows of items need.
    private static let formMinimumWidth: CGFloat = 590

    /// The window is wide enough for the form and the preview side by side from this width: the form keeps the 590
    /// points its rows of items need, the preview is the aside of 461 (`PreviewPane.width`), and there are the margins
    /// of the page and the gap between the two.
    static let sideBySideWidth: CGFloat =
        formMinimumWidth + DesignMetrics.cardSpacing + PreviewPane.width + DesignMetrics.pageLeading
        + DesignMetrics.pageTrailing

    var body: some View {
        GeometryReader { geometry in
            if geometry.size.width >= Self.sideBySideWidth {
                HStack(alignment: .top, spacing: DesignMetrics.cardSpacing) {
                    ScrollView {
                        form
                            .pagePadding(.vertical)
                    }
                    ScrollView {
                        PreviewPane(document: model.document)
                            .pagePadding(.vertical)
                    }
                    .frame(width: PreviewPane.width)
                }
                .pagePadding(.horizontal)
            } else {
                ScrollView {
                    VStack(spacing: DesignMetrics.cardSpacing) {
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

    /// The form: the bar of the template or of the invoice, the sections, what the invoice does to the levies, what
    /// stops it from being saved and the buttons, 16 points apart.
    private var form: some View {
        VStack(alignment: .leading, spacing: DesignMetrics.cardSpacing) {
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
                impactNote(heading: heading, detail: model.impactDetail)
            }
            problemsAndFailure
            buttons
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: Bars

    /// "Šablona <name>" with "Vybrat jinou", over a new invoice.
    private func templateBar(_ name: String) -> some View {
        HStack(spacing: 14) {
            Image(systemName: "doc.on.doc")
                .imageScale(.large)
                .foregroundStyle(Palette.accent)
                .accessibilityHidden(true)
            Text("Šablona")
                .font(Typography.body)
                .foregroundStyle(Palette.text2)
            Text(verbatim: name)
                .font(Typography.bodyBold)
                .foregroundStyle(Palette.text)
            Button("Vybrat jinou") {
                model.chooseAnotherTemplate()
            }
            .buttonStyle(CapsuleButtonStyle(.secondary, size: .small))
            Spacer(minLength: 0)
        }
        .editorBar()
    }

    /// "Upravujete fakturu <number>" with its state, and for an invoice that is issued the warning, a note of
    /// attention.
    private func editBar(_ state: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                Image(systemName: "pencil")
                    .imageScale(.large)
                    .foregroundStyle(Palette.accent)
                    .accessibilityHidden(true)
                Text("Upravujete fakturu")
                    .font(Typography.body)
                    .foregroundStyle(Palette.text2)
                Text(verbatim: model.editing?.number ?? "")
                    .font(Typography.bodyBold)
                    .foregroundStyle(Palette.text)
                    .monospacedDigit()
                Text(verbatim: state)
                    .font(Typography.callout)
                    .foregroundStyle(Palette.text3)
                Spacer(minLength: 0)
            }
            if let warning = model.editWarning {
                Note(.attention, icon: .none, text: warning)
            }
        }
        .editorBar()
    }

    // MARK: Sections

    /// "Odběratel a doklad": the client among chips and what it starts an invoice with, the number, the two dates and
    /// the due days.
    private var clientSection: some View {
        RowsCard(label: "Odběratel a doklad") {
            FormRow("Odběratel", alignment: .top, labelHeight: DesignMetrics.smallControlHeight) {
                VStack(alignment: .leading, spacing: 6) {
                    FlowLayout(spacing: 6) {
                        ForEach(model.clients) { client in
                            FilterChip(client.name, isSelected: client.id == model.clientID) {
                                model.pickClient(client.id)
                            }
                        }
                    }
                    if model.clients.isEmpty {
                        Text(verbatim: EditorText.noClients)
                            .font(Typography.callout)
                            .foregroundStyle(Palette.text2)
                    }
                    if !model.clientInfo.isEmpty {
                        Text(verbatim: model.clientInfo)
                            .font(Typography.callout)
                            .foregroundStyle(Palette.text3)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            Hairline()
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
                            .font(Typography.bodySemibold)
                            .foregroundStyle(Palette.text)
                            .monospacedDigit()
                    }
                    Text(verbatim: model.numberHint)
                        .font(Typography.callout)
                        .foregroundStyle(Palette.text3)
                }
            }
            Hairline()
            FormRow("Datum vystavení") {
                dateField("Datum vystavení", selection: issueDateSelection)
            }
            Hairline()
            FormRow("DUZP") {
                dateField("DUZP", selection: dutySelection)
            }
            Hairline()
            FormRow("Splatnost") {
                HStack(spacing: 8) {
                    TextField("Splatnost ve dnech", text: $model.dueDaysText)
                        .labelsHidden()
                        .multilineTextAlignment(.trailing)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 64)
                    Text(verbatim: model.dueDaysLine)
                        .font(Typography.body)
                        .foregroundStyle(Palette.text)
                        .monospacedDigit()
                }
            }
        }
    }

    /// "Platba, měna a DPH": the way of payment, the currency with its rate, the VAT mode and the QR code.
    private var paymentSection: some View {
        RowsCard(label: "Platba, měna a DPH") {
            FormRow("Platba") {
                Text(verbatim: model.methodText.isEmpty ? "—" : model.methodText)
                    .font(Typography.body)
                    .foregroundStyle(Palette.text)
            }
            Hairline()
            FormRow("Měna a kurz") {
                Text(verbatim: model.currencyText)
                    .font(Typography.body)
                    .foregroundStyle(Palette.text)
                    .monospacedDigit()
                    .fixedSize(horizontal: false, vertical: true)
            }
            Hairline()
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
            Hairline()
            FormRow("QR platba", alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Toggle("Přidat na fakturu QR kód pro platbu", isOn: qrSelection)
                        .disabled(!model.qrAvailable)
                    Text(verbatim: model.qrNote)
                        .font(Typography.callout)
                        .foregroundStyle(Palette.text3)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.leading, 22)
                }
            }
        }
    }

    /// "Poznámka na faktuře": the note that the page prints, on the background of a card with the stronger line of a
    /// field around it and the example of the prototype in it while it is empty, and under it what it is for and how
    /// long it may be.
    private var noteSection: some View {
        Card(title: "Poznámka na faktuře", spacing: 8, label: "Poznámka") {
            ZStack(alignment: .topLeading) {
                TextEditor(text: $model.note)
                    .font(Typography.body)
                    .foregroundStyle(Palette.text)
                    .scrollContentBackground(.hidden)
                    .padding(6)
                    .accessibilityLabel("Poznámka na faktuře")
                if model.note.isEmpty {
                    Text(InvoiceEditorModel.notePlaceholder)
                        .font(Typography.body)
                        .foregroundStyle(Palette.text3)
                        .padding(.horizontal, 11)
                        .padding(.vertical, 6)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
            }
            .frame(height: 110)
            .background(Palette.bgCard, in: RoundedRectangle(cornerRadius: DesignMetrics.controlRadius))
            .overlay(RoundedRectangle(cornerRadius: DesignMetrics.controlRadius).strokeBorder(Palette.sepStrong))
            let tooLong = model.noteLineCount > EditorLimits.noteLines
            Text(
                "Vytiskne se dole na faktuře. Ze šablony se předvyplní, tady ji můžete pro tuto fakturu změnit."
                    + " Nejvýše \(EditorLimits.noteLines) řádků (teď \(model.noteLineCount))."
            )
            .font(Typography.callout)
            .foregroundStyle(tooLong ? Palette.redText : Palette.text3)
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// "Až přijde platba, přibude k odvodům …" or "Po úpravě se odvody za rok … změní o …": the note of an estimate,
    /// read as "Dopad na odvody".
    private func impactNote(heading: String, detail: String?) -> some View {
        Note(.attention, icon: .info, title: heading, text: detail ?? "")
            .accessibilityElement(children: .contain)
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
                        .font(Typography.callout)
                        .foregroundStyle(Palette.orangeText)
                        .multilineTextAlignment(.trailing)
                }
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
            .accessibilityElement(children: .combine)
        }
        if let failure = model.failure {
            Text(verbatim: failure)
                .font(Typography.body)
                .foregroundStyle(Palette.redText)
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
    }

    /// Zrušit, which Esc presses, Uložit koncept for a new invoice and a draft, and the main one, which ⌘↩ presses: the
    /// capsules of the page, 32 points tall. Uložit koncept stands on the window itself, so it is in the colour of a
    /// card.
    private var buttons: some View {
        HStack(spacing: 8) {
            Spacer(minLength: 0)
            Button("Zrušit") {
                model.cancel()
            }
            .buttonStyle(CapsuleButtonStyle(.secondary))
            .keyboardShortcut(.cancelAction)
            if model.showsSaveDraft {
                Button("Uložit koncept") {
                    run { try await model.saveDraft() }
                }
                .buttonStyle(CapsuleButtonStyle(.onWindow))
                .disabled(!model.canSaveDraft || model.isSaving)
            }
            Button(model.primaryTitle) {
                if model.editing?.status == .issued {
                    run { try await model.saveChanges() }
                } else {
                    run { try await model.issue() }
                }
            }
            .buttonStyle(CapsuleButtonStyle(.primary))
            .keyboardShortcut(.return, modifiers: .command)
            .disabled(!model.canIssue || model.isSaving)
        }
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

extension View {
    /// The look of a bar over the form: its content padded 20 at the sides, 16 above and 12 under, as wide as the room,
    /// on a panel in the colour of a card with the elevation of a card. It stands on the window, so it has the corners
    /// of a panel (10 points) and not of a card, as the line of a search does. VoiceOver reads it as a group.
    fileprivate func editorBar() -> some View {
        padding(.top, 16)
            .padding(.horizontal, DesignMetrics.cardPadding)
            .padding(.bottom, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                RoundedRectangle(cornerRadius: DesignMetrics.panelRadius)
                    .surface(Palette.bgCard, elevation: .card)
            }
            .accessibilityElement(children: .contain)
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

/// The sizes of the rows of the form, in points.
private enum FormRowMetrics {
    /// The width of the label of a row, which the content starts after.
    static let labelWidth: CGFloat = 140

    /// The space between the label and the content.
    static let gap: CGFloat = 14

    /// The space above and under the content of a row, on either side of the hairline between two rows.
    static let verticalPadding: CGFloat = 10
}

/// A row of a section: the label on the left, in secondary text, the content beside it. `labelHeight` makes the label
/// as high as the first line of the content where that is a control taller than a line of text, such as a chip, so that
/// the label stands level with it.
private struct FormRow<Content: View>: View {
    let label: String
    let alignment: VerticalAlignment
    let labelHeight: CGFloat?
    let content: Content

    init(
        _ label: String, alignment: VerticalAlignment = .center, labelHeight: CGFloat? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.label = label
        self.alignment = alignment
        self.labelHeight = labelHeight
        self.content = content()
    }

    var body: some View {
        HStack(alignment: alignment, spacing: FormRowMetrics.gap) {
            Text(label)
                .font(Typography.body)
                .foregroundStyle(Palette.text2)
                .frame(width: FormRowMetrics.labelWidth, height: labelHeight, alignment: .leading)
            content
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, FormRowMetrics.verticalPadding)
    }
}

/// A card of rows, which VoiceOver reads under `label`: the rows one under the other with a hairline between two of
/// them. The card is padded 20 as every card is, so its padding above the first row and under the last is less by the
/// 10 points that a row has of its own.
private struct RowsCard<Content: View>: View {
    let label: String
    private let content: Content

    init(label: String, @ViewBuilder content: () -> Content) {
        self.label = label
        self.content = content()
    }

    var body: some View {
        VStack(spacing: 0) {
            content
        }
        .padding(.horizontal, DesignMetrics.cardPadding)
        .padding(.vertical, DesignMetrics.cardPadding - FormRowMetrics.verticalPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
        .accessibilityElement(children: .contain)
        .accessibilityLabel(label)
    }
}

/// "Náhled PDF": the aside with the page of the invoice as it prints, as large as the width allows, on the fill of the
/// design. It is 461 points wide: the 429 points that the prototype gives it as the basis of its width, and 16 points
/// of padding on either side, which the prototype's box model adds to the width (`width`). The page is cut to the
/// paper: an invoice that does not fit it draws below it, and what is cut is not the editor's to judge (the check of
/// the page is `InvoicePDFRenderer.fitsOnOnePage`).
struct PreviewPane: View {
    let document: InvoiceDocument?

    /// The padding of the aside at either side.
    private static let sidePadding: CGFloat = 16

    /// The width the page has in the aside: 429 points, the basis of the width of the aside in the prototype
    /// (`flex: 0 1 429px`).
    static let contentWidth: CGFloat = 429

    /// The width of the aside, 461 points. The prototype sets no `box-sizing`, so the padding of its aside comes to
    /// the width of its basis, and its page, which is a fixed 397 points there, fills the 429 here.
    static let width: CGFloat = contentWidth + 2 * sidePadding

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Náhled PDF")
                .font(Typography.headline)
                .foregroundStyle(Palette.text)
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
                        .paperPage(on: Palette.fill)
                }
                .aspectRatio(PageSize.a4.width / PageSize.a4.height, contentMode: .fit)
            } else {
                Text("Náhled se zobrazí, až bude faktura úplná.")
                    .font(Typography.callout)
                    .foregroundStyle(Palette.text2)
                    .frame(maxWidth: .infinity, minHeight: 120)
            }
        }
        .padding(.horizontal, Self.sidePadding)
        .padding(.top, 14)
        .padding(.bottom, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.fill, in: RoundedRectangle(cornerRadius: DesignMetrics.cardRadius))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Náhled PDF")
    }
}
