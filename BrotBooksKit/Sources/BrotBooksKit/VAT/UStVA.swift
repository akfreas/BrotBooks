import Foundation

/// One record as the UStVA aggregation sees it: its values plus whether it is a draft or removed.
public struct UStVARecord: Sendable, Equatable {
    public var kind: Kind
    public var uid: String
    public var values: RecordValues
    public var isDraft: Bool
    public var isRemoved: Bool

    public init(kind: Kind, uid: String, values: RecordValues, isDraft: Bool = false, isRemoved: Bool = false) {
        self.kind = kind
        self.uid = uid
        self.values = values
        self.isDraft = isDraft
        self.isRemoved = isRemoved
    }

    public init(_ snapshot: RecordSnapshot) {
        self.init(kind: snapshot.kind, uid: snapshot.uid, values: snapshot.values, isDraft: snapshot.isDraft,
                  isRemoved: snapshot.removedAt != nil)
    }

    public init(_ record: some LedgerRecord) {
        self.init(kind: type(of: record).kind, uid: record.uid, values: record.values, isDraft: record.isDraft,
                  isRemoved: record.removedAt != nil)
    }
}

/// Something about a record in the period the user should look at. The aggregation never blocks by itself;
/// the UI decides which issues block sending (`blocksSending`).
public struct UStVAIssue: Sendable, Hashable {
    public enum Code: String, Sendable, Hashable, CaseIterable {
        /// The VAT treatment is only suggested; the record was aggregated with the suggestion.
        case unconfirmedTreatment
        /// Ist-Versteuerung: income invoiced in the period without a payment date; it is left out.
        case unpaidUnderIst
        /// No EUR amount (foreign currency without a conversion rate); the record is left out.
        case missingEURAmount
        /// German VAT treatment without VAT rows; nothing is reported for it.
        case missingVatRows
        /// EU B2B income without a customer VAT ID; its ZM line has an empty ID.
        case missingCustomerVatID
        /// The rate table has no rate for the record date; no self-assessed VAT is computed.
        case missingVatRate
        /// EU B2B income whose customer VAT ID doesn't look like an EU VAT ID outside Germany
        /// (`CustomerVatID.isPlausible`); it is still reported under that ID.
        case implausibleCustomerVatID
        /// A draft dated in the period. Drafts count toward nothing until approved; `aggregate` skips them and
        /// `UStVAAggregator.draftIssues` reports them.
        case draftInPeriod
    }

    public var code: Code
    public var recordUID: String
    public var kind: Kind

    public init(_ code: Code, recordUID: String, kind: Kind) {
        self.code = code
        self.recordUID = recordUID
        self.kind = kind
    }

    /// Unconfirmed treatments block sending; the other issues are warnings.
    public var blocksSending: Bool { code == .unconfirmedTreatment }
}

/// One ZM line: the EU B2B sales to one customer VAT ID of one Umsatzart.
public struct ZMLine: Sendable, Hashable {
    /// Normalized: uppercase, no spaces. Empty when the records have none (`missingCustomerVatID`).
    public var customerVatID: String
    public var umsatzart: ZMUmsatzart
    /// Net EUR, exact.
    public var amount: Decimal
    public var recordUIDs: [String]

    public init(customerVatID: String, umsatzart: ZMUmsatzart, amount: Decimal, recordUIDs: [String]) {
        self.customerVatID = customerVatID
        self.umsatzart = umsatzart
        self.amount = amount
        self.recordUIDs = recordUIDs
    }

    /// The amount in whole euros, truncated toward zero, as the ZM reports it.
    public var wholeEuros: Decimal { Money.truncated(amount, scale: 0) }

    static func normalize(_ vatID: String?) -> String {
        (vatID ?? "").uppercased().filter { !$0.isWhitespace && $0 != "." && $0 != "-" }
    }
}

/// A plausibility check of an EU customer's VAT ID (not a validity check, which needs the BZSt).
public enum CustomerVatID {
    /// The EU member state prefixes of VAT IDs, without Germany (`EL` for Greece, `XI` for Northern Ireland).
    public static let foreignEUPrefixes: Set<String> = [
        "AT", "BE", "BG", "CY", "CZ", "DK", "EE", "EL", "ES", "FI", "FR", "HR", "HU", "IE", "IT", "LT", "LU", "LV",
        "MT", "NL", "PL", "PT", "RO", "SE", "SI", "SK", "XI",
    ]

