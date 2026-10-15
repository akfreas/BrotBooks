import BrotBooksKit
import Foundation
import Testing
@testable import EricKit

/// Preview PDF, Steuernummer conversion and the Finanzamt lists against the real ERiC (nothing is sent).
/// Skipped when ERiC has not been vendored.
@Suite(.serialized, .enabled(if: FileManager.default.fileExists(atPath: vendoredERiC.appending(path: "libericapi.dylib").path),
                             "Vendor/ERiC missing: run scripts/vendor-eric.sh <jar>"))
struct EricLookupAndPreviewLiveTests {
    static let service = EricService(
        ericDirectory: vendoredERiC,
        logDirectory: FileManager.default.temporaryDirectory.appending(path: "EricKitTests-Lookup-\(UUID().uuidString)"))

    typealias U = UStVAValidationLiveTests

    @Test func previewOfAGeneratedUStVAIsAPDF() async throws {
        let configuration = U.configuration()
        let period = VatPeriod.month(2026, 3)
        let result = UStVAAggregator.aggregate(try U.domestic(month: 3), period: period, configuration: configuration)
        let xml = UStVAXML.build(period: period, kennzahlen: result.kennzahlen, configuration: configuration,
                                 header: U.header)

        let preview = try await Self.service.preview(xml: xml, datenartVersion: UStVAXML.datenartVersion(year: 2026))
        print("[preview] code \(preview.validation.code), \(preview.documents.count) PDF(s): "
              + preview.documents.map { "\($0.name) \($0.data.count) bytes" }.joined(separator: ", "))
        #expect(preview.validation.isValid, "\(preview.validation.errors) \(preview.validation.errorText ?? "")")
        #expect(preview.documents.count == 1)
        let pdf = try #require(preview.pdf)
        #expect(pdf.count > 1_000)
        #expect(pdf.starts(with: Data("%PDF".utf8)))
    }

    @Test func previewOfInvalidDataHasErrorsAndNoPDF() async throws {
        let (xml, _) = UStVAValidationLiveTests().ustva(try U.domestic(month: 3), .month(2026, 3))
        let broken = xml.replacingOccurrences(of: "<Kz81>", with: "<Kz35>10</Kz35>\n<Kz81>")
        let preview = try await Self.service.preview(xml: broken, datenartVersion: "UStVA_2026")
        print("[preview broken] code \(preview.validation.code): \(preview.validation.errors)")
        #expect(!preview.validation.isValid)
        #expect(!preview.validation.errors.isEmpty)
        #expect(preview.pdf == nil)
    }

    /// The Bavarian test Steuernummer from EHB table 6-5, the Saarland test office 1096 of the ERiC samples
    /// (`1096081508187`), and the `BBB/UUUUP` notation that needs the Bundesfinanzamtsnummer.
    @Test func convertsRegionalSteuernummern() async throws {
        #expect(try await Self.service.makeElsterSteuernummer("198/113/10010", landesnummer: "91") == "9198011310010")
        #expect(try await Self.service.makeElsterSteuernummer("198/113/10010", bundesfinanzamtsnummer: "9198")
                == "9198011310010")
        #expect(try await Self.service.makeElsterSteuernummer("113/10010", bundesfinanzamtsnummer: "9198")
                == "9198011310010")
        #expect(try await Self.service.makeElsterSteuernummer("096/815/08187", landesnummer: "10") == "1096081508187")
        try await Self.service.checkSteuernummer("9198011310010")
        try await Self.service.checkSteuernummer("1096081508187")
    }

    @Test func reportsInvalidSteuernummernWithERiCsText() async throws {
        let invalid = 610001034  // ERIC_GLOBAL_STEUERNUMMER_UNGUELTIG
        await #expect(throws: EricError.callFailed(function: "EricMtMakeElsterStnr", code: Int32(invalid))) {
            try await Self.service.makeElsterSteuernummer("198/113/10011", landesnummer: "91")
        }
        // BBB/UUUUP without the Bundesfinanzamtsnummer.
        await #expect(throws: EricError.self) {
            try await Self.service.makeElsterSteuernummer("113/10010", landesnummer: "91")
        }
        await #expect(throws: EricError.callFailed(function: "EricMtPruefeSteuernummer", code: Int32(invalid))) {
            try await Self.service.checkSteuernummer("9198011310011")
        }
        let text = await Self.service.errorText(for: Int32(invalid))
        print("[stnr] \(text ?? "-")")
        #expect(text?.isEmpty == false)
    }

    @Test func listsBundeslaenderAndFinanzaemter() async throws {
        let laender = try await Self.service.bundeslaender()
        print("[laender] \(laender.count): \(laender.map { "\($0.nummer) \($0.name)" }.joined(separator: "; "))")
        #expect(laender.contains(EricFinanzamtLand(nummer: "11", name: "Berlin")))
        #expect(laender.contains(EricFinanzamtLand(nummer: "28", name: "Baden-Württemberg")))
        #expect(laender.contains { $0.nummer == "91" })

        let berlin = try await Self.service.finanzaemter(landNummer: "11")
        print("[finanzaemter 11] \(berlin.count), first \(berlin.first.map { "\($0.bufaNummer) \($0.name)" } ?? "-")")
        #expect(berlin.contains(EricFinanzamt(bufaNummer: "1113", name: "Finanzamt Charlottenburg")))
        #expect(berlin.allSatisfy { $0.bufaNummer.hasPrefix("11") && $0.bufaNummer.count == 4 })
        let bayern = try await Self.service.finanzaemter(landNummer: "91")
        #expect(bayern.contains { $0.bufaNummer == "9102" && $0.name == "Finanzamt Augsburg-Land" })
    }

    /// With a W-IdNr. configured, ERiC's `WIdNr_Hinweis` goes away.
    @Test func wIdNrRemovesTheHint() async throws {
        let period = VatPeriod.month(2026, 3)
        var configuration = U.configuration()
        let result = UStVAAggregator.aggregate(try U.domestic(month: 3), period: period, configuration: configuration)
        func hints() async throws -> [EricValidationResult.Message] {
            let xml = UStVAXML.build(period: period, kennzahlen: result.kennzahlen, configuration: configuration,
                                     header: U.header)
            let validation = try await Self.service.validate(xml: xml, datenartVersion: "UStVA_2026")
            #expect(validation.isValid, "\(validation.errors)")
            return validation.hints
        }
        configuration.identity.wIdNr = ""
        let without = try await hints()
        print("[wIdNr] without: \(without)")
        #expect(without.contains { $0.regelName?.contains("WIdNr") == true })

        configuration.identity.wIdNr = "DE123456788-00001"
        let with = try await hints()
        print("[wIdNr] with: \(with)")
        #expect(!with.contains { $0.regelName?.contains("WIdNr") == true })
    }
}

