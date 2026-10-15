import Foundation

/// Builds the ElsterAnmeldung XML of the UStVA data type (`UStVA_<year>`): the monthly or quarterly return,
/// the Sondervorauszahlung and the Dauerfristverlängerung application. Modeled on the ERiC samples
/// `Datenarten/ElsterAnmeldung/UStVA/Beispiele/UStVA_2026.xml`, `UStVA_SoVZ_2026.xml` and `UStVA_Df_2026.xml`;
/// elements follow the XSD sequence order of the year's form.
public enum UStVAXML {
    /// Who built the data and when; the same for all three documents.
    public struct Header: Sendable, Equatable {
        /// The 5-digit ELSTER Hersteller-ID (`TransferHeader/HerstellerID` and `Kz09`).
        public var herstellerID: String
        public var produktVersion: String
        /// `YYYYMMDD`.
        public var erstellungsdatum: String

        public init(herstellerID: String, produktVersion: String, erstellungsdatum: String) {
            self.herstellerID = herstellerID
            self.produktVersion = produktVersion
            self.erstellungsdatum = erstellungsdatum
        }
    }

    public static let produktName = "BrotBooks"

    /// The data type version ERiC validates and sends the documents of `year` as, e.g. `UStVA_2026`.
    public static func datenartVersion(year: Int) -> String { "UStVA_\(year)" }

    /// The `Anmeldungssteuern` namespace of `year`.
    public static func namespace(year: Int) -> String {
        "http://finkonsens.de/elster/elsteranmeldung/ustva/v\(year)"
    }

    /// The UStVA for `period` with the filed `kennzahlen`. Identity, Finanzamt and test mode (Testmerker
    /// `700000004`) come from `configuration`.
    public static func build(period: VatPeriod, kennzahlen: Kennzahlen, flags: UStVAFlags = [],
                             configuration: TaxConfiguration, header: Header) -> String {
        let form = kennzahlen.form
        var fields: [(String, String)] = [
            ("Jahr", String(period.year)), ("Zeitraum", period.zeitraum),
        ] + taxNumbers(configuration) + [("Kz09", header.herstellerID)]
        for number in form.elementOrder {
            if UStVAFlags.numbers.contains(where: { $0.number == number }) {
                if flags.contains(number: number) { fields.append(("Kz\(number)", "1")) }
            } else if let kz = Kennzahl(rawValue: number), let text = kennzahlen.text(kz) {
                fields.append((kz.elementName, text))
            }
        }
        return document(year: period.year, steuerfall: "Umsatzsteuervoranmeldung", fields: fields,
                        configuration: configuration, header: header)
    }

    /// The Sondervorauszahlung return for `year`: Kz38 is `amount` in whole euros (truncated, never negative).
    /// Kz22 is not part of this return and is ignored in `flags`.
    public static func buildSondervorauszahlung(year: Int, amount: Decimal, flags: UStVAFlags = [],
                                                configuration: TaxConfiguration, header: Header) -> String {
        let form = configuration.ustvaForms.form(for: year)
        var fields: [(String, String)] = [("Jahr", String(year))] + taxNumbers(configuration)
            + [("Kz09", header.herstellerID)]
        for number in form.sondervorauszahlungElementOrder {
            if UStVAFlags.numbers.contains(where: { $0.number == number }) {
                if flags.contains(number: number) { fields.append(("Kz\(number)", "1")) }
            } else if Kennzahl(rawValue: number) == form.sondervorauszahlung {
                fields.append((form.sondervorauszahlung.elementName,
                               form.text(form.sondervorauszahlung, max(0, amount))))
            }
        }
        return document(year: year, steuerfall: "Umsatzsteuersondervorauszahlung", fields: fields,
                        configuration: configuration, header: header)
    }

    /// The application for a Dauerfristverlängerung for `year` (quarterly filers; monthly filers apply with
    /// the Sondervorauszahlung).
    public static func buildDauerfristverlaengerung(year: Int, configuration: TaxConfiguration,
                                                    header: Header) -> String {
        document(year: year, steuerfall: "Dauerfristverlaengerung",
                 fields: [("Jahr", String(year))] + taxNumbers(configuration) + [("Kz09", header.herstellerID)],
                 configuration: configuration, header: header)
    }

    /// `Steuernummer`, then `WIdNr` when a well-formed W-IdNr. is configured. The schema takes only `DE` plus nine
    /// digits, so a distinguishing suffix (`-00001`) is left out.
    static func taxNumbers(_ configuration: TaxConfiguration) -> [(String, String)] {
        var fields = [("Steuernummer", configuration.identity.steuernummer)]
        if let wIdNr = WIdNr.base(configuration.identity.wIdNr) { fields.append(("WIdNr", wIdNr)) }
        return fields
    }

    // MARK: Document

