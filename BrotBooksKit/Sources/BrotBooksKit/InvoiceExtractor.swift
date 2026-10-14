import CoreGraphics
import Foundation
import FoundationModels
// `OCRTool` comes from the Vision + FoundationModels cross-import overlay, which the iOS Simulator SDK doesn't
// have (the Simulator can't run image understanding anyway).
#if canImport(_Vision_FoundationModels)
import Vision
#endif

/// Reads the details of one invoice. The app uses the on-device model on real devices and
/// `StubInvoiceExtractor` in tests and the Simulator.
public protocol InvoiceExtracting: Sendable {
    /// `categories` are the user's expense categories the result's `category` should come from.
    func extract(_ input: ExtractionInput, categories: [String]) async throws -> ExtractedInvoice
}

/// One invoice to extract: its stored PDF, plus what the import already has in hand so the extractor
/// needn't redo it.
///
/// `@unchecked Sendable` because of the images: `CGImage` isn't marked `Sendable`, but it is immutable, so
/// passing one to the extraction task is safe. Every other property is a value type.
public struct ExtractionInput: @unchecked Sendable {
    /// The expense document, always a PDF (photos are converted by `ImagePDF` first).
    public var document: Data
    /// Name of the imported file, if it had one.
    public var filename: String?
    /// Text of each page when it was already extracted; empty means not extracted (or no text layer).
    public var pageTexts: [String]
    /// The image to read: the decoded photo (`ImagePDF.Output.image`) for a photo import, kept so the image path
    /// doesn't have to render it back from the PDF, or page 1 of a PDF without usable text (`InvoiceInput.prepare`).
    public var image: CGImage?
    /// The last page of a multi-page PDF without usable text, where totals usually are.
    public var lastPageImage: CGImage?

    public init(document: Data, filename: String? = nil, pageTexts: [String] = [], image: CGImage? = nil,
                lastPageImage: CGImage? = nil) {
        self.document = document
        self.filename = filename
        self.pageTexts = pageTexts
        self.image = image
        self.lastPageImage = lastPageImage
    }
}

/// Returns canned results keyed by the input's filename, for tests and the Simulator (which can't run
/// the on-device model). A file without a canned result, or without a name, gets a blank
/// `ExtractedInvoice()`, so it becomes a blank draft just as it would with no extractor at all.
public struct StubInvoiceExtractor: InvoiceExtracting {
    public let results: [String: ExtractedInvoice]

    public init(results: [String: ExtractedInvoice] = [:]) {
        self.results = results
    }

    public func extract(_ input: ExtractionInput, categories: [String]) async throws -> ExtractedInvoice {
        input.filename.flatMap { results[$0] } ?? ExtractedInvoice()
    }
}

// MARK: - Failures and availability

/// Why an invoice couldn't be read automatically. `reason.state` is the draft's extraction state: `unavailable` when
/// the model can't be used for it at all (no Apple Intelligence, guardrails, language, missing assets), `failed` when
/// it ran but the result couldn't be used. Either way the blank draft stays for the user to fill in.
public struct ExtractionFailure: Error, Equatable, Sendable, LocalizedError {
    public enum Reason: String, Sendable, Equatable, CaseIterable {
        // `SystemLanguageModel.Availability.UnavailableReason`
        case deviceNotEligible, appleIntelligenceNotEnabled, modelNotReady
        /// The model's assets (or the image model) aren't on the device, e.g. in the Simulator.
        case assetsUnavailable
        /// The device can't read images (vision isn't supported here).
        case imageNotSupported
        /// The safety guardrails stopped the request, or the model refused.
        case guardrail
        /// The invoice's language isn't supported by the model.
        case unsupportedLanguage
        /// The document didn't fit the model's context, even trimmed.
        case tooLong
        /// The model ran but returned nothing usable, or another error.
        case unreadable

        public var state: ExtractionInfo.State {
            switch self {
            case .tooLong, .unreadable: .failed
            default: .unavailable
            }
        }

