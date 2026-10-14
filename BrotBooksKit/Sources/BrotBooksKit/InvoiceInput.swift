import CoreGraphics
import Foundation
import PDFKit

/// Prepares an invoice document for the extractor: a text PDF is sent as its text, trimmed to fit the model's
/// context; a scanned PDF or a photo is sent as page images.
public enum InvoiceInput {
    /// Fewer non-space characters than this means the PDF has no usable text layer.
    public static let minimumTextCharacters = 200
    /// Pages are rendered for the image path at this resolution.
    public static let renderDPI: CGFloat = 150

    // MARK: Preparing

    /// The extractor's input for a document. A PDF whose text layer is meaningful (`isMeaningful`) gets its page texts;
    /// otherwise page 1 and, if different, the last page are rendered at `renderDPI`. `image`, a photo already decoded
    /// on import, is used as is, so a photo never takes the text path.
    public static func prepare(document: Data, filename: String?, image: CGImage? = nil) -> ExtractionInput {
        if let image { return ExtractionInput(document: document, filename: filename, image: image) }
        let texts = pageTexts(document)
        if isMeaningful(texts) { return ExtractionInput(document: document, filename: filename, pageTexts: texts) }
        let count = pageCount(document)
        let first = renderPage(document, number: 1)
        let last = count > 1 ? renderPage(document, number: count) : nil
        return ExtractionInput(document: document, filename: filename, image: first, lastPageImage: last)
    }

    /// `input` with its text or images filled in when the caller passed only the document.
    public static func prepared(_ input: ExtractionInput) -> ExtractionInput {
        guard input.pageTexts.isEmpty, input.image == nil else { return input }
        return prepare(document: input.document, filename: input.filename)
    }

    /// The text of every page from the PDF's text layer (empty strings for pages without one).
    public static func pageTexts(_ document: Data) -> [String] {
        guard let pdf = PDFDocument(data: document) else { return [] }
        return (0..<pdf.pageCount).map { pdf.page(at: $0)?.string ?? "" }
    }

    static func pageCount(_ document: Data) -> Int {
        guard let provider = CGDataProvider(data: document as CFData), let pdf = CGPDFDocument(provider) else { return 0 }
        return pdf.numberOfPages
    }

    // MARK: Meaningful text

    /// True when the pages hold more than `minimumTextCharacters` non-space characters and read as words rather than
    /// OCR noise (`readsAsWords`).
    public static func isMeaningful(_ pageTexts: [String]) -> Bool {
        let text = pageTexts.joined(separator: "\n")
        let characters = text.unicodeScalars.count { !CharacterSet.whitespacesAndNewlines.contains($0) }
        return characters > minimumTextCharacters && readsAsWords(text)
    }

    /// A rough test for real words: most whitespace-separated tokens must look like a word ("Rechnung", "MwSt."),
    /// a number or amount ("119,00", "01.10.2026", "19%") or a code ("NS-2026-0042"), and most letter words must
    /// contain a vowel. A broken text layer or a poor embedded OCR layer fails one of the two.
    public static func readsAsWords(_ text: String) -> Bool {
        let tokens = text.split(whereSeparator: \.isWhitespace).map {
            $0.trimmingCharacters(in: CharacterSet(charactersIn: ".,:;!?()[]\"'‘’“”«»€$£%*/-–"))
        }.filter { !$0.isEmpty }
        guard tokens.count >= 20 else { return false }
        var plausible = 0, words = 0, voweled = 0
        for token in tokens {
            let letters = token.count { $0.isLetter }, digits = token.count { $0.isNumber }
            let others = token.count - letters - digits
            if letters == token.count || (letters >= token.count - 1 && letters >= 2 && others <= 1) {
                // A word, allowing one inner mark ("E-Mail", "Leistungsempfänger's").
                guard letters >= 2 else { continue }
                plausible += 1
                if letters >= 3 {
                    words += 1
                    if token.lowercased().contains(where: { "aeiouyäöüéèàáíóú".contains($0) }) { voweled += 1 }
                }
            } else if digits > 0 && token.allSatisfy({ $0.isNumber || ".,%-/:+".contains($0) }) {
                plausible += 1
            } else if digits > 0 && letters > 0 && token.allSatisfy({ $0.isLetter || $0.isNumber || "-_/.".contains($0) }) {
                plausible += 1
            }
        }
        return Double(plausible) / Double(tokens.count) >= 0.7 && words >= 10
            && Double(voweled) / Double(words) >= 0.8
    }

