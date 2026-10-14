import Foundation

/// RFC 4180 CSV parsing (quoted fields, doubled quotes, embedded newlines).
public enum CSV {
    public static func parse(_ text: String) -> [[String]] {
        var rows: [[String]] = []
        var row: [String] = []
        var field = ""
        var inQuotes = false
        var chars = text.unicodeScalars.makeIterator()
        var pending: Unicode.Scalar? = nil
        func next() -> Unicode.Scalar? {
            if let p = pending { pending = nil; return p }
            return chars.next()
        }
        var sawAny = false
        while let c = next() {
            sawAny = true
            if inQuotes {
                if c == "\"" {
                    if let n = next() {
                        if n == "\"" { field.unicodeScalars.append("\"") } else { inQuotes = false; pending = n }
                    } else {
                        inQuotes = false
                    }
                } else {
                    field.unicodeScalars.append(c)
                }
            } else if c == "\"" {
                inQuotes = true
            } else if c == "," {
                row.append(field)
                field = ""
            } else if c == "\n" || c == "\r" {
                if c == "\r", let n = next(), n != "\n" { pending = n }
                row.append(field)
                rows.append(row)
                row = []
                field = ""
            } else {
                field.unicodeScalars.append(c)
            }
        }
        if sawAny && (!field.isEmpty || !row.isEmpty) {
            row.append(field)
            rows.append(row)
        }
        return rows
    }

    /// Header → value dictionaries; blank lines are skipped.
    public static func dictionaries(_ text: String) -> (header: [String], rows: [[String: String]]) {
        var all = parse(text)
        guard !all.isEmpty else { return ([], []) }
        let header = all.removeFirst()
        let rows = all.filter { !($0.count == 1 && $0[0].isEmpty) && !$0.isEmpty }.map { values in
            Dictionary(zip(header, values + Array(repeating: "", count: max(0, header.count - values.count))),
                       uniquingKeysWith: { first, _ in first })
        }
        return (header, rows)
    }
}

/// One record parsed from an export CSV.
public struct ExportRecord: Sendable, Equatable {
    public let kind: Kind
    public let sortedRef: String
    public let values: RecordValues
    /// The original CSV row (header → string), untouched.
    public let sourceRow: [String: String]

    public var documentFilename: String? { values["document_filename"]?.text }
}

/// Read-only view of a Sorted "full export" zip.
///
///     expenses/expenses.csv, expenses/documents/<YYYY>/<file>.pdf
///     income/income.csv,     income/documents/<YYYY>/<file>.pdf
///     tax-reports/..., tax-registration/...   (plain archive files)
public struct SortedExport: Sendable {
    public static let archivePrefixes = ["tax-reports/", "tax-registration/"]

    public let archive: ZipArchive

    public init(url: URL) throws {
        do {
            archive = try ZipArchive(url: url)
        } catch is ZipError {
            throw ExportFormatError("Not a zip file: \(url.lastPathComponent)")
        }
    }

    public init(data: Data) throws {
        do {
            archive = try ZipArchive(data: data)
        } catch is ZipError {
            throw ExportFormatError("Not a zip file")
        }
    }

    public func rawRows(_ kind: Kind) throws -> [[String: String]] {
        let name = "\(kind.rawValue)/\(kind.rawValue).csv"
        guard let data = try archive.read(name) else { throw ExportFormatError("\(name) not found in the export") }
        var text = String(decoding: data, as: UTF8.self)
        if text.hasPrefix("\u{FEFF}") { text.removeFirst() }
        let (header, rows) = CSV.dictionaries(text)
        let expected = Columns.headers(kind)
        guard header == expected else {
            throw ExportFormatError("\(name) header changed.\n  expected: \(expected)\n  got:      \(header)")
        }
        return rows
    }

    public func records(_ kind: Kind) throws -> [ExportRecord] {
        var seen = Set<String>()
        return try rawRows(kind).map { row in
            let (values, ref) = try Columns.parseRow(kind, row)
            guard seen.insert(ref).inserted else {
                throw ExportFormatError("\(kind.rawValue): duplicate record suffix '\(ref)'")
            }
            return ExportRecord(kind: kind, sortedRef: ref, values: values, sourceRow: row)
        }
    }

    /// Bytes of a record's document, or nil if the export doesn't include it.
    public func document(_ kind: Kind, filename: String) throws -> Data? {
        try archive.read("\(kind.rawValue)/documents/\(filename)")
    }

    /// Names of non-record files (VAT reports, tax registration) to keep as-is.
    public func archiveFiles() -> [String] {
        archive.names.filter { name in
            !name.hasSuffix("/") && SortedExport.archivePrefixes.contains { name.hasPrefix($0) }
        }.sorted()
    }

    public func read(_ name: String) throws -> Data? {
        try archive.read(name)
    }
}
