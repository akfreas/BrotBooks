import Foundation

/// What `EricMtVersion` reports (schema `EricVersion.xsd`): every loaded ERiC library and plugin with its versions.
public struct EricVersionInfo: Sendable, Equatable {
    public struct Library: Sendable, Equatable {
        /// File name as ERiC reports it, lowercased, e.g. `libcheckustva_2026.dylib`.
        public var name: String
        /// Dotted product version, e.g. `44.3.4.0`.
        public var productVersion: String
        /// Dotted file version, e.g. `2026.44.3.4`.
        public var fileVersion: String
    }

    /// Version of the ERiC package (the jar, e.g. `44.3.6.0`) from the vendored `VERSION` file. ERiC itself only
    /// reports its API version, which can lag behind the package version.
    public var packageVersion: String?
    public var libraries: [Library]

    /// Product version of libericapi.dylib, e.g. `44.3.4.0`.
    public var apiVersion: String? {
        libraries.first { $0.name == "libericapi.dylib" }?.productVersion
    }

    /// The package version if known, else the API version.
    public var displayVersion: String? { packageVersion ?? apiVersion }

    /// Years of the loaded `libcheckUStVA_<year>` plugins, ascending.
    public var ustvaPluginYears: [Int] {
        libraries.compactMap { library -> Int? in
            guard let match = library.name.wholeMatch(of: /libcheckustva_(\d{4})\.dylib/) else { return nil }
            return Int(match.1)
        }.sorted()
    }

    public init(packageVersion: String?, libraries: [Library]) {
        self.packageVersion = packageVersion
        self.libraries = libraries
    }

    /// Parses the `EricVersion` XML. Returns nil if it is not well-formed.
    public init?(xml: String, packageVersion: String?) {
        let reader = VersionXMLReader()
        let parser = XMLParser(data: Data(xml.utf8))
        parser.delegate = reader
        guard parser.parse() else { return nil }
        self.init(packageVersion: packageVersion, libraries: reader.libraries)
    }
}

private final class VersionXMLReader: NSObject, XMLParserDelegate {
    var libraries: [EricVersionInfo.Library] = []
    private var current: [String: String]?
    private var text = ""

    func parser(_ parser: XMLParser, didStartElement element: String, namespaceURI: String?,
                qualifiedName: String?, attributes: [String: String] = [:]) {
        if element == "Bibliothek" { current = [:] }
        text = ""
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        text += string
    }

    func parser(_ parser: XMLParser, didEndElement element: String, namespaceURI: String?, qualifiedName: String?) {
        if element == "Bibliothek", let fields = current {
            libraries.append(.init(name: (fields["Name"] ?? "").lowercased(),
                                   productVersion: Self.dotted(fields["Produktversion"]),
                                   fileVersion: Self.dotted(fields["Dateiversion"])))
            current = nil
        } else if current != nil {
            current?[element] = text.trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }

    /// ERiC writes versions as `44, 3, 4, 0`.
    private static func dotted(_ version: String?) -> String {
        (version ?? "").split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.joined(separator: ".")
    }
}
