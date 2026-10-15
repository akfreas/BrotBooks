import Foundation

/// A rejected create or edit; the message is shown inline in the editor.
public struct ValidationError: Error, Equatable, LocalizedError, Sendable {
    public let message: String
    public init(_ message: String) { self.message = message }
    public var errorDescription: String? { message }
}

/// One problem with one field of a record that is not yet complete.
public struct RecordIssue: Sendable, Equatable, Hashable {
    public enum Code: String, Sendable {
        case missingDate, missingGrossAmount, missingConversionRate, vatInvalid, vatMismatch
    }

    public let field: String
    public let code: Code

    public init(field: String, code: Code) {
        self.field = field
        self.code = code
    }

    /// English message for the editor; the app may localize by `code`.
    public var message: String {
        switch code {
        case .missingDate: return "Enter the invoice date"
        case .missingGrossAmount: return "Enter the gross amount"
        case .missingConversionRate: return "Enter the conversion rate to EUR"
        case .vatInvalid: return "VAT rates must be between 0 and 100, with no amount at 0 %"
        case .vatMismatch: return "VAT doesn't add up to the gross amount"
        }
    }
}

/// Approval refused because the record is incomplete; `issues` carries the message for each field.
public struct ApprovalError: Error, Equatable, LocalizedError, Sendable {
    public let issues: [RecordIssue]

    public init(issues: [RecordIssue]) { self.issues = issues }

    /// The message for one field, for showing inline next to it.
    public func message(for field: String) -> String? { issues.first { $0.field == field }?.message }

    public var errorDescription: String? { issues.map(\.message).joined(separator: "\n") }
}

/// Raw input for one field, as the editor (or any caller) supplies it, before validation.
public enum FieldInput: Sendable, Equatable {
    case null
    case text(String)
    case bool(Bool)
    case vatRates([VatRowInput])
}

public struct VatRowInput: Sendable, Equatable, Hashable {
    public var rate: String
    public var amount: String

    public init(rate: String, amount: String) {
        self.rate = rate
        self.amount = amount
    }
}

/// Business rules for records: writable fields, validation and derived amounts.
public enum RecordRules {
    /// Writable fields are the CSV columns minus the document filename (documents are attached separately),
    /// plus the app-local fields.
    public static func writable(_ kind: Kind) -> [Column] {
        Columns.of(kind).filter { $0.name != "document_filename" } + localColumns(kind)
    }

    /// Fields stored and edited like columns but local to the app: never part of Sorted's CSV import or export.
    /// The header is only a label; there is no CSV column.
    public static func localColumns(_ kind: Kind) -> [Column] {
        [Column(header: "VAT treatment", name: "vat_treatment", type: .text)]
    }

    public static let required = ["date", "gross_amount"]

    public static func defaults(_ kind: Kind) -> RecordValues {
        switch kind {
        case .expenses:
            return ["currency": .text("EUR"), "vat_rates": .vatRates([])]
        case .income:
            return ["currency": .text("EUR"), "vat_rates": .vatRates([]), "sale_type": .text("Service"),
                    "payment_status": .text("Unpaid")]
        }
    }

    /// (derived field, inputs that trigger a recompute on update), in dependency order.
    public static let derived: [(field: String, inputs: Set<String>)] = [
        ("converted_gross_amount", ["gross_amount", "currency", "currency_conversion_rate"]),
        ("total_vat_amount", ["vat_rates"]),
        ("net_amount", ["converted_gross_amount", "total_vat_amount"]),
        ("deductible_amount", ["converted_gross_amount"]),
    ]

    // MARK: Validation

    /// Validates field names and converts inputs to typed values. A `draft` may clear required fields.
    public static func coerce(_ kind: Kind, _ fields: [String: FieldInput], draft: Bool = false) throws -> RecordValues {
        let columns = Dictionary(uniqueKeysWithValues: writable(kind).map { ($0.name, $0) })
        let unknown = fields.keys.filter { columns[$0] == nil }.sorted()
        if !unknown.isEmpty {
            throw ValidationError("unknown \(kind.rawValue) fields: \(unknown.joined(separator: ", "))")
        }
        var out = RecordValues()
        for (name, input) in fields {
            out[name] = try coerce(columns[name]!, input)
        }
        if let treatment = out["vat_treatment"]?.text, VatTreatment(rawValue: treatment)?.kind != kind {
            throw ValidationError("vat_treatment: not a \(kind.rawValue) treatment: '\(treatment)'")
        }
        for name in required where !draft && out[name] == .null {
            throw ValidationError("\(name) cannot be null")
        }
        return out
    }

