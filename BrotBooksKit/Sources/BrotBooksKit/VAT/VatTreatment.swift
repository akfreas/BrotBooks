import Foundation

/// How a record is treated for VAT, which decides its UStVA Kennzahlen and ZM lines. Stored as the raw value
/// in the app-local `vat_treatment` field of `Expense` and `Income`; region and VAT rows alone can't tell
/// these cases apart (an Irish SaaS invoice and an Irish goods invoice look the same).
///
/// The raw values are also the keys of the English option labels in the string catalog.
public enum VatTreatment: String, Sendable, Hashable, Codable, CaseIterable {
    // Income
    /// German VAT from `vat_rates`.
    case domestic
    /// EU B2B service, customer liable (§3a(2) UStG). ZM, Umsatzart S.
    case euB2BService
    /// Innergemeinschaftliche Lieferung. ZM, Umsatzart L.
    case euB2BGoods
    /// Ausfuhrlieferung (§4 Nr. 1a UStG).
    case exportGoods
    /// Service with its place of supply outside the EU.
    case nonEUService
    /// Not taxable (damages, private).
    case notTaxable

    // Expenses
    /// German input VAT from `vat_rates`.
    case domesticVat
    /// Reverse charge on a service from an EU supplier (e.g. Irish SaaS).
    case rcEUService
    /// Reverse charge on a service from a non-EU supplier (§13b(2) Nr. 1 UStG, e.g. US SaaS).
    case rcNonEUService
    /// Innergemeinschaftlicher Erwerb.
    case euGoodsAcquisition
    /// Einfuhrumsatzsteuer from a customs notice.
    case importVat
    /// No deductible VAT (insurance, small business supplier, foreign VAT charged).
    case noVat

    public var kind: Kind {
        switch self {
        case .domestic, .euB2BService, .euB2BGoods, .exportGoods, .nonEUService, .notTaxable: return .income
        case .domesticVat, .rcEUService, .rcNonEUService, .euGoodsAcquisition, .importVat, .noVat: return .expenses
        }
    }

    /// The treatments of one record kind, in editor order.
    public static func cases(for kind: Kind) -> [VatTreatment] {
        allCases.filter { $0.kind == kind }
    }

    /// The same case for goods instead of a service, or the other way around; nil when the treatment doesn't
    /// depend on that distinction.
    public var goodsServiceCounterpart: VatTreatment? {
        switch self {
        case .euB2BService: return .euB2BGoods
        case .euB2BGoods: return .euB2BService
        case .nonEUService: return .exportGoods
        case .exportGoods: return .nonEUService
        case .rcEUService: return .euGoodsAcquisition
        case .euGoodsAcquisition: return .rcEUService
        case .rcNonEUService: return .importVat
        case .importVat: return .rcNonEUService
        default: return nil
        }
    }

    /// A treatment derived from a record's other fields. It is never stored: it stays a suggestion until the
    /// user sets a treatment explicitly.
    public struct Suggestion: Sendable, Equatable {
        public var treatment: VatTreatment
        /// The goods-or-service alternative the user has to decide between; nil when the fields settle it.
        public var alternative: VatTreatment?

        public init(_ treatment: VatTreatment, alternative: VatTreatment? = nil) {
            self.treatment = treatment
            self.alternative = alternative
        }

        /// Goods vs. service can't be told from the fields, so confirming means choosing between the two.
        public var needsGoodsOrServiceChoice: Bool { alternative != nil }

        static func ambiguous(_ treatment: VatTreatment) -> Suggestion {
            Suggestion(treatment, alternative: treatment.goodsServiceCounterpart)
        }
    }

