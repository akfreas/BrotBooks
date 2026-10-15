import Foundation

/// A UStVA Kennzahl (form field number) that holds an amount.
public enum Kennzahl: Int, Sendable, Hashable, Codable, CaseIterable, Comparable, CustomStringConvertible {
    case kz21 = 21, kz35 = 35, kz36 = 36, kz37 = 37, kz38 = 38, kz39 = 39
    case kz41 = 41, kz42 = 42, kz43 = 43, kz44 = 44, kz45 = 45, kz46 = 46, kz47 = 47, kz48 = 48, kz49 = 49
    case kz50 = 50, kz59 = 59, kz60 = 60, kz61 = 61, kz62 = 62, kz63 = 63, kz64 = 64, kz65 = 65, kz66 = 66
    case kz67 = 67, kz69 = 69, kz73 = 73, kz74 = 74, kz76 = 76, kz77 = 77, kz80 = 80, kz81 = 81, kz83 = 83
    case kz84 = 84, kz85 = 85, kz86 = 86, kz87 = 87, kz89 = 89, kz90 = 90, kz91 = 91, kz93 = 93, kz94 = 94
    case kz95 = 95, kz96 = 96, kz98 = 98

    /// The XML element name, e.g. `Kz81`.
    public var elementName: String { "Kz\(rawValue)" }
    public var description: String { elementName }
    public static func < (a: Kennzahl, b: Kennzahl) -> Bool { a.rawValue < b.rawValue }
}

/// The yes/no fields of the UStVA, sent as `1` when set.
public struct UStVAFlags: OptionSet, Sendable, Hashable {
    public let rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }

    /// Kz10: corrected return (berichtigte Anmeldung).
    public static let correction = UStVAFlags(rawValue: 1 << 0)
    /// Kz22: documents (contracts, invoices) are submitted separately.
    public static let documentsSubmittedSeparately = UStVAFlags(rawValue: 1 << 1)
    /// Kz26: don't use the SEPA direct-debit mandate for this period.
    public static let noDirectDebit = UStVAFlags(rawValue: 1 << 2)
    /// Kz29: offset the refund against other taxes / the refund is assigned.
    public static let offsetRefund = UStVAFlags(rawValue: 1 << 3)

    /// The Kennzahl number of each flag.
    public static let numbers: [(flag: UStVAFlags, number: Int)] = [
        (.correction, 10), (.documentsSubmittedSeparately, 22), (.noDirectDebit, 26), (.offsetRefund, 29),
    ]

    func contains(number: Int) -> Bool {
        Self.numbers.contains { $0.number == number && contains($0.flag) }
    }
}

/// The ZM Umsatzart: L for intra-community deliveries of goods, S for other services (§3a(2) UStG).
public enum ZMUmsatzart: String, Sendable, Hashable, Codable, CaseIterable, Comparable {
    case goods = "L", service = "S"
    public static func < (a: ZMUmsatzart, b: ZMUmsatzart) -> Bool { a.rawValue < b.rawValue }
}

/// One year's UStVA form: where each `VatTreatment` (and rate class) lands, how Kz83 is computed, the amount
/// formats and the XML element order. Kennzahlen change between years (`Deltadokumentation/<year>`), so the
/// form is versioned and picked by the period's year (`UStVAForms`).
public struct UStVAForm: Sendable, Equatable {
    /// Which rate a record's VAT is at, measured against the rates of the filing period.
    public enum RateClass: Sendable, Hashable {
        case standard, reduced, other
        /// The slot applies to every rate.
        case any
    }

    /// Where a record's amounts go.
    public struct Slot: Sendable, Equatable {
        /// The net (assessment base) in EUR.
        public var base: Kennzahl?
        /// The output tax the record owes (reverse charge, acquisitions at other rates, domestic other rates).
        public var tax: Kennzahl?
        /// The deductible input tax.
        public var inputTax: Kennzahl?
        /// Whether `inputTax` is reduced by the Vorsteuer share (`VorsteuerShareRules`).
        public var appliesVorsteuerShare: Bool
        /// The ZM line the base is reported on.
        public var zm: ZMUmsatzart?

