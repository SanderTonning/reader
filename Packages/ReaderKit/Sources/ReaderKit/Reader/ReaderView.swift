import PDFKit
import SwiftData
import SwiftUI

/// Åpner riktig leser eller spiller for boken.
struct ReaderView: View {
    @Bindable var book: Book
    @State private var state: LoadState = .loading

    enum LoadState {
        case loading
        case web(WebDocument)
        case pdf(PDFDocument)
        case audio
        case failed(String)
    }

    var body: some View {
        Group {
            switch state {
            case .loading:
                ProgressView("Åpner …")
            case .web(let document):
                TextReaderView(book: book, document: document)
            case .pdf(let document):
                PDFReaderView(book: book, document: document)
            case .audio:
                AudioPlayerView(book: book)
            case .failed(let message):
                ContentUnavailableView("Kunne ikke åpne", systemImage: "exclamationmark.triangle", description: Text(message))
            }
        }
        .task(id: book.id) { await load() }
    }

    private func load() async {
        switch book.format {
        case .audio:
            state = book.tracks.isEmpty ? .failed("Lydboken har ingen spor.") : .audio
        case .pdf:
            guard let url = book.localURL, let document = PDFDocument(url: url) else {
                state = .failed("PDF-filen mangler.")
                return
            }
            state = .pdf(document)
        case .article:
            guard let url = book.localURL, book.isDownloaded else {
                state = .failed("Artikkelen mangler på denne enheten.")
                return
            }
            state = .web(.article(url: url, title: book.title, language: book.language))
        case .epub:
            guard let url = book.localURL, book.isDownloaded else {
                state = .failed("Boken er ikke lastet ned på denne enheten.")
                return
            }
            let id = book.id
            do {
                let publication = try await Task.detached { try EPUBPublication.open(epubAt: url, bookID: id) }.value
                state = publication.chapters.isEmpty ? .failed("Boken har ingen kapitler.") : .web(.epub(publication))
            } catch {
                state = .failed(error.localizedDescription)
            }
        }
    }
}
