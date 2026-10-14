import CoreGraphics
import Foundation
import Observation
import os
import SwiftData
import UniformTypeIdentifiers
import BrotBooksKit
#if os(iOS)
import BackgroundTasks
#endif

/// "Import Invoices…", Choose Photos…, Scan Documents… and drag and drop: every file becomes a draft expense with its
/// document attached first, then its details are extracted one file at a time.
///
/// Files are read, converted (photos become a one-page PDF through `ImagePDF`), checked for duplicates by SHA-256
/// and saved as drafts before any extraction runs, so nothing is lost if the app quits. Drafts still marked pending
/// are queued again on the next launch (`resume(_:)`).
@MainActor
@Observable
final class InvoiceImportFlow {
    /// One file to import. `load` reads its bytes (and may name the file, for drops that only know it once loaded).
    struct Source: Sendable {
        var filename: String?
        var load: @Sendable () async throws -> (data: Data, filename: String?)

        static func data(_ data: Data, filename: String?) -> Source {
            Source(filename: filename) { (data, filename) }
        }

        /// A file from the file importer, read under its security scope.
        static func file(_ url: URL) -> Source {
            Source(filename: url.lastPathComponent) {
                let accessing = url.startAccessingSecurityScopedResource()
                defer { if accessing { url.stopAccessingSecurityScopedResource() } }
                return (try Data(contentsOf: url), url.lastPathComponent)
            }
        }
    }

    enum ItemState: Equatable {
        /// Waiting to be read.
        case queued
        /// Reading the file and saving its draft.
        case reading
        /// The draft is saved; extraction hasn't started yet.
        case saved
        case extracting
        /// Extracted with a date, an amount and no low-confidence field.
        case ready
        /// The draft exists but needs filling in or checking by hand; the text says why.
        case needsAttention(String)
        /// No draft was made.
        case failed(String)
        /// A non-removed record already has this document; the text names it.
        case duplicate(String)
        case cancelled

        var isFinished: Bool {
            switch self {
            case .queued, .reading, .saved, .extracting: false
            default: true
            }
        }
    }

    struct Item: Identifiable {
        let id = UUID()
        var filename: String
        var state: ItemState
        var draft: PersistentIdentifier?
        fileprivate var source: Source?
        /// Set by Import Anyway: skip the duplicate check.
        fileprivate var force = false
        /// The PDF and decoded photo kept in memory from reading until extraction (only for the next few files).
        fileprivate var input: ExtractionInput?
    }

    private(set) var items: [Item] = []
    var isRunning: Bool { runner != nil }
    /// Files whose work is over (drafted and extracted, failed, skipped or cancelled).
    var finishedCount: Int { items.count { $0.state.isFinished } }
    /// Drafts this batch made.
    var draftCount: Int { items.count { $0.draft != nil } }
    /// Why this batch's drafts won't be filled in automatically (no Apple Intelligence), checked when a batch starts;
    /// the panel says it once.
    private(set) var autoFillUnavailable: ExtractionFailure.Reason?

    private let store: RecordStore
    private let extractor: (any InvoiceExtracting)?
    private let unavailableReason: @MainActor () -> ExtractionFailure.Reason?
    private let today: @MainActor () -> String
    private let categories: @MainActor () -> [String]
    private let onChange: @MainActor () -> Void
    private var runner: Task<Void, Never>?
    /// Identifies the current runner, so a run that was cancelled can't clear a newer one when it ends.
    private var runID = 0
    private let log = Logger(subsystem: "me.freas.BrotBooks", category: "invoiceImport")
    #if os(iOS)
    private let background = ContinuedImportTask()
    #endif

    /// How many read files keep their PDF and decoded photo in memory for extraction; later ones re-read the stored
    /// PDF, so a big batch of photos doesn't hold every decoded image at once.
    private static let retainedInputs = 4

