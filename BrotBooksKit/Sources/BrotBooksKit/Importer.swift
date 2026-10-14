import Foundation
import os
import SwiftData

/// Per-kind outcome of an import.
public struct KindSummary: Sendable, Equatable {
    public var kind: Kind
    public var rows = 0
    public var inserted = 0
    public var updated = 0
    public var unchanged = 0
    public var removed = 0
    public var filesWritten = 0
    public var missingDocuments: [String] = []

    public init(kind: Kind) { self.kind = kind }
}

public struct IngestSummary: Sendable, Equatable {
    public var kinds: [KindSummary]
    public var archiveFilesWritten = 0
    public var dryRun = false
    public var importedFrom: String

    public func kind(_ kind: Kind) -> KindSummary? { kinds.first { $0.kind == kind } }
}

/// Phase 1 output: parsed records with their stored document paths. Built off the main actor.
public struct PreparedImport: Sendable {
    public struct Item: Sendable {
        public let record: ExportRecord
        public let documentPath: String?
        public let documentSha256: String?
    }

    public var items: [Kind: [Item]]
    public var summaries: [KindSummary]
    public var archiveFilesWritten: Int
    public var dryRun: Bool
    public var importedFrom: String
}

/// Syncs a Sorted export zip into the store.
///
/// An export is a full snapshot: records are upserted by `sortedRef` (a row changes only when its
/// CSV row, removal state or document hash changed), documents are copied to `<kind>/<YYYY>/<file>`,
/// and Sorted records missing from the export are soft-deleted — unless that kind's CSV is empty,
/// which is more likely a partial export than "everything was deleted".
public enum Importer {
    private static let log = Logger(subsystem: "me.freas.BrotBooks", category: "import")

    /// Phase 1: parse CSVs and write documents (nothing is written with `dryRun`).
    public static func prepare(_ export: SortedExport, documents: DocumentStore, dryRun: Bool,
                               importedFrom: String) throws -> PreparedImport {
        var items: [Kind: [PreparedImport.Item]] = [:]
        var summaries: [KindSummary] = []
        for kind in Kind.allCases {
            var summary = KindSummary(kind: kind)
            let records = try export.records(kind)
            summary.rows = records.count
            items[kind] = try records.map { record in
                guard let filename = record.documentFilename,
                      let data = try export.document(kind, filename: filename) else {
                    summary.missingDocuments.append(record.documentFilename ?? "")
                    return PreparedImport.Item(record: record, documentPath: nil, documentSha256: nil)
                }
                let path = DocumentStore.relativePath(kind, filename: filename)
                let (sha, written) = try documents.put(path, data: data, dryRun: dryRun)
                if written { summary.filesWritten += 1 }
                return PreparedImport.Item(record: record, documentPath: path, documentSha256: sha)
            }
            summaries.append(summary)
        }
        var archiveWritten = 0
        for name in export.archiveFiles() {
            guard let data = try export.read(name) else { continue }
            if try documents.put(name, data: data, dryRun: dryRun).written { archiveWritten += 1 }
        }
        return PreparedImport(items: items, summaries: summaries, archiveFilesWritten: archiveWritten,
                              dryRun: dryRun, importedFrom: importedFrom)
    }

    /// Phase 2: upsert and sweep. With `dryRun` the store is not modified; only counts are returned.
    @MainActor
    public static func apply(_ prepared: PreparedImport, to store: RecordStore, sweep: Bool = true) throws -> IngestSummary {
        if !prepared.dryRun { try store.dedupe() }
        let now = Date()
        var summaries = prepared.summaries
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        for index in summaries.indices {
            let kind = summaries[index].kind
            let items = prepared.items[kind] ?? []
            var existing: [String: any LedgerRecord] = [:]
            for record in try store.all(kind) {
                if let ref = record.sortedRef { existing[ref] = record }
            }
            for item in items {
                let ref = item.record.sortedRef
                if let current = existing[ref] {
                    let changed = current.decodedSourceRow != item.record.sourceRow
                        || current.removedAt != nil
                        || current.documentSha256 != (item.documentSha256 ?? current.documentSha256)
                    guard changed else {
                        summaries[index].unchanged += 1
                        continue
                    }
                    summaries[index].updated += 1
                    if prepared.dryRun { continue }
                    write(item, into: current, encoder: encoder, importedFrom: prepared.importedFrom)
                    current.removedAt = nil
                    current.updatedAt = now
                } else {
                    summaries[index].inserted += 1
                    if prepared.dryRun { continue }
                    let record: any LedgerRecord = kind == .expenses ? Expense() : Income()
                    record.sortedRef = ref
                    write(item, into: record, encoder: encoder, importedFrom: prepared.importedFrom)
                    record.createdAt = now
                    record.updatedAt = now
                    store.context.insert(record)
                }
            }
            if sweep && !items.isEmpty {
                let refs = Set(items.map(\.record.sortedRef))
                for record in existing.values where record.removedAt == nil && !refs.contains(record.sortedRef!) {
                    summaries[index].removed += 1
                    if prepared.dryRun { continue }
                    record.removedAt = now
                    record.updatedAt = now
                }
            }
        }
        if !prepared.dryRun { try store.save() }
        let summary = IngestSummary(kinds: summaries, archiveFilesWritten: prepared.archiveFilesWritten,
                                    dryRun: prepared.dryRun, importedFrom: prepared.importedFrom)
        log.info("Import \(prepared.importedFrom, privacy: .public) dryRun=\(prepared.dryRun): \(String(describing: summaries), privacy: .public)")
        return summary
    }

    private static func write(_ item: PreparedImport.Item, into record: any LedgerRecord, encoder: JSONEncoder,
                              importedFrom: String) {
        record.apply(item.record.values)
        record.sourceRow = try? encoder.encode(item.record.sourceRow)
        // Keep the existing document when this export lacks it.
        if let path = item.documentPath { record.documentPath = path }
        if let sha = item.documentSha256 { record.documentSha256 = sha }
        record.importedFrom = importedFrom
    }

    /// Both phases in one call (used by tests and the confirm step).
    @MainActor
    public static func run(_ export: SortedExport, store: RecordStore, dryRun: Bool = false, sweep: Bool = true,
                           importedFrom: String) throws -> IngestSummary {
        let prepared = try prepare(export, documents: store.documents, dryRun: dryRun, importedFrom: importedFrom)
        return try apply(prepared, to: store, sweep: sweep)
    }
}
