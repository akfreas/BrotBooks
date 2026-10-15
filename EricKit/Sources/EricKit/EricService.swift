import CEric
import Foundation
import os

/// Errors from loading or calling ERiC.
public enum EricError: Error, Equatable, CustomStringConvertible {
    /// `libericapi.dylib` is not in the ERiC directory.
    case libraryMissing(path: String)
    /// `dlopen` or a symbol lookup failed.
    case loadFailed(String)
    /// `EricMtInstanzErzeugen` returned NULL; the cause is in eric.log in the log directory.
    case instanceCreationFailed(logDirectory: String)
    /// An ERiC function returned a code other than `ERIC_OK` (see eric_fehlercodes.h).
    case callFailed(function: String, code: Int32)
    /// An ERiC function returned data that could not be read.
    case malformedResult(function: String)

    public var description: String {
        switch self {
        case .libraryMissing(let path): "ERiC library not found at \(path)"
        case .loadFailed(let message): "ERiC could not be loaded: \(message)"
        case .instanceCreationFailed(let log): "ERiC instance could not be created; see eric.log in \(log)"
        case .callFailed(let function, let code): "\(function) failed with ERiC code \(code)"
        case .malformedResult(let function): "\(function) returned unreadable data"
        }
    }
}

/// Owns the one ERiC instance (`EricMtInstanzErzeugen`) for the app's lifetime. Being an actor, the instance is
/// never used by two threads at once (EHB 5.3.16). The instance is created on first use and freed by `shutdown()`.
public actor EricService {
    /// Folder holding libericapi.dylib, libericxerces.dylib, libeSigner.dylib and `plugins/`; ERiC searches it
    /// recursively for plugins.
    public nonisolated let ericDirectory: URL
    /// Writable folder for eric.log.
    public nonisolated let logDirectory: URL
    /// Text file with the ERiC package version (scripts/vendor-eric.sh writes it).
    public nonisolated let versionFile: URL

    private var api: CEricAPI?
    private var instance: EricInstanzHandle?

    static let log = Logger(subsystem: "me.freas.BrotBooks", category: "ERiC")

    /// - Parameter versionFile: defaults to `VERSION` in `ericDirectory`, where Vendor/ERiC has it.
    public init(ericDirectory: URL, logDirectory: URL, versionFile: URL? = nil) {
        self.ericDirectory = ericDirectory
        self.logDirectory = logDirectory
        self.versionFile = versionFile ?? ericDirectory.appending(path: "VERSION")
    }

    /// ERiC as the app ships it: `Contents/Frameworks/ERiC` in the bundle, logging to
    /// `Application Support/ERiC/logs` (inside the sandbox container). The version file is
    /// `Contents/Resources/ERiC/VERSION`, since only signed code may sit in Contents/Frameworks.
    public static func bundled(in bundle: Bundle = .main) -> EricService {
        let resources = bundle.resourceURL ?? bundle.bundleURL.appending(path: "Contents/Resources")
        return EricService(ericDirectory: bundledDirectory(in: bundle), logDirectory: defaultLogDirectory,
                           versionFile: resources.appending(path: "ERiC/VERSION"))
    }

    /// `Contents/Frameworks/ERiC` in `bundle`.
    public static func bundledDirectory(in bundle: Bundle = .main) -> URL {
        (bundle.privateFrameworksURL ?? bundle.bundleURL.appending(path: "Contents/Frameworks"))
            .appending(path: "ERiC", directoryHint: .isDirectory)
    }

    /// `~/Library/Application Support/ERiC/logs`, which the sandbox maps into the app's container.
    public static var defaultLogDirectory: URL {
        URL.applicationSupportDirectory.appending(path: "ERiC/logs", directoryHint: .isDirectory)
    }

    isolated deinit {
        if let instance, let free = api?.EricMtInstanzFreigeben {
            _ = free(instance)
        }
    }

    /// Versions of the loaded ERiC libraries and plugins (`EricMtVersion`), plus the package version from
    /// `versionFile`.
    public func version() throws(EricError) -> EricVersionInfo {
        let xml = try withReturnBuffer(function: "EricMtVersion") { api, instance, buffer in
            api.EricMtVersion(instance, buffer)
        }
        guard let info = EricVersionInfo(xml: xml, packageVersion: packageVersion()) else {
            throw .malformedResult(function: "EricMtVersion")
        }
        return info
    }

    /// Checks `xml` locally against the schema and plausibility rules of `datenartVersion` (e.g. `UStVA_2026`)
    /// with `ERIC_VALIDIERE | ERIC_PRUEFE_HINWEISE`; nothing is sent. Rule errors and hints come back in the
    /// result, as do other ERiC error codes (with `EricMtHoleFehlerText`); only failures to load or call ERiC
    /// throw.
    public func validate(xml: String, datenartVersion: String) throws(EricError) -> EricValidationResult {
        let flags = UInt32(ERIC_VALIDIERE.rawValue | ERIC_PRUEFE_HINWEISE.rawValue)
        return try process(xml: xml, datenartVersion: datenartVersion, flags: flags, druck: nil)
    }

    /// The footer ERiC prints on preview PDFs. Vendor text only, never tax data (EHB 5.1.5.3), at most
    /// `ERIC_MAX_LAENGE_FUSSTEXT` (30) characters.
    public static let previewFooter = "Erstellt mit BrotBooks"

    /// Validates `xml` and renders ERiC's preview PDF (`ERIC_VALIDIERE | ERIC_DRUCKE` with `vorschau = 1`,
    /// EBV-2); nothing is sent. The PDF comes back through `pdfCallback` into memory, so no file is written.
    /// When validation fails ERiC prints nothing: the result then has no documents and carries the errors.
    public func preview(xml: String, datenartVersion: String) throws(EricError) -> EricPreviewResult {
        let collector = UnsafeMutablePointer<CEricPdfCollector>.allocate(capacity: 1)
        collector.initialize(to: CEricPdfCollector())
        defer {
            CEricPdfCollectorFree(collector)
            collector.deallocate()
        }
        let flags = UInt32(ERIC_VALIDIERE.rawValue | ERIC_DRUCKE.rawValue)
        let footer = strdup(Self.previewFooter)
        defer { free(footer) }
        var druck = eric_druck_parameter_t(
            version: 4, vorschau: 1, duplexDruck: 0, pdfName: nil, fussText: footer,
            pdfCallback: CEricPdfCollect, pdfCallbackBenutzerdaten: UnsafeMutableRawPointer(collector))
        let validation = try process(xml: xml, datenartVersion: datenartVersion, flags: flags, druck: &druck)
        let documents = (0..<collector.pointee.count).map { index in
            let document = collector.pointee.documents[index]
            return EricPreviewResult.Document(
                name: document.name.map { String(cString: $0) } ?? "",
                data: document.bytes.map { Data(bytes: $0, count: Int(document.length)) } ?? Data())
        }
        if collector.pointee.failed != 0 {
            Self.log.error("Preview PDF could not be copied (out of memory)")
        }
        return EricPreviewResult(validation: validation, documents: documents)
    }

    /// Runs `EricMtBearbeiteVorgang` on `xml` and reads its return buffer: rule errors and hints for
    /// `ERIC_OK`/`ERIC_GLOBAL_PRUEF_FEHLER`/`ERIC_GLOBAL_HINWEISE`, otherwise the code with its error text.
    private func process(xml: String, datenartVersion: String, flags: UInt32,
                         druck: UnsafePointer<eric_druck_parameter_t>?) throws(EricError) -> EricValidationResult {
        try withInstance { api, instance throws(EricError) in
            guard let buffer = api.EricMtRueckgabepufferErzeugen(instance) else {
                throw .callFailed(function: "EricMtRueckgabepufferErzeugen", code: -1)
            }
            defer { _ = api.EricMtRueckgabepufferFreigeben(instance, buffer) }
            guard let serverBuffer = api.EricMtRueckgabepufferErzeugen(instance) else {
                throw .callFailed(function: "EricMtRueckgabepufferErzeugen", code: -1)
            }
            defer { _ = api.EricMtRueckgabepufferFreigeben(instance, serverBuffer) }

            let code = xml.withCString { data in
                datenartVersion.withCString { version in
                    api.EricMtBearbeiteVorgang(instance, data, version, flags, druck, nil, buffer, serverBuffer)
                }
            }
            let response = api.EricMtRueckgabepufferInhalt(instance, buffer).map { String(cString: $0) } ?? ""
            switch code {
            case Int32(ERIC_OK.rawValue), Int32(ERIC_GLOBAL_PRUEF_FEHLER.rawValue), Int32(ERIC_GLOBAL_HINWEISE.rawValue):
                guard let parsed = EricValidationResult.parse(response) else {
                    throw .malformedResult(function: "EricMtBearbeiteVorgang")
                }
                return EricValidationResult(code: code, errors: parsed.errors, hints: parsed.hints, response: response)
            default:
                let text = errorText(code, api: api, instance: instance)
                Self.log.error("EricMtBearbeiteVorgang \(datenartVersion, privacy: .public) failed: \(code) \(text ?? "", privacy: .public)")
                let parsed = EricValidationResult.parse(response)
                return EricValidationResult(code: code, errors: parsed?.errors ?? [], hints: parsed?.hints ?? [],
                                            errorText: text, response: response)
            }
        }
    }

    // MARK: - Steuernummer and Finanzämter

    /// Converts a Steuernummer in the regional notation of the Finanzamt's letters (e.g. `21/815/08150`) into the
    /// 13-digit ELSTER format with `EricMtMakeElsterStnr`, which also checks the result. One of `landesnummer`
    /// (2 digits, the first two of the Bundesfinanzamtsnummer) and `bundesfinanzamtsnummer` (4 digits) is
    /// required; Bavarian and Berlin numbers in the format `BBB/UUUUP` need the Bundesfinanzamtsnummer.
    /// - Throws: `.callFailed(function: "EricMtMakeElsterStnr", code:)`, e.g. with
    ///   `ERIC_GLOBAL_STEUERNUMMER_UNGUELTIG` or `ERIC_GLOBAL_LANDESNUMMER_UNBEKANNT`; `errorText(for:)` has
    ///   ERiC's message for the code.
    public func makeElsterSteuernummer(_ steuernummer: String, landesnummer: String? = nil,
                                       bundesfinanzamtsnummer: String? = nil) throws(EricError) -> String {
        let result = try withReturnBuffer(function: "EricMtMakeElsterStnr") { api, instance, buffer in
            steuernummer.withCString { bescheid in
                Self.withOptionalCString(landesnummer) { land in
                    Self.withOptionalCString(bundesfinanzamtsnummer) { bufa in
                        api.EricMtMakeElsterStnr(instance, bescheid, land, bufa, buffer)
                    }
                }
            }
        }
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Checks a 13-digit ELSTER Steuernummer, including its Bundesfinanzamtsnummer, with
    /// `EricMtPruefeSteuernummer`. Returns normally when it is valid.
    /// - Throws: `.callFailed(function: "EricMtPruefeSteuernummer", code:)`, e.g. with
    ///   `ERIC_GLOBAL_STEUERNUMMER_UNGUELTIG`.
    public func checkSteuernummer(_ steuernummer: String) throws(EricError) {
        let code = try withInstance { api, instance in
            steuernummer.withCString { api.EricMtPruefeSteuernummer(instance, $0) }
        }
        guard code == ERIC_OK.rawValue else { throw .callFailed(function: "EricMtPruefeSteuernummer", code: code) }
    }

    /// The Finanzamt countries (Bundesländer, plus special offices) with their 2-digit numbers
    /// (`EricMtHoleFinanzamtLandNummern`), in ERiC's order.
    public func bundeslaender() throws(EricError) -> [EricFinanzamtLand] {
        let xml = try withReturnBuffer(function: "EricMtHoleFinanzamtLandNummern") { api, instance, buffer in
            api.EricMtHoleFinanzamtLandNummern(instance, buffer)
        }
        guard let laender = EricFinanzamtLand.parse(xml) else {
            throw .malformedResult(function: "EricMtHoleFinanzamtLandNummern")
        }
        return laender
    }

    /// The Finanzämter of a Finanzamt country (`EricMtHoleFinanzaemter`), in ERiC's order.
    /// - Parameter landNummer: 2 digits, from `bundeslaender()`.
    public func finanzaemter(landNummer: String) throws(EricError) -> [EricFinanzamt] {
        let xml = try withReturnBuffer(function: "EricMtHoleFinanzaemter") { api, instance, buffer in
            landNummer.withCString { api.EricMtHoleFinanzaemter(instance, $0, buffer) }
        }
        guard let finanzaemter = EricFinanzamt.parse(xml) else {
            throw .malformedResult(function: "EricMtHoleFinanzaemter")
        }
        return finanzaemter
    }

    /// ERiC's message for an error `code` (`EricMtHoleFehlerText`), or nil when it has none or ERiC can't load.
    public func errorText(for code: Int32) -> String? {
        try? withInstance { api, instance in errorText(code, api: api, instance: instance) }
    }

    private static func withOptionalCString<T>(_ string: String?, _ body: (UnsafePointer<CChar>?) -> T) -> T {
        guard let string, !string.isEmpty else { return body(nil) }
        return string.withCString { body($0) }
    }

    /// `EricMtHoleFehlerText` for `code`, or nil when ERiC has none.
    private func errorText(_ code: Int32, api: CEricAPI, instance: EricInstanzHandle) -> String? {
        guard let buffer = api.EricMtRueckgabepufferErzeugen(instance) else { return nil }
        defer { _ = api.EricMtRueckgabepufferFreigeben(instance, buffer) }
        guard api.EricMtHoleFehlerText(instance, code, buffer) == ERIC_OK.rawValue,
              let content = api.EricMtRueckgabepufferInhalt(instance, buffer) else { return nil }
        let text = String(cString: content).trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : text
    }

    /// Frees the ERiC instance. Call on app quit; a later call creates a new instance.
    public func shutdown() {
        guard let instance, let api else { return }
        let code = api.EricMtInstanzFreigeben(instance)
        self.instance = nil
        Self.log.info("ERiC instance freed (code \(code))")
    }

    // MARK: - Calling ERiC

    /// Runs `body` with the loaded functions and the instance, creating both on first use.
    func withInstance<T>(_ body: (CEricAPI, EricInstanzHandle) throws(EricError) -> T) throws(EricError) -> T {
        let api = try loadedAPI()
        if instance == nil {
            try FileManager.default.createDirectoryIfNeeded(logDirectory)
            // ERiC wants paths in NFD (EHB 5.3.3.3), which is what the file-system representation is.
            let created = ericDirectory.withUnsafeFileSystemRepresentation { plugins in
                logDirectory.withUnsafeFileSystemRepresentation { log in
                    api.EricMtInstanzErzeugen(plugins, log)
                }
            }
            guard let created else {
                throw .instanceCreationFailed(logDirectory: logDirectory.path(percentEncoded: false))
            }
            instance = created
            Self.log.info("ERiC instance created (plugins \(self.ericDirectory.path(percentEncoded: false), privacy: .public), log \(self.logDirectory.path(percentEncoded: false), privacy: .public))")
        }
        return try body(api, instance!)
    }

    /// Calls `call` with a fresh return buffer and returns the buffer's content when it returns `ERIC_OK`.
    func withReturnBuffer(
        function: String,
        _ call: (CEricAPI, EricInstanzHandle, EricRueckgabepufferHandle) -> Int32
    ) throws(EricError) -> String {
        try withInstance { api, instance throws(EricError) in
            guard let buffer = api.EricMtRueckgabepufferErzeugen(instance) else {
                throw .callFailed(function: "EricMtRueckgabepufferErzeugen", code: -1)
            }
            defer { _ = api.EricMtRueckgabepufferFreigeben(instance, buffer) }
            let code = call(api, instance, buffer)
            guard code == ERIC_OK.rawValue else { throw .callFailed(function: function, code: code) }
            guard let content = api.EricMtRueckgabepufferInhalt(instance, buffer) else {
                throw .malformedResult(function: function)
            }
            return String(cString: content)
        }
    }

    private func loadedAPI() throws(EricError) -> CEricAPI {
        if let api { return api }
        let library = ericDirectory.appending(path: "libericapi.dylib")
        guard FileManager.default.fileExists(atPath: library.path(percentEncoded: false)) else {
            throw .libraryMissing(path: library.path(percentEncoded: false))
        }
        var loaded = CEricAPI()
        var message = [CChar](repeating: 0, count: 1024)
        let status = library.withUnsafeFileSystemRepresentation { path in
            CEricLoad(path, &loaded, &message, message.count)
        }
        guard status == 0 else {
            throw .loadFailed(String(decoding: message.prefix { $0 != 0 }.map(UInt8.init(bitPattern:)), as: UTF8.self))
        }
        api = loaded
        return loaded
    }

    private func packageVersion() -> String? {
        guard let text = try? String(contentsOf: versionFile, encoding: .utf8) else {
            return nil
        }
        let version = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return version.isEmpty ? nil : version
    }
}

private extension FileManager {
    func createDirectoryIfNeeded(_ url: URL) throws(EricError) {
        do {
            try createDirectory(at: url, withIntermediateDirectories: true)
        } catch {
            throw .instanceCreationFailed(logDirectory: url.path(percentEncoded: false))
        }
    }
}
