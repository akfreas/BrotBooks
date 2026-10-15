import Foundation

/// A small read-only XML tree (element names without namespace prefixes, trimmed text), for the return
/// documents of ERiC and the ELSTER server answer.
struct XMLNode: Sendable, Equatable {
    var name: String
    var text: String
    var children: [XMLNode]

    /// Parses `xml`; nil when it is not well-formed.
    static func parse(_ xml: String) -> XMLNode? {
        let builder = Builder()
        let parser = XMLParser(data: Data(xml.utf8))
        parser.delegate = builder
        guard parser.parse(), let root = builder.root else { return nil }
        return root
    }

    /// The first child named `name`.
    func child(_ name: String) -> XMLNode? { children.first { $0.name == name } }

    /// The children named `name`.
    func all(_ name: String) -> [XMLNode] { children.filter { $0.name == name } }

    /// The node at `path` below this one, e.g. `["TransferHeader", "RC", "Rueckgabe"]`.
    func at(_ path: [String]) -> XMLNode? {
        path.reduce(Optional(self)) { node, name in node?.child(name) }
    }

    /// Every descendant (depth first, this node excluded) named `name`.
    func descendants(_ name: String) -> [XMLNode] {
        children.flatMap { ($0.name == name ? [$0] : []) + $0.descendants(name) }
    }

    private final class Builder: NSObject, XMLParserDelegate {
        var root: XMLNode?
        private var stack: [XMLNode] = []

        func parser(_ parser: XMLParser, didStartElement element: String, namespaceURI: String?,
                    qualifiedName: String?, attributes: [String: String] = [:]) {
            let local = element.split(separator: ":").last.map(String.init) ?? element
            stack.append(XMLNode(name: local, text: "", children: []))
        }

        func parser(_ parser: XMLParser, foundCharacters string: String) {
            guard !stack.isEmpty else { return }
            stack[stack.count - 1].text += string
        }

        func parser(_ parser: XMLParser, didEndElement element: String, namespaceURI: String?, qualifiedName: String?) {
            guard var node = stack.popLast() else { return }
            node.text = node.text.trimmingCharacters(in: .whitespacesAndNewlines)
            if stack.isEmpty { root = node } else { stack[stack.count - 1].children.append(node) }
        }
    }
}
