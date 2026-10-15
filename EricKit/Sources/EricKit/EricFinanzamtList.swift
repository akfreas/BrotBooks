import Foundation

/// A Finanzamt country from `EricMtHoleFinanzamtLandNummern` (schema `EricHoleFinanzamtLandNummern.xsd`).
public struct EricFinanzamtLand: Sendable, Hashable, Identifiable {
    /// 2 digits; the first two digits of its offices' Bundesfinanzamtsnummern.
    public var nummer: String
    public var name: String

    public var id: String { nummer }

    public init(nummer: String, name: String) {
        self.nummer = nummer
        self.name = name
    }

    /// Parses the return XML. Returns nil if it is not well-formed.
    public static func parse(_ xml: String) -> [EricFinanzamtLand]? {
        EricListReader.parse(xml, item: "FinanzamtLand", key: "FinanzamtLandNummer")?
            .map { EricFinanzamtLand(nummer: $0.key, name: $0.name) }
    }
}

/// A Finanzamt from `EricMtHoleFinanzaemter` (schema `EricHoleFinanzaemter.xsd`).
public struct EricFinanzamt: Sendable, Hashable, Identifiable {
    /// The 4-digit Bundesfinanzamtsnummer.
    public var bufaNummer: String
    public var name: String

    public var id: String { bufaNummer }

    public init(bufaNummer: String, name: String) {
        self.bufaNummer = bufaNummer
        self.name = name
    }

    /// Parses the return XML. Returns nil if it is not well-formed.
    public static func parse(_ xml: String) -> [EricFinanzamt]? {
        EricListReader.parse(xml, item: "Finanzamt", key: "BuFaNummer")?
            .map { EricFinanzamt(bufaNummer: $0.key, name: $0.name) }
    }
}

/// Reads `<item><key>…</key><Name>…</Name></item>` lists.
private final class EricListReader: NSObject, XMLParserDelegate {
    let item: String
    let key: String
    var entries: [(key: String, name: String)] = []
    private var fields: [String: String]?
    private var text = ""

    init(item: String, key: String) {
        self.item = item
        self.key = key
    }

    static func parse(_ xml: String, item: String, key: String) -> [(key: String, name: String)]? {
        let reader = EricListReader(item: item, key: key)
        let parser = XMLParser(data: Data(xml.utf8))
        parser.delegate = reader
        guard parser.parse() else { return nil }
        return reader.entries
    }

    func parser(_ parser: XMLParser, didStartElement element: String, namespaceURI: String?,
                qualifiedName: String?, attributes: [String: String] = [:]) {
        if element == item { fields = [:] }
        text = ""
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        text += string
    }

    func parser(_ parser: XMLParser, didEndElement element: String, namespaceURI: String?, qualifiedName: String?) {
        if element == item, let f = fields {
            if let k = f[key], !k.isEmpty { entries.append((k, f["Name"] ?? "")) }
            fields = nil
        } else if fields != nil {
            fields?[element] = text.trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }
}
