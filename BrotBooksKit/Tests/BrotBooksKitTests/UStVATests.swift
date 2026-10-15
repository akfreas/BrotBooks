import Foundation
import SwiftData
import Testing
@testable import BrotBooksKit

/// Records and configuration shared by the UStVA tests.
enum UStVAFixtures {
    static let identity = TaxIdentity(
        name: "Alois Mustermann", street: "Testgasse", houseNumber: "13a", postalCode: "08151", city: "Musterstadt",
        phone: "0815/99999999", email: "Mustermann@Geschaeft.de", steuernummer: "1096081508187", finanzamt: "1096",
        vatID: "DE123456789")

    static let header = UStVAXML.Header(herstellerID: "27425", produktVersion: "1.0", erstellungsdatum: "20260405")

    static func configuration(_ method: TaxationMethod = .soll, dauerfristverlaengerung: Bool = true,
                              frequency: FilingFrequency = .monthly, testMode: Bool = true) -> TaxConfiguration {
        TaxConfiguration(settings: TaxSettingsPeriod(effectiveFrom: "2026-01-01", taxationMethod: method,
                                                     ustvaFrequency: frequency,
                                                     dauerfristverlaengerung: dauerfristverlaengerung),
                         identity: identity, testMode: testMode)
    }

    static func vat(_ rows: [(String, String)]) -> FieldInput {
        .vatRates(rows.map { VatRowInput(rate: $0.0, amount: $0.1) })
    }

    /// A record built the way the app stores it (derived EUR, VAT and net amounts filled in).
    static func record(_ kind: Kind, _ uid: String, date: String = "2026-03-15", gross: String,
                       _ treatment: VatTreatment?, _ fields: [String: FieldInput] = [:]) -> UStVARecord {
        var input = fields
        input["date"] = .text(date)
        input["gross_amount"] = .text(gross)
        if let treatment { input["vat_treatment"] = .text(treatment.rawValue) }
        let values = try! RecordRules.prepareCreate(kind, input)
        return UStVARecord(kind: kind, uid: uid, values: values)
    }

    static func income(_ uid: String, date: String = "2026-03-15", gross: String, _ treatment: VatTreatment?,
                       _ fields: [String: FieldInput] = [:]) -> UStVARecord {
        record(.income, uid, date: date, gross: gross, treatment, fields)
    }

    static func expense(_ uid: String, date: String = "2026-03-15", gross: String, _ treatment: VatTreatment?,
                        _ fields: [String: FieldInput] = [:]) -> UStVARecord {
        record(.expenses, uid, date: date, gross: gross, treatment, fields)
    }

    /// Every income and expense treatment in March 2026, with partial deductibility and a USD reverse-charge
    /// invoice.
    static let allTreatments: [UStVARecord] = [
        income("i-dom19", gross: "1190", .domestic, ["vat_rates": vat([("19", "190")])]),
        income("i-dom7", gross: "107", .domestic, ["vat_rates": vat([("7", "7")])]),
        income("i-dom-mixed", gross: "1228.52", .domestic, ["vat_rates": vat([("19", "190"), ("7", "2.52")])]),
        income("i-eu-service", gross: "2000.50", .euB2BService, ["client_vat_number": .text("FR 12 345678901")]),
        income("i-eu-service2", gross: "500", .euB2BService, ["client_vat_number": .text("FR12345678901")]),
        income("i-eu-goods", gross: "3000", .euB2BGoods, ["client_vat_number": .text("ATU12345678")]),
        income("i-export", gross: "800", .exportGoods),
        income("i-nonEU", gross: "1500", .nonEUService),
        income("i-notTaxable", gross: "50", .notTaxable),
        expense("e-dom", gross: "119", .domesticVat, ["vat_rates": vat([("19", "19")])]),
        expense("e-phone", gross: "59.50", .domesticVat, ["vat_rates": vat([("19", "9.50")]), "category": .text("Telefon"),
                                                         "deductible_amount": .text("29.75")]),
        expense("e-meal", gross: "71.40", .domesticVat, ["vat_rates": vat([("19", "11.40")]),
                                                       "category": .text("Business meals"),
                                                       "deductible_amount": .text("49.98")]),
        expense("e-gift", gross: "23.80", .domesticVat, ["vat_rates": vat([("19", "3.80")]), "category": .text("Gifts")]),
        expense("e-rc-eu", gross: "100", .rcEUService, ["supplier_region": .text("European Union")]),
        expense("e-rc-us", gross: "120", .rcNonEUService, ["currency": .text("USD"),
                                                          "currency_conversion_rate": .text("0.9172")]),
        expense("e-acq19", gross: "500", .euGoodsAcquisition),
        expense("e-acq7", gross: "200", .euGoodsAcquisition, ["vat_rates": vat([("7", "0")])]),
        expense("e-import", gross: "190", .importVat),
        expense("e-noVat", gross: "300", .noVat),
    ]
}

