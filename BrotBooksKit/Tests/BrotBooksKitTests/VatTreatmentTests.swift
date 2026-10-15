import Foundation
import SwiftData
import Testing
@testable import BrotBooksKit

@Suite struct VatTreatmentSuggestTests {
    static let germany = EditForm.regions[0], eu = EditForm.regions[1], outside = EditForm.regions[2]

    func expense(region: String?, vat: [VatRate] = [], date: String = "2026-05-04") -> RecordValues {
        ["date": .date(date), "supplier_region": region.map(FieldValue.text) ?? .null, "vat_rates": .vatRates(vat)]
    }

    func income(region: String?, vatNumber: String? = nil, isPrivate: Bool? = nil, vat: [VatRate] = []) -> RecordValues {
        ["date": .date("2026-05-04"), "client_region": region.map(FieldValue.text) ?? .null,
         "client_vat_number": vatNumber.map(FieldValue.text) ?? .null,
         "client_is_private_person": isPrivate.map(FieldValue.bool) ?? .null, "vat_rates": .vatRates(vat)]
    }

    func suggest(_ kind: Kind, _ values: RecordValues) -> VatTreatment.Suggestion {
        VatTreatment.suggest(kind, values: values)
    }

    static let vat19 = [VatRate(rate: 19, amount: dec("19.00"))]

