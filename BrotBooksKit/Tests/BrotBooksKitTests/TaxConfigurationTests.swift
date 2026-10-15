import Foundation
import SwiftData
import Testing
@testable import BrotBooksKit

@Suite struct TaxSettingsTests {
    static let history = TaxSettings(periods: [
        TaxSettingsPeriod(effectiveFrom: "2027-01-01", taxationMethod: .ist, ustvaFrequency: .quarterly,
                          dauerfristverlaengerung: false, zmFrequency: .quarterly, zmThreshold: 40_000),
        .initial(from: "2026-01-01"),
        TaxSettingsPeriod(effectiveFrom: "2026-07-01", sondervorauszahlungOverride: dec("1234.56")),
    ])

    @Test func initialValuesMatchThePlan() {
        let initial = TaxSettings.initial
        #expect(initial.testMode)
        #expect(initial.identity == TaxIdentity())
        #expect(initial.periods.count == 1)
        let p = initial.periods[0]
        #expect(p.effectiveFrom == "2026-01-01")
        #expect(p.taxationMethod == .soll)
        #expect(p.ustvaFrequency == .monthly)
        #expect(p.dauerfristverlaengerung)
        #expect(p.sondervorauszahlungOverride == nil)
        #expect(p.zmFrequency == .monthly)
        #expect(p.zmThreshold == 50_000)
    }

    @Test func resolvesTheLatestPeriodStartingOnOrBeforeTheDate() {
        let h = Self.history
        #expect(h.periods.map(\.effectiveFrom) == ["2026-01-01", "2026-07-01", "2027-01-01"])
        #expect(h.configuration(on: "2025-12-31") == nil)
        #expect(h.configuration(on: "2026-01-01")?.settings.effectiveFrom == "2026-01-01")
        #expect(h.configuration(on: "2026-06-30")?.settings.sondervorauszahlungOverride == nil)
        #expect(h.configuration(on: "2026-07-01")?.settings.sondervorauszahlungOverride == dec("1234.56"))
        let c2027 = h.configuration(on: "2027-05-05")
        #expect(c2027?.taxationMethod == .ist)
        #expect(c2027?.ustvaFrequency == .quarterly)
        #expect(c2027?.dauerfristverlaengerung == false)
        #expect(c2027?.zmFrequency == .quarterly)
        #expect(c2027?.zmThreshold == 40_000)
        #expect(c2027?.testMode == true)
        // A period's configuration is the one in force on its first day.
        #expect(h.configuration(for: .quarter(2026, 3))?.settings.effectiveFrom == "2026-07-01")
        #expect(h.configuration(for: .month(2026, 6))?.settings.effectiveFrom == "2026-01-01")
    }

    @Test func addingSettingsNeverRewritesEarlierPeriods() {
        var h = Self.history
        let before = h.configuration(on: "2026-03-01")
        h.set(TaxSettingsPeriod(effectiveFrom: "2028-01-01", taxationMethod: .ist))
        h.set(TaxSettingsPeriod(effectiveFrom: "2027-01-01", ustvaFrequency: .none))
        #expect(h.configuration(on: "2026-03-01") == before)
        #expect(h.configuration(on: "2027-03-01")?.ustvaFrequency == FilingFrequency.none)
        #expect(h.configuration(on: "2028-03-01")?.taxationMethod == .ist)
        #expect(h.periods.count == 4)
        h.remove(effectiveFrom: "2028-01-01")
        #expect(h.configuration(on: "2028-03-01")?.ustvaFrequency == FilingFrequency.none)
    }

    @Test func settingsPeriodJSONKeepsExactMoneyAndToleratesMissingKeys() throws {
        let period = TaxSettingsPeriod(effectiveFrom: "2026-01-01", sondervorauszahlungOverride: dec("1550.10"),
                                       zmThreshold: dec("50000.00"))
        let data = try JSONEncoder().encode(period)
        let json = String(decoding: data, as: UTF8.self)
        #expect(json.contains(#""sondervorauszahlungOverride":"1550.1"#))
        #expect(try JSONDecoder().decode(TaxSettingsPeriod.self, from: data) == period)
        let sparse = #"{"effectiveFrom":"2027-01-01","ustvaFrequency":"weekly","taxationMethod":"ist"}"#
        let decoded = try JSONDecoder().decode(TaxSettingsPeriod.self, from: Data(sparse.utf8))
        #expect(decoded == TaxSettingsPeriod(effectiveFrom: "2027-01-01", taxationMethod: .ist))
    }