    static func coerce(_ column: Column, _ input: FieldInput) throws -> FieldValue {
        if case .null = input { return .null }
        let name = column.name
        switch (column.type, input) {
        case (.decimal, .text(let s)):
            guard let d = Money.parse(s) else { throw ValidationError("\(name): not a number: '\(s)'") }
            return .decimal(d)
        case (.int, .text(let s)):
            guard let d = Money.parse(s), d == Money.rounded(d, scale: 0) else {
                throw ValidationError("\(name): not an integer: '\(s)'")
            }
            return .int(NSDecimalNumber(decimal: d).intValue)
        case (.date, .text(let s)):
            guard ISODate.isValid(s) else { throw ValidationError("\(name): not an ISO date: '\(s)'") }
            return .date(s)
        case (.bool, .bool(let b)):
            return .bool(b)
        case (.vatRates, .vatRates(let rows)):
            return .vatRates(try rows.map { row in
                guard let rate = Money.parse(row.rate), let amount = Money.parse(row.amount) else {
                    throw ValidationError("vat_rates entries need a numeric rate and amount")
                }
                return VatRate(rate: rate, amount: amount)
            })
        case (.text, .text(let s)):
            return name == "currency" ? .text(s.trimmingCharacters(in: .whitespaces).uppercased()) : .text(s)
        case (.bool, _):
            throw ValidationError("\(name): not a boolean")
        case (.vatRates, _):
            throw ValidationError("vat_rates must be a list of {rate, amount}")
        default:
            throw ValidationError("\(name): invalid value")
        }
    }

    // MARK: Derived amounts

    /// A `draft` in a foreign currency may lack a rate; its EUR amounts stay empty until one is entered.
    static func compute(_ field: String, _ record: RecordValues, draft: Bool = false) throws -> FieldValue {
        switch field {
        case "converted_gross_amount":
            guard let gross = record["gross_amount"]?.decimal else { return .null }
            if record["currency"]?.text == "EUR" { return .decimal(gross) }
            guard let rate = record["currency_conversion_rate"]?.decimal else {
                if draft { return .null }
                throw ValidationError("non-EUR records need currency_conversion_rate or converted_gross_amount")
            }
            return .decimal(Money.rounded(gross * rate, mode: .bankers))
        case "total_vat_amount":
            let sum = (record["vat_rates"]?.vatRates ?? []).reduce(Decimal(0)) { $0 + $1.amount }
            return .decimal(Money.rounded(sum, mode: .bankers))
        case "net_amount":
            guard let converted = record["converted_gross_amount"]?.decimal else { return .null }
            return .decimal(converted - (record["total_vat_amount"]?.decimal ?? 0))
        case "deductible_amount":
            return record["converted_gross_amount"] ?? .null
        default:
            preconditionFailure("unknown derived field \(field)")
        }
    }

    /// Fills derived amount fields the caller didn't send. On create every unsent derived field is computed;
    /// on update only those whose inputs were sent or recomputed. Returns the set of fields changed.
    @discardableResult
    public static func deriveAmounts(_ kind: Kind, _ record: inout RecordValues, provided: Set<String>,
                                     creating: Bool, draft: Bool = false) throws -> Set<String> {
        var changed = provided
        let writableNames = Set(writable(kind).map(\.name))
        for (field, inputs) in derived {
            guard writableNames.contains(field), !provided.contains(field) else { continue }
            if creating || !inputs.isDisjoint(with: changed) {
                record[field] = try compute(field, record, draft: draft)
                changed.insert(field)
            }
        }
        return changed
    }

    /// Validated values for a new record: required fields, defaults and derived amounts.
    public static func prepareCreate(_ kind: Kind, _ fields: [String: FieldInput]) throws -> RecordValues {
        let values = try coerce(kind, fields)
        let missing = required.filter { values[$0] == nil }
        if !missing.isEmpty {
            throw ValidationError("missing required fields: \(missing.joined(separator: ", "))")
        }
        var record = defaults(kind).merging(values) { _, new in new }
        try deriveAmounts(kind, &record, provided: Set(values.keys), creating: true)
        return record
    }

