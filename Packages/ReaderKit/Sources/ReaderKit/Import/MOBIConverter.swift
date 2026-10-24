import Foundation
import ZIPFoundation

public enum MOBIError: LocalizedError {
    case unreadable
    case drm
    case unsupportedCompression
    case kf8Only

    public var errorDescription: String? {
        switch self {
        case .unreadable: "Filen kunne ikke leses som MOBI."
        case .drm: "Boken er kopibeskyttet (DRM) og kan bare åpnes i Kindle."
        case .unsupportedCompression: "MOBI-filen bruker en komprimering som ikke støttes ennå."
        case .kf8Only: "Rene AZW3/KF8-filer støttes ikke ennå. Prøv EPUB- eller MOBI-versjonen av boken."
        }
    }
}

/// Gjør en DRM-fri MOBI-fil (Mobipocket/KF6) om til en enkel EPUB, så resten av appen kan lese den.
enum MOBIConverter {
    static let fileExtensions: Set<String> = ["mobi", "prc", "azw", "azw3"]

    struct Book {
        var title: String
        var author: String?
        var language: String?
        var html: Data
        var images: [Int: (data: Data, ext: String)]
        var coverIndex: Int?
    }

    /// Skriver en midlertidig EPUB med samme navn som MOBI-filen og returnerer adressen.
    static func convertToEPUB(_ url: URL) throws -> URL {
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }
        let book = try parse(Data(contentsOf: url))

