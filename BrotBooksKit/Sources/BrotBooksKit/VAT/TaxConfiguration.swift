import Foundation

/// Soll-Versteuerung (VAT when invoiced) or Ist-Versteuerung (VAT when paid).
public enum TaxationMethod: String, Sendable, Hashable, Codable, CaseIterable {
    case soll, ist
}

/// How often the UStVA is filed; `none` means only the annual return.
public enum FilingFrequency: String, Sendable, Hashable, Codable, CaseIterable {
    case monthly, quarterly, none
}

/// How often the Zusammenfassende Meldung is filed.
public enum ZMFrequency: String, Sendable, Hashable, Codable, CaseIterable {
    case monthly, quarterly
}

/// One effective-dated set of filing settings, valid from `effectiveFrom` until the next period starts.
/// Money is `Decimal`, encoded as an exact decimal string. Decoding tolerates missing or unknown values
/// (falling back to the initial settings), so fields can be added without breaking stored profiles.
public struct TaxSettingsPeriod: Sendable, Equatable, Hashable, Codable {
    /// ISO `YYYY-MM-DD`, usually 1 January.
    public var effectiveFrom: String
    public var taxationMethod: TaxationMethod
    public var ustvaFrequency: FilingFrequency
    public var dauerfristverlaengerung: Bool
    /// The Sondervorauszahlung entered by hand; nil uses 1/11 of the prior year's advance payments
    /// (`Sondervorauszahlung.computed`).
    public var sondervorauszahlungOverride: Decimal?
    public var zmFrequency: ZMFrequency
    /// EU goods deliveries per quarter above which quarterly ZM filing gets a warning.
    public var zmThreshold: Decimal

    public init(effectiveFrom: String, taxationMethod: TaxationMethod = .soll, ustvaFrequency: FilingFrequency = .monthly,
                dauerfristverlaengerung: Bool = true, sondervorauszahlungOverride: Decimal? = nil,
                zmFrequency: ZMFrequency = .monthly, zmThreshold: Decimal = 50_000) {
        self.effectiveFrom = effectiveFrom
        self.taxationMethod = taxationMethod
        self.ustvaFrequency = ustvaFrequency
        self.dauerfristverlaengerung = dauerfristverlaengerung
        self.sondervorauszahlungOverride = sondervorauszahlungOverride
        self.zmFrequency = zmFrequency
        self.zmThreshold = zmThreshold
    }

    /// The initial settings: Soll, monthly UStVA with Dauerfristverlängerung, monthly ZM, €50,000 threshold.
    public static func initial(from date: String = "2026-01-01") -> TaxSettingsPeriod {
        TaxSettingsPeriod(effectiveFrom: date)
    }

    enum CodingKeys: String, CodingKey {
        case effectiveFrom, taxationMethod, ustvaFrequency, dauerfristverlaengerung, sondervorauszahlungOverride,
             zmFrequency, zmThreshold
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let fallback = TaxSettingsPeriod.initial()
        func value<T: RawRepresentable>(_ key: CodingKeys, _ fallback: T) -> T where T.RawValue == String {
            ((try? c.decodeIfPresent(String.self, forKey: key)) ?? nil).flatMap(T.init(rawValue:)) ?? fallback
        }
        func decimal(_ key: CodingKeys) -> Decimal? {
            ((try? c.decodeIfPresent(String.self, forKey: key)) ?? nil).flatMap(Money.parse)
        }
        effectiveFrom = try c.decode(String.self, forKey: .effectiveFrom)
        taxationMethod = value(.taxationMethod, fallback.taxationMethod)
        ustvaFrequency = value(.ustvaFrequency, fallback.ustvaFrequency)
        dauerfristverlaengerung = (try? c.decodeIfPresent(Bool.self, forKey: .dauerfristverlaengerung))
            .flatMap { $0 } ?? fallback.dauerfristverlaengerung
        sondervorauszahlungOverride = decimal(.sondervorauszahlungOverride)
        zmFrequency = value(.zmFrequency, fallback.zmFrequency)
        zmThreshold = decimal(.zmThreshold) ?? fallback.zmThreshold
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(effectiveFrom, forKey: .effectiveFrom)
        try c.encode(taxationMethod, forKey: .taxationMethod)
        try c.encode(ustvaFrequency, forKey: .ustvaFrequency)
        try c.encode(dauerfristverlaengerung, forKey: .dauerfristverlaengerung)
        try c.encodeIfPresent(sondervorauszahlungOverride.map(Money.plainString), forKey: .sondervorauszahlungOverride)
        try c.encode(zmFrequency, forKey: .zmFrequency)
        try c.encode(Money.plainString(zmThreshold), forKey: .zmThreshold)
    }
}