    static func document(year: Int, steuerfall: String, fields: [(String, String)], configuration: TaxConfiguration,
                         header: Header) -> String {
        let id = configuration.identity
        let address = Address(street: id.street, houseNumber: id.houseNumber)
        var x = XMLWriter()
        x.line(#"<?xml version="1.0" encoding="UTF-8"?>"#)
        x.open("Elster", attributes: [("xmlns", "http://www.elster.de/elsterxml/schema/v11")])
        x.open("TransferHeader", attributes: [("version", "11")])
        x.element("Verfahren", "ElsterAnmeldung")
        x.element("DatenArt", "UStVA")
        x.element("Vorgang", "send-Auth")
        if configuration.testMode { x.element("Testmerker", "700000004") }
        x.element("HerstellerID", header.herstellerID)
        x.element("DatenLieferant", [id.name, id.street, address.number ?? "", address.suffix ?? "", "",
                                     id.postalCode, id.city, "Deutschland", id.phone, id.email]
            .joined(separator: ";"))
        x.open("Datei")
        x.element("Verschluesselung", "CMSEncryptedData")
        x.element("Kompression", "GZIP")
        x.close("Datei")
        x.close("TransferHeader")
        x.open("DatenTeil")
        x.open("Nutzdatenblock")
        x.open("NutzdatenHeader", attributes: [("version", "11")])
        x.element("NutzdatenTicket", "1")
        x.element("Empfaenger", id.finanzamt, attributes: [("id", "F")])
        x.open("Hersteller")
        x.element("ProduktName", produktName)
        x.element("ProduktVersion", header.produktVersion)
        x.close("Hersteller")
        x.close("NutzdatenHeader")
        x.open("Nutzdaten")
        x.open("Anmeldungssteuern", attributes: [("xmlns", namespace(year: year)), ("version", String(year))])
        x.element("Erstellungsdatum", header.erstellungsdatum)
        x.open("DatenLieferant")
        x.optional("Name", id.name)
        x.optional("Strasse", [id.street, id.houseNumber].filter { !$0.isEmpty }.joined(separator: " "))
        x.optional("PLZ", id.postalCode)
        x.optional("Ort", id.city)
        x.optional("Telefon", id.phone)
        x.optional("Email", id.email)
        x.close("DatenLieferant")
        x.open("Steuerfall")
        x.open("Unternehmer")
        x.optional("Name", id.name)
        x.optional("Str", address.street)
        x.optional("Hausnummer", address.number)
        x.optional("HNrZusatz", address.suffix)
        x.optional("Ort", id.city)
        x.optional("PLZ", id.postalCode)
        x.optional("Telefon", id.phone)
        x.optional("Email", id.email)
        x.close("Unternehmer")
        x.open(steuerfall)
        for (name, value) in fields { x.element(name, value) }
        x.close(steuerfall)
        x.close("Steuerfall")
        x.close("Anmeldungssteuern")
        x.close("Nutzdaten")
        x.close("Nutzdatenblock")
        x.close("DatenTeil")
        x.close("Elster")
        return x.text
    }

    /// The schema's `Hausnummer` is digits only; a suffix ("12a", "12 b") goes into `HNrZusatz`. A house number
    /// without leading digits stays with the street.
    struct Address: Equatable {
        var street: String?
        var number: String?
        var suffix: String?

        init(street: String, houseNumber: String) {
            let house = houseNumber.trimmingCharacters(in: .whitespaces)
            let digits = String(house.prefix { $0.isASCII && $0.isNumber })
            if digits.isEmpty {
                self.street = [street, house].filter { !$0.isEmpty }.joined(separator: " ")
            } else {
                self.street = street
                self.number = digits
                let rest = house.dropFirst(digits.count).trimmingCharacters(in: .whitespaces)
                self.suffix = rest.isEmpty ? nil : rest
            }
            if self.street?.isEmpty == true { self.street = nil }
        }
    }

    /// Escapes text for XML content and attribute values.
    public static func escape(_ text: String) -> String {
        var out = ""
        out.reserveCapacity(text.count)
        for ch in text {
            switch ch {
            case "&": out += "&amp;"
            case "<": out += "&lt;"
            case ">": out += "&gt;"
            case "\"": out += "&quot;"
            case "'": out += "&apos;"
            default: out.append(ch)
            }
        }
        return out
    }

    struct XMLWriter {
        var text = ""
        var depth = 0

        mutating func line(_ s: String) { text += String(repeating: "    ", count: depth) + s + "\n" }

        static func attributes(_ attrs: [(String, String)]) -> String {
            attrs.map { " \($0.0)=\"\(UStVAXML.escape($0.1))\"" }.joined()
        }

        mutating func open(_ name: String, attributes attrs: [(String, String)] = []) {
            line("<\(name)\(Self.attributes(attrs))>")
            depth += 1
        }

        mutating func close(_ name: String) {
            depth -= 1
            line("</\(name)>")
        }

        mutating func element(_ name: String, _ value: String, attributes attrs: [(String, String)] = []) {
            line("<\(name)\(Self.attributes(attrs))>\(UStVAXML.escape(value))</\(name)>")
        }

        /// Writes the element only when `value` is non-empty.
        mutating func optional(_ name: String, _ value: String?) {
            let trimmed = value?.trimmingCharacters(in: .whitespaces) ?? ""
            if !trimmed.isEmpty { element(name, trimmed) }
        }
    }
}
