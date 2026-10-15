import Foundation

/// Extraction metadata of a draft expense, stored as JSON in `Expense.extraction` while the expense is a draft
/// and cleared on approval. Decoding tolerates missing keys, so fields can be added without breaking stored drafts.
public struct ExtractionInfo: Codable, Sendable, Equatable {
    public enum State: String, Codable, Sendable {
        case pending, done, failed, unavailable
    }

    public enum Confidence: String, Codable, Sendable {
        case high, medium, low
    }

    /// Something for the user to check; `field` is a record field name when the warning is about one field.
    /// `message` is English; the app may localize by `code`.
    public struct Warning: Codable, Sendable, Equatable, Hashable {
        public enum Code: String, Codable, Sendable {
            /// The VAT rows didn't add up to the gross amount and were dropped (field `vat_rates`).
            case vatMismatch
            /// A foreign currency needs a conversion rate (field `currency_conversion_rate`).
            case foreignCurrency
            /// The invoice date couldn't be read, is in the future or is before 2015 (field `date`).
            case implausibleDate
        }

        public var field: String?
        public var message: String
        public var code: Code?

        public init(field: String? = nil, message: String, code: Code? = nil) {
            self.field = field
            self.message = message
            self.code = code
        }

        /// The warning for `code`, on its field with its English message.
        public init(_ code: Code) {
            switch code {
            case .vatMismatch:
                self.init(field: "vat_rates", message: "VAT didn't add up to the total", code: code)
            case .foreignCurrency:
                self.init(field: "currency_conversion_rate", message: "Foreign currency – enter the rate", code: code)
            case .implausibleDate:
                self.init(field: "date", message: "Check the date – it looks wrong", code: code)
            }
        }

        enum CodingKeys: String, CodingKey {
            case field, message, code
        }

        public init(from decoder: any Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            field = try c.decodeIfPresent(String.self, forKey: .field)
            message = try c.decodeIfPresent(String.self, forKey: .message) ?? ""
            // An unknown code (from a newer app version) reads as none rather than failing the whole draft.
            code = (try? c.decodeIfPresent(String.self, forKey: .code)).flatMap { $0.flatMap(Code.init(rawValue:)) }
        }

        public func encode(to encoder: any Encoder) throws {
            var c = encoder.container(keyedBy: CodingKeys.self)
            try c.encodeIfPresent(field, forKey: .field)
            try c.encode(message, forKey: .message)
            try c.encodeIfPresent(code, forKey: .code)
        }
    }

    public var state: State
    /// The model's structured output as JSON text, kept for review and debugging.
    public var raw: String?
    /// Confidence per record field name.
    public var confidence: [String: Confidence]
    public var warnings: [Warning]
    /// Why extraction failed or is unavailable.
    public var failureReason: String?
    /// Name of the imported file, shown while the draft has no description yet.
    public var sourceFilename: String?
    /// Fields the user changed while the expense was a draft. `RecordStore.update` adds to it, and
    /// `RecordStore.applyExtraction` never writes these fields, so a late extraction keeps the user's corrections.
    public var editedFields: Set<String>

    public init(state: State, raw: String? = nil, confidence: [String: Confidence] = [:], warnings: [Warning] = [],
                failureReason: String? = nil, sourceFilename: String? = nil, editedFields: Set<String> = []) {
        self.state = state
        self.raw = raw
        self.confidence = confidence
        self.warnings = warnings
        self.failureReason = failureReason
        self.sourceFilename = sourceFilename
        self.editedFields = editedFields
    }

