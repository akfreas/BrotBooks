import BrotBooksKit
import Foundation
import Testing
@testable import EricKit

typealias Fixtures = StubVatSubmitter.Fixtures

/// The SDK's test certificate (`test-softidnr-pse.pfx`, PIN 123456) from `ERIC_TEST_PFX`, or nil.
let testCertificate: URL? = ProcessInfo.processInfo.environment["ERIC_TEST_PFX"].map { URL(filePath: $0) }
let testCertificatePIN = "123456"
let ericVendored = FileManager.default.fileExists(atPath: vendoredERiC.appending(path: "libericapi.dylib").path)

// MARK: - Offline

struct ElsterServerAnswerTests {
    @Test func parsesTheRejectionOfTheTestServer() throws {
        let answer = try #require(ElsterServerAnswer.parse(Fixtures.rejectedHerstellerID))
        #expect(answer.transferTicket == "eh2881d1ry5uyb4j1jp72511y7wkp4t9")
        #expect(answer.transferHeader == .init(
            code: "601015001", text: "Es ist ein Fehler bei der Verfahrenspruefung aufgetreten - HerstellerID ist nicht zugelassen."))
        #expect(answer.nutzdaten.isEmpty)
        #expect(!answer.isAccepted)
        #expect(answer.firstError?.code == "601015001")
    }

    @Test func parsesTheAcceptedAnswerWithItsNutzdatenHeader() throws {
        let answer = try #require(ElsterServerAnswer.parse(Fixtures.accepted))
        #expect(answer.transferTicket == Fixtures.acceptedTicket)
        #expect(answer.transferHeader == .init(code: "0", text: "Daten wurden erfolgreich angenommen."))
        #expect(answer.nutzdaten == [.init(code: "0", text: "Daten wurden erfolgreich angenommen.")])
        #expect(answer.isAccepted)
        #expect(answer.firstError == nil)
    }

    @Test func aNutzdatenHeaderErrorIsAnError() throws {
        let xml = Fixtures.accepted.replacingOccurrences(
            of: "<NutzdatenTicket>1</NutzdatenTicket><Empfaenger id=\"F\">1096</Empfaenger><RC><Rueckgabe><Code>0</Code>",
            with: "<NutzdatenTicket>1</NutzdatenTicket><Empfaenger id=\"F\">1096</Empfaenger><RC><Rueckgabe><Code>570001001</Code>")
        let answer = try #require(ElsterServerAnswer.parse(xml))
        #expect(!answer.isAccepted)
        #expect(answer.firstError?.code == "570001001")
    }

    @Test func emptyOrBrokenAnswersDoNotParse() {
        #expect(ElsterServerAnswer.parse("") == nil)
        #expect(ElsterServerAnswer.parse("<Elster><TransferHeader>") == nil)
        #expect(ElsterServerAnswer.parse(Fixtures.timeoutWithTicket)?.transferTicket == Fixtures.timeoutTicket)
        #expect(ElsterServerAnswer.parse(Fixtures.timeoutWithTicket)?.transferHeader == nil)
    }
}