        /// English text; the app localizes by reason.
        public var message: String {
            switch self {
            case .deviceNotEligible: "This device doesn't support Apple Intelligence."
            case .appleIntelligenceNotEnabled: "Apple Intelligence is turned off in Settings."
            case .modelNotReady: "The Apple Intelligence model is still downloading."
            case .assetsUnavailable: "The Apple Intelligence model isn't available on this device right now."
            case .imageNotSupported: "Reading images isn't supported on this device."
            case .guardrail: "Apple Intelligence declined to read this document."
            case .unsupportedLanguage: "The invoice's language isn't supported."
            case .tooLong: "The document is too long to read automatically."
            case .unreadable: "The details couldn't be read."
            }
        }
    }

    public var reason: Reason
    /// The underlying error's description, for the log.
    public var detail: String?

    public init(_ reason: Reason, detail: String? = nil) {
        self.reason = reason
        self.detail = detail
    }

    public var errorDescription: String? { reason.message }

    /// Maps an error from the model (or anything else thrown while extracting) to a failure. On macOS/iOS 27 the
    /// model throws `LanguageModelError` and `SystemLanguageModel.Error` (the older `GenerationError` is deprecated).
    public static func classify(_ error: any Error) -> ExtractionFailure {
        if let failure = error as? ExtractionFailure { return failure }
        let detail = String(describing: error)
        if let error = error as? LanguageModelError {
            switch error {
            case .contextSizeExceeded: return .init(.tooLong, detail: detail)
            case .guardrailViolation, .refusal: return .init(.guardrail, detail: detail)
            case .unsupportedLanguageOrLocale: return .init(.unsupportedLanguage, detail: detail)
            case .unsupportedCapability, .unsupportedTranscriptContent: return .init(.imageNotSupported, detail: detail)
            default: return .init(.unreadable, detail: detail)
            }
        }
        if error is SystemLanguageModel.Error { return .init(.assetsUnavailable, detail: detail) }
        // Image understanding in the Simulator fails with ModelManagerError 1001.
        if (error as NSError).domain.contains("ModelManager") { return .init(.assetsUnavailable, detail: detail) }
        return .init(.unreadable, detail: detail)
    }

    /// The reason for an unavailable model, or nil when it is available.
    public static func reason(for availability: SystemLanguageModel.Availability) -> Reason? {
        switch availability {
        case .available: nil
        case .unavailable(.deviceNotEligible): .deviceNotEligible
        case .unavailable(.appleIntelligenceNotEnabled): .appleIntelligenceNotEnabled
        case .unavailable(.modelNotReady): .modelNotReady
        @unknown default: .assetsUnavailable
        }
    }
}

// MARK: - Foundation Models extractor

/// Reads invoices with the on-device Apple Intelligence model (Foundation Models).
///
/// Text PDFs are sent as text, trimmed to `textBudget` tokens; scanned PDFs and photos as image attachments with
/// the OCR tool enabled. Each invoice gets a fresh session, so documents never share context. The answer is guided
/// by `InvoiceSchema`, which limits the category, currency, region and VAT rates to known values. When the
/// document doesn't fit the context, it is retried once with a tighter trim or a smaller image.
public struct FoundationModelsInvoiceExtractor: InvoiceExtracting {
    /// Document text budget in tokens. The context is 8,192 tokens, shared with the instructions, schema and answer.
    public var textBudget = 6000
    /// Text budget for the retry after the context was exceeded.
    public var retryTextBudget = 3500
    /// Long edge of the image sent to the model, in pixels. Spike on this Mac (macOS 27, 2026-10-11) with
    /// invoice_photo at 3000 / 2000 / 1684 / 1200 / 800 px: 1508–1510 input tokens and about 5 s at every size, all
    /// read correctly, so the smallest of the planned sizes is used.
    public var imageLongEdge = 1200
    /// Long edge for the retry after the context was exceeded. Image cost barely depends on size (see above), so
    /// this mainly guards against a model that counts pixels in a later release.
    public var retryImageLongEdge = 800
    /// Currencies the answer may use besides `InvoiceSchema.baseCurrencies` (those seen in existing records).
    public var currencies: [String]
    /// Counts tokens for trimming; the model's own count by default.
    public var tokenCounter: InvoiceInput.TokenCounter

