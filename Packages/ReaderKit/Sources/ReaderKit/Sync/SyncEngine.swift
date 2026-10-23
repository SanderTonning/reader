import Foundation
import SwiftData

/// Gratis synk mellom enheter via en mappe brukeren velger, for eksempel i iCloud Drive.
/// Krever ingen betalt Apple-konto og ingen server.
@MainActor
public final class SyncEngine: ObservableObject {
    public static let shared = SyncEngine()

    @Published public private(set) var folderName: String?
    @Published public private(set) var lastSync: Date?
    @Published public private(set) var isSyncing = false
    @Published public private(set) var status: String?
    @Published public var shareOwnFiles: Bool {
        didSet { UserDefaults.standard.set(shareOwnFiles, forKey: "sync.shareFiles") }
    }

    private let bookmarkKey = "sync.folderBookmark"
    private let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }()
    private let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    init() {
        shareOwnFiles = UserDefaults.standard.object(forKey: "sync.shareFiles") as? Bool ?? true
        lastSync = UserDefaults.standard.object(forKey: "sync.lastSync") as? Date
        folderName = resolveFolder()?.lastPathComponent
    }

    public var isConfigured: Bool { folderName != nil }

    // MARK: - Mappe

    public func setFolder(_ url: URL) {
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }
        do {
            #if os(macOS)
            // Sikkerhetsbegrensede bokmerker krever en signert app i sandkasse; usignerte utviklerbygg får et vanlig.
            let data = try (try? url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil))
                ?? url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil)
            #else
            let data = try url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil)
            #endif
            UserDefaults.standard.set(data, forKey: bookmarkKey)
            folderName = url.lastPathComponent
            status = nil
        } catch {
            status = "Kunne ikke huske mappen: \(error.localizedDescription)"
        }
    }

    public func clearFolder() {
        UserDefaults.standard.removeObject(forKey: bookmarkKey)
        folderName = nil
    }

    private func resolveFolder() -> URL? {
        guard let data = UserDefaults.standard.data(forKey: bookmarkKey) else { return nil }
        var stale = false
        #if os(macOS)
        let url = (try? URL(resolvingBookmarkData: data, options: .withSecurityScope, relativeTo: nil, bookmarkDataIsStale: &stale))
            ?? (try? URL(resolvingBookmarkData: data, options: [], relativeTo: nil, bookmarkDataIsStale: &stale))
        #else
        let url = try? URL(resolvingBookmarkData: data, options: [], relativeTo: nil, bookmarkDataIsStale: &stale)
        #endif
        if stale, let url { setFolder(url) }
        return url
    }

    // MARK: - Synk

    /// Leser alle enheters filer, slår sammen med det lokale biblioteket og skriver vår egen fil.
    public func sync(context: ModelContext) async {
        guard !isSyncing, let folder = resolveFolder() else { return }
        isSyncing = true
        defer { isSyncing = false }
        let accessing = folder.startAccessingSecurityScopedResource()
        defer { if accessing { folder.stopAccessingSecurityScopedResource() } }

        let root = folder.appendingPathComponent("Reader-synk", isDirectory: true)
        let devices = root.appendingPathComponent("enheter", isDirectory: true)
        let files = root.appendingPathComponent("filer", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: devices, withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: files, withIntermediateDirectories: true)

            let snapshots = readSnapshots(in: devices).filter { $0.deviceID != DeviceInfo.id }
            try await merge(snapshots, files: files, context: context)
            try await shareFiles(to: files, context: context)
            let own = makeSnapshot(context: context, files: files)
            try coordinatedWrite(encoder.encode(own), to: devices.appendingPathComponent("\(DeviceInfo.id).json"))

            lastSync = .now
            UserDefaults.standard.set(lastSync, forKey: "sync.lastSync")
            status = nil
        } catch {
            status = "Synk feilet: \(error.localizedDescription)"
        }
    }

    private func readSnapshots(in folder: URL) -> [SyncSnapshot] {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []
        var result: [SyncSnapshot] = []
        for name in names {
            // Filer som ikke er lastet ned fra iCloud ennå heter ".navn.json.icloud".
            if name.hasSuffix(".icloud") {
                try? FileManager.default.startDownloadingUbiquitousItem(at: folder.appendingPathComponent(name))
                continue
            }
            guard name.hasSuffix(".json"),
                  let data = coordinatedRead(folder.appendingPathComponent(name)),
                  let snapshot = try? decoder.decode(SyncSnapshot.self, from: data) else { continue }
            result.append(snapshot)
        }
        return result
    }

    private func merge(_ snapshots: [SyncSnapshot], files: URL, context: ModelContext) async throws {
        var deletedBooks = SyncTombstones.books
        var deletedBookmarks = SyncTombstones.bookmarks
        for snapshot in snapshots {
            deletedBooks.merge(snapshot.deletedBooks) { max($0, $1) }
            deletedBookmarks.merge(snapshot.deletedBookmarks) { max($0, $1) }
        }
        SyncTombstones.books = deletedBooks
        SyncTombstones.bookmarks = deletedBookmarks

        var books = Dictionary((try context.fetch(FetchDescriptor<Book>())).map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        for (id, book) in books where deletedBooks[id.uuidString] != nil {
            LibraryImporter.removeFiles(of: book)
            context.delete(book)
            books[id] = nil
        }

        for snapshot in snapshots {
            for remote in snapshot.books where deletedBooks[remote.id.uuidString] == nil {
                if let local = books[remote.id] {
                    update(local, from: remote)
                    if !local.isDownloaded, let shared = remote.sharedFile {
                        await fetchFile(shared, for: local, from: files)
                    }
                } else {
                    let book = Book(
                        id: remote.id,
                        title: remote.title,
                        author: remote.author,
                        format: BookFormat(rawValue: remote.format) ?? .epub,
                        language: remote.language,
                        sourceID: remote.sourceID,
                        sourceItemID: remote.sourceItemID,
                        remoteURL: remote.remoteURL,
                        coverURL: remote.coverURL,
                        addedAt: remote.addedAt
                    )
                    book.summary = remote.summary
                    book.tracks = remote.tracks.map { track in
                        var track = track
                        // Lokale spor fra en annen enhet finnes ikke her før filene er hentet.
                        if track.remoteURL == nil { track.fileName = track.fileName.map { "\(remote.id.uuidString)/" + ($0.split(separator: "/").last.map(String.init) ?? $0) } }
                        return track
                    }
                    book.position = remote.position
                    book.lastOpenedAt = remote.lastOpenedAt
                    book.finishedAt = remote.finishedAt
                    context.insert(book)
                    books[remote.id] = book
                    if let cover = remote.sharedCover {
                        let source = files.appendingPathComponent(cover)
                        if let data = coordinatedRead(source) {
                            book.coverFileName = LibraryImporter.saveCover(data: data, bookID: book.id, ext: source.pathExtension)
                        }
                    }
                    if let shared = remote.sharedFile {
                        await fetchFile(shared, for: book, from: files)
                    }
                }
            }
        }

        // Bokmerker: union, minus slettede.
        var bookmarks = Dictionary((try context.fetch(FetchDescriptor<Bookmark>())).map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        for (id, bookmark) in bookmarks where deletedBookmarks[id.uuidString] != nil {
            context.delete(bookmark)
            bookmarks[id] = nil
        }
        for snapshot in snapshots {
            for remote in snapshot.bookmarks where bookmarks[remote.id] == nil && deletedBookmarks[remote.id.uuidString] == nil {
                guard let book = books[remote.bookID] else { continue }
                let bookmark = Bookmark(id: remote.id, label: remote.label, note: remote.note, position: remote.position ?? ReadingPosition(), createdAt: remote.createdAt)
                context.insert(bookmark)
                bookmark.book = book
                bookmarks[remote.id] = bookmark
            }
        }

        // Egne kataloger.
        let sources = Set(try context.fetch(FetchDescriptor<CatalogSource>()).map(\.id))
        var added = sources
        for snapshot in snapshots {
            for remote in snapshot.sources where !added.contains(remote.id) {
                context.insert(CatalogSource(id: remote.id, name: remote.name, url: remote.url, kind: CatalogKind(rawValue: remote.kind) ?? .opds, addedAt: remote.addedAt))
                added.insert(remote.id)
            }
        }
        try context.save()
    }

    /// Nyeste posisjon vinner, uansett enhet.
    private func update(_ local: Book, from remote: SyncBook) {
        if let remotePosition = remote.position {
            if let localPosition = local.position {
                if remotePosition.updatedAt > localPosition.updatedAt { local.position = remotePosition }
            } else {
                local.position = remotePosition
            }
        }
        if let remoteOpened = remote.lastOpenedAt, remoteOpened > (local.lastOpenedAt ?? .distantPast) {
            local.lastOpenedAt = remoteOpened
        }
        if local.finishedAt == nil, let finished = remote.finishedAt { local.finishedAt = finished }
        if local.tracks.isEmpty, !remote.tracks.isEmpty { local.tracks = remote.tracks }
    }

    /// Henter en delt fil fra synkmappen til det lokale biblioteket.
    private func fetchFile(_ shared: String, for book: Book, from files: URL) async {
        let source = files.appendingPathComponent(shared)
        let destinationName = book.format == .audio ? book.id.uuidString : LibraryFolder.uniqueFileName(for: shared)
        let destination = LibraryFolder.books.appendingPathComponent(destinationName)
        let copied = await Task.detached {
            Self.coordinatedCopy(from: source, to: destination)
        }.value
        guard copied else { return }
        book.fileName = destinationName
        if book.format == .audio {
            book.tracks = book.tracks.map { track in
                var track = track
                if let name = track.fileName?.split(separator: "/").last {
                    track.fileName = "\(destinationName)/\(name)"
                }
                return track
            }
        }
    }

    /// Kopierer egne filer (importerte bøker og artikler) til synkmappen, så andre enheter kan hente dem.
    private func shareFiles(to files: URL, context: ModelContext) async throws {
        guard shareOwnFiles else { return }
        for book in try context.fetch(FetchDescriptor<Book>()) where book.isDownloaded && Self.needsSharedFile(book) {
            guard let local = book.localURL else { continue }
            let name = Self.sharedFileName(for: book)
            let destination = files.appendingPathComponent(name)
            if !FileManager.default.fileExists(atPath: destination.path) {
                _ = await Task.detached { Self.coordinatedCopy(from: local, to: destination) }.value
            }
            if let cover = book.coverFileName {
                let coverDestination = files.appendingPathComponent("\(book.id.uuidString)-omslag.\((cover as NSString).pathExtension)")
                if !FileManager.default.fileExists(atPath: coverDestination.path) {
                    _ = Self.coordinatedCopy(from: LibraryFolder.covers.appendingPathComponent(cover), to: coverDestination)
                }
            }
        }
    }

    /// Bøker fra kataloger kan lastes ned på nytt; egne filer og strømmede spor må deles.
    nonisolated static func needsSharedFile(_ book: Book) -> Bool {
        if book.format == .audio { return book.sourceID == nil }
        return book.remoteURL == nil || book.format == .article
    }

    nonisolated static func sharedFileName(for book: Book) -> String {
        if book.format == .audio { return book.id.uuidString }
        let ext = (book.fileName.map { ($0 as NSString).pathExtension }).flatMap { $0.isEmpty ? nil : $0 } ?? book.format.rawValue
        return "\(book.id.uuidString).\(ext)"
    }

    private func makeSnapshot(context: ModelContext, files: URL) -> SyncSnapshot {
        let books = (try? context.fetch(FetchDescriptor<Book>())) ?? []
        let bookmarks = (try? context.fetch(FetchDescriptor<Bookmark>())) ?? []
        let sources = (try? context.fetch(FetchDescriptor<CatalogSource>())) ?? []
        return SyncSnapshot(
            deviceID: DeviceInfo.id,
            deviceName: DeviceInfo.name,
            updatedAt: .now,
            books: books.map { book in
                let sharedName = Self.sharedFileName(for: book)
                let shared = FileManager.default.fileExists(atPath: files.appendingPathComponent(sharedName).path) ? sharedName : nil
                let coverName = book.coverFileName.map { "\(book.id.uuidString)-omslag.\(($0 as NSString).pathExtension)" }
                let cover = coverName.flatMap { FileManager.default.fileExists(atPath: files.appendingPathComponent($0).path) ? $0 : nil }
                return SyncBook(
                    id: book.id, title: book.title, author: book.author, format: book.formatRaw,
                    language: book.language, summary: book.summary, sourceID: book.sourceID,
                    sourceItemID: book.sourceItemID, remoteURL: book.remoteURL, coverURL: book.coverURL,
                    tracks: book.tracks, position: book.position, addedAt: book.addedAt,
                    lastOpenedAt: book.lastOpenedAt, finishedAt: book.finishedAt,
                    sharedFile: shared, sharedCover: cover
                )
            },
            bookmarks: bookmarks.compactMap { bookmark in
                guard let bookID = bookmark.book?.id else { return nil }
                return SyncBookmark(id: bookmark.id, bookID: bookID, label: bookmark.label, note: bookmark.note, position: bookmark.position, createdAt: bookmark.createdAt)
            },
            sources: sources.map { SyncSource(id: $0.id, name: $0.name, url: $0.url, kind: $0.kindRaw, addedAt: $0.addedAt) },
            deletedBooks: SyncTombstones.books,
            deletedBookmarks: SyncTombstones.bookmarks
        )
    }

    // MARK: - Filkoordinering (kreves for iCloud Drive)

    private func coordinatedRead(_ url: URL) -> Data? {
        var result: Data?
        var error: NSError?
        NSFileCoordinator().coordinate(readingItemAt: url, options: [], error: &error) { readURL in
            result = try? Data(contentsOf: readURL)
        }
        return result
    }

    private func coordinatedWrite(_ data: Data, to url: URL) throws {
        var coordinationError: NSError?
        var writeError: Error?
        NSFileCoordinator().coordinate(writingItemAt: url, options: .forReplacing, error: &coordinationError) { writeURL in
            do { try data.write(to: writeURL, options: .atomic) } catch { writeError = error }
        }
        if let error = coordinationError ?? writeError { throw error }
    }

    nonisolated static func coordinatedCopy(from source: URL, to destination: URL) -> Bool {
        var success = false
        var error: NSError?
        let coordinator = NSFileCoordinator()
        coordinator.coordinate(readingItemAt: source, options: [], writingItemAt: destination, options: .forReplacing, error: &error) { readURL, writeURL in
            try? FileManager.default.removeItem(at: writeURL)
            success = (try? FileManager.default.copyItem(at: readURL, to: writeURL)) != nil
        }
        return success
    }
}
