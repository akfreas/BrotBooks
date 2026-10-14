import Foundation
import Observation
import os
import BrotBooksKit

/// "Import Sorted Export…": read the zip, show a dry-run preview, then import on confirmation.
@MainActor
@Observable
final class ImportFlow: Identifiable {
    enum State {
        case reading
        case preview(IngestSummary)
        case importing
        case done(IngestSummary)
        case failed(String)
    }

    let id = UUID()
    let url: URL
    let documents: DocumentStore
    private(set) var state = State.reading
    private var export: SortedExport?
    private let log = Logger(subsystem: "me.freas.BrotBooks", category: "import")

    init(url: URL, documents: DocumentStore) {
        self.url = url
        self.documents = documents
    }

    var filename: String { url.lastPathComponent }

    func preview(store: RecordStore) async {
        state = .reading
        let url = url, documents = documents, name = filename
        do {
            let (export, prepared) = try await Task.detached(priority: .userInitiated) {
                let accessing = url.startAccessingSecurityScopedResource()
                defer { if accessing { url.stopAccessingSecurityScopedResource() } }
                // Read into memory so the security-scoped access can end right away.
                let export = try SortedExport(data: Data(contentsOf: url))
                return (export, try Importer.prepare(export, documents: documents, dryRun: true, importedFrom: name))
            }.value
            self.export = export
            state = .preview(try Importer.apply(prepared, to: store))
        } catch {
            log.error("Import preview failed: \(error.localizedDescription, privacy: .public)")
            state = .failed(error.localizedDescription)
        }
    }

    func commit(store: RecordStore) async {
        guard let export else { return }
        state = .importing
        let documents = documents, name = filename
        do {
            let prepared = try await Task.detached(priority: .userInitiated) {
                try Importer.prepare(export, documents: documents, dryRun: false, importedFrom: name)
            }.value
            state = .done(try Importer.apply(prepared, to: store))
        } catch {
            log.error("Import failed: \(error.localizedDescription, privacy: .public)")
            state = .failed(error.localizedDescription)
        }
    }
}
