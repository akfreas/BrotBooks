import SwiftData
import SwiftUI
import BrotBooksKit

extension Kind {
    var title: LocalizedStringKey { self == .income ? "Income" : "Expenses" }
    var singular: LocalizedStringKey { self == .income ? "Invoice" : "Expense" }
    var systemImage: String { self == .income ? "arrow.down.left.circle" : "arrow.up.right.circle" }
}

/// One record row: date, initials avatar, description, category or payment status, EUR amount.
/// In compact width (iPhone) the date moves under the description so the amount never wraps.
struct RecordRow: View {
    let record: RecordSnapshot
    var showsDate = true
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Environment(\.dynamicTypeSize) private var typeSize

    /// Date in its own column only when there's room for it.
    private var dateColumn: Bool { showsDate && sizeClass != .compact && !typeSize.isAccessibilitySize }

    var body: some View {
        HStack(spacing: 12) {
            if dateColumn {
                Text(verbatim: Dates.short(record.date))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                    .lineLimit(1)
                    .fixedSize()
                    .frame(minWidth: 50, alignment: .leading)
            }
            if !typeSize.isAccessibilitySize { RecordAvatar(record: record) }
            VStack(alignment: .leading, spacing: 3) {
                Text(verbatim: record.description ?? record.extraction?.sourceFilename ?? String(localized: "Untitled"))
                    .font(.body)
                    .lineLimit(typeSize.isAccessibilitySize ? 3 : 1)
                    .truncationMode(.tail)
                HStack(spacing: 6) {
                    if showsDate && !dateColumn {
                        Text(verbatim: Dates.short(record.date))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                            .lineLimit(1)
                            .fixedSize()
                    }
                    secondary
                }
            }
            .layoutPriority(1)
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 3) {
                Text(verbatim: amountText)
                    .font(.body.weight(.medium))
                    .monospacedDigit()
                    .lineLimit(1)
                    .fixedSize()
                    .foregroundStyle(record.kind == .income ? Theme.moneyIn : .primary)
                if record.currency != "EUR", let gross = record.grossAmount {
                    Text(verbatim: Money.formatForeign(gross, currency: record.currency))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                        .lineLimit(1)
                        .fixedSize()
                }
            }
            if sizeClass != .compact {
                Image(systemName: "doc")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .opacity(record.hasDocument ? 1 : 0)
                    .accessibilityHidden(true)
            }
        }
        .padding(.vertical, 6)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityHint(Text(record.kind == .income ? "Opens the invoice" : "Opens the expense"))
    }

    private var amountText: String {
        // A draft without an amount (not read yet, or in a foreign currency without a rate).
        if record.isDraft && record.convertedGrossAmount == nil { return "—" }
        let amount = record.convertedGrossAmount ?? 0
        return record.kind == .income ? Money.format(amount, signed: true) : Money.format(-amount)
    }

    @ViewBuilder private var secondary: some View {
        if record.removedAt != nil {
            Pill(text: Text("Removed"), tint: Theme.bad)
        } else if record.isDraft {
            if record.extraction?.state == .pending {
                ProgressView()
                    .controlSize(.mini)
                    .accessibilityLabel(Text("Reading the invoice…"))
            } else if record.extraction?.looksComplete == true {
                Pill(text: Text("Looks complete"), tint: Theme.moneyIn)
            } else {
                DraftPill()
            }
        } else if record.kind == .expenses {
            Text(verbatim: record.category ?? String(localized: "Uncategorized"))
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.tail)
        } else {
            PaymentPill(status: record.paymentStatus)
        }
    }
}

/// The initials avatar, or a document symbol for a draft that has no description yet.
struct RecordAvatar: View {
    let record: RecordSnapshot
    var size: CGFloat = 32

    var body: some View {
        if record.description?.isEmpty ?? true {
            Image(systemName: "doc.text")
                .font(.system(size: size * 0.42))
                .foregroundStyle(Theme.avatarText)
                .frame(width: size, height: size)
                .background(Theme.avatar, in: Circle())
                .accessibilityHidden(true)
        } else {
            Avatar(text: record.description, size: size)
        }
    }
}

/// Marks an unapproved draft expense.
struct DraftPill: View {
    var body: some View {
        Pill(text: Text("Draft"), tint: Theme.amber)
    }
}

struct PaymentPill: View {
    let status: String?