    public init(currencies: [String] = [],
                tokenCounter: @escaping InvoiceInput.TokenCounter = { try await SystemLanguageModel.default.tokenCount(for: $0) }) {
        self.currencies = currencies
        self.tokenCounter = tokenCounter
    }

    /// Why the model can't be used right now, or nil when it is available. The import panel shows it once per batch.
    public static var unavailableReason: ExtractionFailure.Reason? {
        ExtractionFailure.reason(for: SystemLanguageModel.default.availability)
    }

    /// How one extraction went, for evaluation and logging.
    public struct Report: Sendable {
        public enum Path: String, Sendable { case text, image }
        public var path: Path
        public var inputTokens: Int
        public var outputTokens: Int
        public var seconds: Double
        /// 2 when the first try exceeded the context and was retried.
        public var attempts: Int
        /// The model's answer as JSON.
        public var rawJSON: String
    }

    /// The OCR tool for dense print on the image path; none where the SDK lacks it (the iOS Simulator).
    static var imageTools: [any Tool] {
        #if canImport(_Vision_FoundationModels)
        [OCRTool()]
        #else
        []
        #endif
    }

    public func extract(_ input: ExtractionInput, categories: [String]) async throws -> ExtractedInvoice {
        try await extractWithReport(input, categories: categories).invoice
    }

    /// `extract`, plus token usage and timing. Throws `ExtractionFailure`.
    public func extractWithReport(_ input: ExtractionInput,
                                  categories: [String]) async throws -> (invoice: ExtractedInvoice, report: Report) {
        if let reason = Self.unavailableReason { throw ExtractionFailure(reason) }
        let input = InvoiceInput.prepared(input)
        let isImage = input.pageTexts.isEmpty
        guard !isImage || input.image != nil else { throw ExtractionFailure(.unreadable, detail: "No text or image") }
        let schema: GenerationSchema
        do {
            schema = try InvoiceSchema.make(categories: categories, currencies: currencies)
        } catch {
            throw ExtractionFailure(.unreadable, detail: String(describing: error))
        }
        let instructions = InvoiceSchema.instructions(categories: InvoiceSchema.categoryChoices(categories))
        let options = GenerationOptions(samplingMode: .greedy)
        let start = Date()
        for attempt in 1...2 {
            let retry = attempt == 2
            let session = LanguageModelSession(model: SystemLanguageModel.default, tools: isImage ? Self.imageTools : [],
                                               instructions: instructions)
            do {
                let response: LanguageModelSession.Response<GeneratedContent>
                if isImage {
                    let edge = retry ? retryImageLongEdge : imageLongEdge
                    let first = InvoiceInput.downscaled(input.image!, longEdge: edge)
                    let last = input.lastPageImage.map { InvoiceInput.downscaled($0, longEdge: edge) }
                    response = try await session.respond(schema: schema, options: options) {
                        "Read this invoice and fill in its details. Use the OCR tool for small or dense print."
                        Attachment(first).label(last == nil ? "invoice" : "invoice, first page")
                        if let last { Attachment(last).label("invoice, last page") }
                    }
                } else {
                    let budget = retry ? retryTextBudget : textBudget
                    guard let text = try await InvoiceInput.trimmedText(input.pageTexts, budget: budget,
                                                                        count: tokenCounter) else {
                        throw ExtractionFailure(.tooLong)
                    }
                    response = try await session.respond(to: "Invoice text:\n\(text)", schema: schema,
                                                         options: options)
                }
                let report = Report(path: isImage ? .image : .text, inputTokens: response.usage.input.totalTokenCount,
                                    outputTokens: response.usage.output.totalTokenCount,
                                    seconds: Date().timeIntervalSince(start), attempts: attempt,
                                    rawJSON: response.content.jsonString)
                return (InvoiceSchema.invoice(from: response.content), report)
            } catch {
                let failure = ExtractionFailure.classify(error)
                if failure.reason == .tooLong && !retry { continue }
                throw failure
            }
        }
        throw ExtractionFailure(.tooLong)
    }
}