struct EricFinanzamtListTests {
    @Test func parsesFinanzamtLandNummern() throws {
        let xml = """
            <?xml version="1.0" encoding="UTF-8"?>
            <EricHoleFinanzamtLandNummern xmlns="http://www.elster.de/EricXML/1.0/EricHoleFinanzamtLandNummern">
            \t<FinanzamtLand>
            \t\t<FinanzamtLandNummer>28</FinanzamtLandNummer>
            \t\t<Name>Baden-Württemberg</Name>
            \t</FinanzamtLand>
            \t<FinanzamtLand>
            \t\t<FinanzamtLandNummer>91</FinanzamtLandNummer>
            \t\t<Name>Bayern (Zuständigkeit LfSt - München)</Name>
            \t</FinanzamtLand>
            \t<FinanzamtLand>
            \t\t<FinanzamtLandNummer>11</FinanzamtLandNummer>
            \t\t<Name>Berlin</Name>
            \t</FinanzamtLand>
            </EricHoleFinanzamtLandNummern>
            """
        #expect(EricFinanzamtLand.parse(xml) == [
            EricFinanzamtLand(nummer: "28", name: "Baden-Württemberg"),
            EricFinanzamtLand(nummer: "91", name: "Bayern (Zuständigkeit LfSt - München)"),
            EricFinanzamtLand(nummer: "11", name: "Berlin"),
        ])
    }

    @Test func parsesFinanzaemter() throws {
        let xml = """
            <?xml version="1.0" encoding="UTF-8"?>
            <EricHoleFinanzaemter xmlns="http://www.elster.de/EricXML/1.0/EricHoleFinanzaemter">
            \t<Finanzamt>
            \t\t<BuFaNummer>1113</BuFaNummer>
            \t\t<Name>Finanzamt Charlottenburg</Name>
            \t</Finanzamt>
            \t<Finanzamt>
            \t\t<BuFaNummer>1116</BuFaNummer>
            \t\t<Name>Finanzamt Neukölln</Name>
            \t</Finanzamt>
            </EricHoleFinanzaemter>
            """
        #expect(EricFinanzamt.parse(xml) == [
            EricFinanzamt(bufaNummer: "1113", name: "Finanzamt Charlottenburg"),
            EricFinanzamt(bufaNummer: "1116", name: "Finanzamt Neukölln"),
        ])
        #expect(EricFinanzamt.parse("<EricHoleFinanzaemter/>") == [])
        #expect(EricFinanzamt.parse("<EricHoleFinanzaemter><Finanzamt>") == nil)
    }

    @Test func previewResultPicksTheFirstDocument() {
        let empty = EricPreviewResult(validation: EricValidationResult(code: 610001002), documents: [])
        #expect(empty.pdf == nil)
        let one = EricPreviewResult(validation: EricValidationResult(code: 0),
                                    documents: [.init(name: "a", data: Data("%PDF-1.4".utf8))])
        #expect(one.pdf == Data("%PDF-1.4".utf8))
    }
}
