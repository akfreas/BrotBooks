import CEric
import Foundation

/// ERiC's progress during `EricMtBearbeiteVorgang` (EHB 6.4), from the callbacks registered with
/// `EricMtRegistriereGlobalenFortschrittCallback` (overall) and `EricMtRegistriereFortschrittCallback` (within
/// the current step).
public struct EricProgress: Sendable, Equatable {
    /// The processing step (`ERIC_FORTSCHRITTCALLBACK_ID_*`).
    public enum Step: UInt32, Sendable, Equatable {
        case reading = 10, preparing = 20, validating = 30, sending = 40, printing = 50
    }

    /// Nil for an id ERiC adds later.
    public var step: Step?
    public var position: UInt32
    public var maximum: UInt32
    /// True for the overall progress, false for the progress within `step`.
    public var isOverall: Bool

    public init(step: Step?, position: UInt32, maximum: UInt32, isOverall: Bool) {
        self.step = step
        self.position = position
        self.maximum = maximum
        self.isOverall = isOverall
    }

    /// 0…1.
    public var fraction: Double { maximum > 0 ? min(1, Double(position) / Double(maximum)) : 0 }
}

/// What to send: the return's XML with the certificate (PKCS#12 bytes) and its PIN.
public struct EricSendRequest: Sendable {
    public var xml: String
    /// E.g. `UStVA_2026`.
    public var datenartVersion: String
    public var certificate: Data
    public var pin: String

    public init(xml: String, datenartVersion: String, certificate: Data, pin: String) {
        self.xml = xml
        self.datenartVersion = datenartVersion
        self.certificate = certificate
        self.pin = pin
    }
}

/// What came back from a send (`ERIC_VALIDIERE | ERIC_SENDE | ERIC_DRUCKE`, EBV-6), unclassified;
/// `EricSendOutcome.classify` reads it.
public struct EricSendResult: Sendable, Equatable {
    /// ERiC's return code: of `EricMtBearbeiteVorgang`, or of `EricMtZertifikatOeffnenAusBytes` when the
    /// certificate could not be opened (nothing was sent then).
    public var code: Int32
    /// `EricMtHoleFehlerText` for a code other than `ERIC_OK`.
    public var errorText: String?
    /// The rule errors of the local validation, parsed from the return buffer.
    public var validation: EricValidationResult
    /// The ELSTER server's answer XML (`serverantwortXmlPuffer`), unchanged; empty when nothing was received.
    public var serverAnswer: String
    /// The protocol PDF(s) ERiC printed.
    public var documents: [EricPreviewResult.Document]

    public init(code: Int32, errorText: String? = nil, validation: EricValidationResult? = nil, serverAnswer: String = "",
                documents: [EricPreviewResult.Document] = []) {
        self.code = code
        self.errorText = errorText
        self.validation = validation ?? EricValidationResult(code: code, errorText: errorText)
        self.serverAnswer = serverAnswer
        self.documents = documents
    }

    /// The first PDF, or nil when ERiC printed none.
    public var pdf: Data? { documents.first?.data }
}

/// Codes of eric_fehlercodes.h the send path needs.
public enum EricCode {
    public static let ok: Int32 = 0
    public static let pruefFehler: Int32 = 610001002
    /// ERIC_TRANSFER_ERR_XML_THEADER: the server reported an error in the TransferHeader.
    public static let transferHeaderError: Int32 = 610101210
    /// ERIC_TRANSFER_ERR_SEND: an error during the data exchange.
    public static let sendError: Int32 = 610101271
    /// ERIC_TRANSFER_ERR_CONNECTSERVER: no connection to the servers.
    public static let connectError: Int32 = 610101278
    /// ERIC_TRANSFER_ERR_NORESPONSE: no answer from the clearing office.
    public static let noResponse: Int32 = 610101279
    /// ERIC_TRANSFER_ERR_XML_NHEADER: the server reported an error in a NutzdatenHeader.
    public static let nutzdatenHeaderError: Int32 = 610101292
    /// ERIC_CRYPT_E_PIN_WRONG.
    public static let pinWrong: Int32 = 610201106
    /// ERIC_CRYPT_E_PIN_LOCKED.
    public static let pinLocked: Int32 = 610201107

