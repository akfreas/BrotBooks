import Foundation

/// A transport that never contacts ELSTER: it answers every send with a canned result for `scenario`, after
/// reporting progress like ERiC. The answers are real server answers (or shaped like them), so the result goes
/// through the same classification and filing records as a real send.
public struct StubVatSubmitter: VatSubmitting {
    public enum Scenario: String, Sendable, CaseIterable {
        /// Accepted, with a ticket and a protocol PDF.
        case success
        /// Rejected with 601015001 "HerstellerID ist nicht zugelassen" (a real answer of the test server).
        case rejected
        /// `ERIC_CRYPT_E_PIN_WRONG`.
        case pinWrong
        /// `ERIC_TRANSFER_ERR_NORESPONSE` with an answer that carries a transfer ticket.
        case timeoutWithTicket
        /// `ERIC_TRANSFER_ERR_CONNECTSERVER` without any answer.
        case timeoutWithoutTicket
    }

    public var scenario: Scenario
    /// Pause between progress steps.
    public var stepDelay: Duration

    public init(scenario: Scenario = .success, stepDelay: Duration = .milliseconds(250)) {
        self.scenario = scenario
        self.stepDelay = stepDelay
    }

    public var isStub: Bool { true }

    public func submit(_ request: EricSendRequest, progress: @escaping @Sendable (EricProgress) -> Void) async throws
        -> EricSendResult {
        let steps: [EricProgress.Step] = scenario == .pinWrong ? [.reading] : [.reading, .validating, .sending, .printing]
        for (index, step) in steps.enumerated() {
            progress(EricProgress(step: step, position: UInt32(index), maximum: UInt32(steps.count), isOverall: true))
            try await Task.sleep(for: stepDelay)
        }
        progress(EricProgress(step: steps.last, position: UInt32(steps.count), maximum: UInt32(steps.count),
                              isOverall: true))
        return Self.result(scenario)
    }

    /// The canned result of `scenario`.
    public static func result(_ scenario: Scenario) -> EricSendResult {
        switch scenario {
        case .success:
            return EricSendResult(code: EricCode.ok, serverAnswer: Fixtures.accepted,
                                  documents: [.init(name: "Protokoll", data: protocolPDF(ticket: Fixtures.acceptedTicket))])
        case .rejected:
            return EricSendResult(code: EricCode.transferHeaderError,
                                  errorText: "Fehler im Transferheader. Der ELSTER-Annahmeserver hat einen Fehler zurückgemeldet. Bitte werten Sie die Serverantwort aus.",
                                  serverAnswer: Fixtures.rejectedHerstellerID)
        case .pinWrong:
            return EricSendResult(code: EricCode.pinWrong,
                                  errorText: "eSigner: Es wurde ein falsches Passwort bzw. eine falsche PIN angegeben.")
        case .timeoutWithTicket:
            return EricSendResult(code: EricCode.noResponse,
                                  errorText: "Von der Clearingstelle konnte keine Antwort empfangen werden.",
                                  serverAnswer: Fixtures.timeoutWithTicket)
        case .timeoutWithoutTicket:
            return EricSendResult(code: EricCode.connectError,
                                  errorText: "Zu den Servern konnte keine Verbindung aufgebaut werden.")
        }
    }

    /// Server answers. `rejectedHerstellerID` is the test server's answer to a send with the not yet activated
    /// Hersteller-ID 27425; `accepted` is the same answer with code 0 in the transfer header and a Nutzdaten
    /// header (EHB 6.2.5.1); `timeoutWithTicket` has a ticket but no result.
    public enum Fixtures {
        public static let rejectedTicket = "eh2881d1ry5uyb4j1jp72511y7wkp4t9"
        public static let acceptedTicket = "eh2881d1ry5uyb4j1jp72511y7wkp4t9"
        public static let timeoutTicket = "eh9o2ks7dw1k3mzy0b6r4xq5c8nfu2ta"