    @Test func sondervorauszahlungIsAnEleventhOfThePriorYearUnlessOverridden() {
        #expect(Sondervorauszahlung.computed(priorYearKz83Total: 11_000, priorYearSondervorauszahlung: 0) == 1_000)
        #expect(Sondervorauszahlung.computed(priorYearKz83Total: dec("17050.00"), priorYearSondervorauszahlung: 0)
                == dec("1550"))
        #expect(Sondervorauszahlung.computed(priorYearKz83Total: 100, priorYearSondervorauszahlung: 0) == dec("9.09"))
        #expect(Sondervorauszahlung.computed(priorYearKz83Total: -500, priorYearSondervorauszahlung: 0) == 0)
        let auto = TaxSettingsPeriod.initial()
        #expect(Sondervorauszahlung.amount(priorYearKz83Total: 11_000, priorYearSondervorauszahlung: 0,
                                           settings: auto) == 1_000)
        let edited = TaxSettingsPeriod(effectiveFrom: "2026-01-01", sondervorauszahlungOverride: 800)
        #expect(Sondervorauszahlung.amount(priorYearKz83Total: 11_000, priorYearSondervorauszahlung: 1_000,
                                           settings: edited) == 800)
    }

    /// The December return credits the prior Sondervorauszahlung as Kz39, so the year's Kz83 sum is net of it. The
    /// advance payments (Kz38 base) add it back: 12 months of 1,000 with 1,000 credited in December sum to 11,000
    /// in Kz83, but the advance payments were 12,000.
    @Test func sondervorauszahlungBaseAddsThePriorSondervorauszahlungBack() {
        #expect(Sondervorauszahlung.computed(priorYearKz83Total: 11_000, priorYearSondervorauszahlung: 1_000)
                == dec("1090.91"))
        #expect(Sondervorauszahlung.amount(priorYearKz83Total: 11_000, priorYearSondervorauszahlung: 1_000,
                                           settings: .initial()) == dec("1090.91"))
        // A refund year: Kz83 negative, but the Sondervorauszahlung paid in still counts.
        #expect(Sondervorauszahlung.computed(priorYearKz83Total: -100, priorYearSondervorauszahlung: 1_200)
                == dec("100"))
        #expect(Sondervorauszahlung.computed(priorYearKz83Total: -1_500, priorYearSondervorauszahlung: 1_000) == 0)
    }

    @Test func wIdNrFormat() {
        #expect(WIdNr.isWellFormed("DE123456788"))
        #expect(WIdNr.isWellFormed("de 123456788-00001"))
        #expect(!WIdNr.isWellFormed("DE12345678"))
        #expect(!WIdNr.isWellFormed("DE123456788-1"))
        #expect(!WIdNr.isWellFormed("AT123456788"))
        #expect(!WIdNr.isWellFormed(""))
        #expect(WIdNr.base("DE123456788-00001") == "DE123456788")
        #expect(WIdNr.base(" de123456788 ") == "DE123456788")
        #expect(WIdNr.base("DE1234") == nil)
    }

    @Test func zmThresholdWarnsOnlyForQuarterlyZMAboveTheThreshold() {
        let quarterly = TaxConfiguration(settings: TaxSettingsPeriod(effectiveFrom: "2026-01-01", zmFrequency: .quarterly))
        let monthly = TaxConfiguration(settings: .initial())
        let q = VatPeriod.quarter(2026, 2)
        #expect(ZMThresholdWarning.check(euGoodsDeliveries: 50_000, quarter: q, configuration: quarterly) == nil)
        #expect(ZMThresholdWarning.check(euGoodsDeliveries: dec("50000.01"), quarter: q, configuration: quarterly)
                == ZMThresholdWarning(quarter: q, deliveries: dec("50000.01"), threshold: 50_000))
        #expect(ZMThresholdWarning.check(euGoodsDeliveries: 90_000, quarter: q, configuration: monthly) == nil)
        let lower = TaxConfiguration(settings: TaxSettingsPeriod(effectiveFrom: "2026-01-01", zmFrequency: .quarterly,
                                                                  zmThreshold: 10_000))
        #expect(ZMThresholdWarning.check(euGoodsDeliveries: 10_001, quarter: q, configuration: lower)?.threshold == 10_000)
    }
}

