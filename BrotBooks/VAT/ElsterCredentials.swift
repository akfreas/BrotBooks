#if os(macOS)
import EricKit
import Foundation
import Observation
import os

/// The ELSTER certificate and PIN in this Mac's Keychain (`ElsterKeychain`), checked with ERiC: a certificate is
/// opened from its bytes (`EricMtZertifikatOeffnenAusBytes`) and its properties read before it and its PIN are
/// saved. Also picks the send transport: ERiC, or the stub of `-elsterTransport stub`.
@MainActor
@Observable
final class ElsterCredentials {
    static let shared = ElsterCredentials()

    enum CredentialError: Error, Equatable {
        case pinWrong
        case pinLocked
        case notACertificate(String)
        case keychain(String)
        case eric(String)
    }

    let keychain: ElsterKeychain
    private let service = EricRuntime.shared.service
    private let log = Logger(subsystem: "me.freas.BrotBooks", category: "ELSTER")

    private(set) var hasCertificate = false
    private(set) var hasPIN = false
    /// The stored certificate's properties, read with the stored PIN.
    private(set) var info: EricCertificateInfo?
    /// Why the stored certificate's properties couldn't be read.
    private(set) var infoError: CredentialError?
    private(set) var loaded = false

    private init() {
        // UI tests and screenshots never touch the real certificate.
        keychain = ElsterKeychain(service: LaunchOptions.uiTesting
                                  ? ElsterKeychain.defaultService + ".uitesting" : ElsterKeychain.defaultService)
    }

    /// The transport sends go through: the stub with `-elsterTransport stub`, else ERiC.
    var submitter: any VatSubmitting {
        if let name = LaunchOptions.elsterStubScenario {
            return StubVatSubmitter(scenario: StubVatSubmitter.Scenario(rawValue: name) ?? .success)
        }
        return service
    }

    var usesStubTransport: Bool { LaunchOptions.elsterStubScenario != nil }

    /// Reads the Keychain items and, when both are there, the certificate's properties.
    func load() async {
        do {
            let certificate = try keychain.certificate()
            let pin = try keychain.pin()
            hasCertificate = certificate != nil
            hasPIN = pin != nil
            infoError = nil
            if let certificate, let pin {
                do {
                    info = try await service.certificateInfo(pkcs12: certificate, pin: pin)
                } catch {
                    info = nil
                    let described = await Self.describe(error, service: service)
                    infoError = described
                    if described == .pinWrong { try? clearPIN() }
                }
            } else if certificate == nil {
                info = nil
            }
        } catch {
            log.error("Reading the ELSTER certificate from the Keychain failed: \(error.description, privacy: .public)")
            infoError = .keychain(error.description)
        }
        loaded = true
    }

    /// Opens `certificate` with `pin` and reads its properties; when that works, stores both in the Keychain
    /// (replacing what was stored).
    func importCertificate(_ certificate: Data, pin: String) async throws(CredentialError) -> EricCertificateInfo {
        let info = try await verify(certificate, pin: pin)
        do {
            try keychain.setCertificate(certificate)
            try keychain.setPIN(pin)
        } catch {
            throw .keychain(error.description)
        }
        hasCertificate = true
        hasPIN = true
        self.info = info
        infoError = nil
        log.notice("ELSTER certificate imported (holder \(info.holder ?? "?", privacy: .public))")
        return info
    }

    /// Checks `pin` against the stored certificate and stores it.
    func savePIN(_ pin: String) async throws(CredentialError) {
        let certificate: Data?
        do { certificate = try keychain.certificate() } catch { throw .keychain(error.description) }
        guard let certificate else { throw .keychain(String(localized: "No certificate is stored.")) }
        let info = try await verify(certificate, pin: pin)
        do { try keychain.setPIN(pin) } catch { throw .keychain(error.description) }
        hasPIN = true
        self.info = info
        infoError = nil
    }

    /// The stored certificate and PIN for a send, or nil when one is missing.
    func credentials() -> (certificate: Data, pin: String)? {
        guard let certificate = try? keychain.certificate(), let pin = try? keychain.pin() else { return nil }
        return (certificate, pin)
    }

    /// Removes the PIN (ERiC reported it wrong); the next send asks for it again.
    func clearPIN() throws {
        try keychain.removePIN()
        hasPIN = false
    }

    /// Removes the certificate and its PIN from the Keychain.
    func remove() throws {
        try keychain.removeAll()
        hasCertificate = false
        hasPIN = false
        info = nil
        infoError = nil
    }

    private func verify(_ certificate: Data, pin: String) async throws(CredentialError) -> EricCertificateInfo {
        do {
            return try await service.certificateInfo(pkcs12: certificate, pin: pin)
        } catch {
            throw await Self.describe(error, service: service)
        }
    }

    /// The user-facing kind of a certificate error.
    private static func describe(_ error: EricError, service: EricService) async -> CredentialError {
        guard case .callFailed(_, let code) = error else { return .eric(error.description) }
        switch code {
        case EricCode.pinWrong: return .pinWrong
        case EricCode.pinLocked: return .pinLocked
        default:
            let text = await service.errorText(for: code) ?? error.description
            return code >= 610201101 && code <= 610201212 ? .notACertificate(text) : .eric(text)
        }
    }

    static func message(_ error: CredentialError) -> String {
        switch error {
        case .pinWrong: String(localized: "The PIN is wrong.")
        case .pinLocked: String(localized: "The certificate's PIN is locked. Unlock or renew the certificate in Mein ELSTER.")
        case .notACertificate(let text): String(localized: "The file can't be used as an ELSTER certificate: \(text)")
        case .keychain(let text): String(localized: "Keychain: \(text)")
        case .eric(let text): text
        }
    }
}
#endif
