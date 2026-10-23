import Foundation

/// Et lite XML-tre bygget med XMLParser, siden XMLDocument ikke finnes på iOS.
final class XMLTree {
    let name: String
    let attributes: [String: String]
    var children: [XMLTree] = []
    var text = ""
    weak var parent: XMLTree?

    init(name: String, attributes: [String: String]) {
        self.name = name
        self.attributes = attributes
    }

    /// Navn uten navnerom-prefiks, for eksempel "title" for "dc:title".
    var localName: String {
        name.split(separator: ":").last.map(String.init) ?? name
    }

    /// All tekst i noden og barna.
    var allText: String {
        (text + children.map(\.allText).joined()).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func attribute(_ key: String) -> String? {
        if let value = attributes[key] { return value }
        return attributes.first { $0.key.split(separator: ":").last.map(String.init) == key }?.value
    }

    func first(_ localName: String) -> XMLTree? {
        children.first { $0.localName == localName }
    }

    func all(_ localName: String) -> [XMLTree] {
        children.filter { $0.localName == localName }
    }

    /// Alle etterkommere med gitt navn, i dokumentrekkefølge.
    func descendants(_ localName: String) -> [XMLTree] {
        var result: [XMLTree] = []
        for child in children {
            if child.localName == localName { result.append(child) }
            result += child.descendants(localName)
        }
        return result
    }

    static func parse(_ data: Data) -> XMLTree? {
        let builder = Builder()
        let parser = XMLParser(data: data)
        parser.delegate = builder
        parser.shouldProcessNamespaces = false
        parser.shouldResolveExternalEntities = false
        guard parser.parse() || builder.root != nil else { return nil }
        return builder.root
    }

    private final class Builder: NSObject, XMLParserDelegate {
        var root: XMLTree?
        private var stack: [XMLTree] = []

        func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]) {
            let node = XMLTree(name: elementName, attributes: attributeDict)
            if let parent = stack.last {
                node.parent = parent
                parent.children.append(node)
            } else {
                root = node
            }
            stack.append(node)
        }

        func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
            _ = stack.popLast()
        }

        func parser(_ parser: XMLParser, foundCharacters string: String) {
            stack.last?.text += string
        }
    }
}