    /// Timeout and connection errors: the data may or may not have reached the server.
    public static let uncertainTransfer: Set<Int32> = [sendError, connectError, noResponse]
}

/// Sends a return. `EricService` sends for real; `StubVatSubmitter` answers from canned server answers so the
/// UI and the filing records can be worked on without network or certificate.
public protocol VatSubmitting: Sendable {
    /// Whether this transport never contacts ELSTER.
    var isStub: Bool { get }
    /// Validates, sends and prints `request`. `progress` is called on ERiC's thread and must return quickly.
    func submit(_ request: EricSendRequest, progress: @escaping @Sendable (EricProgress) -> Void) async throws
        -> EricSendResult
}

/// The transfer header's and the Nutzdaten headers' return codes from `EricMtGetErrormessagesFromXMLAnswer`.
public struct EricServerMessages: Sendable, Equatable {
    public struct Message: Sendable, Equatable {
        public var code: String
        public var text: String

        public init(code: String, text: String) {
            self.code = code
            self.text = text
        }
    }

    public var transferTicket: String
    public var transferHeaderCode: String
    public var transferHeaderText: String
    /// The `Fehler` entries of the Nutzdaten headers (schema `EricGetErrormessagesFromXMLAnswer.xsd`).
    public var nutzdatenErrors: [Message]
}



extension EricService: VatSubmitting {
    public nonisolated var isStub: Bool { false }

    public func submit(_ request: EricSendRequest, progress: @escaping @Sendable (EricProgress) -> Void) async throws
        -> EricSendResult {
        try send(request, progress: progress)
    }

    // MARK: Certificates

    /// Opens the PKCS#12 certificate `pkcs12` with `pin` (`EricMtZertifikatOeffnenAusBytes`, so no file path is
    /// needed) and reads its properties (`EricMtHoleZertifikatEigenschaften`). The bytes stay in memory.
    /// - Throws: `.callFailed(function:code:)`, e.g. with `EricCode.pinWrong` or `EricCode.pinLocked`.
    public func certificateInfo(pkcs12: Data, pin: String) throws(EricError) -> EricCertificateInfo {
        let xml = try withInstance { api, instance throws(EricError) in
            try withCertificate(pkcs12, pin: pin, api: api, instance: instance) { handle throws(EricError) in
                guard let buffer = api.EricMtRueckgabepufferErzeugen(instance) else {
                    throw .callFailed(function: "EricMtRueckgabepufferErzeugen", code: -1)
                }
                defer { _ = api.EricMtRueckgabepufferFreigeben(instance, buffer) }
                let code = pin.withCString { api.EricMtHoleZertifikatEigenschaften(instance, handle, $0, buffer) }
                guard code == ERIC_OK.rawValue else {
                    throw .callFailed(function: "EricMtHoleZertifikatEigenschaften", code: code)
                }
                return api.EricMtRueckgabepufferInhalt(instance, buffer).map { String(cString: $0) } ?? ""
            }
        }
        guard let info = EricCertificateInfo.parse(xml) else {
            throw .malformedResult(function: "EricMtHoleZertifikatEigenschaften")
        }
        return info
    }

    /// Opens the certificate, runs `body` with its handle and closes it again.
    private func withCertificate<T>(_ pkcs12: Data, pin: String, api: CEricAPI, instance: EricInstanzHandle,
                                    _ body: (EricZertifikatHandle) throws(EricError) -> T) throws(EricError) -> T {
        var handle: EricZertifikatHandle = 0
        let code = pkcs12.withUnsafeBytes { bytes in
            pin.withCString { pinPointer in
                api.EricMtZertifikatOeffnenAusBytes(instance, &handle, bytes.baseAddress?.assumingMemoryBound(to: CChar.self),
                                                    UInt32(bytes.count), pinPointer)
            }
        }
        guard code == ERIC_OK.rawValue else {
            throw .callFailed(function: "EricMtZertifikatOeffnenAusBytes", code: code)
        }
        defer { _ = api.EricMtCloseHandleToCertificate(instance, handle) }
        return try body(handle)
    }

