import Foundation
import SwiftData
import Testing
@testable import BrotBooksKit

@Suite struct ZMXMLTests {
    typealias F = UStVAFixtures

    static let records: [UStVARecord] = [
        F.income("goods-pl", date: "2026-05-04", gross: "12000.80", .euB2BGoods,
                 ["client_vat_number": .text("PL5630292567")]),
        F.income("goods-pl2", date: "2026-05-20", gross: "999", .euB2BGoods, ["client_vat_number": .text("PL 563 029 2567")]),
        F.income("service-dk", date: "2026-05-11", gross: "2500.99", .euB2BService,
                 ["client_vat_number": .text("DK13585627")]),
        F.income("service-fr", date: "2026-05-30", gross: "0.75", .euB2BService, ["client_vat_number": .text("FR12345678901")]),
        F.income("domestic", date: "2026-05-04", gross: "1190", .domestic, ["vat_rates": F.vat([("19", "190")])]),
    ]

    @Test func goldenMonthlyReport() throws {
        let lines = UStVAAggregator.zmLines(Self.records, period: .month(2026, 5), configuration: F.configuration())
        let report = ZMReport.initial(lines)
        // The FR line truncates to 0 € and is left out of the first report.
        #expect(report.lines == [
            ZMReportLine(customerVatID: "DK13585627", umsatzart: .service, amount: 2500),
            ZMReportLine(customerVatID: "PL5630292567", umsatzart: .goods, amount: 12999),
        ])
        let xml = ZMXML.build(period: .month(2026, 5), report: report, configuration: F.configuration(), header: F.header)
        try UStVAXMLTests().expectGolden(xml, "ZMDO_2026_05.golden.xml")
        #expect(xml.contains("<Empfaenger id=\"L\">BF</Empfaenger>"))
        #expect(xml.contains("<quart>25</quart>"))
        #expect(xml.contains("<Testmerker>700000004</Testmerker>"))
        #expect(xml.contains("<HerstellerID>27425</HerstellerID>"))
    }

    @Test func productionCorrectionWithoutTestMarker() {
        let report = ZMReport(meldeart: .corrected, lines: [ZMReportLine(customerVatID: "ATU12345678", umsatzart: .goods,
                                                                         amount: 0)])
        let xml = ZMXML.build(period: .quarter(2026, 2), report: report, configuration: F.configuration(testMode: false),
                              header: F.header)
        #expect(!xml.contains("Testmerker"))
        #expect(xml.contains(#"<zm-zeilen waehrung="1" meldeart="11">"#))
        #expect(xml.contains("<quart>2</quart>"))
        #expect(xml.contains("<betrag>0</betrag>"))
    }

    @Test(arguments: Array(1...12))
    func monthCodes(month: Int) {
        #expect(ZMMeldezeitraum(.month(2026, month)).rawValue == 20 + month)
        #expect(ZMMeldezeitraum(.month(2026, month)).isMonth)
    }

    @Test func allPeriodCodes() {
        #expect((1...4).map { ZMMeldezeitraum(.quarter(2026, $0)) } == [.firstQuarter, .secondQuarter, .thirdQuarter, .fourthQuarter])
        #expect((1...4).map { ZMMeldezeitraum(.quarter(2026, $0)).rawValue } == [1, 2, 3, 4])
        #expect(!ZMMeldezeitraum(.quarter(2026, 1)).isMonth)
        #expect(ZMMeldezeitraum(.month(2021, 5)) == .may)
        #expect(ZMMeldezeitraum.may.rawValue == 25)  // the sample's `quart` 25: monthly ZM for May
        #expect(ZMMeldezeitraum(.month(2026, 12)) == .december)
        #expect(ZMMeldezeitraum.allCases.map(\.rawValue) == [1, 2, 3, 4] + Array(21...32))
    }

    @Test func addressSplitsTheHouseNumberAndOmitsAnInvalidPhone() {
        var configuration = F.configuration()
        configuration.identity.phone = "call me"
        let xml = ZMXML.build(period: .month(2026, 5), report: ZMReport(meldeart: .initial, lines: []),
                              configuration: configuration, header: F.header)
        #expect(xml.contains("<strasse>Testgasse</strasse>"))
        #expect(xml.contains("<hausnr>13</hausnr>"))
        #expect(xml.contains("<hausnrzusatz>a</hausnrzusatz>"))
        #expect(!xml.contains("<telefon>"))
        #expect(xml.contains("<staat>DE</staat>"))
    }

    @Test func missingIdentityForTheZM() {
        #expect(F.identity.missingForZM.isEmpty)
        var identity = F.identity
        identity.vatID = "DE12345"
        identity.postalCode = ""
        #expect(identity.missingForZM == [.vatID, .address])
        identity.vatID = "de 123456789"
        identity.postalCode = "08151"
        identity.name = " "
        #expect(identity.missingForZM == [.name])
    }
}

