import Compression
import Foundation

public struct ZipError: Error, Equatable, LocalizedError, Sendable {
    public let message: String
    public init(_ message: String) { self.message = message }
    public var errorDescription: String? { message }
}

/// Minimal read-only ZIP reader: central directory + stored and DEFLATE entries, inflated with the
/// Compression framework. Enough for Sorted's export zips (no ZIP64, no encryption).
public struct ZipArchive: Sendable {
    public struct Entry: Sendable, Equatable {
        public let name: String
        public let method: UInt16
        public let compressedSize: Int
        public let uncompressedSize: Int
        public let crc32: UInt32
        let localHeaderOffset: Int

        public var isDirectory: Bool { name.hasSuffix("/") }
    }

    private let data: Data
    public let entries: [Entry]
    private let index: [String: Int]

    public init(url: URL) throws {
        try self.init(data: Data(contentsOf: url, options: .mappedIfSafe))
    }

    public init(data: Data) throws {
        self.data = data
        entries = try ZipArchive.readCentralDirectory(data)
        var index: [String: Int] = [:]
        for (i, e) in entries.enumerated() { index[e.name] = i }
        self.index = index
    }

    public var names: [String] { entries.map(\.name) }

    public func contains(_ name: String) -> Bool { index[name] != nil }

    /// The entry's uncompressed bytes, or nil when the archive has no such entry.
    public func read(_ name: String) throws -> Data? {
        guard let i = index[name] else { return nil }
        return try read(entries[i])
    }

    public func read(_ entry: Entry) throws -> Data {
        let base = data.startIndex
        let off = entry.localHeaderOffset
        guard off + 30 <= data.count, data.u32(base + off) == 0x0403_4b50 else {
            throw ZipError("Bad local header for \(entry.name)")
        }
        let nameLength = Int(data.u16(base + off + 26))
        let extraLength = Int(data.u16(base + off + 28))
        let start = off + 30 + nameLength + extraLength
        guard start + entry.compressedSize <= data.count else { throw ZipError("Truncated entry \(entry.name)") }
        let payload = data.subdata(in: (base + start)..<(base + start + entry.compressedSize))
        let output: Data
        switch entry.method {
        case 0:
            output = payload
        case 8:
            output = try ZipArchive.inflate(payload, expectedSize: entry.uncompressedSize)
        default:
            throw ZipError("Unsupported compression method \(entry.method) for \(entry.name)")
        }
        guard output.count == entry.uncompressedSize else { throw ZipError("Size mismatch for \(entry.name)") }
        guard CRC32.checksum(output) == entry.crc32 else { throw ZipError("CRC mismatch for \(entry.name)") }
        return output
    }

    /// Raw DEFLATE (RFC 1951), which is what `COMPRESSION_ZLIB` decodes.
    static func inflate(_ input: Data, expectedSize: Int) throws -> Data {
        if expectedSize == 0 { return Data() }
        var output = Data(count: expectedSize)
        let written = output.withUnsafeMutableBytes { (dst: UnsafeMutableRawBufferPointer) -> Int in
            input.withUnsafeBytes { (src: UnsafeRawBufferPointer) -> Int in
                compression_decode_buffer(
                    dst.bindMemory(to: UInt8.self).baseAddress!, expectedSize,
                    src.bindMemory(to: UInt8.self).baseAddress!, input.count,
                    nil, COMPRESSION_ZLIB)
            }
        }
        guard written == expectedSize else { throw ZipError("Inflate failed (\(written) of \(expectedSize) bytes)") }
        return output
    }

    static func readCentralDirectory(_ data: Data) throws -> [Entry] {
        let base = data.startIndex
        // End of central directory: signature, then up to 64 KiB of comment.
        guard data.count >= 22 else { throw ZipError("Not a zip file") }
        var eocd = -1
        let lowest = max(0, data.count - 22 - 0xFFFF)
        var i = data.count - 22
        while i >= lowest {
            if data.u32(base + i) == 0x0605_4b50 { eocd = i; break }
            i -= 1
        }
        guard eocd >= 0 else { throw ZipError("Not a zip file") }
        let count = Int(data.u16(base + eocd + 10))
        let cdOffset = Int(data.u32(base + eocd + 16))
        if count == 0xFFFF || cdOffset == 0xFFFF_FFFF { throw ZipError("ZIP64 archives are not supported") }
        var entries: [Entry] = []
        var p = cdOffset
        for _ in 0..<count {
            guard p + 46 <= data.count, data.u32(base + p) == 0x0201_4b50 else {
                throw ZipError("Bad central directory")
            }
            let flags = data.u16(base + p + 8)
            let method = data.u16(base + p + 10)
            let crc = data.u32(base + p + 16)
            let compressed = Int(data.u32(base + p + 20))
            let uncompressed = Int(data.u32(base + p + 24))
            let nameLength = Int(data.u16(base + p + 28))
            let extraLength = Int(data.u16(base + p + 30))
            let commentLength = Int(data.u16(base + p + 32))
            let localOffset = Int(data.u32(base + p + 42))
            guard p + 46 + nameLength <= data.count else { throw ZipError("Bad central directory") }
            let nameData = data.subdata(in: (base + p + 46)..<(base + p + 46 + nameLength))
            // Bit 11: UTF-8 names. Otherwise CP437; UTF-8 is still the best guess for modern zips.
            let name = String(data: nameData, encoding: .utf8)
                ?? String(data: nameData, encoding: flags & 0x800 != 0 ? .utf8 : .isoLatin1) ?? ""
            if flags & 0x1 != 0 { throw ZipError("Encrypted entries are not supported: \(name)") }
            entries.append(Entry(name: name, method: method, compressedSize: compressed,
                                 uncompressedSize: uncompressed, crc32: crc, localHeaderOffset: localOffset))
            p += 46 + nameLength + extraLength + commentLength
        }
        return entries
    }
}

enum CRC32 {
    static let table: [UInt32] = (0..<256).map { n -> UInt32 in
        var c = UInt32(n)
        for _ in 0..<8 { c = c & 1 != 0 ? 0xEDB8_8320 ^ (c >> 1) : c >> 1 }
        return c
    }

    static func checksum(_ data: Data) -> UInt32 {
        var crc: UInt32 = 0xFFFF_FFFF
        data.withUnsafeBytes { (buf: UnsafeRawBufferPointer) in
            for byte in buf { crc = table[Int((crc ^ UInt32(byte)) & 0xFF)] ^ (crc >> 8) }
        }
        return crc ^ 0xFFFF_FFFF
    }
}

extension Data {
    func u16(_ i: Int) -> UInt16 { UInt16(self[i]) | UInt16(self[i + 1]) << 8 }
    func u32(_ i: Int) -> UInt32 { UInt32(u16(i)) | UInt32(u16(i + 2)) << 16 }
}