    @Test func expenseByRegionAndVatRows() {
        typealias S = VatTreatment.Suggestion
        let g = Self.germany, eu = Self.eu, out = Self.outside
        // German supplier.
        #expect(suggest(.expenses, expense(region: g, vat: Self.vat19)) == S(.domesticVat))
        #expect(suggest(.expenses, expense(region: g, vat: [VatRate(rate: 7, amount: 1), VatRate(rate: 19, amount: 2)]))
                == S(.domesticVat))
        #expect(suggest(.expenses, expense(region: g)) == S(.noVat))
        // A 0 % row or a row with no amount is no VAT.
        #expect(suggest(.expenses, expense(region: g, vat: [VatRate(rate: 0, amount: 0)])) == S(.noVat))
        // EU supplier: reverse charge without VAT (goods acquisition is the alternative to confirm).
        #expect(suggest(.expenses, expense(region: eu)) == S(.rcEUService, alternative: .euGoodsAcquisition))
        #expect(suggest(.expenses, expense(region: eu, vat: [VatRate(rate: 19, amount: 0)]))
                == S(.rcEUService, alternative: .euGoodsAcquisition))
        // EU supplier charging German VAT, or its own country's VAT.
        #expect(suggest(.expenses, expense(region: eu, vat: Self.vat19)) == S(.domesticVat))
        #expect(suggest(.expenses, expense(region: eu, vat: [VatRate(rate: 23, amount: dec("23"))])) == S(.noVat))
        #expect(suggest(.expenses, expense(region: eu, vat: [VatRate(rate: 16, amount: 16)], date: "2020-09-01"))
                == S(.domesticVat))
        #expect(suggest(.expenses, expense(region: eu, vat: [VatRate(rate: 16, amount: 16)])) == S(.noVat))
        // Non-EU supplier: reverse charge without VAT (import is the alternative to confirm).
        #expect(suggest(.expenses, expense(region: out)) == S(.rcNonEUService, alternative: .importVat))
        #expect(suggest(.expenses, expense(region: out, vat: [VatRate(rate: 20, amount: 20)])) == S(.noVat))
        #expect(suggest(.expenses, expense(region: out, vat: Self.vat19)) == S(.domesticVat))
        // No region: decided by the VAT rows alone.
        #expect(suggest(.expenses, expense(region: nil, vat: Self.vat19)) == S(.domesticVat))
        #expect(suggest(.expenses, expense(region: nil)) == S(.noVat))
        // VAT paid to the tax office.
        var payment = expense(region: g)
        payment["category"] = .text(SortedMarkers.vatPaymentCategory)
        #expect(suggest(.expenses, payment) == S(.noVat))
    }

    @Test func incomeByRegionVatNumberAndPrivatePerson() {
        typealias S = VatTreatment.Suggestion
        let g = Self.germany, eu = Self.eu, out = Self.outside
        #expect(suggest(.income, income(region: g)) == S(.domestic))
        #expect(suggest(.income, income(region: g, vatNumber: "DE123456789", isPrivate: false)) == S(.domestic))
        #expect(suggest(.income, income(region: nil)) == S(.domestic))
        // EU: a business (flagged, or with a VAT number) is a B2B service, goods the alternative.
        let b2b = S(.euB2BService, alternative: .euB2BGoods)
        #expect(suggest(.income, income(region: eu, vatNumber: "IE6388047V")) == b2b)
        #expect(suggest(.income, income(region: eu, vatNumber: "IE6388047V", isPrivate: false)) == b2b)
        #expect(suggest(.income, income(region: eu, isPrivate: false)) == b2b)
        #expect(suggest(.income, income(region: eu, vatNumber: "  ")) == S(.domestic))
        #expect(suggest(.income, income(region: eu)) == S(.domestic))
        #expect(suggest(.income, income(region: eu, vatNumber: "IE6388047V", isPrivate: true)) == S(.domestic))
        #expect(suggest(.income, income(region: eu, isPrivate: true)) == S(.domestic))
        // Outside the EU: service abroad, export the alternative.
        let abroad = S(.nonEUService, alternative: .exportGoods)
        #expect(suggest(.income, income(region: out)) == abroad)
        #expect(suggest(.income, income(region: out, vatNumber: "US-EIN", isPrivate: false)) == abroad)
        #expect(suggest(.income, income(region: out, isPrivate: true)) == abroad)
        // German VAT on the invoice is domestic wherever the client is.
        #expect(suggest(.income, income(region: eu, vatNumber: "IE6388047V", vat: Self.vat19)) == S(.domestic))
        #expect(suggest(.income, income(region: out, vat: Self.vat19)) == S(.domestic))
        // A VAT refund from the tax office.
        var refund = income(region: g)
        refund["sale_type"] = .text(SortedMarkers.vatRefundSaleType)
        #expect(suggest(.income, refund) == S(.notTaxable))
    }

    @Test func goodsOrServiceAlwaysNeedsAChoice() {
        for treatment in VatTreatment.allCases {
            if let counterpart = treatment.goodsServiceCounterpart {
                #expect(counterpart.goodsServiceCounterpart == treatment)
                #expect(counterpart.kind == treatment.kind)
            }
        }
        #expect(VatTreatment.Suggestion(.rcEUService, alternative: .euGoodsAcquisition).needsGoodsOrServiceChoice)
        #expect(!VatTreatment.Suggestion(.domesticVat).needsGoodsOrServiceChoice)
        // Every suggestion that lands on a goods-or-service case carries its alternative.
        let samples: [(Kind, RecordValues)] = [
            (.expenses, expense(region: Self.eu)), (.expenses, expense(region: Self.outside)),
            (.income, income(region: Self.eu, vatNumber: "IE1")), (.income, income(region: Self.outside)),
        ]
        for (kind, values) in samples {
            let s = suggest(kind, values)
            #expect(s.alternative != nil && s.alternative == s.treatment.goodsServiceCounterpart)
        }
    }

    @Test func casesPerKind() {
        #expect(VatTreatment.cases(for: .income).map(\.rawValue)
                == ["domestic", "euB2BService", "euB2BGoods", "exportGoods", "nonEUService", "notTaxable"])
        #expect(VatTreatment.cases(for: .expenses).map(\.rawValue)
                == ["domesticVat", "rcEUService", "rcNonEUService", "euGoodsAcquisition", "importVat", "noVat"])
    }

    @Test func statusIsConfirmedOnlyWhenSetExplicitly() {
        var values = expense(region: Self.eu)
        let suggested = VatTreatmentStatus.of(.expenses, values: values)
        #expect(suggested.treatment == .rcEUService && !suggested.isConfirmed)
        #expect(suggested.suggestion == VatTreatment.Suggestion(.rcEUService, alternative: .euGoodsAcquisition))
        values["vat_treatment"] = .text("euGoodsAcquisition")
        #expect(VatTreatmentStatus.of(.expenses, values: values)
                == VatTreatmentStatus(treatment: .euGoodsAcquisition, isConfirmed: true, suggestion: nil))
        // A stored value of the other kind (or an unknown one) doesn't count as set.
        values["vat_treatment"] = .text("euB2BGoods")
        #expect(!VatTreatmentStatus.of(.expenses, values: values).isConfirmed)
        values["vat_treatment"] = .text("bogus")
        #expect(VatTreatmentStatus.of(.expenses, values: values).treatment == .rcEUService)
    }
}