@Suite struct UStVAAggregatorTests {
    typealias F = UStVAFixtures
    let march = VatPeriod.month(2026, 3)

    func aggregate(_ records: [UStVARecord], _ period: VatPeriod = .month(2026, 3),
                   _ configuration: TaxConfiguration = F.configuration(), sondervorauszahlung: Decimal? = nil)
        -> UStVAResult {
        UStVAAggregator.aggregate(records, period: period, configuration: configuration,
                                  sondervorauszahlung: sondervorauszahlung)
    }

    // MARK: Mapping per treatment

    /// One fixture per treatment: the exact sums each record contributes.
    @Test(arguments: [
        ("i-dom19", [Kennzahl.kz81: "1000"]),
        ("i-dom7", [.kz86: "100"]),
        ("i-dom-mixed", [.kz81: "1000", .kz86: "36"]),
        ("i-eu-service", [.kz21: "2000.5"]),
        ("i-eu-goods", [.kz41: "3000"]),
        ("i-export", [.kz43: "800"]),
        ("i-nonEU", [.kz45: "1500"]),
        ("i-notTaxable", [:]),
        ("e-dom", [.kz66: "19"]),
        // Mixed use: the income-tax share (50 %) of the VAT.
        ("e-phone", [.kz66: "4.75"]),
        // Business meals: 70 % for income tax, the VAT in full.
        ("e-meal", [.kz66: "11.4"]),
        // Gifts: no input tax.
        ("e-gift", [:]),
        ("e-rc-eu", [.kz46: "100", .kz47: "19", .kz67: "19"]),
        // USD 120 at 0.9172 = EUR 110.06; 19 % of it is 20.91.
        ("e-rc-us", [.kz84: "110.06", .kz85: "20.91", .kz67: "20.91"]),
        ("e-acq19", [.kz89: "500", .kz61: "95"]),
        ("e-acq7", [.kz93: "200", .kz61: "14"]),
        ("e-import", [.kz62: "190"]),
        ("e-noVat", [:]),
    ] as [(String, [Kennzahl: String])])
    func mapsEachTreatment(uid: String, expected: [Kennzahl: String]) throws {
        let record = try #require(F.allTreatments.first { $0.uid == uid })
        let result = aggregate([record])
        #expect(result.sums == expected.mapValues(dec))
        #expect(result.issues.isEmpty)
        #expect(result.recordUIDs == [uid])
    }

    @Test func everyTreatmentHasAFixture() {
        let covered = Set(F.allTreatments.compactMap { $0.values["vat_treatment"]?.text.flatMap(VatTreatment.init) })
        #expect(covered == Set(VatTreatment.allCases))
    }

