import Foundation

/// One UStVA (or ZM) period: a calendar month or quarter. `zeitraum` is the code the UStVA uses:
/// `01`–`12` for months and `41`–`44` for quarters.
public struct VatPeriod: Sendable, Hashable, Codable, Comparable, CustomStringConvertible {
    public enum Length: String, Sendable, Hashable, Codable {
        case month, quarter
    }

    public let year: Int
    public let length: Length
    /// Month 1–12, or quarter 1–4.
    public let index: Int

    public static func month(_ year: Int, _ month: Int) -> VatPeriod {
        precondition((1...12).contains(month), "month out of range")
        return VatPeriod(year: year, length: .month, index: month)
    }

    public static func quarter(_ year: Int, _ quarter: Int) -> VatPeriod {
        precondition((1...4).contains(quarter), "quarter out of range")
        return VatPeriod(year: year, length: .quarter, index: quarter)
    }

    private init(year: Int, length: Length, index: Int) {
        self.year = year
        self.length = length
        self.index = index
    }

    /// The period for a UStVA `Zeitraum` code ("01"–"12", "41"–"44"), or nil for any other code.
    public init?(year: Int, zeitraum: String) {
        guard zeitraum.count == 2, let n = Int(zeitraum) else { return nil }
        switch n {
        case 1...12: self.init(year: year, length: .month, index: n)
        case 41...44: self.init(year: year, length: .quarter, index: n - 40)
        default: return nil
        }
    }

    public var zeitraum: String {
        String(format: "%02d", length == .month ? index : 40 + index)
    }

    public var firstMonth: Int { length == .month ? index : (index - 1) * 3 + 1 }
    public var lastMonth: Int { length == .month ? index : index * 3 }

    /// First day, ISO `YYYY-MM-DD`.
    public var start: String { ISODate.make(year, firstMonth, 1) }
    /// Last day, ISO `YYYY-MM-DD`.
    public var end: String { ISODate.make(year, lastMonth, ISODate.daysIn(month: lastMonth, year: year)) }

    public func contains(_ date: String) -> Bool { date >= start && date <= end }

    /// The periods of `year` for a filing frequency, in order; none for annual-only filing.
    public static func periods(year: Int, frequency: FilingFrequency) -> [VatPeriod] {
        switch frequency {
        case .monthly: return (1...12).map { month(year, $0) }
        case .quarterly: return (1...4).map { quarter(year, $0) }
        case .none: return []
        }
    }

    /// The periods of `year` for a ZM frequency, in order.
    public static func periods(year: Int, frequency: ZMFrequency) -> [VatPeriod] {
        periods(year: year, frequency: frequency == .monthly ? FilingFrequency.monthly : .quarterly)
    }

    /// The period of `frequency` containing the ISO `date`; nil for an invalid date or annual-only filing.
    public static func containing(_ date: String, frequency: FilingFrequency) -> VatPeriod? {
        guard let c = ISODate.components(date) else { return nil }
        switch frequency {
        case .monthly: return month(c.year, c.month)
        case .quarterly: return quarter(c.year, (c.month - 1) / 3 + 1)
        case .none: return nil
        }
    }

    public static func < (a: VatPeriod, b: VatPeriod) -> Bool {
        (a.start, a.end) < (b.start, b.end)
    }

    public var description: String { "\(year)-\(zeitraum)" }
}

extension ISODate {
    /// `date` plus `days` (may be negative), or nil for an invalid date.
    public static func adding(days: Int, to date: String) -> String? {
        guard var (y, m, d) = components(date) else { return nil }
        d += days
        while d > daysIn(month: m, year: y) {
            d -= daysIn(month: m, year: y)
            (y, m) = m == 12 ? (y + 1, 1) : (y, m + 1)
        }
        while d < 1 {
            (y, m) = m == 1 ? (y - 1, 12) : (y, m - 1)
            d += daysIn(month: m, year: y)
        }
        return make(y, m, d)
    }

    /// `date` plus `months` (may be negative); the day is clamped to the end of a shorter month.
    public static func adding(months: Int, to date: String) -> String? {
        guard let (y, m, d) = components(date) else { return nil }
        let total = y * 12 + (m - 1) + months
        let year = Int((Double(total) / 12).rounded(.down)), month = total - year * 12 + 1
        return make(year, month, min(d, daysIn(month: month, year: year)))
    }
}
