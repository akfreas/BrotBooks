import Foundation

/// One return on the VAT returns screen: a UStVA for a period, the yearly Sondervorauszahlung, or the
/// application for a Dauerfristverlängerung. Built by `VatReturnSchedule` from the configuration in force.
public struct VatReturnItem: Sendable, Equatable, Identifiable {
    public enum ReturnType: Sendable, Hashable {
        case ustva(VatPeriod)
        case sondervorauszahlung(year: Int)
        case dauerfristverlaengerung(year: Int)
    }

    public var type: ReturnType
    /// The configuration the return is filed under: the settings in force on the first day of its period
    /// (1 January for the yearly returns).
    public var configuration: TaxConfiguration
    /// ISO `YYYY-MM-DD`.
    public var dueDate: String
    /// The first day the return can be filed: the day after its period ends; 1 January for the yearly returns.
    public var fileableFrom: String

    public init(type: ReturnType, configuration: TaxConfiguration, dueDate: String, fileableFrom: String) {
        self.type = type
        self.configuration = configuration
        self.dueDate = dueDate
        self.fileableFrom = fileableFrom
    }

    /// Stable across reloads: `2026-03`, `2026-41`, `2026-sondervorauszahlung`, `2026-dauerfristverlaengerung`.
    public var id: String {
        switch type {
        case .ustva(let period): return period.description
        case .sondervorauszahlung(let year): return "\(year)-sondervorauszahlung"
        case .dauerfristverlaengerung(let year): return "\(year)-dauerfristverlaengerung"
        }
    }

    public var year: Int {
        switch type {
        case .ustva(let period): return period.year
        case .sondervorauszahlung(let year), .dauerfristverlaengerung(let year): return year
        }
    }

    public var period: VatPeriod? {
        if case .ustva(let period) = type { return period }
        return nil
    }

    /// The UStVA data type version ERiC validates the return as, e.g. `UStVA_2026`.
    public var datenartVersion: String { UStVAXML.datenartVersion(year: year) }

    /// The Sondervorauszahlung this return files (Kz38) or credits (Kz39 in December): the amount entered in the
    /// settings. Nil when the return has none, or when it needs one that isn't entered yet
    /// (`needsSondervorauszahlungAmount`); 1/11 of the prior year can't be computed until filings are recorded.
    public var sondervorauszahlung: Decimal? {
        usesSondervorauszahlung ? configuration.settings.sondervorauszahlungOverride : nil
    }

    /// The return needs a Sondervorauszahlung amount that isn't entered in the settings.
    public var needsSondervorauszahlungAmount: Bool {
        usesSondervorauszahlung && configuration.settings.sondervorauszahlungOverride == nil
    }

    private var usesSondervorauszahlung: Bool {
        switch type {
        case .sondervorauszahlung: return true
        case .ustva(let period):
            return configuration.requiresSondervorauszahlung && period.length == .month && period.lastMonth == 12
        case .dauerfristverlaengerung: return false
        }
    }

    /// The flags (Kz10, Kz22, Kz26, Kz29) this return can carry, in form order.
    public var availableFlags: [(flag: UStVAFlags, number: Int)] {
        let form = configuration.ustvaForms.form(for: year)
        switch type {
        case .ustva: return UStVAFlags.numbers.filter { form.elementOrder.contains($0.number) }
        case .sondervorauszahlung:
            return UStVAFlags.numbers.filter { form.sondervorauszahlungElementOrder.contains($0.number) }
        case .dauerfristverlaengerung: return []
        }
    }

    /// The return's XML, or nil while a needed Sondervorauszahlung amount is missing for the
    /// Sondervorauszahlung return. `result` is the period's aggregation (UStVA only).
    public func xml(result: UStVAResult?, flags: UStVAFlags, header: UStVAXML.Header) -> String? {
        switch type {
        case .ustva(let period):
            guard let result else { return nil }
            return UStVAXML.build(period: period, kennzahlen: result.kennzahlen, flags: flags,
                                  configuration: configuration, header: header)
        case .sondervorauszahlung(let year):
            guard let amount = sondervorauszahlung else { return nil }
            return UStVAXML.buildSondervorauszahlung(year: year, amount: amount, flags: flags,
                                                     configuration: configuration, header: header)
        case .dauerfristverlaengerung(let year):
            return UStVAXML.buildDauerfristverlaengerung(year: year, configuration: configuration, header: header)
        }
    }

