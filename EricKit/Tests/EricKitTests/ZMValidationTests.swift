import BrotBooksKit
import Foundation
import Testing
@testable import EricKit

/// ZM XML built by BrotBooksKit, validated by the real `checkZMDO` plugin (`ERIC_VALIDIERE | ERIC_PRUEFE_HINWEISE`,
/// nothing is sent). Periods lie in the past: ERiC rejects ZMs for periods that haven't started
/// (`meldezeitraum_Zukunft`). The customer VAT IDs have valid check digits (ERiC hints at implausible ones).
/// Skipped when ERiC has not been vendored.
@Suite(.serialized, .enabled(if: FileManager.default.fileExists(atPath: vendoredERiC.appending(path: "libericapi.dylib").path),
                             "Vendor/ERiC missing: run scripts/vendor-eric.sh <jar>"))
struct ZMValidationLiveTests {
    static let service = EricService(
        ericDirectory: vendoredERiC,
        logDirectory: FileManager.default.temporaryDirectory.appending(path: "EricKitTests-ZM-\(UUID().uuidString)"))

    /// The USt-IdNr of the ERiC sample (`ZMDO_5_send-Auth.xml`); ERiC checks its check digit.
    static let configuration: TaxConfiguration = {
        var configuration = UStVAValidationLiveTests.configuration()
        configuration.identity.vatID = "DE554367942"
        return configuration
    }()
    static let header = UStVAValidationLiveTests.header

    static func income(_ uid: String, date: String, gross: String, _ treatment: VatTreatment, vatID: String) throws
        -> UStVARecord {
        try UStVAValidationLiveTests.record(.income, uid, date: date, gross: gross, treatment,
                                            ["client_vat_number": .text(vatID)])
    }

    func zm(_ records: [UStVARecord], _ period: VatPeriod, filed: [ZMReportLine]? = nil) -> (xml: String, report: ZMReport) {
        let lines = UStVAAggregator.zmLines(records, period: period, configuration: Self.configuration)
        let report = ZMReport.make(lines, filed: filed)
        return (ZMXML.build(period: period, report: report, configuration: Self.configuration, header: Self.header),
                report)
    }

    @discardableResult
    func expectValid(_ xml: String, _ scenario: String) async throws -> EricValidationResult {
        let result = try await Self.service.validate(xml: xml, datenartVersion: ZMCodes.datenartVersion)
        print("[\(scenario)] ERiC code \(result.code), \(result.errors.count) errors, \(result.hints.count) hints")
        for hint in result.hints { print("[\(scenario)]   hint \(hint)") }
        for error in result.errors { print("[\(scenario)]   ERROR \(error)") }
        if let text = result.errorText { print("[\(scenario)]   \(text)") }
        #expect(result.errors.isEmpty, "\(scenario): \(result.errors)")
        #expect(result.isValid, "\(scenario): code \(result.code) \(result.errorText ?? "") \(result.response)")
        return result
    }

    @Test func monthlyGoodsAndServices() async throws {
        let records = [
            try Self.income("goods-at", date: "2026-05-04", gross: "12000.80", .euB2BGoods, vatID: "ATU13585627"),
            try Self.income("goods-at2", date: "2026-05-18", gross: "999", .euB2BGoods, vatID: "ATU13585627"),
            try Self.income("service-fr", date: "2026-05-11", gross: "2500.99", .euB2BService, vatID: "FR83404833048"),
            try Self.income("service-nl", date: "2026-05-30", gross: "300", .euB2BService, vatID: "NL123456782B01"),
        ]
        let (xml, report) = zm(records, .month(2026, 5))
        #expect(report.lines.count == 3)
        #expect(xml.contains("<quart>25</quart>"))
        try await expectValid(xml, "monthly goods + services")
    }

    @Test func quarterlyReport() async throws {
        let records = [
            try Self.income("apr", date: "2026-04-10", gross: "1000", .euB2BService, vatID: "FR83404833048"),
            try Self.income("jun", date: "2026-06-10", gross: "2000", .euB2BService, vatID: "FR83404833048"),
            try Self.income("may-goods", date: "2026-05-10", gross: "750.50", .euB2BGoods, vatID: "ATU13585627"),
        ]
        let (xml, report) = zm(records, .quarter(2026, 2))
        #expect(report.lines.map(\.amount) == [750, 3000])
        #expect(xml.contains("<quart>2</quart>"))
        try await expectValid(xml, "quarterly")
    }

    @Test func creditNoteMakesANegativeLine() async throws {
        let records = [
            try Self.income("credit", date: "2026-07-08", gross: "-400", .euB2BGoods, vatID: "ATU13585627"),
            try Self.income("sale", date: "2026-07-09", gross: "1200", .euB2BService, vatID: "FR83404833048"),
        ]
        let (xml, report) = zm(records, .month(2026, 7))
        #expect(report.lines.first?.amount == -400)
        #expect(xml.contains("<betrag>-400</betrag>"))
        try await expectValid(xml, "credit note")
    }

    @Test func correction() async throws {
        let filed = [
            ZMReportLine(customerVatID: "ATU13585627", umsatzart: .goods, amount: 5000),
            ZMReportLine(customerVatID: "FR83404833048", umsatzart: .service, amount: 300),
            ZMReportLine(customerVatID: "NL123456782B01", umsatzart: .service, amount: 800),
        ]
        let records = [
            try Self.income("goods", date: "2026-03-04", gross: "5000", .euB2BGoods, vatID: "ATU13585627"),
            try Self.income("service", date: "2026-03-11", gross: "350", .euB2BService, vatID: "FR83404833048"),
        ]
        let (xml, report) = zm(records, .month(2026, 3), filed: filed)
        #expect(report.meldeart == .corrected)
        #expect(report.lines == [
            ZMReportLine(customerVatID: "FR83404833048", umsatzart: .service, amount: 350),
            ZMReportLine(customerVatID: "NL123456782B01", umsatzart: .service, amount: 0),
        ])
        #expect(xml.contains(#"meldeart="11""#))
        try await expectValid(xml, "correction")
    }

    @Test func reportsRuleErrors() async throws {
        // A German customer VAT ID breaks `knre1_Laenderkennzeichen_DE`.
        let report = ZMReport(meldeart: .initial,
                              lines: [ZMReportLine(customerVatID: "DE123456789", umsatzart: .goods, amount: 100)])
        let xml = ZMXML.build(period: .month(2026, 5), report: report, configuration: Self.configuration,
                              header: Self.header)
        let result = try await Self.service.validate(xml: xml, datenartVersion: ZMCodes.datenartVersion)
        print("[ZM broken] code \(result.code): \(result.errors)")
        #expect(!result.isValid)
        #expect(result.errors.contains { $0.regelName?.hasSuffix("knre1_Laenderkennzeichen_DE") == true })
    }

    @Test func previewIsAPDF() async throws {
        let records = [try Self.income("goods", date: "2026-05-04", gross: "1000", .euB2BGoods, vatID: "ATU13585627")]
        let (xml, _) = zm(records, .month(2026, 5))
        let result = try await Self.service.preview(xml: xml, datenartVersion: ZMCodes.datenartVersion)
        print("[ZM preview] code \(result.validation.code), \(result.pdf?.count ?? 0) bytes")
        #expect(result.validation.errors.isEmpty)
        let pdf = try #require(result.pdf)
        #expect(pdf.starts(with: Data("%PDF".utf8)))
    }
}