@Suite struct ZMAggregationTests {
    typealias F = UStVAFixtures

    /// §18a(8) UStG: the ZM follows the invoice date, not the payment, so Ist doesn't move ZM lines.
    @Test func zmLinesFollowTheInvoiceDateUnderIst() {
        let records = [
            F.income("march-paid-april", date: "2026-03-20", gross: "1000", .euB2BService,
                     ["client_vat_number": .text("FR12345678901"), "payment_status": .text("Paid"),
                      "payment_date": .text("2026-04-05")]),
            F.income("march-unpaid", date: "2026-03-25", gross: "500", .euB2BGoods,
                     ["client_vat_number": .text("ATU12345678")]),
        ]
        let ist = F.configuration(.ist)
        let march = UStVAAggregator.aggregate(records, period: .month(2026, 3), configuration: ist)
        let april = UStVAAggregator.aggregate(records, period: .month(2026, 4), configuration: ist)
        // The UStVA follows the payment …
        #expect(march.kennzahlen[.kz21] == nil)
        #expect(april.kennzahlen[.kz21] == 1000)
        // … the ZM follows the invoice date.
        #expect(march.zmLines.map(\.recordUIDs) == [["march-unpaid"], ["march-paid-april"]])
        #expect(april.zmLines.isEmpty)
        #expect(UStVAAggregator.zmLines(records, period: .month(2026, 3), configuration: ist) == march.zmLines)
        #expect(UStVAAggregator.zmLines(records, period: .quarter(2026, 1), configuration: ist).count == 2)
    }

    @Test func sollIsUnchanged() {
        let records = [F.income("eu", date: "2026-03-20", gross: "1000", .euB2BService,
                                ["client_vat_number": .text("FR12345678901")])]
        let result = UStVAAggregator.aggregate(records, period: .month(2026, 3), configuration: F.configuration())
        #expect(result.zmLines == UStVAAggregator.zmLines(records, period: .month(2026, 3), configuration: F.configuration()))
        #expect(result.zmLines.first?.amount == 1000)
    }
}

@Suite struct ZMReportTests {
    func line(_ id: String, _ art: ZMUmsatzart, _ amount: String) -> ZMLine {
        ZMLine(customerVatID: id, umsatzart: art, amount: dec(amount), recordUIDs: [])
    }

    func report(_ id: String, _ art: ZMUmsatzart, _ amount: Decimal) -> ZMReportLine {
        ZMReportLine(customerVatID: id, umsatzart: art, amount: amount)
    }

    @Test func firstReportHasWholeEurosWithoutZeroLines() {
        let initial = ZMReport.initial([
            line("FR1", .service, "100.99"), line("AT1", .goods, "0.99"), line("PL1", .goods, "-250.50"),
        ])
        #expect(initial.meldeart == .initial)
        #expect(initial.lines == [report("FR1", .service, 100), report("PL1", .goods, -250)])
        #expect(initial.total == -150)
        #expect(ZMReport.initial([line("AT1", .goods, "-0.5")]).lines.isEmpty)
    }

