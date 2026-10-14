import Foundation
import os
import SwiftData

/// Immutable view of one record for lists and editors.
public struct RecordSnapshot: Sendable, Identifiable, Equatable {
    public let id: PersistentIdentifier
    public let kind: Kind
    public let uid: String
    public let values: RecordValues
    public let sortedRef: String?
    public let documentPath: String?
    public let removedAt: Date?
    public let updatedAt: Date
    /// An unapproved draft expense; it counts toward no total.
    public let isDraft: Bool
    /// Extraction state, confidences and warnings while the record is a draft.
    public let extraction: ExtractionInfo?

    public init(_ record: some LedgerRecord) {
        id = record.persistentModelID
        kind = type(of: record).kind
        uid = record.uid
        values = record.values
        sortedRef = record.sortedRef
        documentPath = record.documentPath
        removedAt = record.removedAt
        updatedAt = record.updatedAt
        isDraft = record.isDraft
        extraction = (record as? Expense).flatMap { ExtractionInfo.decode($0.extraction) }
    }

    public var date: String { values["date"]?.date ?? "" }
    public var description: String? { values["description"]?.text }
    public var currency: String { values["currency"]?.text ?? "EUR" }
    public var grossAmount: Decimal? { values["gross_amount"]?.decimal }
    public var convertedGrossAmount: Decimal? { values["converted_gross_amount"]?.decimal }
    public var netAmount: Decimal? { values["net_amount"]?.decimal }
    public var totalVatAmount: Decimal? { values["total_vat_amount"]?.decimal }
    public var vatRates: [VatRate] { values["vat_rates"]?.vatRates ?? [] }
    public var category: String? { values["category"]?.text }
    public var paymentStatus: String? { values["payment_status"]?.text }
    public var paymentDate: String? { values["payment_date"]?.date }
    public var isPaid: Bool { paymentStatus == "Paid" }
    public var hasDocument: Bool { documentPath != nil }
}

/// Which records `RecordStore.snapshots` returns by review status.
public enum DraftFilter: Sendable {
    /// Approved records only.
    case exclude
    /// Drafts only.
    case only
    /// Both.
    case include

    func admits(_ isDraft: Bool) -> Bool {
        switch self {
        case .exclude: return !isDraft
        case .only: return isDraft
        case .include: return true
        }
    }
}

/// Outcome of `RecordStore.approveAll`: the approved records and, for the rest, why not.
public struct ApproveAllResult: Sendable {
    public struct Failure: Sendable {
        public let id: PersistentIdentifier
        /// Field problems when validation failed; empty for other errors.
        public let issues: [RecordIssue]
        public let message: String
    }

    public var approved: [PersistentIdentifier] = []
    public var failed: [Failure] = []
}

/// All reads and writes of records go through here.
@MainActor
public final class RecordStore {
    public let context: ModelContext
    public let documents: DocumentStore
    private let log = Logger(subsystem: "me.freas.BrotBooks", category: "store")

    public init(context: ModelContext, documents: DocumentStore) {
        self.context = context
        self.documents = documents
    }

    // MARK: Reads

    public func all(_ kind: Kind) throws -> [any LedgerRecord] {
        switch kind {
        case .expenses: return try context.fetch(FetchDescriptor<Expense>())
        case .income: return try context.fetch(FetchDescriptor<Income>())
        }
    }

    public func record(_ id: PersistentIdentifier) -> (any LedgerRecord)? {
        context.model(for: id) as? any LedgerRecord
    }

    /// Amounts of every active, approved record, for summaries, taxes, charts and counts. Drafts are
    /// left out here so that no total includes them.
    public func entries() throws -> [LedgerEntry] {
        try Kind.allCases.flatMap { kind in
            try all(kind).filter { $0.removedAt == nil && !$0.isDraft }.map(\.ledgerEntry)
        }
    }

    /// Records sorted newest first (date, then most recently created), optionally filtered.
    /// Drafts are left out unless `drafts` asks for them, so lists and their totals match `entries()`.
    public func snapshots(_ kind: Kind, from: String? = nil, to: String? = nil, search: String = "",
                          includeRemoved: Bool = false, drafts: DraftFilter = .exclude) throws -> [RecordSnapshot] {
        let needle = search.trimmingCharacters(in: .whitespaces).lowercased()
        return try all(kind)
            .filter { r in
                (includeRemoved || r.removedAt == nil) && drafts.admits(r.isDraft)
                    && (from.map { r.date >= $0 } ?? true) && (to.map { r.date <= $0 } ?? true)
                    && (needle.isEmpty || (r.descriptionText ?? "").lowercased().contains(needle))
            }
            .sorted { a, b in a.date != b.date ? a.date > b.date : a.createdAt > b.createdAt }
            .map { RecordSnapshot($0) }
    }

