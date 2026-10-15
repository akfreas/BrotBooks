import SwiftUI
import BrotBooksKit

@main
struct BrotBooksApp: App {
    @State private var app = AppModel()

    init() {
        #if os(iOS)
        // UI tests: no animations, so screenshots and taps don't race transitions.
        if LaunchOptions.uiTesting { UIView.setAnimationsEnabled(false) }
        #endif
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(app)
                .tint(Theme.accent)
                .preferredColorScheme(LaunchOptions.colorScheme)
                #if os(macOS)
                .frame(minWidth: 820, minHeight: 560)
                #endif
        }
        #if os(macOS)
        .defaultSize(width: 1380, height: 900)
        .commands { AppCommands(app: app) }
        #endif

        #if os(macOS)
        Settings {
            MacSettingsView().environment(app).tint(Theme.accent)
        }
        #endif
    }
}

#if os(macOS)
struct AppCommands: Commands {
    let app: AppModel

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("New Expense") { app.newRecord(.expenses) }
                .keyboardShortcut("n", modifiers: .command)
            Button("New Income") { app.newRecord(.income) }
                .keyboardShortcut("n", modifiers: [.command, .shift])
        }
        CommandGroup(replacing: .importExport) {
            Button("Import Invoices…") { app.requestInvoiceImport() }
                .keyboardShortcut("n", modifiers: [.command, .option])
            Button("Choose Photos…") { app.showingPhotoPicker = true }
            Divider()
            Button("Import Sorted Export…") { app.requestImport() }
                .keyboardShortcut("i", modifiers: .command)
        }
        CommandGroup(after: .textEditing) {
            Button("Find") { app.searchFocusRequested = true }
                .keyboardShortcut("f", modifiers: .command)
        }
        CommandGroup(after: .sidebar) {
            Button("Refresh") { app.handleRemoteChange() }
                .keyboardShortcut("r", modifiers: .command)
        }
    }
}
#endif