@Suite struct DeductibleShareTests {
    func values(gross: String?, deductible: String?) -> RecordValues {
        var v = RecordValues()
        if let gross { v["converted_gross_amount"] = .decimal(dec(gross)) }
        if let deductible { v["deductible_amount"] = .decimal(dec(deductible)) }
        return v
    }

    @Test func fullWhenUnsetOrEqualToGross() {
        #expect(DeductibleShare.of(values(gross: "119.00", deductible: nil)) == 1)
        #expect(DeductibleShare.of(values(gross: "119.00", deductible: "119.00")) == 1)
        #expect(DeductibleShare.of(values(gross: nil, deductible: "50")) == 1)
        #expect(DeductibleShare.of(values(gross: "0", deductible: "0")) == 1)
    }

    @Test func partialShareOfTheGross() {
        // Phone used 50 % for business: deductible is half the gross.
        #expect(DeductibleShare.of(values(gross: "119.00", deductible: "59.50")) == dec("0.5"))
        // Reverse-charge records have no VAT rows, so gross is net.
        #expect(DeductibleShare.of(values(gross: "200.00", deductible: "140.00")) == dec("0.7"))
        // Credit notes: both negative.
        #expect(DeductibleShare.of(values(gross: "-100", deductible: "-25")) == dec("0.25"))
    }

    @Test func clampedToZeroAndOne() {
        #expect(DeductibleShare.of(values(gross: "100", deductible: "150")) == 1)
        #expect(DeductibleShare.of(values(gross: "100", deductible: "-10")) == 0)
        #expect(DeductibleShare.of(values(gross: "100", deductible: "0")) == 0)
    }

    @Test func defaultDeductibleAmountIsAFullShare() throws {
        // A new expense's deductible amount defaults to its gross, which is a 100 % share.
        let record = try RecordRules.prepareCreate(.expenses, ["date": .text("2026-05-04"), "gross_amount": .text("71.40"),
                                                               "vat_rates": .vatRates([VatRowInput(rate: "19", amount: "11.40")])])
        #expect(DeductibleShare.of(record) == 1)
    }
}

@Suite struct VatTreatmentFieldTests {
    @Test func editorHasASelectOfTheKindsTreatments() throws {
        for kind in Kind.allCases {
            let field = try #require(EditForm.fields(kind).first { $0.name == "vat_treatment" })
            #expect(field.label == "VAT treatment" && field.type == .select)
            #expect(field.options == VatTreatment.cases(for: kind).map(\.rawValue))
        }
    }

    @Test func editorRoundTripsTheTreatment() throws {
        let values: RecordValues = ["date": .date("2026-05-04"), "supplier_region": .text("European Union"),
                                    "vat_rates": .vatRates([]), "vat_treatment": .null]
        let initial = EditForm.initialState(.expenses, values: values)
        #expect(initial.text["vat_treatment"] == "")
        var s = initial
        s.text["vat_treatment"] = "rcEUService"
        let changes = EditForm.changedFields(.expenses, initial: initial, current: s)
        #expect(changes == ["vat_treatment": .text("rcEUService")])
        #expect(try RecordRules.prepareUpdate(.expenses, before: values, changes) == ["vat_treatment": .text("rcEUService")])
        // Clearing goes back to unset.
        let set = EditForm.initialState(.expenses, values: values.merging(["vat_treatment": .text("rcEUService")]) { $1 })
        var cleared = set
        cleared.text["vat_treatment"] = ""
        #expect(EditForm.changedFields(.expenses, initial: set, current: cleared) == ["vat_treatment": .null])
    }

