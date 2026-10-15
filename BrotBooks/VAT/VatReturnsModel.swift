#if os(macOS)
import BrotBooksKit
import EricKit
import Foundation
import Observation
import os
import SwiftData

/// The VAT returns screen's data and state: the returns of the current and previous year under the tax profile,
/// each UStVA period's aggregation, the treatment review list, and the Validate / Preview runs.
@MainActor
@Observable
final class VatReturnsModel {
    static let shared = VatReturnsModel()

    enum Operation: Equatable {
        case validating, previewing, sending
    }

    /// A preview PDF shown in the sheet.
    struct PreviewDocument: Identifiable {
        let id = UUID()
        let title: String
        let filename: String
        let data: Data
    }

    private(set) var settings: TaxSettings?
    private(set) var items: [VatReturnItem] = []
    /// Aggregation per UStVA item, by item id.
    private(set) var results: [String: UStVAResult] = [:]
    /// Drafts dated in each UStVA period, by item id.
    private(set) var draftIssues: [String: [UStVAIssue]] = [:]
    /// Records with an unconfirmed treatment in the open periods.
    private(set) var review: [VatTreatmentReview.Entry] = []
    /// Every record (drafts and removed ones included), by uid.
    private(set) var records: [String: RecordSnapshot] = [:]
    private(set) var loadError: String?
    private(set) var today = ISODate.today()

    /// The selected item's id.
    var selection: String? {
        didSet { if selection != oldValue { selectedKennzahl = nil } }
    }
    /// The Kennzahl row whose contributing records are shown.
    var selectedKennzahl: Kennzahl?
    /// Kz10, Kz22, Kz26, Kz29 per item id. Not stored: they are chosen per filing.
    var flags: [String: UStVAFlags] = [:]
    private(set) var running: [String: Operation] = [:]
    /// The last Validate (or failed Preview) result per item id.
    private(set) var validations: [String: EricValidationResult] = [:]
    /// ERiC errors that kept Validate or Preview from running, per item id.
    private(set) var failures: [String: String] = [:]
    var preview: PreviewDocument?
    var showingReview = false
    /// The XML each item's last Validate checked; sending needs it to match the current XML.
    private(set) var validatedXML: [String: String] = [:]
    /// The filings of each item, by item id, oldest first.
    private(set) var filings: [String: [VatFiling]] = [:]
    /// The send in progress or just finished (the send sheet).
    var sendSession: SendSession?
    /// The item whose "Mark as Filed Elsewhere" sheet is open.
    var markingElsewhere: VatReturnItem?
    /// The filings the last bulk "Mark All Past Periods as Filed Elsewhere" created, for its Undo.
    private(set) var lastBulkMark: (year: Int, uids: [String])?
    private weak var app: AppModel?

    private let log = Logger(subsystem: "me.freas.BrotBooks", category: "VAT")

    var selectedItem: VatReturnItem? { items.first { $0.id == selection } }

    // MARK: Loading

    /// Recomputes everything from the store and the tax profile. Called on appear and whenever records or
    /// settings change.
    func reload(_ app: AppModel) {
        guard let store = app.store, let context = app.storage?.container.mainContext else { return }
        self.app = app
        do {
            today = app.today
            let settings = try TaxProfile.load(in: context)
            let allFilings = try context.fetch(FetchDescriptor<VatFiling>())
                .sorted { ($0.sentAt ?? $0.createdAt) < ($1.sentAt ?? $1.createdAt) }
            var snapshots: [RecordSnapshot] = []
            for kind in Kind.allCases {
                snapshots += try store.snapshots(kind, includeRemoved: true, drafts: .include)
            }
            let records = snapshots.map(UStVARecord.init)
            let year = ISODate.year(today) ?? 2026
            let items = VatReturnSchedule.items(years: [year - 1, year], settings: settings,
                                                filings: allFilings.map(\.entry))
            let filings = Dictionary(grouping: allFilings) { $0.itemID ?? "" }

            var results: [String: UStVAResult] = [:]
            var drafts: [String: [UStVAIssue]] = [:]
            for item in items {
                guard let period = item.period else { continue }
                results[item.id] = item.aggregate(records)
                drafts[item.id] = UStVAAggregator.draftIssues(records, period: period)
            }

            self.settings = settings
            self.items = items
            self.filings = filings
            self.results = results
            self.draftIssues = drafts
            self.records = Dictionary(snapshots.map { ($0.uid, $0) }, uniquingKeysWith: { a, _ in a })
            review = VatTreatmentReview.entries(records, items: items) { [today] item in
                VatReturnStatus.of(item, today: today, filing: VatFilings((filings[item.id] ?? []).map(\.entry)).mark)
                    .isOpen
            }
            loadError = nil
        } catch {
            log.error("Loading VAT returns failed: \(error.localizedDescription, privacy: .public)")
            loadError = error.localizedDescription
        }
    }

