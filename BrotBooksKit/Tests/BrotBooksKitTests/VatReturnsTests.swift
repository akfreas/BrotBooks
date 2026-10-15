import Foundation
import Testing
@testable import BrotBooksKit

@Suite struct VatReturnScheduleTests {
    typealias F = UStVAFixtures

    func settings(_ periods: [TaxSettingsPeriod]) -> TaxSettings {
        TaxSettings(identity: F.identity, periods: periods)
    }

    @Test func monthlyWithDauerfristListsMonthsAndSondervorauszahlungNewestDueFirst() {
        let items = VatReturnSchedule.items(years: [2026], settings: settings([.initial(from: "2026-01-01")]))
        #expect(items.map(\.id) == (1...12).reversed().map { String(format: "2026-%02d", $0) } + ["2026-sondervorauszahlung"])
        #expect(items.first { $0.id == "2026-03" }?.dueDate == "2026-05-10")
        #expect(items.first { $0.id == "2026-12" }?.dueDate == "2027-02-10")
        let sv = items.first { $0.id == "2026-sondervorauszahlung" }
        #expect(sv?.dueDate == "2026-02-10")
        #expect(sv?.fileableFrom == "2026-01-01")
        #expect(!items.contains { $0.id == "2026-dauerfristverlaengerung" })
    }

    @Test func quarterlyWithDauerfristListsQuartersAndTheApplication() {
        let quarterly = TaxSettingsPeriod(effectiveFrom: "2025-01-01", ustvaFrequency: .quarterly)
        let items = VatReturnSchedule.items(years: [2025], settings: settings([quarterly]))
        #expect(items.map(\.id) == ["2025-44", "2025-43", "2025-42", "2025-41", "2025-dauerfristverlaengerung"])
        #expect(items.first { $0.id == "2025-41" }?.dueDate == "2025-05-10")
        // Due with the first quarter at its regular due date.
        #expect(items.last?.dueDate == "2025-04-10")
        #expect(items.last?.xml(result: nil, flags: [], header: F.header)?.contains("<Dauerfristverlaengerung>") == true)
    }

    @Test func withoutDauerfristNoYearlyItemsAndShorterDeadlines() {
        let plain = TaxSettingsPeriod(effectiveFrom: "2026-01-01", dauerfristverlaengerung: false)
        let items = VatReturnSchedule.items(years: [2026], settings: settings([plain]))
        #expect(items.count == 12)
        #expect(items.first { $0.id == "2026-03" }?.dueDate == "2026-04-10")
    }