    @Test func rulesRejectTreatmentsOfTheOtherKind() throws {
        #expect(throws: ValidationError("vat_treatment: not a expenses treatment: 'euB2BGoods'")) {
            try RecordRules.coerce(.expenses, ["vat_treatment": .text("euB2BGoods")])
        }
        #expect(throws: ValidationError("vat_treatment: not a income treatment: 'nope'")) {
            try RecordRules.coerce(.income, ["vat_treatment": .text("nope")])
        }
        #expect(try RecordRules.coerce(.income, ["vat_treatment": .text("euB2BGoods")]) == ["vat_treatment": .text("euB2BGoods")])
        #expect(try RecordRules.coerce(.income, ["vat_treatment": .null]) == ["vat_treatment": .null])
    }

    @Test func notASortedColumn() {
        for kind in Kind.allCases {
            #expect(!Columns.of(kind).contains { $0.name == "vat_treatment" })
            #expect(!Columns.headers(kind).contains("VAT treatment"))
            #expect(RecordRules.writable(kind).contains { $0.name == "vat_treatment" })
        }
    }

    @Test func invoiceDraftSuggestsReverseChargeUnconfirmed() {
        let eu = InvoiceDraftBuilder.build(
            ExtractedInvoice(supplier: "Figma Ireland Ltd", invoiceDate: "2026-10-01", grossAmount: "45.00", currency: "EUR",
                             reverseCharge: true, supplierRegion: "Germany"),
            sourceFilename: nil, today: "2026-10-11")
        #expect(eu.vatTreatment == VatTreatment.Suggestion(.rcEUService, alternative: .euGoodsAcquisition))
        #expect(eu.fields["vat_treatment"] == nil)

        let us = InvoiceDraftBuilder.build(ExtractedInvoice(grossAmount: "20.00", currency: "USD", reverseCharge: true),
                                           sourceFilename: nil, today: "2026-10-11")
        #expect(us.vatTreatment == VatTreatment.Suggestion(.rcNonEUService, alternative: .importVat))

        let domestic = InvoiceDraftBuilder.build(
            ExtractedInvoice(invoiceDate: "2026-10-01", grossAmount: "119.00", currency: "EUR",
                             vatLines: [.init(rate: 19, amount: "19.00")], supplierRegion: "Germany"),
            sourceFilename: nil, today: "2026-10-11")
        #expect(domestic.vatTreatment == VatTreatment.Suggestion(.domesticVat))
    }
}

@MainActor
@Suite struct VatTreatmentStoreTests {
    @Test func storedOnRecordsAndKeptAcrossSortedReimport() throws {
        let t = try TestStore()
        defer { t.cleanUp() }
        _ = try t.import("sample_v1.zip")
        let thing = try #require(try t.expenses()["aaaa1"])
        #expect(thing.vatTreatment == nil && !thing.vatTreatmentStatus.isConfirmed)
        try t.store.update(thing.persistentModelID, fields: ["vat_treatment": .text("noVat")])
        #expect(thing.vatTreatment == "noVat")
        #expect(thing.vatTreatmentStatus == VatTreatmentStatus(treatment: .noVat, isConfirmed: true, suggestion: nil))

        // sample_v2 changes aaaa1; the app-local treatment survives the update.
        let summary = try t.import("sample_v2.zip")
        #expect(summary.kind(.expenses)?.updated == 1)
        #expect(try t.expenses()["aaaa1"]?.grossAmount == "12")
        #expect(try t.expenses()["aaaa1"]?.vatTreatment == "noVat")

        let id = try t.store.create(.income, fields: ["date": .text("2026-05-04"), "gross_amount": .text("1000"),
                                                      "client_region": .text("European Union"),
                                                      "client_vat_number": .text("IE6388047V"),
                                                      "vat_treatment": .text("euB2BGoods")])
        let income = try #require(t.store.record(id) as? Income)
        #expect(income.vatTreatment == "euB2BGoods")
        let snapshot = RecordSnapshot(income)
        #expect(snapshot.values["vat_treatment"] == .text("euB2BGoods"))
        #expect(snapshot.vatTreatmentStatus.isConfirmed)
        try t.store.update(id, fields: ["vat_treatment": .null])
        #expect(income.vatTreatment == nil)
        #expect(RecordSnapshot(income).vatTreatmentStatus
                == VatTreatmentStatus(treatment: .euB2BService, isConfirmed: false,
                                      suggestion: .init(.euB2BService, alternative: .euB2BGoods)))
    }
}
