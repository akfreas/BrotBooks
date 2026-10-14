import CoreGraphics
import Foundation
import FoundationModels
import Testing
@testable import BrotBooksKit

/// The Foundation Models extractor's pure parts: input preparation, trimming, schema, mapping and error handling.
/// The model itself runs only in `FoundationModelsLiveTests`.
@Suite struct InvoiceExtractorTests {
    func fixture(_ name: String) throws -> Data { try Data(contentsOf: fixtureURL(name)) }

    static let germanInvoice = """
        Nordlicht Software GmbH Musterstraße 1 20095 Hamburg USt-IdNr. DE000000000 Rechnung Rechnungsnummer: \
        NS-2026-0042 Rechnungsdatum: 01.10.2026 Leistung Betrag Cloud Hosting Oktober 2026 100,00 EUR Netto \
        100,00 EUR MwSt 19% 19,00 EUR Gesamtbetrag (Brutto) 119,00 EUR Zahlbar innerhalb von 14 Tagen ohne Abzug.
        """

    /// A PDF of `pages` pages with only shapes on them (no text layer), like a multi-page scan.
    func imageOnlyPDF(pages: Int) -> Data {
        let data = NSMutableData()
        var box = CGRect(x: 0, y: 0, width: 595, height: 842)
        let consumer = CGDataConsumer(data: data as CFMutableData)!
        let context = CGContext(consumer: consumer, mediaBox: &box, nil)!
        for page in 0..<pages {
            context.beginPDFPage(nil)
            context.setFillColor(CGColor(gray: Double(page) / Double(pages), alpha: 1))
            context.fill(CGRect(x: 50, y: 50, width: 200, height: 200))
            context.endPDFPage()
        }
        context.closePDF()
        return data as Data
    }

    // MARK: Input preparation

    @Test func textPdfTakesTheTextPath() throws {
        let input = InvoiceInput.prepare(document: try fixture("invoice_text.pdf"), filename: "a.pdf")
        #expect(input.pageTexts.count == 1 && input.pageTexts[0].contains("Gesamtbetrag (Brutto) 119,00 EUR"))
        #expect(input.image == nil && input.lastPageImage == nil && input.filename == "a.pdf")
    }

    @Test func scannedPdfTakesTheImagePathAt150Dpi() throws {
        let input = InvoiceInput.prepare(document: try fixture("invoice_scanned.pdf"), filename: nil)
        #expect(input.pageTexts.isEmpty)
        let image = try #require(input.image)
        #expect(image.width == 1240) // 595 pt at 150 dpi
        #expect(input.lastPageImage == nil)
    }

    @Test func multiPageScanRendersFirstAndLastPage() {
        let input = InvoiceInput.prepare(document: imageOnlyPDF(pages: 3), filename: nil)
        #expect(input.pageTexts.isEmpty && input.image != nil && input.lastPageImage != nil)
    }

    @Test func photoAlwaysTakesTheImagePath() throws {
        let photo = try ImagePDF.convert(try fixture("invoice_photo.heic"))
        let input = InvoiceInput.prepare(document: photo.pdf, filename: "p.heic", image: photo.image)
        #expect(input.pageTexts.isEmpty && input.image === photo.image)
        // Resumed after a relaunch without the photo in memory: no text layer, so page 1 is rendered.
        let resumed = InvoiceInput.prepared(ExtractionInput(document: photo.pdf))
        #expect(resumed.pageTexts.isEmpty && resumed.image != nil)
    }

    @Test func preparedKeepsInputThatIsAlreadyPrepared() {
        let input = ExtractionInput(document: Data(), pageTexts: ["text"])
        #expect(InvoiceInput.prepared(input).pageTexts == ["text"])
    }

    @Test func meaningfulTextNeedsEnoughCharactersAndRealWords() {
        #expect(InvoiceInput.isMeaningful([Self.germanInvoice]))
        #expect(!InvoiceInput.isMeaningful(["Rechnung 119,00 EUR"]))
        let noise = String(repeating: "l|1;~ ^^%& Ij|l ,.,'` rnrn ﬁ~~ |||| #@! ", count: 12)
        #expect(!InvoiceInput.readsAsWords(noise))
        let consonants = String(repeating: "xkcd bfrt gnzrt qwrtz plmnk ", count: 20)
        #expect(!InvoiceInput.readsAsWords(consonants))
        #expect(InvoiceInput.readsAsWords(Self.germanInvoice))
    }

    // MARK: Trimming

    /// About four characters per token, like the model.
    static let counter: InvoiceInput.TokenCounter = { $0.count / 4 }

