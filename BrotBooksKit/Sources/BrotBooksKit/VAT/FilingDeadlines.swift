import Foundation

/// Due dates of the UStVA, the ZM and the Sondervorauszahlung, as a table of offsets so that a legal change
/// is a data change. Each rule applies to periods ending on or after its `validFrom`.
///
/// The dates are the statutory ones; a due date on a weekend or public holiday is not moved to the next
/// working day here.
public struct FilingDeadlines: Sendable, Equatable, Codable {
    public struct Rule: Sendable, Equatable, Codable {
        /// ISO `YYYY-MM-DD`; the rule applies to periods ending on or after it.
        public var validFrom: String
        /// UStVA: days after the period end.
        public var ustvaDaysAfterPeriodEnd: Int
        /// UStVA: months added with a Dauerfristverlängerung.
        public var ustvaExtensionMonths: Int
        /// ZM: this day of the month after the period. Not moved by the Dauerfristverlängerung.
        public var zmDayOfFollowingMonth: Int
        /// Sondervorauszahlung: due on this month and day of the year it applies to.
        public var sondervorauszahlungMonth: Int
        public var sondervorauszahlungDay: Int

        public init(validFrom: String, ustvaDaysAfterPeriodEnd: Int, ustvaExtensionMonths: Int,
                    zmDayOfFollowingMonth: Int, sondervorauszahlungMonth: Int, sondervorauszahlungDay: Int) {
            self.validFrom = validFrom
            self.ustvaDaysAfterPeriodEnd = ustvaDaysAfterPeriodEnd
            self.ustvaExtensionMonths = ustvaExtensionMonths
            self.zmDayOfFollowingMonth = zmDayOfFollowingMonth
            self.sondervorauszahlungMonth = sondervorauszahlungMonth
            self.sondervorauszahlungDay = sondervorauszahlungDay
        }
    }

    public var rules: [Rule]

    public init(rules: [Rule]) { self.rules = rules.sorted { $0.validFrom < $1.validFrom } }

    /// §18 UStG / §§46–48 UStDV: UStVA 10 days after the period (+1 month with Dauerfristverlängerung),
    /// ZM on the 25th after the period, Sondervorauszahlung by 10 February.
    public static let germany = FilingDeadlines(rules: [
        Rule(validFrom: "2010-01-01", ustvaDaysAfterPeriodEnd: 10, ustvaExtensionMonths: 1,
             zmDayOfFollowingMonth: 25, sondervorauszahlungMonth: 2, sondervorauszahlungDay: 10),
    ])

    /// The rule for a period ending on `date`; the earliest rule when the date precedes them all.
    public func rule(on date: String) -> Rule {
        rules.last { $0.validFrom <= date } ?? rules[0]
    }

    /// UStVA due date: the period end plus the day offset, then plus the extension months with a Dauerfristverlängerung.
    public func ustvaDueDate(_ period: VatPeriod, dauerfristverlaengerung: Bool) -> String {
        let rule = rule(on: period.end)
        let base = ISODate.adding(days: rule.ustvaDaysAfterPeriodEnd, to: period.end)!
        return dauerfristverlaengerung ? ISODate.adding(months: rule.ustvaExtensionMonths, to: base)! : base
    }

    /// UStVA due date under `configuration` (its Dauerfristverlängerung setting).
    public func ustvaDueDate(_ period: VatPeriod, configuration: TaxConfiguration) -> String {
        ustvaDueDate(period, dauerfristverlaengerung: configuration.dauerfristverlaengerung)
    }

    /// ZM due date: the configured day of the month after the period end.
    public func zmDueDate(_ period: VatPeriod) -> String {
        let rule = rule(on: period.end)
        let next = ISODate.adding(months: 1, to: ISODate.make(period.year, period.lastMonth, 1))!
        let c = ISODate.components(next)!
        return ISODate.make(c.year, c.month, min(rule.zmDayOfFollowingMonth, ISODate.daysIn(month: c.month, year: c.year)))
    }

    /// Sondervorauszahlung due date for `year` (10 February of that year).
    public func sondervorauszahlungDueDate(year: Int) -> String {
        let rule = rule(on: ISODate.make(year, 1, 1))
        return ISODate.make(year, rule.sondervorauszahlungMonth, rule.sondervorauszahlungDay)
    }

    /// The Sondervorauszahlung due date for `year` under `configuration`, or nil when none is owed
    /// (no Dauerfristverlängerung, or not filing monthly).
    public func sondervorauszahlungDueDate(year: Int, configuration: TaxConfiguration) -> String? {
        configuration.requiresSondervorauszahlung ? sondervorauszahlungDueDate(year: year) : nil
    }
}

extension VatPeriod {
    /// The UStVA due date under `configuration` (its deadline table and Dauerfristverlängerung).
    public func ustvaDueDate(_ configuration: TaxConfiguration) -> String {
        configuration.deadlines.ustvaDueDate(self, configuration: configuration)
    }

    /// The ZM due date under `configuration`'s deadline table.
    public func zmDueDate(_ configuration: TaxConfiguration) -> String {
        configuration.deadlines.zmDueDate(self)
    }
}
