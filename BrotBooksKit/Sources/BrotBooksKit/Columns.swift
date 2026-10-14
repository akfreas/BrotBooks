import Foundation

/// Record kind; also the folder name in the export and in the documents container.
public enum Kind: String, Sendable, CaseIterable, Identifiable, Codable {
    case expenses
    case income

    public var id: String { rawValue }
}

public enum ColumnType: Sendable, Equatable {
    case text, decimal, int, date, bool, vatRates
}

/// One CSV column of Sorted's export and the record field it maps to.
public struct Column: Sendable, Equatable {
    public let header: String
    public let name: String
    public let type: ColumnType
}

public struct VatRate: Sendable, Equatable, Hashable, Codable {
    public var rate: Decimal
    public var amount: Decimal

    public init(rate: Decimal, amount: Decimal) {
        self.rate = rate
        self.amount = amount
    }
}

/// A typed field value. `.null` is an explicit "no value".
public enum FieldValue: Sendable, Equatable, Hashable {
    case null
    case text(String)
    case decimal(Decimal)
    case int(Int)
    /// ISO `YYYY-MM-DD`.
    case date(String)
    case bool(Bool)
    case vatRates([VatRate])

    public var text: String? { if case .text(let v) = self { v } else { nil } }
    public var decimal: Decimal? { if case .decimal(let v) = self { v } else { nil } }
    public var int: Int? { if case .int(let v) = self { v } else { nil } }
    public var date: String? { if case .date(let v) = self { v } else { nil } }
    public var bool: Bool? { if case .bool(let v) = self { v } else { nil } }
    public var vatRates: [VatRate]? { if case .vatRates(let v) = self { v } else { nil } }
    public var isNull: Bool { self == .null }
}

/// A record as a column-name → value map, the shape the business rules work on.
public typealias RecordValues = [String: FieldValue]

public struct ExportFormatError: Error, Equatable, LocalizedError, Sendable {
    public let message: String
    public init(_ message: String) { self.message = message }
    public var errorDescription: String? { message }
}

public enum Columns {
    public static let shared: [Column] = [
        Column(header: "Description", name: "description", type: .text),
        Column(header: "Date", name: "date", type: .date),
        Column(header: "Gross amount", name: "gross_amount", type: .decimal),
        Column(header: "Converted gross amount", name: "converted_gross_amount", type: .decimal),
        Column(header: "Net amount", name: "net_amount", type: .decimal),
        Column(header: "Total VAT amount", name: "total_vat_amount", type: .decimal),
        Column(header: "VAT rates", name: "vat_rates", type: .vatRates),
        Column(header: "Currency", name: "currency", type: .text),
        Column(header: "Currency conversion rate", name: "currency_conversion_rate", type: .decimal),
        Column(header: "Document filename", name: "document_filename", type: .text),
    ]

    public static let expenses: [Column] = shared + [
        Column(header: "Category", name: "category", type: .text),
        Column(header: "Supplier's region", name: "supplier_region", type: .text),
        Column(header: "Deductible amount", name: "deductible_amount", type: .decimal),
        Column(header: "Asset lifetime (years)", name: "asset_lifetime_years", type: .int),
        Column(header: "Private car - usage type", name: "private_car_usage_type", type: .text),
        Column(header: "Private car - distance driven", name: "private_car_distance_driven", type: .decimal),
        Column(header: "Private car - number of days driven to work", name: "private_car_days_driven_to_work", type: .int),
        Column(header: "Expense flat rate - start date", name: "expense_flat_rate_start_date", type: .date),
        Column(header: "Expense flat rate - end date", name: "expense_flat_rate_end_date", type: .date),
        Column(header: "Business trip country", name: "business_trip_country", type: .text),
        Column(header: "Is a home office", name: "is_home_office", type: .bool),
    ]

    public static let income: [Column] = shared + [
        Column(header: "Client's region", name: "client_region", type: .text),
        Column(header: "Client's VAT number", name: "client_vat_number", type: .text),
        Column(header: "Client is a private person (not a business)", name: "client_is_private_person", type: .bool),
        Column(header: "Sale type", name: "sale_type", type: .text),
        Column(header: "Payment status", name: "payment_status", type: .text),
        Column(header: "Payment date", name: "payment_date", type: .date),
    ]

    public static func of(_ kind: Kind) -> [Column] {
        kind == .expenses ? expenses : income
    }

    public static func headers(_ kind: Kind) -> [String] {
        of(kind).map(\.header)
    }

    public static func column(_ kind: Kind, named name: String) -> Column? {
        of(kind).first { $0.name == name }
    }

    // MARK: CSV parsing (export strings → values)

