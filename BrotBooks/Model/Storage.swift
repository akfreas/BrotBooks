import Foundation
import os
import SwiftData
import BrotBooksKit

/// Where records and documents live: CloudKit + iCloud Drive, or this device only.
struct Storage {
    enum Mode: Equatable {
        case iCloud
        /// Local fallback, with the reason shown in the banner.
        case local(reason: LocalReason)
    }

    enum LocalReason: Equatable {
        case requested          // -useLocalStore YES launch argument
        case signedOut          // no iCloud account
        case unavailable(String) // container missing (no entitlement) or store failed to open
    }

    let mode: Mode
    let container: ModelContainer
    let documents: DocumentStore

    static let log = Logger(subsystem: "me.freas.BrotBooks", category: "storage")

    /// The iCloud container id from Info.plist (set from `SL_ICLOUD_CONTAINER` in the xcconfig).
    static var cloudContainerID: String {
        Bundle.main.object(forInfoDictionaryKey: "SLCloudContainer") as? String ?? "iCloud.me.freas.BrotBooks"
    }

    /// `-useLocalStore YES`: keep everything on this device (development, screenshots, tests).
    static var localRequested: Bool {
        UserDefaults.standard.bool(forKey: "useLocalStore") || sampleRequested || LaunchOptions.uiTesting
    }

    /// `-loadSampleData YES`: a separate local store filled with generated sample records.
    static var sampleRequested: Bool { UserDefaults.standard.bool(forKey: "loadSampleData") }

    /// Resolves storage. Call off the main actor: looking up the ubiquity container can block.
    static func open() async throws -> Storage {
        let support = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                                  appropriateFor: nil, create: true)
            .appendingPathComponent("BrotBooks", isDirectory: true)
        try FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)

        if LaunchOptions.uiTesting { return try uiTestingStore() }
        var reason = LocalReason.requested
        if !localRequested {
            if FileManager.default.ubiquityIdentityToken == nil {
                reason = .signedOut
            } else if let ubiquity = FileManager.default.url(forUbiquityContainerIdentifier: cloudContainerID) {
                do {
                    let docs = ubiquity.appendingPathComponent("Documents", isDirectory: true)
                    try FileManager.default.createDirectory(at: docs, withIntermediateDirectories: true)
                    let config = ModelConfiguration("BrotBooks", schema: StoreSchema.schema,
                                                    url: support.appendingPathComponent("Cloud.store"),
                                                    cloudKitDatabase: .private(cloudContainerID))
                    let container = try ModelContainer(for: StoreSchema.schema, configurations: [config])
                    log.info("Using iCloud container \(cloudContainerID, privacy: .public)")
                    return Storage(mode: .iCloud, container: container,
                                   documents: DocumentStore(root: docs, isUbiquitous: true))
                } catch {
                    log.error("iCloud store failed, falling back to local: \(error.localizedDescription, privacy: .public)")
                    reason = .unavailable(error.localizedDescription)
                }
            } else {
                reason = .unavailable(String(localized: "The app's iCloud container isn't available."))
            }
        }
        let prefix = sampleRequested ? "Sample" : "Local"
        let docs = support.appendingPathComponent(sampleRequested ? "SampleDocuments" : "Documents", isDirectory: true)
        try FileManager.default.createDirectory(at: docs, withIntermediateDirectories: true)
        let config = ModelConfiguration("BrotBooks\(prefix)", schema: StoreSchema.schema,
                                        url: support.appendingPathComponent("\(prefix).store"), cloudKitDatabase: .none)
        let container = try ModelContainer(for: StoreSchema.schema, configurations: [config])
        log.info("Using local store at \(support.path, privacy: .public)")
        return Storage(mode: .local(reason: reason), container: container,
                       documents: DocumentStore(root: docs, isUbiquitous: false))
    }

    /// `-uiTesting YES`: an in-memory store and an empty documents folder of its own, so every launch starts clean.
    private static func uiTestingStore() throws -> Storage {
        let docs = FileManager.default.temporaryDirectory
            .appendingPathComponent("UITestDocuments-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: docs, withIntermediateDirectories: true)
        let config = ModelConfiguration("BrotBooksUITest", schema: StoreSchema.schema, isStoredInMemoryOnly: true,
                                        cloudKitDatabase: .none)
        let container = try ModelContainer(for: StoreSchema.schema, configurations: [config])
        log.info("UI testing: in-memory store, documents at \(docs.path, privacy: .public)")
        return Storage(mode: .local(reason: .requested), container: container,
                       documents: DocumentStore(root: docs, isUbiquitous: false))
    }
}