    /// `vatID` (normalized like a ZM line: uppercase, no spaces, dots or dashes) starts with another EU state's
    /// prefix followed by 2–12 letters or digits containing at least one digit.
    public static func isPlausible(_ vatID: String) -> Bool {
        let id = ZMLine.normalize(vatID)
        guard id.count >= 4, id.count <= 14, foreignEUPrefixes.contains(String(id.prefix(2))) else { return false }
        let rest = id.dropFirst(2)
        return rest.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "+" || $0 == "*") }
            && rest.contains { $0.isNumber }
    }
}

/// One record's part of a Kennzahl, for drilling down from the Kennzahlen table to the records.
public struct UStVAContribution: Sendable, Hashable {
    public var recordUID: String
    public var kennzahl: Kennzahl
    /// EUR, cents.
    public var amount: Decimal
}

/// The UStVA amounts as filed: bases truncated to whole euros, taxes rounded to cents, Kz83 computed.
/// Zero amounts are left out, except Kz83 (always present) and the partner of a non-zero amount in a
/// base/tax pair.
public struct Kennzahlen: Sendable, Equatable {
    public private(set) var values: [Kennzahl: Decimal]
    public let form: UStVAForm

    public init(values: [Kennzahl: Decimal], form: UStVAForm) {
        self.values = values
        self.form = form
    }

    public subscript(_ kz: Kennzahl) -> Decimal? { values[kz] }

    /// The remaining advance payment (positive) or refund (negative).
    public var kz83: Decimal { values[form.result] ?? 0 }

    /// The XML text of `kz`, or nil when it is not filed.
    public func text(_ kz: Kennzahl) -> String? { values[kz].map { form.text(kz, $0) } }

    /// Files the exact `sums`: formats each amount, drops zeros, keeps pairs together and computes Kz83 with
    /// the rates in force on `rateDate`.
    public static func file(_ sums: [Kennzahl: Decimal], form: UStVAForm, rates: VatRateTable, rateDate: String)
        -> Kennzahlen {
        var filed: [Kennzahl: Decimal] = [:]
        for (kz, amount) in sums where kz != form.result {
            let value = form.filed(kz, amount)
            if value != 0 { filed[kz] = value }
        }
        for pair in form.pairs where pair.contains(where: { filed[$0] != nil }) {
            for kz in pair where filed[kz] == nil { filed[kz] = 0 }
        }
        let entry = rates.entry(on: rateDate) ?? VatRateTable.Entry(validFrom: rateDate, standard: 0, reduced: 0)
        filed[form.result] = form.result(from: filed, rates: entry)
        return Kennzahlen(values: filed, form: form)
    }
}

/// The UStVA for one period: Kennzahlen, ZM lines, issues and the per-record contributions.
public struct UStVAResult: Sendable, Equatable {
    public var period: VatPeriod
    public var kennzahlen: Kennzahlen
    /// The exact (unrounded) EUR sums per Kennzahl before filing.
    public var sums: [Kennzahl: Decimal]
    public var contributions: [UStVAContribution]
    /// Sorted by customer VAT ID, then Umsatzart.
    public var zmLines: [ZMLine]
    public var issues: [UStVAIssue]
    /// UIDs of the records that count toward this period.
    public var recordUIDs: [String]

    /// True while records in the period have an unconfirmed VAT treatment.
    public var hasUnconfirmedTreatments: Bool { issues.contains { $0.code == .unconfirmedTreatment } }
    public var blocksSending: Bool { issues.contains(where: \.blocksSending) }
}

