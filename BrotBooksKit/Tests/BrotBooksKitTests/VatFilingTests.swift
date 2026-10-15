import Foundation
import SwiftData
import Testing
@testable import BrotBooksKit

@MainActor
@Suite struct VatFilingModelTests {
    typealias F = UStVAFixtures

    let items = VatReturnSchedule.items(years: [2026], settings: TaxSettings(identity: F.identity,
                                                                            periods: [.initial(from: "2026-01-01")]))
    func item(_ id: String) -> VatReturnItem { items.first { $0.id == id }! }

    func context() throws -> (ModelContainer, ModelContext) {
        let config = ModelConfiguration(schema: StoreSchema.schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        let container = try ModelContainer(for: StoreSchema.schema, configurations: [config])
        return (container, container.mainContext)
    }

    @Test func roundTripsThroughTheStore() throws {
        let (container, context) = try context()
        _ = container
        let march = item("2026-03")
        let result = march.aggregate([F.income("i", gross: "1190", .domestic, ["vat_rates": F.vat([("19", "190")])])])!
        let sentAt = Date(timeIntervalSince1970: 1_791_000_000)
        let filing = VatFiling(item: march, state: .accepted, kennzahlen: result.kennzahlen.values,
                               flags: [.correction, .noDirectDebit], isTest: true, sentAt: sentAt)
        filing.ticket = "eh2881d1ry5uyb4j1jp72511y7wkp4t9"
        filing.requestXML = "<Elster/>"
        filing.serverResponse = "<Elster><TransferHeader/></Elster>"
        filing.protocolPath = VatFiling.protocolPath(itemID: march.id, year: 2026, sentAt: sentAt, isTest: true)
        context.insert(filing)
        // A rejected attempt of another return, and a return filed elsewhere.
        context.insert(VatFiling(item: item("2026-04"), state: .rejected, kennzahlen: [:], flags: [], isTest: false))
        context.insert(VatFiling(filedElsewhere: item("2026-sondervorauszahlung"), amount: 1500, filedOn: "2026-02-09"))
        try context.save()

        let stored = try VatFiling.all(for: "2026-03", in: context)
        #expect(stored.count == 1)
        let read = try #require(stored.first)
        #expect(read.kind == "ustva")
        #expect(read.year == 2026)
        #expect(read.zeitraum == "03")
        #expect(read.datenartVersion == "UStVA_2026")
        #expect(read.filingState == .accepted)
        #expect(read.isTest)
        #expect(read.isCorrection)
        #expect(read.flags == UStVAFlags([.correction, .noDirectDebit]).rawValue)
        #expect(read.kz83 == "190")
        #expect(read.filedKennzahlen == [.kz81: 1000, .kz83: 190])
        #expect(String(decoding: read.kennzahlen!, as: UTF8.self) == #"{"81":"1000","83":"190"}"#)
        #expect(read.ticket == "eh2881d1ry5uyb4j1jp72511y7wkp4t9")
        #expect(read.protocolPath == "tax-reports/elster/2026/2026-03 20261003T040000Z test.pdf")
        #expect(read.entry.kz83 == 190)
        #expect(read.entry.date == sentAt)

        let elsewhere = try #require(try VatFiling.all(for: "2026-sondervorauszahlung", in: context).first)
        #expect(elsewhere.filingState == .filedElsewhere)
        #expect(!elsewhere.isTest)
        #expect(elsewhere.kz83 == nil)
        #expect(elsewhere.filedOn == "2026-02-09")
        #expect(elsewhere.entry.amount == 1500)
        #expect(elsewhere.zeitraum == nil)

        // Undo "filed elsewhere" by deleting the filing.
        context.delete(elsewhere)
        try context.save()
        #expect(try VatFiling.all(for: "2026-sondervorauszahlung", in: context).isEmpty)
    }

    /// Every property is optional or defaulted (CloudKit): a bare filing saves.
    @Test func aBareFilingSaves() throws {
        let (container, context) = try context()
        _ = container
        context.insert(VatFiling())
        try context.save()
        let all = try context.fetch(FetchDescriptor<VatFiling>())
        #expect(all.count == 1)
        #expect(all.first?.filingState == nil)
        #expect(all.first?.filedKennzahlen == [:])
    }
}

@Suite struct VatFilingsTests {
    func entry(_ state: VatFiling.State, test: Bool = false, day: Int, kz83: Decimal? = nil) -> VatFilingEntry {
        VatFilingEntry(itemID: "2026-03", state: state, isTest: test, kz83: kz83,
                       date: Date(timeIntervalSince1970: TimeInterval(day * 86_400)))
    }

