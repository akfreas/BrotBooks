import Foundation
import Testing
@testable import BrotBooksKit

func dec(_ s: String) -> Decimal { Decimal(string: s, locale: Locale(identifier: "en_US_POSIX"))! }

@Suite struct MoneyTests {
    @Test func parsesApiStringsExactly() {
        #expect(Money.parse("1234.56") == dec("1234.56"))
        #expect(Money.parse("-302.18") == dec("-302.18"))
        #expect(Money.parse("0") == 0)
        #expect(Money.parse("0.973300") == dec("0.9733"))
        #expect(Money.parse("") == nil)
        #expect(Money.parse("abc") == nil)
        #expect(Money.parse("1,5") == nil)
        #expect(Money.parseInput("1,5") == dec("1.5"))
        // No binary floating point on the way: 0.1 + 0.2 is exactly 0.3.
        #expect(Money.parse("0.1")! + Money.parse("0.2")! == dec("0.3"))
    }

    @Test func formatsEuro() {
        #expect(Money.format(dec("127837.05")) == "€127,837.05")
        #expect(Money.format(dec("-302.18")) == "−€302.18")
        #expect(Money.format(dec("5"), signed: true) == "+€5.00")
        #expect(Money.format(0, signed: true) == "€0.00")
        #expect(Money.format(nil) == "€0.00")
        #expect(Money.format(dec("1000000")) == "€1,000,000.00")
        #expect(Money.parts(dec("127837.05")) == Money.Parts(negative: false, symbol: "€", whole: "127,837", cents: "05"))
        #expect(Money.parts(dec("0.5")).cents == "50")
        #expect(Money.formatForeign(dec("800"), currency: "USD") == "USD 800.00")
    }

    @Test func roundingModes() {
        #expect(Money.rounded(dec("0.125")) == dec("0.13"))                  // half away from zero
        #expect(Money.rounded(dec("0.125"), mode: .bankers) == dec("0.12"))  // half even
        #expect(Money.truncated(dec("1195.959")) == dec("1195.95"))
        #expect(Money.plainString(dec("2731.25")) == "2731.25")
    }
}

@Suite struct DashboardWindowTests {
    @Test func currentYearRunsToTodayAndComparesSameWindow() {
        let w = DashboardWindow(year: 2026, today: "2026-10-10")
        #expect(w.partial)
        #expect((w.start, w.end) == ("2026-01-01", "2026-10-10"))
        #expect((w.previousStart, w.previousEnd) == ("2025-01-01", "2025-10-10"))
    }

    @Test func pastYearComparesFullYears() {
        let w = DashboardWindow(year: 2024, today: "2026-10-10")
        #expect(!w.partial)
        #expect((w.start, w.end, w.previousStart, w.previousEnd) == ("2024-01-01", "2024-12-31", "2023-01-01", "2023-12-31"))
    }

    @Test func leapDayComparesWithFeb28() {
        let w = DashboardWindow(year: 2028, today: "2028-02-29")
        #expect(w.previousEnd == "2027-02-28")
        #expect(DashboardWindow.previousYearDate("2024-02-29") == "2023-02-28")
        #expect(DashboardWindow.previousYearDate("2024-03-01") == "2023-03-01")
    }

    @Test func yearOptionsIncludeCurrentYear() {
        #expect(DashboardWindow.yearOptions(dataYears: [2021, 2025, 2023], currentYear: 2026) == [2026, 2025, 2023, 2021])
        #expect(DashboardWindow.yearOptions(dataYears: [2026], currentYear: 2026, selected: 2019) == [2026, 2019])
    }

    @Test func todayUsesTheGivenTimeZone() {
        // 23:30 UTC on Oct 9 is already Oct 10 in Berlin.
        let instant = ISO8601DateFormatter().date(from: "2026-10-09T23:30:00Z")!
        #expect(ISODate.today(instant, timeZone: TimeZone(identifier: "Europe/Berlin")!) == "2026-10-10")
        #expect(ISODate.today(instant, timeZone: TimeZone(identifier: "UTC")!) == "2026-10-09")
    }

    @Test func percentChangeAndInitials() {
        #expect(DashboardMath.percentChange(current: 150, previous: 100) == 50)
        #expect(DashboardMath.percentChange(current: 50, previous: -100) == 150)
        #expect(DashboardMath.percentChange(current: 5, previous: 0) == nil)
        #expect(DashboardMath.initials("Palo Alto Strategy Group 71") == "PA")
        #expect(DashboardMath.initials("🤖 receipts 4CBC5B9E") == "R4")
        #expect(DashboardMath.initials(nil) == "·")
    }