    enum CodingKeys: String, CodingKey {
        case state, raw, confidence, warnings, failureReason, sourceFilename, editedFields
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        state = try c.decodeIfPresent(State.self, forKey: .state) ?? .pending
        raw = try c.decodeIfPresent(String.self, forKey: .raw)
        confidence = try c.decodeIfPresent([String: Confidence].self, forKey: .confidence) ?? [:]
        warnings = try c.decodeIfPresent([Warning].self, forKey: .warnings) ?? []
        failureReason = try c.decodeIfPresent(String.self, forKey: .failureReason)
        sourceFilename = try c.decodeIfPresent(String.self, forKey: .sourceFilename)
        editedFields = Set(try c.decodeIfPresent([String].self, forKey: .editedFields) ?? [])
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(state, forKey: .state)
        try c.encodeIfPresent(raw, forKey: .raw)
        try c.encode(confidence, forKey: .confidence)
        try c.encode(warnings, forKey: .warnings)
        try c.encodeIfPresent(failureReason, forKey: .failureReason)
        try c.encodeIfPresent(sourceFilename, forKey: .sourceFilename)
        try c.encode(editedFields.sorted(), forKey: .editedFields)
    }

    /// Why a field needs a second look in review.
    public enum Flag: Sendable, Equatable {
        /// A warning about this field.
        case warning(Warning)
        /// The extractor wasn't sure about the value.
        case lowConfidence
    }

    /// The field's warning, or `lowConfidence` when the extractor was unsure about it, or nil. A warning wins.
    public func flag(for field: String) -> Flag? {
        if let warning = warnings.first(where: { $0.field == field }) { return .warning(warning) }
        return confidence[field] == .low ? .lowConfidence : nil
    }

    /// Ready to approve without a second look: extraction finished, there are no warnings, and the date, the gross
    /// amount and every other field read have high confidence.
    public var looksComplete: Bool {
        state == .done && warnings.isEmpty && confidence["date"] == .high && confidence["gross_amount"] == .high
            && confidence.values.allSatisfy { $0 == .high }
    }

    /// The stored JSON, or nil when absent or unreadable.
    public static func decode(_ data: Data?) -> ExtractionInfo? {
        data.flatMap { try? JSONDecoder().decode(ExtractionInfo.self, from: $0) }
    }

    public func encoded() -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        // Encoding plain strings, enums and collections can't fail.
        return (try? encoder.encode(self)) ?? Data()
    }
}

/// What an extractor read from one invoice, before validation and mapping to record fields. Amounts are
/// decimal strings (`"119.00"`) and the date is `YYYY-MM-DD`, as the model is asked to return them; an
/// empty string means the value wasn't found. The default value is a blank result.
public struct ExtractedInvoice: Codable, Sendable, Equatable, Hashable {
    public struct VatLine: Codable, Sendable, Equatable, Hashable {
        /// VAT rate in percent: 0, 7 or 19, or another rate the invoice shows.
        public var rate: Int
        /// VAT amount as a decimal string.
        public var amount: String

        public init(rate: Int, amount: String) {
            self.rate = rate
            self.amount = amount
        }
    }

    /// How sure the extractor is about the amount, the date and the VAT rows.
    public struct FieldConfidence: Codable, Sendable, Equatable, Hashable {
        public var amount: ExtractionInfo.Confidence
        public var date: ExtractionInfo.Confidence
        public var vat: ExtractionInfo.Confidence

        public init(amount: ExtractionInfo.Confidence = .low, date: ExtractionInfo.Confidence = .low,
                    vat: ExtractionInfo.Confidence = .low) {
            self.amount = amount
            self.date = date
            self.vat = vat
        }
    }

    /// Company name only.
    public var supplier: String
    /// Short description in the style of existing records, e.g. "Adobe Creative Cloud – Oct 2026".
    public var summary: String
    /// `YYYY-MM-DD`.
    public var invoiceDate: String
    /// The amount actually charged, as a decimal string.
    public var grossAmount: String
    /// ISO currency code.
    public var currency: String
    public var vatLines: [VatLine]
    /// Reverse charge ("Steuerschuldnerschaft des Leistungsempfängers"), or a foreign supplier charging no VAT.
    public var reverseCharge: Bool
    /// One of `EditForm.regions`.
    public var supplierRegion: String
    /// One of the user's expense categories, or "Other expenses".
    public var category: String
    public var invoiceNumber: String?
    public var confidence: FieldConfidence

