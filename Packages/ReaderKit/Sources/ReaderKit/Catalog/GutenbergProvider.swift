import Foundation

/// Project Gutenberg via det åpne Gutendex-API-et (gutendex.com). Gratis og uten nøkkel.
public struct GutenbergProvider: CatalogProvider {
    public let id = "gutenberg"
    public let name = "Project Gutenberg"
    public let supportsSearch = true
    /// Språkfilter, for eksempel "no" eller "en". Nil gir alle språk.
    public var languages: String?

    public init(languages: String? = nil) { self.languages = languages }

    private var base: URLComponents {
        var components = URLComponents(string: "https://gutendex.com/books/")!
        if let languages { components.queryItems = [URLQueryItem(name: "languages", value: languages)] }
        return components
    }

    public func start() async throws -> CatalogPage {
        try await page(at: base.url!)
    }

    public func search(_ query: String) async throws -> CatalogPage {
        var components = base
        components.queryItems = (components.queryItems ?? []) + [URLQueryItem(name: "search", value: query)]
        return try await page(at: components.url!)
    }

    public func page(at url: URL) async throws -> CatalogPage {
        let data = try await CatalogHTTP.data(from: url)
        let response = try JSONDecoder().decode(Response.self, from: data)
        return CatalogPage(items: response.results.compactMap(item), nextPage: response.next.flatMap(URL.init(string:)))
    }

    struct Response: Decodable {
        var next: String?
        var results: [Book]
    }

    struct Book: Decodable {
        struct Person: Decodable { var name: String }
        var id: Int
        var title: String
        var authors: [Person]
        var languages: [String]
        var formats: [String: String]
        var download_count: Int?
        var summaries: [String]?
    }

    func item(_ book: Book) -> CatalogItem? {
        var acquisitions: [CatalogItem.Acquisition] = []
        if let epub = book.formats.first(where: { $0.key.hasPrefix("application/epub+zip") })?.value, let url = URL(string: epub) {
            acquisitions.append(.init(url: url, format: .epub))
        }
        if let pdf = book.formats["application/pdf"], let url = URL(string: pdf) {
            acquisitions.append(.init(url: url, format: .pdf))
        }
        guard !acquisitions.isEmpty else { return nil }
        // Gutenberg skriver forfattere som "Etternavn, Fornavn".
        let authors = book.authors.map { person -> String in
            let parts = person.name.components(separatedBy: ", ")
            return parts.count == 2 ? "\(parts[1]) \(parts[0])" : person.name
        }
        return CatalogItem(
            sourceID: id,
            sourceItemID: String(book.id),
            title: book.title,
            author: authors.isEmpty ? nil : authors.joined(separator: ", "),
            summary: book.summaries?.first,
            language: book.languages.first,
            coverURL: book.formats["image/jpeg"].flatMap(URL.init(string:)),
            kind: .ebook,
            acquisitions: acquisitions,
            detail: book.download_count.map { "\($0.formatted()) nedlastinger" }
        )
    }
}
