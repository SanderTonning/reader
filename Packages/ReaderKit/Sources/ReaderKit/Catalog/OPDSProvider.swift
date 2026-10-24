import Foundation

/// OPDS 1.x-katalog (Atom), for eksempel Project Gutenberg, Calibre-server eller andre åpne bibliotek.
public struct OPDSProvider: CatalogProvider {
    public let id: String
    public let name: String
    public let rootURL: URL
    public var supportsSearch: Bool { true }

    public init(id: String, name: String, rootURL: URL) {
        self.id = id
        self.name = name
        self.rootURL = rootURL
    }

    public func start() async throws -> CatalogPage {
        try await page(at: rootURL)
    }

    public func search(_ query: String) async throws -> CatalogPage {
        let root = try await feed(at: rootURL)
        guard let template = try await searchTemplate(in: root) else {
            // Ingen søk i katalogen: filtrer startsiden lokalt.
            let start = try await page(at: rootURL)
            return CatalogPage(items: start.items.filter { $0.title.localizedCaseInsensitiveContains(query) || ($0.author ?? "").localizedCaseInsensitiveContains(query) })
        }
        let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? query
        let urlString = template
            .replacingOccurrences(of: "{searchTerms}", with: encoded)
            .replacingOccurrences(of: "{startPage?}", with: "1")
            .replacingOccurrences(of: "{count?}", with: "25")
        guard let url = URL(string: urlString, relativeTo: rootURL)?.absoluteURL else { return CatalogPage(items: []) }
        return try await page(at: url)
    }

    public func page(at url: URL) async throws -> CatalogPage {
        let tree = try await feed(at: url)
        return Self.parse(tree, baseURL: url, sourceID: id)
    }

    private func feed(at url: URL) async throws -> XMLTree {
        let data = try await CatalogHTTP.data(from: url)
        guard let tree = XMLTree.parse(data) else { throw URLError(.cannotParseResponse) }
        return tree
    }

    /// Finner søkemal: direkte Atom-mal, eller via et OpenSearch-beskrivelsesdokument.
    private func searchTemplate(in feed: XMLTree) async throws -> String? {
        let links = feed.all("link").filter { $0.attribute("rel") == "search" }
        if let direct = links.first(where: { ($0.attribute("href") ?? "").contains("{searchTerms}") })?.attribute("href") {
            return URL(string: direct, relativeTo: rootURL)?.absoluteString.removingPercentEncoding ?? direct
        }
        guard let descriptionHref = links.first?.attribute("href"),
              let descriptionURL = URL(string: descriptionHref, relativeTo: rootURL)?.absoluteURL,
              let data = try? await CatalogHTTP.data(from: descriptionURL),
              let description = XMLTree.parse(data) else { return nil }
        let urls = description.all("Url")
        let atom = urls.first { ($0.attribute("type") ?? "").contains("atom") } ?? urls.first
        guard let template = atom?.attribute("template") else { return nil }
        return URL(string: template, relativeTo: descriptionURL)?.absoluteString.removingPercentEncoding ?? template
    }

    static func parse(_ feed: XMLTree, baseURL: URL, sourceID: String) -> CatalogPage {
        func resolve(_ href: String?) -> URL? {
            href.flatMap { URL(string: $0, relativeTo: baseURL)?.absoluteURL }
        }
        let items: [CatalogItem] = feed.all("entry").compactMap { entry in
            let title = entry.first("title")?.allText ?? "Uten tittel"
            let id = entry.first("id")?.allText ?? title
            let authors = entry.all("author").compactMap { $0.first("name")?.allText }.filter { !$0.isEmpty }
            let summary = entry.first("summary")?.allText ?? entry.first("content").map { HTMLText.plainText(from: $0.allText) }
            let links = entry.all("link")

            var acquisitions: [CatalogItem.Acquisition] = []
            var cover: URL?
            var navigation: URL?
            for link in links {
                let rel = link.attribute("rel") ?? ""
                let type = link.attribute("type") ?? ""
                if rel.contains("acquisition") {
                    if type.contains("epub"), let url = resolve(link.attribute("href")) {
                        acquisitions.append(.init(url: url, format: .epub))
                    } else if type.contains("pdf"), let url = resolve(link.attribute("href")) {
                        acquisitions.append(.init(url: url, format: .pdf))
                    }
                } else if rel == "http://opds-spec.org/image" || (rel.contains("image") && !rel.contains("thumbnail") && cover == nil) {
                    cover = resolve(link.attribute("href"))
                } else if rel.contains("thumbnail"), cover == nil {
                    cover = resolve(link.attribute("href"))
                } else if type.contains("opds-catalog") || type.contains("atom+xml") {
                    if rel.isEmpty || rel == "subsection" || rel.contains("opds-spec.org/sort") || rel == "related" || rel == "alternate" || rel == "start" {
                        if navigation == nil, rel != "start" { navigation = resolve(link.attribute("href")) }
                    }
                }
            }
            if acquisitions.isEmpty && navigation == nil { return nil }
            return CatalogItem(
                sourceID: sourceID,
                sourceItemID: id,
                title: title,
                author: authors.isEmpty ? nil : authors.joined(separator: ", "),
                summary: summary,
                language: entry.first("language")?.allText,
                coverURL: cover,
                kind: .ebook,
                acquisitions: acquisitions,
                navigationURL: acquisitions.isEmpty ? navigation : nil
            )
        }
        let next = feed.all("link").first { $0.attribute("rel") == "next" }?.attribute("href").flatMap(resolve)
        return CatalogPage(items: items, nextPage: next, title: feed.first("title")?.allText)
    }
}
