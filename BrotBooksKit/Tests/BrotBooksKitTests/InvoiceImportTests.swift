import Foundation
import SwiftData
import Testing
@testable import BrotBooksKit

@MainActor
@Suite struct InvoiceImportTests {
    static let pdf = Data("%PDF-1.4 invoice".utf8)

    func expense(_ t: TestStore, _ id: PersistentIdentifier) throws -> Expense {
        try #require(t.store.record(id) as? Expense)
    }

    func vat(_ rate: String, _ amount: String) -> FieldInput { .vatRates([VatRowInput(rate: rate, amount: amount)]) }

    // MARK: Drafts

    @Test func createDraftAttachesDocumentAndMarksDraft() throws {
        let t = try TestStore()
        defer { t.cleanUp() }
        let id = try t.store.createDraft(document: Self.pdf, filename: "adobe.pdf", today: "2026-10-11")
        let e = try expense(t, id)
        #expect(e.reviewStatus == "draft" && e.isDraft)
        #expect(e.date == "2026-10-11" && e.grossAmount == nil && e.currency == "EUR" && e.sortedRef == nil)
        let path = try #require(e.documentPath)
        #expect(try Data(contentsOf: t.store.documents.resolve(path)) == Self.pdf)
        #expect(e.documentSha256 == DocumentStore.sha256(Self.pdf))

        let snap = try #require(try t.store.snapshots(.expenses, drafts: .only).first)
        #expect(snap.isDraft && snap.hasDocument)
        #expect(snap.extraction == ExtractionInfo(state: .pending, sourceFilename: "adobe.pdf"))
        #expect(throws: ValidationError("document must be a PDF")) {
            try t.store.createDraft(document: Data("jpeg".utf8), filename: "x.jpg")
        }
    }

    @Test func draftsAreExcludedFromEntriesAndTotalsUntilApproved() throws {
        let t = try TestStore()
        defer { t.cleanUp() }
        try t.store.create(.expenses, fields: ["date": .text("2026-03-01"), "gross_amount": .text("50")])
        let id = try t.store.createDraft(document: Self.pdf, filename: nil, today: "2026-03-02")
        try t.store.update(id, fields: ["gross_amount": .text("119"), "vat_rates": vat("19", "19")])

        func expenseTotal() throws -> Decimal {
            try Reports.summary(t.store.entries(), from: "2026-01-01", to: "2026-12-31", groupBy: .year).totals.expensesGross
        }
        #expect(try t.store.entries().count == 1)
        #expect(try expenseTotal() == 50)
        #expect(try t.store.snapshots(.expenses).map(\.isDraft) == [false])
        #expect(try t.store.snapshots(.expenses, drafts: .only).map(\.id) == [id])
        #expect(try t.store.snapshots(.expenses, drafts: .include).count == 2)

        try t.store.approve(id)
        #expect(try t.store.entries().count == 2)
        #expect(try expenseTotal() == 169)
        #expect(try t.store.snapshots(.expenses).count == 2)
        #expect(try t.store.snapshots(.expenses, drafts: .only).isEmpty)
    }

    // MARK: Approval

    @Test func approveRejectsIncompleteDrafts() throws {
        let t = try TestStore()
        defer { t.cleanUp() }
        let id = try t.store.createDraft(document: Self.pdf, filename: nil, today: "2026-10-11")

        #expect(throws: ApprovalError(issues: [RecordIssue(field: "gross_amount", code: .missingGrossAmount)])) {
            try t.store.approve(id)
        }

        // A draft may be saved in a foreign currency without a rate, but not approved.
        try t.store.update(id, fields: ["gross_amount": .text("100"), "currency": .text("USD")])
        #expect(try expense(t, id).convertedGrossAmount == nil)
        do {
            try t.store.approve(id)
            Issue.record("approved a USD draft without a rate")
        } catch let error as ApprovalError {
            #expect(error.issues == [RecordIssue(field: "currency_conversion_rate", code: .missingConversionRate)])
            #expect(error.message(for: "currency_conversion_rate") == "Enter the conversion rate to EUR")
            #expect(error.message(for: "date") == nil)
        }

        try t.store.update(id, fields: ["currency": .text("EUR"), "vat_rates": vat("19", "30")])
        #expect(throws: ApprovalError(issues: [RecordIssue(field: "vat_rates", code: .vatMismatch)])) {
            try t.store.approve(id)
        }
        #expect(try expense(t, id).isDraft)

        try t.store.update(id, fields: ["vat_rates": vat("19", "15.97")])
        try t.store.approve(id)
        #expect(try !expense(t, id).isDraft)
    }

    @Test func finalIssuesCheckVatRows() {
        func issues(_ gross: String, _ rows: [VatRate]) -> [RecordIssue.Code] {
            RecordRules.finalIssues(.expenses, ["date": .date("2026-01-01"), "gross_amount": .decimal(dec(gross)),
                                                "converted_gross_amount": .decimal(dec(gross)), "currency": .text("EUR"),
                                                "vat_rates": .vatRates(rows)]).map(\.code)
        }
        #expect(issues("71.40", [VatRate(rate: 19, amount: dec("11.40"))]).isEmpty)
        #expect(issues("71.40", [VatRate(rate: 19, amount: dec("11.45"))]) == [.vatMismatch])
        #expect(issues("71.40", []).isEmpty)  // reverse charge or no VAT
        #expect(issues("-11.90", [VatRate(rate: 19, amount: dec("-1.90"))]).isEmpty)  // credit note
        // 100 net at 19 % and 50 net at 7 %.
        #expect(issues("172.50", [VatRate(rate: 19, amount: 19), VatRate(rate: 7, amount: dec("3.50"))]).isEmpty)
        #expect(issues("150.00", [VatRate(rate: 19, amount: 19), VatRate(rate: 7, amount: dec("3.50"))]) == [.vatMismatch])
        // A 0 % row covers an untaxed part, so the taxed rows only need to fit inside the gross.
        #expect(issues("130.00", [VatRate(rate: 19, amount: 19), VatRate(rate: 0, amount: 0)]).isEmpty)
        #expect(issues("10.00", [VatRate(rate: 0, amount: 1)]) == [.vatInvalid])
        #expect(RecordRules.finalIssues(.expenses, ["currency": .text("EUR")]).map(\.code)
                    == [.missingDate, .missingGrossAmount])
    }

    @Test func approveClearsExtraction() throws {
        let t = try TestStore()
        defer { t.cleanUp() }
        let id = try t.store.createDraft(document: Self.pdf, filename: "a.pdf", today: "2026-10-11")
        try t.store.applyExtraction(id, fields: ["gross_amount": .text("10")],
                                    extraction: ExtractionInfo(state: .done, confidence: ["gross_amount": .low],
                                                               warnings: [.init(field: "gross_amount", message: "check")]))
        #expect(try expense(t, id).extraction != nil)
        try t.store.approve(id)
        let e = try expense(t, id)
        #expect(e.reviewStatus == nil && e.extraction == nil)
        let snap = RecordSnapshot(e)
        #expect(!snap.isDraft && snap.extraction == nil)
        // Approving again, or approving a record that never was a draft, changes nothing.
        try t.store.approve(id)
        #expect(e.reviewStatus == nil)
    }

    @Test func approveAllReportsPartialResults() throws {
        let t = try TestStore()
        defer { t.cleanUp() }
        let good = try t.store.createDraft(document: Self.pdf, filename: nil, today: "2026-10-11")
        try t.store.update(good, fields: ["gross_amount": .text("20")])
        let usd = try t.store.createDraft(document: Data("%PDF-1.4 b".utf8), filename: nil, today: "2026-10-11")
        try t.store.update(usd, fields: ["gross_amount": .text("20"), "currency": .text("USD")])
        let blank = try t.store.createDraft(document: Data("%PDF-1.4 c".utf8), filename: nil, today: "2026-10-11")

        let result = try t.store.approveAll([good, usd, blank])
        #expect(result.approved == [good])
        #expect(result.failed.map(\.id) == [usd, blank])
        #expect(result.failed[0].issues.map(\.code) == [.missingConversionRate])
        #expect(result.failed[1].issues.map(\.code) == [.missingGrossAmount])
        #expect(result.failed[1].message == "Enter the gross amount")
        #expect(try t.store.snapshots(.expenses, drafts: .only).map(\.id).sorted { "\($0)" < "\($1)" }
                    == [usd, blank].sorted { "\($0)" < "\($1)" })
        #expect(try t.store.entries().count == 1)
    }

    // MARK: Extraction

    @Test func applyExtractionNeverOverwritesUserEdits() throws {
        let t = try TestStore()
        defer { t.cleanUp() }
        let id = try t.store.createDraft(document: Self.pdf, filename: "inv.pdf", today: "2026-10-11")
        // The user corrects the amount and category before extraction finishes.
        try t.store.update(id, fields: ["gross_amount": .text("119.00"), "category": .text("Software")])
        #expect(ExtractionInfo.decode(try expense(t, id).extraction)?.editedFields == ["gross_amount", "category"])

        try t.store.applyExtraction(id, fields: [
            "description": .text("Adobe Creative Cloud – Oct 2026"), "date": .text("2026-10-02"),
            "gross_amount": .text("999.00"), "category": .text("Tools"), "vat_rates": vat("19", "19.00"),
        ], extraction: ExtractionInfo(state: .done, raw: "{}", confidence: ["date": .high]))

        let e = try expense(t, id)
        let snap = RecordSnapshot(e)
        #expect(snap.grossAmount == 119 && e.category == "Software")  // kept
        #expect(e.descriptionText == "Adobe Creative Cloud – Oct 2026" && e.date == "2026-10-02")  // filled
        #expect(snap.totalVatAmount == 19 && snap.netAmount == 100)  // derived from the user's gross
        let info = try #require(ExtractionInfo.decode(e.extraction))
        #expect(info.state == .done && info.raw == "{}" && info.confidence == ["date": .high])
        #expect(info.editedFields == ["gross_amount", "category"])

        // After approval a late extraction changes nothing.
        try t.store.approve(id)
        try t.store.applyExtraction(id, fields: ["description": .text("late")], extraction: ExtractionInfo(state: .done))
        #expect(e.descriptionText == "Adobe Creative Cloud – Oct 2026" && e.extraction == nil)
    }

    @Test func extractionInfoDecodesMissingKeys() throws {
        let info = try JSONDecoder().decode(ExtractionInfo.self, from: Data(#"{"state":"failed"}"#.utf8))
        #expect(info == ExtractionInfo(state: .failed))
        let full = ExtractionInfo(state: .unavailable, raw: "{}", confidence: ["gross_amount": .medium],
                                  warnings: [.init(message: "foreign currency, needs a rate")],
                                  failureReason: "model not ready", sourceFilename: "x.pdf", editedFields: ["date"])
        #expect(ExtractionInfo.decode(full.encoded()) == full)
        #expect(ExtractionInfo.decode(Data("nope".utf8)) == nil)
    }

    // MARK: Safety

    @Test func sortedImporterLeavesDraftsAlone() throws {
        let t = try TestStore()
        defer { t.cleanUp() }
        _ = try t.import("sample_v1.zip")
        let id = try t.store.createDraft(document: Self.pdf, filename: nil, today: "2026-10-11")
        try t.store.update(id, fields: ["gross_amount": .text("5")])
        let before = try expense(t, id)
        let snapshot = RecordSnapshot(before)

        _ = try t.import("sample_v2.zip")  // upserts and sweeps Sorted records
        _ = try t.import("sample_v1.zip")
        try t.store.dedupe()
        let after = try expense(t, id)
        #expect(after.isDraft && after.removedAt == nil && after.sortedRef == nil)
        #expect(RecordSnapshot(after) == snapshot)
    }

    @Test func duplicateDocumentsAreFoundBySha256() throws {
        let t = try TestStore()
        defer { t.cleanUp() }
        let text = try Data(contentsOf: fixtureURL("invoice_text.pdf"))
        #expect(try t.store.existingRecord(forDocument: text) == nil)

        let textID = try t.store.createDraft(document: text, filename: "invoice_text.pdf")
        #expect(try t.store.existingRecord(forDocument: text)?.id == textID)
        #expect(try t.store.existingRecord(withDocumentSha256: DocumentStore.sha256(text))?.id == textID)
        #expect(try t.store.existingRecord(forDocument: Self.pdf) == nil)

        // The same photo imported twice converts to the same PDF, so the second import is caught.
        let photo = try Data(contentsOf: fixtureURL("invoice_photo.heic"))
        let first = try ImagePDF.convert(photo).pdf
        #expect(try t.store.existingRecord(forDocument: first) == nil)
        let photoID = try t.store.createDraft(document: first, filename: "invoice_photo.heic")
        let second = try ImagePDF.convert(photo).pdf
        #expect(try t.store.existingRecord(forDocument: second)?.id == photoID)

        // Documents of income and approved records count too; removed records don't.
        let income = try t.store.create(.income, fields: ["date": .text("2026-10-01"), "gross_amount": .text("10")])
        try t.store.attachDocument(income, data: Self.pdf)
        #expect(try t.store.existingRecord(forDocument: Self.pdf)?.id == income)
        try t.store.setRemoved(income, true)
        try t.store.setRemoved(photoID, true)
        #expect(try t.store.existingRecord(forDocument: Self.pdf) == nil)
        #expect(try t.store.existingRecord(forDocument: second) == nil)
        #expect(try t.store.existingRecord(forDocument: text)?.id == textID)
    }
}

/// The store schema before drafts: `Expense` without `reviewStatus` / `extraction`.
enum SchemaBeforeDrafts: VersionedSchema {
    static let versionIdentifier = Schema.Version(1, 0, 0)
    static var models: [any PersistentModel.Type] { [Expense.self] }

    @Model final class Expense {
        var uid: String = UUID().uuidString
        var sortedRef: String?
        var descriptionText: String?
        var date: String = ""
        var grossAmount: String?
        var convertedGrossAmount: String?
        var netAmount: String?
        var totalVatAmount: String?
        var vatRates: String = "[]"
        var currency: String = "EUR"
        var currencyConversionRate: String?
        var documentFilename: String?
        var documentPath: String?
        var documentSha256: String?
        var category: String?
        var createdAt: Date = Date()
        var updatedAt: Date = Date()
        var removedAt: Date?

        init() {}
    }
}

@MainActor
@Suite struct StoreMigrationTests {
    @Test func olderStoreLoadsAsApproved() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("BrotBooksStore-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("store.sqlite")

        do {
            let schema = Schema(versionedSchema: SchemaBeforeDrafts.self)
            let config = ModelConfiguration(schema: schema, url: url, cloudKitDatabase: .none)
            let old = try ModelContainer(for: schema, configurations: [config])
            let e = SchemaBeforeDrafts.Expense()
            e.date = "2025-05-05"
            e.grossAmount = "12.00"
            e.convertedGrossAmount = "12.00"
            e.netAmount = "12.00"
            e.totalVatAmount = "0.00"
            old.mainContext.insert(e)
            try old.mainContext.save()
        }

        let config = ModelConfiguration(schema: StoreSchema.schema, url: url, cloudKitDatabase: .none)
        let container = try ModelContainer(for: StoreSchema.schema, configurations: [config])
        let store = RecordStore(context: container.mainContext, documents: DocumentStore(root: dir, isUbiquitous: false))
        let expenses = try container.mainContext.fetch(FetchDescriptor<Expense>())
        #expect(expenses.count == 1)
        #expect(expenses.first?.reviewStatus == nil && expenses.first?.extraction == nil)
        #expect(expenses.first?.isDraft == false)
        #expect(try store.entries().count == 1)
    }
}

@MainActor
@Suite struct InvoiceDraftBuilderTests {
    static let today = "2026-10-11"

    func build(_ invoice: ExtractedInvoice, history: [InvoiceDraftBuilder.PastExpense] = []) -> InvoiceDraftBuilder.Draft {
        InvoiceDraftBuilder.build(invoice, sourceFilename: "inv.pdf", today: Self.today, history: history)
    }

    func vat(_ rows: (String, String)...) -> FieldInput { .vatRates(rows.map { VatRowInput(rate: $0.0, amount: $0.1) }) }

    static let high = ExtractedInvoice.FieldConfidence(amount: .high, date: .high, vat: .high)

    @Test func germanDecimalsAndDatesAreNormalized() {
        let amounts: [(String, Decimal?)] = [
            ("119.00", 119), ("119,00", 119), ("1.234,56", Decimal(string: "1234.56")),
            ("1,234.56", Decimal(string: "1234.56")), ("€ 119.00", 119), ("19.00 EUR", 19), ("1.234", 1234),
            ("1 234,5", Decimal(string: "1234.5")), ("0,125", Decimal(string: "0.125")), ("12.5", Decimal(string: "12.5")),
            ("1.234.567,89", Decimal(string: "1234567.89")), ("-5,00", -5), ("119", 119), ("", nil), ("EUR", nil),
        ]
        for (text, expected) in amounts {
            #expect(InvoiceDraftBuilder.normalizeAmount(text) == expected, "\(text)")
        }
        let dates: [(String, String?)] = [
            ("2026-10-01", "2026-10-01"), ("01.10.2026", "2026-10-01"), ("1.10.26", "2026-10-01"),
            ("1. 10. 2026", "2026-10-01"), ("01/10/2026", "2026-10-01"), ("2026/10/1", "2026-10-01"),
            ("1. Oktober 2026", "2026-10-01"), ("3. März 2026", "2026-03-03"), ("1 Oct 2026", "2026-10-01"),
            ("October 1, 2026", "2026-10-01"), ("31.02.2026", nil), ("Oktober", nil), ("", nil),
        ]
        for (text, expected) in dates {
            #expect(InvoiceDraftBuilder.normalizeDate(text) == expected, "\(text)")
        }

        let draft = build(ExtractedInvoice(supplier: "Hetzner Online GmbH", invoiceDate: "01.10.2026",
                                           grossAmount: "1.234,56", currency: "eur", confidence: Self.high))
        #expect(draft.fields == ["description": .text("Hetzner Online GmbH"), "date": .text("2026-10-01"),
                                 "gross_amount": .text("1234.56"), "currency": .text("EUR")])
        #expect(draft.info.warnings.isEmpty && draft.isComplete)
    }

    @Test func implausibleDatesAreKeptWithAWarning() {
        let warning = ExtractionInfo.Warning(.implausibleDate)
        #expect(warning.field == "date" && warning.code == .implausibleDate)
        for date in ["2026-10-12", "2014-12-31"] {
            let draft = build(ExtractedInvoice(invoiceDate: date, grossAmount: "10.00", confidence: Self.high))
            #expect(draft.fields["date"] == .text(date))
            #expect(draft.info.warnings == [warning])
            #expect(draft.info.confidence["date"] == .low && draft.info.confidence["gross_amount"] == .high)
            #expect(!draft.isComplete)
        }
        for date in [Self.today, InvoiceDraftBuilder.earliestDate] {
            let draft = build(ExtractedInvoice(invoiceDate: date, grossAmount: "10.00", confidence: Self.high))
            #expect(draft.info.warnings.isEmpty && draft.isComplete)
        }
        // An unreadable date isn't written (the draft keeps its placeholder) and is flagged.
        let unreadable = build(ExtractedInvoice(invoiceDate: "31.02.2026", grossAmount: "10.00", confidence: Self.high))
        #expect(unreadable.fields["date"] == nil && unreadable.info.warnings == [warning])
    }

    @Test func vatRowsAreKeptOnlyWhenTheyAddUpToTheGross() {
        // 119.00 gross at 19 % is 19.00 VAT; 0.02 off is still fine.
        for amount in ["19.00", "19,00", "19.02", "18.98"] {
            let draft = build(ExtractedInvoice(grossAmount: "119.00", vatLines: [.init(rate: 19, amount: amount)],
                                               confidence: Self.high))
            #expect(draft.fields["vat_rates"] == vat(("19", EditForm.amountText(InvoiceDraftBuilder.normalizeAmount(amount)!))))
            #expect(draft.info.warnings.isEmpty && draft.info.confidence["vat_rates"] == .high)
        }
        // Several rates: 107.00 at 7 % (7.00) plus 119.00 at 19 % (19.00).
        let mixed = build(ExtractedInvoice(grossAmount: "226.00", vatLines: [.init(rate: 7, amount: "7.00"),
                                                                             .init(rate: 19, amount: "19.00")]))
        #expect(mixed.fields["vat_rates"] == vat(("7", "7.00"), ("19", "19.00")) && mixed.info.warnings.isEmpty)

        // Off by more than 0.02, more VAT than the gross allows, an impossible rate (the extractor's "other"),
        // or an unreadable amount: the gross is kept, the VAT rows dropped, and the user warned.
        let bad: [[ExtractedInvoice.VatLine]] = [
            [.init(rate: 19, amount: "19.03")], [.init(rate: 7, amount: "19.00")],
            [.init(rate: 7, amount: "70.00"), .init(rate: 19, amount: "190.00")],
            [.init(rate: -1, amount: "19.00")], [.init(rate: 19, amount: "n/a")], [.init(rate: 0, amount: "5.00")],
        ]
        for lines in bad {
            let draft = build(ExtractedInvoice(invoiceDate: "2026-10-01", grossAmount: "119.00", vatLines: lines,
                                               confidence: Self.high))
            #expect(draft.fields["gross_amount"] == .text("119.00"))
            #expect(draft.fields["vat_rates"] == .vatRates([]), "\(lines)")
            #expect(draft.info.warnings == [ExtractionInfo.Warning(.vatMismatch)])
            #expect(draft.info.warnings.first?.field == "vat_rates"
                    && draft.info.warnings.first?.message == "VAT didn't add up to the total")
            #expect(draft.info.confidence["vat_rates"] == .low && !draft.isComplete)
        }
    }

    @Test func reverseChargeHasNoVatRowsAndAForeignRegion() {
        let eu = build(ExtractedInvoice(supplier: "Figma Ireland Ltd", invoiceDate: "2026-10-01", grossAmount: "45.00",
                                        currency: "EUR", vatLines: [.init(rate: 19, amount: "7.18")], reverseCharge: true,
                                        supplierRegion: "Germany", confidence: Self.high))
        #expect(eu.fields["vat_rates"] == .vatRates([]))
        #expect(eu.fields["supplier_region"] == .text("European Union"))
        #expect(eu.info.warnings.isEmpty && eu.isComplete)

        let outside = build(ExtractedInvoice(grossAmount: "20.00", currency: "USD", reverseCharge: true))
        #expect(outside.fields["vat_rates"] == .vatRates([]))
        #expect(outside.fields["supplier_region"] == .text("Outside of the European Union"))

        // A foreign region the model gave is kept.
        let kept = build(ExtractedInvoice(grossAmount: "20.00", currency: "EUR", reverseCharge: true,
                                          supplierRegion: "Outside of the European Union"))
        #expect(kept.fields["supplier_region"] == .text("Outside of the European Union"))
    }

    @Test func foreignCurrencyLeavesTheRateEmptyAndWarns() {
        let draft = build(ExtractedInvoice(supplier: "GitHub", invoiceDate: "2026-10-01", grossAmount: "$ 4.00",
                                           currency: "usd", confidence: Self.high))
        #expect(draft.fields["currency"] == .text("USD") && draft.fields["gross_amount"] == .text("4.00"))
        #expect(draft.fields["currency_conversion_rate"] == nil)
        #expect(draft.info.warnings == [ExtractionInfo.Warning(field: "currency_conversion_rate",
                                                               message: "Foreign currency – enter the rate",
                                                               code: .foreignCurrency)])
        #expect(draft.info.confidence["currency_conversion_rate"] == .low && !draft.isComplete)

        let euro = build(ExtractedInvoice(invoiceDate: "2026-10-01", grossAmount: "4.00", currency: "€", confidence: Self.high))
        #expect(euro.fields["currency"] == .text("EUR") && euro.info.warnings.isEmpty)
    }

    @Test func mapsToEditorFieldsThatADraftAccepts() throws {
        let invoice = ExtractedInvoice(
            supplier: "Nordlicht Software GmbH", summary: "Nordlicht Cloud Hosting – Oct 2026", invoiceDate: "2026-10-01",
            grossAmount: "119.00", currency: "EUR", vatLines: [.init(rate: 19, amount: "19.00")],
            supplierRegion: "Germany", category: "Software", invoiceNumber: "NS-2026-0042",
            confidence: .init(amount: .high, date: .medium, vat: .high))
        let draft = build(invoice)
        #expect(draft.fields == [
            "description": .text("Nordlicht Cloud Hosting – Oct 2026"), "date": .text("2026-10-01"),
            "gross_amount": .text("119.00"), "currency": .text("EUR"), "vat_rates": vat(("19", "19.00")),
            "category": .text("Software"), "supplier_region": .text("Germany"),
        ])
        #expect(draft.info.state == .done && draft.info.sourceFilename == "inv.pdf" && draft.info.warnings.isEmpty)
        #expect(draft.info.confidence == ["date": .medium, "gross_amount": .high, "vat_rates": .high])
        let raw = try #require(draft.info.raw)
        #expect(try JSONDecoder().decode(ExtractedInvoice.self, from: Data(raw.utf8)) == invoice)
        #expect(draft.isComplete)

        // A blank result writes nothing and needs filling in.
        let blank = build(ExtractedInvoice())
        #expect(blank.fields.isEmpty && blank.info.warnings.isEmpty && !blank.isComplete)

        // The fields go through `applyExtraction` and the draft then approves with derived amounts.
        let t = try TestStore()
        defer { t.cleanUp() }
        let id = try t.store.createDraft(document: InvoiceImportTests.pdf, filename: "inv.pdf", today: Self.today)
        try t.store.applyExtraction(id, fields: draft.fields, extraction: draft.info)
        let snap = try #require(try t.store.snapshots(.expenses, drafts: .only).first)
        #expect(snap.netAmount == 100 && snap.totalVatAmount == 19 && snap.category == "Software")
        #expect(snap.extraction == draft.info)
        try t.store.approve(id)

        // A foreign-currency draft is saved without a rate.
        let usd = build(ExtractedInvoice(invoiceDate: "2026-10-01", grossAmount: "4.00", currency: "USD"))
        let usdID = try t.store.createDraft(document: Data("%PDF-1.4 usd".utf8), filename: nil, today: Self.today)
        try t.store.applyExtraction(usdID, fields: usd.fields, extraction: usd.info)
        #expect(try #require(t.store.record(usdID)).values["converted_gross_amount"] == .null)
    }

    @Test func learnedCategoryAndRegionFromAPreviousSupplier() {
        let history: [InvoiceDraftBuilder.PastExpense] = [
            .init(description: "Adobestock images", category: "Stock", supplierRegion: "Germany"),
            .init(description: "ADOBE Creative Cloud – Sep 2026", category: "Software", supplierRegion: "European Union"),
            .init(description: "Adobe Creative Cloud – Aug 2026", category: "Tools", supplierRegion: "Germany"),
        ]
        let invoice = ExtractedInvoice(supplier: "Adobe Systems Software Ireland Ltd", summary: "Adobe Creative Cloud – Oct 2026",
                                       category: "Tools", invoiceNumber: nil)
        // The supplier name must start the description: "Adobe Systems…" doesn't match "Adobe Creative Cloud".
        #expect(InvoiceDraftBuilder.learnedDefaults(supplier: invoice.supplier, history: history) == nil)

        var adobe = invoice
        adobe.supplier = "Adobe Inc."
        adobe.supplierRegion = "Outside of the European Union"
        let past = InvoiceDraftBuilder.learnedDefaults(supplier: adobe.supplier, history: history)
        #expect(past == history[1])  // the newest same-supplier expense, ignoring case and "Inc."; not "Adobestock"
        let draft = build(adobe, history: history)
        #expect(draft.fields["category"] == .text("Software"))
        #expect(draft.fields["supplier_region"] == .text("European Union"))

        // Without a match, or when the earlier expense has no category, the model's guess stays.
        #expect(build(adobe).fields["category"] == .text("Tools"))
        let partial = build(adobe, history: [.init(description: "Adobe CC", category: nil, supplierRegion: nil)])
        #expect(partial.fields["category"] == .text("Tools"))
        #expect(partial.fields["supplier_region"] == .text("Outside of the European Union"))
        #expect(InvoiceDraftBuilder.learnedDefaults(supplier: "GmbH", history: [.init(description: "GmbH fees")]) == nil)
    }

    @Test func pastExpensesSkipDraftsAndRemovedRecords() throws {
        let t = try TestStore()
        defer { t.cleanUp() }
        try t.store.create(.expenses, fields: ["date": .text("2026-08-01"), "gross_amount": .text("10"),
                                               "description": .text("Adobe CC – Aug"), "category": .text("Software"),
                                               "supplier_region": .text("European Union")])
        try t.store.create(.expenses, fields: ["date": .text("2026-09-01"), "gross_amount": .text("10"),
                                               "description": .text("Adobe CC – Sep")])
        let removed = try t.store.create(.expenses, fields: ["date": .text("2026-09-15"), "gross_amount": .text("10"),
                                                             "description": .text("Removed")])
        try t.store.setRemoved(removed, true)
        try t.store.create(.expenses, fields: ["date": .text("2026-09-20"), "gross_amount": .text("10")])
        let draft = try t.store.createDraft(document: InvoiceImportTests.pdf, filename: nil, today: Self.today)
        try t.store.update(draft, fields: ["description": .text("Adobe CC – Oct"), "category": .text("Guess")])
        try t.store.create(.income, fields: ["date": .text("2026-09-10"), "gross_amount": .text("10"),
                                             "description": .text("Client")])

        #expect(try t.store.pastExpenses() == [
            .init(description: "Adobe CC – Sep"),
            .init(description: "Adobe CC – Aug", category: "Software", supplierRegion: "European Union"),
        ])
    }

    @Test func warningsDecodeWithoutOrWithUnknownCodes() throws {
        let old = try JSONDecoder().decode(ExtractionInfo.Warning.self, from: Data(#"{"field":"date","message":"x"}"#.utf8))
        #expect(old == ExtractionInfo.Warning(field: "date", message: "x"))
        let newer = try JSONDecoder().decode(ExtractionInfo.Warning.self,
                                             from: Data(#"{"message":"y","code":"somethingNew"}"#.utf8))
        #expect(newer == ExtractionInfo.Warning(message: "y") && newer.code == nil)
        let info = ExtractionInfo(state: .done, warnings: [.init(.vatMismatch), .init(.foreignCurrency), .init(.implausibleDate)])
        #expect(ExtractionInfo.decode(info.encoded()) == info)
    }

    @Test func looksCompleteNeedsNoWarningsAndHighConfidenceEverywhere() {
        let clean = build(ExtractedInvoice(supplier: "Nordlicht", invoiceDate: "2026-10-01", grossAmount: "119.00",
                                           currency: "EUR", vatLines: [.init(rate: 19, amount: "19.00")],
                                           confidence: Self.high))
        #expect(clean.info.looksComplete && clean.isComplete)
        // Medium confidence is complete enough to import as "Ready", but doesn't look complete.
        let medium = build(ExtractedInvoice(invoiceDate: "2026-10-01", grossAmount: "119.00",
                                            confidence: .init(amount: .high, date: .medium, vat: .high)))
        #expect(medium.isComplete && !medium.info.looksComplete)
        let foreign = build(ExtractedInvoice(invoiceDate: "2026-10-01", grossAmount: "4.00", currency: "USD",
                                             confidence: Self.high))
        #expect(!foreign.info.looksComplete)
        // Nothing read, or not read yet.
        #expect(!build(ExtractedInvoice()).info.looksComplete)
        #expect(!build(ExtractedInvoice(grossAmount: "10.00", confidence: Self.high)).info.looksComplete)
        var pending = clean.info
        pending.state = .pending
        #expect(!pending.looksComplete)
    }

    @Test func flagsAreWarningsOrLowConfidence() {
        let draft = build(ExtractedInvoice(invoiceDate: "2026-10-01", grossAmount: "119.00", currency: "USD",
                                           vatLines: [.init(rate: 19, amount: "5.00")],
                                           confidence: .init(amount: .low, date: .medium, vat: .high)))
        let info = draft.info
        #expect(info.flag(for: "vat_rates") == .warning(.init(.vatMismatch)))
        #expect(info.flag(for: "currency_conversion_rate") == .warning(.init(.foreignCurrency)))
        #expect(info.flag(for: "gross_amount") == .lowConfidence)
        #expect(info.flag(for: "date") == nil && info.flag(for: "description") == nil)
    }
}
