import CEric
import Foundation

/// The outcome of `EricService.validate`: ERiC's return code plus the rule errors and hints it reported
/// (schema `EricBearbeiteVorgang.xsd`).
public struct EricValidationResult: Sendable, Equatable {
    /// One `FehlerRegelpruefung` (error) or `Hinweis` (hint).
    public struct Message: Sendable, Equatable, CustomStringConvertible {
        public var nutzdatenticket: String?
        /// The field's identifier, e.g. `/Anmeldungssteuern[1]/Steuerfall[1]/...`.
        public var feldidentifikator: String?
        public var regelName: String?
        /// `FachlicheFehlerId` for errors, `FachlicheHinweisId` for hints.
        public var fachlicheID: String?
        public var vordruckZeilennummer: String?
        public var text: String

        public init(nutzdatenticket: String? = nil, feldidentifikator: String? = nil, regelName: String? = nil,
                    fachlicheID: String? = nil, vordruckZeilennummer: String? = nil, text: String) {
            self.nutzdatenticket = nutzdatenticket
            self.feldidentifikator = feldidentifikator
            self.regelName = regelName
            self.fachlicheID = fachlicheID
            self.vordruckZeilennummer = vordruckZeilennummer
            self.text = text
        }

        public var description: String {
            [regelName, fachlicheID, feldidentifikator].compactMap { $0 }.joined(separator: " ") + ": " + text
        }
    }

    /// ERiC's return code: `ERIC_OK`, `ERIC_GLOBAL_PRUEF_FEHLER` (rule errors), `ERIC_GLOBAL_HINWEISE` (hints
    /// only) or another error code (e.g. a schema error), see eric_fehlercodes.h.
    public var code: Int32
    public var errors: [Message]
    public var hints: [Message]
    /// `EricMtHoleFehlerText` for codes other than the three above.
    public var errorText: String?
    /// The return buffer as ERiC wrote it.
    public var response: String

    public init(code: Int32, errors: [Message] = [], hints: [Message] = [], errorText: String? = nil,
                response: String = "") {
        self.code = code
        self.errors = errors
        self.hints = hints
        self.errorText = errorText
        self.response = response
    }

    /// The data passed validation: no errors, possibly hints.
    public var isValid: Bool {
        (code == ERIC_OK.rawValue || code == Int32(ERIC_GLOBAL_HINWEISE.rawValue)) && errors.isEmpty
    }

    /// Parses the return buffer of `EricMtBearbeiteVorgang`. Returns nil if it is not well-formed XML.
    static func parse(_ xml: String) -> (errors: [Message], hints: [Message])? {
        if xml.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return ([], []) }
        let reader = ResponseReader()
        let parser = XMLParser(data: Data(xml.utf8))
        parser.delegate = reader
        guard parser.parse() else { return nil }
        return (reader.errors, reader.hints)
    }
}

private final class ResponseReader: NSObject, XMLParserDelegate {
    var errors: [EricValidationResult.Message] = []
    var hints: [EricValidationResult.Message] = []
    private var fields: [String: String]?
    private var text = ""

    func parser(_ parser: XMLParser, didStartElement element: String, namespaceURI: String?,
                qualifiedName: String?, attributes: [String: String] = [:]) {
        if element == "FehlerRegelpruefung" || element == "Hinweis" { fields = [:] }
        text = ""
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        text += string
    }

    func parser(_ parser: XMLParser, didEndElement element: String, namespaceURI: String?, qualifiedName: String?) {
        if element == "FehlerRegelpruefung" || element == "Hinweis", let f = fields {
            let message = EricValidationResult.Message(
                nutzdatenticket: f["Nutzdatenticket"], feldidentifikator: f["Feldidentifikator"],
                regelName: f["RegelName"], fachlicheID: f["FachlicheFehlerId"] ?? f["FachlicheHinweisId"],
                vordruckZeilennummer: f["VordruckZeilennummer"], text: f["Text"] ?? "")
            if element == "Hinweis" { hints.append(message) } else { errors.append(message) }
            fields = nil
        } else if fields != nil {
            fields?[element] = text.trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }
}