    @Test func statusMappingCountsProductionOnly() {
        #expect(VatFilings([]).mark == nil)
        #expect(VatFilings([entry(.rejected, day: 1)]).mark == nil)
        #expect(VatFilings([entry(.accepted, test: true, day: 1)]).mark == nil)
        #expect(VatFilings([entry(.uncertain, test: true, day: 1)]).mark == nil)
        #expect(VatFilings([entry(.uncertain, day: 1)]).mark == .uncertain)
        #expect(VatFilings([entry(.uncertain, day: 1), entry(.filedElsewhere, day: 2)]).mark == .elsewhere)
        #expect(VatFilings([entry(.filedElsewhere, day: 1), entry(.accepted, day: 2)]).mark == .production)
        #expect(VatFilings([entry(.accepted, day: 1), entry(.uncertain, day: 2)]).mark == .production)
        #expect(VatFilings([entry(.accepted, test: true, day: 1)]).filedInTest)
        #expect(!VatFilings([entry(.rejected, test: true, day: 1)]).filedInTest)
    }

    /// A test filing shows next to the production due status and never makes the return filed.
    @Test func aTestFilingKeepsTheProductionDueStatus() {
        let items = VatReturnSchedule.items(years: [2026], settings: TaxSettings(periods: [.initial(from: "2026-01-01")]))
        let march = items.first { $0.id == "2026-03" }!
        let filings = VatFilings([entry(.accepted, test: true, day: 1)])
        #expect(filings.filedInTest)
        #expect(VatReturnStatus.of(march, today: "2026-06-01", filing: filings.mark) == .overdue(days: 22))
        #expect(VatReturnStatus.of(march, today: "2026-06-01", filing: filings.mark).isOpen)
        let production = VatFilings([entry(.accepted, test: true, day: 1), entry(.accepted, day: 2)])
        #expect(VatReturnStatus.of(march, today: "2026-06-01", filing: production.mark) == .filed)
    }

    @Test func sendingAgainAfterAProductionFilingMustBeACorrection() {
        #expect(!VatFilings([]).requiresCorrection)
        #expect(!VatFilings([entry(.rejected, day: 1), entry(.uncertain, day: 2)]).requiresCorrection)
        #expect(!VatFilings([entry(.accepted, test: true, day: 1)]).requiresCorrection)
        #expect(VatFilings([entry(.accepted, day: 1)]).requiresCorrection)
        #expect(VatFilings([entry(.filedElsewhere, day: 1)]).requiresCorrection)
    }

    @Test func anUncertainSendNeedsAConfirmationBeforeSendingAgain() {
        let uncertain = VatFilings([entry(.uncertain, day: 1)])
        #expect(uncertain.needsResendConfirmation(isTest: false))
        #expect(!uncertain.needsResendConfirmation(isTest: true))
        #expect(VatFilings([entry(.uncertain, test: true, day: 1)]).needsResendConfirmation(isTest: true))
        #expect(VatFilings([entry(.uncertain, day: 1), entry(.rejected, day: 2)]).needsResendConfirmation(isTest: false))
        #expect(!VatFilings([entry(.uncertain, day: 1), entry(.accepted, day: 2)]).needsResendConfirmation(isTest: false))
        #expect(!VatFilings([entry(.rejected, day: 1)]).needsResendConfirmation(isTest: false))
    }

    @Test func theLatestCountedFilingStandsForTheReturn() {
        let filings = VatFilings([entry(.filedElsewhere, day: 1, kz83: 100), entry(.accepted, day: 3, kz83: 120),
                                  entry(.accepted, day: 2, kz83: 110), entry(.accepted, test: true, day: 4, kz83: 999),
                                  entry(.rejected, day: 5, kz83: 500)])
        #expect(filings.counted?.kz83 == 120)
        #expect(VatFilings([entry(.filedElsewhere, day: 1, kz83: 100)]).counted?.kz83 == 100)
        #expect(VatFilings([entry(.accepted, test: true, day: 1)]).counted == nil)
    }
}

@Suite struct SondervorauszahlungFromFilingsTests {
    typealias F = UStVAFixtures

    let settings = TaxSettings(identity: F.identity, periods: [.initial(from: "2025-01-01")])

