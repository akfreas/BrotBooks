import Foundation
import Observation
import os
import SwiftData
import BrotBooksKit

/// The editor sheet's subject: an existing record or a new one of a kind.
enum EditorTarget: Identifiable, Hashable {
    case existing(PersistentIdentifier, Kind)
    case new(Kind)

    var id: String {
        switch self {
        case .existing(let id, _): return "\(id.hashValue)"
        case .new(let kind): return "new-\(kind.rawValue)"
        }
    }

    var kind: Kind {
        switch self {
        case .existing(_, let kind), .new(let kind): return kind
        }
    }
}

/// Review Drafts: the drafts to step through in the editor, in list order.
struct DraftReview: Identifiable {
    let id = UUID()
    let ids: [PersistentIdentifier]
}

/// Everything the dashboard shows for the selected year, computed from the active records.
struct DashboardData {
    var window: DashboardWindow
    var taxes: TaxEstimate?
    var months: Summary
    var previous: SummaryRow
    var profit: [DashboardMath.ProfitPoint]
    var recordCount: Int
}

@MainActor
@Observable
final class AppModel {
    enum Phase {
        case loading
        case ready
        case failed(String)
    }

    private(set) var phase = Phase.loading
    private(set) var storage: Storage?
    private(set) var store: RecordStore?

    var selectedYear = ISODate.year(LaunchOptions.fixedToday ?? ISODate.today()) ?? 2026
    var searchText = ""
    /// Set by Find (⌘F) to move focus into the toolbar search field.
    var searchFocusRequested = false
    var editor: EditorTarget?
    /// Review Drafts: the editor stepping through the drafts.
    var review: DraftReview?
    var showingImporter = false
    var showingSettings = false
    var importFlow: ImportFlow?
    /// Import Invoices… (file picker), Choose Photos… and Scan Documents… (iOS).
    var showingInvoiceImporter = false
    var showingPhotoPicker = false
    var showingScanner = false
    /// The invoice import queue; its panel shows while it has files.
    private(set) var invoiceImport: InvoiceImportFlow?
    var lastError: String?
    /// Set by the dashboard's drafts link: show the Expenses list scrolled to its Drafts section.
    var showDraftsRequested = false
    /// Why a draft approved from a list was refused, keyed by record; the editor shows them inline when it opens.
    @ObservationIgnored private var pendingIssues: [PersistentIdentifier: [RecordIssue]] = [:]

    /// Bumped on every local or remote change; views recompute when it changes.
    private(set) var revision = 0
    private(set) var dashboard: DashboardData?
    private(set) var yearOptions: [Int] = []
    private(set) var categories: [String] = []
    /// Draft expenses waiting for review (all years, not removed), for badges and the dashboard link.
    private(set) var draftCount = 0

    private let log = Logger(subsystem: "me.freas.BrotBooks", category: "app")

    /// The user's local date, or the pinned date in UI tests.
    var today: String { LaunchOptions.fixedToday ?? ISODate.today() }

    var isEmpty: Bool { (dashboard?.recordCount ?? 0) == 0 }

    func start() async {
        guard case .loading = phase else { return }
        do {
            let storage = try await Task.detached(priority: .userInitiated) { try await Storage.open() }.value
            self.storage = storage
            store = RecordStore(context: storage.container.mainContext, documents: storage.documents)
            try store?.dedupe()
            let wantsSample = Storage.sampleRequested || (LaunchOptions.uiTesting && !LaunchOptions.startsEmpty)
            if wantsSample, (try? store?.entries().isEmpty) == true {
                try SampleData.load(into: store!, today: today)
            }
            phase = .ready
            refresh()
            let currencies = Set((try? store!.snapshots(.expenses).map(\.currency)) ?? []).sorted()
            let flow = InvoiceImportFlow(store: store!, extractor: Self.invoiceExtractor(currencies: currencies),
                                         autoFillUnavailable: Self.autoFillUnavailableReason,
                                         today: { [unowned self] in today },
                                         categories: { [unowned self] in categories },
                                         onChange: { [unowned self] in refresh() })
            invoiceImport = flow
            // Drafts whose extraction never finished (the app quit mid-batch).
            flow.resume(try store!.snapshots(.expenses, drafts: .only))
            #if DEBUG
            // Screenshot helper: open the newest unpaid invoice's editor.
            if UserDefaults.standard.bool(forKey: "openFirstUnpaid"),
               let invoice = records(.income).first(where: { !$0.isPaid }) {
                open(invoice)
            }
            #endif
        } catch {
            log.error("Opening storage failed: \(error.localizedDescription, privacy: .public)")
            phase = .failed(error.localizedDescription)
        }
    }

