#if os(macOS)
import BrotBooksKit
import EricKit
import SwiftData
import SwiftUI

/// Sidebar destination (macOS): the returns of the current and previous year with their status, and the
/// selected return's Kennzahlen, warnings, flags, validation and preview.
struct VatReturnsView: View {
    @Environment(AppModel.self) private var app
    @State private var model = VatReturnsModel.shared

    var body: some View {
        @Bindable var model = model
        HStack(spacing: 0) {
            VatReturnList(model: model)
                .frame(width: 300)
            Divider()
            Group {
                if let item = model.selectedItem {
                    VatReturnDetail(model: model, item: item)
                        .id(item.id)
                } else if let error = model.loadError {
                    ContentUnavailableView("Couldn't load the VAT returns", systemImage: "exclamationmark.triangle",
                                           description: Text(verbatim: error))
                } else {
                    ContentUnavailableView("Select a Return", systemImage: "building.columns",
                                           description: Text("Choose a period to see its Kennzahlen, warnings and checks."))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Theme.background)
        }
        .navigationTitle(Text("VAT Returns"))
        .navigationDestination(isPresented: $model.showingReview) {
            TreatmentReviewView(model: model)
        }
        .sheet(item: $model.preview) { document in
            PDFPreviewSheet(document: document)
        }
        .onAppear { model.reload(app) }
        .onChange(of: app.revision) { model.reload(app) }
        .onReceive(NotificationCenter.default.publisher(for: ModelContext.didSave).receive(on: RunLoop.main)) { _ in
            // Settings saved from the ELSTER tab (records bump `revision` already).
            model.reload(app)
        }
        .requiresElsterLicenseAcknowledgment()
    }
}

// MARK: - List

private struct VatReturnList: View {
    @Bindable var model: VatReturnsModel

    var body: some View {
        let years = Array(Set(model.items.map(\.year))).sorted(by: >)
        VStack(spacing: 0) {
            if !model.review.isEmpty {
                ReviewBanner(count: model.review.count) { model.showingReview = true }
                    .padding(10)
                Divider()
            }
            List(selection: $model.selection) {
                ForEach(years, id: \.self) { year in
                    Section {
                        ForEach(model.items.filter { $0.year == year }) { item in
                            VatReturnRow(item: item, status: model.status(item), result: model.results[item.id],
                                         warnings: model.warnings(item).count)
                                .tag(item.id)
                                .accessibilityIdentifier("vat.row.\(item.id)")
                        }
                    } header: {
                        Text(verbatim: String(year))
                    }
                }
                if model.items.isEmpty && model.settings != nil {
                    Text("No returns: the filing settings have no UStVA periods for these years.")
                        .foregroundStyle(.secondary)
                }
            }
            .listStyle(.inset)
        }
    }
}

private struct ReviewBanner: View {
    let count: Int
    let action: () -> Void

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: "questionmark.circle.fill").foregroundStyle(Theme.amber)
            VStack(alignment: .leading, spacing: 4) {
                Text("^[\(count) record](inflect: true) with an unconfirmed VAT treatment")
                    .font(.callout.weight(.medium))
                    .fixedSize(horizontal: false, vertical: true)
                Button("Review Treatments…", action: action)
                    .buttonStyle(.link)
                    .accessibilityIdentifier("vat.review.open")
            }
            Spacer(minLength: 0)
        }
        .padding(10)
        .background(Theme.amber.opacity(0.12), in: .rect(cornerRadius: 8))
    }
}