    @Test func configurationChangesMidHistory() {
        // 2025 quarterly without extension, monthly with Dauerfrist from 2026, annual only from July 2026 on,
        // quarterly again from November (mid-quarter: listed as months).
        let s = settings([
            TaxSettingsPeriod(effectiveFrom: "2025-01-01", ustvaFrequency: .quarterly, dauerfristverlaengerung: false),
            TaxSettingsPeriod(effectiveFrom: "2026-01-01"),
            TaxSettingsPeriod(effectiveFrom: "2026-07-01", ustvaFrequency: .none),
            TaxSettingsPeriod(effectiveFrom: "2026-11-01", ustvaFrequency: .quarterly, dauerfristverlaengerung: false),
        ])
        let items = VatReturnSchedule.items(years: [2025, 2026], settings: s)
        let ids = Set(items.map(\.id))
        #expect(ids == Set(["2025-41", "2025-42", "2025-43", "2025-44", "2026-01", "2026-02", "2026-03", "2026-04",
                            "2026-05", "2026-06", "2026-11", "2026-12", "2026-sondervorauszahlung"]))
        // Each period uses the settings in force on its first day.
        #expect(items.first { $0.id == "2025-44" }?.dueDate == "2026-01-10")
        #expect(items.first { $0.id == "2026-06" }?.dueDate == "2026-08-10")
        #expect(items.first { $0.id == "2026-12" }?.dueDate == "2027-01-10")
        #expect(items.first { $0.id == "2026-12" }?.configuration.ustvaFrequency == .quarterly)
    }

    @Test func nothingBeforeTheFirstSettingsPeriod() {
        let items = VatReturnSchedule.items(years: [2025], settings: settings([.initial(from: "2026-01-01")]))
        #expect(items.isEmpty)
    }

    @Test func status() {
        let items = VatReturnSchedule.items(years: [2026], settings: settings([.initial(from: "2026-01-01")]))
        let march = items.first { $0.id == "2026-03" }!
        #expect(VatReturnStatus.of(march, today: "2026-03-31") == .notDue)
        #expect(VatReturnStatus.of(march, today: "2026-04-01") == .dueIn(days: 39))
        #expect(VatReturnStatus.of(march, today: "2026-05-10") == .dueIn(days: 0))
        #expect(VatReturnStatus.of(march, today: "2026-05-11") == .overdue(days: 1))
        #expect(VatReturnStatus.of(march, today: "2027-05-11") == .overdue(days: 366))
        #expect(VatReturnStatus.of(march, today: "2027-05-11", filing: .test) == .filedTest)
        #expect(VatReturnStatus.of(march, today: "2026-03-01", filing: .production) == .filed)
        #expect(VatReturnStatus.filedTest.isOpen)
        #expect(!VatReturnStatus.filed.isOpen)
        let sv = items.first { $0.id == "2026-sondervorauszahlung" }!
        #expect(VatReturnStatus.of(sv, today: "2025-12-31") == .notDue)
        #expect(VatReturnStatus.of(sv, today: "2026-01-01") == .dueIn(days: 40))
    }

    @Test func daysBetweenDates() {
        #expect(ISODate.days(from: "2026-01-01", to: "2026-01-01") == 0)
        #expect(ISODate.days(from: "2024-02-28", to: "2024-03-01") == 2)
        #expect(ISODate.days(from: "2026-03-01", to: "2025-03-01") == -365)
        #expect(ISODate.days(from: "1970-01-01", to: "2000-01-01") == 10957)
        #expect(ISODate.days(from: "x", to: "2000-01-01") == nil)
    }

    @Test func sondervorauszahlungComesFromTheOverride() {
        var withOverride = TaxSettingsPeriod.initial(from: "2026-01-01")
        withOverride.sondervorauszahlungOverride = 400
        let items = VatReturnSchedule.items(years: [2026], settings: settings([withOverride]))
        let december = items.first { $0.id == "2026-12" }!
        let november = items.first { $0.id == "2026-11" }!
        let sv = items.first { $0.id == "2026-sondervorauszahlung" }!
        #expect(december.sondervorauszahlung == 400)
        #expect(!december.needsSondervorauszahlungAmount)
        #expect(november.sondervorauszahlung == nil)
        #expect(!november.needsSondervorauszahlungAmount)
        #expect(december.aggregate([])?.kennzahlen[.kz39] == 400)
        #expect(sv.xml(result: nil, flags: [], header: F.header)?.contains("<Kz38>400</Kz38>") == true)

        let plain = VatReturnSchedule.items(years: [2026], settings: settings([.initial(from: "2026-01-01")]))
        let decemberPlain = plain.first { $0.id == "2026-12" }!
        let svPlain = plain.first { $0.id == "2026-sondervorauszahlung" }!
        #expect(decemberPlain.needsSondervorauszahlungAmount)
        #expect(decemberPlain.aggregate([])?.kennzahlen[.kz39] == nil)
        #expect(svPlain.needsSondervorauszahlungAmount)
        #expect(svPlain.xml(result: nil, flags: [], header: F.header) == nil)
    }

    @Test func ustvaXMLCarriesFlagsAndHeader() {
        let items = VatReturnSchedule.items(years: [2026], settings: settings([.initial(from: "2026-01-01")]))
        let march = items.first { $0.id == "2026-03" }!
        let result = march.aggregate([F.income("i", gross: "1190", .domestic, ["vat_rates": F.vat([("19", "190")])])])
        let header = UStVAXML.header(herstellerID: "27425", produktVersion: "1.2", today: "2026-10-10")
        #expect(header.erstellungsdatum == "20261010")
        let xml = march.xml(result: result, flags: [.correction, .noDirectDebit], header: header)!
        #expect(xml.contains("<Zeitraum>03</Zeitraum>"))
        #expect(xml.contains("<Kz10>1</Kz10>"))
        #expect(xml.contains("<Kz26>1</Kz26>"))
        #expect(!xml.contains("<Kz22>"))
        #expect(xml.contains("<Kz81>1000</Kz81>"))
        #expect(xml.contains("<Erstellungsdatum>20261010</Erstellungsdatum>"))
        #expect(march.availableFlags.map(\.number) == [10, 22, 26, 29])
        let sv = items.first { $0.id == "2026-sondervorauszahlung" }!
        #expect(sv.availableFlags.map(\.number) == [10, 26, 29])
        #expect(march.datenartVersion == "UStVA_2026")
    }
}

