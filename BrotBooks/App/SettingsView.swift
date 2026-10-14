import SwiftUI
import BrotBooksKit

/// Storage location and iCloud status. A `Settings` scene on macOS, a sheet on iOS.
struct SettingsView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Form {
            Section("Storage") {
                LabeledContent("Records") {
                    Text(isCloud ? "iCloud (CloudKit private database)" : "This device only")
                        .accessibilityIdentifier("settings.storage")
                }
                LabeledContent("iCloud") {
                    HStack(spacing: 6) {
                        Image(systemName: isCloud ? "checkmark.icloud" : "icloud.slash").accessibilityHidden(true)
                        Text(iCloudStatus)
                            .multilineTextAlignment(.trailing)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityIdentifier("settings.icloud")
                    }
                    .foregroundStyle(isCloud ? Theme.moneyIn : Theme.amber)
                }
                if isCloud {
                    LabeledContent("Container", value: Storage.cloudContainerID)
                }
                LabeledContent("Active records", value: "\(app.dashboard?.recordCount ?? 0)")
            }
            Section {
                if let root = app.storage?.documents.root {
                    LabeledContent("Documents") {
                        Text(verbatim: root.path(percentEncoded: false))
                            .font(.caption.monospaced())
                            .textSelection(.enabled)
                            .lineLimit(3)
                            .truncationMode(.middle)
                    }
                    #if os(macOS)
                    Button("Reveal Documents in Finder") { NSWorkspace.shared.activateFileViewerSelecting([root]) }
                    #endif
                }
            } header: {
                Text("Documents")
            } footer: {
                #if os(iOS)
                Text(isCloud ? "Your PDFs appear in the Files app under iCloud Drive › BrotBooks." : "PDFs are kept in the app's own storage on this device.")
                #else
                Text(isCloud ? "Your PDFs appear in Finder under iCloud Drive › BrotBooks." : "PDFs are kept in the app's own storage on this Mac.")
                #endif
            }
            Section {
                Button("Import Sorted Export…") { afterDismiss { app.requestImport() } }
                #if DEBUG
                if !isCloud {
                    Button("Load Sample Data") {
                        if let store = app.store { try? SampleData.load(into: store, today: app.today) }
                        app.refresh()
                    }
                }
                #endif
            } footer: {
                Text("Importing is how you move from Sorted: records are matched by their Sorted reference, so importing a newer export updates them in place.")
            }
        }
        .formStyle(.grouped)
        .navigationTitle(Text("Settings"))
        #if os(iOS)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") { dismiss() }.accessibilityIdentifier("settings.done")
            }
        }
        #else
        .frame(width: 520, height: 460)
        #endif
    }

    /// On iOS Settings is a sheet: let it close before the importer presents its own.
    private func afterDismiss(_ action: @escaping @MainActor () -> Void) {
        dismiss()
        #if os(iOS)
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(500))
            action()
        }
        #else
        action()
        #endif
    }

    private var isCloud: Bool { app.storage?.mode == .iCloud }

    private var iCloudStatus: LocalizedStringKey {
        switch app.storage?.mode {
        case .iCloud: "Syncing"
        case .local(.requested): "Off (local store requested)"
        case .local(.signedOut): "Not signed in"
        case .local(.unavailable): "Unavailable"
        case nil: "Checking…"
        }
    }
}
