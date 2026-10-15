import Foundation

/// The German standard or reduced VAT rate.
public enum VatRateKind: String, Sendable, Hashable, Codable, CaseIterable {
    case standard, reduced
}

/// German VAT rates with validity ranges, so a record is taxed at the rate valid on its date.
public struct VatRateTable: Sendable, Equatable, Codable {
    public struct Entry: Sendable, Equatable, Codable {
        /// First day the rates apply, ISO `YYYY-MM-DD`.
        public var validFrom: String
        /// Last day the rates apply; nil while they are current.
        public var validTo: String?
        public var standard: Decimal
        public var reduced: Decimal

        public init(validFrom: String, validTo: String? = nil, standard: Decimal, reduced: Decimal) {
            self.validFrom = validFrom
            self.validTo = validTo
            self.standard = standard
            self.reduced = reduced
        }

        public func contains(_ date: String) -> Bool {
            date >= validFrom && (validTo.map { date <= $0 } ?? true)
        }

        public func rate(_ kind: VatRateKind) -> Decimal { kind == .standard ? standard : reduced }
    }

    public var entries: [Entry]

    public init(entries: [Entry]) { self.entries = entries }

    /// 19 % / 7 %, with the temporary 16 % / 5 % from July to December 2020.
    public static let germany = VatRateTable(entries: [
        Entry(validFrom: "2007-01-01", validTo: "2020-06-30", standard: 19, reduced: 7),
        Entry(validFrom: "2020-07-01", validTo: "2020-12-31", standard: 16, reduced: 5),
        Entry(validFrom: "2021-01-01", standard: 19, reduced: 7),
    ])

    /// The rates valid on the ISO `date`, or nil when the table doesn't cover it.
    public func entry(on date: String) -> Entry? {
        entries.last { $0.contains(date) }
    }

    /// The `kind` rate in percent valid on `date`.
    public func rate(_ kind: VatRateKind, on date: String) -> Decimal? {
        entry(on: date)?.rate(kind)
    }

    /// Whether `rate` is the standard or the reduced rate on `date`; nil for any other rate (0 %, foreign rates).
    public func kind(of rate: Decimal, on date: String) -> VatRateKind? {
        guard let entry = entry(on: date) else { return nil }
        if rate == entry.standard { return .standard }
        if rate == entry.reduced { return .reduced }
        return nil
    }

    /// The rate for VAT the recipient owes itself (reverse charge, EU acquisitions): the record's own non-zero
    /// rate row when it has one, otherwise the standard rate valid on `date`.
    public func selfAssessedRate(on date: String, rows: [VatRate]) -> Decimal? {
        rows.first { $0.rate > 0 }?.rate ?? rate(.standard, on: date)
    }
}
