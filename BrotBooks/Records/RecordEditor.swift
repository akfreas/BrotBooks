import SwiftData
import SwiftUI
import BrotBooksKit

/// Edit an existing record or create a new one.
struct RecordEditor: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @Environment(\.horizontalSizeClass) private var sizeClass
    @State private var width: CGFloat = 0

    let target: EditorTarget
    /// Set while stepping through drafts with Review Drafts.
    var review: ReviewStep?

    @State private var record: RecordSnapshot?
    @State private var initial = EditForm.State()
    @State private var form = EditForm.State()
    @State private var pendingDocument: Data?
    @State private var error: String?
    /// Why the last Approve was refused, shown next to each field.
    @State private var issues: [RecordIssue] = []
    @State private var notice: LocalizedStringKey?
    @State private var loaded = false
    @State private var confirmingDiscard = false

    private var kind: Kind { target.kind }
    /// Form and PDF side by side when there is room (Mac, iPad page sheets); stacked on iPhone.
    private var sideBySide: Bool {
        #if os(macOS)
        true
        #else
        sizeClass != .compact || width >= 760
        #endif
    }
    private var isNew: Bool { if case .new = target { true } else { false } }
    private var changes: [String: FieldInput] { EditForm.changedFields(kind, initial: initial, current: form) }
    private var canSave: Bool { isNew || !changes.isEmpty }
    /// Unsaved edits: Cancel asks before discarding them and the sheet can't be swiped away.
    private var isDirty: Bool { !changes.isEmpty || pendingDocument != nil }

    var body: some View {
        NavigationStack {
            Group {
                if !sideBySide {
                    formView
                } else {
                    HStack(spacing: 0) {
                        formView.frame(minWidth: 360, idealWidth: 420, maxWidth: 480)
                        Divider()
                        documentPane.frame(minWidth: 320, maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
            }
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
            .navigationTitle(title)
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar { toolbar }
        }
        #if os(macOS)
        .frame(minWidth: 860, idealWidth: 1040, minHeight: 600, idealHeight: 720)
        #else
        .modifier(PageSheetSizing())
        #endif
        .interactiveDismissDisabled(isDirty)
        .onAppear(perform: load)
    }

    private var title: Text {
        if isNew { return Text(kind == .income ? "New Income" : "New Expense") }
        return Text(verbatim: record?.description ?? record?.extraction?.sourceFilename ?? String(localized: "Untitled"))
    }

    private func issue(_ field: String) -> RecordIssue? { issues.first { $0.field == field } }

    /// Why a draft's field needs a second look (a warning or low confidence from extraction), until the user
    /// changes that field.
    private func flag(_ field: String) -> ExtractionInfo.Flag? {
        guard let record, record.isDraft, let extraction = record.extraction,
              changes[field] == nil, !extraction.editedFields.contains(field) else { return nil }
        return extraction.flag(for: field)
    }

    // MARK: Form

    private var formView: some View {
        Form {
            if let record {
                Section { header(record) }
                if record.isDraft, let extraction = record.extraction,
                   extraction.state == .failed || extraction.state == .unavailable {
                    Section { extractionNote(extraction) }
                }
                if record.isDraft, let warnings = record.extraction?.warnings.filter({ $0.field == nil }), !warnings.isEmpty {
                    Section {
                        ForEach(warnings, id: \.self) { FlagText(flag: .warning($0)) }
                    }
                }
            }
            Section {
                ForEach(EditForm.fields(kind)) { field in
                    FieldEditor(field: field, form: $form, suggestions: suggestions(for: field), issue: issue(field.name),
                                flag: flag(field.name))
                }
            }
            vatSection
            if let record {
                Section {
                    LabeledContent("Gross (EUR)", value: Money.format(record.convertedGrossAmount))
                        .accessibilityIdentifier("editor.gross")
                    LabeledContent("VAT", value: Money.format(record.totalVatAmount))
                        .accessibilityIdentifier("editor.vat")
                    LabeledContent("Net", value: Money.format(record.netAmount))
                        .accessibilityIdentifier("editor.net")
                } header: {
                    Text("Calculated")
                } footer: {
                    Text(record.sortedRef == nil
                         ? "EUR gross, VAT and net are recalculated when you change the amount, currency or VAT."
                         : "EUR gross, VAT and net are recalculated when you change the amount, currency or VAT. Imported from Sorted: a newer export that changes this record overwrites local edits.")
                }
            } else {
                Section {
                    Text("EUR gross, VAT and net are calculated when you save.").foregroundStyle(.secondary)
                }
            }
            if !sideBySide {
                Section("Document") {
                    NavigationLink {
                        documentPane
                            .navigationTitle(Text("Document"))
                            #if os(iOS)
                            .navigationBarTitleDisplayMode(.inline)
                            #endif
                    } label: {
                        Label(hasDocument ? "View Document" : "Attach PDF", systemImage: hasDocument ? "doc.richtext" : "paperclip")
                    }
                    .accessibilityIdentifier("editor.document")
                }
            }
            if let error {
                Section {
                    Label { Text(verbatim: error) } icon: { Image(systemName: "exclamationmark.triangle.fill") }
                        .foregroundStyle(.red)
                        .accessibilityAddTraits(.updatesFrequently)
                }
            }
        }
        .formStyle(.grouped)
        // Review Drafts: the queue controls stay in reach however far the form is scrolled.
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if let review, let record, record.isDraft, record.removedAt == nil {
                reviewBar(review)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(.bar)
                    .overlay(alignment: .top) { Divider() }
            }
        }
    }

    /// Review Drafts: where this draft is in the queue, Skip (⌘→) and Approve & Next (⌘↩).
    private func reviewBar(_ review: ReviewStep) -> some View {
        HStack(spacing: 10) {
            Text("\(review.position) of \(review.count)")
                .font(.callout)
                .foregroundStyle(.secondary)
                .monospacedDigit()
                .lineLimit(1)
                .fixedSize()
                .accessibilityIdentifier("review.counter")
            Spacer(minLength: 4)
            Button(action: skip) {
                Label("Skip", systemImage: "arrow.right").labelStyle(.titleAndIcon).lineLimit(1)
            }
            .buttonStyle(.bordered)
            .fixedSize()
            .keyboardShortcut(.rightArrow, modifiers: .command)
            .help(Text("Keep this draft for later and show the next one"))
            .accessibilityIdentifier("review.skip")
            Button(action: approve) {
                Label("Approve & Next", systemImage: "checkmark").labelStyle(.titleAndIcon).lineLimit(1)
            }
            .buttonStyle(.borderedProminent)
            .fixedSize()
            .keyboardShortcut(.return, modifiers: .command)
            .help(Text("Save your changes, count this expense in your totals and show the next draft"))
            .accessibilityIdentifier("review.approveNext")
        }
    }

    /// A draft whose details couldn't be read automatically: what to do, and why.
    private func extractionNote(_ extraction: ExtractionInfo) -> some View {
        Label {
            VStack(alignment: .leading, spacing: 2) {
                Text("Couldn't read this invoice. Fill it in by hand.")
                if let reason = extraction.failureReason, !reason.isEmpty {
                    Text(verbatim: reason).font(.caption).foregroundStyle(.secondary)
                }
            }
        } icon: {
            Image(systemName: "exclamationmark.circle.fill").foregroundStyle(Theme.amber)
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("editor.extractionNote")
    }

    private var hasDocument: Bool { record?.documentPath != nil || pendingDocument != nil }

    private func header(_ record: RecordSnapshot) -> some View {
        let info = HStack(spacing: 12) {
            RecordAvatar(record: record, size: 40)
            VStack(alignment: .leading, spacing: 4) {
                Text("\(Text(kind.singular)) · \(Dates.long(record.date))").font(.caption).foregroundStyle(.secondary)
                    .lineLimit(1)
                    .fixedSize()
                HStack(spacing: 8) {
                    // A draft without an amount (not read yet, or in a foreign currency without a rate).
                    Text(verbatim: record.isDraft && record.convertedGrossAmount == nil
                         ? "—" : Money.format(record.convertedGrossAmount))
                        .font(.title3.weight(.semibold))
                        .monospacedDigit()
                        .lineLimit(1)
                        .fixedSize()
                        .foregroundStyle(kind == .income ? Theme.moneyIn : .primary)
                    if kind == .income {
                        PaymentPill(status: record.paymentStatus).fixedSize().accessibilityIdentifier("editor.paymentStatus")
                    }
                    if record.isDraft { DraftPill().fixedSize().accessibilityIdentifier("editor.draftPill") }
                    if record.removedAt != nil { Pill(text: Text("Removed"), tint: Theme.bad).fixedSize() }
                }
                if kind == .income, record.isPaid, let date = record.paymentDate {
                    Text("Paid on \(Dates.long(date))").font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        return ViewThatFits(in: .horizontal) {
            HStack(spacing: 12) {
                info
                Spacer(minLength: 8)
                headerAction(record)
            }
            VStack(alignment: .leading, spacing: 12) {
                info
                headerAction(record)
            }
        }
    }

    @ViewBuilder private func headerAction(_ record: RecordSnapshot) -> some View {
        if let notice {
            Label { Text(notice) } icon: { Image(systemName: "checkmark.circle.fill") }
                .font(.callout)
                .foregroundStyle(Theme.moneyIn)
                .fixedSize()
                .accessibilityIdentifier("editor.notice")
        } else if kind == .income && !record.isPaid {
            Button(action: markPaid) {
                Label("Mark as Paid", systemImage: "checkmark").labelStyle(.titleAndIcon).lineLimit(1)
            }
                .buttonStyle(.bordered)
                .fixedSize()
                .help(Text("Set payment status to Paid with today's date"))
                .accessibilityIdentifier("editor.markPaid")
        } else if record.isDraft && record.removedAt == nil && review == nil {
            Button(action: approve) {
                Label("Approve", systemImage: "checkmark").labelStyle(.titleAndIcon).lineLimit(1)
            }
                .buttonStyle(.bordered)
                .fixedSize()
                .help(Text("Save your changes and count this expense in your totals"))
                .accessibilityIdentifier("editor.approve")
        }
    }

    private var vatSection: some View {
        Section {
            if form.vat.isEmpty {
                Text("No VAT on this record.").foregroundStyle(.secondary)
            }
            ForEach(form.vat.indices, id: \.self) { i in
                HStack(spacing: 10) {
                    TextField("Rate", text: $form.vat[i].rate, prompt: Text(verbatim: "19"))
                        .frame(maxWidth: 70)
                        .accessibilityLabel(Text("VAT rate in percent"))
                        .accessibilityIdentifier("vat.rate.\(i)")
                    Text(verbatim: "%").foregroundStyle(.secondary)
                    Spacer(minLength: 4)
                    Text(verbatim: "€").foregroundStyle(.secondary)
                    TextField("Amount", text: $form.vat[i].amount, prompt: Text(verbatim: "0.00"))
                        .multilineTextAlignment(.trailing)
                        .frame(maxWidth: 120)
                        .accessibilityLabel(Text("VAT amount in euros"))
                        .accessibilityIdentifier("vat.amount.\(i)")
                    Button(role: .destructive) { form.vat.remove(at: i) } label: {
                        Label("Remove VAT rate", systemImage: "minus.circle.fill")
                    }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.borderless)
                    .foregroundStyle(.red)
                }
                .labelsHidden()
                .monospacedDigit()
                #if os(iOS)
                .keyboardType(.decimalPad)
                #endif
                #if os(macOS)
                .textFieldStyle(.roundedBorder)
                #endif
            }
            Button { form.vat.append(VatRowInput(rate: "19", amount: "")) } label: {
                Label("Add VAT Rate", systemImage: "plus.circle")
            }
            .buttonStyle(.borderless)
            .accessibilityIdentifier("vat.add")
        } header: {
            Text("VAT")
        } footer: {
            if issue("vat_rates") != nil || flag("vat_rates") != nil {
                VStack(alignment: .leading, spacing: 4) {
                    if let issue = issue("vat_rates") { IssueText(issue: issue).accessibilityIdentifier("issue.vat_rates") }
                    if let flag = flag("vat_rates") { FlagText(flag: flag).accessibilityIdentifier("flag.vat_rates") }
                }
            }
        }
    }

    private func suggestions(for field: FormField) -> [String] {
        switch field.suggestions {
        case "categories": return app.categories
        case "currencies": return EditForm.currencies
        default: return []
        }
    }

    // MARK: Document

    private var documentPane: some View {
        DocumentPane(path: record?.documentPath, pending: pendingDocument, documents: app.store?.documents) { data in
            if let id = record?.id {
                do {
                    try app.attach(data, to: id)
                    reload(id)
                } catch {
                    self.error = error.localizedDescription
                }
            } else {
                pendingDocument = data
            }
        }
    }

    // MARK: Toolbar and actions

    @ToolbarContentBuilder private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button("Cancel") { if isDirty { confirmingDiscard = true } else { dismiss() } }
                .accessibilityIdentifier("editor.cancel")
                .confirmationDialog(Text("Discard your changes?"), isPresented: $confirmingDiscard, titleVisibility: .visible) {
                    Button("Discard Changes", role: .destructive) { dismiss() }
                    Button("Keep Editing", role: .cancel) {}
                }
        }
        ToolbarItem(placement: .confirmationAction) {
            Button(isNew ? "Add" : "Save", action: save)
                .disabled(!canSave)
                .keyboardShortcut("s", modifiers: .command)
                .accessibilityIdentifier("editor.save")
        }
        if let record {
            ToolbarItem(placement: .automatic) {
                Menu {
                    if record.removedAt == nil {
                        Button("Remove Record", systemImage: "trash", role: .destructive) { setRemoved(true) }
                            .accessibilityIdentifier("editor.remove")
                    } else {
                        Button("Restore Record", systemImage: "arrow.uturn.backward") { setRemoved(false) }
                            .accessibilityIdentifier("editor.restore")
                    }
                } label: {
                    Label("More", systemImage: "ellipsis.circle")
                }
                .accessibilityIdentifier("editor.more")
            }
        }
    }

    private func load() {
        guard !loaded else { return }
        loaded = true
        switch target {
        case .existing(let id, _):
            reload(id)
            issues = app.takePendingIssues(id)
        case .new(let kind):
            initial = EditForm.newState(kind, today: app.today)
            form = initial
        }
    }

    /// Reloads the record from the store; `keepingEdits` re-applies unsaved edits on top.
    private func reload(_ id: PersistentIdentifier, keepingEdits: Bool = true) {
        guard let snapshot = app.snapshot(id) else { return }
        let fresh = EditForm.initialState(kind, values: snapshot.values)
        // Keep unsaved edits to fields other than those that just changed in the store.
        let pending = keepingEdits ? changes : [:]
        record = snapshot
        initial = fresh
        form = fresh
        for (name, input) in pending {
            switch input {
            case .text(let s): form.text[name] = s
            case .null: form.text[name] = ""
            case .bool(let b): form.flags[name] = b
            case .vatRates(let rows): form.vat = rows
            }
        }
    }

    /// For a draft this saves the edits and it stays a draft; only Approve finalizes it.
    private func save() {
        error = nil
        issues = []
        do {
            switch target {
            case .existing(let id, _):
                if !changes.isEmpty { try app.save(id, changes: changes) }
            case .new(let kind):
                try app.create(kind, fields: EditForm.createFields(kind, state: form), document: pendingDocument)
            }
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func markPaid() {
        guard let id = record?.id else { return }
        error = nil
        do {
            try app.markPaid(id)
            reload(id)
            notice = "Marked as paid"
        } catch {
            self.error = error.localizedDescription
        }
    }

    /// Review Drafts: keeps the edits (the draft stays a draft) and moves on to the next draft.
    private func skip() {
        guard let id = record?.id, let review else { return }
        error = nil
        do {
            if !changes.isEmpty { try app.save(id, changes: changes) }
            review.next()
        } catch {
            self.error = error.localizedDescription
        }
    }

    /// Saves pending edits (the draft stays a draft if approval then fails), then approves. Validation problems
    /// show next to their fields.
    private func approve() {
        guard let id = record?.id else { return }
        error = nil
        issues = []
        do {
            if !changes.isEmpty {
                try app.save(id, changes: changes)
                reload(id, keepingEdits: false)
            }
            try app.approve(id)
            if let review {
                review.next()
                return
            }
            reload(id)
            notice = "Approved"
        } catch let failure as ApprovalError {
            issues = failure.issues
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func setRemoved(_ removed: Bool) {
        guard let id = record?.id else { return }
        do {
            try app.setRemoved(id, removed)
            if removed, let review {
                review.next()
            } else if removed {
                dismiss()
            } else {
                reload(id)
            }
        } catch {
            self.error = error.localizedDescription
        }
    }
}

/// One form field, rendered natively for its type.
struct FieldEditor: View {
    let field: FormField
    @Binding var form: EditForm.State
    let suggestions: [String]
    /// Why approval was refused for this field.
    var issue: RecordIssue?
    /// Why extraction flagged this field for a second look.
    var flag: ExtractionInfo.Flag?

    private var text: Binding<String> {
        Binding { form.text[field.name] ?? "" } set: { form.text[field.name] = $0 }
    }

    private var identifier: String { "field.\(field.name)" }

    var body: some View {
        if issue != nil || flag != nil {
            VStack(alignment: .leading, spacing: 4) {
                control
                if let issue { IssueText(issue: issue).accessibilityIdentifier("issue.\(field.name)") }
                if let flag { FlagText(flag: flag).accessibilityIdentifier("flag.\(field.name)") }
            }
        } else {
            control
        }
    }

    @ViewBuilder private var control: some View {
        switch field.type {
        case .checkbox:
            Toggle(LocalizedStringKey(field.label), isOn: Binding {
                form.flags[field.name] ?? false
            } set: { form.flags[field.name] = $0 })
            .accessibilityIdentifier(identifier)
        case .select:
            Picker(LocalizedStringKey(field.label), selection: text) {
                Text(verbatim: "—").tag("")
                ForEach(field.options, id: \.self) { Text(LocalizedStringKey($0)).tag($0) }
                if !text.wrappedValue.isEmpty && !field.options.contains(text.wrappedValue) {
                    Text(verbatim: text.wrappedValue).tag(text.wrappedValue)
                }
            }
            .accessibilityIdentifier(identifier)
        case .date:
            OptionalDateField(label: LocalizedStringKey(field.label), iso: text, clearable: field.name != "date")
        case .text, .number:
            #if os(iOS)
            // The label keeps its full width and the field takes the rest; the description wraps onto more lines
            // instead of squeezing the label (a single-line field wider than the row made the cell re-layout forever).
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(LocalizedStringKey(field.label))
                    .fixedSize()
                fieldControls
            }
            #else
            LabeledContent { fieldControls } label: { Text(LocalizedStringKey(field.label)) }
            #endif
        }
    }

    private var fieldControls: some View {
        HStack(spacing: 6) {
            TextField(LocalizedStringKey(field.label), text: text,
                      prompt: field.hint.map { Text(LocalizedStringKey($0)) } ?? Text(verbatim: ""),
                      axis: field.wide ? .vertical : .horizontal)
                .lineLimit(field.wide ? 1...4 : 1...1)
                .labelsHidden()
                .multilineTextAlignment(.trailing)
                .monospacedDigit()
                .frame(maxWidth: .infinity, alignment: .trailing)
                .accessibilityIdentifier(identifier)
                #if os(iOS)
                .keyboardType(field.type == .number ? .decimalPad : .default)
                .textInputAutocapitalization(field.name == "currency" ? .characters : .sentences)
                #endif
            if !suggestions.isEmpty {
                Menu {
                    ForEach(suggestions, id: \.self) { s in Button(s) { text.wrappedValue = s } }
                } label: {
                    Image(systemName: "chevron.up.chevron.down").imageScale(.small)
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .accessibilityLabel(Text("Suggestions for \(Text(LocalizedStringKey(field.label)))"))
            }
        }
    }
}

/// An approval problem with one field, shown under it.
struct IssueText: View {
    let issue: RecordIssue

    var body: some View {
        Label { issue.text } icon: { Image(systemName: "exclamationmark.circle.fill") }
            .font(.caption)
            .foregroundStyle(.red)
            .accessibilityElement(children: .combine)
    }
}

extension RecordIssue {
    /// The localized message for the editor (the kit's `message` is English).
    var text: Text {
        switch code {
        case .missingDate: Text("Enter the invoice date")
        case .missingGrossAmount: Text("Enter the gross amount")
        case .missingConversionRate: Text("Enter the conversion rate to EUR")
        case .vatInvalid: Text("VAT rates must be between 0 and 100, and a zero rate can't have an amount")
        case .vatMismatch: Text("VAT doesn't add up to the gross amount")
        }
    }
}

/// A field extraction flagged: a subtle orange marker and a one-line reason.
struct FlagText: View {
    let flag: ExtractionInfo.Flag

    var body: some View {
        Label {
            switch flag {
            case .warning(let warning): warning.text
            case .lowConfidence: Text("Check this value – it may have been misread")
            }
        } icon: {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Theme.amber)
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .accessibilityElement(children: .combine)
    }
}

extension ExtractionInfo.Warning {
    /// The localized message for the editor (the kit's `message` is English); unknown codes show `message`.
    var text: Text {
        switch code {
        case .vatMismatch: Text("VAT didn't add up to the total")
        case .foreignCurrency: Text("Foreign currency – enter the rate")
        case .implausibleDate: Text("Check the date – it looks wrong")
        case nil: Text(verbatim: message)
        }
    }
}

/// Review Drafts: the editor's place in the queue and how to move on.
struct ReviewStep {
    /// 1-based position of this draft in the queue.
    var position: Int
    var count: Int
    /// Shows the next draft, or closes the review after the last one.
    var next: () -> Void
}

/// A date that may be empty (e.g. payment date): "Add" button, or a DatePicker with a clear button.
struct OptionalDateField: View {
    let label: LocalizedStringKey
    @Binding var iso: String
    var clearable = true

    var body: some View {
        LabeledContent {
            if let date = Dates.date(iso) {
                HStack(spacing: 6) {
                    DatePicker(label, selection: Binding { date } set: { iso = Dates.iso($0) }, displayedComponents: .date)
                        .labelsHidden()
                    if clearable {
                        Button { iso = "" } label: { Label("Clear", systemImage: "xmark.circle.fill") }
                            .labelStyle(.iconOnly)
                            .buttonStyle(.borderless)
                            .foregroundStyle(.secondary)
                    }
                }
            } else {
                Button("Add Date") { iso = ISODate.today() }.buttonStyle(.borderless)
            }
        } label: {
            Text(label)
        }
    }
}

#if os(iOS)
/// iPad: a page-sized sheet so the PDF fits beside the form.
private struct PageSheetSizing: ViewModifier {
    func body(content: Content) -> some View {
        content.presentationSizing(.page)
    }
}
#endif

/// Review Drafts: the editor on one draft at a time, moving on after Approve & Next, Skip or Remove. Drafts that
/// were approved or removed elsewhere in the meantime are passed over; the sheet closes after the last one.
struct DraftReviewSheet: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    let queue: [PersistentIdentifier]
    @State private var index = 0

    var body: some View {
        if index < queue.count {
            RecordEditor(target: .existing(queue[index], .expenses),
                         review: ReviewStep(position: index + 1, count: queue.count, next: advance))
                // A fresh editor (form state, issues) for each draft.
                .id(queue[index])
        }
    }

    private func advance() {
        var next = index + 1
        while next < queue.count, !isOpenDraft(queue[next]) { next += 1 }
        if next < queue.count { index = next } else { dismiss() }
    }

    private func isOpenDraft(_ id: PersistentIdentifier) -> Bool {
        guard let record = app.snapshot(id) else { return false }
        return record.isDraft && record.removedAt == nil
    }
}
