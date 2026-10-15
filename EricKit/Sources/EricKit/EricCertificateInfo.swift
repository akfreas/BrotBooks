import Foundation

/// The properties of an ELSTER certificate from `EricMtHoleZertifikatEigenschaften` (schema
/// `EricHoleZertifikatEigenschaften.xsd`, version 2.0). A software certificate (.pfx) holds a signature and an
/// encryption certificate; the signature certificate's properties are shown, the encryption certificate's when
/// there is none.
public struct EricCertificateInfo: Sendable, Equatable {
    /// One `Info` name/value pair of the issuer or subject, e.g. `CN` = `ElsterSoftCA`.
    public struct NameValue: Sendable, Equatable {
        public var name: String
        public var value: String

        public init(name: String, value: String) {
            self.name = name
            self.value = value
        }
    }

    /// `AusgestelltAm`: the certificate is valid from this time.
    public var validFrom: Date?
    /// `GueltigBis`: the certificate is valid until this time.
    public var validUntil: Date?
    public var issuer: [NameValue]
    public var subject: [NameValue]
    /// `Identifikationsmerkmaltyp`, e.g. `Steuernummer` or `Identifikationsnummer`.
    public var identificationType: String?
    /// `Registrierertyp`, e.g. `Person` or `Organisation`.
    public var registrantType: String?
    /// `TokenTyp`, e.g. `Software`.
    public var tokenType: String?
    /// `Testzertifikat`: a certificate of an ELSTER test account.
    public var isTestCertificate: Bool
    /// The properties document as ERiC returned it.
    public var xml: String

    public init(validFrom: Date?, validUntil: Date?, issuer: [NameValue], subject: [NameValue],
                identificationType: String? = nil, registrantType: String? = nil, tokenType: String? = nil,
                isTestCertificate: Bool = false, xml: String = "") {
        self.validFrom = validFrom
        self.validUntil = validUntil
        self.issuer = issuer
        self.subject = subject
        self.identificationType = identificationType
        self.registrantType = registrantType
        self.tokenType = tokenType
        self.isTestCertificate = isTestCertificate
        self.xml = xml
    }

    /// The holder: the subject's common name. For an ELSTER software certificate that is the ID of the ELSTER
    /// account it was issued for (API reference of `EricMtHoleZertifikatEigenschaften`).
    public var holder: String? { value("CN", in: subject) ?? subject.first?.value }

    /// The issuer's common name, else its organization.
    public var issuerName: String? { value("CN", in: issuer) ?? value("O", in: issuer) ?? issuer.first?.value }

    /// Days the certificate expires within, at which `expiryWarning` starts.
    public static let expiryWarningDays = 30

    /// Whether the certificate has expired or expires within `expiryWarningDays` on `now`.
    public func expiryWarning(now: Date = Date()) -> ExpiryWarning? {
        guard let validUntil else { return nil }
        if validUntil <= now { return .expired }
        let days = Calendar(identifier: .gregorian).dateComponents([.day], from: now, to: validUntil).day ?? 0
        return days < Self.expiryWarningDays ? .expiresSoon(days: days) : nil
    }

    public enum ExpiryWarning: Sendable, Equatable {
        case expired
        case expiresSoon(days: Int)
    }

    private func value(_ name: String, in pairs: [NameValue]) -> String? {
        pairs.first { $0.name.caseInsensitiveCompare(name) == .orderedSame }?.value
    }

    /// Parses the return XML; nil when it is not well-formed or holds no certificate.
    public static func parse(_ xml: String) -> EricCertificateInfo? {
        guard let root = XMLNode.parse(xml),
              let properties = root.child("Signaturzertifikateigenschaften")
                ?? root.child("Verschluesselungszertifikateigenschaften") else { return nil }
        func pairs(_ name: String) -> [NameValue] {
            properties.child(name)?.all("Info").map {
                NameValue(name: $0.child("Name")?.text ?? "", value: $0.child("Wert")?.text ?? "")
            } ?? []
        }
        func text(_ name: String) -> String? {
            properties.child(name).map(\.text).flatMap { $0.isEmpty ? nil : $0 }
        }
        return EricCertificateInfo(
            validFrom: text("AusgestelltAm").flatMap(parseTime), validUntil: text("GueltigBis").flatMap(parseTime),
            issuer: pairs("Issuer"), subject: pairs("Subjekt"), identificationType: text("Identifikationsmerkmaltyp"),
            registrantType: text("Registrierertyp"), tokenType: text("TokenTyp"),
            isTestCertificate: text("Testzertifikat") == "true", xml: xml)
    }

    /// An ASN.1 time as ERiC writes it, in UTC: `YYMMDDHHMMSSZ` (UTCTime, as in the API reference's example
    /// `220817152116Z`) or `YYYYMMDDHHMMSSZ` (GeneralizedTime, as in the schema's example `20090317163811Z`),
    /// optionally with fractional seconds or an offset `+HHMM`/`-HHMM`.
    static func parseTime(_ text: String) -> Date? {
        guard let match = text.wholeMatch(of: /([0-9]+)(?:[.,][0-9]*)?(Z|[+-][0-9]{2}(?:[0-9]{2})?)?/) else {
            return nil
        }
        let digits = Array(match.output.1)
        var c = DateComponents()
        c.timeZone = TimeZone(identifier: "UTC")
        func number(_ range: Range<Int>) -> Int? {
            range.upperBound <= digits.count ? Int(String(digits[range])) : nil
        }
        let rest: Int
        switch digits.count {
        case 12:  // UTCTime: YYMMDDHHMMSS; years 50–99 are 19xx (RFC 5280).
            guard let yy = number(0..<2) else { return nil }
            c.year = yy >= 50 ? 1900 + yy : 2000 + yy
            rest = 2
        case 10, 14:  // GeneralizedTime: YYYYMMDDHH[MMSS]
            c.year = number(0..<4)
            rest = 4
        default:
            return nil
        }
        c.month = number(rest..<rest + 2)
        c.day = number(rest + 2..<rest + 4)
        c.hour = number(rest + 4..<rest + 6)
        c.minute = number(rest + 6..<rest + 8) ?? 0
        c.second = number(rest + 8..<rest + 10) ?? 0
        if let zone = match.output.2, zone != "Z" {
            let sign = zone.hasPrefix("-") ? -1 : 1
            let hours = Int(zone.dropFirst().prefix(2)) ?? 0
            let minutes = Int(zone.dropFirst(3).prefix(2)) ?? 0
            c.timeZone = TimeZone(secondsFromGMT: sign * (hours * 3600 + minutes * 60))
        }
        return Calendar(identifier: .gregorian).date(from: c)
    }
}