    // MARK: Status

    /// The filings of `item`, as values.
    func filingSummary(_ item: VatReturnItem) -> VatFilings {
        VatFilings((filings[item.id] ?? []).map(\.entry))
    }

    /// How `item` stands for production: accepted, filed elsewhere or uncertain; test filings never count.
    func filingMark(for item: VatReturnItem) -> VatFilingMark? { filingSummary(item).mark }

    func status(_ item: VatReturnItem) -> VatReturnStatus {
        VatReturnStatus.of(item, today: today, filing: filingMark(for: item))
    }

    /// The return was accepted with the test marker (shown next to its production status).
    func filedInTest(_ item: VatReturnItem) -> Bool { filingSummary(item).filedInTest }

    /// The warnings of a UStVA item: drafts first, then the aggregation's issues.
    func warnings(_ item: VatReturnItem) -> [UStVAIssue] {
        (draftIssues[item.id] ?? []) + (results[item.id]?.issues ?? [])
    }

    /// Sending is blocked while the period has records with an unconfirmed treatment.
    func blocksSending(_ item: VatReturnItem) -> Bool {
        results[item.id]?.blocksSending ?? false
    }

    // MARK: Building

    enum Blocker: Hashable {
        case herstellerID
        case identity(FilingRequirement)
        case sondervorauszahlung
    }

    /// What keeps Validate and Preview from running for `item`.
    func blockers(_ item: VatReturnItem) -> [Blocker] {
        var blockers: [Blocker] = []
        if EricRuntime.herstellerID == nil { blockers.append(.herstellerID) }
        blockers += item.configuration.identity.missingForFiling.map(Blocker.identity)
        if case .sondervorauszahlung = item.type, item.needsSondervorauszahlungAmount {
            blockers.append(.sondervorauszahlung)
        }
        return blockers
    }

    var header: UStVAXML.Header {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
        return UStVAXML.header(herstellerID: EricRuntime.herstellerID ?? "", produktVersion: version, today: today)
    }

    func xml(_ item: VatReturnItem) -> String? {
        item.xml(result: results[item.id], flags: flags[item.id] ?? [], header: header)
    }

    // MARK: ERiC

    /// Validates the return's XML with ERiC (rule errors and hints). Runs on the `EricService` actor.
    func validate(_ item: VatReturnItem) async {
        guard running[item.id] == nil, blockers(item).isEmpty, let xml = xml(item) else { return }
        running[item.id] = .validating
        defer { running[item.id] = nil }
        failures[item.id] = nil
        do {
            validations[item.id] = try await EricRuntime.shared.service.validate(xml: xml,
                                                                                datenartVersion: item.datenartVersion)
            validatedXML[item.id] = xml
        } catch {
            log.error("Validate \(item.id, privacy: .public) failed: \(error.description, privacy: .public)")
            validations[item.id] = nil
            failures[item.id] = error.description
        }
    }

