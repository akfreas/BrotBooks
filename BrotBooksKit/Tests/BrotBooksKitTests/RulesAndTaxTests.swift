import Foundation
import Testing
@testable import BrotBooksKit

@Suite struct RecordRulesTests {
    func create(_ kind: Kind, _ fields: [String: FieldInput]) throws -> RecordValues {
        var record = try RecordRules.coerce(kind, fields)
        if record["currency"] == nil { record["currency"] = .text("EUR") }
        try RecordRules.deriveAmounts(kind, &record, provided: Set(fields.keys), creating: true)
        return record
    }

    @Test func deriveEurWithVat() throws {
        let r = try create(.expenses, ["gross_amount": .text("71.40"),
                                       "vat_rates": .vatRates([VatRowInput(rate: "19", amount: "11.4")])])
        #expect(r["converted_gross_amount"] == .decimal(dec("71.40")))
        #expect(r["total_vat_amount"] == .decimal(dec("11.40")))
        #expect(r["net_amount"] == .decimal(dec("60.00")))
        #expect(r["deductible_amount"] == .decimal(dec("71.40")))
    }

    @Test func deriveUsdWithRateAndIncomeHasNoDeductible() throws {
        let r = try create(.income, ["gross_amount": .text("100"), "currency": .text("usd"),
                                     "currency_conversion_rate": .text("0.9172")])
        #expect(r["currency"] == .text("USD"))
        #expect(r["converted_gross_amount"] == .decimal(dec("91.72")))
        #expect(r["net_amount"] == .decimal(dec("91.72")))
        #expect(r["deductible_amount"] == nil)
    }

    @Test func deriveNonEurWithoutRateFails() {
        #expect(throws: ValidationError("non-EUR records need currency_conversion_rate or converted_gross_amount")) {
            try create(.expenses, ["gross_amount": .text("10"), "currency": .text("USD")])
        }
    }

    @Test func deriveRespectsExplicitValues() throws {
        let r = try create(.expenses, ["gross_amount": .text("10"), "currency": .text("USD"),
                                       "converted_gross_amount": .text("9.50"), "net_amount": .text("9.00")])
        #expect(r["converted_gross_amount"] == .decimal(dec("9.50")))
        #expect(r["net_amount"] == .decimal(dec("9.00")))
    }

    @Test func updateOnlyRecomputesDependents() throws {
        let record: RecordValues = ["currency": .text("EUR"), "gross_amount": .decimal(50), "converted_gross_amount": .decimal(50),
                                    "vat_rates": .vatRates([]), "total_vat_amount": .decimal(0), "net_amount": .decimal(50),
                                    "deductible_amount": .decimal(40)]
        var described = record
        described["description"] = .text("x")
        #expect(try RecordRules.deriveAmounts(.expenses, &described, provided: ["description"], creating: false) == ["description"])
        var updated = record
        updated["vat_rates"] = .vatRates([VatRate(rate: 19, amount: dec("7.98"))])
        let changed = try RecordRules.deriveAmounts(.expenses, &updated, provided: ["vat_rates"], creating: false)
        #expect(changed == ["vat_rates", "total_vat_amount", "net_amount"])
        #expect(updated["net_amount"] == .decimal(dec("42.02")))
        #expect(updated["deductible_amount"] == .decimal(40))
    }

    @Test func coerceRejectsUnknownWrongKindAndBadValues() {
        #expect(throws: ValidationError("unknown income fields: category")) {
            try RecordRules.coerce(.income, ["category": .text("Software")])
        }
        #expect(throws: ValidationError("date: not an ISO date: '04/11/2021'")) {
            try RecordRules.coerce(.expenses, ["date": .text("04/11/2021")])
        }
        #expect(throws: ValidationError("gross_amount cannot be null")) {
            try RecordRules.coerce(.expenses, ["gross_amount": .null])
        }
        #expect(throws: ValidationError("gross_amount: not a number: 'abc'")) {
            try RecordRules.coerce(.expenses, ["gross_amount": .text("abc")])
        }
        #expect(throws: ValidationError.self) {
            try RecordRules.coerce(.expenses, ["vat_rates": .vatRates([VatRowInput(rate: "19", amount: "x")])])
        }
        #expect(throws: ValidationError("missing required fields: gross_amount")) {
            try RecordRules.prepareCreate(.expenses, ["date": .text("2025-01-01")])
        }
    }

    @Test func uploadFilename() {
        #expect(RecordRules.uploadFilename(date: "2025-03-01", description: "AWS: March/2025", ref: "L7", sha256: "abcdef0123")
            == "2025/2025-03-01 AWS March 2025 L7-abcdef01.pdf")
    }

    @Test func parsesVatRatesAndRefs() throws {
        #expect(try VatRates.parse("7%: 0 | 19%: 12.34") == [VatRate(rate: 7, amount: 0), VatRate(rate: 19, amount: dec("12.34"))])
        #expect(try VatRates.parse(" ") == [])
        #expect(throws: ExportFormatError.self) { try VatRates.parse("19 percent") }
        #expect(VatRates.decode(VatRates.encode([VatRate(rate: 19, amount: dec("11.40"))])) == [VatRate(rate: 19, amount: dec("11.4"))])
        #expect(Columns.sortedRef(fromFilename: "2021/2021-11-04 Accounting software November 2021 f00d1.pdf") == "f00d1")
        #expect(Columns.sortedRef(fromFilename: "2021/2021-11-04 Accounting software F00D1.pdf") == nil)
    }
}

