import Foundation

/// The fixed codes of the Zusammenfassende Meldung (data type `ZMDO`, schema `zm_000005.xsd`, rules in
/// `Jahresdokumentation_ZMDO_2.ods`).
public enum ZMCodes {
    /// The data type version passed to ERiC (`Datenartversionmatrix.ods`: ElsterExtern / ZMDO → `ZMDO`, plugin
    /// `checkZMDO`).
    public static let datenartVersion = "ZMDO"
    /// `zm/@version`: the constant `000005` of `zm_000005.xsd`.
    public static let schemaVersion = "000005"

    /// `NutzdatenHeader/Empfaenger` with `id="L"`: the Bundeszentralamt für Steuern (EHB table 8-28, sample
    /// `ZMDO_5_send-Auth.xml`).
    public enum Empfaenger: String, Sendable {
        case bundeszentralamt = "BF"
    }

    /// `zm-zeilen/@meldeart` (`meldeart_Type`; field `meldeart`, rule `meldeart_Pflicht` 170015005).
    public enum Meldeart: Int, Sendable, Hashable, Codable {
        /// 10: Erstmeldung, the first report for the period.
        case initial = 10
        /// 11: berichtigte Meldung, a correction of a report already filed.
        case corrected = 11
    }

    /// `zm-zeilen/@waehrung` (`waehrung_Type`; the field `waehrung` admits only `1`).
    public enum Waehrung: Int, Sendable {
        case euro = 1
    }

    /// `zulassNr/zulnr1`, the Paginierbuchstabe (`zulassNr1_Type`; rule `zulnr1_Teilnehmernummer_Inhalt`
    /// 170015022: only `N` for ERiC transmissions).
    public enum Paginierbuchstabe: String, Sendable {
        case eric = "N"
    }

    /// `zulassNr/zulnr2`: the BZSt issues no new Teilnehmernummern, so without one of your own it is
    /// `1111111` (field `zulnr2_Teilnehmernummer`).
    public static let teilnehmernummerWithoutOwn = "1111111"

    /// `anschrift/staat`: the ISO 3166 code of the filer's country.
    public static let germany = "DE"
}

/// `zm-zeilen/mzr/quart`, the reporting period code (`quart_Type` in `zm_000005.xsd`). The two-month and
/// annual codes (5, 11–14) have no counterpart in the ZM frequencies the app offers.
public enum ZMMeldezeitraum: Int, Sendable, Hashable, CaseIterable {
    case firstQuarter = 1, secondQuarter = 2, thirdQuarter = 3, fourthQuarter = 4
    case january = 21, february = 22, march = 23, april = 24, may = 25, june = 26
    case july = 27, august = 28, september = 29, october = 30, november = 31, december = 32

    /// The code of a month (21–32) or quarter (1–4).
    public init(_ period: VatPeriod) {
        switch period.length {
        case .month: self.init(rawValue: 20 + period.index)!
        case .quarter: self.init(rawValue: period.index)!
        }
    }

    /// A monthly report (`anzeige` may only be set on one; rule `anzeige_keine_Monatsmeldung` 170015008).
    public var isMonth: Bool { rawValue >= 21 }
}

/// One `zeile` of a ZM as sent: customer VAT ID, Umsatzart and the amount in whole euros.
public struct ZMReportLine: Sendable, Hashable, Codable {
    public var customerVatID: String
    public var umsatzart: ZMUmsatzart
    /// Whole euros (may be negative, e.g. after a credit note; 0 cancels a line in a correction).
    public var amount: Decimal

    public init(customerVatID: String, umsatzart: ZMUmsatzart, amount: Decimal) {
        self.customerVatID = customerVatID
        self.umsatzart = umsatzart
        self.amount = amount
    }

    struct Key: Hashable, Comparable {
        var vatID: String
        var art: ZMUmsatzart
        static func < (a: Key, b: Key) -> Bool { (a.vatID, a.art) < (b.vatID, b.art) }
    }

    var key: Key { Key(vatID: customerVatID, art: umsatzart) }