private struct VatReturnRow: View {
    let item: VatReturnItem
    let status: VatReturnStatus
    let result: UStVAResult?
    let warnings: Int

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 3) {
                VatReturnTexts.title(item).font(.body.weight(.medium))
                HStack(spacing: 6) {
                    Text("Due \(Dates.long(item.dueDate))")
                    if warnings > 0 {
                        Label { Text(verbatim: "\(warnings)") } icon: { Image(systemName: "exclamationmark.triangle.fill") }
                            .foregroundStyle(Theme.amber)
                            .accessibilityLabel(Text("^[\(warnings) warning](inflect: true)"))
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Spacer(minLength: 6)
            VStack(alignment: .trailing, spacing: 3) {
                Pill(text: VatReturnTexts.status(status), tint: VatReturnTexts.statusTint(status))
                if let result {
                    Text(verbatim: Money.format(result.kennzahlen.kz83))
                        .font(.caption)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 2)
    }
}

// MARK: - Detail

private struct VatReturnDetail: View {
    @Environment(AppModel.self) private var app
    @Environment(\.openSettings) private var openSettings
    let model: VatReturnsModel
    let item: VatReturnItem

    var body: some View {
        let result = model.results[item.id]
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header
                notes
                if let failure = model.failures[item.id] {
                    Label { Text(verbatim: failure) } icon: { Image(systemName: "xmark.octagon.fill") }
                        .foregroundStyle(Theme.bad)
                        .card(padding: 14)
                }
                if let validation = model.validations[item.id] {
                    ValidationCard(validation: validation) { model.selectedKennzahl = $0 }
                }
                let warnings = model.warnings(item)
                if !warnings.isEmpty {
                    WarningsCard(model: model, issues: warnings)
                }
                if let result {
                    KennzahlenCard(model: model, result: result,
                                   flagged: Set(model.validations[item.id].map(Self.flaggedKennzahlen) ?? []))
                } else if case .sondervorauszahlung = item.type {
                    sondervorauszahlungCard
                }
                if !item.availableFlags.isEmpty { flagsCard }
            }
            .padding(24)
            .frame(maxWidth: 900, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
    }

    static func flaggedKennzahlen(_ validation: EricValidationResult) -> [Kennzahl] {
        validation.errors.compactMap { $0.feldidentifikator.flatMap(UStVAXML.kennzahlNumber).flatMap(Kennzahl.init) }
    }

    // MARK: Header and actions

    private var header: some View {
        let status = model.status(item)
        let blockers = model.blockers(item)
        let running = model.running[item.id]
        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    VatReturnTexts.title(item).font(.title2.bold())
                    HStack(spacing: 6) {
                        VatReturnTexts.subtitle(item)
                        Text(verbatim: "·")
                        Text("Due \(Dates.long(item.dueDate))")
                    }
                    .foregroundStyle(.secondary)
                }
                Spacer()
                if item.configuration.testMode {
                    Pill(text: Text("Test mode"), tint: Theme.accent)
                }
                Pill(text: VatReturnTexts.status(status), tint: VatReturnTexts.statusTint(status))
                    .accessibilityIdentifier("vat.detail.status")
            }
            HStack(spacing: 10) {
                Button {
                    Task { await model.validate(item) }
                } label: {
                    Label("Validate", systemImage: "checkmark.seal")
                }
                .accessibilityIdentifier("vat.validate")
                Button {
                    Task { await model.preview(item, title: VatReturnTexts.titleString(item)) }
                } label: {
                    Label("Preview PDF", systemImage: "doc.text.magnifyingglass")
                }
                .accessibilityIdentifier("vat.preview")
                if running != nil {
                    ProgressView().controlSize(.small)
                    Text(running == .validating ? LocalizedStringKey("Validating…") : LocalizedStringKey("Preparing preview…"))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button {} label: { Label("Send…", systemImage: "paperplane") }
                    .disabled(true)
                    .help(model.blocksSending(item)
                          ? Text("Confirm the VAT treatment of every record in this period first. Sending comes in a later version.")
                          : Text("Sending comes in a later version."))
                    .accessibilityIdentifier("vat.send")
            }
            .disabled(running != nil || !blockers.isEmpty)
            if !blockers.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(blockers, id: \.self) { blocker in
                        Label { VatReturnTexts.blocker(blocker) } icon: { Image(systemName: "info.circle") }
                    }
                    Button("Open ELSTER Settings", action: showElsterSettings).buttonStyle(.link)
                }
                .font(.callout)
                .foregroundStyle(.secondary)
            } else if model.blocksSending(item) {
                Label("Sending is blocked until every record in this period has a confirmed VAT treatment.",
                      systemImage: "lock")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .card()
    }

    private func showElsterSettings() {
        UserDefaults.standard.set("elster", forKey: "settingsTab")
        openSettings()
    }

    // MARK: Notes

    @ViewBuilder private var notes: some View {
        if item.needsSondervorauszahlungAmount {
            NoteCard(icon: "exclamationmark.triangle.fill", tint: Theme.amber) {
                if case .sondervorauszahlung = item.type {
                    Text("The Sondervorauszahlung (1/11 of last year's advance payments) can't be computed until last year's filings are recorded. Enter the amount in the ELSTER settings.")
                } else {
                    Text("The Sondervorauszahlung credit (Kz39) can't be computed until last year's filings are recorded, so it is left out. Enter the amount in the ELSTER settings.")
                }
                Button("Open ELSTER Settings", action: showElsterSettings).buttonStyle(.link)
                    .accessibilityIdentifier("vat.sondervorauszahlung.settings")
            }
        }
        switch item.type {
        case .sondervorauszahlung:
            NoteCard(icon: "info.circle", tint: Theme.accent) {
                Text("With monthly returns, filing the Sondervorauszahlung is also the application for the Dauerfristverlängerung: each return is then due one month later.")
            }
        case .dauerfristverlaengerung:
            NoteCard(icon: "info.circle", tint: Theme.accent) {
                Text("Dauerfristverlängerung application: with quarterly returns, apply once by the due date of the first return it should extend. Each return is then due one month later. No Sondervorauszahlung is owed.")
            }
        case .ustva:
            EmptyView()
        }
    }

    private var sondervorauszahlungCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionLabel("Kennzahlen")
            HStack {
                Text(verbatim: "Kz38").monospacedDigit().foregroundStyle(.secondary).frame(width: 44, alignment: .leading)
                Text("Sondervorauszahlung")
                Spacer()
                Text(verbatim: item.sondervorauszahlung.map { Money.format($0) } ?? "–").monospacedDigit()
            }
        }
        .card()
    }

    private var flagsCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionLabel("Options")
            ForEach(item.availableFlags, id: \.number) { entry in
                Toggle(isOn: Binding {
                    model.flags[item.id, default: []].contains(entry.flag)
                } set: { on in
                    if on { model.flags[item.id, default: []].insert(entry.flag) } else {
                        model.flags[item.id, default: []].remove(entry.flag)
                    }
                }) {
                    VatReturnTexts.flag(entry.number)
                }
                .accessibilityIdentifier("vat.flag.\(entry.number)")
            }
        }
        .card()
    }
}