@Suite struct GermanTaxTests {
    @Test(arguments: GermanTax.tariffs.keys.sorted())
    func tariffIsContinuousAtEveryZoneBoundary(year: Int) {
        let t = GermanTax.tariffs[year]!
        for edge in [t.basicAllowance, t.zone2End, t.zone3End, t.zone4End] {
            #expect(abs(GermanTax.incomeTax(edge + 1, year: year) - GermanTax.incomeTax(edge, year: year)) <= 3, "edge \(edge)")
        }
    }

    @Test(arguments: GermanTax.tariffs.keys.sorted())
    func tariffIsZeroBelowAllowanceAndMonotonic(year: Int) {
        #expect(GermanTax.incomeTax(GermanTax.tariffs[year]!.basicAllowance, year: year) == 0)
        #expect(GermanTax.incomeTax(-5000, year: year) == 0)
        let taxes = stride(from: 0, through: 400_000, by: 2_500).map { GermanTax.incomeTax($0, year: year) }
        #expect(taxes == taxes.sorted())
    }

    @Test func knownValues() {
        #expect(GermanTax.incomeTax(69878, year: 2026) == 18213)
        #expect(GermanTax.incomeTax(69879, year: 2026) == 18213)
        #expect(GermanTax.incomeTax(dec("100000.99"), year: 2025) == Int(0.42 * 100_000 - 10911.92))
        #expect(GermanTax.incomeTax(300_000, year: 2024) == Int(0.45 * 300_000 - 18971.06))
    }

    @Test func tariffYearClamps() {
        #expect(GermanTax.tariffYear(2019) == 2021)
        #expect(GermanTax.tariffYear(2030) == 2026)
        #expect(GermanTax.tariffYear(2024) == 2024)
    }

    @Test func solidaritySurchargeZones() {
        #expect(GermanTax.solidaritySurcharge(19950, year: 2025) == 0)
        #expect(GermanTax.solidaritySurcharge(30000, year: 2025) == dec("1195.95"))   // Milderungszone
        #expect(GermanTax.solidaritySurcharge(100000, year: 2025) == dec("5500.00"))  // full 5.5 %
    }

    @Test func taxEstimate() throws {
        func entry(_ kind: Kind, _ fields: [String: FieldInput]) throws -> LedgerEntry {
            LedgerEntry(kind: kind, values: try RecordRules.prepareCreate(kind, fields))
        }
        func vat(_ rate: String, _ amount: String) -> FieldInput { .vatRates([VatRowInput(rate: rate, amount: amount)]) }
        let entries = [
            try entry(.income, ["date": .text("2025-03-01"), "gross_amount": .text("119000"), "vat_rates": vat("19", "19000")]),
            try entry(.income, ["date": .text("2025-04-01"), "gross_amount": .text("500"),
                                "sale_type": .text(SortedMarkers.vatRefundSaleType)]),
            try entry(.expenses, ["date": .text("2025-03-05"), "gross_amount": .text("11900"), "vat_rates": vat("19", "1900")]),
            try entry(.expenses, ["date": .text("2025-03-06"), "gross_amount": .text("238"), "deductible_amount": .text("166.60"),
                                  "vat_rates": vat("19", "38"), "category": .text("Business meals")]),
            try entry(.expenses, ["date": .text("2025-05-10"), "gross_amount": .text("9000"),
                                  "category": .text(SortedMarkers.vatPaymentCategory)]),
            try entry(.income, ["date": .text("2026-01-02"), "gross_amount": .text("99999")]),
        ]
        let t = try Reports.taxes(entries, year: 2025)
        #expect(t.vat.outputVat == 19000 && t.vat.inputVat == 1938)
        #expect(t.vat.outstanding == dec("8562"))  // 19000 − 1938 − 9000 + 500
        #expect(t.incomeTax.deductibleExpensesNet == dec("10140.00"))
        #expect(t.incomeTax.taxableProfit == dec("89860.00"))
        #expect(t.incomeTax.incomeTax == Decimal(GermanTax.incomeTax(89860, year: 2025)))
        #expect(t.totalDue == t.vat.outstanding + t.incomeTax.incomeTax + t.incomeTax.solidaritySurcharge)

        let totals = Reports.summary(entries, from: "2025-01-01", to: "2025-12-31", groupBy: .year,
                                     excludeVatSettlements: true).totals
        #expect(totals.incomeNet == 100000 && totals.expensesGross == 12138)
        #expect(Reports.summary(entries, groupBy: .year).totals.expensesGross == 21138)

        let partial = try Reports.taxes(entries, year: 2025, dateTo: "2025-03-31")
        #expect(partial.vat.payments == 0 && partial.dateTo == "2025-03-31")
        #expect(throws: ValidationError.self) { try Reports.taxes(entries, year: 2025, dateTo: "2026-01-01") }
    }

    @Test func summaryGroupsByQuarter() throws {
        let entries = [
            LedgerEntry(kind: .income, date: "2025-01-10", convertedGross: 1190, net: 1000, vat: 190),
            LedgerEntry(kind: .expenses, date: "2025-01-20", convertedGross: 119, net: 100, vat: 19, deductible: 119, category: "Software"),
            LedgerEntry(kind: .expenses, date: "2025-04-01", convertedGross: 50, net: 50, vat: 0, deductible: 50, category: "Rent"),
        ]
        let s = Reports.summary(entries, groupBy: .quarter)
        #expect(s.periods.map(\.period) == ["2025-01-01", "2025-04-01"])
        let q1 = s.periods[0]
        #expect((q1.incomeNet, q1.expensesNet, q1.profit, q1.vatBalance) == (1000, 100, 900, 171))
        #expect(s.totals.profit == 850)
    }
}