    @Test func correctionSendsChangedNewAndCancelledLinesOnly() {
        let filed = [report("AT1", .goods, 1000), report("FR1", .service, 500), report("ES111111113", .goods, 21000),
                     report("IT1", .service, 300)]
        let current = [report("AT1", .goods, 1000),            // unchanged: not repeated
                       report("FR1", .service, 400),           // wrong amount: full corrected amount
                       report("ES111111112", .goods, 21000),   // wrong VAT ID: new line …
                       report("IT1", .goods, 300),             // wrong Umsatzart: new line …
                       report("NL1", .service, 50)]            // missing sale
        let correction = ZMReport.correction(current: current, filed: filed)
        #expect(correction.meldeart == .corrected)
        #expect(correction.lines == [
            report("ES111111112", .goods, 21000), report("ES111111113", .goods, 0),  // … and the old one cancelled
            report("FR1", .service, 400), report("IT1", .goods, 300), report("IT1", .service, 0),
            report("NL1", .service, 50),
        ])
    }

    @Test func nothingChangedMeansAnEmptyCorrection() {
        let filed = [report("AT1", .goods, 1000)]
        #expect(ZMReport.correction(current: filed, filed: filed).lines.isEmpty)
        #expect(ZMReport.make([line("AT1", .goods, "1000.40")], filed: filed).lines.isEmpty)
        #expect(ZMReport.make([line("AT1", .goods, "1000.40")], filed: nil) == ZMReport(meldeart: .initial,
                                                                                         lines: filed))
        // Everything credited away: the filed line is cancelled.
        #expect(ZMReport.make([], filed: filed).lines == [report("AT1", .goods, 0)])
    }

    @Test func correctionBasisComesFromTheCountedProductionFiling() {
        let lines = [report("AT1", .goods, 1000)]
        #expect(VatFilings([]).zmCorrectionBasis == .none)
        #expect(VatFilings([VatFilingEntry(itemID: "2026-03-zm", state: .accepted, isTest: true, zmLines: lines)])
            .zmCorrectionBasis == .none)
        #expect(VatFilings([VatFilingEntry(itemID: "2026-03-zm", state: .rejected, zmLines: lines)])
            .zmCorrectionBasis == .none)
        let accepted = VatFilingEntry(itemID: "2026-03-zm", state: .accepted, date: Date(timeIntervalSince1970: 1),
                                      zmLines: lines)
        #expect(VatFilings([accepted]).zmCorrectionBasis == .filed(lines))
        let corrected = [report("AT1", .goods, 900)]
        let correction = VatFilingEntry(itemID: "2026-03-zm", state: .accepted, isCorrection: true,
                                        date: Date(timeIntervalSince1970: 2), zmLines: corrected)
        #expect(VatFilings([accepted, correction]).zmCorrectionBasis == .filed(corrected))
        #expect(VatFilings([VatFilingEntry(itemID: "2026-03-zm", state: .filedElsewhere)]).zmCorrectionBasis == .unknown)
        #expect(VatFilings([accepted]).entries.first?.amount == 1000)
    }
}

@MainActor
@Suite struct ZMFilingStoreTests {
    typealias F = UStVAFixtures

