import SwiftData
import SwiftUI
#if os(iOS)
import UIKit
#else
import AppKit
#endif

enum LibraryFilter: String, CaseIterable, Identifiable {
    case all, ebooks, audiobooks, articles
    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: "Alle"
        case .ebooks: "E-bøker"
        case .audiobooks: "Lydbøker"
        case .articles: "Artikler"
        }
    }

    func matches(_ book: Book) -> Bool {
        switch self {
        case .all: true
        case .ebooks: book.kind == .ebook
        case .audiobooks: book.kind == .audiobook
        case .articles: book.kind == .article
        }
    }
}

struct LibraryView: View {
    @Query(sort: \Book.addedAt, order: .reverse) private var books: [Book]
    @Environment(\.modelContext) private var context
    @EnvironmentObject private var importState: ImportState

    @State private var filter: LibraryFilter = .all
    @State private var search = ""
    @State private var showFileImporter = false
    @State private var showArticlePrompt = false
    @State private var articleLink = ""

    private var filtered: [Book] {
        books.filter { book in
            filter.matches(book) && (search.isEmpty
                || book.title.localizedCaseInsensitiveContains(search)
                || (book.author ?? "").localizedCaseInsensitiveContains(search))
        }
    }

    private var continueReading: [Book] {
        books
            .filter { $0.lastOpenedAt != nil && $0.finishedAt == nil }
            .sorted { ($0.lastOpenedAt ?? .distantPast) > ($1.lastOpenedAt ?? .distantPast) }
            .prefix(6)
            .map { $0 }
    }

    var body: some View {
        ScrollView {
            if books.isEmpty {
                ContentUnavailableView {
                    Label("Biblioteket er tomt", systemImage: "books.vertical")
                } description: {
                    Text("Importer egne filer, lagre en artikkel, eller finn bøker under Utforsk.")
                } actions: {
                    Button("Importer filer") { showFileImporter = true }
                        .buttonStyle(.borderedProminent)
                    Button("Legg til artikkel") { showArticlePrompt = true }
                }
                .padding(.top, 60)
            } else {
                VStack(alignment: .leading, spacing: 20) {
                    if search.isEmpty, filter == .all, !continueReading.isEmpty {
                        Text("Fortsett").font(.title3.bold()).padding(.horizontal)
                        ScrollView(.horizontal, showsIndicators: false) {
                            LazyHStack(alignment: .top, spacing: 14) {
                                ForEach(continueReading) { book in
                                    NavigationLink(value: book) { BookCard(book: book) }
                                        .buttonStyle(.plain)
                                        .frame(width: 120)
                                }
                            }
                            .padding(.horizontal)
                        }
                    }

                    Picker("Vis", selection: $filter) {
                        ForEach(LibraryFilter.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal)

                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 110, maximum: 160), spacing: 16)], spacing: 20) {
                        ForEach(filtered) { book in
                            NavigationLink(value: book) { BookCard(book: book) }
                                .buttonStyle(.plain)
                                .contextMenu {
                                    if book.finishedAt == nil {
                                        Button { book.finishedAt = .now } label: { Label("Merk som ferdig", systemImage: "checkmark.circle") }
                                    } else {
                                        Button { book.finishedAt = nil } label: { Label("Merk som ulest", systemImage: "circle") }
                                    }
                                    Button(role: .destructive) {
                                        LibraryImporter.delete(book, from: context)
                                    } label: {
                                        Label("Slett", systemImage: "trash")
                                    }
                                }
                        }
                    }
                    .padding(.horizontal)
                }
                .padding(.vertical)
            }
        }
        .navigationTitle("Bibliotek")
        .navigationDestination(for: Book.self) { ReaderView(book: $0) }
        .searchable(text: $search, prompt: "Søk i biblioteket")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button { showFileImporter = true } label: { Label("Importer filer", systemImage: "folder") }
                    Button { showArticlePrompt = true } label: { Label("Legg til artikkel", systemImage: "link") }
                    Button { pasteArticle() } label: { Label("Lim inn lenke", systemImage: "doc.on.clipboard") }
                } label: {
                    Label("Legg til", systemImage: "plus")
                }
            }
        }
        .overlay(alignment: .top) {
            if let message = importState.message {
                Text(message)
                    .font(.callout)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(.regularMaterial, in: Capsule())
                    .padding(.top, 8)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .fileImporter(isPresented: $showFileImporter, allowedContentTypes: LibraryImporter.supportedTypes, allowsMultipleSelection: true) { result in
            guard case .success(let urls) = result else { return }
            importState.importFiles(urls, context: context)
        }
        .alert("Legg til artikkel", isPresented: $showArticlePrompt) {
            TextField("https://", text: $articleLink)
                #if os(iOS)
                .keyboardType(.URL)
                .textInputAutocapitalization(.never)
                #endif
            Button("Avbryt", role: .cancel) { articleLink = "" }
            Button("Lagre") {
                if let url = ArticleImporter.firstURL(in: articleLink) ?? URL(string: articleLink) {
                    importState.importArticle(url, context: context)
                }
                articleLink = ""
            }
        } message: {
            Text("Lim inn lenken til en nettartikkel. Teksten lagres i biblioteket og kan leses eller leses opp.")
        }
    }

    private func pasteArticle() {
        #if os(iOS)
        let text = UIPasteboard.general.string ?? UIPasteboard.general.url?.absoluteString ?? ""
        #else
        let text = NSPasteboard.general.string(forType: .string) ?? ""
        #endif
        if let url = ArticleImporter.firstURL(in: text) {
            importState.importArticle(url, context: context)
        } else {
            importState.show("Fant ingen lenke på utklippstavlen.")
        }
    }
}

struct BookCard: View {
    let book: Book

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            CoverView(book: book)
                .frame(maxWidth: .infinity, minHeight: 150, maxHeight: 180)
                .shadow(color: .black.opacity(0.15), radius: 4, y: 2)
            Text(book.title)
                .font(.caption.bold())
                .lineLimit(2)
            if let author = book.author {
                Text(author)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            if let progress = book.position?.totalProgression, progress > 0 {
                ProgressView(value: min(progress, 1))
                    .tint(book.finishedAt == nil ? .accentColor : .green)
            }
        }
        .contentShape(Rectangle())
    }
}

/// Felles tilstand for import, så meldinger kan vises uansett hvor importen startet.
@MainActor
final class ImportState: ObservableObject {
    @Published var message: String?
    private var hideTask: Task<Void, Never>?
    private let articleImporter = ArticleImporter()

    func show(_ text: String) {
        withAnimation { message = text }
        hideTask?.cancel()
        hideTask = Task {
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled else { return }
            withAnimation { message = nil }
        }
    }

    func importFiles(_ urls: [URL], context: ModelContext) {
        show("Importerer …")
        Task {
            let result = await LibraryImporter.importFiles(urls, into: context)
            if let failure = result.failed.first {
                show("Kunne ikke importere \(failure.name): \(failure.error.localizedDescription)")
            } else {
                show(result.added.count == 1 ? "La til «\(result.added[0].title)»" : "La til \(result.added.count) bøker")
            }
        }
    }

    func importArticle(_ url: URL, context: ModelContext) {
        show("Henter artikkel …")
        Task {
            do {
                let book = try await articleImporter.importArticle(from: url, into: context)
                show("Lagret «\(book.title)»")
            } catch {
                show("Kunne ikke lagre artikkelen: \(error.localizedDescription)")
            }
        }
    }
}
