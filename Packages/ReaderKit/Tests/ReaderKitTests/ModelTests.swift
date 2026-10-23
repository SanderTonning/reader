import XCTest
import SwiftData
@testable import ReaderKit

final class ModelTests: XCTestCase {
    func testFormatFromFileExtension() {
        XCTAssertEqual(BookFormat(fileExtension: "EPUB"), .epub)
        XCTAssertEqual(BookFormat(fileExtension: "m4b"), .audio)
        XCTAssertEqual(BookFormat(fileExtension: "pdf")?.kind, .ebook)
        XCTAssertNil(BookFormat(fileExtension: "docx"))
    }

    func testPositionRoundTrip() {
        let position = ReadingPosition(href: "ch3.xhtml", progression: 0.5, totalProgression: 0.42, deviceName: "Test")
        let decoded = ReadingPosition.decode(position.encoded())
        XCTAssertEqual(decoded?.href, "ch3.xhtml")
        XCTAssertEqual(decoded?.percentText, "42 %")
    }

    @MainActor
    func testBookWithBookmarkPersists() throws {
        let container = try ReaderSchema.makeContainer(inMemory: true)
        let context = container.mainContext
        let book = Book(title: "Peer Gynt", author: "Henrik Ibsen", format: .epub)
        context.insert(book)
        let bookmark = Bookmark(label: "Akt 2", position: ReadingPosition(totalProgression: 0.3))
        bookmark.book = book
        context.insert(bookmark)
        book.position = ReadingPosition(page: 12)
        try context.save()

        let fetched = try context.fetch(FetchDescriptor<Book>())
        XCTAssertEqual(fetched.count, 1)
        XCTAssertEqual(fetched.first?.bookmarks?.count, 1)
        XCTAssertEqual(fetched.first?.position?.page, 12)
    }
}