@Suite struct VatRateTableTests {
    let table = VatRateTable.germany

    @Test func standardAndReducedRatesByDate() {
        #expect(table.rate(.standard, on: "2019-12-31") == 19)
        #expect(table.rate(.reduced, on: "2019-12-31") == 7)
        #expect(table.rate(.standard, on: "2020-06-30") == 19)
        #expect(table.rate(.standard, on: "2020-07-01") == 16)
        #expect(table.rate(.reduced, on: "2020-07-01") == 5)
        #expect(table.rate(.standard, on: "2020-12-31") == 16)
        #expect(table.rate(.reduced, on: "2020-12-31") == 5)
        #expect(table.rate(.standard, on: "2021-01-01") == 19)
        #expect(table.rate(.reduced, on: "2026-10-15") == 7)
        #expect(table.rate(.standard, on: "2006-12-31") == nil)
    }

    @Test func classifiesRatesByDate() {
        #expect(table.kind(of: 19, on: "2026-03-01") == .standard)
        #expect(table.kind(of: 7, on: "2026-03-01") == .reduced)
        #expect(table.kind(of: 16, on: "2026-03-01") == nil)
        #expect(table.kind(of: 16, on: "2020-08-01") == .standard)
        #expect(table.kind(of: 5, on: "2020-08-01") == .reduced)
        #expect(table.kind(of: 23, on: "2026-03-01") == nil)
    }

    @Test func selfAssessedRatePrefersTheRecordsOwnRow() {
        #expect(table.selfAssessedRate(on: "2026-03-01", rows: []) == 19)
        #expect(table.selfAssessedRate(on: "2020-09-01", rows: []) == 16)
        #expect(table.selfAssessedRate(on: "2026-03-01", rows: [VatRate(rate: 0, amount: 0), VatRate(rate: 7, amount: 0)]) == 7)
    }
}

@Suite struct VatPeriodTests {
    @Test func zeitraumCodes() {
        #expect((1...12).map { VatPeriod.month(2026, $0).zeitraum }
                == ["01", "02", "03", "04", "05", "06", "07", "08", "09", "10", "11", "12"])
        #expect((1...4).map { VatPeriod.quarter(2026, $0).zeitraum } == ["41", "42", "43", "44"])
        #expect(VatPeriod(year: 2026, zeitraum: "07") == .month(2026, 7))
        #expect(VatPeriod(year: 2026, zeitraum: "43") == .quarter(2026, 3))
        for bad in ["00", "13", "40", "45", "7", "1a"] { #expect(VatPeriod(year: 2026, zeitraum: bad) == nil) }
    }

    @Test func startAndEndDates() {
        #expect(VatPeriod.month(2026, 2).start == "2026-02-01")
        #expect(VatPeriod.month(2026, 2).end == "2026-02-28")
        #expect(VatPeriod.month(2028, 2).end == "2028-02-29")
        #expect(VatPeriod.month(2026, 12).end == "2026-12-31")
        #expect(VatPeriod.quarter(2026, 1).start == "2026-01-01")
        #expect(VatPeriod.quarter(2026, 1).end == "2026-03-31")
        #expect(VatPeriod.quarter(2026, 2).end == "2026-06-30")
        #expect(VatPeriod.quarter(2026, 4).start == "2026-10-01")
        #expect(VatPeriod.quarter(2026, 3).contains("2026-09-30"))
        #expect(!VatPeriod.quarter(2026, 3).contains("2026-10-01"))
    }

    @Test func periodsOfAYear() {
        #expect(VatPeriod.periods(year: 2026, frequency: FilingFrequency.monthly).map(\.zeitraum).count == 12)
        #expect(VatPeriod.periods(year: 2026, frequency: FilingFrequency.monthly).first == .month(2026, 1))
        #expect(VatPeriod.periods(year: 2026, frequency: FilingFrequency.quarterly).map(\.zeitraum) == ["41", "42", "43", "44"])
        #expect(VatPeriod.periods(year: 2026, frequency: FilingFrequency.none).isEmpty)
        #expect(VatPeriod.periods(year: 2026, frequency: ZMFrequency.quarterly).count == 4)
        #expect(VatPeriod.containing("2026-08-15", frequency: .monthly) == .month(2026, 8))
        #expect(VatPeriod.containing("2026-08-15", frequency: .quarterly) == .quarter(2026, 3))
        #expect(VatPeriod.containing("2026-08-15", frequency: .none) == nil)
        #expect(VatPeriod.month(2026, 12) < .month(2027, 1))
    }