    /// `extractor` nil means no extractor is available: drafts are made without auto-fill. `autoFillUnavailable`
    /// tells why the extractor can't run right now, for the panel's notice.
    init(store: RecordStore, extractor: (any InvoiceExtracting)?,
         autoFillUnavailable: @escaping @MainActor () -> ExtractionFailure.Reason? = { nil },
         today: @escaping @MainActor () -> String,
         categories: @escaping @MainActor () -> [String], onChange: @escaping @MainActor () -> Void) {
        self.store = store
        self.extractor = extractor
        self.unavailableReason = autoFillUnavailable
        self.today = today
        self.categories = categories
        self.onChange = onChange
    }

    // MARK: Queue

    /// Queues files in order and starts working through them.
    func add(_ sources: [Source]) {
        guard !sources.isEmpty else { return }
        items += sources.map { Item(filename: $0.filename ?? String(localized: "Untitled"), state: .queued, source: $0) }
        start()
    }

    /// Queues drafts whose extraction never finished (the app quit or was suspended mid-batch).
    func resume(_ drafts: [RecordSnapshot]) {
        let known = Set(items.compactMap(\.draft))
        let pending = drafts.filter { $0.isDraft && $0.extraction?.state == .pending && !known.contains($0.id) }
        guard !pending.isEmpty else { return }
        log.info("Resuming extraction of \(pending.count) drafts")
        items += pending.map { draft in
            Item(filename: draft.extraction?.sourceFilename ?? draft.description ?? String(localized: "Untitled"),
                 state: .saved, draft: draft.id)
        }
        start()
    }

    /// Imports a file the duplicate check skipped.
    func importAnyway(_ id: Item.ID) {
        guard let i = index(id), case .duplicate = items[i].state else { return }
        items[i].state = .queued
        items[i].force = true
        start()
    }

    /// Stops reading and extraction. Drafts already made stay, marked to be filled in by hand.
    func cancel() {
        runner?.cancel()
        runner = nil
        for i in items.indices where !items[i].state.isFinished {
            items[i].input = nil
            if let draft = items[i].draft {
                let reason = String(localized: "Cancelled before it was read. Fill it in by hand.")
                setExtraction(draft, ExtractionInfo(state: .failed, failureReason: reason))
                items[i].state = .needsAttention(reason)
            } else {
                items[i].state = .cancelled
            }
        }
        endBackgroundTask()
        onChange()
    }

    /// Clears the finished batch (the panel closes).
    func clear() {
        guard !isRunning else { return }
        items.removeAll()
        autoFillUnavailable = nil
    }

    private func start() {
        guard runner == nil else {
            updateBackgroundTask()
            return
        }
        if extractor != nil { autoFillUnavailable = unavailableReason() }
        beginBackgroundTask()
        runID += 1
        let id = runID
        runner = Task { [weak self] in
            await self?.run()
            guard let self, self.runID == id else { return }
            self.runner = nil
            self.endBackgroundTask()
        }
    }

    /// Reads and saves every queued file first, then extracts the saved drafts one at a time.
    private func run() async {
        while !Task.isCancelled {
            if let next = items.first(where: { $0.state == .queued }) {
                await read(next.id)
            } else if let next = items.first(where: { $0.state == .saved }) {
                await extract(next.id)
            } else {
                break
            }
            updateBackgroundTask()
        }
    }

    private func index(_ id: Item.ID) -> Int? { items.firstIndex { $0.id == id } }

    // MARK: Reading