    func pages(_ n: Int, length: Int = 1000) -> [String] {
        (1...n).map { "P\($0)START " + String(repeating: "x", count: length) + " P\($0)END" }
    }

    @Test func trimmingKeepsEverythingThatFits() async throws {
        let text = try #require(try await InvoiceInput.trimmedText(pages(4), budget: 6000, count: Self.counter))
        for n in 1...4 { #expect(text.contains("P\(n)START") && text.contains("P\(n)END")) }
        #expect(!text.contains("left out"))
    }

    @Test func trimmingKeepsTheFirstTwoAndTheLastPage() async throws {
        // 6 pages of ~250 tokens; 3 of them fit in 900.
        let text = try #require(try await InvoiceInput.trimmedText(pages(6), budget: 900, count: Self.counter))
        #expect(text.contains("P1START") && text.contains("P2END") && text.contains("P6START") && text.contains("P6END"))
        for n in 3...5 { #expect(!text.contains("P\(n)START")) }
        #expect(text.contains("[pages 3–5 left out]") && text.contains("--- Page 6 of 6 ---"))
        #expect(try await Self.counter(text) <= 900)
    }

    @Test func trimmingCutsPagesKeepingTheStartOfFirstPagesAndTheEndOfTheLast() async throws {
        let text = try #require(try await InvoiceInput.trimmedText(pages(6, length: 4000), budget: 1000,
                                                                   count: Self.counter))
        #expect(try await Self.counter(text) <= 1000)
        #expect(text.contains("P1START") && !text.contains("P1END"))
        #expect(text.contains("P6END") && !text.contains("P6START"))
    }

    @Test func trimmingGivesUpWhenNothingFits() async throws {
        #expect(try await InvoiceInput.trimmedText(pages(3), budget: 0, count: Self.counter) == nil)
        #expect(try await InvoiceInput.trimmedText([], budget: 100, count: Self.counter) == nil)
    }

    @Test func downscaleCapsTheLongEdge() throws {
        let photo = try ImagePDF.convert(try fixture("invoice_photo.png")).image
        let small = InvoiceInput.downscaled(photo, longEdge: 1200)
        #expect(max(small.width, small.height) == 1200)
        #expect(abs(Double(small.width) / Double(small.height) - Double(photo.width) / Double(photo.height)) < 0.01)
        #expect(InvoiceInput.downscaled(photo, longEdge: 5000) === photo)
    }

    // MARK: Schema

    func schemaJSON(categories: [String], currencies: [String] = []) throws -> String {
        let schema = try InvoiceSchema.make(categories: categories, currencies: currencies)
        return String(decoding: try JSONEncoder().encode(schema), as: UTF8.self)
    }

    @Test func categoryChoicesAreTheUsersCategoriesPlusOtherExpenses() throws {
        let choices = InvoiceSchema.categoryChoices(["Software", "ExpenseCategory - vat payment to tax office",
                                                     "Other expenses", "Tools", "Software", " "])
        #expect(choices == ["Software", "Tools", "Other expenses"])
        #expect(InvoiceSchema.categoryChoices([]) == ["Other expenses"])
        let many = (1...30).map { "C\($0)" }
        #expect(InvoiceSchema.categoryChoices(many).count == InvoiceSchema.maxCategories + 1)
        #expect(InvoiceSchema.currencyChoices(["usd", "SEK", "EURO"]) == ["EUR", "USD", "GBP", "CHF", "SEK"])
    }

    @Test func schemaLimitsCategoryRegionCurrencyAndVatRate() throws {
        let json = try schemaJSON(categories: ["Software", "Business meals"], currencies: ["SEK"])
        for value in ["Software", "Business meals", "Other expenses", "SEK", "USD", "other", "high", "low"]
            + EditForm.regions {
            #expect(json.contains("\"\(value)\""), "\(value)")
        }
        for name in ["supplier", "summary", "invoiceDate", "grossAmount", "currency", "vatLines", "otherRate",
                     "reverseCharge", "supplierRegion", "category", "invoiceNumber", "confidence"] {
            #expect(json.contains("\"\(name)\""), "\(name)")
        }
        #expect(InvoiceSchema.instructions(categories: ["Software"]).contains("Software"))
    }

    // MARK: Mapping

