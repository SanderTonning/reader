import Foundation
import SwiftData

@Model
public final class Book {
    @Attribute(.unique) public var id: UUID
    public var title: String
    public var author: String?
    public var formatRaw: String
    public var language: String?
    public var summary: String?

    /// Kilden boken kom fra, for eksempel "gutenberg" eller "librivox". Nil for egne filer.
    public var sourceID: String?
    /// Bokens ID hos kilden, brukt for å unngå duplikater.
    public var sourceItemID: String?
    /// Filnavn i bibliotekmappen når boken er lastet ned eller importert.
    public var fileName: String?
    /// URL for strømming eller nedlasting.
    public var remoteURL: URL?
    public var coverURL: URL?
    public var coverFileName: String?

    public var tracksData: Data?
    public var positionData: Data?

    public var addedAt: Date
    public var lastOpenedAt: Date?
    public var finishedAt: Date?

    @Relationship(deleteRule: .cascade, inverse: \Bookmark.book)
    public var bookmarks: [Bookmark]? = []

    @Relationship(deleteRule: .cascade, inverse: \Highlight.book)
    public var highlights: [Highlight]? = []

    public init(
        id: UUID = UUID(),
        title: String,
        author: String? = nil,
        format: BookFormat,
        language: String? = nil,
        sourceID: String? = nil,
        sourceItemID: String? = nil,
        fileName: String? = nil,
        remoteURL: URL? = nil,
        coverURL: URL? = nil,
        addedAt: Date = .now
    ) {
        self.id = id
        self.title = title
        self.author = author
        self.formatRaw = format.rawValue
        self.language = language
        self.sourceID = sourceID
        self.sourceItemID = sourceItemID
        self.fileName = fileName
        self.remoteURL = remoteURL
        self.coverURL = coverURL
        self.addedAt = addedAt
    }

    public var format: BookFormat {
        get { BookFormat(rawValue: formatRaw) ?? .epub }
        set { formatRaw = newValue.rawValue }
    }

    public var kind: BookKind { format.kind }

    public var position: ReadingPosition? {
        get { ReadingPosition.decode(positionData) }
        set { positionData = newValue?.encoded() }
    }

    public var tracks: [AudioTrack] {
        get {
            guard let tracksData else { return [] }
            return (try? JSONDecoder().decode([AudioTrack].self, from: tracksData)) ?? []
        }
        set { tracksData = try? JSONEncoder().encode(newValue) }
    }

    /// Lokal fil hvis boken er importert eller lastet ned.
    public var localURL: URL? {
        fileName.map { LibraryFolder.books.appendingPathComponent($0) }
    }

    public var isDownloaded: Bool {
        guard let localURL else { return false }
        return FileManager.default.fileExists(atPath: localURL.path)
    }

    /// Lokal fil om den finnes, ellers strømme-URL.
    public var contentURL: URL? {
        isDownloaded ? localURL : remoteURL
    }

    public var sortedBookmarks: [Bookmark] {
        (bookmarks ?? []).sorted { $0.createdAt > $1.createdAt }
    }
}