struct EricSendOutcomeTests {
    @Test func successIsAcceptedWithTicket() {
        #expect(EricSendOutcome.classify(StubVatSubmitter.result(.success))
                == .accepted(ticket: Fixtures.acceptedTicket, text: "Daten wurden erfolgreich angenommen."))
    }

    /// The real answer of the test server: rc 610101210 and 601015001 in the transfer header.
    @Test func serverRejectionKeepsTheServersCodeTextAndTicket() {
        let result = EricSendResult(code: 610101210, errorText: "Fehler im Transferheader.",
                                    serverAnswer: Fixtures.rejectedHerstellerID)
        let outcome = EricSendOutcome.classify(result)
        #expect(outcome == .rejected(
            code: "601015001", text: "Es ist ein Fehler bei der Verfahrenspruefung aufgetreten - HerstellerID ist nicht zugelassen.",
            ticket: "eh2881d1ry5uyb4j1jp72511y7wkp4t9"))
        #expect(outcome.reachedServer)
        #expect(EricSendOutcome.classify(StubVatSubmitter.result(.rejected)) == outcome)
        // The server's code decides even when ERiC itself reported OK.
        #expect(EricSendOutcome.classify(EricSendResult(code: 0, serverAnswer: Fixtures.rejectedHerstellerID)) == outcome)
    }

    @Test func pinErrors() {
        #expect(EricSendOutcome.classify(StubVatSubmitter.result(.pinWrong)) == .pinWrong)
        #expect(EricSendOutcome.classify(EricSendResult(code: 610201107)) == .pinLocked)
        #expect(!EricSendOutcome.pinWrong.reachedServer)
    }

    @Test func timeoutsAreUncertainAndKeepAnyTicket() {
        #expect(EricSendOutcome.classify(StubVatSubmitter.result(.timeoutWithTicket))
                == .uncertain(ticket: Fixtures.timeoutTicket, code: 610101279,
                              text: "Von der Clearingstelle konnte keine Antwort empfangen werden."))
        #expect(EricSendOutcome.classify(StubVatSubmitter.result(.timeoutWithoutTicket))
                == .uncertain(ticket: nil, code: 610101278, text: "Zu den Servern konnte keine Verbindung aufgebaut werden."))
        #expect(EricSendOutcome.classify(EricSendResult(code: 610101271)) == .uncertain(ticket: nil, code: 610101271, text: nil))
        // Even a timeout code with a rejecting answer stays uncertain: never assume either way.
        #expect(EricSendOutcome.classify(EricSendResult(code: 610101279, serverAnswer: Fixtures.rejectedHerstellerID))
                == .uncertain(ticket: "eh2881d1ry5uyb4j1jp72511y7wkp4t9", code: 610101279, text: nil))
        #expect(EricSendOutcome.uncertain(ticket: nil, code: 0, text: nil).reachedServer)
    }

    @Test func okWithoutAReadableAnswerIsUncertain() {
        #expect(EricSendOutcome.classify(EricSendResult(code: 0)) == .uncertain(ticket: nil, code: 0, text: nil))
        #expect(EricSendOutcome.classify(EricSendResult(code: 0, serverAnswer: Fixtures.timeoutWithTicket))
                == .uncertain(ticket: Fixtures.timeoutTicket, code: 0, text: nil))
    }

    @Test func validationErrorsMeanNothingWasSent() {
        let validation = EricValidationResult(code: 610001002, errors: [.init(text: "Kz35 ohne Kz36")])
        let outcome = EricSendOutcome.classify(EricSendResult(code: 610001002, validation: validation))
        #expect(outcome == .validationFailed(validation))
        #expect(!outcome.reachedServer)
    }

    @Test func otherErrorsFailUnlessTheServerAnsweredWithATicket() {
        #expect(EricSendOutcome.classify(EricSendResult(code: 610301001, errorText: "Schemafehler"))
                == .failed(code: 610301001, text: "Schemafehler"))
        #expect(EricSendOutcome.classify(EricSendResult(code: 610101200, serverAnswer: Fixtures.timeoutWithTicket))
                == .uncertain(ticket: Fixtures.timeoutTicket, code: 610101200, text: nil))
    }
}

struct StubVatSubmitterTests {
    @Test func reportsProgressAndReturnsTheScenario() async throws {
        let steps = Steps()
        let stub = StubVatSubmitter(scenario: .success, stepDelay: .milliseconds(1))
        #expect(stub.isStub)
        let result = try await stub.submit(EricSendRequest(xml: "<Elster/>", datenartVersion: "UStVA_2026",
                                                           certificate: Data(), pin: "")) { steps.append($0) }
        #expect(result == StubVatSubmitter.result(.success))
        #expect(steps.values.compactMap(\.step) == [.reading, .validating, .sending, .printing, .printing])
        #expect(steps.values.last?.fraction == 1)
        let pdf = try #require(result.pdf)
        #expect(pdf.starts(with: Data("%PDF-1.4".utf8)))
        #expect(String(decoding: pdf, as: UTF8.self).contains(Fixtures.acceptedTicket))
    }

    final class Steps: @unchecked Sendable {
        private let lock = NSLock()
        private var stored: [EricProgress] = []
        var values: [EricProgress] { lock.withLock { stored } }
        func append(_ progress: EricProgress) { lock.withLock { stored.append(progress) } }
    }
}