    // MARK: Sending

    /// The footer of the protocol PDF (vendor text only, at most 30 characters).
    public static let protocolFooter = previewFooter

    /// Validates, sends with the certificate (send-Auth) and prints the protocol: `ERIC_VALIDIERE | ERIC_SENDE |
    /// ERIC_DRUCKE`, EBV-6. Never retries. ERiC's codes come back in the result (classify it with
    /// `EricSendOutcome.classify`); only failures to load or call ERiC throw.
    public func send(_ request: EricSendRequest, progress: (@Sendable (EricProgress) -> Void)? = nil)
        throws(EricError) -> EricSendResult {
        try withInstance { api, instance throws(EricError) in
            var handle: EricZertifikatHandle = 0
            let openCode = request.certificate.withUnsafeBytes { bytes in
                request.pin.withCString { pin in
                    api.EricMtZertifikatOeffnenAusBytes(instance, &handle,
                                                        bytes.baseAddress?.assumingMemoryBound(to: CChar.self),
                                                        UInt32(bytes.count), pin)
                }
            }
            guard openCode == ERIC_OK.rawValue else {
                let text = errorText(openCode, api: api, instance: instance)
                Self.log.error("Opening the certificate failed: \(openCode) \(text ?? "", privacy: .public)")
                return EricSendResult(code: openCode, errorText: text)
            }
            defer { _ = api.EricMtCloseHandleToCertificate(instance, handle) }

            let box = progress.map { Unmanaged.passRetained(ProgressBox($0)) }
            defer { box?.release() }
            if let box {
                _ = api.EricMtRegistriereGlobalenFortschrittCallback(instance, overallProgressCallback, box.toOpaque())
                _ = api.EricMtRegistriereFortschrittCallback(instance, stepProgressCallback, box.toOpaque())
            }
            defer {
                if box != nil {
                    _ = api.EricMtRegistriereGlobalenFortschrittCallback(instance, nil, nil)
                    _ = api.EricMtRegistriereFortschrittCallback(instance, nil, nil)
                }
            }

            guard let buffer = api.EricMtRueckgabepufferErzeugen(instance) else {
                throw .callFailed(function: "EricMtRueckgabepufferErzeugen", code: -1)
            }
            defer { _ = api.EricMtRueckgabepufferFreigeben(instance, buffer) }
            guard let serverBuffer = api.EricMtRueckgabepufferErzeugen(instance) else {
                throw .callFailed(function: "EricMtRueckgabepufferErzeugen", code: -1)
            }
            defer { _ = api.EricMtRueckgabepufferFreigeben(instance, serverBuffer) }

            let collector = UnsafeMutablePointer<CEricPdfCollector>.allocate(capacity: 1)
            collector.initialize(to: CEricPdfCollector())
            defer {
                CEricPdfCollectorFree(collector)
                collector.deallocate()
            }
            let footer = strdup(Self.protocolFooter)
            defer { free(footer) }
            var druck = eric_druck_parameter_t(
                version: 4, vorschau: 0, duplexDruck: 0, pdfName: nil, fussText: footer,
                pdfCallback: CEricPdfCollect, pdfCallbackBenutzerdaten: UnsafeMutableRawPointer(collector))
            let flags = UInt32(ERIC_VALIDIERE.rawValue | ERIC_SENDE.rawValue | ERIC_DRUCKE.rawValue)

            let code = request.pin.withCString { pin in
                var crypto = eric_verschluesselungs_parameter_t(version: 3, zertifikatHandle: handle, pin: pin)
                return request.xml.withCString { data in
                    request.datenartVersion.withCString { version in
                        api.EricMtBearbeiteVorgang(instance, data, version, flags, &druck, &crypto, buffer, serverBuffer)
                    }
                }
            }
            let response = api.EricMtRueckgabepufferInhalt(instance, buffer).map { String(cString: $0) } ?? ""
            let answer = api.EricMtRueckgabepufferInhalt(instance, serverBuffer).map { String(cString: $0) } ?? ""
            let text = code == ERIC_OK.rawValue ? nil : errorText(code, api: api, instance: instance)
            let parsed = EricValidationResult.parse(response)
            let validation = EricValidationResult(code: code, errors: parsed?.errors ?? [], hints: parsed?.hints ?? [],
                                                  errorText: text, response: response)
            let documents = (0..<collector.pointee.count).map { index in
                let document = collector.pointee.documents[index]
                return EricPreviewResult.Document(
                    name: document.name.map { String(cString: $0) } ?? "",
                    data: document.bytes.map { Data(bytes: $0, count: Int(document.length)) } ?? Data())
            }
            Self.log.notice("Sent \(request.datenartVersion, privacy: .public): code \(code), answer \(answer.utf8.count) bytes, \(documents.count) PDF(s)")
            return EricSendResult(code: code, errorText: text, validation: validation, serverAnswer: answer,
                                  documents: documents)
        }
    }