    @Test func storesTheLinesAndTheCorrectionFlag() throws {
        let config = ModelConfiguration(schema: StoreSchema.schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        let container = try ModelContainer(for: StoreSchema.schema, configurations: [config])
        let context = container.mainContext
        let items = VatReturnSchedule.items(years: [2026], settings: TaxSettings(identity: F.identity,
                                                                                periods: [.initial(from: "2026-01-01")]))
        let item = try #require(items.first { $0.id == "2026-03-zm" })
        let lines = [ZMReportLine(customerVatID: "AT1", umsatzart: .goods, amount: -12)]
        let report = ZMReport(meldeart: .corrected, lines: lines)
        context.insert(VatFiling(item: item, state: .accepted, kennzahlen: [:], flags: [], isTest: false,
                                 zmReport: report, zmLines: lines))
        context.insert(VatFiling(filedElsewhere: item, amount: 99, filedOn: "2026-04-20"))
        try context.save()
        let stored = try VatFiling.all(for: "2026-03-zm", in: context)
        #expect(stored.count == 2)
        let sent = try #require(stored.first { $0.filingState == .accepted })
        #expect(sent.kind == "zm")
        #expect(sent.zeitraum == "03")
        #expect(sent.datenartVersion == "ZMDO")
        #expect(sent.isCorrection)
        #expect(sent.kz83 == nil)
        #expect(sent.filedZMLines == lines)
        let elsewhere = try #require(stored.first { $0.filingState == .filedElsewhere })
        #expect(elsewhere.filedZMLines == nil)
        #expect(elsewhere.filedKennzahlen.isEmpty)
    }
}

@Suite struct ZMScheduleTests {
    typealias F = UStVAFixtures

    func settings(_ periods: [TaxSettingsPeriod]) -> TaxSettings { TaxSettings(identity: F.identity, periods: periods) }

    @Test func monthlyZMItemsAreDueOnThe25thRegardlessOfTheExtension() {
        let items = VatReturnSchedule.items(years: [2026], settings: settings([.initial(from: "2026-01-01")]))
        let zm = items.filter { $0.zmPeriod != nil }
        #expect(zm.map(\.id) == (1...12).reversed().map { String(format: "2026-%02d-zm", $0) })
        let march = try! #require(zm.first { $0.id == "2026-03-zm" })
        #expect(march.dueDate == "2026-04-25")
        #expect(march.fileableFrom == "2026-04-01")
        #expect(march.datenartVersion == "ZMDO")
        #expect(march.filingKind == .zm)
        #expect(march.availableFlags.isEmpty)
        #expect(march.period == nil)
        #expect(march.aggregate([]) == nil)
        #expect(zm.first { $0.id == "2026-12-zm" }?.dueDate == "2027-01-25")
    }