    /// Suggests a treatment from a record's values (`RecordSnapshot.values`, `LedgerRecord.values`).
    ///
    /// Expenses go by supplier region and VAT rows (rows with a non-zero amount): a German supplier is
    /// `domesticVat` with VAT and `noVat` without; a foreign supplier without VAT is reverse charge
    /// (`rcEUService` / `rcNonEUService`, with goods as the alternative), and with VAT it is `domesticVat` when
    /// every rate is a German rate on the record date (a foreign company charging German VAT) and `noVat`
    /// (foreign VAT) otherwise.
    ///
    /// Income goes by client region, VAT number and private-person flag: German VAT on the invoice or a German
    /// client is `domestic`; an EU business client (not flagged private, and flagged a business or with a VAT
    /// number) is `euB2BService` with goods as the alternative, an EU private client `domestic`; a client outside
    /// the EU is `nonEUService` with export as the alternative.
    ///
    /// VAT settlements with the tax office (`SortedMarkers`) suggest `noVat` / `notTaxable`.
    public static func suggest(_ kind: Kind, values: RecordValues, rates: VatRateTable = .germany) -> Suggestion {
        let rows = (values["vat_rates"]?.vatRates ?? []).filter { $0.amount != 0 }
        let date = values["date"]?.date ?? ""
        switch kind {
        case .expenses:
            if values["category"]?.text == SortedMarkers.vatPaymentCategory { return Suggestion(.noVat) }
            switch values["supplier_region"]?.text {
            case EditForm.regions[1], EditForm.regions[2]:
                if rows.isEmpty {
                    return .ambiguous(values["supplier_region"]?.text == EditForm.regions[1] ? .rcEUService : .rcNonEUService)
                }
                let german = rows.allSatisfy { rates.kind(of: $0.rate, on: date) != nil }
                return Suggestion(german ? .domesticVat : .noVat)
            default:
                return Suggestion(rows.isEmpty ? .noVat : .domesticVat)
            }
        case .income:
            if values["sale_type"]?.text == SortedMarkers.vatRefundSaleType { return Suggestion(.notTaxable) }
            if !rows.isEmpty { return Suggestion(.domestic) }
            let isPrivate = values["client_is_private_person"]?.bool
            let hasVatNumber = !(values["client_vat_number"]?.text ?? "").trimmingCharacters(in: .whitespaces).isEmpty
            switch values["client_region"]?.text {
            case EditForm.regions[1]:
                let isBusiness = isPrivate == false || (isPrivate == nil && hasVatNumber)
                return isBusiness ? .ambiguous(.euB2BService) : Suggestion(.domestic)
            case EditForm.regions[2]:
                return .ambiguous(.nonEUService)
            default:
                return Suggestion(.domestic)
            }
        }
    }

    /// Suggests a treatment for `record` from its current fields.
    public static func suggest(_ record: some LedgerRecord, rates: VatRateTable = .germany) -> Suggestion {
        suggest(type(of: record).kind, values: record.values, rates: rates)
    }
}

/// A record's VAT treatment: the one set explicitly (confirmed), or else the current suggestion (unconfirmed).
public struct VatTreatmentStatus: Sendable, Equatable {
    /// The treatment the user set, or the suggested one.
    public var treatment: VatTreatment
    /// True only when the user set the treatment explicitly (`vat_treatment` is stored).
    public var isConfirmed: Bool
    /// The suggestion while unconfirmed; nil once confirmed.
    public var suggestion: VatTreatment.Suggestion?

    /// The stored `vat_treatment` when it is a valid treatment for `kind`, else the suggestion from the other values.
    public static func of(_ kind: Kind, values: RecordValues, rates: VatRateTable = .germany) -> VatTreatmentStatus {
        if let stored = values["vat_treatment"]?.text.flatMap(VatTreatment.init(rawValue:)), stored.kind == kind {
            return VatTreatmentStatus(treatment: stored, isConfirmed: true, suggestion: nil)
        }
        let suggestion = VatTreatment.suggest(kind, values: values, rates: rates)
        return VatTreatmentStatus(treatment: suggestion.treatment, isConfirmed: false, suggestion: suggestion)
    }
}

extension LedgerRecord {
    public var vatTreatmentStatus: VatTreatmentStatus { VatTreatmentStatus.of(Self.kind, values: values) }
}

extension RecordSnapshot {
    public var vatTreatmentStatus: VatTreatmentStatus { VatTreatmentStatus.of(kind, values: values) }
}

/// The share of an expense's VAT that is deductible as input tax.
public enum DeductibleShare {
    /// `deductible_amount / converted_gross_amount`, clamped to 0…1; 1 (100 %) when no deductible amount is set
    /// or the gross is missing or zero.
    ///
    /// `deductible_amount` is a gross EUR amount (it defaults to the converted gross, and `Taxes` applies it as
    /// `net × deductible / gross`), so the share is taken against the gross; for records without VAT rows
    /// (reverse charge) gross and net are equal.
    public static func of(_ values: RecordValues) -> Decimal {
        guard let deductible = values["deductible_amount"]?.decimal,
              let gross = values["converted_gross_amount"]?.decimal, gross != 0 else { return 1 }
        return min(1, max(0, deductible / gross))
    }
}