private struct NoteCard<Content: View>: View {
    let icon: String
    let tint: Color
    @ViewBuilder let content: Content

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: icon).foregroundStyle(tint)
            VStack(alignment: .leading, spacing: 6) { content }
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .card(padding: 14)
    }
}

// MARK: - Warnings

private struct WarningsCard: View {
    @Environment(AppModel.self) private var app
    let model: VatReturnsModel
    let issues: [UStVAIssue]
    @State private var expanded: Set<UStVAIssue.Code> = []

    private let collapsedCount = 4

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                SectionLabel("Warnings")
                Spacer()
                if issues.contains(where: { $0.code == .unconfirmedTreatment }) {
                    Button("Review Treatments…") { model.showingReview = true }
                        .buttonStyle(.link)
                }
            }
            ForEach(VatReturnTexts.issueOrder, id: \.self) { code in
                let group = issues.filter { $0.code == code }
                if !group.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Label { VatReturnTexts.issue(code).font(.callout.weight(.medium)) } icon: {
                            Image(systemName: VatReturnTexts.issueIcon(code))
                                .foregroundStyle(code == .unconfirmedTreatment ? Theme.amber : Theme.bad)
                        }
                        let shown = expanded.contains(code) ? group : Array(group.prefix(collapsedCount))
                        ForEach(shown, id: \.self) { issue in
                            RecordLink(record: model.records[issue.recordUID], amount: nil)
                        }
                        if group.count > collapsedCount && !expanded.contains(code) {
                            Button("Show ^[\(group.count - collapsedCount) more](inflect: true)") { expanded.insert(code) }
                                .buttonStyle(.link)
                                .padding(.leading, 26)
                        }
                    }
                }
            }
        }
        .card()
        .accessibilityIdentifier("vat.warnings")
    }
}

/// A record in a warning or drill-down list; opens the record editor.
private struct RecordLink: View {
    @Environment(AppModel.self) private var app
    let record: RecordSnapshot?
    /// The record's part of a Kennzahl; nil shows the record's EUR gross.
    let amount: Decimal?

    var body: some View {
        if let record {
            Button { app.open(record) } label: {
                HStack {
                    Image(systemName: record.kind == .income ? "arrow.down.left" : "arrow.up.right")
                        .foregroundStyle(.secondary)
                        .frame(width: 16)
                    Text(verbatim: record.description ?? record.extraction?.sourceFilename ?? String(localized: "Untitled"))
                        .lineLimit(1)
                    Text(verbatim: Dates.short(record.date)).foregroundStyle(.secondary)
                    Spacer()
                    Text(verbatim: Money.format(amount ?? record.convertedGrossAmount)).monospacedDigit()
                    Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.leading, 26)
            .padding(.vertical, 2)
        }
    }
}

// MARK: - Kennzahlen

private struct KennzahlenCard: View {
    @Bindable var model: VatReturnsModel
    let result: UStVAResult
    /// Kennzahlen ERiC reported errors for.
    let flagged: Set<Kennzahl>