/// Who files: the DatenLieferant / Unternehmer data of the returns. Empty strings mean "not entered".
public struct TaxIdentity: Sendable, Equatable, Hashable, Codable {
    public var name: String
    public var street: String
    public var houseNumber: String
    public var postalCode: String
    public var city: String
    public var phone: String
    public var email: String
    /// 13-digit ELSTER format (e.g. "9198011310010"), not the regional notation.
    public var steuernummer: String
    /// 4-digit Finanzamt number (Bundesfinanzamtsnummer).
    public var finanzamt: String
    /// USt-IdNr, e.g. "DE123456789".
    public var vatID: String
    /// Wirtschafts-Identifikationsnummer as entered, e.g. "DE123456788" or "DE123456788-00001" (see `WIdNr`).
    public var wIdNr: String
    /// The Steuernummer as it appears on the Finanzamt's letters (e.g. "21/815/08150"), kept to show it again;
    /// `steuernummer` holds the converted ELSTER format.
    public var steuernummerRegional: String

    public init(name: String = "", street: String = "", houseNumber: String = "", postalCode: String = "",
                city: String = "", phone: String = "", email: String = "", steuernummer: String = "",
                finanzamt: String = "", vatID: String = "", wIdNr: String = "", steuernummerRegional: String = "") {
        self.name = name
        self.street = street
        self.houseNumber = houseNumber
        self.postalCode = postalCode
        self.city = city
        self.phone = phone
        self.email = email
        self.steuernummer = steuernummer
        self.finanzamt = finanzamt
        self.vatID = vatID
        self.wIdNr = wIdNr
        self.steuernummerRegional = steuernummerRegional
    }
}

/// The Wirtschafts-Identifikationsnummer (W-IdNr.): `DE`, nine digits (the last a check digit) and an optional
/// distinguishing suffix `-NNNNN` starting at 00001 (EHB 6.3.5).
public enum WIdNr {
    /// Uppercased, with spaces removed.
    public static func normalized(_ text: String) -> String {
        text.uppercased().filter { !$0.isWhitespace }
    }

    /// `text` has the W-IdNr. format (the check digit is not verified).
    public static func isWellFormed(_ text: String) -> Bool {
        normalized(text).wholeMatch(of: /DE[0-9]{9}(-[0-9]{5})?/) != nil
    }

    /// The part the UStVA schema accepts (`DE[0-9]{9}`, without the suffix), or nil when `text` is not well formed.
    public static func base(_ text: String) -> String? {
        guard isWellFormed(text) else { return nil }
        return String(normalized(text).prefix(11))
    }
}

/// The whole tax profile as a value: identity, test mode and the effective-dated settings history.
/// Persisted by the `TaxProfile` model.
public struct TaxSettings: Sendable, Equatable {
    public var identity: TaxIdentity
    /// Returns are sent with the ELSTER test marker while this is on.
    public var testMode: Bool
    /// Each valid from its `effectiveFrom`; kept sorted by it.
    public private(set) var periods: [TaxSettingsPeriod]
    /// Expense categories → share of their VAT deductible as input tax.
    public var vorsteuerShareRules: VorsteuerShareRules

    public init(identity: TaxIdentity = TaxIdentity(), testMode: Bool = true, periods: [TaxSettingsPeriod],
                vorsteuerShareRules: VorsteuerShareRules = .default) {
        self.identity = identity
        self.testMode = testMode
        self.periods = periods.sorted { $0.effectiveFrom < $1.effectiveFrom }
        self.vorsteuerShareRules = vorsteuerShareRules
    }

    /// The seed when no profile exists: test mode on and the initial settings from 1 January 2026.
    public static let initial = TaxSettings(periods: [.initial(from: "2026-01-01")])

    /// Adds `period`, replacing one with the same `effectiveFrom`. Earlier periods are never changed.
    public mutating func set(_ period: TaxSettingsPeriod) {
        periods.removeAll { $0.effectiveFrom == period.effectiveFrom }
        periods.append(period)
        periods.sort { $0.effectiveFrom < $1.effectiveFrom }
    }

    public mutating func remove(effectiveFrom: String) {
        periods.removeAll { $0.effectiveFrom == effectiveFrom }
    }

    /// The settings period in force on the ISO `date`: the latest one starting on or before it.
    public func period(on date: String) -> TaxSettingsPeriod? {
        periods.last { $0.effectiveFrom <= date }
    }

    /// The configuration in force on `date`, or nil before the first settings period.
    public func configuration(on date: String, vatRates: VatRateTable = .germany,
                              deadlines: FilingDeadlines = .germany) -> TaxConfiguration? {
        period(on: date).map {
            TaxConfiguration(settings: $0, identity: identity, testMode: testMode, vatRates: vatRates, deadlines: deadlines,
                             vorsteuerShareRules: vorsteuerShareRules)
        }
    }

