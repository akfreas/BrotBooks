import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Turns an invoice photo (HEIC, JPEG, PNG or anything else ImageIO reads) into a one-page PDF that embeds
/// the photo as a JPEG, so every expense document is a PDF.
///
/// The PDF is written by hand rather than through a CoreGraphics PDF context, which could re-encode the
/// image: the JPEG bytes go into a `/DCTDecode` image stream unchanged. The output has no dates or IDs, so
/// the same photo always gives the same bytes and the same SHA-256, which the duplicate check relies on.
public enum ImagePDF {
    /// The long edge of the embedded image is capped at this many pixels.
    public static let maxLongEdge = 3000
    public static let jpegQuality = 0.85
    /// Page width in points (A4); the height follows the photo's aspect ratio.
    public static let pageWidth = 595.0

    public enum ConversionError: Error, LocalizedError, Equatable {
        case unreadableImage
        case encodingFailed

        public var errorDescription: String? {
            switch self {
            case .unreadableImage: "The file isn't an image that can be read."
            case .encodingFailed: "The image couldn't be converted to a PDF."
            }
        }
    }

    public struct Output {
        /// The finished PDF document.
        public let pdf: Data
        /// The JPEG embedded in `pdf`, byte for byte.
        public let jpeg: Data
        /// The decoded photo, upright and capped, kept in memory for extraction.
        public let image: CGImage
    }

    /// Decodes the photo, applies its EXIF orientation, caps the long edge at `maxLongEdge`, encodes it as
    /// JPEG and wraps that in a one-page PDF.
    public static func convert(_ imageData: Data) throws(ConversionError) -> Output {
        let image = try decode(imageData)
        let jpeg = try encodeJPEG(image)
        return Output(pdf: pdf(jpeg: jpeg, width: image.width, height: image.height), jpeg: jpeg, image: image)
    }

    /// The photo upright (EXIF orientation applied), with the long edge capped at `maxLongEdge`, drawn
    /// into 8-bit sRGB on white so transparency, wide-gamut and CMYK inputs all encode as a plain RGB JPEG.
    static func decode(_ data: Data) throws(ConversionError) -> CGImage {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil), CGImageSourceGetCount(source) > 0,
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int, width > 0, height > 0
        else { throw .unreadableImage }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: min(max(width, height), maxLongEdge),
            kCGImageSourceShouldCacheImmediately: true,
        ]
        guard let oriented = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
        else { throw .unreadableImage }

        guard let srgb = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: nil, width: oriented.width, height: oriented.height, bitsPerComponent: 8,
                                      bytesPerRow: 0, space: srgb,
                                      bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)
        else { throw .encodingFailed }
        let rect = CGRect(x: 0, y: 0, width: oriented.width, height: oriented.height)
        context.setFillColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1))
        context.fill(rect)
        context.draw(oriented, in: rect)
        guard let image = context.makeImage() else { throw .encodingFailed }
        return image
    }

    static func encodeJPEG(_ image: CGImage) throws(ConversionError) -> Data {
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output as CFMutableData, UTType.jpeg.identifier as CFString,
                                                                 1, nil)
        else { throw .encodingFailed }
        CGImageDestinationAddImage(destination, image,
                                   [kCGImageDestinationLossyCompressionQuality: jpegQuality] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { throw .encodingFailed }
        return output as Data
    }

    /// A minimal PDF 1.4 with one page showing the RGB JPEG `jpeg` (`width` × `height` pixels) at A4 width:
    /// catalog, pages, page, image XObject (`/DCTDecode`, the JPEG as-is), content stream, xref and trailer.
    public static func pdf(jpeg: Data, width: Int, height: Int) -> Data {
        let pageHeight = number(pageWidth * Double(height) / Double(width))
        let page = number(pageWidth)
        let content = Data("q \(page) 0 0 \(pageHeight) 0 0 cm /Im0 Do Q".utf8)
        let objects: [Data] = [
            Data("<< /Type /Catalog /Pages 2 0 R >>".utf8),
            Data("<< /Type /Pages /Kids [3 0 R] /Count 1 >>".utf8),
            Data(("<< /Type /Page /Parent 2 0 R /MediaBox [0 0 \(page) \(pageHeight)] "
                + "/Resources << /XObject << /Im0 4 0 R >> >> /Contents 5 0 R >>").utf8),
            stream("/Type /XObject /Subtype /Image /Width \(width) /Height \(height) /ColorSpace /DeviceRGB "
                + "/BitsPerComponent 8 /Filter /DCTDecode", jpeg),
            stream("", content),
        ]

        // A binary comment after the header marks the file as binary for transfer tools.
        var out = Data("%PDF-1.4\n%".utf8) + Data([0xE2, 0xE3, 0xCF, 0xD3]) + Data("\n".utf8)
        var offsets: [Int] = []
        for (index, body) in objects.enumerated() {
            offsets.append(out.count)
            out += Data("\(index + 1) 0 obj\n".utf8) + body + Data("\nendobj\n".utf8)
        }
        let xref = out.count
        var tail = "xref\n0 \(objects.count + 1)\n0000000000 65535 f \n"
        for offset in offsets {
            // Each xref entry is exactly 20 bytes: 10-digit offset, space, 5-digit generation, space, n, space, newline.
            tail += String(repeating: "0", count: max(0, 10 - String(offset).count)) + "\(offset) 00000 n \n"
        }
        tail += "trailer\n<< /Size \(objects.count + 1) /Root 1 0 R >>\nstartxref\n\(xref)\n%%EOF\n"
        return out + Data(tail.utf8)
    }

    private static func stream(_ dictionary: String, _ data: Data) -> Data {
        let head = dictionary.isEmpty ? "<< /Length \(data.count) >>" : "<< \(dictionary) /Length \(data.count) >>"
        return Data("\(head)\nstream\n".utf8) + data + Data("\nendstream".utf8)
    }

    /// A PDF number with up to two decimals, independent of locale: 842, 841.89.
    private static func number(_ value: Double) -> String {
        let hundredths = Int((value * 100).rounded())
        let whole = hundredths / 100, fraction = hundredths % 100
        if fraction == 0 { return "\(whole)" }
        let digits = fraction % 10 == 0 ? "\(fraction / 10)" : (fraction < 10 ? "0\(fraction)" : "\(fraction)")
        return "\(whole).\(digits)"
    }
}
