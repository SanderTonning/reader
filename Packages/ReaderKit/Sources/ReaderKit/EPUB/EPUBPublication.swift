import Foundation
import ZIPFoundation

public struct EPUBChapter: Hashable, Sendable {
    public var href: String
    public var url: URL
}

public struct EPUBTOCEntry: Hashable, Sendable, Identifiable {
    public var id: String { "\(level)-\(href)-\(title)" }
    public var title: String
    public var href: String
    public var level: Int
}

public enum EPUBError: LocalizedError {
    case unreadable
    case missingPackage

    public var errorDescription: String? {
        switch self {
        case .unreadable: "Filen kunne ikke åpnes som EPUB."
        case .missingPackage: "EPUB-filen mangler innholdsfortegnelse (OPF)."
        }
    }
}

/// En utpakket EPUB-bok: metadata, lesrekkefølge (spine) og innholdsfortegnelse.
public struct EPUBPublication: Sendable {
    public var title: String?
    public var author: String?
    public var language: String?
    public var coverURL: URL?
    public var chapters: [EPUBChapter]
    public var toc: [EPUBTOCEntry]
    public var folder: URL

    /// Pakker ut EPUB-en (en gang) til en cache-mappe og leser den.
    public static func open(epubAt fileURL: URL, bookID: UUID) throws -> EPUBPublication {
        let folder = try unpack(fileURL, bookID: bookID)
        return try parse(folder: folder)
    }

    static func cacheFolder(for bookID: UUID) -> URL {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        return caches.appendingPathComponent("EPUB/\(bookID.uuidString)", isDirectory: true)
    }

    static func unpack(_ fileURL: URL, bookID: UUID) throws -> URL {
        let folder = cacheFolder(for: bookID)
        let marker = folder.appendingPathComponent(".unpacked")
        if FileManager.default.fileExists(atPath: marker.path) { return folder }
        try? FileManager.default.removeItem(at: folder)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        do {
            try FileManager.default.unzipItem(at: fileURL, to: folder)
        } catch {
            throw EPUBError.unreadable
        }
        FileManager.default.createFile(atPath: marker.path, contents: Data())
        return folder
    }

    public static func removeCache(for bookID: UUID) {
        try? FileManager.default.removeItem(at: cacheFolder(for: bookID))
    }

    static func parse(folder: URL) throws -> EPUBPublication {
        let containerURL = folder.appendingPathComponent("META-INF/container.xml")
        guard let containerData = try? Data(contentsOf: containerURL),
              let container = XMLTree.parse(containerData),
              let rootfilePath = container.descendants("rootfile").first?.attribute("full-path")
        else { throw EPUBError.missingPackage }

        let opfURL = folder.appendingPathComponent(rootfilePath)
        guard let opfData = try? Data(contentsOf: opfURL), let opf = XMLTree.parse(opfData) else {
            throw EPUBError.missingPackage
        }
        let base = opfURL.deletingLastPathComponent()

        let metadata = opf.first("metadata")
        let title = metadata?.first("title")?.allText
        let author = metadata?.all("creator").map(\.allText).filter { !$0.isEmpty }.joined(separator: ", ")
        let language = metadata?.first("language")?.allText

        struct Item { var href: String; var mediaType: String; var properties: String }
        var items: [String: Item] = [:]
        for item in opf.first("manifest")?.all("item") ?? [] {
            guard let id = item.attribute("id"), let href = item.attribute("href") else { continue }
            items[id] = Item(
                href: href.removingPercentEncoding ?? href,
                mediaType: item.attribute("media-type") ?? "",
                properties: item.attribute("properties") ?? ""
            )
        }

        let spine = opf.first("spine")
        let chapters: [EPUBChapter] = (spine?.all("itemref") ?? []).compactMap { ref in
            guard let idref = ref.attribute("idref"), let item = items[idref] else { return nil }
            return EPUBChapter(href: item.href, url: base.appendingPathComponent(item.href))
        }

        // Omslag: EPUB 3 (properties="cover-image") eller EPUB 2 (<meta name="cover">).
        var coverHref = items.values.first { $0.properties.contains("cover-image") }?.href
        if coverHref == nil,
           let coverID = metadata?.all("meta").first(where: { $0.attribute("name") == "cover" })?.attribute("content") {
            coverHref = items[coverID]?.href
        }
        if coverHref == nil {
            coverHref = items.first { $0.key.lowercased().contains("cover") && $0.value.mediaType.hasPrefix("image/") }?.value.href
        }

        // Innholdsfortegnelse: EPUB 3 nav-dokument, ellers NCX.
        var toc: [EPUBTOCEntry] = []
        if let nav = items.values.first(where: { $0.properties.split(separator: " ").contains("nav") }) {
            toc = parseNav(base.appendingPathComponent(nav.href), relativeTo: base)
        }
        if toc.isEmpty, let tocID = spine?.attribute("toc"), let ncx = items[tocID] {
            toc = parseNCX(base.appendingPathComponent(ncx.href), relativeTo: base)
        }
        if toc.isEmpty {
            toc = chapters.enumerated().map { EPUBTOCEntry(title: "Del \($0.offset + 1)", href: $0.element.href, level: 0) }
        }

        return EPUBPublication(
            title: title?.isEmpty == false ? title : nil,
            author: author?.isEmpty == false ? author : nil,
            language: language,
            coverURL: coverHref.map { base.appendingPathComponent($0) },
            chapters: chapters,
            toc: toc,
            folder: folder
        )
    }