    static func encode(_ lines: [ZMReportLine]) -> Data? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        return try? encoder.encode(lines.map(Stored.init))
    }

    static func decode(_ data: Data?) -> [ZMReportLine]? {
        guard let data, let stored = try? JSONDecoder().decode([Stored].self, from: data) else { return nil }
        return stored.compactMap(\.line)
    }

    /// The JSON form: the amount as a decimal string, the Umsatzart as its letter.
    struct Stored: Codable {
        var vatID: String
        var umsatzart: String
        var amount: String

        init(_ line: ZMReportLine) {
            vatID = line.customerVatID
            umsatzart = line.umsatzart.rawValue
            amount = Money.plainString(line.amount)
        }

        var line: ZMReportLine? {
            guard let art = ZMUmsatzart(rawValue: umsatzart), let value = Money.parse(amount) else { return nil }
            return ZMReportLine(customerVatID: vatID, umsatzart: art, amount: value)
        }
    }
}

/// What a ZM sends for a period: the lines and whether it is the first report or a correction.
///
/// - First report (`meldeart` 10): every customer VAT ID and Umsatzart with a non-zero amount in whole euros.
///   Lines between −0.99 and 0.99 € are zero after truncation and are left out: an Erstmeldung must not report
///   zero amounts, and with none left there is nothing to report (rules `Meldezeile_Pflicht` 170045002,
///   "Nullmeldungen sind nicht zulässig", and `Meldezeile_Nullmeldung_bei_Erstmeldung` 170045001).
/// - Correction (`meldeart` 11), per the BZSt's rules for a berichtigte ZM: only the lines that changed are
///   sent, each with its full corrected amount; correctly reported lines are not repeated; a line reported
///   before that is gone now (wrong VAT ID, wrong Umsatzart, wrong period) is cancelled with the amount 0.
public struct ZMReport: Sendable, Equatable {
    public var meldeart: ZMCodes.Meldeart
    /// Sorted by customer VAT ID, then Umsatzart.
    public var lines: [ZMReportLine]

    public init(meldeart: ZMCodes.Meldeart, lines: [ZMReportLine]) {
        self.meldeart = meldeart
        self.lines = lines
    }

    /// The full set of lines the period's ZM lines amount to: whole euros, zero lines left out.
    public static func reportable(_ lines: [ZMLine]) -> [ZMReportLine] {
        lines.map { ZMReportLine(customerVatID: $0.customerVatID, umsatzart: $0.umsatzart, amount: $0.wholeEuros) }
            .filter { $0.amount != 0 }
            .sorted { $0.key < $1.key }
    }

    /// The first report of `lines`.
    public static func initial(_ lines: [ZMLine]) -> ZMReport {
        ZMReport(meldeart: .initial, lines: reportable(lines))
    }

    /// The correction of `filed` (the full set of lines that stands for the period) to `current`: the changed
    /// and new lines with their full amounts, and a 0 line for each filed line that is gone. Empty when nothing
    /// changed.
    public static func correction(current: [ZMReportLine], filed: [ZMReportLine]) -> ZMReport {
        let now = Dictionary(current.filter { $0.amount != 0 }.map { ($0.key, $0) }, uniquingKeysWith: { a, _ in a })
        let before = Dictionary(filed.filter { $0.amount != 0 }.map { ($0.key, $0) }, uniquingKeysWith: { a, _ in a })
        var lines: [ZMReportLine] = []
        for (key, line) in now where before[key]?.amount != line.amount { lines.append(line) }
        for (key, line) in before where now[key] == nil {
            lines.append(ZMReportLine(customerVatID: line.customerVatID, umsatzart: line.umsatzart, amount: 0))
        }
        return ZMReport(meldeart: .corrected, lines: lines.sorted { $0.key < $1.key })
    }

    /// The report to send now: the first report while `filed` is nil, else the correction of `filed`.
    public static func make(_ lines: [ZMLine], filed: [ZMReportLine]?) -> ZMReport {
        guard let filed else { return initial(lines) }
        return correction(current: reportable(lines), filed: filed)
    }

    /// The sum of the lines in whole euros.
    public var total: Decimal { lines.reduce(0) { $0 + $1.amount } }
}