    public init(supplier: String = "", summary: String = "", invoiceDate: String = "", grossAmount: String = "",
                currency: String = "", vatLines: [VatLine] = [], reverseCharge: Bool = false,
                supplierRegion: String = "", category: String = "", invoiceNumber: String? = nil,
                confidence: FieldConfidence = FieldConfidence()) {
        self.supplier = supplier
        self.summary = summary
        self.invoiceDate = invoiceDate
        self.grossAmount = grossAmount
        self.currency = currency
        self.vatLines = vatLines
        self.reverseCharge = reverseCharge
        self.supplierRegion = supplierRegion
        self.category = category
        self.invoiceNumber = invoiceNumber
        self.confidence = confidence
    }
}

/// Turns an extractor's `ExtractedInvoice` into draft expense fields and extraction metadata: normalizes amounts and
/// dates, checks the date and the VAT rows, handles reverse charge and foreign currencies, prefers the category and
/// region of earlier expenses from the same supplier, and records warnings and per-field confidence.
/// Pure and deterministic: `today` and the earlier expenses are passed in.
public enum InvoiceDraftBuilder {
    /// An earlier, approved expense, for learned defaults (`RecordStore.pastExpenses()`).
    public struct PastExpense: Sendable, Equatable {
        public var description: String
        public var category: String?
        public var supplierRegion: String?

        public init(description: String, category: String? = nil, supplierRegion: String? = nil) {
            self.description = description
            self.category = category
            self.supplierRegion = supplierRegion
        }
    }

    /// What `RecordStore.applyExtraction` takes.
    public struct Draft: Sendable, Equatable {
        public var fields: [String: FieldInput]
        public var info: ExtractionInfo
        /// The VAT treatment suggested by the supplier region and VAT rows set above (reverse charge for a
        /// foreign supplier without VAT). Not part of `fields`: the draft's `vat_treatment` stays unset, so the
        /// treatment shows as unconfirmed until the user sets it.
        public var vatTreatment: VatTreatment.Suggestion?

        /// Ready for review without a second look: a date and a gross amount were read, there are no warnings and
        /// no field has low confidence.
        public var isComplete: Bool {
            fields["date"] != nil && fields["gross_amount"] != nil && info.warnings.isEmpty
                && !info.confidence.values.contains(.low)
        }
    }

    /// Invoice dates before this are taken as misread.
    public static let earliestDate = "2015-01-01"