    @Test func allTreatmentsInOneMonth() {
        let result = aggregate(F.allTreatments)
        let k = result.kennzahlen
        #expect(k.values == [
            .kz81: 2000, .kz86: 136, .kz21: 2500, .kz41: 3000, .kz43: 800, .kz45: 1500,
            .kz66: dec("35.15"), .kz46: 100, .kz47: 19, .kz84: 110, .kz85: dec("20.91"), .kz67: dec("39.91"),
            .kz89: 500, .kz93: 200, .kz61: 109, .kz62: 190,
            // 380 + 9.52 + 95 + 14 + 19 + 20.91 − (35.15 + 109 + 190 + 39.91)
            .kz83: dec("164.37"),
        ])
        #expect(k.text(.kz21) == "2500")
        #expect(k.text(.kz83) == "164.37")
        #expect(k.text(.kz61) == "109.00")
        #expect(result.issues.isEmpty)
        #expect(result.contributions.filter { $0.kennzahl == .kz66 }.map(\.recordUID) == ["e-dom", "e-phone", "e-meal"])
    }

    // MARK: ZM

    @Test func zmLinesAreGroupedPerCustomerVatIDAndUmsatzart() {
        let records = F.allTreatments + [
            F.income("i-goods-fr", gross: "400", .euB2BGoods, ["client_vat_number": .text("fr12345678901")]),
            F.income("i-no-id", gross: "10", .euB2BService),
        ]
        let result = aggregate(records)
        #expect(result.zmLines == [
            ZMLine(customerVatID: "", umsatzart: .service, amount: 10, recordUIDs: ["i-no-id"]),
            ZMLine(customerVatID: "ATU12345678", umsatzart: .goods, amount: 3000, recordUIDs: ["i-eu-goods"]),
            ZMLine(customerVatID: "FR12345678901", umsatzart: .goods, amount: 400, recordUIDs: ["i-goods-fr"]),
            ZMLine(customerVatID: "FR12345678901", umsatzart: .service, amount: dec("2500.5"),
                   recordUIDs: ["i-eu-service", "i-eu-service2"]),
        ])
        #expect(result.zmLines[3].wholeEuros == 2500)
        #expect(result.issues == [UStVAIssue(.missingCustomerVatID, recordUID: "i-no-id", kind: .income)])
        // The ZM totals match Kz21 + Kz41 before truncation.
        #expect(result.zmLines.reduce(0) { $0 + $1.amount } == result.sums[.kz21]! + result.sums[.kz41]!)
    }

    // MARK: Exclusions and issues

    @Test func excludesDraftsRemovedAndVatSettlements() {
        var draft = F.expense("draft", gross: "119", .domesticVat, ["vat_rates": F.vat([("19", "19")])])
        draft.isDraft = true
        var removed = F.income("removed", gross: "1190", .domestic, ["vat_rates": F.vat([("19", "190")])])
        removed.isRemoved = true
        let payment = F.expense("payment", gross: "2400", nil,
                                ["category": .text(SortedMarkers.vatPaymentCategory), "supplier_region": .text("Germany")])
        let refund = F.income("refund", gross: "300", nil, ["sale_type": .text(SortedMarkers.vatRefundSaleType)])
        let result = aggregate([draft, removed, payment, refund])
        #expect(result.sums.isEmpty)
        #expect(result.recordUIDs.isEmpty)
        #expect(result.issues.isEmpty)
        #expect(result.kennzahlen.values == [.kz83: 0])
    }

    @Test func unconfirmedRecordsUseTheSuggestionAndAreReported() {
        let suggested = F.expense("us-saas", gross: "50", nil, ["supplier_region": .text("Outside of the European Union")])
        let result = aggregate([suggested])
        #expect(result.sums == [.kz84: 50, .kz85: dec("9.5"), .kz67: dec("9.5")])
        #expect(result.issues == [UStVAIssue(.unconfirmedTreatment, recordUID: "us-saas", kind: .expenses)])
        #expect(result.hasUnconfirmedTreatments)
        #expect(result.blocksSending)
    }

    @Test func reportsRecordsItCannotMap() {
        var noEUR = F.expense("no-eur", gross: "100", .rcEUService, ["currency": .text("USD"),
                                                                    "currency_conversion_rate": .text("0.9")])
        noEUR.values["converted_gross_amount"] = .null
        noEUR.values["net_amount"] = .null
        let noVat = F.expense("no-vat-rows", gross: "100", .domesticVat)
        let noVatIncome = F.income("no-vat-income", gross: "100", .domestic)
        let result = aggregate([noVat, noVatIncome, noEUR])
        #expect(result.issues == [
            UStVAIssue(.missingVatRows, recordUID: "no-vat-rows", kind: .expenses),
            UStVAIssue(.missingVatRows, recordUID: "no-vat-income", kind: .income),
            UStVAIssue(.missingEURAmount, recordUID: "no-eur", kind: .expenses),
        ])
        #expect(!result.blocksSending)
        #expect(result.sums.isEmpty)
        // No rate in the table for the record date: no self-assessed VAT.
        let early = F.expense("early", date: "2006-05-01", gross: "100", .rcEUService)
        #expect(aggregate([early], .month(2006, 5)).issues == [UStVAIssue(.missingVatRate, recordUID: "early",
                                                                          kind: .expenses)])
    }

    // MARK: Period assignment

    @Test func sollAssignsByInvoiceDate() {
        let records = [
            F.income("last-day", date: "2026-03-31", gross: "119", .domestic, ["vat_rates": F.vat([("19", "19")]),
                                                                              "payment_date": .text("2026-04-02")]),
            F.income("next-month", date: "2026-04-01", gross: "119", .domestic, ["vat_rates": F.vat([("19", "19")])]),
            F.income("prev-month", date: "2026-02-28", gross: "119", .domestic, ["vat_rates": F.vat([("19", "19")]),
                                                                                "payment_date": .text("2026-03-05")]),
        ]
        #expect(aggregate(records).recordUIDs == ["last-day"])
        #expect(aggregate(records, .month(2026, 4)).recordUIDs == ["next-month"])
        #expect(aggregate(records, .quarter(2026, 1)).recordUIDs == ["last-day", "prev-month"])
    }

    @Test func istAssignsIncomeByPaymentDateAndExpensesByDate() {
        let ist = F.configuration(.ist)
        let records = [
            F.income("paid-next-month", date: "2026-03-31", gross: "119", .domestic,
                     ["vat_rates": F.vat([("19", "19")]), "payment_date": .text("2026-04-01")]),
            F.income("paid-from-feb", date: "2026-02-20", gross: "238", .domestic,
                     ["vat_rates": F.vat([("19", "38")]), "payment_date": .text("2026-03-01")]),
            F.income("unpaid", date: "2026-03-10", gross: "119", .domestic, ["vat_rates": F.vat([("19", "19")])]),
            F.income("unpaid-old", date: "2026-01-10", gross: "119", .domestic, ["vat_rates": F.vat([("19", "19")])]),
            F.expense("expense-paid-later", date: "2026-03-31", gross: "119", .domesticVat,
                      ["vat_rates": F.vat([("19", "19")])]),
        ]
        let march = aggregate(records, .month(2026, 3), ist)
        #expect(march.recordUIDs == ["paid-from-feb", "expense-paid-later"])
        #expect(march.sums == [.kz81: 200, .kz66: 19])
        #expect(march.issues == [UStVAIssue(.unpaidUnderIst, recordUID: "unpaid", kind: .income)])
        let april = aggregate(records, .month(2026, 4), ist)
        #expect(april.recordUIDs == ["paid-next-month"])
        #expect(april.issues.isEmpty)
        // Under Soll the same records go by invoice date.
        #expect(aggregate(records, .month(2026, 3)).recordUIDs
                == ["paid-next-month", "unpaid", "expense-paid-later"])
    }

    @Test func dueDatesOfTheFiledPeriods() {
        let config = F.configuration()
        #expect(VatPeriod.month(2026, 12).ustvaDueDate(config) == "2027-02-10")
        #expect(VatPeriod.month(2026, 1).ustvaDueDate(F.configuration(dauerfristverlaengerung: false)) == "2026-02-10")
        #expect(VatPeriod.quarter(2026, 4).ustvaDueDate(F.configuration(frequency: .quarterly)) == "2027-02-10")
        #expect(config.deadlines.sondervorauszahlungDueDate(year: 2026, configuration: config) == "2026-02-10")
        #expect(config.deadlines.sondervorauszahlungDueDate(
            year: 2026, configuration: F.configuration(frequency: .quarterly)) == nil)
    }

    // MARK: Sondervorauszahlung credit

    @Test func creditsTheSondervorauszahlungInDecember() {
        let sale = F.income("sale", date: "2026-12-01", gross: "11900", .domestic, ["vat_rates": F.vat([("19", "1900")])])
        let december = aggregate([sale], .month(2026, 12), sondervorauszahlung: dec("1234.56"))
        #expect(december.kennzahlen[.kz39] == dec("1234.56"))
        #expect(december.kennzahlen.kz83 == dec("665.44"))
        #expect(december.kennzahlen.text(.kz39) == "1234.56")
        // Not before December, not without a Dauerfristverlängerung, not for quarterly filers.
        let november = F.income("sale", date: "2026-11-01", gross: "11900", .domestic, ["vat_rates": F.vat([("19", "1900")])])
        #expect(aggregate([november], .month(2026, 11), sondervorauszahlung: 1000).kennzahlen[.kz39] == nil)
        #expect(aggregate([sale], .month(2026, 12), F.configuration(dauerfristverlaengerung: false),
                          sondervorauszahlung: 1000).kennzahlen[.kz39] == nil)
        #expect(aggregate([sale], .quarter(2026, 4), F.configuration(frequency: .quarterly),
                          sondervorauszahlung: 1000).kennzahlen[.kz39] == nil)
        // A credit above the tax gives a refund.
        #expect(aggregate([], .month(2026, 12), sondervorauszahlung: 500).kennzahlen.kz83 == -500)
    }
}