    /// Recomputes dashboard numbers from the store.
    func refresh() {
        guard let store else { return }
        do {
            let entries = try store.entries()
            let currentYear = ISODate.year(today) ?? selectedYear
            yearOptions = DashboardWindow.yearOptions(dataYears: Reports.years(entries), currentYear: currentYear,
                                                      selected: selectedYear)
            let window = DashboardWindow(year: selectedYear, today: today)
            let months = Reports.summary(entries, from: window.start, to: window.end, groupBy: .month,
                                         excludeVatSettlements: true)
            let previous = Reports.summary(entries, from: window.previousStart, to: window.previousEnd, groupBy: .year,
                                           excludeVatSettlements: true).totals
            let taxes = try? Reports.taxes(entries, year: selectedYear, dateTo: window.partial ? window.end : nil)
            dashboard = DashboardData(window: window, taxes: taxes, months: months, previous: previous,
                                      profit: DashboardMath.cumulativeProfit(year: selectedYear, months: months.periods),
                                      recordCount: entries.count)
            categories = try store.categories()
            draftCount = try store.snapshots(.expenses, drafts: .only).count
            revision += 1
        } catch {
            log.error("Refresh failed: \(error.localizedDescription, privacy: .public)")
            lastError = error.localizedDescription
        }
    }

    /// Called when CloudKit merged changes from another device.
    func handleRemoteChange() {
        guard let store else { return }
        do {
            let removed = try store.dedupe()
            if removed > 0 { log.notice("Removed \(removed) duplicates after remote change") }
        } catch {
            log.error("Dedupe failed: \(error.localizedDescription, privacy: .public)")
        }
        refresh()
    }

    func records(_ kind: Kind, wholeYear: Bool = true) -> [RecordSnapshot] {
        guard let store else { return [] }
        let start = ISODate.make(selectedYear, 1, 1)
        let end = ISODate.make(selectedYear, 12, 31)
        return (try? store.snapshots(kind, from: start, to: end, search: searchText)) ?? []
    }

    /// Removed records of the selected year (newest first), so they can be restored.
    func removedRecords(_ kind: Kind) -> [RecordSnapshot] {
        guard let store else { return [] }
        let start = ISODate.make(selectedYear, 1, 1)
        let end = ISODate.make(selectedYear, 12, 31)
        let all = (try? store.snapshots(kind, from: start, to: end, search: searchText, includeRemoved: true,
                                        drafts: .include)) ?? []
        return all.filter { $0.removedAt != nil }
    }

    /// Draft expenses of every year, newest first, so a draft dated outside the selected year (or not dated yet)
    /// still shows up for review.
    func drafts() -> [RecordSnapshot] {
        guard let store else { return [] }
        return (try? store.snapshots(.expenses, search: searchText, drafts: .only)) ?? []
    }

    func snapshot(_ id: PersistentIdentifier) -> RecordSnapshot? {
        store?.record(id).map { RecordSnapshot($0) }
    }

    // MARK: Actions

    func newRecord(_ kind: Kind) { editor = .new(kind) }

    /// Opens the Expenses list at its Drafts section (the root view switches to Expenses).
    func showDrafts() {
        searchText = ""
        showDraftsRequested = true
    }

    /// "Review Drafts": shows the Drafts section and opens the editor on the first draft, with Approve & Next and Skip.
    /// Drafts still being read are left out.
    func reviewDrafts() {
        showDrafts()
        let ids = drafts().filter { $0.extraction?.state != .pending }.map(\.id)
        if !ids.isEmpty { review = DraftReview(ids: ids) }
    }