/// Builds the ElsterExtern XML of the ZM (data type `ZMDO`), modeled on the ERiC sample
/// `Datenarten/ElsterExtern/ZMDO/Beispiele/ZMDO_5_send-Auth.xml`, elements in the `zm_000005.xsd` order.
public enum ZMXML {
    /// The ZM of `report` for `period`. The filer (USt-IdNr, name and address) and test mode (Testmerker
    /// `700000004`) come from `configuration`; `header` gives the Hersteller-ID.
    ///
    /// - Parameters:
    ///   - anzeige: the declaration to file monthly from now on (§18a(1) Satz 2 UStG); only on a monthly report.
    ///   - widerruf: revokes that declaration; only on a quarterly report or the third month of a quarter.
    public static func build(period: VatPeriod, report: ZMReport, configuration: TaxConfiguration,
                             header: UStVAXML.Header, anzeige: Bool = false, widerruf: Bool = false) -> String {
        let id = configuration.identity
        let address = UStVAXML.Address(street: id.street, houseNumber: id.houseNumber)
        var x = UStVAXML.XMLWriter()
        x.line(#"<?xml version="1.0" encoding="UTF-8"?>"#)
        x.open("Elster", attributes: [("xmlns", "http://www.elster.de/elsterxml/schema/v11")])
        x.open("TransferHeader", attributes: [("version", "11")])
        x.element("Verfahren", "ElsterExtern")
        x.element("DatenArt", "ZMDO")
        x.element("Vorgang", "send-Auth")
        if configuration.testMode { x.element("Testmerker", "700000004") }
        x.element("HerstellerID", header.herstellerID)
        x.element("DatenLieferant", UStVAXML.datenLieferant(id))
        x.open("Datei")
        x.element("Verschluesselung", "CMSEncryptedData")
        x.element("Kompression", "GZIP")
        x.close("Datei")
        x.close("TransferHeader")
        x.open("DatenTeil")
        x.open("Nutzdatenblock")
        x.open("NutzdatenHeader", attributes: [("version", "11")])
        x.element("NutzdatenTicket", "1")
        x.element("Empfaenger", ZMCodes.Empfaenger.bundeszentralamt.rawValue, attributes: [("id", "L")])
        x.close("NutzdatenHeader")
        x.open("Nutzdaten")
        x.open("zm", attributes: [("xmlns", "http://www.elster.de/elsterxml/schema/v11"),
                                  ("version", ZMCodes.schemaVersion)])
        x.open("unternehmer")
        x.element("knri", normalizedVatID(id.vatID))
        x.open("zulassNr")
        x.element("zulnr1", ZMCodes.Paginierbuchstabe.eric.rawValue)
        x.element("zulnr2", ZMCodes.teilnehmernummerWithoutOwn)
        x.close("zulassNr")
        x.open("anschrift")
        x.element("name", id.name.trimmingCharacters(in: .whitespaces))
        x.optional("strasse", address.street)
        x.optional("hausnr", address.number)
        x.optional("hausnrzusatz", address.suffix)
        x.optional("plz", id.postalCode)
        x.optional("ort", id.city)
        x.element("staat", ZMCodes.germany)
        if id.phone.wholeMatch(of: /[0-9+\-\/() ]{1,20}/) != nil { x.element("telefon", id.phone) }
        x.close("anschrift")
        x.open("zm-zeilen", attributes: [("waehrung", String(ZMCodes.Waehrung.euro.rawValue)),
                                         ("meldeart", String(report.meldeart.rawValue))])
        x.element("anzeige", String(anzeige))
        x.element("widerruf", String(widerruf))
        x.open("mzr")
        x.element("quart", String(ZMMeldezeitraum(period).rawValue))
        x.element("jahr", String(period.year))
        x.close("mzr")
        for line in report.lines {
            x.open("zeile", attributes: [("umsatzart", line.umsatzart.rawValue)])
            x.element("knre", line.customerVatID)
            x.element("betrag", Money.plainString(Money.truncated(line.amount, scale: 0)))
            x.close("zeile")
        }
        x.close("zm-zeilen")
        x.close("unternehmer")
        x.close("zm")
        x.close("Nutzdaten")
        x.close("Nutzdatenblock")
        x.close("DatenTeil")
        x.close("Elster")
        return x.text
    }

    /// Uppercased, without spaces.
    static func normalizedVatID(_ vatID: String) -> String {
        vatID.uppercased().filter { !$0.isWhitespace }
    }
}

/// What the ZM needs from the tax profile: the USt-IdNr (`DE` and nine digits, `knri_Type`), the name, street
/// and city, and a five-digit postal code (rules `Name_Unternehmen_Pflicht`, `Strasse_Pflicht`, `Ort_Pflicht`,
/// `PLZ_Pflicht`).
extension TaxIdentity {
    public var missingForZM: [FilingRequirement] {
        var missing: [FilingRequirement] = []
        if ZMXML.normalizedVatID(vatID).wholeMatch(of: /DE[0-9]{9}/) == nil { missing.append(.vatID) }
        if name.trimmingCharacters(in: .whitespaces).isEmpty { missing.append(.name) }
        if street.trimmingCharacters(in: .whitespaces).isEmpty || city.trimmingCharacters(in: .whitespaces).isEmpty
            || postalCode.wholeMatch(of: /[0-9]{5}/) == nil {
            missing.append(.address)
        }
        return missing
    }
}

/// Whether the ZM agrees with Kz41 (goods) and Kz21 (services) of the UStVAs for the same months.
///
/// The comparison window is the ZM period widened to every UStVA period that overlaps it, so a quarterly ZM is
/// compared with the three monthly UStVAs of the quarter and three monthly ZMs with a quarterly UStVA. Both sides
/// are compared as filed, in whole euros: the ZM lines each truncated, the Kennzahlen each truncated per return.
/// Each truncation drops less than one euro, so a difference smaller than the number of truncated amounts on
/// both sides is rounding, not a mismatch.
public struct ZMConsistency: Sendable, Equatable {
    public struct Comparison: Sendable, Equatable {
        public var umsatzart: ZMUmsatzart
        /// The Kennzahl it is compared with: Kz41 for goods, Kz21 for services.
        public var kennzahl: Kennzahl
        /// Σ of the ZM lines, whole euros each.
        public var zmTotal: Decimal
        /// Σ of the Kennzahl over the UStVAs.
        public var ustvaTotal: Decimal
        /// The amounts truncated on both sides: the difference allowed for rounding stays below this.
        public var truncations: Int