@Suite struct KennzahlenFilingTests {
    let form = UStVAForm.ustva2026

    func file(_ sums: [Kennzahl: Decimal]) -> Kennzahlen {
        Kennzahlen.file(sums, form: form, rates: .germany, rateDate: "2026-01-01")
    }

    /// The values of `Beispiele/UStVA_2026.xml`.
    @Test func kz83ReproducesTheOfficialSample() {
        let k = file([.kz35: 10000, .kz36: 1600, .kz66: 15000, .kz69: 200, .kz81: 150000, .kz86: 25000])
        #expect(k.kz83 == 17050)
        #expect(k.text(.kz83) == "17050.00")
        #expect(k.text(.kz81) == "150000")
        #expect(k.text(.kz36) == "1600.00")
    }

    @Test func kz83TakesItsRatesFromTheRateTable() {
        // July–December 2020: 16 % / 5 %.
        let k = Kennzahlen.file([.kz81: 1000, .kz86: 1000, .kz89: 100, .kz93: 100], form: form, rates: .germany,
                                rateDate: "2020-08-01")
        #expect(k.kz83 == dec("231")) // 160 + 50 + 16 + 5
    }

    @Test func basesAreTruncatedAndTaxesRounded() {
        let k = file([.kz81: dec("1000.99"), .kz86: dec("-100.99"), .kz66: dec("10.005"), .kz67: dec("-0.005"),
                      .kz41: dec("99.999")])
        #expect(k[.kz81] == 1000)
        // Negative bases are truncated toward zero as well.
        #expect(k[.kz86] == -100)
        #expect(k.text(.kz86) == "-100")
        // Taxes round half away from zero.
        #expect(k[.kz66] == dec("10.01"))
        #expect(k[.kz67] == dec("-0.01"))
        #expect(k.text(.kz67) == "-0.01")
        #expect(k[.kz41] == 99)
        // The tax on Kz81/86 comes from the truncated base: 190.00 − 7.00 − 10.01 + 0.01.
        #expect(k.kz83 == dec("173.00"))
    }

