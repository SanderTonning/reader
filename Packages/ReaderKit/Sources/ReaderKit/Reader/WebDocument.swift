import Foundation

/// Et dokument som vises i nettleseren: en EPUB (mange kapitler) eller en artikkel (ett kapittel).
struct WebDocument {
    struct Chapter: Hashable {
        var href: String
        var url: URL
        var title: String?
    }

    var chapters: [Chapter]
    var toc: [EPUBTOCEntry]
    var readAccess: URL
    var textSource: TextSource
    var publication: EPUBPublication?

    static func epub(_ publication: EPUBPublication) -> WebDocument {
        WebDocument(
            chapters: publication.chapters.enumerated().map {
                Chapter(href: $0.element.href, url: $0.element.url, title: publication.title(forChapter: $0.offset))
            },
            toc: publication.toc,
            readAccess: publication.folder,
            textSource: EPUBTextSource(publication: publication),
            publication: publication
        )
    }

    static func article(url: URL, title: String, language: String?) -> WebDocument {
        let html = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
        return WebDocument(
            chapters: [Chapter(href: url.lastPathComponent, url: url, title: title)],
            toc: [],
            readAccess: url.deletingLastPathComponent(),
            textSource: HTMLTextSource(html: html, title: title, language: language),
            publication: nil
        )
    }

    func chapterIndex(for href: String?) -> Int? {
        guard let href else { return nil }
        if let publication { return publication.chapterIndex(for: href) }
        return chapters.firstIndex { $0.href == href }
    }

    func chapterIndex(for url: URL) -> Int? {
        let path = url.standardizedFileURL.path
        return chapters.firstIndex { $0.url.standardizedFileURL.path == path }
    }

    /// Antall tegn i kapittelets tekst, brukt for å regne om mellom opplesing og scrollposisjon.
    func characterCount(inChapter index: Int) -> Int {
        textSource.paragraphs(inSection: index).reduce(0) { $0 + $1.count + 1 }
    }
}