    private func read(_ id: Item.ID) async {
        guard let i = index(id), let source = items[i].source else { return }
        items[i].state = .reading
        let input: ExtractionInput
        do {
            input = try await Task.detached(priority: .userInitiated) {
                let (data, name) = try await source.load()
                return try InvoiceDocument.prepare(data, filename: name ?? source.filename)
            }.value
        } catch {
            guard !Task.isCancelled, let i = index(id) else { return }
            log.error("Reading an invoice failed: \(error.localizedDescription, privacy: .public)")
            items[i].state = .failed(error.localizedDescription)
            return
        }
        guard !Task.isCancelled, let i = index(id) else { return }
        if let name = input.filename { items[i].filename = name }
        do {
            if !items[i].force, let existing = try store.existingRecord(forDocument: input.document) {
                let name = existing.description ?? existing.extraction?.sourceFilename ?? String(localized: "Untitled")
                items[i].state = .duplicate(name)
                return
            }
            let draft = try store.createDraft(document: input.document, filename: input.filename, today: today())
            items[i].draft = draft
            items[i].source = nil
            let retained = items.count { $0.input != nil }
            items[i].input = retained < Self.retainedInputs ? input : nil
            items[i].state = .saved
            onChange()
        } catch {
            log.error("Saving a draft failed: \(error.localizedDescription, privacy: .public)")
            items[i].state = .failed(error.localizedDescription)
        }
    }

    // MARK: Extraction

    private func extract(_ id: Item.ID) async {
        guard let i = index(id), let draft = items[i].draft else { return }
        items[i].state = .extracting
        let filename = sourceFilename(draft)
        guard let extractor else {
            let reason = String(localized: "Automatic reading isn't available. Fill it in by hand.")
            setExtraction(draft, ExtractionInfo(state: .unavailable, failureReason: reason, sourceFilename: filename))
            items[i].state = .needsAttention(reason)
            items[i].input = nil
            onChange()
            return
        }
        let kept = items[i].input
        items[i].input = nil
        let categories = categories()
        let outcome: Result<ExtractedInvoice, any Error>
        do {
            let input = try await extractionInput(draft, kept: kept, filename: filename)
            let result = try await Task.detached(priority: .userInitiated) {
                try await extractor.extract(input, categories: categories)
            }.value
            outcome = .success(result)
        } catch {
            outcome = .failure(error)
        }
        // Cancel already settled this draft.
        guard !Task.isCancelled, let i = index(id) else { return }
        switch outcome {
        case .success(let invoice):
            do {
                let built = InvoiceDraftBuilder.build(invoice, sourceFilename: filename, today: today(),
                                                      history: try store.pastExpenses())
                try store.applyExtraction(draft, fields: built.fields, extraction: built.info)
                items[i].state = built.isComplete
                    ? .ready : .needsAttention(String(localized: "Check the details and fill in what's missing."))
            } catch {
                markFailed(i, draft, error, filename: filename)
            }
        case .failure(let error):
            markFailed(i, draft, error, filename: filename)
        }
        onChange()
    }

    /// Keeps the blank draft and records why: `unavailable` when the model couldn't be used for it (no Apple
    /// Intelligence, guardrails, language), `failed` otherwise.
    private func markFailed(_ i: Int, _ draft: PersistentIdentifier, _ error: any Error, filename: String?) {
        let failure = ExtractionFailure.classify(error)
        log.error("Extraction \(failure.reason.rawValue, privacy: .public): \(failure.detail ?? "", privacy: .public)")
        let reason = failure.reason.localizedMessage
        setExtraction(draft, ExtractionInfo(state: failure.reason.state, failureReason: reason, sourceFilename: filename))
        items[i].state = .needsAttention(failure.reason.state == .unavailable
            ? reason : String(localized: "Couldn't read this invoice. Fill it in by hand."))
    }

