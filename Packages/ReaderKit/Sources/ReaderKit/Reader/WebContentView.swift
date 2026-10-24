import SwiftUI
import WebKit
#if os(iOS)
import UIKit
#else
import AppKit
#endif

/// Viser ett HTML-dokument (et EPUB-kapittel eller en artikkel) med leserens utseende.
/// Rapporterer scrollposisjon og ord brukeren trykker på.
struct WebContentView {
    let url: URL
    let readAccess: URL
    let appearance: ReaderAppearance
    let tapToLookUp: Bool
    /// Når denne endres, scrolles det til `scrollTarget`.
    let scrollRequest: Int
    let scrollTarget: Double
    var onProgress: (Double) -> Void
    var onWordTap: (WordLookup) -> Void
    var onNavigate: (URL) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    fileprivate func makeWebView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        let controller = WKUserContentController()
        controller.addUserScript(WKUserScript(source: Self.script, injectionTime: .atDocumentEnd, forMainFrameOnly: true))
        controller.add(WeakMessageHandler(context.coordinator), name: "reader")
        configuration.userContentController = controller
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        #if os(iOS)
        webView.isOpaque = false
        webView.scrollView.contentInsetAdjustmentBehavior = .automatic
        #else
        webView.setValue(false, forKey: "drawsBackground")
        #endif
        context.coordinator.webView = webView
        context.coordinator.load(url, readAccess: readAccess, progression: scrollTarget)
        return webView
    }

    fileprivate func update(context: Context) {
        let coordinator = context.coordinator
        coordinator.parent = self
        if coordinator.loadedURL != url {
            coordinator.load(url, readAccess: readAccess, progression: scrollTarget)
        } else {
            if coordinator.appliedAppearance != appearance { coordinator.applyAppearance() }
            if coordinator.handledScrollRequest != scrollRequest {
                coordinator.handledScrollRequest = scrollRequest
                coordinator.scroll(to: scrollTarget)
            }
        }
    }

    final class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        var parent: WebContentView
        weak var webView: WKWebView?
        var loadedURL: URL?
        var appliedAppearance: ReaderAppearance?
        var handledScrollRequest: Int
        private var pendingProgression: Double = 0

        init(parent: WebContentView) {
            self.parent = parent
            self.handledScrollRequest = parent.scrollRequest
        }

        func load(_ url: URL, readAccess: URL, progression: Double) {
            loadedURL = url
            pendingProgression = progression
            handledScrollRequest = parent.scrollRequest
            webView?.loadFileURL(url, allowingReadAccessTo: readAccess)
        }

        func applyAppearance() {
            appliedAppearance = parent.appearance
            webView?.evaluateJavaScript("window.readerApply && window.readerApply(\(parent.appearance.javaScriptObject));")
        }

        func scroll(to progression: Double) {
            webView?.evaluateJavaScript("window.readerScrollTo && window.readerScrollTo(\(progression));")
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            if let url = webView.url, url != loadedURL {
                // Brukeren fulgte en intern lenke til et annet kapittel.
                loadedURL = url
                pendingProgression = 0
                parent.onNavigate(url)
            }
            applyAppearance()
            let progression = pendingProgression
            webView.evaluateJavaScript("setTimeout(function(){ window.readerScrollTo(\(progression)); }, 60);")
        }

        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping @MainActor @Sendable (WKNavigationActionPolicy) -> Void) {
            guard let url = navigationAction.request.url else {
                decisionHandler(.cancel)
                return
            }
            if url.isFileURL {
                decisionHandler(.allow)
                return
            }
            if navigationAction.navigationType == .linkActivated {
                #if os(iOS)
                UIApplication.shared.open(url)
                #else
                NSWorkspace.shared.open(url)
                #endif
            }
            decisionHandler(.cancel)
        }

        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            guard let body = message.body as? [String: Any], let type = body["type"] as? String else { return }
            switch type {
            case "progress":
                if let value = (body["value"] as? NSNumber)?.doubleValue { parent.onProgress(value) }
            case "word":
                guard parent.tapToLookUp, let word = body["word"] as? String else { return }
                parent.onWordTap(WordLookup(word: word, context: Self.sentence(around: word, in: body["context"] as? String ?? "")))
            default:
                break
            }
        }

        /// Plukker ut setningen som inneholder ordet.
        static func sentence(around word: String, in text: String) -> String {
            var result = text
            text.enumerateSubstrings(in: text.startIndex..., options: .bySentences) { substring, _, _, stop in
                if let substring, substring.contains(word) {
                    result = substring
                    stop = true
                }
            }
            return result.trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }

    static let script = #"""
    (function() {
      if (window.__readerInstalled) return;
      window.__readerInstalled = true;
      var post = function(m) { window.webkit.messageHandlers.reader.postMessage(m); };
      // EPUB-kapitler mangler ofte viewport-tag; da tegner WebKit siden 980 px bred og krymper teksten.
      if (!document.querySelector('meta[name=viewport]')) {
        var meta = document.createElement('meta');
        meta.name = 'viewport';
        meta.content = 'width=device-width, initial-scale=1';
        (document.head || document.documentElement).appendChild(meta);
      }
      var style = document.createElement('style');
      style.id = 'reader-style';
      (document.head || document.documentElement).appendChild(style);
      window.readerApply = function(a) {
        style.textContent =
          'html { -webkit-text-size-adjust: none; }' +
          'html, body { background: ' + a.bg + ' !important; color: ' + a.fg + ' !important; }' +
          'body { font-family: ' + a.font + ' !important; font-size: ' + a.size + '% !important; line-height: ' + a.lineHeight + ' !important;' +
          ' max-width: 38em; margin: 0 auto !important; padding: 1.5em 1.25em 5em !important; overflow-wrap: break-word; }' +
          'p, li, blockquote, dd { line-height: inherit !important; }' +
          'h1, h2, h3, h4, p, li, span, div, blockquote { color: inherit !important; background: transparent !important; }' +
          'a { color: ' + a.link + ' !important; }' +
          'img, video, table { max-width: 100% !important; height: auto !important; }' +
          // Omslagssider pakker bildet i en <svg height="100%">; height:auto gir den null høyde.
          'svg { max-width: 100% !important; max-height: 92vh !important; }' +
          'pre { white-space: pre-wrap; }' +
          '.reader-article-header .byline, .reader-article-header .source { opacity: 0.7; font-size: 0.9em; }';
      };
      var timer = null;
      var report = function() {
        var h = document.documentElement.scrollHeight - window.innerHeight;
        var p = h > 0 ? Math.min(1, Math.max(0, window.scrollY / h)) : 1;
        post({ type: 'progress', value: p });
      };
      window.addEventListener('scroll', function() { clearTimeout(timer); timer = setTimeout(report, 250); }, { passive: true });
      window.readerScrollTo = function(p) {
        var h = document.documentElement.scrollHeight - window.innerHeight;
        window.scrollTo(0, Math.max(0, h * p));
        report();
      };
      document.addEventListener('click', function(e) {
        if (e.target && e.target.closest && e.target.closest('a')) return;
        var sel = window.getSelection();
        if (sel && sel.toString().length > 0) return;
        var r = document.caretRangeFromPoint ? document.caretRangeFromPoint(e.clientX, e.clientY) : null;
        if (!r || !r.startContainer || r.startContainer.nodeType !== 3) return;
        var text = r.startContainer.textContent;
        var s = r.startOffset, en = r.startOffset;
        var re = /[\p{L}\p{N}'’\-]/u;
        while (s > 0 && re.test(text[s - 1])) s--;
        while (en < text.length && re.test(text[en])) en++;
        var word = text.slice(s, en).replace(/^['’\-]+|['’\-]+$/g, '');
        if (!word) return;
        var parent = r.startContainer.parentElement;
        var block = parent && parent.closest ? (parent.closest('p, li, blockquote, td, h1, h2, h3, h4, div') || parent) : parent;
        var context = (block && block.innerText) ? block.innerText : text;
        post({ type: 'word', word: word, context: context.slice(0, 1200) });
      });
    })();
    """#
}

/// Hindrer at WKUserContentController holder koordinatoren i live for alltid.
private final class WeakMessageHandler: NSObject, WKScriptMessageHandler {
    weak var target: WKScriptMessageHandler?
    init(_ target: WKScriptMessageHandler) { self.target = target }
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        target?.userContentController(userContentController, didReceive: message)
    }
}

#if os(iOS)
extension WebContentView: UIViewRepresentable {
    func makeUIView(context: Context) -> WKWebView { makeWebView(context: context) }
    func updateUIView(_ webView: WKWebView, context: Context) { update(context: context) }
}
#else
extension WebContentView: NSViewRepresentable {
    func makeNSView(context: Context) -> WKWebView { makeWebView(context: context) }
    func updateNSView(_ webView: WKWebView, context: Context) { update(context: context) }
}
#endif
