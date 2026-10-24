import SwiftData
import SwiftUI

/// Bla i og søk i åpne bibliotek.
struct ExploreView: View {
    @Query(sort: \CatalogSource.addedAt) private var customSources: [CatalogSource]
    @State private var selectedID = "gutenberg"
    @State private var showAddSource = false

    private var providers: [any CatalogProvider] {
        CatalogDirectory.builtIn() + customSources.map(CatalogDirectory.provider(for:))
    }

    private var selected: any CatalogProvider {
        providers.first { $0.id == selectedID } ?? providers[0]
    }

    var body: some View {
        CatalogBrowser(provider: selected)
            .id(selected.id)
            .navigationTitle("Utforsk")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Picker("Kilde", selection: $selectedID) {
                            ForEach(providers, id: \.id) { provider in
                                Text(provider.name).tag(provider.id)
                            }
                        }
                        Divider()
                        Button { showAddSource = true } label: { Label("Legg til OPDS-katalog", systemImage: "plus") }
                    } label: {
                        Label(selected.name, systemImage: "building.columns")
                    }
                }
            }
            .sheet(isPresented: $showAddSource) { AddSourceView() }
            .navigationDestination(for: CatalogItem.self) { item in
                if item.isNavigation, let url = item.navigationURL {
                    CatalogBrowser(provider: selected, startURL: url, title: item.title)
                } else {
                    CatalogDetailView(item: item)
                }
            }
    }
}

struct CatalogBrowser: View {
    let provider: any CatalogProvider
    var startURL: URL?
    var title: String?

    @State private var items: [CatalogItem] = []
    @State private var nextPage: URL?
    @State private var query = ""
    @State private var isLoading = false
    @State private var errorMessage: String?

    var body: some View {
        List {
            if let errorMessage {
                Text(errorMessage).foregroundStyle(.red)
            }
            ForEach(items) { item in
                NavigationLink(value: item) { CatalogRow(item: item) }
            }
            if let nextPage {
                HStack {
                    Spacer()
                    if isLoading { ProgressView() } else { Button("Last flere") { Task { await load(nextPage, append: true) } } }
                    Spacer()
                }
                .onAppear { Task { await load(nextPage, append: true) } }
            }
            if !isLoading && items.isEmpty && errorMessage == nil {
                Text("Ingen treff.").foregroundStyle(.secondary)
            }
        }
        .overlay { if isLoading && items.isEmpty { ProgressView() } }
        .navigationTitle(title ?? provider.name)
        .searchable(text: $query, prompt: "Søk etter tittel eller forfatter")
        .onSubmit(of: .search) { Task { await search() } }
        .onChange(of: query) {
            if query.isEmpty { Task { await loadStart() } }
        }
        .task { if items.isEmpty { await loadStart() } }
        .refreshable { await loadStart() }
    }

    private func loadStart() async {
        if let startURL {
            await load(startURL, append: false)
        } else {
            await run { try await provider.start() }
        }
    }

    private func search() async {
        let text = query.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return }
        await run { try await provider.search(text) }
    }

    private func load(_ url: URL, append: Bool) async {
        guard !isLoading else { return }
        if append {
            isLoading = true
            defer { isLoading = false }
            if let page = try? await provider.page(at: url) {
                items += page.items.filter { new in !items.contains { $0.id == new.id } }
                nextPage = page.nextPage
            } else {
                nextPage = nil
            }
        } else {
            await run { try await provider.page(at: url) }
        }
    }

    private func run(_ work: () async throws -> CatalogPage) async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            let page = try await work()
            items = page.items
            nextPage = page.nextPage
        } catch {
            items = []
            nextPage = nil
            errorMessage = "Kunne ikke hente katalogen: \(error.localizedDescription)"
        }
    }
}

struct CatalogRow: View {
    let item: CatalogItem

    var body: some View {
        HStack(spacing: 12) {
            if item.isNavigation {
                Image(systemName: "folder").font(.title2).frame(width: 44)
            } else {
                AsyncImage(url: item.coverURL) { image in
                    image.resizable().aspectRatio(contentMode: .fill)
                } placeholder: {
                    Rectangle().fill(.quaternary)
                        .overlay(Image(systemName: item.kind == .audiobook ? "headphones" : "book.closed").foregroundStyle(.secondary))
                }
                .frame(width: 44, height: 64)
                .clipShape(RoundedRectangle(cornerRadius: 4))
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(item.title).font(.headline).lineLimit(2)
                if let author = item.author { Text(author).font(.subheadline).foregroundStyle(.secondary).lineLimit(1) }
                if let detail = item.detail { Text(detail).font(.caption).foregroundStyle(.secondary) }
            }
        }
    }
}