struct EricCertificateInfoTests {
    @Test func parsesTheReferenceExample() throws {
        let xml = """
            <EricHoleZertifikatEigenschaften xmlns="http://www.elster.de/EricXML/2.0/EricHoleZertifikatEigenschaften">
              <Signaturzertifikateigenschaften>
                <AusgestelltAm>220817152116Z</AusgestelltAm>
                <GueltigBis>230817152116Z</GueltigBis>
                <Signaturalgorithmus>sha1WithRSAEncryption(1.2.840.113549.1.1.5)</Signaturalgorithmus>
                <PublicKeyMD5>6b8b191936677957fe74103198e77f4e</PublicKeyMD5>
                <PublicKeySHA1>884b0dfe2e10221a2aedd28c986cf34db0f1d932</PublicKeySHA1>
                <PublicKeyBitLength>2048</PublicKeyBitLength>
                <Issuer>
                  <Info><Name>CN</Name><Wert>ElsterSoftCA</Wert></Info>
                  <Info><Name>OU</Name><Wert>CA</Wert></Info>
                </Issuer>
                <Subjekt><Info><Name>CN</Name><Wert>1000872896</Wert></Info></Subjekt>
                <Identifikationsmerkmaltyp>Steuernummer</Identifikationsmerkmaltyp>
                <Registrierertyp>Person</Registrierertyp>
                <Verifikationsart>Postweg</Verifikationsart>
                <TokenTyp>Software</TokenTyp>
                <Testzertifikat>true</Testzertifikat>
              </Signaturzertifikateigenschaften>
            </EricHoleZertifikatEigenschaften>
            """
        let info = try #require(EricCertificateInfo.parse(xml))
        #expect(info.holder == "1000872896")
        #expect(info.issuerName == "ElsterSoftCA")
        #expect(info.identificationType == "Steuernummer")
        #expect(info.registrantType == "Person")
        #expect(info.tokenType == "Software")
        #expect(info.isTestCertificate)
        #expect(info.validFrom == utc(2022, 8, 17, 15, 21, 16))
        #expect(info.validUntil == utc(2023, 8, 17, 15, 21, 16))
        #expect(info.expiryWarning(now: utc(2023, 9, 1)) == .expired)
        #expect(info.expiryWarning(now: utc(2023, 8, 1)) == .expiresSoon(days: 16))
        #expect(info.expiryWarning(now: utc(2023, 7, 1)) == nil)
        #expect(EricCertificateInfo.parse("<EricHoleZertifikatEigenschaften/>") == nil)
    }

    @Test func parsesBothTimeFormats() {
        #expect(EricCertificateInfo.parseTime("20090317163811Z") == utc(2009, 3, 17, 16, 38, 11))
        #expect(EricCertificateInfo.parseTime("990317163811Z") == utc(1999, 3, 17, 16, 38, 11))
        #expect(EricCertificateInfo.parseTime("2009031716Z") == utc(2009, 3, 17, 16))
        #expect(EricCertificateInfo.parseTime("20090317163811+0100") == utc(2009, 3, 17, 15, 38, 11))
        #expect(EricCertificateInfo.parseTime("garbage") == nil)
    }

    func utc(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 0, _ min: Int = 0, _ s: Int = 0) -> Date {
        Calendar(identifier: .gregorian).date(from: DateComponents(
            timeZone: TimeZone(identifier: "UTC"), year: y, month: m, day: d, hour: h, minute: min, second: s))!
    }
}

/// The Keychain wrapper against this Mac's Keychain (the login keychain under `swift test`, which has no
/// keychain entitlement), with a service of its own that is removed afterwards.
@Suite(.serialized) struct ElsterKeychainTests {
    @Test func storesReadsAndRemovesCertificateAndPIN() throws {
        let keychain = ElsterKeychain(service: "me.freas.BrotBooks.elster.tests-\(UUID().uuidString)")
        defer { try? keychain.removeAll() }
        print("[keychain] data protection keychain: \(ElsterKeychain.usesDataProtectionKeychain)")
        #expect(try keychain.certificate() == nil)
        #expect(try keychain.pin() == nil)

        try keychain.setCertificate(Data([0x30, 0x82, 0x01]))
        try keychain.setPIN("123456")
        #expect(try keychain.certificate() == Data([0x30, 0x82, 0x01]))
        #expect(try keychain.pin() == "123456")

        // Writing again replaces.
        try keychain.setPIN("654321")
        #expect(try keychain.pin() == "654321")

        // A wrong PIN clears only the PIN.
        try keychain.removePIN()
        #expect(try keychain.pin() == nil)
        #expect(try keychain.certificate() != nil)

        try keychain.removeAll()
        #expect(try keychain.certificate() == nil)
        try keychain.removeAll()  // Removing nothing is fine.
    }
}

// MARK: - Live, offline (nothing is sent)

/// Opens the SDK's test certificate from memory and reads its properties; parses server answers with ERiC.
/// Needs Vendor/ERiC; the certificate tests also need the test certificate in `ERIC_TEST_PFX`.
@Suite(.serialized, .enabled(if: ericVendored, "Vendor/ERiC missing: run scripts/vendor-eric.sh <jar>"))
struct EricCertificateLiveTests {
    static let service = EricService(
        ericDirectory: vendoredERiC,
        logDirectory: FileManager.default.temporaryDirectory.appending(path: "EricKitTests-Cert-\(UUID().uuidString)"))