    /// The configuration for a filing period: the settings in force on its first day.
    public func configuration(for period: VatPeriod, vatRates: VatRateTable = .germany,
                              deadlines: FilingDeadlines = .germany) -> TaxConfiguration? {
        configuration(on: period.start, vatRates: vatRates, deadlines: deadlines)
    }
}

/// Every filing rule for one date: the active settings period plus identity, test mode and the rate and
/// deadline tables. Aggregation, XML and deadlines take this as input instead of tax constants of their own.
public struct TaxConfiguration: Sendable, Equatable {
    public var settings: TaxSettingsPeriod
    public var identity: TaxIdentity
    public var testMode: Bool
    public var vatRates: VatRateTable
    public var deadlines: FilingDeadlines
    /// Where each VAT treatment lands on the UStVA, by year.
    public var ustvaForms: UStVAForms
    /// Expense categories → share of their VAT deductible as input tax.
    public var vorsteuerShareRules: VorsteuerShareRules

    public init(settings: TaxSettingsPeriod, identity: TaxIdentity = TaxIdentity(), testMode: Bool = true,
                vatRates: VatRateTable = .germany, deadlines: FilingDeadlines = .germany,
                ustvaForms: UStVAForms = .germany, vorsteuerShareRules: VorsteuerShareRules = .default) {
        self.settings = settings
        self.identity = identity
        self.testMode = testMode
        self.vatRates = vatRates
        self.deadlines = deadlines
        self.ustvaForms = ustvaForms
        self.vorsteuerShareRules = vorsteuerShareRules
    }

    public var taxationMethod: TaxationMethod { settings.taxationMethod }
    public var ustvaFrequency: FilingFrequency { settings.ustvaFrequency }
    public var dauerfristverlaengerung: Bool { settings.dauerfristverlaengerung }
    public var zmFrequency: ZMFrequency { settings.zmFrequency }
    public var zmThreshold: Decimal { settings.zmThreshold }

    /// A Sondervorauszahlung is due: monthly filing with Dauerfristverlängerung.
    public var requiresSondervorauszahlung: Bool { dauerfristverlaengerung && ustvaFrequency == .monthly }
}

/// The Sondervorauszahlung (UStSV) owed for a Dauerfristverlängerung with monthly filing.
public enum Sondervorauszahlung {
    /// 1/11 of the prior year's advance payments, rounded to cents; 0 when they are not positive.
    ///
    /// The advance payments are the sum of the prior year's Kz83 **plus** the prior year's Sondervorauszahlung:
    /// that year's December return credited the Sondervorauszahlung (Kz39), so its Kz83 is already net of it
    /// (form text for Kz38).
    /// - Parameters:
    ///   - priorYearKz83Total: the sum of Kz83 over the prior year's returns.
    ///   - priorYearSondervorauszahlung: the Sondervorauszahlung of the prior year (credited as Kz39 in its
    ///     December return); 0 when there was none.
    public static func computed(priorYearKz83Total: Decimal, priorYearSondervorauszahlung: Decimal) -> Decimal {
        let advancePayments = priorYearKz83Total + priorYearSondervorauszahlung
        return advancePayments > 0 ? Money.rounded(advancePayments / 11) : 0
    }

    /// The override from the settings when one is entered, otherwise `computed`.
    public static func amount(priorYearKz83Total: Decimal, priorYearSondervorauszahlung: Decimal,
                              settings: TaxSettingsPeriod) -> Decimal {
        settings.sondervorauszahlungOverride
            ?? computed(priorYearKz83Total: priorYearKz83Total, priorYearSondervorauszahlung: priorYearSondervorauszahlung)
    }
}

/// EU goods deliveries in a quarter above the threshold while ZM is filed quarterly: monthly filing is required.
/// The app only suggests switching; it never changes the setting itself.
public struct ZMThresholdWarning: Sendable, Equatable {
    public var quarter: VatPeriod
    public var deliveries: Decimal
    public var threshold: Decimal

    /// A warning when ZM is quarterly and `euGoodsDeliveries` in `quarter` exceed the configured threshold.
    public static func check(euGoodsDeliveries: Decimal, quarter: VatPeriod,
                             configuration: TaxConfiguration) -> ZMThresholdWarning? {
        guard configuration.zmFrequency == .quarterly, euGoodsDeliveries > configuration.zmThreshold else { return nil }
        return ZMThresholdWarning(quarter: quarter, deliveries: euGoodsDeliveries, threshold: configuration.zmThreshold)
    }
}
