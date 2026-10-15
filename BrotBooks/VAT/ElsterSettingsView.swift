#if os(macOS)
import BrotBooksKit
import EricKit
import Observation
import os
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

/// The synced tax profile (`TaxProfile`) being edited in Settings. Every change is saved right away.
@MainActor
@Observable
final class ElsterSettingsModel {
    private(set) var settings: TaxSettings
    private(set) var saveError: String?
    private let context: ModelContext
    private let log = Logger(subsystem: "me.freas.BrotBooks", category: "ELSTER")

    init(context: ModelContext) throws {
        self.context = context
        settings = try TaxProfile.load(in: context)
    }

    /// Applies `change` and saves the profile.
    func update(_ change: (inout TaxSettings) -> Void) {
        var updated = settings
        change(&updated)
        guard updated != settings else { return }
        settings = updated
        do {
            try TaxProfile.save(updated, in: context)
            saveError = nil
        } catch {
            log.error("Saving the tax profile failed: \(error.localizedDescription, privacy: .public)")
            saveError = error.localizedDescription
        }
    }

    func binding<Value>(_ keyPath: WritableKeyPath<TaxSettings, Value>) -> Binding<Value> {
        Binding { self.settings[keyPath: keyPath] } set: { value in self.update { $0[keyPath: keyPath] = value } }
    }

    /// A binding to one field of the settings period starting on `effectiveFrom`.
    func binding<Value>(period effectiveFrom: String, _ keyPath: WritableKeyPath<TaxSettingsPeriod, Value>,
                        default fallback: Value) -> Binding<Value> {
        Binding {
            self.settings.periods.first { $0.effectiveFrom == effectiveFrom }?[keyPath: keyPath] ?? fallback
        } set: { value in
            self.update { settings in
                guard var period = settings.periods.first(where: { $0.effectiveFrom == effectiveFrom }) else { return }
                period[keyPath: keyPath] = value
                settings.set(period)
            }
        }
    }
}

/// Settings › ELSTER (macOS): ERiC, Steuernummer and Finanzamt, the filer's details, the effective-dated filing
/// settings, the Vorsteuer share rules and test mode. Shown only after the license notices were acknowledged.
struct ElsterSettingsView: View {
    @Environment(AppModel.self) private var app
    @State private var model: ElsterSettingsModel?
    @State private var loadError: String?

