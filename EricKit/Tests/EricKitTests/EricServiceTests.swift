import Foundation
import Testing
@testable import EricKit

/// The vendored ERiC from scripts/vendor-eric.sh (`Vendor/ERiC` at the repo root), or `ERIC_DIR` if set.
let vendoredERiC: URL = {
    if let dir = ProcessInfo.processInfo.environment["ERIC_DIR"] { return URL(filePath: dir, directoryHint: .isDirectory) }
    return URL(filePath: #filePath)
        .deletingLastPathComponent()   // EricKitTests
        .deletingLastPathComponent()   // Tests
        .deletingLastPathComponent()   // EricKit
        .deletingLastPathComponent()   // repo root
        .appending(path: "Vendor/ERiC", directoryHint: .isDirectory)
}()

/// Loads the real ERiC. Skipped when it has not been vendored: run scripts/vendor-eric.sh <jar> first.
@Suite(.serialized, .enabled(if: FileManager.default.fileExists(atPath: vendoredERiC.appending(path: "libericapi.dylib").path),
                             "Vendor/ERiC missing: run scripts/vendor-eric.sh <jar>"))
struct EricServiceLiveTests {
    @Test func versionListsPackageAndUStVAPlugin() async throws {
        let logs = FileManager.default.temporaryDirectory.appending(path: "EricKitTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: logs) }
        let service = EricService(ericDirectory: vendoredERiC, logDirectory: logs)

        let info = try await service.version()
        print("ERiC package \(info.packageVersion ?? "?") api \(info.apiVersion ?? "?") UStVA \(info.ustvaPluginYears)")
        #expect(info.packageVersion?.contains("44.3.6") == true)
        #expect(info.apiVersion?.hasPrefix("44.3.") == true)
        #expect(info.libraries.contains { $0.name == "libcheckustva_2026.dylib" })
        #expect(info.ustvaPluginYears.contains(2026))
        #expect(FileManager.default.fileExists(atPath: logs.appending(path: "eric.log").path))

        // A second call reuses the instance; after shutdown the next call creates a new one.
        #expect(try await service.version() == info)
        await service.shutdown()
        #expect(try await service.version() == info)
        await service.shutdown()
    }
}

struct EricServiceTests {
    @Test func missingLibraryIsReported() async {
        let service = EricService(ericDirectory: URL(filePath: "/nonexistent/ERiC"), logDirectory: .temporaryDirectory)
        await #expect(throws: EricError.libraryMissing(path: "/nonexistent/ERiC/libericapi.dylib")) {
            try await service.version()
        }
    }
}

struct EricVersionInfoTests {
    @Test func parsesEricVersionXML() throws {
        let xml = """
            <?xml version="1.0" encoding="UTF-8"?>
            <EricVersion xmlns="http://www.elster.de/EricXML/1.0/EricVersion">
                <Bibliothek>
                    <Name>libcheckustva_2026.dylib</Name>
                    <Produktversion>44, 3, 2, 0</Produktversion>
                    <Dateiversion>2026, 44, 3, 2</Dateiversion>
                </Bibliothek>
                <Bibliothek>
                    <Name>libcheckUStVA_2025.dylib</Name>
                    <Produktversion>44, 3, 2, 0</Produktversion>
                    <Dateiversion>2026, 44, 3, 2</Dateiversion>
                </Bibliothek>
                <Bibliothek>
                    <Name>libericapi.dylib</Name>
                    <Produktversion>44, 3, 4, 0</Produktversion>
                    <Dateiversion>2026, 44, 3, 4</Dateiversion>
                </Bibliothek>
            </EricVersion>
            """
        let info = try #require(EricVersionInfo(xml: xml, packageVersion: "44.3.6.0"))
        #expect(info.libraries.count == 3)
        #expect(info.apiVersion == "44.3.4.0")
        #expect(info.libraries[2].fileVersion == "2026.44.3.4")
        #expect(info.ustvaPluginYears == [2025, 2026])
        #expect(info.displayVersion == "44.3.6.0")
        #expect(EricVersionInfo(xml: xml, packageVersion: nil)?.displayVersion == "44.3.4.0")
    }

    @Test func rejectsMalformedXML() {
        #expect(EricVersionInfo(xml: "<EricVersion><Bibliothek>", packageVersion: nil) == nil)
    }
}