    @Test func zeroAmountsAreLeftOutButPairsStayTogether() {
        let k = file([.kz81: dec("0.99"), .kz66: dec("0.004"), .kz35: dec("0.50"), .kz36: dec("0.08"), .kz21: 0])
        #expect(k.values == [.kz35: 0, .kz36: dec("0.08"), .kz83: dec("0.08")])
        #expect(k.text(.kz35) == "0")
        #expect(k.text(.kz81) == nil)
        // Kz83 is always filed.
        #expect(file([:]).text(.kz83) == "0.00")
    }

    @Test func centsTextHasTwoDecimals() {
        #expect(UStVAForm.cents(17050) == "17050.00")
        #expect(UStVAForm.cents(dec("0.5")) == "0.50")
        #expect(UStVAForm.cents(dec("-12.345")) == "-12.35")
        #expect(UStVAForm.cents(0) == "0.00")
    }

    @Test func formsArePickedByYear() {
        let later = UStVAForm(firstYear: 2027, slots: [:], computedTaxBases: [:], outputTaxes: [], inputTaxes: [],
                              sondervorauszahlungCredit: .kz39, result: .kz83, sondervorauszahlung: .kz38,
                              wholeEuroFields: [], pairs: [], elementOrder: [83], sondervorauszahlungElementOrder: [])
        let forms = UStVAForms(forms: [later, .ustva2026])
        #expect(forms.form(for: 2026).firstYear == 2026)
        #expect(forms.form(for: 2028).firstYear == 2027)
        #expect(forms.form(for: 2025).firstYear == 2026)
    }
}

@Suite struct VorsteuerShareTests {
    let rules = VorsteuerShareRules.default

