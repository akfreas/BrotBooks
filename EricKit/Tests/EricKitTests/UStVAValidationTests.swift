import BrotBooksKit
import Foundation
import Testing
@testable import EricKit

/// UStVA XML built by BrotBooksKit for several scenarios, validated by the real `checkUStVA_2026` plugin
/// (`ERIC_VALIDIERE | ERIC_PRUEFE_HINWEISE`, nothing is sent). Skipped when ERiC has not been vendored.
@Suite(.serialized, .enabled(if: FileManager.default.fileExists(atPath: vendoredERiC.appending(path: "libericapi.dylib").path),
                             "Vendor/ERiC missing: run scripts/vendor-eric.sh <jar>"))
struct UStVAValidationLiveTests {
    static let service = EricService(
        ericDirectory: vendoredERiC,
        logDirectory: FileManager.default.temporaryDirectory.appending(path: "EricKitTests-UStVA-\(UUID().uuidString)"))

    static let header = UStVAXML.Header(herstellerID: "27425", produktVersion: "1.0", erstellungsdatum: "20261015")

    /// Test Finanzamt and Steuernummer from the official samples.
    static func configuration(finanzamt: String = "1096", steuernummer: String = "1096081508187") -> TaxConfiguration {
        TaxConfiguration(
            settings: TaxSettingsPeriod(effectiveFrom: "2026-01-01"),
            identity: TaxIdentity(name: "Alois Mustermann", street: "Testgasse", houseNumber: "13a", postalCode: "08151",
                                  city: "Musterstadt", phone: "0815/99999999", email: "mustermann@example.com",
                                  steuernummer: steuernummer, finanzamt: finanzamt, vatID: "DE123456789"),
            testMode: true)
    }

    static func vat(_ rows: [(String, String)]) -> FieldInput {
        .vatRates(rows.map { VatRowInput(rate: $0.0, amount: $0.1) })
    }

    static func record(_ kind: Kind, _ uid: String, date: String, gross: String, _ treatment: VatTreatment,
                       _ fields: [String: FieldInput] = [:]) throws -> UStVARecord {
        var input = fields
        input["date"] = .text(date)
        input["gross_amount"] = .text(gross)
        input["vat_treatment"] = .text(treatment.rawValue)
        return UStVARecord(kind: kind, uid: uid, values: try RecordRules.prepareCreate(kind, input))
    }

    static func domestic(month: Int) throws -> [UStVARecord] {
        let date = String(format: "2026-%02d-15", month)
        return [
            try record(.income, "sale19", date: date, gross: "11900", .domestic, ["vat_rates": vat([("19", "1900")])]),
            try record(.income, "sale7", date: date, gross: "535", .domestic, ["vat_rates": vat([("7", "35")])]),
            try record(.expenses, "rent", date: date, gross: "416.50", .domesticVat, ["vat_rates": vat([("19", "66.50")]),
                                                                                    "category": .text("Rent")]),
            try record(.expenses, "phone", date: date, gross: "59.50", .domesticVat,
                       ["vat_rates": vat([("19", "9.50")]), "category": .text("Phone"), "deductible_amount": .text("29.75")]),
        ]
    }

    static func allTreatments(month: Int) throws -> [UStVARecord] {
        let date = String(format: "2026-%02d-10", month)
        return try domestic(month: month) + [
            try record(.income, "eu-service", date: date, gross: "2000.50", .euB2BService,
                       ["client_vat_number": .text("FR12345678901")]),
            try record(.income, "eu-goods", date: date, gross: "3000", .euB2BGoods,
                       ["client_vat_number": .text("ATU12345678")]),
            try record(.income, "export", date: date, gross: "800", .exportGoods),
            try record(.income, "non-eu", date: date, gross: "1500", .nonEUService),
            try record(.income, "damages", date: date, gross: "50", .notTaxable),
            try record(.expenses, "meal", date: date, gross: "71.40", .domesticVat,
                       ["vat_rates": vat([("19", "11.40")]), "category": .text("Business meals"),
                        "deductible_amount": .text("49.98")]),
            try record(.expenses, "irish-saas", date: date, gross: "100", .rcEUService),
            try record(.expenses, "us-saas", date: date, gross: "120", .rcNonEUService,
                       ["currency": .text("USD"), "currency_conversion_rate": .text("0.9172")]),
            try record(.expenses, "eu-goods19", date: date, gross: "500", .euGoodsAcquisition),
            try record(.expenses, "eu-goods7", date: date, gross: "200", .euGoodsAcquisition, ["vat_rates": vat([("7", "0")])]),
            try record(.expenses, "import", date: date, gross: "190", .importVat),
            try record(.expenses, "insurance", date: date, gross: "300", .noVat),
        ]
    }

