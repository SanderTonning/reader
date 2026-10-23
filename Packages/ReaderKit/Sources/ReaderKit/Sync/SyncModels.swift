import Foundation

/// Alt én enhet vet om biblioteket, skrevet som JSON til synkmappen.
/// Hver enhet skriver bare sin egen fil, så to enheter aldri skriver til samme fil.
struct SyncSnapshot: Codable {
    var version = 1
    var deviceID: String
    var deviceName: String
    var updatedAt: Date
    var books: [SyncBook]
    var bookmarks: [SyncBookmark]
    var sources: [SyncSource]
    var deletedBooks: [String: Date]
    var deletedBookmarks: [String: Date]
}

struct SyncBook: Codable {
    var id: UUID
    var title: String
    var author: String?
    var format: String
    var language: String?
    var summary: String?
    var sourceID: String?
    var sourceItemID: String?
    var remoteURL: URL?
    var coverURL: URL?
    var tracks: [AudioTrack]
    var position: ReadingPosition?
    var addedAt: Date
    var lastOpenedAt: Date?
    var finishedAt: Date?
    /// Navnet på bokens fil i synkmappen (files/), hvis filen er delt.
    var sharedFile: String?
    var sharedCover: String?
}

struct SyncBookmark: Codable {
    var id: UUID
    var bookID: UUID
    var label: String
    var note: String?
    var position: ReadingPosition?
    var createdAt: Date
}

struct SyncSource: Codable {
    var id: UUID
    var name: String
    var url: URL
    var kind: String
    var addedAt: Date
}

/// Husker hva som er slettet lokalt, så slettingen spres til andre enheter.
public enum SyncTombstones {
    private static let booksKey = "sync.deletedBooks"
    private static let bookmarksKey = "sync.deletedBookmarks"

    static var books: [String: Date] {
        get { load(booksKey) }
        set { save(newValue, booksKey) }
    }

    static var bookmarks: [String: Date] {
        get { load(bookmarksKey) }
        set { save(newValue, bookmarksKey) }
    }

    public static func recordBook(_ id: UUID) { books[id.uuidString] = .now }
    public static func recordBookmark(_ id: UUID) { bookmarks[id.uuidString] = .now }

    private static func load(_ key: String) -> [String: Date] {
        guard let data = UserDefaults.standard.data(forKey: key) else { return [:] }
        return (try? JSONDecoder().decode([String: Date].self, from: data)) ?? [:]
    }

    private static func save(_ value: [String: Date], _ key: String) {
        UserDefaults.standard.set(try? JSONEncoder().encode(value), forKey: key)
    }
}
