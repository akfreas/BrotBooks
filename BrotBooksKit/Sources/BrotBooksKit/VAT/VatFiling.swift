import Foundation
import SwiftData

/// One filing of a return: a send through ELSTER (accepted, rejected or with an uncertain outcome) or a return
/// marked as filed elsewhere (Mein ELSTER, an accountant). Rejected attempts are kept as history; only accepted,
/// filed-elsewhere and uncertain filings affect a return's status (`VatFilings`).
///
/// CloudKit rules as in `Models.swift`: every property optional or defaulted, additive changes only, money as
/// decimal strings. iOS reads the history; only the Mac sends. The protocol PDF lives in the `DocumentStore`
/// (`protocolPath`), not in the record.
@Model
public final class VatFiling {
    public var uid: String = UUID().uuidString
    /// `VatFiling.Kind`: `ustva`, `sondervorauszahlung`, `dauerfristverlaengerung`.
    public var kind: String?
    /// The return's `VatReturnItem.id`, e.g. `2026-03` or `2026-sondervorauszahlung`.
    public var itemID: String?
    public var year: Int?
    /// The UStVA `Zeitraum` (`01`–`12`, `41`–`44`); nil for the yearly returns.
    public var zeitraum: String?
    /// The data type version sent, e.g. `UStVA_2026`.
    public var datenartVersion: String?
    /// JSON object of the Kennzahlen filed, number → decimal string, e.g. `{"81":"1000","83":"190.00"}`.
    public var kennzahlen: Data?
    /// Kz83 of a UStVA as a decimal string; nil for the yearly returns, and for a return filed elsewhere without
    /// an amount.
    public var kz83: String?
    /// `UStVAFlags.rawValue` sent (Kz10, Kz22, Kz26, Kz29).
    public var flags: Int?
    /// The ELSTER transfer ticket.
    public var ticket: String?
    /// When the return was sent or marked as filed.
    public var sentAt: Date?
    /// ISO `YYYY-MM-DD` the return was filed on (entered for a return filed elsewhere).
    public var filedOn: String?
    /// Sent with the test marker: never counts as filed.
    public var isTest: Bool = false
    /// Sent with Kz10 (corrected return).
    public var isCorrection: Bool = false
    /// `VatFiling.State`.
    public var state: String?
    /// The ELSTER server's answer XML.
    public var serverResponse: String?
    /// The XML that was sent.
    public var requestXML: String?
    /// The protocol PDF, relative to the `DocumentStore` root.
    public var protocolPath: String?
    public var protocolSha256: String?
    /// The server's or ERiC's error code, and its text.
    public var errorCode: String?
    public var errorText: String?
    public var createdAt: Date = Date()

    public enum Kind: String, Sendable, CaseIterable {
        case ustva, sondervorauszahlung, dauerfristverlaengerung
    }

    public enum State: String, Sendable, CaseIterable {
        /// The server accepted the return (code 0).
        case accepted
        /// The server rejected it.
        case rejected
        /// A timeout or connection error: it may have arrived. Check Mein ELSTER before sending again.
        case uncertain
        /// Filed outside the app.
        case filedElsewhere
    }

    public init() {}

    /// A filing of `item` with the Kennzahlen filed (for the Sondervorauszahlung, Kz38).
    public convenience init(item: VatReturnItem, state: State, kennzahlen: [Kennzahl: Decimal], flags: UStVAFlags,
                            isTest: Bool, sentAt: Date = Date()) {
        self.init()
        kind = item.filingKind.rawValue
        itemID = item.id
        year = item.year
        zeitraum = item.period?.zeitraum
        datenartVersion = item.datenartVersion
        self.kennzahlen = Self.encode(kennzahlen)
        kz83 = item.period != nil ? kennzahlen[.kz83].map(Money.plainString) : nil
        self.flags = flags.rawValue
        isCorrection = flags.contains(.correction)
        self.isTest = isTest
        self.state = state.rawValue
        self.sentAt = sentAt
        filedOn = ISODate.today(sentAt)
    }

    /// A return filed outside the app on the ISO `filedOn`, with its amount when known (Kz83 of a UStVA,
    /// Kz38 of the Sondervorauszahlung). Always a production filing.
    public convenience init(filedElsewhere item: VatReturnItem, amount: Decimal?, filedOn: String?,
                            sentAt: Date = Date()) {
        var kennzahlen: [Kennzahl: Decimal] = [:]
        if let amount {
            switch item.type {
            case .ustva: kennzahlen[.kz83] = amount
            case .sondervorauszahlung: kennzahlen[.kz38] = amount
            case .dauerfristverlaengerung: break
            }
        }
        self.init(item: item, state: .filedElsewhere, kennzahlen: kennzahlen, flags: [], isTest: false, sentAt: sentAt)
        self.filedOn = filedOn
    }

    public var filingState: State? { state.flatMap(State.init(rawValue:)) }

