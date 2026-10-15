import Foundation
import SwiftUI
import BrotBooksKit

/// Launch arguments for UI tests and screenshots. Everything here is compiled into Debug builds only;
/// in Release every option reads as off.
///
/// - `-uiTesting YES`: an in-memory store and a fresh documents folder (nothing touches real data, every launch
///   starts clean), generated sample data, a fixed "today" (2026-10-10), no animations and no iCloud.
/// - `-uiTestingEmpty YES`: with `-uiTesting`, start with no records (first-run state).
/// - `-fixedToday YYYY-MM-DD`: pin "today" (defaults to 2026-10-10 under `-uiTesting`).
/// - `-uiAppearance dark|light`: force the color scheme.
/// - `-startDestination <identifier>`: open this sidebar destination (e.g. `vatReturns`) instead of the dashboard.
/// - `UITEST_SORTED_EXPORT` environment variable: a base64 zip that stands in for the file picker, so the import
///   menu item opens the preview with that file (with `UITEST_SORTED_EXPORT_NAME` as its filename).
/// - `UITEST_INVOICES` environment variable: a JSON array of `{"name": "<filename>", "data": "<base64>"}` that stands
///   in for the Import Invoices… file picker.
/// - `-uiTestingExtractor stub`: invoice extraction returns the canned results in `stubExtractions`, keyed by
///   filename, instead of using the on-device model (which the Simulator can't run).
/// - `-elsterTransport stub` (macOS): sending a VAT return never contacts ELSTER and needs no certificate; it
///   answers with the canned result of `-elsterStubScenario success|rejected|pinWrong|timeoutWithTicket|
///   timeoutWithoutTicket` (default `success`). The filings it records are real records, so combine it with
///   `-uiTesting YES` to keep them in the in-memory store.
enum LaunchOptions {
    static let uiTestingToday = "2026-10-10"

    static var uiTesting: Bool {
        #if DEBUG
        UserDefaults.standard.bool(forKey: "uiTesting")
        #else
        false
        #endif
    }

    static var startsEmpty: Bool {
        #if DEBUG
        uiTesting && UserDefaults.standard.bool(forKey: "uiTestingEmpty")
        #else
        false
        #endif
    }

    /// The pinned "today", or nil for the real date.
    static var fixedToday: String? {
        #if DEBUG
        if let day = UserDefaults.standard.string(forKey: "fixedToday"), ISODate.isValid(day) { return day }
        return uiTesting ? uiTestingToday : nil
        #else
        nil
        #endif
    }

    static var colorScheme: ColorScheme? {
        #if DEBUG
        switch UserDefaults.standard.string(forKey: "uiAppearance") {
        case "dark": .dark
        case "light": .light
        default: nil
        }
        #else
        nil
        #endif
    }

    /// The sidebar destination to start on, by its identifier (`Destination.identifier`).
    static var startDestination: Destination? {
        #if DEBUG
        guard let name = UserDefaults.standard.string(forKey: "startDestination") else { return nil }
        return Destination.allCases.first { $0.identifier == name }
        #else
        nil
        #endif
    }

    enum Fixture: String {
        case sortedExport = "UITEST_SORTED_EXPORT"
    }

    /// The file a UI test handed in for the given picker, written to a temporary folder, or nil.
    static func fixture(_ fixture: Fixture) -> URL? {
        #if DEBUG
        let env = ProcessInfo.processInfo.environment
        guard uiTesting, let encoded = env[fixture.rawValue], let data = Data(base64Encoded: encoded) else { return nil }
        let name = env[fixture.rawValue + "_NAME"] ?? "\(fixture.rawValue.lowercased()).zip"
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("UITestFixtures", isDirectory: true)
        let url = dir.appendingPathComponent(name)
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            try data.write(to: url, options: .atomic)
            return url
        } catch {
            return nil
        }
        #else
        nil
        #endif
    }

    /// The invoice files a UI test handed in for Import Invoices…, or nil.
    static var invoiceFixtures: [(name: String, data: Data)]? {
        #if DEBUG
        struct File: Decodable {
            var name: String
            var data: String
        }
        guard uiTesting, let json = ProcessInfo.processInfo.environment["UITEST_INVOICES"],
              let files = try? JSONDecoder().decode([File].self, from: Data(json.utf8))
        else { return nil }
        return files.compactMap { file in Data(base64Encoded: file.data).map { (file.name, $0) } }
        #else
        nil
        #endif
    }

    /// True with `-uiTestingExtractor stub`: extraction uses `StubInvoiceExtractor(results: stubExtractions)`.
    static var stubExtractor: Bool {
        #if DEBUG
        UserDefaults.standard.string(forKey: "uiTestingExtractor") == "stub"
        #else
        false
        #endif
    }

    /// The stub send scenario with `-elsterTransport stub` (`-elsterStubScenario`), or nil for real sending.
    static var elsterStubScenario: String? {
        #if DEBUG
        guard UserDefaults.standard.string(forKey: "elsterTransport") == "stub" else { return nil }
        return UserDefaults.standard.string(forKey: "elsterStubScenario") ?? "success"
        #else
        nil
        #endif
    }

    /// Canned extraction results for the UI test invoices (the BrotBooksKit fixtures, copied to
    /// `BrotBooksUITests/Fixtures`). Any other file (`invoice_photo_rotated.jpg`) reads as blank.
    static let stubExtractions: [String: ExtractedInvoice] = [
        "invoice_text.pdf": ExtractedInvoice(
            supplier: "Nordlicht Software GmbH", summary: "Nordlicht Cloud Hosting – Oct 2026", invoiceDate: "2026-10-01",
            grossAmount: "119.00", currency: "EUR", vatLines: [.init(rate: 19, amount: "19.00")],
            supplierRegion: "Germany", category: "Software", invoiceNumber: "NS-2026-0042",
            confidence: .init(amount: .high, date: .high, vat: .high)),
        "invoice_photo.heic": ExtractedInvoice(
            supplier: "Druckerei Beispiel GmbH", summary: "Druckerei Beispiel – business cards", invoiceDate: "2026-09-15",
            grossAmount: "59.50", currency: "EUR", vatLines: [.init(rate: 19, amount: "9.50")],
            supplierRegion: "Germany", category: "Office supplies", invoiceNumber: "DB-7781",
            confidence: .init(amount: .high, date: .medium, vat: .high)),
        // The VAT row doesn't add up to the gross: dropped and flagged for review.
        "invoice_photo.png": ExtractedInvoice(
            supplier: "Papierhaus Elbe GmbH", summary: "Papierhaus Elbe – printer paper", invoiceDate: "2026-10-05",
            grossAmount: "119.00", currency: "EUR", vatLines: [.init(rate: 19, amount: "9.50")],
            supplierRegion: "Germany", category: "Office supplies", invoiceNumber: "PE-1182",
            confidence: .init(amount: .high, date: .high, vat: .high)),
        // US dollars: approval needs a conversion rate.
        "invoice_scanned.pdf": ExtractedInvoice(
            supplier: "Orbit Tools Inc.", summary: "Orbit Tools – team plan Sep 2026", invoiceDate: "2026-09-30",
            grossAmount: "48.00", currency: "USD", supplierRegion: "Outside of the European Union", category: "Software",
            invoiceNumber: "OT-5520", confidence: .init(amount: .high, date: .high, vat: .high)),
    ]
}