        public static let rejectedHerstellerID = """
            <Elster xmlns="http://www.elster.de/elsterxml/schema/v11"><TransferHeader version="11"><Verfahren>ElsterAnmeldung</Verfahren><DatenArt>UStVA</DatenArt><Vorgang>send-Auth</Vorgang><TransferTicket>eh2881d1ry5uyb4j1jp72511y7wkp4t9</TransferTicket><Testmerker>700000004</Testmerker><HerstellerID>27425</HerstellerID><DatenLieferant>MIAG…</DatenLieferant><EingangsDatum>20261015073840</EingangsDatum><Datei>…</Datei><RC><Rueckgabe><Code>601015001</Code><Text>Es ist ein Fehler bei der Verfahrenspruefung aufgetreten - HerstellerID ist nicht zugelassen. </Text></Rueckgabe><Stack><Code></Code><Text></Text></Stack></RC></TransferHeader><DatenTeil></DatenTeil></Elster>
            """

        public static let accepted = """
            <Elster xmlns="http://www.elster.de/elsterxml/schema/v11"><TransferHeader version="11"><Verfahren>ElsterAnmeldung</Verfahren><DatenArt>UStVA</DatenArt><Vorgang>send-Auth</Vorgang><TransferTicket>eh2881d1ry5uyb4j1jp72511y7wkp4t9</TransferTicket><Testmerker>700000004</Testmerker><HerstellerID>27425</HerstellerID><DatenLieferant>MIAG…</DatenLieferant><EingangsDatum>20261015073840</EingangsDatum><Datei>…</Datei><RC><Rueckgabe><Code>0</Code><Text>Daten wurden erfolgreich angenommen.</Text></Rueckgabe><Stack><Code></Code><Text></Text></Stack></RC></TransferHeader><DatenTeil><Nutzdatenblock><NutzdatenHeader version="11"><NutzdatenTicket>1</NutzdatenTicket><Empfaenger id="F">1096</Empfaenger><RC><Rueckgabe><Code>0</Code><Text>Daten wurden erfolgreich angenommen.</Text></Rueckgabe><Stack><Code></Code><Text></Text></Stack></RC></NutzdatenHeader><Nutzdaten></Nutzdaten></Nutzdatenblock></DatenTeil></Elster>
            """

        public static let timeoutWithTicket = """
            <Elster xmlns="http://www.elster.de/elsterxml/schema/v11"><TransferHeader version="11"><Verfahren>ElsterAnmeldung</Verfahren><DatenArt>UStVA</DatenArt><Vorgang>send-Auth</Vorgang><TransferTicket>eh9o2ks7dw1k3mzy0b6r4xq5c8nfu2ta</TransferTicket><Testmerker>700000004</Testmerker><HerstellerID>27425</HerstellerID></TransferHeader><DatenTeil></DatenTeil></Elster>
            """
    }

    /// A one-page PDF that stands in for ERiC's protocol.
    public static func protocolPDF(ticket: String) -> Data {
        let lines = [
            "Stub transmission protocol (no data was sent)",
            "Transfer ticket: \(ticket)",
            "Daten wurden erfolgreich angenommen.",
        ]
        var content = "BT /F1 14 Tf 56 780 Td 18 TL\n"
        for line in lines {
            let escaped = line.replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "(", with: "\\(").replacingOccurrences(of: ")", with: "\\)")
            content += "(\(escaped)) Tj T*\n"
        }
        content += "ET"
        let objects = [
            "<< /Type /Catalog /Pages 2 0 R >>",
            "<< /Type /Pages /Kids [3 0 R] /Count 1 >>",
            "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 595 842] /Resources << /Font << /F1 4 0 R >> >> /Contents 5 0 R >>",
            "<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>",
            "<< /Length \(content.utf8.count) >>\nstream\n\(content)\nendstream",
        ]
        var pdf = "%PDF-1.4\n"
        var offsets: [Int] = []
        for (index, object) in objects.enumerated() {
            offsets.append(pdf.utf8.count)
            pdf += "\(index + 1) 0 obj\n\(object)\nendobj\n"
        }
        let xref = pdf.utf8.count
        pdf += "xref\n0 \(objects.count + 1)\n0000000000 65535 f \n"
        for offset in offsets { pdf += String(format: "%010d 00000 n \n", offset) }
        pdf += "trailer\n<< /Size \(objects.count + 1) /Root 1 0 R >>\nstartxref\n\(xref)\n%%EOF\n"
        return Data(pdf.utf8)
    }
}