    /// The fields to write for a partial update of `before` (sent fields plus recomputed dependents).
    /// A `draft` may be incomplete: required fields can be cleared and a foreign currency can lack a rate.
    public static func prepareUpdate(_ kind: Kind, before: RecordValues, _ fields: [String: FieldInput],
                                     draft: Bool = false) throws -> RecordValues {
        let values = try coerce(kind, fields, draft: draft)
        var merged = before.merging(values) { _, new in new }
        let changed = try deriveAmounts(kind, &merged, provided: Set(values.keys), creating: false, draft: draft)
        return merged.filter { changed.contains($0.key) }
    }

    // MARK: Final record

    /// Tolerance for VAT rows against the gross amount: one cent of rounding per row, plus a cent.
    static let vatTolerance = Decimal(string: "0.01")!

    /// What a draft still lacks before it can be approved as a final record: a date, a gross amount, a
    /// conversion rate for a foreign currency, and VAT rows that add up to the gross. Empty when it is complete.
    public static func finalIssues(_ kind: Kind, _ values: RecordValues) -> [RecordIssue] {
        var issues: [RecordIssue] = []
        if values["date"]?.date.map(ISODate.isValid) != true {
            issues.append(RecordIssue(field: "date", code: .missingDate))
        }
        if values["gross_amount"]?.decimal == nil {
            issues.append(RecordIssue(field: "gross_amount", code: .missingGrossAmount))
        }
        let currency = values["currency"]?.text ?? "EUR"
        if currency != "EUR", values["currency_conversion_rate"]?.decimal == nil,
           values["converted_gross_amount"]?.decimal == nil {
            issues.append(RecordIssue(field: "currency_conversion_rate", code: .missingConversionRate))
        }
        if let issue = vatIssue(values) { issues.append(issue) }
        return issues
    }

    /// VAT amounts are in EUR, so they are checked against the converted gross. A single rate must match
    /// gross × rate / (100 + rate); with several rates (or a 0 % row for untaxed parts) the gross implied by
    /// the taxed rows must not exceed the gross.
    static func vatIssue(_ values: RecordValues) -> RecordIssue? {
        let rows = values["vat_rates"]?.vatRates ?? []
        guard !rows.isEmpty else { return nil }
        if rows.contains(where: { $0.rate < 0 || $0.rate > 100 || ($0.rate == 0 && $0.amount != 0) }) {
            return RecordIssue(field: "vat_rates", code: .vatInvalid)
        }
        guard let gross = values["converted_gross_amount"]?.decimal else { return nil }
        let magnitude = { (d: Decimal) in d < 0 ? -d : d }
        let taxed = rows.filter { $0.rate > 0 }
        let totalVat = magnitude(rows.reduce(Decimal(0)) { $0 + $1.amount })
        if totalVat > magnitude(gross) + vatTolerance {
            return RecordIssue(field: "vat_rates", code: .vatMismatch)
        }
        if taxed.count == 1, taxed.count == rows.count, let row = taxed.first {
            let expected = gross * row.rate / (100 + row.rate)
            return magnitude(row.amount - expected) > vatTolerance * 2 ? RecordIssue(field: "vat_rates", code: .vatMismatch) : nil
        }
        // Each row's amount is rounded to a cent, which moves its implied gross by 0.01 × (100 + rate) / rate.
        var impliedGross = Decimal(0), tolerance = vatTolerance
        for row in taxed {
            impliedGross += magnitude(row.amount) * (100 + row.rate) / row.rate
            tolerance += vatTolerance * (100 + row.rate) / row.rate
        }
        return impliedGross > magnitude(gross) + tolerance ? RecordIssue(field: "vat_rates", code: .vatMismatch) : nil
    }

    /// Throws `ApprovalError` with every issue when `values` is not a complete final record.
    public static func validateFinal(_ kind: Kind, _ values: RecordValues) throws {
        let issues = finalIssues(kind, values)
        if !issues.isEmpty { throw ApprovalError(issues: issues) }
    }

    // MARK: Document naming

    static func filenamePart(_ text: String?, maxLength: Int = 120) -> String {
        var s = (text ?? "").replacingOccurrences(of: #"[\x00-\x1f/\\:]"#, with: " ", options: .regularExpression)
        s = s.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
        return String(s.prefix(maxLength)).trimmingCharacters(in: .whitespaces)
    }

    /// `<YYYY>/<date> <description> <ref>-<sha8>.pdf`, relative to `<kind>/` in the documents folder.
    public static func uploadFilename(date: String, description: String?, ref: String, sha256: String) -> String {
        let parts = [date, filenamePart(description), "\(ref)-\(sha256.prefix(8))"].filter { !$0.isEmpty }
        return "\(date.prefix(4))/\(parts.joined(separator: " ")).pdf"
    }
}
