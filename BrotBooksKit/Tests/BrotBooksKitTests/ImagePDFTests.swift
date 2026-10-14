import CoreGraphics
import Foundation
import ImageIO
import PDFKit
import Testing
@testable import BrotBooksKit

/// Photo → PDF conversion and the fixtures and stub extractor the invoice import builds on.
@Suite struct ImagePDFTests {
    static let photos = ["invoice_photo.png", "invoice_photo.heic", "invoice_photo_rotated.jpg"]

    func fixture(_ name: String) throws -> Data { try Data(contentsOf: fixtureURL(name)) }

    func page(_ pdf: Data) throws -> CGPDFPage {
        let document = try #require(CGPDFDocument(CGDataProvider(data: pdf as CFData)!))
        #expect(document.numberOfPages == 1)
        return try #require(document.page(at: 1))
    }

    /// The raw bytes of the page's `/Im0` image stream, which must be JPEG-encoded.
    func embeddedJPEG(_ page: CGPDFPage) throws -> Data {
        var resources: CGPDFDictionaryRef?, xobjects: CGPDFDictionaryRef?, stream: CGPDFStreamRef?
        let dictionary = try #require(page.dictionary)
        try #require(CGPDFDictionaryGetDictionary(dictionary, "Resources", &resources))
        try #require(CGPDFDictionaryGetDictionary(resources!, "XObject", &xobjects))
        try #require(CGPDFDictionaryGetStream(xobjects!, "Im0", &stream))
        var format = CGPDFDataFormat.raw
        let data = try #require(CGPDFStreamCopyData(stream!, &format))
        #expect(format == .jpegEncoded)
        return data as Data
    }