    @Test func quarterlyAndChangingZMFrequency() {
        let s = settings([
            TaxSettingsPeriod(effectiveFrom: "2026-01-01", zmFrequency: .quarterly),
            TaxSettingsPeriod(effectiveFrom: "2026-04-01", zmFrequency: .monthly),
            TaxSettingsPeriod(effectiveFrom: "2026-10-01", zmFrequency: .quarterly),
        ])
        let zm = VatReturnSchedule.items(years: [2026], settings: s).filter { $0.zmPeriod != nil }
        #expect(zm.map(\.id) == ["2026-44-zm", "2026-09-zm", "2026-08-zm", "2026-07-zm", "2026-06-zm", "2026-05-zm",
                                 "2026-04-zm", "2026-41-zm"])
        #expect(zm.first { $0.id == "2026-41-zm" }?.dueDate == "2026-04-25")
        #expect(zm.first { $0.id == "2026-44-zm" }?.dueDate == "2027-01-25")
    }

    @Test func listOrderPutsEachZMAfterItsUStVA() {
        let monthly = VatReturnSchedule.items(years: [2026], settings: settings([.initial(from: "2026-01-01")]))
        let ordered = VatReturnSchedule.listOrder(monthly).map(\.id)
        #expect(ordered.count == monthly.count)
        #expect(Array(ordered.prefix(4)) == ["2026-12", "2026-12-zm", "2026-11", "2026-11-zm"])
        #expect(ordered.last == "2026-sondervorauszahlung")

        // Quarterly UStVA with monthly ZM: the three months follow the quarter, newest first.
        let quarterly = VatReturnSchedule.items(years: [2026], settings: settings([
            TaxSettingsPeriod(effectiveFrom: "2026-01-01", ustvaFrequency: .quarterly),
        ]))
        let q = VatReturnSchedule.listOrder(quarterly).map(\.id)
        #expect(Array(q.prefix(4)) == ["2026-44", "2026-12-zm", "2026-11-zm", "2026-10-zm"])

        // Annual-only UStVA: the ZM items stay in due-date order.
        let annual = VatReturnSchedule.items(years: [2026], settings: settings([
            TaxSettingsPeriod(effectiveFrom: "2026-01-01", ustvaFrequency: .none),
        ]))
        #expect(VatReturnSchedule.listOrder(annual).map(\.id) == annual.map(\.id))
    }

    @Test func emptyPeriodHasNothingToReportOnceItEnded() {
        let items = VatReturnSchedule.items(years: [2026], settings: settings([.initial(from: "2026-01-01")]))
        let march = items.first { $0.id == "2026-03-zm" }!
        #expect(VatReturnStatus.of(march, today: "2026-03-31", nothingToReport: true) == .notDue)
        #expect(VatReturnStatus.of(march, today: "2026-04-01", nothingToReport: true) == .nothingToReport)
        #expect(VatReturnStatus.of(march, today: "2026-12-01", nothingToReport: true) == .nothingToReport)
        #expect(!VatReturnStatus.nothingToReport.isOpen)
        #expect(VatReturnStatus.of(march, today: "2026-04-26") == .overdue(days: 1))
        #expect(VatReturnStatus.of(march, today: "2026-04-26", filing: .production, nothingToReport: true) == .filed)
    }

    @Test func sondervorauszahlungBasisSkipsTheZM() {
        let s = settings([.initial(from: "2025-01-01")])
        let prior = VatReturnSchedule.items(years: [2025], settings: s)
        let filings = prior.filter { $0.period != nil }.map {
            VatFilingEntry(itemID: $0.id, state: .filedElsewhere, kennzahlen: [.kz83: 100])
        }
        let basis = SondervorauszahlungBasis.compute(year: 2026, priorYearItems: prior, filings: filings)
        #expect(basis?.kz83Total == 1200)
        // Only the unfiled Sondervorauszahlung is missing; the ZM items are not part of the basis.
        #expect(basis?.missing == [.sondervorauszahlung(year: 2025)])
    }
}

@Suite struct ZMConsistencyTests {
    typealias F = UStVAFixtures

    func line(_ art: ZMUmsatzart, _ amount: String, _ id: String = "AT1") -> ZMLine {
        ZMLine(customerVatID: id, umsatzart: art, amount: dec(amount), recordUIDs: [])
    }

    func kennzahlen(_ values: [Kennzahl: Decimal]) -> Kennzahlen { Kennzahlen(values: values, form: .ustva2026) }

