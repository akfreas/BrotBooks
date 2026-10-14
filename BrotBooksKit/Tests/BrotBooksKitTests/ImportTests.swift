import Foundation
import SwiftData
import Testing
@testable import BrotBooksKit

func fixtureURL(_ name: String) -> URL {
    Bundle.module.url(forResource: "Fixtures/\(name)", withExtension: nil)!
}

/// An in-memory SwiftData store (no CloudKit) with documents in a fresh temp folder.
@MainActor
final class TestStore {
    let container: ModelContainer
    let store: RecordStore
    let docsRoot: URL

    init() throws {
        let config = ModelConfiguration(schema: StoreSchema.schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        container = try ModelContainer(for: StoreSchema.schema, configurations: [config])
        docsRoot = FileManager.default.temporaryDirectory.appendingPathComponent("BrotBooksTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: docsRoot, withIntermediateDirectories: true)
        store = RecordStore(context: container.mainContext, documents: DocumentStore(root: docsRoot, isUbiquitous: false))
    }

    func cleanUp() { try? FileManager.default.removeItem(at: docsRoot) }

    func `import`(_ name: String, dryRun: Bool = false) throws -> IngestSummary {
        try Importer.run(SortedExport(url: fixtureURL(name)), store: store, dryRun: dryRun, importedFrom: name)
    }

    func expenses(includeRemoved: Bool = true) throws -> [String: Expense] {
        Dictionary(uniqueKeysWithValues: try container.mainContext.fetch(FetchDescriptor<Expense>())
            .filter { includeRemoved || $0.removedAt == nil }.map { ($0.sortedRef!, $0) })
    }
}

@Suite struct ZipAndCSVTests {
    @Test func readsDeflatedAndStoredEntries() throws {
        let zip = try ZipArchive(url: fixtureURL("sample_v1.zip"))
        #expect(zip.names.contains("expenses/expenses.csv"))
        let stored = try #require(zip.entries.first { $0.name.hasPrefix("tax-reports/") })
        #expect(stored.method == 0)
        #expect(try zip.read(stored) == Data("%PDF-1.4 vat".utf8))
        let csv = try #require(try zip.read("income/income.csv"))
        #expect(String(decoding: csv, as: UTF8.self).hasPrefix("\u{FEFF}\"Description\""))
        #expect(try zip.read("missing.txt") == nil)
    }

    @Test func rejectsNonZip() {
        #expect(throws: ZipError.self) { try ZipArchive(data: Data("not a zip at all, definitely".utf8)) }
        #expect(throws: ExportFormatError.self) { try SortedExport(data: Data(repeating: 0, count: 100)) }
    }

    @Test func parsesQuotedCSV() {
        let rows = CSV.parse("a,b\r\n\"x, \"\"y\"\"\",\"line\nbreak\"\r\n\r\nlast,\n")
        #expect(rows == [["a", "b"], ["x, \"y\"", "line\nbreak"], [""], ["last", ""]])
        let (header, dicts) = CSV.dictionaries("a,b\n1,2\n\n3,4\n")
        #expect(header == ["a", "b"] && dicts == [["a": "1", "b": "2"], ["a": "3", "b": "4"]])
    }

    @Test func parsesExportRecords() throws {
        let export = try SortedExport(url: fixtureURL("sample_v1.zip"))
        let expenses = try export.records(.expenses)
        #expect(expenses.map(\.sortedRef) == ["aaaa1", "aaaa2", "aaaa3"])
        let lunch = expenses[2]
        #expect(lunch.values["description"] == .text("Lunch, \"team\"\nwith newline"))
        #expect(lunch.values["vat_rates"] == .vatRates([VatRate(rate: 7, amount: 0), VatRate(rate: 19, amount: dec("3.8"))]))
        #expect(lunch.values["asset_lifetime_years"] == .null)
        #expect(lunch.sourceRow["Gross amount"] == "23.80")
        let income = try export.records(.income)
        #expect(income[0].values["client_is_private_person"] == .bool(false))
        #expect(income[0].values["payment_date"] == .date("2021-12-01"))
        #expect(export.archiveFiles() == ["tax-reports/vat/2021/Dezember 2021 VAT.pdf"])
    }
}

@Suite(.serialized) @MainActor struct ImportTests {
    @Test func firstImportThenUnchanged() throws {
        let t = try TestStore()
        defer { t.cleanUp() }
        let preview = try t.import("sample_v1.zip", dryRun: true)
        #expect(preview.dryRun && preview.kind(.expenses)?.inserted == 3)
        #expect(try t.expenses().isEmpty)
        #expect(!FileManager.default.fileExists(atPath: t.docsRoot.appendingPathComponent("expenses").path))

        let first = try t.import("sample_v1.zip")
        let e = try #require(first.kind(.expenses))
        #expect((e.rows, e.inserted, e.updated, e.unchanged, e.removed, e.filesWritten) == (3, 3, 0, 0, 0, 2))
        #expect(e.missingDocuments == ["2021/2021-11-04 Lunch, \"team\" aaaa3.pdf"])
        #expect(first.kind(.income)?.inserted == 1)
        #expect(first.archiveFilesWritten == 1)

        let rows = try t.expenses()
        let one = try #require(rows["aaaa1"])
        #expect(one.documentPath == "expenses/2021/2021-11-04 Thing aaaa1.pdf")
        #expect(one.documentSha256 == DocumentStore.sha256(Data("%PDF-1.4 2021/2021-11-04 Thing aaaa1.pdf".utf8)))
        #expect(one.grossAmount == "10" && one.netAmount == "60")
        #expect(one.decodedSourceRow?["Gross amount"] == "10.00")
        #expect(rows["aaaa3"]?.documentPath == nil)
        let stored = try Data(contentsOf: t.docsRoot.appendingPathComponent("expenses/2021/2021-11-04 Thing aaaa1.pdf"))
        #expect(stored == Data("%PDF-1.4 2021/2021-11-04 Thing aaaa1.pdf".utf8))
        #expect(FileManager.default.fileExists(atPath: t.docsRoot.appendingPathComponent("tax-reports/vat/2021/Dezember 2021 VAT.pdf").path))

        let again = try t.import("sample_v1.zip")
        #expect(again.kinds.allSatisfy { $0.inserted == 0 && $0.updated == 0 && $0.removed == 0 && $0.filesWritten == 0 })
        #expect(again.kind(.expenses)?.unchanged == 3 && again.archiveFilesWritten == 0)
    }

    @Test func updatesSweepsAndKeepsDocuments() throws {
        let t = try TestStore()
        defer { t.cleanUp() }
        _ = try t.import("sample_v1.zip")
        let lunchID = try #require(try t.expenses()["aaaa3"]).persistentModelID
        // A local edit survives re-imports until Sorted changes the row.
        try t.store.update(lunchID, fields: ["category": .text("Business meals")])

        let preview = try t.import("sample_v2.zip", dryRun: true)
        #expect(preview.kind(.expenses).map { ($0.inserted, $0.updated, $0.unchanged, $0.removed) } ?? (0, 0, 0, 0) == (1, 1, 1, 1))
        #expect(try t.expenses()["aaaa2"]?.removedAt == nil)

        let summary = try t.import("sample_v2.zip")
        let e = try #require(summary.kind(.expenses))
        #expect((e.inserted, e.updated, e.unchanged, e.removed) == (1, 1, 1, 1))
        let rows = try t.expenses()
        #expect(rows["aaaa1"]?.grossAmount == "12")
        #expect(rows["aaaa1"]?.documentPath == "expenses/2021/2021-11-04 Thing aaaa1.pdf")  // kept: export lacks it
        #expect(rows["aaaa2"]?.removedAt != nil)
        #expect(rows["aaaa3"]?.category == "Business meals")
        #expect(rows["aaaa4"] != nil)

        // An empty income CSV doesn't sweep income.
        let empty = try t.import("sample_empty_income.zip")
        #expect(empty.kind(.income)?.removed == 0)
        #expect(try t.container.mainContext.fetch(FetchDescriptor<Income>()).allSatisfy { $0.removedAt == nil })

        // A removed record that reappears is restored.
        let back = try t.import("sample_v1.zip")
        #expect(back.kind(.expenses)?.updated == 2)  // aaaa1 changed back, aaaa2 restored
        #expect(try t.expenses()["aaaa2"]?.removedAt == nil)
    }

    @Test func dedupeKeepsNewestCopy() throws {
        let t = try TestStore()
        defer { t.cleanUp() }
        _ = try t.import("sample_v1.zip")
        let copy = Expense()
        copy.sortedRef = "aaaa1"
        copy.date = "2021-11-04"
        copy.descriptionText = "Older copy from another device"
        copy.updatedAt = .distantPast
        t.container.mainContext.insert(copy)
        try t.container.mainContext.save()
        #expect(try t.store.dedupe() == 1)
        #expect(try t.expenses()["aaaa1"]?.descriptionText == "Thing")
    }

    @Test func createEditMarkPaidRemoveRestore() throws {
        let t = try TestStore()
        defer { t.cleanUp() }
        let pdf = Data("%PDF-1.4 invoice".utf8)
        let id = try t.store.create(.income, fields: [
            "description": .text("E2E Test invoice"), "date": .text("2026-10-01"), "gross_amount": .text("1190"),
            "vat_rates": .vatRates([VatRowInput(rate: "19", amount: "190")]),
        ], document: pdf)
        var snap = try #require(try t.store.snapshots(.income).first)
        #expect(snap.id == id && snap.netAmount == 1000 && snap.paymentStatus == "Unpaid")
        let path = try #require(snap.documentPath)
        #expect(path.hasPrefix("income/2026/2026-10-01 E2E Test invoice L"))
        #expect(try Data(contentsOf: t.store.documents.resolve(path)) == pdf)

        try t.store.update(id, fields: ["gross_amount": .text("2380"), "vat_rates": .vatRates([VatRowInput(rate: "19", amount: "380")])])
        snap = try #require(try t.store.snapshots(.income).first)
        #expect(snap.convertedGrossAmount == 2380 && snap.totalVatAmount == 380 && snap.netAmount == 2000)

        #expect(throws: ValidationError("non-EUR records need currency_conversion_rate or converted_gross_amount")) {
            try t.store.update(id, fields: ["currency": .text("USD")])
        }
        try t.store.markPaid(id, date: "2026-10-10")
        snap = try #require(try t.store.snapshots(.income).first)
        #expect(snap.isPaid && snap.paymentDate == "2026-10-10")

        try t.store.setRemoved(id, true)
        #expect(try t.store.snapshots(.income).isEmpty)
        #expect(try t.store.entries().isEmpty)
        try t.store.setRemoved(id, false)
        #expect(try t.store.snapshots(.income, search: "e2e").count == 1)
        #expect(throws: ValidationError("document must be a PDF")) { try t.store.attachDocument(id, data: Data("nope".utf8)) }
    }

    @Test func sampleDataIsConsistent() throws {
        let t = try TestStore()
        defer { t.cleanUp() }
        try SampleData.load(into: t.store, today: "2026-10-10")
        let entries = try t.store.entries()
        #expect(entries.count > 100)
        #expect(Reports.years(entries) == [2026, 2025])
        let t2025 = try Reports.taxes(entries, year: 2025)
        #expect(t2025.incomeTax.taxableProfit > 0 && t2025.vat.payments > 0)
        let invoice = try #require(try t.store.snapshots(.income).first)
        let path = try #require(invoice.documentPath)
        #expect(try Data(contentsOf: t.store.documents.resolve(path)).starts(with: Array("%PDF-".utf8)))
        #expect(try t.store.snapshots(.income).contains { !$0.isPaid })
        // No invoice is paid after "today".
        #expect(try t.store.snapshots(.income).compactMap(\.paymentDate).allSatisfy { $0 <= "2026-10-10" })
    }
}
