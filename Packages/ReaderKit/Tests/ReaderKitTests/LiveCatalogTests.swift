import XCTest
@testable import ReaderKit

/// Går mot ekte nettkilder. Kjøres bare med `READER_LIVE_TESTS=1`.
final class LiveCatalogTests: XCTestCase {
    override func setUpWithError() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["READER_LIVE_TESTS"] == "1")
    }

    func testBuiltInSourcesLoadAndSearch() async throws {
        for provider in CatalogDirectory.builtIn() {
            let start = try await provider.start()
            XCTAssertFalse(start.items.isEmpty, "\(provider.name): tom startside")
            if let next = start.nextPage {
                let more = try await provider.page(at: next)
                XCTAssertFalse(more.items.isEmpty, "\(provider.name): tom side 2")
            }
            if provider.supportsSearch {
                let hits = try await provider.search("Dickens")
                print("\(provider.name): \(start.items.count) på start, \(hits.items.count) treff på Dickens")
            }
        }
    }

    func testLibriVoxItemsHaveTracks() async throws {
        let page = try await LibriVoxProvider().search("Doyle")
        let item = try XCTUnwrap(page.items.first)
        XCTAssertFalse(item.tracks.isEmpty, "LibriVox-bok uten spor: \(item.title)")
    }

    func testSuggestedOPDSFeeds() async throws {
        let feeds = [
            "https://www.gutenberg.org/ebooks/search.opds/",
            "https://unglue.it/api/opds/",
        ]
        for feed in feeds {
            let provider = OPDSProvider(id: "test", name: feed, rootURL: URL(string: feed)!)
            let start = try await provider.start()
            print("\(feed): \(start.items.count) elementer, søk=\(provider.supportsSearch)")
            XCTAssertFalse(start.items.isEmpty, "\(feed): tom")
            if provider.supportsSearch {
                let hits = try await provider.search("Austen")
                print("  søk Austen: \(hits.items.count)")
            }
        }
    }

    func testGutenbergEPUBDownloadsAndParses() async throws {
        let page = try await GutenbergProvider().search("Pride and Prejudice")
        let item = try XCTUnwrap(page.items.first)
        let epub = try XCTUnwrap(item.acquisitions.first { $0.format == .epub }, "ingen EPUB-lenke")
        let (tmp, _) = try await URLSession.shared.download(from: epub.url)
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("live.epub")
        try? FileManager.default.removeItem(at: file)
        try FileManager.default.moveItem(at: tmp, to: file)
        let id = UUID()
        defer { EPUBPublication.removeCache(for: id) }
        let pub = try EPUBPublication.open(epubAt: file, bookID: id)
        print("EPUB: \(pub.title ?? "-") av \(pub.author ?? "-"), \(pub.chapters.count) kapitler, \(pub.toc.count) i TOC")
        XCTAssertGreaterThan(pub.chapters.count, 3)
        XCTAssertFalse(pub.toc.isEmpty)
        let paragraphs = (0..<min(pub.chapters.count, 6)).flatMap { pub.paragraphs(inChapter: $0) }
        XCTAssertGreaterThan(paragraphs.count, 20)
    }
}
