import Foundation

/// The ELSTER server's answer XML (`Elster` with schema `th000011_extern.xsd` / `ndh000011.xsd`), as far as the
/// app needs it: the transfer ticket and the return codes of the transfer header and the Nutzdaten headers.
public struct ElsterServerAnswer: Sendable, Equatable {
    /// One `RC/Rueckgabe`.
    public struct ReturnCode: Sendable, Equatable {
        /// `0` means accepted.
        public var code: String
        public var text: String

        public init(code: String, text: String) {
            self.code = code
            self.text = text
        }

        public var isSuccess: Bool { code == "0" }
    }

    /// `TransferHeader/TransferTicket`; nil when missing or empty.
    public var transferTicket: String?
    /// `TransferHeader/RC/Rueckgabe`.
    public var transferHeader: ReturnCode?
    /// `DatenTeil/Nutzdatenblock/NutzdatenHeader/RC/Rueckgabe` of each block that has one.
    public var nutzdaten: [ReturnCode]

    public init(transferTicket: String?, transferHeader: ReturnCode?, nutzdaten: [ReturnCode] = []) {
        self.transferTicket = transferTicket
        self.transferHeader = transferHeader
        self.nutzdaten = nutzdaten
    }

    /// Parses `xml`; nil when it is empty or not well-formed.
    public static func parse(_ xml: String) -> ElsterServerAnswer? {
        guard !xml.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, let root = XMLNode.parse(xml) else {
            return nil
        }
        func returnCode(_ node: XMLNode?) -> ReturnCode? {
            guard let rueckgabe = node?.at(["RC", "Rueckgabe"]), let code = rueckgabe.child("Code")?.text,
                  !code.isEmpty else { return nil }
            return ReturnCode(code: code, text: rueckgabe.child("Text")?.text ?? "")
        }
        let header = root.child("TransferHeader")
        let ticket = header?.child("TransferTicket")?.text
        let nutzdaten = root.child("DatenTeil")?.all("Nutzdatenblock")
            .compactMap { returnCode($0.child("NutzdatenHeader")) } ?? []
        return ElsterServerAnswer(transferTicket: ticket?.isEmpty == false ? ticket : nil,
                                  transferHeader: returnCode(header), nutzdaten: nutzdaten)
    }

    /// The first return code that is not 0: the transfer header's, else a Nutzdaten header's.
    public var firstError: ReturnCode? {
        if let transferHeader, !transferHeader.isSuccess { return transferHeader }
        return nutzdaten.first { !$0.isSuccess }
    }

    /// The transfer header and every Nutzdaten header that has a code report 0.
    public var isAccepted: Bool {
        transferHeader?.isSuccess == true && nutzdaten.allSatisfy(\.isSuccess)
    }
}

/// What a send means for the user and for the filing record.
public enum EricSendOutcome: Sendable, Equatable {
    /// ERiC returned `ERIC_OK` and the server answered `TransferHeader/RC/Rueckgabe/Code` 0 (and 0 in every
    /// Nutzdaten header).
    case accepted(ticket: String?, text: String?)
    /// The server answered with an error code (`code` is the server's, e.g. 601015001).
    case rejected(code: String, text: String, ticket: String?)
    /// ERiC's local validation found errors; nothing was sent.
    case validationFailed(EricValidationResult)
    /// The PIN is wrong (`ERIC_CRYPT_E_PIN_WRONG`); nothing was sent.
    case pinWrong
    /// The PIN is locked (`ERIC_CRYPT_E_PIN_LOCKED`); nothing was sent.
    case pinLocked
    /// A timeout or connection error, or a server answer without a readable result: the return may have
    /// arrived. Check Mein ELSTER before sending again; never resend automatically.
    case uncertain(ticket: String?, code: Int32, text: String?)
    /// Any other error; nothing was sent.
    case failed(code: Int32, text: String?)

    /// Classifies a send's result:
    /// - `ERIC_CRYPT_E_PIN_WRONG` / `_LOCKED` → `pinWrong` / `pinLocked`.
    /// - Timeout or connection codes (610101271/278/279) → `uncertain`, with the ticket when the answer has one.
    /// - A server return code other than 0 → `rejected` with the server's code and text.
    /// - `ERIC_OK` with code 0 from the server → `accepted`; `ERIC_OK` without a readable answer → `uncertain`.
    /// - `ERIC_GLOBAL_PRUEF_FEHLER` or rule errors → `validationFailed`.
    /// - Any other code: `uncertain` when the server answered with a ticket, else `failed`.
    public static func classify(_ result: EricSendResult) -> EricSendOutcome {
        let answer = ElsterServerAnswer.parse(result.serverAnswer)
        let ticket = answer?.transferTicket
        switch result.code {
        case EricCode.pinWrong: return .pinWrong
        case EricCode.pinLocked: return .pinLocked
        case let code where EricCode.uncertainTransfer.contains(code):
            return .uncertain(ticket: ticket, code: code, text: result.errorText)
        default: break
        }
        if let error = answer?.firstError {
            return .rejected(code: error.code, text: error.text, ticket: ticket)
        }
        if result.code == EricCode.ok {
            if let answer, answer.isAccepted {
                return .accepted(ticket: ticket, text: answer.transferHeader?.text)
            }
            return .uncertain(ticket: ticket, code: result.code, text: result.errorText)
        }
        if result.code == EricCode.pruefFehler || !result.validation.errors.isEmpty {
            return .validationFailed(result.validation)
        }
        if ticket != nil {
            return .uncertain(ticket: ticket, code: result.code, text: result.errorText)
        }
        return .failed(code: result.code, text: result.errorText)
    }

    /// The transfer ticket, when the server returned one.
    public var ticket: String? {
        switch self {
        case .accepted(let ticket, _), .rejected(_, _, let ticket), .uncertain(let ticket, _, _): return ticket
        default: return nil
        }
    }

    /// Whether the return may have reached the server, so it is kept as a filing record.
    public var reachedServer: Bool {
        switch self {
        case .accepted, .rejected, .uncertain: return true
        case .validationFailed, .pinWrong, .pinLocked, .failed: return false
        }
    }
}
