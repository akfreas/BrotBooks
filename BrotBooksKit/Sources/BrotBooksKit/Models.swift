import Foundation
import SwiftData

// CloudKit-backed SwiftData rules: every property optional or defaulted, no unique constraints,
// no required relationships. Money and other numeric(12,x) amounts are stored as exact decimal
// strings ("71.40", "0.973300") because CloudKit has no decimal type and Double is lossy;
// strings keep the scale and any precision (conversion rates use six decimals). Dates are ISO
// "YYYY-MM-DD" strings: they are calendar dates without a time zone, and sort lexicographically.
// Schema evolution: only add new optional/defaulted properties; never rename or delete a synced
// property or change its type (CloudKit production schemas are additive-only).

/// Shared shape of `Expense` and `Income`, so import, edit and reports work on either.
public protocol LedgerRecord: PersistentModel {
    static var kind: Kind { get }

    var uid: String { get set }
    var sortedRef: String? { get set }
    var descriptionText: String? { get set }
    var date: String { get set }
    var grossAmount: String? { get set }
    var convertedGrossAmount: String? { get set }
    var netAmount: String? { get set }
    var totalVatAmount: String? { get set }
    var vatRates: String { get set }
    var currency: String { get set }
    var currencyConversionRate: String? { get set }
    var documentFilename: String? { get set }
    var documentPath: String? { get set }
    var documentSha256: String? { get set }
    var sourceRow: Data? { get set }
    var importedFrom: String? { get set }
    var createdAt: Date { get set }
    var updatedAt: Date { get set }
    var removedAt: Date? { get set }

    /// Kind-specific columns.
    func specificValue(_ name: String) -> FieldValue?
    func setSpecificValue(_ value: FieldValue, for name: String) -> Bool
}

@Model
public final class Expense: LedgerRecord {
    public static let kind = Kind.expenses

    public var uid: String = UUID().uuidString
    /// Stable Sorted record key: the 5-hex suffix of the export document filename. Nil for records created here.
    public var sortedRef: String?
    public var descriptionText: String?
    public var date: String = ""
    public var grossAmount: String?
    public var convertedGrossAmount: String?
    public var netAmount: String?
    public var totalVatAmount: String?
    /// JSON `[{"rate":"19","amount":"11.4"}]` with decimal strings.
    public var vatRates: String = "[]"
    public var currency: String = "EUR"
    public var currencyConversionRate: String?
    public var documentFilename: String?
    public var documentPath: String?
    public var documentSha256: String?
    public var category: String?
    public var supplierRegion: String?
    public var deductibleAmount: String?
    public var assetLifetimeYears: Int?
    public var privateCarUsageType: String?
    public var privateCarDistanceDriven: String?
    public var privateCarDaysDrivenToWork: Int?
    public var expenseFlatRateStartDate: String?
    public var expenseFlatRateEndDate: String?
    public var businessTripCountry: String?
    public var isHomeOffice: Bool?
    /// The original CSV row (header → string) as JSON.
    public var sourceRow: Data?
    public var importedFrom: String?
    public var createdAt: Date = Date()
    public var updatedAt: Date = Date()
    public var removedAt: Date?
    /// `"draft"` for an unapproved expense (e.g. an imported invoice); nil once approved, and for every
    /// older record. Not a CSV column: drafts are local only and never part of the Sorted import or export.
    public var reviewStatus: String?
    /// `ExtractionInfo` JSON while the expense is a draft; nil otherwise.
    public var extraction: Data?

    public static let draftStatus = "draft"

    public init() {}

    public func specificValue(_ name: String) -> FieldValue? {
        switch name {
        case "category": return .optionalText(category)
        case "supplier_region": return .optionalText(supplierRegion)
        case "deductible_amount": return .storedDecimal(deductibleAmount)
        case "asset_lifetime_years": return assetLifetimeYears.map(FieldValue.int) ?? .null
        case "private_car_usage_type": return .optionalText(privateCarUsageType)
        case "private_car_distance_driven": return .storedDecimal(privateCarDistanceDriven)
        case "private_car_days_driven_to_work": return privateCarDaysDrivenToWork.map(FieldValue.int) ?? .null
        case "expense_flat_rate_start_date": return .optionalDate(expenseFlatRateStartDate)
        case "expense_flat_rate_end_date": return .optionalDate(expenseFlatRateEndDate)
        case "business_trip_country": return .optionalText(businessTripCountry)
        case "is_home_office": return isHomeOffice.map(FieldValue.bool) ?? .null
        default: return nil
        }
    }

    public func setSpecificValue(_ value: FieldValue, for name: String) -> Bool {
        switch name {
        case "category": category = value.text
        case "supplier_region": supplierRegion = value.text
        case "deductible_amount": deductibleAmount = Money.store(value.decimal)
        case "asset_lifetime_years": assetLifetimeYears = value.int
        case "private_car_usage_type": privateCarUsageType = value.text
        case "private_car_distance_driven": privateCarDistanceDriven = Money.store(value.decimal)
        case "private_car_days_driven_to_work": privateCarDaysDrivenToWork = value.int
        case "expense_flat_rate_start_date": expenseFlatRateStartDate = value.date
        case "expense_flat_rate_end_date": expenseFlatRateEndDate = value.date
        case "business_trip_country": businessTripCountry = value.text
        case "is_home_office": isHomeOffice = value.bool
        default: return false
        }
        return true
    }
}