    /// The Kennzahlen as stored; empty when unreadable.
    public var filedKennzahlen: [Kennzahl: Decimal] { Self.decode(kennzahlen) }

    /// The filing as a value, for `VatFilings`.
    public var entry: VatFilingEntry {
        VatFilingEntry(uid: uid, itemID: itemID ?? "", state: filingState, isTest: isTest, isCorrection: isCorrection,
                       kennzahlen: filedKennzahlen, kz83: kz83.flatMap(Money.parse), date: sentAt ?? createdAt,
                       ticket: ticket)
    }

    static func encode(_ kennzahlen: [Kennzahl: Decimal]) -> Data? {
        let object = Dictionary(uniqueKeysWithValues: kennzahlen.map { (String($0.key.rawValue), Money.plainString($0.value)) })
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        return try? encoder.encode(object)
    }

    static func decode(_ data: Data?) -> [Kennzahl: Decimal] {
        guard let data, let object = try? JSONDecoder().decode([String: String].self, from: data) else { return [:] }
        var result: [Kennzahl: Decimal] = [:]
        for (key, value) in object {
            if let number = Int(key), let kz = Kennzahl(rawValue: number), let amount = Money.parse(value) {
                result[kz] = amount
            }
        }
        return result
    }

    /// The filings of `itemID`, oldest first.
    public static func all(for itemID: String, in context: ModelContext) throws -> [VatFiling] {
        try context.fetch(FetchDescriptor<VatFiling>(predicate: #Predicate { $0.itemID == itemID }))
            .sorted { ($0.sentAt ?? $0.createdAt) < ($1.sentAt ?? $1.createdAt) }
    }

    /// Where the protocol PDF of a filing goes in the `DocumentStore`:
    /// `tax-reports/elster/<year>/<item id> <timestamp>[ test].pdf`.
    public static func protocolPath(itemID: String, year: Int, sentAt: Date, isTest: Bool) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyyMMdd'T'HHmmss'Z'"
        return "tax-reports/elster/\(year)/\(itemID) \(formatter.string(from: sentAt))\(isTest ? " test" : "").pdf"
    }
}

extension VatReturnItem {
    /// The kind of filing this return produces.
    public var filingKind: VatFiling.Kind {
        switch type {
        case .ustva: return .ustva
        case .sondervorauszahlung: return .sondervorauszahlung
        case .dauerfristverlaengerung: return .dauerfristverlaengerung
        }
    }
}

/// A filing as a value (see `VatFiling.entry`).
public struct VatFilingEntry: Sendable, Equatable, Identifiable {
    public var uid: String
    public var itemID: String
    public var state: VatFiling.State?
    public var isTest: Bool
    public var isCorrection: Bool
    public var kennzahlen: [Kennzahl: Decimal]
    public var kz83: Decimal?
    public var date: Date
    public var ticket: String?

    public var id: String { uid }

    public init(uid: String = UUID().uuidString, itemID: String, state: VatFiling.State?, isTest: Bool = false,
                isCorrection: Bool = false, kennzahlen: [Kennzahl: Decimal] = [:], kz83: Decimal? = nil,
                date: Date = Date(), ticket: String? = nil) {
        self.uid = uid
        self.itemID = itemID
        self.state = state
        self.isTest = isTest
        self.isCorrection = isCorrection
        self.kennzahlen = kennzahlen
        self.kz83 = kz83 ?? kennzahlen[.kz83]
        self.date = date
        self.ticket = ticket
    }

    /// Counts as filed for production: accepted without the test marker, or filed elsewhere.
    public var isProductionFiled: Bool {
        !isTest && (state == .accepted || state == .filedElsewhere)
    }

    /// The return's main amount: Kz83 of a UStVA, else Kz38 of the Sondervorauszahlung.
    public var amount: Decimal? { kz83 ?? kennzahlen[.kz38] }
}

/// A return's filings, read for its status, the send rules and the Sondervorauszahlung.
public struct VatFilings: Sendable, Equatable {
    /// One return's filings, oldest first.
    public var entries: [VatFilingEntry]

    public init(_ entries: [VatFilingEntry]) {
        self.entries = entries.sorted { $0.date < $1.date }
    }

    /// The production status: an accepted filing wins, then one filed elsewhere, then an uncertain one. Test
    /// filings and rejected attempts never count.
    public var mark: VatFilingMark? {
        let production = entries.filter { !$0.isTest }
        if production.contains(where: { $0.state == .accepted }) { return .production }
        if production.contains(where: { $0.state == .filedElsewhere }) { return .elsewhere }
        if production.contains(where: { $0.state == .uncertain }) { return .uncertain }
        return nil
    }

    /// The return was accepted with the test marker (shown next to the production status, which stays visible).
    public var filedInTest: Bool { entries.contains { $0.isTest && $0.state == .accepted } }

