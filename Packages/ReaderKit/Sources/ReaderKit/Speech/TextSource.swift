import Foundation
import PDFKit

/// Tekst delt i seksjoner (kapitler, sider) og avsnitt, som opplesing og oversettelse kan gå gjennom.
public protocol TextSource {
    var sectionCount: Int { get }
    var language: String? { get }
    func title(ofSection index: Int) -> String?
    func paragraphs(inSection index: Int) -> [String]
}

public struct EPUBTextSource: TextSource {
    public let publication: EPUBPublication
    public init(publication: EPUBPublication) { self.publication = publication }
    public var sectionCount: Int { publication.chapters.count }
    public var language: String? { publication.language }
    public func title(ofSection index: Int) -> String? { publication.title(forChapter: index) }
    public func paragraphs(inSection index: Int) -> [String] { publication.paragraphs(inChapter: index) }
}

public struct PDFTextSource: TextSource {
    public let document: PDFDocument
    public init(document: PDFDocument) { self.document = document }
    public var sectionCount: Int { document.pageCount }
    public var language: String? { nil }
    public func title(ofSection index: Int) -> String? { "Side \(index + 1)" }
    public func paragraphs(inSection index: Int) -> [String] {
        guard let text = document.page(at: index)?.string else { return [] }
        // PDF-tekst har linjeskift midt i setninger; slå sammen linjer og del på tomme linjer.
        return text
            .components(separatedBy: "\n\n")
            .map { $0.replacingOccurrences(of: "-\n", with: "").replacingOccurrences(of: "\n", with: " ").trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }
}

public struct HTMLTextSource: TextSource {
    public let title: String?
    public let language: String?
    private let cachedParagraphs: [String]

    public init(html: String, title: String?, language: String?) {
        self.title = title
        self.language = language
        self.cachedParagraphs = HTMLText.paragraphs(from: html)
    }

    public var sectionCount: Int { 1 }
    public func title(ofSection index: Int) -> String? { title }
    public func paragraphs(inSection index: Int) -> [String] { cachedParagraphs }
}