    @Test func cumulativeProfitFillsGaps() {
        var jan = SummaryRow(period: "2026-01-01"); jan.incomeNet = 100
        var mar = SummaryRow(period: "2026-03-01"); mar.expensesNet = 30
        let points = DashboardMath.cumulativeProfit(year: 2026, months: [jan, mar])
        #expect(points.map(\.cumulative) == [100, 100, 70])
        #expect(points.map(\.month) == [1, 2, 3])
    }
}

@Suite struct EditFormTests {
    let record: RecordValues = [
        "description": .text("Laptop"), "date": .date("2025-02-01"), "gross_amount": .decimal(dec("1190.00")),
        "currency": .text("EUR"), "category": .text("Tools"), "supplier_region": .null,
        "vat_rates": .vatRates([VatRate(rate: 19, amount: dec("190.0"))]),
    ]

    @Test func unchangedFormHasNoChanges() {
        let s = EditForm.initialState(.expenses, values: record)
        #expect(s.text["gross_amount"] == "1190.00")
        #expect(s.vat == [VatRowInput(rate: "19", amount: "190.00")])
        #expect(EditForm.amountText(dec("-0.5")) == "-0.50" && EditForm.amountText(dec("1.234")) == "1.234")
        #expect(EditForm.changedFields(.expenses, initial: s, current: s).isEmpty)
    }

    @Test func onlyChangedFieldsWithEmptyAsNullAndDecimalCommas() {
        let initial = EditForm.initialState(.expenses, values: record)
        var s = initial
        s.text["description"] = "Laptop 14\""
        s.text["category"] = ""
        s.text["gross_amount"] = "2380,50"
        let changes = EditForm.changedFields(.expenses, initial: initial, current: s)
        #expect(changes == ["description": .text("Laptop 14\""), "category": .null, "gross_amount": .text("2380.50")])
    }

    @Test func vatRowsCompareByValue() {
        let initial = EditForm.initialState(.expenses, values: record)
        var s = initial
        s.vat = [VatRowInput(rate: "19", amount: "190,00"), VatRowInput(rate: " ", amount: "")]
        #expect(EditForm.changedFields(.expenses, initial: initial, current: s).isEmpty)
        s.vat.append(VatRowInput(rate: "7", amount: "3,5"))
        #expect(EditForm.changedFields(.expenses, initial: initial, current: s)
            == ["vat_rates": .vatRates([VatRowInput(rate: "19", amount: "190.00"), VatRowInput(rate: "7", amount: "3.5")])])
        s.vat = []
        #expect(EditForm.changedFields(.expenses, initial: initial, current: s) == ["vat_rates": .vatRates([])])
    }

    @Test func checkboxAndIncomeFields() {
        let income: RecordValues = ["date": .date("2025-01-01"), "payment_status": .text("Unpaid"),
                                    "client_is_private_person": .bool(false)]
        let initial = EditForm.initialState(.income, values: income)
        var s = initial
        s.flags["client_is_private_person"] = true
        s.text["payment_date"] = "2025-02-01"
        #expect(EditForm.changedFields(.income, initial: initial, current: s)
            == ["client_is_private_person": .bool(true), "payment_date": .text("2025-02-01")])
    }

    @Test func diffFeedsUpdateRules() throws {
        let initial = EditForm.initialState(.expenses, values: record)
        var s = initial
        s.vat = [VatRowInput(rate: "19", amount: "380")]
        s.text["gross_amount"] = "2380"
        var before = record
        before["converted_gross_amount"] = .decimal(dec("1190")); before["total_vat_amount"] = .decimal(dec("190"))
        before["net_amount"] = .decimal(dec("1000")); before["deductible_amount"] = .decimal(dec("1190"))
        let changes = try RecordRules.prepareUpdate(.expenses, before: before,
                                                    EditForm.changedFields(.expenses, initial: initial, current: s))
        #expect(changes["net_amount"] == .decimal(dec("2000")))
        #expect(changes["deductible_amount"] == .decimal(dec("2380")))
        #expect(changes["description"] == nil)
    }

    @Test func newRecordFields() throws {
        var s = EditForm.newState(.income, today: "2026-10-10")
        #expect(s.text["date"] == "2026-10-10" && s.text["payment_status"] == "Unpaid" && s.text["sale_type"] == "Service")
        s.text["gross_amount"] = "100"
        let values = try RecordRules.prepareCreate(.income, EditForm.createFields(.income, state: s))
        #expect(values["net_amount"] == .decimal(100))
        #expect(values["currency"] == .text("EUR"))
    }
}