    @Test func isoDateArithmetic() {
        #expect(ISODate.adding(days: 10, to: "2026-01-31") == "2026-02-10")
        #expect(ISODate.adding(days: 10, to: "2026-12-31") == "2027-01-10")
        #expect(ISODate.adding(days: -1, to: "2026-03-01") == "2026-02-28")
        #expect(ISODate.adding(days: 400, to: "2026-01-01") == "2027-02-05")
        #expect(ISODate.adding(months: 1, to: "2026-01-31") == "2026-02-28")
        #expect(ISODate.adding(months: 1, to: "2026-12-10") == "2027-01-10")
        #expect(ISODate.adding(months: -1, to: "2026-01-10") == "2025-12-10")
        #expect(ISODate.adding(days: 1, to: "nope") == nil)
    }
}

@Suite struct FilingDeadlinesTests {
    let deadlines = FilingDeadlines.germany
    let withExtension = TaxConfiguration(settings: .initial())
    let withoutExtension = TaxConfiguration(settings: TaxSettingsPeriod(effectiveFrom: "2026-01-01",
                                                                        dauerfristverlaengerung: false))

    @Test func ustvaMonthly() {
        #expect(VatPeriod.month(2026, 1).ustvaDueDate(withoutExtension) == "2026-02-10")
        #expect(VatPeriod.month(2026, 1).ustvaDueDate(withExtension) == "2026-03-10")
        #expect(VatPeriod.month(2026, 2).ustvaDueDate(withoutExtension) == "2026-03-10")
        #expect(VatPeriod.month(2026, 2).ustvaDueDate(withExtension) == "2026-04-10")
        #expect(VatPeriod.month(2026, 11).ustvaDueDate(withExtension) == "2027-01-10")
        #expect(VatPeriod.month(2026, 12).ustvaDueDate(withoutExtension) == "2027-01-10")
        #expect(VatPeriod.month(2026, 12).ustvaDueDate(withExtension) == "2027-02-10")
    }

    @Test func ustvaQuarterly() {
        #expect(VatPeriod.quarter(2026, 1).ustvaDueDate(withoutExtension) == "2026-04-10")
        #expect(VatPeriod.quarter(2026, 1).ustvaDueDate(withExtension) == "2026-05-10")
        #expect(VatPeriod.quarter(2026, 4).ustvaDueDate(withoutExtension) == "2027-01-10")
        #expect(VatPeriod.quarter(2026, 4).ustvaDueDate(withExtension) == "2027-02-10")
    }

    @Test func zmIsThe25thAfterThePeriodAndIgnoresTheExtension() {
        #expect(VatPeriod.month(2026, 1).zmDueDate(withExtension) == "2026-02-25")
        #expect(VatPeriod.month(2026, 1).zmDueDate(withoutExtension) == "2026-02-25")
        #expect(VatPeriod.month(2026, 12).zmDueDate(withExtension) == "2027-01-25")
        #expect(VatPeriod.quarter(2026, 2).zmDueDate(withExtension) == "2026-07-25")
        #expect(deadlines.zmDueDate(.quarter(2026, 4)) == "2027-01-25")
    }

    @Test func sondervorauszahlungIsDueOn10FebruaryWithExtensionAndMonthlyFiling() {
        #expect(deadlines.sondervorauszahlungDueDate(year: 2027) == "2027-02-10")
        #expect(deadlines.sondervorauszahlungDueDate(year: 2027, configuration: withExtension) == "2027-02-10")
        #expect(deadlines.sondervorauszahlungDueDate(year: 2027, configuration: withoutExtension) == nil)
        let quarterly = TaxConfiguration(settings: TaxSettingsPeriod(effectiveFrom: "2026-01-01", ustvaFrequency: .quarterly))
        #expect(deadlines.sondervorauszahlungDueDate(year: 2027, configuration: quarterly) == nil)
    }