// MARK: - Schema, instructions and mapping

/// The guided-generation schema, the instructions and the mapping of the model's answer to `ExtractedInvoice`.
/// Pure, so it is unit-tested without the model.
public enum InvoiceSchema {
    public static let otherCategory = "Other expenses"
    public static let baseCurrencies = EditForm.currencies
    /// VAT rate choices; "other" asks for the rate in `otherRate`.
    public static let vatRateChoices = ["19", "7", "0", "other"]
    public static let confidenceChoices = ["high", "medium", "low"]
    /// Most used categories offered to the model.
    public static let maxCategories = 20

    /// The user's most used categories (already sorted by use), without the tax office's VAT payments, which are
    /// never an invoice, plus `otherCategory`.
    public static func categoryChoices(_ categories: [String]) -> [String] {
        var out: [String] = []
        for c in categories.map({ $0.trimmingCharacters(in: .whitespacesAndNewlines) })
        where !c.isEmpty && !c.hasPrefix("ExpenseCategory") && !out.contains(c) && c != otherCategory {
            out.append(c)
        }
        return Array(out.prefix(maxCategories)) + [otherCategory]
    }

    public static func currencyChoices(_ extra: [String]) -> [String] {
        var out = baseCurrencies
        for c in extra.map({ $0.uppercased() }) where c.count == 3 && !out.contains(c) { out.append(c) }
        return out
    }

    /// The answer's properties in the order the model generates them, so earlier answers inform later ones:
    /// supplier → date → currency → reverse charge → VAT lines → gross → region → category → confidence.
    public static func make(categories: [String], currencies: [String] = []) throws -> GenerationSchema {
        let amount = DynamicGenerationSchema(type: String.self, guides: [.pattern(/\d+\.\d{2}/)])
        let vatLine = DynamicGenerationSchema(name: "VatLine", properties: [
            .init(name: "rate", description: "VAT rate in percent", schema: .init(name: "VatRate", anyOf: vatRateChoices)),
            .init(name: "otherRate", description: "The rate in percent when rate is other",
                  schema: .init(type: Int.self, guides: [.range(0...100)]), isOptional: true),
            .init(name: "amount", description: "VAT amount, not the net", schema: amount),
        ])
        let level = DynamicGenerationSchema(name: "Confidence", anyOf: confidenceChoices)
        let confidence = DynamicGenerationSchema(name: "FieldConfidence", properties: [
            .init(name: "amount", schema: level), .init(name: "date", schema: level), .init(name: "vat", schema: level),
        ])
        let root = DynamicGenerationSchema(name: "Invoice", properties: [
            .init(name: "supplier", description: "Short brand name of the issuer", schema: .init(type: String.self)),
            .init(name: "invoiceNumber", schema: .init(type: String.self), isOptional: true),
            .init(name: "invoiceDate", description: "YYYY-MM-DD",
                  schema: .init(type: String.self, guides: [.pattern(/\d{4}-\d{2}-\d{2}/)])),
            .init(name: "summary", description: "Brand, product and month, e.g. Adobe Creative Cloud – Oct 2026",
                  schema: .init(type: String.self)),
            .init(name: "currency", schema: .init(name: "Currency", anyOf: currencyChoices(currencies))),
            .init(name: "reverseCharge", schema: .init(type: Bool.self)),
            .init(name: "vatLines", schema: .init(arrayOf: vatLine, maximumElements: 4)),
            .init(name: "grossAmount", description: "Total actually charged, including VAT", schema: amount),
            .init(name: "supplierRegion", schema: .init(name: "Region", anyOf: EditForm.regions)),
            .init(name: "category", schema: .init(name: "Category", anyOf: categoryChoices(categories))),
            .init(name: "confidence", description: "How clearly the invoice shows each value", schema: confidence),
        ])
        return try GenerationSchema(root: root, dependencies: [])
    }

