import Foundation
import Testing
@testable import BrotBooksKit

/// Runs the real on-device model on the invoice fixtures. Needs a Mac with Apple Intelligence; skipped unless
/// `SORTED_FM_LIVE` is set: `SORTED_FM_LIVE=1 swift test --filter FoundationModelsLive`.
@Suite(.serialized, .enabled(if: ProcessInfo.processInfo.environment["SORTED_FM_LIVE"] != nil,
                             "set SORTED_FM_LIVE=1 to run the on-device model"))
struct FoundationModelsLiveTests {
    static let categories = ["Software", "Tools", "Communication", "Business meals", "Rent"]

    func run(_ name: String) async throws -> (ExtractedInvoice, FoundationModelsInvoiceExtractor.Report) {
        let data = try Data(contentsOf: fixtureURL(name))
        let input = InvoiceDocumentInput.load(data, filename: name)
        let result = try await FoundationModelsInvoiceExtractor().extractWithReport(input, categories: Self.categories)
        let r = result.report
        print("""
            FoundationModelsLive \(name): path=\(r.path.rawValue) gross=\(result.invoice.grossAmount) \
            date=\(result.invoice.invoiceDate) supplier=\(result.invoice.supplier) \
            input=\(r.inputTokens) output=\(r.outputTokens) seconds=\(String(format: "%.1f", r.seconds)) \
            attempts=\(r.attempts)
            \(r.rawJSON)
            """)
        return result
    }

    @Test func textPDF() async throws {
        let (invoice, report) = try await run("invoice_text.pdf")
        #expect(report.path == .text)
        #expect(invoice.grossAmount == "119.00")
        #expect(invoice.invoiceDate == "2026-10-01")
    }

    @Test func photo() async throws {
        let (invoice, report) = try await run("invoice_photo.heic")
        #expect(report.path == .image)
        #expect(invoice.grossAmount == "59.50")
        #expect(invoice.invoiceDate == "2026-09-15")
    }
}

/// A fixture as the import flow hands it to the extractor: PDFs as-is, photos converted with `ImagePDF`.
enum InvoiceDocumentInput {
    static func load(_ data: Data, filename: String) -> ExtractionInput {
        if data.starts(with: Array("%PDF-".utf8)) { return InvoiceInput.prepare(document: data, filename: filename) }
        let output = try! ImagePDF.convert(data)
        return InvoiceInput.prepare(document: output.pdf, filename: filename, image: output.image)
    }
}
