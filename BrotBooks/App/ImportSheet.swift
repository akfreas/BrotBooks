import SwiftUI
import BrotBooksKit

/// Dry-run preview of a Sorted export import, then the result.
struct ImportSheet: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    let flow: ImportFlow

    var body: some View {
        NavigationStack {
            Group {
                switch flow.state {
                case .reading:
                    ProgressView("Reading \(flow.filename)…").frame(maxWidth: .infinity, maxHeight: .infinity)
                case .importing:
                    ProgressView("Importing records and documents…").frame(maxWidth: .infinity, maxHeight: .infinity)
                case .preview(let summary):
                    SummaryForm(summary: summary, intro: Text("Nothing has been changed yet. This is what importing \(flow.filename) will do:"))
                case .done(let summary):
                    SummaryForm(summary: summary, intro: Text("Imported \(flow.filename)."))
                case .failed(let message):
                    ContentUnavailableView {
                        Label("This export can't be imported", systemImage: "exclamationmark.triangle")
                    } description: {
                        Text(verbatim: message)
                    }
                }
            }
            .navigationTitle(Text("Import Sorted Export"))
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                switch flow.state {
                case .preview:
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel") { close() } }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Import") { Task { if let store = app.store { await flow.commit(store: store) } } }
                            .accessibilityIdentifier("import.confirm")
                    }
                case .done, .failed:
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { close() }.accessibilityIdentifier("import.done")
                    }
                default:
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel") { close() }.disabled(true) }
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 520, minHeight: 460)
        #endif
        .interactiveDismissDisabled()
    }

    private func close() {
        app.finishImport()
        dismiss()
    }
}

private struct SummaryForm: View {
    let summary: IngestSummary
    let intro: Text

    var body: some View {
        Form {
            Section { intro.foregroundStyle(.secondary).accessibilityIdentifier("import.intro") }
            ForEach(summary.kinds, id: \.kind) { k in
                Section {
                    row("New", k.inserted, id: "import.\(k.kind.rawValue).new")
                    row("Updated", k.updated, id: "import.\(k.kind.rawValue).updated")
                    row("Unchanged", k.unchanged, id: "import.\(k.kind.rawValue).unchanged")
                    row("Removed (no longer in Sorted)", k.removed, id: "import.\(k.kind.rawValue).removed")
                    row(summary.dryRun ? "Documents to copy" : "Documents copied", k.filesWritten,
                        id: "import.\(k.kind.rawValue).documents")
                    if !k.missingDocuments.isEmpty {
                        DisclosureGroup {
                            ForEach(k.missingDocuments, id: \.self) { Text(verbatim: $0).font(.caption).foregroundStyle(.secondary) }
                        } label: {
                            row("Missing documents", k.missingDocuments.count)
                        }
                    }
                } header: {
                    Text("\(Text(k.kind.title)) · \(Text("^[\(k.rows) row](inflect: true)"))")
                }
            }
            Section {
                row(summary.dryRun ? "Tax reports to copy" : "Tax reports copied", summary.archiveFilesWritten)
            }
        }
        .formStyle(.grouped)
    }

    private func row(_ label: LocalizedStringKey, _ value: Int, id: String = "") -> some View {
        LabeledContent(label) { Text(verbatim: "\(value)").monospacedDigit() }
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier(id)
    }
}