    /// Stores extraction metadata without touching any field (keeps the source filename when none is given).
    private func setExtraction(_ draft: PersistentIdentifier, _ info: ExtractionInfo) {
        var info = info
        if info.sourceFilename == nil {
            info.sourceFilename = sourceFilename(draft)
        }
        do {
            try store.applyExtraction(draft, fields: [:], extraction: info)
        } catch {
            log.error("Saving extraction state failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func sourceFilename(_ draft: PersistentIdentifier) -> String? {
        store.record(draft).map { RecordSnapshot($0) }?.extraction?.sourceFilename
    }

    /// What the extractor gets for a draft: the PDF and photo kept from reading, or for a resumed or later draft its
    /// stored PDF, prepared again.
    private func extractionInput(_ draft: PersistentIdentifier, kept: ExtractionInput?,
                                 filename: String?) async throws -> ExtractionInput {
        if let kept {
            return await Task.detached(priority: .userInitiated) {
                InvoiceInput.prepare(document: kept.document, filename: kept.filename, image: kept.image)
            }.value
        }
        guard let path = store.record(draft)?.documentPath else { throw ValidationError("The draft has no document") }
        let document = try await store.documents.read(path)
        return await Task.detached(priority: .userInitiated) {
            InvoiceInput.prepare(document: document, filename: filename)
        }.value
    }

    // MARK: Background (iOS)

    private func beginBackgroundTask() {
        #if os(iOS)
        if !LaunchOptions.uiTesting { background.begin(total: items.count, finished: finishedCount) }
        #endif
    }

    private func updateBackgroundTask() {
        #if os(iOS)
        background.update(total: items.count, finished: finishedCount)
        #endif
    }

    private func endBackgroundTask() {
        #if os(iOS)
        background.finish()
        #endif
    }
}

extension ExtractionFailure.Reason {
    /// Why an invoice wasn't filled in automatically, for the import panel and the editor.
    var localizedMessage: String {
        switch self {
        case .deviceNotEligible: String(localized: "This device doesn't support Apple Intelligence.")
        case .appleIntelligenceNotEnabled: String(localized: "Apple Intelligence is turned off in Settings.")
        case .modelNotReady: String(localized: "The Apple Intelligence model is still downloading.")
        case .assetsUnavailable: String(localized: "The Apple Intelligence model isn't available on this device right now.")
        case .imageNotSupported: String(localized: "Reading images isn't supported on this device.")
        case .guardrail: String(localized: "Apple Intelligence declined to read this document.")
        case .unsupportedLanguage: String(localized: "The invoice's language isn't supported.")
        case .tooLong: String(localized: "The document is too long to read automatically.")
        case .unreadable: String(localized: "The details couldn't be read.")
        }
    }
}

/// Turns an imported file into an expense document.
enum InvoiceDocument {
    static func isPDF(_ data: Data) -> Bool { data.starts(with: Array("%PDF-".utf8)) }

    /// A PDF as-is, or an image converted to a one-page PDF (keeping the decoded photo for extraction).
    nonisolated static func prepare(_ data: Data, filename: String?) throws -> ExtractionInput {
        if isPDF(data) { return ExtractionInput(document: data, filename: filename) }
        do {
            let output = try ImagePDF.convert(data)
            return ExtractionInput(document: output.pdf, filename: filename, image: output.image)
        } catch {
            throw ValidationError(String(localized: "This file isn't a PDF or an image that can be read."))
        }
    }

    /// The PDF for attaching: a PDF as-is, or an image converted to one.
    nonisolated static func pdf(_ data: Data) throws -> Data {
        try prepare(data, filename: nil).document
    }

    /// Content types the import and the editor accept.
    static let contentTypes: [UTType] = [.pdf, .image]

    /// Sources for dropped items: PDFs and images, or file URLs. Loading starts right away, while the drop's
    /// providers are still valid; the queue awaits the result when it gets to the file.
    static func sources(_ providers: [NSItemProvider]) -> [InvoiceImportFlow.Source] {
        providers.compactMap { provider in
            let box = ProviderBox(provider: provider)
            let name = provider.suggestedName
            if let type = provider.registeredContentTypes.first(where: { $0.conforms(to: .pdf) || $0.conforms(to: .image) }) {
                let filename = name.map { $0.contains(".") ? $0 : $0 + "." + (type.preferredFilenameExtension ?? "") }
                let load = Task { try await loadData(box, type) }
                return InvoiceImportFlow.Source(filename: filename) { (try await load.value, filename) }
            }
            if provider.canLoadObject(ofClass: URL.self) {
                let load = Task { try await loadURL(box) }
                return InvoiceImportFlow.Source(filename: name) {
                    let url = try await load.value
                    return (try await InvoiceImportFlow.Source.file(url).load().data, url.lastPathComponent)
                }
            }
            return nil
        }
    }

    /// `NSItemProvider` isn't marked `Sendable`, but its loading methods may be called from any thread.
    private struct ProviderBox: @unchecked Sendable {
        let provider: NSItemProvider
    }

    private static func loadData(_ box: ProviderBox, _ type: UTType) async throws -> Data {
        try await withCheckedThrowingContinuation { continuation in
            _ = box.provider.loadDataRepresentation(for: type) { data, error in
                if let data { continuation.resume(returning: data) }
                else { continuation.resume(throwing: error ?? CocoaError(.fileReadUnknown)) }
            }
        }
    }

    private static func loadURL(_ box: ProviderBox) async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            _ = box.provider.loadObject(ofClass: URL.self) { url, error in
                if let url { continuation.resume(returning: url) }
                else { continuation.resume(throwing: error ?? CocoaError(.fileReadUnknown)) }
            }
        }
    }
}

