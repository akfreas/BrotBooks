import PDFKit
import SwiftUI
import UniformTypeIdentifiers
import BrotBooksKit

/// PDF preview for a record, with iCloud download progress, drag-and-drop and file import to attach.
/// Dropped or chosen images are converted to a one-page PDF (`ImagePDF`), so the document is always a PDF.
struct DocumentPane: View {
    let path: String?
    let pending: Data?
    let documents: DocumentStore?
    let onAttach: (Data) -> Void

    enum LoadState: Equatable {
        case none
        case loading
        case downloading
        case loaded(Data)
        case failed(String)
    }

    @State private var state = LoadState.none
    @State private var importing = false
    @State private var dropTargeted = false
    @State private var attachError: String?

    var body: some View {
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Theme.background)
            .overlay {
                if dropTargeted {
                    RoundedRectangle(cornerRadius: 12).strokeBorder(Theme.accent, style: StrokeStyle(lineWidth: 2, dash: [6]))
                        .padding(8)
                }
            }
            .onDrop(of: InvoiceDocument.contentTypes + [.fileURL], isTargeted: $dropTargeted, perform: handleDrop)
            .fileImporter(isPresented: $importing, allowedContentTypes: InvoiceDocument.contentTypes) { result in
                if case .success(let url) = result { attachFile(url) }
            }
            .task(id: path ?? (pending == nil ? "" : "pending")) { await load() }
            .toolbar {
                ToolbarItem(placement: .automatic) {
                    Button { importing = true } label: {
                        Label(hasDocument ? "Replace PDF…" : "Attach PDF…", systemImage: "paperclip")
                    }
                    .accessibilityIdentifier("document.attach")
                }
                if let path, let url = try? documents?.resolve(path), case .loaded = state {
                    ToolbarItem(placement: .automatic) {
                        ShareLink(item: url) { Label("Share PDF", systemImage: "square.and.arrow.up") }
                            .accessibilityIdentifier("document.share")
                    }
                }
                #if os(macOS)
                if let path, let url = try? documents?.resolve(path), case .loaded = state {
                    ToolbarItem(placement: .automatic) {
                        Button { NSWorkspace.shared.activateFileViewerSelecting([url]) } label: {
                            Label("Show in Finder", systemImage: "folder")
                        }
                    }
                }
                #endif
            }
    }

    private var hasDocument: Bool { path != nil || pending != nil }

    @ViewBuilder private var content: some View {
        switch state {
        case .loaded(let data):
            PDFKitView(data: data)
                .accessibilityLabel(Text("Document preview"))
                .accessibilityIdentifier("document.preview")
        case .loading:
            ProgressView("Loading document…")
        case .downloading:
            ProgressView("Downloading from iCloud…")
        case .failed(let message):
            ContentUnavailableView {
                Label("Document unavailable", systemImage: "exclamationmark.triangle")
            } description: {
                Text(verbatim: message)
            } actions: {
                Button("Attach PDF…") { importing = true }
            }
        case .none:
            ContentUnavailableView {
                Label("No document", systemImage: "doc.badge.plus")
            } description: {
                Text("Drop a PDF or photo here or choose one to attach it to this record.")
                if let attachError { Text(verbatim: attachError).foregroundStyle(.red) }
            } actions: {
                Button("Choose PDF…") { importing = true }
            }
        }
    }

    private func load() async {
        if let pending {
            state = .loaded(pending)
            return
        }
        guard let path, let documents else {
            state = .none
            return
        }
        state = .loading
        if documents.availability(path) == .downloading { state = .downloading }
        do {
            state = .loaded(try await documents.read(path))
        } catch {
            state = .failed(String(localized: "The PDF couldn't be read. It may still be uploading from another device."))
        }
    }

    private func attachFile(_ url: URL) {
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }
        do {
            accept(try Data(contentsOf: url))
        } catch {
            attachError = error.localizedDescription
        }
    }

    private func accept(_ data: Data) {
        Task {
            // Converting a photo takes a moment; keep it off the main thread.
            guard let pdf = await Task.detached(operation: { try? InvoiceDocument.pdf(data) }).value else {
                attachError = String(localized: "Only PDFs and images can be attached.")
                return
            }
            attachError = nil
            onAttach(pdf)
        }
    }

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first else { return false }
        if let type = provider.registeredContentTypes.first(where: { $0.conforms(to: .pdf) || $0.conforms(to: .image) }) {
            _ = provider.loadDataRepresentation(for: type) { data, _ in
                if let data { Task { @MainActor in accept(data) } }
            }
            return true
        }
        _ = provider.loadObject(ofClass: URL.self) { url, _ in
            guard let url, let data = try? Data(contentsOf: url) else { return }
            Task { @MainActor in accept(data) }
        }
        return true
    }
}

#if os(macOS)
struct PDFKitView: NSViewRepresentable {
    let data: Data

    func makeNSView(context: Context) -> PDFView {
        let view = PDFView()
        view.autoScales = true
        view.displayMode = .singlePageContinuous
        view.backgroundColor = .windowBackgroundColor
        view.document = PDFDocument(data: data)
        return view
    }

    func updateNSView(_ view: PDFView, context: Context) {
        if view.document?.dataRepresentation() != data { view.document = PDFDocument(data: data) }
    }
}
#else
struct PDFKitView: UIViewRepresentable {
    let data: Data

    func makeUIView(context: Context) -> PDFView {
        let view = PDFView()
        view.autoScales = true
        view.displayMode = .singlePageContinuous
        view.backgroundColor = .systemGroupedBackground
        view.document = PDFDocument(data: data)
        view.accessibilityIdentifier = "document.preview"
        return view
    }

    func updateUIView(_ view: PDFView, context: Context) {
        if view.document?.dataRepresentation() != data { view.document = PDFDocument(data: data) }
    }
}
#endif