    func ustva(_ records: [UStVARecord], _ period: VatPeriod, flags: UStVAFlags = [],
               sondervorauszahlung: Decimal? = nil) -> (xml: String, result: UStVAResult) {
        let configuration = Self.configuration()
        let result = UStVAAggregator.aggregate(records, period: period, configuration: configuration,
                                               sondervorauszahlung: sondervorauszahlung)
        let xml = UStVAXML.build(period: period, kennzahlen: result.kennzahlen, flags: flags,
                                 configuration: configuration, header: Self.header)
        return (xml, result)
    }

    /// Validates and prints every hint; fails on any rule error or other ERiC error.
    @discardableResult
    func expectValid(_ xml: String, _ scenario: String) async throws -> EricValidationResult {
        let result = try await Self.service.validate(xml: xml, datenartVersion: UStVAXML.datenartVersion(year: 2026))
        print("[\(scenario)] ERiC code \(result.code), \(result.errors.count) errors, \(result.hints.count) hints")
        for hint in result.hints { print("[\(scenario)]   hint \(hint)") }
        for error in result.errors { print("[\(scenario)]   ERROR \(error)") }
        if let text = result.errorText { print("[\(scenario)]   \(text)") }
        #expect(result.errors.isEmpty, "\(scenario): \(result.errors)")
        #expect(result.isValid, "\(scenario): code \(result.code) \(result.errorText ?? "") \(result.response)")
        return result
    }

    @Test func domesticOnly() async throws {
        let (xml, result) = ustva(try Self.domestic(month: 3), .month(2026, 3))
        #expect(result.kennzahlen.kz83 == dec("1863.75"))  // 1900 + 35 − 66.50 − 4.75 (phone: 50 % of 9.50)
        try await expectValid(xml, "domestic only")
    }

    @Test func everyTreatmentInOneMonth() async throws {
        let (xml, result) = ustva(try Self.allTreatments(month: 4), .month(2026, 4))
        for kz: Kennzahl in [.kz81, .kz86, .kz21, .kz41, .kz43, .kz45, .kz46, .kz47, .kz84, .kz85, .kz89, .kz93,
                             .kz61, .kz62, .kz66, .kz67] {
            #expect(result.kennzahlen[kz] != nil, "\(kz) missing")
        }
        try await expectValid(xml, "all treatments")
    }

    @Test func refund() async throws {
        let records = [
            try Self.record(.expenses, "laptop", date: "2026-05-04", gross: "5950", .domesticVat,
                            ["vat_rates": Self.vat([("19", "950")])]),
            try Self.record(.income, "small-sale", date: "2026-05-20", gross: "119", .domestic,
                            ["vat_rates": Self.vat([("19", "19")])]),
            try Self.record(.income, "credit-note", date: "2026-05-21", gross: "-59.50", .domestic,
                            ["vat_rates": Self.vat([("19", "-9.50")])]),
        ]
        let (xml, result) = ustva(records, .month(2026, 5), flags: [.offsetRefund])
        #expect(result.kennzahlen.kz83 == dec("-940.50"))
        try await expectValid(xml, "refund")
    }

    @Test func decemberWithSondervorauszahlungCredit() async throws {
        let (xml, result) = ustva(try Self.domestic(month: 12), .month(2026, 12), sondervorauszahlung: dec("1500.00"))
        #expect(result.kennzahlen[.kz39] == 1500)
        #expect(xml.contains("<Kz39>1500.00</Kz39>"))
        try await expectValid(xml, "December with Kz39")
    }

    @Test func sondervorauszahlung() async throws {
        let configuration = Self.configuration(finanzamt: "9198", steuernummer: "9198011310134")
        let xml = UStVAXML.buildSondervorauszahlung(year: 2026, amount: dec("1500.75"), configuration: configuration,
                                                    header: Self.header)
        #expect(xml.contains("<Kz38>1500</Kz38>"))
        try await expectValid(xml, "Sondervorauszahlung")
    }

