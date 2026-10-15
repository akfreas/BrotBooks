#if os(macOS)
import AppKit
import EricKit
import Observation
import os

/// The app's ERiC bridge: one `EricService` on the ERiC embedded in the bundle, created on first use and freed
/// when the app quits.
@MainActor
@Observable
final class EricRuntime {
    enum Status {
        case notLoaded
        case loading
        case ready(EricVersionInfo)
        case failed(String)
    }

    static let shared = EricRuntime()

    let service = EricService.bundled()
    private(set) var status = Status.notLoaded

    /// The loaded version, once `loadVersion()` succeeded.
    var version: EricVersionInfo? {
        if case .ready(let info) = status { return info }
        return nil
    }

    /// The ELSTER Hersteller-ID from Info.plist (`ElsterHerstellerID`, set from `ELSTER_HERSTELLER_ID` in
    /// Config/BrotBooks.xcconfig); nil when it is missing.
    static var herstellerID: String? {
        guard let id = Bundle.main.object(forInfoDictionaryKey: "ElsterHerstellerID") as? String,
              !id.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
        return id
    }

    private let log = Logger(subsystem: "me.freas.BrotBooks", category: "ERiC")

    private init() {
        let service = service
        NotificationCenter.default.addObserver(forName: NSApplication.willTerminateNotification, object: nil, queue: nil) { _ in
            // Free the instance before exit (EHB 5.3.16). The actor isn't the main actor, so waiting briefly is safe.
            let done = DispatchSemaphore(value: 0)
            Task.detached {
                await service.shutdown()
                done.signal()
            }
            _ = done.wait(timeout: .now() + 2)
        }
    }

    /// Loads ERiC and reads its version, once.
    func loadVersion() async {
        switch status {
        case .loading, .ready: return
        case .notLoaded, .failed: break
        }
        status = .loading
        do {
            let info = try await service.version()
            log.notice("ERiC \(info.displayVersion ?? "?", privacy: .public) loaded (API \(info.apiVersion ?? "?", privacy: .public), UStVA plugins \(info.ustvaPluginYears.map(String.init).joined(separator: ","), privacy: .public))")
            status = .ready(info)
        } catch {
            log.error("ERiC failed to load: \(error.description, privacy: .public)")
            status = .failed(error.description)
        }
    }
}
#endif