    /// Mean brightness (0...1) of the image row at `fraction` of the height from the top.
    func rowBrightness(_ image: CGImage, at fraction: Double) -> Double {
        let width = image.width, height = image.height
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        pixels.withUnsafeMutableBytes { buffer in
            let context = CGContext(data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8,
                                    bytesPerRow: width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                    bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        }
        // Bitmap memory starts with the top row.
        let row = min(height - 1, Int(Double(height) * fraction))
        var sum = 0
        for x in 0..<width {
            let i = (row * width + x) * 4
            sum += Int(pixels[i]) + Int(pixels[i + 1]) + Int(pixels[i + 2])
        }
        return Double(sum) / Double(width * 3 * 255)
    }

    @MainActor
    @Test func outputIsOnePdfPageAtA4WidthWithThePhotosAspectRatio() throws {
        let output = try ImagePDF.convert(try fixture("invoice_photo.png"))
        #expect(output.pdf.starts(with: Array("%PDF-".utf8)))
        #expect(output.pdf.suffix(6) == Data("%%EOF\n".utf8))
        #expect((output.image.width, output.image.height) == (1190, 1684))
        let box = try page(output.pdf).getBoxRect(.mediaBox)
        #expect(box.width == 595)
        #expect(abs(box.height - 595 * 1684 / 1190) < 0.01)
        // The draft check for stored documents accepts it.
        try RecordStore.checkPDF(output.pdf)
    }

    @Test func embeddedStreamIsTheJpegByteForByte() throws {
        let output = try ImagePDF.convert(try fixture("invoice_photo.heic"))
        #expect(output.jpeg.starts(with: [0xFF, 0xD8]))
        #expect(try embeddedJPEG(page(output.pdf)) == output.jpeg)
        #expect(output.pdf.range(of: output.jpeg) != nil)
        let decoded = try #require(CGImageSourceCreateWithData(output.jpeg as CFData, nil))
        let properties = try #require(CGImageSourceCopyPropertiesAtIndex(decoded, 0, nil) as? [CFString: Any])
        #expect(properties[kCGImagePropertyPixelWidth] as? Int == output.image.width)
        #expect(properties[kCGImagePropertyPixelHeight] as? Int == output.image.height)
    }

    @Test(arguments: photos) func heicPngAndJpegInputsConvert(_ name: String) throws {
        let output = try ImagePDF.convert(try fixture(name))
        #expect((output.image.width, output.image.height) == (1190, 1684))
        #expect(try embeddedJPEG(page(output.pdf)) == output.jpeg)
        // Upright: the dark header bar is at the top and the bottom margin is white.
        #expect(rowBrightness(output.image, at: 0.03) < 0.4)
        #expect(rowBrightness(output.image, at: 0.95) > 0.95)
    }

    @Test func exifOrientationIsApplied() throws {
        let data = try fixture("invoice_photo_rotated.jpg")
        // The stored pixels are landscape, turned 90° clockwise, with EXIF orientation 8.
        let source = try #require(CGImageSourceCreateWithData(data as CFData, nil))
        let properties = try #require(CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any])
        #expect(properties[kCGImagePropertyPixelWidth] as? Int == 1684)
        #expect(properties[kCGImagePropertyPixelHeight] as? Int == 1190)
        #expect(properties[kCGImagePropertyOrientation] as? Int == 8)
        let raw = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
        #expect(rowBrightness(raw, at: 0.03) > 0.6)  // no header bar along the top before rotating

        let output = try ImagePDF.convert(data)
        #expect((output.image.width, output.image.height) == (1190, 1684))
        #expect(rowBrightness(output.image, at: 0.03) < 0.4)
        #expect(rowBrightness(output.image, at: 0.95) > 0.95)
        let box = try page(output.pdf).getBoxRect(.mediaBox)
        #expect(box.height > box.width)
        // The embedded JPEG carries no orientation of its own, so viewers can't turn it again.
        let embedded = try #require(CGImageSourceCreateWithData(output.jpeg as CFData, nil))
        let embeddedProperties = CGImageSourceCopyPropertiesAtIndex(embedded, 0, nil) as? [CFString: Any]
        #expect((embeddedProperties?[kCGImagePropertyOrientation] as? Int ?? 1) == 1)
    }

    @Test(arguments: photos) func sameInputGivesSameBytes(_ name: String) throws {
        let data = try fixture(name)
        let first = try ImagePDF.convert(data), second = try ImagePDF.convert(data)
        #expect(first.pdf == second.pdf)
        #expect(DocumentStore.sha256(first.pdf) == DocumentStore.sha256(second.pdf))
        #expect(first.pdf.range(of: Data("CreationDate".utf8)) == nil)
    }

    @Test func longEdgeIsCappedAt3000Pixels() throws {
        let context = try #require(CGContext(data: nil, width: 4000, height: 1000, bitsPerComponent: 8, bytesPerRow: 0,
                                             space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                             bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(CGColor(srgbRed: 0.2, green: 0.4, blue: 0.6, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 4000, height: 1000))
        let png = NSMutableData()
        let destination = try #require(CGImageDestinationCreateWithData(png, "public.png" as CFString, 1, nil))
        CGImageDestinationAddImage(destination, try #require(context.makeImage()), nil)
        #expect(CGImageDestinationFinalize(destination))

        let output = try ImagePDF.convert(png as Data)
        #expect((output.image.width, output.image.height) == (3000, 750))
        let box = try page(output.pdf).getBoxRect(.mediaBox)
        #expect(box.width == 595 && abs(box.height - 148.75) < 0.01)
    }

    @Test func unreadableDataThrows() {
        #expect(throws: ImagePDF.ConversionError.unreadableImage) { try ImagePDF.convert(Data("not an image".utf8)) }
        #expect(throws: ImagePDF.ConversionError.unreadableImage) { try ImagePDF.convert(Data()) }
    }

    // MARK: Fixtures for the extractor

    @Test func invoicePdfFixturesHaveTextAndNoTextLayer() throws {
        let text = try #require(PDFDocument(url: fixtureURL("invoice_text.pdf")))
        let pageText: String = try #require(text.page(at: 0)).string ?? ""
        #expect(pageText.contains("Nordlicht Software GmbH") && pageText.contains("119,00"))
        let scanned = try #require(PDFDocument(url: fixtureURL("invoice_scanned.pdf")))
        #expect(scanned.pageCount == 1)
        let scannedText: String = try #require(scanned.page(at: 0)).string ?? ""
        #expect(scannedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }

    // MARK: Stub extractor

    @Test func stubReturnsCannedResultsByFilenameAndBlankOtherwise() async throws {
        let adobe = ExtractedInvoice(supplier: "Adobe", summary: "Adobe Creative Cloud – Oct 2026",
                                     invoiceDate: "2026-10-01", grossAmount: "59.49", currency: "EUR",
                                     vatLines: [.init(rate: 19, amount: "9.50")], supplierRegion: "European Union",
                                     category: "Software", invoiceNumber: "IE123",
                                     confidence: .init(amount: .high, date: .high, vat: .medium))
        let extractor: any InvoiceExtracting = StubInvoiceExtractor(results: ["adobe.pdf": adobe])
        let pdf = try fixture("invoice_text.pdf")

        #expect(try await extractor.extract(ExtractionInput(document: pdf, filename: "adobe.pdf"), categories: []) == adobe)
        let blank = try await extractor.extract(ExtractionInput(document: pdf, filename: "other.pdf"), categories: [])
        #expect(blank == ExtractedInvoice())
        #expect(blank.supplier.isEmpty && blank.grossAmount.isEmpty && blank.vatLines.isEmpty)
        #expect(try await extractor.extract(ExtractionInput(document: pdf), categories: []) == ExtractedInvoice())

        // The photo path hands the decoded image along with the PDF.
        let photo = try ImagePDF.convert(try fixture("invoice_photo.heic"))
        let input = ExtractionInput(document: photo.pdf, filename: "adobe.pdf", image: photo.image)
        #expect(try await extractor.extract(input, categories: ["Software"]) == adobe)

        let decoded = try JSONDecoder().decode(ExtractedInvoice.self, from: JSONEncoder().encode(adobe))
        #expect(decoded == adobe)
    }
}