    @Test func dauerfristverlaengerungApplication() async throws {
        let configuration = Self.configuration(finanzamt: "9198", steuernummer: "9198011310134")
        let xml = UStVAXML.buildDauerfristverlaengerung(year: 2026, configuration: configuration, header: Self.header)
        try await expectValid(xml, "Dauerfristverlängerung")
    }

    @Test func reportsRuleErrors() async throws {
        // Kz35 without Kz36 breaks the rule UStVA_Kz35_36_Gemeinsam.
        let (xml, _) = ustva(try Self.domestic(month: 3), .month(2026, 3))
        let broken = xml.replacingOccurrences(of: "<Kz81>", with: "<Kz35>10</Kz35>\n<Kz81>")
        let result = try await Self.service.validate(xml: broken, datenartVersion: "UStVA_2026")
        print("[broken] code \(result.code): \(result.errors)")
        #expect(!result.isValid)
        #expect(result.code == Int32(ERIC_GLOBAL_PRUEF_FEHLER_CODE))
        #expect(result.errors.contains { $0.regelName?.hasSuffix("/UStVA_Kz35_36_Gemeinsam") == true })
    }

    @Test func reportsSchemaErrorsWithTheirText() async throws {
        let result = try await Self.service.validate(xml: "<Elster/>", datenartVersion: "UStVA_2026")
        print("[schema] code \(result.code): \(result.errorText ?? "-")")
        #expect(!result.isValid)
        #expect(result.errorText?.isEmpty == false)
    }
}

/// ERIC_GLOBAL_PRUEF_FEHLER (eric_fehlercodes.h).
let ERIC_GLOBAL_PRUEF_FEHLER_CODE = 610001002

func dec(_ s: String) -> Decimal { Decimal(string: s, locale: Locale(identifier: "en_US_POSIX"))! }

struct EricValidationResultTests {
    @Test func parsesErrorsAndHints() throws {
        let xml = """
            <?xml version="1.0" encoding="UTF-8"?>
            <EricBearbeiteVorgang xmlns="http://www.elster.de/EricXML/1.1/EricBearbeiteVorgang">
                <FehlerRegelpruefung>
                    <Nutzdatenticket>1</Nutzdatenticket>
                    <Feldidentifikator>/Anmeldungssteuern[1]/Steuerfall[1]/Umsatzsteuervoranmeldung[1]/Kz35[1]</Feldidentifikator>
                    <RegelName>UStVA_Kz35_36_Gemeinsam</RegelName>
                    <FachlicheFehlerId>110085065</FachlicheFehlerId>
                    <Text>Die Felder sind gemeinsam einzugeben.</Text>
                </FehlerRegelpruefung>
                <Hinweis>
                    <Nutzdatenticket>1</Nutzdatenticket>
                    <RegelName>WIdNr_Hinweis</RegelName>
                    <FachlicheHinweisId>11085154</FachlicheHinweisId>
                    <Text>Bitte geben Sie Ihre W-IdNr. an.</Text>
                </Hinweis>
            </EricBearbeiteVorgang>
            """
        let parsed = try #require(EricValidationResult.parse(xml))
        #expect(parsed.errors == [.init(nutzdatenticket: "1",
                                        feldidentifikator: "/Anmeldungssteuern[1]/Steuerfall[1]/Umsatzsteuervoranmeldung[1]/Kz35[1]",
                                        regelName: "UStVA_Kz35_36_Gemeinsam", fachlicheID: "110085065",
                                        text: "Die Felder sind gemeinsam einzugeben.")])
        #expect(parsed.hints == [.init(nutzdatenticket: "1", regelName: "WIdNr_Hinweis", fachlicheID: "11085154",
                                       text: "Bitte geben Sie Ihre W-IdNr. an.")])
        #expect(EricValidationResult(code: 610001003, hints: parsed.hints).isValid)
        #expect(!EricValidationResult(code: 610001002, errors: parsed.errors).isValid)
        #expect(!EricValidationResult(code: 610301001).isValid)
        #expect(EricValidationResult.parse("")?.errors == [])
        #expect(EricValidationResult.parse("<a>") == nil)
    }
}