@Suite struct VatTreatmentReviewTests {
    typealias F = UStVAFixtures

    let items = VatReturnSchedule.items(years: [2026], settings: TaxSettings(periods: [.initial(from: "2026-01-01")]))

    @Test func listsUnconfirmedRecordsInOpenPeriodsOnly() {
        var draft = F.expense("draft", gross: "50", nil, ["supplier_region": .text("European Union")])
        draft.isDraft = true
        var removed = F.expense("removed", gross: "50", nil, ["supplier_region": .text("European Union")])
        removed.isRemoved = true
        let records = [
            F.expense("eu-saas", gross: "50", nil, ["supplier_region": .text("European Union")]),
            F.income("eu-client", date: "2026-04-02", gross: "1000", nil,
                     ["client_region": .text("European Union"), "client_vat_number": .text("FR12345678901")]),
            F.expense("confirmed", gross: "50", .rcEUService, ["supplier_region": .text("European Union")]),
            F.expense("domestic", gross: "119", nil, ["vat_rates": F.vat([("19", "19")])]),
            F.expense("last-year", date: "2025-12-01", gross: "50", nil, ["supplier_region": .text("European Union")]),
            draft, removed,
        ]
        let entries = VatTreatmentReview.entries(records, items: items)
        #expect(Set(entries.map(\.id)) == ["eu-saas", "eu-client", "domestic"])
        let saas = entries.first { $0.id == "eu-saas" }!
        #expect(saas.period == .month(2026, 3))
        #expect(saas.suggestion == VatTreatment.Suggestion(.rcEUService, alternative: .euGoodsAcquisition))
        #expect(saas.suggestion.needsGoodsOrServiceChoice)
        let client = entries.first { $0.id == "eu-client" }!
        #expect(client.period == .month(2026, 4))
        #expect(client.suggestion == VatTreatment.Suggestion(.euB2BService, alternative: .euB2BGoods))
        #expect(entries.first { $0.id == "domestic" }?.suggestion.needsGoodsOrServiceChoice == false)

        // Filed periods drop out.
        let open = VatTreatmentReview.entries(records, items: items) { $0.id != "2026-03" }
        #expect(open.map(\.id) == ["eu-client"])
    }

    @Test func quietWhenEverythingIsConfirmed() {
        let records = [F.expense("confirmed", gross: "50", .rcEUService, ["supplier_region": .text("European Union")])]
        #expect(VatTreatmentReview.entries(records, items: items).isEmpty)
    }
}

@Suite struct VatReturnIssueTests {
    typealias F = UStVAFixtures