    @Test(arguments: [
        ("Business meals", VorsteuerSharePolicy.full), ("Bewirtungskosten", .full), ("Restaurant", .full),
        ("Gifts", .none), ("Geschenke an Kunden", .none),
        ("Phone", .followsDeductibleShare), ("Telefonkosten", .followsDeductibleShare),
        ("Internet", .followsDeductibleShare), ("Car", .followsDeductibleShare), ("Kfz-Kosten", .followsDeductibleShare),
        ("Home office", .followsDeductibleShare), ("Häusliches Arbeitszimmer", .followsDeductibleShare),
        ("Software", .full), ("Rent", .full), ("Cards and stationery", .full), ("Automation tools", .full),
    ] as [(String, VorsteuerSharePolicy)])
    func defaultPolicyPerCategory(category: String, policy: VorsteuerSharePolicy) {
        #expect(rules.policy(forCategory: category) == policy)
    }

    @Test func shareFollowsThePolicy() {
        let half: RecordValues = ["deductible_amount": .decimal(50), "converted_gross_amount": .decimal(100)]
        #expect(rules.share(for: half.merging(["category": .text("Phone")]) { $1 }) == dec("0.5"))
        #expect(rules.share(for: half.merging(["category": .text("Business meals")]) { $1 }) == 1)
        #expect(rules.share(for: half.merging(["category": .text("Gifts")]) { $1 }) == 0)
        #expect(rules.share(for: half) == 1)
        // A home-office record follows its deductible share whatever its category.
        #expect(rules.share(for: half.merging(["category": .text("Rent"), "is_home_office": .bool(true)]) { $1 })
                == dec("0.5"))
    }

    @Test @MainActor func rulesArePersistedInTheTaxProfile() throws {
        let container = try ModelContainer(for: StoreSchema.schema,
                                           configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let context = container.mainContext
        var settings = try TaxProfile.load(in: context)
        #expect(settings.vorsteuerShareRules == .default)
        #expect(try TaxProfile.current(in: context)?.vorsteuerShareRules == nil)
        settings.vorsteuerShareRules.rules.insert(.init(.none, ["coffee"]), at: 0)
        try TaxProfile.save(settings, in: context)
        let loaded = try TaxProfile.load(in: context)
        #expect(loaded.vorsteuerShareRules.policy(forCategory: "Coffee") == VorsteuerSharePolicy.none)
        #expect(loaded.configuration(on: "2026-05-01")?.vorsteuerShareRules == loaded.vorsteuerShareRules)
    }
}

@Suite struct UStVAXMLTests {
    typealias F = UStVAFixtures

