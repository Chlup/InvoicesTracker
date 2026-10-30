import SwiftUI

/// Šablony faktur: a card for every template with its client, its items, and its due days and VAT mode; Použít
/// starts an invoice from it, Upravit opens its form, and Nová šablona opens the form of a new one. The line over the
/// cards says what the descriptions may hold. The title and the line under it are the shell's. The data is loaded again
/// whenever what it depends on changes.
///
/// The page fills the room the window gives it and asks for no minimum size of its own: it scrolls.
struct TemplatesScreen: View {
    let app: AppModel
    @State private var model: TemplatesModel

    /// The form that is open as a sheet.
    @State private var form: TemplateFormModel?

    init(app: AppModel) {
        self.app = app
        _model = State(initialValue: TemplatesModel(app: app))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                topRow
                content
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 20)
        }
        .task(id: app.reloadKey) {
            await model.load()
        }
        .sheet(item: $form) { form in
            TemplateForm(model: form, cancel: { self.form = nil }, finished: { self.form = nil })
                .idleLockCover()
        }
    }

    /// What the descriptions may hold, and Nová šablona.
    private var topRow: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .center, spacing: 10) {
                hint
                Spacer(minLength: 12)
                newTemplateButton
            }
            VStack(alignment: .leading, spacing: 10) {
                hint
                newTemplateButton
            }
        }
    }

    private var hint: some View {
        Text(verbatim: TemplateFormModel.placeholderHint)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var newTemplateButton: some View {
        Button {
            form = model.newTemplateForm()
        } label: {
            Label("Nová šablona", systemImage: "plus")
                .labelStyle(.titleAndIcon)
        }
        .buttonStyle(.borderedProminent)
        .buttonBorderShape(.capsule)
        .controlSize(.large)
    }

    @ViewBuilder
    private var content: some View {
        if let cards = model.cards {
            if cards.isEmpty {
                Text("Zatím nemáte žádnou šablonu.")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 24)
            } else {
                AdaptiveColumns(minimumColumnWidth: 340, spacing: 16) {
                    ForEach(cards) { card in
                        TemplateCardView(
                            card: card,
                            use: {
                                model.use(card.id)
                            },
                            edit: {
                                form = model.form(editing: card.id)
                            })
                    }
                }
            }
        } else if let errorText = model.errorText {
            Text(verbatim: errorText)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
                .padding(.top, 40)
        }
    }
}

/// The card of a template.
private struct TemplateCardView: View {
    let card: TemplateCard

    /// Použít.
    let use: () -> Void

    /// Upravit.
    let edit: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(verbatim: card.name)
                .font(.system(size: 17, weight: .bold))
                .accessibilityAddTraits(.isHeader)
            Text(verbatim: card.client)
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 2) {
                ForEach(Array(card.itemLines.enumerated()), id: \.offset) { _, line in
                    Text(verbatim: line)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Text(verbatim: card.options)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 8) {
                Button("Použít", action: use)
                    .buttonStyle(.borderedProminent)
                    .accessibilityLabel("Použít šablonu \(card.name)")
                Button("Upravit", action: edit)
                    .buttonStyle(.bordered)
                    .accessibilityLabel("Upravit šablonu \(card.name)")
            }
            .buttonBorderShape(.capsule)
            .padding(.top, 6)
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
        .accessibilityElement(children: .contain)
    }
}