    /// The period's aggregation of `records`, crediting the Sondervorauszahlung in December; nil for the yearly
    /// returns.
    public func aggregate(_ records: [UStVARecord]) -> UStVAResult? {
        guard let period else { return nil }
        return UStVAAggregator.aggregate(records, period: period, configuration: configuration,
                                         sondervorauszahlung: sondervorauszahlung)
    }
}

/// Whether a return was filed, as recorded by a filing (`VatFiling`). Filings are not recorded yet, so callers
/// pass nil.
public enum VatFilingMark: Sendable, Equatable {
    /// Sent with the ELSTER test marker.
    case test
    case production
}

/// Where a return stands on `today`.
public enum VatReturnStatus: Sendable, Equatable {
    /// Its period hasn't ended yet.
    case notDue
    /// Its period ended; due in `days` (0 = today).
    case dueIn(days: Int)
    /// Past its due date by `days`.
    case overdue(days: Int)
    /// Sent with the test marker only; it still counts as open.
    case filedTest
    case filed

    /// `item` on the ISO `today`. A production filing wins; a test filing shows as `filedTest`.
    public static func of(_ item: VatReturnItem, today: String, filing: VatFilingMark? = nil) -> VatReturnStatus {
        switch filing {
        case .production: return .filed
        case .test: return .filedTest
        case nil: break
        }
        if today < item.fileableFrom { return .notDue }
        let days = ISODate.days(from: today, to: item.dueDate) ?? 0
        return days >= 0 ? .dueIn(days: days) : .overdue(days: -days)
    }

    /// Not filed for real: test filings still count as open.
    public var isOpen: Bool { self != .filed }
}

/// The returns to show: per year, the UStVA periods of the configured frequency, plus the Sondervorauszahlung
/// (monthly filing with Dauerfristverlängerung) and the Dauerfristverlängerung application (quarterly filing
/// with Dauerfristverlängerung; monthly filers apply with the Sondervorauszahlung).
public enum VatReturnSchedule {
    /// The returns of `years` under `settings`, newest due date first.
    ///
    /// Each month uses the settings in force on its first day. A quarter is listed when the quarterly settings are
    /// in force on its first day; a month that falls into a quarter already listed is skipped, and a month in
    /// the middle of a quarter (quarterly settings starting mid-quarter) is listed as a month. Months before the
    /// first settings period and months with annual-only filing have no return.
    public static func items(years: [Int], settings: TaxSettings) -> [VatReturnItem] {
        var items: [VatReturnItem] = []
        for year in Set(years).sorted() {
            var covered: VatPeriod?
            var yearPeriods: [VatPeriod] = []
            for month in 1...12 {
                let start = ISODate.make(year, month, 1)
                if let covered, covered.contains(start) { continue }
                guard let configuration = settings.configuration(on: start),
                      let containing = VatPeriod.containing(start, frequency: configuration.ustvaFrequency) else { continue }
                let period = containing.start == start ? containing : VatPeriod.month(year, month)
                covered = period
                yearPeriods.append(period)
                guard let config = settings.configuration(for: period) else { continue }
                items.append(VatReturnItem(type: .ustva(period), configuration: config, dueDate: period.ustvaDueDate(config),
                                           fileableFrom: ISODate.adding(days: 1, to: period.end)!))
            }

            let january = ISODate.make(year, 1, 1)
            guard let configuration = settings.configuration(on: january) else { continue }
            if let due = configuration.deadlines.sondervorauszahlungDueDate(year: year, configuration: configuration) {
                items.append(VatReturnItem(type: .sondervorauszahlung(year: year), configuration: configuration,
                                           dueDate: due, fileableFrom: january))
            }
            if configuration.dauerfristverlaengerung, configuration.ustvaFrequency == .quarterly,
               let first = yearPeriods.first {
                // Due with the first return it extends, at that return's regular (unextended) due date.
                let due = configuration.deadlines.ustvaDueDate(first, dauerfristverlaengerung: false)
                items.append(VatReturnItem(type: .dauerfristverlaengerung(year: year), configuration: configuration,
                                           dueDate: due, fileableFrom: january))
            }
        }
        return items.sorted { ($0.dueDate, $0.id) > ($1.dueDate, $1.id) }
    }
}

/// The records whose VAT treatment is only suggested, in the open periods: the one-time review before filing.
public enum VatTreatmentReview {
    public struct Entry: Sendable, Equatable, Identifiable {
        public var recordUID: String
        public var kind: Kind
        /// The period the record counts toward.
        public var period: VatPeriod
        public var suggestion: VatTreatment.Suggestion

        public var id: String { recordUID }
    }