    var body: some View {
        let form = result.kennzahlen.form
        let rows = result.kennzahlen.values.keys.sorted { a, b in
            if a == form.result || b == form.result { return b == form.result && a != form.result }
            return (form.elementOrder.firstIndex(of: a.rawValue) ?? 999) < (form.elementOrder.firstIndex(of: b.rawValue) ?? 999)
        }
        VStack(alignment: .leading, spacing: 4) {
            SectionLabel("Kennzahlen")
                .padding(.bottom, 6)
            ForEach(rows, id: \.self) { kz in
                row(kz, form: form)
                if model.selectedKennzahl == kz { contributions(kz, form: form) }
                if kz != rows.last { Divider().opacity(0.6) }
            }
            Text("Bases are cut to whole euros; taxes keep their cents. Select a row to see its records.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.top, 8)
        }
        .card()
        .accessibilityIdentifier("vat.kennzahlen")
    }

    private func row(_ kz: Kennzahl, form: UStVAForm) -> some View {
        let selected = model.selectedKennzahl == kz
        return Button {
            model.selectedKennzahl = selected ? nil : kz
        } label: {
            HStack {
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .rotationEffect(.degrees(selected ? 90 : 0))
                    .foregroundStyle(.secondary)
                Text(verbatim: kz.elementName)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .frame(width: 44, alignment: .leading)
                (VatReturnTexts.kennzahl(kz) ?? Text(verbatim: ""))
                    .fontWeight(kz == form.result ? .semibold : .regular)
                if flagged.contains(kz) {
                    Image(systemName: "xmark.octagon.fill").foregroundStyle(Theme.bad)
                        .accessibilityLabel(Text("ERiC reported an error"))
                }
                Spacer()
                Text(verbatim: Money.format(result.kennzahlen[kz]))
                    .monospacedDigit()
                    .fontWeight(kz == form.result ? .semibold : .regular)
            }
            .padding(.vertical, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("vat.kz.\(kz.rawValue)")
    }

    @ViewBuilder private func contributions(_ kz: Kennzahl, form: UStVAForm) -> some View {
        let parts = Dictionary(grouping: result.contributions.filter { $0.kennzahl == kz }, by: \.recordUID)
            .map { (uid: $0.key, amount: $0.value.reduce(Decimal(0)) { $0 + $1.amount }) }
            .sorted { (model.records[$0.uid]?.date ?? "", $0.uid) < (model.records[$1.uid]?.date ?? "", $1.uid) }
        VStack(alignment: .leading, spacing: 2) {
            if kz == form.result {
                Text("Computed from the other Kennzahlen.").foregroundStyle(.secondary).padding(.leading, 26)
            } else if kz == form.sondervorauszahlungCredit {
                Text("The Sondervorauszahlung entered in the ELSTER settings.").foregroundStyle(.secondary)
                    .padding(.leading, 26)
            } else if parts.isEmpty {
                Text("Computed from the paired Kennzahl.").foregroundStyle(.secondary).padding(.leading, 26)
            } else {
                ForEach(parts, id: \.uid) { part in
                    RecordLink(record: model.records[part.uid], amount: part.amount)
                }
            }
        }
        .font(.callout)
        .padding(.bottom, 6)
    }
}

// MARK: - Validation

private struct ValidationCard: View {
    let validation: EricValidationResult
    let select: (Kennzahl) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if validation.isValid {
                Label(validation.hints.isEmpty ? LocalizedStringKey("ERiC found no errors.")
                      : LocalizedStringKey("ERiC found no errors, but has hints."),
                      systemImage: "checkmark.seal.fill")
                    .foregroundStyle(Theme.moneyIn)
                    .font(.body.weight(.medium))
            } else {
                Label("ERiC found ^[\(validation.errors.count) error](inflect: true).", systemImage: "xmark.octagon.fill")
                    .foregroundStyle(Theme.bad)
                    .font(.body.weight(.medium))
                if validation.errors.isEmpty, let text = validation.errorText {
                    Text(verbatim: text).textSelection(.enabled)
                }
            }
            ForEach(Array(validation.errors.enumerated()), id: \.offset) { _, message in
                MessageRow(message: message, isError: true, select: select)
            }
            ForEach(Array(validation.hints.enumerated()), id: \.offset) { _, message in
                MessageRow(message: message, isError: false, select: select)
            }
        }
        .card()
        .accessibilityIdentifier("vat.validation")
    }
}

private struct MessageRow: View {
    let message: EricValidationResult.Message
    let isError: Bool
    let select: (Kennzahl) -> Void

    var body: some View {
        let number = message.feldidentifikator.flatMap(UStVAXML.kennzahlNumber)
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: isError ? "xmark.circle" : "info.circle")
                .foregroundStyle(isError ? Theme.bad : .secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: message.text).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                if let id = message.fachlicheID ?? message.regelName {
                    Text(verbatim: id).font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
            if let number {
                if let kz = Kennzahl(rawValue: number) {
                    Button { select(kz) } label: { Text(verbatim: "Kz\(number)") }
                        .buttonStyle(.link)
                        .help(Text("Show this Kennzahl"))
                } else {
                    Text(verbatim: "Kz" + String(format: "%02d", number)).foregroundStyle(.secondary)
                }
            }
        }
        .font(.callout)
    }
}
#endif