    /// Prints ERiC's preview PDF and shows it; when ERiC prints none (validation failed), shows the messages.
    func preview(_ item: VatReturnItem, title: String) async {
        guard running[item.id] == nil, blockers(item).isEmpty, let xml = xml(item) else { return }
        running[item.id] = .previewing
        defer { running[item.id] = nil }
        failures[item.id] = nil
        do {
            let result = try await EricRuntime.shared.service.preview(xml: xml, datenartVersion: item.datenartVersion)
            validations[item.id] = result.validation
            if let pdf = result.pdf {
                preview = PreviewDocument(title: title, filename: "\(Self.filenameStem(item)).pdf", data: pdf)
            }
        } catch {
            log.error("Preview \(item.id, privacy: .public) failed: \(error.description, privacy: .public)")
            failures[item.id] = error.description
        }
    }

    static func filenameStem(_ item: VatReturnItem) -> String {
        switch item.type {
        case .ustva(let period): return "UStVA \(period.year)-\(period.zeitraum)"
        case .sondervorauszahlung(let year): return "Sondervorauszahlung \(year)"
        case .dauerfristverlaengerung(let year): return "Dauerfristverlaengerung \(year)"
        }
    }

    // MARK: Sending

    enum SendBlocker: Hashable {
        /// Validate and Preview are blocked too (`blockers`).
        case cannotBuild
        case unconfirmedTreatments
        case noCertificate
        /// Validate hasn't run on the current XML (or the flags changed since).
        case notValidated
        case validationFailed
        /// The return was filed already: sending again needs Kz10.
        case correctionRequired
        /// The return was filed already and this kind of return has no Kz10.
        case alreadyFiled
        case sending
    }

    /// What keeps `item` from being sent; empty when Send… is enabled.
    func sendBlockers(_ item: VatReturnItem) -> [SendBlocker] {
        var blockers: [SendBlocker] = []
        if !self.blockers(item).isEmpty || xml(item) == nil { blockers.append(.cannotBuild) }
        if blocksSending(item) { blockers.append(.unconfirmedTreatments) }
        let credentials = ElsterCredentials.shared
        if !credentials.usesStubTransport && !credentials.hasCertificate { blockers.append(.noCertificate) }
        if let validation = validations[item.id], validatedXML[item.id] == xml(item) {
            if !validation.isValid { blockers.append(.validationFailed) }
        } else {
            blockers.append(.notValidated)
        }
        if filingSummary(item).requiresCorrection && !(flags[item.id] ?? []).contains(.correction) {
            blockers.append(item.availableFlags.contains { $0.flag == .correction } ? .correctionRequired : .alreadyFiled)
        }
        if running[item.id] != nil { blockers.append(.sending) }
        return blockers
    }

    /// The send sheet: confirmation, progress and result of sending one return.
    struct SendSession: Identifiable {
        enum Stage: Equatable {
            case confirm, sending, result
        }

        let id = UUID()
        let itemID: String
        let isTest: Bool
        var stage = Stage.confirm
        var progress: EricProgress?
        var outcome: EricSendOutcome?
        /// The filing recorded for the outcome.
        var filingUID: String?
        /// A PIN problem found before sending.
        var pinError: String?
        /// Recording the filing or its protocol failed.
        var saveError: String?
    }

    /// Opens the send sheet for `item`.
    func beginSend(_ item: VatReturnItem) {
        guard sendBlockers(item).isEmpty else { return }
        sendSession = SendSession(itemID: item.id, isTest: item.configuration.testMode)
    }

