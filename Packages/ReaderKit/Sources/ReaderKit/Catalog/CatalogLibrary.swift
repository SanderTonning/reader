import Foundation
import SwiftData

/// Kildene appen kan bla i: innebygde åpne kilder pluss OPDS-kataloger brukeren har lagt til.
public enum CatalogDirectory {
    public static func builtIn() -> [any CatalogProvider] {
        [
            GutenbergProvider(),
            GutenbergProvider(languages: "no").renamed("Gutenberg – norske bøker", id: "gutenberg-no"),
            LibriVoxProvider(),
        ]
    }

    public static func provider(for source: CatalogSource) -> any CatalogProvider {
        OPDSProvider(id: "opds-\(source.id.uuidString)", name: source.name, rootURL: source.url)
    }
}

/// Gir en innebygd kilde et eget navn (for eksempel et språkfiltrert utvalg).
struct RenamedProvider: CatalogProvider {
    let base: any CatalogProvider
    let id: String
    let name: String
    var supportsSearch: Bool { base.supportsSearch }
    func start() async throws -> CatalogPage { try await base.start() }
    func search(_ query: String) async throws -> CatalogPage { try await base.search(query) }
    func page(at url: URL) async throws -> CatalogPage { try await base.page(at: url) }
}

extension CatalogProvider {
    func renamed(_ name: String, id: String) -> any CatalogProvider {
        RenamedProvider(base: self, id: id, name: name)
    }
}

/// Legger katalogbøker til i biblioteket: laster ned e-bøker, og lagrer lydbøker for strømming.
@MainActor
public enum CatalogImporter {
    public static func existingBook(for item: CatalogItem, in context: ModelContext) -> Book? {
        let sourceID: String? = canonicalSourceID(item.sourceID)
        let itemID: String? = item.sourceItemID
        let descriptor = FetchDescriptor<Book>(predicate: #Predicate { $0.sourceID == sourceID && $0.sourceItemID == itemID })
        return try? context.fetch(descriptor).first
    }

    /// Gutenberg med språkfilter er samme kilde som Gutenberg.
    static func canonicalSourceID(_ id: String) -> String {
        id.hasPrefix("gutenberg") ? "gutenberg" : id
    }

    public static func add(_ item: CatalogItem, into context: ModelContext) async throws -> Book {
        if let existing = existingBook(for: item, in: context) { return existing }
        let sourceID = canonicalSourceID(item.sourceID)

        if item.kind == .audiobook {
            let book = Book(title: item.title, author: item.author, format: .audio, language: item.language, sourceID: sourceID, sourceItemID: item.sourceItemID, coverURL: item.coverURL)
            book.summary = item.summary
            book.tracks = item.tracks
            context.insert(book)
            try? context.save()
            return book
        }

        guard let acquisition = item.preferredAcquisition else { throw URLError(.fileDoesNotExist) }
        let book = Book(title: item.title, author: item.author, format: acquisition.format, language: item.language, sourceID: sourceID, sourceItemID: item.sourceItemID, remoteURL: acquisition.url, coverURL: item.coverURL)
        book.summary = item.summary
        try await download(book)
        context.insert(book)
        try? context.save()
        return book
    }

    /// Laster ned filen til en e-bok (for eksempel på en ny enhet etter synk).
    public static func download(_ book: Book) async throws {
        guard let remoteURL = book.remoteURL else { throw URLError(.badURL) }
        let (temporary, response) = try await CatalogHTTP.session.download(from: remoteURL)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw URLError(.badServerResponse)
        }
        let ext = book.format == .pdf ? "pdf" : "epub"
        let safeTitle = book.title.components(separatedBy: CharacterSet(charactersIn: "/\\:?*\"<>|")).joined(separator: "-").prefix(80)
        let fileName = book.fileName ?? LibraryFolder.uniqueFileName(for: "\(safeTitle).\(ext)")
        let destination = LibraryFolder.books.appendingPathComponent(fileName)
        try? FileManager.default.removeItem(at: destination)
        try FileManager.default.moveItem(at: temporary, to: destination)
        book.fileName = fileName

        if book.format == .epub, let publication = try? EPUBPublication.open(epubAt: destination, bookID: book.id) {
            if book.language == nil { book.language = publication.language }
            if let cover = publication.coverURL, book.coverFileName == nil {
                book.coverFileName = LibraryImporter.saveCover(from: cover, bookID: book.id)
            }
        }
    }

    /// Laster ned alle spor i en strømmet lydbok, så den kan spilles uten nett.
    public static func downloadAudio(_ book: Book, progress: @escaping (Double) -> Void) async throws {
        var tracks = book.tracks
        let folder = book.fileName ?? LibraryFolder.uniqueFileName(for: "lydbok-\(book.id.uuidString.prefix(8))")
        let directory = LibraryFolder.ensure(LibraryFolder.books.appendingPathComponent(folder, isDirectory: true))
        for index in tracks.indices {
            guard let remote = tracks[index].remoteURL else { continue }
            let name = String(format: "%03d.%@", index + 1, remote.pathExtension.isEmpty ? "mp3" : remote.pathExtension)
            let destination = directory.appendingPathComponent(name)
            if !FileManager.default.fileExists(atPath: destination.path) {
                let (temporary, _) = try await CatalogHTTP.session.download(from: remote)
                try FileManager.default.moveItem(at: temporary, to: destination)
            }
            tracks[index].fileName = "\(folder)/\(name)"
            progress(Double(index + 1) / Double(tracks.count))
        }
        book.fileName = folder
        book.tracks = tracks
    }
}
