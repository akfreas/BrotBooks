import CryptoKit
import Foundation
import os

/// Write-once document storage under a root folder: the app's iCloud Drive `Documents/` folder,
/// or a local Application Support folder when iCloud is unavailable.
///
/// Layout mirrors the Sorted export: `expenses/<YYYY>/<file>.pdf`, `income/<YYYY>/<file>.pdf`,
/// `tax-reports/…`, `tax-registration/…`. Records store the path relative to the root plus its SHA-256.
public final class DocumentStore: Sendable {
    public let root: URL
    /// True when `root` is inside an iCloud ubiquity container (files may need downloading first).
    public let isUbiquitous: Bool

    private static let log = Logger(subsystem: "me.freas.BrotBooks", category: "documents")

    public init(root: URL, isUbiquitous: Bool) {
        self.root = root.standardizedFileURL
        self.isUbiquitous = isUbiquitous
    }

    public static func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    /// Relative path for a record document: `<kind>/<document filename>`.
    public static func relativePath(_ kind: Kind, filename: String) -> String {
        "\(kind.rawValue)/\(filename)"
    }

    /// Absolute URL for a relative path; refuses paths that escape the root.
    public func resolve(_ relativePath: String) throws -> URL {
        let url = root.appendingPathComponent(relativePath).standardizedFileURL
        guard url.path.hasPrefix(root.path + "/") else {
            throw ValidationError("Refusing to use a path outside the documents folder: '\(relativePath)'")
        }
        return url
    }

    /// Stores `data` at `relativePath` unless an identical file is already there.
    /// Returns the SHA-256 and whether a write happened (or would happen, with `dryRun`).
    @discardableResult
    public func put(_ relativePath: String, data: Data, dryRun: Bool = false) throws -> (sha256: String, written: Bool) {
        let sha = DocumentStore.sha256(data)
        let dest = try resolve(relativePath)
        if let existing = try? Data(contentsOf: dest), DocumentStore.sha256(existing) == sha {
            return (sha, false)
        }
        if dryRun { return (sha, true) }
        try FileManager.default.createDirectory(at: dest.deletingLastPathComponent(), withIntermediateDirectories: true)
        var coordinationError: NSError?
        var writeError: Error?
        NSFileCoordinator(filePresenter: nil).coordinate(writingItemAt: dest, options: .forReplacing,
                                                         error: &coordinationError) { url in
            do {
                try data.write(to: url, options: .atomic)
            } catch {
                writeError = error
            }
        }
        if let error = coordinationError ?? writeError {
            DocumentStore.log.error("Writing \(relativePath, privacy: .public) failed: \(error.localizedDescription, privacy: .public)")
            throw error
        }
        return (sha, true)
    }

    public enum Availability: Sendable, Equatable {
        case available(URL)
        case downloading
        case missing
    }

    /// Whether a document can be read now. In iCloud, a not-yet-downloaded file starts downloading.
    public func availability(_ relativePath: String) -> Availability {
        guard let url = try? resolve(relativePath) else { return .missing }
        guard isUbiquitous else {
            return FileManager.default.fileExists(atPath: url.path) ? .available(url) : .missing
        }
        let values = try? url.resourceValues(forKeys: [.isUbiquitousItemKey, .ubiquitousItemDownloadingStatusKey])
        if values?.isUbiquitousItem != true {
            return FileManager.default.fileExists(atPath: url.path) ? .available(url) : .missing
        }
        if values?.ubiquitousItemDownloadingStatus == .current { return .available(url) }
        do {
            try FileManager.default.startDownloadingUbiquitousItem(at: url)
            return .downloading
        } catch {
            return .missing
        }
    }

    /// Reads a document, waiting (up to `timeout`) for iCloud to download it first.
    public func read(_ relativePath: String, timeout: Duration = .seconds(60)) async throws -> Data {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: timeout)
        while true {
            switch availability(relativePath) {
            case .available(let url):
                return try coordinatedRead(url)
            case .missing:
                throw CocoaError(.fileNoSuchFile)
            case .downloading:
                if clock.now >= deadline { throw CocoaError(.fileReadUnknown) }
                try await Task.sleep(for: .milliseconds(500))
            }
        }
    }

    private func coordinatedRead(_ url: URL) throws -> Data {
        var coordinationError: NSError?
        var result: Result<Data, Error> = .failure(CocoaError(.fileReadUnknown))
        NSFileCoordinator(filePresenter: nil).coordinate(readingItemAt: url, options: [], error: &coordinationError) { url in
            result = Result { try Data(contentsOf: url) }
        }
        if let coordinationError { throw coordinationError }
        return try result.get()
    }
}