    /// The invoice extractor: the on-device Apple Intelligence model, which may be unavailable when an import runs
    /// (it then marks the drafts `unavailable` with the reason). `-uiTestingExtractor stub` returns canned results
    /// keyed by filename. `currencies` are those seen in existing records, offered to the model.
    static func invoiceExtractor(currencies: [String]) -> (any InvoiceExtracting)? {
        if LaunchOptions.stubExtractor { return StubInvoiceExtractor(results: LaunchOptions.stubExtractions) }
        return FoundationModelsInvoiceExtractor(currencies: currencies)
    }

    /// Why imported invoices won't be filled in automatically right now (no Apple Intelligence), or nil.
    static func autoFillUnavailableReason() -> ExtractionFailure.Reason? {
        LaunchOptions.stubExtractor ? nil : FoundationModelsInvoiceExtractor.unavailableReason
    }

    /// "Import Invoices…": the file picker, or in UI tests the files the test handed in.
    func requestInvoiceImport() {
        if let files = LaunchOptions.invoiceFixtures {
            importInvoices(files.map { .data($0.data, filename: $0.name) })
        } else {
            showingInvoiceImporter = true
        }
    }

    /// Queues invoice files (PDFs or images); each becomes a draft expense.
    func importInvoices(_ sources: [InvoiceImportFlow.Source]) {
        invoiceImport?.add(sources)
    }

    /// "Import Sorted Export…": the file picker, or in UI tests the fixture the test handed in.
    func requestImport() {
        if let url = LaunchOptions.fixture(.sortedExport) {
            beginImport(url)
        } else {
            showingImporter = true
        }
    }

    func open(_ record: RecordSnapshot) { editor = .existing(record.id, record.kind) }

    func save(_ id: PersistentIdentifier, changes: [String: FieldInput]) throws {
        try store?.update(id, fields: changes)
        refresh()
    }

    @discardableResult
    func create(_ kind: Kind, fields: [String: FieldInput], document: Data?) throws -> PersistentIdentifier? {
        let id = try store?.create(kind, fields: fields, document: document)
        refresh()
        return id
    }

    func markPaid(_ id: PersistentIdentifier) throws {
        try store?.markPaid(id, date: today)
        refresh()
    }

    /// Finalizes a draft; throws `ApprovalError` with the field problems when it is incomplete.
    func approve(_ id: PersistentIdentifier) throws {
        defer { refresh() }
        try store?.approve(id)
    }

    /// Approves every draft that passes validation; the result lists the ones that stay drafts.
    @discardableResult
    func approveAll(_ ids: [PersistentIdentifier]) throws -> ApproveAllResult? {
        guard let store else { return nil }
        defer { refresh() }
        return try store.approveAll(ids)
    }

    /// Approve from a list (swipe or context menu). An incomplete draft opens in the editor with its problems
    /// shown next to the fields.
    func approveOrOpen(_ record: RecordSnapshot) {
        do {
            try approve(record.id)
        } catch let error as ApprovalError {
            pendingIssues[record.id] = error.issues
            open(record)
        } catch {
            lastError = error.localizedDescription
        }
    }

    /// The approval problems a list action left for this record's editor, once.
    func takePendingIssues(_ id: PersistentIdentifier) -> [RecordIssue] {
        pendingIssues.removeValue(forKey: id) ?? []
    }

    func setRemoved(_ id: PersistentIdentifier, _ removed: Bool) throws {
        try store?.setRemoved(id, removed)
        refresh()
    }

    func attach(_ data: Data, to id: PersistentIdentifier) throws {
        try store?.attachDocument(id, data: data)
        refresh()
    }

    func beginImport(_ url: URL) {
        guard let store else { return }
        let flow = ImportFlow(url: url, documents: store.documents)
        importFlow = flow
        Task { await flow.preview(store: store) }
    }

    func finishImport() {
        importFlow = nil
        refresh()
    }
}