        public init(base: Kennzahl? = nil, tax: Kennzahl? = nil, inputTax: Kennzahl? = nil,
                    appliesVorsteuerShare: Bool = false, zm: ZMUmsatzart? = nil) {
            self.base = base
            self.tax = tax
            self.inputTax = inputTax
            self.appliesVorsteuerShare = appliesVorsteuerShare
            self.zm = zm
        }
    }

    public struct SlotKey: Sendable, Hashable {
        public var treatment: VatTreatment
        public var rate: RateClass
        public init(_ treatment: VatTreatment, _ rate: RateClass = .any) {
            self.treatment = treatment
            self.rate = rate
        }
    }

    /// First UStVA year this form applies to.
    public var firstYear: Int
    /// Treatment (and rate class) → Kennzahlen. A treatment without a slot reports nothing.
    public var slots: [SlotKey: Slot]
    /// Bases whose tax the form computes itself (`base × rate`), with the rate they are taxed at.
    public var computedTaxBases: [Kennzahl: VatRateKind]
    /// Tax amounts added in Kz83.
    public var outputTaxes: [Kennzahl]
    /// Input-tax amounts subtracted in Kz83.
    public var inputTaxes: [Kennzahl]
    /// The Sondervorauszahlung credited in the last return of the year, subtracted in Kz83.
    public var sondervorauszahlungCredit: Kennzahl
    /// The remaining advance payment or refund.
    public var result: Kennzahl
    /// The Sondervorauszahlung in its own return (`Umsatzsteuersondervorauszahlung`).
    public var sondervorauszahlung: Kennzahl
    /// Amounts written as whole euros; every other Kennzahl has two decimals.
    public var wholeEuroFields: Set<Kennzahl>
    /// Base/tax pairs that must be sent together.
    public var pairs: [[Kennzahl]]
    /// Kennzahl numbers (amounts and the flags 10, 22, 26, 29) in the XSD sequence order of
    /// `Umsatzsteuervoranmeldung`, after `Jahr`, `Zeitraum`, `Steuernummer` and `Kz09`.
    public var elementOrder: [Int]
    /// The same for `Umsatzsteuersondervorauszahlung`.
    public var sondervorauszahlungElementOrder: [Int]

    /// The slot for `treatment` at `rate`, falling back to the treatment's `.any` slot.
    public func slot(_ treatment: VatTreatment, _ rate: RateClass = .any) -> Slot? {
        slots[SlotKey(treatment, rate)] ?? slots[SlotKey(treatment, .any)]
    }

    public func isWholeEuros(_ kz: Kennzahl) -> Bool { wholeEuroFields.contains(kz) }

    /// The amount as filed: whole-euro fields truncated toward zero, the others rounded to cents.
    public func filed(_ kz: Kennzahl, _ amount: Decimal) -> Decimal {
        isWholeEuros(kz) ? Money.truncated(amount, scale: 0) : Money.rounded(amount)
    }

    /// The XML text of a filed amount: `150000` or `1600.00`.
    public func text(_ kz: Kennzahl, _ amount: Decimal) -> String {
        isWholeEuros(kz) ? Money.plainString(Money.truncated(amount, scale: 0)) : UStVAForm.cents(amount)
    }

    /// `amount` with exactly two decimals ("1600.00", "-12.50").
    static func cents(_ amount: Decimal) -> String {
        let r = Money.rounded(amount)
        let negative = r < 0
        let text = Money.plainString(negative ? -r : r)
        let parts = text.split(separator: ".", omittingEmptySubsequences: false)
        let fraction = parts.count > 1 ? String(parts[1]) : ""
        return (negative ? "-" : "") + parts[0] + "." + String((fraction + "00").prefix(2))
    }

    /// Kz83 from filed amounts: the tax on the form-computed bases (at `rates`, from the already truncated
    /// whole-euro base, as on the paper form) plus the output taxes, minus the input taxes and the
    /// Sondervorauszahlung credit.
    public func result(from filed: [Kennzahl: Decimal], rates: VatRateTable.Entry) -> Decimal {
        var total = Decimal(0)
        for (base, kind) in computedTaxBases {
            total += Money.rounded((filed[base] ?? 0) * rates.rate(kind) / 100)
        }
        for kz in outputTaxes { total += filed[kz] ?? 0 }
        for kz in inputTaxes { total -= filed[kz] ?? 0 }
        total -= filed[sondervorauszahlungCredit] ?? 0
        return Money.rounded(total)
    }

