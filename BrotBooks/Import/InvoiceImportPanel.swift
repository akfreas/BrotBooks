import SwiftUI
import BrotBooksKit

/// Non-modal progress of an invoice import: one row per file (queued → reading → extracting → ready / needs
/// attention / failed), Cancel while it runs, then "n drafts ready to review" with Review Drafts.
struct InvoiceImportPanel: View {
    @Environment(AppModel.self) private var app
    let flow: InvoiceImportFlow
    @State private var showsFiles = true

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Image(systemName: flow.isRunning ? "tray.and.arrow.down" : "checkmark.circle.fill")
                    .foregroundStyle(flow.isRunning ? Theme.accent : Theme.moneyIn)
                    .accessibilityHidden(true)
                status
                    .font(.headline)
                    .accessibilityIdentifier("invoiceImport.status")
                Spacer(minLength: 8)
                Button { showsFiles.toggle() } label: {
                    Label(showsFiles ? "Hide Files" : "Show Files",
                          systemImage: showsFiles ? "chevron.down" : "chevron.up")
                }
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless)
                .accessibilityIdentifier("invoiceImport.toggle")
            }
            if let reason = flow.autoFillUnavailable {
                Label {
                    Text("Drafts will be created without auto-fill. \(reason.localizedMessage)")
                } icon: {
                    Image(systemName: "sparkles")
                }
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("invoiceImport.unavailable")
            }
            if flow.isRunning {
                ProgressView(value: Double(flow.finishedCount), total: Double(max(flow.items.count, 1)))
                    .accessibilityLabel(Text("Import progress"))
            }
            if showsFiles {
                // A short batch shows every row; a long one scrolls.
                if flow.items.count <= 4 {
                    rows
                } else {
                    ScrollView { rows }.frame(maxHeight: 200)
                }
            }
            HStack {
                Spacer()
                if flow.isRunning {
                    Button("Cancel", role: .cancel) { flow.cancel() }
                        .accessibilityIdentifier("invoiceImport.cancel")
                } else {
                    Button("Done") { flow.clear() }
                        .accessibilityIdentifier("invoiceImport.done")
                    if flow.draftCount > 0 {
                        Button("Review Drafts") {
                            flow.clear()
                            app.reviewDrafts()
                        }
                        .buttonStyle(.borderedProminent)
                        .accessibilityIdentifier("invoiceImport.review")
                    }
                }
            }
        }
        .padding(14)
        .frame(maxWidth: 480)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
        .overlay { RoundedRectangle(cornerRadius: 16).strokeBorder(.separator, lineWidth: 0.5) }
        .shadow(color: .black.opacity(0.15), radius: 12, y: 4)
        .padding(.horizontal, 12)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("invoiceImport.panel")
    }

    private var rows: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(flow.items.enumerated()), id: \.element.id) { index, item in
                row(item, index: index)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var status: Text {
        if flow.isRunning {
            return Text("Importing \(flow.finishedCount) of \(flow.items.count)…")
        }
        if flow.draftCount == 0 { return Text("No new drafts") }
        return Text("^[\(flow.draftCount) draft](inflect: true) ready to review")
    }

    private func row(_ item: InvoiceImportFlow.Item, index: Int) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            icon(item.state).frame(width: 18).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: item.filename).lineLimit(1).truncationMode(.middle)
                stateText(item.state)
                    .font(.caption)
                    .foregroundStyle(Color.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 4)
            if case .duplicate = item.state {
                Button("Import Anyway") { flow.importAnyway(item.id) }
                    .buttonStyle(.borderless)
                    .font(.caption)
                    .accessibilityIdentifier("invoiceImport.importAnyway.\(index)")
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("invoiceImport.row.\(index)")
    }

    @ViewBuilder private func icon(_ state: InvoiceImportFlow.ItemState) -> some View {
        switch state {
        case .queued: Image(systemName: "clock").foregroundStyle(.secondary)
        case .reading, .saved, .extracting: ProgressView().controlSize(.mini)
        case .ready: Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.moneyIn)
        case .needsAttention: Image(systemName: "exclamationmark.circle.fill").foregroundStyle(Theme.amber)
        case .failed: Image(systemName: "xmark.octagon.fill").foregroundStyle(Theme.bad)
        case .duplicate: Image(systemName: "doc.on.doc").foregroundStyle(.secondary)
        case .cancelled: Image(systemName: "minus.circle").foregroundStyle(.secondary)
        }
    }

    private func stateText(_ state: InvoiceImportFlow.ItemState) -> Text {
        switch state {
        case .queued: Text("Queued")
        case .reading: Text("Reading…")
        case .saved: Text("Draft saved, waiting to extract")
        case .extracting: Text("Extracting details…")
        case .ready: Text("Ready")
        case .needsAttention(let why): Text("Needs attention: \(why)")
        case .failed(let why): Text("Failed: \(why)")
        case .duplicate(let existing): Text("Already imported as \(existing)")
        case .cancelled: Text("Cancelled")
        }
    }
}

/// Accepts PDFs and images dropped onto a view (the Expenses list, the sidebar) and imports each as a draft expense.
struct InvoiceDropTarget: ViewModifier {
    @Environment(AppModel.self) private var app
    @State private var targeted = false

    func body(content: Content) -> some View {
        content
            .overlay {
                if targeted {
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(Theme.accent, style: StrokeStyle(lineWidth: 2, dash: [6]))
                        .padding(4)
                        .allowsHitTesting(false)
                }
            }
            .onDrop(of: InvoiceDocument.contentTypes + [.fileURL], isTargeted: $targeted) { providers in
                let sources = InvoiceDocument.sources(providers)
                app.importInvoices(sources)
                return !sources.isEmpty
            }
    }
}

extension View {
    func invoiceDropTarget() -> some View { modifier(InvoiceDropTarget()) }
}