    @Test func draftsInThePeriodAreReportedSeparately() {
        var draft = F.expense("draft", gross: "119", .domesticVat, ["vat_rates": F.vat([("19", "19")])])
        draft.isDraft = true
        var removedDraft = draft
        removedDraft.uid = "removed-draft"
        removedDraft.isRemoved = true
        var otherMonth = F.expense("draft-april", date: "2026-04-01", gross: "119", .domesticVat)
        otherMonth.isDraft = true
        let records = [draft, removedDraft, otherMonth, F.expense("approved", gross: "119", .domesticVat)]
        #expect(UStVAAggregator.draftIssues(records, period: .month(2026, 3))
            == [UStVAIssue(.draftInPeriod, recordUID: "draft", kind: .expenses)])
        // Drafts never block sending by themselves.
        #expect(!UStVAIssue(.draftInPeriod, recordUID: "draft", kind: .expenses).blocksSending)
    }

    @Test func implausibleCustomerVatIDs() {
        #expect(CustomerVatID.isPlausible("FR 12 345678901"))
        #expect(CustomerVatID.isPlausible("ATU12345678"))
        #expect(CustomerVatID.isPlausible("EL123456789"))
        #expect(!CustomerVatID.isPlausible("DE123456789"))
        #expect(!CustomerVatID.isPlausible("GR123456789"))
        #expect(!CustomerVatID.isPlausible("FRABC"))
        #expect(!CustomerVatID.isPlausible("n/a"))
        #expect(!CustomerVatID.isPlausible("FR123456789012345"))

        let records = [
            F.income("ok", gross: "100", .euB2BService, ["client_vat_number": .text("FR12345678901")]),
            F.income("german", gross: "100", .euB2BService, ["client_vat_number": .text("DE123456789")]),
            F.income("junk", gross: "100", .euB2BGoods, ["client_vat_number": .text("unknown")]),
            F.income("none", gross: "100", .euB2BGoods),
        ]
        let result = UStVAAggregator.aggregate(records, period: .month(2026, 3), configuration: F.configuration())
        #expect(result.issues == [
            UStVAIssue(.implausibleCustomerVatID, recordUID: "german", kind: .income),
            UStVAIssue(.implausibleCustomerVatID, recordUID: "junk", kind: .income),
            UStVAIssue(.missingCustomerVatID, recordUID: "none", kind: .income),
        ])
        #expect(!result.blocksSending)
    }

    @Test func filingRequirements() {
        #expect(F.identity.missingForFiling.isEmpty)
        #expect(TaxIdentity().missingForFiling == [.name, .steuernummer, .finanzamt])
        var regional = F.identity
        regional.steuernummer = "21/815/08150"
        #expect(regional.missingForFiling == [.steuernummer])
    }

    @Test func feldidentifikatorToKennzahl() {
        #expect(UStVAXML.kennzahlNumber(
            feldidentifikator: "/Anmeldungssteuern[1]/Steuerfall[1]/Umsatzsteuervoranmeldung[1]/Kz81[1]") == 81)
        #expect(UStVAXML.kennzahlNumber(feldidentifikator: "/Umsatzsteuervoranmeldung[1]/Kz09[1]") == 9)
        #expect(UStVAXML.kennzahlNumber(feldidentifikator: "/Anmeldungssteuern[1]/Steuerfall[1]/Unternehmer[1]") == nil)
        #expect(UStVAXML.kennzahlNumber(feldidentifikator: "/X/Kz123[1]") == nil)
    }
}

@Suite struct EditorSuggestionTests {
    @Test func followsTheFormWhileTheTreatmentIsEmpty() {
        let values = try! RecordRules.prepareCreate(.expenses, [
            "date": .text("2026-03-15"), "gross_amount": .text("50"), "supplier_region": .text("Germany"),
        ])
        let initial = EditForm.initialState(.expenses, values: values)
        #expect(EditForm.suggestedTreatment(.expenses, values: values, initial: initial, current: initial)
            == VatTreatment.Suggestion(.noVat))

        var edited = initial
        edited.text["supplier_region"] = "European Union"
        #expect(EditForm.suggestedTreatment(.expenses, values: values, initial: initial, current: edited)
            == VatTreatment.Suggestion(.rcEUService, alternative: .euGoodsAcquisition))

        edited.text["vat_treatment"] = "rcEUService"
        #expect(EditForm.suggestedTreatment(.expenses, values: values, initial: initial, current: edited) == nil)
    }

    @Test func newRecordsSuggestFromTheEnteredFields() {
        var state = EditForm.newState(.income, today: "2026-03-15")
        state.text["client_region"] = "Outside of the European Union"
        #expect(EditForm.suggestedTreatment(.income, values: [:], initial: EditForm.State(), current: state)
            == VatTreatment.Suggestion(.nonEUService, alternative: .exportGoods))
        // A half-typed amount doesn't hide the suggestion.
        state.text["gross_amount"] = "12,,"
        #expect(EditForm.suggestedTreatment(.income, values: [:], initial: EditForm.State(), current: state) != nil)
    }
}
