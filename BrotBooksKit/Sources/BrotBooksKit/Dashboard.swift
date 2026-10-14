import Foundation

/// The dashboard's date window for a selected year (same rules as `web/app/page.tsx`).
/// The current year runs Jan 1 → today and compares with the same window last year;
/// past years compare the full year with the previous full year.
public struct DashboardWindow: Sendable, Equatable {
    public let year: Int
    public let partial: Bool
    public let start: String
    public let end: String
    public let previousStart: String
    public let previousEnd: String

    public init(year: Int, today: String) {
        let currentYear = ISODate.year(today) ?? year
        self.year = year
        partial = year == currentYear
        start = ISODate.make(year, 1, 1)
        end = partial ? today : ISODate.make(year, 12, 31)
        previousStart = ISODate.make(year - 1, 1, 1)
        previousEnd = DashboardWindow.previousYearDate(end)
    }

    /// Same calendar day one year earlier (Feb 29 → Feb 28).
    public static func previousYearDate(_ iso: String) -> String {
        guard let c = ISODate.components(iso) else { return iso }
        let day = c.month == 2 && c.day == 29 ? 28 : c.day
        return ISODate.make(c.year - 1, c.month, day)
    }

    /// Year picker options: years with data plus the current and selected year, newest first.
    public static func yearOptions(dataYears: [Int], currentYear: Int, selected: Int? = nil) -> [Int] {
        Set(dataYears + [currentYear] + (selected.map { [$0] } ?? [])).sorted(by: >)
    }
}

public enum DashboardMath {
    /// Percent change from previous to current, or nil when there is no baseline.
    public static func percentChange(current: Decimal, previous: Decimal) -> Decimal? {
        guard previous != 0 else { return nil }
        return (current - previous) / (previous < 0 ? -previous : previous) * 100
    }

    public struct ProfitPoint: Sendable, Equatable, Identifiable {
        public let month: Int
        /// First day of the month, ISO.
        public let date: String
        public let cumulative: Decimal
        public var id: Int { month }
    }

    /// Cumulative profit per month from January through the last month with data.
    public static func cumulativeProfit(year: Int, months: [SummaryRow]) -> [ProfitPoint] {
        var byMonth: [Int: Decimal] = [:]
        for row in months {
            guard let period = row.period, let c = ISODate.components(period), c.year == year else { continue }
            byMonth[c.month, default: 0] += row.profit
        }
        let lastMonth = byMonth.keys.max() ?? 1
        var running: Decimal = 0
        return (1...max(lastMonth, 1)).map { m in
            running += byMonth[m] ?? 0
            return ProfitPoint(month: m, date: ISODate.make(year, m, 1), cumulative: running)
        }
    }

    /// Up to two initials from the first two words (letters and digits only), or "·".
    public static func initials(_ text: String?) -> String {
        let cleaned = (text ?? "").unicodeScalars.map { CharacterSet.alphanumerics.contains($0) ? Character($0) : " " }
        let words = String(cleaned).split(whereSeparator: \.isWhitespace)
        let letters = words.prefix(2).compactMap { $0.first.map { String($0).uppercased() } }.joined()
        return letters.isEmpty ? "·" : letters
    }
}