    /// The transfer ticket and return codes of a server answer, read by ERiC
    /// (`EricMtGetErrormessagesFromXMLAnswer`). Works offline: it only parses `answer`.
    public func serverMessages(answer: String) throws(EricError) -> EricServerMessages {
        try withInstance { api, instance throws(EricError) in
            var buffers: [EricRueckgabepufferHandle] = []
            defer { for buffer in buffers { _ = api.EricMtRueckgabepufferFreigeben(instance, buffer) } }
            for _ in 0..<4 {
                guard let buffer = api.EricMtRueckgabepufferErzeugen(instance) else {
                    throw .callFailed(function: "EricMtRueckgabepufferErzeugen", code: -1)
                }
                buffers.append(buffer)
            }
            // ERiC wants the answer unchanged and without line breaks.
            let single = answer.replacingOccurrences(of: "\r", with: "").replacingOccurrences(of: "\n", with: "")
            let code = single.withCString {
                api.EricMtGetErrormessagesFromXMLAnswer(instance, $0, buffers[0], buffers[1], buffers[2], buffers[3])
            }
            guard code == ERIC_OK.rawValue else {
                throw .callFailed(function: "EricMtGetErrormessagesFromXMLAnswer", code: code)
            }
            let texts = buffers.map {
                (api.EricMtRueckgabepufferInhalt(instance, $0).map { String(cString: $0) } ?? "")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            }
            let errors = XMLNode.parse(texts[3])?.all("Fehler").map {
                EricServerMessages.Message(code: $0.child("Code")?.text ?? "", text: $0.child("Meldung")?.text ?? "")
            } ?? []
            return EricServerMessages(transferTicket: texts[0], transferHeaderCode: texts[1],
                                      transferHeaderText: texts[2], nutzdatenErrors: errors)
        }
    }
}

/// Holds the progress handler while ERiC may call it; passed to ERiC as `benutzerdaten`.
private final class ProgressBox: @unchecked Sendable {
    let handler: @Sendable (EricProgress) -> Void
    init(_ handler: @escaping @Sendable (EricProgress) -> Void) { self.handler = handler }
}

private let overallProgressCallback: EricFortschrittCallback = { id, position, maximum, user in
    guard let user else { return }
    Unmanaged<ProgressBox>.fromOpaque(user).takeUnretainedValue()
        .handler(EricProgress(step: .init(rawValue: id), position: position, maximum: maximum, isOverall: true))
}

private let stepProgressCallback: EricFortschrittCallback = { id, position, maximum, user in
    guard let user else { return }
    Unmanaged<ProgressBox>.fromOpaque(user).takeUnretainedValue()
        .handler(EricProgress(step: .init(rawValue: id), position: position, maximum: maximum, isOverall: false))
}