    /// Every record with an unconfirmed treatment that counts toward the UStVA of an item in `items` for which
    /// `isOpen` is true, in item order. Drafts and removed records are left out, as the aggregation leaves them
    /// out; confirmed records never appear.
    public static func entries(_ records: [UStVARecord], items: [VatReturnItem],
                               isOpen: (VatReturnItem) -> Bool = { _ in true }) -> [Entry] {
        let byUID = Dictionary(records.map { ($0.uid, $0) }, uniquingKeysWith: { first, _ in first })
        var seen: Set<String> = []
        var entries: [Entry] = []
        for item in items where isOpen(item) {
            guard let period = item.period, let result = item.aggregate(records) else { continue }
            for issue in result.issues where issue.code == .unconfirmedTreatment && !seen.contains(issue.recordUID) {
                guard let record = byUID[issue.recordUID] else { continue }
                let status = VatTreatmentStatus.of(record.kind, values: record.values,
                                                   rates: item.configuration.vatRates)
                guard let suggestion = status.suggestion else { continue }
                seen.insert(issue.recordUID)
                entries.append(Entry(recordUID: record.uid, kind: record.kind, period: period, suggestion: suggestion))
            }
        }
        return entries
    }
}

/// What a return needs from the tax profile before ERiC can validate or preview it.
public enum FilingRequirement: String, Sendable, Hashable, CaseIterable {
    case name, steuernummer, finanzamt
}

extension TaxIdentity {
    /// The filer details still missing for a return: the name, the 13-digit ELSTER Steuernummer and the 4-digit
    /// Finanzamt number.
    public var missingForFiling: [FilingRequirement] {
        var missing: [FilingRequirement] = []
        if name.trimmingCharacters(in: .whitespaces).isEmpty { missing.append(.name) }
        if steuernummer.wholeMatch(of: /[0-9]{13}/) == nil { missing.append(.steuernummer) }
        if finanzamt.wholeMatch(of: /[0-9]{4}/) == nil { missing.append(.finanzamt) }
        return missing
    }
}

extension UStVAXML {
    /// The Kennzahl number an ERiC `Feldidentifikator` points at (the last `Kz<nn>` step, e.g. 81 for
    /// `/Anmeldungssteuern[1]/Steuerfall[1]/Umsatzsteuervoranmeldung[1]/Kz81[1]`), or nil.
    public static func kennzahlNumber(feldidentifikator: String) -> Int? {
        feldidentifikator.matches(of: /Kz([0-9]{2})(?![0-9])/).last.flatMap { Int($0.output.1) }
    }

    /// The header for documents built `today` (ISO `YYYY-MM-DD`): `Erstellungsdatum` is `YYYYMMDD`.
    public static func header(herstellerID: String, produktVersion: String, today: String) -> Header {
        Header(herstellerID: herstellerID, produktVersion: produktVersion,
               erstellungsdatum: today.replacingOccurrences(of: "-", with: ""))
    }
}

extension ISODate {
    /// Days from `start` to `end` (negative when `end` is earlier), or nil for an invalid date.
    public static func days(from start: String, to end: String) -> Int? {
        guard let a = dayNumber(start), let b = dayNumber(end) else { return nil }
        return b - a
    }

    /// Days since 1970-01-01 (Howard Hinnant's `days_from_civil`).
    static func dayNumber(_ date: String) -> Int? {
        guard let (y0, m, d) = components(date) else { return nil }
        let y = m <= 2 ? y0 - 1 : y0
        let era = (y >= 0 ? y : y - 399) / 400
        let yoe = y - era * 400
        let doy = (153 * (m + (m > 2 ? -3 : 9)) + 2) / 5 + d - 1
        let doe = yoe * 365 + yoe / 4 - yoe / 100 + doy
        return era * 146097 + doe - 719468
    }
}

extension EditForm {
    /// The treatment the editor suggests while its "VAT treatment" select is empty: computed from the record's
    /// stored `values` (empty for a new record) with the form's edits since `initial` applied, so it follows what
    /// the user types. Nil once a treatment is selected. Edits that don't parse yet are ignored.
    public static func suggestedTreatment(_ kind: Kind, values: RecordValues, initial: State, current: State,
                                          rates: VatRateTable = .germany) -> VatTreatment.Suggestion? {
        guard (current.text["vat_treatment"] ?? "").isEmpty else { return nil }
        var merged = values
        var changes = changedFields(kind, initial: initial, current: current)
        changes["vat_treatment"] = nil
        if let updated = try? RecordRules.prepareUpdate(kind, before: values, changes, draft: true) {
            merged.merge(updated) { _, new in new }
        }
        merged["vat_treatment"] = nil
        return VatTreatment.suggest(kind, values: merged, rates: rates)
    }
}
