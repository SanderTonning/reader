import AVFoundation
import Foundation
import PDFKit
import SwiftData
import UniformTypeIdentifiers
#if os(macOS)
import AppKit
#endif

/// Importerer egne filer (EPUB, PDF, lyd, HTML/tekst) til biblioteket.
@MainActor
public enum LibraryImporter {
    public static let supportedTypes: [UTType] = [.epub, .pdf, .audio, .mp3, .mpeg4Audio, .html, .plainText]

    public struct Result {
        public var added: [Book] = []
        public var failed: [(name: String, error: Error)] = []
    }

    /// Importerer valgte filer. Flere lydfiler valgt samtidig blir én lydbok med flere spor.
    @discardableResult
    public static func importFiles(_ urls: [URL], into context: ModelContext) async -> Result {
        var result = Result()
        let audio = urls.filter { BookFormat(fileExtension: $0.pathExtension) == .audio }
        let others = urls.filter { BookFormat(fileExtension: $0.pathExtension) != .audio }

        for url in others {
            do {
                result.added.append(try await importSingle(url, into: context))
            } catch {
                result.failed.append((url.lastPathComponent, error))
            }
        }
        if !audio.isEmpty {
            do {
                result.added.append(try await importAudiobook(audio, into: context))
            } catch {
                result.failed.append((audio[0].lastPathComponent, error))
            }
        }
        try? context.save()
        return result
    }

    static func copyIntoLibrary(_ url: URL, subfolder: String? = nil) throws -> String {
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }
        var folder = LibraryFolder.books
        var prefix = ""
        if let subfolder {
            folder = LibraryFolder.ensure(folder.appendingPathComponent(subfolder, isDirectory: true))
            prefix = subfolder + "/"
        }
        let name = subfolder == nil ? LibraryFolder.uniqueFileName(for: url.lastPathComponent) : url.lastPathComponent
        let destination = folder.appendingPathComponent(name)
        if FileManager.default.fileExists(atPath: destination.path) {
            try FileManager.default.removeItem(at: destination)
        }
        try FileManager.default.copyItem(at: url, to: destination)
        return prefix + name
    }

    static func importSingle(_ url: URL, into context: ModelContext) async throws -> Book {
        guard let format = BookFormat(fileExtension: url.pathExtension) else {
            throw CocoaError(.fileReadUnsupportedScheme)
        }
        let fileName = try copyIntoLibrary(url)
        let localURL = LibraryFolder.books.appendingPathComponent(fileName)
        let fallbackTitle = url.deletingPathExtension().lastPathComponent
        let book = Book(title: fallbackTitle, format: format, fileName: fileName)

        switch format {
        case .epub:
            if let publication = try? EPUBPublication.open(epubAt: localURL, bookID: book.id) {
                book.title = publication.title ?? fallbackTitle
                book.author = publication.author
                book.language = publication.language
                if let cover = publication.coverURL {
                    book.coverFileName = saveCover(from: cover, bookID: book.id)
                }
            } else {
                throw EPUBError.unreadable
            }
        case .pdf:
            if let document = PDFDocument(url: localURL) {
                let attributes = document.documentAttributes ?? [:]
                if let title = attributes[PDFDocumentAttribute.titleAttribute] as? String, !title.isEmpty {
                    book.title = title
                }
                book.author = attributes[PDFDocumentAttribute.authorAttribute] as? String
                book.coverFileName = savePDFThumbnail(document, bookID: book.id)
            }
        case .article:
            let html = (try? String(contentsOf: localURL, encoding: .utf8)) ?? ""
            if let title = html.range(of: "(?<=<title>)[^<]+", options: .regularExpression).map({ String(html[$0]) }) {
                book.title = HTMLText.decodeEntities(title)
            }
        case .audio:
            break
        }
        context.insert(book)
        return book
    }

    static func importAudiobook(_ urls: [URL], into context: ModelContext) async throws -> Book {
        let sorted = urls.sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
        let folderName = LibraryFolder.uniqueFileName(for: sorted[0].deletingPathExtension().lastPathComponent)
        var tracks: [AudioTrack] = []
        var title: String?
        var author: String?
        var album: String?

        for (index, url) in sorted.enumerated() {
            let fileName = try copyIntoLibrary(url, subfolder: folderName)
            let asset = AVURLAsset(url: LibraryFolder.books.appendingPathComponent(fileName))
            let metadata = (try? await asset.load(.commonMetadata)) ?? []
            let trackTitle = await stringValue(metadata, .commonIdentifierTitle)
            if author == nil { author = await stringValue(metadata, .commonIdentifierArtist) }
            if album == nil { album = await stringValue(metadata, .commonIdentifierAlbumName) }
            if title == nil { title = trackTitle }
            let duration = try? await asset.load(.duration)
            tracks.append(AudioTrack(
                index: index,
                title: trackTitle ?? url.deletingPathExtension().lastPathComponent,
                fileName: fileName,
                duration: duration.map(\.seconds).flatMap { $0.isFinite ? $0 : nil }
            ))
        }

        let bookTitle = sorted.count > 1 ? (album ?? folderName) : (title ?? album ?? folderName)
        let book = Book(title: bookTitle, author: author, format: .audio, fileName: folderName)
        book.tracks = tracks
        context.insert(book)
        return book
    }

    private static func stringValue(_ items: [AVMetadataItem], _ identifier: AVMetadataIdentifier) async -> String? {
        guard let item = AVMetadataItem.metadataItems(from: items, filteredByIdentifier: identifier).first else { return nil }
        return try? await item.load(.stringValue)
    }

    static func saveCover(from url: URL, bookID: UUID) -> String? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        let name = "\(bookID.uuidString).\(url.pathExtension.isEmpty ? "jpg" : url.pathExtension)"
        do {
            try data.write(to: LibraryFolder.covers.appendingPathComponent(name))
            return name
        } catch {
            return nil
        }
    }

    static func saveCover(data: Data, bookID: UUID, ext: String = "jpg") -> String? {
        let name = "\(bookID.uuidString).\(ext)"
        do {
            try data.write(to: LibraryFolder.covers.appendingPathComponent(name))
            return name
        } catch {
            return nil
        }
    }

    private static func savePDFThumbnail(_ document: PDFDocument, bookID: UUID) -> String? {
        guard let page = document.page(at: 0) else { return nil }
        let image = page.thumbnail(of: CGSize(width: 400, height: 600), for: .mediaBox)
        #if os(iOS)
        guard let data = image.jpegData(compressionQuality: 0.8) else { return nil }
        #else
        guard let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let data = rep.representation(using: .jpeg, properties: [.compressionFactor: 0.8]) else { return nil }
        #endif
        return saveCover(data: data, bookID: bookID)
    }

    /// Sletter boken og filene dens, også på andre enheter ved neste synk.
    public static func delete(_ book: Book, from context: ModelContext) {
        SyncTombstones.recordBook(book.id)
        for bookmark in book.bookmarks ?? [] { SyncTombstones.recordBookmark(bookmark.id) }
        removeFiles(of: book)
        context.delete(book)
        try? context.save()
    }

    /// Fjerner lokale filer for en bok (fil, omslag og utpakket EPUB).
    public static func removeFiles(of book: Book) {
        if AudioPlayer.shared.book?.id == book.id { AudioPlayer.shared.unload() }
        if let localURL = book.localURL { try? FileManager.default.removeItem(at: localURL) }
        if let cover = book.coverFileName { try? FileManager.default.removeItem(at: LibraryFolder.covers.appendingPathComponent(cover)) }
        EPUBPublication.removeCache(for: book.id)
    }
}
