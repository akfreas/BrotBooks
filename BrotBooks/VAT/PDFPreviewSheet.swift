#if os(macOS)
import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// ERiC's preview PDF in a sheet (the record editor's `PDFKitView`), with Save… (save panel).
struct PDFPreviewSheet: View {
    let document: VatReturnsModel.PreviewDocument
    @Environment(\.dismiss) private var dismiss
    @State private var saveError: String?

    var body: some View {
        VStack(spacing: 0) {
            PDFKitView(data: document.data)
                .frame(minWidth: 680, idealWidth: 760, minHeight: 640, idealHeight: 860)
            Divider()
            HStack {
                Text(verbatim: document.title).foregroundStyle(.secondary)
                if let saveError {
                    Text(verbatim: saveError).foregroundStyle(Theme.bad).lineLimit(2)
                }
                Spacer()
                Button("Close") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Save…", action: save)
                    .keyboardShortcut("s", modifiers: .command)
                    .accessibilityIdentifier("vat.preview.save")
            }
            .padding(12)
        }
    }

    private func save() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.pdf]
        panel.nameFieldStringValue = document.filename
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try document.data.write(to: url, options: .atomic)
            saveError = nil
        } catch {
            saveError = error.localizedDescription
        }
    }
}
#endif