    var body: some View {
        if status == "Paid" {
            Pill(text: Text("Paid"), tint: Theme.moneyIn)
        } else {
            Pill(text: Text("Unpaid"), tint: Theme.amber)
        }
    }
}

/// Dashboard card: Income / Expenses tabs over the selected year's records, 25 per page.
struct RecordListCard: View {
    @Environment(AppModel.self) private var app
    @State private var kind = Kind.income
    @State private var page = 0
    private let pageSize = 25

    var body: some View {
        let _ = app.revision
        let records = app.records(kind)
        let pages = max(1, (records.count + pageSize - 1) / pageSize)
        let current = min(page, pages - 1)
        let slice = records.dropFirst(current * pageSize).prefix(pageSize)
        VStack(alignment: .leading, spacing: 8) {
            Picker("Record type", selection: $kind) {
                ForEach(Kind.allCases.reversed()) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(.bottom, 4)

            if records.isEmpty {
                ContentUnavailableView {
                    Label(kind == .income ? "No income in \(String(app.selectedYear))" : "No expenses in \(String(app.selectedYear))",
                          systemImage: kind.systemImage)
                } description: {
                    Text(app.searchText.isEmpty ? "Records you add or import appear here." : "Nothing matches your search.")
                }
                .frame(minHeight: 240)
            } else {
                LazyVStack(spacing: 0) {
                    ForEach(Array(slice)) { record in
                        Button { app.open(record) } label: { RecordRow(record: record) }
                            .buttonStyle(.plain)
                        if record.id != slice.last?.id { Divider().opacity(0.6) }
                    }
                }
            }
            Divider()
            HStack {
                Text(verbatim: records.isEmpty ? "0" : "\(current * pageSize + 1)–\(current * pageSize + slice.count) of \(records.count)")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                Spacer()
                Button { page = current - 1 } label: { Label("Previous", systemImage: "chevron.left") }
                    .disabled(current == 0)
                Button { page = current + 1 } label: { Label("Next", systemImage: "chevron.right") }
                    .disabled(current >= pages - 1)
            }
            .labelStyle(.iconOnly)
            .buttonStyle(.borderless)
        }
        .card(padding: 16)
        .onChange(of: kind) { page = 0 }
        .onChange(of: app.selectedYear) { page = 0 }
        .onChange(of: app.searchText) { page = 0 }
    }
}

/// Full-height list of one kind (sidebar destination on Mac/iPad, tab on iPhone).
/// Expenses start with a Drafts section: drafts are approved by swipe, context menu or Approve Selected.
struct RecordsScreen: View {
    @Environment(AppModel.self) private var app
    let kind: Kind
    @State private var showsRemoved = false
    /// Drafts chosen for Approve Selected (Edit mode on iOS, ⌘-click on Mac). Only draft rows are selectable.
    @State private var selection = Set<PersistentIdentifier>()
    /// How many drafts Approve Selected left as drafts because they are incomplete.
    @State private var notApproved = 0
    #if os(iOS)
    @State private var editMode = EditMode.inactive
    #endif