    /// Sending again must be a corrected return (Kz10): the return was accepted for production or filed
    /// elsewhere, so a second plain return for the period would be a duplicate filing.
    public var requiresCorrection: Bool { entries.contains(where: \.isProductionFiled) }

    /// The latest send in this mode (test or production) has an uncertain outcome and nothing was accepted after
    /// it: sending again needs the user's explicit "I checked Mein ELSTER" confirmation.
    public func needsResendConfirmation(isTest: Bool) -> Bool {
        let mode = entries.filter { $0.isTest == isTest }
        guard let lastUncertain = mode.lastIndex(where: { $0.state == .uncertain }) else { return false }
        return !mode[(lastUncertain + 1)...].contains { $0.state == .accepted || $0.state == .filedElsewhere }
    }

    /// The latest production filing that counts as filed (accepted, else filed elsewhere): the one whose amount
    /// stands for the return. A later correction replaces an earlier filing.
    public var counted: VatFilingEntry? {
        entries.last { $0.isProductionFiled && $0.state == .accepted }
            ?? entries.last { $0.isProductionFiled }
    }
}

/// The prior year's advance payments, from its filings, for the Sondervorauszahlung of `year`: the sum of the
/// prior year's Kz83 plus its Sondervorauszahlung (Kz38), each from the latest production filing of that return
/// (accepted or filed elsewhere; test filings never count).
public struct SondervorauszahlungBasis: Sendable, Equatable {
    /// The year whose Sondervorauszahlung this is; the filings are of `year - 1`.
    public var year: Int
    public var kz83Total: Decimal
    /// The prior year's Sondervorauszahlung (0 when it had none).
    public var priorSondervorauszahlung: Decimal
    /// The prior year's returns missing from the total: not filed, or filed elsewhere without an amount. The
    /// computed amount is incomplete while this is not empty.
    public var missing: [VatReturnItem.ReturnType]

    public init(year: Int, kz83Total: Decimal, priorSondervorauszahlung: Decimal, missing: [VatReturnItem.ReturnType]) {
        self.year = year
        self.kz83Total = kz83Total
        self.priorSondervorauszahlung = priorSondervorauszahlung
        self.missing = missing
    }

    /// The Sondervorauszahlung for `settings`: its override when one is entered, else 1/11 of the advance payments.
    public func amount(settings: TaxSettingsPeriod) -> Decimal {
        Sondervorauszahlung.amount(priorYearKz83Total: kz83Total, priorYearSondervorauszahlung: priorSondervorauszahlung,
                                   settings: settings)
    }

    /// The basis for `year` from the filings of the prior year's returns (`priorYearItems`: its UStVA periods and
    /// its Sondervorauszahlung, from `VatReturnSchedule`). Nil when none of them has a counted filing: then
    /// nothing is known about the prior year and the amount must be entered.
    public static func compute(year: Int, priorYearItems: [VatReturnItem], filings: [VatFilingEntry])
        -> SondervorauszahlungBasis? {
        let byItem = Dictionary(grouping: filings, by: \.itemID).mapValues(VatFilings.init)
        var total: Decimal = 0
        var prior: Decimal = 0
        var missing: [VatReturnItem.ReturnType] = []
        var counted = 0
        for item in priorYearItems.sorted(by: { ($0.fileableFrom, $0.id) < ($1.fileableFrom, $1.id) }) {
            switch item.type {
            case .dauerfristverlaengerung: continue
            case .ustva, .sondervorauszahlung: break
            }
            guard let filing = byItem[item.id]?.counted else {
                missing.append(item.type)
                continue
            }
            counted += 1
            let amount: Decimal?
            if case .sondervorauszahlung = item.type { amount = filing.kennzahlen[.kz38] } else { amount = filing.kz83 }
            guard let amount else {
                missing.append(item.type)
                continue
            }
            if case .sondervorauszahlung = item.type { prior += amount } else { total += amount }
        }
        guard counted > 0 else { return nil }
        return SondervorauszahlungBasis(year: year, kz83Total: total, priorSondervorauszahlung: prior, missing: missing)
    }
}

extension VatReturnSchedule {
    /// `items(years:settings:)` with the computed Sondervorauszahlung of each year from the prior year's
    /// `filings` (`SondervorauszahlungBasis`) set on its Sondervorauszahlung and December returns.
    public static func items(years: [Int], settings: TaxSettings, filings: [VatFilingEntry]) -> [VatReturnItem] {
        var items = items(years: years, settings: settings)
        for year in Set(items.map(\.year)) {
            let prior = Self.items(years: [year - 1], settings: settings)
            guard let basis = SondervorauszahlungBasis.compute(year: year, priorYearItems: prior, filings: filings) else {
                continue
            }
            for index in items.indices where items[index].year == year {
                items[index].sondervorauszahlungBasis = basis
            }
        }
        return items
    }
}