    /// Gjør en href i nav/NCX om til en href relativ til OPF-mappen.
    private static func normalize(_ href: String, document: URL, base: URL) -> String {
        let clean = href.removingPercentEncoding ?? href
        let absolute = URL(fileURLWithPath: clean, relativeTo: document.deletingLastPathComponent()).standardizedFileURL.path
        let basePath = base.standardizedFileURL.path
        if absolute.hasPrefix(basePath + "/") {
            return String(absolute.dropFirst(basePath.count + 1))
        }
        return clean
    }

    private static func parseNav(_ url: URL, relativeTo base: URL) -> [EPUBTOCEntry] {
        guard let data = try? Data(contentsOf: url), let tree = XMLTree.parse(data) else { return [] }
        let navs = tree.descendants("nav")
        guard let nav = navs.first(where: { $0.attribute("type") == "toc" }) ?? navs.first,
              let list = nav.descendants("ol").first else { return [] }
        var entries: [EPUBTOCEntry] = []
        func walk(_ ol: XMLTree, level: Int) {
            for li in ol.all("li") {
                if let a = li.first("a") ?? li.descendants("a").first, let href = a.attribute("href") {
                    entries.append(EPUBTOCEntry(title: a.allText, href: normalize(href, document: url, base: base), level: level))
                }
                if let sub = li.first("ol") { walk(sub, level: level + 1) }
            }
        }
        walk(list, level: 0)
        return entries
    }

    private static func parseNCX(_ url: URL, relativeTo base: URL) -> [EPUBTOCEntry] {
        guard let data = try? Data(contentsOf: url), let tree = XMLTree.parse(data),
              let navMap = tree.descendants("navMap").first else { return [] }
        var entries: [EPUBTOCEntry] = []
        func walk(_ node: XMLTree, level: Int) {
            for point in node.all("navPoint") {
                let title = point.first("navLabel")?.first("text")?.allText ?? ""
                if let src = point.first("content")?.attribute("src") {
                    entries.append(EPUBTOCEntry(title: title, href: normalize(src, document: url, base: base), level: level))
                }
                walk(point, level: level + 1)
            }
        }
        walk(navMap, level: 0)
        return entries
    }

    /// Indeksen til kapittelet en href (eventuelt med #anker) peker på.
    public func chapterIndex(for href: String) -> Int? {
        let path = href.split(separator: "#").first.map(String.init) ?? href
        return chapters.firstIndex { $0.href == path || $0.href.hasSuffix("/" + path) || path.hasSuffix("/" + $0.href) }
    }

    public func paragraphs(inChapter index: Int) -> [String] {
        guard chapters.indices.contains(index),
              let data = try? Data(contentsOf: chapters[index].url) else { return [] }
        let html = String(decoding: data, as: UTF8.self)
        return HTMLText.paragraphs(from: html)
    }

    public func title(forChapter index: Int) -> String? {
        guard chapters.indices.contains(index) else { return nil }
        let href = chapters[index].href
        return toc.first { ($0.href.split(separator: "#").first.map(String.init) ?? $0.href) == href }?.title
    }
}
