import PhotosUI
import SwiftUI
import UniformTypeIdentifiers
import BrotBooksKit

enum Destination: Hashable, CaseIterable {
    case dashboard, income, expenses
    #if os(macOS)
    /// UStVA returns via ELSTER (macOS only).
    case vatReturns
    #endif

    var title: LocalizedStringKey {
        switch self {
        case .dashboard: "Dashboard"
        case .income: "Income"
        case .expenses: "Expenses"
        #if os(macOS)
        case .vatReturns: "VAT Returns"
        #endif
        }
    }

    var systemImage: String {
        switch self {
        case .dashboard: "square.grid.2x2"
        case .income: "arrow.down.left.circle"
        case .expenses: "arrow.up.right.circle"
        #if os(macOS)
        case .vatReturns: "building.columns"
        #endif
        }
    }
}

struct RootView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.horizontalSizeClass) private var sizeClass
    #if DEBUG && os(macOS)
    @Environment(\.openSettings) private var openSettings
    #endif
    @State private var photoSelection: [PhotosPickerItem] = []

    var body: some View {
        @Bindable var app = app
        Group {
            switch app.phase {
            case .loading:
                ProgressView("Opening your books…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .accessibilityIdentifier("loading")
            case .failed(let message):
                ContentUnavailableView {
                    Label("Couldn't open your records", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(verbatim: message)
                }
            case .ready:
                if sizeClass == .compact { CompactRoot() } else { SplitRoot() }
            }
        }
        .overlay(alignment: .bottom) {
            if let flow = app.invoiceImport, !flow.items.isEmpty {
                // Above the iPhone tab bar.
                InvoiceImportPanel(flow: flow).padding(.bottom, sizeClass == .compact ? 64 : 16)
            }
        }
        #if os(iOS)
        .sheet(isPresented: $app.showingSettings) { NavigationStack { SettingsView() }.environment(app) }
        #endif
        .task {
            await app.start()
            #if DEBUG && os(macOS)
            await SnapshotAgent.run(app: app, openSettings: { openSettings() })
            #endif
        }
        .sheet(item: $app.editor) { target in
            RecordEditor(target: target).environment(app)
        }
        .sheet(item: $app.review) { review in
            DraftReviewSheet(queue: review.ids).environment(app)
        }
        .sheet(item: $app.importFlow) { flow in
            ImportSheet(flow: flow).environment(app)
        }
        .background {
            // A second file importer needs its own view.
            Color.clear
                .fileImporter(isPresented: $app.showingInvoiceImporter, allowedContentTypes: InvoiceDocument.contentTypes,
                              allowsMultipleSelection: true) { result in
                    switch result {
                    case .success(let urls): app.importInvoices(urls.map { .file($0) })
                    case .failure(let error): app.lastError = error.localizedDescription
                    }
                }
                .photosPicker(isPresented: $app.showingPhotoPicker, selection: $photoSelection, maxSelectionCount: nil,
                              matching: .images)
                .onChange(of: photoSelection) { _, items in
                    guard !items.isEmpty else { return }
                    app.importInvoices(items.enumerated().map { Self.photoSource($1, number: $0 + 1) })
                    photoSelection = []
                }
        }
        #if os(iOS)
        .fullScreenCover(isPresented: $app.showingScanner) {
            DocumentScanner { pdf in
                app.showingScanner = false
                if let pdf {
                    let name = String(localized: "Scan \(Dates.long(app.today))") + ".pdf"
                    app.importInvoices([.data(pdf, filename: name)])
                }
            }
            .ignoresSafeArea()
        }
        #endif
        .fileImporter(isPresented: $app.showingImporter, allowedContentTypes: [.zip]) { result in
            switch result {
            case .success(let url): app.beginImport(url)
            case .failure(let error): app.lastError = error.localizedDescription
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .NSPersistentStoreRemoteChange).receive(on: RunLoop.main)) { _ in
            app.handleRemoteChange()
        }
        .onChange(of: app.selectedYear) { app.refresh() }
        .alert(Text("Something went wrong"), isPresented: Binding { app.lastError != nil } set: { if !$0 { app.lastError = nil } }) {
            Button("OK") { app.lastError = nil }
        } message: {
            Text(verbatim: app.lastError ?? "")
        }
    }
}

extension RootView {
    /// A picked photo, loaded through `Transferable` when the import queue gets to it.
    static func photoSource(_ item: PhotosPickerItem, number: Int) -> InvoiceImportFlow.Source {
        let ext = item.supportedContentTypes.first?.preferredFilenameExtension.map { "." + $0 } ?? ""
        return InvoiceImportFlow.Source(filename: String(localized: "Photo \(number)") + ext) {
            guard let data = try await item.loadTransferable(type: Data.self) else {
                throw ValidationError(String(localized: "The photo couldn't be loaded."))
            }
            return (data, nil)
        }
    }
}

/// Mac and iPad: sidebar + detail.
struct SplitRoot: View {
    @Environment(AppModel.self) private var app
    @State private var selection: Destination? = LaunchOptions.startDestination ?? .dashboard

    var body: some View {
        @Bindable var app = app
        NavigationSplitView {
            List(selection: $selection) {
                Section {
                    ForEach(Destination.allCases, id: \.self) { d in
                        Label(d.title, systemImage: d.systemImage)
                            .badge(d == .expenses ? app.draftCount : 0)
                            .tag(d)
                            .accessibilityIdentifier("sidebar.\(d.identifier)")
                    }
                } header: {
                    // iPad shows the app name as the sidebar title instead.
                    #if os(macOS)
                    Text(verbatim: "BROTBOOKS")
                        .font(.caption.weight(.semibold))
                        .kerning(2)
                        .foregroundStyle(Theme.accent)
                        .accessibilityLabel(Text(verbatim: "BrotBooks"))
                    #endif
                }
            }
            .invoiceDropTarget()
            .navigationSplitViewColumnWidth(min: 180, ideal: 210)
            #if os(iOS)
            .navigationTitle(Text(verbatim: "BrotBooks"))
            .toolbar {
                ToolbarItem(placement: .bottomBar) {
                    Button { app.showingSettings = true } label: { Label("Settings", systemImage: "gearshape") }
                        .accessibilityIdentifier("sidebar.settings")
                }
            }
            #endif
        } detail: {
            NavigationStack {
                Group {
                    switch selection ?? .dashboard {
                    case .dashboard: DashboardView()
                    case .income: RecordsScreen(kind: .income)
                    case .expenses: RecordsScreen(kind: .expenses)
                    #if os(macOS)
                    case .vatReturns: VatReturnsView()
                    #endif
                    }
                }
                // Record screens have their own New button; the dashboard's menu offers both kinds.
                .toolbar { MainToolbar(showsNew: (selection ?? .dashboard) == .dashboard) }
                .searchable(text: $app.searchText, placement: .toolbar, prompt: Text("Search descriptions"))
                .modifier(SearchFocus(requested: $app.searchFocusRequested))
            }
        }
        .onChange(of: app.showDraftsRequested) { _, requested in if requested { selection = .expenses } }
    }
}

/// iPhone: tabs.
struct CompactRoot: View {
    @Environment(AppModel.self) private var app
    @State private var tab = Destination.dashboard

    var body: some View {
        @Bindable var app = app
        TabView(selection: $tab) {
            NavigationStack {
                DashboardView(showsRecords: false).toolbar { MainToolbar() }
            }
            .tabItem {
                Label("Dashboard", systemImage: Destination.dashboard.systemImage)
                    .accessibilityIdentifier("tab.dashboard")
            }
            .tag(Destination.dashboard)
            ForEach([Kind.income, .expenses]) { kind in
                NavigationStack {
                    RecordsScreen(kind: kind)
                        .toolbar { MainToolbar(showsNew: false) }
                        .searchable(text: $app.searchText, prompt: Text("Search descriptions"))
                }
                .tabItem {
                    Label(kind.title, systemImage: kind.systemImage)
                        .accessibilityIdentifier("tab.\(kind.rawValue)")
                }
                .badge(kind == .expenses ? app.draftCount : 0)
                .tag(kind == .income ? Destination.income : .expenses)
            }
        }
        // Search applies to one list at a time.
        .onChange(of: tab) { app.searchText = "" }
        .onChange(of: app.showDraftsRequested) { _, requested in if requested { tab = .expenses } }
    }
}

extension Destination {
    /// Stable name for accessibility identifiers ("sidebar.income", "tab.income").
    var identifier: String {
        switch self {
        case .dashboard: "dashboard"
        case .income: "income"
        case .expenses: "expenses"
        #if os(macOS)
        case .vatReturns: "vatReturns"
        #endif
        }
    }
}

/// Year picker, add menu (new records, import, iOS settings).
struct MainToolbar: ToolbarContent {
    @Environment(AppModel.self) private var app
    /// Offer New Income / New Expense (the dashboard); record screens have their own New button.
    var showsNew = true

    var body: some ToolbarContent {
        @Bindable var app = app
        ToolbarItem(placement: .navigation) {
            Picker(selection: $app.selectedYear) {
                ForEach(app.yearOptions, id: \.self) { Text(verbatim: String($0)).tag($0) }
            } label: {
                Text("Year")
            }
            .pickerStyle(.menu)
            .accessibilityValue(Text(verbatim: String(app.selectedYear)))
            .accessibilityIdentifier("yearPicker")
        }
        ToolbarItem(placement: .primaryAction) {
            Menu {
                if showsNew {
                    Button("New Income", systemImage: "arrow.down.left") { app.newRecord(.income) }
                        .accessibilityIdentifier("newIncome")
                    Button("New Expense", systemImage: "arrow.up.right") { app.newRecord(.expenses) }
                        .accessibilityIdentifier("newExpense")
                    Divider()
                }
                Button("Import Invoices…", systemImage: "doc.badge.plus") { app.requestInvoiceImport() }
                    .accessibilityIdentifier("importInvoices")
                Button("Choose Photos…", systemImage: "photo.on.rectangle") { app.showingPhotoPicker = true }
                    .accessibilityIdentifier("choosePhotos")
                #if os(iOS)
                if DocumentScanner.isSupported {
                    Button("Scan Documents…", systemImage: "doc.viewfinder") { app.showingScanner = true }
                        .accessibilityIdentifier("scanDocuments")
                }
                #endif
                Divider()
                Button("Import Sorted Export…", systemImage: "square.and.arrow.down") { app.requestImport() }
                    .accessibilityIdentifier("importSortedExport")
                #if os(iOS)
                Divider()
                Button("Settings", systemImage: "gearshape") { app.showingSettings = true }
                    .accessibilityIdentifier("openSettings")
                #endif
            } label: {
                if showsNew {
                    Label("Add", systemImage: "plus")
                } else {
                    Label("More", systemImage: "ellipsis.circle")
                }
            }
            .accessibilityIdentifier("toolbar.menu")
        }
    }
}

/// Moves focus to the search field when Find (⌘F) is chosen.
struct SearchFocus: ViewModifier {
    @Binding var requested: Bool

    func body(content: Content) -> some View {
        FocusedSearch(content: content, requested: $requested)
    }
}

private struct FocusedSearch<Content: View>: View {
    let content: Content
    @Binding var requested: Bool
    @FocusState private var focused: Bool

    var body: some View {
        content
            .searchFocused($focused)
            .onChange(of: requested) {
                if requested {
                    focused = true
                    requested = false
                }
            }
    }
}