    @Test func mapsTheModelAnswerToAnExtractedInvoice() throws {
        let content = try GeneratedContent(json: """
            {"supplier": " Adobe ", "invoiceNumber": "IE-1", "invoiceDate": "2026-10-01",
             "summary": "Adobe Creative Cloud – Oct 2026", "currency": "EUR", "reverseCharge": false,
             "vatLines": [{"rate": "19", "amount": "9.50"}, {"rate": "other", "otherRate": 10, "amount": "1.00"},
                          {"rate": "other", "amount": "2.00"}],
             "grossAmount": "59.49", "supplierRegion": "European Union", "category": "Software",
             "confidence": {"amount": "high", "date": "medium", "vat": "low"}}
            """)
        let invoice = InvoiceSchema.invoice(from: content)
        #expect(invoice == ExtractedInvoice(
            supplier: "Adobe", summary: "Adobe Creative Cloud – Oct 2026", invoiceDate: "2026-10-01",
            grossAmount: "59.49", currency: "EUR",
            vatLines: [.init(rate: 19, amount: "9.50"), .init(rate: 10, amount: "1.00"), .init(rate: -1, amount: "2.00")],
            reverseCharge: false, supplierRegion: "European Union", category: "Software", invoiceNumber: "IE-1",
            confidence: .init(amount: .high, date: .medium, vat: .low)))
    }

    @Test func missingValuesMapToBlanksAndOtherRateWithoutANumberIsDropped() throws {
        let content = try GeneratedContent(json: """
            {"supplier": "Druckerei", "invoiceNumber": "", "vatLines": [{"rate": "other", "amount": "9.50"}],
             "grossAmount": "59.50"}
            """)
        let invoice = InvoiceSchema.invoice(from: content)
        #expect(invoice.invoiceNumber == nil && invoice.invoiceDate == "" && invoice.reverseCharge == false)
        #expect(invoice.confidence == .init(amount: .low, date: .low, vat: .low))
        #expect(invoice.vatLines == [.init(rate: -1, amount: "9.50")])
        let draft = InvoiceDraftBuilder.build(invoice, sourceFilename: nil, today: "2026-10-11")
        #expect(draft.fields["vat_rates"] == .vatRates([]))
        #expect(draft.info.warnings.contains(.init(.vatMismatch)))
    }

    @Test func imagePathHasTheOCRToolOnTheMac() {
        #expect(FoundationModelsInvoiceExtractor.imageTools.count == 1)
    }

    // MARK: Errors and availability

    @Test func errorsMapToStatesAndReasons() {
        func classify(_ error: any Error) -> ExtractionFailure.Reason { ExtractionFailure.classify(error).reason }
        #expect(classify(LanguageModelError.contextSizeExceeded(
            .init(contextSize: 8192, tokenCount: 9000, debugDescription: ""))) == .tooLong)
        #expect(classify(LanguageModelError.guardrailViolation(.init(debugDescription: ""))) == .guardrail)
        #expect(classify(LanguageModelError.refusal(.init(explanation: "", debugDescription: ""))) == .guardrail)
        #expect(classify(LanguageModelError.unsupportedLanguageOrLocale(
            .init(languageCode: Locale.LanguageCode("xx"), debugDescription: ""))) == .unsupportedLanguage)
        #expect(classify(SystemLanguageModel.Error.assetsUnavailable(.init(debugDescription: ""))) == .assetsUnavailable)
        #expect(classify(NSError(domain: "com.apple.ModelManagerError", code: 1001)) == .assetsUnavailable)
        #expect(classify(CocoaError(.fileReadUnknown)) == .unreadable)
        #expect(classify(ExtractionFailure(.modelNotReady)) == .modelNotReady)

        #expect(ExtractionFailure.Reason.tooLong.state == .failed && ExtractionFailure.Reason.unreadable.state == .failed)
        for reason in [ExtractionFailure.Reason.guardrail, .unsupportedLanguage, .assetsUnavailable, .modelNotReady,
                       .deviceNotEligible, .appleIntelligenceNotEnabled, .imageNotSupported] {
            #expect(reason.state == .unavailable, "\(reason)")
        }
        for reason in ExtractionFailure.Reason.allCases { #expect(!reason.message.isEmpty) }
    }

    @Test func availabilityReasonsMapToFailureReasons() {
        #expect(ExtractionFailure.reason(for: .available) == nil)
        #expect(ExtractionFailure.reason(for: .unavailable(.deviceNotEligible)) == .deviceNotEligible)
        #expect(ExtractionFailure.reason(for: .unavailable(.appleIntelligenceNotEnabled)) == .appleIntelligenceNotEnabled)
        #expect(ExtractionFailure.reason(for: .unavailable(.modelNotReady)) == .modelNotReady)
        #expect(ExtractionFailure.Reason.modelNotReady.message == "The Apple Intelligence model is still downloading.")
    }
}