/// Turns a period's records into UStVA Kennzahlen and ZM lines.
///
/// - Skips drafts, removed records and VAT settlements with the tax office.
/// - Period assignment follows the taxation method: Soll uses the record `date`; Ist uses `payment_date` for
///   income (unpaid income invoiced in the period is left out with `unpaidUnderIst`); expenses always go by `date`.
///   The ZM lines always go by `date` (`zmLines`).
/// - Records with an unconfirmed treatment are aggregated with the suggestion and reported as
///   `unconfirmedTreatment`.
/// - Amounts are in EUR: `net_amount` (from the converted gross) and the VAT rows, which are EUR already.
///   Self-assessed VAT (reverse charge, acquisitions) is the record's rate (`VatRateTable.selfAssessedRate`)
///   × its EUR net, rounded per record to cents.
/// - Domestic rows are classed against the period's rates: the standard rate goes to Kz81, the reduced rate
///   to Kz86 and any other rate to Kz35/36.
public enum UStVAAggregator {
    /// - Parameter sondervorauszahlung: the Sondervorauszahlung set for the year; credited as Kz39 in the
    ///   December return when the configuration requires one (monthly filing with Dauerfristverlängerung).
    public static func aggregate(_ records: [UStVARecord], period: VatPeriod, configuration: TaxConfiguration,
                                 sondervorauszahlung: Decimal? = nil) -> UStVAResult {
        let form = configuration.ustvaForms.form(for: period.year)
        var acc = Accumulator(form: form)
        var included: [String] = []

        for record in records where !record.isDraft && !record.isRemoved {
            let entry = LedgerEntry(kind: record.kind, values: record.values)
            if entry.isVatPayment || entry.isVatRefund { continue }

            let date = record.values["date"]?.date ?? ""
            if record.kind == .income && configuration.taxationMethod == .ist {
                guard let paid = record.values["payment_date"]?.date else {
                    if period.contains(date) { acc.issue(.unpaidUnderIst, record) }
                    continue
                }
                guard period.contains(paid) else { continue }
            } else {
                guard period.contains(date) else { continue }
            }

            included.append(record.uid)
            let status = VatTreatmentStatus.of(record.kind, values: record.values, rates: configuration.vatRates)
            if !status.isConfirmed { acc.issue(.unconfirmedTreatment, record) }
            add(record, treatment: status.treatment, period: period, configuration: configuration, to: &acc)
        }

        if let sondervorauszahlung, sondervorauszahlung > 0, configuration.requiresSondervorauszahlung,
           period.length == .month, period.lastMonth == 12 {
            acc.sums[form.sondervorauszahlungCredit, default: 0] += sondervorauszahlung
        }

        let kennzahlen = Kennzahlen.file(acc.sums, form: form, rates: configuration.vatRates, rateDate: period.start)
        let zm = configuration.taxationMethod == .soll
            ? acc.zmLines : zmLines(records, period: period, configuration: configuration)
        return UStVAResult(period: period, kennzahlen: kennzahlen, sums: acc.sums, contributions: acc.contributions,
                           zmLines: zm, issues: acc.issues, recordUIDs: included)
    }

    /// The ZM lines of `period`: the EU B2B sales by record `date` (the invoice date) under either taxation method.
    /// §18a(8) UStG ties the ZM to the period in which the invoice is issued (goods) or the service is performed,
    /// not to the payment, so Ist-Versteuerung doesn't move them.
    public static func zmLines(_ records: [UStVARecord], period: VatPeriod,
                               configuration: TaxConfiguration) -> [ZMLine] {
        zmAggregate(records, period: period, configuration: configuration).zmLines
    }

    /// The aggregation of `period` by record `date` under either taxation method: its `zmLines` and the issues of
    /// the records behind them (the ZM's warnings). Its Kennzahlen are not a UStVA under Ist-Versteuerung.
    public static func zmAggregate(_ records: [UStVARecord], period: VatPeriod,
                                   configuration: TaxConfiguration) -> UStVAResult {
        var soll = configuration
        soll.settings.taxationMethod = .soll
        return aggregate(records, period: period, configuration: soll)
    }

    /// The drafts (not removed) dated in `period`, as `draftInPeriod` issues. Kept apart from `aggregate`, which
    /// leaves drafts out entirely; the VAT returns screen shows both lists.
    public static func draftIssues(_ records: [UStVARecord], period: VatPeriod) -> [UStVAIssue] {
        records.filter { $0.isDraft && !$0.isRemoved && period.contains($0.values["date"]?.date ?? "") }
            .map { UStVAIssue(.draftInPeriod, recordUID: $0.uid, kind: $0.kind) }
    }

    struct ZMKey: Hashable {
        var vatID: String
        var art: ZMUmsatzart
    }

    struct Accumulator {
        let form: UStVAForm
        var sums: [Kennzahl: Decimal] = [:]
        var contributions: [UStVAContribution] = []
        var issues: [UStVAIssue] = []
        var zm: [ZMKey: (amount: Decimal, uids: [String])] = [:]

        mutating func add(_ amount: Decimal, to kz: Kennzahl?, _ record: UStVARecord) {
            guard let kz, amount != 0 else { return }
            sums[kz, default: 0] += amount
            contributions.append(UStVAContribution(recordUID: record.uid, kennzahl: kz, amount: amount))
        }

