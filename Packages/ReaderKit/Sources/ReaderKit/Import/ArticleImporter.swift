import Foundation
import SwiftData
import WebKit

public enum ArticleImportError: LocalizedError {
    case invalidURL
    case notReadable

    public var errorDescription: String? {
        switch self {
        case .invalidURL: "Lenken er ikke gyldig."
        case .notReadable: "Fant ingen artikkeltekst på siden."
        }
    }
}

/// Henter en nettartikkel, trekker ut selve teksten med Mozilla Readability og lagrer den i biblioteket.
@MainActor
public final class ArticleImporter: NSObject, WKNavigationDelegate {
    private var webView: WKWebView?
    private var continuation: CheckedContinuation<Void, Error>?

    public override init() {}

    struct Article: Decodable {
        var title: String?
        var byline: String?
        var content: String?
        var textContent: String?
        var excerpt: String?
        var siteName: String?
        var lang: String?
    }

    /// Finner første lenke i en tekst, for eksempel fra utklippstavlen.
    nonisolated public static func firstURL(in text: String) -> URL? {
        let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)
        let range = NSRange(text.startIndex..., in: text)
        return detector?.firstMatch(in: text, range: range)?.url
    }

    public func importArticle(from url: URL, into context: ModelContext) async throws -> Book {
        guard let scheme = url.scheme?.lowercased(), ["http", "https"].contains(scheme) else {
            throw ArticleImportError.invalidURL
        }
        let article = try await extract(url)
        guard let content = article.content, !(article.textContent ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ArticleImportError.notReadable
        }

        let title = article.title?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? url.host ?? "Artikkel"
        let byline = article.byline?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        let book = Book(
            title: title,
            author: byline ?? article.siteName ?? url.host,
            format: .article,
            language: article.lang,
            sourceID: "web",
            sourceItemID: url.absoluteString,
            remoteURL: url
        )
        book.summary = article.excerpt

        let html = Self.document(title: title, byline: byline, source: url, body: content, language: article.lang)
        let fileName = "\(book.id.uuidString).html"
        try html.write(to: LibraryFolder.books.appendingPathComponent(fileName), atomically: true, encoding: .utf8)
        book.fileName = fileName

        context.insert(book)
        try? context.save()
        return book
    }

    static func document(title: String, byline: String?, source: URL, body: String, language: String?) -> String {
        """
        <!DOCTYPE html>
        <html lang="\(HTMLText.escape(language ?? "nb"))">
        <head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <title>\(HTMLText.escape(title))</title>
        </head>
        <body>
        <header class="reader-article-header">
        <h1>\(HTMLText.escape(title))</h1>
        \(byline.map { "<p class=\"byline\">\(HTMLText.escape($0))</p>" } ?? "")
        <p class="source"><a href="\(HTMLText.escape(source.absoluteString))">\(HTMLText.escape(source.host ?? source.absoluteString))</a></p>
        </header>
        \(body)
        </body>
        </html>
        """
    }

    private func extract(_ url: URL) async throws -> Article {
        let configuration = WKWebViewConfiguration()
        // Sidens egne skript trengs ikke; Readability kjøres i en egen JavaScript-verden.
        configuration.defaultWebpagePreferences.allowsContentJavaScript = false
        let webView = WKWebView(frame: CGRect(x: 0, y: 0, width: 1024, height: 768), configuration: configuration)
        webView.navigationDelegate = self
        self.webView = webView
        defer { self.webView = nil }

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            self.continuation = continuation
            webView.load(URLRequest(url: url, timeoutInterval: 30))
        }

        guard let scriptURL = Bundle.module.url(forResource: "Readability", withExtension: "js"),
              let readability = try? String(contentsOf: scriptURL, encoding: .utf8) else {
            throw ArticleImportError.notReadable
        }
        let script = readability + "\nconst parsed = new Readability(document.cloneNode(true)).parse();\nreturn parsed ? JSON.stringify(parsed) : null;"
        let result = try await webView.callAsyncJavaScript(script, arguments: [:], in: nil, contentWorld: .defaultClient)
        guard let json = result as? String, let data = json.data(using: .utf8) else {
            throw ArticleImportError.notReadable
        }
        return try JSONDecoder().decode(Article.self, from: data)
    }

    private func resume(with error: Error?) {
        guard let continuation else { return }
        self.continuation = nil
        if let error { continuation.resume(throwing: error) } else { continuation.resume() }
    }

    nonisolated public func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        Task { @MainActor in self.resume(with: nil) }
    }

    nonisolated public func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        Task { @MainActor in self.resume(with: error) }
    }

    nonisolated public func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        Task { @MainActor in self.resume(with: error) }
    }
}

extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
