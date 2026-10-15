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
        case validating, previewing
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

    private let log = Logger(subsystem: "me.freas.BrotBooks", category: "VAT")

    var selectedItem: VatReturnItem? { items.first { $0.id == selection } }

    // MARK: Loading

    /// Recomputes everything from the store and the tax profile. Called on appear and whenever records or
    /// settings change.
    func reload(_ app: AppModel) {
        guard let store = app.store, let context = app.storage?.container.mainContext else { return }
        do {
            today = app.today
            let settings = try TaxProfile.load(in: context)
            var snapshots: [RecordSnapshot] = []
            for kind in Kind.allCases {
                snapshots += try store.snapshots(kind, includeRemoved: true, drafts: .include)
            }
            let records = snapshots.map(UStVARecord.init)
            let year = ISODate.year(today) ?? 2026
            let items = VatReturnSchedule.items(years: [year - 1, year], settings: settings)

            var results: [String: UStVAResult] = [:]
            var drafts: [String: [UStVAIssue]] = [:]
            for item in items {
                guard let period = item.period else { continue }
                results[item.id] = item.aggregate(records)
                drafts[item.id] = UStVAAggregator.draftIssues(records, period: period)
            }

            self.settings = settings
            self.items = items
            self.results = results
            self.draftIssues = drafts
            self.records = Dictionary(snapshots.map { ($0.uid, $0) }, uniquingKeysWith: { a, _ in a })
            review = VatTreatmentReview.entries(records, items: items) { [today] item in
                VatReturnStatus.of(item, today: today, filing: Self.filingMark(for: item)).isOpen
            }
            loadError = nil
        } catch {
            log.error("Loading VAT returns failed: \(error.localizedDescription, privacy: .public)")
            loadError = error.localizedDescription
        }
    }

    // MARK: Status

    /// How `item` was filed. Seam for filings: always nil until filings are recorded (`VatFiling`).
    static func filingMark(for item: VatReturnItem) -> VatFilingMark? { nil }

    func status(_ item: VatReturnItem) -> VatReturnStatus {
        VatReturnStatus.of(item, today: today, filing: Self.filingMark(for: item))
    }

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