    @Test(.enabled(if: testCertificate != nil, "test-softidnr-pse.pfx not found: set ERIC_TEST_PFX"))
    func opensTheTestCertificateFromBytes() async throws {
        let data = try Data(contentsOf: try #require(testCertificate))
        let info = try await Self.service.certificateInfo(pkcs12: data, pin: testCertificatePIN)
        print("[cert] holder \(info.holder ?? "-"), issuer \(info.issuerName ?? "-"), valid \(info.validFrom.map(String.init(describing:)) ?? "-") – \(info.validUntil.map(String.init(describing:)) ?? "-"), test \(info.isTestCertificate), token \(info.tokenType ?? "-"), id \(info.identificationType ?? "-")")
        print("[cert] xml \(info.xml)")
        #expect(info.holder?.isEmpty == false)
        #expect(info.issuerName?.isEmpty == false)
        let from = try #require(info.validFrom)
        let until = try #require(info.validUntil)
        #expect(from < until)
        #expect(info.tokenType == "Software")
    }

    @Test(.enabled(if: testCertificate != nil, "test-softidnr-pse.pfx not found: set ERIC_TEST_PFX"))
    func aWrongPINIsReported() async throws {
        let data = try Data(contentsOf: try #require(testCertificate))
        do {
            _ = try await Self.service.certificateInfo(pkcs12: data, pin: "000000")
            Issue.record("A wrong PIN opened the certificate")
        } catch {
            print("[cert] wrong PIN: \(error)")
            guard case .callFailed(_, let code) = error else { Issue.record("\(error)"); return }
            #expect(code == EricCode.pinWrong)
        }
    }

    @Test func ericReadsTheServerAnswersLikeTheParser() async throws {
        let rejected = try await Self.service.serverMessages(answer: Fixtures.rejectedHerstellerID)
        print("[answer] \(rejected)")
        #expect(rejected.transferTicket == "eh2881d1ry5uyb4j1jp72511y7wkp4t9")
        #expect(rejected.transferHeaderCode == "601015001")
        #expect(rejected.transferHeaderText.hasSuffix("HerstellerID ist nicht zugelassen."))
        #expect(rejected.nutzdatenErrors.isEmpty)

        let accepted = try await Self.service.serverMessages(answer: Fixtures.accepted)
        print("[answer] \(accepted)")
        #expect(accepted.transferTicket == Fixtures.acceptedTicket)
        #expect(accepted.transferHeaderCode == "0")
        #expect(accepted.nutzdatenErrors.allSatisfy { $0.code == "0" })
    }
}

// MARK: - Live send (ERIC_LIVE_SEND=1 only)

/// Sends a generated UStVA with the test marker (700000004) to the test Finanzamt 1096, signed with the SDK's test
/// certificate. Runs only with `ERIC_LIVE_SEND=1`, Vendor/ERiC and `ERIC_TEST_PFX`; it contacts the ELSTER test
/// server. Until the Hersteller-ID is activated the server rejects with 601015001.
@Suite(.serialized, .enabled(if: ProcessInfo.processInfo.environment["ERIC_LIVE_SEND"] == "1" && ericVendored
                             && ProcessInfo.processInfo.environment["ERIC_TEST_PFX"] != nil,
                             "Set ERIC_LIVE_SEND=1 and ERIC_TEST_PFX to send to the ELSTER test server"))
struct EricSendLiveTests {
    @Test func sendsATestUStVAToFinanzamt1096() async throws {
        let service = EricService(
            ericDirectory: vendoredERiC,
            logDirectory: FileManager.default.temporaryDirectory.appending(path: "EricKitTests-Send-\(UUID().uuidString)"))
        let configuration = UStVAValidationLiveTests.configuration()
        #expect(configuration.testMode)
        let period = VatPeriod.month(2026, 3)
        let result = UStVAAggregator.aggregate(try UStVAValidationLiveTests.domestic(month: 3), period: period,
                                               configuration: configuration)
        let header = UStVAXML.Header(herstellerID: ProcessInfo.processInfo.environment["ELSTER_HERSTELLER_ID"] ?? "27425",
                                     produktVersion: "1.0", erstellungsdatum: "20261015")
        let xml = UStVAXML.build(period: period, kennzahlen: result.kennzahlen, configuration: configuration, header: header)
        #expect(xml.contains("<Testmerker>700000004</Testmerker>"))

        let pfx = try Data(contentsOf: URL(filePath: ProcessInfo.processInfo.environment["ERIC_TEST_PFX"]!))
        let sent = try await service.send(EricSendRequest(xml: xml, datenartVersion: "UStVA_2026", certificate: pfx,
                                                          pin: testCertificatePIN)) { progress in
            print("[send] progress \(progress)")
        }
        let outcome = EricSendOutcome.classify(sent)
        print("[send] code \(sent.code) \(sent.errorText ?? "")\n[send] answer \(sent.serverAnswer)\n[send] outcome \(outcome)\n[send] \(sent.documents.count) PDF(s)")
        await service.shutdown()
        switch outcome {
        case .accepted(let ticket, _):
            #expect(ticket?.isEmpty == false)
            #expect(sent.pdf?.starts(with: Data("%PDF".utf8)) == true)
        case .rejected(let code, _, let ticket):
            // 601015001 while the Hersteller-ID is not activated.
            #expect(ticket?.isEmpty == false)
            print("[send] rejected with \(code)")
        default:
            Issue.record("Unexpected outcome \(outcome)")
        }
    }
}