struct CatalogDetailView: View {
    let item: CatalogItem
    @Environment(\.modelContext) private var context
    @State private var book: Book?
    @State private var isWorking = false
    @State private var errorMessage: String?
    @State private var openBook: Book?

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                AsyncImage(url: item.coverURL) { image in
                    image.resizable().aspectRatio(contentMode: .fit)
                } placeholder: {
                    RoundedRectangle(cornerRadius: 8).fill(.quaternary).aspectRatio(2.0 / 3.0, contentMode: .fit)
                }
                .frame(maxWidth: 200, maxHeight: 300)
                .shadow(radius: 6)

                Text(item.title).font(.title2.bold()).multilineTextAlignment(.center)
                if let author = item.author { Text(author).foregroundStyle(.secondary) }
                if let detail = item.detail { Text(detail).font(.caption).foregroundStyle(.secondary) }

                if let book {
                    Button { openBook = book } label: {
                        Label(item.kind == .audiobook ? "Lytt" : "Les", systemImage: item.kind == .audiobook ? "play.fill" : "book")
                            .frame(maxWidth: 260)
                    }
                    .buttonStyle(.borderedProminent)
                    Text("Ligger i biblioteket ditt.").font(.caption).foregroundStyle(.secondary)
                } else {
                    Button { Task { await add() } } label: {
                        if isWorking {
                            ProgressView()
                        } else {
                            Label(item.kind == .audiobook ? "Legg til og lytt" : "Last ned til biblioteket", systemImage: "plus.circle.fill")
                                .frame(maxWidth: 260)
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isWorking)
                }
                if let errorMessage { Text(errorMessage).foregroundStyle(.red).font(.callout) }

                if let summary = item.summary, !summary.isEmpty {
                    Text(summary)
                        .font(.callout)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                }
                if item.kind == .audiobook {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("\(item.tracks.count) deler").font(.headline)
                        ForEach(item.tracks.prefix(50)) { track in
                            Text(track.title).font(.callout).lineLimit(1)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding()
        }
        .navigationTitle(item.title)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .onAppear { book = CatalogImporter.existingBook(for: item, in: context) }
        .navigationDestination(item: $openBook) { ReaderView(book: $0) }
    }

    private func add() async {
        isWorking = true
        errorMessage = nil
        defer { isWorking = false }
        do {
            let added = try await CatalogImporter.add(item, into: context)
            book = added
            openBook = added
        } catch {
            errorMessage = "Kunne ikke legge til: \(error.localizedDescription)"
        }
    }
}

struct AddSourceView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var urlText = ""

    private static let suggestions: [(String, String)] = [
        ("Project Gutenberg (OPDS)", "https://www.gutenberg.org/ebooks/search.opds/"),
        ("Unglue.it – gratis e-bøker", "https://unglue.it/api/opds/"),
    ]

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Navn", text: $name)
                    TextField("https://…/opds", text: $urlText)
                        #if os(iOS)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        #endif
                } footer: {
                    Text("OPDS er et åpent katalogformat som brukes av mange bibliotek og av Calibre-server.")
                }
                Section("Forslag") {
                    ForEach(Self.suggestions, id: \.1) { suggestion in
                        Button(suggestion.0) {
                            name = suggestion.0
                            urlText = suggestion.1
                        }
                    }
                }
            }
            .navigationTitle("Ny katalog")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Avbryt") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Legg til") {
                        guard let url = URL(string: urlText.trimmingCharacters(in: .whitespaces)) else { return }
                        context.insert(CatalogSource(name: name.isEmpty ? (url.host ?? "Katalog") : name, url: url))
                        try? context.save()
                        dismiss()
                    }
                    .disabled(URL(string: urlText)?.scheme?.hasPrefix("http") != true)
                }
            }
        }
        .frame(minWidth: 360, minHeight: 320)
    }
}