    /// The 2026 form (Jahresdokumentation_UStVA_2026, schema `ustva/v2026`).
    public static let ustva2026 = UStVAForm(
        firstYear: 2026,
        slots: [
            // Income
            SlotKey(.domestic, .standard): Slot(base: .kz81),
            SlotKey(.domestic, .reduced): Slot(base: .kz86),
            SlotKey(.domestic, .other): Slot(base: .kz35, tax: .kz36),
            SlotKey(.euB2BService): Slot(base: .kz21, zm: .service),
            SlotKey(.euB2BGoods): Slot(base: .kz41, zm: .goods),
            SlotKey(.exportGoods): Slot(base: .kz43),
            SlotKey(.nonEUService): Slot(base: .kz45),
            // Expenses
            SlotKey(.domesticVat): Slot(inputTax: .kz66, appliesVorsteuerShare: true),
            SlotKey(.rcEUService): Slot(base: .kz46, tax: .kz47, inputTax: .kz67, appliesVorsteuerShare: true),
            SlotKey(.rcNonEUService): Slot(base: .kz84, tax: .kz85, inputTax: .kz67, appliesVorsteuerShare: true),
            SlotKey(.euGoodsAcquisition, .standard): Slot(base: .kz89, inputTax: .kz61, appliesVorsteuerShare: true),
            SlotKey(.euGoodsAcquisition, .reduced): Slot(base: .kz93, inputTax: .kz61, appliesVorsteuerShare: true),
            SlotKey(.euGoodsAcquisition, .other): Slot(base: .kz95, tax: .kz98, inputTax: .kz61, appliesVorsteuerShare: true),
            SlotKey(.importVat): Slot(inputTax: .kz62),
        ],
        computedTaxBases: [.kz81: .standard, .kz86: .reduced, .kz89: .standard, .kz93: .reduced],
        outputTaxes: [.kz36, .kz80, .kz98, .kz96, .kz47, .kz74, .kz85, .kz65, .kz69],
        inputTaxes: [.kz66, .kz61, .kz62, .kz67, .kz63, .kz64, .kz59],
        sondervorauszahlungCredit: .kz39,
        result: .kz83,
        sondervorauszahlung: .kz38,
        wholeEuroFields: [.kz21, .kz35, .kz38, .kz41, .kz42, .kz43, .kz44, .kz45, .kz46, .kz48, .kz49, .kz50, .kz60,
                          .kz73, .kz76, .kz77, .kz81, .kz84, .kz86, .kz87, .kz89, .kz90, .kz91, .kz93, .kz94, .kz95],
        pairs: [[.kz35, .kz36], [.kz46, .kz47], [.kz73, .kz74], [.kz76, .kz80], [.kz84, .kz85], [.kz95, .kz98],
                [.kz94, .kz96]],
        elementOrder: [10, 21, 22, 26, 29, 35, 36, 37, 39, 41, 42, 43, 44, 45, 46, 47, 48, 49, 50, 59, 60, 61, 62, 63,
                       64, 65, 66, 67, 69, 73, 74, 76, 77, 80, 81, 83, 84, 85, 86, 87, 89, 91, 93, 90, 94, 95, 96, 98],
        sondervorauszahlungElementOrder: [10, 26, 29, 38]
    )
}

/// The UStVA forms by year.
public struct UStVAForms: Sendable, Equatable {
    public var forms: [UStVAForm]

    public init(forms: [UStVAForm]) { self.forms = forms.sorted { $0.firstYear < $1.firstYear } }

    public static let germany = UStVAForms(forms: [.ustva2026])

    /// The latest form whose first year is on or before `year`; the earliest form for older years.
    public func form(for year: Int) -> UStVAForm {
        forms.last { $0.firstYear <= year } ?? forms[0]
    }
}
