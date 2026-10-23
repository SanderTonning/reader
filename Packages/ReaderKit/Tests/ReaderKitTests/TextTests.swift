import XCTest
@testable import ReaderKit

final class TextTests: XCTestCase {
    func testPlainTextFromHTML() {
        let html = "<html><head><title>X</title><style>p{}</style></head><body><h1>Tittel</h1><p>Første &amp; beste.</p><p>Andre&nbsp;avsnitt &#229;&#x00F8;</p></body></html>"
        XCTAssertEqual(HTMLText.paragraphs(from: html), ["Tittel", "Første & beste.", "Andre avsnitt åø"])
    }

    func testEPUBParsing() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let fm = FileManager.default
        try fm.createDirectory(at: folder.appendingPathComponent("META-INF"), withIntermediateDirectories: true)
        try fm.createDirectory(at: folder.appendingPathComponent("OEBPS"), withIntermediateDirectories: true)
        try """
        <?xml version="1.0"?>
        <container xmlns="urn:oasis:names:tc:opendocument:xmlns:container" version="1.0">
          <rootfiles><rootfile full-path="OEBPS/content.opf" media-type="application/oebps-package+xml"/></rootfiles>
        </container>
        """.write(to: folder.appendingPathComponent("META-INF/container.xml"), atomically: true, encoding: .utf8)
        try """
        <?xml version="1.0"?>
        <package xmlns="http://www.idpf.org/2007/opf" version="3.0">
          <metadata xmlns:dc="http://purl.org/dc/elements/1.1/">
            <dc:title>Et dukkehjem</dc:title><dc:creator>Henrik Ibsen</dc:creator><dc:language>nb</dc:language>
          </metadata>
          <manifest>
            <item id="nav" href="nav.xhtml" media-type="application/xhtml+xml" properties="nav"/>
            <item id="c1" href="text/c1.xhtml" media-type="application/xhtml+xml"/>
            <item id="c2" href="text/c2.xhtml" media-type="application/xhtml+xml"/>
            <item id="img" href="cover.jpg" media-type="image/jpeg" properties="cover-image"/>
          </manifest>
          <spine><itemref idref="c1"/><itemref idref="c2"/></spine>
        </package>
        """.write(to: folder.appendingPathComponent("OEBPS/content.opf"), atomically: true, encoding: .utf8)
        try """
        <?xml version="1.0"?>
        <html xmlns="http://www.w3.org/1999/xhtml" xmlns:epub="http://www.idpf.org/2007/ops"><body>
        <nav epub:type="toc"><ol><li><a href="text/c1.xhtml">Første akt</a></li><li><a href="text/c2.xhtml#start">Andre akt</a></li></ol></nav>
        </body></html>
        """.write(to: folder.appendingPathComponent("OEBPS/nav.xhtml"), atomically: true, encoding: .utf8)

        let publication = try EPUBPublication.parse(folder: folder)
        XCTAssertEqual(publication.title, "Et dukkehjem")
        XCTAssertEqual(publication.author, "Henrik Ibsen")
        XCTAssertEqual(publication.chapters.map(\.href), ["text/c1.xhtml", "text/c2.xhtml"])
        XCTAssertEqual(publication.toc.map(\.title), ["Første akt", "Andre akt"])
        XCTAssertEqual(publication.chapterIndex(for: "text/c2.xhtml#start"), 1)
        XCTAssertEqual(publication.title(forChapter: 0), "Første akt")
        XCTAssertEqual(publication.coverURL?.lastPathComponent, "cover.jpg")
    }

    func testFirstURLInText() {
        XCTAssertEqual(ArticleImporter.firstURL(in: "Les denne: https://example.com/a?b=1 nå")?.absoluteString, "https://example.com/a?b=1")
    }
}