    public func categories() throws -> [String] {
        let values = try context.fetch(FetchDescriptor<Expense>()).compactMap(\.category)
        var counts: [String: Int] = [:]
        for c in values { counts[c, default: 0] += 1 }
        return counts.keys.sorted { counts[$0]! != counts[$1]! ? counts[$0]! > counts[$1]! : $0 < $1 }
    }

    /// Description, category and supplier region of every non-removed, approved expense, newest first, for
    /// `InvoiceDraftBuilder`'s learned defaults. Drafts are left out: their values are still unchecked guesses.
    public func pastExpenses() throws -> [InvoiceDraftBuilder.PastExpense] {
        try snapshots(.expenses).compactMap { snap in
            guard let description = snap.description, !description.isEmpty else { return nil }
            return .init(description: description, category: snap.category,
                         supplierRegion: snap.values["supplier_region"]?.text)
        }
    }

    // MARK: Writes

    /// Creates a record from editor input; optionally attaches a PDF. Returns its identifier.
    @discardableResult
    public func create(_ kind: Kind, fields: [String: FieldInput], document: Data? = nil) throws -> PersistentIdentifier {
        let values = try RecordRules.prepareCreate(kind, fields)
        if let document { try Self.checkPDF(document) }
        let record: any LedgerRecord = kind == .expenses ? Expense() : Income()
        record.apply(values)
        context.insert(record)
        if let document { try attach(document, to: record) }
        try save()
        log.info("Created \(kind.rawValue, privacy: .public) record \(record.uid, privacy: .public)")
        return record.persistentModelID
    }

    /// Partial update with only the changed fields; derived amounts are recomputed.
    /// A draft may stay incomplete, and the fields sent are remembered as edited by the user
    /// (`ExtractionInfo.editedFields`) so a later `applyExtraction` leaves them alone.
    public func update(_ id: PersistentIdentifier, fields: [String: FieldInput]) throws {
        guard let record = record(id) else { throw ValidationError("Record not found") }
        let draft = record as? Expense
        let isDraft = draft?.reviewStatus == Expense.draftStatus
        let changes = try RecordRules.prepareUpdate(record.kind, before: record.values, fields, draft: isDraft)
        guard !changes.isEmpty else { return }
        record.apply(changes)
        if isDraft, let draft {
            var info = ExtractionInfo.decode(draft.extraction) ?? ExtractionInfo(state: .done)
            info.editedFields.formUnion(fields.keys)
            draft.extraction = info.encoded()
        }
        record.updatedAt = Date()
        try save()
    }

    /// Marks an invoice paid on `date` (the user's local today).
    public func markPaid(_ id: PersistentIdentifier, date: String) throws {
        try update(id, fields: ["payment_status": .text("Paid"), "payment_date": .text(date)])
    }

    // MARK: Drafts

    /// Creates an empty draft expense for an imported invoice: dated `today` as a placeholder, with the PDF
    /// attached and extraction pending. The document is saved before any extraction runs, so nothing is lost.
    @discardableResult
    public func createDraft(document: Data, filename: String?, today: String = ISODate.today()) throws -> PersistentIdentifier {
        try Self.checkPDF(document)
        let expense = Expense()
        expense.date = today
        expense.reviewStatus = Expense.draftStatus
        expense.extraction = ExtractionInfo(state: .pending, sourceFilename: filename).encoded()
        context.insert(expense)
        try attach(document, to: expense)
        try save()
        log.info("Created draft expense \(expense.uid, privacy: .public)")
        return expense.persistentModelID
    }

    /// Writes extracted fields into a draft, skipping every field the user edited (and any amount derived
    /// from the extracted ones that the user set), and stores `extraction` keeping the edited-field list.
    /// Does nothing once the record is no longer a draft.
    public func applyExtraction(_ id: PersistentIdentifier, fields: [String: FieldInput],
                                extraction: ExtractionInfo) throws {
        guard let expense = record(id) as? Expense else { throw ValidationError("Record not found") }
        guard expense.reviewStatus == Expense.draftStatus else { return }
        let edited = ExtractionInfo.decode(expense.extraction)?.editedFields ?? []
        let changes = try RecordRules.prepareUpdate(.expenses, before: expense.values,
                                                    fields.filter { !edited.contains($0.key) }, draft: true)
        expense.apply(changes.filter { !edited.contains($0.key) })
        var info = extraction
        info.editedFields.formUnion(edited)
        expense.extraction = info.encoded()
        expense.updatedAt = Date()
        try save()
    }

