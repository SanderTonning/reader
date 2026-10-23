import Foundation

/// Gratis lydbøker fra LibriVox (librivox.org), strømmet fra Internet Archive.
public struct LibriVoxProvider: CatalogProvider {
    public let id = "librivox"
    public let name = "LibriVox (lydbøker)"
    public let supportsSearch = true

    public init() {}

    private func url(_ extra: [URLQueryItem], offset: Int = 0) -> URL {
        var components = URLComponents(string: "https://librivox.org/api/feed/audiobooks/")!
        components.queryItems = [
            URLQueryItem(name: "format", value: "json"),
            URLQueryItem(name: "extended", value: "1"),
            URLQueryItem(name: "limit", value: "25"),
            URLQueryItem(name: "offset", value: String(offset)),
        ] + extra
        return components.url!
    }

    public func start() async throws -> CatalogPage {
        try await page(at: url([URLQueryItem(name: "since", value: "0")]))
    }

    public func search(_ query: String) async throws -> CatalogPage {
        // API-et søker enten på tittel eller forfatter; prøv tittel først, så forfatter.
        let byTitle = try? await page(at: url([URLQueryItem(name: "title", value: "^" + query)]))
        if let byTitle, !byTitle.items.isEmpty { return byTitle }
        let lastName = query.split(separator: " ").last.map(String.init) ?? query
        return (try? await page(at: url([URLQueryItem(name: "author", value: lastName)]))) ?? CatalogPage(items: [])
    }

    public func page(at url: URL) async throws -> CatalogPage {
        let data = try await CatalogHTTP.data(from: url)
        // API-et svarer med {"error": ...} når ingenting er funnet.
        guard let response = try? JSONDecoder().decode(Response.self, from: data) else {
            return CatalogPage(items: [])
        }
        let items = response.books.compactMap(item)
        var next: URL?
        if response.books.count == 25, var components = URLComponents(url: url, resolvingAgainstBaseURL: false) {
            var query = components.queryItems ?? []
            let offset = Int(query.first { $0.name == "offset" }?.value ?? "0") ?? 0
            query.removeAll { $0.name == "offset" }
            query.append(URLQueryItem(name: "offset", value: String(offset + 25)))
            components.queryItems = query
            next = components.url
        }
        return CatalogPage(items: items, nextPage: next)
    }

    struct Response: Decodable {
        var books: [Book]
    }

    struct Book: Decodable {
        struct Author: Decodable { var first_name: String?; var last_name: String? }
        struct Section: Decodable {
            var section_number: String?
            var title: String?
            var listen_url: String?
            var playtime: String?
        }
        var id: String
        var title: String
        var description: String?
        var language: String?
        var totaltime: String?
        var url_iarchive: String?
        var authors: [Author]?
        var sections: [Section]?
    }

    func item(_ book: Book) -> CatalogItem? {
        let tracks: [AudioTrack] = (book.sections ?? []).enumerated().compactMap { index, section in
            guard let listen = section.listen_url, let url = URL(string: listen) else { return nil }
            return AudioTrack(
                index: index,
                title: section.title?.nilIfEmpty ?? "Del \(index + 1)",
                remoteURL: url,
                duration: section.playtime.flatMap(Double.init)
            )
        }
        guard !tracks.isEmpty else { return nil }
        let authors = (book.authors ?? []).map { [$0.first_name, $0.last_name].compactMap { $0 }.joined(separator: " ") }
        let identifier = book.url_iarchive.flatMap { URL(string: $0)?.lastPathComponent }
        return CatalogItem(
            sourceID: id,
            sourceItemID: book.id,
            title: HTMLText.decodeEntities(book.title),
            author: authors.isEmpty ? nil : authors.joined(separator: ", "),
            summary: book.description.map(HTMLText.plainText(from:)),
            language: book.language,
            coverURL: identifier.flatMap { URL(string: "https://archive.org/services/img/\($0)") },
            kind: .audiobook,
            tracks: tracks,
            detail: book.totaltime.map { "Spilletid \($0)" }
        )
    }
}