    public static func parse(_ text: String, as type: ColumnType) throws -> FieldValue {
        if type == .vatRates { return .vatRates(try VatRates.parse(text)) }
        if text.isEmpty { return .null }
        switch type {
        case .text:
            return .text(text)
        case .decimal:
            guard let d = Money.parse(text) else { throw ExportFormatError("Not a number: '\(text)'") }
            return .decimal(d)
        case .int:
            guard let i = Int(text) else { throw ExportFormatError("Not an integer: '\(text)'") }
            return .int(i)
        case .date:
            guard ISODate.isValid(text) else { throw ExportFormatError("Not an ISO date: '\(text)'") }
            return .date(text)
        case .bool:
            guard text == "True" || text == "False" else { throw ExportFormatError("Not a boolean: '\(text)'") }
            return .bool(text == "True")
        case .vatRates:
            fatalError("handled above")
        }
    }

    /// The 5-hex record suffix Sorted appends to document filenames, or nil.
    public static func sortedRef(fromFilename filename: String) -> String? {
        guard let match = filename.range(of: #" ([0-9a-f]{5})\.[A-Za-z0-9]+$"#, options: .regularExpression) else {
            return nil
        }
        let suffix = filename[match].dropFirst()
        return String(suffix.prefix(5))
    }

    /// One raw CSV row (header → string) as record values.
    public static func parseRow(_ kind: Kind, _ row: [String: String]) throws -> (values: RecordValues, sortedRef: String) {
        var values = RecordValues()
        for column in of(kind) {
            do {
                values[column.name] = try parse(row[column.header] ?? "", as: column.type)
            } catch let error as ExportFormatError {
                throw ExportFormatError("\(kind.rawValue): column '\(column.header)': \(error.message)")
            }
        }
        let filename = row["Document filename"] ?? ""
        guard let ref = sortedRef(fromFilename: filename) else {
            throw ExportFormatError("\(kind.rawValue): no record suffix in document filename '\(filename)'")
        }
        return (values, ref)
    }
}

/// Sorted's VAT rates text: "7%: 0 | 19%: 12.34".
public enum VatRates {
    public static func parse(_ text: String) throws -> [VatRate] {
        if text.trimmingCharacters(in: .whitespaces).isEmpty { return [] }
        return try text.split(separator: "|", omittingEmptySubsequences: false).map { part in
            let pattern = #"^\s*(-?[\d.]+)%:\s*(-?[\d.]+)\s*$"#
            let s = String(part)
            guard let regex = try? NSRegularExpression(pattern: pattern),
                  let m = regex.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)),
                  let r1 = Range(m.range(at: 1), in: s), let r2 = Range(m.range(at: 2), in: s),
                  let rate = Money.parse(String(s[r1])), let amount = Money.parse(String(s[r2]))
            else { throw ExportFormatError("Unrecognized VAT rates: '\(text)'") }
            return VatRate(rate: rate, amount: amount)
        }
    }

    public static func format(_ rates: [VatRate]) -> String {
        rates.map { "\(Money.plainString($0.rate))%: \(Money.plainString($0.amount))" }.joined(separator: " | ")
    }

    /// Storage form: compact JSON `[{"rate":"19","amount":"11.4"}]` with exact decimal strings.
    public static func encode(_ rates: [VatRate]) -> String {
        "[" + rates.map { #"{"rate":"\#(Money.plainString($0.rate))","amount":"\#(Money.plainString($0.amount))"}"# }
            .joined(separator: ",") + "]"
    }

    public static func decode(_ text: String?) -> [VatRate] {
        guard let text, let data = text.data(using: .utf8),
              let items = try? JSONDecoder().decode([[String: String]].self, from: data) else { return [] }
        return items.compactMap { item in
            guard let rate = item["rate"].flatMap(Money.parse), let amount = item["amount"].flatMap(Money.parse) else {
                return nil
            }
            return VatRate(rate: rate, amount: amount)
        }
    }
}

/// ISO `YYYY-MM-DD` helpers in the proleptic Gregorian calendar, independent of time zone.
public enum ISODate {
    public static func isValid(_ text: String) -> Bool {
        components(text) != nil
    }

    public static func components(_ text: String) -> (year: Int, month: Int, day: Int)? {
        let parts = text.split(separator: "-", omittingEmptySubsequences: false)
        guard text.count == 10, parts.count == 3, parts[0].count == 4, parts[1].count == 2, parts[2].count == 2,
              let y = Int(parts[0]), let m = Int(parts[1]), let d = Int(parts[2]),
              (1...12).contains(m), d >= 1, d <= daysIn(month: m, year: y) else { return nil }
        return (y, m, d)
    }

    public static func daysIn(month: Int, year: Int) -> Int {
        switch month {
        case 2: return (year % 4 == 0 && year % 100 != 0) || year % 400 == 0 ? 29 : 28
        case 4, 6, 9, 11: return 30
        default: return 31
        }
    }

    public static func make(_ year: Int, _ month: Int, _ day: Int) -> String {
        String(format: "%04d-%02d-%02d", year, month, day)
    }

    /// Today's date in the given time zone (local by default; UTC would be "yesterday" just after midnight in Germany).
    public static func today(_ now: Date = Date(), timeZone: TimeZone = .current) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let c = calendar.dateComponents([.year, .month, .day], from: now)
        return make(c.year!, c.month!, c.day!)
    }

    public static func year(_ text: String) -> Int? { components(text)?.year }
}