    /// Sends `item` through the transport (ERiC, or the stub) once: never retried. With `pin`, the PIN is first
    /// checked against the stored certificate and stored. Records a `VatFiling` for every outcome that may have
    /// reached the server (accepted, rejected, uncertain) with its protocol PDF in the documents folder.
    func send(_ item: VatReturnItem, pin: String? = nil) async {
        guard var session = sendSession, session.itemID == item.id, session.stage == .confirm,
              sendBlockers(item).isEmpty, let xml = xml(item) else { return }
        let credentials = ElsterCredentials.shared
        var request = EricSendRequest(xml: xml, datenartVersion: item.datenartVersion, certificate: Data(), pin: "")
        if !credentials.usesStubTransport {
            if let pin {
                do {
                    try await credentials.savePIN(pin)
                } catch {
                    session.pinError = ElsterCredentials.message(error)
                    sendSession = session
                    return
                }
            }
            guard let stored = credentials.credentials() else {
                session.pinError = String(localized: "Enter the certificate's PIN.")
                sendSession = session
                return
            }
            request.certificate = stored.certificate
            request.pin = stored.pin
        }

        session.pinError = nil
        session.stage = .sending
        sendSession = session
        running[item.id] = .sending
        defer { running[item.id] = nil }
        let sessionID = session.id
        let progress: @Sendable (EricProgress) -> Void = { progress in
            Task { @MainActor in
                guard VatReturnsModel.shared.sendSession?.id == sessionID,
                      VatReturnsModel.shared.sendSession?.stage == .sending else { return }
                if progress.isOverall || VatReturnsModel.shared.sendSession?.progress == nil {
                    VatReturnsModel.shared.sendSession?.progress = progress
                }
            }
        }

        let flags = self.flags[item.id] ?? []
        let outcome: EricSendOutcome
        var result: EricSendResult?
        do {
            let sent = try await credentials.submitter.submit(request, progress: progress)
            result = sent
            outcome = EricSendOutcome.classify(sent)
        } catch {
            log.error("Send \(item.id, privacy: .public) failed to run: \(String(describing: error), privacy: .public)")
            outcome = .failed(code: -1, text: (error as? EricError)?.description ?? error.localizedDescription)
        }
        log.notice("Send \(item.id, privacy: .public) (test \(item.configuration.testMode)): \(String(describing: outcome), privacy: .public)")

        if outcome == .pinWrong { try? credentials.clearPIN() }
        if outcome.reachedServer, let result {
            session.filingUID = record(item, outcome: outcome, result: result, flags: flags, xml: xml,
                                       error: &session.saveError)
        }
        session.outcome = outcome
        session.stage = .result
        if sendSession?.id == session.id {
            session.progress = sendSession?.progress
            sendSession = session
        }
        if let app { reload(app) }
    }

    /// Stores the filing of a send and its protocol PDF; returns its uid.
    private func record(_ item: VatReturnItem, outcome: EricSendOutcome, result: EricSendResult, flags: UStVAFlags,
                        xml: String, error saveError: inout String?) -> String? {
        guard let app, let context = app.storage?.container.mainContext else { return nil }
        let state: VatFiling.State
        switch outcome {
        case .accepted: state = .accepted
        case .rejected: state = .rejected
        default: state = .uncertain
        }
        let sentAt = Date()
        let filing = VatFiling(item: item, state: state, kennzahlen: filedKennzahlen(item), flags: flags,
                               isTest: item.configuration.testMode, sentAt: sentAt)
        filing.ticket = outcome.ticket
        filing.requestXML = xml
        filing.serverResponse = result.serverAnswer.isEmpty ? nil : result.serverAnswer
        switch outcome {
        case .rejected(let code, let text, _):
            filing.errorCode = code
            filing.errorText = text
        case .uncertain(_, let code, let text):
            filing.errorCode = String(code)
            filing.errorText = text
        default: break
        }
        if let pdf = result.pdf, let documents = app.storage?.documents {
            let path = VatFiling.protocolPath(itemID: item.id, year: item.year, sentAt: sentAt,
                                              isTest: item.configuration.testMode)
            do {
                filing.protocolSha256 = try documents.put(path, data: pdf).sha256
                filing.protocolPath = path
            } catch {
                log.error("Storing the protocol of \(item.id, privacy: .public) failed: \(error.localizedDescription, privacy: .public)")
                saveError = error.localizedDescription
            }
        }
        context.insert(filing)
        do {
            try context.save()
        } catch {
            log.error("Saving the filing of \(item.id, privacy: .public) failed: \(error.localizedDescription, privacy: .public)")
            saveError = error.localizedDescription
        }
        return filing.uid
    }