    func filing(_ itemID: String, _ state: VatFiling.State = .accepted, test: Bool = false, kz83: Decimal? = nil,
                kz38: Decimal? = nil, day: Int = 1) -> VatFilingEntry {
        var kennzahlen: [Kennzahl: Decimal] = [:]
        if let kz83 { kennzahlen[.kz83] = kz83 }
        if let kz38 { kennzahlen[.kz38] = kz38 }
        return VatFilingEntry(itemID: itemID, state: state, isTest: test, kennzahlen: kennzahlen,
                              date: Date(timeIntervalSince1970: TimeInterval(day * 86_400)))
    }

    var fullYear: [VatFilingEntry] {
        (1...12).map { filing(String(format: "2025-%02d", $0), $0 == 1 ? .filedElsewhere : .accepted, kz83: 1000) }
            + [filing("2025-sondervorauszahlung", .filedElsewhere, kz38: 900)]
    }

    @Test func computesFromTheProductionFilingsOfThePriorYear() throws {
        let prior = VatReturnSchedule.items(years: [2025], settings: settings)
        // A test filing and a rejected attempt never count; a correction replaces the earlier filing.
        let filings = fullYear + [filing("2025-03", test: true, kz83: 99_999, day: 9),
                                  filing("2025-04", .rejected, kz83: 99_999, day: 9),
                                  filing("2025-05", kz83: 1500, day: 9)]
        let basis = try #require(SondervorauszahlungBasis.compute(year: 2026, priorYearItems: prior, filings: filings))
        #expect(basis.kz83Total == 12_500)
        #expect(basis.priorSondervorauszahlung == 900)
        #expect(basis.missing.isEmpty)
        // (12,500 + 900) / 11
        #expect(basis.amount(settings: .initial(from: "2026-01-01")) == dec("1218.18"))
    }

    @Test func listsTheMonthsMissingFromTheTotal() throws {
        let prior = VatReturnSchedule.items(years: [2025], settings: settings)
        var filings = fullYear.filter { !["2025-11", "2025-12", "2025-sondervorauszahlung"].contains($0.itemID) }
        filings.append(filing("2025-11", .filedElsewhere))  // filed elsewhere, without an amount
        let basis = try #require(SondervorauszahlungBasis.compute(year: 2026, priorYearItems: prior, filings: filings))
        #expect(basis.missing == [.sondervorauszahlung(year: 2025), .ustva(.month(2025, 11)), .ustva(.month(2025, 12))])
        #expect(basis.kz83Total == 10_000)
        #expect(basis.priorSondervorauszahlung == 0)
    }

    @Test func nothingFiledMeansNothingToCompute() {
        let prior = VatReturnSchedule.items(years: [2025], settings: settings)
        #expect(SondervorauszahlungBasis.compute(year: 2026, priorYearItems: prior, filings: []) == nil)
        #expect(SondervorauszahlungBasis.compute(year: 2026, priorYearItems: prior,
                                                 filings: [filing("2025-03", test: true, kz83: 100)]) == nil)
    }

    @Test func feedsKz38AndTheDecemberKz39AndTheOverrideWins() {
        let items = VatReturnSchedule.items(years: [2026], settings: settings, filings: fullYear)
        let sv = items.first { $0.id == "2026-sondervorauszahlung" }!
        let december = items.first { $0.id == "2026-12" }!
        let november = items.first { $0.id == "2026-11" }!
        // (12,000 + 900) / 11
        #expect(sv.sondervorauszahlung == dec("1172.73"))
        #expect(sv.computesSondervorauszahlung)
        #expect(!sv.needsSondervorauszahlungAmount)
        #expect(sv.xml(result: nil, flags: [], header: F.header)?.contains("<Kz38>1172</Kz38>") == true)
        #expect(december.sondervorauszahlung == dec("1172.73"))
        #expect(december.aggregate([])?.kennzahlen[.kz39] == dec("1172.73"))
        #expect(november.sondervorauszahlung == nil)

        var override = TaxSettingsPeriod.initial(from: "2026-01-01")
        override.sondervorauszahlungOverride = 400
        var withOverride = settings
        withOverride.set(override)
        let overridden = VatReturnSchedule.items(years: [2026], settings: withOverride, filings: fullYear)
        let svOverridden = overridden.first { $0.id == "2026-sondervorauszahlung" }!
        #expect(svOverridden.sondervorauszahlung == 400)
        #expect(!svOverridden.computesSondervorauszahlung)
        #expect(overridden.first { $0.id == "2026-12" }!.aggregate([])?.kennzahlen[.kz39] == 400)

        // Without filings of the prior year, the amount must be entered.
        let none = VatReturnSchedule.items(years: [2026], settings: settings, filings: [])
        #expect(none.first { $0.id == "2026-sondervorauszahlung" }!.needsSondervorauszahlungAmount)
    }
}
