import Foundation

/// En bok i en ekstern katalog, før den er lagt til i biblioteket.
public struct CatalogItem: Identifiable, Hashable, Sendable {
    public struct Acquisition: Hashable, Sendable {
        public var url: URL
        public var format: BookFormat
    }

    public var id: String { "\(sourceID):\(sourceItemID)" }
    public var sourceID: String
    public var sourceItemID: String
    public var title: String
    public var author: String?
    public var summary: String?
    public var language: String?
    public var coverURL: URL?
    public var kind: BookKind
    public var acquisitions: [Acquisition]
    public var tracks: [AudioTrack]
    /// Lenke til en underkatalog (OPDS-navigasjon) i stedet for en bok.
    public var navigationURL: URL?
    public var detail: String?

    public init(
        sourceID: String,
        sourceItemID: String,
        title: String,
        author: String? = nil,
        summary: String? = nil,
        language: String? = nil,
        coverURL: URL? = nil,
        kind: BookKind = .ebook,
        acquisitions: [Acquisition] = [],
        tracks: [AudioTrack] = [],
        navigationURL: URL? = nil,
        detail: String? = nil
    ) {
        self.sourceID = sourceID
        self.sourceItemID = sourceItemID
        self.title = title
        self.author = author
        self.summary = summary
        self.language = language
        self.coverURL = coverURL
        self.kind = kind
        self.acquisitions = acquisitions
        self.tracks = tracks
        self.navigationURL = navigationURL
        self.detail = detail
    }

    public var isNavigation: Bool { navigationURL != nil && acquisitions.isEmpty && tracks.isEmpty }

    /// Beste nedlasting: EPUB før PDF.
    public var preferredAcquisition: Acquisition? {
        acquisitions.first { $0.format == .epub } ?? acquisitions.first
    }
}

public struct CatalogPage: Sendable {
    public var items: [CatalogItem]
    public var nextPage: URL?
    public var title: String?

    public init(items: [CatalogItem], nextPage: URL? = nil, title: String? = nil) {
        self.items = items
        self.nextPage = nextPage
        self.title = title
    }
}

public protocol CatalogProvider: Sendable {
    var id: String { get }
    var name: String { get }
    var supportsSearch: Bool { get }
    /// Startsiden for katalogen (populære bøker eller rotnivået i OPDS).
    func start() async throws -> CatalogPage
    func search(_ query: String) async throws -> CatalogPage
    func page(at url: URL) async throws -> CatalogPage
}

enum CatalogHTTP {
    static let session: URLSession = {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 30
        configuration.httpAdditionalHeaders = ["User-Agent": "Reader/0.1 (hobby e-reader; github.com/SanderTonning/reader)"]
        return URLSession(configuration: configuration)
    }()

    static func data(from url: URL) async throws -> Data {
        let (data, response) = try await session.data(from: url)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw URLError(.badServerResponse)
        }
        return data
    }
}