    var body: some View {
        let _ = app.revision
        let records = app.records(kind)
        let drafts = kind == .expenses ? app.drafts() : []
        let removed = app.removedRecords(kind)
        let total = records.reduce(Decimal(0)) { $0 + ($1.convertedGrossAmount ?? 0) }
        let selectedDrafts = drafts.filter { selection.contains($0.id) }.map(\.id)
        ScrollViewReader { proxy in
            List(selection: $selection) {
                if !drafts.isEmpty {
                    draftsSection(drafts)
                }
                if records.isEmpty && drafts.isEmpty && !app.searchText.isEmpty {
                    ContentUnavailableView.search(text: app.searchText)
                        .listRowSeparator(.hidden)
                        .accessibilityElement(children: .contain)
                        .accessibilityIdentifier("records.empty")
                } else if records.isEmpty && app.searchText.isEmpty {
                    ContentUnavailableView {
                        Label(kind == .income ? "No income in \(String(app.selectedYear))" : "No expenses in \(String(app.selectedYear))",
                              systemImage: kind.systemImage)
                    } description: {
                        Text("Add a record or import a Sorted export.")
                    } actions: {
                        Button { app.newRecord(kind) } label: { Text(kind == .income ? "New Income" : "New Expense") }
                    }
                    .listRowSeparator(.hidden)
                    .accessibilityElement(children: .contain)
                    .accessibilityIdentifier("records.empty")
                } else if !records.isEmpty {
                    Section {
                        ForEach(Array(records.enumerated()), id: \.element.id) { index, record in
                            Button { app.open(record) } label: { RecordRow(record: record) }
                                .buttonStyle(.plain)
                                .accessibilityIdentifier("record.row.\(index)")
                                .selectionDisabled()
                                .contextMenu { RecordContextMenu(record: record) }
                                .swipeActions(edge: .trailing) {
                                    Button(role: .destructive) { try? app.setRemoved(record.id, true) } label: {
                                        Label("Remove", systemImage: "trash")
                                    }
                                }
                                .swipeActions(edge: .leading) {
                                    if record.kind == .income && !record.isPaid {
                                        Button { try? app.markPaid(record.id) } label: {
                                            Label("Mark as Paid", systemImage: "checkmark.circle")
                                        }
                                        .tint(Theme.moneyIn)
                                    }
                                }
                        }
                    } header: {
                        HStack {
                            Text("^[\(records.count) record](inflect: true)")
                            Spacer()
                            Text(verbatim: Money.format(total)).monospacedDigit()
                        }
                        .accessibilityElement(children: .combine)
                        .accessibilityIdentifier("records.header")
                    }
                }
                if !removed.isEmpty {
                    Section {
                        if showsRemoved {
                            ForEach(Array(removed.enumerated()), id: \.element.id) { index, record in
                                Button { app.open(record) } label: { RecordRow(record: record) }
                                    .buttonStyle(.plain)
                                    .accessibilityIdentifier("record.removed.\(index)")
                                    .selectionDisabled()
                                    .contextMenu { RecordContextMenu(record: record) }
                                    .swipeActions(edge: .trailing) {
                                        Button { try? app.setRemoved(record.id, false) } label: {
                                            Label("Restore", systemImage: "arrow.uturn.backward")
                                        }
                                        .tint(Theme.accent)
                                    }
                            }
                        }
                    } header: {
                        Button { showsRemoved.toggle() } label: {
                            HStack {
                                Text("Removed · \(removed.count)")
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .rotationEffect(.degrees(showsRemoved ? 90 : 0))
                                    .accessibilityHidden(true)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityValue(Text(showsRemoved ? "Shown" : "Hidden"))
                        .accessibilityHint(Text("Shows or hides removed records, which you can restore"))
                        .accessibilityIdentifier("records.removedToggle")
                    }
                }
            }
            // Draft rows are the only selectable ones: tap (Mac: double-click) opens, the menu acts on the selection.
            .contextMenu(forSelectionType: PersistentIdentifier.self) { ids in
                draftMenu(drafts.filter { ids.contains($0.id) })
            } primaryAction: { ids in
                if ids.count == 1, let record = drafts.first(where: { ids.contains($0.id) }) { app.open(record) }
            }
            .onAppear { revealDrafts(drafts, proxy) }
            .onChange(of: app.showDraftsRequested) { _, requested in if requested { revealDrafts(drafts, proxy) } }
        }
        .refreshable { app.handleRemoteChange() }
        .modifier(ExpensesDrop(enabled: kind == .expenses))
        .navigationTitle(Text(kind.title))
        .toolbar {
            #if os(iOS)
            // While choosing drafts, Approve Selected takes the New button's place (a bottom bar would sit under
            // the iPhone tab bar).
            if editMode.isEditing {
                ToolbarItem(placement: .primaryAction) {
                    approveSelectedButton(selectedDrafts)
                }
            } else {
                ToolbarItem(placement: .primaryAction) { newButton }
            }
            if !drafts.isEmpty {
                ToolbarItem(placement: .primaryAction) {
                    EditButton().accessibilityIdentifier("records.edit")
                }
            }
            #else
            ToolbarItem(placement: .primaryAction) { newButton }
            if !selectedDrafts.isEmpty {
                ToolbarItem(placement: .primaryAction) {
                    approveSelectedButton(selectedDrafts)
                }
            }
            #endif
        }
        #if os(iOS)
        .environment(\.editMode, $editMode)
        .onChange(of: drafts.isEmpty) { _, empty in if empty { editMode = .inactive } }
        #endif
        // Alert titles don't apply Markdown inflection, so it is resolved here.
        .alert(Text(verbatim: String(AttributedString(localized: "^[\(notApproved) draft](inflect: true) not approved").characters)),
               isPresented: Binding { notApproved > 0 } set: { if !$0 { notApproved = 0 } }) {
            Button("OK") { notApproved = 0 }
        } message: {
            Text("They are still selected. Open each one to fill in what's missing.")
        }
    }

    private func draftsSection(_ drafts: [RecordSnapshot]) -> some View {
        let sum = drafts.reduce(Decimal(0)) { $0 + ($1.convertedGrossAmount ?? 0) }
        return Section {
            ForEach(Array(drafts.enumerated()), id: \.element.id) { index, record in
                RecordRow(record: record)
                    .tag(record.id)
                    .accessibilityIdentifier("record.draft.\(index)")
                    .swipeActions(edge: .trailing) {
                        Button(role: .destructive) { try? app.setRemoved(record.id, true) } label: {
                            Label("Remove", systemImage: "trash")
                        }
                    }
                    .swipeActions(edge: .leading) {
                        Button { app.approveOrOpen(record) } label: {
                            Label("Approve", systemImage: "checkmark.circle")
                        }
                        .tint(Theme.moneyIn)
                    }
            }
        } header: {
            HStack {
                HStack(spacing: 4) {
                    Text("Drafts")
                    Text(verbatim: "(\(drafts.count))").monospacedDigit()
                }
                Spacer()
                Text("\(Money.format(sum)) not counted").monospacedDigit()
            }
            .help(Text("Not counted in totals"))
            .accessibilityElement(children: .combine)
            .accessibilityHint(Text("Not counted in totals"))
            .accessibilityIdentifier("records.drafts")
        }
    }

    @ViewBuilder private func draftMenu(_ chosen: [RecordSnapshot]) -> some View {
        if chosen.count == 1, let record = chosen.first {
            RecordContextMenu(record: record)
        } else if chosen.count > 1 {
            Button("Approve Selected") { approveSelected(chosen.map(\.id)) }
            Divider()
            Button("Remove", role: .destructive) {
                for record in chosen { try? app.setRemoved(record.id, true) }
            }
        }
    }

    private var newButton: some View {
        Button { app.newRecord(kind) } label: {
            Label(kind == .income ? "New Income" : "New Expense", systemImage: "plus")
        }
        .accessibilityIdentifier(kind == .income ? "newIncome" : "newExpense")
    }

    private func approveSelectedButton(_ ids: [PersistentIdentifier]) -> some View {
        Button { approveSelected(ids) } label: {
            Label("Approve Selected", systemImage: "checkmark.circle")
        }
        .labelStyle(.titleAndIcon)
        .disabled(ids.isEmpty)
        .accessibilityIdentifier("records.approveSelected")
    }

    /// Approves the chosen drafts; incomplete ones stay selected and an alert says how many.
    private func approveSelected(_ ids: [PersistentIdentifier]) {
        do {
            guard let result = try app.approveAll(ids) else { return }
            selection = Set(result.failed.map(\.id))
            notApproved = result.failed.count
            #if os(iOS)
            if result.failed.isEmpty { editMode = .inactive }
            #endif
        } catch {
            app.lastError = error.localizedDescription
        }
    }

    /// Answers the dashboard's drafts link: scroll to the top of the Drafts section.
    private func revealDrafts(_ drafts: [RecordSnapshot], _ proxy: ScrollViewProxy) {
        guard kind == .expenses, app.showDraftsRequested else { return }
        app.showDraftsRequested = false
        if let first = drafts.first { proxy.scrollTo(first.id, anchor: .top) }
    }
}

struct RecordContextMenu: View {
    @Environment(AppModel.self) private var app
    let record: RecordSnapshot

    var body: some View {
        Button("Open") { app.open(record) }
        if record.removedAt != nil {
            Button("Restore") { try? app.setRemoved(record.id, false) }
        } else {
            if record.kind == .income && !record.isPaid {
                Button("Mark as Paid") { try? app.markPaid(record.id) }
            }
            if record.isDraft {
                Button("Approve") { app.approveOrOpen(record) }
            }
            Divider()
            Button("Remove", role: .destructive) { try? app.setRemoved(record.id, true) }
        }
    }
}

/// Invoices dropped onto the Expenses list become draft expenses.
private struct ExpensesDrop: ViewModifier {
    let enabled: Bool

    func body(content: Content) -> some View {
        if enabled { content.invoiceDropTarget() } else { content }
    }
}