        public var difference: Decimal { zmTotal - ustvaTotal }
        public var matches: Bool { abs(difference) < Decimal(max(truncations, 1)) }
    }

    /// The ZM periods and UStVA periods of the widened window.
    public var zmPeriods: [VatPeriod]
    public var ustvaPeriods: [VatPeriod]
    /// Goods (Kz41), then services (Kz21).
    public var comparisons: [Comparison]

    public var matches: Bool { comparisons.allSatisfy(\.matches) }

    /// - Parameters:
    ///   - zmPeriod: the ZM whose consistency is checked.
    ///   - zmLines: the ZM lines of every ZM period (by period), at least those overlapping the UStVA periods.
    ///   - ustva: the filed (or computed) Kennzahlen of each UStVA period.
    /// - Returns: nil when no UStVA period overlaps `zmPeriod` (e.g. annual-only filing).
    public static func check(zmPeriod: VatPeriod, zmLines: [VatPeriod: [ZMLine]],
                             ustva: [VatPeriod: Kennzahlen]) -> ZMConsistency? {
        func overlaps(_ a: VatPeriod, _ b: VatPeriod) -> Bool { a.start <= b.end && b.start <= a.end }
        var start = zmPeriod.start, end = zmPeriod.end
        // Widen until both sides cover the same months.
        while true {
            let window = (start, end)
            for period in ustva.keys where period.start <= end && start <= period.end {
                start = min(start, period.start)
                end = max(end, period.end)
            }
            for period in zmLines.keys where period.start <= end && start <= period.end {
                start = min(start, period.start)
                end = max(end, period.end)
            }
            if window == (start, end) { break }
        }
        let ustvaPeriods = ustva.keys.filter { $0.start >= start && $0.end <= end }.sorted()
        guard ustvaPeriods.contains(where: { overlaps($0, zmPeriod) }) else { return nil }
        let zmPeriods = zmLines.keys.filter { $0.start >= start && $0.end <= end }.sorted()
        let comparisons = [(ZMUmsatzart.goods, Kennzahl.kz41), (.service, .kz21)].map { art, kz in
            let lines = zmPeriods.flatMap { zmLines[$0] ?? [] }.filter { $0.umsatzart == art }
            let filedLines = lines.filter { $0.wholeEuros != 0 }
            let returns = ustvaPeriods.compactMap { ustva[$0]?[kz] }
            return Comparison(umsatzart: art, kennzahl: kz,
                              zmTotal: filedLines.reduce(0) { $0 + $1.wholeEuros },
                              ustvaTotal: returns.reduce(0) { $0 + Money.truncated($1, scale: 0) },
                              truncations: lines.count + returns.count)
        }
        return ZMConsistency(zmPeriods: zmPeriods, ustvaPeriods: ustvaPeriods, comparisons: comparisons)
    }
}