    static func golden(_ name: String) -> URL {
        URL(filePath: #filePath).deletingLastPathComponent().appending(path: "Fixtures/\(name)")
    }

    /// Compares with the golden file; `UPDATE_GOLDEN=1` rewrites it instead.
    func expectGolden(_ xml: String, _ name: String) throws {
        if ProcessInfo.processInfo.environment["UPDATE_GOLDEN"] == "1" {
            try xml.write(to: Self.golden(name), atomically: true, encoding: .utf8)
        }
        let expected = try String(contentsOf: fixtureURL(name), encoding: .utf8)
        #expect(xml == expected)
    }

    func sampleKennzahlen() -> Kennzahlen {
        Kennzahlen.file([.kz35: 10000, .kz36: 1600, .kz66: 15000, .kz69: 200, .kz81: 150000, .kz86: 25000],
                        form: .ustva2026, rates: .germany, rateDate: "2026-01-01")
    }

    @Test func goldenSampleReturn() throws {
        let xml = UStVAXML.build(period: .month(2026, 1), kennzahlen: sampleKennzahlen(),
                                 configuration: F.configuration(), header: F.header)
        try expectGolden(xml, "UStVA_2026_sample.golden.xml")
    }

    @Test func goldenAllTreatmentsReturn() throws {
        let result = UStVAAggregator.aggregate(F.allTreatments, period: .month(2026, 3), configuration: F.configuration())
        let xml = UStVAXML.build(period: .month(2026, 3), kennzahlen: result.kennzahlen,
                                 flags: [.correction, .documentsSubmittedSeparately], configuration: F.configuration(),
                                 header: F.header)
        try expectGolden(xml, "UStVA_2026_all_treatments.golden.xml")
    }

    @Test func goldenSondervorauszahlungAndDauerfristverlaengerung() throws {
        try expectGolden(UStVAXML.buildSondervorauszahlung(year: 2026, amount: dec("1234.56"),
                                                           flags: [.documentsSubmittedSeparately, .noDirectDebit],
                                                           configuration: F.configuration(), header: F.header),
                         "UStVA_SoVZ_2026.golden.xml")
        try expectGolden(UStVAXML.buildDauerfristverlaengerung(year: 2026, configuration: F.configuration(),
                                                               header: F.header),
                         "UStVA_Df_2026.golden.xml")
    }

    @Test func testmerkerOnlyInTestMode() {
        let test = UStVAXML.build(period: .month(2026, 1), kennzahlen: sampleKennzahlen(),
                                  configuration: F.configuration(testMode: true), header: F.header)
        let production = UStVAXML.build(period: .month(2026, 1), kennzahlen: sampleKennzahlen(),
                                        configuration: F.configuration(testMode: false), header: F.header)
        #expect(test.contains("<Testmerker>700000004</Testmerker>"))
        #expect(!production.contains("Testmerker"))
        #expect(test.replacingOccurrences(of: "        <Testmerker>700000004</Testmerker>\n", with: "") == production)
    }

    @Test func namespaceAndVersionFollowTheYear() {
        let k = sampleKennzahlen()
        let xml2027 = UStVAXML.build(period: .month(2027, 1), kennzahlen: k, configuration: F.configuration(),
                                     header: F.header)
        #expect(xml2027.contains(#"<Anmeldungssteuern xmlns="http://finkonsens.de/elster/elsteranmeldung/ustva/v2027" version="2027">"#))
        #expect(xml2027.contains("<Jahr>2027</Jahr>"))
        #expect(UStVAXML.datenartVersion(year: 2027) == "UStVA_2027")
    }

    @Test func elementsFollowTheSchemaSequence() throws {
        let k = Kennzahlen.file([.kz90: 1, .kz93: 1, .kz89: 1, .kz21: 1, .kz66: 1], form: .ustva2026, rates: .germany,
                                rateDate: "2026-01-01")
        let xml = UStVAXML.build(period: .quarter(2026, 2), kennzahlen: k, flags: [.offsetRefund, .correction],
                                 configuration: F.configuration(), header: F.header)
        let names = xml.matches(of: /<(Jahr|Zeitraum|Steuernummer|Kz\d+)>/).map { String($0.1) }
        #expect(names == ["Jahr", "Zeitraum", "Steuernummer", "Kz09", "Kz10", "Kz21", "Kz29", "Kz66", "Kz83", "Kz89",
                          "Kz93", "Kz90"])
        #expect(xml.contains("<Zeitraum>42</Zeitraum>"))
    }

    @Test func escapesTextAndSplitsTheHouseNumber() {
        var config = F.configuration()
        config.identity.name = "Müller & Söhne <GmbH>"
        config.identity.houseNumber = "7 b"
        let xml = UStVAXML.buildDauerfristverlaengerung(year: 2026, configuration: config, header: F.header)
        #expect(xml.contains("<Name>Müller &amp; Söhne &lt;GmbH&gt;</Name>"))
        #expect(xml.contains("<Hausnummer>7</Hausnummer>"))
        #expect(xml.contains("<HNrZusatz>b</HNrZusatz>"))
        #expect(UStVAXML.escape(#"a"b'c"#) == "a&quot;b&apos;c")
        #expect(UStVAXML.Address(street: "Hauptstr.", houseNumber: "12").number == "12")
        #expect(UStVAXML.Address(street: "Hauptstr.", houseNumber: "12").suffix == nil)
        #expect(UStVAXML.Address(street: "Am Hof", houseNumber: "ohne").street == "Am Hof ohne")
        #expect(UStVAXML.Address(street: "Am Hof", houseNumber: "ohne").number == nil)
    }

    @Test func sondervorauszahlungIsWholeEuros() {
        let xml = UStVAXML.buildSondervorauszahlung(year: 2026, amount: dec("1234.99"), configuration: F.configuration(),
                                                    header: F.header)
        #expect(xml.contains("<Kz38>1234</Kz38>"))
        #expect(UStVAXML.buildSondervorauszahlung(year: 2026, amount: -5, configuration: F.configuration(),
                                                  header: F.header).contains("<Kz38>0</Kz38>"))
    }
}