@Model
public final class Income: LedgerRecord {
    public static let kind = Kind.income

    public var uid: String = UUID().uuidString
    public var sortedRef: String?
    public var descriptionText: String?
    public var date: String = ""
    public var grossAmount: String?
    public var convertedGrossAmount: String?
    public var netAmount: String?
    public var totalVatAmount: String?
    public var vatRates: String = "[]"
    public var currency: String = "EUR"
    public var currencyConversionRate: String?
    public var documentFilename: String?
    public var documentPath: String?
    public var documentSha256: String?
    public var clientRegion: String?
    public var clientVatNumber: String?
    public var clientIsPrivatePerson: Bool?
    public var saleType: String?
    public var paymentStatus: String?
    public var paymentDate: String?
    public var sourceRow: Data?
    public var importedFrom: String?
    public var createdAt: Date = Date()
    public var updatedAt: Date = Date()
    public var removedAt: Date?

    public init() {}

    public func specificValue(_ name: String) -> FieldValue? {
        switch name {
        case "client_region": return .optionalText(clientRegion)
        case "client_vat_number": return .optionalText(clientVatNumber)
        case "client_is_private_person": return clientIsPrivatePerson.map(FieldValue.bool) ?? .null
        case "sale_type": return .optionalText(saleType)
        case "payment_status": return .optionalText(paymentStatus)
        case "payment_date": return .optionalDate(paymentDate)
        default: return nil
        }
    }

    public func setSpecificValue(_ value: FieldValue, for name: String) -> Bool {
        switch name {
        case "client_region": clientRegion = value.text
        case "client_vat_number": clientVatNumber = value.text
        case "client_is_private_person": clientIsPrivatePerson = value.bool
        case "sale_type": saleType = value.text
        case "payment_status": paymentStatus = value.text
        case "payment_date": paymentDate = value.date
        default: return false
        }
        return true
    }
}

extension FieldValue {
    static func optionalText(_ s: String?) -> FieldValue { s.map(FieldValue.text) ?? .null }
    static func optionalDate(_ s: String?) -> FieldValue { s.map(FieldValue.date) ?? .null }
    static func storedDecimal(_ s: String?) -> FieldValue { s.flatMap(Money.parse).map(FieldValue.decimal) ?? .null }
}

extension LedgerRecord {
    public var kind: Kind { Self.kind }

    /// All CSV columns as typed values.
    public var values: RecordValues {
        var out = RecordValues()
        for column in Columns.of(Self.kind) { out[column.name] = value(column.name) }
        return out
    }

    public func value(_ name: String) -> FieldValue {
        switch name {
        case "description": return .optionalText(descriptionText)
        case "date": return date.isEmpty ? .null : .date(date)
        case "gross_amount": return .storedDecimal(grossAmount)
        case "converted_gross_amount": return .storedDecimal(convertedGrossAmount)
        case "net_amount": return .storedDecimal(netAmount)
        case "total_vat_amount": return .storedDecimal(totalVatAmount)
        case "vat_rates": return .vatRates(VatRates.decode(vatRates))
        case "currency": return .optionalText(currency)
        case "currency_conversion_rate": return .storedDecimal(currencyConversionRate)
        case "document_filename": return .optionalText(documentFilename)
        default: return specificValue(name) ?? .null
        }
    }

    public func setValue(_ value: FieldValue, for name: String) {
        switch name {
        case "description": descriptionText = value.text
        case "date": date = value.date ?? ""
        case "gross_amount": grossAmount = Money.store(value.decimal)
        case "converted_gross_amount": convertedGrossAmount = Money.store(value.decimal)
        case "net_amount": netAmount = Money.store(value.decimal)
        case "total_vat_amount": totalVatAmount = Money.store(value.decimal)
        case "vat_rates": vatRates = VatRates.encode(value.vatRates ?? [])
        case "currency": currency = value.text ?? "EUR"
        case "currency_conversion_rate": currencyConversionRate = Money.store(value.decimal)
        case "document_filename": documentFilename = value.text
        default:
            if !setSpecificValue(value, for: name) {
                assertionFailure("Unknown \(Self.kind.rawValue) field \(name)")
            }
        }
    }

    public func apply(_ values: RecordValues) {
        for (name, value) in values { setValue(value, for: name) }
    }

    public var decodedSourceRow: [String: String]? {
        sourceRow.flatMap { try? JSONDecoder().decode([String: String].self, from: $0) }
    }

    public var ledgerEntry: LedgerEntry { LedgerEntry(kind: Self.kind, values: values) }

    /// True for an unapproved draft expense; drafts don't count toward any total.
    public var isDraft: Bool { (self as? Expense)?.reviewStatus == Expense.draftStatus }

    /// `sorted_ref`, or a local reference for records created in the app (used in document names).
    public var reference: String { sortedRef ?? "L\(uid.prefix(6).lowercased())" }
}

public enum StoreSchema {
    public static let models: [any PersistentModel.Type] = [Expense.self, Income.self]
    public static var schema: Schema { Schema(models) }
}