        mutating func issue(_ code: UStVAIssue.Code, _ record: UStVARecord) {
            issues.append(UStVAIssue(code, recordUID: record.uid, kind: record.kind))
        }

        /// Sorted by customer VAT ID, then Umsatzart.
        var zmLines: [ZMLine] {
            zm.map { key, value in
                ZMLine(customerVatID: key.vatID, umsatzart: key.art, amount: value.amount, recordUIDs: value.uids)
            }.sorted { ($0.customerVatID, $0.umsatzart) < ($1.customerVatID, $1.umsatzart) }
        }
    }

    static func add(_ record: UStVARecord, treatment: VatTreatment, period: VatPeriod,
                    configuration: TaxConfiguration, to acc: inout Accumulator) {
        let values = record.values
        let form = acc.form
        let rates = configuration.vatRates
        let date = values["date"]?.date ?? ""
        let allRows = values["vat_rates"]?.vatRates ?? []
        let rows = allRows.filter { $0.amount != 0 }
        guard let gross = values["converted_gross_amount"]?.decimal else {
            if treatment != .notTaxable && treatment != .noVat { acc.issue(.missingEURAmount, record) }
            return
        }
        let vat = rows.reduce(Decimal(0)) { $0 + $1.amount }
        let net = values["net_amount"]?.decimal ?? (gross - vat)

        func rateClass(_ rate: Decimal) -> UStVAForm.RateClass {
            switch rates.kind(of: rate, on: period.start) {
            case .standard: .standard
            case .reduced: .reduced
            case nil: .other
            }
        }
        let vorsteuerShare = configuration.vorsteuerShareRules.share(for: values)
        func inputTax(_ slot: UStVAForm.Slot, _ tax: Decimal) {
            acc.add(Money.rounded(slot.appliesVorsteuerShare ? tax * vorsteuerShare : tax), to: slot.inputTax, record)
        }

        switch treatment {
        case .domestic:
            let taxed = rows.filter { $0.rate > 0 }
            guard !taxed.isEmpty else { acc.issue(.missingVatRows, record); return }
            for row in taxed {
                guard let slot = form.slot(.domestic, rateClass(row.rate)) else { continue }
                // One rate: the record's net. Several: each row's base from its VAT.
                let base = taxed.count == 1 ? net : Money.rounded(row.amount * 100 / row.rate)
                acc.add(base, to: slot.base, record)
                acc.add(row.amount, to: slot.tax, record)
            }

        case .euB2BService, .euB2BGoods, .exportGoods, .nonEUService:
            guard let slot = form.slot(treatment) else { return }
            acc.add(net, to: slot.base, record)
            if let art = slot.zm {
                let vatID = ZMLine.normalize(values["client_vat_number"]?.text)
                if vatID.isEmpty {
                    acc.issue(.missingCustomerVatID, record)
                } else if !CustomerVatID.isPlausible(vatID) {
                    acc.issue(.implausibleCustomerVatID, record)
                }
                let key = ZMKey(vatID: vatID, art: art)
                acc.zm[key, default: (0, [])].amount += net
                acc.zm[key, default: (0, [])].uids.append(record.uid)
            }

        case .domesticVat:
            guard let slot = form.slot(treatment) else { return }
            guard !rows.isEmpty else { acc.issue(.missingVatRows, record); return }
            inputTax(slot, vat)

        case .rcEUService, .rcNonEUService, .euGoodsAcquisition:
            // A rate row without an amount ("7%: 0") still names the rate the recipient owes.
            guard let rate = rates.selfAssessedRate(on: date, rows: allRows) else {
                acc.issue(.missingVatRate, record)
                return
            }
            let cls: UStVAForm.RateClass = treatment == .euGoodsAcquisition ? rateClass(rate) : .any
            guard let slot = form.slot(treatment, cls) else { return }
            let tax = Money.rounded(net * rate / 100)
            acc.add(net, to: slot.base, record)
            acc.add(tax, to: slot.tax, record)
            inputTax(slot, tax)

        case .importVat:
            guard let slot = form.slot(treatment) else { return }
            // The EUSt from the customs notice: its VAT rows, or the whole amount paid when it has none.
            inputTax(slot, rows.isEmpty ? gross : vat)

        case .notTaxable, .noVat:
            return
        }
    }
}