    /// The Kennzahlen `item` files: the period's for a UStVA, Kz38 for the Sondervorauszahlung.
    func filedKennzahlen(_ item: VatReturnItem) -> [Kennzahl: Decimal] {
        switch item.type {
        case .ustva: return results[item.id]?.kennzahlen.values ?? [:]
        case .sondervorauszahlung: return item.sondervorauszahlung.map { [.kz38: $0] } ?? [:]
        case .dauerfristverlaengerung: return [:]
        }
    }

    /// The amount shown for `item` before sending: Kz83, or Kz38 for the Sondervorauszahlung.
    func mainAmount(_ item: VatReturnItem) -> (kennzahl: Kennzahl, amount: Decimal)? {
        switch item.type {
        case .ustva: return results[item.id].map { (.kz83, $0.kennzahlen.kz83) }
        case .sondervorauszahlung: return item.sondervorauszahlung.map { (.kz38, $0) }
        case .dauerfristverlaengerung: return nil
        }
    }

    // MARK: Filings

    /// Shows the protocol PDF of `filing`.
    func showProtocol(_ filing: VatFiling, item: VatReturnItem) async {
        guard let path = filing.protocolPath, let documents = app?.storage?.documents else { return }
        do {
            let data = try await documents.read(path)
            preview = PreviewDocument(title: String(localized: "Protocol: \(VatReturnTexts.titleString(item))"),
                                      filename: (path as NSString).lastPathComponent, data: data)
        } catch {
            failures[item.id] = String(localized: "The protocol couldn't be read: \(error.localizedDescription)")
        }
    }

    /// Records `item` as filed outside the app.
    func markFiledElsewhere(_ item: VatReturnItem, amount: Decimal?, filedOn: String?) {
        guard let context = app?.storage?.container.mainContext else { return }
        context.insert(VatFiling(filedElsewhere: item, amount: amount, filedOn: filedOn))
        save(context)
    }

    /// The returns of `year` past their due date with no production filing: what "Mark All Past Periods as Filed
    /// Elsewhere" marks.
    func pastUnfiledItems(year: Int) -> [VatReturnItem] {
        items.filter { $0.year == year && $0.dueDate < today && filingMark(for: $0) == nil }
    }

    /// Marks every past, unfiled return of `year` as filed elsewhere, without amounts.
    func markPastFiledElsewhere(year: Int) {
        guard let context = app?.storage?.container.mainContext else { return }
        let marked = pastUnfiledItems(year: year).map { item in
            let filing = VatFiling(filedElsewhere: item, amount: nil, filedOn: nil)
            context.insert(filing)
            return filing.uid
        }
        lastBulkMark = (year, marked)
        save(context)
    }

    /// Undoes the last bulk mark.
    func undoBulkMark() {
        guard let bulk = lastBulkMark, let context = app?.storage?.container.mainContext else { return }
        let uids = Set(bulk.uids)
        for filing in filings.values.joined() where uids.contains(filing.uid) { context.delete(filing) }
        lastBulkMark = nil
        save(context)
    }

    /// Removes a "filed elsewhere" record (undo). Sends are history and are never removed.
    func removeFiledElsewhere(_ filing: VatFiling) {
        guard filing.filingState == .filedElsewhere, let context = app?.storage?.container.mainContext else { return }
        context.delete(filing)
        save(context)
    }

    private func save(_ context: ModelContext) {
        do {
            try context.save()
        } catch {
            log.error("Saving filings failed: \(error.localizedDescription, privacy: .public)")
            app?.lastError = error.localizedDescription
        }
        if let app { reload(app) }
    }

    // MARK: Treatments

    /// Sets the VAT treatment of each record explicitly (through `RecordStore.update`), then refreshes.
    func confirm(_ choices: [(uid: String, treatment: VatTreatment)], app: AppModel) {
        guard let store = app.store else { return }
        var failed: [String] = []
        for choice in choices {
            guard let record = records[choice.uid] else { continue }
            do {
                try store.update(record.id, fields: ["vat_treatment": .text(choice.treatment.rawValue)])
            } catch {
                failed.append(error.localizedDescription)
            }
        }
        app.refresh()
        if let message = failed.first { app.lastError = message }
    }
}
#endif