    @Test func monthlyZMMatchesTheMonthlyUStVA() throws {
        let check = try #require(ZMConsistency.check(
            zmPeriod: .month(2026, 3), zmLines: [.month(2026, 3): [line(.goods, "1000.80"), line(.service, "250.10", "FR1")]],
            ustva: [.month(2026, 3): kennzahlen([.kz41: 1000, .kz21: 250]), .month(2026, 4): kennzahlen([.kz41: 7])]))
        #expect(check.matches)
        #expect(check.ustvaPeriods == [.month(2026, 3)])
        #expect(check.comparisons.map(\.zmTotal) == [1000, 250])
    }

    @Test func aMismatchIsReportedPerUmsatzart() throws {
        let check = try #require(ZMConsistency.check(
            zmPeriod: .month(2026, 3), zmLines: [.month(2026, 3): [line(.goods, "1000"), line(.service, "250", "FR1")]],
            ustva: [.month(2026, 3): kennzahlen([.kz41: 1000, .kz21: 300])]))
        #expect(!check.matches)
        #expect(check.comparisons[0].matches)
        #expect(check.comparisons[1].kennzahl == .kz21)
        #expect(check.comparisons[1].difference == -50)
    }

    @Test func quarterlyZMSumsTheThreeMonthlyUStVAs() throws {
        let zm = [line(.goods, "900.90"), line(.goods, "600.90", "PL1")]  // 900 + 600 as filed
        // Monthly Kz41 300.6, 600.6, 600.6 → 300 + 600 + 600 as filed: within the 5 truncations.
        let ustva: [VatPeriod: Kennzahlen] = [
            .month(2026, 1): kennzahlen([.kz41: 300]), .month(2026, 2): kennzahlen([.kz41: 600]),
            .month(2026, 3): kennzahlen([.kz41: 600]), .month(2026, 4): kennzahlen([.kz41: 5000]),
        ]
        let check = try #require(ZMConsistency.check(zmPeriod: .quarter(2026, 1), zmLines: [.quarter(2026, 1): zm],
                                                     ustva: ustva))
        #expect(check.ustvaPeriods == [.month(2026, 1), .month(2026, 2), .month(2026, 3)])
        #expect(check.comparisons[0].zmTotal == 1500)
        #expect(check.comparisons[0].ustvaTotal == 1500)
        #expect(check.matches)
        // Rounding stays below one euro per truncated amount; more is a mismatch.
        var off = ustva
        off[.month(2026, 2)] = kennzahlen([.kz41: 595])
        #expect(ZMConsistency.check(zmPeriod: .quarter(2026, 1), zmLines: [.quarter(2026, 1): zm], ustva: off)?.matches
            == false)
        off[.month(2026, 2)] = kennzahlen([.kz41: 598])
        #expect(ZMConsistency.check(zmPeriod: .quarter(2026, 1), zmLines: [.quarter(2026, 1): zm], ustva: off)?.matches
            == true)
    }

    @Test func monthlyZMsAreSummedForAQuarterlyUStVA() throws {
        let zm: [VatPeriod: [ZMLine]] = [
            .month(2026, 4): [line(.service, "100", "FR1")], .month(2026, 5): [],
            .month(2026, 6): [line(.service, "200", "FR1")], .month(2026, 7): [line(.service, "999", "FR1")],
        ]
        let check = try #require(ZMConsistency.check(zmPeriod: .month(2026, 5), zmLines: zm,
                                                     ustva: [.quarter(2026, 2): kennzahlen([.kz21: 300])]))
        #expect(check.zmPeriods == [.month(2026, 4), .month(2026, 5), .month(2026, 6)])
        #expect(check.comparisons[1].zmTotal == 300)
        #expect(check.matches)
    }

    @Test func noUStVAMeansNoCheck() {
        #expect(ZMConsistency.check(zmPeriod: .month(2026, 3), zmLines: [.month(2026, 3): [line(.goods, "1")]],
                                    ustva: [:]) == nil)
    }

    @Test func aggregatedPeriodsAgree() throws {
        let records = [
            F.income("a", date: "2026-01-10", gross: "1000.70", .euB2BGoods, ["client_vat_number": .text("ATU12345678")]),
            F.income("b", date: "2026-02-10", gross: "1000.70", .euB2BGoods, ["client_vat_number": .text("ATU12345678")]),
            F.income("c", date: "2026-03-10", gross: "1000.70", .euB2BGoods, ["client_vat_number": .text("ATU12345678")]),
        ]
        let configuration = F.configuration()
        var ustva: [VatPeriod: Kennzahlen] = [:]
        for month in 1...3 {
            ustva[.month(2026, month)] = UStVAAggregator.aggregate(records, period: .month(2026, month),
                                                                  configuration: configuration).kennzahlen
        }
        let quarter = VatPeriod.quarter(2026, 1)
        let lines = UStVAAggregator.zmLines(records, period: quarter, configuration: configuration)
        let check = try #require(ZMConsistency.check(zmPeriod: quarter, zmLines: [quarter: lines], ustva: ustva))
        // ZM 3002 (3002.10 truncated) vs. 1000 × 3 per month: rounding only.
        #expect(check.comparisons[0].zmTotal == 3002)
        #expect(check.comparisons[0].ustvaTotal == 3000)
        #expect(check.matches)
    }
}