        let work = FileManager.default.temporaryDirectory.appendingPathComponent("mobi-\(UUID().uuidString)", isDirectory: true)
        let root = work.appendingPathComponent("bok", isDirectory: true)
        try writeEPUBFolder(book, to: root)
        let epub = work.appendingPathComponent(url.deletingPathExtension().lastPathComponent + ".epub")
        try FileManager.default.zipItem(at: root, to: epub, shouldKeepParent: false)
        return epub
    }

    // MARK: - Lesing

    static func parse(_ data: Data) throws -> Book {
        let bytes = [UInt8](data)
        guard bytes.count > 78, String(decoding: bytes[60..<68], as: UTF8.self) == "BOOKMOBI" else {
            throw MOBIError.unreadable
        }
        let recordCount = Int(bytes.u16(76))
        var offsets: [Int] = (0..<recordCount).map { Int(bytes.u32(78 + $0 * 8)) }
        offsets.append(bytes.count)
        func record(_ i: Int) -> ArraySlice<UInt8> {
            guard i >= 0, i + 1 < offsets.count, offsets[i] <= offsets[i + 1], offsets[i + 1] <= bytes.count else { return [] }
            return bytes[offsets[i]..<offsets[i + 1]]
        }

        let r0 = Array(record(0))
        guard r0.count >= 24 else { throw MOBIError.unreadable }
        let compression = r0.u16(0)
        let textRecords = Int(r0.u16(8))
        guard r0.u16(12) == 0 else { throw MOBIError.drm }
        guard compression == 1 || compression == 2 else { throw MOBIError.unsupportedCompression }

        var title = String(decoding: bytes[0..<32].prefix { $0 != 0 }, as: UTF8.self)
        var author: String?
        var language: String?
        var encoding = String.Encoding.windowsCP1252
        var firstImage = Int.max
        var extraFlags: UInt16 = 0
        var coverOffset: Int?

        if r0.count >= 24, String(decoding: r0[16..<20], as: UTF8.self) == "MOBI" {
            let headerLength = Int(r0.u32(20))
            // Ren KF8 (AZW3): teksten er delt i skjelett og fragmenter som krever egne indekser.
            // Kombinerte filer har en KF6-del først, og den kan vi lese.
            if r0.u32(36) >= 8 { throw MOBIError.kf8Only }
            if r0.u32(28) == 65001 { encoding = .utf8 }
            if r0.count >= 0x70 { firstImage = Int(r0.u32(0x6C)) }
            if headerLength >= 0xE4, r0.count >= 0xF4 { extraFlags = r0.u16(0xF2) }
            if r0.count >= 0x5C {
                let nameOffset = Int(r0.u32(0x54)), nameLength = Int(r0.u32(0x58))
                if nameLength > 0, nameOffset + nameLength <= r0.count,
                   let full = String(bytes: r0[nameOffset..<nameOffset + nameLength], encoding: encoding) {
                    title = full
                }
            }
            let exthStart = 16 + headerLength
            if r0.count >= 0x84, r0.u32(0x80) & 0x40 != 0, exthStart + 12 <= r0.count,
               String(decoding: r0[exthStart..<exthStart + 4], as: UTF8.self) == "EXTH" {
                let count = Int(r0.u32(exthStart + 8))
                var p = exthStart + 12
                for _ in 0..<count {
                    guard p + 8 <= r0.count else { break }
                    let type = r0.u32(p), length = Int(r0.u32(p + 4))
                    guard length >= 8, p + length <= r0.count else { break }
                    let value = r0[(p + 8)..<(p + length)]
                    switch type {
                    case 100: author = String(bytes: value, encoding: encoding)
                    case 503: if let t = String(bytes: value, encoding: encoding), !t.isEmpty { title = t }
                    case 524: language = String(bytes: value, encoding: encoding)
                    case 201: if value.count >= 4 { coverOffset = Int(Array(value).u32(0)) }
                    default: break
                    }
                    p += length
                }
            }
        }

        var text: [UInt8] = []
        for i in 1...max(1, textRecords) where i < recordCount {
            var chunk = Array(record(i))
            chunk.removeLast(min(chunk.count, trailingSize(chunk, flags: extraFlags)))
            text += compression == 2 ? decompressPalmDOC(chunk) : chunk
        }
        insertFileposAnchors(&text)
        let htmlString = String(bytes: text, encoding: encoding) ?? String(decoding: text, as: UTF8.self)

        var images: [Int: (data: Data, ext: String)] = [:]
        if firstImage < recordCount {
            for i in firstImage..<recordCount {
                let rec = record(i)
                guard let ext = imageExtension(rec) else { continue }
                images[i - firstImage + 1] = (data: Data(rec), ext: ext)
            }
        }
        return Book(
            title: title.isEmpty ? "Uten tittel" : title,
            author: author,
            language: language,
            html: Data(htmlString.utf8),
            images: images,
            coverIndex: coverOffset.map { $0 + 1 }
        )
    }

    /// Interne lenker peker på byteposisjoner i den utpakkede teksten (filepos). Setter inn ankre der.
    static func insertFileposAnchors(_ text: inout [UInt8]) {
        let latin = String(decoding: text.map { $0 < 0x80 ? $0 : 0x3F }, as: UTF8.self)
        let targets = Set(matches(#"filepos=["']?0*(\d+)"#, in: latin).compactMap { Int($0) }).filter { $0 < text.count }
        for target in targets.sorted(by: >) {
            text.insert(contentsOf: Array("<a id=\"filepos\(target)\"></a>".utf8), at: target)
        }
    }

    /// Størrelsen på ekstradata som kan ligge bakerst i hver tekstpost.
    static func trailingSize(_ data: [UInt8], flags: UInt16) -> Int {
        var size = 0
        var f = flags >> 1
        while f != 0 {
            if f & 1 != 0 {
                var bit = 0, value = 0, pos = data.count - size
                while pos > 0 {
                    let byte = Int(data[pos - 1])
                    value |= (byte & 0x7F) << bit
                    bit += 7
                    pos -= 1
                    if byte & 0x80 != 0 || bit >= 28 { break }
                }
                size += value
            }
            f >>= 1
        }
        if flags & 1 != 0, data.count - size - 1 >= 0 {
            size += Int(data[data.count - size - 1] & 0x3) + 1
        }
        return size
    }

    /// PalmDOC-dekomprimering (LZ77-variant).
    static func decompressPalmDOC(_ input: [UInt8]) -> [UInt8] {
        var out: [UInt8] = []
        out.reserveCapacity(input.count * 2)
        var i = 0
        while i < input.count {
            let c = input[i]
            i += 1
            switch c {
            case 1...8:
                let end = min(input.count, i + Int(c))
                out += input[i..<end]
                i = end
            case 0..<0x80:
                out.append(c)
            case 0xC0...:
                out.append(0x20)
                out.append(c ^ 0x80)
            default:
                guard i < input.count else { break }
                let pair = (Int(c) << 8) | Int(input[i])
                i += 1
                let distance = (pair >> 3) & 0x7FF
                let length = (pair & 7) + 3
                guard distance > 0, distance <= out.count else { continue }
                for _ in 0..<length { out.append(out[out.count - distance]) }
            }
        }
        return out
    }

    static func imageExtension(_ data: ArraySlice<UInt8>) -> String? {
        let b = Array(data.prefix(4))
        guard b.count == 4 else { return nil }
        if b[0] == 0xFF, b[1] == 0xD8 { return "jpg" }
        if b == [0x89, 0x50, 0x4E, 0x47] { return "png" }
        if b[0] == 0x47, b[1] == 0x49, b[2] == 0x46 { return "gif" }
        return nil
    }

    // MARK: - EPUB

    static func writeEPUBFolder(_ book: Book, to root: URL) throws {
        let fm = FileManager.default
        let oebps = root.appendingPathComponent("OEBPS", isDirectory: true)
        try fm.createDirectory(at: root.appendingPathComponent("META-INF"), withIntermediateDirectories: true)
        try fm.createDirectory(at: oebps.appendingPathComponent("images"), withIntermediateDirectories: true)
        try Data("application/epub+zip".utf8).write(to: root.appendingPathComponent("mimetype"))
        try Data("""
        <?xml version="1.0"?>
        <container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container">
          <rootfiles><rootfile full-path="OEBPS/content.opf" media-type="application/oebps-package+xml"/></rootfiles>
        </container>
        """.utf8).write(to: root.appendingPathComponent("META-INF/container.xml"))

        for (index, image) in book.images {
            try image.data.write(to: oebps.appendingPathComponent("images/\(index).\(image.ext)"))
        }

        let chapters = splitChapters(String(decoding: book.html, as: UTF8.self), images: book.images)
        var manifest: [String] = []
        var spine: [String] = []
        var nav: [String] = []
        for (i, chapter) in chapters.enumerated() {
            let name = "kapittel\(i + 1).html"
            let document = "<!DOCTYPE html><html><head><meta charset=\"utf-8\"><title>\(escape(book.title))</title></head><body>\(chapter.html)</body></html>"
            try Data(document.utf8).write(to: oebps.appendingPathComponent(name))
            manifest.append("<item id=\"k\(i + 1)\" href=\"\(name)\" media-type=\"text/html\"/>")
            spine.append("<itemref idref=\"k\(i + 1)\"/>")
            nav.append("<li><a href=\"\(name)\">\(escape(chapter.title ?? "Del \(i + 1)"))</a></li>")
        }
        for (index, image) in book.images.sorted(by: { $0.key < $1.key }) {
            let mime = image.ext == "jpg" ? "image/jpeg" : "image/\(image.ext)"
            let cover = index == book.coverIndex ? " properties=\"cover-image\"" : ""
            manifest.append("<item id=\"img\(index)\" href=\"images/\(index).\(image.ext)\" media-type=\"\(mime)\"\(cover)/>")
        }
        try Data("""
        <?xml version="1.0" encoding="utf-8"?>
        <html xmlns="http://www.w3.org/1999/xhtml" xmlns:epub="http://www.idpf.org/2007/ops"><head><title>Innhold</title></head>
        <body><nav epub:type="toc"><ol>\(nav.joined())</ol></nav></body></html>
        """.utf8).write(to: oebps.appendingPathComponent("nav.xhtml"))
        manifest.append("<item id=\"nav\" href=\"nav.xhtml\" media-type=\"application/xhtml+xml\" properties=\"nav\"/>")

        let opf = """
        <?xml version="1.0" encoding="utf-8"?>
        <package xmlns="http://www.idpf.org/2007/opf" version="3.0" unique-identifier="id">
          <metadata xmlns:dc="http://purl.org/dc/elements/1.1/">
            <dc:identifier id="id">mobi-\(UUID().uuidString)</dc:identifier>
            <dc:title>\(escape(book.title))</dc:title>
            \(book.author.map { "<dc:creator>\(escape($0))</dc:creator>" } ?? "")
            <dc:language>\(escape(book.language ?? "en"))</dc:language>
          </metadata>
          <manifest>\(manifest.joined(separator: "\n"))</manifest>
          <spine>\(spine.joined())</spine>
        </package>
        """
        try Data(opf.utf8).write(to: oebps.appendingPathComponent("content.opf"))
    }

    /// Deler MOBI-HTML ved sideskift, gjør bildereferanser og interne lenker om til vanlig HTML.
    static func splitChapters(_ raw: String, images: [Int: (data: Data, ext: String)]) -> [(title: String?, html: String)] {
        var html = raw
        html = html.replacingOccurrences(of: #"recindex=["']?0*(\d+)["']?"#, with: "src=\"images/$1.IMGEXT\"", options: .regularExpression)
        // Riktig filtype per bilde.
        for (index, image) in images {
            html = html.replacingOccurrences(of: "images/\(index).IMGEXT", with: "images/\(index).\(image.ext)")
        }
        html = html.replacingOccurrences(of: #"<mbp:pagebreak\s*/?>"#, with: "\u{1}", options: [.regularExpression, .caseInsensitive])
        html = html.replacingOccurrences(of: #"</?(html|head|body|guide|reference|mbp:[a-z]+)[^>]*>"#, with: "", options: [.regularExpression, .caseInsensitive])

        var parts = html.split(separator: "\u{1}", omittingEmptySubsequences: false).map(String.init)
            .filter { !$0.replacingOccurrences(of: #"<[^>]+>|\s"#, with: "", options: .regularExpression).isEmpty || $0.contains("<img") }
        if parts.isEmpty { parts = [html] }

        // Lenker til ankre må peke på kapittelet ankeret havnet i.
        var anchorChapter: [String: Int] = [:]
        for (i, part) in parts.enumerated() {
            for id in matches(#"id="(filepos\d+)""#, in: part) { anchorChapter[id] = i }
        }
        return parts.map { part in
            var chapter = part
            chapter = chapter.replacingOccurrences(of: #"filepos=["']?0*(\d+)["']?"#, with: "href=\"#filepos$1\"", options: .regularExpression)
            for (anchor, index) in anchorChapter {
                chapter = chapter.replacingOccurrences(of: "href=\"#\(anchor)\"", with: "href=\"kapittel\(index + 1).html#\(anchor)\"")
            }
            // MOBI-filer bruker ofte <font size="5"> i stedet for overskrifter.
            let candidates = matches(#"<h[1-3][^>]*>([\s\S]*?)</h[1-3]>"#, in: chapter)
                + matches(#"<font size="?[4-9]"?[^>]*>([\s\S]*?)</font>"#, in: chapter)
            let heading = candidates.lazy
                .map { HTMLText.decodeEntities($0.replacingOccurrences(of: #"<[^>]+>"#, with: "", options: .regularExpression)).trimmingCharacters(in: .whitespacesAndNewlines) }
                .first { !$0.isEmpty && $0.count <= 80 }
            return (heading, chapter)
        }
    }

    private static func matches(_ pattern: String, in text: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return [] }
        return regex.matches(in: text, range: NSRange(text.startIndex..., in: text)).compactMap {
            Range($0.range(at: 1), in: text).map { String(text[$0]) }
        }
    }

    private static func escape(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;").replacingOccurrences(of: ">", with: "&gt;")
    }
}

private extension Collection where Element == UInt8, Index == Int {
    func u16(_ i: Int) -> UInt16 {
        let s = startIndex + i
        return UInt16(self[s]) << 8 | UInt16(self[s + 1])
    }
    func u32(_ i: Int) -> UInt32 {
        let s = startIndex + i
        return UInt32(self[s]) << 24 | UInt32(self[s + 1]) << 16 | UInt32(self[s + 2]) << 8 | UInt32(self[s + 3])
    }
}