    public static func instructions(categories: [String]) -> String {
        """
        You extract data from supplier invoices and receipts for a German freelancer's bookkeeping. Invoices are \
        often German (Rechnung, Rechnungsdatum, Netto, MwSt/USt, Brutto, Gesamtbetrag), with DD.MM.YYYY dates and \
        decimal commas. Return the amount actually charged: the final total including VAT (Gesamtbetrag, Brutto, \
        Total, Amount paid), not the net amount or a subtotal.
        - supplier: the short brand name of the company that issued the invoice, without legal form or country \
        ("Adobe", not "Adobe Systems Software Ireland Ltd"). Never the customer.
        - summary: brand, product and month, like "Adobe Creative Cloud – Oct 2026".
        - invoiceDate: the invoice date as YYYY-MM-DD (01.10.2026 is 2026-10-01).
        - Amounts: digits, a dot and two decimals, no thousands separators (1.234,56 is 1234.56).
        - vatLines: one row per VAT rate the invoice charges, with its VAT amount. Leave it empty when no VAT is \
        charged or the VAT is 0.00; never add a row with a zero amount. For a rate other than 19 or 7 use \
        "other" and give otherRate.
        - reverseCharge: false whenever the invoice charges VAT (a VAT, MwSt or USt amount above zero), \
        wherever the supplier is. True only when the invoice says "Steuerschuldnerschaft des \
        Leistungsempfängers" or "reverse charge", or the supplier is outside Germany and charges no VAT at all.
        - supplierRegion: where the supplier is based.
        - category: the best match; "\(otherCategory)" when none fits.
        - confidence: high when the value is printed clearly, low when you had to guess.
        The user's most used expense categories: \(categories.joined(separator: ", ")).
        """
    }

    /// The model's answer as an `ExtractedInvoice`. Missing or malformed values become blanks for
    /// `InvoiceDraftBuilder` to flag. A VAT line with rate "other" takes `otherRate`, or -1 when none was given,
    /// which the builder rejects (outside 0–100) so the VAT rows are dropped with a warning.
    public static func invoice(from content: GeneratedContent) -> ExtractedInvoice {
        func string(_ c: GeneratedContent, _ key: String) -> String {
            ((try? c.value(String?.self, forProperty: key)) ?? nil)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        }
        func level(_ c: GeneratedContent?, _ key: String) -> ExtractionInfo.Confidence {
            c.flatMap { ExtractionInfo.Confidence(rawValue: string($0, key)) } ?? .low
        }
        let lines = ((try? content.value([GeneratedContent]?.self, forProperty: "vatLines")) ?? nil) ?? []
        let vatLines = lines.map { line -> ExtractedInvoice.VatLine in
            let choice = string(line, "rate")
            let rate = choice == "other"
                ? ((try? line.value(Int?.self, forProperty: "otherRate")) ?? nil) ?? -1
                : Int(choice) ?? -1
            return .init(rate: rate, amount: string(line, "amount"))
        }
        let confidence = (try? content.value(GeneratedContent?.self, forProperty: "confidence")) ?? nil
        let number = string(content, "invoiceNumber")
        return ExtractedInvoice(
            supplier: string(content, "supplier"), summary: string(content, "summary"),
            invoiceDate: string(content, "invoiceDate"), grossAmount: string(content, "grossAmount"),
            currency: string(content, "currency"), vatLines: vatLines,
            reverseCharge: ((try? content.value(Bool?.self, forProperty: "reverseCharge")) ?? nil) ?? false,
            supplierRegion: string(content, "supplierRegion"), category: string(content, "category"),
            invoiceNumber: number.isEmpty ? nil : number,
            confidence: .init(amount: level(confidence, "amount"), date: level(confidence, "date"),
                              vat: level(confidence, "vat")))
    }
}