    /// The draft for `invoice`. `today` is `YYYY-MM-DD`; `history` is earlier expenses newest first (the first
    /// one from the same supplier wins).
    public static func build(_ invoice: ExtractedInvoice, sourceFilename: String?, today: String,
                             history: [PastExpense] = []) -> Draft {
        var fields: [String: FieldInput] = [:]
        var confidence: [String: ExtractionInfo.Confidence] = [:]
        var warnings: [ExtractionInfo.Warning] = []
        func clean(_ s: String) -> String { s.trimmingCharacters(in: .whitespacesAndNewlines) }

        let supplier = clean(invoice.supplier)
        let description = clean(invoice.summary).isEmpty ? supplier : clean(invoice.summary)
        if !description.isEmpty { fields["description"] = .text(description) }

        // Date: normalized, then not in the future and not before 2015.
        if !clean(invoice.invoiceDate).isEmpty {
            if let date = normalizeDate(invoice.invoiceDate) {
                fields["date"] = .text(date)
                confidence["date"] = invoice.confidence.date
                if date > today || date < earliestDate { warnings.append(.init(.implausibleDate)) }
            } else {
                warnings.append(.init(.implausibleDate))
            }
        }

        let gross = normalizeAmount(invoice.grossAmount)
        if let gross {
            fields["gross_amount"] = .text(EditForm.amountText(gross))
            confidence["gross_amount"] = invoice.confidence.amount
        }

        let currency = normalizeCurrency(invoice.currency)
        if let currency {
            fields["currency"] = .text(currency)
            // The app has no rate source: the rate stays empty for the user to enter.
            if currency != "EUR" { warnings.append(.init(.foreignCurrency)) }
        }

        // VAT rows: none under reverse charge; otherwise kept only when they add up to the gross.
        if invoice.reverseCharge {
            fields["vat_rates"] = .vatRates([])
            confidence["vat_rates"] = invoice.confidence.vat
        } else if !invoice.vatLines.isEmpty {
            if let rows = reconciledVat(invoice.vatLines, gross: gross) {
                fields["vat_rates"] = .vatRates(rows.map {
                    VatRowInput(rate: Money.plainString($0.rate), amount: EditForm.amountText($0.amount))
                })
                confidence["vat_rates"] = invoice.confidence.vat
            } else {
                fields["vat_rates"] = .vatRates([])
                warnings.append(.init(.vatMismatch))
            }
        }

        var category = clean(invoice.category)
        var region = EditForm.regions.contains(clean(invoice.supplierRegion)) ? clean(invoice.supplierRegion) : ""
        if invoice.reverseCharge, region.isEmpty || region == EditForm.regions[0] {
            // Reverse charge means a foreign supplier: inside the EU when it bills in euros.
            region = (currency ?? "EUR") == "EUR" ? EditForm.regions[1] : EditForm.regions[2]
        }
        if let past = learnedDefaults(supplier: supplier, history: history) {
            if let c = past.category.map(clean), !c.isEmpty { category = c }
            if let r = past.supplierRegion, EditForm.regions.contains(r) { region = r }
        }
        if !category.isEmpty { fields["category"] = .text(category) }
        if !region.isEmpty { fields["supplier_region"] = .text(region) }

        for warning in warnings {
            if let field = warning.field { confidence[field] = .low }
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        let raw = (try? encoder.encode(invoice)).flatMap { String(data: $0, encoding: .utf8) }
        let vatTreatment = (try? RecordRules.coerce(.expenses, fields, draft: true))
            .map { VatTreatment.suggest(.expenses, values: $0) }
        return Draft(fields: fields, info: ExtractionInfo(state: .done, raw: raw, confidence: confidence,
                                                          warnings: warnings, sourceFilename: sourceFilename),
                     vatTreatment: vatTreatment)
    }

    // MARK: Amounts

    /// A money amount as printed on an invoice: "119.00", "119,00", "1.234,56", "1,234.56", "€ 119.00",
    /// "19.00 EUR", "-5,00". A single separator followed by exactly three digits (after a non-zero integer part of
    /// at most three digits) is a thousands separator: "1.234" is 1234. Nil when there is no number.
    public static func normalizeAmount(_ text: String) -> Decimal? {
        let negative = text.contains("-") || text.contains("−")
        let kept = Array(text.filter { $0.isASCII && ($0.isNumber || $0 == "," || $0 == ".") })
        guard kept.contains(where: \.isNumber) else { return nil }
        let separators = kept.indices.filter { !kept[$0].isNumber }
        var decimalIndex: Int?
        if let last = separators.last {
            let mark = kept[last]
            let sameMarks = separators.count { kept[$0] == mark }
            if sameMarks < separators.count {
                // Both marks appear: the last one is the decimal separator.
                decimalIndex = last
            } else if sameMarks == 1 {
                let before = String(kept[..<last]), after = kept.count - last - 1
                let grouping = after == 3 && (1...3).contains(before.count) && before != "0"
                decimalIndex = grouping ? nil : last
            }
        }
        var digits = ""
        for i in kept.indices {
            if kept[i].isNumber { digits.append(kept[i]) } else if i == decimalIndex { digits.append(".") }
        }
        guard let value = Money.parse(digits) else { return nil }
        return negative ? -value : value
    }

    static func normalizeCurrency(_ text: String) -> String? {
        let s = text.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        switch s {
        case "": return nil
        case "€": return "EUR"
        case "$", "US$": return "USD"
        case "£": return "GBP"
        default: return s
        }
    }

    // MARK: Dates

    private static let monthPrefixes: [String: Int] = [
        "jan": 1, "jän": 1, "feb": 2, "mär": 3, "mar": 3, "mae": 3, "apr": 4, "mai": 5, "may": 5, "jun": 6,
        "jul": 7, "aug": 8, "sep": 9, "okt": 10, "oct": 10, "nov": 11, "dez": 12, "dec": 12,
    ]

    /// An invoice date as `YYYY-MM-DD`: ISO ("2026-10-01", "2026/10/1"), day first ("01.10.2026", "1.10.26",
    /// "01/10/2026") or with a German or English month name ("1. Oktober 2026", "1 Oct 2026", "October 1, 2026").
    /// Two-digit years are 20xx. Nil when it isn't a real date.
    public static func normalizeDate(_ text: String) -> String? {
        let s = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        var parts: (year: Int, month: Int, day: Int)?
        if let m = s.wholeMatch(of: /(\d{4})[-\/.](\d{1,2})[-\/.](\d{1,2})/) {
            parts = (Int(m.1)!, Int(m.2)!, Int(m.3)!)
        } else if let m = s.wholeMatch(of: /(\d{1,2})\s*[.\/-]\s*(\d{1,2})\s*[.\/-]\s*(\d{4}|\d{2})/) {
            parts = (Int(m.3)!, Int(m.2)!, Int(m.1)!)
        } else if let m = s.wholeMatch(of: /(\d{1,2})\.?\s*(\p{L}+)\.?,?\s*(\d{4})/) {
            parts = month(m.2).map { (Int(m.3)!, $0, Int(m.1)!) }
        } else if let m = s.wholeMatch(of: /(\p{L}+)\.?\s+(\d{1,2}),?\s+(\d{4})/) {
            parts = month(m.1).map { (Int(m.3)!, $0, Int(m.2)!) }
        }
        guard var p = parts else { return nil }
        if p.year < 100 { p.year += 2000 }
        let date = ISODate.make(p.year, p.month, p.day)
        return ISODate.isValid(date) ? date : nil
    }

    private static func month(_ name: Substring) -> Int? {
        guard name.count >= 3 else { return nil }
        return monthPrefixes[String(name.prefix(3))]
    }

    // MARK: VAT

    /// The VAT rows as numbers when they add up to the gross amount (the check approval makes: one rate must be
    /// within 0.02 of gross × rate / (100 + rate); several must not imply more than the gross), or nil when a row
    /// can't be read, has an impossible rate or the rows don't add up. Without a gross there is nothing to check.
    static func reconciledVat(_ lines: [ExtractedInvoice.VatLine], gross: Decimal?) -> [VatRate]? {
        var rows: [VatRate] = []
        for line in lines {
            guard let amount = normalizeAmount(line.amount) else { return nil }
            rows.append(VatRate(rate: Decimal(line.rate), amount: amount))
        }
        var values: RecordValues = ["vat_rates": .vatRates(rows)]
        if let gross { values["converted_gross_amount"] = .decimal(gross) }
        return RecordRules.vatIssue(values) == nil ? rows : nil
    }

    // MARK: Learned defaults

    /// Legal forms dropped from the end of a supplier name before matching descriptions.
    private static let legalForms: Set<String> = [
        "gmbh", "mbh", "ag", "ug", "kg", "ohg", "gbr", "ek", "se", "co", "&", "inc", "llc", "ltd", "limited", "plc",
        "corp", "corporation", "company", "bv", "nv", "sa", "sas", "sarl", "srl", "sl", "ab", "as", "oy",
        "(haftungsbeschränkt)",
    ]

    /// The first earlier expense whose description starts with the supplier's name (ignoring case and a trailing
    /// legal form such as "GmbH"), as a whole word.
    public static func learnedDefaults(supplier: String, history: [PastExpense]) -> PastExpense? {
        var words = supplier.lowercased().split(whereSeparator: \.isWhitespace).map(String.init)
        while let last = words.last, legalForms.contains(last.filter { $0 != "." && $0 != "," }) || last == "-" {
            words.removeLast()
        }
        let key = words.joined(separator: " ").trimmingCharacters(in: CharacterSet(charactersIn: " ,."))
        guard key.count >= 3 else { return nil }
        return history.first { past in
            let description = past.description.lowercased()
            guard description.hasPrefix(key) else { return false }
            let next = description.dropFirst(key.count).first
            return next.map { !$0.isLetter && !$0.isNumber } ?? true
        }
    }
}