    // MARK: Trimming

    /// Counts the tokens of a text; the extractor passes the model's `tokenCount(for:)`.
    public typealias TokenCounter = @Sendable (String) async throws -> Int

    /// The page texts as one prompt text within `budget` tokens, or nil when even a cut-down version doesn't fit.
    ///
    /// All pages when they fit. Otherwise the first two pages and the last one (totals and VAT summaries sit at the
    /// end), and if that is still too long, the start of the first pages and the end of the last page, shortened
    /// in proportion until it fits.
    public static func trimmedText(_ pageTexts: [String], budget: Int, count: TokenCounter) async throws -> String? {
        let pages = pageTexts.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        guard !pages.isEmpty else { return nil }
        let all = join(pages.indices.map { ($0, pages[$0]) }, total: pages.count)
        if try await count(all) <= budget { return all }

        var kept = Array(pages.indices.prefix(2))
        if let last = pages.indices.last, !kept.contains(last) { kept.append(last) }
        var parts = kept.map { ($0, pages[$0]) }
        var text = join(parts, total: pages.count)
        var tokens = try await count(text)
        if tokens <= budget { return text }

        // Cut the kept pages in proportion: the first pages keep their start, the last page its end.
        for _ in 0..<4 {
            let ratio = Double(budget) / Double(tokens) * 0.9
            parts = parts.map { index, page in
                let keep = max(0, Int(Double(page.count) * ratio))
                let cut = index == pages.count - 1 && pages.count > 1
                    ? String(page.suffix(keep)) : String(page.prefix(keep))
                return (index, cut)
            }
            text = join(parts, total: pages.count)
            tokens = try await count(text)
            if tokens <= budget { return text }
        }
        return nil
    }

    /// Pages with their numbers, so the model knows where the last page starts and that pages were left out.
    static func join(_ pages: [(Int, String)], total: Int) -> String {
        var out: [String] = []
        var previous = -1
        for (index, text) in pages {
            if index > previous + 1 { out.append("[pages \(previous + 2)–\(index) left out]") }
            out.append("--- Page \(index + 1) of \(total) ---\n\(text)")
            previous = index
        }
        return out.joined(separator: "\n")
    }

    // MARK: Images

    /// Page `number` (1-based) of a PDF as an image at `dpi`, on white.
    public static func renderPage(_ document: Data, number: Int = 1, dpi: CGFloat = renderDPI) -> CGImage? {
        guard let provider = CGDataProvider(data: document as CFData), let pdf = CGPDFDocument(provider),
              let page = pdf.page(at: number) else { return nil }
        let box = page.getBoxRect(.cropBox)
        let scale = dpi / 72
        let width = Int((box.width * scale).rounded()), height = Int((box.height * scale).rounded())
        guard width > 0, height > 0, let context = whiteContext(width: width, height: height) else { return nil }
        context.scaleBy(x: scale, y: scale)
        context.translateBy(x: -box.minX, y: -box.minY)
        context.drawPDFPage(page)
        return context.makeImage()
    }

    /// `image` scaled down so its long edge is at most `longEdge` pixels; smaller images are returned unchanged.
    public static func downscaled(_ image: CGImage, longEdge: Int) -> CGImage {
        let long = max(image.width, image.height)
        guard long > longEdge, longEdge > 0 else { return image }
        let scale = Double(longEdge) / Double(long)
        let width = max(1, Int((Double(image.width) * scale).rounded()))
        let height = max(1, Int((Double(image.height) * scale).rounded()))
        guard let context = whiteContext(width: width, height: height) else { return image }
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage() ?? image
    }

    private static func whiteContext(width: Int, height: Int) -> CGContext? {
        guard let srgb = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: srgb, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)
        else { return nil }
        context.setFillColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return context
    }
}