    /// Finalizes a draft: validates it as a complete record (`RecordRules.finalIssues`), then clears the
    /// draft status and extraction data so it counts toward totals. Throws `ApprovalError` with the field
    /// problems otherwise. Approving a record that isn't a draft does nothing.
    public func approve(_ id: PersistentIdentifier) throws {
        try approveWithoutSaving(id)
        try save()
    }

    /// Approves each draft that passes validation; the rest stay drafts and are reported with their problems.
    @discardableResult
    public func approveAll(_ ids: [PersistentIdentifier]) throws -> ApproveAllResult {
        var result = ApproveAllResult()
        for id in ids {
            do {
                try approveWithoutSaving(id)
                result.approved.append(id)
            } catch let error as ApprovalError {
                result.failed.append(.init(id: id, issues: error.issues, message: error.localizedDescription))
            } catch {
                result.failed.append(.init(id: id, issues: [], message: error.localizedDescription))
            }
        }
        try save()
        return result
    }

    private func approveWithoutSaving(_ id: PersistentIdentifier) throws {
        guard let record = record(id) else { throw ValidationError("Record not found") }
        guard let expense = record as? Expense, expense.reviewStatus == Expense.draftStatus else { return }
        try RecordRules.validateFinal(.expenses, expense.values)
        expense.reviewStatus = nil
        expense.extraction = nil
        expense.updatedAt = Date()
    }

    public func setRemoved(_ id: PersistentIdentifier, _ removed: Bool) throws {
        guard let record = record(id) else { throw ValidationError("Record not found") }
        record.removedAt = removed ? Date() : nil
        record.updatedAt = Date()
        try save()
    }

    public func attachDocument(_ id: PersistentIdentifier, data: Data) throws {
        guard let record = record(id) else { throw ValidationError("Record not found") }
        try Self.checkPDF(data)
        try attach(data, to: record)
        record.updatedAt = Date()
        try save()
    }

    /// A non-removed record (expense or income, draft or not) whose document has this SHA-256, if any.
    /// The invoice import uses it to skip files that are already in the books.
    public func existingRecord(withDocumentSha256 sha256: String) throws -> RecordSnapshot? {
        for kind in Kind.allCases {
            if let match = try all(kind).first(where: { $0.removedAt == nil && $0.documentSha256 == sha256 }) {
                return RecordSnapshot(match)
            }
        }
        return nil
    }

    /// `existingRecord(withDocumentSha256:)` for the SHA-256 of `document`.
    public func existingRecord(forDocument document: Data) throws -> RecordSnapshot? {
        try existingRecord(withDocumentSha256: DocumentStore.sha256(document))
    }

    static func checkPDF(_ data: Data) throws {
        guard data.starts(with: Array("%PDF-".utf8)) else { throw ValidationError("document must be a PDF") }
    }

    private func attach(_ data: Data, to record: any LedgerRecord) throws {
        let filename = RecordRules.uploadFilename(date: record.date, description: record.descriptionText,
                                                  ref: record.reference, sha256: DocumentStore.sha256(data))
        let relativePath = DocumentStore.relativePath(record.kind, filename: filename)
        let (sha, _) = try documents.put(relativePath, data: data)
        record.documentFilename = filename
        record.documentPath = relativePath
        record.documentSha256 = sha
    }

    /// Removes duplicate Sorted records (same `sortedRef`), which two devices importing the same
    /// export can create once CloudKit merges them. Keeps the most recently updated copy.
    @discardableResult
    public func dedupe() throws -> Int {
        var removed = 0
        for kind in Kind.allCases {
            let groups = Dictionary(grouping: try all(kind).filter { $0.sortedRef != nil }) { $0.sortedRef! }
            for (_, copies) in groups where copies.count > 1 {
                let ordered = copies.sorted { a, b in
                    a.updatedAt != b.updatedAt ? a.updatedAt > b.updatedAt : a.createdAt < b.createdAt
                }
                for duplicate in ordered.dropFirst() {
                    context.delete(duplicate)
                    removed += 1
                }
            }
        }
        if removed > 0 {
            try save()
            log.notice("Removed \(removed) duplicate records")
        }
        return removed
    }

    public func save() throws {
        if context.hasChanges { try context.save() }
    }
}