#if os(iOS)
/// Wraps an import batch in a `BGContinuedProcessingTask`, so it keeps running with system-shown progress when the
/// user leaves the app. The in-app queue does the work either way; this only reports progress and keeps the app
/// running. If the system expires the task, the queue carries on when the app runs again, and drafts still pending
/// after a quit are resumed on the next launch.
@MainActor
final class ContinuedImportTask {
    private var task: BGContinuedProcessingTask?
    private var active = false
    private var progress = (total: 0, finished: 0)
    private let log = Logger(subsystem: "me.freas.BrotBooks", category: "invoiceImport")

    func begin(total: Int, finished: Int) {
        guard !active, let bundle = Bundle.main.bundleIdentifier else { return }
        active = true
        progress = (total, finished)
        // Each batch gets its own identifier under the wildcard in BGTaskSchedulerPermittedIdentifiers;
        // registering one identifier twice would end the app.
        let identifier = "\(bundle).invoiceImport.\(UUID().uuidString)"
        let registered = BGTaskScheduler.shared.register(forTaskWithIdentifier: identifier, using: .main) { [weak self] task in
            MainActor.assumeIsolated {
                guard let self, let task = task as? BGContinuedProcessingTask else {
                    task.setTaskCompleted(success: false)
                    return
                }
                self.attach(task)
            }
        }
        guard registered else {
            log.error("Couldn't register the continued processing task")
            return
        }
        let request = BGContinuedProcessingTaskRequest(identifier: identifier,
                                                       title: String(localized: "Importing invoices"),
                                                       subtitle: subtitle)
        request.strategy = .fail
        Task {
            do {
                try await BGTaskScheduler.shared.submitTaskRequest(request)
            } catch {
                log.notice("Continued processing not available: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    func update(total: Int, finished: Int) {
        progress = (total, finished)
        guard let task else { return }
        task.progress.totalUnitCount = Int64(total)
        task.progress.completedUnitCount = Int64(finished)
        task.updateTitle(String(localized: "Importing invoices"), subtitle: subtitle)
    }

    func finish() {
        active = false
        task?.setTaskCompleted(success: true)
        task = nil
    }

    private var subtitle: String { String(localized: "\(progress.finished) of \(progress.total) files") }

    private func attach(_ task: BGContinuedProcessingTask) {
        // The batch may have ended before the system started the task.
        guard active else {
            task.setTaskCompleted(success: true)
            return
        }
        self.task = task
        task.expirationHandler = { [weak self] in
            Task { @MainActor in self?.expire() }
        }
        update(total: progress.total, finished: progress.finished)
    }

    private func expire() {
        task?.setTaskCompleted(success: false)
        task = nil
    }
}
#endif
