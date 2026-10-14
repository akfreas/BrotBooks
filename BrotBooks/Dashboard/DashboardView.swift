import SwiftUI
import BrotBooksKit

/// Taxes, income and expenses, profit chart and (on wide layouts) the record browser.
struct DashboardView: View {
    @Environment(AppModel.self) private var app
    /// Show the record list beside the cards (Mac and iPad), or cards only (iPhone tab).
    var showsRecords = true

    var body: some View {
        GeometryReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    StorageBanner()
                    if let data = app.dashboard {
                        header(data)
                        if app.isEmpty {
                            EmptyLibraryView()
                        } else if showsRecords && proxy.size.width >= 1000 {
                            HStack(alignment: .top, spacing: 16) {
                                cards(data, wide: true).frame(maxWidth: .infinity)
                                RecordListCard().frame(width: min(460, proxy.size.width * 0.4))
                            }
                        } else {
                            cards(data, wide: proxy.size.width >= 640)
                            if showsRecords { RecordListCard() }
                        }
                    }
                }
                .padding(proxy.size.width < 500 ? 16 : 24)
                .frame(maxWidth: 1500)
                .frame(maxWidth: .infinity)
            }
        }
        .background(Theme.background)
        .refreshable { app.handleRemoteChange() }
        .navigationTitle(Text("Dashboard"))
    }

    private func header(_ data: DashboardData) -> some View {
        Text(verbatim: "\(Dates.long(data.window.start)) – \(Dates.long(data.window.end))")
            .font(.callout)
            .foregroundStyle(.secondary)
            .accessibilityIdentifier("dashboard.period")
    }

    @ViewBuilder private func cards(_ data: DashboardData, wide: Bool) -> some View {
        let w = data.window
        let totals = data.months.totals
        let previousLabel = w.partial ? Text("same period \(String(w.year - 1))") : Text("in \(String(w.year - 1))")
        VStack(spacing: 16) {
            if let taxes = data.taxes { TaxCard(taxes: taxes, partial: w.partial) }
            let income = StatCard(label: w.partial ? Text("Income so far · \(String(w.year))") : Text("Income · \(String(w.year))"),
                                  net: totals.incomeNet, gross: totals.incomeGross, previousNet: data.previous.incomeNet,
                                  previousLabel: previousLabel, identifier: "dashboard.incomeCard")
            let expenses = StatCard(label: w.partial ? Text("Expenses so far · \(String(w.year))") : Text("Expenses · \(String(w.year))"),
                                    net: totals.expensesNet, gross: totals.expensesGross,
                                    previousNet: data.previous.expensesNet, previousLabel: previousLabel, upIsBad: true,
                                    identifier: "dashboard.expensesCard", drafts: app.draftCount,
                                    showDrafts: { app.showDrafts() })
            if wide {
                HStack(alignment: .top, spacing: 16) { income; expenses }
            } else {
                income
                expenses
            }
            ProfitChart(year: w.year, points: data.profit, total: totals.profit)
        }
    }
}

/// First-run state: nothing imported or created yet.
struct EmptyLibraryView: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        ContentUnavailableView {
            Label("Welcome to BrotBooks", systemImage: "books.vertical")
        } description: {
            Text("Import your Sorted export to bring over every income and expense record with its documents, or start fresh by adding a record.")
        } actions: {
            Button { app.requestImport() } label: { Text("Import Sorted Export…") }
                .buttonStyle(.borderedProminent)
            HStack {
                Button("New Income") { app.newRecord(.income) }
                Button("New Expense") { app.newRecord(.expenses) }
            }
        }
        .frame(maxWidth: .infinity)
        .card(padding: 32)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("dashboard.empty")
    }
}

/// Shown when records are stored on this device only.
struct StorageBanner: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        if case .local(let reason)? = app.storage?.mode {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "icloud.slash").foregroundStyle(Theme.amber)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Stored on this device only").font(.callout.weight(.semibold))
                    Text(message(reason)).font(.callout).foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(12)
            .background(Theme.amber.opacity(0.1), in: RoundedRectangle(cornerRadius: 10))
            .accessibilityElement(children: .combine)
        }
    }

    private func message(_ reason: Storage.LocalReason) -> LocalizedStringKey {
        switch reason {
        case .requested: return "Local storage was requested at launch, so nothing syncs with iCloud."
        case .signedOut: return "Sign in to iCloud in System Settings to sync records and documents across your devices."
        case .unavailable: return "iCloud isn't available for this app right now. Records stay on this device until it is."
        }
    }
}