    @Test func offsetsComeFromTheTable() {
        let changed = FilingDeadlines(rules: [
            FilingDeadlines.germany.rules[0],
            .init(validFrom: "2030-01-01", ustvaDaysAfterPeriodEnd: 15, ustvaExtensionMonths: 2,
                  zmDayOfFollowingMonth: 20, sondervorauszahlungMonth: 3, sondervorauszahlungDay: 1),
        ])
        let config = TaxConfiguration(settings: .initial(), deadlines: changed)
        #expect(VatPeriod.month(2029, 12).ustvaDueDate(config) == "2030-02-10")
        #expect(VatPeriod.month(2030, 1).ustvaDueDate(config) == "2030-04-15")
        #expect(VatPeriod.month(2030, 1).zmDueDate(config) == "2030-02-20")
        #expect(changed.sondervorauszahlungDueDate(year: 2030) == "2030-03-01")
        #expect(changed.sondervorauszahlungDueDate(year: 2029) == "2029-02-10")
    }
}

@MainActor
@Suite struct TaxProfileTests {
    func context() throws -> (ModelContainer, ModelContext) {
        let config = ModelConfiguration(schema: StoreSchema.schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        let container = try ModelContainer(for: StoreSchema.schema, configurations: [config])
        return (container, container.mainContext)
    }

    @Test func seedsTheInitialProfileOnceWhenNoneExists() throws {
        let (container, context) = try context()
        _ = container
        #expect(try TaxProfile.current(in: context) == nil)
        let settings = try TaxProfile.load(in: context)
        #expect(settings == .initial)
        #expect(try context.fetch(FetchDescriptor<TaxProfile>()).count == 1)
        _ = try TaxProfile.load(in: context)
        #expect(try context.fetch(FetchDescriptor<TaxProfile>()).count == 1)
        #expect(settings.configuration(on: "2026-01-01")?.taxationMethod == .soll)
        #expect(settings.configuration(on: "2025-12-31") == nil)
    }

    @Test func roundTripsIdentityTestModeAndPeriods() throws {
        let (container, context) = try context()
        _ = container
        var settings = TaxSettings.initial
        settings.identity = TaxIdentity(name: "Alex Freas", street: "Brotstraße", houseNumber: "12a", postalCode: "10115",
                                        city: "Berlin", phone: "+49 30 123", email: "alex@example.com",
                                        steuernummer: "1121081508150", finanzamt: "1121", vatID: "DE123456789",
                                        wIdNr: "DE123456788-00001", steuernummerRegional: "21/815/08150")
        settings.testMode = false
        settings.set(TaxSettingsPeriod(effectiveFrom: "2027-01-01", taxationMethod: .ist, ustvaFrequency: .quarterly,
                                       dauerfristverlaengerung: false, sondervorauszahlungOverride: dec("1550.10"),
                                       zmFrequency: .quarterly, zmThreshold: dec("40000.50")))
        try TaxProfile.save(settings, in: context)
        #expect(try context.fetch(FetchDescriptor<TaxProfile>()).count == 1)
        #expect(try TaxProfile.load(in: context) == settings)

        let profile = try #require(try TaxProfile.current(in: context))
        #expect(profile.steuernummer == "1121081508150")
        #expect(profile.wIdNr == "DE123456788-00001")
        #expect(profile.steuernummerRegional == "21/815/08150")
        #expect(profile.testMode == false)
        var cleared = settings
        cleared.identity.phone = ""
        profile.apply(cleared)
        #expect(profile.phone == nil)
        #expect(profile.settings == cleared)
    }

    @Test func unreadableSettingsReadAsNoPeriods() throws {
        let profile = TaxProfile()
        profile.settingsPeriods = Data("not json".utf8)
        #expect(profile.settings.periods.isEmpty)
        #expect(profile.settings.configuration(on: "2026-05-01") == nil)
        #expect(profile.testMode)
    }

    @Test func picksTheMostRecentlyUpdatedProfileWhenSeveralExist() throws {
        let (container, context) = try context()
        _ = container
        let older = TaxProfile()
        older.apply(.initial)
        older.updatedAt = Date(timeIntervalSince1970: 1_000)
        var edited = TaxSettings.initial
        edited.testMode = false
        let newer = TaxProfile()
        newer.apply(edited)
        newer.updatedAt = Date(timeIntervalSince1970: 2_000)
        context.insert(older)
        context.insert(newer)
        try context.save()
        #expect(try TaxProfile.current(in: context)?.uid == newer.uid)
        #expect(try TaxProfile.load(in: context).testMode == false)
    }
}