    var body: some View {
        Group {
            if let model {
                ElsterSettingsForm(model: model)
            } else if let loadError {
                ContentUnavailableView("Couldn't load the tax profile", systemImage: "exclamationmark.triangle",
                                       description: Text(verbatim: loadError))
            } else {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .requiresElsterLicenseAcknowledgment()
        .frame(width: 640, height: 720)
        .task(id: app.storage == nil) {
            guard model == nil, let context = app.storage?.container.mainContext else { return }
            do {
                model = try ElsterSettingsModel(context: context)
            } catch {
                loadError = error.localizedDescription
            }
        }
    }
}

private struct ElsterSettingsForm: View {
    let model: ElsterSettingsModel

    var body: some View {
        Form {
            EricSection()
            CertificateSection()
            SteuernummerSection(model: model)
            DetailsSection(model: model)
            FilingSettingsSection(model: model)
            VorsteuerRulesSection(model: model)
            Section {
                Toggle("Test mode", isOn: model.binding(\.testMode))
                    .accessibilityIdentifier("settings.elster.testMode")
            } header: {
                Text("Sending")
            } footer: {
                Text("In test mode returns carry the ELSTER test marker, so the Finanzamt does not process them.")
            }
            if let error = model.saveError {
                Section {
                    Label(error, systemImage: "exclamationmark.triangle").foregroundStyle(Theme.bad)
                }
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - ERiC

/// The ERiC library embedded in the app: version and available UStVA plugins, plus the Hersteller-ID.
private struct EricSection: View {
    private let eric = EricRuntime.shared

    var body: some View {
        Section("ELSTER") {
            LabeledContent("ERiC") {
                Text(summary)
                    .multilineTextAlignment(.trailing)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
                    .accessibilityIdentifier("settings.eric")
            }
            LabeledContent("Hersteller-ID") {
                Text(verbatim: EricRuntime.herstellerID ?? "–")
                    .textSelection(.enabled)
                    .accessibilityIdentifier("settings.elster.herstellerID")
            }
        }
        .task { await eric.loadVersion() }
    }

    private var summary: String {
        switch eric.status {
        case .notLoaded, .loading:
            return String(localized: "Loading…")
        case .failed(let message):
            return String(localized: "Not available: \(message)")
        case .ready(let info):
            let version = info.displayVersion ?? "?"
            let years = info.ustvaPluginYears.map(String.init)
            switch years.count {
            case 0: return String(localized: "ERiC \(version), no UStVA plugin")
            case 1: return String(localized: "ERiC \(version), UStVA \(years[0]) plugin available")
            default: return String(localized: "ERiC \(version), UStVA \(years.formatted(.list(type: .and))) plugins available")
            }
        }
    }
}

// MARK: - Certificate

/// The ELSTER certificate (.pfx/.p12) and its PIN, kept in this Mac's Keychain. Importing opens the certificate
/// with the PIN and reads its properties before anything is stored.
private struct CertificateSection: View {
    @State private var credentials = ElsterCredentials.shared
    @State private var importing = false
    /// A picked certificate waiting for its PIN.
    @State private var pending: (name: String, data: Data)?
    @State private var pin = ""
    @State private var verifying = false
    @State private var message: String?
    @State private var confirmingRemove = false

    static let types: [UTType] = [.pkcs12] + [UTType(filenameExtension: "pfx"), UTType(filenameExtension: "p12")]
        .compactMap { $0 }

    var body: some View {
        Section {
            if let info = credentials.info {
                CertificateInfoRows(info: info)
            } else if credentials.hasCertificate {
                LabeledContent("Certificate") { Text("Stored in the Keychain") }
            } else if credentials.loaded {
                Text("No certificate yet. Import the .pfx file you use for Mein ELSTER.")
                    .foregroundStyle(.secondary)
            }
            if let error = credentials.infoError, pending == nil {
                Label(ElsterCredentials.message(error), systemImage: "exclamationmark.triangle")
                    .foregroundStyle(Theme.bad)
            }
            if let pending {
                LabeledContent("File") { Text(verbatim: pending.name) }
            }
            if pending != nil || (credentials.hasCertificate && !credentials.hasPIN) {
                LabeledContent("PIN") {
                    HStack {
                        SecureField("PIN", text: $pin)
                            .labelsHidden()
                            .textContentType(.password)
                            .onSubmit(verify)
                            .accessibilityIdentifier("settings.elster.pin")
                        Button(pending == nil ? "Save PIN" : "Verify and Save", action: verify)
                            .disabled(pin.isEmpty || verifying)
                            .accessibilityIdentifier("settings.elster.verifyCertificate")
                    }
                }
            }
            if let message {
                Label(message, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(Theme.bad)
                    .accessibilityIdentifier("settings.elster.certificateError")
            }
            HStack {
                Button(credentials.hasCertificate ? "Replace…" : "Import…") { importing = true }
                    .accessibilityIdentifier("settings.elster.importCertificate")
                if pending != nil {
                    Button("Cancel") {
                        pending = nil
                        pin = ""
                        message = nil
                    }
                }
                Spacer()
                if credentials.hasCertificate {
                    Button("Remove", role: .destructive) { confirmingRemove = true }
                        .accessibilityIdentifier("settings.elster.removeCertificate")
                }
                if verifying { ProgressView().controlSize(.small) }
            }
        } header: {
            Text("Certificate")
        } footer: {
            Text("The certificate and its PIN are kept in this Mac's Keychain only; they don't sync. Every send still asks for confirmation.")
        }
        .fileImporter(isPresented: $importing, allowedContentTypes: Self.types) { result in
            pick(result)
        }
        .confirmationDialog("Remove the certificate and its PIN from this Mac?", isPresented: $confirmingRemove) {
            Button("Remove", role: .destructive) {
                do {
                    try credentials.remove()
                    message = nil
                } catch {
                    message = error.localizedDescription
                }
            }
        }
        .task { await credentials.load() }
    }

    private func pick(_ result: Result<URL, any Error>) {
        message = nil
        do {
            let url = try result.get()
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            pending = (url.lastPathComponent, try Data(contentsOf: url))
            pin = ""
        } catch {
            message = error.localizedDescription
        }
    }

    private func verify() {
        guard !pin.isEmpty, !verifying else { return }
        verifying = true
        Task {
            defer { verifying = false }
            do {
                if let pending {
                    _ = try await credentials.importCertificate(pending.data, pin: pin)
                } else {
                    try await credentials.savePIN(pin)
                }
                pending = nil
                pin = ""
                message = nil
            } catch let error as ElsterCredentials.CredentialError {
                message = ElsterCredentials.message(error)
            } catch {
                message = error.localizedDescription
            }
        }
    }
}

/// Holder, issuer, validity and the expiry warning of a certificate.
struct CertificateInfoRows: View {
    let info: EricCertificateInfo

    var body: some View {
        LabeledContent("Holder") {
            Text(verbatim: info.holder ?? "–").textSelection(.enabled)
                .accessibilityIdentifier("settings.elster.certificateHolder")
        }
        LabeledContent("Issuer") { Text(verbatim: info.issuerName ?? "–").textSelection(.enabled) }
        LabeledContent("Valid") {
            Text(verbatim: [info.validFrom, info.validUntil]
                .map { $0?.formatted(date: .long, time: .omitted) ?? "?" }.joined(separator: " – "))
        }
        if info.isTestCertificate {
            Label("ELSTER test certificate", systemImage: "testtube.2").foregroundStyle(Theme.accent)
        }
        switch info.expiryWarning() {
        case .expired:
            Label("The certificate has expired. Renew it in Mein ELSTER and import the new file.",
                  systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(Theme.bad)
        case .expiresSoon(let days):
            Label("The certificate expires in ^[\(days) day](inflect: true). Renew it in Mein ELSTER.",
                  systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(Theme.amber)
        case nil:
            EmptyView()
        }
    }
}

// MARK: - Steuernummer and Finanzamt

/// Bundesland and Finanzamt from ERiC's lists, and the Steuernummer in the notation of the Finanzamt's letters,
/// converted to the 13-digit ELSTER format (`EricMtMakeElsterStnr`) and checked (`EricMtPruefeSteuernummer`).
private struct SteuernummerSection: View {
    let model: ElsterSettingsModel
    private let service = EricRuntime.shared.service

    @State private var laender: [EricFinanzamtLand] = []
    @State private var finanzaemter: [EricFinanzamt] = []
    @State private var landNummer = ""
    @State private var regional = ""
    @State private var message: String?
    @State private var checking = false
    @State private var lookupError: String?

    private var identity: TaxIdentity { model.settings.identity }

    var body: some View {
        Section {
            Picker("Bundesland", selection: $landNummer) {
                Text("Choose…").tag("")
                ForEach(laender) { land in Text(verbatim: land.name).tag(land.nummer) }
            }
            .accessibilityIdentifier("settings.elster.bundesland")
            Picker("Finanzamt", selection: finanzamtBinding) {
                Text("Choose…").tag("")
                ForEach(finanzamtOptions) { amt in
                    Text(verbatim: "\(amt.name) (\(amt.bufaNummer))").tag(amt.bufaNummer)
                }
            }
            .disabled(landNummer.isEmpty)
            .accessibilityIdentifier("settings.elster.finanzamt")
            LabeledContent("Steuernummer") {
                HStack {
                    TextField("Steuernummer", text: $regional, prompt: Text(verbatim: "21/815/08150"))
                        .labelsHidden()
                        .onSubmit(convert)
                        .accessibilityIdentifier("settings.elster.steuernummer")
                    Button("Check", action: convert)
                        .disabled(checking || regional.trimmingCharacters(in: .whitespaces).isEmpty || landNummer.isEmpty)
                }
            }
            if let message {
                Label(message, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(Theme.bad)
                    .accessibilityIdentifier("settings.elster.steuernummerError")
            } else if !identity.steuernummer.isEmpty {
                LabeledContent("ELSTER format") {
                    Label {
                        Text(verbatim: identity.steuernummer).monospacedDigit().textSelection(.enabled)
                    } icon: {
                        Image(systemName: "checkmark.circle").foregroundStyle(Theme.moneyIn)
                    }
                    .accessibilityIdentifier("settings.elster.steuernummerElster")
                }
            }
            if let lookupError {
                Label(lookupError, systemImage: "exclamationmark.triangle").foregroundStyle(Theme.amber)
            }
        } header: {
            Text("Steuernummer")
        } footer: {
            Text("Enter the Steuernummer as it appears on letters from your Finanzamt. It is converted to the ELSTER format and checked.")
        }
        .task { await loadLaender() }
        .onChange(of: landNummer) { _, land in Task { await loadFinanzaemter(land) } }
    }

    /// The Finanzämter of the chosen Bundesland, plus the stored one when ERiC doesn't list it (a test office).
    private var finanzamtOptions: [EricFinanzamt] {
        let stored = identity.finanzamt
        guard !stored.isEmpty, stored.hasPrefix(landNummer), !finanzaemter.contains(where: { $0.bufaNummer == stored })
        else { return finanzaemter }
        return finanzaemter + [EricFinanzamt(bufaNummer: stored, name: String(localized: "Finanzamt"))]
    }

    private var finanzamtBinding: Binding<String> {
        Binding { identity.finanzamt } set: { bufa in
            model.update { settings in
                settings.identity.finanzamt = bufa
                // A Steuernummer belongs to its Finanzamt (its first four digits).
                if !settings.identity.steuernummer.isEmpty, !settings.identity.steuernummer.hasPrefix(bufa) {
                    settings.identity.steuernummer = ""
                }
            }
            message = nil
        }
    }

    private func loadLaender() async {
        regional = identity.steuernummerRegional
        landNummer = String(identity.finanzamt.prefix(2))
        do {
            laender = try await service.bundeslaender()
            lookupError = nil
        } catch {
            lookupError = String(localized: "ERiC is not available: \(error.description)")
        }
    }

    private func loadFinanzaemter(_ land: String) async {
        guard !land.isEmpty else {
            finanzaemter = []
            return
        }
        do {
            finanzaemter = try await service.finanzaemter(landNummer: land)
        } catch {
            finanzaemter = []
            lookupError = String(localized: "ERiC is not available: \(error.description)")
        }
    }

    private func convert() {
        let input = regional.trimmingCharacters(in: .whitespaces)
        guard !input.isEmpty, !landNummer.isEmpty else { return }
        let bufa = identity.finanzamt.hasPrefix(landNummer) ? identity.finanzamt : ""
        checking = true
        Task {
            defer { checking = false }
            do {
                let elster = try await service.makeElsterSteuernummer(
                    input, landesnummer: bufa.isEmpty ? landNummer : nil,
                    bundesfinanzamtsnummer: bufa.isEmpty ? nil : bufa)
                try await service.checkSteuernummer(elster)
                model.update { settings in
                    settings.identity.steuernummer = elster
                    settings.identity.steuernummerRegional = input
                    settings.identity.finanzamt = String(elster.prefix(4))
                }
                message = nil
            } catch {
                message = await describe(error)
            }
        }
    }

    private func describe(_ error: any Error) async -> String {
        guard let error = error as? EricError else { return error.localizedDescription }
        if case .callFailed(_, let code) = error, let text = await service.errorText(for: code) {
            if code == Int32(ERIC_GLOBAL_UNGUELTIGER_PARAMETER_CODE) || code == Int32(ERIC_GLOBAL_BUFANR_UNBEKANNT_CODE) {
                return String(localized: "\(text) Choose your Finanzamt: numbers like 113/10010 need it.")
            }
            return text
        }
        return error.description
    }
}

/// ERIC_GLOBAL_UNGUELTIGER_PARAMETER and ERIC_GLOBAL_BUFANR_UNBEKANNT (eric_fehlercodes.h).
private let ERIC_GLOBAL_UNGUELTIGER_PARAMETER_CODE = 610001222
private let ERIC_GLOBAL_BUFANR_UNBEKANNT_CODE = 610001038

// MARK: - Details

private struct DetailsSection: View {
    let model: ElsterSettingsModel

    var body: some View {
        Section {
            TextField("Name", text: model.binding(\.identity.name))
            TextField("Street", text: model.binding(\.identity.street))
            TextField("House number", text: model.binding(\.identity.houseNumber))
            TextField("Postal code", text: model.binding(\.identity.postalCode))
            TextField("City", text: model.binding(\.identity.city))
            TextField("Phone", text: model.binding(\.identity.phone))
            TextField("Email", text: model.binding(\.identity.email))
            TextField("USt-IdNr", text: model.binding(\.identity.vatID), prompt: Text(verbatim: "DE123456789"))
                .accessibilityIdentifier("settings.elster.vatID")
            if !vatID.isEmpty, vatID.wholeMatch(of: /DE[0-9]{9}/) == nil {
                invalid("A German USt-IdNr is DE followed by nine digits.")
            }
            TextField("W-IdNr", text: model.binding(\.identity.wIdNr), prompt: Text(verbatim: "DE123456788-00001"))
                .accessibilityIdentifier("settings.elster.wIdNr")
            if !model.settings.identity.wIdNr.isEmpty, !WIdNr.isWellFormed(model.settings.identity.wIdNr) {
                invalid("A W-IdNr is DE followed by nine digits, optionally with a suffix like -00001.")
            }
        } header: {
            Text("Your Details")
        } footer: {
            Text("Sent with every return. The USt-IdNr is required for the Zusammenfassende Meldung.")
        }
    }

    private var vatID: String { model.settings.identity.vatID.uppercased().filter { !$0.isWhitespace } }

    private func invalid(_ text: LocalizedStringKey) -> some View {
        Label(text, systemImage: "exclamationmark.triangle").font(.callout).foregroundStyle(Theme.bad)
    }
}

// MARK: - Filing settings

/// The effective-dated `TaxSettingsPeriod`s: pick one by its start date, edit it, or add a new one.
private struct FilingSettingsSection: View {
    let model: ElsterSettingsModel
    @State private var selected = ""
    @State private var newStart = Date()

    private var periods: [TaxSettingsPeriod] { model.settings.periods }

    var body: some View {
        Section {
            if periods.isEmpty {
                Text("No filing settings yet.").foregroundStyle(.secondary)
            } else {
                Picker("Settings from", selection: $selected) {
                    ForEach(periods, id: \.effectiveFrom) { period in
                        Text(Self.display(period.effectiveFrom)).tag(period.effectiveFrom)
                    }
                }
                .accessibilityIdentifier("settings.elster.period")
                if periods.contains(where: { $0.effectiveFrom == selected }) {
                    PeriodFields(model: model, effectiveFrom: selected)
                    if periods.count > 1 {
                        Button("Remove These Settings", role: .destructive) {
                            model.update { $0.remove(effectiveFrom: selected) }
                            selected = currentStart
                        }
                    }
                }
            }
            HStack {
                DatePicker("New settings from", selection: $newStart, displayedComponents: .date)
                Button("Add Settings from \(newStart.formatted(date: .abbreviated, time: .omitted))", action: add)
                    .disabled(periods.contains { $0.effectiveFrom == Self.iso(newStart) })
                    .accessibilityIdentifier("settings.elster.addPeriod")
            }
        } header: {
            Text("Filing Settings")
        } footer: {
            Text("Each set of settings applies from its date until the next one starts. The Finanzamt usually sets them per calendar year, so add new settings from 1 January instead of changing past ones.")
        }
        .onAppear {
            if selected.isEmpty { selected = currentStart }
            newStart = Self.date(nextStart) ?? Date()
        }
    }

    /// The period in force today, else the latest.
    private var currentStart: String {
        model.settings.period(on: ISODate.today())?.effectiveFrom ?? periods.last?.effectiveFrom ?? ""
    }

    /// 1 January after the latest period's year.
    private var nextStart: String {
        let year = periods.last.flatMap { ISODate.year($0.effectiveFrom) } ?? (ISODate.year(ISODate.today()) ?? 2026)
        return ISODate.make(year + 1, 1, 1)
    }

    private func add() {
        let start = Self.iso(newStart)
        // The new period starts as a copy of the settings in force on its start date.
        var period = model.settings.period(on: start) ?? periods.first ?? .initial(from: start)
        period.effectiveFrom = start
        model.update { $0.set(period) }
        selected = start
    }

    static func iso(_ date: Date) -> String { ISODate.today(date) }

    static func date(_ iso: String) -> Date? {
        guard let c = ISODate.components(iso) else { return nil }
        return Calendar.current.date(from: DateComponents(year: c.year, month: c.month, day: c.day))
    }

    static func display(_ iso: String) -> String {
        date(iso)?.formatted(date: .long, time: .omitted) ?? iso
    }
}

private struct PeriodFields: View {
    let model: ElsterSettingsModel
    let effectiveFrom: String

    private var period: TaxSettingsPeriod? { model.settings.periods.first { $0.effectiveFrom == effectiveFrom } }

    private func binding<Value>(_ keyPath: WritableKeyPath<TaxSettingsPeriod, Value>) -> Binding<Value> {
        model.binding(period: effectiveFrom, keyPath, default: TaxSettingsPeriod.initial(from: effectiveFrom)[keyPath: keyPath])
    }

    var body: some View {
        Picker("Taxation method", selection: binding(\.taxationMethod)) {
            Text("Soll (VAT when invoiced)").tag(TaxationMethod.soll)
            Text("Ist (VAT when paid)").tag(TaxationMethod.ist)
        }
        Picker("UStVA", selection: binding(\.ustvaFrequency)) {
            Text("Monthly").tag(FilingFrequency.monthly)
            Text("Quarterly").tag(FilingFrequency.quarterly)
            Text("None (annual return only)").tag(FilingFrequency.none)
        }
        Toggle("Dauerfristverlängerung", isOn: binding(\.dauerfristverlaengerung))
        if period?.dauerfristverlaengerung == true, period?.ustvaFrequency == .monthly {
            Toggle("Enter Sondervorauszahlung by hand", isOn: overrideOn)
            if period?.sondervorauszahlungOverride != nil {
                LabeledContent("Sondervorauszahlung") {
                    AmountField(value: overrideAmount).frame(maxWidth: 140)
                }
            } else {
                Text("Computed as 1/11 of the prior year's advance payments: the sum of its Kz83 plus its Sondervorauszahlung.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        Picker("Zusammenfassende Meldung", selection: binding(\.zmFrequency)) {
            Text("Monthly").tag(ZMFrequency.monthly)
            Text("Quarterly").tag(ZMFrequency.quarterly)
        }
        LabeledContent("ZM warning threshold") {
            AmountField(value: Binding { period?.zmThreshold } set: { if let v = $0 { binding(\.zmThreshold).wrappedValue = v } })
                .frame(maxWidth: 140)
        }
    }

    private var overrideOn: Binding<Bool> {
        Binding { period?.sondervorauszahlungOverride != nil } set: { on in
            binding(\.sondervorauszahlungOverride).wrappedValue = on ? 0 : nil
        }
    }

    private var overrideAmount: Binding<Decimal?> {
        Binding { period?.sondervorauszahlungOverride } set: { value in
            if let value { binding(\.sondervorauszahlungOverride).wrappedValue = value }
        }
    }
}

/// A euro amount, typed with a decimal point or comma. Keeps the text as typed and reports parsed values only.
private struct AmountField: View {
    @Binding var value: Decimal?
    @State private var text = ""

    var body: some View {
        TextField("Amount", text: $text, prompt: Text(verbatim: "0.00"))
            .labelsHidden()
            .multilineTextAlignment(.trailing)
            .onAppear { text = value.map(Money.plainString) ?? "" }
            .onChange(of: text) { _, newText in
                if let parsed = Money.parseInput(newText), parsed >= 0, parsed != value { value = parsed }
            }
            .onChange(of: value) { _, newValue in
                if Money.parseInput(text) != newValue { text = newValue.map(Money.plainString) ?? "" }
            }
            .foregroundStyle(!text.isEmpty && Money.parseInput(text) == nil ? Theme.bad : Color.primary)
    }
}

// MARK: - Vorsteuer share rules

/// Expense category keywords → how much of the VAT counts as input tax. The first matching rule wins.
private struct VorsteuerRulesSection: View {
    let model: ElsterSettingsModel

    private var rules: VorsteuerShareRules { model.settings.vorsteuerShareRules }

    var body: some View {
        Section {
            ForEach(Array(rules.rules.indices), id: \.self) { index in
                HStack(alignment: .firstTextBaseline) {
                    KeywordsField(keywords: rule(index, \.keywords, default: []))
                    Picker("Share", selection: rule(index, \.policy, default: .full)) {
                        PolicyOptions()
                    }
                    .labelsHidden()
                    .fixedSize()
                    Menu {
                        Button("Move Up") { move(index, by: -1) }.disabled(index == 0)
                        Button("Move Down") { move(index, by: 1) }.disabled(index == rules.rules.count - 1)
                        Divider()
                        Button("Delete Rule", role: .destructive) {
                            model.update { settings in
                                guard settings.vorsteuerShareRules.rules.indices.contains(index) else { return }
                                settings.vorsteuerShareRules.rules.remove(at: index)
                            }
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                    .menuStyle(.borderlessButton)
                    .menuIndicator(.hidden)
                    .fixedSize()
                    .accessibilityLabel(Text("Rule Actions"))
                }
            }
            Picker("Other categories", selection: model.binding(\.vorsteuerShareRules.fallback)) { PolicyOptions() }
            Picker("Home office records", selection: homeOffice) {
                Text("By category").tag(VorsteuerSharePolicy?.none)
                ForEach(VorsteuerSharePolicy.allCases, id: \.self) { policy in
                    Text(PolicyOptions.label(policy)).tag(Optional(policy))
                }
            }
            HStack {
                Button("Add Rule") {
                    model.update { $0.vorsteuerShareRules.rules.append(.init(.full, [])) }
                }
                Spacer()
                Button("Reset to Defaults") { model.update { $0.vorsteuerShareRules = .default } }
                    .disabled(rules == .default)
                    .accessibilityIdentifier("settings.elster.resetRules")
            }
        } header: {
            Text("Input Tax (Vorsteuer) Share")
        } footer: {
            Text("Comma-separated keywords match whole words of an expense's category; end a keyword with * to match words starting with it. The first matching rule wins.")
        }
    }

    /// A binding to a field of rule `index` that tolerates the row outliving its rule.
    private func rule<Value>(_ index: Int, _ keyPath: WritableKeyPath<VorsteuerShareRules.Rule, Value>,
                             default fallback: Value) -> Binding<Value> {
        Binding {
            let rules = model.settings.vorsteuerShareRules.rules
            return rules.indices.contains(index) ? rules[index][keyPath: keyPath] : fallback
        } set: { value in
            model.update { settings in
                guard settings.vorsteuerShareRules.rules.indices.contains(index) else { return }
                settings.vorsteuerShareRules.rules[index][keyPath: keyPath] = value
            }
        }
    }

    private var homeOffice: Binding<VorsteuerSharePolicy?> {
        model.binding(\.vorsteuerShareRules.homeOffice)
    }

    private func move(_ index: Int, by offset: Int) {
        model.update { settings in
            let target = index + offset
            guard settings.vorsteuerShareRules.rules.indices.contains(target) else { return }
            settings.vorsteuerShareRules.rules.swapAt(index, target)
        }
    }
}

private struct PolicyOptions: View {
    var body: some View {
        ForEach(VorsteuerSharePolicy.allCases, id: \.self) { policy in
            Text(Self.label(policy)).tag(policy)
        }
    }

    static func label(_ policy: VorsteuerSharePolicy) -> LocalizedStringKey {
        switch policy {
        case .full: "Full VAT"
        case .followsDeductibleShare: "Deductible share"
        case .none: "No VAT"
        }
    }
}

/// Comma-separated keywords. Keeps the text as typed (a trailing comma survives) and reports the parsed list.
private struct KeywordsField: View {
    @Binding var keywords: [String]
    @State private var text = ""

    var body: some View {
        TextField("Keywords", text: $text, prompt: Text("keywords, like phone*"))
            .labelsHidden()
            .onAppear { text = keywords.joined(separator: ", ") }
            .onChange(of: text) { _, newText in
                let parsed = Self.parse(newText)
                if parsed != keywords { keywords = parsed }
            }
            .onChange(of: keywords) { _, newKeywords in
                if Self.parse(text) != newKeywords { text = newKeywords.joined(separator: ", ") }
            }
    }

    static func parse(_ text: String) -> [String] {
        text.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }
}
#endif
