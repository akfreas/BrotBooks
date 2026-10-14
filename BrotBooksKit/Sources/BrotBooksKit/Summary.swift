import Foundation

/// Sorted's markers for VAT settled with the tax office.
public enum SortedMarkers {
    public static let vatPaymentCategory = "ExpenseCategory - vat payment to tax office"
    public static let vatRefundSaleType = "SaleType - vat refund"
}

/// The amounts of one active record that reports need. Build these from the active (not removed) records.
public struct LedgerEntry: Sendable, Equatable {
    public var kind: Kind
    /// ISO `YYYY-MM-DD`.
    public var date: String
    public var convertedGross: Decimal?
    public var net: Decimal?
    public var vat: Decimal?
    public var deductible: Decimal?
    public var category: String?
    public var saleType: String?

    public init(kind: Kind, date: String, convertedGross: Decimal?, net: Decimal?, vat: Decimal?,
                deductible: Decimal? = nil, category: String? = nil, saleType: String? = nil) {
        self.kind = kind
        self.date = date
        self.convertedGross = convertedGross
        self.net = net
        self.vat = vat
        self.deductible = deductible
        self.category = category
        self.saleType = saleType
    }

    public init(kind: Kind, values: RecordValues) {
        self.init(kind: kind, date: values["date"]?.date ?? "",
                  convertedGross: values["converted_gross_amount"]?.decimal,
                  net: values["net_amount"]?.decimal, vat: values["total_vat_amount"]?.decimal,
                  deductible: values["deductible_amount"]?.decimal, category: values["category"]?.text,
                  saleType: values["sale_type"]?.text)
    }

    var isVatPayment: Bool { kind == .expenses && category == SortedMarkers.vatPaymentCategory }
    var isVatRefund: Bool { kind == .income && saleType == SortedMarkers.vatRefundSaleType }

    func within(_ from: String?, _ to: String?) -> Bool {
        (from.map { date >= $0 } ?? true) && (to.map { date <= $0 } ?? true)
    }
}

public enum GroupBy: String, Sendable, CaseIterable {
    case year, quarter, month

    /// First day of the period containing `date`.
    public func periodStart(_ date: String) -> String {
        guard let c = ISODate.components(date) else { return date }
        switch self {
        case .year: return ISODate.make(c.year, 1, 1)
        case .quarter: return ISODate.make(c.year, (c.month - 1) / 3 * 3 + 1, 1)
        case .month: return ISODate.make(c.year, c.month, 1)
        }
    }
}

public struct SummaryRow: Sendable, Equatable {
    public var period: String?
    public var incomeGross: Decimal = 0
    public var incomeNet: Decimal = 0
    public var incomeVat: Decimal = 0
    public var expensesGross: Decimal = 0
    public var expensesNet: Decimal = 0
    public var expensesVat: Decimal = 0
    public var expensesDeductible: Decimal = 0

    public init(period: String?) { self.period = period }

    /// Income net − expenses net.
    public var profit: Decimal { incomeNet - expensesNet }
    /// Income VAT − expenses VAT.
    public var vatBalance: Decimal { incomeVat - expensesVat }
}

public struct Summary: Sendable, Equatable {
    public var groupBy: GroupBy
    public var periods: [SummaryRow]
    public var totals: SummaryRow
}

public enum Reports {
    /// Income and expense totals per period.
    /// `excludeVatSettlements` leaves out VAT paid to / refunded by the tax office.
    public static func summary(_ entries: [LedgerEntry], from: String? = nil, to: String? = nil,
                               groupBy: GroupBy = .month, excludeVatSettlements: Bool = false) -> Summary {
        var rows: [String: SummaryRow] = [:]
        for e in entries where e.within(from, to) {
            if excludeVatSettlements && (e.isVatPayment || e.isVatRefund) { continue }
            let key = groupBy.periodStart(e.date)
            var row = rows[key] ?? SummaryRow(period: key)
            switch e.kind {
            case .income:
                row.incomeGross += e.convertedGross ?? 0
                row.incomeNet += e.net ?? 0
                row.incomeVat += e.vat ?? 0
            case .expenses:
                row.expensesGross += e.convertedGross ?? 0
                row.expensesNet += e.net ?? 0
                row.expensesVat += e.vat ?? 0
                row.expensesDeductible += e.deductible ?? 0
            }
            rows[key] = row
        }
        let periods = rows.values.sorted { ($0.period ?? "") < ($1.period ?? "") }
        var totals = SummaryRow(period: nil)
        for r in periods {
            totals.incomeGross += r.incomeGross
            totals.incomeNet += r.incomeNet
            totals.incomeVat += r.incomeVat
            totals.expensesGross += r.expensesGross
            totals.expensesNet += r.expensesNet
            totals.expensesVat += r.expensesVat
            totals.expensesDeductible += r.expensesDeductible
        }
        return Summary(groupBy: groupBy, periods: periods, totals: totals)
    }

    /// Years that have records, newest first.
    public static func years(_ entries: [LedgerEntry]) -> [Int] {
        Set(entries.compactMap { ISODate.year($0.date) }).sorted(by: >)
    }
}
